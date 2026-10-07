import {expect, test, type Page} from '@playwright/test'
import {contratoReal, irAMiCartera, loginReal, montarBackendReal, UID} from './_helpers'
import {carteraF5, fichaF5, inversionF5, PERSONA_F5} from '../src/test/fixtures/f5'

// Navegador real con API sintética; la política real se prueba en el banco SQL.
async function abrirUpgrade(page: Page, modo: 'observacion' | 'enforcement', ancho: number) {
  await page.clock.install()
  const origen = contratoReal({tasa_anual: 18})
  const backend = await montarBackendReal(page, {rolCrm: 'vendedor', contratos: [origen]})
  const estado = {modo, envios: 0, confirmaciones: 0, solicitud: null as Record<string, unknown> | null,
    inversion: null as Record<string, unknown> | null}
  const totales = [{empresa: 'avance', moneda: 'PEN', cantidad: 1, capital_registrado: 10000, capital_activo: 10000}]
  await page.route('**/rest/v1/rpc/*', async ruta => {
    const nombre = new URL(ruta.request().url()).pathname.split('/').at(-1)
    const datos = ruta.request().postDataJSON() ?? {}
    const json = (data: unknown) => ruta.fulfill({json: data})
    if (nombre === 'cartera_inversionistas_estado_fn') return json({version: 1, habilitada: true, escritura_habilitada: true, motivo: null})
    if (nombre === 'cartera_inversionistas_filtrada_fn') return json({...carteraF5, totales,
      filas: [{...carteraF5.filas[0], empresas: ['avance'], resumen: totales}]})
    if (nombre === 'inversionista_ficha_fn') return json({...fichaF5,
      persona: {...fichaF5.persona, perfil_id: origen.cliente_id, responsable_id: UID}, totales,
      inversiones: [{...inversionF5, fuente_id: origen.id, empresa: 'avance', perfil_id: origen.cliente_id,
        numero: origen.numero_contrato, capital: origen.capital, estado: 'activo', vence_en: origen.fecha_vencimiento,
        contrato: {fecha_inicio: origen.fecha_inicio, tasa_anual: 18, modalidad: 'mensual', tipo_interes: 'simple', categoria: 'nuevo'}}]})
    if (nombre === 'resolver_tasa_fn') return json({cliente_id: datos.p_cliente_id, categoria: datos.p_categoria,
      tasa_base: 18, tasa_minima_sin_autorizacion: 18, tasa_minima_upgrade_sin_autorizacion: 0.01, regla: 'heredada_upgrade', observacion_sin_aprobacion: true,
      contrato_origen: {id: datos.p_contrato_origen_id, numero_contrato: origen.numero_contrato, tasa_anual: 18,
        estado: 'activo', moneda: 'PEN', capital: 10000, fecha_vencimiento: origen.fecha_vencimiento},
      contratos_previos: 1, contratos_activos: 1, prioridad_bandeja: false,
      politica: {id: 'politica-upgrade', version: 18, modo: estado.modo, tasa_base_nueva: 15, tope_tecnico: 25, vigencia_solicitud_dias: 7}})
    if (nombre === 'solicitudes_tasa_fn') return json(estado.solicitud ? [estado.solicitud] : [])
    if (nombre === 'solicitar_tasa_fn') {
      estado.envios++
      estado.solicitud = {...datos.p_solicitud, id: 'solicitud-upgrade', estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true,
        contrato_origen_numero: origen.numero_contrato, tasa_base: 18, regla_base: 'heredada_upgrade', tasa_maxima_autorizada: null,
        motivo_resolucion: null, solicitada_por: UID, solicitada_en: new Date().toISOString(),
        vence_en: new Date(Date.now() + 7 * 86400000).toISOString(), resuelta_por: null, resuelta_en: null,
        contrato_id: null, es_mia: true}
      return json(Object.fromEntries(Object.entries(estado.solicitud).filter(([campo]) => !['es_mia', 'vigente', 'estado_efectivo'].includes(campo))))
    }
    if (nombre === 'preparar_inversion_fn') {
      estado.inversion = {solicitud_id: datos.p_clave, estado: 'preparada', inversion_id: null,
        inversionista_id: PERSONA_F5, inversionista_origen_id: PERSONA_F5, identidad_fusionada: false,
        responsable_esperado_id: UID, responsable_actual_id: UID, requiere_revision_responsable: false,
        revision_datos: 0, revision_responsable: 0, hash_datos: 'huella-sintetica', resultado: null,
        necesita_portal: false, comprobante_bucket: null, comprobante_ruta: null, datos: datos.p_datos}
      return json(estado.inversion)
    }
    if (nombre === 'solicitud_inversion_fn') return json(estado.inversion)
    if (nombre === 'confirmar_inversion_revisada_fn') {
      estado.confirmaciones++
      return json({ok: true, solicitud_id: datos.p_solicitud, inversion_id: PERSONA_F5, inversionista_id: PERSONA_F5,
        empresa: 'avance', fuente: {numero_contrato: '2026-01-000777'}})
    }
    return ruta.fallback()
  })
  await loginReal(page)
  await irAMiCartera(page)
  await page.setViewportSize({width: ancho, height: 900})
  if (ancho < 600) await page.getByRole('button', {name: 'Ocultar menú'}).click()
  await page.getByRole('button', {name: 'Abrir ficha de ANA SINTÉTICA F5'}).click()
  await page.getByRole('region', {name: 'Inversiones y contratos'}).getByRole('button', {name: 'Registrar upgrade', exact: true}).click()
  const formulario = page.getByRole('dialog', {name: /Registrar upgrade de ANA SINTÉTICA F5/})
  await expect(formulario.getByLabel('Tasa anual (%)')).toHaveValue('18')
  await expect(formulario.getByTestId('tasa-politica')).toContainText('Tasa de referencia: 18%')
  await formulario.getByLabel('Capital', {exact: true}).fill('10000')
  await formulario.getByLabel('N° de contrato', {exact: true}).fill('000777')
  await formulario.getByRole('radio', {name: /BCP.*8901/i}).check()
  return {estado, formulario, backend, origen}
}

for (const ancho of [1280, 390]) {
  for (const tasa of [16, 22]) test(`upgrade: solicitudes desactivadas, ${tasa}% desde referencia 18% (${ancho}px)`, async ({page}, info) => {
    const {estado, formulario, backend, origen} = await abrirUpgrade(page, 'observacion', ancho)
    await expect(formulario.getByText('Solicitudes desactivadas · tasa libre')).toBeVisible()
    await expect(formulario.getByRole('button', {name: 'Solicitar tasa superior'})).toHaveCount(0)
    await formulario.getByLabel('Tasa anual (%)').fill(String(tasa))
    await page.screenshot({path: info.outputPath('upgrade-libre.png'), fullPage: true})
    await formulario.getByRole('button', {name: 'Revisar inversión', exact: true}).click()
    await expect(page.getByRole('heading', {name: 'Revisar inversión', exact: true})).toBeVisible()
    expect(estado.inversion).toMatchObject({datos: {contrato: {tasa_anual: tasa, categoria: 'upgrade', contrato_origen_id: origen.id}}})
    await page.getByRole('button', {name: 'Confirmar inversión', exact: true}).click()
    await expect(page.getByRole('heading', {name: 'Inversión confirmada'})).toBeVisible()
    expect(estado.confirmaciones).toBe(1)
    expect(estado.envios).toBe(0)
    expect(backend.contratos[0]).toEqual(origen)
  })

  test(`upgrade: menor libre, mayor solicita y espera aprobación (${ancho}px)`, async ({page}, info) => {
    const {estado, formulario, origen} = await abrirUpgrade(page, 'enforcement', ancho)
    const revisar = formulario.getByRole('button', {name: 'Revisar inversión', exact: true})
    await formulario.getByLabel('Tasa anual (%)').fill('16')
    await expect(revisar).toBeEnabled()
    await formulario.getByLabel('Tasa anual (%)').fill('20')
    await formulario.getByRole('button', {name: 'Solicitar tasa superior'}).click()
    await expect(formulario.getByLabel('Tasa solicitada (%)')).toHaveValue('20')
    await formulario.getByLabel('Motivo comercial', {exact: true}).fill('Nuevo aporte del cliente con tasa acordada de 20%')
    await page.screenshot({path: info.outputPath('upgrade-solicitud.png'), fullPage: true})
    await formulario.getByRole('button', {name: 'Enviar a Gerencia'}).click()
    await expect(formulario.getByTestId('tasa-politica').getByRole('status')).toContainText('pendiente de Gerencia')
    await expect(revisar).toBeDisabled()
    expect(estado.solicitud).toMatchObject({categoria: 'upgrade', contrato_origen_id: origen.id, tasa_solicitada: 20})
    estado.solicitud = {...estado.solicitud, estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 20}
    await page.clock.fastForward(31_000)
    await expect(formulario.getByLabel('Tasa anual (%)')).toHaveValue('20')
    await expect(revisar).toBeEnabled()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await revisar.click()
    await expect(page.getByRole('heading', {name: 'Revisar inversión', exact: true})).toBeVisible()
    expect(estado.inversion).toMatchObject({datos: {contrato: {tasa_anual: 20, categoria: 'upgrade', contrato_origen_id: origen.id}}})
    expect(estado.envios).toBe(1)
  })
}
