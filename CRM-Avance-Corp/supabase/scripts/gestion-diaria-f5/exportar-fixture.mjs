// Respuestas auténticas de las RPC sobre fixtures sintéticos, sólo para tests.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from './banco.mjs';

let preparacion = readFileSync(new URL('./test-pulso-habitos.sql', import.meta.url), 'utf8')
  .split('create temporary table f5_fotos')[0];
const fechaMovil = "(statement_timestamp() at time zone 'America/Lima')::date-1 as dia";
assert.ok(preparacion.includes(fechaMovil), 'No se encontró el ancla de fecha del fixture');
preparacion = preparacion.replace(fechaMovil, "date '2026-09-23' as dia");
const salida = sql(`${preparacion}
select set_config('request.jwt.claim.sub',gerente::text,true) from f5_actores;
set local role authenticated;
select jsonb_build_object('pulso',crm.gestion_diaria_pulso_fn(dia),
  'habitos',crm.gestion_diaria_habitos_fn(dia,7),
  'habitos14',crm.gestion_diaria_habitos_fn(dia,14),
  'habitos30',crm.gestion_diaria_habitos_fn(dia,30),
  'equipo',crm.gestion_diaria_equipo_fn(dia,null)) from f5_actores;
rollback;`);
const fixture = JSON.parse(salida.split('\n').findLast((linea) => linea.startsWith('{')));
writeFileSync(new URL('../../../app/src/lib/gestion-diaria-f5.test.fixture.json', import.meta.url), `${JSON.stringify(fixture, null, 2)}\n`);
console.log('PASS: fixture de pulso/equipo/hábitos 7, 14 y 30 exportado; datos locales revertidos.');
