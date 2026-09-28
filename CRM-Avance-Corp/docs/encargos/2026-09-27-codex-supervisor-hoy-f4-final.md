ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado de este encargo), TEST GAPS,
REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como
hipótesis lo no demostrado. Omite secciones vacías.

# Encargo: AUDITORÍA FINAL del «Hoy» del supervisor — F4 (enrutado) + arreglos de tu revisión F2/F3 + arreglos de accesibilidad — LEVEL 2

El dueño pidió que Codex audite TODO el código. Ya auditaste F1 (CHANGES_REQUESTED, cerrado en
605ac085) y F2/F3 (CHANGES_REQUESTED: 1 P1 + 3 P2 + 1 P3). Este es el último tramo (commit
b862ac80, diff 605ac085..b862ac80 abajo):
1. Tus 5 hallazgos de F2/F3: analista vigente contra el conjunto SELECCIONABLE; consulta de
   decisiones con clave estable `{senal:'pendientes', analista:null}` (los `totales` no dependen de
   la señal); sin todas las fuentes no se ordena («Revisando…»); conversión con error ⇒ «—» y aviso
   visible; textos/etiquetas.
2. Revisión del subagente de accesibilidad (1 P1 + 7 P2): fila sin `disabled` (aria-disabled);
   avisos → `AvisoDegradacion` (ancla de foco); popover cierra en `focusout`; severidad con forma +
   texto (triángulo/punto/aro, «urgente», «En rojo/ámbar»); `DesgloseMonedas tono="fuerte"`; nombre
   de la fila del equipo con los USD aparte; reflow en 375 px; objetivos ≥36/40 px; `role="list"`;
   foco inicial del diálogo en el título; «Por repartir:» en el nombre del KPI.
3. F4: `hoy.tsx` enruta a `HoySupervisorMando` (modo legado/demo ⇒ pantalla clásica). e2e nuevo
   `hoy-supervisor-mando.spec.ts` y ajuste de `sla-operacion.spec.ts`.
4. Extra: `nombresCortos` para que dos analistas con el mismo primer nombre no den chips iguales;
   pestañas en la línea del título.

Residuos aceptados por el PRIMARY (dilos solo si crees que NO deben aceptarse): el error de apertura
de ficha se anuncia dos veces (toast del store + aviso local, igual que el módulo Seguimiento); el
anillo `ring/40` de la casa; el `Sheet` de la ficha no descarta `<body>` como origen de foco.

VERIFICACIÓN corrida por el PRIMARY (júzgala, no la repitas):
- `tsc -b`: PASS (pre-commit de b862ac80). `oxlint`: PASS.
- vitest `src/screens/hoy/` + `src/lib/`: PASS (2538 antes de nombresCortos; 439 de hoy+cola-supervision después).
- `supervisor-mando.test.tsx`: 41/41 PASS.
- e2e Docker: `hoy-supervisor-mando.spec.ts` 2/2 PASS; `sla-operacion.spec.ts` + `gestion-diaria-cola.spec.ts`
  PASS (1 flaky de tiempo en sla-operacion:579 «modelo 3: actualiza el aviso al vencer la tarea», pasó
  al reintento; ya conocido como flake de tiempo).
- `npm run check` completo: se está corriendo en paralelo sobre este mismo árbol.

Busca bugs nuevos introducidos por estos arreglos y confirma si tus 5 hallazgos de F2/F3 quedaron
bien cerrados. Si algo está bien, no lo menciones.

## DIFF 605ac085..b862ac80
```diff
diff --git a/CRM-Avance-Corp/app/e2e/hoy-supervisor-mando.spec.ts b/CRM-Avance-Corp/app/e2e/hoy-supervisor-mando.spec.ts
new file mode 100644
index 00000000..9a48974f
--- /dev/null
+++ b/CRM-Avance-Corp/app/e2e/hoy-supervisor-mando.spec.ts
@@ -0,0 +1,90 @@
+// Hoy del supervisor como puesto de mando (27/09/2026), en el MUNDO DE
+// PRODUCCIÓN: seguimiento ACTIVO. Se recorre con teclado a 1440×900 y se deja
+// una captura para la revisión visual de Miguel.
+import { expect, test } from '@playwright/test'
+import { loginReal } from './_helpers'
+import { montarColaEquipo } from './_sla-cola'
+
+test('supervisor: decide primero, cola filtrada en el servidor y detalle — todo con teclado', async ({ page }) => {
+  await page.setViewportSize({ width: 1440, height: 900 })
+  const { pedidos, analistaUno } = await montarColaEquipo(page, 'supervisor')
+  const errores: string[] = []
+  page.on('pageerror', (error) => errores.push(error.message))
+  await loginReal(page)
+
+  // 1 · Decide primero: la primera gestión vencida la cuenta el servidor.
+  await expect(page.getByRole('heading', { name: 'Decide primero', exact: true })).toBeVisible()
+  await expect(page.getByRole('button', { name: 'Hoy: 4 primeras gestiones vencidas' })).toBeVisible()
+
+  // 2 · Cola: vista previa de 7 del seguimiento, conteos del servidor.
+  await expect(page.getByRole('heading', { name: 'Pendientes del equipo', exact: true })).toBeVisible()
+  const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
+  await expect(lista.locator(':scope > li')).toHaveCount(7)
+  expect(pedidos.at(-1)).toMatchObject({ p_limite: 7, p_senal: 'pendientes', p_cursor: null })
+  await expect(page.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
+  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-1440x900.png'), animations: 'disabled' })
+
+  // Abrir la ficha con teclado y volver con Esc: el foco regresa a la fila
+  // (con `disabled` en la fila se perdía a <body>; revisor a11y P1).
+  const primeraFila = lista.locator(':scope > li').first().getByRole('button', { name: /^Abrir ficha de / })
+  await primeraFila.focus()
+  await page.keyboard.press('Enter')
+  await expect(page.getByRole('dialog')).toBeVisible()
+  await page.keyboard.press('Escape')
+  await expect(page.getByRole('dialog')).toHaveCount(0)
+  await expect(primeraFila).toBeFocused()
+
+  // Pestañas con flechas (tabindex itinerante) → la señal va al servidor.
+  await page.getByRole('tab', { name: /Para atender ahora/ }).focus()
+  await page.keyboard.press('ArrowRight')
+  await expect(page.getByRole('tab', { name: 'Primera gestión: 4' })).toBeFocused()
+  await expect.poll(() => pedidos.at(-1)?.p_senal).toBe('primera_atencion')
+  await expect(lista.locator(':scope > li')).toHaveCount(4)
+
+  // La tarjeta despliega su contexto y deja la cola en esa pestaña.
+  const tarjeta = page.getByRole('button', { name: 'Hoy: 4 primeras gestiones vencidas' })
+  await tarjeta.focus()
+  await page.keyboard.press('Enter')
+  await expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
+  await expect(page.getByText('Revisa la primera gestión con cada analista: abajo quedan solo esos casos.')).toBeVisible()
+
+  // Chip de analista: el filtro lo hace el SERVIDOR.
+  // Dos analistas con el mismo primer nombre: los chips los distinguen.
+  const chips = page.getByRole('group', { name: 'Filtrar por analista' })
+  await expect(chips.getByRole('button', { name: 'Analista Norte Uno' })).toHaveText('Analista U.')
+  await chips.getByRole('button', { name: 'Analista Norte Uno' }).click()
+  await expect.poll(() => pedidos.some((p) => p.p_analista_id === analistaUno)).toBe(true)
+  await expect(page.getByRole('heading', { name: 'Pendientes de Analista U.', exact: true })).toBeVisible()
+
+  // 3 · Detalle: Enter abre, Esc cierra y el foco vuelve al botón.
+  const detalle = page.getByRole('button', { name: 'Detalle', exact: true })
+  await detalle.focus()
+  await page.keyboard.press('Enter')
+  const dialogo = page.getByRole('dialog', { name: 'Detalle del equipo' })
+  await expect(dialogo).toBeVisible()
+  await expect(dialogo.getByRole('heading', { name: 'Cumplimiento del mes' })).toBeVisible()
+  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-detalle.png'), animations: 'disabled' })
+  await page.keyboard.press('Escape')
+  await expect(dialogo).toHaveCount(0)
+  await expect(detalle).toBeFocused()
+
+  // Sin jerga en pantalla.
+  await expect(page.locator('main')).not.toContainText(/pipeline|SLA/)
+  expect(errores).toEqual([])
+})
+
+test('supervisor: en un celular (375 px) la pantalla reacomoda sin cortar lo esencial', async ({ page }) => {
+  await page.setViewportSize({ width: 375, height: 800 })
+  await montarColaEquipo(page, 'supervisor')
+  // En el celular no hay menú de escritorio que esperar.
+  await loginReal(page, { esperarWorkspace: false })
+  await expect(page.getByRole('heading', { name: 'Pendientes del equipo', exact: true })).toBeVisible()
+  const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
+  await expect(lista.locator(':scope > li')).toHaveCount(7)
+  // Sin columna de analista, el dueño pasa a la segunda línea de cada fila.
+  await expect(lista.locator(':scope > li').first()).toContainText('Analista U. ·')
+  // Nada desborda en horizontal.
+  const desborde = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
+  expect(desborde).toBeLessThanOrEqual(0)
+  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-375.png'), fullPage: true, animations: 'disabled' })
+})
diff --git a/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts b/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts
index 27393cf4..b1fd70f6 100644
--- a/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts
@@ -160,15 +160,20 @@ for (const rol of ['gerencia', 'supervisor'] as const) {
     if (rol === 'gerencia') {
       await expect(page.getByRole('heading', { name: 'Resumen', exact: true })).toBeVisible()
     } else {
-      await expect(page.getByRole('link', { name: 'Abrir seguimiento', exact: true })).toBeVisible()
+      // 27/09/2026: el Hoy del supervisor es un puesto de mando con una VISTA
+      // PREVIA de 7 pendientes; el módulo completo sigue siendo Seguimiento.
+      await expect(page.getByRole('heading', { name: 'Pendientes del equipo', exact: true })).toBeVisible()
     }
     await expect(page.getByRole('list', { name: 'Oportunidades de esta página' })).toHaveCount(0)
-    expect(pedidos).toHaveLength(0)
+    if (rol === 'gerencia') expect(pedidos).toHaveLength(0)
+    else expect(pedidos.every((pedido) => pedido.p_limite === 7 && pedido.p_cursor === null)).toBe(true)
+    const antesDelModulo = pedidos.length
     await expect(page.getByRole('button', { name: 'Seguimiento', exact: true })).toBeVisible()
     if (rol === 'supervisor') {
-      await page.getByRole('link', { name: 'Abrir seguimiento', exact: true }).click()
+      await page.getByRole('link', { name: /Ver todo en Seguimiento/ }).click()
       await expect(page).toHaveURL(/#\/seguimiento$/)
     } else await irASeguimiento(page)
+    await expect.poll(() => pedidos.length).toBeGreaterThan(antesDelModulo)
     const lista = page.getByRole('list', { name: 'Oportunidades de esta página' })
     const prioridades = page.getByRole('group', { name: 'Prioridades de seguimiento' })
     await expect(lista.locator(':scope > li')).toHaveCount(10)
diff --git a/CRM-Avance-Corp/app/src/components/common/desglose-monedas.tsx b/CRM-Avance-Corp/app/src/components/common/desglose-monedas.tsx
index 8d5658d6..631ffa87 100644
--- a/CRM-Avance-Corp/app/src/components/common/desglose-monedas.tsx
+++ b/CRM-Avance-Corp/app/src/components/common/desglose-monedas.tsx
@@ -21,6 +21,8 @@ const TONOS = {
   casa: { conTc: 'text-muted-foreground', sinTc: 'text-foreground' },
   /** Dentro del panel de inteligencia de gerencia. */
   gerencia: { conTc: 'text-[var(--gi-muted)]', sinTc: 'text-[var(--gi-navy)]' },
+  /** Filas con fondo tintado (selección): el gris flojo baja de 4,5:1 a 11 px. */
+  fuerte: { conTc: 'text-muted-foreground-strong', sinTc: 'text-foreground' },
 } as const
 
 export interface DesgloseMonedasProps {
diff --git a/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts b/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts
index 608ca215..cbaf5743 100644
--- a/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/cola-supervision.test.ts
@@ -1,5 +1,5 @@
 import { describe, expect, it } from 'vitest'
-import { estadoCasoSupervision, momentoCaso } from './cola-supervision'
+import { estadoCasoSupervision, momentoCaso, nombresCortos } from './cola-supervision'
 
 const AHORA = Date.parse('2026-09-27T15:00:00Z')
 
@@ -35,3 +35,16 @@ describe('momentoCaso', () => {
     expect(momentoCaso('seguimiento', 'no-es-fecha', AHORA)).toBe('sin fecha confirmada')
   })
 })
+
+describe('nombresCortos', () => {
+  it('primer nombre cuando no se repite', () => {
+    expect([...nombresCortos(['KAREN ZAPATA', 'JORGE HUAMÁN']).values()]).toEqual(['Karen', 'Jorge'])
+  })
+
+  it('si dos comparten el primer nombre, los distingue con la inicial del apellido', () => {
+    const m = nombresCortos(['KAREN ZAPATA', 'KAREN LÓPEZ', 'JORGE HUAMÁN', 'KAREN ZAPATA'])
+    expect(m.get('KAREN ZAPATA')).toBe('Karen Z.')
+    expect(m.get('KAREN LÓPEZ')).toBe('Karen L.')
+    expect(m.get('JORGE HUAMÁN')).toBe('Jorge')
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/cola-supervision.ts b/CRM-Avance-Corp/app/src/lib/cola-supervision.ts
index f6585804..6406bd89 100644
--- a/CRM-Avance-Corp/app/src/lib/cola-supervision.ts
+++ b/CRM-Avance-Corp/app/src/lib/cola-supervision.ts
@@ -7,6 +7,7 @@
 // caso, y el tiempo dice qué significa la fecha de referencia de ese bucket:
 // en unos es un plazo (vence / venció), en otros el inicio (desde).
 import { DIA_MS, duracionTexto, haceTexto } from './inteligencia'
+import { primerNombre } from './format'
 
 /** Estado del caso visto desde supervisión, por bucket del seguimiento. */
 export const ESTADO_CASO_SUPERVISION: Record<string, string> = {
@@ -40,3 +41,21 @@ export function momentoCaso(bucket: string, referenciaEn: string | null, ahora:
   if (!BUCKETS_CON_PLAZO.has(bucket)) return `desde ${haceTexto(Math.max(0, dias))}`
   return dias >= 0 ? `venció ${haceTexto(dias)}` : `vence en ${duracionTexto(-dias)}`
 }
+
+/**
+ * Nombre corto de cada persona para chips y columnas estrechas: el primer
+ * nombre, y si dos lo comparten, la inicial del último apellido para
+ * distinguirlos («Karen Z.» / «Karen L.»). Dos chips iguales no se pueden elegir.
+ */
+export function nombresCortos(nombres: readonly string[]): Map<string, string> {
+  const unicos = [...new Set(nombres.map((n) => n.trim()).filter(Boolean))]
+  const porPila = new Map<string, number>()
+  for (const n of unicos) porPila.set(primerNombre(n), (porPila.get(primerNombre(n)) ?? 0) + 1)
+  return new Map(unicos.map((n) => {
+    const pila = primerNombre(n)
+    if ((porPila.get(pila) ?? 0) < 2) return [n, pila] as const
+    const partes = n.split(/\s+/)
+    const inicial = partes.length > 1 ? (partes[partes.length - 1] ?? '').charAt(0).toUpperCase() : ''
+    return [n, inicial ? `${pila} ${inicial}.` : pila] as const
+  }))
+}
diff --git a/CRM-Avance-Corp/app/src/screens/hoy.tsx b/CRM-Avance-Corp/app/src/screens/hoy.tsx
index 6692eb4c..550f4189 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy.tsx
@@ -4,7 +4,8 @@
 import type { JSX } from 'react'
 import { useAuth } from '@/lib/auth-context'
 import { HoyVendedor } from './hoy/vendedor'
-import { HoySupervisor } from './hoy/supervisor'
+// Puesto de mando (27/09/2026). Rollback = volver a <HoySupervisor /> de './hoy/supervisor'.
+import { HoySupervisorMando } from './hoy/supervisor-mando'
 import { HoyGerencia } from './hoy/gerencia'
 import { HoyDirectorio } from './hoy/directorio'
 import { ConfiguracionRespuestasTasa } from '@/components/app/respuestas-tasa'
@@ -13,7 +14,7 @@ export function Hoy(): JSX.Element {
   const { yo } = useAuth()
   switch (yo?.rol) {
     case 'supervisor':
-      return <><ConfiguracionRespuestasTasa soloActivacion /><HoySupervisor /></>
+      return <><ConfiguracionRespuestasTasa soloActivacion /><HoySupervisorMando /></>
     case 'gerencia':
       return <HoyGerencia seccion="resumen" />
     case 'directorio':
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts b/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts
index f8ea192d..b2013d40 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts
+++ b/CRM-Avance-Corp/app/src/screens/hoy/datos-supervisor.ts
@@ -351,6 +351,7 @@ export function useDatosSupervisor() {
     etiquetaAccesoReparto,
     cumplimientoMensual,
     conversionConfirmada,
+    conversionMensualError,
     filasMeta,
     hayErrorMensual,
     reintentarMensual,
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
index 27c4c5cc..ff8a03e1 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
@@ -4,7 +4,7 @@
 // (./datos-supervisor.ts) corre de verdad sobre los mismos mocks que usa
 // supervisor.test.tsx; lo que se sustituye es la red.
 import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
-import { act, fireEvent, render, screen, within } from '@testing-library/react'
+import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
 import { objetivosCero, type CumplimientoMetasJerarquico, type ObjetivosPorRol } from '@/lib/objetivos'
 import type { Actividad, Lead, Miembro, Yo } from '@/lib/tipos'
 import type { ColaSlaPagina, FiltrosSla } from '@/lib/sla-operacion'
@@ -46,6 +46,7 @@ vi.mock('./agenda-equipo', () => ({ AgendaEquipoPanel: () => <section aria-label
 vi.mock('./supervisor', () => ({ HoySupervisor: () => <p>Pantalla clásica del supervisor</p> }))
 
 let METRICAS_AGENDA: MetricasAgenda | undefined
+let CONVERSION: { data: unknown; isError: boolean } = { data: undefined, isError: false }
 let AGENDA_ERROR: Error | null = null
 const REFETCH_AGENDA = vi.fn()
 vi.mock('@/data/crm-queries', () => ({
@@ -56,7 +57,7 @@ vi.mock('@/data/crm-queries', () => ({
   useSolicitarTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
   useHistorialTasaCliente: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
   useMetricasAgenda: () => ({ data: METRICAS_AGENDA, error: AGENDA_ERROR, isPending: false, isFetching: false, refetch: REFETCH_AGENDA }),
-  useConversionMensual: () => ({ data: undefined, isError: false, isPending: false, isFetching: false, refetch: vi.fn() }),
+  useConversionMensual: () => ({ data: CONVERSION.data, isError: CONVERSION.isError, isPending: false, isFetching: false, refetch: vi.fn() }),
   useCierresExternos: () => ({ data: undefined, isError: false, isPending: false, isFetching: false, refetch: () => {} }),
 }))
 vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))
@@ -185,6 +186,7 @@ beforeEach(() => {
   CUMPLIMIENTO = null
   METRICAS_AGENDA = agenda([{ vendedor_id: KAREN, nombre: 'KAREN ZAPATA' }, { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' }])
   AGENDA_ERROR = null
+  CONVERSION = { data: undefined, isError: false }
   RESPONDER = (filtros) => {
     const todas = colaTodo().filter((i) => filtros.analista_id == null || i.lead.analista_id === filtros.analista_id)
     return {
@@ -224,9 +226,8 @@ describe('Hoy · supervisor — puesto de mando: qué pantalla se elige', () =>
     MODO.activo = false
     MODO.error = new Error('caído')
     montar()
-    const alerta = screen.getByRole('alert')
-    expect(alerta).toHaveTextContent('No se pudo cargar el seguimiento')
-    fireEvent.click(within(alerta).getByRole('button', { name: /Reintentar/ }))
+    expect(screen.getByText(/No se pudo cargar el seguimiento/)).toBeInTheDocument()
+    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga del seguimiento' }))
     expect(REFETCH_MODO).toHaveBeenCalledTimes(1)
   })
 })
@@ -318,9 +319,8 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     montar()
     expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
     expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
-    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('No se pudo cargar la cola'))
-    expect(alerta).toBeDefined()
-    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
+    expect(screen.getByText(/No se pudo cargar la cola/)).toBeInTheDocument()
+    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de los pendientes del equipo' }))
     expect(REFETCH_COLA).toHaveBeenCalledTimes(1)
   })
 
@@ -345,6 +345,16 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     expect(screen.getByRole('button', { name: 'Todos' })).toHaveAttribute('aria-pressed', 'true')
   })
 
+  it('si el analista elegido se DESACTIVA (sigue en el roster), el filtro también cae', () => {
+    const { rerender } = montar()
+    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
+    expect(pedidoCola()?.filtros.analista_id).toBe(JORGE)
+    VENDEDORES = VENDEDORES.map((m) => (m.perfil_id === JORGE ? { ...m, activo: false } : m))
+    rerender(<HoySupervisorMando />)
+    expect(pedidoCola()?.filtros.analista_id).toBeNull()
+    expect(screen.getByRole('button', { name: 'Todos' })).toHaveAttribute('aria-pressed', 'true')
+  })
+
   it('una respuesta que ya no es del modo activo no se pinta como vigente', () => {
     RESPONDER = () => ({ data: pagina(colaTodo(), { modo: 'legado' }), error: null, isFetching: false })
     montar()
@@ -372,7 +382,7 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     montar()
     const fila = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')[0]!
     await act(async () => {
-      fireEvent.click(within(fila).getByRole('button', { name: 'Abrir ficha de ROSA CHÁVEZ, de Karen: Primera gestión pendiente · venció hace 2 días, S/ 20k' }))
+      fireEvent.click(within(fila).getByRole('button', { name: 'Abrir ficha de ROSA CHÁVEZ, de Karen, urgente: Primera gestión pendiente · venció hace 2 días, S/ 20k' }))
     })
     expect(abrirLead).toHaveBeenCalledWith('l-1')
     expect(screen.getByRole('alert')).toHaveTextContent('No se pudo abrir la ficha')
@@ -423,9 +433,8 @@ describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
     ]
     montar()
     expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
-    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('La agenda del equipo no respondió'))
-    expect(alerta).toBeDefined()
-    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
+    expect(screen.getByText(/La agenda del equipo no respondió/)).toBeInTheDocument()
+    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de la agenda del equipo' }))
     expect(REFETCH_AGENDA).toHaveBeenCalledTimes(1)
     const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
     expect(equipo).not.toHaveTextContent('Al día')
@@ -457,7 +466,7 @@ describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
 
   it('el enlace de la cabecera lleva a «Mi equipo hoy»', () => {
     montar()
-    expect(screen.getByRole('link', { name: 'Mi equipo hoy →' })).toHaveAttribute('href', '#/gestion-diaria')
+    expect(screen.getByRole('link', { name: 'Mi equipo hoy' })).toHaveAttribute('href', '#/gestion-diaria')
   })
 })
 
@@ -495,6 +504,9 @@ describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
     expect(document.getElementById(tarjeta.getAttribute('aria-controls')!)).toHaveTextContent('Revisa la primera gestión con cada analista')
     expect(screen.getByRole('tab', { name: /Primera gestión/ })).toHaveAttribute('aria-selected', 'true')
     expect(pedidoCola()?.filtros).toEqual({ senal: 'primera_atencion', etapa: null, analista_id: null })
+    // La fuente de la tarjeta NO cambia de clave al cambiar la pestaña (Codex F2/F3).
+    expect(pedidoEquipo()?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: null })
+    expect(tarjeta).toBeInTheDocument()
     fireEvent.click(tarjeta)
     expect(tarjeta).toHaveAttribute('aria-expanded', 'false')
     expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveAttribute('aria-selected', 'true')
@@ -502,7 +514,7 @@ describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
 
   it('«Ver» lleva a la cola y le pasa el foco a la pestaña', () => {
     montar()
-    fireEvent.click(screen.getByRole('button', { name: 'Ver las 1 primera gestión vencida en la cola' }))
+    fireEvent.click(screen.getByRole('button', { name: 'Ver en la cola: 1 primera gestión vencida' }))
     act(() => { vi.advanceTimersByTime(32) })
     const pestana = screen.getByRole('tab', { name: /Primera gestión/ })
     expect(pestana).toHaveAttribute('aria-selected', 'true')
@@ -518,7 +530,7 @@ describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
     expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
     expect(pedidoCola()?.filtros).toEqual(antes)
     expect(document.getElementById(tarjeta.getAttribute('aria-controls')!))
-      .toHaveTextContent('En 7 días: 2 sin asistir · 1 tareas vencidas · 1 sin próxima acción.')
+      .toHaveTextContent('En 7 días: 2 citas sin asistir · 1 tarea vencida · 1 lead sin próxima acción.')
     expect(screen.getByRole('link', { name: 'Ver su día: KAREN ZAPATA: 2 citas sin asistir' })).toHaveAttribute('href', '#/gestion-diaria')
   })
 
@@ -552,6 +564,14 @@ describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
     expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
   })
 
+  it('con una fuente AÚN cargando no ordena: ni la tarjeta que ya se conoce ocupa un puesto', () => {
+    // El seguimiento ya trae 1 primera gestión, pero la agenda no llegó.
+    METRICAS_AGENDA = undefined
+    montar()
+    expect(screen.getByText('Revisando las decisiones del día…')).toBeInTheDocument()
+    expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
+  })
+
   it('mientras el seguimiento carga no afirma que no hay nada: «Revisando…»', () => {
     RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
     montar()
@@ -563,10 +583,9 @@ describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
     RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: new Error('caído'), isFetching: false })
     AGENDA_ERROR = new Error('agenda caída')
     montar()
-    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('Algunas decisiones no se pudieron confirmar'))
-    expect(alerta).toHaveTextContent('no respondió el seguimiento ni la agenda')
+    expect(screen.getByText(/Algunas decisiones no se pudieron confirmar/)).toHaveTextContent('no respondió el seguimiento ni la agenda')
     expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
-    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
+    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de las decisiones del día' }))
     expect(REFETCH_COLA).toHaveBeenCalled()
     expect(REFETCH_AGENDA).toHaveBeenCalled()
   })
@@ -595,7 +614,7 @@ describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () =>
     expect(cifras).toHaveTextContent('10 toques en 7 días')
     expect(cifras).toHaveTextContent('60 % completadas')
     // 2 no asistió en el equipo: el número va en rojo de TEXTO, con su palabra al lado.
-    const itemNoAsistio = within(cifras).getAllByRole('listitem').find((li) => li.textContent === '2 no asistió')!
+    const itemNoAsistio = within(cifras).getAllByRole('listitem').find((li) => li.textContent === '2 citas sin asistir')!
     expect(itemNoAsistio.querySelector('strong')).toHaveStyle({ color: 'var(--destructive-text)' })
     expect(document.body).not.toHaveTextContent(/pipeline|suma÷suma|solo producción/i)
   })
@@ -615,7 +634,7 @@ describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () =>
     expect(within(dialogo).getAllByText('Sin meta fijada para este mes').length).toBeGreaterThan(0)
     expect(within(dialogo).getByRole('region', { name: 'Agenda del equipo' })).toBeInTheDocument()
     expect(within(dialogo).getByText(/Ves solo a tu equipo/)).toBeInTheDocument()
-    expect(within(dialogo).getByRole('link', { name: 'Ver derivaciones; bandeja sin pendientes' })).toHaveAttribute('href', '#/derivaciones')
+    expect(within(dialogo).getByRole('link', { name: 'Por repartir: Ver derivaciones; bandeja sin pendientes' })).toHaveAttribute('href', '#/derivaciones')
     fireEvent.keyDown(dialogo, { key: 'Escape' })
     expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
   })
@@ -628,3 +647,49 @@ describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () =>
     expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
   })
 })
+
+describe('Hoy · supervisor — puesto de mando: arreglos de la revisión F2/F3', () => {
+  it('una conversión RETENIDA tras un error no se publica en la franja y el aviso es visible sin abrir el detalle', () => {
+    CONVERSION = {
+      data: {
+        version: 1, generado_en: '2026-09-26T15:00:00Z', alcance: 'equipo',
+        periodo: { mes: '2026-09', mes_nombre: 'septiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01T05:00:00Z', hasta: '2026-10-01T05:00:00Z' },
+        ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
+        fuentes: { divisor: 'x', numerador: 'x', referido: 'x' },
+        cobertura: { medible: true, suelo_historico: null, motivo_no_medible: null, divisor_aproximado: 0, divisor_por_motivo: { ingreso: 10 }, cierres_sin_episodio: 0, fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 } },
+        cartera: {},
+        total: { analistas: 1, divisor: 10, cierres_no_referidos: 0, cierres_referidos: 0, cierres_de_arrastre: 0, referidos_recibidos: 0, numerador: 4, conversion_pct: 40, referidos_aporta_pct: null, cartera: {} },
+        responsables: [],
+      },
+      isError: true,
+    }
+    montar()
+    expect(screen.getByRole('list', { name: 'Cifras del equipo' })).toHaveTextContent('— conversión del mes')
+    expect(screen.getByText(/No se pudieron cargar algunos indicadores del equipo/)).toBeInTheDocument()
+  })
+
+  it('al cerrar «Detalle» con Esc el foco VUELVE al botón', async () => {
+    vi.useRealTimers()
+    montar()
+    const boton = screen.getByRole('button', { name: 'Detalle' })
+    boton.focus()
+    fireEvent.click(boton)
+    fireEvent.keyDown(screen.getByRole('dialog', { name: 'Detalle del equipo' }), { key: 'Escape' })
+    await waitFor(() => expect(boton).toHaveFocus())
+  })
+
+  it('«Esta semana» se cierra con un clic fuera y usa la etiqueta del reparto del servidor', () => {
+    METRICAS_AGENDA = agenda([
+      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2 },
+      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 5 },
+    ])
+    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
+    montar()
+    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
+    fireEvent.click(disparador)
+    const lista = screen.getByRole('list', { name: 'Decisiones para esta semana' })
+    expect(within(lista).getByRole('link', { name: 'Repartir 1 lead pendiente' })).toHaveAttribute('href', '#/derivaciones')
+    fireEvent.pointerDown(document.body)
+    expect(disparador).toHaveAttribute('aria-expanded', 'false')
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
index 82c45046..ad17b04f 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
@@ -12,7 +12,7 @@
 // clásica ./supervisor.tsx, que sigue siendo también el rollback de una línea.
 // Meta, reparto, agenda y TC: ./datos-supervisor.ts, compartido con ella.
 import { useEffect, useId, useMemo, useRef, useState, type JSX } from 'react'
-import { AlertTriangle, ChevronRight, Inbox, ListChecks, RefreshCw, Target, Users, UsersRound, Wallet } from 'lucide-react'
+import { AlertTriangle, ChevronRight, Inbox, ListChecks, Target, Users, UsersRound, Wallet } from 'lucide-react'
 import { Card, CardContent } from '@/components/ui/card'
 import { Avatar } from '@/components/ui/avatar'
 import { Badge } from '@/components/ui/badge'
@@ -26,7 +26,7 @@ import { AccionesContacto } from '@/components/app/contacto'
 import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
 import { DesgloseMonedas } from '@/components/common/desglose-monedas'
 import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
-import { estadoCasoSupervision, momentoCaso } from '@/lib/cola-supervision'
+import { estadoCasoSupervision, momentoCaso, nombresCortos } from '@/lib/cola-supervision'
 import { conteoSemaforoEquipo, lecturaAnalista, type LecturaAnalista } from '@/lib/senal-equipo'
 import { candidatosDeHoy, partesDeCosa, tresCosasDeHoy, type CosaDeHoy } from '@/lib/tres-cosas'
 import { colorMeta, haceTexto } from '@/lib/inteligencia'
@@ -79,6 +79,31 @@ const COLOR_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
   atencion: SEMAFORO.atencion,
   neutro: SEMAFORO.neutro,
 }
+const TEXTO_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
+  critico: 'En rojo',
+  atencion: 'En ámbar',
+  neutro: 'Sin cartera abierta',
+}
+
+/**
+ * Marca del nivel con FORMA además de color (rojo y ámbar se confunden con
+ * protanopia): triángulo = rojo, punto lleno = ámbar, aro = neutro.
+ */
+function MarcaNivel({ nivel }: { nivel: LecturaAnalista['nivel'] }): JSX.Element {
+  if (nivel == null) return <span className="size-3 shrink-0" aria-hidden />
+  if (nivel === 'critico') {
+    return <AlertTriangle data-testid="equipo-semaforo" data-nivel={nivel} className="size-3 shrink-0" style={{ color: SEMAFORO.critico }} aria-hidden />
+  }
+  return (
+    <span
+      data-testid="equipo-semaforo"
+      data-nivel={nivel}
+      className={cn('size-2 shrink-0 rounded-full', nivel === 'neutro' && 'border-2 bg-transparent')}
+      style={nivel === 'neutro' ? { borderColor: COLOR_NIVEL.neutro } : { background: COLOR_NIVEL[nivel] }}
+      aria-hidden
+    />
+  )
+}
 
 export function HoySupervisorMando(): JSX.Element {
   const modo = useModoSla()
@@ -100,8 +125,17 @@ function PuestoDeMando(): JSX.Element {
 
   const [pestana, setPestana] = useState<PestanaMando>('pendientes')
   const [analistaElegido, setAnalistaId] = useState<string | null>(null)
-  // Un analista que sale del equipo no deja la cola filtrada por un id oculto.
-  const analistaId = analistaElegido != null && ambito.vendedores.some((m) => m.perfil_id === analistaElegido)
+  // Analistas SELECCIONABLES del equipo (no las filas cargadas): los chips no
+  // dependen de lo que haya traído la página ni prometen conteos del cliente.
+  const analistas = useMemo(
+    () => ambito.vendedores
+      .filter((m) => m.activo && m.rol_crm === 'vendedor')
+      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
+    [ambito.vendedores],
+  )
+  // El filtro vale solo para quien sigue siendo seleccionable: quien sale, se
+  // desactiva o cambia de rol no deja la cola filtrada por un id sin chip.
+  const analistaId = analistaElegido != null && analistas.some((m) => m.perfil_id === analistaElegido)
     ? analistaElegido
     : null
   const [anuncio, setAnuncio] = useState('')
@@ -109,6 +143,7 @@ function PuestoDeMando(): JSX.Element {
   const [errorApertura, setErrorApertura] = useState(false)
   const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
   const [detalleAbierto, setDetalleAbierto] = useState(false)
+  const tituloDetalle = useRef<HTMLSpanElement>(null)
 
   const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
   const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
@@ -121,24 +156,27 @@ function PuestoDeMando(): JSX.Element {
   const revisionVigente = modo.data?.control_revision
   const esVigente = (p: typeof pagina) => p != null && p.modo === 'activo' && p.control_revision === revisionVigente
   const paginaVigente = esVigente(pagina) ? pagina : undefined
-  // Las decisiones del día miran a TODO el equipo: sin filtro por analista.
-  // Sin filtro es la MISMA clave que la cola (TanStack la comparte); con
-  // filtro es la consulta que la cola tenía antes de filtrar.
-  const consultaEquipo = useColaSlaPagina({ senal: pestana, etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
+  // Las decisiones del día miran a TODO el equipo y a una clave ESTABLE: los
+  // `totales` no dependen de la señal (cola_accion_v2_fn filtra por etapa y
+  // analista antes de contarlos), así que cambiar de pestaña no deja la
+  // banda sin su fuente mientras llega otra respuesta. Con «Para atender
+  // ahora» y sin analista, es la misma clave que la cola: TanStack la comparte.
+  const consultaEquipo = useColaSlaPagina({ senal: 'pendientes', etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
   const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
   const paginaEquipoVigente = esVigente(paginaEquipo) ? paginaEquipo : undefined
 
   // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
   // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
   const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
-  // Analistas del equipo (no las filas cargadas): los chips no dependen de
-  // lo que haya traído la página y no prometen conteos del lado cliente.
-  const analistas = useMemo(
-    () => ambito.vendedores
-      .filter((m) => m.activo && m.rol_crm === 'vendedor')
-      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
-    [ambito.vendedores],
+  // Nombres cortos sin ambigüedad para chips y la columna del analista.
+  const cortos = useMemo(
+    () => nombresCortos([
+      ...analistas.map((m) => m.nombre_completo),
+      ...(paginaVigente?.items ?? []).map((i) => i.lead.analista_nombre ?? ''),
+    ]),
+    [analistas, paginaVigente],
   )
+  const corto = (nombre: string | null | undefined) => (nombre ? cortos.get(nombre.trim()) ?? primerNombre(nombre) : '')
   const nombreAnalista = analistaId != null
     ? ambito.vendedores.find((m) => m.perfil_id === analistaId)?.nombre_completo ?? null
     : null
@@ -246,7 +284,8 @@ function PuestoDeMando(): JSX.Element {
         if (cosa.vendedorId != null) {
           const r = rezagosConfirmados.get(cosa.vendedorId)
           if (!r) return null
-          return `En 7 días: ${numero(r.no_asistio)} sin asistir · ${numero(r.vencidas)} tareas vencidas · ${numero(r.leads_sin_accion)} sin próxima acción.`
+          const plural = (n: number, uno: string, varios: string) => `${numero(n)} ${n === 1 ? uno : varios}`
+          return `En 7 días: ${plural(r.no_asistio, 'cita sin asistir', 'citas sin asistir')} · ${plural(r.vencidas, 'tarea vencida', 'tareas vencidas')} · ${plural(r.leads_sin_accion, 'lead sin próxima acción', 'leads sin próxima acción')}.`
         }
         const nombres = (datos.agendaConfirmada?.vendedores ?? [])
           .filter((v) => v.rol === 'vendedor' && v.activo
@@ -261,26 +300,31 @@ function PuestoDeMando(): JSX.Element {
     }
   }
 
+  // Los errores del mes (meta, cumplimiento, conversión, TC) también se
+  // avisan aquí: la franja muestra «—» y el aviso no espera a abrir «Detalle».
   const errorIndicadores = !datos.sesionReal
     ? false
-    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error)
+    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error || datos.hayErrorMensual)
   const reintentarIndicadores = () => {
     if (datos.resumenOp.error) void datos.resumenOp.recargar()
     if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
+    if (datos.hayErrorMensual) datos.reintentarMensual()
   }
 
   // ── 3 · Consulta: las cifras de siempre, en una línea; el detalle, encima ──
   const agendaResumen = datos.agendaConfirmada ? resumenAgenda(datos.agendaConfirmada.vendedores) : null
   const filaCapital = datos.filasMeta[0]
   const metaTexto = filaCapital == null || filaCapital.sinDato ? '—' : `${Math.round(filaCapital.pct)} %`
-  const conversionTexto = datos.conversionConfirmada == null ? '—' : porcentajeConversionCanonica(datos.conversionConfirmada)
+  const conversionTexto = datos.conversionMensualError || datos.conversionConfirmada == null
+    ? '—'
+    : porcentajeConversionCanonica(datos.conversionConfirmada)
   const pronostico = datos.capitalPronostico
   // En la franja, compacto (S/ 1.48 M); la cifra exacta vive en el KPI del detalle.
   const pronosticoCorto = pronostico && datos.resumen
     ? moneyCompacta(pronostico.soloDolares ? datos.resumen.capital.asignado.usd : datos.resumen.capital.asignado.pen, pronostico.moneda)
     : '—'
 
-  const tituloCola = nombreAnalista ? `Pendientes de ${primerNombre(nombreAnalista)}` : 'Pendientes del equipo'
+  const tituloCola = nombreAnalista ? `Pendientes de ${corto(nombreAnalista)}` : 'Pendientes del equipo'
 
   return (
     <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
@@ -290,25 +334,25 @@ function PuestoDeMando(): JSX.Element {
         <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
           <div className="flex items-center justify-between gap-4">
             <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
-            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} />}
+            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} etiquetaReparto={datos.etiquetaAccesoReparto} />}
           </div>
-          {fuentesCaidas.length > 0 && (
-            <div role="alert" className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-destructive/30 bg-card px-4 py-2.5">
-              <p className="text-xs">
-                Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
-              </p>
-              <Button variant="outline" size="sm" onClick={reintentarDecisiones}>
-                <RefreshCw aria-hidden /> Reintentar
-              </Button>
-            </div>
-          )}
-          {cosas.length === 0 ? (
+          <AvisoDegradacion activo={fuentesCaidas.length > 0} queReintenta="de las decisiones del día" onReintentar={reintentarDecisiones}>
+            Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
+          </AvisoDegradacion>
+          {/* Sin todas las fuentes no se ORDENA: una tarjeta ámbar no ocupa el
+              puesto de una roja que aún no llegó. Con una fuente caída sí se
+              muestra lo confirmado, bajo el aviso de que está incompleto. */}
+          {!fuentesListas && fuentesCaidas.length === 0 ? (
+            <Card>
+              <CardContent className="py-4">
+                <p role="status" className="text-sm text-muted-foreground">Revisando las decisiones del día…</p>
+              </CardContent>
+            </Card>
+          ) : cosas.length === 0 ? (
             fuentesCaidas.length > 0 ? null : (
               <Card>
                 <CardContent className="py-4">
-                  <p role="status" className="text-sm text-muted-foreground">
-                    {fuentesListas ? 'Nada que decidir ahora mismo.' : 'Revisando las decisiones del día…'}
-                  </p>
+                  <p role="status" className="text-sm text-muted-foreground">Nada que decidir ahora mismo.</p>
                 </CardContent>
               </Card>
             )
@@ -340,62 +384,62 @@ function PuestoDeMando(): JSX.Element {
       </AvisoDegradacion>
 
       {/* ── 2 · Cola del seguimiento + Equipo hoy ── */}
+      <h2 className="sr-only">Pendientes y equipo</h2>
       <div className="grid gap-4 lg:grid-cols-5">
         <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
-          <SectionHead icon={ListChecks} title={tituloCola} />
+          <SectionHead
+            icon={ListChecks}
+            title={tituloCola}
+            className="flex-wrap gap-y-2"
+            right={modo.activo ? (
+              <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
+                {PESTANAS.map((p, indice) => {
+                  const n = conteoPestana(p.id)
+                  return (
+                    <button
+                      key={p.id}
+                      id={`${idPanelCola}-tab-${p.id}`}
+                      type="button"
+                      role="tab"
+                      aria-selected={pestana === p.id}
+                      aria-controls={`${idPanelCola}-panel`}
+                      aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
+                      tabIndex={pestana === p.id ? 0 : -1}
+                      onClick={() => elegirPestana(p.id)}
+                      onKeyDown={(e) => {
+                        const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
+                          : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
+                          : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
+                        if (destino == null) return
+                        e.preventDefault()
+                        const siguiente = PESTANAS[destino]
+                        if (!siguiente) return
+                        elegirPestana(siguiente.id)
+                        document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
+                      }}
+                      className={cn(
+                        'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
+                        pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
+                      )}
+                    >
+                      {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
+                    </button>
+                  )
+                })}
+              </div>
+            ) : undefined}
+          />
           {!modo.activo ? (
             <CardContent className="pb-5 pt-0">
-              {modo.error ? (
-                <div role="alert" className="flex flex-wrap items-center justify-between gap-3">
-                  <p className="text-sm">No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.</p>
-                  <Button variant="outline" size="sm" onClick={() => void modo.refetch()}>
-                    <RefreshCw aria-hidden /> Reintentar
-                  </Button>
-                </div>
-              ) : (
+              <AvisoDegradacion activo={modo.error != null} queReintenta="del seguimiento" onReintentar={() => void modo.refetch()}>
+                No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.
+              </AvisoDegradacion>
+              {modo.error == null && (
                 <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
               )}
             </CardContent>
           ) : (
             <>
-              <div className="flex flex-wrap items-center gap-2 px-5 pb-2.5">
-                <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
-                  {PESTANAS.map((p, indice) => {
-                    const n = conteoPestana(p.id)
-                    return (
-                      <button
-                        key={p.id}
-                        id={`${idPanelCola}-tab-${p.id}`}
-                        type="button"
-                        role="tab"
-                        aria-selected={pestana === p.id}
-                        aria-controls={`${idPanelCola}-panel`}
-                        aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
-                        tabIndex={pestana === p.id ? 0 : -1}
-                        onClick={() => elegirPestana(p.id)}
-                        onKeyDown={(e) => {
-                          const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
-                            : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
-                            : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
-                          if (destino == null) return
-                          e.preventDefault()
-                          const siguiente = PESTANAS[destino]
-                          if (!siguiente) return
-                          elegirPestana(siguiente.id)
-                          document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
-                        }}
-                        className={cn(
-                          'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
-                          pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
-                        )}
-                      >
-                        {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
-                      </button>
-                    )
-                  })}
-                </div>
-              </div>
-
               {analistas.length > 0 && (
                 <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
                   <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
@@ -404,7 +448,7 @@ function PuestoDeMando(): JSX.Element {
                     aria-pressed={analistaId == null}
                     onClick={() => elegirAnalista(null)}
                     className={cn(
-                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
+                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                       analistaId == null ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
                     )}
                   >
@@ -418,11 +462,11 @@ function PuestoDeMando(): JSX.Element {
                       aria-label={m.nombre_completo}
                       onClick={() => elegirAnalista(m.perfil_id)}
                       className={cn(
-                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
+                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                         analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
                       )}
                     >
-                      {primerNombre(m.nombre_completo)}
+                      {corto(m.nombre_completo)}
                     </button>
                   ))}
                 </div>
@@ -438,14 +482,12 @@ function PuestoDeMando(): JSX.Element {
                 tabIndex={paginaVigente && paginaVigente.items.length > 0 ? undefined : 0}
                 className="flex flex-1 flex-col"
               >
-                {consultaCola.error ? (
-                  <div role="alert" className="flex flex-wrap items-center justify-between gap-3 border-t border-border/60 px-5 py-4">
-                    <p className="text-sm">No se pudo cargar la cola. Los pendientes todavía no están confirmados.</p>
-                    <Button variant="outline" size="sm" onClick={() => void consultaCola.refetch()}>
-                      <RefreshCw aria-hidden /> Reintentar
-                    </Button>
-                  </div>
-                ) : !pagina ? (
+                <div className={cn(consultaCola.error && 'border-t border-border/60 px-5 py-4')}>
+                  <AvisoDegradacion activo={consultaCola.error != null} queReintenta="de los pendientes del equipo" onReintentar={() => void consultaCola.refetch()}>
+                    No se pudo cargar la cola. Los pendientes todavía no están confirmados.
+                  </AvisoDegradacion>
+                </div>
+                {consultaCola.error ? null : !pagina ? (
                   <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
                 ) : !paginaVigente ? (
                   <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
@@ -455,16 +497,18 @@ function PuestoDeMando(): JSX.Element {
                   </p>
                 ) : paginaVigente.items.length === 0 ? (
                   <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
-                    {nombreAnalista ? `${primerNombre(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
+                    {nombreAnalista ? `${corto(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
                   </p>
                 ) : (
-                  <ul aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
+                  // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+                  <ul role="list" aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
                     {paginaVigente.items.map((item) => {
                       const leadStore = leadPorId.get(item.lead_id)
                       const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
-                      const analistaFila = item.lead.analista_nombre ? primerNombre(item.lead.analista_nombre) : 'Sin analista'
+                      const analistaFila = item.lead.analista_nombre ? corto(item.lead.analista_nombre) : 'Sin analista'
                       const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
                       const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
+                      const urgente = item.severidad === 'critica'
                       return (
                         <li
                           key={item.lead_id}
@@ -474,27 +518,41 @@ function PuestoDeMando(): JSX.Element {
                         >
                           <button
                             type="button"
-                            disabled={abriendo !== null}
+                            // aria-disabled y NO disabled: un botón enfocado que se deshabilita
+                            // suelta el foco a <body> y la ficha lo devolvía ahí al cerrarse.
+                            // La guarda de abrirFicha ya evita el doble envío.
+                            aria-disabled={abriendo !== null || undefined}
                             onClick={() => void abrirFicha(item.lead_id)}
-                            // El nombre dicta TODO lo visible (dueño, estado, tiempo, monto):
-                            // un lector de pantalla no puede perder lo que se ve.
-                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}: ${estado}${monto ? `, ${monto}` : ''}`}
-                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 disabled:cursor-wait"
+                            // El nombre dicta TODO lo visible (dueño, urgencia, estado,
+                            // tiempo, monto): un lector de pantalla no puede perder lo que se ve.
+                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}${urgente ? ', urgente' : ''}: ${estado}${monto ? `, ${monto}` : ''}`}
+                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 aria-disabled:cursor-wait"
                           >
                             {analistaId == null && (
-                              <span className="flex w-[118px] shrink-0 items-center gap-2">
+                              <span className="hidden w-[118px] shrink-0 items-center gap-2 sm:flex">
                                 <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
                                 <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
                               </span>
                             )}
                             <span className="min-w-0 flex-1 leading-tight">
                               <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
-                              <span className="block truncate text-xs text-muted-foreground">{estado}</span>
+                              <span className="flex min-w-0 items-center gap-1 text-xs text-muted-foreground-strong">
+                                {urgente && <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />}
+                                <span className="truncate">
+                                  {analistaId == null && <span className="sm:hidden">{analistaFila} · </span>}
+                                  {estado}
+                                </span>
+                              </span>
                             </span>
                             {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
                             <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                           </button>
-                          {leadStore && <AccionesContacto lead={leadStore} compacto />}
+                          {leadStore && (
+                            // Las acciones compactas miden 28 px: se llevan al mínimo de 36 (40 táctil).
+                            <div className="[&_a]:min-h-9 [&_button]:min-h-9 pointer-coarse:[&_a]:min-h-10 pointer-coarse:[&_button]:min-h-10">
+                              <AccionesContacto lead={leadStore} compacto />
+                            </div>
+                          )}
                         </li>
                       )
                     })}
@@ -506,7 +564,7 @@ function PuestoDeMando(): JSX.Element {
                       ? `${numero(paginaVigente.items.length)} de ${numero(paginaVigente.total_items)}`
                       : ''}
                   </span>
-                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
+                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
                     Ver todo en Seguimiento <ChevronRight className="size-3.5" aria-hidden />
                   </a>
                 </div>
@@ -521,8 +579,8 @@ function PuestoDeMando(): JSX.Element {
             icon={UsersRound}
             title="Equipo hoy"
             right={(
-              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center rounded-md px-1 text-xs font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
-                Mi equipo hoy →
+              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-1 text-xs font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
+                Mi equipo hoy <span aria-hidden>→</span>
               </a>
             )}
           />
@@ -534,14 +592,11 @@ function PuestoDeMando(): JSX.Element {
                 : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
             </p>
           )}
-          {datos.errorAgenda && (
-            <div role="alert" className="mx-5 mb-2 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-warning-text/30 bg-warning-text/5 px-3 py-2">
-              <p className="text-xs">La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.</p>
-              <Button variant="outline" size="sm" onClick={datos.recargarAgenda}>
-                <RefreshCw aria-hidden /> Reintentar
-              </Button>
-            </div>
-          )}
+          <div className={cn(datos.errorAgenda && 'mx-5 mb-2')}>
+            <AvisoDegradacion activo={datos.errorAgenda != null} queReintenta="de la agenda del equipo" onReintentar={datos.recargarAgenda}>
+              La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.
+            </AvisoDegradacion>
+          </div>
           {rank == null ? (
             <CardContent className="pb-5 pt-0">
               <p className="text-sm text-muted-foreground">
@@ -555,7 +610,8 @@ function PuestoDeMando(): JSX.Element {
               <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
             </CardContent>
           ) : (
-            <ul aria-label="Analistas del equipo" className="border-t border-border/60">
+            // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+            <ul role="list" aria-label="Analistas del equipo" className="border-t border-border/60">
               {rank.map((r) => {
                 const id = r.m.perfil_id
                 const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
@@ -567,6 +623,13 @@ function PuestoDeMando(): JSX.Element {
                     : rezago != null ? 'Al día' : `Última actividad ${haceTexto(r.diasSinActividadMax)}`)
                 const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
                 const idDetalle = `${idPanelCola}-equipo-${id}`
+                // PEN y USD jamás se suman sin decirlo: el nombre lleva el desglose.
+                const desglose = r.capitalUSD > 0
+                  ? cap.tc != null
+                    ? ` (${moneyK(r.capitalPEN, 'PEN')} más ${moneyK(r.capitalUSD, 'USD')})`
+                    : `, más ${moneyK(r.capitalUSD, 'USD')} aparte sin tipo de cambio`
+                  : ''
+                const nivelTexto = lectura.nivel != null ? `${TEXTO_NIVEL[lectura.nivel]}. ` : ''
                 const conversion = r.conversion == null
                   ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
                   : `${textoConversionOperativa(r.conversion)} conversión`
@@ -576,16 +639,14 @@ function PuestoDeMando(): JSX.Element {
                       type="button"
                       aria-expanded={abierto}
                       aria-controls={idDetalle}
-                      aria-label={`${r.m.nombre_completo}: ${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
+                      aria-label={`${r.m.nombre_completo}: ${nivelTexto}${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}${desglose}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
                       onClick={() => elegirAnalista(id)}
                       className={cn(
                         'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
                         abierto && 'bg-accent/[0.08]',
                       )}
                     >
-                      {lectura.nivel != null
-                        ? <span data-testid="equipo-semaforo" data-nivel={lectura.nivel} className="size-2 shrink-0 rounded-full" style={{ background: COLOR_NIVEL[lectura.nivel] }} aria-hidden />
-                        : <span className="size-2 shrink-0" aria-hidden />}
+                      <MarcaNivel nivel={lectura.nivel} />
                       <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
                       <span className="min-w-0 flex-1 leading-tight">
                         <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
@@ -593,7 +654,7 @@ function PuestoDeMando(): JSX.Element {
                       </span>
                       <span className="shrink-0 text-right leading-tight">
                         <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
-                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
+                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto tono="fuerte" />
                       </span>
                       <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierto ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
                     </button>
@@ -627,7 +688,8 @@ function PuestoDeMando(): JSX.Element {
       {/* ── 3 · Consulta: cifras en una línea; «Detalle» abre todo lo demás ── */}
       <section aria-label="Consulta" className="flex min-h-12 flex-wrap items-center gap-x-5 gap-y-1.5 rounded-xl border border-border bg-card px-5 py-2">
         <span className="text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground-strong" aria-hidden>Consulta</span>
-        <ul aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
+        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
+        <ul role="list" aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
           <li>
             <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
             {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
@@ -638,16 +700,19 @@ function PuestoDeMando(): JSX.Element {
           <li aria-hidden className="h-[18px] w-px bg-border" />
           <li><strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días</li>
           <li><strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas</li>
-          <li>
+          <li className="inline-flex items-center gap-1">
+            {agendaResumen && agendaResumen.noAsistio >= 2 && (
+              <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />
+            )}
             <strong
               className="font-extrabold"
               style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
             >
               {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
-            </strong> no asistió
+            </strong> {agendaResumen?.noAsistio === 1 ? 'cita sin asistir' : 'citas sin asistir'}
           </li>
         </ul>
-        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent" onClick={() => setDetalleAbierto(true)}>
+        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent pointer-coarse:min-h-10" onClick={() => setDetalleAbierto(true)}>
           Detalle
         </Button>
       </section>
@@ -655,10 +720,12 @@ function PuestoDeMando(): JSX.Element {
       <Dialog
         open={detalleAbierto}
         onClose={() => setDetalleAbierto(false)}
+        focoInicial={tituloDetalle}
         className="w-[1180px] max-h-[88vh] max-w-[94vw]"
       >
         <DialogHeader>
-          <DialogTitle>Detalle del equipo</DialogTitle>
+          {/* El foco entra por el título, no en mitad de la rejilla de indicadores. */}
+          <DialogTitle><span ref={tituloDetalle} tabIndex={-1} className="outline-none">Detalle del equipo</span></DialogTitle>
           <DialogDescription>Indicadores, cumplimiento del mes y agenda de los últimos 7 días.</DialogDescription>
         </DialogHeader>
         <DialogBody className="space-y-4">
@@ -699,7 +766,7 @@ function PuestoDeMando(): JSX.Element {
             />
             <a
               href={hashDe('derivaciones')}
-              aria-label={datos.etiquetaAccesoReparto}
+              aria-label={`Por repartir: ${datos.etiquetaAccesoReparto}`}
               className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
             >
               <KpiCard
@@ -736,11 +803,9 @@ function PuestoDeMando(): JSX.Element {
                 <p className="text-[11px] text-muted-foreground-strong">
                   El capital en dólares entra al total convertido a tipo de cambio real. El pronóstico no cuenta como cumplimiento.
                 </p>
-                {datos.hayErrorMensual && (
-                  <Button variant="ghost" size="sm" onClick={datos.reintentarMensual}>
-                    Reintentar
-                  </Button>
-                )}
+                <AvisoDegradacion activo={datos.hayErrorMensual} queReintenta="de la meta y el cumplimiento del mes" onReintentar={datos.reintentarMensual}>
+                  Parte del cumplimiento del mes no se pudo cargar: se muestra «—» donde falta el dato.
+                </AvisoDegradacion>
               </CardContent>
             </Card>
             <div className="min-w-0 lg:col-span-3">
@@ -764,7 +829,7 @@ function PuestoDeMando(): JSX.Element {
           </p>
         </DialogBody>
         <DialogFooter>
-          <Button variant="outline" size="sm" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
+          <Button variant="outline" size="sm" className="min-h-9" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
         </DialogFooter>
       </Dialog>
     </div>
@@ -777,10 +842,10 @@ function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
   onVerPrimeraGestion: () => void
   etiquetaReparto: string
 }): JSX.Element {
-  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
+  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
   if (cosa.id === 'primera_gestion') {
     return (
-      <button type="button" className={clase} aria-label={`Ver las ${cosa.texto} en la cola`} onClick={onVerPrimeraGestion}>
+      <button type="button" className={clase} aria-label={`Ver en la cola: ${cosa.texto}`} onClick={onVerPrimeraGestion}>
         Ver <ChevronRight className="size-3.5" aria-hidden />
       </button>
     )
@@ -827,7 +892,7 @@ function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVe
       className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')}
       style={{ borderLeftColor: SEV_BORDE[cosa.severidad] }}
     >
-      <div className="flex items-center gap-2 py-2 pl-4 pr-3">
+      <div className="flex flex-wrap items-center gap-2 py-2 pl-4 pr-3">
         <button
           type="button"
           aria-expanded={abierta}
@@ -843,7 +908,7 @@ function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVe
             <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: SEV_TEXTO_COLOR[cosa.severidad] }}>
               {SEV_TEXTO[cosa.severidad]}
             </span>
-            <span className="block truncate text-[15px] font-bold" title={resto}>{resto}</span>
+            <span className="line-clamp-2 break-words text-[15px] font-bold">{resto}</span>
           </span>
           <ChevronRight
             className={cn('size-4 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')}
@@ -860,7 +925,11 @@ function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVe
 }
 
 /** «Esta semana · N»: lo que no entró en las tres tarjetas. Esc y clic fuera lo cierran. */
-function EstaSemana({ cosas, onVerPrimeraGestion }: { cosas: CosaDeHoy[]; onVerPrimeraGestion: () => void }): JSX.Element {
+function EstaSemana({ cosas, onVerPrimeraGestion, etiquetaReparto }: {
+  cosas: CosaDeHoy[]
+  onVerPrimeraGestion: () => void
+  etiquetaReparto: string
+}): JSX.Element {
   const [abierto, setAbierto] = useState(false)
   const contenedor = useRef<HTMLDivElement>(null)
   const disparador = useRef<HTMLButtonElement>(null)
@@ -877,11 +946,19 @@ function EstaSemana({ cosas, onVerPrimeraGestion }: { cosas: CosaDeHoy[]; onVerP
       setAbierto(false)
       if (contenedor.current?.contains(document.activeElement)) disparador.current?.focus()
     }
+    // Tabular fuera del popover lo cierra: si no, quedaría encima de las
+    // tarjetas que reciben el foco a continuación (WCAG 2.4.11).
+    const nodo = contenedor.current
+    const salida = (e: FocusEvent) => {
+      if (e.relatedTarget instanceof Node && !nodo?.contains(e.relatedTarget)) setAbierto(false)
+    }
     document.addEventListener('pointerdown', fuera)
     document.addEventListener('keydown', escape)
+    nodo?.addEventListener('focusout', salida)
     return () => {
       document.removeEventListener('pointerdown', fuera)
       document.removeEventListener('keydown', escape)
+      nodo?.removeEventListener('focusout', salida)
     }
   }, [abierto])
   return (
@@ -892,13 +969,14 @@ function EstaSemana({ cosas, onVerPrimeraGestion }: { cosas: CosaDeHoy[]; onVerP
         aria-expanded={abierto}
         aria-controls={idLista}
         onClick={() => setAbierto((v) => !v)}
-        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
+        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
       >
         <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
         Esta semana · {cosas.length}
         <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
       </button>
-      <ul
+      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
+      <ul role="list"
         id={idLista}
         hidden={!abierto}
         aria-label="Decisiones para esta semana"
@@ -910,7 +988,7 @@ function EstaSemana({ cosas, onVerPrimeraGestion }: { cosas: CosaDeHoy[]; onVerP
             <span className="min-w-0 flex-1">
               <span className="sr-only">{SEV_TEXTO[c.severidad]}: </span>{c.texto}
             </span>
-            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={`Repartir: ${c.texto}`} />
+            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={etiquetaReparto} />
           </li>
         ))}
       </ul>
```

## `app/src/screens/hoy/supervisor-mando.tsx` (estado FINAL completo)
```
     1	// Hoy · SUPERVISOR — puesto de mando en UNA pantalla (diseño 2a, 27/09/2026).
     2	// Plan aprobado por Miguel y refutado por Codex: nota del vault «Hoy del
     3	// supervisor - puesto de mando en una pantalla, plan (2026-09-27)».
     4	//
     5	// Producción corre el seguimiento en modo ACTIVO desde el 07/09/2026: la cola
     6	// legada (cola_accion_fn) no se consulta y la pantalla clásica solo enlazaba
     7	// al módulo Seguimiento. Aquí la cola sale de crm.cola_accion_v2_fn —la misma
     8	// del módulo—, filtrada por analista EN EL SERVIDOR: sus `totales` respetan el
     9	// filtro, así que los números cuadran sin contar filas en el navegador.
    10	//
    11	// Modo legado (demo, o seguimiento apagado por gerencia) → la pantalla
    12	// clásica ./supervisor.tsx, que sigue siendo también el rollback de una línea.
    13	// Meta, reparto, agenda y TC: ./datos-supervisor.ts, compartido con ella.
    14	import { useEffect, useId, useMemo, useRef, useState, type JSX } from 'react'
    15	import { AlertTriangle, ChevronRight, Inbox, ListChecks, Target, Users, UsersRound, Wallet } from 'lucide-react'
    16	import { Card, CardContent } from '@/components/ui/card'
    17	import { Avatar } from '@/components/ui/avatar'
    18	import { Badge } from '@/components/ui/badge'
    19	import { Button } from '@/components/ui/button'
    20	import { Progress } from '@/components/ui/progress'
    21	import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
    22	import { KpiCard } from '@/components/common/kpi-card'
    23	import { SectionHead } from '@/components/common/section-head'
    24	import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
    25	import { AccionesContacto } from '@/components/app/contacto'
    26	import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
    27	import { DesgloseMonedas } from '@/components/common/desglose-monedas'
    28	import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
    29	import { estadoCasoSupervision, momentoCaso, nombresCortos } from '@/lib/cola-supervision'
    30	import { conteoSemaforoEquipo, lecturaAnalista, type LecturaAnalista } from '@/lib/senal-equipo'
    31	import { candidatosDeHoy, partesDeCosa, tresCosasDeHoy, type CosaDeHoy } from '@/lib/tres-cosas'
    32	import { colorMeta, haceTexto } from '@/lib/inteligencia'
    33	import { resumenAgenda } from '@/lib/agenda-equipo-vista'
    34	import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
    35	import { textoConversionOperativa } from '@/lib/metricas-vendedores'
    36	import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
    37	import { moneyCompacta, moneyK, numero, porcentajeConversionCanonica, primerNombre } from '@/lib/format'
    38	import { hashDe } from '@/lib/router'
    39	import { cn } from '@/lib/utils'
    40	import { usePanelesActions } from '@/lib/store-context'
    41	import { useAuth } from '@/lib/auth-context'
    42	import type { FiltrosSla } from '@/lib/sla-operacion'
    43	import { HoySupervisor } from './supervisor'
    44	import { useDatosSupervisor } from './datos-supervisor'
    45	import { AgendaEquipoPanel } from './agenda-equipo'
    46	import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
    47	
    48	/** Filas de la vista previa: lo demás vive en el módulo Seguimiento. */
    49	const COLA_VISIBLES = 7
    50	
    51	type PestanaMando = 'pendientes' | 'primera_atencion' | 'tareas_vencidas' | 'todas'
    52	const PESTANAS: ReadonlyArray<{ id: PestanaMando; label: string }> = [
    53	  { id: 'pendientes', label: 'Para atender ahora' },
    54	  { id: 'primera_atencion', label: 'Primera gestión' },
    55	  { id: 'tareas_vencidas', label: 'Tareas vencidas' },
    56	  { id: 'todas', label: 'Todas' },
    57	]
    58	const VACIO_PESTANA: Record<PestanaMando, string> = {
    59	  pendientes: 'Nada para atender ahora: el equipo no tiene pendientes vencidos.',
    60	  primera_atencion: 'Ninguna primera gestión vencida.',
    61	  tareas_vencidas: 'Ninguna tarea vencida.',
    62	  todas: 'Sin oportunidades con acciones en el seguimiento.',
    63	}
    64	
    65	// La severidad TAMBIÉN en texto: el color nunca va solo.
    66	const SEV_TEXTO: Record<CosaDeHoy['severidad'], string> = { critica: 'Hoy', atencion: 'Esta semana' }
    67	const SEV_TEXTO_COLOR: Record<CosaDeHoy['severidad'], string> = { critica: 'var(--destructive-text)', atencion: 'var(--warning-text)' }
    68	const SEV_BORDE: Record<CosaDeHoy['severidad'], string> = { critica: SEMAFORO.critico, atencion: SEMAFORO.atencion }
    69	
    70	/** Chip de señal: el ámbar suave usa el token de TEXTO (el hex puro no llega a 4.5:1 sobre su tinte). */
    71	function ChipSenal({ texto, nivel }: { texto: string; nivel: 'critico' | 'atencion' }): JSX.Element {
    72	  return nivel === 'critico'
    73	    ? <Badge color={SEMAFORO.critico} variant="solid">{texto}</Badge>
    74	    : <Badge color="var(--warning-text)">{texto}</Badge>
    75	}
    76	
    77	const COLOR_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
    78	  critico: SEMAFORO.critico,
    79	  atencion: SEMAFORO.atencion,
    80	  neutro: SEMAFORO.neutro,
    81	}
    82	const TEXTO_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
    83	  critico: 'En rojo',
    84	  atencion: 'En ámbar',
    85	  neutro: 'Sin cartera abierta',
    86	}
    87	
    88	/**
    89	 * Marca del nivel con FORMA además de color (rojo y ámbar se confunden con
    90	 * protanopia): triángulo = rojo, punto lleno = ámbar, aro = neutro.
    91	 */
    92	function MarcaNivel({ nivel }: { nivel: LecturaAnalista['nivel'] }): JSX.Element {
    93	  if (nivel == null) return <span className="size-3 shrink-0" aria-hidden />
    94	  if (nivel === 'critico') {
    95	    return <AlertTriangle data-testid="equipo-semaforo" data-nivel={nivel} className="size-3 shrink-0" style={{ color: SEMAFORO.critico }} aria-hidden />
    96	  }
    97	  return (
    98	    <span
    99	      data-testid="equipo-semaforo"
   100	      data-nivel={nivel}
   101	      className={cn('size-2 shrink-0 rounded-full', nivel === 'neutro' && 'border-2 bg-transparent')}
   102	      style={nivel === 'neutro' ? { borderColor: COLOR_NIVEL.neutro } : { background: COLOR_NIVEL[nivel] }}
   103	      aria-hidden
   104	    />
   105	  )
   106	}
   107	
   108	export function HoySupervisorMando(): JSX.Element {
   109	  const modo = useModoSla()
   110	  const { yo } = useAuth()
   111	  if (modo.legado) return <HoySupervisor />
   112	  // Cambiar de identidad o de revisión del seguimiento remonta la pantalla:
   113	  // ningún filtro ni selección sobrevive sobre datos de otra (como
   114	  // SlaOperacionBoundary).
   115	  return <PuestoDeMando key={`${yo?.id ?? ''}|${yo?.rol ?? ''}|${modo.data?.control_revision ?? 'sin-revision'}`} />
   116	}
   117	
   118	function PuestoDeMando(): JSX.Element {
   119	  const modo = useModoSla()
   120	  const datos = useDatosSupervisor()
   121	  const { abrirLead } = usePanelesActions()
   122	  const { yo } = useAuth()
   123	  const { ambito, rank, tc, ahora } = datos
   124	  const idPanelCola = useId()
   125	
   126	  const [pestana, setPestana] = useState<PestanaMando>('pendientes')
   127	  const [analistaElegido, setAnalistaId] = useState<string | null>(null)
   128	  // Analistas SELECCIONABLES del equipo (no las filas cargadas): los chips no
   129	  // dependen de lo que haya traído la página ni prometen conteos del cliente.
   130	  const analistas = useMemo(
   131	    () => ambito.vendedores
   132	      .filter((m) => m.activo && m.rol_crm === 'vendedor')
   133	      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
   134	    [ambito.vendedores],
   135	  )
   136	  // El filtro vale solo para quien sigue siendo seleccionable: quien sale, se
   137	  // desactiva o cambia de rol no deja la cola filtrada por un id sin chip.
   138	  const analistaId = analistaElegido != null && analistas.some((m) => m.perfil_id === analistaElegido)
   139	    ? analistaElegido
   140	    : null
   141	  const [anuncio, setAnuncio] = useState('')
   142	  const [abriendo, setAbriendo] = useState<string | null>(null)
   143	  const [errorApertura, setErrorApertura] = useState(false)
   144	  const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
   145	  const [detalleAbierto, setDetalleAbierto] = useState(false)
   146	  const tituloDetalle = useRef<HTMLSpanElement>(null)
   147	
   148	  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
   149	  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
   150	  // Fail-closed: TanStack conserva la última respuesta tras un refetch
   151	  // fallido; con error, la cola NO se muestra como vigente.
   152	  const pagina = consultaCola.error ? undefined : consultaCola.data
   153	  // Vigente = modo activo Y la MISMA revisión de reglas que el modo: la caché
   154	  // de TanStack no conoce la revisión y, al remontar, podría servir una página
   155	  // calculada con las reglas anteriores mientras refresca.
   156	  const revisionVigente = modo.data?.control_revision
   157	  const esVigente = (p: typeof pagina) => p != null && p.modo === 'activo' && p.control_revision === revisionVigente
   158	  const paginaVigente = esVigente(pagina) ? pagina : undefined
   159	  // Las decisiones del día miran a TODO el equipo y a una clave ESTABLE: los
   160	  // `totales` no dependen de la señal (cola_accion_v2_fn filtra por etapa y
   161	  // analista antes de contarlos), así que cambiar de pestaña no deja la
   162	  // banda sin su fuente mientras llega otra respuesta. Con «Para atender
   163	  // ahora» y sin analista, es la misma clave que la cola: TanStack la comparte.
   164	  const consultaEquipo = useColaSlaPagina({ senal: 'pendientes', etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
   165	  const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
   166	  const paginaEquipoVigente = esVigente(paginaEquipo) ? paginaEquipo : undefined
   167	
   168	  // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
   169	  // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
   170	  const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
   171	  // Nombres cortos sin ambigüedad para chips y la columna del analista.
   172	  const cortos = useMemo(
   173	    () => nombresCortos([
   174	      ...analistas.map((m) => m.nombre_completo),
   175	      ...(paginaVigente?.items ?? []).map((i) => i.lead.analista_nombre ?? ''),
   176	    ]),
   177	    [analistas, paginaVigente],
   178	  )
   179	  const corto = (nombre: string | null | undefined) => (nombre ? cortos.get(nombre.trim()) ?? primerNombre(nombre) : '')
   180	  const nombreAnalista = analistaId != null
   181	    ? ambito.vendedores.find((m) => m.perfil_id === analistaId)?.nombre_completo ?? null
   182	    : null
   183	
   184	  const elegirAnalista = (id: string | null) => {
   185	    const siguiente = id === analistaId ? null : id
   186	    setAnalistaId(siguiente)
   187	    const nombre = siguiente == null ? null : ambito.vendedores.find((m) => m.perfil_id === siguiente)?.nombre_completo
   188	    setAnuncio(nombre ? `Mostrando los pendientes de ${primerNombre(nombre)}` : 'Mostrando los pendientes de todo el equipo')
   189	  }
   190	  const elegirPestana = (id: PestanaMando) => {
   191	    setPestana(id)
   192	    setErrorApertura(false)
   193	    // La tarjeta de primera gestión ES esa pestaña: si se va de ella, se cierra.
   194	    if (id !== 'primera_atencion' && decisionAbierta === 'primera_gestion') setDecisionAbierta(null)
   195	  }
   196	
   197	  async function abrirFicha(id: string) {
   198	    if (abriendo) return
   199	    setAbriendo(id)
   200	    setErrorApertura(false)
   201	    try {
   202	      if (await abrirLead(id) === false) setErrorApertura(true)
   203	    } catch {
   204	      setErrorApertura(true)
   205	    } finally {
   206	      setAbriendo(null)
   207	    }
   208	  }
   209	
   210	  const conteoPestana = (id: PestanaMando): number | null => {
   211	    if (!paginaVigente) return null
   212	    if (id === 'todas') return pestana === 'todas' ? paginaVigente.total_items : null
   213	    return paginaVigente.totales[id]
   214	  }
   215	
   216	  // ── Equipo hoy: UNA lectura por analista alimenta punto, cabecera y chips ──
   217	  const rezagosConfirmados = useMemo(
   218	    () => new Map((datos.agendaConfirmada?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
   219	    [datos.agendaConfirmada],
   220	  )
   221	  const lecturas = useMemo(
   222	    () => new Map((rank ?? []).map((r) => [r.m.perfil_id, lecturaAnalista(r, rezagosConfirmados.get(r.m.perfil_id))] as const)),
   223	    [rank, rezagosConfirmados],
   224	  )
   225	  const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])
   226	
   227	  // ── 1 · Decide primero: las mismas reglas de la franja clásica ──
   228	  // Fail-closed por fuente: un candidato solo existe si su fuente llegó bien,
   229	  // y «Nada que decidir» solo se afirma con TODAS las fuentes confirmadas.
   230	  const primeraGestionPendiente = paginaEquipoVigente?.totales.primera_atencion ?? null
   231	  const entradaCosas = {
   232	    cola: null,
   233	    totalPorRepartir: datos.resumenOp.error ? null : datos.totalPorRepartir,
   234	    esperaMasLargaReparto: datos.esperaMasLargaReparto,
   235	    vendedoresAgenda: datos.agendaConfirmada?.vendedores ?? [],
   236	    primeraGestionPendiente,
   237	  }
   238	  const candidatos = candidatosDeHoy(entradaCosas)
   239	  const cosas = tresCosasDeHoy(entradaCosas)
   240	  const estaSemana = candidatos.slice(cosas.length)
   241	  const fuentesCaidas = [
   242	    consultaEquipo.error ? 'el seguimiento' : null,
   243	    datos.errorAgenda ? 'la agenda' : null,
   244	    datos.resumenOp.error ? 'el reparto' : null,
   245	  ].filter((f): f is string => f != null)
   246	  const fuentesListas = paginaEquipoVigente != null
   247	    && datos.agendaConfirmada != null
   248	    && datos.resumen != null
   249	  const reintentarDecisiones = () => {
   250	    if (consultaEquipo.error) void consultaEquipo.refetch()
   251	    if (datos.errorAgenda) datos.recargarAgenda()
   252	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   253	  }
   254	
   255	  const alternarDecision = (cosa: CosaDeHoy) => {
   256	    const abrir = decisionAbierta !== cosa.id
   257	    setDecisionAbierta(abrir ? cosa.id : null)
   258	    if (cosa.id !== 'primera_gestion') return
   259	    // Primera gestión: la cola de abajo pasa a ESA pestaña, para todo el equipo.
   260	    if (abrir) {
   261	      setPestana('primera_atencion')
   262	      setAnalistaId(null)
   263	      setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   264	    } else if (pestana === 'primera_atencion') {
   265	      setPestana('pendientes')
   266	      setAnuncio('Mostrando los pendientes de todo el equipo')
   267	    }
   268	  }
   269	  const verPrimeraGestion = () => {
   270	    setDecisionAbierta('primera_gestion')
   271	    setPestana('primera_atencion')
   272	    setAnalistaId(null)
   273	    setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   274	    requestAnimationFrame(() => document.getElementById(`${idPanelCola}-tab-primera_atencion`)?.focus())
   275	  }
   276	
   277	  /** Una línea de contexto con datos YA confirmados; sin dato, nada. */
   278	  const contextoDe = (cosa: CosaDeHoy): string | null => {
   279	    switch (cosa.id) {
   280	      case 'primera_gestion':
   281	        return 'Revisa la primera gestión con cada analista: abajo quedan solo esos casos.'
   282	      case 'no_asistio':
   283	      case 'sin_accion': {
   284	        if (cosa.vendedorId != null) {
   285	          const r = rezagosConfirmados.get(cosa.vendedorId)
   286	          if (!r) return null
   287	          const plural = (n: number, uno: string, varios: string) => `${numero(n)} ${n === 1 ? uno : varios}`
   288	          return `En 7 días: ${plural(r.no_asistio, 'cita sin asistir', 'citas sin asistir')} · ${plural(r.vencidas, 'tarea vencida', 'tareas vencidas')} · ${plural(r.leads_sin_accion, 'lead sin próxima acción', 'leads sin próxima acción')}.`
   289	        }
   290	        const nombres = (datos.agendaConfirmada?.vendedores ?? [])
   291	          .filter((v) => v.rol === 'vendedor' && v.activo
   292	            && (cosa.id === 'no_asistio' ? v.no_asistio >= 2 : v.leads_sin_accion >= 3))
   293	          .map((v) => `${primerNombre(v.nombre)} (${cosa.id === 'no_asistio' ? v.no_asistio : v.leads_sin_accion})`)
   294	        return nombres.length > 0 ? nombres.join(' · ') : null
   295	      }
   296	      case 'por_repartir':
   297	        return 'Leads sin analista en tu bandeja. El reparto se hace en Derivar leads.'
   298	      default:
   299	        return null
   300	    }
   301	  }
   302	
   303	  // Los errores del mes (meta, cumplimiento, conversión, TC) también se
   304	  // avisan aquí: la franja muestra «—» y el aviso no espera a abrir «Detalle».
   305	  const errorIndicadores = !datos.sesionReal
   306	    ? false
   307	    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error || datos.hayErrorMensual)
   308	  const reintentarIndicadores = () => {
   309	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   310	    if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
   311	    if (datos.hayErrorMensual) datos.reintentarMensual()
   312	  }
   313	
   314	  // ── 3 · Consulta: las cifras de siempre, en una línea; el detalle, encima ──
   315	  const agendaResumen = datos.agendaConfirmada ? resumenAgenda(datos.agendaConfirmada.vendedores) : null
   316	  const filaCapital = datos.filasMeta[0]
   317	  const metaTexto = filaCapital == null || filaCapital.sinDato ? '—' : `${Math.round(filaCapital.pct)} %`
   318	  const conversionTexto = datos.conversionMensualError || datos.conversionConfirmada == null
   319	    ? '—'
   320	    : porcentajeConversionCanonica(datos.conversionConfirmada)
   321	  const pronostico = datos.capitalPronostico
   322	  // En la franja, compacto (S/ 1.48 M); la cifra exacta vive en el KPI del detalle.
   323	  const pronosticoCorto = pronostico && datos.resumen
   324	    ? moneyCompacta(pronostico.soloDolares ? datos.resumen.capital.asignado.usd : datos.resumen.capital.asignado.pen, pronostico.moneda)
   325	    : '—'
   326	
   327	  const tituloCola = nombreAnalista ? `Pendientes de ${corto(nombreAnalista)}` : 'Pendientes del equipo'
   328	
   329	  return (
   330	    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
   331	      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>
   332	
   333	      {modo.activo && (
   334	        <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
   335	          <div className="flex items-center justify-between gap-4">
   336	            <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
   337	            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} etiquetaReparto={datos.etiquetaAccesoReparto} />}
   338	          </div>
   339	          <AvisoDegradacion activo={fuentesCaidas.length > 0} queReintenta="de las decisiones del día" onReintentar={reintentarDecisiones}>
   340	            Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
   341	          </AvisoDegradacion>
   342	          {/* Sin todas las fuentes no se ORDENA: una tarjeta ámbar no ocupa el
   343	              puesto de una roja que aún no llegó. Con una fuente caída sí se
   344	              muestra lo confirmado, bajo el aviso de que está incompleto. */}
   345	          {!fuentesListas && fuentesCaidas.length === 0 ? (
   346	            <Card>
   347	              <CardContent className="py-4">
   348	                <p role="status" className="text-sm text-muted-foreground">Revisando las decisiones del día…</p>
   349	              </CardContent>
   350	            </Card>
   351	          ) : cosas.length === 0 ? (
   352	            fuentesCaidas.length > 0 ? null : (
   353	              <Card>
   354	                <CardContent className="py-4">
   355	                  <p role="status" className="text-sm text-muted-foreground">Nada que decidir ahora mismo.</p>
   356	                </CardContent>
   357	              </Card>
   358	            )
   359	          ) : (
   360	            <div className="grid gap-3.5 lg:grid-cols-3">
   361	              {cosas.map((cosa) => (
   362	                <TarjetaDecision
   363	                  key={cosa.id}
   364	                  cosa={cosa}
   365	                  abierta={decisionAbierta === cosa.id}
   366	                  contexto={contextoDe(cosa)}
   367	                  idContexto={`${idPanelCola}-decision-${cosa.id}`}
   368	                  onAlternar={() => alternarDecision(cosa)}
   369	                  onVerPrimeraGestion={verPrimeraGestion}
   370	                  etiquetaReparto={datos.etiquetaAccesoReparto}
   371	                />
   372	              ))}
   373	            </div>
   374	          )}
   375	        </section>
   376	      )}
   377	
   378	      <AvisoDegradacion
   379	        activo={errorIndicadores}
   380	        queReintenta="de los indicadores del equipo"
   381	        onReintentar={reintentarIndicadores}
   382	      >
   383	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   384	      </AvisoDegradacion>
   385	
   386	      {/* ── 2 · Cola del seguimiento + Equipo hoy ── */}
   387	      <h2 className="sr-only">Pendientes y equipo</h2>
   388	      <div className="grid gap-4 lg:grid-cols-5">
   389	        <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
   390	          <SectionHead
   391	            icon={ListChecks}
   392	            title={tituloCola}
   393	            className="flex-wrap gap-y-2"
   394	            right={modo.activo ? (
   395	              <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
   396	                {PESTANAS.map((p, indice) => {
   397	                  const n = conteoPestana(p.id)
   398	                  return (
   399	                    <button
   400	                      key={p.id}
   401	                      id={`${idPanelCola}-tab-${p.id}`}
   402	                      type="button"
   403	                      role="tab"
   404	                      aria-selected={pestana === p.id}
   405	                      aria-controls={`${idPanelCola}-panel`}
   406	                      aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
   407	                      tabIndex={pestana === p.id ? 0 : -1}
   408	                      onClick={() => elegirPestana(p.id)}
   409	                      onKeyDown={(e) => {
   410	                        const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
   411	                          : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
   412	                          : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
   413	                        if (destino == null) return
   414	                        e.preventDefault()
   415	                        const siguiente = PESTANAS[destino]
   416	                        if (!siguiente) return
   417	                        elegirPestana(siguiente.id)
   418	                        document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
   419	                      }}
   420	                      className={cn(
   421	                        'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   422	                        pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
   423	                      )}
   424	                    >
   425	                      {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
   426	                    </button>
   427	                  )
   428	                })}
   429	              </div>
   430	            ) : undefined}
   431	          />
   432	          {!modo.activo ? (
   433	            <CardContent className="pb-5 pt-0">
   434	              <AvisoDegradacion activo={modo.error != null} queReintenta="del seguimiento" onReintentar={() => void modo.refetch()}>
   435	                No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.
   436	              </AvisoDegradacion>
   437	              {modo.error == null && (
   438	                <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
   439	              )}
   440	            </CardContent>
   441	          ) : (
   442	            <>
   443	              {analistas.length > 0 && (
   444	                <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
   445	                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
   446	                  <button
   447	                    type="button"
   448	                    aria-pressed={analistaId == null}
   449	                    onClick={() => elegirAnalista(null)}
   450	                    className={cn(
   451	                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   452	                      analistaId == null ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   453	                    )}
   454	                  >
   455	                    Todos
   456	                  </button>
   457	                  {analistas.map((m) => (
   458	                    <button
   459	                      key={m.perfil_id}
   460	                      type="button"
   461	                      aria-pressed={analistaId === m.perfil_id}
   462	                      aria-label={m.nombre_completo}
   463	                      onClick={() => elegirAnalista(m.perfil_id)}
   464	                      className={cn(
   465	                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   466	                        analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   467	                      )}
   468	                    >
   469	                      {corto(m.nombre_completo)}
   470	                    </button>
   471	                  ))}
   472	                </div>
   473	              )}
   474	
   475	              {abriendo && <p role="status" className="px-5 pb-2 text-xs text-muted-foreground">Abriendo ficha…</p>}
   476	              {errorApertura && <p role="alert" className="px-5 pb-2 text-xs text-destructive-text">No se pudo abrir la ficha. Vuelve a intentarlo.</p>}
   477	
   478	              <div
   479	                id={`${idPanelCola}-panel`}
   480	                role="tabpanel"
   481	                aria-labelledby={`${idPanelCola}-tab-${pestana}`}
   482	                tabIndex={paginaVigente && paginaVigente.items.length > 0 ? undefined : 0}
   483	                className="flex flex-1 flex-col"
   484	              >
   485	                <div className={cn(consultaCola.error && 'border-t border-border/60 px-5 py-4')}>
   486	                  <AvisoDegradacion activo={consultaCola.error != null} queReintenta="de los pendientes del equipo" onReintentar={() => void consultaCola.refetch()}>
   487	                    No se pudo cargar la cola. Los pendientes todavía no están confirmados.
   488	                  </AvisoDegradacion>
   489	                </div>
   490	                {consultaCola.error ? null : !pagina ? (
   491	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
   492	                ) : !paginaVigente ? (
   493	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   494	                    {pagina.modo !== 'activo'
   495	                      ? 'Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.'
   496	                      : 'Actualizando los pendientes con las reglas vigentes…'}
   497	                  </p>
   498	                ) : paginaVigente.items.length === 0 ? (
   499	                  <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   500	                    {nombreAnalista ? `${corto(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
   501	                  </p>
   502	                ) : (
   503	                  // oxlint-disable-next-line jsx-a11y/no-redundant-roles
   504	                  <ul role="list" aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
   505	                    {paginaVigente.items.map((item) => {
   506	                      const leadStore = leadPorId.get(item.lead_id)
   507	                      const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
   508	                      const analistaFila = item.lead.analista_nombre ? corto(item.lead.analista_nombre) : 'Sin analista'
   509	                      const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
   510	                      const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
   511	                      const urgente = item.severidad === 'critica'
   512	                      return (
   513	                        <li
   514	                          key={item.lead_id}
   515	                          data-sev={item.severidad}
   516	                          className="flex items-center gap-2 border-l-[3px] border-t border-t-border/60 pr-5"
   517	                          style={{ borderLeftColor: colorTira }}
   518	                        >
   519	                          <button
   520	                            type="button"
   521	                            // aria-disabled y NO disabled: un botón enfocado que se deshabilita
   522	                            // suelta el foco a <body> y la ficha lo devolvía ahí al cerrarse.
   523	                            // La guarda de abrirFicha ya evita el doble envío.
   524	                            aria-disabled={abriendo !== null || undefined}
   525	                            onClick={() => void abrirFicha(item.lead_id)}
   526	                            // El nombre dicta TODO lo visible (dueño, urgencia, estado,
   527	                            // tiempo, monto): un lector de pantalla no puede perder lo que se ve.
   528	                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}${urgente ? ', urgente' : ''}: ${estado}${monto ? `, ${monto}` : ''}`}
   529	                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 aria-disabled:cursor-wait"
   530	                          >
   531	                            {analistaId == null && (
   532	                              <span className="hidden w-[118px] shrink-0 items-center gap-2 sm:flex">
   533	                                <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
   534	                                <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
   535	                              </span>
   536	                            )}
   537	                            <span className="min-w-0 flex-1 leading-tight">
   538	                              <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
   539	                              <span className="flex min-w-0 items-center gap-1 text-xs text-muted-foreground-strong">
   540	                                {urgente && <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />}
   541	                                <span className="truncate">
   542	                                  {analistaId == null && <span className="sm:hidden">{analistaFila} · </span>}
   543	                                  {estado}
   544	                                </span>
   545	                              </span>
   546	                            </span>
   547	                            {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
   548	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   549	                          </button>
   550	                          {leadStore && (
   551	                            // Las acciones compactas miden 28 px: se llevan al mínimo de 36 (40 táctil).
   552	                            <div className="[&_a]:min-h-9 [&_button]:min-h-9 pointer-coarse:[&_a]:min-h-10 pointer-coarse:[&_button]:min-h-10">
   553	                              <AccionesContacto lead={leadStore} compacto />
   554	                            </div>
   555	                          )}
   556	                        </li>
   557	                      )
   558	                    })}
   559	                  </ul>
   560	                )}
   561	                <div className="mt-auto flex items-center justify-between gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
   562	                  <span className="tabular-nums text-muted-foreground-strong">
   563	                    {paginaVigente && paginaVigente.items.length > 0
   564	                      ? `${numero(paginaVigente.items.length)} de ${numero(paginaVigente.total_items)}`
   565	                      : ''}
   566	                  </span>
   567	                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   568	                    Ver todo en Seguimiento <ChevronRight className="size-3.5" aria-hidden />
   569	                  </a>
   570	                </div>
   571	              </div>
   572	            </>
   573	          )}
   574	        </Card>
   575	
   576	        {/* ── Equipo hoy: tocar a alguien filtra la cola y despliega sus señales ── */}
   577	        <Card className="min-w-0 overflow-hidden lg:col-span-2">
   578	          <SectionHead
   579	            icon={UsersRound}
   580	            title="Equipo hoy"
   581	            right={(
   582	              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-1 text-xs font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   583	                Mi equipo hoy <span aria-hidden>→</span>
   584	              </a>
   585	            )}
   586	          />
   587	          {rank != null && rank.length > 0 && (semaforoEquipo.rojo > 0 || semaforoEquipo.ambar > 0 || datos.agendaConfirmada != null) && (
   588	            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
   589	              {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
   590	                // Solo con la agenda confirmada: sin ella, cero señales es desconocido.
   591	                ? 'Sin alertas en el equipo'
   592	                : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
   593	            </p>
   594	          )}
   595	          <div className={cn(datos.errorAgenda && 'mx-5 mb-2')}>
   596	            <AvisoDegradacion activo={datos.errorAgenda != null} queReintenta="de la agenda del equipo" onReintentar={datos.recargarAgenda}>
   597	              La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.
   598	            </AvisoDegradacion>
   599	          </div>
   600	          {rank == null ? (
   601	            <CardContent className="pb-5 pt-0">
   602	              <p className="text-sm text-muted-foreground">
   603	                {datos.vendedoresOp.error
   604	                  ? 'El resumen por analista no está disponible en este momento.'
   605	                  : 'Cargando el resumen por analista…'}
   606	              </p>
   607	            </CardContent>
   608	          ) : rank.length === 0 ? (
   609	            <CardContent className="pb-5 pt-0">
   610	              <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   611	            </CardContent>
   612	          ) : (
   613	            // oxlint-disable-next-line jsx-a11y/no-redundant-roles
   614	            <ul role="list" aria-label="Analistas del equipo" className="border-t border-border/60">
   615	              {rank.map((r) => {
   616	                const id = r.m.perfil_id
   617	                const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
   618	                const rezago = rezagosConfirmados.get(id)
   619	                const abierto = analistaId === id
   620	                const principal = lectura.senales[0]?.texto
   621	                  ?? (r.activos === 0
   622	                    ? 'Sin leads abiertos'
   623	                    : rezago != null ? 'Al día' : `Última actividad ${haceTexto(r.diasSinActividadMax)}`)
   624	                const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   625	                const idDetalle = `${idPanelCola}-equipo-${id}`
   626	                // PEN y USD jamás se suman sin decirlo: el nombre lleva el desglose.
   627	                const desglose = r.capitalUSD > 0
   628	                  ? cap.tc != null
   629	                    ? ` (${moneyK(r.capitalPEN, 'PEN')} más ${moneyK(r.capitalUSD, 'USD')})`
   630	                    : `, más ${moneyK(r.capitalUSD, 'USD')} aparte sin tipo de cambio`
   631	                  : ''
   632	                const nivelTexto = lectura.nivel != null ? `${TEXTO_NIVEL[lectura.nivel]}. ` : ''
   633	                const conversion = r.conversion == null
   634	                  ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
   635	                  : `${textoConversionOperativa(r.conversion)} conversión`
   636	                return (
   637	                  <li key={id} className="border-b border-border/60 last:border-b-0">
   638	                    <button
   639	                      type="button"
   640	                      aria-expanded={abierto}
   641	                      aria-controls={idDetalle}
   642	                      aria-label={`${r.m.nombre_completo}: ${nivelTexto}${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}${desglose}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
   643	                      onClick={() => elegirAnalista(id)}
   644	                      className={cn(
   645	                        'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
   646	                        abierto && 'bg-accent/[0.08]',
   647	                      )}
   648	                    >
   649	                      <MarcaNivel nivel={lectura.nivel} />
   650	                      <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
   651	                      <span className="min-w-0 flex-1 leading-tight">
   652	                        <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
   653	                        <span className="block truncate text-xs text-muted-foreground-strong">{principal}</span>
   654	                      </span>
   655	                      <span className="shrink-0 text-right leading-tight">
   656	                        <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
   657	                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto tono="fuerte" />
   658	                      </span>
   659	                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierto ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
   660	                    </button>
   661	                    <div id={idDetalle} hidden={!abierto} className="space-y-1.5 px-5 pb-3 pl-[62px]">
   662	                      {lectura.senales.length > 1 && (
   663	                        <div className="flex flex-wrap gap-1.5">
   664	                          {lectura.senales.slice(1).map((s) => <ChipSenal key={s.texto} texto={s.texto} nivel={s.nivel} />)}
   665	                        </div>
   666	                      )}
   667	                      <p className="text-xs tabular-nums text-muted-foreground-strong">
   668	                        {numero(r.activos)} activos · {conversion}
   669	                        {r.operacionesCartera != null && r.operacionesCartera > 0 ? ` · ${numero(r.operacionesCartera)} de cartera` : ''}
   670	                        {r.sinTocar > 0 ? ` · ${numero(r.sinTocar)} sin tocar` : ''}
   671	                      </p>
   672	                      {rezago != null && (
   673	                        <p className="text-xs tabular-nums text-muted-foreground-strong">
   674	                          {rezago.toques > 0
   675	                            ? `${numero(rezago.toques)} toques en 7 días${rezago.pct_completadas != null ? ` · ${Math.round(rezago.pct_completadas)} % completadas` : ''}`
   676	                            : 'Sin toques registrados en 7 días'}
   677	                        </p>
   678	                      )}
   679	                    </div>
   680	                  </li>
   681	                )
   682	              })}
   683	            </ul>
   684	          )}
   685	        </Card>
   686	      </div>
   687	
   688	      {/* ── 3 · Consulta: cifras en una línea; «Detalle» abre todo lo demás ── */}
   689	      <section aria-label="Consulta" className="flex min-h-12 flex-wrap items-center gap-x-5 gap-y-1.5 rounded-xl border border-border bg-card px-5 py-2">
   690	        <span className="text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground-strong" aria-hidden>Consulta</span>
   691	        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
   692	        <ul role="list" aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
   693	          <li>
   694	            <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
   695	            {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
   696	          </li>
   697	          <li><strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos</li>
   698	          <li><strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta</li>
   699	          <li><strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes</li>
   700	          <li aria-hidden className="h-[18px] w-px bg-border" />
   701	          <li><strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días</li>
   702	          <li><strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas</li>
   703	          <li className="inline-flex items-center gap-1">
   704	            {agendaResumen && agendaResumen.noAsistio >= 2 && (
   705	              <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />
   706	            )}
   707	            <strong
   708	              className="font-extrabold"
   709	              style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
   710	            >
   711	              {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
   712	            </strong> {agendaResumen?.noAsistio === 1 ? 'cita sin asistir' : 'citas sin asistir'}
   713	          </li>
   714	        </ul>
   715	        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent pointer-coarse:min-h-10" onClick={() => setDetalleAbierto(true)}>
   716	          Detalle
   717	        </Button>
   718	      </section>
   719	
   720	      <Dialog
   721	        open={detalleAbierto}
   722	        onClose={() => setDetalleAbierto(false)}
   723	        focoInicial={tituloDetalle}
   724	        className="w-[1180px] max-h-[88vh] max-w-[94vw]"
   725	      >
   726	        <DialogHeader>
   727	          {/* El foco entra por el título, no en mitad de la rejilla de indicadores. */}
   728	          <DialogTitle><span ref={tituloDetalle} tabIndex={-1} className="outline-none">Detalle del equipo</span></DialogTitle>
   729	          <DialogDescription>Indicadores, cumplimiento del mes y agenda de los últimos 7 días.</DialogDescription>
   730	        </DialogHeader>
   731	        <DialogBody className="space-y-4">
   732	          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   733	            {/* Pronóstico: `capitalPrincipal`, NUNCA un total mixto con los dólares. */}
   734	            <KpiCard
   735	              label="Pronóstico de capital abierto"
   736	              value={pronostico ? pronostico.valor : '—'}
   737	              icon={Wallet}
   738	              color={SEMAFORO.neutro}
   739	              sub={
   740	                pronostico?.otra
   741	                  ? `En soles · +${pronostico.otra} aparte`
   742	                  : pronostico?.soloDolares
   743	                    ? 'En dólares · abiertos con analista'
   744	                    : datos.resumen && datos.resumen.capital.asignado.pen === 0 && datos.resumen.totales.asignados > 0
   745	                      ? 'Sin montos estimados — complétalos en cada ficha'
   746	                      : 'En soles · abiertos con analista'
   747	              }
   748	            />
   749	            <KpiCard
   750	              label="Leads activos del equipo"
   751	              value={datos.resumen ? String(datos.resumen.totales.asignados) : '—'}
   752	              icon={Users}
   753	              color={SEMAFORO.neutro}
   754	              sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
   755	              delay={60}
   756	            />
   757	            <KpiCard
   758	              label="Primeras gestiones vencidas"
   759	              value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
   760	              icon={AlertTriangle}
   761	              color={SEMAFORO.neutro}
   762	              sub={primeraGestionPendiente == null
   763	                ? 'Sin dato por ahora'
   764	                : primeraGestionPendiente > 0 ? 'Revísalas con cada analista' : 'Ninguna vencida'}
   765	              delay={120}
   766	            />
   767	            <a
   768	              href={hashDe('derivaciones')}
   769	              aria-label={`Por repartir: ${datos.etiquetaAccesoReparto}`}
   770	              className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
   771	            >
   772	              <KpiCard
   773	                label="Por repartir"
   774	                value={datos.totalPorRepartir == null ? '—' : String(datos.totalPorRepartir)}
   775	                icon={Inbox}
   776	                color={SEMAFORO.neutro}
   777	                sub={datos.detalleReparto}
   778	                delay={180}
   779	              />
   780	            </a>
   781	          </div>
   782	
   783	          <div className="grid gap-4 lg:grid-cols-5">
   784	            <Card className="lg:col-span-2">
   785	              <SectionHead
   786	                icon={Target}
   787	                title="Cumplimiento del mes"
   788	                right={tc ? <span className="text-xs text-muted-foreground-strong">{rotuloTipoCambio(tc.promedio, tc.fuente)}</span> : undefined}
   789	              />
   790	              <CardContent className="space-y-4 pb-5 pt-0">
   791	                {datos.filasMeta.map((f) => (
   792	                  <div key={f.label}>
   793	                    <div className="mb-1.5 flex items-baseline justify-between gap-2">
   794	                      <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
   795	                      <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
   796	                    </div>
   797	                    {f.nota && <p className="mb-1 text-[11px] tabular-nums text-muted-foreground-strong">{f.nota}</p>}
   798	                    {f.sinDato
   799	                      ? <p className="text-[11px] text-muted-foreground-strong">{f.sinDato}</p>
   800	                      : <Progress value={f.pct} color={colorMeta(f.pct)} />}
   801	                  </div>
   802	                ))}
   803	                <p className="text-[11px] text-muted-foreground-strong">
   804	                  El capital en dólares entra al total convertido a tipo de cambio real. El pronóstico no cuenta como cumplimiento.
   805	                </p>
   806	                <AvisoDegradacion activo={datos.hayErrorMensual} queReintenta="de la meta y el cumplimiento del mes" onReintentar={datos.reintentarMensual}>
   807	                  Parte del cumplimiento del mes no se pudo cargar: se muestra «—» donde falta el dato.
   808	                </AvisoDegradacion>
   809	              </CardContent>
   810	            </Card>
   811	            <div className="min-w-0 lg:col-span-3">
   812	              <AgendaEquipoPanel
   813	                datos={datos.datosAgenda}
   814	                cargando={datos.cargandoAgenda}
   815	                error={datos.errorAgenda}
   816	                modoDemo={yo?.demo === true}
   817	                onReintentar={datos.recargarAgenda}
   818	                equipo={datos.equipo}
   819	              />
   820	            </div>
   821	          </div>
   822	
   823	          {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC). */}
   824	          <DesglosePorEmpresa demo={yo?.demo === true} porVendedor={datos.cumplimientoMensual?.porVendedor ?? null} />
   825	          {/* Rentabilidad R3: las solicitudes de tasa propias en curso (solo si hay). */}
   826	          <TasasAutorizadasAnalistaPanel />
   827	          <p className="text-[11px] text-muted-foreground-strong">
   828	            Ves solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
   829	          </p>
   830	        </DialogBody>
   831	        <DialogFooter>
   832	          <Button variant="outline" size="sm" className="min-h-9" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
   833	        </DialogFooter>
   834	      </Dialog>
   835	    </div>
   836	  )
   837	}
   838	
   839	/** El botón de acción de una decisión. Nunca va DENTRO del botón que la despliega. */
   840	function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
   841	  cosa: CosaDeHoy
   842	  onVerPrimeraGestion: () => void
   843	  etiquetaReparto: string
   844	}): JSX.Element {
   845	  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
   846	  if (cosa.id === 'primera_gestion') {
   847	    return (
   848	      <button type="button" className={clase} aria-label={`Ver en la cola: ${cosa.texto}`} onClick={onVerPrimeraGestion}>
   849	        Ver <ChevronRight className="size-3.5" aria-hidden />
   850	      </button>
   851	    )
   852	  }
   853	  if (cosa.id === 'por_repartir') {
   854	    return (
   855	      <a href={hashDe('derivaciones')} className={clase} aria-label={etiquetaReparto}>
   856	        Repartir <ChevronRight className="size-3.5" aria-hidden />
   857	      </a>
   858	    )
   859	  }
   860	  if (cosa.id === 'no_asistio' || cosa.id === 'sin_accion') {
   861	    // La cola no contiene citas ni leads «sin próxima acción»: filtrarla
   862	    // enseñaría OTROS casos. La decisión se toma viendo el día del equipo.
   863	    const label = cosa.vendedorId != null ? 'Ver su día' : 'Ver el equipo'
   864	    return (
   865	      <a href={hashDe('gestion-diaria')} className={clase} aria-label={`${label}: ${cosa.texto}`}>
   866	        {label} <ChevronRight className="size-3.5" aria-hidden />
   867	      </a>
   868	    )
   869	  }
   870	  // Candidatos del modo legado: aquí no aparecen (la cola legada llega null),
   871	  // pero si algún día lo hicieran, su lugar es el módulo de seguimiento.
   872	  return (
   873	    <a href={hashDe('seguimiento')} className={clase} aria-label={`${cosa.accion}: ${cosa.texto}`}>
   874	      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
   875	    </a>
   876	  )
   877	}
   878	
   879	function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVerPrimeraGestion, etiquetaReparto }: {
   880	  cosa: CosaDeHoy
   881	  abierta: boolean
   882	  contexto: string | null
   883	  idContexto: string
   884	  onAlternar: () => void
   885	  onVerPrimeraGestion: () => void
   886	  etiquetaReparto: string
   887	}): JSX.Element {
   888	  const { cifra, resto } = partesDeCosa(cosa.texto)
   889	  return (
   890	    <Card
   891	      data-decision={cosa.id}
   892	      className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')}
   893	      style={{ borderLeftColor: SEV_BORDE[cosa.severidad] }}
   894	    >
   895	      <div className="flex flex-wrap items-center gap-2 py-2 pl-4 pr-3">
   896	        <button
   897	          type="button"
   898	          aria-expanded={abierta}
   899	          aria-controls={idContexto}
   900	          aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto}`}
   901	          onClick={onAlternar}
   902	          className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 rounded-md text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
   903	        >
   904	          {cifra && (
   905	            <span className="min-w-10 text-[32px] font-extrabold leading-none tracking-tight tabular-nums text-primary">{cifra}</span>
   906	          )}
   907	          <span className="min-w-0 flex-1 leading-tight">
   908	            <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: SEV_TEXTO_COLOR[cosa.severidad] }}>
   909	              {SEV_TEXTO[cosa.severidad]}
   910	            </span>
   911	            <span className="line-clamp-2 break-words text-[15px] font-bold">{resto}</span>
   912	          </span>
   913	          <ChevronRight
   914	            className={cn('size-4 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')}
   915	            aria-hidden
   916	          />
   917	        </button>
   918	        <AccionDecision cosa={cosa} onVerPrimeraGestion={onVerPrimeraGestion} etiquetaReparto={etiquetaReparto} />
   919	      </div>
   920	      <p id={idContexto} hidden={!abierta} className="border-t border-border/60 px-4 py-2.5 text-xs text-muted-foreground-strong">
   921	        {contexto ?? 'Sin más detalle confirmado por ahora.'}
   922	      </p>
   923	    </Card>
   924	  )
   925	}
   926	
   927	/** «Esta semana · N»: lo que no entró en las tres tarjetas. Esc y clic fuera lo cierran. */
   928	function EstaSemana({ cosas, onVerPrimeraGestion, etiquetaReparto }: {
   929	  cosas: CosaDeHoy[]
   930	  onVerPrimeraGestion: () => void
   931	  etiquetaReparto: string
   932	}): JSX.Element {
   933	  const [abierto, setAbierto] = useState(false)
   934	  const contenedor = useRef<HTMLDivElement>(null)
   935	  const disparador = useRef<HTMLButtonElement>(null)
   936	  const idLista = useId()
   937	  useEffect(() => {
   938	    if (!abierto) return
   939	    const fuera = (e: PointerEvent) => {
   940	      if (!contenedor.current?.contains(e.target as Node)) setAbierto(false)
   941	    }
   942	    // Esc cierra y devuelve el foco al disparador, esté donde esté el foco
   943	    // dentro de la lista (y también si quedó fuera: el popover no atrapa).
   944	    const escape = (e: KeyboardEvent) => {
   945	      if (e.key !== 'Escape') return
   946	      setAbierto(false)
   947	      if (contenedor.current?.contains(document.activeElement)) disparador.current?.focus()
   948	    }
   949	    // Tabular fuera del popover lo cierra: si no, quedaría encima de las
   950	    // tarjetas que reciben el foco a continuación (WCAG 2.4.11).
   951	    const nodo = contenedor.current
   952	    const salida = (e: FocusEvent) => {
   953	      if (e.relatedTarget instanceof Node && !nodo?.contains(e.relatedTarget)) setAbierto(false)
   954	    }
   955	    document.addEventListener('pointerdown', fuera)
   956	    document.addEventListener('keydown', escape)
   957	    nodo?.addEventListener('focusout', salida)
   958	    return () => {
   959	      document.removeEventListener('pointerdown', fuera)
   960	      document.removeEventListener('keydown', escape)
   961	      nodo?.removeEventListener('focusout', salida)
   962	    }
   963	  }, [abierto])
   964	  return (
   965	    <div ref={contenedor} className="relative">
   966	      <button
   967	        ref={disparador}
   968	        type="button"
   969	        aria-expanded={abierto}
   970	        aria-controls={idLista}
   971	        onClick={() => setAbierto((v) => !v)}
   972	        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
   973	      >
   974	        <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
   975	        Esta semana · {cosas.length}
   976	        <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
   977	      </button>
   978	      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
   979	      <ul role="list"
   980	        id={idLista}
   981	        hidden={!abierto}
   982	        aria-label="Decisiones para esta semana"
   983	        className="ac-pop absolute right-0 top-11 z-20 w-[340px] max-w-[90vw] rounded-xl border border-border bg-card p-2 shadow-[var(--shadow-pop)]"
   984	      >
   985	        {cosas.map((c) => (
   986	          <li key={c.id} className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-xs font-semibold">
   987	            <span className="size-2 shrink-0 rounded-full" style={{ background: SEV_BORDE[c.severidad] }} aria-hidden />
   988	            <span className="min-w-0 flex-1">
   989	              <span className="sr-only">{SEV_TEXTO[c.severidad]}: </span>{c.texto}
   990	            </span>
   991	            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={etiquetaReparto} />
   992	          </li>
   993	        ))}
   994	      </ul>
   995	    </div>
   996	  )
   997	}
```

## `app/src/screens/hoy/supervisor-mando.test.tsx` (estado FINAL completo)
```
     1	// Hoy · supervisor — puesto de mando (27/09/2026). Se prueba en el MUNDO DE
     2	// PRODUCCIÓN: seguimiento ACTIVO (la cola legada no se consulta), sin metas
     3	// publicadas y con la agenda que llegue o no llegue. La derivación compartida
     4	// (./datos-supervisor.ts) corre de verdad sobre los mismos mocks que usa
     5	// supervisor.test.tsx; lo que se sustituye es la red.
     6	import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
     7	import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
     8	import { objetivosCero, type CumplimientoMetasJerarquico, type ObjetivosPorRol } from '@/lib/objetivos'
     9	import type { Actividad, Lead, Miembro, Yo } from '@/lib/tipos'
    10	import type { ColaSlaPagina, FiltrosSla } from '@/lib/sla-operacion'
    11	import type { MetricaAgendaVendedor, MetricasAgenda } from '@/lib/metricas-agenda'
    12	
    13	// Sábado 2026-09-26, 10:00 en Lima (UTC-5).
    14	const AHORA = new Date('2026-09-26T15:00:00Z')
    15	
    16	let YO: Yo | null = null
    17	let LEADS: Lead[] = []
    18	let VENDEDORES: Miembro[] = []
    19	let OBJETIVOS: ObjetivosPorRol = objetivosCero('2026-09-01')
    20	let CUMPLIMIENTO: CumplimientoMetasJerarquico | null = null
    21	const recargar = vi.fn()
    22	const abrirLead = vi.fn<(id: string) => Promise<boolean>>()
    23	
    24	vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
    25	vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
    26	  ...(await importOriginal<typeof import('@/lib/tipo-cambio')>()),
    27	  useTipoCambio: () => ({ tc: { promedio: 3.5, fuente: 'BCRP · prom. 7d' }, recargar: vi.fn() }),
    28	}))
    29	vi.mock('@/lib/store-context', () => ({
    30	  useCRMData: () => ({
    31	    conocerLeads: () => {}, asegurarLead: async () => true,
    32	    ambito: { leads: LEADS, vendedores: VENDEDORES, esGlobal: false },
    33	    actividades: [] as Actividad[],
    34	    tareas: [],
    35	    objetivos: OBJETIVOS,
    36	    objetivosError: false,
    37	    cumplimientoMetas: CUMPLIMIENTO,
    38	    cumplimientoMetasError: false,
    39	    recargar,
    40	    equipo: VENDEDORES,
    41	  }),
    42	  usePanelesActions: () => ({ abrirLead }),
    43	}))
    44	vi.mock('./agenda-equipo', () => ({ AgendaEquipoPanel: () => <section aria-label="Agenda del equipo" /> }))
    45	// La pantalla clásica tiene su propia suite: aquí solo importa CUÁNDO se elige.
    46	vi.mock('./supervisor', () => ({ HoySupervisor: () => <p>Pantalla clásica del supervisor</p> }))
    47	
    48	let METRICAS_AGENDA: MetricasAgenda | undefined
    49	let CONVERSION: { data: unknown; isError: boolean } = { data: undefined, isError: false }
    50	let AGENDA_ERROR: Error | null = null
    51	const REFETCH_AGENDA = vi.fn()
    52	vi.mock('@/data/crm-queries', () => ({
    53	  useSolicitudesTasa: () => ({ data: [], isPending: false, isError: false, refetch: () => {} }),
    54	  useResolverSolicitudTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    55	  useResponderTopeTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    56	  useResolucionTasa: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
    57	  useSolicitarTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    58	  useHistorialTasaCliente: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
    59	  useMetricasAgenda: () => ({ data: METRICAS_AGENDA, error: AGENDA_ERROR, isPending: false, isFetching: false, refetch: REFETCH_AGENDA }),
    60	  useConversionMensual: () => ({ data: CONVERSION.data, isError: CONVERSION.isError, isPending: false, isFetching: false, refetch: vi.fn() }),
    61	  useCierresExternos: () => ({ data: undefined, isError: false, isPending: false, isFetching: false, refetch: () => {} }),
    62	}))
    63	vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))
    64	vi.mock('@/data/use-resumen-cartera-operativo', async () => {
    65	  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
    66	  return {
    67	    useResumenCarteraOperativo: (leads: Lead[], actividades: Actividad[]) => ({
    68	      resumen: resumenCarteraDesdeAmbito(leads, actividades ?? [], Date.now()),
    69	      cargando: false, error: null, recargar: vi.fn(),
    70	    }),
    71	  }
    72	})
    73	vi.mock('@/data/use-metricas-vendedores-operativas', async () => {
    74	  const { metricasVendedoresDesdeAmbito } = await import('@/lib/metricas-vendedores')
    75	  return {
    76	    useMetricasVendedoresOperativas: (roster: Miembro[], equipo: Miembro[], leads: Lead[], actividades: Actividad[]) => ({
    77	      metricas: metricasVendedoresDesdeAmbito(roster ?? [], equipo ?? [], leads ?? [], actividades ?? [], Date.now()),
    78	      cargando: false, error: null, recargar: vi.fn(),
    79	    }),
    80	  }
    81	})
    82	
    83	// ── Seguimiento activo: modo + cola del servidor, controlables por prueba ──
    84	const MODO = { legado: false, activo: true, error: null as Error | null, data: { control_revision: 1 } as { control_revision: number } | undefined }
    85	const REFETCH_MODO = vi.fn()
    86	type RespuestaCola = { data: ColaSlaPagina | undefined; error: Error | null; isFetching: boolean }
    87	let RESPONDER: (filtros: FiltrosSla) => RespuestaCola = () => ({ data: undefined, error: null, isFetching: false })
    88	const REFETCH_COLA = vi.fn()
    89	const pedidosCola: Array<{ filtros: FiltrosSla; limite: number; habilitada: boolean }> = []
    90	vi.mock('@/data/sla-operacion-queries', () => ({
    91	  useModoSla: () => ({ ...MODO, refetch: REFETCH_MODO }),
    92	  useColaSlaPagina: (filtros: FiltrosSla, _cursor: unknown, limite: number, habilitada: boolean) => {
    93	    pedidosCola.push({ filtros, limite, habilitada })
    94	    return { ...RESPONDER(filtros), refetch: REFETCH_COLA }
    95	  },
    96	}))
    97	
    98	const { HoySupervisorMando } = await import('./supervisor-mando')
    99	
   100	/** Cada render pide la cola (con el filtro por analista) y luego la del equipo (sin él). */
   101	const pedidoCola = () => pedidosCola.at(-2)
   102	const pedidoEquipo = () => pedidosCola.at(-1)
   103	
   104	const KAREN = 'aaaaaaaa-0000-4000-8000-000000000001'
   105	const JORGE = 'aaaaaaaa-0000-4000-8000-000000000002'
   106	
   107	function miembro(id: string, nombre: string, over: Partial<Miembro> = {}): Miembro {
   108	  return { perfil_id: id, nombre_completo: nombre, rol_crm: 'vendedor', supervisor_id: 's-1', activo: true, ...over }
   109	}
   110	
   111	function lead(over: Partial<Lead> = {}): Lead {
   112	  return {
   113	    id: 'l-1', nombre_completo: 'ROSA CHÁVEZ', telefono: '+51987654321', etapa: 'contactado', origen: 'referido',
   114	    monto_estimado: 20_000, moneda: 'PEN', vendedor_id: KAREN, creado_en: '2026-09-20T15:00:00Z', activo: true, ...over,
   115	  }
   116	}
   117	
   118	type ItemCola = ColaSlaPagina['items'][number]
   119	function item(over: { lead_id: string; nombre: string; analistaId: string | null; analista: string | null; bucket?: string; severidad?: ItemCola['severidad']; referencia_en?: string | null }): ItemCola {
   120	  return {
   121	    lead_id: over.lead_id,
   122	    bucket: over.bucket ?? 'primera_atencion',
   123	    severidad: over.severidad ?? 'critica',
   124	    prioridad: 10,
   125	    referencia_en: over.referencia_en === undefined ? '2026-09-24T15:00:00Z' : over.referencia_en,
   126	    tarea_id: null,
   127	    lead: { id: over.lead_id, nombre_completo: over.nombre, etapa: 'nuevo', analista_id: over.analistaId, analista_nombre: over.analista },
   128	    senales: { pendientes: true, primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
   129	  } as unknown as ItemCola
   130	}
   131	
   132	const TOTALES_CERO = { pendientes: 0, primera_atencion: 0, tareas_vencidas: 0, seguimientos_pendientes: 0, revisiones: 0, datos_incompletos: 0, por_repartir: 0 }
   133	function pagina(items: ItemCola[], over: Partial<Omit<ColaSlaPagina, 'totales'>> & { totales?: Partial<ColaSlaPagina['totales']> } = {}): ColaSlaPagina {
   134	  const { totales, ...resto } = over
   135	  return {
   136	    version: 2, modo: 'activo', control_revision: 1, calculado_en: '2026-09-26T15:00:00Z', modelo_avisos: 3,
   137	    filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7,
   138	    total_items: items.length, hay_mas: false, cursor_siguiente: null, rango: { desde: 1, hasta: items.length },
   139	    totales: { ...TOTALES_CERO, ...totales },
   140	    items,
   141	    ...resto,
   142	  } as ColaSlaPagina
   143	}
   144	
   145	function agenda(vendedores: Array<Partial<MetricaAgendaVendedor> & { vendedor_id: string; nombre: string }>): MetricasAgenda {
   146	  return {
   147	    version: 1, generado_en: '2026-09-26T15:00:00Z',
   148	    periodo: { desde: '2026-09-20', hasta: '2026-09-26', dias: 7, zona: 'America/Lima' },
   149	    vendedores: vendedores.map((v) => ({
   150	      rol: 'vendedor', activo: true, toques: 0, toques_por_dia: 0, reuniones_realizadas: 0, completadas: 0, no_asistio: 0,
   151	      canceladas: 0, pct_completadas: null, tareas_creadas: 0, reuniones_agendadas: 0, reprogramaciones: 0, pendientes: 0,
   152	      vencidas: 0, leads_sin_accion: 0, ...v,
   153	    })),
   154	  } as MetricasAgenda
   155	}
   156	
   157	function montar(): ReturnType<typeof render> {
   158	  vi.setSystemTime(AHORA)
   159	  YO = { id: 's-1', nombre_completo: 'SUPERVISOR UNO', rol: 'supervisor', demo: false, puede_contratar: true }
   160	  return render(<HoySupervisorMando />)
   161	}
   162	
   163	const colaTodo = () => [
   164	  item({ lead_id: 'l-1', nombre: 'ROSA CHÁVEZ', analistaId: KAREN, analista: 'KAREN ZAPATA' }),
   165	  item({ lead_id: 'l-2', nombre: 'VÍCTOR PALOMINO', analistaId: JORGE, analista: 'JORGE HUAMÁN', bucket: 'tarea_vencida', severidad: 'critica', referencia_en: '2026-09-26T12:00:00Z' }),
   166	  item({ lead_id: 'l-3', nombre: 'MARTHA SOTO', analistaId: KAREN, analista: 'KAREN ZAPATA', bucket: 'seguimiento', severidad: 'media', referencia_en: '2026-09-26T18:00:00Z' }),
   167	]
   168	
   169	beforeEach(() => {
   170	  vi.useFakeTimers()
   171	  vi.clearAllMocks()
   172	  recargar.mockResolvedValue(true)
   173	  abrirLead.mockResolvedValue(true)
   174	  pedidosCola.length = 0
   175	  MODO.legado = false
   176	  MODO.activo = true
   177	  MODO.error = null
   178	  MODO.data = { control_revision: 1 }
   179	  VENDEDORES = [
   180	    miembro(KAREN, 'KAREN ZAPATA'),
   181	    miembro(JORGE, 'JORGE HUAMÁN'),
   182	    miembro('v-ex', 'EX ANALISTA', { activo: false }),
   183	  ]
   184	  LEADS = [lead(), lead({ id: 'l-3', nombre_completo: 'MARTHA SOTO', monto_estimado: 15_000, moneda: 'USD' })]
   185	  OBJETIVOS = objetivosCero('2026-09-01')
   186	  CUMPLIMIENTO = null
   187	  METRICAS_AGENDA = agenda([{ vendedor_id: KAREN, nombre: 'KAREN ZAPATA' }, { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' }])
   188	  AGENDA_ERROR = null
   189	  CONVERSION = { data: undefined, isError: false }
   190	  RESPONDER = (filtros) => {
   191	    const todas = colaTodo().filter((i) => filtros.analista_id == null || i.lead.analista_id === filtros.analista_id)
   192	    return {
   193	      data: pagina(todas, {
   194	        filtros: { ...filtros },
   195	        totales: { pendientes: todas.length, primera_atencion: todas.filter((i) => i.bucket === 'primera_atencion').length, tareas_vencidas: todas.filter((i) => i.bucket === 'tarea_vencida').length },
   196	      }),
   197	      error: null,
   198	      isFetching: false,
   199	    }
   200	  }
   201	})
   202	
   203	afterEach(() => {
   204	  vi.useRealTimers()
   205	})
   206	
   207	describe('Hoy · supervisor — puesto de mando: qué pantalla se elige', () => {
   208	  it('en modo LEGADO (demo o seguimiento apagado) sigue la pantalla clásica', () => {
   209	    MODO.legado = true
   210	    MODO.activo = false
   211	    montar()
   212	    expect(screen.getByText('Pantalla clásica del supervisor')).toBeInTheDocument()
   213	    expect(pedidosCola).toHaveLength(0)
   214	  })
   215	
   216	  it('mientras el modo se consulta no pide la cola ni inventa pendientes', () => {
   217	    MODO.activo = false
   218	    MODO.data = undefined
   219	    montar()
   220	    expect(screen.getByText('Consultando el seguimiento comercial…')).toHaveAttribute('role', 'status')
   221	    expect(screen.queryByRole('tablist')).not.toBeInTheDocument()
   222	    expect(pedidosCola.every((p) => !p.habilitada)).toBe(true)
   223	  })
   224	
   225	  it('si el modo falla lo dice y deja reintentar', () => {
   226	    MODO.activo = false
   227	    MODO.error = new Error('caído')
   228	    montar()
   229	    expect(screen.getByText(/No se pudo cargar el seguimiento/)).toBeInTheDocument()
   230	    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga del seguimiento' }))
   231	    expect(REFETCH_MODO).toHaveBeenCalledTimes(1)
   232	  })
   233	})
   234	
   235	describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', () => {
   236	  it('ESTADO DE PRODUCCIÓN: la cola sale del seguimiento con 7 filas, conteos del servidor y enlace al módulo', () => {
   237	    montar()
   238	    expect(pedidoCola()).toEqual({ filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7, habilitada: true })
   239	    expect(pedidoEquipo()).toEqual(pedidoCola())
   240	    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
   241	    const pestanas = screen.getByRole('tablist', { name: 'Filtrar los pendientes' })
   242	    expect(within(pestanas).getByRole('tab', { name: 'Para atender ahora: 3' })).toHaveAttribute('aria-selected', 'true')
   243	    expect(within(pestanas).getByRole('tab', { name: 'Primera gestión: 1' })).toBeInTheDocument()
   244	    expect(within(pestanas).getByRole('tab', { name: 'Tareas vencidas: 1' })).toBeInTheDocument()
   245	    // «Todas» no tiene total en `totales`: sin número hasta que se abre.
   246	    expect(within(pestanas).getByRole('tab', { name: 'Todas' })).toBeInTheDocument()
   247	    expect(screen.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
   248	    expect(screen.getByText('3 de 3')).toBeInTheDocument()
   249	  })
   250	
   251	  it('cada fila dice de quién es, en qué estado está y desde cuándo, con la severidad en la tira', () => {
   252	    montar()
   253	    const lista = screen.getByRole('list', { name: /Pendientes del equipo/ })
   254	    const filas = within(lista).getAllByRole('listitem')
   255	    expect(filas).toHaveLength(3)
   256	    expect(filas[0]).toHaveAttribute('data-sev', 'critica')
   257	    expect(filas[0]).toHaveTextContent('Karen')
   258	    expect(filas[0]).toHaveTextContent('Primera gestión pendiente · venció hace 2 días')
   259	    expect(filas[1]).toHaveTextContent('Actividad vencida · venció hace 3 horas')
   260	    expect(filas[2]).toHaveAttribute('data-sev', 'media')
   261	    expect(filas[2]).toHaveTextContent('Seguimiento pendiente · vence en 3 horas')
   262	  })
   263	
   264	  it('monto y contacto SOLO con el lead completo del store (caché parcial: desconocido no es cero)', () => {
   265	    montar()
   266	    const filas = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')
   267	    expect(filas[0]).toHaveTextContent('S/ 20k')
   268	    expect(within(filas[0]!).getAllByRole('link', { name: /ROSA CHÁVEZ/ }).length + within(filas[0]!).queryAllByRole('button', { name: /número de ROSA CHÁVEZ|Llamar a ROSA CHÁVEZ/ }).length).toBeGreaterThan(0)
   269	    // VÍCTOR no está en el store: ni monto ni acciones de contacto.
   270	    expect(filas[1]).not.toHaveTextContent(/S\/|US\$/)
   271	    expect(within(filas[1]!).getAllByRole('button')).toHaveLength(1)
   272	    expect(filas[2]).toHaveTextContent('US$ 15k')
   273	  })
   274	
   275	  it('una fila sin fecha de referencia lo dice en vez de inventar un tiempo', () => {
   276	    RESPONDER = () => ({ data: pagina([item({ lead_id: 'l-9', nombre: 'SIN FECHA', analistaId: KAREN, analista: 'KAREN ZAPATA', referencia_en: null })], { totales: { pendientes: 1 } }), error: null, isFetching: false })
   277	    montar()
   278	    expect(screen.getByText(/Primera gestión pendiente · sin fecha confirmada/)).toBeInTheDocument()
   279	  })
   280	
   281	  it('el filtro por analista lo hace el SERVIDOR y los conteos son los suyos', () => {
   282	    montar()
   283	    const chips = screen.getByRole('group', { name: 'Filtrar por analista' })
   284	    // Solo analistas activos del equipo, sin conteos inventados en el cliente.
   285	    expect(within(chips).getAllByRole('button').map((b) => b.textContent)).toEqual(['Todos', 'Jorge', 'Karen'])
   286	    fireEvent.click(within(chips).getByRole('button', { name: 'KAREN ZAPATA' }))
   287	    expect(pedidoCola()?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: KAREN })
   288	    // Las decisiones siguen mirando a TODO el equipo.
   289	    expect(pedidoEquipo()?.filtros.analista_id).toBeNull()
   290	    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
   291	    expect(screen.getByRole('tab', { name: 'Para atender ahora: 2' })).toBeInTheDocument()
   292	    expect(screen.getByText('Mostrando los pendientes de Karen')).toHaveAttribute('aria-live', 'polite')
   293	    // Con el filtro, la columna del analista sobra.
   294	    const filas = within(screen.getByRole('list', { name: /Pendientes de Karen/ })).getAllByRole('listitem')
   295	    expect(filas).toHaveLength(2)
   296	    fireEvent.click(within(chips).getByRole('button', { name: 'Todos' }))
   297	    expect(pedidoCola()?.filtros.analista_id).toBeNull()
   298	  })
   299	
   300	  it('las flechas recorren las pestañas, mueven el foco y piden la señal al servidor', () => {
   301	    montar()
   302	    const primera = screen.getByRole('tab', { name: /Para atender ahora/ })
   303	    primera.focus()
   304	    fireEvent.keyDown(primera, { key: 'ArrowRight' })
   305	    const segunda = screen.getByRole('tab', { name: /Primera gestión/ })
   306	    expect(segunda).toHaveAttribute('aria-selected', 'true')
   307	    expect(segunda).toHaveFocus()
   308	    expect(pedidoCola()?.filtros.senal).toBe('primera_atencion')
   309	    fireEvent.keyDown(segunda, { key: 'End' })
   310	    expect(screen.getByRole('tab', { name: /^Todas/ })).toHaveAttribute('aria-selected', 'true')
   311	    // Con «Todas» abierta, su total sí es del servidor.
   312	    expect(screen.getByRole('tab', { name: 'Todas: 3' })).toBeInTheDocument()
   313	    fireEvent.keyDown(screen.getByRole('tab', { name: 'Todas: 3' }), { key: 'Home' })
   314	    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveFocus()
   315	  })
   316	
   317	  it('fail-closed: con error NO enseña la cola retenida y deja reintentar', () => {
   318	    RESPONDER = () => ({ data: pagina(colaTodo(), { totales: { pendientes: 3 } }), error: new Error('refetch caído'), isFetching: false })
   319	    montar()
   320	    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
   321	    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
   322	    expect(screen.getByText(/No se pudo cargar la cola/)).toBeInTheDocument()
   323	    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de los pendientes del equipo' }))
   324	    expect(REFETCH_COLA).toHaveBeenCalledTimes(1)
   325	  })
   326	
   327	  it('una página de OTRA revisión de reglas (caché) no se pinta mientras refresca', () => {
   328	    RESPONDER = (filtros) => ({ data: pagina(colaTodo(), { filtros: { ...filtros }, control_revision: 1 }), error: null, isFetching: true })
   329	    MODO.data = { control_revision: 2 }
   330	    montar()
   331	    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
   332	    expect(screen.getByText('Actualizando los pendientes con las reglas vigentes…')).toBeInTheDocument()
   333	    // Las decisiones tampoco usan esos conteos viejos.
   334	    expect(screen.queryByRole('button', { name: /primera gestión vencida/ })).not.toBeInTheDocument()
   335	  })
   336	
   337	  it('si el analista elegido sale del equipo, la cola deja de filtrarse por su id', () => {
   338	    const { rerender } = montar()
   339	    fireEvent.click(screen.getByRole('button', { name: 'KAREN ZAPATA' }))
   340	    expect(pedidoCola()?.filtros.analista_id).toBe(KAREN)
   341	    VENDEDORES = VENDEDORES.filter((m) => m.perfil_id !== KAREN)
   342	    rerender(<HoySupervisorMando />)
   343	    expect(pedidoCola()?.filtros.analista_id).toBeNull()
   344	    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
   345	    expect(screen.getByRole('button', { name: 'Todos' })).toHaveAttribute('aria-pressed', 'true')
   346	  })
   347	
   348	  it('si el analista elegido se DESACTIVA (sigue en el roster), el filtro también cae', () => {
   349	    const { rerender } = montar()
   350	    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
   351	    expect(pedidoCola()?.filtros.analista_id).toBe(JORGE)
   352	    VENDEDORES = VENDEDORES.map((m) => (m.perfil_id === JORGE ? { ...m, activo: false } : m))
   353	    rerender(<HoySupervisorMando />)
   354	    expect(pedidoCola()?.filtros.analista_id).toBeNull()
   355	    expect(screen.getByRole('button', { name: 'Todos' })).toHaveAttribute('aria-pressed', 'true')
   356	  })
   357	
   358	  it('una respuesta que ya no es del modo activo no se pinta como vigente', () => {
   359	    RESPONDER = () => ({ data: pagina(colaTodo(), { modo: 'legado' }), error: null, isFetching: false })
   360	    montar()
   361	    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
   362	    expect(screen.getByText(/Las reglas del seguimiento cambiaron/)).toBeInTheDocument()
   363	  })
   364	
   365	  it('cargando: lo dice, sin filas ni ceros', () => {
   366	    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
   367	    montar()
   368	    expect(screen.getByText('Cargando los pendientes del equipo…')).toBeInTheDocument()
   369	    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
   370	  })
   371	
   372	  it('vacío honesto por pestaña y por analista', () => {
   373	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
   374	    montar()
   375	    expect(screen.getByText(/Nada para atender ahora/)).toBeInTheDocument()
   376	    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
   377	    expect(screen.getByText('Jorge no tiene casos aquí.')).toBeInTheDocument()
   378	  })
   379	
   380	  it('abrir una ficha llama al store; si falla, lo avisa', async () => {
   381	    abrirLead.mockResolvedValueOnce(false)
   382	    montar()
   383	    const fila = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')[0]!
   384	    await act(async () => {
   385	      fireEvent.click(within(fila).getByRole('button', { name: 'Abrir ficha de ROSA CHÁVEZ, de Karen, urgente: Primera gestión pendiente · venció hace 2 días, S/ 20k' }))
   386	    })
   387	    expect(abrirLead).toHaveBeenCalledWith('l-1')
   388	    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo abrir la ficha')
   389	  })
   390	})
   391	
   392	describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
   393	  it('UNA severidad por analista: el no-show repetido es rojo en el punto, la cabecera y el detalle', () => {
   394	    METRICAS_AGENDA = agenda([
   395	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, toques: 9, pct_completadas: 50 },
   396	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' },
   397	    ])
   398	    montar()
   399	    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
   400	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   401	    const karen = within(equipo).getByRole('button', { name: /KAREN ZAPATA/ })
   402	    expect(karen).toHaveTextContent('2 citas sin asistir')
   403	    expect(within(karen).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
   404	    expect(karen).toHaveAttribute('aria-expanded', 'false')
   405	    fireEvent.click(karen)
   406	    expect(karen).toHaveAttribute('aria-expanded', 'true')
   407	    const detalle = document.getElementById(karen.getAttribute('aria-controls')!)!
   408	    expect(detalle).toBeVisible()
   409	    // El detalle NO repite la señal principal: trae las demás y los hechos.
   410	    expect(detalle).not.toHaveTextContent('2 citas sin asistir')
   411	    expect(detalle).toHaveTextContent('1 tarea vencida')
   412	    expect(detalle).toHaveTextContent('9 toques en 7 días · 50 % completadas')
   413	    // Y filtra la cola a sus pendientes.
   414	    expect(pedidoCola()?.filtros.analista_id).toBe(KAREN)
   415	    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
   416	  })
   417	
   418	  it('«Al día» solo con la agenda confirmada; sin ella no se afirma', () => {
   419	    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
   420	    montar()
   421	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   422	    expect(within(equipo).getByRole('button', { name: /JORGE HUAMÁN/ })).toHaveTextContent('Al día')
   423	    // Karen no tiene actividad desde el 20/09: 6 días, rojo. Jorge no cuenta.
   424	    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
   425	  })
   426	
   427	  it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día» ni «Sin alertas»', () => {
   428	    AGENDA_ERROR = new Error('agenda caída')
   429	    // Todos con actividad fresca: sin agenda, cero señales es DESCONOCIDO.
   430	    LEADS = [
   431	      lead({ creado_en: '2026-09-26T14:00:00Z' }),
   432	      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
   433	    ]
   434	    montar()
   435	    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
   436	    expect(screen.getByText(/La agenda del equipo no respondió/)).toBeInTheDocument()
   437	    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de la agenda del equipo' }))
   438	    expect(REFETCH_AGENDA).toHaveBeenCalledTimes(1)
   439	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   440	    expect(equipo).not.toHaveTextContent('Al día')
   441	  })
   442	
   443	  it('«Sin alertas» solo con la agenda confirmada y todos sin señal', () => {
   444	    LEADS = [
   445	      lead({ creado_en: '2026-09-26T14:00:00Z' }),
   446	      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
   447	    ]
   448	    montar()
   449	    expect(screen.getByText('Sin alertas en el equipo')).toBeInTheDocument()
   450	  })
   451	
   452	  it('mientras la agenda carga tampoco afirma «Sin alertas»', () => {
   453	    METRICAS_AGENDA = undefined
   454	    LEADS = [lead({ creado_en: '2026-09-26T14:00:00Z' })]
   455	    montar()
   456	    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
   457	  })
   458	
   459	  it('un analista sin leads abiertos conserva su alerta roja de agenda', () => {
   460	    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', no_asistio: 3 }])
   461	    montar()
   462	    const jorge = within(screen.getByRole('list', { name: 'Analistas del equipo' })).getByRole('button', { name: /JORGE HUAMÁN/ })
   463	    expect(jorge).toHaveTextContent('3 citas sin asistir')
   464	    expect(within(jorge).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
   465	  })
   466	
   467	  it('el enlace de la cabecera lleva a «Mi equipo hoy»', () => {
   468	    montar()
   469	    expect(screen.getByRole('link', { name: 'Mi equipo hoy' })).toHaveAttribute('href', '#/gestion-diaria')
   470	  })
   471	})
   472	
   473	describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
   474	  const conAgendaYReparto = () => {
   475	    METRICAS_AGENDA = agenda([
   476	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, leads_sin_accion: 1 },
   477	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 3 },
   478	    ])
   479	    // Un lead SIN analista: el reparto lo cuenta el resumen (espejo del RPC).
   480	    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
   481	  }
   482	
   483	  it('ESTADO DE PRODUCCIÓN: tres tarjetas, el rojo primero, cifra grande y la severidad en texto', () => {
   484	    conAgendaYReparto()
   485	    montar()
   486	    expect(screen.getByRole('heading', { name: 'Decide primero' })).toBeInTheDocument()
   487	    const tarjetas = document.querySelectorAll('[data-decision]')
   488	    // Rojo primero; entre los ámbar manda el peso fijo: el reparto antes que «sin próxima acción».
   489	    expect([...tarjetas].map((t) => t.getAttribute('data-decision'))).toEqual(['primera_gestion', 'no_asistio', 'por_repartir'])
   490	    const primera = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
   491	    expect(primera).toHaveTextContent('1')
   492	    expect(primera).toHaveTextContent('primera gestión vencida')
   493	    expect(screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })).toHaveTextContent('citas sin asistir · Karen')
   494	    // Lo que no entra en tres, a «Esta semana».
   495	    expect(screen.getByRole('button', { name: /Esta semana · 1/ })).toBeInTheDocument()
   496	  })
   497	
   498	  it('la primera gestión filtra la cola a ESA pestaña para todo el equipo; el segundo clic la devuelve', () => {
   499	    montar()
   500	    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
   501	    const tarjeta = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
   502	    fireEvent.click(tarjeta)
   503	    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
   504	    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!)).toHaveTextContent('Revisa la primera gestión con cada analista')
   505	    expect(screen.getByRole('tab', { name: /Primera gestión/ })).toHaveAttribute('aria-selected', 'true')
   506	    expect(pedidoCola()?.filtros).toEqual({ senal: 'primera_atencion', etapa: null, analista_id: null })
   507	    // La fuente de la tarjeta NO cambia de clave al cambiar la pestaña (Codex F2/F3).
   508	    expect(pedidoEquipo()?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: null })
   509	    expect(tarjeta).toBeInTheDocument()
   510	    fireEvent.click(tarjeta)
   511	    expect(tarjeta).toHaveAttribute('aria-expanded', 'false')
   512	    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveAttribute('aria-selected', 'true')
   513	  })
   514	
   515	  it('«Ver» lleva a la cola y le pasa el foco a la pestaña', () => {
   516	    montar()
   517	    fireEvent.click(screen.getByRole('button', { name: 'Ver en la cola: 1 primera gestión vencida' }))
   518	    act(() => { vi.advanceTimersByTime(32) })
   519	    const pestana = screen.getByRole('tab', { name: /Primera gestión/ })
   520	    expect(pestana).toHaveAttribute('aria-selected', 'true')
   521	    expect(pestana).toHaveFocus()
   522	  })
   523	
   524	  it('citas sin asistir NO filtran la cola (no contiene esos casos): despliegan y llevan al día del equipo', () => {
   525	    conAgendaYReparto()
   526	    montar()
   527	    const antes = pedidoCola()?.filtros
   528	    const tarjeta = screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })
   529	    fireEvent.click(tarjeta)
   530	    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
   531	    expect(pedidoCola()?.filtros).toEqual(antes)
   532	    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!))
   533	      .toHaveTextContent('En 7 días: 2 citas sin asistir · 1 tarea vencida · 1 lead sin próxima acción.')
   534	    expect(screen.getByRole('link', { name: 'Ver su día: KAREN ZAPATA: 2 citas sin asistir' })).toHaveAttribute('href', '#/gestion-diaria')
   535	  })
   536	
   537	  it('«Esta semana» lista lo que no entró, con su acción; Esc lo cierra y devuelve el foco', () => {
   538	    conAgendaYReparto()
   539	    montar()
   540	    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
   541	    fireEvent.click(disparador)
   542	    expect(disparador).toHaveAttribute('aria-expanded', 'true')
   543	    const lista = screen.getByRole('list', { name: 'Decisiones para esta semana' })
   544	    expect(lista).toHaveTextContent('Esta semana: JORGE HUAMÁN: 3 leads sin próxima acción')
   545	    const verDia = within(lista).getByRole('link', { name: 'Ver su día: JORGE HUAMÁN: 3 leads sin próxima acción' })
   546	    expect(verDia).toHaveAttribute('href', '#/gestion-diaria')
   547	    verDia.focus()
   548	    fireEvent.keyDown(document, { key: 'Escape' })
   549	    expect(disparador).toHaveAttribute('aria-expanded', 'false')
   550	    expect(disparador).toHaveFocus()
   551	  })
   552	
   553	  it('el reparto como tarjeta conserva la etiqueta accesible del servidor', () => {
   554	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
   555	    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
   556	    montar()
   557	    expect(screen.getByRole('link', { name: 'Repartir 1 lead pendiente' })).toHaveAttribute('href', '#/derivaciones')
   558	  })
   559	
   560	  it('con TODAS las fuentes confirmadas y nada pendiente dice «Nada que decidir»', () => {
   561	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
   562	    montar()
   563	    expect(screen.getByText('Nada que decidir ahora mismo.')).toBeInTheDocument()
   564	    expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
   565	  })
   566	
   567	  it('con una fuente AÚN cargando no ordena: ni la tarjeta que ya se conoce ocupa un puesto', () => {
   568	    // El seguimiento ya trae 1 primera gestión, pero la agenda no llegó.
   569	    METRICAS_AGENDA = undefined
   570	    montar()
   571	    expect(screen.getByText('Revisando las decisiones del día…')).toBeInTheDocument()
   572	    expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
   573	  })
   574	
   575	  it('mientras el seguimiento carga no afirma que no hay nada: «Revisando…»', () => {
   576	    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
   577	    montar()
   578	    expect(screen.getByText('Revisando las decisiones del día…')).toBeInTheDocument()
   579	    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
   580	  })
   581	
   582	  it('fail-closed: con el seguimiento o la agenda caídos lo dice, deja reintentar y nunca «Nada que decidir»', () => {
   583	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: new Error('caído'), isFetching: false })
   584	    AGENDA_ERROR = new Error('agenda caída')
   585	    montar()
   586	    expect(screen.getByText(/Algunas decisiones no se pudieron confirmar/)).toHaveTextContent('no respondió el seguimiento ni la agenda')
   587	    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
   588	    fireEvent.click(screen.getByRole('button', { name: 'Reintentar la carga de las decisiones del día' }))
   589	    expect(REFETCH_COLA).toHaveBeenCalled()
   590	    expect(REFETCH_AGENDA).toHaveBeenCalled()
   591	  })
   592	
   593	  it('sin el modo activo confirmado no hay banda de decisiones', () => {
   594	    MODO.activo = false
   595	    MODO.data = undefined
   596	    montar()
   597	    expect(screen.queryByRole('heading', { name: 'Decide primero' })).not.toBeInTheDocument()
   598	  })
   599	})
   600	
   601	describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () => {
   602	  it('ESTADO DE PRODUCCIÓN (sin metas publicadas): la franja da cifras con «—» donde no hay dato y sin jerga', () => {
   603	    METRICAS_AGENDA = agenda([
   604	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', toques: 6, completadas: 3, no_asistio: 1, pct_completadas: 75 },
   605	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', toques: 4, completadas: 0, no_asistio: 1 },
   606	    ])
   607	    montar()
   608	    const cifras = screen.getByRole('list', { name: 'Cifras del equipo' })
   609	    expect(cifras).toHaveTextContent('S/ 20k pronóstico · +US$ 15k aparte')
   610	    expect(cifras).toHaveTextContent('2 leads activos')
   611	    // Sin meta publicada no hay % de meta que inventar.
   612	    expect(cifras).toHaveTextContent('— de la meta')
   613	    expect(cifras).toHaveTextContent('— conversión del mes')
   614	    expect(cifras).toHaveTextContent('10 toques en 7 días')
   615	    expect(cifras).toHaveTextContent('60 % completadas')
   616	    // 2 no asistió en el equipo: el número va en rojo de TEXTO, con su palabra al lado.
   617	    const itemNoAsistio = within(cifras).getAllByRole('listitem').find((li) => li.textContent === '2 citas sin asistir')!
   618	    expect(itemNoAsistio.querySelector('strong')).toHaveStyle({ color: 'var(--destructive-text)' })
   619	    expect(document.body).not.toHaveTextContent(/pipeline|suma÷suma|solo producción/i)
   620	  })
   621	
   622	  it('«Detalle» abre un diálogo con TODO lo que la pantalla clásica mostraba; Esc lo cierra y el foco vuelve', () => {
   623	    vi.useRealTimers()
   624	    montar()
   625	    const boton = screen.getByRole('button', { name: 'Detalle' })
   626	    boton.focus()
   627	    fireEvent.click(boton)
   628	    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
   629	    for (const kpi of ['Pronóstico de capital abierto', 'Leads activos del equipo', 'Primeras gestiones vencidas', 'Por repartir']) {
   630	      expect(within(dialogo).getByText(kpi)).toBeInTheDocument()
   631	    }
   632	    expect(within(dialogo).getByText('Revísalas con cada analista')).toBeInTheDocument()
   633	    expect(within(dialogo).getByRole('heading', { name: 'Cumplimiento del mes' })).toBeInTheDocument()
   634	    expect(within(dialogo).getAllByText('Sin meta fijada para este mes').length).toBeGreaterThan(0)
   635	    expect(within(dialogo).getByRole('region', { name: 'Agenda del equipo' })).toBeInTheDocument()
   636	    expect(within(dialogo).getByText(/Ves solo a tu equipo/)).toBeInTheDocument()
   637	    expect(within(dialogo).getByRole('link', { name: 'Por repartir: Ver derivaciones; bandeja sin pendientes' })).toHaveAttribute('href', '#/derivaciones')
   638	    fireEvent.keyDown(dialogo, { key: 'Escape' })
   639	    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
   640	  })
   641	
   642	  it('«Cerrar» también cierra el detalle', () => {
   643	    vi.useRealTimers()
   644	    montar()
   645	    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
   646	    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cerrar' }))
   647	    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
   648	  })
   649	})
   650	
   651	describe('Hoy · supervisor — puesto de mando: arreglos de la revisión F2/F3', () => {
   652	  it('una conversión RETENIDA tras un error no se publica en la franja y el aviso es visible sin abrir el detalle', () => {
   653	    CONVERSION = {
   654	      data: {
   655	        version: 1, generado_en: '2026-09-26T15:00:00Z', alcance: 'equipo',
   656	        periodo: { mes: '2026-09', mes_nombre: 'septiembre', anio: 2026, zona: 'America/Lima', desde: '2026-09-01T05:00:00Z', hasta: '2026-10-01T05:00:00Z' },
   657	        ponderacion: { referido: 0.15, fuente: 'crm.conversion_pesos' },
   658	        fuentes: { divisor: 'x', numerador: 'x', referido: 'x' },
   659	        cobertura: { medible: true, suelo_historico: null, motivo_no_medible: null, divisor_aproximado: 0, divisor_por_motivo: { ingreso: 10 }, cierres_sin_episodio: 0, fuera_de_roster: { analistas: 0, divisor: 0, cierres: 0, numerador: 0 } },
   660	        cartera: {},
   661	        total: { analistas: 1, divisor: 10, cierres_no_referidos: 0, cierres_referidos: 0, cierres_de_arrastre: 0, referidos_recibidos: 0, numerador: 4, conversion_pct: 40, referidos_aporta_pct: null, cartera: {} },
   662	        responsables: [],
   663	      },
   664	      isError: true,
   665	    }
   666	    montar()
   667	    expect(screen.getByRole('list', { name: 'Cifras del equipo' })).toHaveTextContent('— conversión del mes')
   668	    expect(screen.getByText(/No se pudieron cargar algunos indicadores del equipo/)).toBeInTheDocument()
   669	  })
   670	
   671	  it('al cerrar «Detalle» con Esc el foco VUELVE al botón', async () => {
   672	    vi.useRealTimers()
   673	    montar()
   674	    const boton = screen.getByRole('button', { name: 'Detalle' })
   675	    boton.focus()
   676	    fireEvent.click(boton)
   677	    fireEvent.keyDown(screen.getByRole('dialog', { name: 'Detalle del equipo' }), { key: 'Escape' })
   678	    await waitFor(() => expect(boton).toHaveFocus())
   679	  })
   680	
   681	  it('«Esta semana» se cierra con un clic fuera y usa la etiqueta del reparto del servidor', () => {
   682	    METRICAS_AGENDA = agenda([
   683	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2 },
   684	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 5 },
   685	    ])
   686	    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
   687	    montar()
   688	    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
   689	    fireEvent.click(disparador)
   690	    const lista = screen.getByRole('list', { name: 'Decisiones para esta semana' })
   691	    expect(within(lista).getByRole('link', { name: 'Repartir 1 lead pendiente' })).toHaveAttribute('href', '#/derivaciones')
   692	    fireEvent.pointerDown(document.body)
   693	    expect(disparador).toHaveAttribute('aria-expanded', 'false')
   694	  })
   695	})
```

## `app/e2e/hoy-supervisor-mando.spec.ts` (estado FINAL completo)
```
     1	// Hoy del supervisor como puesto de mando (27/09/2026), en el MUNDO DE
     2	// PRODUCCIÓN: seguimiento ACTIVO. Se recorre con teclado a 1440×900 y se deja
     3	// una captura para la revisión visual de Miguel.
     4	import { expect, test } from '@playwright/test'
     5	import { loginReal } from './_helpers'
     6	import { montarColaEquipo } from './_sla-cola'
     7	
     8	test('supervisor: decide primero, cola filtrada en el servidor y detalle — todo con teclado', async ({ page }) => {
     9	  await page.setViewportSize({ width: 1440, height: 900 })
    10	  const { pedidos, analistaUno } = await montarColaEquipo(page, 'supervisor')
    11	  const errores: string[] = []
    12	  page.on('pageerror', (error) => errores.push(error.message))
    13	  await loginReal(page)
    14	
    15	  // 1 · Decide primero: la primera gestión vencida la cuenta el servidor.
    16	  await expect(page.getByRole('heading', { name: 'Decide primero', exact: true })).toBeVisible()
    17	  await expect(page.getByRole('button', { name: 'Hoy: 4 primeras gestiones vencidas' })).toBeVisible()
    18	
    19	  // 2 · Cola: vista previa de 7 del seguimiento, conteos del servidor.
    20	  await expect(page.getByRole('heading', { name: 'Pendientes del equipo', exact: true })).toBeVisible()
    21	  const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
    22	  await expect(lista.locator(':scope > li')).toHaveCount(7)
    23	  expect(pedidos.at(-1)).toMatchObject({ p_limite: 7, p_senal: 'pendientes', p_cursor: null })
    24	  await expect(page.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
    25	  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-1440x900.png'), animations: 'disabled' })
    26	
    27	  // Abrir la ficha con teclado y volver con Esc: el foco regresa a la fila
    28	  // (con `disabled` en la fila se perdía a <body>; revisor a11y P1).
    29	  const primeraFila = lista.locator(':scope > li').first().getByRole('button', { name: /^Abrir ficha de / })
    30	  await primeraFila.focus()
    31	  await page.keyboard.press('Enter')
    32	  await expect(page.getByRole('dialog')).toBeVisible()
    33	  await page.keyboard.press('Escape')
    34	  await expect(page.getByRole('dialog')).toHaveCount(0)
    35	  await expect(primeraFila).toBeFocused()
    36	
    37	  // Pestañas con flechas (tabindex itinerante) → la señal va al servidor.
    38	  await page.getByRole('tab', { name: /Para atender ahora/ }).focus()
    39	  await page.keyboard.press('ArrowRight')
    40	  await expect(page.getByRole('tab', { name: 'Primera gestión: 4' })).toBeFocused()
    41	  await expect.poll(() => pedidos.at(-1)?.p_senal).toBe('primera_atencion')
    42	  await expect(lista.locator(':scope > li')).toHaveCount(4)
    43	
    44	  // La tarjeta despliega su contexto y deja la cola en esa pestaña.
    45	  const tarjeta = page.getByRole('button', { name: 'Hoy: 4 primeras gestiones vencidas' })
    46	  await tarjeta.focus()
    47	  await page.keyboard.press('Enter')
    48	  await expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
    49	  await expect(page.getByText('Revisa la primera gestión con cada analista: abajo quedan solo esos casos.')).toBeVisible()
    50	
    51	  // Chip de analista: el filtro lo hace el SERVIDOR.
    52	  // Dos analistas con el mismo primer nombre: los chips los distinguen.
    53	  const chips = page.getByRole('group', { name: 'Filtrar por analista' })
    54	  await expect(chips.getByRole('button', { name: 'Analista Norte Uno' })).toHaveText('Analista U.')
    55	  await chips.getByRole('button', { name: 'Analista Norte Uno' }).click()
    56	  await expect.poll(() => pedidos.some((p) => p.p_analista_id === analistaUno)).toBe(true)
    57	  await expect(page.getByRole('heading', { name: 'Pendientes de Analista U.', exact: true })).toBeVisible()
    58	
    59	  // 3 · Detalle: Enter abre, Esc cierra y el foco vuelve al botón.
    60	  const detalle = page.getByRole('button', { name: 'Detalle', exact: true })
    61	  await detalle.focus()
    62	  await page.keyboard.press('Enter')
    63	  const dialogo = page.getByRole('dialog', { name: 'Detalle del equipo' })
    64	  await expect(dialogo).toBeVisible()
    65	  await expect(dialogo.getByRole('heading', { name: 'Cumplimiento del mes' })).toBeVisible()
    66	  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-detalle.png'), animations: 'disabled' })
    67	  await page.keyboard.press('Escape')
    68	  await expect(dialogo).toHaveCount(0)
    69	  await expect(detalle).toBeFocused()
    70	
    71	  // Sin jerga en pantalla.
    72	  await expect(page.locator('main')).not.toContainText(/pipeline|SLA/)
    73	  expect(errores).toEqual([])
    74	})
    75	
    76	test('supervisor: en un celular (375 px) la pantalla reacomoda sin cortar lo esencial', async ({ page }) => {
    77	  await page.setViewportSize({ width: 375, height: 800 })
    78	  await montarColaEquipo(page, 'supervisor')
    79	  // En el celular no hay menú de escritorio que esperar.
    80	  await loginReal(page, { esperarWorkspace: false })
    81	  await expect(page.getByRole('heading', { name: 'Pendientes del equipo', exact: true })).toBeVisible()
    82	  const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
    83	  await expect(lista.locator(':scope > li')).toHaveCount(7)
    84	  // Sin columna de analista, el dueño pasa a la segunda línea de cada fila.
    85	  await expect(lista.locator(':scope > li').first()).toContainText('Analista U. ·')
    86	  // Nada desborda en horizontal.
    87	  const desborde = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    88	  expect(desborde).toBeLessThanOrEqual(0)
    89	  await page.screenshot({ path: test.info().outputPath('hoy-supervisor-375.png'), fullPage: true, animations: 'disabled' })
    90	})
```

## Contexto (sin cambios)

### `app/src/components/common/aviso-degradacion.tsx`
```
     1	// aviso-degradacion.tsx — la franja que aparece cuando una fuente de métricas
     2	// se cae: la pantalla NO se bloquea, los indicadores quedan en «—» y aquí se
     3	// explica por qué, con un botón para reintentar (precedente objetivosError).
     4	//
     5	// Fuente ÚNICA a propósito. El patrón vivió clonado en 9 sitios y los defectos
     6	// que arrastraba estaban clonados con él:
     7	//   1. Texto en `muted-foreground` sobre el fondo ámbar: 4,25:1 a 12 px, por
     8	//      debajo del 4,5:1 exigible. Justo el texto que explica por qué faltan
     9	//      los números era el menos legible de la pantalla. Va en `warning-text`
    10	//      (6,34:1 medido sobre el fondo compuesto real).
    11	//   2. El botón se desmonta cuando el reintento SALE BIEN (el aviso desaparece
    12	//      con él) y el foco del teclado caía a <body>: había que retabular la
    13	//      pantalla entera. Lo recoge el ancla de abajo.
    14	// Cualquier aviso nuevo que use este componente nace con ambos resueltos.
    15	import { useEffect, useRef, type ReactNode } from 'react'
    16	import { cn } from '@/lib/utils'
    17	
    18	export interface AvisoDegradacionProps {
    19	  /** Si no, no hay nada que avisar (queda solo el ancla de foco, sin pintar). */
    20	  activo: boolean
    21	  /** Qué no se pudo cargar y qué implica. Frase completa, en español. */
    22	  children: ReactNode
    23	  /**
    24	   * Complemento que completa el nombre accesible del botón
    25	   * («Reintentar la carga ___»). Llega YA DECLINADO, con su preposición:
    26	   * «de los indicadores de la cartera», «del reloj SLA». Se pide así para no
    27	   * anteponer un `de` a ciegas y acabar diciendo «de el reloj SLA» en voz alta.
    28	   *
    29	   * Existe porque varias pantallas tienen más de un «Reintentar» a la vez
    30	   * —Pipeline muestra dos avisos, y las listas traen el suyo en el panel de
    31	   * error— y en el rotor del lector se verían botones idénticos.
    32	   */
    33	  queReintenta: string
    34	  onReintentar: () => void
    35	}
    36	
    37	export function AvisoDegradacion({
    38	  activo,
    39	  children,
    40	  queReintenta,
    41	  onReintentar,
    42	}: AvisoDegradacionProps) {
    43	  // Ancla SIEMPRE montada, `sr-only` cuando no hay aviso —absoluta y recortada,
    44	  // NUNCA `hidden`: un display:none no se puede enfocar— para que sobreviva al
    45	  // aviso y recoja el foco cuando el botón se va. Al estar en la MISMA posición
    46	  // del DOM, el siguiente Tab continúa por donde tocaba. tabIndex={-1} = destino
    47	  // programático, no alcanzable con Tab, que es lo que hace legítimo el
    48	  // outline-none.
    49	  const ancla = useRef<HTMLDivElement>(null)
    50	  const boton = useRef<HTMLButtonElement>(null)
    51	  const esperandoFoco = useRef(false)
    52	  const activoPrevio = useRef(activo)
    53	
    54	  // El rescate del foco se cuelga del cambio de `activo`, NO del click: el
    55	  // reintento es un refetch de red y el aviso desaparece cientos de ms después,
    56	  // no en el par de cuadros siguientes. Colgarlo del click dejaba el rescate en
    57	  // código muerto (lo cazó la revisión de Codex y la de a11y).
    58	  useEffect(() => {
    59	    const desaparecio = activoPrevio.current && !activo
    60	    activoPrevio.current = activo
    61	    if (!desaparecio || !esperandoFoco.current) return
    62	    esperandoFoco.current = false
    63	    // Solo si el foco quedó huérfano: si el usuario ya se movió a otro control
    64	    // —el reintento pudo tardar—, no se lo robamos. Tras un desmontaje algunos
    65	    // motores dejan `activeElement` en null en vez de en <body>.
    66	    const foco = document.activeElement
    67	    if (!foco || foco === document.body) ancla.current?.focus()
    68	  }, [activo])
    69	
    70	  return (
    71	    <div ref={ancla} tabIndex={-1} className={cn('outline-none', !activo && 'sr-only')}>
    72	      {/* La región vive SIEMPRE en el DOM y el contenido llega después: es el
    73	          orden fiable para que un lector de pantalla anuncie el cambio.
    74	          `status` (polite) y no `alert`: la pantalla queda operable con «—», no
    75	          hay nada urgente ni con plazo, y un anuncio asertivo interrumpiría la
    76	          lectura en curso sin necesidad. */}
    77	      <div role="status">
    78	        {activo && (
    79	          <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warning/30 bg-warning/5 px-3 py-2 text-xs text-warning-text">
    80	            <span>{children}</span>
    81	            <button
    82	              ref={boton}
    83	              type="button"
    84	              aria-label={`Reintentar la carga ${queReintenta}`}
    85	              // Anillo SÓLIDO (4,62:1): el token /40 de la casa se queda en
    86	              // 1,76:1 y no llega al 3:1 que exige un indicador de foco. El
    87	              // subrayado añade un segundo canal que no depende del color.
    88	              className="rounded font-semibold text-foreground underline-offset-2 hover:underline focus-visible:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring"
    89	              onClick={() => {
    90	                // Solo hay foco que rescatar si el foco estaba de verdad AQUÍ.
    91	                // Con ratón puede no estarlo (Safari no enfoca al hacer clic):
    92	                // inferirlo de <body> daría un falso positivo y movería el foco
    93	                // de quien nunca lo tuvo puesto (hallazgo de Codex).
    94	                esperandoFoco.current = document.activeElement === boton.current
    95	                onReintentar()
    96	              }}
    97	            >
    98	              Reintentar
    99	            </button>
   100	          </div>
   101	        )}
   102	      </div>
   103	    </div>
   104	  )
   105	}
```

### `app/src/components/ui/dialog.tsx`
```
     1	// Modal centrado sobre Radix Dialog (accesibilidad completa: focus-trap real,
     2	// fondo inerte, scroll lock, Esc por capas — con modales apilados cierra SOLO
     3	// el de más arriba — y retorno de foco al cerrar). El aspecto es el mismo de
     4	// siempre: mismas clases, mismos keyframes. API sin cambios: open/onClose.
     5	import { useRef, type HTMLAttributes, type ReactNode, type RefObject } from 'react'
     6	import * as RadixDialog from '@radix-ui/react-dialog'
     7	import { cn } from '@/lib/utils'
     8	import { cerrarEscapeAnidado, protegerEscapeAnidado } from './escape-dialogo'
     9	
    10	const KEYFRAMES = `
    11	@keyframes ac-dialog-overlay { from { opacity: 0 } to { opacity: 1 } }
    12	@keyframes ac-dialog-panel { from { opacity: 0; transform: translateY(10px) scale(0.96) } to { opacity: 1; transform: none } }
    13	@media (prefers-reduced-motion: reduce) {
    14	  [data-slot='dialog'], [data-slot='dialog-overlay'] { animation: none !important }
    15	}
    16	`
    17	
    18	interface DialogProps {
    19	  open: boolean
    20	  onClose: () => void
    21	  children: ReactNode
    22	  ariaLabel?: string
    23	  /** Una acción puede transferir explícitamente el foco a otra vista/panel. */
    24	  focoAlCerrar?: RefObject<HTMLElement | null> | undefined
    25	  /**
    26	   * Dónde empieza el foco al abrir (si existe), en vez del primer control. Un `autoFocus`
    27	   * no basta en un modal apilado sobre otro: la trampa del de abajo lo roba antes de que
    28	   * la del nuevo se registre, y Radix acaba enfocando el primer control.
    29	   */
    30	  focoInicial?: RefObject<HTMLElement | null> | undefined
    31	  /** Clases extra para el panel (p. ej. ancho distinto). */
    32	  className?: string
    33	}
    34	
    35	export function Dialog({ open, onClose, children, ariaLabel, className, focoAlCerrar, focoInicial }: DialogProps) {
    36	  // Estos modales se controlan desde acciones externas, sin Radix.Trigger.
    37	  // Una resolución puede retirar la acción: conservamos también su ficha.
    38	  const origenFoco = useRef<HTMLElement | null>(null)
    39	  const ambitoFoco = useRef<HTMLElement | null>(null)
    40	  const contenido = useRef<HTMLDivElement | null>(null)
    41	  return (
    42	    <RadixDialog.Root open={open} onOpenChange={(sigueAbierto) => { if (!sigueAbierto) onClose() }}>
    43	      <RadixDialog.Portal>
    44	        <RadixDialog.Overlay
    45	          data-slot="dialog-overlay"
    46	          className="fixed inset-0 z-50 bg-primary/25 backdrop-blur-[2px]"
    47	          style={{ animation: 'ac-dialog-overlay 0.2s ease both' }}
    48	        />
    49	        {/* Contenedor de layout no interactivo: el click en el padding cae al overlay. */}
    50	        <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center p-4">
    51	          <RadixDialog.Content
    52	            ref={contenido}
    53	            onEscapeKeyDown={(evento) => protegerEscapeAnidado(evento, contenido.current)}
    54	            onKeyDown={(evento) => cerrarEscapeAnidado(evento, onClose)}
    55	            onOpenAutoFocus={(evento) => {
    56	              const activo = document.activeElement
    57	              const origen = activo instanceof HTMLElement && activo !== document.body ? activo : null
    58	              origenFoco.current = origen
    59	              ambitoFoco.current = origen?.closest<HTMLElement>('[role="dialog"]') ?? null
    60	              if (focoInicial?.current) {
    61	                evento.preventDefault()
    62	                focoInicial.current.focus({ preventScroll: true })
    63	              }
    64	            }}
    65	            onCloseAutoFocus={(evento) => {
    66	              if (focoAlCerrar) {
    67	                evento.preventDefault()
    68	                requestAnimationFrame(() => focoAlCerrar.current?.focus({ preventScroll: true }))
    69	                return
    70	              }
    71	              const origen = origenFoco.current
    72	              const ambito = ambitoFoco.current
    73	              origenFoco.current = null
    74	              ambitoFoco.current = null
    75	              if (!origen?.isConnected && !ambito?.isConnected) return
    76	              evento.preventDefault()
    77	              // Esperar a que Radix retire la trampa del diálogo que se cierra.
    78	              requestAnimationFrame(() => {
    79	                const destino = origen?.isConnected && !origen.matches(':disabled, [aria-disabled="true"]')
    80	                  ? origen : ambito?.isConnected ? ambito : null
    81	                destino?.focus({ preventScroll: true })
    82	                // Un nodo conectado también puede quedar oculto o inerte.
    83	                if (document.activeElement !== destino && ambito?.isConnected) ambito.focus({ preventScroll: true })
    84	              })
    85	            }}
    86	            aria-label={ariaLabel}
    87	            aria-describedby={undefined}
    88	            data-slot="dialog"
    89	            className={cn(
    90	              'pointer-events-auto relative flex max-h-[85vh] w-[520px] max-w-[92vw] flex-col rounded-xl border border-border bg-card text-card-foreground shadow-[var(--shadow-pop)] outline-none',
    91	              className,
    92	            )}
    93	            style={{ animation: 'ac-dialog-panel 0.3s var(--ease-out-expo) both' }}
    94	          >
    95	            <style>{KEYFRAMES}</style>
    96	            {children}
    97	          </RadixDialog.Content>
    98	        </div>
    99	      </RadixDialog.Portal>
   100	    </RadixDialog.Root>
   101	  )
   102	}
   103	
   104	export function DialogHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
   105	  return <div className={cn('flex flex-col gap-1 border-b border-border px-5 py-4', className)} {...props} />
   106	}
   107	
   108	/** Título accesible: Radix lo enlaza como aria-labelledby del dialog. */
   109	export function DialogTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
   110	  return (
   111	    <RadixDialog.Title asChild>
   112	      <h2 className={cn('text-[15px] font-bold tracking-tight', className)} {...props} />
   113	    </RadixDialog.Title>
   114	  )
   115	}
   116	
   117	export function DialogDescription({ className, ...props }: HTMLAttributes<HTMLParagraphElement>) {
   118	  return <p className={cn('text-xs text-muted-foreground', className)} {...props} />
   119	}
   120	
   121	/** Cuerpo con scroll interno si el contenido crece (`ac-scroll`). */
   122	export function DialogBody({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
   123	  return <div className={cn('ac-scroll flex-1 overflow-y-auto px-5 py-4', className)} {...props} />
   124	}
   125	
   126	export function DialogFooter({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
   127	  return <div className={cn('flex items-center justify-end gap-2 border-t border-border px-5 py-3', className)} {...props} />
   128	}
```

### `app/src/screens/hoy/datos-supervisor.ts`
```
     1	// Datos COMPARTIDOS de Hoy · supervisor (27/09/2026). Los usan las dos
     2	// pantallas del rol: la clásica (./supervisor.tsx, que sigue sirviendo el modo
     3	// legado y el demo) y el puesto de mando (./supervisor-mando.tsx, modo activo).
     4	// Se extrajeron tal cual de supervisor.tsx para que la meta, el reparto, la
     5	// agenda y el tipo de cambio tengan UNA sola derivación: dos copias de esta
     6	// lógica divergirían en silencio. La cola NO vive aquí: cada modo trae la suya.
     7	import { useEffect, useMemo, useRef, useState } from 'react'
     8	import {
     9	  DIA_MS,
    10	  capitalPrincipal,
    11	  diasSinActividad,
    12	  haceCortoTexto,
    13	  indexarUltimaActividad,
    14	  pctMeta,
    15	} from '@/lib/inteligencia'
    16	import { fechaLima } from '@/lib/agenda-derivada'
    17	import {
    18	  capitalObjetivo,
    19	  metaVigente,
    20	  capitalReal,
    21	  metaConversionAplicable,
    22	  objetivosCero,
    23	  periodoLima,
    24	} from '@/lib/objetivos'
    25	import { useConversionMensual, useMetricasAgenda } from '@/data/crm-queries'
    26	import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
    27	import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
    28	import { useAhora } from '@/lib/ahora'
    29	import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
    30	import { useAuth } from '@/lib/auth-context'
    31	import { useCRMData } from '@/lib/store-context'
    32	import { mensajeDeError } from '@/data/crm-api'
    33	import { money, moneyK, numero, porcentajeConversionCanonica } from '@/lib/format'
    34	import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
    35	import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
    36	import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
    37	import { useTipoCambio } from '@/lib/tipo-cambio'
    38	
    39	// Texto neutro de una meta que gerencia todavía no fijó para el mes.
    40	const SIN_META = 'Sin meta fijada para este mes'
    41	
    42	export interface FilaMeta {
    43	  label: string
    44	  txt: string
    45	  pct: number
    46	  sinDato: string | null
    47	  nota?: string | null
    48	}
    49	
    50	export function useDatosSupervisor() {
    51	  const {
    52	    ambito,
    53	    actividades,
    54	    objetivos,
    55	    objetivosError,
    56	    cumplimientoMetas,
    57	    cumplimientoMetasError,
    58	    recargar,
    59	    equipo,
    60	  } = useCRMData()
    61	  const { yo } = useAuth()
    62	  // Reloj vivo: tick por minuto y al volver a la pestaña — la bandeja y los
    63	  // "hace N" se refrescan solos al pasar el tiempo.
    64	  const ahora = useAhora()
    65	  const periodoVigente = periodoLima(ahora)
    66	  const periodoStoreIntentado = useRef<string | null>(null)
    67	  const [recargaPeriodoFallida, setRecargaPeriodoFallida] = useState(false)
    68	  const fotoMensualStoreVigente = yo?.demo === true || (
    69	    objetivos.periodo === periodoVigente
    70	    && (cumplimientoMetas == null || cumplimientoMetas.periodo === periodoVigente)
    71	  )
    72	  useEffect(() => {
    73	    if (yo?.demo || fotoMensualStoreVigente
    74	      || periodoStoreIntentado.current === periodoVigente) return
    75	    periodoStoreIntentado.current = periodoVigente
    76	    setRecargaPeriodoFallida(false)
    77	    void recargar().then((ok) => {
    78	      if (!ok) setRecargaPeriodoFallida(true)
    79	    })
    80	  }, [fotoMensualStoreVigente, periodoVigente, recargar, yo?.demo])
    81	
    82	  // ── F1b: los agregados llegan del servidor (o del espejo demo vivo) ──
    83	  // resumen_cartera_fn → tiles de capital/activos/parkeados;
    84	  // metricas_vendedores_fn → ranking.
    85	  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
    86	  const resumen = resumenOp.resumen
    87	  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividades)
    88	  const rank = vendedoresOp.metricas?.filas ?? null
    89	  // TC izado UNA vez por pantalla: el hook no pasa por TanStack (sin cache ni
    90	  // dedupe), así que uno por fila multiplicaría las llamadas a la edge.
    91	  const { tc, recargar: recargarTipoCambio } = useTipoCambio()
    92	  const diaTipoCambio = fechaLima(ahora)
    93	  const diaTipoCambioAnterior = useRef(diaTipoCambio)
    94	  useEffect(() => {
    95	    if (diaTipoCambioAnterior.current === diaTipoCambio) return
    96	    diaTipoCambioAnterior.current = diaTipoCambio
    97	    recargarTipoCambio()
    98	  }, [diaTipoCambio, recargarTipoCambio])
    99	  // Pronóstico: `capitalPrincipal` (criterio compartido con Cartera/Pipeline),
   100	  // NUNCA un total mixto. Antes se fijaba PEN a mano y un equipo que vende en
   101	  // dólares se titulaba «S/ 0».
   102	  const capitalPronostico = resumen
   103	    ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd)
   104	    : null
   105	  // HOY solo resume la bandeja; la operación completa vive en Derivar leads.
   106	  // Conservamos el índice local para resumir la espera observable del caso más
   107	  // rezagado sin añadir otra consulta; si no hubo actividad, parte del ingreso.
   108	  // Fase 3 «sin topes»: en sesión real el arranque ya no baja el registro de
   109	  // actividades, y sin él la «espera» de un parkeado caería a `creado_en`
   110	  // (un lead de 30 días parkeado hace una hora diría «30 días»; su
   111	  // `tenencia_desde` se anula al quedar sin analista). Antes que exagerar, en
   112	  // sesión real se omite la antigüedad: el conteo del RPC sigue siendo la
   113	  // verdad y el CTA lo dice sin cifra. En demo sigue el timeline del fixture.
   114	  const bandejaReparto = useMemo(() => {
   115	    const parkeados = ambito.leads.filter(
   116	      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado' && l.vendedor_id == null,
   117	    )
   118	    const indice = indexarUltimaActividad(actividades)
   119	    return { parkeados, indice }
   120	  }, [ambito, actividades])
   121	
   122	  const esperaMasLargaReparto = useMemo(() => {
   123	    if (!yo?.demo) return null
   124	    if (bandejaReparto.parkeados.length === 0) return null
   125	    let maxima = 0
   126	    for (const lead of bandejaReparto.parkeados) {
   127	      maxima = Math.max(
   128	        maxima,
   129	        diasSinActividad(lead, actividades, ahora, bandejaReparto.indice),
   130	      )
   131	    }
   132	    return maxima
   133	  }, [actividades, ahora, bandejaReparto, yo?.demo])
   134	
   135	  // El conteo del RPC sigue siendo la autoridad. Si el detalle local aún no
   136	  // está disponible, el CTA conserva la verdad y omite la antigüedad.
   137	  const totalPorRepartir = resumen?.totales.parkeados ?? null
   138	  const hayPorRepartir = (totalPorRepartir ?? 0) > 0
   139	  const detalleReparto = totalPorRepartir == null
   140	    ? 'Sin dato por ahora · Ver derivaciones →'
   141	    : hayPorRepartir
   142	      ? esperaMasLargaReparto == null
   143	        ? 'Pendientes en tu bandeja · Repartir →'
   144	        : `Más rezagado: ${haceCortoTexto(esperaMasLargaReparto)} · Repartir →`
   145	      : 'Bandeja al día · Ver historial →'
   146	  const etiquetaAccesoReparto = totalPorRepartir == null
   147	    ? 'Ver derivaciones; total por repartir no disponible'
   148	    : hayPorRepartir
   149	      ? `Repartir ${totalPorRepartir} ${totalPorRepartir === 1 ? 'lead pendiente' : 'leads pendientes'}`
   150	      : 'Ver derivaciones; bandeja sin pendientes'
   151	
   152	  // La meta sale del snapshot cuando lo hay: si un analista se fue o cambió
   153	  // de equipo, su meta y su producción viajan juntas (ver `metaVigente`).
   154	  const fotoMensualStoreCargando = !yo?.demo
   155	    && !fotoMensualStoreVigente
   156	    && !recargaPeriodoFallida
   157	  const objetivosMensualesError = fotoMensualStoreVigente
   158	    ? objetivosError
   159	    : recargaPeriodoFallida
   160	  const cumplimientoMensualError = fotoMensualStoreVigente
   161	    ? cumplimientoMetasError
   162	    : recargaPeriodoFallida
   163	  const objetivosMensuales = fotoMensualStoreVigente
   164	    ? objetivos
   165	    : objetivosCero(periodoVigente)
   166	  const cumplimientoMensual = fotoMensualStoreVigente ? cumplimientoMetas : null
   167	  const meta = metaVigente(objetivosMensuales.supervisor, cumplimientoMensual?.supervisor ?? null)
   168	  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
   169	  const cumplimiento = cumplimientoMensual?.supervisor ?? null
   170	  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
   171	  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
   172	  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
   173	  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
   174	
   175	  // LA CONVERSIÓN DEL MES del EQUIPO — total del payload de alcance 'equipo'
   176	  // (crm.conversion_mensual_fn), no el cumplimiento: la definición acordada
   177	  // llega ya, sin esperar a la migración B (E1, plan §4bis). El total viene
   178	  // RECALCULADO del servidor (suma÷suma, jamás media de porcentajes).
   179	  const esDemoConversion = yo?.demo === true
   180	  const qConversionMensual = useConversionMensual(
   181	    !esDemoConversion,
   182	    periodoVigente,
   183	    'equipo',
   184	    yo?.id,
   185	  )
   186	  const conversionMensualCargando = !esDemoConversion
   187	    && qConversionMensual.isPending
   188	    && qConversionMensual.data === undefined
   189	  const conversionMensual = esDemoConversion
   190	    ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
   191	    : conversionMensualCargando
   192	      ? undefined
   193	      : (qConversionMensual.data ?? null)
   194	  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
   195	  // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
   196	  // 2026-08-14). La regla vive en `lecturaCobertura`, compartida con las otras
   197	  // tres pantallas que pintan esta misma cifra.
   198	  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
   199	  const totalConversion = totalConversionPublicable(conversionMensual)
   200	  const conversionConfirmada = totalConversion?.conversion_pct ?? null
   201	  const recibidosEquipo = totalConversion?.divisor ?? null
   202	  // ── Cumplimiento del mes ──────────────────────────────────────────────────
   203	  // PEN y USD ya NO van por separado: la meta se pacta en soles (el editor
   204	  // escribe todo en `nuevo/PEN`), así que la fila de dólares vivía en «Sin meta
   205	  // fijada» para siempre mientras el capital real en USD no movía ninguna
   206	  // barra. Se consolida con el MISMO tipo de cambio en numerador y denominador
   207	  // —comparar a tasas distintas es comparar peras con manzanas— igual que en el
   208	  // panel del analista y en el de gerencia.
   209	  const capitalConfirmado = totalEnSoles(capitalConfirmadoPen, capitalConfirmadoUsd, tc?.promedio)
   210	  const metaCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
   211	  const hayDolares = (capitalConfirmadoUsd ?? 0) > 0 || metaCapitalUsd > 0
   212	  const tcEnVuelo = tc === undefined && hayDolares
   213	  const tcCaido = tc === null && hayDolares
   214	  const ajusteCierre = cumplimiento?.ajuste
   215	  const notaAjusteCierre = ajusteCierre != null && (
   216	    ajusteCierre.aplicadoPen > 0
   217	    || ajusteCierre.aplicadoUsd > 0
   218	    || ajusteCierre.contratosAplicados > 0
   219	  )
   220	    ? [
   221	        'Neto tras ajuste de cierre',
   222	        ajusteCierre.aplicadoPen > 0 ? `−${money(ajusteCierre.aplicadoPen, 'PEN')}` : null,
   223	        ajusteCierre.aplicadoUsd > 0 ? `−${money(ajusteCierre.aplicadoUsd, 'USD')}` : null,
   224	        ajusteCierre.contratosAplicados > 0
   225	          ? `−${numero(ajusteCierre.contratosAplicados)} ${ajusteCierre.contratosAplicados === 1 ? 'contrato' : 'contratos'}`
   226	          : null,
   227	      ].filter(Boolean).join(' · ')
   228	    : null
   229	  const notaCapitalMonedas = !tcEnVuelo && (capitalConfirmadoUsd ?? 0) > 0
   230	    ? `${moneyK(capitalConfirmadoPen ?? 0, 'PEN')} + ${moneyK(capitalConfirmadoUsd ?? 0, 'USD')}`
   231	      + (capitalConfirmado.tc == null
   232	        ? ' · sin tipo de cambio: el total NO incluye los dólares'
   233	        : ` · ${rotuloTipoCambio(capitalConfirmado.tc, tc?.fuente ?? 'TC del día')}`)
   234	    : null
   235	  const filasMeta: FilaMeta[] = [
   236	    {
   237	      label: 'Capital confirmado',
   238	      txt:
   239	        tcEnVuelo
   240	          ? 'Calculando…'
   241	          : (metaCapital.total ?? 0) > 0 && capitalConfirmado.total != null
   242	          ? `${moneyK(capitalConfirmado.total, 'PEN')} de ${moneyK(metaCapital.total ?? 0, 'PEN')}`
   243	          : capitalConfirmado.total == null ? '—' : moneyK(capitalConfirmado.total, 'PEN'),
   244	      pct: tcEnVuelo ? 0 : pctMeta(capitalConfirmado.total ?? 0, metaCapital.total ?? 0),
   245	      // El desglose solo aporta cuando hay dólares; si no, repetiría el total.
   246	      nota: [notaCapitalMonedas, notaAjusteCierre].filter(Boolean).join(' · ') || null,
   247	      sinDato: fotoMensualStoreCargando
   248	        ? 'Actualizando la meta y el cumplimiento de este mes…'
   249	        : objetivosMensualesError
   250	        ? 'Meta mensual no disponible'
   251	        : tcEnVuelo
   252	          ? 'Consultando el tipo de cambio para consolidar los dólares…'
   253	          : (metaCapital.total ?? 0) <= 0
   254	            ? SIN_META
   255	            : cumplimientoMensualError || capitalConfirmado.total == null
   256	              ? 'Cumplimiento confirmado no disponible'
   257	              : null,
   258	    },
   259	    {
   260	      label: 'Conversión del mes',
   261	      txt:
   262	        conversionMensualCargando
   263	          ? 'Calculando…'
   264	          : conversionConfirmada == null
   265	          ? '—'
   266	          : metaConversion != null
   267	            ? `${porcentajeConversionCanonica(conversionConfirmada)} de ${metaConversion}% · ${numero(recibidosEquipo)} recibidos`
   268	            : `${porcentajeConversionCanonica(conversionConfirmada)} · ${numero(recibidosEquipo)} recibidos`,
   269	      // El porqué de que la cifra no sea definitiva viaja PEGADO a ella. Antes
   270	      // esto la sustituía, y un mes con recibidos y cierres decía «sin datos».
   271	      nota: lecturaConversion.aviso,
   272	      pct: pctMeta(conversionConfirmada ?? 0, metaConversion ?? 0),
   273	      sinDato: conversionMensualCargando
   274	        ? 'Consultando la conversión del mes…'
   275	        : conversionMensualError
   276	          ? 'Conversión del mes no disponible'
   277	          : !lecturaConversion.mostrar
   278	          ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
   279	          : conversionConfirmada == null
   280	            ? 'Sin leads recibidos este mes'
   281	            : fotoMensualStoreCargando
   282	              ? 'Actualizando la meta de este mes…'
   283	              : objetivosMensualesError
   284	              ? 'Meta mensual no disponible'
   285	              : metaConversion == null
   286	                ? SIN_META
   287	                : null,
   288	    },
   289	  ]
   290	  const hayErrorMensual = objetivosMensualesError || cumplimientoMensualError || conversionMensualError || tcCaido
   291	  const reintentarMensual = () => {
   292	    if (objetivosMensualesError || cumplimientoMensualError) {
   293	      setRecargaPeriodoFallida(false)
   294	      void recargar().then((ok) => {
   295	        if (!ok && !fotoMensualStoreVigente) setRecargaPeriodoFallida(true)
   296	      })
   297	    }
   298	    if (conversionMensualError) void qConversionMensual.refetch()
   299	    if (tcCaido) recargarTipoCambio()
   300	  }
   301	
   302	  // ── Fase F — Agenda del equipo (RPC crm.metricas_agenda_fn) ──
   303	  // Periodo fijo: últimos 7 días con el reloj vivo (se corre solo al pasar la
   304	  // medianoche de Lima). En demo se alimenta del fixture sin tocar la red.
   305	  const sesionReal = Boolean(yo && !yo.demo)
   306	  const hastaMA = fechaLima(ahora)
   307	  const desdeMA = fechaLima(ahora - 6 * DIA_MS)
   308	  const consultaAgenda = useMetricasAgenda(sesionReal, desdeMA, hastaMA)
   309	  // En sesión real con data aún undefined y sin error, viaja undefined a
   310	  // propósito: el panel muestra su estado de carga.
   311	  const datosAgenda = sesionReal ? consultaAgenda.data : metricasAgendaDemo(desdeMA, hastaMA)
   312	  const errorAgenda =
   313	    sesionReal && consultaAgenda.error
   314	      ? mensajeDeError(
   315	          consultaAgenda.error,
   316	          'No pudimos consultar la agenda del equipo. Revisa tu conexión e inténtalo otra vez.',
   317	        )
   318	      : null
   319	  const cargandoAgenda =
   320	    sesionReal && (consultaAgenda.isPending || consultaAgenda.isFetching)
   321	  const recargarAgenda = () => {
   322	    if (sesionReal) void consultaAgenda.refetch()
   323	  }
   324	  // Rezagos de agenda por miembro (vendedor_id → métrica) para que la señal de
   325	  // vencidas / sin acción / no-shows viva DENTRO de la fila de "Tu equipo hoy":
   326	  // la persona se juzga en un solo lugar, sin cruzar a la tabla de la izquierda.
   327	  const rezagosAgenda = useMemo(
   328	    () => new Map((datosAgenda?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
   329	    [datosAgenda],
   330	  )
   331	  // Para DECIDIR (franja y semáforos del puesto de mando) la agenda cuenta
   332	  // solo si está confirmada: TanStack conserva la última respuesta tras un
   333	  // refetch fallido, y una señal vieja no puede pasar por vigente.
   334	  const agendaConfirmada = errorAgenda == null ? datosAgenda : undefined
   335	
   336	  return {
   337	    ahora,
   338	    ambito,
   339	    actividades,
   340	    equipo,
   341	    resumenOp,
   342	    resumen,
   343	    vendedoresOp,
   344	    rank,
   345	    tc,
   346	    capitalPronostico,
   347	    esperaMasLargaReparto,
   348	    totalPorRepartir,
   349	    hayPorRepartir,
   350	    detalleReparto,
   351	    etiquetaAccesoReparto,
   352	    cumplimientoMensual,
   353	    conversionConfirmada,
   354	    conversionMensualError,
   355	    filasMeta,
   356	    hayErrorMensual,
   357	    reintentarMensual,
   358	    sesionReal,
   359	    datosAgenda,
   360	    agendaConfirmada,
   361	    errorAgenda,
   362	    cargandoAgenda,
   363	    recargarAgenda,
   364	    rezagosAgenda,
   365	  }
   366	}
```

### `app/src/lib/tres-cosas.ts`
```
     1	// lib/tres-cosas.ts — la franja «Hoy, tres cosas» del supervisor (F3,
     2	// 2026-08-23). Ley de Tesler aplicada: el SISTEMA absorbe la priorización del
     3	// día — qué mirar primero — en vez de dejar que el supervisor escanee cinco
     4	// tarjetas. Máximo TRES intervenciones (Hick/Miller), cada una con su acción.
     5	//
     6	// Reglas de la casa que esta función custodia:
     7	// · Sin dato NO hay tarjeta: un candidato solo existe si su fuente llegó
     8	//   (nada de «—» en la franja; la degradación se avisa en AvisoDegradacion).
     9	// · Presupuesto de color: rojo = interviene HOY (nuevos sin responder,
    10	//   no-show repetido); ámbar = esta semana. El rojo va siempre primero.
    11	// · Espejo de la campana (lib/alertas.ts): mismas DECISIONES y mismos
    12	//   umbrales (no_asistio ≥ 2 · sin acción ≥ 3, crítica ≥ 5). Los CONTEOS
    13	//   pueden diferir a propósito: la campana deduplica lead a lead y trabaja
    14	//   sobre ambito.leads (tope 2000); la franja lee los agregados del RPC
    15	//   (universo completo, foto actual). Misma decisión, lentes distintas —
    16	//   auditado y aceptado (Codex F3 #2).
    17	// · Degradación honesta: con cola null (cargando o error) el candidato NO
    18	//   existe y no se inventa urgencia desde el store local; el fallo se avisa
    19	//   en AvisoDegradacion, que es el canal de errores de la pantalla (F3 #4).
    20	// · Seguimiento ACTIVO (producción desde el 07/09/2026): la cola legada no se
    21	//   consulta y `cola` llega null. La interrupción del día sale entonces del
    22	//   conteo del seguimiento (`primeraGestionPendiente`, 27/09/2026).
    23	import type { MetricaAgendaVendedor } from './metricas-agenda'
    24	import { haceTexto } from './inteligencia'
    25	import { primerNombre } from './format'
    26	import { TOPE_ESTANCADOS, type ColaAccionOperativa } from './cola-accion'
    27	
    28	/** Pestaña de la cola a la que salta una cosa (espejo del tablist de HOY). */
    29	export type PestanaColaDestino = 'urgente' | 'sin_movimiento' | 'todo'
    30	
    31	export type DestinoCosa =
    32	  | { tipo: 'pestana'; pestana: PestanaColaDestino }
    33	  | { tipo: 'vista'; vista: 'derivaciones' | 'equipo' | 'seguimiento' }
    34	
    35	export interface CosaDeHoy {
    36	  id: 'sin_responder' | 'primera_gestion' | 'no_asistio' | 'por_repartir' | 'sin_accion' | 'sin_movimiento'
    37	  severidad: 'critica' | 'atencion'
    38	  texto: string
    39	  /** Etiqueta del enlace/botón — siempre hay UNA acción al lado del rojo. */
    40	  accion: string
    41	  destino: DestinoCosa
    42	  /** Dueño de la cosa cuando señala a UN analista (agrupada = ausente). */
    43	  vendedorId?: string
    44	}
    45	
    46	export interface TresCosasInput {
    47	  /** Cola operativa (null = sin dato: ese candidato no existe). */
    48	  cola: ColaAccionOperativa | null
    49	  /** Total autorizado por resumen_cartera_fn (null = sin dato). */
    50	  totalPorRepartir: number | null
    51	  /** Espera observable del parkeado más rezagado, en días (null = sin detalle). */
    52	  esperaMasLargaReparto: number | null
    53	  /** Métricas de agenda por analista (vacío = sin dato o sin rezago). */
    54	  vendedoresAgenda: readonly MetricaAgendaVendedor[]
    55	  /**
    56	   * Seguimiento activo: leads cuya primera gestión ya venció, según
    57	   * `totales.primera_atencion` de crm.cola_accion_v2_fn (null/ausente = sin
    58	   * dato). La señal solo existe con el plazo vencido y su aviso es crítico
    59	   * por definición en private.sla_operacion_leads: si hay alguno, es rojo.
    60	   */
    61	  primeraGestionPendiente?: number | null
    62	}
    63	
    64	/** Peso del candidato dentro de su severidad (menor = primero). */
    65	const PESO: Record<CosaDeHoy['id'], number> = {
    66	  sin_responder: 0,
    67	  primera_gestion: 0,
    68	  no_asistio: 1,
    69	  por_repartir: 2,
    70	  sin_accion: 3,
    71	  sin_movimiento: 4,
    72	}
    73	
    74	const TOPE = 3
    75	
    76	/**
    77	 * Deriva las (a lo sumo) tres intervenciones del día del supervisor.
    78	 * Devuelve [] cuando no hay nada que hacer O nada que decir con datos: la
    79	 * franja entera no se pinta — el silencio también es información.
    80	 */
    81	export function tresCosasDeHoy(input: TresCosasInput): CosaDeHoy[] {
    82	  return candidatosDeHoy(input).slice(0, TOPE)
    83	}
    84	
    85	/**
    86	 * Todos los candidatos del día, ya ordenados (rojo primero, peso fijo), SIN
    87	 * el recorte a tres: lo que no entra en la franja va a «Esta semana».
    88	 */
    89	export function candidatosDeHoy({
    90	  cola,
    91	  totalPorRepartir,
    92	  esperaMasLargaReparto,
    93	  vendedoresAgenda,
    94	  primeraGestionPendiente,
    95	}: TresCosasInput): CosaDeHoy[] {
    96	  const cosas: CosaDeHoy[] = []
    97	
    98	  // 1 · Nuevos sin responder — la interrupción del día (un lead nuevo se
    99	  //     enfría por horas). Autoridad del CONTEO: el resumen por bucket del
   100	  //     RPC. La SEVERIDAD sale de los items: un nuevo de dos horas es media
   101	  //     para el RPC y pintarlo rojo desalinearía franja, cola y campana
   102	  //     (Codex F3 #1) — rojo solo cuando algún sin_responder ya es crítico.
   103	  const sinResponder = cola?.porBucket.sin_responder ?? 0
   104	  if (cola != null && sinResponder > 0) {
   105	    const hayCritico = cola.items.some(
   106	      (i) => i.bucket === 'sin_responder' && i.sev === 'critica',
   107	    )
   108	    cosas.push({
   109	      id: 'sin_responder',
   110	      severidad: hayCritico ? 'critica' : 'atencion',
   111	      texto: `${sinResponder} ${sinResponder === 1 ? 'nuevo sin responder' : 'nuevos sin responder'}`,
   112	      accion: 'Ver',
   113	      destino: { tipo: 'pestana', pestana: 'urgente' },
   114	    })
   115	  }
   116	
   117	  // 1b · Seguimiento activo: la primera gestión vencida es la misma
   118	  //      interrupción del día, contada por el servidor.
   119	  if (primeraGestionPendiente != null && primeraGestionPendiente > 0) {
   120	    cosas.push({
   121	      id: 'primera_gestion',
   122	      severidad: 'critica',
   123	      texto: `${primeraGestionPendiente} ${primeraGestionPendiente === 1 ? 'primera gestión vencida' : 'primeras gestiones vencidas'}`,
   124	      accion: 'Ver',
   125	      destino: { tipo: 'vista', vista: 'seguimiento' },
   126	    })
   127	  }
   128	
   129	  // 2 · No-show repetido — el otro rojo del presupuesto (≥2, umbral de la
   130	  //     campana y de «Tu equipo hoy»). Con varios analistas se agrupa.
   131	  // Solo ANALISTAS activos: el RPC también trae la fila del propio
   132	  // supervisor, y sin este filtro su agenda ocupaba un cupo disfrazada de
   133	  // problema de analista (Codex F3 #3) — mismo corte que la campana.
   134	  const vendedores = vendedoresAgenda.filter((v) => v.rol === 'vendedor' && v.activo)
   135	  const conNoShow = vendedores
   136	    .filter((v) => v.no_asistio >= 2)
   137	    .sort((a, b) => b.no_asistio - a.no_asistio || a.vendedor_id.localeCompare(b.vendedor_id))
   138	  const peorNoShow = conNoShow[0]
   139	  if (peorNoShow != null) {
   140	    cosas.push({
   141	      id: 'no_asistio',
   142	      severidad: 'critica',
   143	      texto: conNoShow.length === 1
   144	        ? `${peorNoShow.nombre}: ${peorNoShow.no_asistio} citas sin asistir`
   145	        : `${conNoShow.length} analistas con citas sin asistir`,
   146	      accion: 'Ver equipo',
   147	      destino: { tipo: 'vista', vista: 'equipo' },
   148	      ...(conNoShow.length === 1 ? { vendedorId: peorNoShow.vendedor_id } : {}),
   149	    })
   150	  }
   151	
   152	  // 3 · Por repartir — el conteo es SIEMPRE el del servidor; el rezago solo
   153	  //     acompaña si el detalle local llegó (misma regla del KPI compacto).
   154	  if (totalPorRepartir != null && totalPorRepartir > 0) {
   155	    cosas.push({
   156	      id: 'por_repartir',
   157	      severidad: 'atencion',
   158	      texto: `${totalPorRepartir} por repartir`
   159	        + (esperaMasLargaReparto != null ? ` · el más rezagado ${haceTexto(esperaMasLargaReparto)}` : ''),
   160	      accion: 'Repartir',
   161	      destino: { tipo: 'vista', vista: 'derivaciones' },
   162	    })
   163	  }
   164	
   165	  // 4 · Analista con más leads sin próxima acción (≥3, umbral de la campana).
   166	  const conSinAccion = vendedores
   167	    .filter((v) => v.leads_sin_accion >= 3)
   168	    .sort((a, b) => b.leads_sin_accion - a.leads_sin_accion || a.vendedor_id.localeCompare(b.vendedor_id))
   169	  const peorSinAccion = conSinAccion[0]
   170	  if (peorSinAccion != null) {
   171	    cosas.push({
   172	      id: 'sin_accion',
   173	      // Desde 5 es crítico — el MISMO umbral que la campana (Codex F3 #1).
   174	      severidad: peorSinAccion.leads_sin_accion >= 5 ? 'critica' : 'atencion',
   175	      texto: conSinAccion.length === 1
   176	        ? `${peorSinAccion.nombre}: ${peorSinAccion.leads_sin_accion} leads sin próxima acción`
   177	        : `${conSinAccion.length} analistas con leads sin próxima acción`,
   178	      accion: 'Ver equipo',
   179	      destino: { tipo: 'vista', vista: 'equipo' },
   180	      ...(conSinAccion.length === 1 ? { vendedorId: peorSinAccion.vendedor_id } : {}),
   181	    })
   182	  }
   183	
   184	  // 5 · Sin movimiento — el peor caso del bloque estancados del RPC (≥5 días).
   185	  const peorEstancado = cola?.estancados[0]
   186	  if (cola != null && peorEstancado != null) {
   187	    // Al tope del RPC el conteo dice «50+», igual que la pestaña: con 50
   188	    // justos afirmar «50» sería mentir por omisión (Codex F3 #6).
   189	    const conteoEstancados = cola.estancados.length >= TOPE_ESTANCADOS
   190	      ? `${TOPE_ESTANCADOS}+`
   191	      : String(cola.estancados.length)
   192	    cosas.push({
   193	      id: 'sin_movimiento',
   194	      severidad: 'atencion',
   195	      texto: `${conteoEstancados} sin movimiento · el peor lleva ${haceTexto(peorEstancado.dias).replace('hace ', '')}`,
   196	      accion: 'Ver',
   197	      destino: { tipo: 'pestana', pestana: 'sin_movimiento' },
   198	    })
   199	  }
   200	
   201	  // Rojo primero, luego el peso fijo: el orden es una decisión, no un azar.
   202	  return cosas.sort((a, b) => (
   203	    (a.severidad === b.severidad ? 0 : a.severidad === 'critica' ? -1 : 1)
   204	    || PESO[a.id] - PESO[b.id]
   205	  ))
   206	}
   207	
   208	/**
   209	 * Cifra y título de una cosa para pintarla en grande (Hoy del supervisor,
   210	 * puesto de mando): «4 primeras gestiones vencidas» → 4 + «primeras gestiones
   211	 * vencidas»; «KAREN ZAPATA: 2 citas sin asistir» → 2 + «citas sin asistir ·
   212	 * Karen». Sin número, sin cifra: el texto queda entero.
   213	 */
   214	export function partesDeCosa(texto: string): { cifra: string | null; resto: string } {
   215	  const inicial = /^(\d+\+?)\s+(.*)$/.exec(texto)
   216	  if (inicial) return { cifra: inicial[1] ?? null, resto: inicial[2] ?? texto }
   217	  const deAnalista = /^(.+?):\s+(\d+\+?)\s+(.*)$/.exec(texto)
   218	  if (deAnalista) return { cifra: deAnalista[2] ?? null, resto: `${deAnalista[3] ?? ''} · ${primerNombre(deAnalista[1])}` }
   219	  return { cifra: null, resto: texto }
   220	}
```

### `app/e2e/_sla-cola.ts`
```
     1	import type { Page } from '@playwright/test'
     2	import { leadReal, montarBackendReal, UID } from './_helpers'
     3	import muestraSql from '../src/data/sla-operacion-sql.test.fixture.json' with { type: 'json' }
     4	
     5	export type PedidoCola = {
     6	  p_cursor: { inicio: number } | null
     7	  p_limite: number
     8	  p_senal: string
     9	  p_etapa?: string
    10	  p_analista_id?: string
    11	}
    12	
    13	export async function montarColaEquipo(page: Page, rolCrm: 'gerencia' | 'supervisor' | 'vendedor', cantidad = 14) {
    14	  const analistaUno = 'aaaaaaaa-0000-4000-8000-000000000001'
    15	  const analistaDos = 'aaaaaaaa-0000-4000-8000-000000000002'
    16	  const analistaAjeno = 'aaaaaaaa-0000-4000-8000-000000000003'
    17	  const equipoVisible = [
    18	    { perfil_id: analistaUno, nombre_completo: 'Analista Norte Uno', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
    19	    { perfil_id: analistaDos, nombre_completo: 'Analista Norte Dos', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
    20	    ...(rolCrm === 'gerencia' ? [{ perfil_id: analistaAjeno, nombre_completo: 'Analista Sur', rol_crm: 'vendedor', supervisor_id: null, activo: true }] : []),
    21	  ]
    22	  const cartera = Array.from({ length: cantidad }, (_, i) => leadReal({
    23	    id: `cccccccc-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
    24	    nombre_completo: `OPORTUNIDAD ${i < 12 ? 'NORTE' : 'SUR'} ${String(i + 1).padStart(2, '0')}`,
    25	    vendedor_id: rolCrm === 'vendedor' ? UID : i < 6 ? analistaUno : i < 12 ? analistaDos : analistaAjeno,
    26	    fueraDelBoot: i >= 100,
    27	    etapa: i % 4 < 2 ? 'contactado' : 'propuesta_enviada',
    28	  }))
    29	  // La respuesta simula el ámbito de la RPC, no autorización en el navegador.
    30	  // El banco SQL prueba RLS: aquí comprobamos que la UI conserva sus filas y
    31	  // envía filtros al servidor sin sustituirlos por una búsqueda del store.
    32	  const visibles = rolCrm === 'gerencia' ? cartera : cartera.slice(0, 12)
    33	  await montarBackendReal(page, { rolCrm, leads: visibles })
    34	  await page.route('**/rest/v1/rpc/equipo_visible_fn', (route) => route.fulfill({ json: [
    35	    { perfil_id: UID, nombre_completo: 'Responsable del equipo', rol_crm: rolCrm, supervisor_id: null, activo: true },
    36	    ...equipoVisible,
    37	  ] }))
    38	  const calculado = '2026-09-07T12:00:00.000Z'
    39	  const filas = visibles.map((lead, i) => {
    40	    const original = muestraSql.cola.items[0]!
    41	    const revision = i % 2 === 0
    42	    return {
    43	      ...original, lead_id: lead.id,
    44	      bucket: i % 3 === 0 ? 'primera_atencion' : i % 3 === 1 ? 'tarea_vencida' : 'seguimiento',
    45	      severidad: i % 3 === 0 ? 'critica' : 'media', prioridad: 10 + i,
    46	      referencia_en: calculado,
    47	      lead: { id: lead.id, nombre_completo: lead.nombre_completo, etapa: lead.etapa,
    48	        analista_id: lead.vendedor_id, analista_nombre: lead.vendedor_id === UID ? 'Analista de prueba' : equipoVisible.find((miembro) => miembro.perfil_id === lead.vendedor_id)!.nombre_completo },
    49	      senales: { pendientes: true, primera_atencion: i % 3 === 0, tareas_vencidas: i % 3 === 1,
    50	        seguimientos_pendientes: i % 3 === 2, revisiones: revision, datos_incompletos: false, por_repartir: false },
    51	      estado: { ...original.estado, lead_id: lead.id,
    52	        compromiso: i % 5 === 4 ? original.estado.compromiso : { tarea: null, validez: 'sin_tarea', hasta_en: null, cobertura_activa: false },
    53	        etapa: { ...original.estado.etapa,
    54	        revision_requerida: revision, motivos_revision: revision ? ['limite_operativo_agotado'] : [] } },
    55	    }
    56	  })
    57	  // Caso histórico como el que motivó aclarar los textos: seguimiento, etapa
    58	  // y Agenda tienen fechas distintas. La UI debe explicar cada una por separado.
    59	  const ejemplo = filas[0]!.estado
    60	  ejemplo.seguimiento = { ...ejemplo.seguimiento, limite_en: '2026-09-07T04:03:00Z', vencido: true, accion_pendiente: true }
    61	  ejemplo.compromiso = {
    62	    tarea: { id: 'eeeeeeee-0000-4000-8000-000000000001', tipo: 'llamada', vence_en: '2026-08-31T15:00:00Z', reprogramaciones: 0 },
    63	    validez: 'valido', cobertura_activa: false, hasta_en: '2026-08-31T19:00:00Z',
    64	  }
    65	  ejemplo.avisos = [...ejemplo.avisos, { ...ejemplo.avisos[0]!, id: 'revision-ejemplo', bucket: 'revision_comercial', tarea_id: null }]
    66	  ejemplo.etapa = { ...ejemplo.etapa,
    67	    limite_original_en: '2026-09-01T15:00:00Z', limite_prorrogado_en: '2026-09-01T15:00:00Z',
    68	    limite_operativo_en: '2026-09-01T15:00:00Z', techo_en: '2026-09-02T16:21:00Z',
    69	    prorrogas_usadas: 0,
    70	  }
    71	  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', async (route) => {
    72	    const args = route.request().postDataJSON() as { p_lead_ids: string[] }
    73	    await route.fulfill({ json: { ...muestraSql.estado, calculado_en: calculado,
    74	      filas: args.p_lead_ids.map((id) => filas.find((fila) => fila.lead_id === id)?.estado ?? { ...muestraSql.estado.filas[0], lead_id: id }) } })
    75	  })
    76	  const pedidos: PedidoCola[] = []
    77	  await page.route('**/rest/v1/rpc/cola_accion_v2_fn', async (route) => {
    78	    const args = route.request().postDataJSON() as PedidoCola
    79	    pedidos.push(args)
    80	    const ambito = filas.filter((fila) => (!args.p_etapa || fila.lead.etapa === args.p_etapa)
    81	      && (!args.p_analista_id || fila.lead.analista_id === args.p_analista_id))
    82	    const filtradas = args.p_senal === 'todas' ? ambito : ambito.filter((fila) => fila.senales[args.p_senal as keyof typeof fila.senales])
    83	    const inicio = args.p_cursor?.inicio ?? 0
    84	    const items = filtradas.slice(inicio, inicio + args.p_limite)
    85	    const hayMas = inicio + items.length < filtradas.length
    86	    const totales = Object.fromEntries(Object.keys(filas[0]!.senales).map((senal) => [senal,
    87	      ambito.filter((fila) => fila.senales[senal as keyof typeof fila.senales]).length]))
    88	    await route.fulfill({ json: { ...muestraSql.cola, calculado_en: calculado, limite: args.p_limite,
    89	      // La RPC aplica DEFAULT NULL a argumentos omitidos y devuelve ambas claves.
    90	      filtros: { senal: args.p_senal, etapa: args.p_etapa ?? null, analista_id: args.p_analista_id ?? null },
    91	      total_items: filtradas.length, rango: { desde: items.length ? inicio + 1 : 0, hasta: inicio + items.length },
    92	      hay_mas: hayMas, cursor_siguiente: hayMas ? { inicio: inicio + items.length } : null,
    93	      totales, items,
    94	    } })
    95	  })
    96	  return { pedidos, analistaUno, analistaDos, analistaAjeno }
    97	}
```

---
## PROTOCOLO DEL PROYECTO (.ai/REVIEW_PROTOCOL.md, íntegro)
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.

## PROTOCOLO GLOBAL (~/.config/ai-collaboration/REVIEW_PROTOCOL.md, íntegro)
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
