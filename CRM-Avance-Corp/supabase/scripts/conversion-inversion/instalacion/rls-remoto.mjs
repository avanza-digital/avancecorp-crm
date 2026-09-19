// Ejecuta el gate bancario vigente en el banco remoto exclusivo y sintético.
// No admite otro destino; las credenciales solo se pasan por entorno.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {cfg,apiUrl,env,sql} from './banco-remoto.mjs';

const esperado='2a8ce9e9be01ccdbf13871e299858db4a6a90551b195a2369ba14d06ddc4c5f4';
assert.equal(sql(`select encode(extensions.digest(statements[1],'sha256'),'hex')
  from supabase_migrations.schema_migrations where version='20260919172019'`),esperado);
// Receta LEEME-seed: retirar exclusivamente hechos ficticios de las pruebas
// anteriores. Conservar configuración y DDL, incluida la candidata exacta.
sql(`begin;
  set local session_replication_role=replica;
  truncate crm.actividades,crm.tareas,crm.lead_asignaciones,crm.leads,
    crm.inversionistas,crm.cuentas_bancarias,public.contratos cascade;
  delete from crm.equipo;
  update public.perfiles set domicilio=null where rol='cliente';
  set local session_replication_role=origin;
  grant select on crm.periodos_cerrados to service_role;
  commit;`);
const destino=new URL(cfg.POSTGRES_URL);destino.port='5432';
const entorno={...env,PATH:'/opt/homebrew/opt/postgresql@17/bin:'+process.env.PATH,
  SUPABASE_URL:apiUrl,SUPABASE_ANON_KEY:cfg.SUPABASE_ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY:cfg.SUPABASE_SERVICE_ROLE_KEY,
  CRM_DEMO_PASSWORD:randomBytes(24).toString('base64url'),CRM_BANCO_PSQL_URL:destino.href};
function ejecutar(archivo,args=[]){
  const r=spawnSync(process.execPath,[archivo,...args],{env:entorno,stdio:'inherit'});
  assert.equal(r.status,0,`Fallo del gate ${archivo}; consultar su salida.`);
}
try {
  ejecutar('supabase/scripts/seed-demo.mjs');
} finally {
  sql('revoke select on crm.periodos_cerrados from service_role;');
}
sql(`begin;
  alter table crm.equipo disable trigger user;
  update crm.equipo set activo=false where perfil_id=(select id from public.perfiles where nombre_completo='ANALISTA INACTIVO');
  alter table crm.equipo enable trigger user;
  update public.perfiles set activo=false where nombre_completo='ANALISTA INACTIVO';
  commit;`);
assert.equal(sql(`select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('crm','private','public')
  and not t.tgisinternal and t.tgenabled='D'`),'0');
assert.equal(sql("select has_table_privilege('service_role','crm.periodos_cerrados','select')"),'f');
console.log('PASS: fixtures nuevos; triggers y permisos restaurados antes de medir.');
ejecutar('supabase/scripts/test-rls.mjs',['--contratos']);
