// E2E de la cartera de clientes (#/clientes) — la vista por DEFECTO de una
// cuenta real con el gate de leads cerrado (FUNCIONES_LEADS_APROBADAS=false).
// La pantalla se adapta por rol: vendedor ("Mis clientes", acciones en sus
// filas), supervisor (su cartera + equipo, acciones SOLO en filas propias —
// regla de cartera POR FILA del servidor), Gerencia (todo y opera todo) y
// Directorio (todo en lectura). Todo el HTTP de Supabase va interceptado por
// montarBackendReal (fail-closed): nada llega a producción.
import { expect, test } from '@playwright/test'
import { bloquearSupabase, clienteReal, entrarDemo, loginReal, montarBackendReal, UID } from './_helpers'

// Fase 6.1 (2026-07-21): la pantalla Clientes se RETIRÓ. Esta suite prueba su
// layout de tabla ("Mis clientes: N", columnas del portal, "Corregir datos",
// búsqueda "Buscar clientes", filas por rol) — TODO ello reemplazado por la
// cartera unificada, cuya tabla + búsqueda + filtro-por-asesor + "Sin asesor" +
// gating POR FILA ya están cubiertos en `screens/mi-cartera.test.tsx` (vitest,
// incluida la parity de supervisión portada en Fase 6.1). El alta/corrección de
// cliente en real-browser vive en `cliente-form.spec.ts` (migrado a #/mi-cartera).
test.skip(
  true,
  'Fase 6: Clientes retirada — cobertura de tabla/búsqueda/filtro-asesor/gating en mi-cartera.test.tsx; alta/corrección en cliente-form.spec.ts',
)

// Cartera de dos clientes: uno RECIÉN creado (ventana de 5 h viva) y uno viejo
// (ventana vencida) — el par exacto que necesita el reloj y el gate de corregir.
function carteraConVentanas() {
  return [
    clienteReal({
      id: 'cli-fresco-1',
      nombre_completo: 'CLIENTE FRESCO DOS',
      dni: '41112223',
      correo: 'fresco@correo.pe',
      creado_en: new Date().toISOString(),
    }),
    clienteReal(), // CLIENTE PORTAL UNO, creado_en 2026-07-01 → vencida hace rato
  ]
}

/** Cartera del supervisor: una fila PROPIA, una del equipo y una huérfana propia. */
function carteraDeSupervision() {
  return [
    clienteReal({
      id: 'cli-mio',
      nombre_completo: 'CLIENTE PROPIO SUPERVISOR',
      dni: '40000001',
      correo: 'propio@correo.pe',
      // asesor = yo (UID): fila de MI cartera personal → acciones.
    }),
    clienteReal({
      id: 'cli-del-equipo',
      nombre_completo: 'CLIENTE DEL VENDEDOR UNO',
      dni: '40000002',
      correo: 'equipo@correo.pe',
      asesor_perfil_id: 'vend-1',
      creado_por: 'vend-1',
    }),
    clienteReal({
      id: 'cli-huerfano-mio',
      nombre_completo: 'CLIENTE SIN ASESOR CREADO POR MI',
      dni: '40000003',
      correo: 'huerfano@correo.pe',
      // La rama OR de la regla del servidor: sin asesor, manda creado_por.
      asesor_perfil_id: null,
      creado_por: UID,
    }),
  ]
}

test('lista: pinta la cartera con columnas del portal y el contador', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: carteraConVentanas() })
  await loginReal(page)

  // Con el gate cerrado la cuenta real cae directo en Clientes.
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  const filaVieja = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await expect(filaVieja).toBeVisible()
  await expect(filaVieja.getByText('45781234')).toBeVisible()
  await expect(filaVieja.getByText('cliente1@correo.pe')).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE FRESCO DOS/ })).toBeVisible()

  // La regla de las 5 h se explica en pantalla (copy del portal).
  await expect(page.getByText(/El reloj de corrección corre 5 h/)).toBeVisible()

  // El vendedor solo ve SU cartera: ni columna Asesor ni filtro por asesor.
  await expect(page.getByRole('columnheader', { name: 'Asesor' })).toHaveCount(0)
  await expect(page.getByLabel('Filtrar por asesor')).toHaveCount(0)
})

test('reloj de ventana: "Quedan…" para el recién creado y "Bloqueado" para el vencido', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  const filaFresca = page.getByRole('row', { name: /CLIENTE FRESCO DOS/ })
  const filaVieja = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })

  // Recién creado → quedan ~4 h 59 m; el formato exacto es 'Quedan H h MM m'.
  await expect(filaFresca.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(filaVieja.getByText('Bloqueado')).toBeVisible()
})

test('corregir: deshabilitado con la ventana vencida, habilitado con la ventana viva', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  const corregirVencido = page
    .getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    .getByRole('button', { name: 'Corregir datos' })
  await expect(corregirVencido).toBeDisabled()

  const corregirVigente = page
    .getByRole('row', { name: /CLIENTE FRESCO DOS/ })
    .getByRole('button', { name: 'Corregir datos' })
  await expect(corregirVigente).toBeEnabled()

  // Con la ventana viva, el botón abre el formulario de corrección.
  await corregirVigente.click()
  await expect(page.getByRole('dialog')).toBeVisible()
})

test('"+ Contrato" abre el formulario de contrato del cliente (sin ventana: siempre activo)', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  // Incluso en la fila con la ventana de corrección VENCIDA: crear contrato no
  // tiene ventana (regla del portal).
  await page
    .getByRole('row', { name: /CLIENTE PORTAL UNO/ })
    .getByRole('button', { name: '+ Contrato' })
    .click()

  // El título del formulario (ContratoNuevo) nombra al cliente.
  await expect(page.getByRole('dialog', { name: /Registrar nueva inversión de CLIENTE PORTAL UNO/ })).toBeVisible()
})

test('búsqueda: filtra por texto normalizado y muestra el contador "X de N"', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: carteraConVentanas() })
  await loginReal(page)
  await expect(page.getByText('Mis clientes: 2')).toBeVisible()

  await page.getByLabel('Buscar clientes').fill('fresco')
  await expect(page.getByRole('row', { name: /CLIENTE FRESCO DOS/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })).toHaveCount(0)
  await expect(page.getByText('1 de 2')).toBeVisible()

  // Sin coincidencias: estado honesto (no una tabla vacía muda).
  await page.getByLabel('Buscar clientes').fill('nadie-con-este-nombre')
  await expect(page.getByText('Sin resultados')).toBeVisible()

  // Limpiar la búsqueda repone la cartera completa.
  await page.getByLabel('Buscar clientes').fill('')
  await expect(page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })).toBeVisible()
})

test('supervisor: acciones SOLO en filas de su cartera personal (regla de cartera por fila)', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor', clientes: carteraDeSupervision() })
  await loginReal(page)

  // Título honesto para quien ve más que lo suyo.
  await expect(page.getByText('Cartera de clientes: 3')).toBeVisible()
  // Sigue siendo analista del portal: el alta sí se le ofrece.
  await expect(page.getByRole('button', { name: 'Nuevo cliente' })).toBeVisible()

  // Fila PROPIA (asesor = yo): Corregir y + Contrato presentes.
  const filaMia = page.getByRole('row', { name: /CLIENTE PROPIO SUPERVISOR/ })
  await expect(filaMia.getByRole('button', { name: 'Corregir datos' })).toBeVisible()
  await expect(filaMia.getByRole('button', { name: '+ Contrato' })).toBeVisible()

  // Fila huérfana creada por mí (asesor NULL + creado_por = yo): también MÍA —
  // es la rama OR exacta de crear_contrato/perfiles_analista_update.
  const filaHuerfana = page.getByRole('row', { name: /CLIENTE SIN ASESOR CREADO POR MI/ })
  await expect(filaHuerfana.getByRole('button', { name: '+ Contrato' })).toBeVisible()

  // Fila del EQUIPO: CERO botones (el servidor los rechazaría: "Solo puedes
  // crear contratos para clientes de tu cartera") y el asesor a la vista.
  const filaAjena = page.getByRole('row', { name: /CLIENTE DEL VENDEDOR UNO/ })
  await expect(filaAjena.getByRole('button', { name: 'Corregir datos' })).toHaveCount(0)
  await expect(filaAjena.getByRole('button', { name: '+ Contrato' })).toHaveCount(0)
  await expect(filaAjena.getByText('Vendedor Real Uno')).toBeVisible()
})

test('supervisor: filtro por asesor con el roster (incluye la herencia por creado_por)', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'supervisor', clientes: carteraDeSupervision() })
  await loginReal(page)
  await expect(page.getByText('Cartera de clientes: 3')).toBeVisible()

  // Solo la cartera del vendedor del equipo.
  await page.getByLabel('Filtrar por asesor').selectOption({ label: 'Vendedor Real Uno' })
  await expect(page.getByRole('row', { name: /CLIENTE DEL VENDEDOR UNO/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE PROPIO SUPERVISOR/ })).toHaveCount(0)
  await expect(page.getByText('1 de 3')).toBeVisible()

  // Mi cartera personal incluye la fila huérfana (dueño por creado_por).
  await page.getByLabel('Filtrar por asesor').selectOption({ label: 'Gerente Real' })
  await expect(page.getByRole('row', { name: /CLIENTE PROPIO SUPERVISOR/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE SIN ASESOR CREADO POR MI/ })).toBeVisible()
  await expect(page.getByText('2 de 3')).toBeVisible()
})

test('paginación: 60 clientes → 2 páginas de 50 con Anterior/Siguiente', async ({ page }) => {
  // Fábrica en bucle: 60 filas con creado_en decreciente (001 la más nueva)
  // para que el orden desc de la pantalla sea determinista.
  const base = Date.parse('2026-07-01T12:00:00.000Z')
  const cartera = Array.from({ length: 60 }, (_, i) => {
    const n = String(i + 1).padStart(3, '0')
    return clienteReal({
      id: `cli-pag-${n}`,
      nombre_completo: `CLIENTE PAGINA ${n}`,
      dni: String(40100000 + i),
      correo: `pagina${n}@correo.pe`,
      creado_en: new Date(base - i * 60_000).toISOString(),
    })
  })
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: cartera })
  await loginReal(page)

  await expect(page.getByText('Mis clientes: 60')).toBeVisible()
  await expect(page.getByText('Página 1 de 2 · 60 registros')).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE PAGINA 001/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE PAGINA 060/ })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Anterior' })).toBeDisabled()

  await page.getByRole('button', { name: 'Siguiente' }).click()
  await expect(page.getByText('Página 2 de 2 · 60 registros')).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE PAGINA 060/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /CLIENTE PAGINA 001/ })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Siguiente' })).toBeDisabled()

  await page.getByRole('button', { name: 'Anterior' }).click()
  await expect(page.getByRole('row', { name: /CLIENTE PAGINA 001/ })).toBeVisible()
})

// Gerencia (aunque su rol de portal sea 'directorio') ve y opera toda la cartera
// por su rol CRM. No hereda la ventana de 5 h del analista.
test('gerencia: cartera completa con columna Asesor y acciones globales', async ({ page }) => {
  await montarBackendReal(page, { rolPortal: 'directorio', clientes: carteraConVentanas() })
  await loginReal(page)
  // Gerencia aterriza en su panel Hoy (gate parcial 2026-07-16): navega a Clientes.
  await page.getByRole('button', { name: 'Clientes' }).click()

  // Título honesto: NO es "su" cartera, es la de la empresa.
  await expect(page.getByText('Cartera de clientes: 2')).toBeVisible()

  const filaVieja = page.getByRole('row', { name: /CLIENTE PORTAL UNO/ })
  await expect(filaVieja).toBeVisible()
  // Columna Asesor con el nombre resuelto del roster (UID → Gerente Real).
  await expect(page.getByRole('columnheader', { name: 'Asesor' })).toBeVisible()
  await expect(filaVieja.getByText('Gerente Real')).toBeVisible()

  // Acciones globales, sin reloj: la ventana de 5 h solo limita al analista.
  await expect(page.getByRole('button', { name: 'Nuevo cliente' })).toBeVisible()
  await expect(filaVieja.getByRole('button', { name: 'Corregir datos' })).toBeVisible()
  await expect(filaVieja.getByRole('button', { name: '+ Contrato' })).toBeVisible()
  await expect(page.getByRole('columnheader', { name: 'Ventana de corrección' })).toHaveCount(0)
  await expect(page.getByRole('columnheader', { name: 'Registrado' })).toBeVisible()
})

test('cartera vacía: estado vacío con el copy del portal', async ({ page }) => {
  await montarBackendReal(page, { rolCrm: 'vendedor', clientes: [] })
  await loginReal(page)

  await expect(page.getByText('Mis clientes: 0')).toBeVisible()
  await expect(page.getByText('Aún no registraste clientes.')).toBeVisible()
  await expect(page.getByText(/Usa “\+ Nuevo cliente”/)).toBeVisible()
})

// ── DEMO (fixtures gated + recorte de ámbito local; cero red) ──────────────────

test('demo vendedor: SU cartera con el reloj vivo y la regla por creado_por — SIN pegarle a Supabase', async ({
  page,
}) => {
  // Fail-closed: en demo NINGÚN request debe salir al host de Supabase. Si el
  // módulo intentara listar/crear, el route lo abortaría y el contador (== 0 al
  // final) lo delataría.
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Vendedor')
  await page.getByRole('button', { name: 'Clientes' }).click()

  // El ámbito demo espeja el scoping del servidor: d-v1 ve SOLO sus 3 clientes
  // (ROSA/JAVIER/GLADYS); BRUNO (d-v3) y NADIA (d-v2) quedan fuera.
  await expect(page.getByText('Mis clientes: 3')).toBeVisible()
  await expect(page.getByRole('row', { name: /BRUNO ALEXIS FONSECA IPARRAGUIRRE/ })).toHaveCount(0)
  // Sin equipo no hay columna Asesor.
  await expect(page.getByRole('columnheader', { name: 'Asesor' })).toHaveCount(0)

  // El reloj de 5 h: viva para la recién creada (−1 h), Bloqueado para la vieja (−40 d).
  const filaViva = page.getByRole('row', { name: /ROSA MERCEDES AGUILAR VENTURA/ })
  await expect(filaViva.getByText(/Quedan \d+ h \d{2} m/)).toBeVisible()
  await expect(page.getByRole('row', { name: /GLADYS PILAR YUPANQUI ROJAS/ }).getByText('Bloqueado')).toBeVisible()

  // JAVIER no tiene asesor asignado pero lo creó d-v1: la rama OR de la regla
  // de cartera le da acciones igual (espejo del servidor).
  await expect(
    page.getByRole('row', { name: /JAVIER ERNESTO MEZA COLLANTES/ }).getByRole('button', { name: 'Corregir datos' }),
  ).toBeEnabled()

  // Acción demo: "+ Nuevo cliente" NO llama a la API — solo el toast "(demo)".
  await page.getByRole('button', { name: 'Nuevo cliente' }).click()
  await expect(page.getByText(/disponible solo con tu cuenta real \(demo\)/i)).toBeVisible()

  // Ninguna request salió al host de Supabase.
  expect(requestsSupabase()).toBe(0)
})

test('demo supervisor: su cartera + equipo, acciones SOLO en la fila propia', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Supervisor')
  await page.getByRole('button', { name: 'Clientes' }).click()

  // d-sup1: TERESA (propia) + las carteras de d-v1 y d-v2 = 5 (BRUNO, de d-v3, no).
  await expect(page.getByText('Cartera de clientes: 5')).toBeVisible()
  await expect(page.getByRole('row', { name: /BRUNO ALEXIS FONSECA IPARRAGUIRRE/ })).toHaveCount(0)

  // Su fila propia (ventana viva −2 h): acciones completas.
  const filaPropia = page.getByRole('row', { name: /TERESA VICTORIA PAREDES OCHOA/ })
  await expect(filaPropia.getByRole('button', { name: 'Corregir datos' })).toBeEnabled()
  await expect(filaPropia.getByRole('button', { name: '+ Contrato' })).toBeVisible()

  // Fila del equipo: sin botones y con el asesor a la vista; la sigla CE
  // acompaña al documento (patrón del portal).
  const filaEquipo = page.getByRole('row', { name: /NADIA SOLEDAD CHOQUE MAMANI/ })
  await expect(filaEquipo.getByRole('button', { name: 'Corregir datos' })).toHaveCount(0)
  await expect(filaEquipo.getByRole('button', { name: '+ Contrato' })).toHaveCount(0)
  await expect(filaEquipo.getByText('VENDEDOR DOS')).toBeVisible()
  await expect(filaEquipo.getByText('CE', { exact: true })).toBeVisible()

  expect(requestsSupabase()).toBe(0)
})

test('demo gerencia: los 6 clientes, acciones globales, búsqueda y filtro', async ({ page }) => {
  const requestsSupabase = await bloquearSupabase(page)

  await entrarDemo(page, 'Gerencia')
  await page.getByRole('button', { name: 'Clientes' }).click()

  await expect(page.getByText('Cartera de clientes: 6')).toBeVisible()
  await expect(page.getByRole('columnheader', { name: 'Asesor' })).toBeVisible()

  // El pasaporte luce su sigla y su asesor (BRUNO es de VENDEDOR TRES).
  const filaBruno = page.getByRole('row', { name: /BRUNO ALEXIS FONSECA IPARRAGUIRRE/ })
  await expect(filaBruno.getByText('PASAPORTE')).toBeVisible()
  await expect(filaBruno.getByText('PE1548792')).toBeVisible()
  await expect(filaBruno.getByText('VENDEDOR TRES')).toBeVisible()

  // Gerencia opera toda la cartera, incluso si el cliente pertenece a otro asesor.
  await expect(page.getByRole('button', { name: 'Nuevo cliente' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Corregir datos' }).first()).toBeVisible()
  await expect(page.getByRole('button', { name: '+ Contrato' }).first()).toBeVisible()

  // Búsqueda normalizada sobre los fixtures.
  await page.getByLabel('Buscar clientes').fill('nadia')
  await expect(page.getByRole('row', { name: /NADIA SOLEDAD CHOQUE MAMANI/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /ROSA MERCEDES AGUILAR VENTURA/ })).toHaveCount(0)
  await expect(page.getByText('1 de 6')).toBeVisible()
  await page.getByLabel('Buscar clientes').fill('')

  // Filtro por asesor: la cartera de VENDEDOR UNO incluye a JAVIER (sin asesor
  // asignado, dueño por creado_por) — 3 de 6.
  await page.getByLabel('Filtrar por asesor').selectOption({ label: 'VENDEDOR UNO' })
  await expect(page.getByText('3 de 6')).toBeVisible()
  await expect(page.getByRole('row', { name: /JAVIER ERNESTO MEZA COLLANTES/ })).toBeVisible()
  await expect(page.getByRole('row', { name: /NADIA SOLEDAD CHOQUE MAMANI/ })).toHaveCount(0)

  expect(requestsSupabase()).toBe(0)
})
