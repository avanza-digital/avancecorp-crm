// Banco sintético exclusivo de «Base para gestión»; no recibe URL, credenciales ni destino externo.
// Uso: node supabase/scripts/base-gestion/banco.mjs crear | aplicar | test | reversa-y-reaplicar
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
export const db = 'base_gestion_20261002';
export const plantilla = 'conversion_tipos_v3_20260927';
export const contenedor = 'supabase_db_crm-avance-corp-local';
export const sello = 'BANCO SINTETICO base gestion 20261002 / sin produccion';
const migracion = new URL('../../migrations/20261002054402_crm_base_gestion_esquema.sql', import.meta.url);
function psql(base, texto, { candado = true } = {}) {
  const guardia = candado ? `do $$ begin if current_database()<>'${db}' or shobj_description(
      (select oid from pg_database where datname=current_database()),'pg_database')
      is distinct from '${sello}' then raise exception 'Banco de base gestion no autorizado'; end if; end $$;\n` : '';
  const r = spawnSync('docker', ['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres',
    '-d',base,'-v','ON_ERROR_STOP=1','-f','-'], {encoding:'utf8',maxBuffer:8*1024*1024, input: guardia + texto});
  assert.equal(r.status,0,(r.stderr || r.error?.message || '') + '\n' + (r.stdout || ''));
  if (['test','aplicar','fixtures-b2','fixtures-b2-persona','aplicar-b2','test-b2'].includes(process.argv[2])) process.stderr.write(r.stderr);
  return r.stdout.trim();
}
export const sql = (texto) => psql(db, texto);
const orden = process.argv[2];
if (orden==='crear') {
  const existe = psql('postgres', `select 1 from pg_database where datname='${db}'`, {candado:false});
  assert.equal(existe, '', `La base ${db} ya existe; usa test o reversa-y-reaplicar`);
  psql('postgres', `create database ${db} template ${plantilla};`, {candado:false});
  psql('postgres', `comment on database ${db} is '${sello}';`, {candado:false});
  console.log(`PASS: ${db} creada desde ${plantilla} y sellada`);
}
if (orden==='aplicar') { sql(readFileSync(migracion,'utf8')); console.log('PASS: migración aplicada en el banco'); }
if (orden==='test') console.log(sql(readFileSync(new URL('./test.sql',import.meta.url),'utf8')));
if (orden==='reversa-y-reaplicar') {
  sql(readFileSync(new URL('./reversa-esquema.sql',import.meta.url),'utf8'));
  assert.equal(sql("select to_regprocedure('private.base_gestion_constantes()') is null"),'t');
  sql(readFileSync(migracion,'utf8'));
  console.log('PASS: reversa y reaplicación con preflight en banco sintético');
}
const migracionB2 = new URL('../../migrations/20261002061500_crm_base_gestion_no_contactar_supervisor.sql', import.meta.url);
if (orden==='fixtures-b2') { console.log(sql(readFileSync(new URL('./fixtures-b2.sql',import.meta.url),'utf8'))); console.log('PASS: fixtures B2 en el banco'); }
if (orden==='fixtures-b2-persona') { console.log(sql(readFileSync(new URL('./fixtures-b2-persona.sql',import.meta.url),'utf8'))); console.log('PASS: fixtures B2 persona en el banco'); }
if (orden==='restaurar-levantar-vivo') { const r=readFileSync(new URL('./reversa-no-contactar-supervisor.sql',import.meta.url),'utf8'); const i=r.indexOf('create or replace function'); const j=r.indexOf('$function$;', i)+'$function$;'.length; sql("set search_path=''; set quote_all_identifiers=off;\n"+r.slice(i,j)); console.log('PASS: levantar_no_contactar restaurada al texto vivo (solo banco, sin guarda)'); }
if (orden==='aplicar-b2') { sql(readFileSync(migracionB2,'utf8')); console.log('PASS: migración B2 aplicada en el banco'); }
if (orden==='test-b2') console.log(sql(readFileSync(new URL('./b2-rls.sql',import.meta.url),'utf8')));
if (orden==='reversa-y-reaplicar-b2') {
  sql(readFileSync(new URL('./reversa-no-contactar-supervisor.sql',import.meta.url),'utf8'));
  sql(readFileSync(migracionB2,'utf8'));
  console.log('PASS: reversa y reaplicación de B2 con preflight en banco sintético');
}
// paridad-acl: el banco nace SIN ACL (esquema, tablas, columnas y funciones a NULL). Copia al banco los GRANT que el
// stack local de Supabase (base `postgres` del mismo contenedor, ACL igual a producción) tiene para anon/authenticated/
// service_role en `crm` y `private`. Cada sentencia va en su DO: lo que no exista en el banco se salta sin ruido.
if (orden==='paridad-acl') {
  const gen = psql('postgres', `set search_path=''; set quote_all_identifiers=off;
with roles as (select r from unnest(array['anon','authenticated','service_role']) r)
select string_agg(stmt, E'\n' order by orden, stmt) from (
  select 1 orden, format('grant usage on schema %I to %I;', n.nspname, a.grantee::regrole) stmt
    from pg_namespace n, aclexplode(n.nspacl) a where n.nspname in ('crm','private') and a.privilege_type='USAGE' and a.grantee::regrole::text in (select r from roles)
  union all
  select 2, format('revoke all on %I.%I from public, anon, authenticated, service_role;', n.nspname, c.relname)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='crm' and c.relkind in ('r','v','m','p') and c.relacl is not null
  union all
  select 3, format('grant %s on %I.%I to %I;', a.privilege_type, n.nspname, c.relname, a.grantee::regrole)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace, aclexplode(c.relacl) a where n.nspname='crm' and c.relkind in ('r','v','m','p') and a.grantee::regrole::text in (select r from roles)
  union all
  select 4, format('grant %s (%I) on %I.%I to %I;', a.privilege_type, at.attname, n.nspname, c.relname, a.grantee::regrole)
    from pg_attribute at join pg_class c on c.oid=at.attrelid join pg_namespace n on n.oid=c.relnamespace, aclexplode(at.attacl) a where n.nspname='crm' and not at.attisdropped and a.grantee::regrole::text in (select r from roles)
  union all
  select 5, format('revoke all on function %s from public, anon, authenticated, service_role;', p.oid::regprocedure)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private') and p.proacl is not null and p.prokind='f'
  union all
  select 6, format('grant execute on function %s to %I;', p.oid::regprocedure, a.grantee::regrole)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace, aclexplode(p.proacl) a where n.nspname in ('crm','private') and p.prokind='f' and a.privilege_type='EXECUTE' and a.grantee::regrole::text in (select r from roles)
  union all
  select 7, format('grant %s on sequence %I.%I to %I;', a.privilege_type, n.nspname, c.relname, a.grantee::regrole)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace, aclexplode(c.relacl) a where n.nspname='crm' and c.relkind='S' and a.grantee::regrole::text in (select r from roles)
) q;`, {candado:false});
  const stmts = gen.split('\n').filter(Boolean);
  const envueltas = stmts.map(st => `do $acl$ begin execute ${JSON.stringify(st).replace(/^"|"$/g, "'").replace(/\\"/g, '"')}; exception when undefined_function or undefined_table or undefined_column or undefined_object or invalid_schema_name then null; end $acl$;`);
  sql("set search_path=''; set quote_all_identifiers=off;\n" + envueltas.join('\n'));
  console.log(`PASS: paridad de ACL aplicada al banco (${stmts.length} sentencias del stack local; las de objetos ausentes se saltaron)`);
}
const ORDENES = ['crear','aplicar','test','reversa-y-reaplicar','fixtures-b2','aplicar-b2','test-b2','reversa-y-reaplicar-b2','paridad-acl','fixtures-b2-persona','restaurar-levantar-vivo'];
if (!ORDENES.includes(orden)) { console.error('Uso: banco.mjs ' + ORDENES.join(' | ')); process.exit(2); }
