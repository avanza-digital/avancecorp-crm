// Ensayo completo de «las llamadas a clientes cuentan» (Gestión Diaria, 19/10/2026) sobre el banco propio:
// 1) foto ANTES (huellas = producción, estado de los gates, censo analítico); 2) SELLADO en dos pasadas (la
// migración con placeholders instala sin postflight, se miden las tres huellas y se escriben en el archivo, se
// deshace con la reversa); 3) instalación real; 4) en el banco SE SIMULA el re-sellado ajeno pendiente
// (20261016211001: huellas de crm.equipo_visible_fn en el gate del analista y de private.trg_sla_recibo_guard en
// el gate del resultado) para que el gate esté VERDE y los mutantes sean concluyentes; 5) gate, mutantes nuevos
// (11) y viejos (24), oráculo, censo intacto; 6) reversa → huellas de producción, reinstalación determinista.
// Nunca toca producción: banco.mjs fija contenedor y base.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, contenedor, sql, ejecutar, md5Vivo, existe } from './banco.mjs';

const VERSION = '20261019170422';
const NOMBRE = 'crm_gestion_diaria_llamadas_clientes';
const rutaMigracion = new URL(`../../migrations/${VERSION}_${NOMBRE}.sql`, import.meta.url);
const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const rutaReversa = new URL('./reversa.sql', import.meta.url);
let reversa = leer('./reversa.sql');
const oraculo = leer('./test-gestion-diaria-llamadas-clientes.sql');

const AYUDANTE = 'private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])';
const LECTOR = 'private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])';
const AGREGADOR = 'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])';
const GATE = 'private.assert_gestion_diaria_analista()';
const MUTANTES = 'private.assert_gestion_diaria_llamadas_clientes_mutantes()';
// Huellas vivas en producción el 19/10/2026 (medidas por pg_get_functiondef, iguales en el banco).
const PROD = {
  lector: '27d25609c74e04c58f82e36af45d7327',
  agregador: '7c5d14e65cc0e55e57214589d11e9c9d',
  gate: 'eb2c03fd99f13cda077f8c02e4533ec4',
  citas: '12012959d2e751c43df86b847dcce037',
  pulso: 'bdccbb6e3fee574416a0987941ae344b',
  equipoVisible: '58bd05540d2a3eb576a7b648978707e7',
  equipoVisibleSellado: '200162f4519586a6c68d8ccf0cf591f7',
  trgRecibo: 'f111fdd9d8eb904fde961c6dcc7a9a9a',
};
const gate = () => { const r = ejecutar(`select ${GATE}`); return r.status === 0 ? r.stdout.trim() : 'ROJO: ' + (r.stderr.match(/ERROR:\s+(.*)/)?.[1] ?? r.stderr); };
const censo = () => sql(`select coalesce(string_agg(objeto::text || '|' || declarada::text || '|' || huella_ok::text, ';' order by objeto::text), '') from private.contadores_crudos_leads_citas()`);
const existeHoy = (txt) => sql(`select (${txt})::text`) === 'true';

console.log(`banco ${contenedor}/${db}`);
assert.equal(sql('select current_database()'), db);

// 1. Si ya estaba instalada (segunda corrida), se retira con la reversa para ensayar limpio, y se deshacen las
//    simulaciones banco-only de una corrida anterior si quedaron puestas.
const desimular = (firma, viejo, nuevo) => sql(`do $x$ declare d text := pg_get_functiondef('${firma}'::regprocedure); begin
  if strpos(d, '${viejo}') > 0 then execute replace(d, '${viejo}', '${nuevo}'); end if; end $x$;`);
if (existe(AYUDANTE)) {
  // La reversa pinna las huellas selladas; para limpiar una instalación de una corrida ANTERIOR (otra versión del
  // cuerpo) se le dan las huellas vivas del banco, solo en memoria.
  const limpieza = reversa
    .replaceAll('REV_MD5_AYUDANTE_PENDIENTE_000000', md5Vivo(AYUDANTE))
    .replaceAll('REV_MD5_LECTOR_PENDIENTE_00000000', md5Vivo(LECTOR))
    .replaceAll('REV_MD5_AGREGADOR_PENDIENTE_00000', md5Vivo(AGREGADOR))
    .replace(/'[0-9a-f]{32}' or v_md5_lector <> '[0-9a-f]{32}'\n     or v_md5_agregador <> '[0-9a-f]{32}'/, `'${md5Vivo(AYUDANTE)}' or v_md5_lector <> '${md5Vivo(LECTOR)}'\n     or v_md5_agregador <> '${md5Vivo(AGREGADOR)}'`);
  sql(limpieza); console.log('instalación previa retirada con la reversa (huellas vivas)');
}
desimular(GATE, PROD.equipoVisible, PROD.equipoVisibleSellado);
desimular('private.assert_gestion_diaria_pulso()', '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado', '  perform private.assert_analitica_leads_citas();');
assert.ok(!existe(AYUDANTE));
assert.equal(md5Vivo(LECTOR), PROD.lector, 'El banco tiene el lector de producción');
assert.equal(md5Vivo(AGREGADOR), PROD.agregador, 'El banco tiene el agregador de producción');
assert.equal(md5Vivo('crm.equipo_visible_fn()'), PROD.equipoVisible, 'El banco tiene el roster vivo (consulta de Coordinación)');
const censoAntes = censo();
assert.equal(md5Vivo(GATE), PROD.gate, 'El banco tiene el gate del analista de producción (eb2c03fd…)');
assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), PROD.citas, 'El banco tiene el gate de citas de producción');
assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), PROD.pulso, 'El banco tiene el gate del pulso de producción');
const gateAntes = gate();
console.log(`gate ANTES: ${gateAntes}`);
assert.match(gateAntes, /^ROJO: (P0001: )?El cuerpo de crm\.equipo_visible_fn\(\) cambio/, 'ANTES: el gate está en rojo SOLO por el roster (ajeno, 15/10)');

// 2. SELLADO en dos pasadas.
let migracion = readFileSync(rutaMigracion, 'utf8');
if (migracion.includes('_PENDIENTE_')) {
  const sinPostflight = migracion.replace(/do \$postflight\$[\s\S]*?\$postflight\$;/, 'select 1;');
  assert.notEqual(sinPostflight, migracion, 'no se encontró el bloque postflight');
  sql(sinPostflight);
  const sellos = {
    MD5_AYUDANTE_CLIENTES_PENDIENTE_00: md5Vivo(AYUDANTE),
    MD5_LECTOR_PENDIENTE_000000000000: md5Vivo(LECTOR),
    MD5_AGREGADOR_PENDIENTE_0000000000: md5Vivo(AGREGADOR),
  };
  for (const [k, v] of Object.entries(sellos)) {
    assert.match(v, /^[0-9a-f]{32}$/, `md5 de ${k}`);
    assert.ok(migracion.includes(k), `placeholder ${k} ausente`);
    migracion = migracion.replaceAll(k, v);
  }
  writeFileSync(rutaMigracion, migracion);
  // La reversa pinna las mismas huellas (no pisa a ciegas).
  const sellosReversa = {
    REV_MD5_AYUDANTE_PENDIENTE_000000: sellos.MD5_AYUDANTE_CLIENTES_PENDIENTE_00,
    REV_MD5_LECTOR_PENDIENTE_00000000: sellos.MD5_LECTOR_PENDIENTE_000000000000,
    REV_MD5_AGREGADOR_PENDIENTE_00000: sellos.MD5_AGREGADOR_PENDIENTE_0000000000,
  };
  for (const [k, v] of Object.entries(sellosReversa)) {
    assert.ok(reversa.includes(k), `placeholder ${k} ausente en la reversa`);
    reversa = reversa.replaceAll(k, v);
  }
  writeFileSync(rutaReversa, reversa);
  sql(reversa);
  assert.ok(!existe(AYUDANTE), 'la instalación provisional se retiró');
  assert.equal(md5Vivo(GATE), PROD.gate, 'la reversa devolvió el gate de producción');
  assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), PROD.citas, 'la reversa devolvió el gate de citas');
  assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), PROD.pulso, 'la reversa devolvió el gate del pulso');
  console.log(`md5 sellados en la migración: ${Object.values(sellos).join(' ')}`);
}
assert.ok(!migracion.includes('_PENDIENTE_'));
assert.ok(!reversa.includes('REV_MD5_'), 'la reversa quedó con placeholders');

// 3. Instalación real: el postflight acepta el rojo ajeno del roster.
sql(migracion);
assert.ok(existe(AYUDANTE) && existe(MUTANTES));
const md5 = { ayudante: md5Vivo(AYUDANTE), lector: md5Vivo(LECTOR), agregador: md5Vivo(AGREGADOR), gate: md5Vivo(GATE),
  citas: md5Vivo('private.assert_gestion_diaria_citas()'), pulso: md5Vivo('private.assert_gestion_diaria_pulso()') };
assert.match(sql('select private.assert_gestion_diaria_citas()'), /^OK/, 'gate de citas VERDE tras instalar (re-sellado)');
assert.match(gate(), /^ROJO: (P0001: )?El cuerpo de crm\.equipo_visible_fn\(\) cambio/, 'tras instalar: el gate sigue en rojo SOLO por el roster');
assert.match(ejecutar(`set gestion_diaria.banco = on; select ${MUTANTES}`).stderr, /GATE EN ROJO antes de mutar/, 'los mutantes se niegan con el gate en rojo');

// 4. Simulación BANCO-ONLY del re-sellado ajeno (20261016211001) para poner el gate en verde.
const simular = (firma, viejo, nuevo) => sql(`do $x$ declare d text := pg_get_functiondef('${firma}'::regprocedure); begin
  if strpos(d, '${viejo}') = 0 then raise exception 'simulacion: % no trae %', '${firma}', '${viejo}'; end if;
  execute replace(d, '${viejo}', '${nuevo}'); end $x$;`);
simular(GATE, PROD.equipoVisibleSellado, PROD.equipoVisible);
assert.match(gate(), /^OK/, 'gate del analista VERDE con el roster re-sellado (simulación de 211001)');
// El pulso también exige el censo analítico, rojo en producción desde el 01/10 por otras 10 piezas ajenas: se
// neutraliza SOLO en el banco (y se deshace antes de comprobar la identidad con producción).
const PULSO = 'private.assert_gestion_diaria_pulso()';
const CENSO_LINEA = '  perform private.assert_analitica_leads_citas();';
const censoRojo = ejecutar('select private.assert_analitica_leads_citas()');
assert.ok(censoRojo.status !== 0 && !/llamadas_clientes|gestion_diaria_llamadas/.test(censoRojo.stderr), 'el censo está rojo solo por piezas ajenas: ' + censoRojo.stderr.split('\n')[0]);
simular(PULSO, CENSO_LINEA, '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado');
assert.match(sql(`select ${PULSO}`), /^OK/, 'gate del pulso VERDE (re-sellado + roster simulado + censo ajeno neutralizado)');
const paraguasAntes = ejecutar('select private.assert_gestion_diaria()');
if (paraguasAntes.status !== 0 && /trg_sla_recibo_guard/.test(paraguasAntes.stderr)) {
  const viejoTrg = paraguasAntes.stderr.match(/trg_sla_recibo_guard\(\) cambio: [^(]*\(md5 ([0-9a-f]{32})\)/)?.[1];
  const sellado = sql(`select substring(prosrc from '''private\\.trg_sla_recibo_guard\\(\\)''[^'']*''([0-9a-f]{32})''') from pg_proc where oid = 'private.assert_gestion_diaria_resultado()'::regprocedure`);
  assert.equal(viejoTrg, PROD.trgRecibo);
  simular('private.assert_gestion_diaria_resultado()', sellado, PROD.trgRecibo);
}
const paraguas = ejecutar('select private.assert_gestion_diaria()');
console.log(`paraguas tras simular 211001: ${paraguas.status === 0 ? paraguas.stdout.trim() : 'ROJO ' + paraguas.stderr.split('\n')[0]}`);

// 5. Mutantes nuevos y viejos, oráculo, censo.
const mutantesNuevos = sql(`set gestion_diaria.banco = on; select ${MUTANTES}`);
assert.match(mutantesNuevos, /^OK: 12 mutantes detectados/, mutantesNuevos);
assert.match(gate(), /^OK/, 'gate tras los mutantes nuevos (nada quedó alterado)');
let mutantesViejos = 'NOT RUN (paraguas en rojo por un guardián ajeno)';
if (paraguas.status === 0) {
  mutantesViejos = sql('set gestion_diaria.banco = on; select private.assert_gestion_diaria_analista_mutantes()');
  assert.match(mutantesViejos, /^OK: 24 mutantes detectados/, mutantesViejos);
}
assert.match(ejecutar(`select ${MUTANTES}`).stderr, /solo corren en el banco/, 'Sin la marca de banco los mutantes se niegan');
const salida = sql(oraculo);
assert.match(salida, /GESTION_DIARIA_LLAMADAS_CLIENTES_OK/, salida);
assert.equal(censo(), censoAntes, 'El censo analítico no cambia');

// 5b. La cadena completa en una transacción de SOLO LECTURA (como PostgREST ejecuta las puertas STABLE), con tiempos.
const soloLectura = (sub, consulta) => {
  const r = ejecutar(`begin read only;
select set_config('request.jwt.claim.sub','${sub}',true);
select set_config('request.jwt.claims','{"sub":"${sub}","role":"authenticated"}',true);
set local role authenticated;
select extract(epoch from clock_timestamp())::text; ${consulta}; select extract(epoch from clock_timestamp())::text;
reset role; rollback;`);
  assert.equal(r.status, 0, 'solo lectura: ' + r.stderr);
  const lineas = r.stdout.trim().split('\n');
  return Math.round((Number(lineas.at(-1)) - Number(lineas.at(-3))) * 1000);
};
const GER = 'b0000000-0000-4000-8000-000000000003', V1 = 'b0000000-0000-4000-8000-000000000002';
const medir = () => ({
  analista_ms: soloLectura(V1, 'select crm.gestion_diaria_analista_fn()'),
  pulso_ms: soloLectura(GER, "select crm.gestion_diaria_pulso_fn((now() at time zone 'America/Lima')::date)"),
  habitos30_ms: soloLectura(GER, "select crm.gestion_diaria_habitos_fn((now() at time zone 'America/Lima')::date, 30)"),
});
const tiemposInstalada = medir();
console.log(`solo lectura OK · instalada: ${JSON.stringify(tiemposInstalada)}`);

// 6. Reversa (sobre el gate simulado: compone) → lector y agregador de producción; reinstalación determinista.
sql(reversa);
const tiemposProduccion = medir();
console.log(`solo lectura OK · producción (tras la reversa): ${JSON.stringify(tiemposProduccion)}`);
assert.ok(!existe(AYUDANTE) && !existe(MUTANTES), 'La reversa retira el ayudante y los mutantes');
assert.equal(md5Vivo(LECTOR), PROD.lector, 'La reversa devuelve el lector de producción');
assert.equal(md5Vivo(AGREGADOR), PROD.agregador, 'La reversa devuelve el agregador de producción');
assert.match(gate(), /^OK/, 'gate verde tras la reversa (sigue con el roster simulado)');
// Y sobre el gate de producción exacto: deshacer las simulaciones y comprobar la identidad byte a byte.
simular(GATE, PROD.equipoVisible, PROD.equipoVisibleSellado);
simular(PULSO, '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado', CENSO_LINEA);
assert.equal(md5Vivo(GATE), PROD.gate, 'La reversa + deshacer la simulación devuelven el gate EXACTO de producción');
assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), PROD.citas, 'La reversa devuelve el gate de citas EXACTO de producción');
assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), PROD.pulso, 'La reversa devuelve el gate del pulso EXACTO de producción');
sql(migracion);
assert.equal(md5Vivo(AYUDANTE), md5.ayudante, 'La reinstalación es determinista (ayudante)');
assert.equal(md5Vivo(LECTOR), md5.lector, 'La reinstalación es determinista (lector)');
assert.equal(md5Vivo(AGREGADOR), md5.agregador, 'La reinstalación es determinista (agregador)');
assert.equal(md5Vivo(GATE), md5.gate, 'La reinstalación es determinista (gate)');
assert.equal(md5Vivo('private.assert_gestion_diaria_citas()'), md5.citas, 'La reinstalación es determinista (citas)');
assert.equal(md5Vivo('private.assert_gestion_diaria_pulso()'), md5.pulso, 'La reinstalación es determinista (pulso)');
simular(GATE, PROD.equipoVisibleSellado, PROD.equipoVisible);
assert.match(gate(), /^OK/, 'gate verde reinstalado (roster simulado)');
simular(PULSO, CENSO_LINEA, '  perform 1; -- SIMULACION BANCO: censo analitico ajeno neutralizado');
assert.match(sql(`select ${PULSO}`), /^OK/, 'pulso verde reinstalado (simulaciones del banco)');

const verificacion = {
  version: VERSION, nombre: NOMBRE, banco: `${contenedor}/${db}`, ensayado_en: new Date().toISOString(),
  md5_ayudante: md5.ayudante, md5_lector: md5.lector, md5_agregador: md5.agregador, md5_gate: md5.gate, md5_gate_citas: md5.citas, md5_gate_pulso: md5.pulso,
  md5_gate_produccion_antes: PROD.gate,
  sha256_migracion: createHash('sha256').update(migracion).digest('hex'),
  sha256_reversa: createHash('sha256').update(reversa).digest('hex'),
  gate_antes: gateAntes, mutantes_nuevos: mutantesNuevos, mutantes_viejos: mutantesViejos,
  paraguas_con_211001_simulado: paraguas.status === 0 ? paraguas.stdout.trim() : 'ROJO',
  oraculo: 'GESTION_DIARIA_LLAMADAS_CLIENTES_OK', censo_intacto: true, reversa_a_produccion: true,
  solo_lectura: { instalada_ms: tiemposInstalada, produccion_ms: tiemposProduccion, banco_sin_datos: true },
};
writeFileSync(new URL('./verificacion.json', import.meta.url), JSON.stringify(verificacion, null, 2) + '\n');
console.log(`ENSAYO OK · ${mutantesNuevos} · viejos: ${mutantesViejos} · ayudante ${md5.ayudante} · lector ${md5.lector} · agregador ${md5.agregador} · gate ${md5.gate}`);
