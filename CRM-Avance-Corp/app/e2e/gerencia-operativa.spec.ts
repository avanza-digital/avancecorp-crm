// E2E mínimo de la ampliación 2026-08-07. A diferencia de acciones-real.spec,
// este caso no depende del gate general de la fuerza de ventas: Gerencia ya
// tiene aprobadas las vistas de leads y debe poder operar un lead ajeno.
import { expect, test } from '@playwright/test'
import { abrirLead, irAPipeline, leadReal, loginReal, montarBackendReal } from './_helpers'
import type { Page } from '@playwright/test'

/** La tabla de LEADS. Ojo: su botón de nav se llama «Leads»; «Cartera» es la
 *  pantalla de clientes y contratos, que es otra cosa. Un lead CONVERTIDO solo
 *  se alcanza por aquí: en el Pipeline los terminales son un contador, no
 *  tarjetas que se puedan abrir. */
async function abrirFichaDesdeLeads(page: Page, nombre: RegExp) {
  // `exact`: sin él también casa «Repartir leads», que es otra pantalla.
  await page.getByRole('button', { name: 'Leads', exact: true }).click()
  await page.getByRole('row', { name: new RegExp(`Abrir ficha de ${nombre.source}`, 'i') }).click()
  const drawer = page.getByRole('dialog', { name: nombre })
  await expect(drawer).toBeVisible()
  return drawer
}

test('Gerencia abre un lead asignado a otro analista y puede iniciar su conversión', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1' })],
  })
  await loginReal(page)
  await irAPipeline(page)
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)

  await drawer.getByRole('button', { name: /Convertir a cliente/i }).click()
  // Desde los cierres en cooperativas el flujo arranca preguntando DÓNDE cerró:
  // Avance sigue su camino de siempre (portal + correo); Qorilazo/Prodelco solo
  // registran el cierre. Gerencia debe poder recorrer el camino de Avance.
  // Nombre accesible = el DialogTitle (manda sobre el ariaLabel del componente).
  const destino = page.getByRole('dialog', { name: '¿Dónde invirtió?' })
  await expect(destino).toBeVisible()
  await destino.getByRole('button', { name: /Avance Corp/i }).click()
  await expect(page.getByRole('dialog', { name: 'Convertir a cliente' })).toBeVisible()
})

test('los tiles F1 del tablero sirven los números del RPC resumen_cartera_fn', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1', monto_estimado: 10000, moneda: 'PEN' })],
  })
  await loginReal(page)
  await irAPipeline(page)

  const chips = page.locator('[data-slot="card"]')
  await expect(chips.filter({ hasText: 'Leads activos' }).first()).toContainText('1')
  await expect(chips.filter({ hasText: 'Capital en proceso' }).first()).toContainText('S/ 10,000')
})

test('RPC de resumen caída: el tablero degrada a «—» con aviso y sigue operable', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    fallarResumenCartera: true,
    leads: [leadReal({ vendedor_id: 'vend-1' })],
  })
  await loginReal(page)
  await irAPipeline(page)

  // Degradación honesta: aviso visible + «—» en los chips, sin inventar cifras.
  await expect(page.getByText(/No se pudieron cargar los indicadores del tablero/)).toBeVisible()
  await expect(
    page.locator('[data-slot="card"]').filter({ hasText: 'Leads activos' }).first(),
  ).toContainText('—')

  // …y el tablero sigue operable: la card del lead abre su ficha igual.
  const drawer = await abrirLead(page, /CLIENTE REAL UNO/)
  await expect(drawer).toBeVisible()
})

test('Equipo (gerencia real): comparativa y chips cargan desde metricas_vendedores_fn', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1', monto_estimado: 12000, moneda: 'PEN' })],
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Equipo' }).click()

  // El payload parsea y la pantalla pinta: chips con números (no «—») y la
  // tabla en su estado honesto (el ROSTER del mock no tiene supervisores).
  await expect(page.getByText('Comparativa de equipos')).toBeVisible()
  await expect(page.getByText(/Aún no hay supervisores activos/)).toBeVisible()
  const chipEquipos = page.locator('[data-slot="card"]').filter({ hasText: 'Equipos' }).first()
  await expect(chipEquipos).toContainText('0')
  await expect(chipEquipos).not.toContainText('—')
})

test('métricas de equipo caídas: Equipo degrada a «—» con aviso y reintento', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    fallarMetricasEquipo: true,
    leads: [leadReal({ vendedor_id: 'vend-1' })],
  })
  await loginReal(page)
  await page.getByRole('button', { name: 'Equipo' }).click()

  await expect(page.getByText(/No se pudieron cargar las métricas por equipo/)).toBeVisible()
  await expect(page.getByText('La comparativa no está disponible en este momento.')).toBeVisible()
  await expect(
    page.locator('[data-slot="card"]').filter({ hasText: 'Equipos' }).first(),
  ).toContainText('—')
})

// La Fase 2 de la anulación de cierres de Avance: gerencia le quita el mérito a
// un cierre mal registrado y la marca queda a la vista. Lo que este caso vigila
// es que la marca venga de la RELECTURA del servidor y no de un optimismo del
// front — si el servidor no guardara, la pantalla no debe decir que sí.
test('Gerencia anula el cierre de un lead convertido y la marca queda a la vista', async ({ page }) => {
  const backend = await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1', etapa: 'convertido' })],
  })
  await loginReal(page)
  const drawer = await abrirFichaDesdeLeads(page, /CLIENTE REAL UNO/)

  // «Anular el cierre», no «Anular»: esta ficha ya tiene botones «Anular» que
  // quitan una TAREA, y el rótulo es lo único que los distingue.
  await drawer.getByRole('button', { name: /Anular el cierre de/i }).click()
  const dialogo = page.getByRole('dialog', { name: /Anular el cierre de/i })
  await expect(dialogo).toBeVisible()

  // Sin motivo no se envía nada: quitar mérito sin razón escrita es justo lo que
  // el servidor no permite, y el front no debe llegar a intentarlo.
  await dialogo.getByRole('button', { name: 'Anular cierre' }).click()
  expect(backend.anulacionesAvance).toHaveLength(0)
  await expect(dialogo.getByRole('alert')).toContainText(/motivo/i)

  await dialogo.getByLabel(/Motivo de la anulación/i).fill('Mala práctica del asesor')
  await dialogo.getByRole('button', { name: 'Anular cierre' }).click()

  await expect.poll(() => backend.anulacionesAvance).toEqual([
    { lead_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', motivo: 'Mala práctica del asesor' },
  ])
  await expect(drawer.getByText('CIERRE ANULADO')).toBeVisible()
  await expect(drawer.getByText('Mala práctica del asesor')).toBeVisible()
})

// El caso que apaga el botón, y el único lead convertido que hay HOY en
// producción: un cierre en cooperativa se anula con su propia acción, que guarda
// la foto del depósito. La RPC de Avance lo rechaza, así que el botón no puede
// llegar a ofrecerse.
test('un cierre en cooperativa NO ofrece el botón de anular de Avance', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'directorio',
    leads: [leadReal({ vendedor_id: 'vend-1', etapa: 'convertido' })],
    cierresEstado: [{
      lead_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      canal: 'cooperativa',
      anulado_en: null,
      motivo: null,
    }],
  })
  await loginReal(page)
  const drawer = await abrirFichaDesdeLeads(page, /CLIENTE REAL UNO/)
  await expect(drawer.getByText(/Convertido a cliente/i)).toBeVisible()
  await expect(drawer.getByRole('button', { name: /Anular el cierre de/i })).toHaveCount(0)
})
