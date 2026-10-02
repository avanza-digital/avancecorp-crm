import { expect, test, type Page } from '@playwright/test'
import { abrirConversionAvance, leadReal, loginReal, montarBackendReal, UID } from './_helpers'

for (const ancho of [1440, 390]) {
  test(`un analista corrige el primer rechazo sin duplicar la solicitud (${ancho}px)`, async ({page}, info) => {
    await page.setViewportSize({width: ancho, height: 940})
    const ficha = await abrirLeadDePrueba(page, ancho)
    let acceso = await abrirConversionAvance(page, ficha)
    const claves: string[] = []
    let registrada = false
    let altas = 0
    page.on('request', request => {
      if (/crm-inversion-portal|confirmar_inversion_revisada_fn/.test(request.url())) altas++
    })
    await page.route('**/rest/v1/rpc/preparar_inversion_fn', async route => {
      claves.push(route.request().postDataJSON().p_clave)
      if (claves.length === 1) return route.fulfill({status: 400, json: {
        code: '22023', message: 'Completa el nombre legal y un correo válido para el acceso Avance',
      }})
      registrada = true
      return route.fallback()
    })
    await page.route('**/rest/v1/rpc/solicitud_inversion_fn', async route => {
      if (!registrada) return route.fulfill({status: 404, json: {code: 'P0002', message: 'Solicitud no encontrada'}})
      return route.fallback()
    })
    await acceso.getByLabel('Apellidos', {exact: true}).fill('PRUEBA')
    await acceso.getByLabel('Nombres', {exact: true}).fill('PERSONA')
    await acceso.getByLabel('Correo de acceso Avance').fill('primero@example.invalid')
    await acceso.getByLabel('Domicilio legal').fill('AVENIDA SINTETICA 123 LIMA')
    await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
    await expect(acceso.getByRole('alert')).toContainText('Completa el nombre legal')
    await expect(acceso.getByLabel('Nombres', {exact: true})).toHaveValue('PERSONA')
    await expect(acceso.getByText(/La solicitud aún no está registrada/)).toBeVisible()
    await acceso.screenshot({path: info.outputPath(`rechazo-editable-${ancho}.png`), animations: 'disabled'})

    // Retomar un intento rechazado de una versión anterior tampoco lo reenvía
    // a ciegas: conserva los datos y permite corregir con la misma referencia.
    await acceso.getByRole('button', {name: 'Cerrar y continuar después'}).click()
    await ficha.getByRole('button', {name: /Convertir a cliente/i}).click()
    await page.getByRole('button', {name: 'Continuar a Nueva inversión'}).click()
    acceso = page.getByRole('dialog', {name: 'Acceso Avance'})
    await expect(acceso.getByLabel('Correo de acceso Avance')).toHaveValue('primero@example.invalid')
    expect(claves).toHaveLength(1)
    await acceso.getByLabel('Correo de acceso Avance').fill('corregido@example.invalid')
    await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
    await expect(acceso.getByRole('button', {name: 'Completar acceso Avance'})).toBeEnabled()
    await expect(acceso.getByRole('definition').filter({hasText: /^corregido@example\.invalid$/})).toBeVisible()
    expect(claves).toHaveLength(2)
    expect(claves[1]).toBe(claves[0])
    expect(altas).toBe(0)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  })
}

async function abrirLeadDePrueba(page: Page, ancho: number) {
  const lead = leadReal({
    vendedor_id: UID, nombre_completo: 'CLIENTE SINTÉTICO DE ACCESO', dni: '71309001',
    etapa: 'propuesta_enviada', monto_estimado: 20000,
  })
  await montarBackendReal(page, {rolCrm: 'vendedor', leads: [lead]})
  await loginReal(page, {esperarWorkspace: ancho >= 768})
  await page.goto('/#/cartera')
  await page.getByRole('row', {name: `Abrir ficha de ${lead.nombre_completo}`, exact: true}).click()
  return page.getByRole('dialog', {name: lead.nombre_completo, exact: true})
}

for (const ancho of [1440, 390]) {
  test(`primer acceso Avance se retoma y muestra tres pasos sin desbordar (${ancho}px)`, async ({page}, info) => {
    await page.setViewportSize({width: ancho, height: 940})
    const ficha = await abrirLeadDePrueba(page, ancho)
    let acceso = await abrirConversionAvance(page, ficha)
    const pasos = acceso.getByRole('navigation', {name: 'Progreso de primera inversión Avance'})
    await expect(pasos).toContainText('Paso 1 de 3')
    await acceso.getByLabel('Apellidos', {exact: true}).fill('PRUEBA')
    await acceso.getByLabel('Nombres', {exact: true}).fill('PERSONA')
    await acceso.getByLabel('Correo de acceso Avance').fill('persona-final@example.invalid')
    await acceso.getByLabel('Domicilio legal').fill('Av. Corta 1')
    await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
    await expect(acceso.getByLabel('Domicilio legal')).toHaveAttribute('aria-invalid', 'true')
    await expect(acceso.getByRole('alert')).toContainText('entre 15 y 240 caracteres')
    await acceso.getByLabel('Domicilio legal').fill('Av. Javier Prado Este 123, San Isidro, Lima')
    await acceso.screenshot({path: info.outputPath(`01-acceso-${ancho}.png`), animations: 'disabled'})
    await acceso.getByRole('button', {name: 'Cerrar y continuar después'}).click()
    await expect(acceso).toHaveCount(0)

    await ficha.getByRole('button', {name: /Convertir a cliente/i}).click()
    await page.getByRole('button', {name: 'Continuar a Nueva inversión'}).click()
    await page.getByRole('button', {name: 'Avance', exact: true}).click()
    acceso = page.getByRole('dialog', {name: 'Acceso Avance'})
    await expect(acceso.getByLabel('Apellidos', {exact: true})).toHaveValue('PRUEBA')
    await expect(acceso.getByLabel('Nombres', {exact: true})).toHaveValue('PERSONA')
    await expect(acceso.getByLabel('Correo de acceso Avance')).toHaveValue('persona-final@example.invalid')
    await expect(acceso.getByLabel('Domicilio legal')).toHaveValue('Av. Javier Prado Este 123, San Isidro, Lima')

    await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
    await expect(acceso.getByRole('button', {name: 'Completar acceso Avance'})).toBeVisible()
    await expect(acceso.getByText('persona-final@example.invalid')).toBeVisible()
    await acceso.screenshot({path: info.outputPath(`02-revision-acceso-${ancho}.png`), animations: 'disabled'})

    // La suite usa un backend sintético cerrado a red real. Estas dos RPC
    // completan la revisión de condiciones dentro de la misma solicitud.
    const llave = await page.evaluate(() => Object.keys(sessionStorage).find(k => k.startsWith('crm:f5:solicitud:')))
    expect(llave).toBeTruthy()
    const intento = await page.evaluate(k => JSON.parse(sessionStorage.getItem(k!)!), llave)
    let solicitud = {
      solicitud_id: intento.clave, lead_id: intento.datos.lead_id, estado: 'preparada', inversion_id: null,
      inversionista_id: intento.persona, inversionista_origen_id: intento.persona, identidad_fusionada: false,
      responsable_esperado_id: UID, responsable_actual_id: UID, requiere_revision_responsable: false,
      revision_datos: 0, revision_responsable: 0, hash_datos: 'prueba', necesita_portal: true,
      comprobante_bucket: null, comprobante_ruta: null, resultado: null, datos: intento.datos,
    }
    await page.route('**/rest/v1/rpc/solicitud_inversion_fn', route => route.fulfill({json: solicitud}))
    await page.route('**/rest/v1/rpc/corregir_solicitud_inversion_fn', route => {
      const cuerpo = route.request().postDataJSON()
      solicitud = {...solicitud, datos: cuerpo.p_datos, revision_datos: solicitud.revision_datos + 1, hash_datos: 'revisada'}
      return route.fulfill({json: solicitud})
    })
    await page.route('**/functions/v1/crm-inversion-portal', async route => {
      solicitud = {...solicitud, necesita_portal: false}
      await route.fallback()
    })

    await acceso.getByRole('button', {name: 'Completar acceso Avance'}).click()
    const contrato = page.getByRole('dialog', {name: /Crear contrato de/})
    await expect(contrato.getByRole('navigation', {name: 'Progreso de primera inversión Avance'})).toContainText('Paso 2 de 3')
    await contrato.screenshot({path: info.outputPath(`03-condiciones-${ancho}.png`), animations: 'disabled'})
    expect(await page.evaluate(() => Object.keys(sessionStorage).some(k => k.startsWith('crm:f5:condiciones:')))).toBe(false)
    await contrato.getByLabel('Capital', {exact: true}).fill('23000')
    await contrato.getByLabel('N° de contrato', {exact: true}).fill('000719')
    await contrato.getByRole('radio', {name: /BCP.*8901/i}).check()
    const condicionesLocales = await page.evaluate(() => {
      const llave = Object.keys(sessionStorage).find(k => k.startsWith('crm:f5:condiciones:'))
      return llave ? JSON.parse(sessionStorage.getItem(llave)!) : null
    })
    expect(condicionesLocales?.datos).toMatchObject({capital: '23000', numero: '000719'})
    expect(condicionesLocales?.datos).not.toHaveProperty('cuentaNueva')
    expect(condicionesLocales?.datos).not.toHaveProperty('titulares')
    await contrato.getByRole('button', {name: 'Cerrar y continuar después'}).click()
    await expect(contrato).toHaveCount(0)

    await ficha.getByRole('button', {name: /Convertir a cliente/i}).click()
    await page.getByRole('button', {name: 'Continuar a Nueva inversión'}).click()
    const retomado = page.getByRole('dialog', {name: /Crear contrato de/})
    await expect(retomado.getByRole('navigation', {name: 'Progreso de primera inversión Avance'})).toContainText('Paso 2 de 3')
    await expect(retomado.getByLabel('Capital', {exact: true})).toHaveValue('23000')
    await expect(retomado.getByLabel('N° de contrato', {exact: true})).toHaveValue('000719')
    await expect(retomado.getByRole('radio', {name: /BCP.*8901/i})).toBeChecked()
    await expect(retomado.getByText(/Recuperamos las condiciones que escribiste/)).toBeVisible()
    await retomado.screenshot({path: info.outputPath(`03b-condiciones-recuperadas-${ancho}.png`), animations: 'disabled'})
    await retomado.getByRole('button', {name: 'Revisar inversión'}).click()
    const revision = page.getByRole('dialog', {name: 'Revisar inversión'})
    await expect(revision.getByRole('navigation', {name: 'Progreso de primera inversión Avance'})).toContainText('Paso 3 de 3')
    await revision.screenshot({path: info.outputPath(`04-revision-contrato-${ancho}.png`), animations: 'disabled'})
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  })
}

test('corregir el correo permite continuar y un conflicto conocido conserva el formulario', async ({page}) => {
  const ficha = await abrirLeadDePrueba(page, 1440)
  const acceso = await abrirConversionAvance(page, ficha)
  await acceso.getByLabel('Apellidos', {exact: true}).fill('PRUEBA')
  await acceso.getByLabel('Nombres', {exact: true}).fill('PERSONA')
  await acceso.getByLabel('Correo de acceso Avance').fill('primero@example.invalid')
  await acceso.getByLabel('Domicilio legal').fill('Av. Javier Prado Este 123, San Isidro, Lima')
  await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
  await acceso.getByRole('button', {name: 'Corregir datos de acceso'}).click()
  await acceso.getByLabel('Correo de acceso Avance').fill('corregido@example.invalid')
  let rechazar = true
  await page.route('**/rest/v1/rpc/corregir_solicitud_inversion_fn', async route => {
    if (rechazar) {
      rechazar = false
      return route.fulfill({status: 409, json: {code: 'PT409', message: 'Los datos cambiaron; vuelve a revisar la solicitud'}})
    }
    return route.fallback()
  })
  await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
  await expect(acceso.getByRole('alert')).toContainText('Los datos cambiaron')
  await expect(acceso.getByLabel('Correo de acceso Avance')).toHaveValue('corregido@example.invalid')
  await expect(page.getByRole('dialog', {name: 'Actualización pendiente'})).toHaveCount(0)
  await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
  await expect(acceso.getByRole('definition').filter({hasText: /^corregido@example\.invalid$/})).toBeVisible()
  await expect(acceso.getByRole('button', {name: 'Completar acceso Avance'})).toBeEnabled()
  await acceso.getByRole('button', {name: 'Completar acceso Avance'}).click()
  await expect(page.getByRole('dialog', {name: /Crear contrato de/})).toBeVisible()
})

test('volver a la ventana y recargar la página en las condiciones del contrato conservan el wizard y lo escrito', async ({page}) => {
  const lead = leadReal({
    vendedor_id: UID, nombre_completo: 'CLIENTE SINTÉTICO DE FOCO', dni: '71309001',
    etapa: 'propuesta_enviada', monto_estimado: 20000,
  })
  const backend = await montarBackendReal(page, {rolCrm: 'vendedor', leads: [lead]})
  await loginReal(page)
  await page.goto('/#/cartera')
  await page.getByRole('row', {name: `Abrir ficha de ${lead.nombre_completo}`, exact: true}).click()
  const ficha = page.getByRole('dialog', {name: lead.nombre_completo, exact: true})
  const llamadas = {identidad: 0, preparar: 0}
  page.on('request', request => {
    if (request.url().endsWith('/rpc/preparar_persona_lead_inversion_fn')) llamadas.identidad++
    if (request.url().endsWith('/rpc/preparar_inversion_fn')) llamadas.preparar++
  })
  const acceso = await abrirConversionAvance(page, ficha)
  await acceso.getByLabel('Apellidos', {exact: true}).fill('PRUEBA')
  await acceso.getByLabel('Nombres', {exact: true}).fill('PERSONA')
  await acceso.getByLabel('Correo de acceso Avance').fill('persona-foco@example.invalid')
  await acceso.getByLabel('Domicilio legal').fill('Av. Javier Prado Este 123, San Isidro, Lima')
  await acceso.getByRole('button', {name: 'Revisar acceso Avance'}).click()
  await acceso.getByRole('button', {name: 'Completar acceso Avance'}).click()
  const contrato = page.getByRole('dialog', {name: /Crear contrato de/})
  const pasos = {name: 'Progreso de primera inversión Avance'}
  await expect(contrato.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
  await contrato.getByLabel('Capital', {exact: true}).fill('23000')
  await contrato.getByLabel('N° de contrato', {exact: true}).fill('000719')
  await contrato.getByRole('radio', {name: /BCP.*8901/i}).check()

  // Preparar la identidad ESCRIBIÓ en el lead: el servidor ya tiene otra fecha de
  // actualización y la cartera la trae al volver a la ventana. Antes eso cambiaba la
  // consulta del documento, desmontaba el wizard y reaparecía el modal de identidad.
  backend.leads = backend.leads.map(l => ({...l, actualizado_en: '2026-07-02T00:00:00.000Z'}))
  // La ficha relee el documento con el lead nuevo: es la señal de que la resincronización llegó a pantalla.
  const relectura = page.waitForResponse(r => r.url().endsWith('/rpc/documento_lead_fn'))
  await page.evaluate(() => {
    document.dispatchEvent(new Event('visibilitychange', {bubbles: true}))
    window.dispatchEvent(new Event('focus'))
  })
  await relectura
  await expect(contrato.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
  await expect(contrato.getByLabel('Capital', {exact: true})).toHaveValue('23000')
  await expect(contrato.getByLabel('N° de contrato', {exact: true})).toHaveValue('000719')
  await expect(page.getByRole('dialog', {name: /Registrar la inversión del lead|Documento del lead/})).toHaveCount(0)

  // Más de una hora con la pestaña oculta: el token ya venció y Auth lo renueva al volver.
  // La renovación de la misma cuenta no puede remontar nada.
  const renovacion = page.waitForResponse(r => r.url().includes('/auth/v1/token') && r.url().includes('grant_type=refresh_token'))
  await page.evaluate(() => {
    const llave = Object.keys(localStorage).find(k => k.startsWith('sb-') && k.endsWith('-auth-token'))!
    const sesion = JSON.parse(localStorage.getItem(llave)!)
    localStorage.setItem(llave, JSON.stringify({...sesion, expires_at: Math.floor(Date.now() / 1000) - 60}))
    document.dispatchEvent(new Event('visibilitychange', {bubbles: true}))
    window.dispatchEvent(new Event('focus'))
  })
  expect((await renovacion).ok()).toBe(true)
  await expect(contrato.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
  await expect(contrato.getByLabel('Capital', {exact: true})).toHaveValue('23000')
  await expect(contrato.getByLabel('N° de contrato', {exact: true})).toHaveValue('000719')

  // Recargar: la ficha vuelve por la URL y reabre el wizard donde estaba, sin pedir otra vez la identidad.
  await page.reload()
  const retomado = page.getByRole('dialog', {name: /Crear contrato de/})
  await expect(retomado.getByRole('navigation', pasos)).toContainText('Paso 2 de 3')
  await expect(retomado.getByLabel('Capital', {exact: true})).toHaveValue('23000')
  await expect(retomado.getByLabel('N° de contrato', {exact: true})).toHaveValue('000719')
  await expect(retomado.getByRole('radio', {name: /BCP.*8901/i})).toBeChecked()
  await retomado.getByRole('button', {name: 'Revisar inversión'}).click()
  await expect(page.getByRole('dialog', {name: 'Revisar inversión'}).getByRole('navigation', pasos)).toContainText('Paso 3 de 3')
  // Una sola identidad y una sola solicitud en todo el recorrido: nada se duplicó.
  expect(llamadas).toEqual({identidad: 1, preparar: 1})
  // Cerrado a mano, recargar otra vez ya no lo reabre: vuelve la ficha sola.
  await page.getByRole('dialog', {name: 'Revisar inversión'}).getByRole('button', {name: 'Cerrar y continuar después'}).click()
  await expect(page.getByRole('dialog', {name: 'Revisar inversión'})).toHaveCount(0)
  await page.reload()
  await expect(ficha.getByRole('button', {name: 'Convertir a cliente'})).toBeVisible()
  await expect(page.getByRole('dialog', {name: /Crear contrato de|Revisar inversión|Nueva inversión|Documento del lead/})).toHaveCount(0)
})
