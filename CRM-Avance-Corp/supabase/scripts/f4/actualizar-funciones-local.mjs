import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
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
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  do $guard$ begin
  ${vivas.map(f => `if md5(pg_get_functiondef(${q(f.firma)}::regprocedure))<>${q(f.md5)} then raise exception 'Cambió una función mientras se preparaba la iteración'; end if;`).join('\n')}
  end; $guard$;
  ${actualizar.join('\n')}
  notify pgrst,'reload schema';
  commit;`);
writeFileSync(new URL('../evidencia-f4/2026-09-07-iteracion-local.json', import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', aplicadoEn: new Date().toISOString(), archivo,
  sha256Candidata: createHash('sha256').update(contenido).digest('hex'), funciones: solicitadas,
  cambioSoloFunciones: true, banderaInversiones: false, produccionModificada: false,
}, null, 2) + '\n');
console.log(`Iteración F4 local: ${solicitadas.length} funciones actualizadas; las otras ${funciones.length - solicitadas.length} coinciden con la candidata.`);
