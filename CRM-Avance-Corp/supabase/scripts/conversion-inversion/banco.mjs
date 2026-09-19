// Banco sintético exclusivo de esta tarea; no admite conexiones remotas.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
export const db = 'conversion_inversion_20260918';
export const baseDb = 'conversion_inversion_base_20260919';
export const replayDb = 'conversion_inversion_replay_main_20260919';
export const contenedor = 'supabase_db_avancecorp-f5-bank';
export const q = (x) => x === null ? 'null' : "'" + String(x).replaceAll("'", "''") + "'";
export function ejecutar(input, base = db, usuario = 'postgres') {
  assert.ok([db, baseDb, replayDb, 'postgres', 'prodelco_usd_20260917'].includes(base));
  return spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', usuario,
    '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  {input: '\\set VERBOSITY verbose\n' + input, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
}
export function sql(input, base, usuario) {
  const r = ejecutar(input, base, usuario);
  assert.equal(r.status, 0, r.stderr || r.error?.message);
  return r.stdout.trim();
}
export const objeto = (input) => JSON.parse(sql(input));
const esMain=process.argv[1] && fileURLToPath(import.meta.url)===resolve(process.argv[1]);
if (esMain && process.argv[2] === 'crear') {
  assert.equal(sql(`select count(*) from pg_database where datname=${q(db)}`, 'postgres'), '0',
    'La copia ya existe: consérvala; no se elimina ni reinicia automáticamente.');
  const baseline = JSON.parse(readFileSync(new URL('./baseline-funciones.json', import.meta.url), 'utf8'));
  const actuales = JSON.parse(sql(`select jsonb_object_agg(n.nspname||'.'||p.proname,md5(pg_get_functiondef(p.oid)))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private')`, baseDb));
  for (const f of baseline) assert.equal(actuales[`${f.esquema}.${f.nombre}`], f.huella, `Paridad: ${f.nombre}`);
  sql(`create database ${db} template ${baseDb}`, 'postgres', 'supabase_admin');
  console.log('Copia aislada creada; 16 funciones coinciden con el catálogo productivo leído.');
} else if (esMain && process.argv[2] === 'aplicar') {
  sql(readFileSync(new URL('../../migrations/20260919161807_crm_conversion_inversion_unificada.sql', import.meta.url), 'utf8'));
  console.log('Migración aplicada únicamente a la copia aislada.');
} else if (esMain && process.argv[2] === 'test') {
  console.log(sql(readFileSync(new URL('./test-conversion.sql', import.meta.url), 'utf8'), db, 'supabase_admin'));
  console.log('PASS: oráculo de conversión en la copia aislada; datos revertidos.');
} else if (esMain && process.argv[2] === 'actualizar-funciones') {
  const migracion = readFileSync(new URL('../../migrations/20260919161807_crm_conversion_inversion_unificada.sql', import.meta.url), 'utf8');
  const funciones = [...migracion.matchAll(/create or replace function[\s\S]+?\bas\s+(\$(?:function)?\$)[\s\S]+?\1;/gi)].map(m=>m[0]);
  assert.equal(funciones.length, 21, 'Cambió el número de funciones; revisa el ensayo antes de actualizar.');
  sql("begin; alter table crm.inversion_solicitudes add column if not exists bienvenida jsonb;\n"+funciones.join('\n')+`
    create or replace trigger conversion_reserva_legacy_cerrada before insert on crm.conversion_reservas
      for each row execute function private.conversion_reserva_legacy_cerrada();
    revoke all on function private.conversion_reserva_legacy_cerrada() from public,anon,authenticated,service_role;
    revoke all on function crm.bienvenida_inversion_estado_fn(uuid) from public,anon,service_role;
    grant execute on function crm.bienvenida_inversion_estado_fn(uuid) to authenticated;
    revoke all on function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) from public,anon,authenticated;
    grant execute on function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) to service_role;
    revoke all on function private.inversion_persona_lectura(uuid), private.inversion_contexto_lectura(uuid,uuid) from public,anon,authenticated,service_role;
    revoke all on function crm.cancelar_solicitud_inversion_fn(uuid,integer) from public,anon,service_role;
    grant execute on function crm.cancelar_solicitud_inversion_fn(uuid,integer) to authenticated;
    notify pgrst,'reload schema'; commit;`);
  console.log('Funciones candidatas actualizadas en la copia aislada.');
}
