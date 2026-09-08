import { expect, test } from '@playwright/test'
import { irAMiCartera, loginReal, montarBackendReal, UID } from './_helpers'

for (const ancho of [1280, 390]) {
  test(`motivo editable y contrato bloqueado hasta la respuesta de Gerencia (${ancho}px)`, async ({ page }, testInfo) => {
    await page.clock.install()
    await page.setViewportSize({ width: 1280, height: 900 })
    const backend = await montarBackendReal(page, { rolCrm: 'vendedor', contratos: [] })
    let solicitud: Record<string, unknown> | null = null
    let envios = 0
    await page.route('**/rest/v1/rpc/resolver_tasa_fn', async (ruta) => {
      const datos = ruta.request().postDataJSON()
      await ruta.fulfill({ json: {
        cliente_id: datos.p_cliente_id, categoria: 'nuevo', tasa_base: 15, regla: 'primera_inversion',
        contrato_origen: null, contratos_previos: 0, contratos_activos: 0, prioridad_bandeja: false,
        politica: { id: 'politica-1', version: 6, modo: 'enforcement', tasa_base_nueva: 15, tope_tecnico: 50, vigencia_solicitud_dias: 7 },
      } })
    })
    await page.route('**/rest/v1/rpc/solicitudes_tasa_fn', (ruta) => ruta.fulfill({ json: solicitud ? [solicitud] : [] }))
    await page.route('**/rest/v1/rpc/solicitar_tasa_fn', async (ruta) => {
      envios++
      const { p_solicitud: datos } = ruta.request().postDataJSON()
      solicitud = {
        ...datos, id: 'solicitud-1', estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true,
        contrato_origen_numero: null, tasa_base: 15, regla_base: 'primera_inversion', tasa_maxima_autorizada: null,
        motivo_resolucion: null, solicitada_por: UID, solicitada_en: new Date().toISOString(),
        vence_en: new Date(Date.now() + 7 * 86400000).toISOString(), resuelta_por: null, resuelta_en: null,
        contrato_id: null, es_mia: true,
      }
      // La RPC de escritura devuelve la fila, sin las proyecciones de la lectura.
      // El parser real del API debe derivar vigente/estado_efectivo y conservar el bloqueo.
      await ruta.fulfill({ json: Object.fromEntries(Object.entries(solicitud).filter(([campo]) => !['es_mia', 'vigente', 'estado_efectivo'].includes(campo))) })
    })
    await loginReal(page)
    await irAMiCartera(page)
    const abrir = async () => {
      await page.getByRole('row', { name: /CLIENTE PORTAL UNO/ }).getByRole('button', { name: /Registrar (primera|nueva) inversión/ }).click()
      return page.getByRole('dialog', { name: /Crear contrato de CLIENTE PORTAL UNO/ })
    }
    let formulario = await abrir()
    await page.setViewportSize({ width: ancho, height: 900 })
    await formulario.getByLabel('Categoría', { exact: true }).selectOption('nuevo')
    await formulario.getByLabel('Capital', { exact: true }).fill('30000')
    await formulario.getByLabel('N° de contrato', { exact: true }).fill('000777')
    await formulario.getByRole('radio', { name: /BCP.*8901/i }).check()
    const crear = () => formulario.getByRole('button', { name: 'Crear contrato', exact: true })
    await expect(crear()).toBeEnabled()
    await formulario.getByRole('button', { name: 'Solicitar tasa superior' }).click()
    await expect(crear()).toBeDisabled()
    await formulario.getByLabel('Tasa solicitada (%)').fill('17')
    const motivo = formulario.getByLabel('Motivo comercial', { exact: true })
    await motivo.click()
    await motivo.pressSequentially('Cliente referido con nueva inversion')
    await motivo.press('Enter')
    await motivo.pressSequentially('Solicita mejorar su rentabilidad')
    await expect(motivo).toHaveValue('Cliente referido con nueva inversion\nSolicita mejorar su rentabilidad')
    await expect(motivo).toBeFocused()
    expect((await motivo.boundingBox())!.width).toBeGreaterThan(180)
    await page.screenshot({ path: testInfo.outputPath(`motivo-${ancho}.png`) })
    await formulario.getByRole('button', { name: 'Enviar a Gerencia' }).click()
    await expect.poll(() => envios).toBe(1)
    await expect(formulario.getByTestId('tasa-politica').getByRole('status')).toContainText('pendiente de Gerencia')
    await expect(crear()).toBeDisabled()
    // La pantalla recargada y otra intención no permiten eludir la espera.
    await formulario.getByRole('button', { name: 'Omitir por ahora' }).click()
    await page.setViewportSize({ width: 1280, height: 900 })
    formulario = await abrir()
    await page.setViewportSize({ width: ancho, height: 900 })
    await formulario.getByLabel('Categoría', { exact: true }).selectOption('nuevo')
    await formulario.getByLabel('Capital', { exact: true }).fill('40000')
    await formulario.getByLabel('N° de contrato', { exact: true }).fill('000778')
    await formulario.getByRole('radio', { name: /BCP.*8901/i }).check()
    await expect(crear()).toBeDisabled()
    await formulario.getByLabel('N° de contrato', { exact: true }).press('Enter')
    expect(backend.llamadas.rpcCrearContrato).toBe(0)
    solicitud = { ...solicitud, estado: 'rechazada', estado_efectivo: 'rechazada', vigente: false, resuelta_por: 'gerencia', resuelta_en: new Date().toISOString() }
    await page.clock.fastForward(31_000)
    await expect(crear()).toBeEnabled()
    await expect(formulario.getByLabel('Tasa anual (%)')).toHaveValue('15')
  })
}
