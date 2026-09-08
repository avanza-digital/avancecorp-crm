import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';

const solicitadas = process.argv.slice(2);
assert(solicitadas.length > 0 && solicitadas.every(s => /^[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*$/.test(s)), 'Nombra solo las funciones revisadas para esta iteración local');
const { archivo, funciones: esperadas } = JSON.parse(readFileSync(new URL('./ultima-migracion.json', import.meta.url), 'utf8'));
assert(/^\d{14}_crm_f4_.*\.sql$/.test(archivo));
const contenido = readFileSync(new URL(`../../migrations/${archivo}`, import.meta.url), 'utf8');
const funciones = funcionesDelSql(contenido);
assert.deepEqual(funciones.map(f => f.nombre).sort(), esperadas, 'La comparación debe cubrir todas las funciones declaradas, incluidas las versiones con dígitos');
const vivas = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',n.nspname||'.'||p.proname,
  'firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
  'body',p.prosrc,'md5',md5(pg_get_functiondef(p.oid)),'owner',pg_get_userbyid(p.proowner)))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${funciones.map(f => q(f.nombre)).join(',')}])`));
assert.equal(vivas.length, funciones.length);
for (const fn of funciones) assert.equal(vivas.filter(v=>v.nombre===fn.nombre).length,1,
  `Se exige una sola firma instalada para ${fn.nombre}`);
assert.equal(new Set(solicitadas).size,solicitadas.length,'No repitas funciones');
for (const fn of funciones) {
  const actual = vivas.find(x => x.nombre === fn.nombre);
  if (!solicitadas.includes(fn.nombre)) assert.equal(actual.body, fn.body,
    `Difiere una función que no se pidió modificar: ${fn.nombre}`);
}
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f',
  'Apaga el escritor del banco antes de cambiar sus funciones');
const actualizar = solicitadas.map(nombre => {
  const f = funciones.find(f => f.nombre === nombre);
  assert(f, `Función ausente de la candidata: ${nombre}`);
  return f.definicion;
});
sql(`begin;
  set local lock_timeout='5s';
  select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  do $guard$ begin
  if private.inversiones_escritura_bajo_candado() then
    raise exception 'El escritor se encendió antes de la iteración'; end if;
  ${vivas.map(f => `if md5(pg_get_functiondef(${q(f.firma)}::regprocedure))<>${q(f.md5)} then raise exception 'Cambió una función mientras se preparaba la iteración'; end if;`).join('\n')}
  end; $guard$;
  ${actualizar.join('\n')}
  notify pgrst,'reload schema';
  commit;`);
const aplicadoEn=new Date().toISOString();
writeFileSync(new URL(`../evidencia-f4/iteracion-funciones-${aplicadoEn.replaceAll(':','-')}-${randomUUID()}.json`, import.meta.url), JSON.stringify({
  entorno, aplicadoEn, archivo,
  sha256Candidata: createHash('sha256').update(contenido).digest('hex'), funciones: solicitadas,
  cambioSoloFunciones: true, banderaInversiones: false, produccionModificada: false,
}, null, 2) + '\n', {flag:'wx'});
console.log(`Iteración F4 local: ${solicitadas.length} funciones actualizadas; las otras ${funciones.length - solicitadas.length} coinciden con la candidata.`);
