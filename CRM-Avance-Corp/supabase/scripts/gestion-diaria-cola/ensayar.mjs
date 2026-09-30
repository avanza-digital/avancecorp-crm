import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { sql, db, ejecutar, objeto, q } from './banco.mjs';

const migracion = readFileSync(new URL('../../migrations/20260930190028_crm_gestion_diaria_cola_trabajo.sql', import.meta.url), 'utf8');
sql(`begin;
  drop function if exists crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text);
  drop function if exists private.gestion_diaria_cola_filas(uuid,text,timestamptz);
  drop function if exists private.gestion_diaria_cola_hechos(uuid,timestamptz);
  ${migracion.replace(/^begin;$/m, '').replace(/^commit;$/m, '')}
  commit;`);
console.log(`PASS: migración instalada en ${db}`);
const actores = objeto("select jsonb_object_agg(rol_crm,perfil_id) from crm.equipo where activo and rol_crm in ('vendedor','gerencia')");
for (const [caso, actor, rol, consulta, error] of [
  ['filtro inválido', actores.vendedor, 'authenticated', "crm.gestion_diaria_cola_trabajo_fn('invalido')", '22023'],
  ['página negativa', actores.vendedor, 'authenticated', "crm.gestion_diaria_cola_trabajo_fn('todo',-1)", '22023'],
  ['límite inválido', actores.vendedor, 'authenticated', "crm.gestion_diaria_cola_trabajo_fn('todo',0,201)", '22023'],
  ['ancla inválida', actores.vendedor, 'authenticated', "crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'ajena')", '22023'],
  ['ayudante privado', actores.vendedor, 'authenticated', `private.gestion_diaria_cola_hechos(${q(actores.vendedor)},now())`, '42501'],
  ['gerencia', actores.gerencia, 'authenticated', 'crm.gestion_diaria_cola_trabajo_fn()', '42501'],
  ['sin sesión', '', 'authenticated', 'crm.gestion_diaria_cola_trabajo_fn()', '42501'],
  ['anónimo', '', 'anon', 'crm.gestion_diaria_cola_trabajo_fn()', '42501'],
]) {
  const r = ejecutar(`\\set VERBOSITY verbose\nbegin;
    select set_config('request.jwt.claim.sub',${q(actor)},true) is not null;
    set local role ${rol}; select ${consulta}; rollback;`);
  assert.notEqual(r.status, 0, caso);
  assert.match(r.stderr, new RegExp(error), `${caso}: ${r.stderr}`);
  console.log(`PASS: ${caso} (${error})`);
}
const inicio = performance.now();
for (const [caso, cambio] of [
  ['miembro inactivo', 'activo=false'], ['coordinador', "rol_crm='coordinador'"],
]) {
  const r = ejecutar(`\\set VERBOSITY verbose\nbegin;
    alter table crm.equipo disable trigger user;
    update crm.equipo set ${cambio} where perfil_id=${q(actores.vendedor)};
    alter table crm.equipo enable trigger user;
    select set_config('request.jwt.claim.sub',${q(actores.vendedor)},true) is not null;
    set local role authenticated; select crm.gestion_diaria_cola_trabajo_fn(); rollback;`);
  assert.notEqual(r.status, 0, caso); assert.match(r.stderr, /42501/, r.stderr);
  console.log(`PASS: ${caso} (42501)`);
}
const salida = sql(readFileSync(new URL('./prueba.sql', import.meta.url), 'utf8'));
const lineas = salida.split('\n');
const fixture = lineas.find((l) => l.startsWith('GESTION_COLA_FIXTURE:'));
assert.ok(fixture, 'fixture del SQL real');
writeFileSync(new URL('../../../app/src/data/gestion-diaria-cola-sql.fixture.json', import.meta.url),
  JSON.stringify(JSON.parse(fixture.slice('GESTION_COLA_FIXTURE:'.length)), null, 2) + '\n');
console.log(lineas.filter((l) => l.startsWith('GESTION_DIARIA_COLA_OK')).join('\n'));
console.log(sql('select private.assert_cola_v3(); select private.assert_sla_nucleo();'));
const roles = sql(readFileSync(new URL('./roles.sql', import.meta.url), 'utf8'));
console.log(roles.split('\n').filter((l) => l.startsWith('GESTION_COLA_ROLES_OK')).join('\n'));
writeFileSync(new URL('./resultado-local.json', import.meta.url), JSON.stringify({
  banco: db, comprobado_en: new Date().toISOString(), duracion_ms: Math.round(performance.now() - inicio),
  salida: lineas.filter((l) => l.startsWith('GESTION_DIARIA_COLA_OK')).join('\n'),
}, null, 2) + '\n');
