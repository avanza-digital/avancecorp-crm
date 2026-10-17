import { readFileSync, writeFileSync } from 'node:fs'
import assert from 'node:assert/strict'

// Produce exclusivamente un banco local con identidades personales ficticias.
// Los ids de fuente y hechos monetarios permiten cotejar cada valoración.
const [entrada, simulacion, salida] = process.argv.slice(2)
assert.ok(entrada && simulacion && salida, 'Uso: preparar-historico.mjs inventario.json simulacion.json salida.sql')
const raw = JSON.parse(readFileSync(entrada, 'utf8'))
const inv = raw.rows?.find((r) => r.inventario)?.inventario ?? raw.inventario ?? raw
const sim = JSON.parse(readFileSync(simulacion, 'utf8'))
assert.equal(inv.proyecto, 'dctqcbznekcyxhjujuci')
assert.equal(inv.periodo, '2026-10-01')
assert.equal(sim.inventario_capturado_en, inv.capturado_en)
assert.equal(sim.pendientes.length, 0, 'La simulación tiene fechas pendientes')
const q = (x) => x == null ? 'null' : "'" + String(x).replaceAll("'", "''") + "'"
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const cliente = 'e0000000-0000-4000-8000-000000000099'
const producto = 'e0000000-0000-4000-8000-000000000098'
const sinAnalista = 'e0000000-0000-4000-8000-000000000097'
const sql = [
  '-- Hechos de octubre; contactos, documentos e identidades de cliente ficticios.',
  'begin;',
  "do $$ begin if current_database()<>'tc_venta_historico' then raise exception 'Solo banco histórico exclusivo'; end if;",
  "if exists(select 1 from public.contratos) or exists(select 1 from crm.cierres_externos) then raise exception 'El banco debe estar vacío'; end if; end $$;",
  'set local session_replication_role=replica;',
]
for (const [i, h] of inv.operaciones.entries()) {
  assert.match(h.fuente_id, uuid)
  assert.ok(['contrato', 'cierre_externo'].includes(h.fuente))
  assert.ok(['PEN', 'USD'].includes(h.moneda))
  assert.match(h.fecha_comercial, /^2026-10-\d{2}$/)
  assert.match(h.fecha_imputacion, /^2026-10-\d{2}$/)
  assert.ok(Number.isFinite(Number(h.monto)) && Number(h.monto) >= 0)
  const fecha = q(h.fecha_comercial), actor = q(h.analista_id ?? sinAnalista)
  if (h.fuente === 'contrato') {
    sql.push(`insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id)
values(${q(h.fuente_id)},${q(`TC-HISTORICO-${i}`)},${q(cliente)},${q(h.monto)},${q(h.moneda)},'mensual',${fecha}::date,${fecha}::date+365,${q(h.categoria)},${q(producto)},${fecha},${actor});`)
  } else {
    sql.push(`insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en,fecha_comercial,fecha_imputacion)
values(${q(h.fuente_id)},${q(h.fuente_id)},'qorilazo',${q(h.monto)},${q(h.moneda)},'DNI','00000000','Persona sintética',${q(`TC-HISTORICO-${i}`)},${actor},${actor},(${q(h.fecha_imputacion)}::date::timestamp at time zone 'America/Lima'),${fecha},${q(h.fecha_imputacion)});`)
  }
}
sql.push('set local session_replication_role=origin;')
for (const evidencia of sim.evidencias) {
  sql.push(`select private.consolidar_tc_venta(${q(JSON.stringify(evidencia))}::jsonb);`)
}
sql.push('select private.materializar_capital_valoraciones(500);')
sql.push(`do $$ begin if (select count(*) from crm.capital_valoraciones)<>${inv.operaciones.length} then raise exception 'Cobertura histórica incompleta'; end if; end $$;`)
sql.push(`select jsonb_build_object('operaciones',count(*),'usd',count(*) filter(where moneda='USD'),
  'monto_pen',sum(monto) filter(where moneda='PEN'),'monto_usd',sum(monto) filter(where moneda='USD'),
  'equivalente_pen',sum(equivalente_pen),'tasas',(select count(*) from crm.tipo_cambio_diario),
  'nuevas_valoraciones_al_repetir',private.materializar_capital_valoraciones(500)->'creadas') as resultado
  from crm.capital_valoraciones;`)
sql.push('commit;')
writeFileSync(salida, sql.join('\n'), { mode: 0o600 })
console.log(`Banco histórico preparado: ${inv.operaciones.length} hechos y ${sim.evidencias.length} fechas; sin contactos ni documentos reales.`)
