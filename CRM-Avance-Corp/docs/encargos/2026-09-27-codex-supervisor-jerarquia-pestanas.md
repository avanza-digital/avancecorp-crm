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

# Encargo: REFUTAR el ajuste de «Mi equipo hoy» (jerarquía, ficha, Registro y Pendientes) — LEVEL 2

Rutas relativas a `CRM-Avance-Corp/app/`. Stack: React 19, Vite 8, Tailwind 4, vitest, Playwright.
La revisión anterior de esta pantalla (misma rama) fue CHANGES_REQUESTED y se aplicó entera.
Esto es el AJUSTE posterior, pedido por el dueño (Miguel) al verlo en local. Va a producción ya.

## Pedidos del dueño (decisiones, NO son hallazgos)

1. «ese dash tiene mucha jerarquía… la ficha y el componente donde ve a todos sus analistas es lo más
   importante»: el tablero de 5 cifras deja de ser un bloque; sus números pasan a la barra de la tabla
   como filtros (regla vigente: «todo número se abre» — cada cifra lleva a su lista).
2. «dale más protagonismo a detalles del analista»: la ficha crece (360–440 px), borde azul, sombra,
   cabecera teñida, avatar relleno, nombre 22 px, cifras 28 px.
3. «registro y pendientes del detalle tienen demasiado texto y no se entiende; hazlo igual que resumen».
   Se aceptó quitar de la ficha: la descripción del registro, el filtro de etapa y su «Actualizar» propio
   (la pantalla entera ya se actualiza cada minuto y desde su cabecera). Gerencia NO cambia.

## Qué se implementó (el diff manda)

- `screens/gestion-diaria/supervisor.tsx`: sin `FranjaCifras`; grupo `role=group` «Resumen del equipo» con 5
  botones `aria-pressed` (Todos · Con registro · Sin registro · Con pendientes · Necesitan atención), uno a
  la vez; «Necesitan atención» = `soloProblemas`, exclusivo con los estados. Los números salen de
  `dia.resumen` (el servidor usa las MISMAS reglas que el filtro: `resumenEquipo`). «Registro del equipo» pasa
  a la cabecera. Buscador 160–220 px. Grid `minmax(0,1fr)_clamp(360px,32%,440px)`; umbral en línea sigue
  1100 (calculado con el mínimo 360).
- `components/gestion-diaria/registro-actividad.tsx` (COMPARTIDO con analista y gerencia): prop nueva
  `encabezadoExterno` solo para el modo `compacto`: sin título interno, foco de respaldo al título externo;
  en compacto con `mostrarAnalista`, fila con autor y selector «Analista». Sin la prop, nada cambia.
- `components/gestion-diaria/panel-analista-supervisor.tsx`: ficha elevada; pestaña Registro con h4
  «Actividad de hoy / del <día>» + `RegistroActividad compacto encabezadoExterno`.
- `components/gestion-diaria/pendientes-supervisor.tsx` (solo supervisor): reescrito. Dos cuadros-botón
  (Todas N / Vencidas N) que filtran; señales de leads solo con número > 0; filas con «Vencida» si
  `vence_en < pendientes_al` (instantes con microsegundos); el título no repite el lead
  («Acción — LEAD»); «Ver más», «Reintentar», «Actualizar tareas» (solo con la lista congelada) con
  recuperación de foco al título si desaparecen con el foco dentro.
- Se revirtió la variante `en-linea`/`aviso` de `franja-cifras.tsx` (ya sin uso).

## Verificación del PRIMARY (no la repitas; juzga la evidencia)

- `npm run check` PASS (lint + typecheck + 4629 pruebas + build + bundle + duplicados).
- E2E Docker local de Gestión Diaria: 61/64 en la corrida anterior a los dos arreglos finales (filtro
  «Analista» del registro del equipo y nombre «Actualizar tareas»); el 3.º fallo (H5 «consultas iguales»)
  también falla 3/3 en el commit publicado SIN estos cambios (consultas de la pantalla de inicio al entrar).

## Preguntas concretas

1. ¿Algún camino deja un número que NO coincide con la lista que abre (píldoras y cuadros)?
2. ¿La prop `encabezadoExterno` puede alterar al analista o a gerencia (que no la pasan)?
3. ¿Foco y anuncios: algún control que desaparece con el foco dentro sin recuperación, o nombres
   accesibles ambiguos entre la cabecera, la tabla y la ficha?
4. ¿«Vencida» puede marcar mal una tarea (zona, microsegundos, página sin `pendientes_al`)?
5. ¿El recorte del título «Acción — LEAD» puede ocultar información que no sea el nombre del lead?

## DIFF (git diff 360beeb8 38ffd3d9 -- CRM-Avance-Corp/app)

```diff
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts
index acfe2740..0af694c1 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-equipo.spec.ts
@@ -69,7 +69,7 @@ test('Ruta real con store vacío: cero actividad, 270 pendientes, error y revoca
   const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
   await expect(vista.getByText('ANA PÉREZ', { exact: true })).toBeVisible()
   await expect(vista.getByRole('cell', { name: '270', exact: true }).first()).toBeVisible()
-  await vista.getByRole('button', { name: /Con atención/ }).click()
+  await vista.getByRole('button', { name: /^Necesitan atención/ }).click()
   await expect(vista.getByText('ANA PÉREZ', { exact: true })).toHaveCount(0)
   await expect(vista.getByText('BRUNO', { exact: true })).toBeVisible()
   await page.screenshot({ path: info.outputPath('equipo-ruta-real.png'), fullPage: true })
@@ -133,7 +133,7 @@ test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginaci
   await abrirRegistro.focus()
   await page.keyboard.press('Enter')
   const registro = page.getByRole('region', { name: 'Registro seleccionado', exact: true })
-  await expect(registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true })).toBeFocused()
+  await expect(registro.getByRole('heading', { name: 'Actividad de hoy', exact: true })).toBeFocused()
   await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
   await expect(registro.getByRole('combobox', { name: 'Analista', exact: true })).toHaveCount(0)
   await registro.getByRole('tab', { name: 'Todo', exact: true }).click()
@@ -162,17 +162,18 @@ test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginaci
   await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toHaveCount(0)
   await registro.getByRole('button', { name: 'Ver más' }).click()
   await expect(registro.getByRole('listitem')).toHaveCount(26)
-  await registro.getByRole('combobox', { name: 'Etapa actual del lead' }).focus()
+  // Registro compacto en la ficha (27/09): el filtro que conserva el foco es la pastilla elegida.
+  await registro.getByRole('tab', { selected: true }).focus()
   await page.setViewportSize({ width: 1512, height: 805 })
   await expect(page.getByRole('dialog', { name: 'Detalle de Analista Real Uno' })).toHaveCount(0)
-  await expect(registro.getByRole('combobox', { name: 'Etapa actual del lead' })).toBeFocused()
+  await expect(registro.getByRole('tab', { selected: true })).toBeFocused()
   await expect(registro.getByRole('listitem')).toHaveCount(26)
   await page.setViewportSize({ width: 390, height: 844 })
-  await registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true }).scrollIntoViewIfNeeded()
+  await registro.getByRole('heading', { name: 'Actividad de hoy', exact: true }).scrollIntoViewIfNeeded()
   await page.screenshot({ path: info.outputPath('registro-detalle.png') })
   await page.setViewportSize({ width: 390, height: 844 })
   await expect(registro.getByRole('listitem')).toHaveCount(26)
-  await registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true }).scrollIntoViewIfNeeded()
+  await registro.getByRole('heading', { name: 'Actividad de hoy', exact: true }).scrollIntoViewIfNeeded()
   expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
   await page.screenshot({ path: info.outputPath('registro-detalle-movil.png') })
   const pestañas = registro.getByRole('tablist', { name: 'Tipo de actividad' })
@@ -192,7 +193,8 @@ test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginaci
       && Number.parseFloat(getComputedStyle(el).fontSize) < 11).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
   expect(pequenos).toEqual([])
   revocado = true
-  await registro.getByRole('button', { name: 'Actualizar', exact: true }).click()
+  // Sin «Actualizar» propio en la ficha: la pantalla entera se actualiza desde su cabecera.
+  await vista.locator(':scope > header').getByRole('button', { name: 'Actualizar', exact: true }).click()
   await expect(registro.getByRole('alert')).toContainText('Ya no tienes autorización')
   await expect(registro.getByRole('listitem')).toHaveCount(0)
   await detalle.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
@@ -202,8 +204,9 @@ test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginaci
 })
 
 // Diseño de Gestión Diaria (27/09/2026): filas de 52 px con aire en vez de las 44 px de H2 (23/09); se ven
-// menos filas sin desplazar y el resto se alcanza dentro de la tabla, sin mover la página.
-for (const medida of [{ width: 1512, height: 805, filas: 6 }, { width: 1366, height: 768, filas: 5 }]) {
+// menos filas sin desplazar y el resto se alcanza dentro de la tabla, sin mover la página. Sin el tablero de
+// cifras (Miguel, 27/09: la jerarquía es de la tabla) se gana una fila en cada tamaño: 7 y 6.
+for (const medida of [{ width: 1512, height: 805, filas: 7 }, { width: 1366, height: 768, filas: 6 }]) {
   test(`H2 densidad ${medida.width}: ${medida.filas} filas, seis columnas y texto completo`, async ({ page }, info) => {
     await page.setViewportSize(medida)
     await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
index 382236ba..db8c25b7 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
@@ -67,7 +67,7 @@ test('H3: últimas tres comparten Registro; pendientes conservan páginas, ficha
   await expect(lista.getByText('Tarea de perfil')).toBeVisible()
   await expect(lista.getByText('Tarea de postventa')).toBeVisible()
   await page.screenshot({path:info.outputPath('h3-pendientes-escritorio.png')})
-  await panel.getByRole('button',{name:'Cargar más tareas'}).click()
+  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
   await expect(lista.getByRole('listitem')).toHaveCount(50)
   const n=estado.consultas
   await panel.getByRole('tab',{name:'Registro',exact:true}).click()
@@ -80,15 +80,15 @@ test('H3: últimas tres comparten Registro; pendientes conservan páginas, ficha
   await page.keyboard.press('Escape');await expect(enlace).toBeFocused()
   await expect(lista.getByRole('listitem')).toHaveCount(50)
   await panel.getByRole('button',{name:'Restaurar panel'}).click()
-  await panel.getByRole('button',{name:'Cargar más tareas'}).click()
+  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
   await expect(lista.getByRole('listitem')).toHaveCount(55)
-  await panel.getByRole('button',{name:'Vencidas',exact:true}).click()
+  await panel.getByRole('button',{name:/^Vencidas/}).click()
   await expect(lista.getByRole('listitem')).toHaveCount(25)
-  await panel.getByRole('button',{name:'Cargar más tareas'}).click()
+  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
   await expect(lista.getByRole('listitem')).toHaveCount(30)
   await vista.getByRole('button',{name:'Actualizar',exact:true}).click()
   await expect(lista.getByRole('listitem')).toHaveCount(25)
-  await expect(panel.getByRole('button',{name:'Vencidas',exact:true})).toHaveAttribute('aria-pressed','true')
+  await expect(panel.getByRole('button',{name:/^Vencidas/})).toHaveAttribute('aria-pressed','true')
   await page.setViewportSize({width:390,height:844})
   await expect(page.getByRole('dialog',{name:'Detalle de ANA H3'})).toBeVisible()
   expect(await panel.evaluate(e=>e.scrollWidth<=e.clientWidth)).toBe(true)
@@ -102,7 +102,7 @@ for(const codigo of ['PGRST202','XX000','42501']) test(`H3: ${codigo} no se pres
   const lista=panel.getByRole('list',{name:'Lista de tareas pendientes'})
   await expect(lista.getByRole('listitem')).toHaveCount(25)
   estado.error=codigo
-  await panel.getByRole('button',{name:'Cargar más tareas'}).click()
+  await panel.getByRole('button',{name:'Ver más',exact:true}).click()
   await expect(panel.getByRole('alert')).toBeVisible()
   await expect(panel.getByText('Sin tareas pendientes.')).toHaveCount(0)
   if(codigo==='42501') {await expect(lista.getByRole('listitem')).toHaveCount(0);expect(estado.equipo).toBeGreaterThan(1)}
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx
index d159385e..030e6485 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.test.tsx
@@ -43,16 +43,3 @@ describe('FranjaCifras', () => {
     expect(screen.getByTestId('chip')).toHaveTextContent('Bien')
   })
 })
-
-describe('FranjaCifras en línea (supervisor, 27/09/2026)', () => {
-  it('pinta número y etiqueta en una línea SIN cambiar el orden término → definición', () => {
-    const { container } = render(<FranjaCifras etiqueta="Resumen del equipo" disposicion="en-linea" cifras={[{ etiqueta: 'Analistas', valor: '5' }]} />)
-    const celda = container.querySelector('dl > div')!
-    expect(celda).toHaveClass('flex-row-reverse')
-    expect(celda.firstElementChild?.tagName).toBe('DT')
-  })
-  it('el tono de aviso usa el ámbar de TEXTO: «Necesitan atención» no es un vencimiento', () => {
-    render(<FranjaCifras etiqueta="Cifras" cifras={[{ etiqueta: 'Necesitan atención', valor: '4', tono: 'aviso' }]} />)
-    expect(screen.getByText('4')).toHaveClass('text-[var(--warning-text)]')
-  })
-})
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
index 1dad9f1a..43527214 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/franja-cifras.tsx
@@ -16,10 +16,8 @@ export interface CifraDelDia {
   valorAccesible?: string | undefined
   /** Texto o chip que acompaña al número («de 18», «hoy», el nivel). */
   apoyo?: ReactNode
-  /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy».
-   * `aviso` lo pinta en ámbar: una señal que NO es un vencimiento (p. ej. «Necesitan atención»,
-   * que mezcla vencidas con cortes y tiempo sin llamar). */
-  tono?: 'normal' | 'alerta' | 'aviso' | undefined
+  /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy». */
+  tono?: 'normal' | 'alerta' | undefined
 }
 
 // Clases escritas enteras: Tailwind no ve las que se arman con plantillas.
@@ -27,33 +25,23 @@ const COLUMNAS: Record<number, string> = {
   1: 'sm:grid-cols-1', 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-4', 5: 'sm:grid-cols-5', 6: 'sm:grid-cols-6',
 }
 
-const TONO: Record<NonNullable<CifraDelDia['tono']>, string> = {
-  normal: 'text-primary', alerta: 'text-[var(--destructive-text)]', aviso: 'text-[var(--warning-text)]',
-}
-
-export function FranjaCifras({ etiqueta, cifras, className, disposicion = 'apilada' }: {
+export function FranjaCifras({ etiqueta, cifras, className }: {
   /** Nombre del grupo para el lector de pantalla («Tu día en cifras»). */
   etiqueta: string
   cifras: readonly CifraDelDia[]
   className?: string | undefined
-  /** `apilada`: etiqueta arriba y número debajo (analista). `en-linea`: número y
-   * etiqueta en una línea, como la franja del supervisor en el diseño. El DOM
-   * conserva término → definición; solo cambia el orden visual. */
-  disposicion?: 'apilada' | 'en-linea' | undefined
 }): JSX.Element {
-  const enLinea = disposicion === 'en-linea'
   return (
     // Grupo con nombre, no una región más: la pantalla ya tiene las suyas.
     <section role="group" aria-label={etiqueta} className={cn('rounded-2xl border border-border bg-card', className)}>
-      <dl className={cn('grid grid-cols-2 gap-y-4', enLinea ? 'py-[18px]' : 'py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
+      <dl className={cn('grid grid-cols-2 gap-y-4 py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
         {cifras.map((c, i) => (
           // En el celular son 2 por fila (raya solo en la segunda); desde tablet,
           // raya a la izquierda de todas menos la primera.
-          <div key={c.etiqueta} className={cn('flex min-w-0 px-5', enLinea ? 'flex-row-reverse items-baseline justify-end gap-2.5' : 'flex-col gap-1',
-            i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
-            <dt className={enLinea ? 'min-w-0 text-[13px] text-[var(--muted-foreground-strong)]' : 'text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]'}>{c.etiqueta}</dt>
+          <div key={c.etiqueta} className={cn('flex min-w-0 flex-col gap-1 px-5', i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
+            <dt className="text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
             <dd className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
-              <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', TONO[c.tono ?? 'normal'])}>
+              <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', c.tono === 'alerta' ? 'text-[var(--destructive-text)]' : 'text-primary')}>
                 {c.valorAccesible !== undefined ? (
                   <>
                     <span aria-hidden="true">{c.valor}</span>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
index 24a787f6..d923b279 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx
@@ -51,14 +51,14 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
   const nombre = seleccion && !equipo ? fila?.nombre_completo ?? seleccion.nombre ?? 'Analista' : null
   const titulo = seleccion ? equipo ? 'Registro del equipo' : `Detalle de ${nombre}` : 'Detalle del analista'
   return (
-    <section id={id} aria-label={titulo} className="flex min-h-0 min-w-0 flex-1 flex-col overflow-clip rounded-2xl border border-border bg-card">
-      <header className="flex shrink-0 items-center gap-3 border-b border-border px-5 py-3.5">
-        {nombre !== null ? <Avatar nombre={nombre} color="var(--accent-press)" />
+    <section id={id} aria-label={titulo} className="flex min-h-0 min-w-0 flex-1 flex-col overflow-clip rounded-2xl border border-accent/30 bg-card shadow-[0_14px_34px_-18px_rgba(17,30,61,0.35)]">
+      <header className="flex shrink-0 items-center gap-3.5 border-b border-accent/15 bg-accent/[0.06] px-5 py-4">
+        {nombre !== null ? <Avatar nombre={nombre} color="var(--accent-press)" relleno className="size-11 text-[15px]" />
           : equipo ? <span aria-hidden="true" className="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-primary"><ClipboardList className="size-4" /></span> : null}
         <div className="min-w-0 flex-1">
           {/* El nombre visible es el del analista; el lector oye «Detalle de …»,
               como el nombre de la región y del diálogo. */}
-          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className="rounded-md text-[17px] font-extrabold leading-tight tracking-[-0.01em] text-primary [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
+          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1} className="rounded-md text-[22px] font-extrabold leading-tight tracking-[-0.015em] text-primary [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
             {/* El espacio va FUERA del texto oculto: dentro se perdía («Detalle deANA»). */}
             {nombre !== null ? <><span className="sr-only">Detalle de</span>{' '}{nombre}</> : titulo}
           </h3></TituloDialogo>
@@ -77,6 +77,8 @@ export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, titu
   )
 }
 
+const FECHA_TITULO = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })
+
 function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar, esHoy, ahora, silencioso }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor; esHoy: boolean; ahora: number; silencioso: boolean }) {
   const equipo = seleccion.analista === null
   const [pestana, setPestana] = useState<PestanaPanel>(equipo || seleccion.enfocar ? 'registro' : 'resumen')
@@ -127,9 +129,13 @@ function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta
       </>}
     </div>
     <div className={cuerpo} hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
-      {registro && <section aria-label="Registro seleccionado">
-        <h4 ref={tituloRegistro} tabIndex={-1} className="mb-3 text-[15px] font-extrabold text-primary">{equipo ? 'Registro del equipo' : `Registro de ${seleccion.nombre}`}</h4>
-        <RegistroActividad key={registro.apertura} dia={dia} pestanaInicial={registro.pestana}
+      {/* Como el resumen (Miguel, 27/09): un título corto con el día, filtros en
+          pastilla y filas limpias; sin la descripción ni controles de pantalla completa. */}
+      {registro && <section aria-label="Registro seleccionado" className="space-y-2">
+        <h4 ref={tituloRegistro} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
+          {esHoy ? 'Actividad de hoy' : `Actividad del ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
+        </h4>
+        <RegistroActividad compacto encabezadoExterno={tituloRegistro} key={registro.apertura} dia={dia} pestanaInicial={registro.pestana}
           analistaIds={seleccion.analista === null ? null : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
       </section>}
     </div>
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx
index 767017ae..e9f9488e 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx
@@ -23,7 +23,7 @@ describe('Lista útil de pendientes', () => {
     render(<PendientesSupervisor {...props} />)
     expect(screen.getByText('Sin título')).toBeVisible()
     for (const texto of ['Referencia no disponible','Tarea de perfil','Tarea de postventa']) expect(screen.getByText(texto)).toBeVisible()
-    expect(within(screen.getByRole('list')).getAllByRole('button')).toHaveLength(1)
+    expect(within(screen.getByRole('list', { name: 'Lista de tareas pendientes' })).getAllByRole('button')).toHaveLength(1)
     fireEvent.click(screen.getByRole('button', { name: 'Lead visible' })); expect(dobles.abrir).toHaveBeenCalledWith(tareaPendiente().lead_id)
   })
   it.each(['PGRST202','XX000','42501'])('distingue %s de un vacío confirmado', codigo => {
@@ -37,11 +37,39 @@ describe('Lista útil de pendientes', () => {
   it('informa página congelada y datos anteriores; filtros y refresco externo conservan foco', () => {
     dobles.lista.congelada = true; dobles.lista.error = new Error('sin red')
     const vista=render(<PendientesSupervisor {...props} />)
-    expect(screen.getByText(/Datos anteriores; la actualización falló/)).toBeVisible()
-    fireEvent.click(screen.getByRole('button', { name: 'Vencidas' }))
+    expect(screen.getByText(/Datos anteriores/)).toBeVisible()
+    fireEvent.click(screen.getByRole('button', { name: /^Vencidas/ }))
     expect(dobles.hook).toHaveBeenLastCalledWith(props.dia,props.analista,true,true,0)
-    const filtro=screen.getByRole('button', { name: 'Vencidas' }); filtro.focus()
+    const filtro=screen.getByRole('button', { name: /^Vencidas/ }); filtro.focus()
     vista.rerender(<PendientesSupervisor {...props} actualizacion={1} />)
     expect(dobles.recargar).toHaveBeenCalledOnce(); expect(filtro).toHaveFocus(); expect(filtro).toHaveAttribute('aria-pressed','true')
   })
+  it('como el resumen: dos cuadros con número que filtran, la vencida se marca y el título no repite el lead (Miguel, 27/09)', () => {
+    dobles.lista.items = [
+      tareaPendiente(20, { tipo: 'whatsapp', titulo: 'WhatsApp — LEAD VISIBLE', vence_en: '2026-09-23T16:00:00.000001+00:00' }),
+      tareaPendiente(21, { titulo: 'Responder propuesta — Lead', vence_en: '2026-09-23T18:00:00.000001+00:00' }),
+    ]
+    dobles.lista.pagina = paginaPendientes(dobles.lista.items, { resumen: { tareas_pendientes: 5, tareas_vencidas: 2 } })
+    render(<PendientesSupervisor {...props} />)
+    const filtro = screen.getByRole('group', { name: 'Filtro de tareas' })
+    expect(within(filtro).getByRole('button', { name: /^Todas 5$/ })).toHaveAttribute('aria-pressed', 'true')
+    fireEvent.click(within(filtro).getByRole('button', { name: /^Vencidas 2$/ }))
+    expect(dobles.hook).toHaveBeenLastCalledWith(props.dia, props.analista, true, true, 0)
+    const [primera, segunda] = within(screen.getByRole('list', { name: 'Lista de tareas pendientes' })).getAllByRole('listitem')
+    // Vence antes del corte de la consulta (17:00 UTC): vencida. La otra, después: no.
+    expect(within(primera!).getByText('Vencida')).toBeVisible()
+    expect(within(segunda!).queryByText('Vencida')).not.toBeInTheDocument()
+    // «WhatsApp — LEAD VISIBLE» ya lo dicen el tipo y el lead: sin título repetido.
+    expect(within(primera!).queryByText(/WhatsApp —/)).not.toBeInTheDocument()
+    expect(within(segunda!).getByText('Responder propuesta')).toBeVisible()
+    expect(screen.getByRole('heading', { name: 'Pendientes de ANA' })).toBeInTheDocument()
+  })
+  it('las señales de leads solo aparecen con número confirmado mayor que cero', () => {
+    const vista = render(<PendientesSupervisor {...props} fila={filaEquipoPrueba({ primer_intento_vencido: 3, datos_incompletos: null })} />)
+    expect(within(screen.getByRole('list', { name: 'Leads por revisar' })).getByText('3 leads con el primer intento tarde')).toBeVisible()
+    expect(screen.queryByText(/datos por revisar/)).not.toBeInTheDocument()
+    vista.rerender(<PendientesSupervisor {...props} fila={filaEquipoPrueba({ primer_intento_vencido: null, datos_incompletos: 0 })} />)
+    expect(screen.queryByRole('list', { name: 'Leads por revisar' })).not.toBeInTheDocument()
+    expect(screen.queryByText(/no evaluado/)).not.toBeInTheDocument()
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
index fd5a1c2d..5e6a0fad 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
@@ -1,12 +1,34 @@
+// Pendientes del analista en la ficha del supervisor. Como el resumen (Miguel,
+// 27/09/2026: «demasiado texto y no se entiende»): dos cuadros que SON el
+// filtro (cada número abre su lista), las señales de leads solo si hay algo que
+// decir, y filas limpias —hora, tipo, lead y «Vencida»—. Los estados que no se
+// pueden confirmar se siguen diciendo, en una línea.
 import { useEffect, useEffectEvent, useId, useLayoutEffect, useRef, useState } from 'react'
+import { Check } from 'lucide-react'
 import { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
 import { CrmApiError } from '@/data/crm-api'
 import { usePanelesActions } from '@/lib/store-context'
 import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
-import { Button } from '@/components/ui/button'
+import { instantePendiente } from '@/lib/gestion-diaria-pendientes'
+import { Badge } from '@/components/ui/badge'
 import { TIPO_EVENTO } from '@/lib/tipos'
+import { cn } from '@/lib/utils'
 
-const FECHA = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })
+const HORA = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false })
+const DIA_MES = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', day: 'numeric', month: 'numeric' })
+const DIA_LIMA = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' })
+const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
+const ENLACE = cn('inline-flex h-9 cursor-pointer items-center rounded-[10px] px-3 text-[13px] font-bold text-[var(--accent-press)] transition-colors hover:bg-accent/10 aria-disabled:cursor-default aria-disabled:opacity-50 pointer-coarse:h-11', FOCO)
+const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`
+
+type Accion = 'cargar' | 'reintentar' | 'actualizar'
+
+const normalizar = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es').trim()
+/** Las tareas automáticas se titulan «Acción — LEAD»: el lead ya va al lado, no se repite. */
+function sinElLead(titulo: string, lead: string | null): string {
+  const partes = /^(.+?)\s+[—–-]\s+(.+)$/.exec(titulo)
+  return lead && partes && normalizar(lead).startsWith(normalizar(partes[2]!)) ? partes[1]! : titulo
+}
 
 export function PendientesSupervisor({ analista, nombre, dia, fila, visible, soloVencidasInicial, apertura, enfocar, actualizacion, revalidar }: {
   analista: string; nombre: string; dia: string; fila: FilaEquipoPresentada | undefined; visible: boolean
@@ -27,58 +49,111 @@ export function PendientesSupervisor({ analista, nombre, dia, fila, visible, sol
   }, [actualizacion])
   useEffect(() => { if (lista.sinPermiso) revocar() }, [lista.sinPermiso])
   const noInstalada = lista.error instanceof CrmApiError && lista.error.code === 'PGRST202'
-  // «Cargar más» y «Reintentar» se desmontan al terminar: si el que tenía el
-  // foco desaparece, el foco pasa al título (se sigue CADA control, no un conjunto).
-  const enfocado = useRef<'cargar' | 'reintentar' | null>(null)
-  const recordar = (cual: 'cargar' | 'reintentar') => ({ onFocus: () => { enfocado.current = cual }, onBlur: () => { enfocado.current = null } })
+  // «Ver más», «Reintentar» y «Actualizar» se desmontan al terminar: si el que
+  // tenía el foco desaparece, el foco pasa al título (se sigue CADA control).
+  const enfocado = useRef<Accion | null>(null)
+  const recordar = (cual: Accion) => ({ onFocus: () => { enfocado.current = cual }, onBlur: () => { enfocado.current = null } })
   const cargarVisible = lista.hayMas
   const reintentarVisible = Boolean(lista.error) && !lista.sinPermiso
+  const actualizarVisible = lista.congelada && !lista.error
   useLayoutEffect(() => {
     const cual = enfocado.current
-    if (cual === null || (cual === 'cargar' ? cargarVisible : reintentarVisible)) return
+    if (cual === null || (cual === 'cargar' ? cargarVisible : cual === 'reintentar' ? reintentarVisible : actualizarVisible)) return
     enfocado.current = null
     titulo.current?.focus({ preventScroll: true })
-  }, [cargarVisible, reintentarVisible])
-  const deshabilitado = 'aria-disabled:cursor-default aria-disabled:opacity-60'
+  }, [cargarVisible, reintentarVisible, actualizarVisible])
   const resumen = lista.pagina?.resumen ?? (fila && !lista.sinPermiso ? fila : null)
-  // Escala del diseño de Gestión Diaria (27/09): 13–15 px y controles compactos que crecen en táctil.
+  const corte = lista.pagina ? instantePendiente(lista.pagina.pendientes_al) : null
+  // Señales de LEADS (no son tareas): solo con número confirmado mayor que cero.
+  const senales = fila && !lista.sinPermiso ? [
+    fila.primer_intento_vencido ? plural(fila.primer_intento_vencido, 'lead con el primer intento tarde', 'leads con el primer intento tarde') : null,
+    fila.datos_incompletos ? plural(fila.datos_incompletos, 'lead con datos por revisar', 'leads con datos por revisar') : null,
+  ].filter((s): s is string => s !== null) : []
+  const cuadros = [
+    { vencidas: false, etiqueta: 'Todas', valor: resumen?.tareas_pendientes },
+    { vencidas: true, etiqueta: 'Vencidas', valor: resumen?.tareas_vencidas },
+  ]
   return <section aria-labelledby={tituloId} className="space-y-3 text-[13.5px]">
-    <h4 id={tituloId} ref={titulo} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Pendientes de {nombre}</h4>
-    {resumen && <p><strong>{resumen.tareas_pendientes}</strong> tareas pendientes · <strong>{resumen.tareas_vencidas}</strong> vencidas.
-      {lista.pagina ? ' Foto de la consulta de tareas.' : ' Último resumen confirmado del equipo.'}</p>}
-    {fila && !lista.sinPermiso && <p className="text-[var(--muted-foreground-strong)]">Primer intento fuera de plazo: {fila.primer_intento_vencido ?? 'no evaluado'}. Datos incompletos: {fila.datos_incompletos ?? 'no evaluado'}.
-      {' '}Estas señales corresponden a leads y no se suman como tareas.</p>}
-    <div className="flex flex-wrap gap-2" role="group" aria-label="Filtro de tareas">
-      <Button className="h-9 text-[13px] pointer-coarse:h-11" variant={!soloVencidas ? 'default' : 'outline'} aria-pressed={!soloVencidas} onClick={() => setSoloVencidas(false)}>Todas</Button>
-      <Button className="h-9 text-[13px] pointer-coarse:h-11" variant={soloVencidas ? 'default' : 'outline'} aria-pressed={soloVencidas} onClick={() => setSoloVencidas(true)}>Vencidas</Button>
+    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
+      {/* El nombre del analista lo dice la cabecera de la ficha; el lector lo oye aquí también. */}
+      <h4 id={tituloId} ref={titulo} tabIndex={-1} className={cn('rounded-md text-[15px] font-extrabold text-primary', FOCO)}>
+        Pendientes{' '}<span className="sr-only">de {nombre}</span>
+      </h4>
+      {lista.pagina && <p className="flex items-center gap-1 text-xs text-[var(--muted-foreground-strong)]">
+        Consulta {HORA.format(new Date(lista.pagina.generado_en))}{actualizarVisible ? ' · pausada' : ''}
+        {actualizarVisible && <button type="button" className={cn(ENLACE, 'h-7 px-2 text-xs')} aria-disabled={lista.enVuelo} {...recordar('actualizar')}
+          onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Actualizar tareas</button>}
+      </p>}
+    </div>
+
+    <div role="group" aria-label="Filtro de tareas" className="grid grid-cols-2 gap-2.5">
+      {cuadros.map((c) => {
+        const activo = c.vencidas === soloVencidas
+        return (
+          <button key={c.etiqueta} type="button" aria-pressed={activo} onClick={() => setSoloVencidas(c.vencidas)}
+            className={cn('min-w-0 cursor-pointer rounded-xl border-2 px-3.5 py-3 text-left transition-colors', FOCO,
+              activo ? 'border-accent bg-accent/[0.06]' : 'border-transparent bg-muted/70 hover:bg-muted')}>
+            <span className="flex items-center gap-1 text-xs font-semibold text-[var(--muted-foreground-strong)]">
+              {activo && <Check aria-hidden className="size-3.5 text-[var(--accent-press)]" />}{c.etiqueta}
+            </span>
+            {c.valor !== undefined && <>{' '}<span className={cn('mt-1 block text-[28px] font-extrabold leading-tight tabular-nums',
+              c.vencidas && c.valor > 0 ? 'text-[var(--destructive-text)]' : 'text-primary')}>{c.valor}</span></>}
+          </button>
+        )
+      })}
     </div>
-    {lista.cargando && <p role="status">Consultando las tareas de este analista…</p>}
-    {lista.error && <div role="alert" className="space-y-2">
-      <p>{lista.sinPermiso ? 'Ya no tienes acceso a estas tareas. Se retiraron los datos anteriores.'
-        : noInstalada ? 'Detalle de tareas no disponible. La consulta aún no está instalada.'
-          : 'No se pudo confirmar la lista de tareas. Esto no significa que esté vacía.'}</p>
-      {!lista.sinPermiso && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} variant="outline" aria-disabled={lista.enVuelo} {...recordar('reintentar')} onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Reintentar desde el inicio</Button>}
+
+    {senales.length > 0 && (
+      // oxlint-disable-next-line jsx-a11y/no-redundant-roles
+      <ul role="list" aria-label="Leads por revisar" className="space-y-1 rounded-xl bg-warning/10 px-4 py-2.5 text-[13px] font-semibold text-[var(--warning-text)]">
+        {senales.map((s) => <li key={s}>{s}</li>)}
+      </ul>
+    )}
+
+    {lista.cargando && <p role="status" className="text-[var(--muted-foreground-strong)]">Consultando tareas…</p>}
+    {lista.error && <div role="alert" className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-muted/70 px-4 py-2.5">
+      <p className="font-semibold text-primary">{lista.sinPermiso ? 'Ya no tienes acceso a estas tareas.'
+        : noInstalada ? 'Detalle de tareas no disponible.'
+          : lista.items.length > 0 ? 'Datos anteriores: no se pudo actualizar.' : 'No se pudo cargar la lista. No significa que esté vacía.'}</p>
+      {reintentarVisible && <button type="button" className={ENLACE} aria-disabled={lista.enVuelo} {...recordar('reintentar')}
+        onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Reintentar</button>}
     </div>}
-    {lista.pagina && <p className="text-[var(--muted-foreground-strong)]">
-      Consulta: {FECHA.format(new Date(lista.pagina.generado_en))} · Lima.
-      {lista.error ? ' Datos anteriores; la actualización falló.' : lista.congelada ? ' Actualización automática pausada: hay varias páginas cargadas.' : ' Actualización cada minuto mientras esta pestaña está visible.'}
-    </p>}
-    {lista.congelada && lista.consultadoDesde && <p className="text-[var(--muted-foreground-strong)]">Primera página consultada: {FECHA.format(new Date(lista.consultadoDesde))}. Las tareas pueden cambiar; actualizar comienza una nueva consulta.</p>}
-    {!lista.error && lista.pagina && lista.items.length === 0 && <p>{soloVencidas ? 'No hay tareas vencidas en esta consulta.' : 'Sin tareas pendientes.'}</p>}
+    {!lista.error && lista.pagina && lista.items.length === 0 && <p className="text-[var(--muted-foreground-strong)]">{soloVencidas ? 'Sin tareas vencidas.' : 'Sin tareas pendientes.'}</p>}
+
     {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
-    <ul role="list" className="divide-y divide-border" aria-label="Lista de tareas pendientes">
-      {lista.items.map(tarea => <li key={tarea.id} className="space-y-1 py-3 break-words">
-        <p className="font-bold text-primary">{tarea.titulo.trim() || 'Sin título'}</p>
-        <p>{TIPO_EVENTO[tarea.tipo] ?? tarea.tipo} · <time dateTime={new Date(tarea.vence_en).toISOString()}>{FECHA.format(new Date(tarea.vence_en))}</time> · Lima</p>
-        {tarea.lead_id && tarea.lead_nombre
-          ? <Button variant="link" className="h-auto min-h-6 max-w-full whitespace-normal px-0 text-left text-[13.5px] pointer-coarse:min-h-11" onClick={() => abrirLead(tarea.lead_id!)}>{tarea.lead_nombre}</Button>
-          : <p className="text-[var(--muted-foreground-strong)]">{tarea.referencia_tipo === 'perfil' ? 'Tarea de perfil' : tarea.referencia_tipo === 'postventa' ? 'Tarea de postventa' : 'Referencia no disponible'}</p>}
-      </li>)}
+    <ul role="list" aria-label="Lista de tareas pendientes">
+      {lista.items.map((tarea) => {
+        const vence = new Date(tarea.vence_en)
+        const instante = instantePendiente(tarea.vence_en)
+        const vencida = corte !== null && instante !== null && instante < corte
+        const tipo = TIPO_EVENTO[tarea.tipo] ?? tarea.tipo
+        const tituloTarea = sinElLead(tarea.titulo.trim(), tarea.lead_nombre) || 'Sin título'
+        return (
+          <li key={tarea.id} className="flex gap-3 border-b border-muted py-2.5 break-words">
+            <time dateTime={vence.toISOString()} className="w-11 shrink-0 pt-0.5 text-[13px] font-bold tabular-nums text-foreground/80">
+              {HORA.format(vence)}
+              {DIA_LIMA.format(vence) !== dia && <span className="block text-[11.5px] font-semibold text-[var(--muted-foreground-strong)]">{DIA_MES.format(vence)}</span>}
+            </time>
+            <div className="min-w-0 flex-1 space-y-1">
+              <div className="flex flex-wrap items-center gap-2">
+                <Badge className="min-h-[22px] py-0 text-[11.5px]" color="var(--accent-press)">{tipo}</Badge>
+                {vencida && <Badge className="min-h-[22px] py-0 text-[11.5px]" color="var(--destructive-text)">Vencida</Badge>}
+                {tarea.lead_id && tarea.lead_nombre
+                  ? <button type="button" onClick={() => abrirLead(tarea.lead_id!)}
+                    className={cn('rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline pointer-coarse:min-h-11', FOCO)}>{tarea.lead_nombre}</button>
+                  : <span className="text-[13px] text-[var(--muted-foreground-strong)]">{tarea.referencia_tipo === 'perfil' ? 'Tarea de perfil' : tarea.referencia_tipo === 'postventa' ? 'Tarea de postventa' : 'Referencia no disponible'}</span>}
+              </div>
+              {/* El título solo si dice algo más que el tipo («WhatsApp» / «WhatsApp»). */}
+              {normalizar(tituloTarea) !== normalizar(tipo) && <p className="text-[13px] leading-snug text-foreground/80">{tituloTarea}</p>}
+            </div>
+          </li>
+        )
+      })}
     </ul>
-    {lista.pagina && <p role="status">{lista.items.length} tareas cargadas{lista.hayMas ? ' · Hay más por consultar.' : lista.error ? ' · Consulta incompleta.' : ' · Fin de las páginas consultadas.'}</p>}
-    <div className="flex flex-wrap gap-2">
-      {lista.hayMas && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} aria-disabled={lista.enVuelo} {...recordar('cargar')} onClick={() => { if (!lista.enVuelo) void lista.cargarMas() }}>{lista.enVuelo ? 'Consultando…' : 'Cargar más tareas'}</Button>}
-      {!lista.sinPermiso && !noInstalada && <Button className={`h-9 text-[13px] pointer-coarse:h-11 ${deshabilitado}`} variant="outline" aria-disabled={lista.enVuelo} onClick={() => { if (!lista.enVuelo) void lista.recargar() }}>Actualizar desde el inicio</Button>}
-    </div>
+    {lista.pagina && <p role="status" className="sr-only">{plural(lista.items.length, 'tarea cargada', 'tareas cargadas')}{lista.hayMas ? ' · hay más' : lista.error ? ' · consulta incompleta' : ''}</p>}
+    {cargarVisible && <div className="flex justify-center">
+      <button type="button" className={ENLACE} aria-disabled={lista.enVuelo} aria-busy={lista.enVuelo || undefined} {...recordar('cargar')}
+        onClick={() => { if (!lista.enVuelo) void lista.cargarMas() }}>{lista.enVuelo ? 'Cargando…' : 'Ver más'}</button>
+    </div>}
   </section>
 }
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.test.tsx
index f421a4aa..d542b62b 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.test.tsx
@@ -3,6 +3,7 @@
 // cursor al cambiar un filtro, estados vacío/error/carga, filtro por equipo y
 // la exportación solo para quien la tiene permitida. El data layer se mockea:
 // aquí se prueba la presentación y el contrato con el hook, no el servidor.
+import { createRef } from 'react'
 import { beforeEach, describe, expect, it, vi } from 'vitest'
 import { fireEvent, render, screen, within } from '@testing-library/react'
 import type { RegistroItem, RegistroPagina } from '@/lib/gestion-diaria'
@@ -324,4 +325,21 @@ describe('RegistroActividad compacto — «Ver más» no suelta el foco (revisi
     expect(screen.getByRole('list', { name: 'Registro de actividad' })).toHaveAttribute('role', 'list')
     expect(screen.getByText(/gestiones cargadas/)).not.toHaveTextContent(/actualizando/)
   })
+
+  it('en la ficha del supervisor usa el título de la ficha: sin «¿Qué hice hoy?» y con el autor en el registro del equipo', () => {
+    ESTADO.pagina = pagina(Array.from({ length: 26 }, (_, n) => item(n + 1)))
+    const titulo = createRef<HTMLHeadingElement>()
+    const vista = render(<><h4 ref={titulo} tabIndex={-1}>Actividad de hoy</h4>
+      <RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} compacto encabezadoExterno={titulo} /></>)
+    expect(screen.queryByRole('heading', { name: '¿Qué hice hoy?' })).not.toBeInTheDocument()
+    expect(screen.getAllByText('· ANALISTA UNO').length).toBeGreaterThan(0)
+    // El registro del equipo conserva su filtro por analista.
+    expect(screen.getByRole('combobox', { name: /^Analista/ })).toBeInTheDocument()
+    const boton = screen.getByRole('button', { name: 'Ver más' })
+    boton.focus()
+    ESTADO.pagina = pagina([item(40)])
+    vista.rerender(<><h4 ref={titulo} tabIndex={-1}>Actividad de hoy</h4>
+      <RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} compacto encabezadoExterno={titulo} /></>)
+    expect(screen.getByRole('heading', { name: 'Actividad de hoy' })).toHaveFocus()
+  })
 })
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
index 583636b9..0e3e1992 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/registro-actividad.tsx
@@ -10,7 +10,7 @@
 // resultado tipificado (`metadata.evento = 'revision'`); el «buscador» de
 // analista es un desplegable (≤ 20 nombres); el CSV exporta las filas CARGADAS,
 // no el día entero (el aviso lo dice con el número exacto).
-import { useEffect, useEffectEvent, useId, useLayoutEffect, useMemo, useRef, useState } from 'react'
+import { useEffect, useEffectEvent, useId, useLayoutEffect, useMemo, useRef, useState, type RefObject } from 'react'
 import { ArrowUpRight, ClipboardList, Download, RefreshCw } from 'lucide-react'
 import { useAuth } from '@/lib/auth-context'
 import { useAhora } from '@/lib/ahora'
@@ -66,6 +66,11 @@ interface Props {
    * Supervisor y gerencia conservan su versión hasta sus propios planes.
    */
   compacto?: boolean
+  /**
+   * Compacto dentro de la ficha del supervisor (27/09/2026): el título lo pone
+   * la ficha y el foco de respaldo («Ver más» que se va, «Reintentar») va a él.
+   */
+  encabezadoExterno?: RefObject<HTMLHeadingElement | null> | undefined
 }
 
 export function RegistroActividad(props: Props) {
@@ -75,7 +80,7 @@ export function RegistroActividad(props: Props) {
   return <RegistroDelAmbito key={identidad} {...props} />
 }
 
-function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo = false, permitirExportar, pestanaInicial = 'llamadas', actualizacion = 0, onSinPermiso, compartirPrimeraPagina = false, compacto = false }: Props) {
+function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo = false, permitirExportar, pestanaInicial = 'llamadas', actualizacion = 0, onSinPermiso, compartirPrimeraPagina = false, compacto = false, encabezadoExterno }: Props) {
   const { yo } = useAuth()
   const ahora = useAhora()
   const { equipo, ambito } = useCRMData()
@@ -91,7 +96,8 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
   const [cursor, setCursor] = useState<CursorRegistro | null>(null)
   const [aviso, setAviso] = useState<string | null>(null)
   const [reinicio, setReinicio] = useState(0)
-  const encabezado = useRef<HTMLHeadingElement>(null)
+  const propio = useRef<HTMLHeadingElement>(null)
+  const encabezado = encabezadoExterno ?? propio
 
   const idsEquipo = useMemo(() => (equipoSel ? analistasDelEquipo(equipo, equipoSel) : null), [equipo, equipoSel])
   const filtros = useMemo<FiltrosRegistro>(() => ({
@@ -244,6 +250,7 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
                     className="rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
                     {item.lead_nombre}
                   </button>
+                  {mostrarAnalista && <span className="text-[12.5px] font-semibold text-[var(--muted-foreground-strong)]">· {item.autor_nombre}</span>}
                 </div>
                 {item.detalle && <p className="whitespace-pre-wrap break-words text-[13px] leading-snug text-foreground/80">{item.detalle}</p>}
                 <p className="text-[11.5px] text-[var(--muted-foreground-strong)]">{etapaEntonces ? `${etapaEntonces} entonces · ` : ''}{etapaActual} ahora</p>
@@ -285,16 +292,34 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
       detalle={pestana === 'todo' && etapa === null ? 'Ninguna gestión registrada en el ámbito consultado.' : 'Prueba con la pestaña «Todo» u otra etapa. Esto no significa que no haya otras gestiones.'} />
   ) : compacto ? listaCompacta : lista
 
+  const pastillas = (
+    <Tabs variante="pastilla" etiqueta="Tipo de actividad" pestanas={PESTANAS_REGISTRO} valor={pestana} onCambio={setPestana}
+      className="space-y-2 [&>[role=tablist]]:gap-1.5 [&>[role=tablist]>[role=tab]]:min-h-9 [&>[role=tablist]>[role=tab]]:px-3 [&>[role=tablist]>[role=tab]]:py-0 [&>[role=tablist]>[role=tab]]:text-[12.5px] [&>[role=tablist]>[role=tab]]:font-bold">
+      {panel}
+    </Tabs>
+  )
+  if (compacto && encabezadoExterno) {
+    return (
+      <div className="space-y-2">
+        {mostrarAnalista && analistaIds?.length !== 1 && (
+          <label htmlFor={`${id}-analista`} className="flex flex-wrap items-center gap-2 text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Analista
+            <Select id={`${id}-analista`} value={analista ?? ''} onChange={(e) => setAnalista(e.target.value || null)} className="h-9 min-h-0 w-auto min-w-48 text-[13px]">
+              <option value="">Todos los analistas</option>
+              {analistas.map((m) => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
+            </Select>
+          </label>
+        )}
+        {pastillas}
+      </div>
+    )
+  }
   if (compacto) {
     return (
       <section aria-labelledby={`${id}-titulo`} className="space-y-2">
-        <h3 ref={encabezado} tabIndex={-1} id={`${id}-titulo`} className="text-[15px] font-extrabold text-primary">
+        <h3 ref={propio} tabIndex={-1} id={`${id}-titulo`} className="text-[15px] font-extrabold text-primary">
           ¿Qué hice hoy?
         </h3>
-        <Tabs variante="pastilla" etiqueta="Tipo de actividad" pestanas={PESTANAS_REGISTRO} valor={pestana} onCambio={setPestana}
-          className="space-y-2 [&>[role=tablist]]:gap-1.5 [&>[role=tablist]>[role=tab]]:min-h-9 [&>[role=tablist]>[role=tab]]:px-3 [&>[role=tablist]>[role=tab]]:py-0 [&>[role=tablist]>[role=tab]]:text-[12.5px] [&>[role=tablist]>[role=tab]]:font-bold">
-          {panel}
-        </Tabs>
+        {pastillas}
       </section>
     )
   }
@@ -303,7 +328,7 @@ function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo =
     <section aria-labelledby={`${id}-titulo`} className="space-y-4">
       <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
         <div>
-          <h3 ref={encabezado} tabIndex={-1} id={`${id}-titulo`} className="text-base font-bold text-primary">
+          <h3 ref={propio} tabIndex={-1} id={`${id}-titulo`} className="text-base font-bold text-primary">
             Registro de actividad {esHoy ? 'de hoy' : `del ${dia}`}
           </h3>
           <p className="max-w-3xl text-base text-[var(--muted-foreground-strong)]">
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
index 55bacd97..54ba6f1d 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/resumen-analista.tsx
@@ -72,7 +72,7 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
 
       <dl className="grid grid-cols-2 gap-2.5">
         <Cuadro etiqueta="Llamadas">
-          <span className="block text-2xl font-extrabold leading-tight tabular-nums text-primary">{f.marcador.llamadas}</span>
+          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.marcador.llamadas}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">{plural(f.marcador.contestadas, 'contestó', 'contestaron')}</span>
           <button type="button" onClick={abrirLlamadas} aria-label={`Ver llamadas del día de ${f.nombre_completo}`} className={ENLACE}>
             Ver llamadas<ChevronRight aria-hidden className="size-3.5" />
@@ -80,7 +80,7 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
         </Cuadro>
         <Cuadro etiqueta="Contacto">
           <span aria-hidden="true" className={cn('block font-extrabold leading-tight tabular-nums',
-            contacto.estado === 'evaluado' ? 'text-2xl text-primary' : 'text-base text-[var(--muted-foreground-strong)]')}>{contacto.valor}</span>
+            contacto.estado === 'evaluado' ? 'text-[28px] text-primary' : 'text-base text-[var(--muted-foreground-strong)]')}>{contacto.valor}</span>
           <span aria-hidden="true" className="block text-xs text-[var(--muted-foreground-strong)]">
             {contacto.estado === 'evaluado'
               ? <>{contacto.detalle} · <span className="font-semibold" style={{ color: COLOR_NIVEL[contacto.nivel!] }}>{ETIQUETA_NIVEL[contacto.nivel!]}</span></>
@@ -89,11 +89,11 @@ export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlama
           <span className="sr-only">{contacto.accesible}</span>
         </Cuadro>
         <Cuadro etiqueta="Citas agendadas">
-          <span className="block text-2xl font-extrabold leading-tight tabular-nums text-primary">{f.marcador.citas_agendadas}</span>
+          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.marcador.citas_agendadas}</span>
           <span className="block text-xs text-[var(--muted-foreground-strong)]">desde «Agendó cita»</span>
         </Cuadro>
         <Cuadro etiqueta="Pendientes">
-          <span className="block text-2xl font-extrabold leading-tight tabular-nums text-primary">{f.tareas_pendientes}</span>
+          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.tareas_pendientes}</span>
           <span className={cn('block text-xs', f.tareas_vencidas > 0 ? 'font-semibold text-[var(--destructive-text)]' : 'text-[var(--muted-foreground-strong)]')}>
             {plural(f.tareas_vencidas, 'vencida', 'vencidas')}
           </span>
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
index 25ac5db0..deb335af 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.test.tsx
@@ -124,7 +124,7 @@ describe('Supervisor horizontal', () => {
   it('los filtros no cambian indicadores y la ordenación comunica su dirección', () => {
     render(<GestionDiariaSupervisor />)
     const resumen = screen.getByRole('group', { name: 'Resumen del equipo' }).textContent
-    fireEvent.click(screen.getByRole('button', { name: /Con atención/ }))
+    fireEvent.click(screen.getByRole('button', { name: /^Necesitan atención/ }))
     expect(screen.queryByText('ANA PÉREZ')).not.toBeInTheDocument()
     fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'ana' } })
     expect(screen.getByText('Ningún analista coincide con estos filtros.')).toBeVisible()
@@ -132,6 +132,23 @@ describe('Supervisor horizontal', () => {
     fireEvent.click(screen.getByRole('button', { name: 'Ordenar por vencidas' }))
     expect(screen.getByRole('button', { name: 'Ordenar por vencidas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
   })
+  it('cada número del resumen abre su lista en la tabla; solo una píldora a la vez (Miguel, 27/09)', () => {
+    render(<GestionDiariaSupervisor />)
+    const resumen = screen.getByRole('group', { name: 'Resumen del equipo' })
+    const pildora = (nombre: RegExp) => within(resumen).getByRole('button', { name: nombre })
+    expect(pildora(/^Todos 2$/)).toHaveAttribute('aria-pressed', 'true')
+    fireEvent.click(pildora(/^Necesitan atención 1$/))
+    expect(pildora(/^Necesitan atención/)).toHaveAttribute('aria-pressed', 'true')
+    expect(pildora(/^Todos/)).toHaveAttribute('aria-pressed', 'false')
+    expect(screen.getAllByRole('button', { name: /^Seleccionar a / }).map((b) => b.textContent)).toEqual(['BRUNO'])
+    fireEvent.click(pildora(/^Sin registro 2$/))
+    expect(pildora(/^Necesitan atención/)).toHaveAttribute('aria-pressed', 'false')
+    expect(screen.getAllByRole('button', { name: /^Seleccionar a / })).toHaveLength(2)
+    fireEvent.click(pildora(/^Con registro 0$/))
+    expect(screen.getByText('Ningún analista coincide con estos filtros.')).toBeVisible()
+    fireEvent.click(pildora(/^Con pendientes 1$/))
+    expect(screen.getAllByRole('button', { name: /^Seleccionar a / }).map((b) => b.textContent)).toEqual(['BRUNO'])
+  })
   it('seleccionar conserva foco, volver a pulsar no cierra y sólo la fila activa ofrece ir al detalle', () => {
     render(<GestionDiariaSupervisor />)
     const boton = screen.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' })
@@ -174,7 +191,7 @@ describe('Supervisor horizontal', () => {
     fireEvent.click(screen.getByRole('tab', { name: 'Resumen' }))
     fireEvent.click(screen.getByRole('button', { name: 'Ver llamadas del día de ANA PÉREZ' }))
     expect(screen.getByRole('button', { name: 'Página 1' })).toBeVisible()
-    expect(screen.getByRole('heading', { name: 'Registro de ANA PÉREZ' })).toHaveFocus()
+    expect(screen.getByRole('heading', { name: 'Actividad de hoy' })).toHaveFocus()
     expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: ['a1'], pestanaInicial: 'llamadas' }))
   })
   it('un fallo del resumen no desmonta el registro ni roba foco al recuperarse', () => {
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
index c275589c..843a0fdd 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/supervisor.tsx
@@ -14,9 +14,7 @@ import { PanelSupervisorAdaptable } from '@/components/gestion-diaria/panel-supe
 import { PanelVacio } from '@/components/common/estado-panel'
 import { Button } from '@/components/ui/button'
 import { Input } from '@/components/ui/input'
-import { Select } from '@/components/ui/select'
 import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
-import { FranjaCifras } from '@/components/gestion-diaria/franja-cifras'
 import { FranjaCortesSupervisor } from '@/components/gestion-diaria/franja-cortes-supervisor'
 import { AvisosEquipo } from '@/components/gestion-diaria/avisos-equipo'
 import { EstadoCortesEquipo } from '@/components/gestion-diaria/estado-cortes-equipo'
@@ -29,12 +27,23 @@ import './mi-equipo.css'
 
 const FECHA_JORNADA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })
 // «Atención» por gravedad (revisión Codex, 27/09): lo vencido primero.
+type Pildora = EstadoEquipo | 'atencion'
+const PILDORAS: readonly { valor: Pildora; etiqueta: string }[] = [
+  { valor: 'todos', etiqueta: 'Todos' }, { valor: 'con_registro', etiqueta: 'Con registro' },
+  { valor: 'sin_registro', etiqueta: 'Sin registro' }, { valor: 'con_pendientes', etiqueta: 'Con pendientes' },
+  { valor: 'atencion', etiqueta: 'Necesitan atención' },
+]
+/** El resumen del servidor usa las MISMAS reglas que el filtro (`resumenEquipo`): el número es la lista. */
+function conteoPildora(p: Pildora, r: { analistas: number; con_actividad: number; sin_actividad: number; con_pendientes: number }, atencion: number): number {
+  return p === 'todos' ? r.analistas : p === 'con_registro' ? r.con_actividad : p === 'sin_registro' ? r.sin_actividad
+    : p === 'con_pendientes' ? r.con_pendientes : atencion
+}
 const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false, gravedad: true }
 /**
  * Ancho mínimo de la pantalla para tener tabla y panel LADO A LADO: columnas
  * fijas de la tabla (68 + 132 + 56 + 72 + 156 = 484) + nombre con iniciales
  * (≥ 200) + rellenos y bordes (24) + canal de scroll (16) + separación (16) +
- * panel (360) = 1100. A 1440 con el menú abierto la pantalla mide ~1150: cabe.
+ * panel (360, su mínimo: crece hasta 440 con la pantalla) = 1100. A 1440 con el menú abierto la pantalla mide ~1150: cabe.
  * Por debajo, el detalle se abre encima como siempre. La tabla pasa a tarjetas
  * por debajo de 640 px (mi-equipo.css): nunca en línea. Solo del supervisor.
  */
@@ -90,6 +99,8 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
   const filas = filtrarOrdenarEquipo(equipo, filtros)
   const fila = equipo.find((f) => f.analista_id === seleccion?.analista)
   const atencion = equipo.filter((f) => f.requiere_atencion).length
+  const pildora: Pildora = filtros.soloProblemas ? 'atencion' : filtros.estado ?? 'todos'
+  const elegirPildora = (p: Pildora) => setFiltros((f) => ({ ...f, estado: p === 'atencion' ? 'todos' : p, soloProblemas: p === 'atencion' }))
   const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
   const fueraDeAmbito = seleccion !== null && (sinPermiso || (dia !== null && seleccion.analista !== null && !fila))
   const automatica = seleccion?.origen === 'automatica'
@@ -260,7 +271,7 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
       <header className="flex shrink-0 flex-wrap items-start justify-between gap-x-6 gap-y-3">
         <div className="min-w-0">
           <h2 ref={tituloEquipo} tabIndex={-1} className="rounded-md text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">{esHoy ? 'Mi equipo hoy' : 'Mi equipo'}</h2>
-          <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">Actividad registrada, pendientes y analistas que necesitan atención.</p>
+          <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">Actividad, pendientes y atención de tu equipo.</p>
         </div>
         <div className="flex min-w-0 flex-wrap items-center gap-2">
           {/* El selector ya dice la fecha: al lado solo va la hora de la foto. */}
@@ -274,6 +285,12 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
           </label>
           <button type="button" className={BOTON_CABECERA} aria-disabled={esHoy} onClick={() => { if (!esHoy) cambiarFecha(hoy) }}>Hoy</button>
           {accesoSeguimiento}
+          {/* Con cualquier foto válida, aunque no haya analistas (Codex, 27/09). */}
+          {dia && !consulta.error && !consulta.cargando && (
+            <button type="button" className={BOTON_CABECERA} onClick={abrirRegistroEquipo} aria-disabled={sinPermiso}>
+              <ClipboardList aria-hidden className="size-4" />Registro del equipo
+            </button>
+          )}
           {hora && <p className="whitespace-nowrap pl-1 text-xs tabular-nums text-[var(--muted-foreground-strong)]">Actualizado {hora}</p>}
           <button type="button" className={BOTON_CABECERA} aria-disabled={actualizando} aria-busy={actualizando} onClick={actualizar}>
             <RefreshCw className={cn('size-4', actualizando && 'motion-safe:animate-spin')} aria-hidden />{actualizando ? 'Actualizando…' : 'Actualizar'}
@@ -284,19 +301,7 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
         </div>
       </header>
 
-      {dia ? <FranjaCifras etiqueta="Resumen del equipo" disposicion="en-linea" className="shrink-0" cifras={[
-        { etiqueta: 'Analistas', valor: String(dia.resumen.analistas) },
-        { etiqueta: 'Con registro', valor: String(dia.resumen.con_actividad) },
-        { etiqueta: 'Sin registro', valor: String(dia.resumen.sin_actividad) },
-        { etiqueta: 'Con pendientes', valor: String(dia.resumen.con_pendientes) },
-        // Ámbar y no rojo: mezcla vencidas con cortes y tiempo sin llamar (Codex, 27/09).
-        { etiqueta: 'Necesitan atención', valor: String(atencion), tono: atencion > 0 ? 'aviso' : 'normal' },
-      ]} />
-        : <div role="group" aria-label="Resumen del equipo" className="shrink-0 rounded-2xl border border-border bg-card px-5 py-4 text-[13px] text-[var(--muted-foreground-strong)]">
-          <p>{consulta.error ? 'Resumen no disponible' : 'Consultando indicadores…'}</p>
-        </div>}
-
-      <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_360px]')}>
+      <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
         <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
           {consulta.error ? <div role="alert" className="flex flex-col items-start gap-3 p-6 text-[13.5px]">
             <h3 ref={tituloError} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">{sinPermiso ? 'Ya no tienes autorización para ver este equipo' : 'No pudimos consultar la actividad y los pendientes del equipo'}</h3>
@@ -305,32 +310,32 @@ function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string;
               onClick={() => { if (consulta.enVuelo) return; setReintentando(true); void consulta.recargar() }}>{reintentando ? 'Reintentando…' : 'Reintentar'}</Button>}
           </div> : consulta.cargando || !dia ? <p role="status" className="p-6 text-[13.5px] text-[var(--muted-foreground-strong)]">Consultando el equipo completo…</p>
             : <>
-              {/* La barra existe con cualquier foto válida: «Registro del equipo»
-                  sigue a mano aunque no haya analistas (Codex, 27/09). */}
-              <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
-                {dia.equipo.length > 0 && <>
-                  <label className="relative w-[220px] max-w-full"><span className="sr-only">Buscar analista</span>
-                    <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
-                    <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista…" className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
-                  </label>
-                  <div className="w-[170px]">
-                    <Select aria-label="Estado de actividad" value={filtros.estado} onChange={(e) => setFiltros((f) => ({ ...f, estado: e.target.value as EstadoEquipo }))} className={cn(CONTROL, 'min-h-0')}>
-                      <option value="todos">Todos los estados</option><option value="con_registro">Con registro</option><option value="sin_registro">Sin registro</option><option value="con_pendientes">Con pendientes</option>
-                    </Select>
-                  </div>
-                  <button type="button" aria-pressed={filtros.soloProblemas} onClick={() => setFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}
-                    className={cn('inline-flex h-9 cursor-pointer items-center gap-2 rounded-full border px-3.5 text-[13px] font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11',
-                      filtros.soloProblemas ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-foreground hover:bg-muted')}>
-                    {filtros.soloProblemas && <Check aria-hidden className="size-3.5" />}Con atención
-                    <span className={cn('grid min-w-5 place-items-center rounded-full px-1.5 text-[11px] font-bold tabular-nums',
-                      atencion > 0 ? 'bg-[var(--warning-text)] text-white' : 'bg-muted text-[var(--muted-foreground-strong)]')}>{atencion}</span>
-                  </button>
-                </>}
-                <button type="button" onClick={abrirRegistroEquipo} aria-disabled={sinPermiso}
-                  className="ml-auto inline-flex h-9 cursor-pointer items-center gap-1.5 rounded-md px-1 text-[13px] font-semibold text-[var(--accent-press)] hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50 pointer-coarse:h-11">
-                  <ClipboardList aria-hidden className="size-4" />Registro del equipo
-                </button>
-              </div>
+              {dia.equipo.length > 0 && <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
+                {/* El resumen del equipo SON los filtros: cada número abre su
+                    lista en la tabla (Miguel, 27/09: la jerarquía es de la tabla
+                    y de la ficha, no de un tablero de cifras). */}
+                <div role="group" aria-label="Resumen del equipo" className="flex flex-wrap items-center gap-1.5">
+                  {PILDORAS.map((p) => {
+                    const activa = pildora === p.valor
+                    const n = conteoPildora(p.valor, dia.resumen, atencion)
+                    return (
+                      <button key={p.valor} type="button" aria-pressed={activa} onClick={() => elegirPildora(p.valor)}
+                        className={cn('inline-flex h-9 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-full border px-3 text-[13px] font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11',
+                          activa ? 'border-accent bg-accent text-accent-foreground' : 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-border-strong hover:text-primary')}>
+                        {activa && <Check aria-hidden className="size-3.5" />}{p.etiqueta}{' '}
+                        {p.valor === 'atencion' && n > 0
+                          // Ámbar y no rojo: mezcla vencidas con cortes y tiempo sin llamar (Codex, 27/09).
+                          ? <span className="grid min-w-5 place-items-center rounded-full bg-[var(--warning-text)] px-1.5 text-[11px] font-bold tabular-nums text-white">{n}</span>
+                          : <span className="font-bold tabular-nums">{n}</span>}
+                      </button>
+                    )
+                  })}
+                </div>
+                <label className="relative ml-auto min-w-40 max-w-[220px] flex-1"><span className="sr-only">Buscar analista</span>
+                  <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
+                  <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista…" className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
+                </label>
+              </div>}
               {dia.equipo.length === 0
                 ? <PanelVacio icono={Users} titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
                 : <>
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
