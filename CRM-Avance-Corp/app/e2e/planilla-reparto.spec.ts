import { expect, test, type Page } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
const sumar = (fecha: string, dias: number) => new Date(Date.parse(`${fecha}T12:00:00Z`) + dias * 86400000).toISOString().slice(0, 10)
const ayer = sumar(hoy, -1)
const antes = sumar(hoy, -2)
type Evento = { fecha: string; origen: string; supervisor: string; cantidad: number }

async function preparar(page: Page) {
  const eventos: Evento[] = [{ fecha: ayer, origen: 'formulario_3', supervisor: 'Ana', cantidad: 8 }, { fecha: antes, origen: 'landing', supervisor: 'Beto', cantidad: 3 }]
  const backend = await montarBackendReal(page, {
    rolCrm: 'coordinador', rolPortal: 'comercial',
    supervisoresReparto: ['Ana', 'Beto', 'Carla'].map((nombre) => ({ perfil_id: nombre, nombre, activo: true, bandeja_pendiente: 0 })),
    colaReparto: [
      { id: 'antiguo', nombre_completo: 'LEAD ANTERIOR', origen: 'formulario_3', creado_en: `${ayer}T12:00:00Z`, moneda: 'PEN', monto_estimado: 5000, distrito: null, categoria_interes: null },
      { id: 'nuevo', nombre_completo: 'LEAD NUEVO', origen: 'formulario_3', creado_en: `${hoy}T12:00:00Z`, moneda: 'PEN', monto_estimado: 5000, distrito: null, categoria_interes: null },
      { id: 'landing', nombre_completo: 'LEAD LANDING', origen: 'landing', creado_en: `${hoy}T12:00:00Z`, moneda: 'PEN', monto_estimado: 5000, distrito: null, categoria_interes: null },
    ],
  })
  let llamadas = 0
  let fallarEn = 0
  let libre = true
  let pausa: Promise<void> | null = null
  // Este banco responde al período real solicitado y registra cada entrega
  // exitosa. No reutiliza el fixture estático de la agenda histórica.
  await page.route('**/rest/v1/rpc/agenda_reparto_diaria', async (ruta) => {
    const { p_desde = hoy, p_dias = 7 } = ruta.request().postDataJSON()
    const dias = Array.from({ length: p_dias }, (_, i) => {
      const fecha = sumar(p_desde, i)
      const presentes = eventos.filter((e) => e.fecha === fecha)
      const origenes = [...new Set(presentes.map((e) => e.origen))].map((origen) => {
        const grupo = presentes.filter((e) => e.origen === origen)
        const turno = origen === 'formulario_3' ? 'formulario' : origen
        const entregas = [...new Set(grupo.map((e) => e.supervisor))].map((supervisor) => ({ supervisor_id: supervisor, supervisor_nombre: supervisor, supervisor_alias: null, derivados: grupo.filter((e) => e.supervisor === supervisor).reduce((n, e) => n + e.cantidad, 0), coincide_turno: true }))
        return { origen, turno, derivados: entregas.reduce((n, e) => n + e.derivados, 0), fuera_turno: 0, entregas }
      })
      const asignaciones = ['landing', 'formulario'].map((origen) => {
        const grupos = origenes.filter((g) => g.turno === origen)
        const entregas = grupos.flatMap((g) => g.entregas)
        return { origen, supervisor_id: null, supervisor_nombre: null, supervisor_alias: null, derivados: grupos.reduce((n, g) => n + g.derivados, 0), fuera_turno: 0, entregas, origenes: grupos }
      })
      return { fecha, asignaciones, origenes }
    })
    await ruta.fulfill({ json: { version: 1, fecha_desde: p_desde, reparto_libre: libre, destinos: [], dias } })
  })
  await page.route('**/rest/v1/rpc/repartir_lead', async (ruta) => {
    llamadas++
    if (pausa) await pausa
    const { p_lead, p_supervisor } = ruta.request().postDataJSON()
    if (!libre || llamadas === fallarEn) { await ruta.fulfill({ status: 400, json: { code: 'P0002', message: 'El lead ya salió de la cola' } }); return }
    const lead = backend.colaReparto.find((l) => l.id === p_lead)
    if (!lead) { await ruta.fulfill({ status: 400, json: { code: 'P0002', message: 'Fuera de cola' } }); return }
    eventos.push({ fecha: hoy, origen: String(lead.origen), supervisor: p_supervisor, cantidad: 1 })
    backend.colaReparto = backend.colaReparto.filter((l) => l.id !== p_lead)
    await ruta.fulfill({ json: { lead_id: p_lead, asignado_supervisor_id: p_supervisor } })
  })
  await loginReal(page)
  await expect(page.getByRole('table', { name: 'Planilla de reparto' })).toBeVisible()
  return { backend, eventos, llamadas: () => llamadas, fallar: (n: number) => { fallarEn = n }, revocar: () => { libre = false }, retener: () => { let resolver!: () => void; pausa = new Promise<void>((r) => { resolver = r }); return () => { resolver(); pausa = null } } }
}

for (const ancho of [390, 1366]) test(`planilla con tres supervisores, calendarios separados y reparto confirmado (${ancho}px)`, async ({ page }, info) => {
  await page.setViewportSize({ width: 1366, height: 950 })
  const banco = await preparar(page)
  await page.setViewportSize({ width: ancho, height: 950 })
  if (ancho < 600) await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  await page.getByLabel('Fecha de reparto: período').selectOption('dia')
  await page.getByLabel('Fecha de reparto: inicio').fill(ayer)
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período8')
  await page.getByLabel('Fecha de ingreso al CRM: período').selectOption('dia')
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Pendientes disponibles2')
  await page.getByLabel('Enviar Formulario 3 a Carla').fill('1')
  await expect(page.getByRole('columnheader', { name: 'Histórico consultado' })).toBeVisible()
  await page.getByRole('button', { name: 'Revisar reparto' }).click()
  await expect(page.getByRole('dialog')).toContainText('LEAD NUEVO')
  await expect(page.getByRole('dialog')).not.toContainText('LEAD ANTERIOR')
  expect(banco.llamadas()).toBe(0)
  await page.getByRole('button', { name: 'Confirmar reparto' }).click()
  await expect(page.getByText('1 entregas confirmadas · 0 sin intentar', { exact: true })).toBeVisible()
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período8')
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Pendientes disponibles1')
  await page.getByLabel('Fecha de reparto: inicio').fill(hoy)
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período1')
  expect(banco.eventos.at(-1)).toMatchObject({ supervisor: 'Carla', origen: 'formulario_3', fecha: hoy })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.screenshot({ path: info.outputPath(`planilla-${ancho}.png`), fullPage: true })
  await page.getByRole('table', { name: 'Planilla de reparto' }).scrollIntoViewIfNeeded()
  await page.screenshot({ path: info.outputPath(`planilla-tabla-${ancho}.png`), fullPage: true })
})

test('días sueltos combinados, filtros y confirmación parcial sin reintento automático', async ({ page }) => {
  const banco = await preparar(page)
  await page.getByLabel('Fecha de reparto: período').selectOption('dias')
  await page.getByLabel('Fecha de reparto: añadir día').fill(antes)
  await page.getByRole('button', { name: 'Añadir día' }).click()
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período3')
  await page.getByLabel('Vista de entregas').selectOption('dias')
  const desglose = page.getByRole('table', { name: 'Entregas por día' })
  await expect(desglose).toContainText(antes)
  await expect(desglose).not.toContainText(ayer)
  await page.getByLabel('Enviar Formulario 3 a Ana').fill('2')
  banco.fallar(2)
  await page.getByRole('button', { name: 'Revisar reparto' }).click()
  await page.getByRole('button', { name: 'Confirmar reparto' }).click()
  await expect(page.getByText('1 entregas confirmadas · 0 sin intentar · 1 rechazada', { exact: true })).toBeVisible()
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período4')
  expect(banco.llamadas()).toBe(2)
  expect(banco.backend.colaReparto).toHaveLength(2)
  await page.getByText('Todos los orígenes', { exact: true }).first().click()
  await page.getByRole('checkbox', { name: 'Formulario 3' }).check()
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período1')
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Pendientes disponibles1')
  await page.getByLabel('Enviar Formulario 3 a Ana').fill('1')
  banco.revocar()
  await page.getByRole('button', { name: 'Revisar reparto' }).click()
  await expect(page.getByRole('alert')).toContainText('no está habilitado')
  expect(banco.llamadas()).toBe(2)
})

test('repartir desde la cola bloquea el cruce y actualiza la planilla conservando filtros', async ({ page }) => {
  const banco = await preparar(page)
  await page.getByLabel('Fecha de reparto: período').selectOption('dia')
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período0')
  await page.getByText('Todos los orígenes', { exact: true }).first().click()
  await page.getByRole('checkbox', { name: 'Formulario 3' }).check()
  await page.getByRole('tab', { name: 'Cola de nuevos' }).click()
  await page.getByLabel('Asignar LEAD ANTERIOR a un supervisor').selectOption('Ana')
  const liberar = banco.retener()
  await page.getByRole('button', { name: 'Repartir a LEAD ANTERIOR', exact: true }).click()
  await expect(page.getByRole('tab', { name: 'Coordinación → supervisores' })).toBeDisabled()
  liberar()
  await expect(page.getByRole('tab', { name: 'Coordinación → supervisores' })).toBeEnabled()
  await page.getByRole('tab', { name: 'Coordinación → supervisores' }).click()
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Entregas en el período1')
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Pendientes disponibles1')
  await expect(page.getByRole('checkbox', { name: 'Formulario 3' })).toBeChecked()
})

test('90 pendientes limitan la escritura entre supervisores y orígenes antes de revisar', async ({ page }) => {
  const banco = await preparar(page)
  banco.backend.colaReparto = Array.from({ length: 90 }, (_, i) => ({ ...banco.backend.colaReparto[0], id: `disponible-${i}`, nombre_completo: `LEAD ${i}`, origen: i < 60 ? 'formulario_3' : 'landing' }))
  await page.getByRole('button', { name: 'Actualizar', exact: true }).click()
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Pendientes disponibles90')
  const ana = page.getByLabel('Enviar Formulario 3 a Ana')
  const beto = page.getByLabel('Enviar Formulario 3 a Beto')
  const carla = page.getByLabel('Enviar Formulario 3 a Carla')
  await ana.fill('40')
  await expect(beto).toHaveAttribute('max', '20')
  await beto.fill('90')
  await expect(beto).toHaveValue('20')
  await beto.press('ArrowUp')
  await expect(beto).toHaveValue('20')
  await carla.fill('1')
  await expect(carla).toHaveValue('0')
  await page.getByLabel('Enviar LANDING a Ana').fill('20')
  await page.getByLabel('Enviar LANDING a Beto').fill('99')
  await expect(page.getByLabel('Enviar LANDING a Beto')).toHaveValue('10')
  await expect(page.getByLabel('Resumen de la planilla')).toContainText('Preparados para hoy90Pendientes después del plan0')
  await ana.fill('10')
  await expect(carla).toHaveAttribute('max', '30')
  await carla.fill('999')
  await expect(carla).toHaveValue('30')
  await expect(ana).toHaveValue('10')
  await expect(beto).toHaveValue('20')
  await page.getByRole('button', { name: 'Revisar reparto' }).click()
  await expect(page.getByRole('dialog')).toContainText('90 leads pendientes.')
  expect(banco.llamadas()).toBe(0)
})
