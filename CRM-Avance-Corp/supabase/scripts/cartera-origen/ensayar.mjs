// Ensayo completo del filtro de origen en la copia local, a paridad con
// producción: gate analítico verde antes, equivalencia sin filtro para todos
// los actores (deshecha), instalación real, oráculo, reversa y reinstalación.
// Nunca toca producción: `banco.mjs` fija el contenedor y la base.
import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, sql, objeto, claims } from './banco.mjs';

const F9 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)';
const F10 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)';
const MD5_F9 = '5d246e9518123c72352a958606853c35'; // producción, 16/09
const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const migracion = leer('../../migrations/20260916220124_crm_cartera_filtro_origen.sql');
const cuerpo = migracion.replace(/^begin;\n/m, '').replace(/^commit;\s*$/m, '');
const oraculo = leer('./test-cartera-origen.sql');
const oraculo13 = leer('../test-cartera-filtrada.sql');
const reversa = leer('./reversa.sql');

assert.equal(sql('select current_database()'), db);
const gate = () => sql('select private.assert_analitica_leads_citas()');
const md5Vivo = (f) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))),'-')`);
const acl = (f) => sql(`select coalesce((select proacl::text from pg_proc where oid=to_regprocedure('${f}')),'-')`);
assert.match(gate(), /^OK/, 'El gate analítico debe estar verde ANTES del ensayo');
assert.equal(md5Vivo(F9), MD5_F9, 'La copia debe partir de la función viva de producción');
const aclAntes = acl(F9);

// 1. Equivalencia sin filtro, actor por actor, en UNA transacción deshecha: la
//    función anterior renombrada a pg_temp responde igual que la nueva sin
//    p_origen (salvo la clave nueva `origen`, que llega nula).
const actores = objeto(`select coalesce(jsonb_agg(perfil_id),'[]') from (
  select perfil_id from crm.equipo where activo and private.rol_crm(perfil_id) is not null
  union select id from public.perfiles where rol='directorio' and activo) a`);
assert.ok(actores.length >= 5, 'Faltan actores para comparar');
const anterior = sql(`select pg_get_functiondef('${F9}'::regprocedure)`)
  .replace('crm.cartera_filtrada_fn', 'pg_temp.cartera_filtrada_anterior') + ';';
const comparaciones = [
  'p_limite=>50', "p_limite=>200,p_etapa=>'nuevo'", "p_limite=>10,p_texto=>'an'",
  "p_limite=>50,p_desde=>(now() at time zone 'America/Lima')::date-30,p_hasta=>(now() at time zone 'America/Lima')::date",
];
const equivalencia = `
do $equivalencia$
declare actor uuid; a jsonb; b jsonb; n integer:=0; c text;
begin
  foreach actor in array array[${actores.map((a) => `'${a}'::uuid`).join(',')}] loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    foreach c in array array[${comparaciones.map((c) => `$c$${c}$c$`).join(',')}] loop
      execute 'select pg_temp.cartera_filtrada_anterior('||c||')' into a;
      execute 'select crm.cartera_filtrada_fn('||c||')' into b;
      if b->'origen' is distinct from 'null'::jsonb or (b - 'origen') is distinct from a then
        raise exception 'Respuesta distinta para % con %: anterior % / nueva %',actor,c,a,b;
      end if;
      n:=n+1;
    end loop;
  end loop;
  raise notice 'Equivalencia sin filtro: % lecturas idénticas para % actores',n,${actores.length};
end;
$equivalencia$;`;
const ensayo = sql(`begin;${anterior}\n${cuerpo}\nset local role authenticated;${equivalencia}\nreset role;\nselect 'ENSAYO_DESHECHO';rollback;`);
assert.match(ensayo, /ENSAYO_DESHECHO/);
assert.equal(md5Vivo(F9), MD5_F9, 'El ensayo deshecho no dejó rastro');

// 2. Instalación real en la copia + gate + oráculo.
sql(migracion);
assert.match(gate(), /^OK/, 'Gate analítico tras instalar');
assert.equal(md5Vivo(F9), '-', 'La firma de 9 desaparece');
assert.equal(acl(F10), aclAntes, 'ACL idéntica en la firma nueva');
assert.match(sql(oraculo), /CARTERA_ORIGEN_OK/);

// 3. Reversa: vuelve la función del 13/09 byte a byte, el gate sigue verde y el
//    oráculo del 13/09 vuelve a pasar sobre ella.
sql(reversa);
assert.match(gate(), /^OK/, 'Gate analítico tras la reversa');
assert.equal(md5Vivo(F9), MD5_F9, 'Reversa: la función del 13/09 tal cual');
assert.equal(md5Vivo(F10), '-', 'Reversa: la firma de 10 desaparece');
assert.equal(acl(F9), aclAntes, 'Reversa: ACL original');
assert.match(sql(oraculo13), /CARTERA_FILTRADA_RLS_OK/);

// 4. Reinstalación: idempotencia del preflight sobre una base revertida.
sql(migracion);
assert.match(gate(), /^OK/, 'Gate analítico tras reinstalar');
assert.match(sql(oraculo), /CARTERA_ORIGEN_OK/);

writeFileSync(new URL('verificacion.json', import.meta.url), JSON.stringify({
  estado: 'PASS', banco: db, fecha: new Date().toISOString(),
  migracion_sha256: createHash('sha256').update(migracion).digest('hex'),
  reversa_sha256: createHash('sha256').update(reversa).digest('hex'),
  actores_comparados: actores.length, lecturas_por_actor: comparaciones.length,
  pasos: ['gate verde antes', 'equivalencia sin filtro deshecha', 'instalación + gate + oráculo',
    'reversa + gate + oráculo 13/09', 'reinstalación + gate + oráculo'],
}, null, 2) + '\n');
console.log(`PASS: equivalencia (${actores.length} actores × ${comparaciones.length} lecturas), instalación, oráculo, reversa y reinstalación en ${db}.`);
