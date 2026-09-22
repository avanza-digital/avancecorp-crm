// Usa los fixtures canónicos y Auth admin local, no inserts de contraseñas SQL.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { carpeta, sql, credencialesLocales } from './banco.mjs';
import { USERS } from '../../fixtures.mjs';

assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado']);
const paridad = JSON.parse(readFileSync(`${carpeta}/paridad-diferencias.json`, 'utf8'));
assert.equal(paridad.estado, 'PASS', 'Falta paridad con el esquema vigente');
assert.equal(paridad.banco, 'gestion-diaria-f4-http');
const existentes = JSON.parse(sql("select coalesce(jsonb_agg(email),'[]') from auth.users"));
assert.ok(existentes.every(email => USERS.some(u => u.email === email)), 'Hay usuarios ajenos a los fixtures');
sql(readFileSync(new URL('./reglas-fixture.sql', import.meta.url), 'utf8'));
sql(`begin;
  insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo,nota)
  select 1,'-infinity',15,18,1,'observacion','Regla sintética inicial del banco'
  where not exists(select 1 from crm.politica_rentabilidad);
  insert into crm.multiempresa_flags(nombre,activo)
  select * from (values ('ficha_360_neutral',true),('inversiones_escritura',true),
    ('metricas_multiempresa_sombra',false),('postventa_neutral',true),('resolver_en_puertas',true)) x(nombre,activo)
  where not exists(select 1 from crm.multiempresa_flags f where f.nombre=x.nombre);
  commit;`);
sql(`insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  select 'f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf','image/jpeg','image/png']
  where not exists(select 1 from storage.buckets where id='f4-comprobantes');`,{propietarioAlmacen:true});
assert.equal(sql("select (not public and file_size_limit=10485760)::text from storage.buckets where id='f4-comprobantes'"),'true');
const archivoClave = `${carpeta}/credenciales-fixtures.json`;
let password;
if (existsSync(archivoClave)) {
  password = JSON.parse(readFileSync(archivoClave, 'utf8')).password;
} else {
  assert.equal(existentes.length, 0, 'No cambiar credenciales de un seed previo sin su estado');
  password = randomBytes(24).toString('base64url');
  writeFileSync(archivoClave, JSON.stringify({ password })+'\n', { mode: 0o600, flag: 'wx' });
}
const c = credencialesLocales();
const env = { PATH: process.env.PATH, TMPDIR: process.env.TMPDIR, LANG: process.env.LANG,
  TZ: 'America/Lima', SUPABASE_URL: c.API_URL, SUPABASE_ANON_KEY: c.ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY: c.SERVICE_ROLE_KEY, CRM_DEMO_PASSWORD: password,
  CRM_BANCO_PSQL_URL: c.DB_URL };
const permisoPrevio = sql("select has_table_privilege('service_role','crm.periodos_cerrados','SELECT')") === 't';
let resultado;
try {
  if (!permisoPrevio) sql('grant select on crm.periodos_cerrados to service_role');
  resultado = spawnSync(process.execPath, ['--import', fileURLToPath(new URL('./fetch-local.mjs', import.meta.url)),
    fileURLToPath(new URL('../../seed-demo.mjs', import.meta.url))],
  { env, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 120_000 });
} finally {
  if (!permisoPrevio) sql('revoke select on crm.periodos_cerrados from service_role');
}
// El seed sólo informa fixtures ficticios; no imprime la contraseña ni JWT.
console.log(resultado.stdout ?? '');
if (resultado.status !== 0) {
  console.error(resultado.stderr ?? 'Seed interrumpido');
  process.exitCode = 1;
} else {
  sql(`begin;
    do $pre$ begin
      if (select tgenabled from pg_trigger where tgrelid='crm.equipo'::regclass
        and tgname='trg_equipo_validar_usuarios_jerarquia') is distinct from 'O'::"char"
      then raise exception 'Guardia de jerarquía no está habilitado'; end if;
    end $pre$;
    alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
    update crm.equipo set activo=false where perfil_id=(select id from public.perfiles
      where correo='vend-inactivo.crm@demo.avancecorp.pe' and nombre_completo='ANALISTA INACTIVO');
    alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
    commit;`);
  assert.equal(sql("select count(*) from crm.equipo e join public.perfiles p on p.id=e.perfil_id where p.correo='vend-inactivo.crm@demo.avancecorp.pe' and not e.activo and not p.activo"), '1');
  console.log('PASS: fixture de baja heredada completado; guardia restaurado en la misma transacción');
}
