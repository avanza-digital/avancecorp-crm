// E2E de C1 — "Repartir leads" por la RUTA REAL (sesión autenticada con rol
// `coordinador`, todo el HTTP de Supabase interceptado: cero escritura en prod).
//
// Prueba lo que ni el gate SQL ni los tests de componente cubren: que el rol
// nuevo ATERRIZA en su pantalla, que su navegación se reduce a lo suyo, que el
// reparto viaja con los argumentos correctos y saca la fila, y que los dos
// rechazos que importan — el veto legal (Ley 29571) y el lead que ya salió de la
// cola — avisan al usuario y fuerzan una resincronización en vez de mentir.
import { expect, test } from '@playwright/test'
import { loginReal, montarBackendReal } from './_helpers'

const SUPERVISORES = [
  { perfil_id: 'sup-1', nombre: 'SUPERVISOR UNO', activo: true, bandeja_pendiente: 2 },
  { perfil_id: 'sup-2', nombre: 'SUPERVISOR DOS', activo: true, bandeja_pendiente: 0 },
]

const COLA = [
  {
    id: 'lead-usd',
    nombre_completo: 'MARTHA VILCA',
    distrito: 'Miraflores',
    origen: 'landing',
    categoria_interes: 'nuevo',
    monto_estimado: 45000,
    moneda: 'USD',
    creado_en: '2026-07-20T12:00:00.000Z',
    clasificacion_auto: null,
    comentario: 'Quiero información sobre el plazo fijo para invertir',
  },
  {
    id: 'lead-pen',
    nombre_completo: 'JORGE CASTRO',
    distrito: 'San Isidro',
    origen: 'referido',
    categoria_interes: 'nuevo',
    monto_estimado: 120000,
    moneda: 'PEN',
    creado_en: '2026-07-21T12:00:00.000Z',
    clasificacion_auto: null,
    comentario: null,
  },
]

/** C1-bis: lead que el clasificador marcó (menciona préstamo en el comentario). */
const LEAD_CREDITO = {
  id: 'lead-credito',
  nombre_completo: 'PEDRO HUAMÁN',
  distrito: 'Comas',
  origen: 'formulario',
  categoria_interes: null,
  monto_estimado: 1000,
  moneda: 'PEN',
  creado_en: '2026-07-22T12:00:00.000Z',
  clasificacion_auto: 'posible_credito',
  comentario: 'Necesito un préstamo urgente, mi número es [teléfono oculto]',
}

/** Monta el backend con rol coordinador y entra; devuelve el estado mutable. */
async function entrarComoCoordinador(page: Parameters<typeof loginReal>[0], init = {}) {
  const backend = await montarBackendReal(page, {
    rolCrm: 'coordinador',
    rolPortal: 'comercial',
    colaReparto: COLA,
    supervisoresReparto: SUPERVISORES,
    ...init,
  })
  await loginReal(page)
  await expect(page.getByRole('heading', { name: 'Repartir leads' })).toBeVisible()
  return backend
}

test('el coordinador aterriza en Repartir y su navegación se reduce a lo suyo', async ({ page }) => {
  await entrarComoCoordinador(page)

  // Aterrizaje por capacidad (no por hash guardado): su vista base es 'repartir'.
  await expect(page).toHaveURL(/#\/repartir$/)

  // El nav NO le ofrece cartera, equipo ni configuración (espejo de la RLS: su
  // ámbito de leads es vacío y no tiene cartera propia).
  await expect(page.getByRole('button', { name: 'Repartir leads' })).toBeVisible()
  for (const ajena of ['Mi cartera', 'Cartera', 'Equipo', 'Configuración', 'Pipeline']) {
    await expect(page.getByRole('button', { name: ajena, exact: true })).toHaveCount(0)
  }
})

test('#/mi-cartera por URL expulsa al coordinador de vuelta a Repartir', async ({ page }) => {
  await entrarComoCoordinador(page)

  await page.evaluate(() => { window.location.hash = '#/mi-cartera' })

  await expect(page).toHaveURL(/#\/repartir$/)
  await expect(page.getByRole('heading', { name: 'Repartir leads' })).toBeVisible()
})

test('la cabecera separa el capital PEN del USD (jamás los suma)', async ({ page }) => {
  await entrarComoCoordinador(page)

  // Acotar cada cifra a SU KPI: "S/ 120k" también aparece legítimamente en la
  // fila del lead y un selector global sería estricto-ambiguo, no una falla UI.
  const pen = page.locator('.ac-lift').filter({ hasText: 'Capital en juego (PEN)' })
  const usd = page.locator('.ac-lift').filter({ hasText: 'Capital en juego (USD)' })
  await expect(pen).toHaveCount(1)
  await expect(usd).toHaveCount(1)
  await expect(pen.getByText('S/ 120k')).toBeVisible()
  await expect(usd.getByText('US$ 45k')).toBeVisible()
  // 165k sería la suma mezclada de dos monedas: no debe existir.
  await expect(page.getByText(/165k/)).toHaveCount(0)
})

test('repartir un lead lo saca de la cola y sube la bandeja del supervisor', async ({ page }) => {
  const backend = await entrarComoCoordinador(page)

  await expect(page.getByText('MARTHA VILCA')).toBeVisible()
  await page.getByLabel('Asignar MARTHA VILCA a un supervisor').selectOption('sup-1')
  await page.getByRole('button', { name: 'Repartir a MARTHA VILCA', exact: true }).click()

  // El servidor recibió el par correcto…
  await expect.poll(() => backend.llamadas.rpcRepartirLead).toBe(1)
  expect(backend.ultimoReparto).toEqual({ lead: 'lead-usd', supervisor: 'sup-1' })

  // …la fila desaparece de la cola y el capital USD se recalcula…
  await expect(page.getByText('MARTHA VILCA')).toHaveCount(0)
  await expect(page.getByText('US$ 0')).toBeVisible()
  // …y la bandeja del destino ya refleja el lead que acaba de recibir.
  await expect(page.getByLabel('Asignar JORGE CASTRO a un supervisor'))
    .toContainText('SUPERVISOR UNO (3 en bandeja)')
})

test('el veto legal (No Insista) avisa, NO mueve la fila y resincroniza la cola', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, {
    fallarProximoReparto: {
      code: 'P0429',
      message: 'Lead marcado No Insista (Ley 29571): no se puede repartir',
    },
  })

  const releidasAntes = backend.llamadas.rpcLeadsPorRepartir
  await page.getByLabel('Asignar MARTHA VILCA a un supervisor').selectOption('sup-2')
  await page.getByRole('button', { name: 'Repartir a MARTHA VILCA', exact: true }).click()

  // Mensaje LEGAL literal (no un "no tienes permiso" genérico).
  await expect(page.getByText('Lead marcado No Insista (Ley 29571): no se puede repartir'))
    .toBeVisible()
  // La fila NO se movió: el servidor revirtió y el frontend no miente.
  await expect(page.getByText('MARTHA VILCA')).toBeVisible()
  // Y la cola se relee: el estado local estaba desfasado respecto del servidor.
  await expect.poll(() => backend.llamadas.rpcLeadsPorRepartir).toBeGreaterThan(releidasAntes)
})

test('si el lead ya salió de la cola, avisa y resincroniza', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, {
    fallarProximoReparto: {
      code: 'P0002',
      message: 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)',
    },
  })

  const releidasAntes = backend.llamadas.rpcLeadsPorRepartir
  await page.getByLabel('Asignar JORGE CASTRO a un supervisor').selectOption('sup-1')
  await page.getByRole('button', { name: 'Repartir a JORGE CASTRO', exact: true }).click()

  await expect(page.getByText(/ya no está en la cola por repartir/)).toBeVisible()
  await expect.poll(() => backend.llamadas.rpcLeadsPorRepartir).toBeGreaterThan(releidasAntes)
})

test('cola vacía: estado honesto que explica de dónde vendrán los leads', async ({ page }) => {
  await entrarComoCoordinador(page, { colaReparto: [] })

  await expect(page.getByText('No hay leads por repartir')).toBeVisible()
  await expect(page.getByRole('button', { name: /Repartir a / })).toHaveCount(0)
})

// ── F1b tanda 3: los indicadores los cuenta el SERVIDOR ─────────────────────

test('los tiles de la cola los sirve resumen_reparto_fn, no el conteo del navegador', async ({ page }) => {
  const backend = await entrarComoCoordinador(page)

  const total = page.locator('.ac-lift').filter({ hasText: 'Por repartir' })
  await expect(total.getByText('2')).toBeVisible()
  // Y consta que el número salió de una llamada al agregado, no de contar filas.
  await expect.poll(() => backend.llamadas.rpcResumenReparto).toBeGreaterThan(0)
})

test('el StatStrip dice lo que dice el SERVIDOR, aunque no cuadre con las filas cargadas', async ({ page }) => {
  // Divergencia deliberada: el agregado habla de la cola GLOBAL (57 leads) y la
  // lista muestra 2. Es la única prueba fuerte del objetivo de la tanda — con un
  // payload derivado de la cola, un verde no distingue "lo dijo el servidor" de
  // "lo contó el navegador". En producción coinciden hasta que F2 pagine.
  await entrarComoCoordinador(page, {
    resumenRepartoOverride: {
      version: 1,
      generado_en: '2026-08-09T15:00:00+00:00',
      cola: {
        total: 57,
        capital: { pen: 999000, usd: 0 },
        espera_max_dias: 9,
        posible_credito: 4,
        por_origen: [{ origen: 'landing', n: 57 }],
      },
    },
  })

  await expect(page.locator('.ac-lift').filter({ hasText: 'Por repartir' }).getByText('57')).toBeVisible()
  await expect(page.locator('.ac-lift').filter({ hasText: 'Capital en juego (PEN)' }).getByText('S/ 999k')).toBeVisible()
  await expect(page.locator('.ac-lift').filter({ hasText: 'Espera más larga' }).getByText('hace 9 días')).toBeVisible()
  // …mientras la lista sigue mostrando las 2 filas que sí tiene cargadas.
  await expect(page.getByText('MARTHA VILCA')).toBeVisible()
  await expect(page.getByText('JORGE CASTRO')).toBeVisible()
})

test('resumen_reparto_fn caída: los tiles degradan a «—» con aviso y la cola sigue repartible', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, { fallarResumenReparto: true })

  await expect(page.getByRole('status')).toContainText(/No se pudieron cargar los indicadores de la cola/)
  for (const etiqueta of ['Por repartir', 'Capital en juego (PEN)', 'Capital en juego (USD)', 'Espera más larga']) {
    await expect(page.locator('.ac-lift').filter({ hasText: etiqueta }).getByText('—')).toBeVisible()
  }
  // Y —lo que importa— la operación no se bloquea: la lista tiene su propia fuente.
  await page.getByLabel('Asignar MARTHA VILCA a un supervisor').selectOption('sup-1')
  await page.getByRole('button', { name: 'Repartir a MARTHA VILCA', exact: true }).click()
  await expect.poll(() => backend.llamadas.rpcRepartirLead).toBe(1)
  await expect(page.getByText('MARTHA VILCA')).toHaveCount(0)
})

test('sin supervisores activos no se puede repartir y la pantalla lo dice', async ({ page }) => {
  await entrarComoCoordinador(page, { supervisoresReparto: [] })

  await expect(page.getByText('No hay supervisores activos')).toBeVisible()
  await expect(page.getByRole('button', { name: /Repartir a / })).toHaveCount(0)
})

// ── C1-bis: el código marca, Rosa lee el comentario y cierra ────────────────

test('el lead marcado muestra la etiqueta "Posible crédito" y el comentario redactado', async ({ page }) => {
  await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  // La marca del clasificador es visible y el comentario (ya redactado por el
  // servidor) se lee en la fila: el dato con el que Rosa decide. Se scopea a
  // las FILAS porque el toolbar tiene su propio chip "Posible crédito (N)".
  await expect(page.locator('[data-lead-id="lead-credito"]').getByText('Posible crédito')).toBeVisible()
  await expect(page.getByText(/Necesito un préstamo urgente/)).toBeVisible()
  // Los leads sin marca NO llevan etiqueta (una sola entre todas las filas).
  await expect(page.locator('[data-lead-id]').getByText('Posible crédito')).toHaveCount(1)
  // El comentario del lead limpio también se muestra.
  await expect(page.getByText(/plazo fijo para invertir/)).toBeVisible()
})

test('descartar un lead marcado: motivo pre-propuesto, RPC exacta y fila fuera', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  await page.getByRole('button', { name: 'Descartar a PEDRO HUAMÁN de la cola' }).click()
  // La marca del código PROPONE el motivo; el humano solo confirma.
  await expect(page.getByLabel('Motivo para descartar a PEDRO HUAMÁN')).toHaveValue('pide_credito')
  await page.getByRole('button', { name: 'Descartar a PEDRO HUAMÁN', exact: true }).click()

  // El servidor recibió lead y motivo exactos, sin nota.
  await expect.poll(() => backend.llamadas.rpcDescartarLead).toBe(1)
  expect(backend.ultimoDescarte).toEqual({ lead: 'lead-credito', motivo: 'pide_credito', nota: null })

  // La fila salió de la cola (se asevera por sus CONTROLES: el toast de éxito
  // también contiene el nombre y un getByText lo confundiría con la fila).
  await expect(page.getByLabel(/PEDRO HUAMÁN/)).toHaveCount(0)
  await expect(page.getByLabel('Asignar MARTHA VILCA a un supervisor')).toBeVisible()
  // …y el tile SERVIDO baja con ella: sin la invalidación del descarte, el
  // agregado se quedaría en 3 durante los 30 s de staleTime mientras la lista
  // muestra 2 — exactamente la divergencia que esta tanda vino a evitar.
  await expect(page.locator('.ac-lift').filter({ hasText: 'Por repartir' }).getByText('2')).toBeVisible()
})

test('el descarte se puede deshacer desde el aviso y el lead vuelve a la cola', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  await page.getByRole('button', { name: 'Descartar a PEDRO HUAMÁN de la cola' }).click()
  await page.getByRole('button', { name: 'Descartar a PEDRO HUAMÁN', exact: true }).click()
  await expect(page.getByLabel(/PEDRO HUAMÁN/)).toHaveCount(0)

  // El aviso de éxito ofrece Deshacer (la ventana real de 24 h vive en la BD).
  await page.getByRole('button', { name: 'Deshacer' }).click()

  await expect.poll(() => backend.llamadas.rpcDeshacerDescarte).toBe(1)
  // Tras deshacer se relee la cola: la fila está de vuelta con sus controles…
  await expect(page.getByLabel('Asignar PEDRO HUAMÁN a un supervisor')).toBeVisible()
  // …y el tile servido vuelve a 3 (cubre la invalidación del Deshacer del toast).
  await expect(page.locator('.ac-lift').filter({ hasText: 'Por repartir' }).getByText('3')).toBeVisible()
})

test('un lead sin marca exige elegir motivo antes de poder descartar', async ({ page }) => {
  const backend = await entrarComoCoordinador(page)

  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA de la cola' }).click()
  // Sin marca no hay motivo pre-propuesto: el botón queda deshabilitado.
  await expect(page.getByLabel('Motivo para descartar a MARTHA VILCA')).toHaveValue('')
  await expect(page.getByRole('button', { name: 'Descartar a MARTHA VILCA', exact: true })).toBeDisabled()

  await page.getByLabel('Motivo para descartar a MARTHA VILCA').selectOption('no_responde')
  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA', exact: true }).click()

  await expect.poll(() => backend.llamadas.rpcDescartarLead).toBe(1)
  expect(backend.ultimoDescarte).toEqual({ lead: 'lead-usd', motivo: 'no_responde', nota: null })
})

test('si el descarte pierde la carrera, avisa y resincroniza la cola', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, {
    fallarProximoDescarte: {
      code: 'P0002',
      message: 'El lead ya no está en la cola por repartir (carrera de descarte)',
    },
  })

  const releidasAntes = backend.llamadas.rpcLeadsPorRepartir
  const resumenAntes = backend.llamadas.rpcResumenReparto
  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA de la cola' }).click()
  await page.getByLabel('Motivo para descartar a MARTHA VILCA').selectOption('sin_interes')
  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA', exact: true }).click()

  await expect(page.getByText(/carrera de descarte/)).toBeVisible()
  await expect.poll(() => backend.llamadas.rpcLeadsPorRepartir).toBeGreaterThan(releidasAntes)
  // La fila no se movió, pero la foto local quedó en duda: el agregado también
  // se re-pide (rama FUERA_DE_COLA/REINTENTAR de la invalidación).
  await expect.poll(() => backend.llamadas.rpcResumenReparto).toBeGreaterThan(resumenAntes)
})

test('Cancelar sale del modo descarte sin llamar al servidor', async ({ page }) => {
  const backend = await entrarComoCoordinador(page)

  await page.getByRole('button', { name: 'Descartar a MARTHA VILCA de la cola' }).click()
  await expect(page.getByLabel('Motivo para descartar a MARTHA VILCA')).toBeVisible()

  await page.getByRole('button', { name: 'Cancelar' }).click()

  await expect(page.getByLabel('Asignar MARTHA VILCA a un supervisor')).toBeVisible()
  expect(backend.llamadas.rpcDescartarLead).toBe(0)
})

// ── Rediseño 2026-07-24 (feedback de Miguel): orden, filtros, paginación ─────

test('el último lead en entrar se ve PRIMERO, y el orden se puede invertir', async ({ page }) => {
  await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  // Default "más recientes primero": PEDRO (22 jul) arriba, MARTHA (20 jul) al final.
  await expect(page.locator('[data-lead-id]').first()).toHaveAttribute('data-lead-id', 'lead-credito')
  await expect(page.locator('[data-lead-id]').last()).toHaveAttribute('data-lead-id', 'lead-usd')

  // Invertir a "más antiguos primero" (para repartir lo que más ha esperado).
  await page.getByLabel('Ordenar la cola por fecha de ingreso').selectOption('antiguos')
  await expect(page.locator('[data-lead-id]').first()).toHaveAttribute('data-lead-id', 'lead-usd')
})

test('cada fila muestra la fecha y hora de ingreso del lead', async ({ page }) => {
  await entrarComoCoordinador(page)

  // "entró <fecha con hora>": el dato pedido explícitamente (no solo "hace N días").
  const fila = page.locator('[data-lead-id="lead-usd"]')
  await expect(fila).toContainText('entró')
  await expect(fila).toContainText(/\d{2}:\d{2}/)
})

test('la búsqueda filtra por nombre y el vacío de filtros ofrece limpiar', async ({ page }) => {
  await entrarComoCoordinador(page)

  await page.getByLabel('Buscar en la cola por nombre, distrito o comentario').fill('JORGE')
  await expect(page.locator('[data-lead-id]')).toHaveCount(1)
  await expect(page.locator('[data-lead-id]').first()).toHaveAttribute('data-lead-id', 'lead-pen')

  // Sin coincidencias: estado honesto + salida de un clic.
  await page.getByLabel('Buscar en la cola por nombre, distrito o comentario').fill('NOEXISTE')
  await expect(page.getByText('Ningún lead coincide con la búsqueda o los filtros')).toBeVisible()
  await page.getByRole('button', { name: 'Limpiar filtros' }).click()
  await expect(page.locator('[data-lead-id]')).toHaveCount(2)
})

test('el toggle "Posible crédito" deja solo los marcados por el clasificador', async ({ page }) => {
  await entrarComoCoordinador(page, { colaReparto: [...COLA, LEAD_CREDITO] })

  await page.getByRole('button', { name: /Posible crédito \(1\)/ }).click()
  await expect(page.locator('[data-lead-id]')).toHaveCount(1)
  await expect(page.locator('[data-lead-id]').first()).toHaveAttribute('data-lead-id', 'lead-credito')
})

test('la cola pagina de a 20 con "Mostrar 20 más" (adiós scroll infinito)', async ({ page }) => {
  const colaLarga = Array.from({ length: 25 }, (_, i) => ({
    id: `lead-lote-${i}`,
    nombre_completo: `LEAD LOTE ${i}`,
    distrito: null,
    origen: 'otro',
    categoria_interes: null,
    monto_estimado: 1000 + i,
    moneda: 'PEN',
    creado_en: `2026-07-20T10:${String(i).padStart(2, '0')}:00.000Z`,
    clasificacion_auto: null,
    comentario: null,
  }))
  await entrarComoCoordinador(page, { colaReparto: colaLarga })

  await expect(page.locator('[data-lead-id]')).toHaveCount(20)
  await expect(page.getByText('Mostrando 20 de 25')).toBeVisible()

  await page.getByRole('button', { name: 'Mostrar 20 más' }).click()
  await expect(page.locator('[data-lead-id]')).toHaveCount(25)
  await expect(page.getByText('Fin de la cola · 25 leads')).toBeVisible()
})

test('un comentario largo se expande con "Ver todo" y se vuelve a plegar', async ({ page }) => {
  const largo = {
    ...LEAD_CREDITO,
    id: 'lead-largo',
    nombre_completo: 'COMENTARIO LARGO',
    comentario: 'Quiero saber todo sobre el plazo fijo: tasas, plazos, garantías, qué pasa al vencimiento, '
      + 'si puedo renovar automáticamente, cómo se pagan los intereses mes a mes y qué documentos necesito '
      + 'para abrir el contrato la próxima semana.',
  }
  await entrarComoCoordinador(page, { colaReparto: [largo] })

  const boton = page.getByRole('button', { name: 'Ver todo el comentario' })
  await expect(boton).toBeVisible()
  await boton.click()
  await expect(page.getByRole('button', { name: 'Ver menos' })).toBeVisible()
  await page.getByRole('button', { name: 'Ver menos' }).click()
  await expect(page.getByRole('button', { name: 'Ver todo el comentario' })).toBeVisible()
})

// ── C1-ter: la pestaña "Descartados" (vista + deshacer dentro de las 24 h) ───

const DESCARTADOS = [
  {
    id: 'dsc-mio',
    nombre_completo: 'LUCÍA MENDOZA',
    distrito: 'Ate',
    origen: 'formulario',
    categoria_interes: null,
    monto_estimado: 2000,
    moneda: 'PEN',
    creado_en: '2026-07-22T09:00:00.000Z',
    clasificacion_auto: 'posible_credito',
    comentario: 'Necesito un préstamo rápido',
    nota_descarte: 'confirmado por teléfono: solo busca crédito',
    motivo_descarte: 'pide_credito',
    descartado_en: '2026-07-24T14:00:00.000Z',
    descartado_por_nombre: 'ROSA COORDINADORA',
    es_mio: true,
    puede_deshacer: true,
  },
  {
    id: 'dsc-ajeno',
    nombre_completo: 'CARLOS RUIZ',
    distrito: null,
    origen: 'landing',
    categoria_interes: null,
    monto_estimado: 8000,
    moneda: 'USD',
    creado_en: '2026-07-10T09:00:00.000Z',
    clasificacion_auto: null,
    comentario: 'No me interesa por ahora',
    nota_descarte: null,
    motivo_descarte: 'sin_interes',
    descartado_en: '2026-07-23T11:00:00.000Z',
    descartado_por_nombre: 'GERENTE REAL',
    es_mio: false,
    puede_deshacer: false,
  },
]

test('la pestaña Descartados lista lo cerrado, con motivo, autor y nota', async ({ page }) => {
  await entrarComoCoordinador(page, { descartados: DESCARTADOS })

  await page.getByRole('tab', { name: 'Descartados' }).click()

  await expect(page.getByText('Leads descartados')).toBeVisible()
  const mio = page.locator('[data-descartado-id="dsc-mio"]')
  await expect(mio).toContainText('LUCÍA MENDOZA')
  await expect(mio).toContainText('Pide préstamo / crédito') // motivo legible
  await expect(mio).toContainText('Posible crédito') // marca del clasificador
  await expect(mio).toContainText('Necesito un préstamo rápido') // comentario
  await expect(mio).toContainText('confirmado por teléfono') // nota_descarte
  await expect(mio).toContainText('por ti') // es_mio
})

test('deshacer un descarte propio dentro de la ventana lo saca de la lista', async ({ page }) => {
  const backend = await entrarComoCoordinador(page, { descartados: DESCARTADOS })
  await page.getByRole('tab', { name: 'Descartados' }).click()

  await page.getByRole('button', { name: 'Deshacer el descarte de LUCÍA MENDOZA' }).click()

  const resumenAntes = backend.llamadas.rpcResumenReparto
  await expect.poll(() => backend.llamadas.rpcDeshacerDescarte).toBe(1)
  await expect(page.locator('[data-descartado-id="dsc-mio"]')).toHaveCount(0)
  // El ajeno sigue: no tenía botón, tenía el aviso.
  await expect(page.locator('[data-descartado-id="dsc-ajeno"]')).toBeVisible()

  // El lead reabierto vuelve a la cola, así que el agregado de la otra pestaña
  // quedó rancio: al volver debe RE-PEDIRSE. Sin la invalidación de `onCambio`
  // el remonte serviría la foto anterior durante los 30 s de staleTime.
  await page.getByRole('tab', { name: 'Cola de nuevos' }).click()
  await expect.poll(() => backend.llamadas.rpcResumenReparto).toBeGreaterThan(resumenAntes)
})

test('un descarte ajeno o fuera de ventana NO ofrece deshacer, explica por qué', async ({ page }) => {
  await entrarComoCoordinador(page, { descartados: DESCARTADOS })
  await page.getByRole('tab', { name: 'Descartados' }).click()

  const ajeno = page.locator('[data-descartado-id="dsc-ajeno"]')
  await expect(ajeno.getByRole('button', { name: /Deshacer/ })).toHaveCount(0)
  await expect(ajeno).toContainText('Descartado por otra persona')
})

test('si el deshacer falla (ventana vencida en el server), avisa y no miente', async ({ page }) => {
  await entrarComoCoordinador(page, {
    descartados: DESCARTADOS,
    fallarProximoDeshacer: {
      code: 'P0002',
      message: 'Solo puedes deshacer tus propios descartes de las últimas 24 horas',
    },
  })
  await page.getByRole('tab', { name: 'Descartados' }).click()

  await page.getByRole('button', { name: 'Deshacer el descarte de LUCÍA MENDOZA' }).click()

  await expect(page.getByText(/últimas 24 horas/)).toBeVisible()
})

test('la pestaña Descartados vacía explica de dónde saldrán los datos', async ({ page }) => {
  await entrarComoCoordinador(page, { descartados: [] })
  await page.getByRole('tab', { name: 'Descartados' }).click()

  await expect(page.getByText('No hay leads descartados')).toBeVisible()
})
