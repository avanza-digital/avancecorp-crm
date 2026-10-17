import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'

export const nombres = [
  '20261016201516_crm_capital_operaciones_compartidas.sql',
  '20261016204221_crm_capital_cortes_lecturas.sql',
  '20261016204946_crm_capital_sello_y_activacion.sql',
  '20261016220524_crm_facturacion_detalle_cortes.sql',
  '20261016223745_crm_capital_valoracion_en_escritores.sql',
  '20261016230914_crm_capital_reevaluar_cierre.sql',
  '20261016233037_crm_citas_capital_corte.sql',
  '20261017025829_crm_capital_indices_relaciones.sql',
  '20261017033241_crm_capital_cierre_sin_reconciliacion_bajo_bloqueo.sql',
  '20261017040525_crm_capital_conservar_censo_analitico.sql',
]
export function cuerpoMigracion(nombre) {
  assert.ok(nombres.includes(nombre))
  const sql = readFileSync(new URL(`../../migrations/${nombre}`, import.meta.url), 'utf8')
  assert.equal(sql.split('\nbegin;').length, 2)
  assert.ok(sql.trimEnd().endsWith('commit;'))
  const cuerpo = sql.replace('\nbegin;', '').replace(/commit;\s*$/, '')
  assert.ok(!/^\s*(?:begin|commit|rollback);/m.test(cuerpo))
  return cuerpo
}
