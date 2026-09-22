import { expect, test, type Page } from '@playwright/test'
import { abrirConversionAvance, leadReal, loginReal, montarBackendReal, UID } from './_helpers'

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
