import { entorno } from './banco-local.mjs';
// Iteración acotada del banco existente; una base nueva instala la candidata completa.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';

assert.equal(entorno, 'avancecorp-f4-bank', 'El instalador de transición sólo corresponde al banco de desarrollo');
const anterior = readFileSync('/private/tmp/avancecorp-f4-bank/candidata-antes-reintento-confirmado.sql', 'utf8');
const manifiesto = JSON.parse(readFileSync(new URL('./ultima-migracion.json', import.meta.url), 'utf8'));
const candidata = readFileSync(new URL(`../../migrations/${manifiesto.archivo}`, import.meta.url), 'utf8');
const previas = funcionesDelSql(anterior);
const actuales = funcionesDelSql(candidata);
const cambios = ['private.inversion_persona_autorizada', 'private.inversion_persona_contexto',
  'crm.preparar_inversion_fn', 'crm.confirmar_inversion_fn', 'crm.acceso_inversion_fn'];
assert.equal(previas.length, 33);
assert.equal(actuales.length, 34);
assert.deepEqual(actuales.map(f => f.nombre).sort(), manifiesto.funciones);
assert.deepEqual(actuales.map(f => f.nombre).sort(), [...previas.map(f => f.nombre), cambios[0]].sort());
for (const f of previas) if (!cambios.includes(f.nombre)) {
  assert.equal(actuales.find(a => a.nombre === f.nombre).body, f.body, `Cambio fuera de esta iteración: ${f.nombre}`);
}
assert.equal(sql("select to_regprocedure('private.inversion_persona_autorizada(uuid)') is null"), 't');
const vivas = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',n.nspname||'.'||p.proname,
  'firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
  'body',p.prosrc,'md5',md5(pg_get_functiondef(p.oid))))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${previas.map(f => q(f.nombre)).join(',')}])`));
assert.equal(vivas.length, previas.length);
for (const f of previas) assert.equal(vivas.find(v => v.nombre === f.nombre).body, f.body);
sql(`begin;
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  do $guard$ begin
    if (select activo from crm.multiempresa_flags where nombre='inversiones_escritura') then
      raise exception 'Apaga el escritor del banco antes de iterar'; end if;
    if to_regprocedure('private.inversion_persona_autorizada(uuid)') is not null then
      raise exception 'La ampliación de reintento ya está instalada'; end if;
    ${vivas.map(f => `if md5(pg_get_functiondef(${q(f.firma)}::regprocedure))<>${q(f.md5)} then raise exception 'Cambió una función desde la captura'; end if;`).join('\n')}
  end; $guard$;
  ${cambios.map(nombre => actuales.find(f => f.nombre === nombre).definicion).join('\n')}
  alter function private.inversion_persona_autorizada(uuid) owner to postgres;
  revoke all on function private.inversion_persona_autorizada(uuid) from public,anon,authenticated,service_role;
  notify pgrst,'reload schema';
  commit;`);
const instaladoEn = new Date().toISOString();
const sha = texto => createHash('sha256').update(texto).digest('hex');
writeFileSync(new URL(`../evidencia-f4/iteracion-reintento-${instaladoEn.replaceAll(':', '-')}.json`, import.meta.url),
  JSON.stringify({ entorno, instaladoEn, funciones: cambios,
    sha256Anterior: sha(anterior), sha256Candidata: sha(candidata),
    soloFunciones: true, banderaInversiones: false, produccionModificada: false }, null, 2) + '\n', { flag: 'wx' });
console.log('Reintento F4 local: cuatro funciones ajustadas y un auxiliar privado; escritor apagado.');
