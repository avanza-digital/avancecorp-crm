import type { Page } from '@playwright/test'
import { diaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
import { UID } from './_helpers'

/** Lecturas explícitas de aterrizaje de Hoy para specs que ejercitan otro flujo.
 * No cambia el backend compartido ni su red fail-closed. Cada spec puede
 * sobrescribirlas con una jornada o ventas concretas después de montarlas. */
export async function montarLecturasHoySupervisor(page: Page) {
  await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', async route => {
    const pedido = route.request().postDataJSON() as { p_dia: string; p_supervisor_id?: string }
    const corte = `${pedido.p_dia}T15:00:00.000Z`
    await route.fulfill({ json: { ...diaEquipoPrueba([]), dia: pedido.p_dia,
      supervisor_id: pedido.p_supervisor_id ?? UID, generado_en: corte, pendientes_al: corte } })
  })
  await page.route('**/rest/v1/rpc/facturacion_diaria_v2_fn', route => route.fulfill({
    json: { version: 2, valoracion_activa: false, filas: [] },
  }))
  await page.route('**/rest/v1/rpc/citas_gerencia_consulta_v2_fn', async route => {
    const pedido = route.request().postDataJSON() as { p_desde: string; p_hasta: string }
    await route.fulfill({ json: { version: 1, periodo: { desde: pedido.p_desde, hasta: pedido.p_hasta },
      generado_en: new Date().toISOString(), disponibilidad_depositos: 'sin_registro', depositos: [], citas_clientes: 0, citas: [] } })
  })
}
