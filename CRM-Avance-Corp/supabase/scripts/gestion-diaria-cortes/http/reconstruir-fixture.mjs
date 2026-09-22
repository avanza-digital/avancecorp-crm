// Reconstrucción de fixtures ANTES del candidato. Conserva la base sintética
// usada completa con otro nombre y en pg_dump: no trunca auditoría ni desactiva
// sus guardas. API/Auth siguen apuntando a «postgres», nunca a otro banco.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { writeFileSync, existsSync } from 'node:fs';
import { carpeta, proyecto, contenedor, docker, sql, verificarBanco } from './banco.mjs';

assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
verificarBanco();
assert.equal(sql("select to_regclass('crm.politica_gestion_diaria') is null"),'t',
  'No reconstruir fixtures después de instalar F4: usar la recuperación de la etapa');
const nueva = 'gd_f4_http_limpio';
const anterior = 'gd_f4_http_historial_20260922';
assert.equal(sql(`select count(*) from pg_database where datname='${anterior}'`),'0',
  'La reconstrucción ya se intercambió: detener, no reemplazar ni borrar');
const yaCreada = sql(`select count(*) from pg_database where datname='${nueva}'`) === '1';
const rutaBackup = `${carpeta}/antes-reconstruir-fixtures-${Date.now()}.dump`;
assert.equal(existsSync(rutaBackup),false,'Conservar el respaldo anterior');
const socket = 'unix:///Users/usuario/.docker/run/docker.sock';
function ejecutar(args,{input,binario=false}={}) {
  const r = spawnSync('docker',['--host',socket,...args],
    {input,encoding:binario?null:'utf8',maxBuffer:96*1024*1024});
  if(r.status!==0) throw new Error((r.stderr?.toString()??'').split('\n')
    .filter(l=>/ERROR:|FATAL:/.test(l)).join('\n') || 'Reconstrucción falló; no se imprimen credenciales');
  return r.stdout;
}
const psql = (db,input) => ejecutar(['exec','-i',contenedor,'psql','-XqAt','-U','supabase_admin','-d',db,
  '-v','ON_ERROR_STOP=1','-f','-'],{input});
const dump = opciones => ejecutar(['exec',contenedor,'pg_dump','-U','supabase_admin','-d','postgres',...opciones],
  {binario:opciones.includes('-Fc')});
const respaldo = dump(['-Fc']);
assert.ok(respaldo.length>100_000);
writeFileSync(rutaBackup,respaldo,{mode:0o600});
const esquema = dump(['--schema-only','--no-publications','--no-subscriptions']);
assert.ok(esquema.includes('CREATE SCHEMA crm;') && esquema.includes('CREATE SCHEMA auth;'));
// Sólo historial de instalación de los servicios y reglas técnicas sin actores.
const tablas = ['auth.schema_migrations','storage.migrations','storage.buckets',
  'private.analitica_lc_sello','private.analitica_leads_citas_exenciones','private.analitica_leads_citas_tope',
  'private.auditoria_exenciones','private.auditoria_condicionada','private.auditoria_sello',
  'crm.empresas','crm.enfriamiento_politica','crm.conversion_pesos','crm.productos_inversion','crm.rentabilidad_hitos'];
for(const tabla of tablas) assert.equal(sql(`select to_regclass('${tabla}') is not null`),'t',tabla);
const metadatos = dump(['--data-only',...tablas.flatMap(t=>['--table',t])]);
// Si alguno de estos metadatos adquirió FK hacia personas durante el ensayo,
// la carga falla cerrada; no se copian los usuarios para hacerla pasar.
if(yaCreada) assert.equal(psql(nueva,"select count(*) from pg_tables where schemaname not in ('pg_catalog','information_schema');").trim(),'0',
  'La base de preparación no está vacía: no se toca');
else psql('postgres',`create database ${nueva} with template template0 owner postgres;`);
psql(nueva,`begin; ${esquema}\n${metadatos}
  comment on database ${nueva} is 'BANCO SINTETICO gestion-diaria-f4-http / sin produccion';
  commit;`);
assert.equal(psql(nueva,'select count(*) from auth.users;').trim(),'0');
assert.equal(psql(nueva,'select count(*) from crm.leads;').trim(),'0');
// Intercambio recuperable: la base anterior permanece INTACTA, sin conexiones.
const servicios = ['auth','rest','kong','storage','inbucket'].map(s=>`supabase_${s}_${proyecto}`);
docker(['stop',...servicios]);
psql('template1',`select pg_terminate_backend(pid) from pg_stat_activity where datname='postgres' and pid<>pg_backend_pid();
  alter database postgres rename to ${anterior};
  alter database ${nueva} rename to postgres;`);
docker(['start',...servicios]);
console.log(`PASS: fixture reconstruido sin datos de personas; respaldo y base anterior ${anterior} conservados`);
console.log('ANTES de usar API/SQL: aislar-egreso.mjs --solo-banco-autorizado; luego sembrar y verificar paridad');
