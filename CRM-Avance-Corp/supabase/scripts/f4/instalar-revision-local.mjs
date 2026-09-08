// Iteración aditiva del banco F4; exige la candidata previa exactamente instalada.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { banco, sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';

const anterior = readFileSync(`${banco}/candidata-antes-revision.sql`, 'utf8');
const { archivo, funciones: nombres } = JSON.parse(readFileSync(new URL('./ultima-migracion.json', import.meta.url), 'utf8'));
const contenido = readFileSync(new URL(`../../migrations/${archivo}`, import.meta.url), 'utf8');
const previas = funcionesDelSql(anterior);
const candidatas = funcionesDelSql(contenido);
assert.equal(previas.length, 30);
assert.equal(candidatas.length, 33);
assert.deepEqual(candidatas.map(f => f.nombre).sort(), nombres);
const modificadas = ['private.inversion_solicitud_resultado','crm.preparar_inversion_fn',
  'crm.confirmar_inversion_fn','private.f4_fuente_inmutable','public.proteger_campos_inmutables'];
const nuevas = ['private.f4_alineacion_perfil_permitida','crm.revisar_solicitud_inversion_fn'];
const originalPerfil = JSON.parse(readFileSync(new URL('./base-funciones-adicionales.json', import.meta.url), 'utf8'))
  .find(f => f.nombre === 'public.proteger_campos_inmutables');
assert(originalPerfil);
const vivas = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',n.nspname||'.'||p.proname,
  'firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
  'body',p.prosrc,'md5',md5(pg_get_functiondef(p.oid)))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${nombres.map(q).join(',')}])`));
assert.equal(vivas.length, 31);
assert.equal(vivas.find(f => f.nombre === originalPerfil.nombre).md5, originalPerfil.md5);
for (const f of previas) {
  assert.equal(vivas.find(v => v.nombre === f.nombre)?.body, f.body, `Cambió ${f.nombre}`);
  if (!modificadas.includes(f.nombre)) assert.equal(candidatas.find(c => c.nombre === f.nombre).body, f.body);
}
assert.deepEqual(candidatas.filter(f => !vivas.some(v => v.nombre === f.nombre)).map(f => f.nombre).sort(), nuevas.slice().sort());
const base = readFileSync(new URL('./01-base.sql', import.meta.url), 'utf8');
const ini = base.indexOf('create table crm.inversion_solicitud_revisiones');
const fin = base.indexOf('create table crm.inversion_ajustes_mes_cerrado', ini);
assert(ini > 0 && fin > ini);
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
const seleccion = nombre => candidatas.find(f => f.nombre === nombre).definicion;
sql(`begin;
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  do $guard$ begin
    if (select activo from crm.multiempresa_flags where nombre='inversiones_escritura') then raise exception 'Apaga el escritor'; end if;
    ${vivas.map(f => `if md5(pg_get_functiondef(${q(f.firma)}::regprocedure))<>${q(f.md5)} then raise exception 'Cambió una función del banco'; end if;`).join('\n')}
  end; $guard$;
  ${base.slice(ini, fin)}
  ${nuevas.map(seleccion).join('\n')}
  ${modificadas.map(seleccion).join('\n')}
  create trigger trg_inversion_revisiones_inmutables before update or delete on crm.inversion_solicitud_revisiones
    for each row execute function private.f4_fuente_inmutable();
  alter table crm.inversion_solicitud_revisiones owner to postgres;
  alter function private.f4_alineacion_perfil_permitida(uuid,uuid) owner to postgres;
  alter function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) owner to postgres;
  revoke all on function private.f4_alineacion_perfil_permitida(uuid,uuid),crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) from public,anon,authenticated,service_role;
  grant execute on function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) to authenticated;
  notify pgrst,'reload schema';
  commit;`);
writeFileSync(new URL('../evidencia-f4/2026-09-07-instalacion-revision-local.json', import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', aplicadoEn: new Date().toISOString(), archivo, modificadas, nuevas,
  sha256Anterior: createHash('sha256').update(anterior).digest('hex'),
  sha256Candidata: createHash('sha256').update(contenido).digest('hex'),
  tablaNueva: 'crm.inversion_solicitud_revisiones', banderaInversiones: false, produccionModificada: false,
}, null, 2) + '\n');
console.log('Revisión de responsable instalada en el banco F4, con historial inmutable y controles de la transacción.');
