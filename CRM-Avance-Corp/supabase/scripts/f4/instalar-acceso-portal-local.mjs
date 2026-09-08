import { entorno } from './banco-local.mjs';
// Iteración aditiva exclusiva del banco que ya contiene la candidata anterior.
// No registra migraciones, importa filas ni admite bases remotas.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { banco, sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';

assert.equal(entorno, 'avancecorp-f4-bank', 'El instalador de transición sólo corresponde al banco de desarrollo');
const anterior = readFileSync(`${banco}/candidata-antes-portal.sql`, 'utf8');
const { archivo, funciones: nombres } = JSON.parse(readFileSync(new URL('./ultima-migracion.json', import.meta.url), 'utf8'));
const contenido = readFileSync(new URL(`../../migrations/${archivo}`, import.meta.url), 'utf8');
const previas = funcionesDelSql(anterior);
const candidatas = funcionesDelSql(contenido);
assert.equal(previas.length, 28);
assert.equal(candidatas.length, 30);
assert.deepEqual(candidatas.map(f => f.nombre).sort(), nombres);
const agregadas = candidatas.filter(f => !previas.some(p => p.nombre === f.nombre));
assert.deepEqual(agregadas.map(f => f.nombre).sort(), ['crm.acceso_inversion_fn', 'private.inversion_datos_portal']);
for (const f of previas) {
  if (f.nombre !== 'crm.preparar_inversion_fn') assert.equal(candidatas.find(c => c.nombre === f.nombre).body, f.body);
}
const vivas = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',n.nspname||'.'||p.proname,
  'firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
  'body',p.prosrc,'md5',md5(pg_get_functiondef(p.oid))))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${nombres.map(q).join(',')}])`));
assert.equal(vivas.length, 28, 'La iteración requiere la candidata previa sin este módulo');
for (const f of previas) assert.equal(vivas.find(v => v.nombre === f.nombre)?.body, f.body, `Cambió ${f.nombre}`);
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
const seleccionar = nombre => candidatas.find(f => f.nombre === nombre).definicion;
sql(`begin;
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  do $guard$ begin
    if (select activo from crm.multiempresa_flags where nombre='inversiones_escritura') then
      raise exception 'Apaga primero el escritor del banco'; end if;
    ${vivas.map(f => `if md5(pg_get_functiondef(${q(f.firma)}::regprocedure))<>${q(f.md5)} then raise exception 'Cambió una función del banco'; end if;`).join('\n')}
  end; $guard$;
  alter table crm.inversion_solicitudes add column auth_claim_id uuid, add column auth_contexto jsonb,
    add constraint inversion_solicitud_auth_contexto check (
      (auth_claim_id is null and auth_contexto is null) or
      (auth_claim_id is not null and auth_contexto is not null and jsonb_typeof(auth_contexto)='object'));
  create index inversion_solicitudes_auth_idx on crm.inversion_solicitudes(auth_claim_id) where auth_claim_id is not null;
  create or replace trigger trg_audit_inversion_solicitudes after insert or update or delete on crm.inversion_solicitudes
    for each row execute function private.log_audit_sin_secretos('datos','auth_contexto');
  ${seleccionar('private.inversion_datos_portal')}
  ${seleccionar('crm.preparar_inversion_fn')}
  ${seleccionar('crm.acceso_inversion_fn')}
  alter function private.inversion_datos_portal(jsonb) owner to postgres;
  alter function crm.acceso_inversion_fn(uuid,text,jsonb) owner to postgres;
  revoke all on function private.inversion_datos_portal(jsonb),crm.acceso_inversion_fn(uuid,text,jsonb) from public,anon,authenticated,service_role;
  grant execute on function crm.acceso_inversion_fn(uuid,text,jsonb) to authenticated;
  notify pgrst,'reload schema';
  commit;`);
writeFileSync(new URL('../evidencia-f4/2026-09-07-instalacion-portal-local.json', import.meta.url), JSON.stringify({
  entorno, aplicadoEn: new Date().toISOString(), archivo,
  sha256Anterior: createHash('sha256').update(anterior).digest('hex'),
  sha256Candidata: createHash('sha256').update(contenido).digest('hex'),
  nuevas: agregadas.map(f => f.nombre), modificadas: ['crm.preparar_inversion_fn'],
  columnasSolicitud: ['auth_claim_id', 'auth_contexto'], banderaInversiones: false, produccionModificada: false,
}, null, 2) + '\n');
console.log('Acceso Portal F4 instalado en el banco: dos funciones nuevas, solicitud vinculada y contexto enmascarado en auditoría.');
