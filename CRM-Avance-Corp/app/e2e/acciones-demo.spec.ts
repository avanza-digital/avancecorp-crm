// E2E de las ACCIONES del CRM en modo DEMO (sin backend). Recorre crear/editar/
// mover/descartar+nota/reabrir/actividad/reasignar/convertir de punta a punta.
// En demo los toasts SÍ deben decir "(demo)" (espejo del guard yo?.demo).
import { expect, test } from '@playwright/test'
import { abrirLead, entrarDemo, irAPipeline } from './_helpers'

test('crear lead: alta rápida, toast "(demo)" y abre la ficha del nuevo lead', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await page.getByRole('button', { name: /nuevo lead/i }).click()

  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await expect(modal).toBeVisible()
  // Regla D8 (Miguel, 2026-08-11): el alta manual del vendedor ofrece SOLO
  // Referido/Oficina/Otro — Landing y Formulario se cargan solos (puente) y
  // jamás a mano. El servidor lo exige (migración F); el form lo espeja.
  for (const origen of ['referido', 'oficina', 'otro']) {
    await expect(modal.locator(`#nl-origen option[value="${origen}"]`)).toHaveCount(1)
  }
  for (const origenRetirado of ['landing', 'formulario', 'web', 'campania', 'whatsapp']) {
    await expect(modal.locator(`#nl-origen option[value="${origenRetirado}"]`)).toHaveCount(0)
  }
  await modal.locator('#nl-nombre').fill('LEAD PRUEBA E2E')
  await modal.locator('#nl-telefono').fill('987111222')
  await modal.locator('#nl-monto').fill('5000')
  await modal.locator('#nl-origen').selectOption('referido')
  await modal.getByRole('button', { name: /crear lead/i }).click()

  await expect(page.getByText(/Lead creado \(demo\)/i)).toBeVisible()
  // Abre la ficha del nuevo lead (el drawer queda etiquetado por su nombre).
  await expect(page.getByRole('dialog', { name: 'LEAD PRUEBA E2E' })).toBeVisible()
})

test('editar lead: cambia el monto y confirma con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByRole('button', { name: /editar/i }).click()
  await drawer.locator('#ld-monto').fill('99999')
  await drawer.getByRole('button', { name: /^Guardar$/ }).click()

  await expect(page.getByText(/Cambios guardados \(demo\)/i)).toBeVisible()
  // El capital refleja el nuevo valor (ahora vive DOS veces en el drawer:
  // subió al SheetHeader y sigue en la sección Datos → .first()).
  await expect(drawer.getByText(/99[.,]?999/).first()).toBeVisible()
})

test('mover etapa: el stepper avanza a Contactado (aria-current)', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByRole('button', { name: 'Contactado' }).click()
  await expect(drawer.getByRole('button', { name: 'Contactado' })).toHaveAttribute('aria-current', 'step')
})

test('descartar con nota: toast "(demo)" y banner de lead descartado', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /MARÍA LÓPEZ CASTRO/)

  await drawer.getByRole('button', { name: /descartar/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Descartar lead' })
  await expect(dialogo).toBeVisible()
  await dialogo.locator('#ld-nota-descarte').fill('No tiene fondos ahora; retomar en Q4')
  await dialogo.getByRole('button', { name: /descartar/i }).click()

  await expect(page.getByText(/Lead descartado \(demo\)/i)).toBeVisible()
  await expect(drawer.getByText('Lead descartado')).toBeVisible()
  // La nota del descarte queda en el timeline (no se pierde).
  await expect(drawer.getByText(/No tiene fondos ahora; retomar en Q4/)).toBeVisible()
})

test('reabrir: un lead descartado vuelve a Nuevo con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  // Descartar primero para tener un lead terminal en el drawer…
  await drawer.getByRole('button', { name: /descartar/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Descartar lead' })
  await dialogo.getByRole('button', { name: /descartar/i }).click()
  await expect(drawer.getByText('Lead descartado')).toBeVisible()

  // …y reabrir.
  await drawer.getByRole('button', { name: /reabrir/i }).click()
  await expect(page.getByText(/Lead reabierto \(demo\)/i)).toBeVisible()
})

test('registrar actividad: entra al timeline con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  // El composer ahora es un disclosure con aspecto de input: se expande al clic.
  await drawer.getByRole('button', { name: /Registrar actividad/ }).click()
  await drawer.getByLabel('Detalle de la actividad').fill('Llamada de prueba E2E')
  await drawer.getByRole('button', { name: /^Registrar$/ }).click()

  // El composer arranca en 'llamada_realizada', que es CONVERSACIÓN, y este
  // lead demo está en 'nuevo' → la etapa sube sola (lib/avance-automatico) y el
  // toast lo canta. Se asevera el aviso COMPLETO a propósito: un avance de
  // etapa silencioso es justo lo que este comportamiento vino a evitar.
  await expect(page.getByText(/Actividad registrada · pasó a Contactado \(demo\)/i)).toBeVisible()
  await expect(drawer.getByText('Llamada de prueba E2E')).toBeVisible()
  // Y el hecho de verdad, no solo el aviso: el stepper quedó en Contactado.
  await expect(drawer.getByRole('button', { name: 'Contactado' })).toHaveAttribute('aria-current', 'step')
})

test('reasignar (gerencia): cambia el vendedor con toast "(demo)"', async ({ page }) => {
  await entrarDemo(page, 'Gerencia')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByLabel('Reasignar vendedor').selectOption({ label: 'VENDEDOR DOS' })
  await expect(page.getByText(/Lead reasignado \(demo\)/i)).toBeVisible()
})

// El caso del vendedor sobre SU lead; Gerencia tiene otro camino global, pero el
// analista responsable conserva la atribución del cliente y del contrato.
test('convertir (demo): abre el diálogo y marca el lead como convertido', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /JUAN PÉREZ ROJAS/)

  await drawer.getByRole('button', { name: /Convertir a cliente/i }).click()
  // Paso 0 (cierres en cooperativas): elegir la empresa donde cerró. Este caso
  // es el de Avance Corp — el único que crea cuenta de portal y manda correo.
  // Nombre accesible = el DialogTitle (manda sobre el ariaLabel del componente).
  const destino = page.getByRole('dialog', { name: '¿Dónde invirtió?' })
  await expect(destino).toBeVisible()
  await destino.getByRole('button', { name: /Avance Corp/i }).click()
  const dialogo = page.getByRole('dialog', { name: 'Convertir a cliente' })
  await expect(dialogo).toBeVisible()
  await dialogo.getByRole('button', { name: /^Convertir/i }).click()

  await expect(page.getByText(/ahora es cliente \(demo\)/i)).toBeVisible()
  await expect(drawer.getByText(/Convertido a cliente \(demo\)/i)).toBeVisible()
})

// EL CASO DE MIGUEL (2026-07-26), de punta a punta: agendas la reunión y la
// tarea anterior sobra. Antes de que existiera «anular», la única salida era
// cerrarla con un resultado FALSO —«Contestó»/«No contestó»— que entra al log
// inmutable del lead y puede subirle la etapa.
test('anular la tarea que sobra tras agendar la reunión (demo)', async ({ page }) => {
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /MARÍA LÓPEZ CASTRO/)

  // Parte de una pendiente sembrada (el WhatsApp de la cola de hoy).
  const whatsapp = drawer.getByText('WhatsApp — MARÍA LÓPEZ CASTRO')
  await expect(whatsapp).toBeVisible()

  // 1) Se agenda la reunión: ahora hay DOS pendientes y el WhatsApp sobra.
  await drawer.getByRole('button', { name: /Agendar otra/i }).click()
  await drawer.getByLabel('Tipo de tarea').selectOption('reunion')
  await drawer.getByLabel('Modalidad de la cita').selectOption('virtual')
  await expect(drawer.getByLabel('Enlace de la cita')).toHaveCount(0)
  await drawer.getByRole('button', { name: /^Agendar$/ }).click()
  await expect(drawer.getByText('2 pendientes')).toBeVisible()
  await expect(drawer.getByText(/\breuni[oó]n(?:es)?\b/i)).toHaveCount(0)

  // 2) Anular pide confirmación: es irreversible en el servidor. La fila NO se
  //    reemplaza —el destructivo nace ABAJO Y A LA IZQUIERDA, nunca bajo el
  //    dedo que acaba de pulsar el icono—, así que el WhatsApp sigue visible.
  const icono = drawer.getByRole('button', { name: 'Anular tarea — WhatsApp — MARÍA LÓPEZ CASTRO' })
  await icono.click()
  await expect(icono).toHaveAttribute('aria-expanded', 'true')
  await expect(whatsapp).toBeVisible()
  await drawer.getByRole('button', { name: 'Sí, anular — WhatsApp — MARÍA LÓPEZ CASTRO' }).click()

  // 3) Se fue del plan, y NO se promete el amarillo: le queda la reunión.
  await expect(page.getByText(/^Tarea anulada \(demo\)$/)).toBeVisible()
  await expect(whatsapp).toBeHidden()
  await expect(drawer.getByText('1 pendiente')).toBeVisible()
})

test('anular la reunión devuelve el lead a su etapa anterior (demo)', async ({ page }) => {
  // Pedido de Miguel (2026-07-26): «si se anula la reu y no se reagenda una en
  // ese mismo momento, debería bajar de etapa». El circuito completo: agendar
  // sube, anular baja, y las dos veces la pantalla lo DICE.
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)
  const drawer = await abrirLead(page, /MARÍA LÓPEZ CASTRO/)

  // 1) Agendar la reunión sube al lead a «Reunión agendada».
  await drawer.getByRole('button', { name: /Agendar otra/i }).click()
  await drawer.getByLabel('Tipo de tarea').selectOption('reunion')
  await drawer.getByLabel('Modalidad de la cita').selectOption('virtual')
  await expect(drawer.getByLabel('Enlace de la cita')).toHaveCount(0)
  await drawer.getByRole('button', { name: /^Agendar$/ }).click()
  await expect(drawer.getByText('2 pendientes')).toBeVisible()

  // 2) La confirmación AVISA del retroceso antes del tap — no después.
  const icono = drawer.getByRole('button', { name: /^Anular tarea — Cita/ })
  await icono.click()
  const confirmar = drawer.getByRole('button', { name: /^Sí, anular — Cita/ })
  await expect(confirmar).toHaveAccessibleDescription(/Era su única cita: vuelve a «/)
  await drawer.getByLabel(/^Motivo de cancelación — Cita/).selectOption('cancelada_cliente')

  // 3) Al confirmar, el toast canta la etapa nueva en vez del genérico.
  await confirmar.click()
  await expect(page.getByText(/vuelve a «/)).toBeVisible()

  // 4) …y el WhatsApp sembrado sigue en pie: anular no barre la agenda.
  await expect(drawer.getByText('1 pendiente')).toBeVisible()
})

test('crear lead mueve el tile "Leads activos" al instante (espejo demo VIVO, F1)', async ({ page }) => {
  // El bloqueante del plan F1: los tiles demo se calculan del estado vivo del
  // store, no de la semilla estática — crear un lead debe moverlos sin reload.
  await entrarDemo(page, 'Vendedor')
  await irAPipeline(page)

  const chip = page.locator('[data-slot="card"]').filter({ hasText: 'Leads activos' }).first()
  const antes = Number(/\d+/.exec(await chip.innerText())?.[0])
  expect(Number.isFinite(antes)).toBe(true)

  // Alta por columna (el "+ Agregar lead" de Nuevo abre el mismo modal).
  await page.getByRole('button', { name: /agregar lead/i }).first().click()
  const modal = page.getByRole('dialog', { name: 'Nuevo lead' })
  await modal.locator('#nl-nombre').fill('LEAD TILE E2E')
  await modal.locator('#nl-telefono').fill('987333444')
  await modal.locator('#nl-monto').fill('7000')
  await modal.locator('#nl-origen').selectOption('referido')
  await modal.getByRole('button', { name: /crear lead/i }).click()
  await expect(page.getByText(/Lead creado \(demo\)/i)).toBeVisible()

  // El drawer del lead nuevo queda abierto por encima; el tile ya cambió detrás.
  await expect(chip).toContainText(String(antes + 1))
})
