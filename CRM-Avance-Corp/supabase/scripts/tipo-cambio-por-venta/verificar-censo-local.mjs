import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { nombres, cuerpoMigracion } from './migraciones-locales.mjs'

// Configuración analítica exportada sin usuarios ni datos financieros. Nunca se
// conecta a producción: crea y elimina exclusivamente su clon local con PID.
const archivo = process.argv[2]
assert.ok(archivo, 'Indicar el JSON de configuración analítica nativa')
const cfg = JSON.parse(readFileSync(archivo, 'utf8'))
const db = `tc_venta_censo_${process.pid}`
const ultima = '20261017040525_crm_capital_conservar_censo_analitico.sql'
assert.equal(nombres.at(-1), ultima)
const literal = (s) => "'" + s.replaceAll("'", "''") + "'"
function ejecutar(sql, base = db, errorEsperado) {
  assert.ok([db, 'postgres'].includes(base))
  const r = spawnSync('docker', ['exec', '-i', 'avancecorp-tc-20261016', 'psql',
    '-XqAt', '-U', 'supabase_admin', '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { input: sql, encoding: 'utf8', timeout: 120_000, maxBuffer: 5e6 })
  if (r.error) throw r.error
  if (errorEsperado) {
    assert.notEqual(r.status, 0)
    assert.match(r.stderr, errorEsperado)
  } else assert.equal(r.status, 0, r.stderr)
  return r.stdout.trim()
}
function estado() {
  return JSON.parse(ejecutar(`select jsonb_build_object(
    'exenciones',(select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e),
    'tope',(select jsonb_agg(to_jsonb(t)) from private.analitica_leads_citas_tope t),
    'sello',(select jsonb_agg(to_jsonb(s)) from private.analitica_lc_sello s),
    'censo',(select jsonb_agg(to_jsonb(c) order by objeto) from private.contadores_crudos_leads_citas() c));`))
}
let creado = false
try {
  ejecutar(`create database ${db} template tc_venta;`, 'postgres'); creado = true
  ejecutar(readFileSync(new URL('reversa-persistencia.sql', import.meta.url), 'utf8'))
  for (const [key, tabla] of [
    ['analitica_exenciones', 'analitica_leads_citas_exenciones'],
    ['analitica_tope', 'analitica_leads_citas_tope'],
    ['analitica_sello', 'analitica_lc_sello'],
  ]) {
    assert.ok(Array.isArray(cfg[key]) && cfg[key].length > 0)
    ejecutar(`begin; set local session_replication_role=replica;
      insert into private.${tabla} select * from jsonb_populate_recordset(null::private.${tabla},
      ${literal(JSON.stringify(cfg[key]))}::jsonb); commit;`)
  }
  const nativo = estado()
  ejecutar(readFileSync(new URL('../../migrations/20261016190725_crm_tipo_cambio_por_venta.sql', import.meta.url), 'utf8')
    + '\nbegin;\n' + nombres.slice(0, -1).map(cuerpoMigracion).join('\n') + '\ncommit;')
  const previo = estado()
  ejecutar(`begin; update private.analitica_lc_sello set sello='alterado' where id;
    ${cuerpoMigracion(ultima)}`, db, /sello desactualizado/)
  assert.deepEqual(estado(), previo, 'el rechazo por sello revierte todo')
  ejecutar(`begin; update private.analitica_leads_citas_exenciones set huella='alterada'
    where objeto='crm.cerrar_periodo(date)';
    update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc() where id;
    ${cuerpoMigracion(ultima)}`, db, /Cambió la declaración del cierre/)
  assert.deepEqual(estado(), previo, 'el rechazo de una declaración desconocida revierte todo')
  ejecutar(`begin; ${cuerpoMigracion(ultima)} commit;`)
  const despues = estado()
  assert.deepEqual(despues.tope, nativo.tope)
  assert.equal(despues.exenciones.length, nativo.exenciones.length + 2)
  for (const e of nativo.exenciones) {
    const actual = despues.exenciones.find((a) => a.objeto === e.objeto)
    if (e.objeto === 'crm.cerrar_periodo(date)') {
      assert.notEqual(actual.huella, e.huella)
      assert.deepEqual({ ...actual, huella: e.huella }, e)
    } else assert.deepEqual(actual, e, e.objeto)
  }
  for (const objeto of ['crm.cerrar_periodo(date)',
    'private.produccion_operaciones(timestamp with time zone,timestamp with time zone,uuid)',
    'private.citas_gerencia_consulta_corte(date,date,uuid)']) {
    const fila = despues.censo.find((e) => e.objeto === objeto)
    assert.equal(fila?.declarada, true, objeto)
    assert.equal(fila.huella_ok, true, objeto)
  }
  for (const antes of nativo.censo) {
    const actual = despues.censo.find((e) => e.objeto === antes.objeto)
    if (actual && antes.objeto !== 'crm.cerrar_periodo(date)') {
      assert.equal(actual.declarada, antes.declarada, antes.objeto)
      assert.equal(actual.huella_ok, antes.huella_ok, antes.objeto)
    }
  }
  const pendientes = (censo) => censo.filter((e) => !e.declarada).length
  assert.equal(pendientes(despues.censo), pendientes(nativo.censo), 'no aumenta deuda no declarada')
  ejecutar(`begin; ${cuerpoMigracion(ultima)}`, db, /Cambió la declaración del cierre/)
  assert.deepEqual(estado(), despues, 'rechaza la aplicación duplicada sin alterar la certificación')
  console.log(`PASS: censo vigente; ${nativo.exenciones.length} declaraciones conservadas, dos incorporadas; tope y deuda ajenos intactos; tres rechazos con rollback`)
} finally {
  if (creado) ejecutar(`drop database ${db} with(force);`, 'postgres')
}
