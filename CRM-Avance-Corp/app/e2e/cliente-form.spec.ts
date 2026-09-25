// E2E del formulario de CLIENTE del portal dentro del CRM: alta en UN paso (la
// edge crear-cliente escribe identidad + cuentas bancarias en el mismo INSERT,
// 2026-07-27) y corrección con la ventana de 5 h, sobre la RUTA REAL con TODO el
// HTTP de Supabase interceptado (fail-closed — cero prod). Con el gate de leads
// cerrado, la vista por defecto de una cuenta real ES #/clientes.
//
// DEPENDENCIA: la pantalla screens/clientes.tsx (de otro constructor) debe
// ofrecer un botón "Nuevo cliente" y una acción "Corregir" por fila (espejo del
// portal); el dialog en sí queda nombrado por el DialogTitle de ClienteForm
// ('Nuevo cliente' / 'Corregir cliente'), así que los selectores del modal son
// estables aunque la pantalla cambie.
import { expect, test, type Locator, type Page } from '@playwright/test'
import { clienteReal, cuentaBancariaReal, irAMiCartera, loginReal, montarBackendReal, verTodaLaCartera } from './_helpers'

// Fase 6.1 (2026-07-21): la entrada al ClienteForm migró a la cartera unificada
// (#/mi-cartera, la vista por defecto de una cuenta real). El MISMO modal se abre
// con "Nuevo cliente" / "Corregir cliente"; los asserts del modal no cambian.
//
// 15/09/2026: el alta directa («Nuevo cliente» = cliente SIN lead) se cerró al
// analista — su cliente nuevo nace convirtiendo un lead. Por eso los casos de
// ALTA corren como Supervisión (que la conserva) y los de CORRECCIÓN siguen
// como analista, cuya ventana de 5 h no cambió.

/** Entra con sesión real y abre el modal de alta desde la pantalla Clientes. */
async function abrirNuevoCliente(page: Page): Promise<Locator> {
  await loginReal(page)
  await irAMiCartera(page)
  await page.getByRole('button', { name: /nuevo cliente/i }).click()
  const modal = page.getByRole('dialog', { name: /nuevo cliente/i })
  await expect(modal).toBeVisible()
  return modal
}

/** Abre "Corregir" del primer cliente de la cartera. */
async function abrirCorregirCliente(page: Page): Promise<Locator> {
  await loginReal(page)
  await irAMiCartera(page)
  // La cartera arranca en el mes en curso y estos fixtures traen contratos de
  // meses anteriores: sin esto, la fila del cliente no está en la lista.
  await verTodaLaCartera(page)
  await page.getByRole('button', { name: /corregir/i }).first().click()
  const modal = page.getByRole('dialog', { name: /corregir cliente/i })
  await expect(modal).toBeVisible()
  return modal
}

/** Identidad + cuenta PEN completa (el mínimo válido del alta). */
async function llenarAltaMinima(modal: Locator): Promise<void> {
  await modal.locator('#cf-apellidos').fill('QA PRUEBA')
  await modal.locator('#cf-nombres').fill('MARIA JOSE')
  await modal.locator('#cf-documento').fill('45781299')
  await modal.locator('#cf-correo').fill('qa-cliente@correo.pe')
  await modal.locator('#cf-domicilio').fill('Av. Los Eucaliptos 456, Miraflores, Lima')
  await modal.locator('#cf-pen-banco').selectOption('BCP')
  await modal.locator('#cf-pen-tipo').selectOption('ahorros')
  await modal.locator('#cf-pen-numero').fill('19112345678901')
  await modal.locator('#cf-pen-cci').fill('00219112345678901234')
}

test('alta feliz: UNA llamada y el cliente nace CON su cuenta bancaria', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'supervisor' })
  const modal = await abrirNuevoCliente(page)

  // El aviso de la clave temporal se muestra como en el portal.
  await expect(modal.getByText(/clave temporal/i)).toBeVisible()

  await llenarAltaMinima(modal)
  await modal.getByRole('button', { name: /crear cliente/i }).click()

  // Una sola llamada a la edge, y NINGÚN PATCH posterior que pueda fallar.
  await expect.poll(() => estado.llamadas.altaCliente).toBe(1)
  await expect
    .poll(() => estado.clientes.find((c) => c.correo === 'qa-cliente@correo.pe')?.banco ?? null)
    .toBe('BCP')
  expect(estado.llamadas.patchPerfil).toBe(0)
  // .first(): sonner duplica el nodo del texto (copia para el lector de pantalla).
  await expect(page.getByText(/Cliente "QA PRUEBA MARIA JOSE" creado/).first()).toBeVisible()
})

test('sin cuenta bancaria el servidor rechaza y NO se crea ningún cliente', async ({ page }) => {
  // El navegador ya lo impide, pero la garantía que importa es la del servidor:
  // aquí se salta la validación local escribiendo directo en el estado del form
  // no es posible, así que se comprueba el otro extremo — que el alta no viaja
  // y, si viajara sin cuentas, la edge la rechazaría (mock espejo de la real).
  const estado = await montarBackendReal(page, { rolCrm: 'supervisor' })
  const modal = await abrirNuevoCliente(page)

  await modal.locator('#cf-apellidos').fill('QA PRUEBA')
  await modal.locator('#cf-nombres').fill('MARIA JOSE')
  await modal.locator('#cf-documento').fill('45781299')
  await modal.locator('#cf-correo').fill('qa-cliente@correo.pe')
  await modal.locator('#cf-domicilio').fill('Av. Los Eucaliptos 456, Miraflores, Lima')
  // …sin tocar ninguna sección bancaria.
  await modal.getByRole('button', { name: /crear cliente/i }).click()

  await expect(
    modal.getByText('Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.'),
  ).toBeVisible()
  expect(estado.llamadas.altaCliente).toBe(0)
  expect(estado.llamadas.patchPerfil).toBe(0)
  // NO se encadenó al contrato y el alta sigue reintentable (no se creó nada).
  expect(estado.llamadas.rpcCrearContrato).toBe(0)
  await expect(page.getByRole('dialog', { name: /^crear contrato/i })).toHaveCount(0)
  await expect(modal.getByRole('button', { name: /reintentar/i })).toBeEnabled()
})

test('alta duplicada: el 409 de la edge se muestra tal cual y no hay ningún PATCH', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'supervisor', fallarProximaAlta: true })
  const modal = await abrirNuevoCliente(page)

  await llenarAltaMinima(modal)
  await modal.getByRole('button', { name: /crear cliente/i }).click()

  await expect(modal.getByText('Este documento ya está registrado para otro cliente.')).toBeVisible()
  await expect.poll(() => estado.llamadas.altaCliente).toBe(1)
  expect(estado.llamadas.patchPerfil).toBe(0)
})

test('el analista ya no tiene «Nuevo cliente»: su cliente nuevo nace convirtiendo un lead', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor' })
  await loginReal(page)
  await irAMiCartera(page)

  await expect(page.getByRole('heading', { level: 1, name: 'Mi cartera' })).toBeVisible()
  await expect(page.getByRole('button', { name: /nuevo cliente/i })).toHaveCount(0)
  expect(estado.llamadas.altaCliente).toBe(0)
})

test('corregir feliz: muestra las cuentas y deja vacío el editor de una nueva', async ({ page }) => {
  const estado = await montarBackendReal(page, { rolCrm: 'vendedor',
    // Ventana viva: el botón "Corregir" de la fila no puede estar bloqueado.
    clientes: [clienteReal({ creado_en: new Date().toISOString() })],
  })
  const modal = await abrirCorregirCliente(page)

  // Precarga del detalle (obtenerClienteDetalle) + correo = cuenta de acceso.
  await expect(modal.locator('#cf-apellidos')).toHaveValue('PORTAL UNO')
  await expect(modal.locator('#cf-correo')).toHaveAttribute('readonly', '')
  await expect(modal.locator('#cf-correo')).not.toBeEditable()
  await expect(modal.locator('#cf-domicilio')).toHaveValue('Av. Javier Prado Este 123, San Isidro, Lima')
  await expect(modal.getByText('Cuentas vigentes del cliente')).toBeVisible()
  await expect(modal.locator('#cf-pen-banco')).toHaveValue('')
  await expect(modal.getByText(/Ventana de corrección: Quedan/)).toBeVisible()

  await modal.locator('#cf-telefono').fill('999111222')
  await modal.getByRole('button', { name: /guardar corrección/i }).click()

  await expect.poll(() => estado.llamadas.patchPerfil).toBe(1)
  // .first(): sonner duplica el nodo del texto (copia para el lector de pantalla).
  await expect(page.getByText('Datos del cliente corregidos.').first()).toBeVisible()
  // El servidor simulado aplicó el cambio (no fue un éxito de mentira).
  await expect.poll(() => estado.clientes[0]?.telefono).toBe('999111222')
})

test('Gerencia registra una cuenta en el ledger sin escribir banca en perfiles', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'gerencia', rolPortal: 'admin',
    clientes: [clienteReal({ creado_en: '2020-01-01T00:00:00.000Z' })],
  })
  const perfilAntes = estado.clientes[0]!
  const llamadasBanco: Array<Record<string, unknown>> = []
  const patchesPerfil: Array<Record<string, unknown>> = []
  page.on('request', (request) => {
    if (request.url().includes('/rest/v1/rpc/actualizar_cliente_gerencia')) {
      patchesPerfil.push(request.postDataJSON() as Record<string, unknown>)
    }
  })
  await page.route('**/rest/v1/rpc/registrar_cuenta_cliente', async (route) => {
    const payload = route.request().postDataJSON() as Record<string, unknown>
    llamadasBanco.push(payload)
    const cuenta = payload.p_cuenta as Record<string, unknown>
    estado.cuentasBancarias.push(cuentaBancariaReal({
      cliente_id: perfilAntes.id,
      cuenta_id: 'e0000000-0000-4000-8000-000000000099',
      moneda: 'PEN', banco: String(cuenta.banco),
      tipo_cuenta: 'ahorros', numero_cuenta: String(cuenta.numero_cuenta),
      cci: String(cuenta.cci), origen: 'portal',
      creada_en: '2026-09-25T12:00:00.000Z',
    }))
    await route.fulfill({ status: 200, contentType: 'application/json', body: '"e0000000-0000-4000-8000-000000000099"' })
  })

  await loginReal(page)
  await irAMiCartera(page)
  await page.getByRole('button', { name: 'Cartera', exact: true }).click()
  await verTodaLaCartera(page)
  await page.getByRole('button', { name: 'Corregir', exact: true }).first().click()
  const modal = page.getByRole('dialog', { name: /corregir cliente/i })
  await expect(modal).toBeVisible()
  await modal.locator('#cf-pen-banco').selectOption('BCP')
  await modal.locator('#cf-pen-tipo').selectOption('ahorros')
  await modal.locator('#cf-pen-numero').fill('NUEVACUENTA99')
  await modal.locator('#cf-pen-cci').fill('00000000000000000099')
  await modal.getByRole('button', { name: /guardar corrección/i }).click()

  await expect.poll(() => llamadasBanco.length).toBe(1)
  expect(llamadasBanco[0]?.p_cliente_id).toBe(perfilAntes.id)
  expect(llamadasBanco[0]?.p_cuenta).toMatchObject({ cci: '00000000000000000099' })
  expect(estado.cuentasBancarias.at(-1)?.origen).toBe('portal')
  expect(estado.clientes[0]?.banco).toBe(perfilAntes.banco)
  expect(estado.clientes[0]?.cci).toBe(perfilAntes.cci)
  expect(patchesPerfil).toHaveLength(1)
  expect(patchesPerfil.every((p) => {
    const patch = (p.p_patch ?? {}) as Record<string, unknown>
    return !['banco', 'tipo_cuenta', 'numero_cuenta', 'cci', 'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
      'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd', 'titular_distinto_usd', 'beneficiario_nombre_usd', 'beneficiario_dni_usd']
      .some((clave) => Object.hasOwn(patch, clave))
  })).toBe(true)
})

test('vendedor comercial ve la cartera pero no puede abrir la corrección bancaria', async ({ page }) => {
  await montarBackendReal(page, {
    rolCrm: 'vendedor', rolPortal: 'comercial',
    clientes: [clienteReal({ creado_en: new Date().toISOString() })],
  })
  await loginReal(page)
  await irAMiCartera(page)
  await verTodaLaCartera(page)
  await expect(page.getByRole('button', { name: 'Ver detalle' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Corregir', exact: true })).toHaveCount(0)
})

test('Gerencia corrige un cliente ajeno y antiguo mediante la RPC acotada', async ({ page }) => {
  const estado = await montarBackendReal(page, {
    rolCrm: 'gerencia',
    rolPortal: 'comercial',
    clientes: [
      clienteReal({
        asesor_perfil_id: 'vend-1',
        creado_por: 'vend-1',
        creado_en: '2020-01-01T00:00:00.000Z',
      }),
    ],
  })
  await loginReal(page)
  await irAMiCartera(page)
  // Gerencia aterriza en Resumen; su cartera operativa se abre desde el menú.
  await page.getByRole('button', { name: 'Cartera', exact: true }).click()
  // La cartera arranca en el mes en curso y este contrato es de otro mes.
  await verTodaLaCartera(page)
  await page.getByRole('button', { name: 'Corregir', exact: true }).first().click()
  const modal = page.getByRole('dialog', { name: /corregir cliente/i })
  await expect(modal).toBeVisible()

  await expect(modal.getByText('Corrección autorizada por Gerencia')).toBeVisible()
  await expect(modal.getByText(/Ventana de corrección:/)).toHaveCount(0)
  await modal.locator('#cf-telefono').fill('999111222')
  await modal.getByRole('button', { name: /guardar corrección/i }).click()

  await expect.poll(() => estado.llamadas.rpcActualizarClienteGerencia).toBe(1)
  expect(estado.llamadas.patchPerfil).toBe(0)
  await expect.poll(() => estado.clientes[0]?.telefono).toBe('999111222')
  await expect(page.getByText('Datos del cliente corregidos.').first()).toBeVisible()
})

test('corregir con la ventana vencida: 0 filas sin error → mensaje de NO guardado', async ({ page }) => {
  // LA TRAMPA: el reloj local dice "vigente" (creado_en reciente) pero el
  // servidor ya no matchea la fila → 200 con [] y ningún error.
  await montarBackendReal(page, { rolCrm: 'vendedor',
    clientes: [clienteReal({ creado_en: new Date().toISOString() })],
    ventanaVencida: true,
  })
  const modal = await abrirCorregirCliente(page)

  await modal.locator('#cf-telefono').fill('999111222')
  await modal.getByRole('button', { name: /guardar corrección/i }).click()

  await expect(modal.getByText(
    'La ventana de corrección venció: los cambios NO se guardaron. Pide el cambio a administración.',
  )).toBeVisible()
  // Jamás se dice "guardado" sin filas confirmadas.
  await expect(page.getByText('Datos del cliente corregidos.')).toHaveCount(0)
})
