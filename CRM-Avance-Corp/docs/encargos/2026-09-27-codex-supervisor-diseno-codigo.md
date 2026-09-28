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

# Encargo: REFUTAR la IMPLEMENTACIÓN del rediseño de la pantalla del SUPERVISOR («Mi equipo hoy») — LEVEL 2

Ya HAY código: el plan v2 (que corrigió tus 10 hallazgos del plan) está implementado en una copia
aislada sobre el commit publicado 8d4be227. Se revisa el DIFF completo antes de enseñarlo y publicarlo. Tu trabajo es encontrar lo que el plan rompe, olvida o subestima: funciones en
producción que se perderían, efectos sobre GERENCIA (que reutiliza piezas del supervisor),
regresiones de accesibilidad y de foco, el panel adaptable (en línea ↔ ventana), la selección
automática, estados vacíos/caídos/sin permiso, pruebas faltantes y si el corte en fases es sano.
Si el plan es correcto en un punto, no lo menciones.

## Contexto

CRM interno (React 19 + Vite + Tailwind 4 + Supabase) de una empresa de inversiones en Lima.
Miguel trajo un diseño («Gestión diaria pantallas», hecho para un proyecto hermano) y pidió
aplicarlo manteniendo los colores del CRM (navy #111e3d + azul #2563eb, Plus Jakarta Sans, SIN
verde). Un plan por pantalla. La del ANALISTA ya está hecha y PUBLICADA hoy (27/09) en tres
releases: franja de cifras, «Ahora» con aire de celular a todo el alto, cola en pestañas, resultado
dentro de la tarjeta, «Lo último con este lead». De ahí salieron piezas comunes que el supervisor
debe reutilizar: `FranjaCifras`, `BarrasPorHora`, `Tabs` con variantes `subrayado`/`pastilla` y
`panelEnfocable`, `Avatar` con `relleno`, `components/app/actividad-visual.ts` (iconos y «hace X»).
Todas están transcritas abajo. La de GERENCIA vendrá después.

Otra sesión acaba de construir (sin publicar) el «Hoy del supervisor — puesto de mando» en `#/hoy`
(`screens/hoy/supervisor-mando.tsx`, `lib/senal-equipo.ts`, `lib/cola-supervision.ts`,
`lib/tres-cosas.ts`). Un análisis de solape concluyó: NO comparte archivos con este rediseño y NO
muestra la actividad del día (llamadas, contacto, citas, barras, últimas gestiones); para el
detalle diario enlaza a `#/gestion-diaria` con el texto «Mi equipo hoy →» y su prueba
`supervisor-mando.test.tsx:469-471` exige ese destino. Sus semáforos salen de OTRAS fuentes
(agenda de 7 días, `cola_accion_v2_fn`) y usa «Primera gestión vencida» donde Gestión Diaria dice
«Primer intento fuera de plazo».

### Qué dibuja el diseño para el supervisor («Mi equipo hoy», 1440×1000)
- Cabecera: «Mi equipo hoy» (título grande) + «Actividad registrada, pendientes y analistas que
  necesitan atención.»; a la derecha «Sábado 26 sep 2026 · Actualizado 16:30» y botón «Actualizar».
- Franja (tarjeta) de 5 cifras: 5 Analistas · 4 Con registro · 1 Sin registro · 5 Con pendientes ·
  4 Necesitan atención (este en rojo).
- Izquierda, tarjeta con barra: buscador «Buscar analista…», selector «Todos», píldora
  «Con atención (4)» con el 4 en círculo rojo, enlace «Registro del equipo». Tabla: Analista
  (círculo de iniciales + nombre), Llamadas, Contacto («18 %» + chip «Bajo»/«Bien»/«Atención», o
  «67 % 3 útiles» sin nivel), Citas, Vencidas (número rojo si >0), Atención ↓ (texto: «4 vencidas»
  rojo, «1 vencida», «Primer intento tarde» ámbar, «—»). Fila elegida resaltada. Pie: «5 de 5
  analistas · Actualizado 16:30» | «La actividad registrada no acredita presencia.»
- Derecha, panel (≈390 px) SIEMPRE abierto con quien más atención necesita: iniciales + «Karen Díaz»
  + «Analista · equipo de Mónica Rivas»; pestañas subrayadas Resumen · Registro · Pendientes.
  Resumen: aviso rojo suave «⚠ 4 tareas vencidas ›»; 4 cuadros 2×2 (Llamadas 12 · «2
  contestaron» | Contacto 18 % · «de 11 llamadas útiles · Bajo» | Citas agendadas 0 · «desde
  «Agendó cita»» | WhatsApp 5 · «enviados y respondidos»); «Llamadas por hora» con «Última llamada
  16:05 · hace 25 min» y barras apiladas contestaron/no contestaron con número encima, 08–19;
  «Últimas gestiones»: 3 filas «16:05 [No contestó] Gabriel Ortiz León»; botón azul ancho «Ver el
  registro del día».

## Decisiones del dueño (NO son hallazgos)
1. Colores del CRM, menú navy sin cambios, sin verde; la escala de letra y el aire del DISEÑO
   rigen en Gestión Diaria (27/09: «hay demasiada letra, la proximidad está mal»), con controles
   que crecen a 44 px en pantallas táctiles (`pointer-coarse`).
2. Un plan por pantalla; Codex revisa cada plan antes; nada empieza sin su OK.
3. Horizontal, nunca apilado en vertical en escritorio.
4. «No complicar, ejecutar»: el dueño decide lo irreversible o lo que no puede deducirse del código;
   los defaults defendibles los toma el agente y los dice en una línea.

## Qué se implementó (resumen; el diff manda)
- `lib/gestion-diaria-equipo.ts`: `PRIORIDAD_MOTIVO`, `compararGravedad`, `presentarAtencion` (texto con número,
  tono vencido/aviso, «+N», lista), `presentarContacto` (3 estados), `OrdenEquipo` 'citas', `FiltrosEquipo.gravedad`.
- `TablaEquipoDiaria`: prop `contexto` ('gerencia' por defecto = la tabla de siempre, SIN cambios; 'supervisor' = la nueva).
- `PanelSupervisorAdaptable`: prop `claseAlojamiento` (el supervisor usa la suya para no heredar los cortes de
  `supervisor.css`, que siguen siendo de gerencia; OJO: la raíz de gerencia TAMBIÉN se llama `gd-supervisor`).
- `supervisor.tsx`: estilos propios (`mi-equipo.css`), umbral en línea 1076 px, selección automática con `origen`
  (`automatica`/`usuario`/`aviso`) e inhibición (`autoInhibida`), el modal excluye las automáticas y una automática
  se CIERRA al estrecharse (o pasa a `usuario` si el foco está dentro), barra siempre presente con «Registro del
  equipo», franja `FranjaCifras` en línea con «Necesitan atención» en ámbar, pie con `role=status` SIN la hora,
  refresco manual (el de cada minuto no cambia el botón), reintento con foco al título / aviso si vuelve a fallar,
  foco al título de la alerta si un error reemplaza la tabla con el foco dentro, anuncio al ordenar.
- `PanelAnalistaSupervisor`: cabecera con iniciales y h3 «Detalle de» oculto (espacio FUERA del sr-only: dentro se
  perdía → «Detalle deANA»), pestañas subrayadas con el tabpanel como contenedor con scroll, cada vista vuelve arriba,
  `silencioso` para la automática. `ResumenAnalista` nuevo (sustituye a `DetalleAnalista` SOLO en el supervisor).
- Reestilizados: `UltimasGestionesSupervisor`, `FranjaCortesSupervisor` (44 px de alto), `PendientesSupervisor`
  (`aria-disabled` + guarda, foco al título si «Cargar más»/«Reintentar» se desmonta, `role=list`).
- `supervisor.css`: retiradas 4 reglas sin uso (gd-estado, gd-atencion-detalle, gd-cortes-resumen, gd-cortes-consulta).
- `tabs.tsx`: la activa `subrayado` se subraya en forced-colors. `gestion-diaria.tsx`: el supervisor usa el enlace
  compacto «Seguimiento completo ›». `analista.tsx`: mismo arreglo del espacio fuera del sr-only en «Contacto 1 de 3».
- Pruebas: unitarias nuevas (lógica, tabla por contexto, franja en línea, resumen, selección automática con dos
  mutantes que fallan si se rompen sus reglas) y E2E migrados al diseño (piso 11 px en vez de 16; filas de 52 px en
  vez de 44 y 6/5 filas visibles a 1512×805/1366×768 en vez de 10/9 — decisión del dueño: manda la escala del diseño;
  el panel abre solo con quien necesita atención; `.gd-cortes` → selector por nombre).
- Verificación hasta ahora: typecheck y oxlint limpios; vitest de las zonas tocadas 1307/1307.

## Preguntas concretas
1. ¿La máquina de estados de la selección automática tiene huecos (carreras con `registroPedido`, `fueraDeAmbito`,
   cambio de fecha, el primer render antes de medir el ancho, `seleccionar` sobre la automática)?
2. ¿Algo del diff cambia GERENCIA (clases compartidas, `supervisor.css`, `TablaEquipoDiaria` por defecto,
   `PanelSupervisorAdaptable`, `tabs.tsx`)?
3. ¿Las migraciones de pruebas debilitan la cobertura en vez de trasladarla?
4. ¿Los nuevos manejos de foco (reintento, error con foco en la tabla, desmontajes en Pendientes/Últimas) pueden
   robar el foco o dejarlo en un lugar peor?

## DIFF COMPLETO (git diff 8d4be227 -- CRM-Avance-Corp/app)
```diff
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-cortes.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-cortes.spec.ts
index 72375e1f..a3e8bf63 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-cortes.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-cortes.spec.ts
@@ -65,7 +65,7 @@ test('H4: franja compacta, otro analista seleccionado, llamadas y ficha conserva
   const franja = page.getByRole('region', { name: 'Estado de cortes y avisos' })
   await expect(franja).toContainText('16:00 Programado')
   const medidas = await vista.evaluate((e) => ({
-    franja: e.querySelector('.gd-cortes')!.getBoundingClientRect().toJSON(),
+    franja: e.querySelector('[aria-label="Estado de cortes y avisos"]')!.getBoundingClientRect().toJSON(),
     scroll: e.closest<HTMLElement>('[data-vista-scroll]')!.scrollHeight - e.closest<HTMLElement>('[data-vista-scroll]')!.clientHeight,
   }))
   expect(medidas.franja.height).toBeLessThanOrEqual(45); expect(medidas.scroll).toBeLessThanOrEqual(1)
@@ -97,7 +97,8 @@ test('H4: franja compacta, otro analista seleccionado, llamadas y ficha conserva
   await dialogo.getByRole('button', { name: 'Ver pendientes', exact: true }).click()
   await expect(page).toHaveURL(/#\/seguimiento$/)
   await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
-  await expect(page.getByText('Selecciona un analista de la tabla para consultar su día.')).toBeVisible()
+  // Al volver, abre sola con quien más atención necesita (ANA H4, 1 vencida; plan v2, 27/09).
+  await expect(page.getByRole('region', { name: 'Detalle de ANA H4', exact: true })).toBeVisible()
 })
 
 test('H4: aplazar una vez, reintento con mismo UUID y reconocimiento reflejado en campana', async ({ page }) => {
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts
index e49d8c7f..acfe2740 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts
@@ -4,7 +4,8 @@ import { entrarDemo, leadReal, loginReal, montarBackendReal, UID } from './_help
 import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
 import { fechaLima } from '../src/lib/agenda-derivada'
 
-test('Supervisor: roster demo, búsqueda y detalle con texto de al menos 16 px', async ({ page }, info) => {
+// Escala del diseño de Gestión Diaria (Miguel, 27/09/2026): el piso es 11 px, como en el analista.
+test('Supervisor: roster demo, búsqueda y detalle con texto de al menos 11 px', async ({ page }, info) => {
   await page.setViewportSize({ width: 1512, height: 805 })
   await entrarDemo(page, 'Supervisor')
   await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
@@ -31,7 +32,7 @@ test('Supervisor: roster demo, búsqueda y detalle con texto de al menos 16 px',
   await expect(vista.getByText('Llamadas por lead', { exact: true })).toBeVisible()
   const chicos = await vista.evaluate((raiz) => Array.from(raiz.querySelectorAll<HTMLElement>('*')).filter((el) =>
     el.getClientRects().length > 0 && Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim())
-      && Number.parseFloat(getComputedStyle(el).fontSize) < 16).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
+      && Number.parseFloat(getComputedStyle(el).fontSize) < 11).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
   expect(chicos).toEqual([])
   await page.evaluate(() => document.fonts.ready)
   expect(await page.evaluate(() => [...document.fonts].some((f) => f.family.includes('Jakarta') && f.status === 'loaded'))).toBe(true)
@@ -125,8 +126,8 @@ test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginaci
   await expect(abrirDetalle).toHaveAttribute('aria-current', 'true')
   await expect(abrirDetalle).toBeFocused()
   await expect(detalle).toBeVisible()
-  await detalle.getByText('Ver cifras por hora').click()
-  await expect(detalle.getByText('De 10:00 a 10:59: 26 llamadas, 26 contestadas')).toBeVisible()
+  // Barras del diseño (27/09): el dato viaja en una lista para el lector de pantalla, sin desplegable.
+  await expect(detalle.getByRole('list', { name: 'Llamadas por hora' }).getByText('10:00 — 26 llamadas, 26 contestadas')).toBeAttached()
   await detalle.screenshot({ path: info.outputPath('detalle-horario.png') })
   const abrirRegistro = detalle.getByRole('button', { name: 'Ver llamadas del día de Analista Real Uno' })
   await abrirRegistro.focus()
@@ -188,7 +189,7 @@ test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginaci
   await page.setViewportSize({ width: 1280, height: 720 })
   const pequenos = await registro.evaluate((raiz) => Array.from(raiz.querySelectorAll<HTMLElement>('*')).filter((el) =>
     el.getClientRects().length > 0 && Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim())
-      && Number.parseFloat(getComputedStyle(el).fontSize) < 16).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
+      && Number.parseFloat(getComputedStyle(el).fontSize) < 11).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
   expect(pequenos).toEqual([])
   revocado = true
   await registro.getByRole('button', { name: 'Actualizar', exact: true }).click()
@@ -200,7 +201,9 @@ test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginaci
   await expect(abrirDetalle).not.toHaveAttribute('aria-current')
 })
 
-for (const medida of [{ width: 1512, height: 805, filas: 10 }, { width: 1366, height: 768, filas: 9 }]) {
+// Diseño de Gestión Diaria (27/09/2026): filas de 52 px con aire en vez de las 44 px de H2 (23/09); se ven
+// menos filas sin desplazar y el resto se alcanza dentro de la tabla, sin mover la página.
+for (const medida of [{ width: 1512, height: 805, filas: 6 }, { width: 1366, height: 768, filas: 5 }]) {
   test(`H2 densidad ${medida.width}: ${medida.filas} filas, seis columnas y texto completo`, async ({ page }, info) => {
     await page.setViewportSize(medida)
     await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
@@ -226,15 +229,15 @@ for (const medida of [{ width: 1512, height: 805, filas: 10 }, { width: 1366, he
       const caja = tabla.getBoundingClientRect()
       const filas = [...tabla.querySelectorAll<HTMLElement>('tr[data-analista]')].map((f) => f.getBoundingClientRect().toJSON())
       const fuentesPequenas = [...nodo.querySelectorAll<HTMLElement>('*')].filter((e) => e.getClientRects().length && !e.closest('[hidden],.sr-only')
-        && [...e.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim()) && parseFloat(getComputedStyle(e).fontSize) < 16).map((e) => e.textContent)
-      const controlesBajos = [...nodo.querySelectorAll<HTMLElement>('button,input,select')].filter((e) => e.getClientRects().length && e.getBoundingClientRect().height < 43.9).map((e) => e.textContent)
+        && [...e.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim()) && parseFloat(getComputedStyle(e).fontSize) < 11).map((e) => e.textContent)
+      const controlesBajos = [...nodo.querySelectorAll<HTMLElement>('button,input,select')].filter((e) => e.getClientRects().length && e.getBoundingClientRect().height < 23.9).map((e) => e.textContent)
       const contenedor = nodo.closest<HTMLElement>('[data-vista-scroll]')!
       return { viewport: [innerWidth, innerHeight], ancho: nodo.clientWidth, tabla: caja.toJSON(), filas,
         completas: filas.filter((f) => f.bottom <= caja.bottom + .5).length, fuentesPequenas, controlesBajos,
         scrollPagina: contenedor.scrollHeight - contenedor.clientHeight, overflowTabla: tabla.scrollWidth - tabla.clientWidth }
     })
     expect(geometria.completas).toBeGreaterThanOrEqual(medida.filas)
-    expect(geometria.filas.slice(0, medida.filas).every((f) => Math.abs(f.height - 44) < .5)).toBe(true)
+    expect(geometria.filas.slice(0, medida.filas).every((f) => Math.abs(f.height - 52) < 1.5)).toBe(true)
     expect(geometria.fuentesPequenas).toEqual([])
     expect(geometria.controlesBajos).toEqual([])
     expect(geometria.scrollPagina).toBeLessThanOrEqual(1)
@@ -262,7 +265,8 @@ for (const medida of [{ width: 1512, height: 805, filas: 10 }, { width: 1366, he
       await vista.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' }).click()
       await expect(dialogo).toBeVisible()
       await dialogo.getByRole('tab', { name: 'Pendientes', exact: true }).click()
-      await expect(dialogo.getByText('270', { exact: true })).toBeVisible()
+      // El Resumen nuevo también muestra 270 en su cuadro de Pendientes: se mira la pestaña Pendientes.
+      await expect(dialogo.getByLabel('Pendientes de ANA PÉREZ', { exact: true }).getByText('270', { exact: true })).toBeVisible()
       expect(await dialogo.evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true)
       await page.screenshot({ path: info.outputPath('horizontal-movil.png') })
       await page.keyboard.press('Escape')
@@ -291,7 +295,8 @@ test('H2 nombre largo, varios motivos, control de foco y cambio de ruta', async
   await seleccion.click()
   await expect(seleccion).toHaveText(nombre)
   const panel = page.getByRole('region', { name: `Detalle de ${nombre}` })
-  for (const motivo of ['Tareas vencidas', 'Primer intento fuera de plazo', 'Datos pendientes de revisar']) await expect(panel.getByText(motivo, { exact: true })).toBeVisible()
+  await expect(panel.getByRole('button', { name: '321 tareas vencidas' })).toBeVisible()
+  for (const motivo of ['Primer intento fuera de plazo', 'Datos pendientes de revisar']) await expect(panel.getByText(motivo, { exact: true })).toBeVisible()
   expect(await seleccion.evaluate((e) => e.scrollHeight <= e.clientHeight && e.scrollWidth <= e.clientWidth)).toBe(true)
   await panel.getByRole('button', { name: 'Ampliar panel' }).click()
   const dialogo = page.getByRole('dialog', { name: `Detalle de ${nombre}` })
@@ -307,5 +312,7 @@ test('H2 nombre largo, varios motivos, control de foco y cambio de ruta', async
   await expect(seleccion).toBeFocused()
   await page.getByRole('button', { name: 'Agenda', exact: true }).click()
   await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
-  await expect(page.getByText('Selecciona un analista de la tabla para consultar su día.')).toBeVisible()
+  // Al volver, la pantalla abre sola con quien más atención necesita (plan v2, 27/09), sin mover el foco.
+  await expect(page.getByRole('region', { name: `Detalle de ${nombre}` })).toBeVisible()
+  await expect(vista.getByRole('button', { name: `Seleccionar a ${nombre}` })).toHaveAttribute('aria-current', 'true')
 })
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
index 295757eb..382236ba 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
@@ -58,7 +58,9 @@ test('H3: últimas tres comparten Registro; pendientes conservan páginas, ficha
   await expect(registro.getByRole('listitem')).toHaveCount(5)
   expect(estado.registro).toBe(lecturasRegistro)
   await panel.getByRole('tab',{name:'Resumen',exact:true}).click()
-  await panel.getByRole('button',{name:'Ver pendientes (55)'}).click()
+  // Resumen del diseño (27/09): el cuadro Pendientes muestra el 55 y su acceso «Ver pendientes».
+  await expect(panel.getByRole('term').filter({hasText:/^Pendientes$/}).locator('xpath=following-sibling::dd[1]')).toContainText('55')
+  await panel.getByRole('button',{name:'Ver pendientes de ANA H3'}).click()
   const lista=panel.getByRole('list',{name:'Lista de tareas pendientes'})
   await expect(panel.getByRole('heading',{name:'Pendientes de ANA H3'})).toBeFocused()
   await expect(lista.getByRole('listitem')).toHaveCount(25)
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx
index 030e6485..d159385e 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx
@@ -43,3 +43,16 @@ describe('FranjaCifras', () => {
     expect(screen.getByTestId('chip')).toHaveTextContent('Bien')
   })
 })
+
+describe('FranjaCifras en línea (supervisor, 27/09/2026)', () => {
+  it('pinta número y etiqueta en una línea SIN cambiar el orden término → definición', () => {
+    const { container } = render(<FranjaCifras etiqueta="Resumen del equipo" disposicion="en-linea" cifras={[{ etiqueta: 'Analistas', valor: '5' }]} />)
+    const celda = container.querySelector('dl > div')!
+    expect(celda).toHaveClass('flex-row-reverse')
+    expect(celda.firstElementChild?.tagName).toBe('DT')
+  })
+  it('el tono de aviso usa el ámbar de TEXTO: «Necesitan atención» no es un vencimiento', () => {
+    render(<FranjaCifras etiqueta="Cifras" cifras={[{ etiqueta: 'Necesitan atención', valor: '4', tono: 'aviso' }]} />)
+    expect(screen.getByText('4')).toHaveClass('text-[var(--warning-text)]')
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
index 43527214..1dad9f1a 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
@@ -16,8 +16,10 @@ export interface CifraDelDia {
   valorAccesible?: string | undefined
   /** Texto o chip que acompaña al número («de 18», «hoy», el nivel). */
   apoyo?: ReactNode
-  /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy». */
-  tono?: 'normal' | 'alerta' | undefined
+  /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy».
+   * `aviso` lo pinta en ámbar: una señal que NO es un vencimiento (p. ej. «Necesitan atención»,
+   * que mezcla vencidas con cortes y tiempo sin llamar). */
+  tono?: 'normal' | 'alerta' | 'aviso' | undefined
 }
 
 // Clases escritas enteras: Tailwind no ve las que se arman con plantillas.
@@ -25,23 +27,33 @@ const COLUMNAS: Record<number, string> = {
   1: 'sm:grid-cols-1', 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-4', 5: 'sm:grid-cols-5', 6: 'sm:grid-cols-6',
 }
 
-export function FranjaCifras({ etiqueta, cifras, className }: {
+const TONO: Record<NonNullable<CifraDelDia['tono']>, string> = {
+  normal: 'text-primary', alerta: 'text-[var(--destructive-text)]', aviso: 'text-[var(--warning-text)]',
+}
+
+export function FranjaCifras({ etiqueta, cifras, className, disposicion = 'apilada' }: {
   /** Nombre del grupo para el lector de pantalla («Tu día en cifras»). */
   etiqueta: string
   cifras: readonly CifraDelDia[]
   className?: string | undefined
+  /** `apilada`: etiqueta arriba y número debajo (analista). `en-linea`: número y
+   * etiqueta en una línea, como la franja del supervisor en el diseño. El DOM
+   * conserva término → definición; solo cambia el orden visual. */
+  disposicion?: 'apilada' | 'en-linea' | undefined
 }): JSX.Element {
+  const enLinea = disposicion === 'en-linea'
   return (
     // Grupo con nombre, no una región más: la pantalla ya tiene las suyas.
     <section role="group" aria-label={etiqueta} className={cn('rounded-2xl border border-border bg-card', className)}>
-      <dl className={cn('grid grid-cols-2 gap-y-4 py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
+      <dl className={cn('grid grid-cols-2 gap-y-4', enLinea ? 'py-[18px]' : 'py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
         {cifras.map((c, i) => (
           // En el celular son 2 por fila (raya solo en la segunda); desde tablet,
           // raya a la izquierda de todas menos la primera.
-          <div key={c.etiqueta} className={cn('flex min-w-0 flex-col gap-1 px-5', i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
-            <dt className="text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
+          <div key={c.etiqueta} className={cn('flex min-w-0 px-5', enLinea ? 'flex-row-reverse items-baseline justify-end gap-2.5' : 'flex-col gap-1',
+            i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
+            <dt className={enLinea ? 'min-w-0 text-[13px] text-[var(--muted-foreground-strong)]' : 'text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]'}>{c.etiqueta}</dt>
             <dd className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
-              <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', c.tono === 'alerta' ? 'text-[var(--destructive-text)]' : 'text-primary')}>
+              <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', TONO[c.tono ?? 'normal'])}>
                 {c.valorAccesible !== undefined ? (
                   <>
                     <span aria-hidden="true">{c.valor}</span>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cortes-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cortes-supervisor.tsx
index 13cd02e2..0a46e423 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cortes-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cortes-supervisor.tsx
@@ -5,7 +5,6 @@ import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
 import { useAlertasCRM } from '@/lib/alertas-context'
 import { presentarCortesJornada } from '@/lib/gestion-diaria-cortes-presentacion'
 import { horaCorte } from '@/lib/gestion-diaria-avisos'
-import { Button } from '@/components/ui/button'
 
 export function FranjaCortesSupervisor({ consulta, abrir }: { consulta: DiaEquipoHook; abrir: () => void }) {
   const avisos = useGestionDiariaAvisos()
@@ -18,14 +17,16 @@ export function FranjaCortesSupervisor({ consulta, abrir }: { consulta: DiaEquip
   const ultimoConteo = useRef<number | null>(null)
   if (avisos?.error || !avisos?.datos || otros.errores.length) ultimoConteo.current = null
   else if (!otros.cargando) ultimoConteo.current = otros.alertas.filter((a) => !a.corte && !a.reconocimiento).length
-  return <section className="gd-cortes" aria-label="Estado de cortes y avisos">
-    <Button variant="ghost" className="min-h-11 shrink-0 text-base" aria-haspopup="dialog" onClick={abrir}>
-      <Bell aria-hidden />Cortes y avisos
-    </Button>
-    <div className="gd-cortes-resumen">
+  // Diseño de Gestión Diaria (27/09): una tira fina al pie, mismos estados.
+  return <section className="flex shrink-0 flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl border border-border bg-card px-2 py-[3px] text-[13px]" aria-label="Estado de cortes y avisos">
+    <button type="button" aria-haspopup="dialog" onClick={abrir}
+      className="inline-flex h-9 shrink-0 cursor-pointer items-center gap-1.5 rounded-[10px] px-2.5 font-semibold text-primary transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11">
+      <Bell aria-hidden className="size-4" />Cortes y avisos
+    </button>
+    <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-4 gap-y-0.5 text-[var(--muted-foreground-strong)] [overflow-wrap:anywhere]">
       {estado ? <span>{estado}</span> : cortes.map((c) => <span key={c.clave}>
         <time dateTime={c.instante}>{c.hora}</time> {c.estado}
-        {c.bajoMinimo > 0 && <strong> · {c.bajoMinimo} bajo el mínimo</strong>}
+        {c.bajoMinimo > 0 && <strong className="font-semibold text-[var(--warning-text)]"> · {c.bajoMinimo} bajo el mínimo</strong>}
       </span>)}
       {avisos?.error ? <span>Avisos no disponibles</span> : avisos?.cargando ? <span>Consultando avisos…</span>
         : avisos?.datos && <>
@@ -33,6 +34,6 @@ export function FranjaCortesSupervisor({ consulta, abrir }: { consulta: DiaEquip
           <span>{otros.errores.length ? 'Otros avisos sin confirmar' : ultimoConteo.current === null ? 'Consultando otros avisos…' : `Otros sin reconocer: ${ultimoConteo.current}`}</span>
         </>}
     </div>
-    <p className="gd-cortes-consulta">{dia ? `Consulta ${horaCorte(dia.generado_en)} · Lima` : 'Sin consulta confirmada'}</p>
+    <p className="whitespace-nowrap pr-2 text-xs tabular-nums text-[var(--muted-foreground-strong)]">{dia ? `Consulta ${horaCorte(dia.generado_en)} · Lima` : 'Sin consulta confirmada'}</p>
   </section>
 }
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
index 94977dcd..c5d9255d 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
@@ -1,20 +1,31 @@
 import { useLayoutEffect, useRef, useState, type RefObject } from 'react'
 import { Title as TituloDialogo } from '@radix-ui/react-dialog'
-import { Maximize2, Minimize2, X, Users } from 'lucide-react'
+import { ClipboardList, Maximize2, Minimize2, X, Users } from 'lucide-react'
+import { Avatar } from '@/components/ui/avatar'
 import { Button } from '@/components/ui/button'
 import { Tabs } from '@/components/ui/tabs'
-import { DetalleAnalista } from './detalle-analista'
 import { RegistroActividad } from './registro-actividad'
 import { PendientesSupervisor } from './pendientes-supervisor'
+import { ResumenAnalista } from './resumen-analista'
 import { UltimasGestionesSupervisor } from './ultimas-gestiones-supervisor'
-import { MOTIVOS_EQUIPO, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
+import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
 import type { PestanaRegistro } from '@/lib/gestion-diaria'
-import { textoTasa } from '@/lib/gestion-diaria-analista'
+import { cn } from '@/lib/utils'
 
-export interface SeleccionSupervisor { analista: string | null; nombre: string | null; apertura: number; pestana: PestanaRegistro; enfocar: boolean }
+/**
+ * `origen` (revisión Codex del plan, 27/09): una selección AUTOMÁTICA (quien más
+ * atención necesita) no abre nunca una ventana ni mueve el foco; la del usuario
+ * y la de un aviso, sí siguen la mecánica adaptable de siempre.
+ */
+export interface SeleccionSupervisor {
+  analista: string | null; nombre: string | null; apertura: number; pestana: PestanaRegistro; enfocar: boolean
+  origen?: 'automatica' | 'usuario' | 'aviso' | undefined
+}
 type PestanaPanel = 'resumen' | 'registro' | 'pendientes'
 
-export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, tituloRef, ampliado, ampliar, cerrar, puedeAmpliar, oculta, limpiar, actualizacion, revalidar }: {
+const BOTON_ICONO = 'grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] text-[var(--muted-foreground-strong)] transition-colors hover:bg-muted hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:size-11'
+
+export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, tituloRef, ampliado, ampliar, cerrar, puedeAmpliar, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, vacio, silencioso = false }: {
   id: string
   seleccion: SeleccionSupervisor | null
   fila: FilaEquipoPresentada | undefined
@@ -29,30 +40,51 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
   limpiar: () => void
   actualizacion: number
   revalidar: () => void
+  esHoy: boolean
+  ahora: number
+  /** El texto del panel sin selección (p. ej., «Nadie necesita atención ahora…»). */
+  vacio?: string | undefined
+  /** Selección automática: sus cargas y errores no se anuncian (el usuario no la abrió). */
+  silencioso?: boolean
 }) {
-  const titulo = seleccion ? seleccion.analista === null ? 'Registro del equipo' : `Detalle de ${fila?.nombre_completo ?? seleccion.nombre}` : 'Detalle del analista'
+  const equipo = seleccion?.analista === null
+  const nombre = seleccion && !equipo ? fila?.nombre_completo ?? seleccion.nombre ?? 'Analista' : null
+  const titulo = seleccion ? equipo ? 'Registro del equipo' : `Detalle de ${nombre}` : 'Detalle del analista'
   return (
-    <section id={id} aria-label={titulo} className="gd-panel">
-      <header className="gd-panel-cabecera">
-        <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1}>{titulo}</h3></TituloDialogo>
-        {seleccion && <div className="flex shrink-0">
-          {puedeAmpliar && <Button variant="ghost" size="icon" className="size-11" aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden /> : <Maximize2 aria-hidden />}</Button>}
-          <Button variant="ghost" size="icon" className="size-11" aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden /></Button>
+    <section id={id} aria-label={titulo} className="flex min-h-0 min-w-0 flex-1 flex-col overflow-clip rounded-2xl border border-border bg-card">
+      <header className="flex shrink-0 items-center gap-3 border-b border-border px-5 py-3.5">
+        {nombre !== null ? <Avatar nombre={nombre} color="var(--accent-press)" />
+          : equipo ? <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary"><ClipboardList className="size-4" /></span> : null}
+        <div className="min-w-0 flex-1">
+          {/* El nombre visible es el del analista; el lector oye «Detalle de …»,
+              como el nombre de la región y del diálogo. */}
+          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className="rounded-md text-[17px] font-extrabold leading-tight tracking-[-0.01em] text-primary [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
+            {/* El espacio va FUERA del texto oculto: dentro se perdía («Detalle deANA»). */}
+            {nombre !== null ? <><span className="sr-only">Detalle de</span>{' '}{nombre}</> : titulo}
+          </h3></TituloDialogo>
+          {nombre !== null && <p className="mt-0.5 text-[12.5px] text-[var(--muted-foreground-strong)]">Analista de tu equipo</p>}
+        </div>
+        {seleccion && <div className="flex shrink-0 gap-0.5">
+          {puedeAmpliar && <button type="button" className={BOTON_ICONO} aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden className="size-4" /> : <Maximize2 aria-hidden className="size-4" />}</button>}
+          <button type="button" className={BOTON_ICONO} aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden className="size-[18px]" /></button>
         </div>}
       </header>
-      {!seleccion ? <div className="gd-panel-inicial"><Users className="size-10 text-muted-foreground" aria-hidden /><p>Selecciona un analista de la tabla para consultar su día.</p></div>
+      {!seleccion ? <div className="flex flex-1 flex-col items-center justify-center gap-3 px-8 text-center text-[13.5px] text-[var(--muted-foreground-strong)]">
+        <Users className="size-9 text-muted-foreground" aria-hidden /><p>{vacio ?? 'Selecciona un analista de la tabla para consultar su día.'}</p></div>
         : <ContenidoSeleccionado key={`${seleccion.analista ?? 'equipo'}:${seleccion.apertura}`} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo}
-          tituloRef={tituloRef} oculta={oculta} limpiar={limpiar} actualizacion={actualizacion} revalidar={revalidar} />}
+          tituloRef={tituloRef} oculta={oculta} limpiar={limpiar} actualizacion={actualizacion} revalidar={revalidar} esHoy={esHoy} ahora={ahora} silencioso={silencioso} />}
     </section>
   )
 }
 
-function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor }) {
+function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, silencioso }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor; esHoy: boolean; ahora: number; silencioso: boolean }) {
   const equipo = seleccion.analista === null
   const [pestana, setPestana] = useState<PestanaPanel>(equipo || seleccion.enfocar ? 'registro' : 'resumen')
   const [registro, setRegistro] = useState<{ pestana: PestanaRegistro; apertura: number } | null>(equipo || seleccion.enfocar ? { pestana: seleccion.pestana, apertura: 0 } : null)
   const [pendientes, setPendientes] = useState<{ soloVencidas: boolean; apertura: number; enfocar: boolean } | null>(null)
   const tituloRegistro = useRef<HTMLHeadingElement>(null)
+  const cuerpoResumen = useRef<HTMLDivElement>(null)
+  const alInicio = () => cuerpoResumen.current?.closest('[role=tabpanel]')?.scrollTo?.({ top: 0 })
   const [focoRegistro, setFocoRegistro] = useState(0)
   useLayoutEffect(() => {
     if (seleccion.enfocar) tituloRef.current?.focus({ preventScroll: true })
@@ -61,46 +93,47 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
     if (focoRegistro) tituloRegistro.current?.focus({ preventScroll: true })
   }, [focoRegistro])
   const cambiar = (valor: PestanaPanel) => {
+    alInicio()
     setPestana(valor)
     if (valor === 'registro' && !registro) setRegistro({ pestana: 'todo', apertura: 0 })
     if (valor === 'pendientes' && !pendientes) setPendientes({ soloVencidas: false, apertura: 0, enfocar: false })
   }
   const abrirRegistro = (inicial: PestanaRegistro) => {
+    alInicio()
     setRegistro((r) => ({ pestana: inicial, apertura: (r?.apertura ?? 0) + 1 }))
     setPestana('registro')
     setFocoRegistro((n) => n + 1)
   }
   const abrirPendientes = (soloVencidas: boolean) => {
+    alInicio()
     setPendientes(p => ({ soloVencidas, apertura: (p?.apertura ?? 0) + 1, enfocar: true }))
     setPestana('pendientes')
   }
+  const cuerpo = 'min-w-0 px-5 py-4 [overflow-wrap:anywhere]'
   const contenido = <>
-    <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
-      {!fila ? <p role="status">El resumen no está disponible. El registro conserva su consulta independiente.</p> : <>
-        <div className="gd-resumen-principal"><strong>{fila.marcador.llamadas}</strong><span>Llamadas registradas</span></div>
-        <p className="mb-3 text-[var(--muted-foreground-strong)]">{fila.gestiones_hoy} gestiones · {dia} · Lima</p>
-        <p><strong>Contacto: {textoTasa(fila.marcador)}</strong> · {fila.marcador.contestadas} de {fila.marcador.utiles} llamadas útiles. {fila.marcador.utiles === 0 ? 'Sin llamadas útiles.' : fila.marcador.nivel === null ? 'Sin muestra suficiente.' : ''} Mínimo: {minimo ?? 'no disponible'}.</p>
-        <p className="mt-2 text-[var(--muted-foreground-strong)]">Número errado y otra persona quedan fuera del contacto útil.</p>
-        {fila.motivos_atencion.length > 0 && <div className="gd-atencion-detalle"><h4 className="font-semibold">Necesita atención</h4><ul className="list-disc pl-5">{fila.motivos_atencion.map((m) => <li key={m}>{MOTIVOS_EQUIPO[m]}</li>)}</ul></div>}
-        <div className="my-3 flex flex-wrap gap-2">
-          <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirPendientes(false)}>Ver pendientes ({fila.tareas_pendientes})</Button>
-          {fila.tareas_vencidas > 0 && <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirPendientes(true)}>{fila.tareas_vencidas} tareas vencidas</Button>}
-        </div>
-        <DetalleAnalista fila={fila} dia={dia} abrirLlamadas={() => abrirRegistro('llamadas')} />
-      </>}
+    <div ref={cuerpoResumen} className={cn(cuerpo, 'space-y-5')} hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
+      {!fila || minimo === undefined ? <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">El resumen no está disponible. El registro conserva su consulta independiente.</p>
+        : <ResumenAnalista fila={fila} minimo={minimo} esHoy={esHoy} ahora={ahora}
+          abrirLlamadas={() => abrirRegistro('llamadas')} abrirPendientes={abrirPendientes} />}
       {seleccion.analista !== null && <>
-        <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} />
-        <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirRegistro('todo')}>Ver registro</Button>
+        <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} silencioso={silencioso} />
+        <div className="space-y-2">
+          <button type="button" onClick={() => abrirRegistro('todo')}
+            className="flex h-11 w-full cursor-pointer items-center justify-center rounded-xl bg-accent text-sm font-bold text-accent-foreground transition-colors hover:bg-[var(--accent-press)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
+            Ver el registro del día
+          </button>
+          <p className="text-xs leading-relaxed text-[var(--muted-foreground-strong)]">El registro se consulta al abrirlo y solo muestra actividades cuyos leads siguen visibles para tu sesión; puede diferir de esta foto.</p>
+        </div>
       </>}
     </div>
-    <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
+    <div className={cuerpo} hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
       {registro && <section aria-label="Registro seleccionado">
-        <h4 ref={tituloRegistro} tabIndex={-1} className="mb-3 font-semibold">{equipo ? 'Registro del equipo' : `Registro de ${seleccion.nombre}`}</h4>
+        <h4 ref={tituloRegistro} tabIndex={-1} className="mb-3 text-[15px] font-extrabold text-primary">{equipo ? 'Registro del equipo' : `Registro de ${seleccion.nombre}`}</h4>
         <RegistroActividad key={registro.apertura} dia={dia} pestanaInicial={registro.pestana}
           analistaIds={seleccion.analista === null ? null : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
       </section>}
     </div>
-    <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'pendientes'} inert={pestana !== 'pendientes'}>
+    <div className={cuerpo} hidden={pestana !== 'pendientes'} inert={pestana !== 'pendientes'}>
       {pendientes && seleccion.analista !== null && <PendientesSupervisor key={pendientes.apertura}
         analista={seleccion.analista} nombre={fila?.nombre_completo ?? seleccion.nombre ?? 'Analista'} dia={dia} fila={fila}
         visible={pestana === 'pendientes'} soloVencidasInicial={pendientes.soloVencidas} apertura={pendientes.apertura}
@@ -108,8 +141,14 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
     </div>
   </>
   return <>
-    {oculta && <div className="gd-seleccion-oculta">La selección está fuera de los filtros.<Button variant="ghost" className="min-h-11 text-base" onClick={limpiar}>Limpiar filtros</Button></div>}
-    {equipo ? contenido : <Tabs className="gd-pestanas-panel" tamano="grande" etiqueta="Detalle del analista" valor={pestana} onCambio={cambiar}
-      pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, { valor: 'pendientes', etiqueta: 'Pendientes' }]}>{contenido}</Tabs>}
+    {oculta && <div className="flex shrink-0 flex-wrap items-center justify-between gap-2 bg-muted px-5 py-1.5 text-[13px]">La selección está fuera de los filtros.
+      <Button variant="ghost" className="h-9 text-[13px] pointer-coarse:h-11" onClick={limpiar}>Limpiar filtros</Button></div>}
+    {/* El cuerpo con scroll es el panel de la pestaña (parada del tabulador):
+        así el texto tras el último control se alcanza sin ratón. */}
+    {equipo ? <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">{contenido}</div>
+      : <Tabs etiqueta="Detalle del analista" variante="subrayado" valor={pestana} onCambio={cambiar}
+        pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, { valor: 'pendientes', etiqueta: 'Pendientes' }]}
+        className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]]:px-5 [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm pointer-coarse:[&>[role=tablist]>[role=tab]]:min-h-11"
+        clasePanel="ac-scroll min-h-0 flex-1 overflow-y-auto focus-visible:!-outline-offset-2">{contenido}</Tabs>}
   </>
 }
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-supervisor-adaptable.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-supervisor-adaptable.tsx
index 0fbf7ffa..4beaf8b0 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-supervisor-adaptable.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-supervisor-adaptable.tsx
@@ -7,11 +7,14 @@ import { protegerEscapeAnidado } from '@/components/ui/escape-dialogo'
  * región y diálogo mantiene filtros, páginas, scroll e instancias React.
  * Radix conserva la modalidad, capas y foco, también sobre la ficha del lead.
  * Content no debe tener animación de salida: el destino se traslada en el commit. */
-export function PanelSupervisorAdaptable({ modal, cerrar, tituloRef, children }: {
+export function PanelSupervisorAdaptable({ modal, cerrar, tituloRef, children, claseAlojamiento = 'gd-panel-alojamiento' }: {
   modal: boolean
   cerrar: () => void
   tituloRef: RefObject<HTMLHeadingElement | null>
   children: ReactNode
+  /** Clase del alojamiento en línea. El supervisor usa la suya (27/09) para no
+   * heredar los cortes de ancho de `supervisor.css`, que siguen siendo de gerencia. */
+  claseAlojamiento?: string | undefined
 }) {
   const [destino] = useState(() => {
     const nodo = document.createElement('div')
@@ -46,7 +49,7 @@ export function PanelSupervisorAdaptable({ modal, cerrar, tituloRef, children }:
   }, [modal])
   return (
     <Dialog.Root open={modal} onOpenChange={(abierto) => { if (!abierto) cerrar() }}>
-      <div ref={alojarEnLinea} className="gd-panel-alojamiento" hidden={modal} />
+      <div ref={alojarEnLinea} className={claseAlojamiento} hidden={modal} />
       <Dialog.Portal>
         <Dialog.Overlay className="fixed inset-0 z-50 bg-primary/25 backdrop-blur-[2px]" />
         <Dialog.Content ref={alojarEnDialogo} className="gd-panel-modal" data-slot="dialog" aria-describedby={undefined}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
index dde92a23..7f675c24 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
@@ -1,4 +1,4 @@
-import { useEffect, useEffectEvent, useId, useRef, useState } from 'react'
+import { useEffect, useEffectEvent, useId, useLayoutEffect, useRef, useState } from 'react'
 import { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
 import { CrmApiError } from '@/data/crm-api'
 import { usePanelesActions } from '@/lib/store-context'
@@ -27,23 +27,34 @@ export function PendientesSupervisor({ analista, nombre, dia, fila, visible, sol
   }, [actualizacion])
   useEffect(() => { if (lista.sinPermiso) revocar() }, [lista.sinPermiso])
   const noInstalada = lista.error instanceof CrmApiError && lista.error.code === 'PGRST202'
+  // «Cargar más» o «Reintentar» se desmontan al terminar: si tenían el foco, pasa al título.
+  const focoEnAccion = useRef(false)
+  const recordar = { onFocus: () => { focoEnAccion.current = true }, onBlur: () => { focoEnAccion.current = false } }
+  const accionVisible = lista.hayMas || Boolean(lista.error)
+  useLayoutEffect(() => {
+    if (accionVisible || !focoEnAccion.current) return
+    focoEnAccion.current = false
+    titulo.current?.focus({ preventScroll: true })
+  }, [accionVisible])
+  const deshabilitado = 'aria-disabled:cursor-default aria-disabled:opacity-60'
   const resumen = lista.pagina?.resumen ?? (fila && !lista.sinPermiso ? fila : null)
-  return <section aria-labelledby={tituloId} className="space-y-3">
-    <h4 id={tituloId} ref={titulo} tabIndex={-1} className="font-semibold">Pendientes de {nombre}</h4>
+  // Escala del diseño de Gestión Diaria (27/09): 13–15 px y controles compactos que crecen en táctil.
+  return <section aria-labelledby={tituloId} className="space-y-3 text-[13.5px]">
+    <h4 id={tituloId} ref={titulo} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Pendientes de {nombre}</h4>
     {resumen && <p><strong>{resumen.tareas_pendientes}</strong> tareas pendientes · <strong>{resumen.tareas_vencidas}</strong> vencidas.
       {lista.pagina ? ' Foto de la consulta de tareas.' : ' Último resumen confirmado del equipo.'}</p>}
     {fila && !lista.sinPermiso && <p className="text-[var(--muted-foreground-strong)]">Primer intento fuera de plazo: {fila.primer_intento_vencido ?? 'no evaluado'}. Datos incompletos: {fila.datos_incompletos ?? 'no evaluado'}.
       {' '}Estas señales corresponden a leads y no se suman como tareas.</p>}
     <div className="flex flex-wrap gap-2" role="group" aria-label="Filtro de tareas">
-      <Button className="min-h-11 text-base" variant={!soloVencidas ? 'default' : 'outline'} aria-pressed={!soloVencidas} onClick={() => setSoloVencidas(false)}>Todas</Button>
-      <Button className="min-h-11 text-base" variant={soloVencidas ? 'default' : 'outline'} aria-pressed={soloVencidas} onClick={() => setSoloVencidas(true)}>Vencidas</Button>
+      <Button className="h-9 text-[13px] pointer-coarse:h-11" variant={!soloVencidas ? 'default' : 'outline'} aria-pressed={!soloVencidas} onClick={() => setSoloVencidas(false)}>Todas</Button>
+      <Button className="h-9 text-[13px] pointer-coarse:h-11" variant={soloVencidas ? 'default' : 'outline'} aria-pressed={soloVencidas} onClick={() => setSoloVencidas(true)}>Vencidas</Button>
     </div>
     {lista.cargando && <p role="status">Consultando las tareas de este analista…</p>}
     {lista.error && <div role="alert" className="space-y-2">
       <p>{lista.sinPermiso ? 'Ya no tienes acceso a estas tareas. Se retiraron los datos anteriores.'
         : noInstalada ? 'Detalle de tareas no disponible. La consulta aún no está instalada.'
           : 'No se pudo confirmar la lista de tareas. Esto no significa que esté vacía.'}</p>
-      {!lista.sinPermiso && <Button className="min-h-11 text-base" variant="outline" disabled={lista.enVuelo} onClick={() => { void lista.recargar() }}>Reintentar desde el inicio</Button>}
+      {!lista.sinPermiso && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} variant="outline" aria-disabled={lista.enVuelo} {...recordar} onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Reintentar desde el inicio</Button>}
     </div>}
     {lista.pagina && <p className="text-[var(--muted-foreground-strong)]">
       Consulta: {FECHA.format(new Date(lista.pagina.generado_en))} · Lima.
@@ -51,19 +62,20 @@ export function PendientesSupervisor({ analista, nombre, dia, fila, visible, sol
     </p>}
     {lista.congelada && lista.consultadoDesde && <p className="text-[var(--muted-foreground-strong)]">Primera página consultada: {FECHA.format(new Date(lista.consultadoDesde))}. Las tareas pueden cambiar; actualizar comienza una nueva consulta.</p>}
     {!lista.error && lista.pagina && lista.items.length === 0 && <p>{soloVencidas ? 'No hay tareas vencidas en esta consulta.' : 'Sin tareas pendientes.'}</p>}
-    <ul className="divide-y divide-border" aria-label="Lista de tareas pendientes">
+    {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
+    <ul role="list" className="divide-y divide-border" aria-label="Lista de tareas pendientes">
       {lista.items.map(tarea => <li key={tarea.id} className="space-y-1 py-3 break-words">
-        <p className="font-semibold">{tarea.titulo.trim() || 'Sin título'}</p>
+        <p className="font-bold text-primary">{tarea.titulo.trim() || 'Sin título'}</p>
         <p>{TIPO_EVENTO[tarea.tipo] ?? tarea.tipo} · <time dateTime={new Date(tarea.vence_en).toISOString()}>{FECHA.format(new Date(tarea.vence_en))}</time> · Lima</p>
         {tarea.lead_id && tarea.lead_nombre
-          ? <Button variant="link" className="min-h-11 h-auto max-w-full whitespace-normal px-0 text-left text-base" onClick={() => abrirLead(tarea.lead_id!)}>{tarea.lead_nombre}</Button>
+          ? <Button variant="link" className="h-auto min-h-6 max-w-full whitespace-normal px-0 text-left text-[13.5px] pointer-coarse:min-h-11" onClick={() => abrirLead(tarea.lead_id!)}>{tarea.lead_nombre}</Button>
           : <p className="text-[var(--muted-foreground-strong)]">{tarea.referencia_tipo === 'perfil' ? 'Tarea de perfil' : tarea.referencia_tipo === 'postventa' ? 'Tarea de postventa' : 'Referencia no disponible'}</p>}
       </li>)}
     </ul>
     {lista.pagina && <p role="status">{lista.items.length} tareas cargadas{lista.hayMas ? ' · Hay más por consultar.' : lista.error ? ' · Consulta incompleta.' : ' · Fin de las páginas consultadas.'}</p>}
     <div className="flex flex-wrap gap-2">
-      {lista.hayMas && <Button className="min-h-11 text-base" disabled={lista.enVuelo} onClick={() => { void lista.cargarMas() }}>{lista.enVuelo ? 'Consultando…' : 'Cargar más tareas'}</Button>}
-      {!lista.sinPermiso && !noInstalada && <Button className="min-h-11 text-base" variant="outline" disabled={lista.enVuelo} onClick={() => { void lista.recargar() }}>Actualizar desde el inicio</Button>}
+      {lista.hayMas && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} aria-disabled={lista.enVuelo} {...recordar} onClick={() => { if (!lista.enVuelo) void lista.cargarMas() }}>{lista.enVuelo ? 'Consultando…' : 'Cargar más tareas'}</Button>}
+      {!lista.sinPermiso && !noInstalada && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} variant="outline" aria-disabled={lista.enVuelo} onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Actualizar desde el inicio</Button>}
     </div>
   </section>
 }
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.test.tsx
new file mode 100644
index 00000000..c30fefba
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.test.tsx
@@ -0,0 +1,76 @@
+// El resumen del analista en el panel del supervisor (diseño 27/09/2026): el
+// aviso de lo vencido lleva a Pendientes, los 4 cuadros (Pendientes en lugar de
+// WhatsApp), «Sin muestra» dicho con útiles y mínimo, el desglose por hora solo
+// si se confirma y lo que el diseño no dibuja, conservado.
+import { describe, expect, it, vi } from 'vitest'
+import { fireEvent, render, screen, within } from '@testing-library/react'
+import { ResumenAnalista } from './resumen-analista'
+import { filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
+import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
+
+const AHORA = Date.parse('2026-09-21T21:30:00Z')
+const fila = (cambios: Parameters<typeof filaEquipoPrueba>[0] = {}) => filaEquipoPrueba(cambios) as FilaEquipoPresentada
+const conLlamadas = fila({
+  nombre_completo: 'KAREN DÍAZ', tareas_pendientes: 5, tareas_vencidas: 4, requiere_atencion: true,
+  motivos_atencion: ['tarea_vencida', 'sin_llamar_2h'], llamadas_por_lead: 1.5, citas_hoy: 2,
+  marcador: { ...filaEquipoPrueba().marcador, llamadas: 12, utiles: 11, contestadas: 2, tasa_contacto_pct: 18, nivel: 'bajo',
+    leads_tocados: 8, citas_agendadas: 1, primera_llamada_en: '2026-09-21T13:10:00Z', ultima_llamada_en: '2026-09-21T21:05:00Z',
+    por_hora: [{ hora: 9, llamadas: 5, contestadas: 1 }, { hora: 16, llamadas: 7, contestadas: 1 }] },
+})
+
+function montar(f: FilaEquipoPresentada, esHoy = true) {
+  const abrirLlamadas = vi.fn()
+  const abrirPendientes = vi.fn()
+  render(<ResumenAnalista fila={f} minimo={5} esHoy={esHoy} ahora={AHORA} abrirLlamadas={abrirLlamadas} abrirPendientes={abrirPendientes} />)
+  return { abrirLlamadas, abrirPendientes }
+}
+
+describe('ResumenAnalista', () => {
+  it('el aviso de vencidas abre Pendientes SOLO vencidas y los demás motivos se dicen aparte', () => {
+    const { abrirPendientes } = montar(conLlamadas)
+    fireEvent.click(screen.getByRole('button', { name: '4 tareas vencidas' }))
+    expect(abrirPendientes).toHaveBeenCalledWith(true)
+    expect(within(screen.getByRole('list', { name: 'Otros motivos de atención' })).getByText('Más de 2 h sin llamar en la jornada')).toBeInTheDocument()
+  })
+  it('los 4 cuadros: Llamadas, Contacto, Citas agendadas y Pendientes (no WhatsApp), con sus accesos', () => {
+    const { abrirLlamadas, abrirPendientes } = montar(conLlamadas)
+    const terminos = screen.getAllByRole('term').slice(0, 4).map((t) => t.textContent)
+    expect(terminos).toEqual(['Llamadas', 'Contacto', 'Citas agendadas', 'Pendientes'])
+    expect(screen.queryByText('WhatsApp')).not.toBeInTheDocument()
+    expect(screen.getByText('18 %')).toBeInTheDocument()
+    expect(screen.getByText('Bajo')).toBeInTheDocument()
+    fireEvent.click(screen.getByRole('button', { name: 'Ver llamadas del día de KAREN DÍAZ' }))
+    expect(abrirLlamadas).toHaveBeenCalledTimes(1)
+    fireEvent.click(screen.getByRole('button', { name: 'Ver pendientes de KAREN DÍAZ' }))
+    expect(abrirPendientes).toHaveBeenCalledWith(false)
+  })
+  it('sin muestra suficiente lo dice con útiles y mínimo, nunca como una tasa evaluada', () => {
+    montar(fila({ marcador: { ...filaEquipoPrueba().marcador, llamadas: 3, utiles: 3, contestadas: 2, tasa_contacto_pct: 67, nivel: null } }))
+    expect(screen.getByText('Sin muestra suficiente · 3 útiles · mínimo 5')).toBeInTheDocument()
+    expect(screen.queryByText('67 %')).not.toBeInTheDocument()
+  })
+  it('las barras llevan «hace X» solo hoy; en otra fecha, solo la hora', () => {
+    montar(conLlamadas)
+    expect(screen.getByText('Última llamada 16:05 · hace 25 min')).toBeInTheDocument()
+  })
+  it('en una fecha pasada no dice «hace»', () => {
+    montar(conLlamadas, false)
+    expect(screen.getByText('Última llamada 16:05')).toBeInTheDocument()
+  })
+  it('un desglose por hora que no cuadra NO se dibuja con ceros', () => {
+    montar(fila({ marcador: { ...conLlamadas.marcador, por_hora: [{ hora: 9, llamadas: 1, contestadas: 0 }] } }))
+    expect(screen.getByRole('status')).toHaveTextContent('No se pudo confirmar el desglose por hora')
+  })
+  it('sin llamadas no pinta barras vacías y no lo presenta como ausencia', () => {
+    montar(fila())
+    expect(screen.getByText('No hay llamadas registradas ese día. Esto no indica ausencia ni descarta otras gestiones.')).toBeInTheDocument()
+  })
+  it('conserva lo que el diseño no dibuja: leads distintos, llamadas por lead, primera llamada y citas del día', () => {
+    montar(conLlamadas)
+    const datos = screen.getByLabelText('Más datos del día')
+    for (const [titulo, valor] of [['Leads distintos', '8'], ['Llamadas por lead', '1.5'], ['Primera llamada', '08:10'], ['Citas pendientes del día', '2']] as const) {
+      const termino = within(datos).getByText(titulo)
+      expect(termino.nextElementSibling).toHaveTextContent(valor)
+    }
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
new file mode 100644
index 00000000..181442dc
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
@@ -0,0 +1,137 @@
+// El resumen del analista en el panel del supervisor (diseño de Gestión Diaria,
+// 27/09/2026): el aviso de lo vencido, 4 cuadros, las llamadas por hora y una
+// línea con lo que el diseño no dibuja pero hoy existe. Explica la foto del
+// servidor; no reconstruye cifras desde el store.
+//
+// El diseño pone «WhatsApp» en el cuarto cuadro; la foto no trae ese conteo por
+// analista, así que va «Pendientes» (decisión del plan, 27/09). Gerencia sigue
+// con `DetalleAnalista` hasta su propio plan (revisión Codex del plan).
+import type { JSX, ReactNode } from 'react'
+import { AlertCircle, ChevronRight } from 'lucide-react'
+import { COLOR_NIVEL, ETIQUETA_NIVEL, horaLimaDe } from '@/lib/gestion-diaria-analista'
+import {
+  MOTIVOS_EQUIPO, horarioConfirmado, presentarAtencion, presentarContacto, tiempoSinLlamar,
+  type FilaEquipoPresentada,
+} from '@/lib/gestion-diaria-equipo'
+import { haceRelativo } from '@/components/app/actividad-visual'
+import { BarrasPorHora } from './barras-por-hora'
+import { cn } from '@/lib/utils'
+
+const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
+const ENLACE = cn('mt-1.5 inline-flex min-h-6 cursor-pointer items-center gap-0.5 rounded-md text-xs font-semibold text-[var(--accent-press)] hover:underline pointer-coarse:min-h-11', FOCO)
+
+function Cuadro({ etiqueta, children }: { etiqueta: string; children: ReactNode }): JSX.Element {
+  return (
+    <div className="min-w-0 rounded-xl bg-muted/70 px-3.5 py-3">
+      <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</dt>
+      <dd className="mt-1 min-w-0">{children}</dd>
+    </div>
+  )
+}
+
+const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`
+
+export function ResumenAnalista({ fila: f, minimo, esHoy, ahora, abrirLlamadas, abrirPendientes }: {
+  fila: FilaEquipoPresentada
+  minimo: number
+  /** Solo hoy tiene sentido «hace 25 min». */
+  esHoy: boolean
+  ahora: number
+  abrirLlamadas: () => void
+  abrirPendientes: (soloVencidas: boolean) => void
+}): JSX.Element {
+  const atencion = presentarAtencion(f)
+  const contacto = presentarContacto(f.marcador, minimo)
+  const otros = atencion.lista.filter((m) => m !== MOTIVOS_EQUIPO.tarea_vencida)
+  const contestadasPorHora = f.marcador.por_hora.reduce((total, h) => total + h.contestadas, 0)
+  const ultima = f.marcador.ultima_llamada_en
+  return (
+    <div className="space-y-4">
+      {f.tareas_vencidas > 0 && (
+        <button type="button" onClick={() => abrirPendientes(true)}
+          className={cn('flex w-full cursor-pointer items-center gap-2.5 rounded-xl bg-destructive/10 px-4 py-3 text-left text-sm font-bold text-[var(--destructive-text)] transition-colors hover:bg-destructive/15', FOCO)}>
+          <AlertCircle aria-hidden className="size-[18px] shrink-0" />
+          <span className="flex-1">{plural(f.tareas_vencidas, 'tarea vencida', 'tareas vencidas')}</span>
+          <ChevronRight aria-hidden className="size-4 shrink-0" />
+        </button>
+      )}
+      {otros.length > 0 && (
+        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+        <ul role="list" aria-label="Otros motivos de atención" className="space-y-1 rounded-xl bg-warning/10 px-4 py-2.5 text-[13px] font-semibold text-[var(--warning-text)]">
+          {otros.map((m) => <li key={m}>{m}</li>)}
+        </ul>
+      )}
+
+      <dl className="grid grid-cols-2 gap-2.5">
+        <Cuadro etiqueta="Llamadas">
+          <span className="block text-2xl font-extrabold leading-tight tabular-nums text-primary">{f.marcador.llamadas}</span>
+          <span className="block text-xs text-[var(--muted-foreground-strong)]">{plural(f.marcador.contestadas, 'contestó', 'contestaron')}</span>
+          <button type="button" onClick={abrirLlamadas} aria-label={`Ver llamadas del día de ${f.nombre_completo}`} className={ENLACE}>
+            Ver llamadas<ChevronRight aria-hidden className="size-3.5" />
+          </button>
+        </Cuadro>
+        <Cuadro etiqueta="Contacto">
+          <span aria-hidden="true" className={cn('block font-extrabold leading-tight tabular-nums',
+            contacto.estado === 'evaluado' ? 'text-2xl text-primary' : 'text-base text-[var(--muted-foreground-strong)]')}>{contacto.valor}</span>
+          <span aria-hidden="true" className="block text-xs text-[var(--muted-foreground-strong)]">
+            {contacto.estado === 'evaluado'
+              ? <>{contacto.detalle} · <span className="font-semibold" style={{ color: COLOR_NIVEL[contacto.nivel!] }}>{ETIQUETA_NIVEL[contacto.nivel!]}</span></>
+              : contacto.estado === 'sin_muestra' ? `Sin muestra suficiente · ${contacto.detalle}` : contacto.detalle}
+          </span>
+          <span className="sr-only">{contacto.accesible}</span>
+        </Cuadro>
+        <Cuadro etiqueta="Citas agendadas">
+          <span className="block text-2xl font-extrabold leading-tight tabular-nums text-primary">{f.marcador.citas_agendadas}</span>
+          <span className="block text-xs text-[var(--muted-foreground-strong)]">desde «Agendó cita»</span>
+        </Cuadro>
+        <Cuadro etiqueta="Pendientes">
+          <span className="block text-2xl font-extrabold leading-tight tabular-nums text-primary">{f.tareas_pendientes}</span>
+          <span className={cn('block text-xs', f.tareas_vencidas > 0 ? 'font-semibold text-[var(--destructive-text)]' : 'text-[var(--muted-foreground-strong)]')}>
+            {plural(f.tareas_vencidas, 'vencida', 'vencidas')}
+          </span>
+          <button type="button" onClick={() => abrirPendientes(false)} aria-label={`Ver pendientes de ${f.nombre_completo}`} className={ENLACE}>
+            Ver pendientes<ChevronRight aria-hidden className="size-3.5" />
+          </button>
+        </Cuadro>
+      </dl>
+
+      {/* El desglose por hora se confirma ANTES de dibujarlo: con un desglose
+          parcial no se pintan ceros como sustituto. */}
+      {!horarioConfirmado(f.marcador) ? (
+        <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">
+          No se pudo confirmar el desglose por hora. Consulta las llamadas en el registro; no se muestran ceros como sustituto.
+        </p>
+      ) : f.marcador.llamadas === 0 ? (
+        <div className="space-y-1">
+          <h4 className="text-[15px] font-extrabold text-primary">Llamadas por hora</h4>
+          <p className="text-[13px] text-[var(--muted-foreground-strong)]">No hay llamadas registradas ese día. Esto no indica ausencia ni descarta otras gestiones.</p>
+        </div>
+      ) : (
+        <div className="space-y-1.5">
+          <BarrasPorHora porHora={f.marcador.por_hora} titulo="Llamadas por hora" alto={96}
+            apoyo={ultima !== null ? `Última llamada ${horaLimaDe(ultima)}${esHoy ? ` · ${haceRelativo(ultima, ahora)}` : ''}` : undefined} />
+          {contestadasPorHora !== f.marcador.contestadas && (
+            <p className="text-xs text-[var(--muted-foreground-strong)]">Las barras incluyen respuestas de «Número errado» o «No es la persona», que el contacto útil excluye.</p>
+          )}
+        </div>
+      )}
+
+      {/* Lo que hoy da el detalle y el diseño no dibuja: se conserva, compacto. */}
+      <div role="group" aria-label="Más datos del día" className="border-t border-border pt-3">
+      <dl className="grid grid-cols-1 gap-y-1.5 text-[12.5px]">
+        {([
+          ['Leads distintos', f.marcador.leads_tocados], ['Llamadas por lead', f.llamadas_por_lead ?? '—'],
+          ['Primera llamada', horaLimaDe(f.marcador.primera_llamada_en)], ['Tiempo sin llamar', tiempoSinLlamar(f.minutos_sin_llamar)],
+          ['Última gestión', horaLimaDe(f.ultima_gestion_en)], ['Citas pendientes del día', f.citas_hoy],
+        ] as const).map(([titulo, valor]) => (
+          <div key={titulo} className="flex min-w-0 items-baseline justify-between gap-2">
+            <dt className="text-[var(--muted-foreground-strong)]">{titulo}</dt>
+            {/* «—» se oye «Sin dato», no como silencio (revisión a11y, 27/09). */}
+            <dd className="font-semibold tabular-nums text-foreground">{valor === '—' ? <><span aria-hidden="true">—</span><span className="sr-only">Sin dato</span></> : valor}</dd>
+          </div>
+        ))}
+      </dl>
+      </div>
+    </div>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.test.tsx
new file mode 100644
index 00000000..2d06621b
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.test.tsx
@@ -0,0 +1,60 @@
+// La tabla del equipo tiene DOS contextos (plan supervisor v2, 27/09/2026):
+// gerencia la conserva como estaba (con Pendientes) y el supervisor estrena el
+// diseño: iniciales, Citas, contacto en tres estados y atención en palabras.
+import { describe, expect, it, vi } from 'vitest'
+import { render, screen, within } from '@testing-library/react'
+import { TablaEquipoDiaria } from './tabla-equipo-diaria'
+import { filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
+import type { FilaEquipoPresentada, FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
+
+const FILTROS: FiltrosEquipo = { busqueda: '', soloProblemas: false, orden: 'atencion', ascendente: false }
+const filas = [
+  filaEquipoPrueba({ analista_id: 'k', nombre_completo: 'KAREN DÍAZ', gestiones_hoy: 5, tareas_pendientes: 6, tareas_vencidas: 4,
+    requiere_atencion: true, motivos_atencion: ['tarea_vencida', 'sin_llamar_2h'],
+    marcador: { ...filaEquipoPrueba().marcador, llamadas: 12, utiles: 11, contestadas: 2, tasa_contacto_pct: 18, nivel: 'bajo', citas_agendadas: 1 } }),
+  filaEquipoPrueba({ analista_id: 'a', nombre_completo: 'ANDREA MORALES', gestiones_hoy: 3,
+    marcador: { ...filaEquipoPrueba().marcador, llamadas: 3, utiles: 3, contestadas: 2, tasa_contacto_pct: 67, nivel: null } }),
+  filaEquipoPrueba({ analista_id: 'r', nombre_completo: 'RENATO FLORES' }),
+] as FilaEquipoPresentada[]
+
+function montar(contexto?: 'supervisor') {
+  render(<TablaEquipoDiaria filas={filas} filtros={FILTROS} ordenar={vi.fn()} seleccion="k" seleccionar={vi.fn()}
+    panelId="panel" irAlDetalle={vi.fn()} minimo={5} {...(contexto ? { contexto } : {})} />)
+  return screen.getByRole('table')
+}
+
+describe('TablaEquipoDiaria', () => {
+  it('gerencia (por defecto) no cambia: Pendientes y «N motivos»', () => {
+    const tabla = montar()
+    expect(within(tabla).getAllByRole('columnheader').map((c) => c.textContent)).toEqual(['Analista', 'Llamadas', 'Contacto', 'Pendientes', 'Vencidas', 'Atención'])
+    expect(within(tabla).getByText('2 motivos')).toBeInTheDocument()
+  })
+  it('supervisor: Citas en lugar de Pendientes, orden comunicado y la fila elegida marcada', () => {
+    const tabla = montar('supervisor')
+    const cabeceras = within(tabla).getAllByRole('columnheader')
+    expect(cabeceras.map((c) => c.textContent)).toEqual(['Analista', 'Llamadas', 'Contacto', 'Citas', 'Vencidas', 'Atención'])
+    expect(cabeceras[5]).toHaveAttribute('aria-sort', 'descending')
+    expect(within(tabla).getByRole('button', { name: 'Seleccionar a KAREN DÍAZ' })).toHaveAttribute('aria-current', 'true')
+    expect(within(tabla).getByRole('button', { name: 'Ir al detalle de KAREN DÍAZ' })).toBeInTheDocument()
+  })
+  it('supervisor: la atención se dice en palabras, en rojo si es vencido, con «+N» y la lista para el lector', () => {
+    const tabla = montar('supervisor')
+    const fila = within(tabla).getByRole('button', { name: 'Seleccionar a KAREN DÍAZ' }).closest('tr')!
+    const atencion = within(fila).getByText('4 vencidas')
+    expect(atencion).toHaveStyle({ color: 'var(--destructive-text)' })
+    expect(within(fila).getByText('+1')).toBeInTheDocument()
+    expect(within(fila).getByText(': Tareas vencidas; Más de 2 h sin llamar en la jornada')).toHaveClass('sr-only')
+    const sinActividad = within(tabla).getByRole('button', { name: 'Seleccionar a RENATO FLORES' }).closest('tr')!
+    expect(within(sinActividad).getByText('Sin registro')).toBeInTheDocument()
+  })
+  it('supervisor: el contacto sin muestra suficiente dice útiles y mínimo; el evaluado, % y nivel', () => {
+    const tabla = montar('supervisor')
+    const andrea = within(tabla).getByRole('button', { name: 'Seleccionar a ANDREA MORALES' }).closest('tr')!
+    expect(within(andrea).getByText('Sin muestra')).toBeInTheDocument()
+    expect(within(andrea).getByText('3 útiles · mínimo 5')).toBeInTheDocument()
+    expect(within(andrea).queryByText('67 %')).not.toBeInTheDocument()
+    const karen = within(tabla).getByRole('button', { name: 'Seleccionar a KAREN DÍAZ' }).closest('tr')!
+    expect(within(karen).getByText('18 %')).toBeInTheDocument()
+    expect(within(karen).getByText('Bajo')).toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx
index 15ded226..d72e09b9 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx
@@ -1,6 +1,9 @@
 import { ArrowDown, ArrowUp, ArrowRight } from 'lucide-react'
 import { COLOR_NIVEL, ETIQUETA_NIVEL, textoTasa } from '@/lib/gestion-diaria-analista'
-import { MOTIVOS_EQUIPO, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
+import { MOTIVOS_EQUIPO, presentarAtencion, presentarContacto, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
+import { Avatar } from '@/components/ui/avatar'
+import { Badge } from '@/components/ui/badge'
+import { cn } from '@/lib/utils'
 
 const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
   { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
@@ -8,8 +11,7 @@ const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
   { orden: 'vencidas', titulo: 'Vencidas' }, { orden: 'atencion', titulo: 'Atención' },
 ]
 
-/** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. */
-export function TablaEquipoDiaria({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: {
+interface PropsTabla {
   filas: readonly FilaEquipoPresentada[]
   filtros: FiltrosEquipo
   ordenar: (orden: OrdenEquipo) => void
@@ -18,7 +20,18 @@ export function TablaEquipoDiaria({ filas, filtros, ordenar, seleccion, seleccio
   panelId: string
   irAlDetalle: () => void
   minimo: number
-}) {
+  /** `gerencia` (por defecto): la tabla de siempre, con Pendientes. `supervisor`:
+   * el diseño de Gestión Diaria (27/09) — iniciales, Citas, atención en palabras.
+   * Gerencia no cambia hasta su propio plan (revisión Codex del plan supervisor). */
+  contexto?: 'gerencia' | 'supervisor' | undefined
+}
+
+/** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. */
+export function TablaEquipoDiaria({ contexto = 'gerencia', ...props }: PropsTabla) {
+  return contexto === 'supervisor' ? <TablaSupervisor {...props} /> : <TablaGerencia {...props} />
+}
+
+function TablaGerencia({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: Omit<PropsTabla, 'contexto'>) {
   return (
     <div className="gd-tabla-scroll ac-scroll">
       <table aria-label="Actividad y pendientes por analista" className="gd-tabla">
@@ -60,3 +73,89 @@ export function TablaEquipoDiaria({ filas, filtros, ordenar, seleccion, seleccio
     </div>
   )
 }
+
+const COLUMNAS_SUPERVISOR: { orden: OrdenEquipo; titulo: string; ancho: string; derecha?: boolean }[] = [
+  { orden: 'nombre', titulo: 'Analista', ancho: 'me-col-nombre' }, { orden: 'llamadas', titulo: 'Llamadas', ancho: 'w-[68px]', derecha: true },
+  { orden: 'contacto', titulo: 'Contacto', ancho: 'w-[132px]', derecha: true }, { orden: 'citas', titulo: 'Citas', ancho: 'w-[56px]', derecha: true },
+  { orden: 'vencidas', titulo: 'Vencidas', ancho: 'w-[72px]', derecha: true }, { orden: 'atencion', titulo: 'Atención', ancho: 'w-[156px]' },
+]
+
+const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
+
+/**
+ * La tabla del supervisor con el diseño de Gestión Diaria (27/09). Sigue siendo
+ * una tabla semántica con `aria-sort`, el botón de selección con su nombre y la
+ * flecha «Ir al detalle»; en un contenedor estrecho (celular, zoom 200 %) las
+ * filas se vuelven tarjetas con rótulos (`mi-equipo.css`), sin scroll lateral.
+ */
+function TablaSupervisor({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: Omit<PropsTabla, 'contexto'>) {
+  return (
+    <div className="gd-tabla-scroll ac-scroll min-h-0 flex-1 overflow-y-auto">
+      <table aria-label="Actividad y pendientes por analista" className="me-tabla w-full table-fixed border-separate border-spacing-0">
+        <colgroup>{COLUMNAS_SUPERVISOR.map((c) => <col key={c.orden} className={c.ancho} />)}</colgroup>
+        <thead className="sticky top-0 z-[1] bg-card">
+          <tr>{COLUMNAS_SUPERVISOR.map((c, i) => (
+            <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}
+              className={cn('border-b border-border px-2 py-0 font-normal', i === 0 && 'pl-4', i === COLUMNAS_SUPERVISOR.length - 1 && 'pr-4')}>
+              <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}
+                className={cn('flex min-h-10 w-full cursor-pointer items-center gap-1 whitespace-nowrap rounded-md text-[12.5px] font-semibold text-[var(--muted-foreground-strong)] hover:text-primary focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11',
+                  c.derecha && 'justify-end', filtros.orden === c.orden && 'text-primary')}>
+                {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden className="size-3.5" /> : <ArrowDown aria-hidden className="size-3.5" />)}
+              </button>
+            </th>
+          ))}</tr>
+        </thead>
+        <tbody>
+          {filas.length === 0 && <tr><td colSpan={6} className="px-4 py-6 text-[13px] text-[var(--muted-foreground-strong)]">Ningún analista coincide con estos filtros.</td></tr>}
+          {filas.map((f) => {
+            const activa = f.analista_id === seleccion
+            const contacto = presentarContacto(f.marcador, minimo)
+            const atencion = presentarAtencion(f)
+            return (
+              <tr key={f.analista_id} data-analista={f.analista_id} data-activa={activa}
+                className={cn('transition-colors [&>*]:border-b [&>*]:border-border', activa ? 'bg-accent/[0.07]' : 'hover:bg-muted/50')}>
+                <th scope="row" className={cn('py-0 pl-4 pr-2 text-left font-normal', activa && 'shadow-[inset_3px_0_0_var(--color-accent)]')}>
+                  <div className="flex min-h-[52px] items-center gap-2.5">
+                    <Avatar nombre={f.nombre_completo} color="var(--accent-press)" relleno={activa} />
+                    <button type="button" aria-label={`Seleccionar a ${f.nombre_completo}`} aria-current={activa ? 'true' : undefined}
+                      aria-controls={panelId} onClick={() => seleccionar(f)}
+                      className={cn('min-w-0 flex-1 cursor-pointer rounded-md py-1 text-left text-sm font-bold leading-snug [overflow-wrap:anywhere] pointer-coarse:min-h-11', FOCO,
+                        activa ? 'text-[var(--accent-press)]' : 'text-primary')}>{f.nombre_completo}</button>
+                    {activa && <button type="button" aria-label={`Ir al detalle de ${f.nombre_completo}`} onClick={irAlDetalle}
+                      className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-md text-[var(--accent-press)] hover:bg-accent/10 pointer-coarse:size-11', FOCO)}>
+                      <ArrowRight aria-hidden className="size-4" />
+                    </button>}
+                  </div>
+                </th>
+                <td data-etiqueta="Llamadas" className="px-2 text-right text-sm font-semibold tabular-nums text-foreground">{f.marcador.llamadas}</td>
+                <td data-etiqueta="Contacto" className="px-2 text-right">
+                  <span aria-hidden="true" className="inline-flex flex-wrap items-center justify-end gap-x-2 gap-y-0.5">
+                    {contacto.estado === 'evaluado' ? <>
+                      <span className="text-sm font-bold tabular-nums text-foreground">{contacto.valor}</span>
+                      <Badge className="min-h-[22px] py-0 text-[11.5px]" color={COLOR_NIVEL[contacto.nivel!]}>{ETIQUETA_NIVEL[contacto.nivel!]}</Badge>
+                    </> : contacto.estado === 'sin_muestra' ? <>
+                      <span className="text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Sin muestra</span>
+                      <span className="w-full text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{contacto.detalle}</span>
+                    </> : <span className="text-sm text-[var(--muted-foreground-strong)]">—</span>}
+                  </span>
+                  <span className="sr-only">{contacto.accesible}</span>
+                </td>
+                <td data-etiqueta="Citas" className="px-2 text-right text-sm tabular-nums text-foreground">{f.marcador.citas_agendadas}</td>
+                <td data-etiqueta="Vencidas" className={cn('px-2 text-right text-sm font-semibold tabular-nums', f.tareas_vencidas > 0 ? 'text-[var(--destructive-text)]' : 'text-foreground')}>{f.tareas_vencidas}</td>
+                <td data-etiqueta="Atención" className="py-2 pl-4 pr-4 text-[13px]">
+                  {atencion.texto === null
+                    ? f.gestiones_hoy === 0 ? <span className="text-[var(--muted-foreground-strong)]">Sin registro</span>
+                      : <><span aria-hidden="true" className="text-[var(--muted-foreground-strong)]">—</span><span className="sr-only">Sin alertas</span></>
+                    : <span className="font-semibold" style={{ color: atencion.tono === 'vencido' ? 'var(--destructive-text)' : 'var(--warning-text)' }}>
+                      {atencion.texto}{atencion.mas > 0 && <span className="ml-1.5 font-normal text-[var(--muted-foreground-strong)]">+{atencion.mas}</span>}
+                    </span>}
+                  {atencion.lista.length > 0 && <span className="sr-only">: {atencion.lista.join('; ')}</span>}
+                </td>
+              </tr>
+            )
+          })}
+        </tbody>
+      </table>
+    </div>
+  )
+}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/ultimas-gestiones-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/ultimas-gestiones-supervisor.tsx
index 3bf0064d..ff88bcc3 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/ultimas-gestiones-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/ultimas-gestiones-supervisor.tsx
@@ -1,12 +1,20 @@
-import { useEffect, useEffectEvent, useMemo, useRef } from 'react'
+import { useEffect, useEffectEvent, useLayoutEffect, useMemo, useRef } from 'react'
 import { useRegistroActividadOperativo } from '@/data/gestion-diaria-queries'
 import { CrmApiError } from '@/data/crm-api'
 import { usePanelesActions } from '@/lib/store-context'
 import { ETIQUETA_CORTA, horaDeItem, type FiltrosRegistro } from '@/lib/gestion-diaria'
+import { Badge } from '@/components/ui/badge'
 import { Button } from '@/components/ui/button'
 
-export function UltimasGestionesSupervisor({ analista, dia, visible, actualizacion, revalidar }: {
+const HORA = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false })
+
+/** Las 3 últimas gestiones del analista con el diseño de Gestión Diaria (27/09):
+ * hora, etiqueta del resultado y el lead (abre su ficha). Misma consulta y clave
+ * que «Registro → Todo», así que no pide nada de más. */
+export function UltimasGestionesSupervisor({ analista, dia, visible, actualizacion, revalidar, silencioso = false }: {
   analista: string; dia: string; visible: boolean; actualizacion: number; revalidar: () => void
+  /** Panel abierto solo (selección automática): sin anunciar cargas ni errores. */
+  silencioso?: boolean
 }) {
   const filtros = useMemo<FiltrosRegistro>(() => ({ dia, analistaIds: [analista], pestana: 'todo', etapa: null }), [dia, analista])
   // Misma clave y tamaño que Registro → Todo, primera página sin filtro.
@@ -21,16 +29,32 @@ export function UltimasGestionesSupervisor({ analista, dia, visible, actualizaci
     revision.current = actualizacion; refrescar()
   }, [actualizacion])
   useEffect(() => { if (sinPermiso) revocar() }, [sinPermiso])
-  return <section className="space-y-2 mt-4" aria-label="Últimas gestiones del analista">
-    <h4 className="font-semibold">Últimas gestiones</h4>
-    {consulta.pagina && <p className="text-[var(--muted-foreground-strong)]">Consulta: {new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(consulta.pagina.generado_en))} · Lima.</p>}
-    {consulta.cargando && <p role="status">Consultando las últimas gestiones…</p>}
-    {consulta.error ? <div role="alert"><p>No se pudieron confirmar las últimas gestiones.</p>
-      {!sinPermiso && <Button className="min-h-11 text-base" variant="outline" onClick={() => { void consulta.recargar() }} disabled={consulta.enVuelo}>Reintentar últimas gestiones</Button>}</div>
-      : consulta.pagina && consulta.pagina.items.length === 0 ? <p>No hay gestiones visibles de este analista en el día.</p>
-        : <ol>{consulta.pagina?.items.slice(0, 3).map(item => <li key={item.id} className="py-2">
-          <p><time dateTime={new Date(item.creado_en).toISOString()}>{horaDeItem(item)}</time> · {ETIQUETA_CORTA[item.tipo]}</p>
-          <Button variant="link" className="min-h-11 h-auto max-w-full whitespace-normal px-0 text-left text-base" onClick={() => abrirLead(item.lead_id)}>{item.lead_nombre}</Button>
+  // Si «Reintentar» se desmonta con el foco dentro (salió bien), el foco pasa al título.
+  const titulo = useRef<HTMLHeadingElement>(null)
+  const focoEnReintento = useRef(false)
+  useLayoutEffect(() => {
+    if (consulta.error) return
+    if (focoEnReintento.current) { focoEnReintento.current = false; titulo.current?.focus({ preventScroll: true }) }
+  }, [consulta.error])
+  return <section className="space-y-2" aria-label="Últimas gestiones del analista">
+    <div className="flex items-baseline justify-between gap-3">
+      <h4 ref={titulo} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Últimas gestiones</h4>
+      {consulta.pagina && <p className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">Consulta {HORA.format(new Date(consulta.pagina.generado_en))}</p>}
+    </div>
+    {consulta.cargando && <p role={silencioso ? undefined : 'status'} className="text-[13px] text-[var(--muted-foreground-strong)]">Consultando las últimas gestiones…</p>}
+    {consulta.error ? <div role={silencioso ? undefined : 'alert'} className="space-y-2 text-[13px]"><p>No se pudieron confirmar las últimas gestiones.</p>
+      {!sinPermiso && <Button className="h-9 text-[13px] pointer-coarse:h-11 aria-disabled:cursor-default aria-disabled:opacity-60" variant="outline" aria-disabled={consulta.enVuelo}
+        onFocus={() => { focoEnReintento.current = true }} onBlur={() => { focoEnReintento.current = false }}
+        onClick={() => { if (!consulta.enVuelo) void consulta.recargar() }}>Reintentar últimas gestiones</Button>}</div>
+      : consulta.pagina && consulta.pagina.items.length === 0 ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">No hay gestiones visibles de este analista en el día.</p>
+        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+        : <ol role="list" className="divide-y divide-border">{consulta.pagina?.items.slice(0, 3).map(item => <li key={item.id} className="flex min-w-0 items-center gap-3 py-2">
+          <time dateTime={new Date(item.creado_en).toISOString()} className="w-11 shrink-0 text-[13px] tabular-nums text-[var(--muted-foreground-strong)]">{horaDeItem(item)}</time>
+          <Badge className="min-h-[22px] shrink-0 py-0 text-[11.5px]" color="var(--primary)" variant="outline">{ETIQUETA_CORTA[item.tipo]}</Badge>
+          {item.lead_nombre
+            ? <button type="button" onClick={() => abrirLead(item.lead_id)}
+              className="min-w-0 cursor-pointer truncate rounded-md text-left text-[13.5px] font-bold text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:min-h-11">{item.lead_nombre}</button>
+            : <span className="min-w-0 truncate text-[13px] text-[var(--muted-foreground-strong)]">Lead no visible</span>}
         </li>)}</ol>}
   </section>
 }
diff --git a/CRM-Avance-Corp/app/src/components/ui/tabs.tsx b/CRM-Avance-Corp/app/src/components/ui/tabs.tsx
index 878726d0..8eecb955 100644
--- a/CRM-Avance-Corp/app/src/components/ui/tabs.tsx
+++ b/CRM-Avance-Corp/app/src/components/ui/tabs.tsx
@@ -68,7 +68,7 @@ const CLASES_VARIANTE = {
   subrayado: {
     lista: 'flex w-full gap-6 overflow-x-auto border-b border-border',
     tab: 'shrink-0 justify-center whitespace-nowrap !px-0.5 font-semibold focus-visible:!-outline-offset-2',
-    activa: 'font-bold text-[var(--accent-press)] shadow-[inset_0_-2px_0_var(--color-accent)]',
+    activa: 'font-bold text-[var(--accent-press)] shadow-[inset_0_-2px_0_var(--color-accent)] forced-colors:underline forced-colors:decoration-2 forced-colors:underline-offset-8',
     inactiva: 'text-[var(--muted-foreground-strong)] hover:text-primary',
     extra: '',
   },
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.test.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.test.ts
index d492d4e9..116c833e 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.test.ts
@@ -1,6 +1,6 @@
 import { describe, expect, it } from 'vitest'
 import * as v from 'valibot'
-import { DiaEquipoSchema, filtrarOrdenarEquipo, horarioConfirmado, tiempoSinLlamar, type OrdenEquipo } from './gestion-diaria-equipo'
+import { DiaEquipoSchema, compararGravedad, filtrarOrdenarEquipo, horarioConfirmado, presentarAtencion, presentarContacto, tiempoSinLlamar, type FilaEquipoPresentada, type OrdenEquipo } from './gestion-diaria-equipo'
 import { diaEquipoPrueba, filaEquipoPrueba } from './gestion-diaria-equipo.fixture'
 import { diaEquipoDesdeDemo } from './gestion-diaria-equipo-demo'
 import type { Actividad, Miembro } from './tipos'
@@ -127,3 +127,43 @@ describe('Espejo demo: roster y calendario', () => {
     expect(d.equipo[0]?.sin_llamar_2h).toBe(esperado)
   })
 })
+
+describe('Supervisor con el diseño de Gestión Diaria (27/09/2026)', () => {
+  const fila = (cambios: Parameters<typeof filaEquipoPrueba>[0] = {}) => filaEquipoPrueba(cambios) as FilaEquipoPresentada
+  it('«Atención» dice el motivo MÁS GRAVE con su número, en rojo solo si es vencido, y el resto en «+N»', () => {
+    const vencidas = presentarAtencion(fila({ tareas_vencidas: 4, requiere_atencion: true, motivos_atencion: ['sin_llamar_2h', 'tarea_vencida', 'datos_incompletos'] }))
+    expect(vencidas).toEqual({ texto: '4 vencidas', tono: 'vencido', mas: 2,
+      lista: ['Tareas vencidas', 'Más de 2 h sin llamar en la jornada', 'Datos pendientes de revisar'] })
+    expect(presentarAtencion(fila({ tareas_vencidas: 1, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })).texto).toBe('1 vencida')
+    const primer = presentarAtencion(fila({ primer_intento_vencido: 3, requiere_atencion: true, motivos_atencion: ['primer_intento_vencido'] }))
+    expect(primer).toMatchObject({ texto: 'Primer intento tarde (3)', tono: 'aviso', mas: 0 })
+    expect(presentarAtencion(fila())).toEqual({ texto: null, tono: null, mas: 0, lista: [] })
+  })
+  it('sin número confirmado no inventa uno (tareas 0 o señal sin conteo)', () => {
+    expect(presentarAtencion(fila({ tareas_vencidas: 0, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })).texto).toBe('Tareas vencidas')
+    expect(presentarAtencion(fila({ primer_intento_vencido: null, requiere_atencion: true, motivos_atencion: ['primer_intento_vencido'] })).texto).toBe('Primer intento tarde')
+  })
+  it('el orden «Atención» del supervisor va por GRAVEDAD, no por número de motivos', () => {
+    const tres = fila({ analista_id: 'x', nombre_completo: 'TRES AVISOS', requiere_atencion: true, motivos_atencion: ['sin_llamar_2h', 'datos_incompletos', 'primer_intento_vencido'] })
+    const vencida = fila({ analista_id: 'y', nombre_completo: 'UNA VENCIDA', tareas_vencidas: 9, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })
+    const base = { busqueda: '', soloProblemas: false, orden: 'atencion' as const, ascendente: false }
+    expect(filtrarOrdenarEquipo([tres, vencida], { ...base, gravedad: true }).map((f) => f.nombre_completo)).toEqual(['UNA VENCIDA', 'TRES AVISOS'])
+    // Gerencia no cambia: sigue contando motivos.
+    expect(filtrarOrdenarEquipo([tres, vencida], base).map((f) => f.nombre_completo)).toEqual(['TRES AVISOS', 'UNA VENCIDA'])
+    expect(compararGravedad(vencida, tres)).toBeLessThan(0)
+  })
+  it('ordena por citas agendadas', () => {
+    const a = fila({ analista_id: 'a', nombre_completo: 'A', marcador: { ...fila().marcador, citas_agendadas: 1 } })
+    const b = fila({ analista_id: 'b', nombre_completo: 'B', marcador: { ...fila().marcador, citas_agendadas: 3 } })
+    expect(filtrarOrdenarEquipo([a, b], { busqueda: '', soloProblemas: false, orden: 'citas', ascendente: false }).map((f) => f.nombre_completo)).toEqual(['B', 'A'])
+  })
+  it('el contacto tiene TRES estados y el de muestra insuficiente dice útiles y mínimo', () => {
+    const m = fila().marcador
+    expect(presentarContacto(m, 5)).toMatchObject({ estado: 'sin_utiles', valor: '—', detalle: 'Sin llamadas útiles' })
+    const poca = presentarContacto({ ...m, llamadas: 3, utiles: 3, contestadas: 2, tasa_contacto_pct: 67, nivel: null }, 5)
+    expect(poca).toMatchObject({ estado: 'sin_muestra', valor: 'Sin muestra', detalle: '3 útiles · mínimo 5' })
+    expect(poca.accesible).toBe('Sin muestra suficiente: 2 de 3 útiles contestaron; se evalúa desde 5 útiles')
+    const buena = presentarContacto({ ...m, llamadas: 12, utiles: 11, contestadas: 2, tasa_contacto_pct: 18, nivel: 'bajo' }, 5)
+    expect(buena).toMatchObject({ estado: 'evaluado', valor: '18 %', nivel: 'bajo', detalle: 'de 11 útiles' })
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.ts
index f9b87735..ace6292a 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-equipo.ts
@@ -1,7 +1,7 @@
 // Contrato de F4. En real, todos los indicadores proceden de una sola foto
 // autorizada del servidor. Aquí sólo se valida, busca, ordena y presenta.
 import * as v from 'valibot'
-import { MarcadorSchema, UmbralesSchema, type Marcador } from './gestion-diaria-analista'
+import { ETIQUETA_NIVEL, MarcadorSchema, UmbralesSchema, type Marcador } from './gestion-diaria-analista'
 import { CortesJornadaSchema } from './gestion-diaria-cortes'
 
 const Natural = v.pipe(v.number(), v.integer(), v.minValue(0))
@@ -96,9 +96,13 @@ export function resumenEquipo(equipo: readonly FilaEquipoDiario[]) {
   }
 }
 
-export type OrdenEquipo = 'nombre' | 'llamadas' | 'contacto' | 'pendientes' | 'vencidas' | 'atencion'
+export type OrdenEquipo = 'nombre' | 'llamadas' | 'contacto' | 'pendientes' | 'citas' | 'vencidas' | 'atencion'
 export type EstadoEquipo = 'todos' | 'con_registro' | 'sin_registro' | 'con_pendientes'
-export interface FiltrosEquipo { busqueda: string; soloProblemas: boolean; estado?: EstadoEquipo; orden: OrdenEquipo; ascendente: boolean }
+export interface FiltrosEquipo {
+  busqueda: string; soloProblemas: boolean; estado?: EstadoEquipo; orden: OrdenEquipo; ascendente: boolean
+  /** «Atención» por GRAVEDAD (supervisor, 27/09) y no por número de motivos (gerencia, como antes). */
+  gravedad?: boolean
+}
 const normalizar = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es').trim()
 
 export function filtrarOrdenarEquipo<T extends FilaEquipoPresentada>(equipo: readonly T[], filtros: FiltrosEquipo): T[] {
@@ -113,8 +117,13 @@ export function filtrarOrdenarEquipo<T extends FilaEquipoPresentada>(equipo: rea
         case 'nombre': diferencia = a.nombre_completo.localeCompare(b.nombre_completo, 'es'); break
         case 'llamadas': diferencia = a.marcador.llamadas - b.marcador.llamadas; break
         case 'pendientes': diferencia = a.tareas_pendientes - b.tareas_pendientes; break
+        case 'citas': diferencia = a.marcador.citas_agendadas - b.marcador.citas_agendadas; break
         case 'vencidas': diferencia = a.tareas_vencidas - b.tareas_vencidas; break
         case 'atencion': {
+          if (filtros.gravedad) {
+            diferencia = -compararGravedad(a, b)
+            break
+          }
           diferencia = a.motivos_atencion.length - b.motivos_atencion.length
           if (!diferencia) return b.tareas_vencidas - a.tareas_vencidas
             || a.nombre_completo.localeCompare(b.nombre_completo, 'es') || a.analista_id.localeCompare(b.analista_id)
@@ -157,3 +166,93 @@ export function horarioConfirmado(marcador: Marcador): boolean {
     && contestadasPorHora >= marcador.contestadas
     && contestadasPorHora - marcador.contestadas <= marcador.llamadas - marcador.utiles
 }
+
+/**
+ * Prioridad de los motivos de atención (revisión Codex, 27/09): lo vencido
+ * primero. El orden en que llegan del servidor no dice gravedad, y contar
+ * motivos ponía tres avisos por delante de muchas tareas vencidas.
+ */
+export const PRIORIDAD_MOTIVO: readonly (keyof typeof MOTIVOS_EQUIPO)[] = [
+  'tarea_vencida', 'primer_intento_vencido', 'corte_manana', 'corte_tarde', 'sin_llamar_2h', 'datos_incompletos',
+]
+
+const rangoAtencion = (f: FilaEquipoPresentada) => {
+  const i = PRIORIDAD_MOTIVO.findIndex((m) => f.motivos_atencion.includes(m))
+  return i === -1 ? PRIORIDAD_MOTIVO.length : i
+}
+
+/** Negativo si `a` necesita atención ANTES que `b` (más grave primero). */
+export function compararGravedad(a: FilaEquipoPresentada, b: FilaEquipoPresentada): number {
+  return rangoAtencion(a) - rangoAtencion(b)
+    || b.tareas_vencidas - a.tareas_vencidas
+    || (b.primer_intento_vencido ?? 0) - (a.primer_intento_vencido ?? 0)
+    || b.motivos_atencion.length - a.motivos_atencion.length
+}
+
+export interface AtencionPresentada {
+  /** El motivo más grave, dicho con su número («4 vencidas»); null si no hay. */
+  texto: string | null
+  /** `vencido` (rojo) SOLO para tareas vencidas; el resto es `aviso` (ámbar). */
+  tono: 'vencido' | 'aviso' | null
+  /** Motivos además del principal («+2»). */
+  mas: number
+  /** Todos los motivos en palabras, en orden de gravedad. */
+  lista: string[]
+}
+
+function textoMotivo(motivo: keyof typeof MOTIVOS_EQUIPO, f: FilaEquipoPresentada): string {
+  switch (motivo) {
+    case 'tarea_vencida': return f.tareas_vencidas > 0 ? `${f.tareas_vencidas} ${f.tareas_vencidas === 1 ? 'vencida' : 'vencidas'}` : MOTIVOS_EQUIPO.tarea_vencida
+    // `null` = sin control vigente: el motivo no llega; si llega, se dice sin inventar el número.
+    case 'primer_intento_vencido': return f.primer_intento_vencido !== null && f.primer_intento_vencido > 1 ? `Primer intento tarde (${f.primer_intento_vencido})` : 'Primer intento tarde'
+    case 'corte_manana': case 'corte_tarde': return 'Corte de llamadas pendiente'
+    case 'sin_llamar_2h': return 'Más de 2 h sin llamar'
+    case 'datos_incompletos': return 'Datos por revisar'
+  }
+}
+
+/** «Atención» dicha en palabras para la tabla y el panel del supervisor. */
+export function presentarAtencion(f: FilaEquipoPresentada): AtencionPresentada {
+  const motivos = PRIORIDAD_MOTIVO.filter((m) => f.motivos_atencion.includes(m))
+  const principal = motivos[0]
+  if (principal === undefined) return { texto: null, tono: null, mas: 0, lista: [] }
+  return {
+    texto: textoMotivo(principal, f),
+    tono: principal === 'tarea_vencida' ? 'vencido' : 'aviso',
+    mas: motivos.length - 1,
+    lista: motivos.map((m) => MOTIVOS_EQUIPO[m]),
+  }
+}
+
+export interface ContactoPresentado {
+  estado: 'sin_utiles' | 'sin_muestra' | 'evaluado'
+  /** Lo que se lee grande: «18 %», «Sin muestra» o «—». */
+  valor: string
+  nivel: Marcador['nivel']
+  /** El apoyo visible: «de 11 útiles», «3 útiles · mínimo 5», «Sin llamadas útiles». */
+  detalle: string
+  /** La frase completa para el lector de pantalla. */
+  accesible: string
+}
+
+/**
+ * Los TRES estados del contacto (revisión Codex, 27/09): sin útiles, muestra
+ * insuficiente (se dice con el mínimo, nunca como una tasa evaluada) y evaluado.
+ */
+export function presentarContacto(m: Marcador, minimo: number): ContactoPresentado {
+  if (m.utiles === 0 || m.tasa_contacto_pct === null) {
+    return { estado: 'sin_utiles', valor: '—', nivel: null, detalle: 'Sin llamadas útiles', accesible: 'Sin llamadas útiles' }
+  }
+  if (m.nivel === null) {
+    return {
+      estado: 'sin_muestra', valor: 'Sin muestra', nivel: null,
+      detalle: `${m.utiles} ${m.utiles === 1 ? 'útil' : 'útiles'} · mínimo ${minimo}`,
+      accesible: `Sin muestra suficiente: ${m.contestadas} de ${m.utiles} útiles contestaron; se evalúa desde ${minimo} útiles`,
+    }
+  }
+  return {
+    estado: 'evaluado', valor: `${m.tasa_contacto_pct} %`, nivel: m.nivel,
+    detalle: `de ${m.utiles} ${m.utiles === 1 ? 'útil' : 'útiles'}`,
+    accesible: `${m.tasa_contacto_pct} %: ${m.contestadas} de ${m.utiles} útiles contestaron; nivel ${ETIQUETA_NIVEL[m.nivel]}`,
+  }
+}
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx
index 0db1eddc..403322a5 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx
@@ -42,12 +42,12 @@ export function GestionDiaria(): JSX.Element {
     <a href={hashDe('gestion-diaria')} aria-current={!cola ? 'page' : undefined} className={`${enlace} ${!cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Resumen del día</a>
     {accesoCola}
   </nav>
-  // El analista lleva a su cabecera un solo botón, como el «Mi Hoy completo ›»
-  // del diseño (27/09/2026): la cabecera no puede pesar más que la pregunta. La
-  // vuelta al resumen sigue en la barra de secciones de la cola, con su
-  // `aria-current`. Supervisor y gerencia conservan su acceso, como hasta ahora.
-  const integrada = yo.rol === 'vendedor'
-    ? <nav aria-label="Secciones de Gestión Diaria"><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} className="inline-flex h-9 items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Seguimiento completo<ChevronRight aria-hidden className="size-4" /></a></nav>
+  // El analista y el supervisor llevan a su cabecera un solo botón compacto, como
+  // el «Mi Hoy completo ›» del diseño (27/09/2026): la cabecera no puede pesar
+  // más que la pregunta. La vuelta al resumen sigue en la barra de secciones de
+  // la cola, con su `aria-current`. Gerencia conserva su acceso hasta su plan.
+  const integrada = yo.rol === 'vendedor' || yo.rol === 'supervisor'
+    ? <nav aria-label="Secciones de Gestión Diaria"><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} className="inline-flex h-9 items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11">Seguimiento completo<ChevronRight aria-hidden className="size-4" /></a></nav>
     : <nav aria-label="Secciones de Gestión Diaria">{accesoCola}</nav>
   return <div key={`${yo.id}:${yo.rol}:${yo.demo}`} className="mx-auto w-full max-w-[1640px] space-y-5">
     {!cabeceraIntegrada && secciones}
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx
index 294abbb2..5dabba08 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx
@@ -562,7 +562,7 @@ function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaid
           <div className="flex items-center gap-2.5 px-5 pb-3.5 pt-2">
             <Phone aria-hidden className="size-[18px]" />
             <h3 id={`${id}-ahora`} className="text-[15px] font-extrabold">Ahora</h3>
-            {fila !== null && posicion > 0 && <span className="ml-auto text-[13px] tabular-nums text-primary-foreground/80"><span className="sr-only">Contacto </span>{posicion} de {total}<span className="sr-only"> en esta lista</span></span>}
+            {fila !== null && posicion > 0 && <span className="ml-auto text-[13px] tabular-nums text-primary-foreground/80"><span className="sr-only">Contacto</span>{' '}{posicion} de {total}{' '}<span className="sr-only">en esta lista</span></span>}
           </div>
         </div>
         {fila === null ? (
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/mi-equipo.css b/CRM-Avance-Corp/app/src/screens/gestion-diaria/mi-equipo.css
new file mode 100644
index 00000000..56ae4a27
--- /dev/null
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/mi-equipo.css
@@ -0,0 +1,38 @@
+/* «Mi equipo hoy» del supervisor con el diseño de Gestión Diaria (27/09/2026).
+ * Estilos PROPIOS: gerencia sigue con supervisor.css (su raíz también se llama
+ * gd-supervisor, por eso aquí nada cuelga de esa clase).
+ * Shell vigente: Topbar 64 + padding vertical 48 = 112 px. Solo desplazan la
+ * tabla y el panel; la página no, salvo en pantallas bajas o angostas. */
+.me-pantalla { container-type: inline-size; height: calc(100svh - 112px); min-height: 560px; }
+@media (max-height: 650px), (max-width: 1023px) {
+  .me-pantalla { height: auto; min-height: 0; }
+  /* Con la página desplazándose, la tabla no lleva un scroll propio encima. */
+  .me-pantalla .gd-tabla-scroll { flex: none; overflow: visible; }
+}
+
+.me-equipo { container-type: inline-size; }
+.me-col-nombre { width: auto; }
+/* El foco no queda bajo la cabecera pegada de la tabla (SC 2.4.11). */
+.me-tabla tbody :is(button, a) { scroll-margin-top: 3rem; }
+
+/* Contenedor angosto (celular, zoom 200 %): cada analista es una tarjeta con
+ * rótulos, sin scroll lateral (reflujo WCAG 1.4.10). Los botones de ordenar
+ * siguen arriba, en una fila que se reparte. */
+@container (max-width: 44rem) {
+  .me-tabla colgroup { display: none; }
+  .me-tabla thead { display: block; position: static; }
+  .me-tabla thead tr { display: flex; flex-wrap: wrap; gap: 0 6px; padding: 4px 10px; border-bottom: 1px solid var(--border); }
+  .me-tabla thead th { border: 0 !important; padding: 0 !important; }
+  .me-tabla thead th button { justify-content: flex-start !important; }
+  .me-tabla tbody { display: block; }
+  .me-tabla tbody tr { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); padding: 6px 6px 10px; border-bottom: 1px solid var(--border); }
+  .me-tabla tbody tr > * { border: 0 !important; text-align: left !important; padding: 4px 10px !important; box-shadow: none !important; }
+  .me-tabla tbody th, .me-tabla tbody td[colspan] { grid-column: 1 / -1; }
+  .me-tabla tbody td::before { content: attr(data-etiqueta); display: block; margin-bottom: 2px; font-size: 11.5px; font-weight: 600; color: var(--muted-foreground-strong); }
+  .me-tabla tbody td [aria-hidden='true'] { justify-content: flex-start; }
+}
+
+@media (forced-colors: active) {
+  .me-tabla [data-activa='true'] th, .me-tabla tbody tr[data-activa='true'] > th { border-left: 3px solid Highlight !important; }
+  .me-tabla th, .me-tabla td { border-bottom: 1px solid CanvasText; }
+}
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.css b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.css
index 64e899bf..219bf7be 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.css
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.css
@@ -38,7 +38,6 @@
 .gd-tabla button:focus-visible,.gd-panel :focus-visible,.gd-cabecera h2:focus-visible { outline:2px solid var(--accent); outline-offset:-2px; border-radius:4px; }
 .gd-motivos { color:var(--warning-text); font-weight:600; }
 .gd-tabla .gd-sin-filas { padding:24px; }
-.gd-estado { padding:24px; display:flex; flex-direction:column; gap:16px; align-items:start; }
 .gd-panel-alojamiento,.gd-panel-host { min-width:0; min-height:0; height:100%; }
 .gd-panel-host { display:flex; flex-direction:column; }
 .gd-panel { display:flex; flex:1; flex-direction:column; min-height:0; min-width:0; border-radius:10px; background:var(--card); box-shadow:inset 0 0 0 1px var(--border); font-size:16px; line-height:1.375; overflow:hidden; }
@@ -53,13 +52,8 @@
 .gd-panel-cuerpo[hidden],.gd-panel-alojamiento[hidden] { display:none; }
 .gd-resumen-principal { display:flex; gap:12px; align-items:baseline; color:var(--primary); }
 .gd-resumen-principal strong { font-size:36px; font-weight:750; line-height:1.2; }
-.gd-atencion-detalle { margin-top:12px; padding:12px; border-radius:8px; background:color-mix(in srgb,var(--warning) 10%,var(--card)); color:var(--warning-text); }
 .gd-seleccion-oculta { padding:8px 12px; background:var(--muted); flex-shrink:0; }
 .gd-cortes { display:flex; align-items:center; justify-content:space-between; gap:8px; min-height:44px; flex-shrink:0; border-radius:10px; background:var(--card); box-shadow:inset 0 0 0 1px var(--border); }
-.gd-cortes-resumen { display:flex; flex:1; flex-wrap:wrap; align-items:center; gap:2px 16px; min-width:0; }
-.gd-cortes-resumen>span { overflow-wrap:anywhere; }
-.gd-cortes-resumen strong { color:var(--warning-text); font-weight:600; }
-.gd-cortes-consulta { color:var(--muted-foreground-strong); padding-right:12px; white-space:nowrap; }
 .gd-resultado-corte { border:1px solid var(--border); border-radius:8px; }
 .gd-resultado-corte summary { cursor:pointer; min-height:44px; padding:10px 12px; display:flex; flex-wrap:wrap; align-items:center; gap:4px 16px; list-style:none; }
 .gd-resultado-corte summary::-webkit-details-marker { display:none; }
@@ -100,8 +94,6 @@
   .gd-tabla tbody td::before { content:attr(data-etiqueta); display:block; color:var(--muted-foreground-strong); font-size:16px; margin-bottom:4px; }
   .gd-tabla [data-activa=true] .gd-nombre { box-shadow:none; }
   .gd-cortes { flex-wrap:wrap; }
-  .gd-cortes-resumen { flex-basis:100%; padding:0 12px; }
-  .gd-cortes-consulta { padding:0 12px 8px; }
 }
 @media (max-height:650px), (max-width:900px) {
   .gd-supervisor { height:auto; min-height:0; }
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
index f6690aaf..5c8a2b0c 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
@@ -1,5 +1,5 @@
-import { beforeEach, describe, expect, it, vi } from 'vitest'
-import { fireEvent, render, screen, within, waitFor } from '@testing-library/react'
+import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
+import { act, fireEvent, render, screen, within, waitFor } from '@testing-library/react'
 import { useState } from 'react'
 import { diaEquipoPrueba, filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
 import { idH4, jornadaH4 } from '@/lib/gestion-diaria-h4.fixture'
@@ -41,7 +41,8 @@ describe('Supervisor horizontal', () => {
     expect(fecha).toHaveValue('2026-09-21')
     expect(fecha).toHaveAttribute('min', '2025-09-21')
     expect(fecha).toHaveAttribute('max', '2026-09-21')
-    expect(screen.getByRole('button', { name: 'Hoy' })).toBeDisabled()
+    // aria-disabled y no disabled: el botón puede conservar el foco (revisión Codex, 27/09).
+    expect(screen.getByRole('button', { name: 'Hoy' })).toHaveAttribute('aria-disabled', 'true')
     abrirRegistro()
     fireEvent.click(screen.getByRole('button', { name: 'Página 1' }))
     fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'ana' } })
@@ -103,15 +104,21 @@ describe('Supervisor horizontal', () => {
     await waitFor(() => expect(screen.getByRole('heading', { name: 'Detalle de ANA H4' })).toHaveFocus())
     expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-18', analistaIds: [idH4(2)], pestanaInicial: 'llamadas' }))
   })
-  it('seis columnas, ceros, cifras completas y panel inicial sin consultas', () => {
+  it('seis columnas (Citas en lugar de Pendientes), ceros, cifras completas y panel con quien más atención necesita', () => {
     render(<GestionDiariaSupervisor />)
     const tabla = screen.getByRole('table')
-    expect(within(tabla).getAllByRole('columnheader')).toHaveLength(6)
-    expect(within(tabla).getAllByText('270')).toHaveLength(2)
+    expect(within(tabla).getAllByRole('columnheader').map((c) => c.textContent)).toEqual(['Analista', 'Llamadas', 'Contacto', 'Citas', 'Vencidas', 'Atención'])
+    // Diseño 27/09: Pendientes sale de la tabla (sigue en la franja y el panel); las 270 vencidas quedan.
+    expect(within(tabla).getAllByText('270')).toHaveLength(1)
+    expect(within(tabla).getByText('270 vencidas')).toBeInTheDocument()
     expect(within(tabla).getByText(/Tareas vencidas/)).toBeInTheDocument()
     expect(within(tabla).getAllByText('Sin llamadas útiles')).toHaveLength(2)
     expect(within(tabla).getByRole('rowheader', { name: /ANA PÉREZ/ })).toHaveAttribute('scope', 'row')
-    expect(screen.getByText('Selecciona un analista de la tabla para consultar su día.')).toBeVisible()
+    // Selección automática: el panel abre con BRUNO (270 vencidas) SIN mover el foco
+    // y sin montar el registro (se consulta al visitarlo).
+    expect(screen.getByRole('region', { name: 'Detalle de BRUNO' })).toBeVisible()
+    expect(screen.getByRole('button', { name: 'Seleccionar a BRUNO' })).toHaveAttribute('aria-current', 'true')
+    expect(document.body).toHaveFocus()
     expect(dobles.registro).not.toHaveBeenCalled()
   })
   it('los filtros no cambian indicadores y la ordenación comunica su dirección', () => {
@@ -291,3 +298,59 @@ describe('Pedido de registro desde avisos', () => {
     expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
   })
 })
+
+describe('Selección automática del panel (plan v2 tras la revisión de Codex, 27/09/2026)', () => {
+  let alMedir: (() => void) | null = null
+  beforeEach(() => {
+    alMedir = null
+    // jsdom no mide: se simula el observador para poder estrechar la pantalla.
+    vi.stubGlobal('ResizeObserver', class { constructor(cb: () => void) { alMedir = cb } observe() {} disconnect() {} })
+  })
+  afterEach(() => { vi.unstubAllGlobals() })
+
+  it('si nadie necesita atención, no elige a nadie y el panel lo dice', () => {
+    dobles.consulta = { ...dobles.consulta, dia: diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO' })]) }
+    render(<GestionDiariaSupervisor />)
+    expect(screen.getByText('Nadie necesita atención ahora. Elige un analista para ver su día.')).toBeVisible()
+    expect(screen.queryByRole('button', { name: /Ir al detalle/ })).not.toBeInTheDocument()
+  })
+  it('cerrar el panel apaga la apertura automática aunque llegue otra foto', () => {
+    const vista = render(<GestionDiariaSupervisor />)
+    expect(screen.getByRole('region', { name: 'Detalle de BRUNO' })).toBeVisible()
+    fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle' }))
+    dobles.consulta = { ...dobles.consulta, dia: { ...dobles.consulta.dia!, generado_en: '2026-09-21T15:01:00Z' } }
+    vista.rerender(<GestionDiariaSupervisor />)
+    expect(screen.queryByRole('region', { name: 'Detalle de BRUNO' })).not.toBeInTheDocument()
+    expect(screen.getByRole('region', { name: 'Detalle del analista' })).toBeVisible()
+  })
+  it('una automática que se queda sin sitio se CIERRA sin abrir ninguna ventana', () => {
+    render(<GestionDiariaSupervisor />)
+    expect(screen.getByRole('region', { name: 'Detalle de BRUNO' })).toBeVisible()
+    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1000)
+    act(() => { alMedir?.() })
+    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
+    expect(screen.queryByRole('region', { name: 'Detalle de BRUNO' })).not.toBeInTheDocument()
+  })
+  it('con la pantalla estrecha desde el inicio no elige a nadie ni abre ventana', () => {
+    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1000)
+    render(<GestionDiariaSupervisor />)
+    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
+    expect(screen.getByRole('button', { name: 'Seleccionar a BRUNO' })).not.toHaveAttribute('aria-current')
+  })
+  it('una selección del USUARIO sí sigue la mecánica de siempre: con poco sitio se abre encima', () => {
+    render(<GestionDiariaSupervisor />)
+    seleccionar()
+    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1000)
+    act(() => { alMedir?.() })
+    expect(screen.getByRole('dialog', { name: 'Detalle de ANA PÉREZ' })).toBeVisible()
+  })
+  it('en otra fecha no se abre sola', () => {
+    render(<GestionDiariaSupervisor />)
+    fireEvent.change(screen.getByLabelText('Fecha de gestión'), { target: { value: '2026-09-10' } })
+    expect(screen.queryByRole('region', { name: 'Detalle de BRUNO' })).not.toBeInTheDocument()
+  })
+  it('el título del panel se oye «Detalle de …» con su espacio', () => {
+    render(<GestionDiariaSupervisor />)
+    expect(screen.getByRole('heading', { level: 3, name: 'Detalle de BRUNO' })).toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
index e7792af8..de455878 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
@@ -1,5 +1,5 @@
 import { useEffect, useId, useLayoutEffect, useRef, useState, type JSX, type ReactNode } from 'react'
-import { Info, ListFilter, RefreshCw, Search, Users, X } from 'lucide-react'
+import { Check, ClipboardList, Info, RefreshCw, Search, Users, X } from 'lucide-react'
 import { useAlertasCRM } from '@/lib/alertas-context'
 import { useAuth } from '@/lib/auth-context'
 import { useAhora } from '@/lib/ahora'
@@ -16,14 +16,30 @@ import { Button } from '@/components/ui/button'
 import { Input } from '@/components/ui/input'
 import { Select } from '@/components/ui/select'
 import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
+import { FranjaCifras } from '@/components/gestion-diaria/franja-cifras'
 import { FranjaCortesSupervisor } from '@/components/gestion-diaria/franja-cortes-supervisor'
 import { AvisosEquipo } from '@/components/gestion-diaria/avisos-equipo'
 import { EstadoCortesEquipo } from '@/components/gestion-diaria/estado-cortes-equipo'
 import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
+import { cn } from '@/lib/utils'
+// supervisor.css sigue siendo de gerencia y de los diálogos de cortes; la
+// pantalla del supervisor tiene sus estilos propios (mi-equipo.css, 27/09).
 import './supervisor.css'
+import './mi-equipo.css'
 
 const FECHA_JORNADA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })
-const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false }
+// «Atención» por gravedad (revisión Codex, 27/09): lo vencido primero.
+const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false, gravedad: true }
+/**
+ * Ancho mínimo de la pantalla para tener tabla y panel LADO A LADO: columnas
+ * fijas de la tabla (68 + 132 + 56 + 72 + 156 = 484) + nombre con iniciales
+ * (≥ 200) + canal de scroll (16) + separación (16) + panel (360) = 1076. A
+ * 1440 con el menú abierto la pantalla mide ~1150: cabe. Por debajo, el detalle
+ * se abre encima como siempre. Solo del supervisor: gerencia conserva el suyo.
+ */
+const ANCHO_EN_LINEA = 1076
+const CONTROL = 'h-9 text-[13px] pointer-coarse:h-11'
+const BOTON_CABECERA = 'inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50 aria-disabled:hover:bg-card pointer-coarse:h-11'
 
 export function GestionDiariaSupervisor({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode } = {}): JSX.Element {
   const { yo } = useAuth()
@@ -58,6 +74,16 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
   const origen = useRef<HTMLElement | null>(null)
   const focoEnPanel = useRef(false)
   const apertura = useRef(0)
+  // Un cierre voluntario, una salida de ámbito o una apertura pedida por un aviso
+  // apagan la selección automática en esta visita a la pantalla.
+  const autoInhibida = useRef(false)
+  const ahora = useAhora()
+  // «Actualizando…» solo cuando lo pidió el supervisor: el refresco de cada minuto
+  // no cambia el botón enfocado ni lo anuncia (revisión a11y, 27/09).
+  const [manual, setManual] = useState(false)
+  const [reintentando, setReintentando] = useState(false)
+  const tituloError = useRef<HTMLHeadingElement>(null)
+  const focoEnEquipo = useRef(false)
   const dia = consulta.error ? null : consulta.dia
   const equipo = dia ? presentarEquipo(dia) : []
   const filas = filtrarOrdenarEquipo(equipo, filtros)
@@ -65,13 +91,14 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
   const atencion = equipo.filter((f) => f.requiere_atencion).length
   const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
   const fueraDeAmbito = seleccion !== null && (sinPermiso || (dia !== null && seleccion.analista !== null && !fila))
+  const automatica = seleccion?.origen === 'automatica'
   useLayoutEffect(() => {
     const nodo = pantalla.current
     if (!nodo || typeof ResizeObserver === 'undefined') return
     const medir = () => {
       const tabla = nodo.querySelector('.gd-tabla-scroll')
       const scrollbar = tabla instanceof HTMLElement ? tabla.offsetWidth - tabla.clientWidth : 0
-      setEstrecho(nodo.clientWidth < 1236 + Math.max(0, scrollbar - 16))
+      setEstrecho(nodo.clientWidth < ANCHO_EN_LINEA + Math.max(0, scrollbar - 16))
     }
     const observador = new ResizeObserver(medir)
     observador.observe(nodo)
@@ -81,6 +108,7 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
   useEffect(() => {
     const recordarFoco = (e: FocusEvent) => {
       focoEnPanel.current = e.target instanceof Node && Boolean(document.getElementById(panelId)?.contains(e.target))
+      focoEnEquipo.current = e.target instanceof Element && Boolean(e.target.closest('.me-equipo'))
     }
     document.addEventListener('focusin', recordarFoco)
     return () => document.removeEventListener('focusin', recordarFoco)
@@ -88,6 +116,7 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
   useLayoutEffect(() => {
     if (!fueraDeAmbito) return
     const focoDentro = focoEnPanel.current
+    autoInhibida.current = true
     setSeleccion(null)
     setAmpliado(false)
     setAnuncio('Se cerró el detalle porque su ámbito ya no está autorizado. Revisa el equipo antes de abrir otro.')
@@ -113,8 +142,9 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
     if (!dia) return
     if (pedido.actor === actor && pedido.dia === hoy && esHoy && dia.equipo.some((f) => f.analista_id === pedido.analista)) {
       origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
+      autoInhibida.current = true
       setSeleccion({ analista: pedido.analista, nombre: dia.equipo.find((f) => f.analista_id === pedido.analista)!.nombre_completo,
-        pestana: 'llamadas', apertura: ++apertura.current, enfocar: true })
+        pestana: 'llamadas', apertura: ++apertura.current, enfocar: true, origen: 'aviso' })
       setDevolverFocoAuxiliar(false)
       setAuxiliar(null)
       setAnuncio('Abierto el registro de llamadas solicitado.')
@@ -135,99 +165,198 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
     const persona = dia?.equipo.find((f) => f.analista_id === id)
     if (!persona || sinPermiso) return
     origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
-    setSeleccion({ analista: id, nombre: persona.nombre_completo, pestana: 'llamadas', apertura: ++apertura.current, enfocar: true })
+    autoInhibida.current = true
+    setSeleccion({ analista: id, nombre: persona.nombre_completo, pestana: 'llamadas', apertura: ++apertura.current, enfocar: true, origen: 'aviso' })
     setDevolverFocoAuxiliar(false); setAuxiliar(null)
     setAnuncio('Abierto el registro de llamadas solicitado.')
   }
   const seleccionar = (persona: FilaEquipoPresentada) => {
     origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
-    if (seleccion?.analista === persona.analista_id) return
-    setSeleccion({ analista: persona.analista_id, nombre: persona.nombre_completo, pestana: 'todo', apertura: ++apertura.current, enfocar: false })
+    // Pulsar a quien ya abrió la selección automática la hace SUYA.
+    if (seleccion?.analista === persona.analista_id) {
+      if (automatica) setSeleccion((s) => s && { ...s, origen: 'usuario' })
+      return
+    }
+    setSeleccion({ analista: persona.analista_id, nombre: persona.nombre_completo, pestana: 'todo', apertura: ++apertura.current, enfocar: false, origen: 'usuario' })
     setAnuncio(`Seleccionado ${persona.nombre_completo}. Detalle disponible.`)
   }
   const cerrar = () => {
+    autoInhibida.current = true
+    const analista = seleccion?.analista ?? null
     setSeleccion(null); setAmpliado(false)
     requestAnimationFrame(() => {
-      if (origen.current?.isConnected && origen.current.getClientRects().length) origen.current.focus({ preventScroll: true })
-      else tituloEquipo.current?.focus({ preventScroll: true })
+      // Una selección automática no tiene origen: el foco vuelve a SU fila, no al título.
+      const fila = analista === null ? null : pantalla.current?.querySelector<HTMLElement>(`[data-analista="${CSS.escape(analista)}"] button[aria-controls]`)
+      const destino = origen.current?.isConnected && origen.current.getClientRects().length ? origen.current : fila ?? tituloEquipo.current
+      destino?.focus({ preventScroll: true })
+      destino?.scrollIntoView?.({ block: 'nearest' })
     })
   }
-  const ordenar = (orden: OrdenEquipo) => setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : orden === 'nombre' }))
-  const modal = seleccion !== null && !fueraDeAmbito && (estrecho || ampliado)
+  const ordenar = (orden: OrdenEquipo) => {
+    const titulo = { nombre: 'nombre', llamadas: 'llamadas', contacto: 'contacto', pendientes: 'pendientes', citas: 'citas', vencidas: 'vencidas', atencion: 'atención' }[orden]
+    const ascendente = filtros.orden === orden ? !filtros.ascendente : orden === 'nombre'
+    setFiltros((f) => ({ ...f, orden, ascendente }))
+    setAnuncio(`Ordenado por ${titulo}, ${ascendente ? 'ascendente' : 'descendente'}.`)
+  }
+  // Selección AUTOMÁTICA (plan v2 tras Codex, 27/09): quien más atención
+  // necesita, SOLO con el panel en línea, hoy, con una foto válida de la fecha
+  // pedida y sin un aviso esperando; nunca abre una ventana ni mueve el foco.
+  const candidata = filas.find((f) => f.requiere_atencion)
+  useEffect(() => {
+    if (autoInhibida.current || seleccion !== null || !esHoy || estrecho || !dia || dia.dia !== fecha
+      || consulta.cargando || consulta.error || sinPermiso || avisos?.registroPedido || !candidata) return
+    origen.current = null
+    setSeleccion({ analista: candidata.analista_id, nombre: candidata.nombre_completo, pestana: 'todo', apertura: ++apertura.current, enfocar: false, origen: 'automatica' })
+  }, [seleccion, esHoy, estrecho, dia, fecha, consulta.cargando, consulta.error, sinPermiso, avisos?.registroPedido, candidata])
+  // Una automática que se queda sin sitio al lado se CIERRA sin abrir ventana;
+  // si el supervisor ya la estaba leyendo (foco dentro), pasa a ser suya.
+  useLayoutEffect(() => {
+    if (!estrecho || !automatica) return
+    if (focoEnPanel.current) setSeleccion((s) => s && { ...s, origen: 'usuario' })
+    else setSeleccion(null)
+  }, [estrecho, automatica])
+  const modal = seleccion !== null && !fueraDeAmbito && !automatica && (estrecho || ampliado)
+  const vacioPanel = dia && esHoy && dia.equipo.length > 0 && !equipo.some((f) => f.requiere_atencion)
+    ? 'Nadie necesita atención ahora. Elige un analista para ver su día.' : undefined
+  const abrirRegistroEquipo = () => {
+    if (!dia || sinPermiso) return
+    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
+    setSeleccion({ analista: null, nombre: null, pestana: 'todo', apertura: ++apertura.current, enfocar: true, origen: 'usuario' })
+  }
+  const actualizar = () => {
+    if (consulta.enVuelo || alertas.cargando) return
+    setManual(true)
+    void consulta.recargar(); alertas.reintentar(); setActualizacion((n) => n + 1)
+  }
+  const enVuelo = consulta.enVuelo || alertas.cargando
+  const actualizando = manual && enVuelo
+  useEffect(() => { if (!enVuelo) setManual(false) }, [enVuelo])
+  // Reintento: si sale bien, el bloque de error desaparece con el foco dentro →
+  // el foco va al título; si vuelve a fallar, se dice (revisión a11y, 27/09).
+  useEffect(() => {
+    if (!reintentando || consulta.enVuelo) return
+    setReintentando(false)
+    if (consulta.error) setAnuncio('El reintento no pudo consultar el equipo.')
+    else requestAnimationFrame(() => tituloEquipo.current?.focus({ preventScroll: true }))
+  }, [reintentando, consulta.enVuelo, consulta.error])
+  // Si un refresco falla con el foco en la tabla o la barra, la alerta los reemplaza:
+  // el foco pasa a su título en vez de caer al documento.
+  useLayoutEffect(() => {
+    // Solo si el foco se PERDIÓ (cayó al documento); si sigue en «Reintentar», se queda.
+    const activo = document.activeElement
+    if (!consulta.error || !focoEnEquipo.current || (activo && activo !== document.body)) return
+    focoEnEquipo.current = false
+    tituloError.current?.focus({ preventScroll: true })
+  }, [consulta.error])
+  const hora = dia ? horaLimaDe(dia.generado_en) : null
   return (
-    <section ref={pantalla} aria-label={esHoy ? 'Mi equipo hoy' : 'Mi equipo por fecha'} className="gd-supervisor" data-estrecho={estrecho}>
-      <header className="gd-cabecera">
-        <h2 ref={tituloEquipo} tabIndex={-1}>{esHoy ? 'Mi equipo hoy' : 'Mi equipo'}</h2>
-        <div className="gd-selector-fecha">
+    <section ref={pantalla} aria-label={esHoy ? 'Mi equipo hoy' : 'Mi equipo por fecha'} data-estrecho={estrecho}
+      className="me-pantalla mx-auto flex w-full max-w-[1440px] flex-col gap-4 text-foreground">
+      <header className="flex shrink-0 flex-wrap items-start justify-between gap-x-6 gap-y-3">
+        <div className="min-w-0">
+          <h2 ref={tituloEquipo} tabIndex={-1} className="rounded-md text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">{esHoy ? 'Mi equipo hoy' : 'Mi equipo'}</h2>
+          <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">Actividad registrada, pendientes y analistas que necesitan atención.</p>
+        </div>
+        <div className="flex min-w-0 flex-wrap items-center gap-2">
+          {/* El selector ya dice la fecha: al lado solo va la hora de la foto. */}
           <label><span className="sr-only">Fecha de gestión</span>
-            <Input ref={entradaFecha} type="date" defaultValue={hoy} min={primeraFecha} max={hoy} className="min-h-11 text-base"
+            <Input ref={entradaFecha} type="date" defaultValue={hoy} min={primeraFecha} max={hoy} className={cn(CONTROL, 'w-[150px] min-h-0')}
               onChange={(e) => {
                 // El campo nativo conserva la escritura por segmentos. Volver a
                 // asignar value en cada tecla reinicia el año en Chromium.
                 if (e.currentTarget.validity.valid) cambiarFecha(e.currentTarget.value)
               }} onBlur={(e) => { e.currentTarget.value = fecha }} />
           </label>
-          <Button variant="outline" className="min-h-11 text-base" disabled={esHoy} onClick={() => cambiarFecha(hoy)}>Hoy</Button>
-          <span className="gd-fecha">Lima{demo ? ' · Demo' : ''}</span>
-        </div>
-        <div className="gd-acciones-cabecera">
+          <button type="button" className={BOTON_CABECERA} aria-disabled={esHoy} onClick={() => { if (!esHoy) cambiarFecha(hoy) }}>Hoy</button>
           {accesoSeguimiento}
-          <Button variant="ghost" className="min-h-11 text-base" disabled={!dia || sinPermiso} onClick={() => {
-            origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
-            setSeleccion({ analista: null, nombre: null, pestana: 'todo', apertura: ++apertura.current, enfocar: true })
-          }}>Registro del equipo</Button>
-          <Button variant="outline" className="min-h-11 text-base" disabled={consulta.enVuelo || alertas.cargando} onClick={() => { void consulta.recargar(); alertas.reintentar(); setActualizacion((n) => n + 1) }}>
-            <RefreshCw className="size-4" aria-hidden />{consulta.enVuelo || alertas.cargando ? 'Actualizando…' : 'Actualizar'}
-          </Button>
-          <Button variant="ghost" size="icon" className="size-11" aria-label="Información de esta vista" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('info') }}><Info aria-hidden /></Button>
+          {hora && <p className="whitespace-nowrap pl-1 text-xs tabular-nums text-[var(--muted-foreground-strong)]">Actualizado {hora}</p>}
+          <button type="button" className={BOTON_CABECERA} aria-disabled={actualizando} aria-busy={actualizando} onClick={actualizar}>
+            <RefreshCw className={cn('size-4', actualizando && 'motion-safe:animate-spin')} aria-hidden />{actualizando ? 'Actualizando…' : 'Actualizar'}
+          </button>
+          <button type="button" className={cn(BOTON_CABECERA, 'w-9 justify-center px-0 pointer-coarse:w-11')} aria-label="Información de esta vista" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('info') }}>
+            <Info aria-hidden className="size-4" />
+          </button>
         </div>
       </header>
-      <div role="group" aria-label="Resumen del equipo" className="gd-indicadores">
-        {dia ? <dl>{[
-          ['Analistas', dia.resumen.analistas], ['Con registro', dia.resumen.con_actividad], ['Sin registro', dia.resumen.sin_actividad],
-          ['Con pendientes', dia.resumen.con_pendientes], ['Necesitan atención', atencion],
-        ].map(([etiqueta, valor]) => <div key={etiqueta}><dt>{etiqueta}</dt><dd>{valor}</dd></div>)}</dl>
-          : <p>{consulta.error ? 'Resumen no disponible' : 'Consultando indicadores…'}</p>}
-      </div>
-      <div className="gd-espacio">
-        <div className="gd-equipo">
-          {consulta.error ? <div role="alert" className="gd-estado">
-            <h3 className="font-semibold">{sinPermiso ? 'Ya no tienes autorización para ver este equipo' : 'No pudimos consultar la actividad y los pendientes del equipo'}</h3>
-            <p>{sinPermiso ? 'Revisa tu acceso con gerencia. No se muestran los datos anteriores.' : 'Los datos no están disponibles; esto no significa que el equipo no tenga actividad o pendientes.'}</p>
-            {!sinPermiso && <Button className="min-h-11 text-base" disabled={consulta.enVuelo} onClick={() => { void consulta.recargar() }}>Reintentar</Button>}
-          </div> : consulta.cargando || !dia ? <p role="status" aria-busy="true" className="gd-estado">Consultando el equipo completo…</p>
-            : dia.equipo.length === 0 ? <PanelVacio icono={Users} tamano="grande" titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
-              : <>
-                <div className="gd-filtros">
-                  <label className="gd-busqueda"><span className="sr-only">Buscar analista</span><Search aria-hidden />
-                    <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista" className="min-h-11 pl-9 text-base" /></label>
-                  <Select aria-label="Estado de actividad" value={filtros.estado} onChange={(e) => setFiltros((f) => ({ ...f, estado: e.target.value as EstadoEquipo }))} className="min-h-11 text-base">
-                    <option value="todos">Todos</option><option value="con_registro">Con registro</option><option value="sin_registro">Sin registro</option><option value="con_pendientes">Con pendientes</option>
-                  </Select>
-                  <Button variant={filtros.soloProblemas ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={filtros.soloProblemas} onClick={() => setFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}><ListFilter aria-hidden />Con atención ({atencion})</Button>
-                  <p aria-live="polite" className="gd-conteo">{filas.length} de {dia.resumen.analistas}</p>
-                </div>
-                <TablaEquipoDiaria filas={filas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null} seleccionar={seleccionar}
-                  panelId={panelId} minimo={dia.umbrales.minimo_llamadas_utiles} irAlDetalle={() => tituloPanel.current?.focus({ preventScroll: true })} />
-              </>}
+
+      {dia ? <FranjaCifras etiqueta="Resumen del equipo" disposicion="en-linea" className="shrink-0" cifras={[
+        { etiqueta: 'Analistas', valor: String(dia.resumen.analistas) },
+        { etiqueta: 'Con registro', valor: String(dia.resumen.con_actividad) },
+        { etiqueta: 'Sin registro', valor: String(dia.resumen.sin_actividad) },
+        { etiqueta: 'Con pendientes', valor: String(dia.resumen.con_pendientes) },
+        // Ámbar y no rojo: mezcla vencidas con cortes y tiempo sin llamar (Codex, 27/09).
+        { etiqueta: 'Necesitan atención', valor: String(atencion), tono: atencion > 0 ? 'aviso' : 'normal' },
+      ]} />
+        : <div role="group" aria-label="Resumen del equipo" className="shrink-0 rounded-2xl border border-border bg-card px-5 py-4 text-[13px] text-[var(--muted-foreground-strong)]">
+          <p>{consulta.error ? 'Resumen no disponible' : 'Consultando indicadores…'}</p>
+        </div>}
+
+      <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_360px]')}>
+        <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
+          {consulta.error ? <div role="alert" className="flex flex-col items-start gap-3 p-6 text-[13.5px]">
+            <h3 ref={tituloError} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">{sinPermiso ? 'Ya no tienes autorización para ver este equipo' : 'No pudimos consultar la actividad y los pendientes del equipo'}</h3>
+            <p className="text-[var(--muted-foreground-strong)]">{sinPermiso ? 'Revisa tu acceso con gerencia. No se muestran los datos anteriores.' : 'Los datos no están disponibles; esto no significa que el equipo no tenga actividad o pendientes.'}</p>
+            {!sinPermiso && <Button className={cn(CONTROL, 'aria-disabled:cursor-default aria-disabled:opacity-60')} aria-disabled={consulta.enVuelo}
+              onClick={() => { if (consulta.enVuelo) return; setReintentando(true); void consulta.recargar() }}>{reintentando ? 'Reintentando…' : 'Reintentar'}</Button>}
+          </div> : consulta.cargando || !dia ? <p role="status" className="p-6 text-[13.5px] text-[var(--muted-foreground-strong)]">Consultando el equipo completo…</p>
+            : <>
+              {/* La barra existe con cualquier foto válida: «Registro del equipo»
+                  sigue a mano aunque no haya analistas (Codex, 27/09). */}
+              <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
+                {dia.equipo.length > 0 && <>
+                  <label className="relative w-[220px] max-w-full"><span className="sr-only">Buscar analista</span>
+                    <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
+                    <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista…" className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
+                  </label>
+                  <div className="w-[150px]">
+                    <Select aria-label="Estado de actividad" value={filtros.estado} onChange={(e) => setFiltros((f) => ({ ...f, estado: e.target.value as EstadoEquipo }))} className={cn(CONTROL, 'min-h-0')}>
+                      <option value="todos">Todos los estados</option><option value="con_registro">Con registro</option><option value="sin_registro">Sin registro</option><option value="con_pendientes">Con pendientes</option>
+                    </Select>
+                  </div>
+                  <button type="button" aria-pressed={filtros.soloProblemas} onClick={() => setFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}
+                    className={cn('inline-flex h-9 cursor-pointer items-center gap-2 rounded-full border px-3.5 text-[13px] font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11',
+                      filtros.soloProblemas ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-foreground hover:bg-muted')}>
+                    {filtros.soloProblemas && <Check aria-hidden className="size-3.5" />}Con atención
+                    <span className={cn('grid min-w-5 place-items-center rounded-full px-1.5 text-[11px] font-bold tabular-nums',
+                      atencion > 0 ? 'bg-[var(--warning-text)] text-white' : 'bg-muted text-[var(--muted-foreground-strong)]')}>{atencion}</span>
+                  </button>
+                </>}
+                <button type="button" onClick={abrirRegistroEquipo} aria-disabled={sinPermiso}
+                  className="ml-auto inline-flex h-9 cursor-pointer items-center gap-1.5 rounded-md px-1 text-[13px] font-semibold text-[var(--accent-press)] hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50 pointer-coarse:h-11">
+                  <ClipboardList aria-hidden className="size-4" />Registro del equipo
+                </button>
+              </div>
+              {dia.equipo.length === 0
+                ? <PanelVacio icono={Users} titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
+                : <>
+                  <TablaEquipoDiaria contexto="supervisor" filas={filas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null} seleccionar={seleccionar}
+                    panelId={panelId} minimo={dia.umbrales.minimo_llamadas_utiles} irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />
+                  <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
+                    <p><span role="status">{filas.length} de {dia.resumen.analistas} analistas</span> · Actualizado {hora}</p>
+                    <p>La actividad registrada no acredita presencia.</p>
+                  </div>
+                </>}
+            </>}
         </div>
-        <PanelSupervisorAdaptable modal={modal} cerrar={cerrar} tituloRef={tituloPanel}>
+        <PanelSupervisorAdaptable modal={modal} cerrar={cerrar} tituloRef={tituloPanel} claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
           <PanelAnalistaSupervisor key={fecha} id={panelId} seleccion={fueraDeAmbito ? null : seleccion} fila={fila} dia={fecha} minimo={dia?.umbrales.minimo_llamadas_utiles} tituloRef={tituloPanel}
-            ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => setAmpliado((v) => !v)} cerrar={cerrar} oculta={Boolean(dia && seleccion?.analista && !filas.some((f) => f.analista_id === seleccion.analista))}
-            limpiar={() => setFiltros(FILTROS_INICIALES)} actualizacion={actualizacion} revalidar={() => { void consulta.recargar() }} />
+            ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => { setAmpliado((v) => !v); if (automatica) setSeleccion((s) => s && { ...s, origen: 'usuario' }) }} cerrar={cerrar}
+            oculta={Boolean(dia && seleccion?.analista && !filas.some((f) => f.analista_id === seleccion.analista))}
+            limpiar={() => setFiltros(FILTROS_INICIALES)} actualizacion={actualizacion} revalidar={() => { void consulta.recargar() }}
+            esHoy={esHoy} ahora={ahora} vacio={vacioPanel} silencioso={automatica} />
         </PanelSupervisorAdaptable>
       </div>
       {esHoy ? <FranjaCortesSupervisor consulta={consulta} abrir={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }} />
-        : <section className="gd-cortes" aria-label="Consulta de otra fecha">
-          <Button variant="ghost" className="min-h-11 shrink-0 text-base" aria-haspopup="dialog" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }}>Cortes del día</Button>
-          <p className="gd-cortes-resumen">Actividad del día elegido. El equipo y los pendientes reflejan su estado actual.</p>
+        : <section className="flex shrink-0 flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl border border-border bg-card px-3 py-1.5 text-[13px]" aria-label="Consulta de otra fecha">
+          <button type="button" className={BOTON_CABECERA} aria-haspopup="dialog" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }}>Cortes del día</button>
+          <p className="min-w-0 flex-1 text-[var(--muted-foreground-strong)]">Actividad del día elegido. El equipo y los pendientes reflejan su estado actual.</p>
         </section>}
       <p className="sr-only" role="status">{anuncio}</p>
       <Dialog focoAlCerrar={devolverFocoAuxiliar ? undefined : tituloPanel} open={auxiliar !== null} onClose={() => setAuxiliar(null)} className={auxiliar === 'info' ? 'gd-dialogo-info' : 'gd-dialogo-avisos'}>
         <DialogHeader className="flex-row items-center justify-between"><DialogTitle className="text-base">{auxiliar === 'info' ? 'Información de esta vista' : esHoy ? 'Cortes de llamadas y otros avisos' : 'Cortes del día seleccionado'}</DialogTitle>
           <Button variant="ghost" size="icon" className="size-11 shrink-0" aria-label={auxiliar === 'info' ? 'Cerrar información' : 'Cerrar avisos'} onClick={() => setAuxiliar(null)}><X aria-hidden /></Button></DialogHeader>
         <DialogBody className="space-y-3 text-base">{auxiliar === 'info' ? <>
-          <p>{fecha} · Hora de Lima. {dia ? `Datos consultados a las ${horaLimaDe(dia.generado_en)}.` : 'Sin datos confirmados.'} Actualización cada minuto.</p>
+          <p>{fecha} · Hora de Lima{demo ? ' · Modo demo' : ''}. {dia ? `Datos consultados a las ${horaLimaDe(dia.generado_en)}.` : 'Sin datos confirmados.'} Actualización cada minuto.</p>
           <p>Puedes consultar desde hoy hasta 365 días atrás. Las llamadas y el registro corresponden a la fecha elegida; el equipo y los pendientes reflejan su estado actual.</p>
           <p>Los indicadores cuentan personas del equipo completo, incluso cuando filtras la tabla.</p>
           <p>La tasa usa llamadas útiles; número errado y otra persona quedan fuera. Se califica desde {dia?.umbrales.minimo_llamadas_utiles ?? 'el mínimo vigente de'} llamadas útiles.</p>

```

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
