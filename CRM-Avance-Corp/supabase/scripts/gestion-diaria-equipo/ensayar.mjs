// Ensayo reproducible, únicamente en la copia F4. El sellado es un reemplazo
// mecánico generado desde pg_get_functiondef, no una edición de migraciones publicadas.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { db, sql } from './banco.mjs';
const migracion = new URL('../../migrations/20260921040335_crm_gestion_diaria_equipo_vista.sql', import.meta.url);
const leer = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
const firmas = ['crm.gestion_diaria_equipo_fn(date,uuid)', 'private.gestion_diaria_equipo_core(date,uuid)', 'private.gestion_diaria_equipo_pendientes()'];
const placeholders = ['MD5_EQUIPO_PUERTA', 'MD5_EQUIPO_CORE', 'MD5_EQUIPO_PENDIENTES'];
const huellas = `select jsonb_build_array(${firmas.map((f) => `md5(pg_get_functiondef('${f}'::regprocedure))`).join(',')});`;
assert.equal(sql('select current_database()'), db);
if (sql(`select to_regprocedure('${firmas[0]}') is not null`) === 't') sql(leer('./reversa.sql'));
const censo = () => sql("select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()");
const censoAntes = censo();
const paraguasAntes = sql("select md5(pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure))");
let fuente = readFileSync(migracion, 'utf8');
if (placeholders.some((p) => fuente.includes(p))) {
  const provisional = fuente.replace(/do \$postflight\$[\s\S]*?\$postflight\$;/, '')
    .replace("notify pgrst, 'reload schema';", '').replace(/commit;\s*$/, `${huellas}\nrollback;`);
  const sellos = JSON.parse(sql(provisional));
  for (let i = 0; i < placeholders.length; i++) {
    assert.match(sellos[i], /^[a-f0-9]{32}$/);
    fuente = fuente.replaceAll(placeholders[i], sellos[i]);
  }
  writeFileSync(migracion, fuente);
}
sql(fuente);
console.log('PASS: migración sellada, gates F1–F4 y SLA');
assert.match(sql(leer('./test-equipo.sql')), /GESTION_DIARIA_EQUIPO_OK/);
console.log('PASS: oráculo de equipo bajo authenticated');
assert.match(sql(leer('./test-jerarquia.sql')), /GESTION_DIARIA_JERARQUIA_OK/);
console.log('PASS: puente inactivo, ciclo, ámbito gerencia/global y SLA canónico');
assert.match(sql(leer('./test-calendario.sql')), /GESTION_DIARIA_CALENDARIO_OK/);
console.log('PASS: sin cartera, cero actividad, reloj Lima, fin de semana y modo observación');
assert.equal(censo(), censoAntes, 'El censo analítico no cambia');
const sellos = JSON.parse(sql(huellas));
sql(leer('./reversa.sql'));
assert.equal(sql("select md5(pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure))"), paraguasAntes, 'Reversa exacta de F3');
assert.equal(sql(`select to_regprocedure('${firmas[0]}') is null`), 't');
sql(fuente);
assert.deepEqual(JSON.parse(sql(huellas)), sellos);
console.log('PASS: reversa sin pérdida y reinstalación determinista');
writeFileSync(new URL('./verificacion.json', import.meta.url), JSON.stringify({
  estado: 'PASS', base: db, ensayado_en: new Date().toISOString(),
  sha256_migracion: createHash('sha256').update(fuente).digest('hex'),
  funciones: firmas.map((firma, i) => ({ firma, md5: sellos[i] })),
  censo_intacto: true, reversa_exacta: true,
  oraculos: ['GESTION_DIARIA_EQUIPO_OK', 'GESTION_DIARIA_JERARQUIA_OK', 'GESTION_DIARIA_CALENDARIO_OK'],
}, null, 2) + '\n');
