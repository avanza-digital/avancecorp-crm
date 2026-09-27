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

# Encargo: AUDITAR la F2 + F3 del «Hoy» del supervisor y VERIFICAR los arreglos de tu revisión de la F1 — LEVEL 2

Contexto: el dueño aprobó ejecutar todas las fases con Codex auditando todo el código. Tu revisión
de la F1 fue CHANGES_REQUESTED (3 P1 + 2 P2): los 5 se aceptaron y se arreglaron en el commit
605ac085 (junto con la F3). Aquí van:
- F2 (commit 40654da1): banda «Decide primero» — hasta 3 tarjetas (tresCosasDeHoy con la entrada
  del seguimiento activo), desplegable «Esta semana», fail-closed por fuente.
- F3 (commit 605ac085): franja «Consulta» + diálogo «Detalle» (Radix, components/ui/dialog.tsx).
- Arreglos de tu F1 (commit 605ac085): (1) página exige `control_revision` igual al modo;
  (2) `lecturaAnalista` evalúa la agenda aunque `activos === 0`; (3) la franja clásica usa
  `agendaConfirmada`; (4) «Sin alertas» solo con agenda confirmada; (5) `analistaId` vigente se
  valida contra el roster y el remonte incluye identidad.
Todavía NO está enrutada (F4 conectará hoy.tsx y actualizará el e2e).

VERIFICACIÓN YA CORRIDA por el PRIMARY en el working tree (no la repitas; júzgala):
- `tsc -b` (typecheck del proyecto): PASS (pre-commit). `oxlint`: PASS.
- `vitest` de `src/screens/hoy/` + `src/lib/`: 2500/2500 PASS (tras corregir 1 aserción de test).
- `supervisor-mando.test.tsx`: 36/36 PASS; `supervisor.test.tsx`: 49/49 PASS.

Pregunta explícita: ¿alguno de tus 5 hallazgos quedó mal cerrado? Y busca bugs nuevos de la F2/F3:
estados fail-closed de «Decide primero», la interacción tarjeta ↔ pestaña de la cola, a11y del
desplegable «Esta semana» (popover no modal), del diálogo y de las tarjetas, textos sin jerga, y
cualquier pérdida frente a la pantalla clásica (transcrita). Si algo está bien, no lo menciones.

## DIFF F2 + F3 + arreglos (bc97b98d..605ac085)
```diff
diff --git a/CRM-Avance-Corp/app/src/lib/senal-equipo.test.ts b/CRM-Avance-Corp/app/src/lib/senal-equipo.test.ts
index 2051ab45..5bd06234 100644
--- a/CRM-Avance-Corp/app/src/lib/senal-equipo.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/senal-equipo.test.ts
@@ -4,9 +4,19 @@ import { conteoSemaforoEquipo, lecturaAnalista } from './senal-equipo'
 const sinRezago = { no_asistio: 0, leads_sin_accion: 0, vencidas: 0 }
 
 describe('lecturaAnalista', () => {
-  it('sin cartera abierta es NEUTRO y no enseña señales (no hay nada que medir)', () => {
-    expect(lecturaAnalista({ activos: 0, diasSinActividadMax: 9 }, { no_asistio: 3, leads_sin_accion: 2, vencidas: 1 }))
-      .toEqual({ nivel: 'neutro', senales: [] })
+  it('sin cartera abierta NI señales de agenda es NEUTRO (no hay nada que medir)', () => {
+    expect(lecturaAnalista({ activos: 0, diasSinActividadMax: 9 }, sinRezago)).toEqual({ nivel: 'neutro', senales: [] })
+    expect(lecturaAnalista({ activos: 0, diasSinActividadMax: 0 }, null)).toEqual({ nivel: 'neutro', senales: [] })
+  })
+
+  it('sin cartera abierta la AGENDA sigue mandando: un no-show repetido no desaparece (Codex F1)', () => {
+    const l = lecturaAnalista({ activos: 0, diasSinActividadMax: 9 }, { no_asistio: 3, leads_sin_accion: 0, vencidas: 1 })
+    expect(l.nivel).toBe('critico')
+    // Los días sin actividad no cuentan sin leads abiertos.
+    expect(l.senales).toEqual([
+      { texto: '3 citas sin asistir', nivel: 'critico' },
+      { texto: '1 tarea vencida', nivel: 'atencion' },
+    ])
   })
 
   it('con actividad fresca y sin rezago no hay señal', () => {
diff --git a/CRM-Avance-Corp/app/src/lib/senal-equipo.ts b/CRM-Avance-Corp/app/src/lib/senal-equipo.ts
index 7629bfb7..90ef4538 100644
--- a/CRM-Avance-Corp/app/src/lib/senal-equipo.ts
+++ b/CRM-Avance-Corp/app/src/lib/senal-equipo.ts
@@ -10,7 +10,10 @@
 // · citas sin asistir: ≥2 rojo (una sola no es patrón);
 // · leads sin próxima acción: ≥1 ámbar · ≥5 rojo (umbral de la campana);
 // · tareas vencidas: ámbar.
-// La severidad del analista es la PEOR de sus señales: nunca se rebaja.
+// La severidad del analista es la PEOR de sus señales: nunca se rebaja. Las
+// señales de AGENDA valen aunque su cartera abierta haya llegado a cero (un
+// patrón de no-shows de esta semana no desaparece por cerrar leads); solo la de
+// días sin actividad exige leads abiertos. Neutro = sin cartera Y sin señales.
 import type { MetricaAgendaVendedor } from './metricas-agenda'
 import { haceTexto } from './inteligencia'
 
@@ -38,7 +41,6 @@ export function lecturaAnalista(
   fila: { activos: number; diasSinActividadMax: number },
   rezago: RezagoAgenda | null | undefined,
 ): LecturaAnalista {
-  if (fila.activos === 0) return { nivel: 'neutro', senales: [] }
   const senales: SenalAnalista[] = []
   if (rezago != null && rezago.no_asistio >= 2) {
     senales.push({ texto: `${rezago.no_asistio} citas sin asistir`, nivel: 'critico' })
@@ -51,7 +53,7 @@ export function lecturaAnalista(
     })
   }
   const dias = fila.diasSinActividadMax
-  if (dias >= 2) {
+  if (fila.activos > 0 && dias >= 2) {
     senales.push({ texto: `Un lead sin actividad ${haceTexto(dias)}`, nivel: dias > 5 ? 'critico' : 'atencion' })
   }
   if (rezago != null && rezago.vencidas > 0) {
@@ -60,8 +62,8 @@ export function lecturaAnalista(
   }
   // sort estable: las rojas suben y cada nivel conserva el orden de arriba.
   senales.sort((a, b) => (a.nivel === b.nivel ? 0 : a.nivel === 'critico' ? -1 : 1))
-  const nivel = senales.length === 0 ? null : senales[0]?.nivel ?? null
-  return { nivel, senales }
+  if (senales.length === 0) return { nivel: fila.activos === 0 ? 'neutro' : null, senales }
+  return { nivel: senales[0]?.nivel ?? null, senales }
 }
 
 /** Conteo EXCLUSIVO de la cabecera: cada analista cuenta una sola vez. */
diff --git a/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts b/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts
index 867012f7..d478d8e9 100644
--- a/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts
@@ -1,5 +1,5 @@
 import { describe, expect, it } from 'vitest'
-import { candidatosDeHoy, tresCosasDeHoy, type TresCosasInput } from './tres-cosas'
+import { candidatosDeHoy, partesDeCosa, tresCosasDeHoy, type TresCosasInput } from './tres-cosas'
 import type { ColaAccionOperativa } from './cola-accion'
 import type { ItemCola } from './inteligencia'
 import type { MetricaAgendaVendedor } from './metricas-agenda'
@@ -243,3 +243,18 @@ describe('candidatosDeHoy + seguimiento activo (27/09/2026)', () => {
     for (const cosa of agrupadas) expect(cosa).not.toHaveProperty('vendedorId')
   })
 })
+
+describe('partesDeCosa', () => {
+  it('separa la cifra inicial del título', () => {
+    expect(partesDeCosa('4 primeras gestiones vencidas')).toEqual({ cifra: '4', resto: 'primeras gestiones vencidas' })
+    expect(partesDeCosa('50+ sin movimiento · el peor lleva 9 días')).toEqual({ cifra: '50+', resto: 'sin movimiento · el peor lleva 9 días' })
+  })
+
+  it('con dueño, la cifra sale de detrás del nombre y el nombre va al final', () => {
+    expect(partesDeCosa('KAREN ZAPATA: 2 citas sin asistir')).toEqual({ cifra: '2', resto: 'citas sin asistir · Karen' })
+  })
+
+  it('sin número no inventa cifra', () => {
+    expect(partesDeCosa('Revisar el equipo')).toEqual({ cifra: null, resto: 'Revisar el equipo' })
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/tres-cosas.ts b/CRM-Avance-Corp/app/src/lib/tres-cosas.ts
index beb042ab..bddedf7a 100644
--- a/CRM-Avance-Corp/app/src/lib/tres-cosas.ts
+++ b/CRM-Avance-Corp/app/src/lib/tres-cosas.ts
@@ -22,6 +22,7 @@
 //   conteo del seguimiento (`primeraGestionPendiente`, 27/09/2026).
 import type { MetricaAgendaVendedor } from './metricas-agenda'
 import { haceTexto } from './inteligencia'
+import { primerNombre } from './format'
 import { TOPE_ESTANCADOS, type ColaAccionOperativa } from './cola-accion'
 
 /** Pestaña de la cola a la que salta una cosa (espejo del tablist de HOY). */
@@ -203,3 +204,17 @@ export function candidatosDeHoy({
     || PESO[a.id] - PESO[b.id]
   ))
 }
+
+/**
+ * Cifra y título de una cosa para pintarla en grande (Hoy del supervisor,
+ * puesto de mando): «4 primeras gestiones vencidas» → 4 + «primeras gestiones
+ * vencidas»; «KAREN ZAPATA: 2 citas sin asistir» → 2 + «citas sin asistir ·
+ * Karen». Sin número, sin cifra: el texto queda entero.
+ */
+export function partesDeCosa(texto: string): { cifra: string | null; resto: string } {
+  const inicial = /^(\d+\+?)\s+(.*)$/.exec(texto)
+  if (inicial) return { cifra: inicial[1] ?? null, resto: inicial[2] ?? texto }
+  const deAnalista = /^(.+?):\s+(\d+\+?)\s+(.*)$/.exec(texto)
+  if (deAnalista) return { cifra: deAnalista[2] ?? null, resto: `${deAnalista[3] ?? ''} · ${primerNombre(deAnalista[1])}` }
+  return { cifra: null, resto: texto }
+}
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx
index ffa912c9..ead774f1 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx
@@ -362,63 +362,77 @@ export function GestionDiariaAnalista({ accesoSeguimiento }: { accesoSeguimiento
       })() : undefined} />
   )
 
+  // Con teléfono en pantalla (el día cargado, o una llamada en curso aunque el
+  // día se haya caído), desde `lg` el teléfono ocupa TODO el alto a la
+  // izquierda, desde la altura del título, y el título, los avisos, las cifras
+  // y las pestañas van a la derecha (Miguel, 27/09: «que el teléfono sea más
+  // largo»). El orden del DOM no cambia —título, avisos, cifras, teléfono,
+  // pestañas—: el lector de pantalla y el tabulador recorren lo mismo que antes.
+  const conTelefono = dia.dia !== null || sesion !== null
+
   return (
-    <div className="mx-auto flex w-full max-w-[1440px] flex-col gap-4 lg:h-[calc(100svh-7rem)] lg:min-h-[640px]">
-      <header className="flex shrink-0 flex-wrap items-end justify-between gap-x-4 gap-y-3">
-        <div className="min-w-0 flex-1 basis-80">
+    <div className={cn('mx-auto grid w-full max-w-[1440px] content-start gap-4 lg:h-[calc(100svh-7rem)] lg:min-h-[640px]',
+      conTelefono && 'lg:grid-cols-[430px_minmax(0,1fr)] lg:grid-rows-[auto_minmax(0,1fr)]')}>
+      <div className={cn('flex min-w-0 flex-col gap-4', conTelefono && 'lg:col-start-2 lg:row-start-1')}>
+        {/* El título comparte fila con la fecha y los botones, y el subtítulo va
+            debajo a todo el ancho (`order-last`): en la columna derecha no cabían
+            lado a lado. El DOM conserva título → subtítulo → botones. */}
+        <header className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1.5">
           <h2 ref={encabezado} tabIndex={-1} className="text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary">¿A quién llamo ahora?</h2>
-          <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">
+          <p className="order-last basis-full text-[13px] text-[var(--muted-foreground-strong)]">
             Llama, guarda el resultado y pasas al siguiente. {corte ? `Corte ${corte}` : 'Sin corte confirmado'} · se actualiza cada minuto.
           </p>
-        </div>
-        <div className="flex min-w-0 flex-wrap items-center gap-3">
-          <span className="text-[13px] text-foreground/80 first-letter:uppercase">{fecha}</span>
-          {accesoSeguimiento}
-          <button type="button" aria-label="Actualizar" title="Actualizar" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
-            className="grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] border border-border bg-card text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
-            onClick={() => { if (dia.enVuelo) return; void dia.recargar(); if (!yo?.demo) void cola.refetch() }}>
-            <RefreshCw aria-hidden className={`size-4 ${dia.enVuelo ? 'motion-safe:animate-spin' : ''}`} />
-          </button>
-        </div>
-      </header>
+          <div className="flex min-w-0 flex-wrap items-center gap-3">
+            <span className="text-[13px] text-foreground/80 first-letter:uppercase">{fecha}</span>
+            {accesoSeguimiento}
+            <button type="button" aria-label="Actualizar" title="Actualizar" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
+              className="grid size-9 shrink-0 cursor-pointer place-items-center rounded-[10px] border border-border bg-card text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
+              onClick={() => { if (dia.enVuelo) return; void dia.recargar(); if (!yo?.demo) void cola.refetch() }}>
+              <RefreshCw aria-hidden className={`size-4 ${dia.enVuelo ? 'motion-safe:animate-spin' : ''}`} />
+            </button>
+          </div>
+        </header>
 
-      {dia.dia === null && sesion !== null ? (
-        // Con una llamada en curso, un refresco fallido (p. ej. al volver del
-        // marcador) NO desmonta «Ahora»: se perdería el formulario a medio llenar.
-        // Se avisa y se sigue pintando la sesión; lo demás espera a que vuelva.
-        <>
+        {dia.dia === null && sesion !== null ? (
+          // Con una llamada en curso, un refresco fallido (p. ej. al volver del
+          // marcador) NO desmonta «Ahora»: se perdería el formulario a medio llenar.
+          // Se avisa y se sigue pintando la sesión; lo demás espera a que vuelva.
           <p role="alert" className="shrink-0 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
             No se pudo actualizar tu día. Termina de registrar a {primerNombre(sesion.lead.nombre_completo)}: lo demás vuelve en cuanto se recupere la conexión.
           </p>
-          <div className="flex min-h-0 flex-1 flex-col gap-4 lg:flex-row">{tarjetaAhora}</div>
-        </>
-      ) : dia.error != null && dia.dia === null ? (
-        <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
-      ) : dia.dia === null && dia.cargando ? (
-        <PanelCargando filas={6} />
-      ) : dia.dia === null ? (
-        <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
-      ) : (
-        <>
-          {/* Los avisos que cambian la decisión de marcar van FUERA de las
-              pestañas: se ven siempre, esté abierta la que esté. */}
-          {colaCaida && (
-            <p role="alert" className="shrink-0 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
-              No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
-            </p>
-          )}
-          {dia.dia.cartera_truncada && (
-            <p role="status" className="shrink-0 text-[13px] font-semibold text-[var(--muted-foreground-strong)]">
-              Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
-            </p>
-          )}
-
-          <FranjaCifras etiqueta="Tu día en cifras" cifras={cifrasDelDia(dia.dia)} className="shrink-0" />
+        ) : dia.dia !== null && (
+          <>
+            {/* Los avisos que cambian la decisión de marcar van FUERA de las
+                pestañas: se ven siempre, esté abierta la que esté. */}
+            {colaCaida && (
+              <p role="alert" className="shrink-0 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
+                No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
+              </p>
+            )}
+            {dia.dia.cartera_truncada && (
+              <p role="status" className="shrink-0 text-[13px] font-semibold text-[var(--muted-foreground-strong)]">
+                Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
+              </p>
+            )}
 
-          <div className="flex min-h-0 flex-1 flex-col gap-4 lg:flex-row">
-            {tarjetaAhora}
+            <FranjaCifras etiqueta="Tu día en cifras" cifras={cifrasDelDia(dia.dia)} />
+          </>
+        )}
+      </div>
 
-            <section aria-label="Tu cola y tu actividad" className="flex min-h-[520px] min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-border bg-card lg:min-h-0">
+      {!conTelefono ? (
+        dia.error != null ? (
+          <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
+        ) : dia.cargando ? (
+          <PanelCargando filas={6} />
+        ) : (
+          <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
+        )
+      ) : (
+        <>
+          {tarjetaAhora}
+          {dia.dia !== null && (
+            <section aria-label="Tu cola y tu actividad" className="flex min-h-[520px] min-w-0 flex-col overflow-hidden rounded-2xl border border-border bg-card lg:col-start-2 lg:row-start-2 lg:min-h-0">
               <Tabs
                 etiqueta="Qué ver"
                 variante="subrayado"
@@ -453,10 +467,9 @@ export function GestionDiariaAnalista({ accesoSeguimiento }: { accesoSeguimiento
                 )}
               </Tabs>
             </section>
-          </div>
+          )}
         </>
       )}
-
     </div>
   )
 }
@@ -538,7 +551,7 @@ function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaid
     return () => nodo.removeEventListener('focusin', alEntrar)
   }, [])
   return (
-    <div className="flex min-h-0 shrink-0 justify-center lg:w-[430px]">
+    <div className="flex min-h-0 justify-center lg:col-start-1 lg:row-span-2 lg:row-start-1 lg:w-[430px]">
       <section ref={enlazarSeccion} aria-labelledby={`${id}-ahora`}
         className="flex w-full max-w-[384px] flex-col overflow-clip rounded-[32px] border border-border-strong bg-card shadow-[0_10px_28px_rgb(17_30_61/0.10)] lg:h-full">
         <div className="shrink-0 bg-primary text-primary-foreground">
@@ -550,7 +563,7 @@ function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaid
           </div>
         </div>
         {fila === null ? (
-          <p className="flex-1 px-6 py-8 text-center text-sm leading-relaxed text-[var(--muted-foreground-strong)]">
+          <p className="grid flex-1 place-items-center px-6 py-8 text-center text-sm leading-relaxed text-[var(--muted-foreground-strong)]">
             {cargando ? 'Buscando a quién llamar…'
               : colaCaida ? 'No se pudo leer tu cola: no sabemos a quién te toca llamar. Pulsa «Actualizar».'
                 : filtroVacio ? 'Nada en este filtro. Vuelve a «Todo» para ver a quién llamar.'
@@ -576,8 +589,18 @@ function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaid
                 {fila.senal === null ? 'Historial no cargado. Ábrelo en la ficha antes de llamar.' : detalleDeFila(fila, sinConversacionDias)}
               </p>
             </div>}
-            {lead !== null && <p className={cn('text-center font-extrabold tracking-[0.02em] tabular-nums text-primary', registro !== undefined ? 'text-xl' : 'text-2xl')}>{lead.telefono}</p>}
-            {registro !== undefined ? registro : <div className="relative">
+            {registro !== undefined ? (
+              <>
+                {lead !== null && <p className="text-center text-xl font-extrabold tracking-[0.02em] tabular-nums text-primary">{lead.telefono}</p>}
+                {registro}
+              </>
+            ) : (
+            // En reposo, el número y las acciones bajan al PIE, como en una
+            // pantalla de llamada: arriba quién es, abajo cómo llamarlo. Con el
+            // teléfono a todo el alto, el aire queda en medio y no bajo «Llamar».
+            <div className="mt-auto flex flex-col gap-3.5">
+            {lead !== null && <p className="text-center text-2xl font-extrabold tracking-[0.02em] tabular-nums text-primary">{lead.telefono}</p>}
+            <div className="relative">
               {lead !== null ? (
                 // `key={lead.id}`: UNA instancia por lead. Antes las acciones
                 // vivían dentro de cada fila y se desmontaban con ella; aquí hay
@@ -610,7 +633,9 @@ function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaid
                   <DropdownItem className="min-h-11 text-base" onSelect={onAbrirFicha}>Ver la ficha completa</DropdownItem>
                 </DropdownMenu>
               </div>
-            </div>}
+            </div>
+            </div>
+            )}
           </div>
         )}
         {registro === undefined && <p className="shrink-0 border-t border-border px-5 pb-1.5 pt-3 text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
index 4e7acbe7..27c4c5cc 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
@@ -96,6 +96,10 @@ vi.mock('@/data/sla-operacion-queries', () => ({
 
 const { HoySupervisorMando } = await import('./supervisor-mando')
 
+/** Cada render pide la cola (con el filtro por analista) y luego la del equipo (sin él). */
+const pedidoCola = () => pedidosCola.at(-2)
+const pedidoEquipo = () => pedidosCola.at(-1)
+
 const KAREN = 'aaaaaaaa-0000-4000-8000-000000000001'
 const JORGE = 'aaaaaaaa-0000-4000-8000-000000000002'
 
@@ -230,7 +234,8 @@ describe('Hoy · supervisor — puesto de mando: qué pantalla se elige', () =>
 describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', () => {
   it('ESTADO DE PRODUCCIÓN: la cola sale del seguimiento con 7 filas, conteos del servidor y enlace al módulo', () => {
     montar()
-    expect(pedidosCola.at(-1)).toEqual({ filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7, habilitada: true })
+    expect(pedidoCola()).toEqual({ filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7, habilitada: true })
+    expect(pedidoEquipo()).toEqual(pedidoCola())
     expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
     const pestanas = screen.getByRole('tablist', { name: 'Filtrar los pendientes' })
     expect(within(pestanas).getByRole('tab', { name: 'Para atender ahora: 3' })).toHaveAttribute('aria-selected', 'true')
@@ -278,7 +283,9 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     // Solo analistas activos del equipo, sin conteos inventados en el cliente.
     expect(within(chips).getAllByRole('button').map((b) => b.textContent)).toEqual(['Todos', 'Jorge', 'Karen'])
     fireEvent.click(within(chips).getByRole('button', { name: 'KAREN ZAPATA' }))
-    expect(pedidosCola.at(-1)?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: KAREN })
+    expect(pedidoCola()?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: KAREN })
+    // Las decisiones siguen mirando a TODO el equipo.
+    expect(pedidoEquipo()?.filtros.analista_id).toBeNull()
     expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
     expect(screen.getByRole('tab', { name: 'Para atender ahora: 2' })).toBeInTheDocument()
     expect(screen.getByText('Mostrando los pendientes de Karen')).toHaveAttribute('aria-live', 'polite')
@@ -286,7 +293,7 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     const filas = within(screen.getByRole('list', { name: /Pendientes de Karen/ })).getAllByRole('listitem')
     expect(filas).toHaveLength(2)
     fireEvent.click(within(chips).getByRole('button', { name: 'Todos' }))
-    expect(pedidosCola.at(-1)?.filtros.analista_id).toBeNull()
+    expect(pedidoCola()?.filtros.analista_id).toBeNull()
   })
 
   it('las flechas recorren las pestañas, mueven el foco y piden la señal al servidor', () => {
@@ -297,7 +304,7 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     const segunda = screen.getByRole('tab', { name: /Primera gestión/ })
     expect(segunda).toHaveAttribute('aria-selected', 'true')
     expect(segunda).toHaveFocus()
-    expect(pedidosCola.at(-1)?.filtros.senal).toBe('primera_atencion')
+    expect(pedidoCola()?.filtros.senal).toBe('primera_atencion')
     fireEvent.keyDown(segunda, { key: 'End' })
     expect(screen.getByRole('tab', { name: /^Todas/ })).toHaveAttribute('aria-selected', 'true')
     // Con «Todas» abierta, su total sí es del servidor.
@@ -317,6 +324,27 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     expect(REFETCH_COLA).toHaveBeenCalledTimes(1)
   })
 
+  it('una página de OTRA revisión de reglas (caché) no se pinta mientras refresca', () => {
+    RESPONDER = (filtros) => ({ data: pagina(colaTodo(), { filtros: { ...filtros }, control_revision: 1 }), error: null, isFetching: true })
+    MODO.data = { control_revision: 2 }
+    montar()
+    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
+    expect(screen.getByText('Actualizando los pendientes con las reglas vigentes…')).toBeInTheDocument()
+    // Las decisiones tampoco usan esos conteos viejos.
+    expect(screen.queryByRole('button', { name: /primera gestión vencida/ })).not.toBeInTheDocument()
+  })
+
+  it('si el analista elegido sale del equipo, la cola deja de filtrarse por su id', () => {
+    const { rerender } = montar()
+    fireEvent.click(screen.getByRole('button', { name: 'KAREN ZAPATA' }))
+    expect(pedidoCola()?.filtros.analista_id).toBe(KAREN)
+    VENDEDORES = VENDEDORES.filter((m) => m.perfil_id !== KAREN)
+    rerender(<HoySupervisorMando />)
+    expect(pedidoCola()?.filtros.analista_id).toBeNull()
+    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
+    expect(screen.getByRole('button', { name: 'Todos' })).toHaveAttribute('aria-pressed', 'true')
+  })
+
   it('una respuesta que ya no es del modo activo no se pinta como vigente', () => {
     RESPONDER = () => ({ data: pagina(colaTodo(), { modo: 'legado' }), error: null, isFetching: false })
     montar()
@@ -373,7 +401,7 @@ describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
     expect(detalle).toHaveTextContent('1 tarea vencida')
     expect(detalle).toHaveTextContent('9 toques en 7 días · 50 % completadas')
     // Y filtra la cola a sus pendientes.
-    expect(pedidosCola.at(-1)?.filtros.analista_id).toBe(KAREN)
+    expect(pedidoCola()?.filtros.analista_id).toBe(KAREN)
     expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
   })
 
@@ -386,10 +414,15 @@ describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
     expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
   })
 
-  it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día»', () => {
+  it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día» ni «Sin alertas»', () => {
     AGENDA_ERROR = new Error('agenda caída')
+    // Todos con actividad fresca: sin agenda, cero señales es DESCONOCIDO.
+    LEADS = [
+      lead({ creado_en: '2026-09-26T14:00:00Z' }),
+      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
+    ]
     montar()
-    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
+    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
     const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('La agenda del equipo no respondió'))
     expect(alerta).toBeDefined()
     fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
@@ -398,8 +431,200 @@ describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
     expect(equipo).not.toHaveTextContent('Al día')
   })
 
+  it('«Sin alertas» solo con la agenda confirmada y todos sin señal', () => {
+    LEADS = [
+      lead({ creado_en: '2026-09-26T14:00:00Z' }),
+      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
+    ]
+    montar()
+    expect(screen.getByText('Sin alertas en el equipo')).toBeInTheDocument()
+  })
+
+  it('mientras la agenda carga tampoco afirma «Sin alertas»', () => {
+    METRICAS_AGENDA = undefined
+    LEADS = [lead({ creado_en: '2026-09-26T14:00:00Z' })]
+    montar()
+    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
+  })
+
+  it('un analista sin leads abiertos conserva su alerta roja de agenda', () => {
+    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', no_asistio: 3 }])
+    montar()
+    const jorge = within(screen.getByRole('list', { name: 'Analistas del equipo' })).getByRole('button', { name: /JORGE HUAMÁN/ })
+    expect(jorge).toHaveTextContent('3 citas sin asistir')
+    expect(within(jorge).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
+  })
+
   it('el enlace de la cabecera lleva a «Mi equipo hoy»', () => {
     montar()
     expect(screen.getByRole('link', { name: 'Mi equipo hoy →' })).toHaveAttribute('href', '#/gestion-diaria')
   })
 })
+
+describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
+  const conAgendaYReparto = () => {
+    METRICAS_AGENDA = agenda([
+      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, leads_sin_accion: 1 },
+      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 3 },
+    ])
+    // Un lead SIN analista: el reparto lo cuenta el resumen (espejo del RPC).
+    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
+  }
+
+  it('ESTADO DE PRODUCCIÓN: tres tarjetas, el rojo primero, cifra grande y la severidad en texto', () => {
+    conAgendaYReparto()
+    montar()
+    expect(screen.getByRole('heading', { name: 'Decide primero' })).toBeInTheDocument()
+    const tarjetas = document.querySelectorAll('[data-decision]')
+    // Rojo primero; entre los ámbar manda el peso fijo: el reparto antes que «sin próxima acción».
+    expect([...tarjetas].map((t) => t.getAttribute('data-decision'))).toEqual(['primera_gestion', 'no_asistio', 'por_repartir'])
+    const primera = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
+    expect(primera).toHaveTextContent('1')
+    expect(primera).toHaveTextContent('primera gestión vencida')
+    expect(screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })).toHaveTextContent('citas sin asistir · Karen')
+    // Lo que no entra en tres, a «Esta semana».
+    expect(screen.getByRole('button', { name: /Esta semana · 1/ })).toBeInTheDocument()
+  })
+
+  it('la primera gestión filtra la cola a ESA pestaña para todo el equipo; el segundo clic la devuelve', () => {
+    montar()
+    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
+    const tarjeta = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
+    fireEvent.click(tarjeta)
+    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
+    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!)).toHaveTextContent('Revisa la primera gestión con cada analista')
+    expect(screen.getByRole('tab', { name: /Primera gestión/ })).toHaveAttribute('aria-selected', 'true')
+    expect(pedidoCola()?.filtros).toEqual({ senal: 'primera_atencion', etapa: null, analista_id: null })
+    fireEvent.click(tarjeta)
+    expect(tarjeta).toHaveAttribute('aria-expanded', 'false')
+    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveAttribute('aria-selected', 'true')
+  })
+
+  it('«Ver» lleva a la cola y le pasa el foco a la pestaña', () => {
+    montar()
+    fireEvent.click(screen.getByRole('button', { name: 'Ver las 1 primera gestión vencida en la cola' }))
+    act(() => { vi.advanceTimersByTime(32) })
+    const pestana = screen.getByRole('tab', { name: /Primera gestión/ })
+    expect(pestana).toHaveAttribute('aria-selected', 'true')
+    expect(pestana).toHaveFocus()
+  })
+
+  it('citas sin asistir NO filtran la cola (no contiene esos casos): despliegan y llevan al día del equipo', () => {
+    conAgendaYReparto()
+    montar()
+    const antes = pedidoCola()?.filtros
+    const tarjeta = screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })
+    fireEvent.click(tarjeta)
+    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
+    expect(pedidoCola()?.filtros).toEqual(antes)
+    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!))
+      .toHaveTextContent('En 7 días: 2 sin asistir · 1 tareas vencidas · 1 sin próxima acción.')
+    expect(screen.getByRole('link', { name: 'Ver su día: KAREN ZAPATA: 2 citas sin asistir' })).toHaveAttribute('href', '#/gestion-diaria')
+  })
+
+  it('«Esta semana» lista lo que no entró, con su acción; Esc lo cierra y devuelve el foco', () => {
+    conAgendaYReparto()
+    montar()
+    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
+    fireEvent.click(disparador)
+    expect(disparador).toHaveAttribute('aria-expanded', 'true')
+    const lista = screen.getByRole('list', { name: 'Decisiones para esta semana' })
+    expect(lista).toHaveTextContent('Esta semana: JORGE HUAMÁN: 3 leads sin próxima acción')
+    const verDia = within(lista).getByRole('link', { name: 'Ver su día: JORGE HUAMÁN: 3 leads sin próxima acción' })
+    expect(verDia).toHaveAttribute('href', '#/gestion-diaria')
+    verDia.focus()
+    fireEvent.keyDown(document, { key: 'Escape' })
+    expect(disparador).toHaveAttribute('aria-expanded', 'false')
+    expect(disparador).toHaveFocus()
+  })
+
+  it('el reparto como tarjeta conserva la etiqueta accesible del servidor', () => {
+    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
+    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
+    montar()
+    expect(screen.getByRole('link', { name: 'Repartir 1 lead pendiente' })).toHaveAttribute('href', '#/derivaciones')
+  })
+
+  it('con TODAS las fuentes confirmadas y nada pendiente dice «Nada que decidir»', () => {
+    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
+    montar()
+    expect(screen.getByText('Nada que decidir ahora mismo.')).toBeInTheDocument()
+    expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
+  })
+
+  it('mientras el seguimiento carga no afirma que no hay nada: «Revisando…»', () => {
+    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
+    montar()
+    expect(screen.getByText('Revisando las decisiones del día…')).toBeInTheDocument()
+    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
+  })
+
+  it('fail-closed: con el seguimiento o la agenda caídos lo dice, deja reintentar y nunca «Nada que decidir»', () => {
+    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: new Error('caído'), isFetching: false })
+    AGENDA_ERROR = new Error('agenda caída')
+    montar()
+    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('Algunas decisiones no se pudieron confirmar'))
+    expect(alerta).toHaveTextContent('no respondió el seguimiento ni la agenda')
+    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
+    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
+    expect(REFETCH_COLA).toHaveBeenCalled()
+    expect(REFETCH_AGENDA).toHaveBeenCalled()
+  })
+
+  it('sin el modo activo confirmado no hay banda de decisiones', () => {
+    MODO.activo = false
+    MODO.data = undefined
+    montar()
+    expect(screen.queryByRole('heading', { name: 'Decide primero' })).not.toBeInTheDocument()
+  })
+})
+
+describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () => {
+  it('ESTADO DE PRODUCCIÓN (sin metas publicadas): la franja da cifras con «—» donde no hay dato y sin jerga', () => {
+    METRICAS_AGENDA = agenda([
+      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', toques: 6, completadas: 3, no_asistio: 1, pct_completadas: 75 },
+      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', toques: 4, completadas: 0, no_asistio: 1 },
+    ])
+    montar()
+    const cifras = screen.getByRole('list', { name: 'Cifras del equipo' })
+    expect(cifras).toHaveTextContent('S/ 20k pronóstico · +US$ 15k aparte')
+    expect(cifras).toHaveTextContent('2 leads activos')
+    // Sin meta publicada no hay % de meta que inventar.
+    expect(cifras).toHaveTextContent('— de la meta')
+    expect(cifras).toHaveTextContent('— conversión del mes')
+    expect(cifras).toHaveTextContent('10 toques en 7 días')
+    expect(cifras).toHaveTextContent('60 % completadas')
+    // 2 no asistió en el equipo: el número va en rojo de TEXTO, con su palabra al lado.
+    const itemNoAsistio = within(cifras).getAllByRole('listitem').find((li) => li.textContent === '2 no asistió')!
+    expect(itemNoAsistio.querySelector('strong')).toHaveStyle({ color: 'var(--destructive-text)' })
+    expect(document.body).not.toHaveTextContent(/pipeline|suma÷suma|solo producción/i)
+  })
+
+  it('«Detalle» abre un diálogo con TODO lo que la pantalla clásica mostraba; Esc lo cierra y el foco vuelve', () => {
+    vi.useRealTimers()
+    montar()
+    const boton = screen.getByRole('button', { name: 'Detalle' })
+    boton.focus()
+    fireEvent.click(boton)
+    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
+    for (const kpi of ['Pronóstico de capital abierto', 'Leads activos del equipo', 'Primeras gestiones vencidas', 'Por repartir']) {
+      expect(within(dialogo).getByText(kpi)).toBeInTheDocument()
+    }
+    expect(within(dialogo).getByText('Revísalas con cada analista')).toBeInTheDocument()
+    expect(within(dialogo).getByRole('heading', { name: 'Cumplimiento del mes' })).toBeInTheDocument()
+    expect(within(dialogo).getAllByText('Sin meta fijada para este mes').length).toBeGreaterThan(0)
+    expect(within(dialogo).getByRole('region', { name: 'Agenda del equipo' })).toBeInTheDocument()
+    expect(within(dialogo).getByText(/Ves solo a tu equipo/)).toBeInTheDocument()
+    expect(within(dialogo).getByRole('link', { name: 'Ver derivaciones; bandeja sin pendientes' })).toHaveAttribute('href', '#/derivaciones')
+    fireEvent.keyDown(dialogo, { key: 'Escape' })
+    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
+  })
+
+  it('«Cerrar» también cierra el detalle', () => {
+    vi.useRealTimers()
+    montar()
+    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
+    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cerrar' }))
+    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
index b3c9443f..82c45046 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
@@ -11,30 +11,39 @@
 // Modo legado (demo, o seguimiento apagado por gerencia) → la pantalla
 // clásica ./supervisor.tsx, que sigue siendo también el rollback de una línea.
 // Meta, reparto, agenda y TC: ./datos-supervisor.ts, compartido con ella.
-import { useId, useMemo, useState, type JSX } from 'react'
-import { ChevronRight, ListChecks, RefreshCw, UsersRound } from 'lucide-react'
+import { useEffect, useId, useMemo, useRef, useState, type JSX } from 'react'
+import { AlertTriangle, ChevronRight, Inbox, ListChecks, RefreshCw, Target, Users, UsersRound, Wallet } from 'lucide-react'
 import { Card, CardContent } from '@/components/ui/card'
 import { Avatar } from '@/components/ui/avatar'
 import { Badge } from '@/components/ui/badge'
 import { Button } from '@/components/ui/button'
+import { Progress } from '@/components/ui/progress'
+import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
+import { KpiCard } from '@/components/common/kpi-card'
 import { SectionHead } from '@/components/common/section-head'
+import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
 import { AccionesContacto } from '@/components/app/contacto'
 import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
 import { DesgloseMonedas } from '@/components/common/desglose-monedas'
 import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
 import { estadoCasoSupervision, momentoCaso } from '@/lib/cola-supervision'
 import { conteoSemaforoEquipo, lecturaAnalista, type LecturaAnalista } from '@/lib/senal-equipo'
-import { haceTexto } from '@/lib/inteligencia'
+import { candidatosDeHoy, partesDeCosa, tresCosasDeHoy, type CosaDeHoy } from '@/lib/tres-cosas'
+import { colorMeta, haceTexto } from '@/lib/inteligencia'
+import { resumenAgenda } from '@/lib/agenda-equipo-vista'
 import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
 import { textoConversionOperativa } from '@/lib/metricas-vendedores'
-import { totalEnSoles } from '@/lib/capital-unificado'
-import { moneyK, numero, primerNombre } from '@/lib/format'
+import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
+import { moneyCompacta, moneyK, numero, porcentajeConversionCanonica, primerNombre } from '@/lib/format'
 import { hashDe } from '@/lib/router'
 import { cn } from '@/lib/utils'
 import { usePanelesActions } from '@/lib/store-context'
+import { useAuth } from '@/lib/auth-context'
 import type { FiltrosSla } from '@/lib/sla-operacion'
 import { HoySupervisor } from './supervisor'
 import { useDatosSupervisor } from './datos-supervisor'
+import { AgendaEquipoPanel } from './agenda-equipo'
+import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
 
 /** Filas de la vista previa: lo demás vive en el módulo Seguimiento. */
 const COLA_VISIBLES = 7
@@ -53,6 +62,11 @@ const VACIO_PESTANA: Record<PestanaMando, string> = {
   todas: 'Sin oportunidades con acciones en el seguimiento.',
 }
 
+// La severidad TAMBIÉN en texto: el color nunca va solo.
+const SEV_TEXTO: Record<CosaDeHoy['severidad'], string> = { critica: 'Hoy', atencion: 'Esta semana' }
+const SEV_TEXTO_COLOR: Record<CosaDeHoy['severidad'], string> = { critica: 'var(--destructive-text)', atencion: 'var(--warning-text)' }
+const SEV_BORDE: Record<CosaDeHoy['severidad'], string> = { critica: SEMAFORO.critico, atencion: SEMAFORO.atencion }
+
 /** Chip de señal: el ámbar suave usa el token de TEXTO (el hex puro no llega a 4.5:1 sobre su tinte). */
 function ChipSenal({ texto, nivel }: { texto: string; nivel: 'critico' | 'atencion' }): JSX.Element {
   return nivel === 'critico'
@@ -68,31 +82,51 @@ const COLOR_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
 
 export function HoySupervisorMando(): JSX.Element {
   const modo = useModoSla()
+  const { yo } = useAuth()
   if (modo.legado) return <HoySupervisor />
-  // Cambiar de revisión del seguimiento remonta la pantalla: ningún filtro ni
-  // selección de la revisión anterior sobrevive sobre datos de otra.
-  return <PuestoDeMando key={String(modo.data?.control_revision ?? 'sin-revision')} />
+  // Cambiar de identidad o de revisión del seguimiento remonta la pantalla:
+  // ningún filtro ni selección sobrevive sobre datos de otra (como
+  // SlaOperacionBoundary).
+  return <PuestoDeMando key={`${yo?.id ?? ''}|${yo?.rol ?? ''}|${modo.data?.control_revision ?? 'sin-revision'}`} />
 }
 
 function PuestoDeMando(): JSX.Element {
   const modo = useModoSla()
   const datos = useDatosSupervisor()
   const { abrirLead } = usePanelesActions()
+  const { yo } = useAuth()
   const { ambito, rank, tc, ahora } = datos
   const idPanelCola = useId()
 
   const [pestana, setPestana] = useState<PestanaMando>('pendientes')
-  const [analistaId, setAnalistaId] = useState<string | null>(null)
+  const [analistaElegido, setAnalistaId] = useState<string | null>(null)
+  // Un analista que sale del equipo no deja la cola filtrada por un id oculto.
+  const analistaId = analistaElegido != null && ambito.vendedores.some((m) => m.perfil_id === analistaElegido)
+    ? analistaElegido
+    : null
   const [anuncio, setAnuncio] = useState('')
   const [abriendo, setAbriendo] = useState<string | null>(null)
   const [errorApertura, setErrorApertura] = useState(false)
+  const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
+  const [detalleAbierto, setDetalleAbierto] = useState(false)
 
   const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
   const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
   // Fail-closed: TanStack conserva la última respuesta tras un refetch
   // fallido; con error, la cola NO se muestra como vigente.
   const pagina = consultaCola.error ? undefined : consultaCola.data
-  const paginaVigente = pagina?.modo === 'activo' ? pagina : undefined
+  // Vigente = modo activo Y la MISMA revisión de reglas que el modo: la caché
+  // de TanStack no conoce la revisión y, al remontar, podría servir una página
+  // calculada con las reglas anteriores mientras refresca.
+  const revisionVigente = modo.data?.control_revision
+  const esVigente = (p: typeof pagina) => p != null && p.modo === 'activo' && p.control_revision === revisionVigente
+  const paginaVigente = esVigente(pagina) ? pagina : undefined
+  // Las decisiones del día miran a TODO el equipo: sin filtro por analista.
+  // Sin filtro es la MISMA clave que la cola (TanStack la comparte); con
+  // filtro es la consulta que la cola tenía antes de filtrar.
+  const consultaEquipo = useColaSlaPagina({ senal: pestana, etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
+  const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
+  const paginaEquipoVigente = esVigente(paginaEquipo) ? paginaEquipo : undefined
 
   // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
   // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
@@ -118,6 +152,8 @@ function PuestoDeMando(): JSX.Element {
   const elegirPestana = (id: PestanaMando) => {
     setPestana(id)
     setErrorApertura(false)
+    // La tarjeta de primera gestión ES esa pestaña: si se va de ella, se cierra.
+    if (id !== 'primera_atencion' && decisionAbierta === 'primera_gestion') setDecisionAbierta(null)
   }
 
   async function abrirFicha(id: string) {
@@ -150,6 +186,81 @@ function PuestoDeMando(): JSX.Element {
   )
   const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])
 
+  // ── 1 · Decide primero: las mismas reglas de la franja clásica ──
+  // Fail-closed por fuente: un candidato solo existe si su fuente llegó bien,
+  // y «Nada que decidir» solo se afirma con TODAS las fuentes confirmadas.
+  const primeraGestionPendiente = paginaEquipoVigente?.totales.primera_atencion ?? null
+  const entradaCosas = {
+    cola: null,
+    totalPorRepartir: datos.resumenOp.error ? null : datos.totalPorRepartir,
+    esperaMasLargaReparto: datos.esperaMasLargaReparto,
+    vendedoresAgenda: datos.agendaConfirmada?.vendedores ?? [],
+    primeraGestionPendiente,
+  }
+  const candidatos = candidatosDeHoy(entradaCosas)
+  const cosas = tresCosasDeHoy(entradaCosas)
+  const estaSemana = candidatos.slice(cosas.length)
+  const fuentesCaidas = [
+    consultaEquipo.error ? 'el seguimiento' : null,
+    datos.errorAgenda ? 'la agenda' : null,
+    datos.resumenOp.error ? 'el reparto' : null,
+  ].filter((f): f is string => f != null)
+  const fuentesListas = paginaEquipoVigente != null
+    && datos.agendaConfirmada != null
+    && datos.resumen != null
+  const reintentarDecisiones = () => {
+    if (consultaEquipo.error) void consultaEquipo.refetch()
+    if (datos.errorAgenda) datos.recargarAgenda()
+    if (datos.resumenOp.error) void datos.resumenOp.recargar()
+  }
+
+  const alternarDecision = (cosa: CosaDeHoy) => {
+    const abrir = decisionAbierta !== cosa.id
+    setDecisionAbierta(abrir ? cosa.id : null)
+    if (cosa.id !== 'primera_gestion') return
+    // Primera gestión: la cola de abajo pasa a ESA pestaña, para todo el equipo.
+    if (abrir) {
+      setPestana('primera_atencion')
+      setAnalistaId(null)
+      setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
+    } else if (pestana === 'primera_atencion') {
+      setPestana('pendientes')
+      setAnuncio('Mostrando los pendientes de todo el equipo')
+    }
+  }
+  const verPrimeraGestion = () => {
+    setDecisionAbierta('primera_gestion')
+    setPestana('primera_atencion')
+    setAnalistaId(null)
+    setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
+    requestAnimationFrame(() => document.getElementById(`${idPanelCola}-tab-primera_atencion`)?.focus())
+  }
+
+  /** Una línea de contexto con datos YA confirmados; sin dato, nada. */
+  const contextoDe = (cosa: CosaDeHoy): string | null => {
+    switch (cosa.id) {
+      case 'primera_gestion':
+        return 'Revisa la primera gestión con cada analista: abajo quedan solo esos casos.'
+      case 'no_asistio':
+      case 'sin_accion': {
+        if (cosa.vendedorId != null) {
+          const r = rezagosConfirmados.get(cosa.vendedorId)
+          if (!r) return null
+          return `En 7 días: ${numero(r.no_asistio)} sin asistir · ${numero(r.vencidas)} tareas vencidas · ${numero(r.leads_sin_accion)} sin próxima acción.`
+        }
+        const nombres = (datos.agendaConfirmada?.vendedores ?? [])
+          .filter((v) => v.rol === 'vendedor' && v.activo
+            && (cosa.id === 'no_asistio' ? v.no_asistio >= 2 : v.leads_sin_accion >= 3))
+          .map((v) => `${primerNombre(v.nombre)} (${cosa.id === 'no_asistio' ? v.no_asistio : v.leads_sin_accion})`)
+        return nombres.length > 0 ? nombres.join(' · ') : null
+      }
+      case 'por_repartir':
+        return 'Leads sin analista en tu bandeja. El reparto se hace en Derivar leads.'
+      default:
+        return null
+    }
+  }
+
   const errorIndicadores = !datos.sesionReal
     ? false
     : Boolean(datos.resumenOp.error || datos.vendedoresOp.error)
@@ -158,12 +269,68 @@ function PuestoDeMando(): JSX.Element {
     if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
   }
 
+  // ── 3 · Consulta: las cifras de siempre, en una línea; el detalle, encima ──
+  const agendaResumen = datos.agendaConfirmada ? resumenAgenda(datos.agendaConfirmada.vendedores) : null
+  const filaCapital = datos.filasMeta[0]
+  const metaTexto = filaCapital == null || filaCapital.sinDato ? '—' : `${Math.round(filaCapital.pct)} %`
+  const conversionTexto = datos.conversionConfirmada == null ? '—' : porcentajeConversionCanonica(datos.conversionConfirmada)
+  const pronostico = datos.capitalPronostico
+  // En la franja, compacto (S/ 1.48 M); la cifra exacta vive en el KPI del detalle.
+  const pronosticoCorto = pronostico && datos.resumen
+    ? moneyCompacta(pronostico.soloDolares ? datos.resumen.capital.asignado.usd : datos.resumen.capital.asignado.pen, pronostico.moneda)
+    : '—'
+
   const tituloCola = nombreAnalista ? `Pendientes de ${primerNombre(nombreAnalista)}` : 'Pendientes del equipo'
 
   return (
     <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
       <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>
 
+      {modo.activo && (
+        <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
+          <div className="flex items-center justify-between gap-4">
+            <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
+            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} />}
+          </div>
+          {fuentesCaidas.length > 0 && (
+            <div role="alert" className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-destructive/30 bg-card px-4 py-2.5">
+              <p className="text-xs">
+                Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
+              </p>
+              <Button variant="outline" size="sm" onClick={reintentarDecisiones}>
+                <RefreshCw aria-hidden /> Reintentar
+              </Button>
+            </div>
+          )}
+          {cosas.length === 0 ? (
+            fuentesCaidas.length > 0 ? null : (
+              <Card>
+                <CardContent className="py-4">
+                  <p role="status" className="text-sm text-muted-foreground">
+                    {fuentesListas ? 'Nada que decidir ahora mismo.' : 'Revisando las decisiones del día…'}
+                  </p>
+                </CardContent>
+              </Card>
+            )
+          ) : (
+            <div className="grid gap-3.5 lg:grid-cols-3">
+              {cosas.map((cosa) => (
+                <TarjetaDecision
+                  key={cosa.id}
+                  cosa={cosa}
+                  abierta={decisionAbierta === cosa.id}
+                  contexto={contextoDe(cosa)}
+                  idContexto={`${idPanelCola}-decision-${cosa.id}`}
+                  onAlternar={() => alternarDecision(cosa)}
+                  onVerPrimeraGestion={verPrimeraGestion}
+                  etiquetaReparto={datos.etiquetaAccesoReparto}
+                />
+              ))}
+            </div>
+          )}
+        </section>
+      )}
+
       <AvisoDegradacion
         activo={errorIndicadores}
         queReintenta="de los indicadores del equipo"
@@ -282,7 +449,9 @@ function PuestoDeMando(): JSX.Element {
                   <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
                 ) : !paginaVigente ? (
                   <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
-                    Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.
+                    {pagina.modo !== 'activo'
+                      ? 'Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.'
+                      : 'Actualizando los pendientes con las reglas vigentes…'}
                   </p>
                 ) : paginaVigente.items.length === 0 ? (
                   <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
@@ -357,9 +526,10 @@ function PuestoDeMando(): JSX.Element {
               </a>
             )}
           />
-          {rank != null && rank.length > 0 && (
+          {rank != null && rank.length > 0 && (semaforoEquipo.rojo > 0 || semaforoEquipo.ambar > 0 || datos.agendaConfirmada != null) && (
             <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
               {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
+                // Solo con la agenda confirmada: sin ella, cero señales es desconocido.
                 ? 'Sin alertas en el equipo'
                 : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
             </p>
@@ -453,6 +623,297 @@ function PuestoDeMando(): JSX.Element {
           )}
         </Card>
       </div>
+
+      {/* ── 3 · Consulta: cifras en una línea; «Detalle» abre todo lo demás ── */}
+      <section aria-label="Consulta" className="flex min-h-12 flex-wrap items-center gap-x-5 gap-y-1.5 rounded-xl border border-border bg-card px-5 py-2">
+        <span className="text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground-strong" aria-hidden>Consulta</span>
+        <ul aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
+          <li>
+            <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
+            {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
+          </li>
+          <li><strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos</li>
+          <li><strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta</li>
+          <li><strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes</li>
+          <li aria-hidden className="h-[18px] w-px bg-border" />
+          <li><strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días</li>
+          <li><strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas</li>
+          <li>
+            <strong
+              className="font-extrabold"
+              style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
+            >
+              {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
+            </strong> no asistió
+          </li>
+        </ul>
+        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent" onClick={() => setDetalleAbierto(true)}>
+          Detalle
+        </Button>
+      </section>
+
+      <Dialog
+        open={detalleAbierto}
+        onClose={() => setDetalleAbierto(false)}
+        className="w-[1180px] max-h-[88vh] max-w-[94vw]"
+      >
+        <DialogHeader>
+          <DialogTitle>Detalle del equipo</DialogTitle>
+          <DialogDescription>Indicadores, cumplimiento del mes y agenda de los últimos 7 días.</DialogDescription>
+        </DialogHeader>
+        <DialogBody className="space-y-4">
+          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
+            {/* Pronóstico: `capitalPrincipal`, NUNCA un total mixto con los dólares. */}
+            <KpiCard
+              label="Pronóstico de capital abierto"
+              value={pronostico ? pronostico.valor : '—'}
+              icon={Wallet}
+              color={SEMAFORO.neutro}
+              sub={
+                pronostico?.otra
+                  ? `En soles · +${pronostico.otra} aparte`
+                  : pronostico?.soloDolares
+                    ? 'En dólares · abiertos con analista'
+                    : datos.resumen && datos.resumen.capital.asignado.pen === 0 && datos.resumen.totales.asignados > 0
+                      ? 'Sin montos estimados — complétalos en cada ficha'
+                      : 'En soles · abiertos con analista'
+              }
+            />
+            <KpiCard
+              label="Leads activos del equipo"
+              value={datos.resumen ? String(datos.resumen.totales.asignados) : '—'}
+              icon={Users}
+              color={SEMAFORO.neutro}
+              sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
+              delay={60}
+            />
+            <KpiCard
+              label="Primeras gestiones vencidas"
+              value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
+              icon={AlertTriangle}
+              color={SEMAFORO.neutro}
+              sub={primeraGestionPendiente == null
+                ? 'Sin dato por ahora'
+                : primeraGestionPendiente > 0 ? 'Revísalas con cada analista' : 'Ninguna vencida'}
+              delay={120}
+            />
+            <a
+              href={hashDe('derivaciones')}
+              aria-label={datos.etiquetaAccesoReparto}
+              className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
+            >
+              <KpiCard
+                label="Por repartir"
+                value={datos.totalPorRepartir == null ? '—' : String(datos.totalPorRepartir)}
+                icon={Inbox}
+                color={SEMAFORO.neutro}
+                sub={datos.detalleReparto}
+                delay={180}
+              />
+            </a>
+          </div>
+
+          <div className="grid gap-4 lg:grid-cols-5">
+            <Card className="lg:col-span-2">
+              <SectionHead
+                icon={Target}
+                title="Cumplimiento del mes"
+                right={tc ? <span className="text-xs text-muted-foreground-strong">{rotuloTipoCambio(tc.promedio, tc.fuente)}</span> : undefined}
+              />
+              <CardContent className="space-y-4 pb-5 pt-0">
+                {datos.filasMeta.map((f) => (
+                  <div key={f.label}>
+                    <div className="mb-1.5 flex items-baseline justify-between gap-2">
+                      <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
+                      <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
+                    </div>
+                    {f.nota && <p className="mb-1 text-[11px] tabular-nums text-muted-foreground-strong">{f.nota}</p>}
+                    {f.sinDato
+                      ? <p className="text-[11px] text-muted-foreground-strong">{f.sinDato}</p>
+                      : <Progress value={f.pct} color={colorMeta(f.pct)} />}
+                  </div>
+                ))}
+                <p className="text-[11px] text-muted-foreground-strong">
+                  El capital en dólares entra al total convertido a tipo de cambio real. El pronóstico no cuenta como cumplimiento.
+                </p>
+                {datos.hayErrorMensual && (
+                  <Button variant="ghost" size="sm" onClick={datos.reintentarMensual}>
+                    Reintentar
+                  </Button>
+                )}
+              </CardContent>
+            </Card>
+            <div className="min-w-0 lg:col-span-3">
+              <AgendaEquipoPanel
+                datos={datos.datosAgenda}
+                cargando={datos.cargandoAgenda}
+                error={datos.errorAgenda}
+                modoDemo={yo?.demo === true}
+                onReintentar={datos.recargarAgenda}
+                equipo={datos.equipo}
+              />
+            </div>
+          </div>
+
+          {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC). */}
+          <DesglosePorEmpresa demo={yo?.demo === true} porVendedor={datos.cumplimientoMensual?.porVendedor ?? null} />
+          {/* Rentabilidad R3: las solicitudes de tasa propias en curso (solo si hay). */}
+          <TasasAutorizadasAnalistaPanel />
+          <p className="text-[11px] text-muted-foreground-strong">
+            Ves solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
+          </p>
+        </DialogBody>
+        <DialogFooter>
+          <Button variant="outline" size="sm" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
+        </DialogFooter>
+      </Dialog>
+    </div>
+  )
+}
+
+/** El botón de acción de una decisión. Nunca va DENTRO del botón que la despliega. */
+function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
+  cosa: CosaDeHoy
+  onVerPrimeraGestion: () => void
+  etiquetaReparto: string
+}): JSX.Element {
+  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
+  if (cosa.id === 'primera_gestion') {
+    return (
+      <button type="button" className={clase} aria-label={`Ver las ${cosa.texto} en la cola`} onClick={onVerPrimeraGestion}>
+        Ver <ChevronRight className="size-3.5" aria-hidden />
+      </button>
+    )
+  }
+  if (cosa.id === 'por_repartir') {
+    return (
+      <a href={hashDe('derivaciones')} className={clase} aria-label={etiquetaReparto}>
+        Repartir <ChevronRight className="size-3.5" aria-hidden />
+      </a>
+    )
+  }
+  if (cosa.id === 'no_asistio' || cosa.id === 'sin_accion') {
+    // La cola no contiene citas ni leads «sin próxima acción»: filtrarla
+    // enseñaría OTROS casos. La decisión se toma viendo el día del equipo.
+    const label = cosa.vendedorId != null ? 'Ver su día' : 'Ver el equipo'
+    return (
+      <a href={hashDe('gestion-diaria')} className={clase} aria-label={`${label}: ${cosa.texto}`}>
+        {label} <ChevronRight className="size-3.5" aria-hidden />
+      </a>
+    )
+  }
+  // Candidatos del modo legado: aquí no aparecen (la cola legada llega null),
+  // pero si algún día lo hicieran, su lugar es el módulo de seguimiento.
+  return (
+    <a href={hashDe('seguimiento')} className={clase} aria-label={`${cosa.accion}: ${cosa.texto}`}>
+      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
+    </a>
+  )
+}
+
+function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVerPrimeraGestion, etiquetaReparto }: {
+  cosa: CosaDeHoy
+  abierta: boolean
+  contexto: string | null
+  idContexto: string
+  onAlternar: () => void
+  onVerPrimeraGestion: () => void
+  etiquetaReparto: string
+}): JSX.Element {
+  const { cifra, resto } = partesDeCosa(cosa.texto)
+  return (
+    <Card
+      data-decision={cosa.id}
+      className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')}
+      style={{ borderLeftColor: SEV_BORDE[cosa.severidad] }}
+    >
+      <div className="flex items-center gap-2 py-2 pl-4 pr-3">
+        <button
+          type="button"
+          aria-expanded={abierta}
+          aria-controls={idContexto}
+          aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto}`}
+          onClick={onAlternar}
+          className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 rounded-md text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
+        >
+          {cifra && (
+            <span className="min-w-10 text-[32px] font-extrabold leading-none tracking-tight tabular-nums text-primary">{cifra}</span>
+          )}
+          <span className="min-w-0 flex-1 leading-tight">
+            <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: SEV_TEXTO_COLOR[cosa.severidad] }}>
+              {SEV_TEXTO[cosa.severidad]}
+            </span>
+            <span className="block truncate text-[15px] font-bold" title={resto}>{resto}</span>
+          </span>
+          <ChevronRight
+            className={cn('size-4 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')}
+            aria-hidden
+          />
+        </button>
+        <AccionDecision cosa={cosa} onVerPrimeraGestion={onVerPrimeraGestion} etiquetaReparto={etiquetaReparto} />
+      </div>
+      <p id={idContexto} hidden={!abierta} className="border-t border-border/60 px-4 py-2.5 text-xs text-muted-foreground-strong">
+        {contexto ?? 'Sin más detalle confirmado por ahora.'}
+      </p>
+    </Card>
+  )
+}
+
+/** «Esta semana · N»: lo que no entró en las tres tarjetas. Esc y clic fuera lo cierran. */
+function EstaSemana({ cosas, onVerPrimeraGestion }: { cosas: CosaDeHoy[]; onVerPrimeraGestion: () => void }): JSX.Element {
+  const [abierto, setAbierto] = useState(false)
+  const contenedor = useRef<HTMLDivElement>(null)
+  const disparador = useRef<HTMLButtonElement>(null)
+  const idLista = useId()
+  useEffect(() => {
+    if (!abierto) return
+    const fuera = (e: PointerEvent) => {
+      if (!contenedor.current?.contains(e.target as Node)) setAbierto(false)
+    }
+    // Esc cierra y devuelve el foco al disparador, esté donde esté el foco
+    // dentro de la lista (y también si quedó fuera: el popover no atrapa).
+    const escape = (e: KeyboardEvent) => {
+      if (e.key !== 'Escape') return
+      setAbierto(false)
+      if (contenedor.current?.contains(document.activeElement)) disparador.current?.focus()
+    }
+    document.addEventListener('pointerdown', fuera)
+    document.addEventListener('keydown', escape)
+    return () => {
+      document.removeEventListener('pointerdown', fuera)
+      document.removeEventListener('keydown', escape)
+    }
+  }, [abierto])
+  return (
+    <div ref={contenedor} className="relative">
+      <button
+        ref={disparador}
+        type="button"
+        aria-expanded={abierto}
+        aria-controls={idLista}
+        onClick={() => setAbierto((v) => !v)}
+        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
+      >
+        <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
+        Esta semana · {cosas.length}
+        <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
+      </button>
+      <ul
+        id={idLista}
+        hidden={!abierto}
+        aria-label="Decisiones para esta semana"
+        className="ac-pop absolute right-0 top-11 z-20 w-[340px] max-w-[90vw] rounded-xl border border-border bg-card p-2 shadow-[var(--shadow-pop)]"
+      >
+        {cosas.map((c) => (
+          <li key={c.id} className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-xs font-semibold">
+            <span className="size-2 shrink-0 rounded-full" style={{ background: SEV_BORDE[c.severidad] }} aria-hidden />
+            <span className="min-w-0 flex-1">
+              <span className="sr-only">{SEV_TEXTO[c.severidad]}: </span>{c.texto}
+            </span>
+            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={`Repartir: ${c.texto}`} />
+          </li>
+        ))}
+      </ul>
     </div>
   )
 }
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx
index 634660e5..fcf899ca 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx
@@ -72,6 +72,7 @@ let CONVERSION_MENSUAL_ERROR = false
 let CONVERSION_MENSUAL_PENDING = false
 const REFETCH_CONVERSION_MENSUAL = vi.fn()
 let METRICAS_AGENDA: import('@/lib/metricas-agenda').MetricasAgenda | undefined
+let AGENDA_ERROR: Error | null = null
 vi.mock('@/data/crm-queries', () => ({
   // Rentabilidad R3: sin solicitudes ni decisiones en estos escenarios (tienen sus propios tests).
   useSolicitudesTasa: () => ({ data: [], isPending: false, isError: false, refetch: () => {} }),
@@ -82,7 +83,7 @@ vi.mock('@/data/crm-queries', () => ({
   useHistorialTasaCliente: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
   useMetricasAgenda: () => ({
     data: METRICAS_AGENDA,
-    error: null,
+    error: AGENDA_ERROR,
     isPending: false,
     isFetching: false,
     refetch: () => {},
@@ -320,6 +321,7 @@ beforeEach(() => {
   MODO_SLA.activo = false
   instalarAlmacen()
   METRICAS_AGENDA = undefined
+  AGENDA_ERROR = null
   CONVERSION_MENSUAL = null
   CONVERSION_MENSUAL_ERROR = false
   CONVERSION_MENSUAL_PENDING = false
@@ -513,6 +515,24 @@ describe('Hoy · supervisor — «Hoy, tres cosas» (F3)', () => {
       .toHaveAttribute('href', '#/equipo')
   })
 
+  it('una agenda RETENIDA tras un refetch fallido no decide: la franja no usa esos datos', () => {
+    METRICAS_AGENDA = {
+      version: 1,
+      generado_en: '2026-07-15T15:00:00Z',
+      periodo: { desde: '2026-07-09', hasta: '2026-07-15', dias: 7, zona: 'America/Lima' },
+      vendedores: [{
+        vendedor_id: 'v-1', nombre: 'CARLA DÍAZ', rol: 'vendedor', activo: true,
+        toques: 5, toques_por_dia: 0.7, reuniones_realizadas: 0, completadas: 0,
+        no_asistio: 2, canceladas: 0, pct_completadas: null, tareas_creadas: 0,
+        reuniones_agendadas: 0, reprogramaciones: 0, pendientes: 0, vencidas: 0,
+        leads_sin_accion: 0,
+      }],
+    } as import('@/lib/metricas-agenda').MetricasAgenda
+    AGENDA_ERROR = new Error('refetch caído')
+    montar({ leads: [] })
+    expect(screen.queryByText(/citas sin asistir/)).not.toBeInTheDocument()
+  })
+
   it('ESTADO DE PRODUCCIÓN (sin nada que hacer): la franja NO se pinta', () => {
     montar({ leads: [] })
     expect(screen.queryByRole('region', { name: 'Hoy, tres cosas' })).not.toBeInTheDocument()
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
index 1fe60b1f..b3fc57c1 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
@@ -105,6 +105,7 @@ export function HoySupervisor(): JSX.Element {
     hayErrorMensual,
     reintentarMensual,
     datosAgenda,
+    agendaConfirmada,
     errorAgenda,
     cargandoAgenda,
     recargarAgenda,
@@ -222,9 +223,11 @@ export function HoySupervisor(): JSX.Element {
       cola,
       totalPorRepartir,
       esperaMasLargaReparto,
-      vendedoresAgenda: datosAgenda?.vendedores ?? [],
+      // Para DECIDIR, solo la agenda confirmada: tras un refetch fallido
+      // TanStack conserva la respuesta anterior (Codex, F1 del puesto de mando).
+      vendedoresAgenda: agendaConfirmada?.vendedores ?? [],
     }),
-    [cola, totalPorRepartir, esperaMasLargaReparto, datosAgenda],
+    [cola, totalPorRepartir, esperaMasLargaReparto, agendaConfirmada],
   )
   // «Ver →» de la franja: selecciona la pestaña y le LLEVA el foco (el
   // focus() también hace scroll hasta la tarjeta de la cola).
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
    15	import { AlertTriangle, ChevronRight, Inbox, ListChecks, RefreshCw, Target, Users, UsersRound, Wallet } from 'lucide-react'
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
    29	import { estadoCasoSupervision, momentoCaso } from '@/lib/cola-supervision'
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
    82	
    83	export function HoySupervisorMando(): JSX.Element {
    84	  const modo = useModoSla()
    85	  const { yo } = useAuth()
    86	  if (modo.legado) return <HoySupervisor />
    87	  // Cambiar de identidad o de revisión del seguimiento remonta la pantalla:
    88	  // ningún filtro ni selección sobrevive sobre datos de otra (como
    89	  // SlaOperacionBoundary).
    90	  return <PuestoDeMando key={`${yo?.id ?? ''}|${yo?.rol ?? ''}|${modo.data?.control_revision ?? 'sin-revision'}`} />
    91	}
    92	
    93	function PuestoDeMando(): JSX.Element {
    94	  const modo = useModoSla()
    95	  const datos = useDatosSupervisor()
    96	  const { abrirLead } = usePanelesActions()
    97	  const { yo } = useAuth()
    98	  const { ambito, rank, tc, ahora } = datos
    99	  const idPanelCola = useId()
   100	
   101	  const [pestana, setPestana] = useState<PestanaMando>('pendientes')
   102	  const [analistaElegido, setAnalistaId] = useState<string | null>(null)
   103	  // Un analista que sale del equipo no deja la cola filtrada por un id oculto.
   104	  const analistaId = analistaElegido != null && ambito.vendedores.some((m) => m.perfil_id === analistaElegido)
   105	    ? analistaElegido
   106	    : null
   107	  const [anuncio, setAnuncio] = useState('')
   108	  const [abriendo, setAbriendo] = useState<string | null>(null)
   109	  const [errorApertura, setErrorApertura] = useState(false)
   110	  const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
   111	  const [detalleAbierto, setDetalleAbierto] = useState(false)
   112	
   113	  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
   114	  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
   115	  // Fail-closed: TanStack conserva la última respuesta tras un refetch
   116	  // fallido; con error, la cola NO se muestra como vigente.
   117	  const pagina = consultaCola.error ? undefined : consultaCola.data
   118	  // Vigente = modo activo Y la MISMA revisión de reglas que el modo: la caché
   119	  // de TanStack no conoce la revisión y, al remontar, podría servir una página
   120	  // calculada con las reglas anteriores mientras refresca.
   121	  const revisionVigente = modo.data?.control_revision
   122	  const esVigente = (p: typeof pagina) => p != null && p.modo === 'activo' && p.control_revision === revisionVigente
   123	  const paginaVigente = esVigente(pagina) ? pagina : undefined
   124	  // Las decisiones del día miran a TODO el equipo: sin filtro por analista.
   125	  // Sin filtro es la MISMA clave que la cola (TanStack la comparte); con
   126	  // filtro es la consulta que la cola tenía antes de filtrar.
   127	  const consultaEquipo = useColaSlaPagina({ senal: pestana, etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
   128	  const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
   129	  const paginaEquipoVigente = esVigente(paginaEquipo) ? paginaEquipo : undefined
   130	
   131	  // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
   132	  // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
   133	  const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
   134	  // Analistas del equipo (no las filas cargadas): los chips no dependen de
   135	  // lo que haya traído la página y no prometen conteos del lado cliente.
   136	  const analistas = useMemo(
   137	    () => ambito.vendedores
   138	      .filter((m) => m.activo && m.rol_crm === 'vendedor')
   139	      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
   140	    [ambito.vendedores],
   141	  )
   142	  const nombreAnalista = analistaId != null
   143	    ? ambito.vendedores.find((m) => m.perfil_id === analistaId)?.nombre_completo ?? null
   144	    : null
   145	
   146	  const elegirAnalista = (id: string | null) => {
   147	    const siguiente = id === analistaId ? null : id
   148	    setAnalistaId(siguiente)
   149	    const nombre = siguiente == null ? null : ambito.vendedores.find((m) => m.perfil_id === siguiente)?.nombre_completo
   150	    setAnuncio(nombre ? `Mostrando los pendientes de ${primerNombre(nombre)}` : 'Mostrando los pendientes de todo el equipo')
   151	  }
   152	  const elegirPestana = (id: PestanaMando) => {
   153	    setPestana(id)
   154	    setErrorApertura(false)
   155	    // La tarjeta de primera gestión ES esa pestaña: si se va de ella, se cierra.
   156	    if (id !== 'primera_atencion' && decisionAbierta === 'primera_gestion') setDecisionAbierta(null)
   157	  }
   158	
   159	  async function abrirFicha(id: string) {
   160	    if (abriendo) return
   161	    setAbriendo(id)
   162	    setErrorApertura(false)
   163	    try {
   164	      if (await abrirLead(id) === false) setErrorApertura(true)
   165	    } catch {
   166	      setErrorApertura(true)
   167	    } finally {
   168	      setAbriendo(null)
   169	    }
   170	  }
   171	
   172	  const conteoPestana = (id: PestanaMando): number | null => {
   173	    if (!paginaVigente) return null
   174	    if (id === 'todas') return pestana === 'todas' ? paginaVigente.total_items : null
   175	    return paginaVigente.totales[id]
   176	  }
   177	
   178	  // ── Equipo hoy: UNA lectura por analista alimenta punto, cabecera y chips ──
   179	  const rezagosConfirmados = useMemo(
   180	    () => new Map((datos.agendaConfirmada?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
   181	    [datos.agendaConfirmada],
   182	  )
   183	  const lecturas = useMemo(
   184	    () => new Map((rank ?? []).map((r) => [r.m.perfil_id, lecturaAnalista(r, rezagosConfirmados.get(r.m.perfil_id))] as const)),
   185	    [rank, rezagosConfirmados],
   186	  )
   187	  const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])
   188	
   189	  // ── 1 · Decide primero: las mismas reglas de la franja clásica ──
   190	  // Fail-closed por fuente: un candidato solo existe si su fuente llegó bien,
   191	  // y «Nada que decidir» solo se afirma con TODAS las fuentes confirmadas.
   192	  const primeraGestionPendiente = paginaEquipoVigente?.totales.primera_atencion ?? null
   193	  const entradaCosas = {
   194	    cola: null,
   195	    totalPorRepartir: datos.resumenOp.error ? null : datos.totalPorRepartir,
   196	    esperaMasLargaReparto: datos.esperaMasLargaReparto,
   197	    vendedoresAgenda: datos.agendaConfirmada?.vendedores ?? [],
   198	    primeraGestionPendiente,
   199	  }
   200	  const candidatos = candidatosDeHoy(entradaCosas)
   201	  const cosas = tresCosasDeHoy(entradaCosas)
   202	  const estaSemana = candidatos.slice(cosas.length)
   203	  const fuentesCaidas = [
   204	    consultaEquipo.error ? 'el seguimiento' : null,
   205	    datos.errorAgenda ? 'la agenda' : null,
   206	    datos.resumenOp.error ? 'el reparto' : null,
   207	  ].filter((f): f is string => f != null)
   208	  const fuentesListas = paginaEquipoVigente != null
   209	    && datos.agendaConfirmada != null
   210	    && datos.resumen != null
   211	  const reintentarDecisiones = () => {
   212	    if (consultaEquipo.error) void consultaEquipo.refetch()
   213	    if (datos.errorAgenda) datos.recargarAgenda()
   214	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   215	  }
   216	
   217	  const alternarDecision = (cosa: CosaDeHoy) => {
   218	    const abrir = decisionAbierta !== cosa.id
   219	    setDecisionAbierta(abrir ? cosa.id : null)
   220	    if (cosa.id !== 'primera_gestion') return
   221	    // Primera gestión: la cola de abajo pasa a ESA pestaña, para todo el equipo.
   222	    if (abrir) {
   223	      setPestana('primera_atencion')
   224	      setAnalistaId(null)
   225	      setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   226	    } else if (pestana === 'primera_atencion') {
   227	      setPestana('pendientes')
   228	      setAnuncio('Mostrando los pendientes de todo el equipo')
   229	    }
   230	  }
   231	  const verPrimeraGestion = () => {
   232	    setDecisionAbierta('primera_gestion')
   233	    setPestana('primera_atencion')
   234	    setAnalistaId(null)
   235	    setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   236	    requestAnimationFrame(() => document.getElementById(`${idPanelCola}-tab-primera_atencion`)?.focus())
   237	  }
   238	
   239	  /** Una línea de contexto con datos YA confirmados; sin dato, nada. */
   240	  const contextoDe = (cosa: CosaDeHoy): string | null => {
   241	    switch (cosa.id) {
   242	      case 'primera_gestion':
   243	        return 'Revisa la primera gestión con cada analista: abajo quedan solo esos casos.'
   244	      case 'no_asistio':
   245	      case 'sin_accion': {
   246	        if (cosa.vendedorId != null) {
   247	          const r = rezagosConfirmados.get(cosa.vendedorId)
   248	          if (!r) return null
   249	          return `En 7 días: ${numero(r.no_asistio)} sin asistir · ${numero(r.vencidas)} tareas vencidas · ${numero(r.leads_sin_accion)} sin próxima acción.`
   250	        }
   251	        const nombres = (datos.agendaConfirmada?.vendedores ?? [])
   252	          .filter((v) => v.rol === 'vendedor' && v.activo
   253	            && (cosa.id === 'no_asistio' ? v.no_asistio >= 2 : v.leads_sin_accion >= 3))
   254	          .map((v) => `${primerNombre(v.nombre)} (${cosa.id === 'no_asistio' ? v.no_asistio : v.leads_sin_accion})`)
   255	        return nombres.length > 0 ? nombres.join(' · ') : null
   256	      }
   257	      case 'por_repartir':
   258	        return 'Leads sin analista en tu bandeja. El reparto se hace en Derivar leads.'
   259	      default:
   260	        return null
   261	    }
   262	  }
   263	
   264	  const errorIndicadores = !datos.sesionReal
   265	    ? false
   266	    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error)
   267	  const reintentarIndicadores = () => {
   268	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   269	    if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
   270	  }
   271	
   272	  // ── 3 · Consulta: las cifras de siempre, en una línea; el detalle, encima ──
   273	  const agendaResumen = datos.agendaConfirmada ? resumenAgenda(datos.agendaConfirmada.vendedores) : null
   274	  const filaCapital = datos.filasMeta[0]
   275	  const metaTexto = filaCapital == null || filaCapital.sinDato ? '—' : `${Math.round(filaCapital.pct)} %`
   276	  const conversionTexto = datos.conversionConfirmada == null ? '—' : porcentajeConversionCanonica(datos.conversionConfirmada)
   277	  const pronostico = datos.capitalPronostico
   278	  // En la franja, compacto (S/ 1.48 M); la cifra exacta vive en el KPI del detalle.
   279	  const pronosticoCorto = pronostico && datos.resumen
   280	    ? moneyCompacta(pronostico.soloDolares ? datos.resumen.capital.asignado.usd : datos.resumen.capital.asignado.pen, pronostico.moneda)
   281	    : '—'
   282	
   283	  const tituloCola = nombreAnalista ? `Pendientes de ${primerNombre(nombreAnalista)}` : 'Pendientes del equipo'
   284	
   285	  return (
   286	    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
   287	      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>
   288	
   289	      {modo.activo && (
   290	        <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
   291	          <div className="flex items-center justify-between gap-4">
   292	            <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
   293	            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} />}
   294	          </div>
   295	          {fuentesCaidas.length > 0 && (
   296	            <div role="alert" className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-destructive/30 bg-card px-4 py-2.5">
   297	              <p className="text-xs">
   298	                Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
   299	              </p>
   300	              <Button variant="outline" size="sm" onClick={reintentarDecisiones}>
   301	                <RefreshCw aria-hidden /> Reintentar
   302	              </Button>
   303	            </div>
   304	          )}
   305	          {cosas.length === 0 ? (
   306	            fuentesCaidas.length > 0 ? null : (
   307	              <Card>
   308	                <CardContent className="py-4">
   309	                  <p role="status" className="text-sm text-muted-foreground">
   310	                    {fuentesListas ? 'Nada que decidir ahora mismo.' : 'Revisando las decisiones del día…'}
   311	                  </p>
   312	                </CardContent>
   313	              </Card>
   314	            )
   315	          ) : (
   316	            <div className="grid gap-3.5 lg:grid-cols-3">
   317	              {cosas.map((cosa) => (
   318	                <TarjetaDecision
   319	                  key={cosa.id}
   320	                  cosa={cosa}
   321	                  abierta={decisionAbierta === cosa.id}
   322	                  contexto={contextoDe(cosa)}
   323	                  idContexto={`${idPanelCola}-decision-${cosa.id}`}
   324	                  onAlternar={() => alternarDecision(cosa)}
   325	                  onVerPrimeraGestion={verPrimeraGestion}
   326	                  etiquetaReparto={datos.etiquetaAccesoReparto}
   327	                />
   328	              ))}
   329	            </div>
   330	          )}
   331	        </section>
   332	      )}
   333	
   334	      <AvisoDegradacion
   335	        activo={errorIndicadores}
   336	        queReintenta="de los indicadores del equipo"
   337	        onReintentar={reintentarIndicadores}
   338	      >
   339	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   340	      </AvisoDegradacion>
   341	
   342	      {/* ── 2 · Cola del seguimiento + Equipo hoy ── */}
   343	      <div className="grid gap-4 lg:grid-cols-5">
   344	        <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
   345	          <SectionHead icon={ListChecks} title={tituloCola} />
   346	          {!modo.activo ? (
   347	            <CardContent className="pb-5 pt-0">
   348	              {modo.error ? (
   349	                <div role="alert" className="flex flex-wrap items-center justify-between gap-3">
   350	                  <p className="text-sm">No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.</p>
   351	                  <Button variant="outline" size="sm" onClick={() => void modo.refetch()}>
   352	                    <RefreshCw aria-hidden /> Reintentar
   353	                  </Button>
   354	                </div>
   355	              ) : (
   356	                <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
   357	              )}
   358	            </CardContent>
   359	          ) : (
   360	            <>
   361	              <div className="flex flex-wrap items-center gap-2 px-5 pb-2.5">
   362	                <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
   363	                  {PESTANAS.map((p, indice) => {
   364	                    const n = conteoPestana(p.id)
   365	                    return (
   366	                      <button
   367	                        key={p.id}
   368	                        id={`${idPanelCola}-tab-${p.id}`}
   369	                        type="button"
   370	                        role="tab"
   371	                        aria-selected={pestana === p.id}
   372	                        aria-controls={`${idPanelCola}-panel`}
   373	                        aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
   374	                        tabIndex={pestana === p.id ? 0 : -1}
   375	                        onClick={() => elegirPestana(p.id)}
   376	                        onKeyDown={(e) => {
   377	                          const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
   378	                            : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
   379	                            : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
   380	                          if (destino == null) return
   381	                          e.preventDefault()
   382	                          const siguiente = PESTANAS[destino]
   383	                          if (!siguiente) return
   384	                          elegirPestana(siguiente.id)
   385	                          document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
   386	                        }}
   387	                        className={cn(
   388	                          'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   389	                          pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
   390	                        )}
   391	                      >
   392	                        {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
   393	                      </button>
   394	                    )
   395	                  })}
   396	                </div>
   397	              </div>
   398	
   399	              {analistas.length > 0 && (
   400	                <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
   401	                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
   402	                  <button
   403	                    type="button"
   404	                    aria-pressed={analistaId == null}
   405	                    onClick={() => elegirAnalista(null)}
   406	                    className={cn(
   407	                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   408	                      analistaId == null ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   409	                    )}
   410	                  >
   411	                    Todos
   412	                  </button>
   413	                  {analistas.map((m) => (
   414	                    <button
   415	                      key={m.perfil_id}
   416	                      type="button"
   417	                      aria-pressed={analistaId === m.perfil_id}
   418	                      aria-label={m.nombre_completo}
   419	                      onClick={() => elegirAnalista(m.perfil_id)}
   420	                      className={cn(
   421	                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   422	                        analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   423	                      )}
   424	                    >
   425	                      {primerNombre(m.nombre_completo)}
   426	                    </button>
   427	                  ))}
   428	                </div>
   429	              )}
   430	
   431	              {abriendo && <p role="status" className="px-5 pb-2 text-xs text-muted-foreground">Abriendo ficha…</p>}
   432	              {errorApertura && <p role="alert" className="px-5 pb-2 text-xs text-destructive-text">No se pudo abrir la ficha. Vuelve a intentarlo.</p>}
   433	
   434	              <div
   435	                id={`${idPanelCola}-panel`}
   436	                role="tabpanel"
   437	                aria-labelledby={`${idPanelCola}-tab-${pestana}`}
   438	                tabIndex={paginaVigente && paginaVigente.items.length > 0 ? undefined : 0}
   439	                className="flex flex-1 flex-col"
   440	              >
   441	                {consultaCola.error ? (
   442	                  <div role="alert" className="flex flex-wrap items-center justify-between gap-3 border-t border-border/60 px-5 py-4">
   443	                    <p className="text-sm">No se pudo cargar la cola. Los pendientes todavía no están confirmados.</p>
   444	                    <Button variant="outline" size="sm" onClick={() => void consultaCola.refetch()}>
   445	                      <RefreshCw aria-hidden /> Reintentar
   446	                    </Button>
   447	                  </div>
   448	                ) : !pagina ? (
   449	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
   450	                ) : !paginaVigente ? (
   451	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   452	                    {pagina.modo !== 'activo'
   453	                      ? 'Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.'
   454	                      : 'Actualizando los pendientes con las reglas vigentes…'}
   455	                  </p>
   456	                ) : paginaVigente.items.length === 0 ? (
   457	                  <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   458	                    {nombreAnalista ? `${primerNombre(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
   459	                  </p>
   460	                ) : (
   461	                  <ul aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
   462	                    {paginaVigente.items.map((item) => {
   463	                      const leadStore = leadPorId.get(item.lead_id)
   464	                      const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
   465	                      const analistaFila = item.lead.analista_nombre ? primerNombre(item.lead.analista_nombre) : 'Sin analista'
   466	                      const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
   467	                      const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
   468	                      return (
   469	                        <li
   470	                          key={item.lead_id}
   471	                          data-sev={item.severidad}
   472	                          className="flex items-center gap-2 border-l-[3px] border-t border-t-border/60 pr-5"
   473	                          style={{ borderLeftColor: colorTira }}
   474	                        >
   475	                          <button
   476	                            type="button"
   477	                            disabled={abriendo !== null}
   478	                            onClick={() => void abrirFicha(item.lead_id)}
   479	                            // El nombre dicta TODO lo visible (dueño, estado, tiempo, monto):
   480	                            // un lector de pantalla no puede perder lo que se ve.
   481	                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}: ${estado}${monto ? `, ${monto}` : ''}`}
   482	                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 disabled:cursor-wait"
   483	                          >
   484	                            {analistaId == null && (
   485	                              <span className="flex w-[118px] shrink-0 items-center gap-2">
   486	                                <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
   487	                                <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
   488	                              </span>
   489	                            )}
   490	                            <span className="min-w-0 flex-1 leading-tight">
   491	                              <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
   492	                              <span className="block truncate text-xs text-muted-foreground">{estado}</span>
   493	                            </span>
   494	                            {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
   495	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   496	                          </button>
   497	                          {leadStore && <AccionesContacto lead={leadStore} compacto />}
   498	                        </li>
   499	                      )
   500	                    })}
   501	                  </ul>
   502	                )}
   503	                <div className="mt-auto flex items-center justify-between gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
   504	                  <span className="tabular-nums text-muted-foreground-strong">
   505	                    {paginaVigente && paginaVigente.items.length > 0
   506	                      ? `${numero(paginaVigente.items.length)} de ${numero(paginaVigente.total_items)}`
   507	                      : ''}
   508	                  </span>
   509	                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   510	                    Ver todo en Seguimiento <ChevronRight className="size-3.5" aria-hidden />
   511	                  </a>
   512	                </div>
   513	              </div>
   514	            </>
   515	          )}
   516	        </Card>
   517	
   518	        {/* ── Equipo hoy: tocar a alguien filtra la cola y despliega sus señales ── */}
   519	        <Card className="min-w-0 overflow-hidden lg:col-span-2">
   520	          <SectionHead
   521	            icon={UsersRound}
   522	            title="Equipo hoy"
   523	            right={(
   524	              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center rounded-md px-1 text-xs font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   525	                Mi equipo hoy →
   526	              </a>
   527	            )}
   528	          />
   529	          {rank != null && rank.length > 0 && (semaforoEquipo.rojo > 0 || semaforoEquipo.ambar > 0 || datos.agendaConfirmada != null) && (
   530	            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
   531	              {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
   532	                // Solo con la agenda confirmada: sin ella, cero señales es desconocido.
   533	                ? 'Sin alertas en el equipo'
   534	                : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
   535	            </p>
   536	          )}
   537	          {datos.errorAgenda && (
   538	            <div role="alert" className="mx-5 mb-2 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-warning-text/30 bg-warning-text/5 px-3 py-2">
   539	              <p className="text-xs">La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.</p>
   540	              <Button variant="outline" size="sm" onClick={datos.recargarAgenda}>
   541	                <RefreshCw aria-hidden /> Reintentar
   542	              </Button>
   543	            </div>
   544	          )}
   545	          {rank == null ? (
   546	            <CardContent className="pb-5 pt-0">
   547	              <p className="text-sm text-muted-foreground">
   548	                {datos.vendedoresOp.error
   549	                  ? 'El resumen por analista no está disponible en este momento.'
   550	                  : 'Cargando el resumen por analista…'}
   551	              </p>
   552	            </CardContent>
   553	          ) : rank.length === 0 ? (
   554	            <CardContent className="pb-5 pt-0">
   555	              <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   556	            </CardContent>
   557	          ) : (
   558	            <ul aria-label="Analistas del equipo" className="border-t border-border/60">
   559	              {rank.map((r) => {
   560	                const id = r.m.perfil_id
   561	                const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
   562	                const rezago = rezagosConfirmados.get(id)
   563	                const abierto = analistaId === id
   564	                const principal = lectura.senales[0]?.texto
   565	                  ?? (r.activos === 0
   566	                    ? 'Sin leads abiertos'
   567	                    : rezago != null ? 'Al día' : `Última actividad ${haceTexto(r.diasSinActividadMax)}`)
   568	                const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   569	                const idDetalle = `${idPanelCola}-equipo-${id}`
   570	                const conversion = r.conversion == null
   571	                  ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
   572	                  : `${textoConversionOperativa(r.conversion)} conversión`
   573	                return (
   574	                  <li key={id} className="border-b border-border/60 last:border-b-0">
   575	                    <button
   576	                      type="button"
   577	                      aria-expanded={abierto}
   578	                      aria-controls={idDetalle}
   579	                      aria-label={`${r.m.nombre_completo}: ${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
   580	                      onClick={() => elegirAnalista(id)}
   581	                      className={cn(
   582	                        'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
   583	                        abierto && 'bg-accent/[0.08]',
   584	                      )}
   585	                    >
   586	                      {lectura.nivel != null
   587	                        ? <span data-testid="equipo-semaforo" data-nivel={lectura.nivel} className="size-2 shrink-0 rounded-full" style={{ background: COLOR_NIVEL[lectura.nivel] }} aria-hidden />
   588	                        : <span className="size-2 shrink-0" aria-hidden />}
   589	                      <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
   590	                      <span className="min-w-0 flex-1 leading-tight">
   591	                        <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
   592	                        <span className="block truncate text-xs text-muted-foreground-strong">{principal}</span>
   593	                      </span>
   594	                      <span className="shrink-0 text-right leading-tight">
   595	                        <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
   596	                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
   597	                      </span>
   598	                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierto ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
   599	                    </button>
   600	                    <div id={idDetalle} hidden={!abierto} className="space-y-1.5 px-5 pb-3 pl-[62px]">
   601	                      {lectura.senales.length > 1 && (
   602	                        <div className="flex flex-wrap gap-1.5">
   603	                          {lectura.senales.slice(1).map((s) => <ChipSenal key={s.texto} texto={s.texto} nivel={s.nivel} />)}
   604	                        </div>
   605	                      )}
   606	                      <p className="text-xs tabular-nums text-muted-foreground-strong">
   607	                        {numero(r.activos)} activos · {conversion}
   608	                        {r.operacionesCartera != null && r.operacionesCartera > 0 ? ` · ${numero(r.operacionesCartera)} de cartera` : ''}
   609	                        {r.sinTocar > 0 ? ` · ${numero(r.sinTocar)} sin tocar` : ''}
   610	                      </p>
   611	                      {rezago != null && (
   612	                        <p className="text-xs tabular-nums text-muted-foreground-strong">
   613	                          {rezago.toques > 0
   614	                            ? `${numero(rezago.toques)} toques en 7 días${rezago.pct_completadas != null ? ` · ${Math.round(rezago.pct_completadas)} % completadas` : ''}`
   615	                            : 'Sin toques registrados en 7 días'}
   616	                        </p>
   617	                      )}
   618	                    </div>
   619	                  </li>
   620	                )
   621	              })}
   622	            </ul>
   623	          )}
   624	        </Card>
   625	      </div>
   626	
   627	      {/* ── 3 · Consulta: cifras en una línea; «Detalle» abre todo lo demás ── */}
   628	      <section aria-label="Consulta" className="flex min-h-12 flex-wrap items-center gap-x-5 gap-y-1.5 rounded-xl border border-border bg-card px-5 py-2">
   629	        <span className="text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground-strong" aria-hidden>Consulta</span>
   630	        <ul aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
   631	          <li>
   632	            <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
   633	            {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
   634	          </li>
   635	          <li><strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos</li>
   636	          <li><strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta</li>
   637	          <li><strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes</li>
   638	          <li aria-hidden className="h-[18px] w-px bg-border" />
   639	          <li><strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días</li>
   640	          <li><strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas</li>
   641	          <li>
   642	            <strong
   643	              className="font-extrabold"
   644	              style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
   645	            >
   646	              {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
   647	            </strong> no asistió
   648	          </li>
   649	        </ul>
   650	        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent" onClick={() => setDetalleAbierto(true)}>
   651	          Detalle
   652	        </Button>
   653	      </section>
   654	
   655	      <Dialog
   656	        open={detalleAbierto}
   657	        onClose={() => setDetalleAbierto(false)}
   658	        className="w-[1180px] max-h-[88vh] max-w-[94vw]"
   659	      >
   660	        <DialogHeader>
   661	          <DialogTitle>Detalle del equipo</DialogTitle>
   662	          <DialogDescription>Indicadores, cumplimiento del mes y agenda de los últimos 7 días.</DialogDescription>
   663	        </DialogHeader>
   664	        <DialogBody className="space-y-4">
   665	          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   666	            {/* Pronóstico: `capitalPrincipal`, NUNCA un total mixto con los dólares. */}
   667	            <KpiCard
   668	              label="Pronóstico de capital abierto"
   669	              value={pronostico ? pronostico.valor : '—'}
   670	              icon={Wallet}
   671	              color={SEMAFORO.neutro}
   672	              sub={
   673	                pronostico?.otra
   674	                  ? `En soles · +${pronostico.otra} aparte`
   675	                  : pronostico?.soloDolares
   676	                    ? 'En dólares · abiertos con analista'
   677	                    : datos.resumen && datos.resumen.capital.asignado.pen === 0 && datos.resumen.totales.asignados > 0
   678	                      ? 'Sin montos estimados — complétalos en cada ficha'
   679	                      : 'En soles · abiertos con analista'
   680	              }
   681	            />
   682	            <KpiCard
   683	              label="Leads activos del equipo"
   684	              value={datos.resumen ? String(datos.resumen.totales.asignados) : '—'}
   685	              icon={Users}
   686	              color={SEMAFORO.neutro}
   687	              sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
   688	              delay={60}
   689	            />
   690	            <KpiCard
   691	              label="Primeras gestiones vencidas"
   692	              value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
   693	              icon={AlertTriangle}
   694	              color={SEMAFORO.neutro}
   695	              sub={primeraGestionPendiente == null
   696	                ? 'Sin dato por ahora'
   697	                : primeraGestionPendiente > 0 ? 'Revísalas con cada analista' : 'Ninguna vencida'}
   698	              delay={120}
   699	            />
   700	            <a
   701	              href={hashDe('derivaciones')}
   702	              aria-label={datos.etiquetaAccesoReparto}
   703	              className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
   704	            >
   705	              <KpiCard
   706	                label="Por repartir"
   707	                value={datos.totalPorRepartir == null ? '—' : String(datos.totalPorRepartir)}
   708	                icon={Inbox}
   709	                color={SEMAFORO.neutro}
   710	                sub={datos.detalleReparto}
   711	                delay={180}
   712	              />
   713	            </a>
   714	          </div>
   715	
   716	          <div className="grid gap-4 lg:grid-cols-5">
   717	            <Card className="lg:col-span-2">
   718	              <SectionHead
   719	                icon={Target}
   720	                title="Cumplimiento del mes"
   721	                right={tc ? <span className="text-xs text-muted-foreground-strong">{rotuloTipoCambio(tc.promedio, tc.fuente)}</span> : undefined}
   722	              />
   723	              <CardContent className="space-y-4 pb-5 pt-0">
   724	                {datos.filasMeta.map((f) => (
   725	                  <div key={f.label}>
   726	                    <div className="mb-1.5 flex items-baseline justify-between gap-2">
   727	                      <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
   728	                      <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
   729	                    </div>
   730	                    {f.nota && <p className="mb-1 text-[11px] tabular-nums text-muted-foreground-strong">{f.nota}</p>}
   731	                    {f.sinDato
   732	                      ? <p className="text-[11px] text-muted-foreground-strong">{f.sinDato}</p>
   733	                      : <Progress value={f.pct} color={colorMeta(f.pct)} />}
   734	                  </div>
   735	                ))}
   736	                <p className="text-[11px] text-muted-foreground-strong">
   737	                  El capital en dólares entra al total convertido a tipo de cambio real. El pronóstico no cuenta como cumplimiento.
   738	                </p>
   739	                {datos.hayErrorMensual && (
   740	                  <Button variant="ghost" size="sm" onClick={datos.reintentarMensual}>
   741	                    Reintentar
   742	                  </Button>
   743	                )}
   744	              </CardContent>
   745	            </Card>
   746	            <div className="min-w-0 lg:col-span-3">
   747	              <AgendaEquipoPanel
   748	                datos={datos.datosAgenda}
   749	                cargando={datos.cargandoAgenda}
   750	                error={datos.errorAgenda}
   751	                modoDemo={yo?.demo === true}
   752	                onReintentar={datos.recargarAgenda}
   753	                equipo={datos.equipo}
   754	              />
   755	            </div>
   756	          </div>
   757	
   758	          {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC). */}
   759	          <DesglosePorEmpresa demo={yo?.demo === true} porVendedor={datos.cumplimientoMensual?.porVendedor ?? null} />
   760	          {/* Rentabilidad R3: las solicitudes de tasa propias en curso (solo si hay). */}
   761	          <TasasAutorizadasAnalistaPanel />
   762	          <p className="text-[11px] text-muted-foreground-strong">
   763	            Ves solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
   764	          </p>
   765	        </DialogBody>
   766	        <DialogFooter>
   767	          <Button variant="outline" size="sm" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
   768	        </DialogFooter>
   769	      </Dialog>
   770	    </div>
   771	  )
   772	}
   773	
   774	/** El botón de acción de una decisión. Nunca va DENTRO del botón que la despliega. */
   775	function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
   776	  cosa: CosaDeHoy
   777	  onVerPrimeraGestion: () => void
   778	  etiquetaReparto: string
   779	}): JSX.Element {
   780	  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
   781	  if (cosa.id === 'primera_gestion') {
   782	    return (
   783	      <button type="button" className={clase} aria-label={`Ver las ${cosa.texto} en la cola`} onClick={onVerPrimeraGestion}>
   784	        Ver <ChevronRight className="size-3.5" aria-hidden />
   785	      </button>
   786	    )
   787	  }
   788	  if (cosa.id === 'por_repartir') {
   789	    return (
   790	      <a href={hashDe('derivaciones')} className={clase} aria-label={etiquetaReparto}>
   791	        Repartir <ChevronRight className="size-3.5" aria-hidden />
   792	      </a>
   793	    )
   794	  }
   795	  if (cosa.id === 'no_asistio' || cosa.id === 'sin_accion') {
   796	    // La cola no contiene citas ni leads «sin próxima acción»: filtrarla
   797	    // enseñaría OTROS casos. La decisión se toma viendo el día del equipo.
   798	    const label = cosa.vendedorId != null ? 'Ver su día' : 'Ver el equipo'
   799	    return (
   800	      <a href={hashDe('gestion-diaria')} className={clase} aria-label={`${label}: ${cosa.texto}`}>
   801	        {label} <ChevronRight className="size-3.5" aria-hidden />
   802	      </a>
   803	    )
   804	  }
   805	  // Candidatos del modo legado: aquí no aparecen (la cola legada llega null),
   806	  // pero si algún día lo hicieran, su lugar es el módulo de seguimiento.
   807	  return (
   808	    <a href={hashDe('seguimiento')} className={clase} aria-label={`${cosa.accion}: ${cosa.texto}`}>
   809	      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
   810	    </a>
   811	  )
   812	}
   813	
   814	function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVerPrimeraGestion, etiquetaReparto }: {
   815	  cosa: CosaDeHoy
   816	  abierta: boolean
   817	  contexto: string | null
   818	  idContexto: string
   819	  onAlternar: () => void
   820	  onVerPrimeraGestion: () => void
   821	  etiquetaReparto: string
   822	}): JSX.Element {
   823	  const { cifra, resto } = partesDeCosa(cosa.texto)
   824	  return (
   825	    <Card
   826	      data-decision={cosa.id}
   827	      className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')}
   828	      style={{ borderLeftColor: SEV_BORDE[cosa.severidad] }}
   829	    >
   830	      <div className="flex items-center gap-2 py-2 pl-4 pr-3">
   831	        <button
   832	          type="button"
   833	          aria-expanded={abierta}
   834	          aria-controls={idContexto}
   835	          aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto}`}
   836	          onClick={onAlternar}
   837	          className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 rounded-md text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
   838	        >
   839	          {cifra && (
   840	            <span className="min-w-10 text-[32px] font-extrabold leading-none tracking-tight tabular-nums text-primary">{cifra}</span>
   841	          )}
   842	          <span className="min-w-0 flex-1 leading-tight">
   843	            <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: SEV_TEXTO_COLOR[cosa.severidad] }}>
   844	              {SEV_TEXTO[cosa.severidad]}
   845	            </span>
   846	            <span className="block truncate text-[15px] font-bold" title={resto}>{resto}</span>
   847	          </span>
   848	          <ChevronRight
   849	            className={cn('size-4 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')}
   850	            aria-hidden
   851	          />
   852	        </button>
   853	        <AccionDecision cosa={cosa} onVerPrimeraGestion={onVerPrimeraGestion} etiquetaReparto={etiquetaReparto} />
   854	      </div>
   855	      <p id={idContexto} hidden={!abierta} className="border-t border-border/60 px-4 py-2.5 text-xs text-muted-foreground-strong">
   856	        {contexto ?? 'Sin más detalle confirmado por ahora.'}
   857	      </p>
   858	    </Card>
   859	  )
   860	}
   861	
   862	/** «Esta semana · N»: lo que no entró en las tres tarjetas. Esc y clic fuera lo cierran. */
   863	function EstaSemana({ cosas, onVerPrimeraGestion }: { cosas: CosaDeHoy[]; onVerPrimeraGestion: () => void }): JSX.Element {
   864	  const [abierto, setAbierto] = useState(false)
   865	  const contenedor = useRef<HTMLDivElement>(null)
   866	  const disparador = useRef<HTMLButtonElement>(null)
   867	  const idLista = useId()
   868	  useEffect(() => {
   869	    if (!abierto) return
   870	    const fuera = (e: PointerEvent) => {
   871	      if (!contenedor.current?.contains(e.target as Node)) setAbierto(false)
   872	    }
   873	    // Esc cierra y devuelve el foco al disparador, esté donde esté el foco
   874	    // dentro de la lista (y también si quedó fuera: el popover no atrapa).
   875	    const escape = (e: KeyboardEvent) => {
   876	      if (e.key !== 'Escape') return
   877	      setAbierto(false)
   878	      if (contenedor.current?.contains(document.activeElement)) disparador.current?.focus()
   879	    }
   880	    document.addEventListener('pointerdown', fuera)
   881	    document.addEventListener('keydown', escape)
   882	    return () => {
   883	      document.removeEventListener('pointerdown', fuera)
   884	      document.removeEventListener('keydown', escape)
   885	    }
   886	  }, [abierto])
   887	  return (
   888	    <div ref={contenedor} className="relative">
   889	      <button
   890	        ref={disparador}
   891	        type="button"
   892	        aria-expanded={abierto}
   893	        aria-controls={idLista}
   894	        onClick={() => setAbierto((v) => !v)}
   895	        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
   896	      >
   897	        <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
   898	        Esta semana · {cosas.length}
   899	        <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
   900	      </button>
   901	      <ul
   902	        id={idLista}
   903	        hidden={!abierto}
   904	        aria-label="Decisiones para esta semana"
   905	        className="ac-pop absolute right-0 top-11 z-20 w-[340px] max-w-[90vw] rounded-xl border border-border bg-card p-2 shadow-[var(--shadow-pop)]"
   906	      >
   907	        {cosas.map((c) => (
   908	          <li key={c.id} className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-xs font-semibold">
   909	            <span className="size-2 shrink-0 rounded-full" style={{ background: SEV_BORDE[c.severidad] }} aria-hidden />
   910	            <span className="min-w-0 flex-1">
   911	              <span className="sr-only">{SEV_TEXTO[c.severidad]}: </span>{c.texto}
   912	            </span>
   913	            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={`Repartir: ${c.texto}`} />
   914	          </li>
   915	        ))}
   916	      </ul>
   917	    </div>
   918	  )
   919	}
```

## `app/src/lib/tres-cosas.ts` (estado FINAL completo)
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

## `app/src/lib/senal-equipo.ts` (estado FINAL completo)
```
     1	// lib/senal-equipo.ts — la lectura de UN analista en «Equipo hoy» (Hoy del
     2	// supervisor, puesto de mando, 27/09/2026). Una sola severidad por persona:
     3	// el punto, la cabecera («N en rojo · N en ámbar») y los chips salen de aquí,
     4	// así nunca se contradicen. El borrador del diseño contaba a una persona en
     5	// rojo Y en ámbar a la vez, y pintaba ámbar un no-show repetido que su chip
     6	// decía rojo (Codex, revisión del plan).
     7	//
     8	// Umbrales de la casa, sin cambios (lib/semaforo.ts, «Tu equipo hoy»):
     9	// · días sin actividad del lead más quieto: 2–5 ámbar · >5 rojo;
    10	// · citas sin asistir: ≥2 rojo (una sola no es patrón);
    11	// · leads sin próxima acción: ≥1 ámbar · ≥5 rojo (umbral de la campana);
    12	// · tareas vencidas: ámbar.
    13	// La severidad del analista es la PEOR de sus señales: nunca se rebaja. Las
    14	// señales de AGENDA valen aunque su cartera abierta haya llegado a cero (un
    15	// patrón de no-shows de esta semana no desaparece por cerrar leads); solo la de
    16	// días sin actividad exige leads abiertos. Neutro = sin cartera Y sin señales.
    17	import type { MetricaAgendaVendedor } from './metricas-agenda'
    18	import { haceTexto } from './inteligencia'
    19	
    20	export type NivelSenal = 'critico' | 'atencion'
    21	
    22	export interface SenalAnalista {
    23	  texto: string
    24	  nivel: NivelSenal
    25	}
    26	
    27	export interface LecturaAnalista {
    28	  /** null = sin señal · 'neutro' = sin cartera abierta: no hay nada que medir. */
    29	  nivel: NivelSenal | 'neutro' | null
    30	  /** Rojas primero; dentro de cada nivel, el orden fijo de arriba. */
    31	  senales: SenalAnalista[]
    32	}
    33	
    34	export type RezagoAgenda = Pick<MetricaAgendaVendedor, 'no_asistio' | 'leads_sin_accion' | 'vencidas'>
    35	
    36	/**
    37	 * `rezago` null = la agenda no llegó (o el analista no tiene fila): solo se
    38	 * juzga lo que hay, sin inventar «al día».
    39	 */
    40	export function lecturaAnalista(
    41	  fila: { activos: number; diasSinActividadMax: number },
    42	  rezago: RezagoAgenda | null | undefined,
    43	): LecturaAnalista {
    44	  const senales: SenalAnalista[] = []
    45	  if (rezago != null && rezago.no_asistio >= 2) {
    46	    senales.push({ texto: `${rezago.no_asistio} citas sin asistir`, nivel: 'critico' })
    47	  }
    48	  if (rezago != null && rezago.leads_sin_accion > 0) {
    49	    const n = rezago.leads_sin_accion
    50	    senales.push({
    51	      texto: `${n} ${n === 1 ? 'lead' : 'leads'} sin próxima acción`,
    52	      nivel: n >= 5 ? 'critico' : 'atencion',
    53	    })
    54	  }
    55	  const dias = fila.diasSinActividadMax
    56	  if (fila.activos > 0 && dias >= 2) {
    57	    senales.push({ texto: `Un lead sin actividad ${haceTexto(dias)}`, nivel: dias > 5 ? 'critico' : 'atencion' })
    58	  }
    59	  if (rezago != null && rezago.vencidas > 0) {
    60	    const n = rezago.vencidas
    61	    senales.push({ texto: `${n} ${n === 1 ? 'tarea vencida' : 'tareas vencidas'}`, nivel: 'atencion' })
    62	  }
    63	  // sort estable: las rojas suben y cada nivel conserva el orden de arriba.
    64	  senales.sort((a, b) => (a.nivel === b.nivel ? 0 : a.nivel === 'critico' ? -1 : 1))
    65	  if (senales.length === 0) return { nivel: fila.activos === 0 ? 'neutro' : null, senales }
    66	  return { nivel: senales[0]?.nivel ?? null, senales }
    67	}
    68	
    69	/** Conteo EXCLUSIVO de la cabecera: cada analista cuenta una sola vez. */
    70	export function conteoSemaforoEquipo(lecturas: readonly LecturaAnalista[]): { rojo: number; ambar: number } {
    71	  let rojo = 0
    72	  let ambar = 0
    73	  for (const l of lecturas) {
    74	    if (l.nivel === 'critico') rojo += 1
    75	    else if (l.nivel === 'atencion') ambar += 1
    76	  }
    77	  return { rojo, ambar }
    78	}
```

## `app/src/screens/hoy/supervisor-mando.test.tsx` (estado FINAL completo)
```
     1	// Hoy · supervisor — puesto de mando (27/09/2026). Se prueba en el MUNDO DE
     2	// PRODUCCIÓN: seguimiento ACTIVO (la cola legada no se consulta), sin metas
     3	// publicadas y con la agenda que llegue o no llegue. La derivación compartida
     4	// (./datos-supervisor.ts) corre de verdad sobre los mismos mocks que usa
     5	// supervisor.test.tsx; lo que se sustituye es la red.
     6	import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
     7	import { act, fireEvent, render, screen, within } from '@testing-library/react'
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
    49	let AGENDA_ERROR: Error | null = null
    50	const REFETCH_AGENDA = vi.fn()
    51	vi.mock('@/data/crm-queries', () => ({
    52	  useSolicitudesTasa: () => ({ data: [], isPending: false, isError: false, refetch: () => {} }),
    53	  useResolverSolicitudTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    54	  useResponderTopeTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    55	  useResolucionTasa: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
    56	  useSolicitarTasa: () => ({ mutateAsync: async () => ({}), isPending: false }),
    57	  useHistorialTasaCliente: () => ({ data: undefined, isPending: false, isError: false, refetch: () => {} }),
    58	  useMetricasAgenda: () => ({ data: METRICAS_AGENDA, error: AGENDA_ERROR, isPending: false, isFetching: false, refetch: REFETCH_AGENDA }),
    59	  useConversionMensual: () => ({ data: undefined, isError: false, isPending: false, isFetching: false, refetch: vi.fn() }),
    60	  useCierresExternos: () => ({ data: undefined, isError: false, isPending: false, isFetching: false, refetch: () => {} }),
    61	}))
    62	vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))
    63	vi.mock('@/data/use-resumen-cartera-operativo', async () => {
    64	  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
    65	  return {
    66	    useResumenCarteraOperativo: (leads: Lead[], actividades: Actividad[]) => ({
    67	      resumen: resumenCarteraDesdeAmbito(leads, actividades ?? [], Date.now()),
    68	      cargando: false, error: null, recargar: vi.fn(),
    69	    }),
    70	  }
    71	})
    72	vi.mock('@/data/use-metricas-vendedores-operativas', async () => {
    73	  const { metricasVendedoresDesdeAmbito } = await import('@/lib/metricas-vendedores')
    74	  return {
    75	    useMetricasVendedoresOperativas: (roster: Miembro[], equipo: Miembro[], leads: Lead[], actividades: Actividad[]) => ({
    76	      metricas: metricasVendedoresDesdeAmbito(roster ?? [], equipo ?? [], leads ?? [], actividades ?? [], Date.now()),
    77	      cargando: false, error: null, recargar: vi.fn(),
    78	    }),
    79	  }
    80	})
    81	
    82	// ── Seguimiento activo: modo + cola del servidor, controlables por prueba ──
    83	const MODO = { legado: false, activo: true, error: null as Error | null, data: { control_revision: 1 } as { control_revision: number } | undefined }
    84	const REFETCH_MODO = vi.fn()
    85	type RespuestaCola = { data: ColaSlaPagina | undefined; error: Error | null; isFetching: boolean }
    86	let RESPONDER: (filtros: FiltrosSla) => RespuestaCola = () => ({ data: undefined, error: null, isFetching: false })
    87	const REFETCH_COLA = vi.fn()
    88	const pedidosCola: Array<{ filtros: FiltrosSla; limite: number; habilitada: boolean }> = []
    89	vi.mock('@/data/sla-operacion-queries', () => ({
    90	  useModoSla: () => ({ ...MODO, refetch: REFETCH_MODO }),
    91	  useColaSlaPagina: (filtros: FiltrosSla, _cursor: unknown, limite: number, habilitada: boolean) => {
    92	    pedidosCola.push({ filtros, limite, habilitada })
    93	    return { ...RESPONDER(filtros), refetch: REFETCH_COLA }
    94	  },
    95	}))
    96	
    97	const { HoySupervisorMando } = await import('./supervisor-mando')
    98	
    99	/** Cada render pide la cola (con el filtro por analista) y luego la del equipo (sin él). */
   100	const pedidoCola = () => pedidosCola.at(-2)
   101	const pedidoEquipo = () => pedidosCola.at(-1)
   102	
   103	const KAREN = 'aaaaaaaa-0000-4000-8000-000000000001'
   104	const JORGE = 'aaaaaaaa-0000-4000-8000-000000000002'
   105	
   106	function miembro(id: string, nombre: string, over: Partial<Miembro> = {}): Miembro {
   107	  return { perfil_id: id, nombre_completo: nombre, rol_crm: 'vendedor', supervisor_id: 's-1', activo: true, ...over }
   108	}
   109	
   110	function lead(over: Partial<Lead> = {}): Lead {
   111	  return {
   112	    id: 'l-1', nombre_completo: 'ROSA CHÁVEZ', telefono: '+51987654321', etapa: 'contactado', origen: 'referido',
   113	    monto_estimado: 20_000, moneda: 'PEN', vendedor_id: KAREN, creado_en: '2026-09-20T15:00:00Z', activo: true, ...over,
   114	  }
   115	}
   116	
   117	type ItemCola = ColaSlaPagina['items'][number]
   118	function item(over: { lead_id: string; nombre: string; analistaId: string | null; analista: string | null; bucket?: string; severidad?: ItemCola['severidad']; referencia_en?: string | null }): ItemCola {
   119	  return {
   120	    lead_id: over.lead_id,
   121	    bucket: over.bucket ?? 'primera_atencion',
   122	    severidad: over.severidad ?? 'critica',
   123	    prioridad: 10,
   124	    referencia_en: over.referencia_en === undefined ? '2026-09-24T15:00:00Z' : over.referencia_en,
   125	    tarea_id: null,
   126	    lead: { id: over.lead_id, nombre_completo: over.nombre, etapa: 'nuevo', analista_id: over.analistaId, analista_nombre: over.analista },
   127	    senales: { pendientes: true, primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
   128	  } as unknown as ItemCola
   129	}
   130	
   131	const TOTALES_CERO = { pendientes: 0, primera_atencion: 0, tareas_vencidas: 0, seguimientos_pendientes: 0, revisiones: 0, datos_incompletos: 0, por_repartir: 0 }
   132	function pagina(items: ItemCola[], over: Partial<Omit<ColaSlaPagina, 'totales'>> & { totales?: Partial<ColaSlaPagina['totales']> } = {}): ColaSlaPagina {
   133	  const { totales, ...resto } = over
   134	  return {
   135	    version: 2, modo: 'activo', control_revision: 1, calculado_en: '2026-09-26T15:00:00Z', modelo_avisos: 3,
   136	    filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7,
   137	    total_items: items.length, hay_mas: false, cursor_siguiente: null, rango: { desde: 1, hasta: items.length },
   138	    totales: { ...TOTALES_CERO, ...totales },
   139	    items,
   140	    ...resto,
   141	  } as ColaSlaPagina
   142	}
   143	
   144	function agenda(vendedores: Array<Partial<MetricaAgendaVendedor> & { vendedor_id: string; nombre: string }>): MetricasAgenda {
   145	  return {
   146	    version: 1, generado_en: '2026-09-26T15:00:00Z',
   147	    periodo: { desde: '2026-09-20', hasta: '2026-09-26', dias: 7, zona: 'America/Lima' },
   148	    vendedores: vendedores.map((v) => ({
   149	      rol: 'vendedor', activo: true, toques: 0, toques_por_dia: 0, reuniones_realizadas: 0, completadas: 0, no_asistio: 0,
   150	      canceladas: 0, pct_completadas: null, tareas_creadas: 0, reuniones_agendadas: 0, reprogramaciones: 0, pendientes: 0,
   151	      vencidas: 0, leads_sin_accion: 0, ...v,
   152	    })),
   153	  } as MetricasAgenda
   154	}
   155	
   156	function montar(): ReturnType<typeof render> {
   157	  vi.setSystemTime(AHORA)
   158	  YO = { id: 's-1', nombre_completo: 'SUPERVISOR UNO', rol: 'supervisor', demo: false, puede_contratar: true }
   159	  return render(<HoySupervisorMando />)
   160	}
   161	
   162	const colaTodo = () => [
   163	  item({ lead_id: 'l-1', nombre: 'ROSA CHÁVEZ', analistaId: KAREN, analista: 'KAREN ZAPATA' }),
   164	  item({ lead_id: 'l-2', nombre: 'VÍCTOR PALOMINO', analistaId: JORGE, analista: 'JORGE HUAMÁN', bucket: 'tarea_vencida', severidad: 'critica', referencia_en: '2026-09-26T12:00:00Z' }),
   165	  item({ lead_id: 'l-3', nombre: 'MARTHA SOTO', analistaId: KAREN, analista: 'KAREN ZAPATA', bucket: 'seguimiento', severidad: 'media', referencia_en: '2026-09-26T18:00:00Z' }),
   166	]
   167	
   168	beforeEach(() => {
   169	  vi.useFakeTimers()
   170	  vi.clearAllMocks()
   171	  recargar.mockResolvedValue(true)
   172	  abrirLead.mockResolvedValue(true)
   173	  pedidosCola.length = 0
   174	  MODO.legado = false
   175	  MODO.activo = true
   176	  MODO.error = null
   177	  MODO.data = { control_revision: 1 }
   178	  VENDEDORES = [
   179	    miembro(KAREN, 'KAREN ZAPATA'),
   180	    miembro(JORGE, 'JORGE HUAMÁN'),
   181	    miembro('v-ex', 'EX ANALISTA', { activo: false }),
   182	  ]
   183	  LEADS = [lead(), lead({ id: 'l-3', nombre_completo: 'MARTHA SOTO', monto_estimado: 15_000, moneda: 'USD' })]
   184	  OBJETIVOS = objetivosCero('2026-09-01')
   185	  CUMPLIMIENTO = null
   186	  METRICAS_AGENDA = agenda([{ vendedor_id: KAREN, nombre: 'KAREN ZAPATA' }, { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' }])
   187	  AGENDA_ERROR = null
   188	  RESPONDER = (filtros) => {
   189	    const todas = colaTodo().filter((i) => filtros.analista_id == null || i.lead.analista_id === filtros.analista_id)
   190	    return {
   191	      data: pagina(todas, {
   192	        filtros: { ...filtros },
   193	        totales: { pendientes: todas.length, primera_atencion: todas.filter((i) => i.bucket === 'primera_atencion').length, tareas_vencidas: todas.filter((i) => i.bucket === 'tarea_vencida').length },
   194	      }),
   195	      error: null,
   196	      isFetching: false,
   197	    }
   198	  }
   199	})
   200	
   201	afterEach(() => {
   202	  vi.useRealTimers()
   203	})
   204	
   205	describe('Hoy · supervisor — puesto de mando: qué pantalla se elige', () => {
   206	  it('en modo LEGADO (demo o seguimiento apagado) sigue la pantalla clásica', () => {
   207	    MODO.legado = true
   208	    MODO.activo = false
   209	    montar()
   210	    expect(screen.getByText('Pantalla clásica del supervisor')).toBeInTheDocument()
   211	    expect(pedidosCola).toHaveLength(0)
   212	  })
   213	
   214	  it('mientras el modo se consulta no pide la cola ni inventa pendientes', () => {
   215	    MODO.activo = false
   216	    MODO.data = undefined
   217	    montar()
   218	    expect(screen.getByText('Consultando el seguimiento comercial…')).toHaveAttribute('role', 'status')
   219	    expect(screen.queryByRole('tablist')).not.toBeInTheDocument()
   220	    expect(pedidosCola.every((p) => !p.habilitada)).toBe(true)
   221	  })
   222	
   223	  it('si el modo falla lo dice y deja reintentar', () => {
   224	    MODO.activo = false
   225	    MODO.error = new Error('caído')
   226	    montar()
   227	    const alerta = screen.getByRole('alert')
   228	    expect(alerta).toHaveTextContent('No se pudo cargar el seguimiento')
   229	    fireEvent.click(within(alerta).getByRole('button', { name: /Reintentar/ }))
   230	    expect(REFETCH_MODO).toHaveBeenCalledTimes(1)
   231	  })
   232	})
   233	
   234	describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', () => {
   235	  it('ESTADO DE PRODUCCIÓN: la cola sale del seguimiento con 7 filas, conteos del servidor y enlace al módulo', () => {
   236	    montar()
   237	    expect(pedidoCola()).toEqual({ filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7, habilitada: true })
   238	    expect(pedidoEquipo()).toEqual(pedidoCola())
   239	    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
   240	    const pestanas = screen.getByRole('tablist', { name: 'Filtrar los pendientes' })
   241	    expect(within(pestanas).getByRole('tab', { name: 'Para atender ahora: 3' })).toHaveAttribute('aria-selected', 'true')
   242	    expect(within(pestanas).getByRole('tab', { name: 'Primera gestión: 1' })).toBeInTheDocument()
   243	    expect(within(pestanas).getByRole('tab', { name: 'Tareas vencidas: 1' })).toBeInTheDocument()
   244	    // «Todas» no tiene total en `totales`: sin número hasta que se abre.
   245	    expect(within(pestanas).getByRole('tab', { name: 'Todas' })).toBeInTheDocument()
   246	    expect(screen.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
   247	    expect(screen.getByText('3 de 3')).toBeInTheDocument()
   248	  })
   249	
   250	  it('cada fila dice de quién es, en qué estado está y desde cuándo, con la severidad en la tira', () => {
   251	    montar()
   252	    const lista = screen.getByRole('list', { name: /Pendientes del equipo/ })
   253	    const filas = within(lista).getAllByRole('listitem')
   254	    expect(filas).toHaveLength(3)
   255	    expect(filas[0]).toHaveAttribute('data-sev', 'critica')
   256	    expect(filas[0]).toHaveTextContent('Karen')
   257	    expect(filas[0]).toHaveTextContent('Primera gestión pendiente · venció hace 2 días')
   258	    expect(filas[1]).toHaveTextContent('Actividad vencida · venció hace 3 horas')
   259	    expect(filas[2]).toHaveAttribute('data-sev', 'media')
   260	    expect(filas[2]).toHaveTextContent('Seguimiento pendiente · vence en 3 horas')
   261	  })
   262	
   263	  it('monto y contacto SOLO con el lead completo del store (caché parcial: desconocido no es cero)', () => {
   264	    montar()
   265	    const filas = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')
   266	    expect(filas[0]).toHaveTextContent('S/ 20k')
   267	    expect(within(filas[0]!).getAllByRole('link', { name: /ROSA CHÁVEZ/ }).length + within(filas[0]!).queryAllByRole('button', { name: /número de ROSA CHÁVEZ|Llamar a ROSA CHÁVEZ/ }).length).toBeGreaterThan(0)
   268	    // VÍCTOR no está en el store: ni monto ni acciones de contacto.
   269	    expect(filas[1]).not.toHaveTextContent(/S\/|US\$/)
   270	    expect(within(filas[1]!).getAllByRole('button')).toHaveLength(1)
   271	    expect(filas[2]).toHaveTextContent('US$ 15k')
   272	  })
   273	
   274	  it('una fila sin fecha de referencia lo dice en vez de inventar un tiempo', () => {
   275	    RESPONDER = () => ({ data: pagina([item({ lead_id: 'l-9', nombre: 'SIN FECHA', analistaId: KAREN, analista: 'KAREN ZAPATA', referencia_en: null })], { totales: { pendientes: 1 } }), error: null, isFetching: false })
   276	    montar()
   277	    expect(screen.getByText(/Primera gestión pendiente · sin fecha confirmada/)).toBeInTheDocument()
   278	  })
   279	
   280	  it('el filtro por analista lo hace el SERVIDOR y los conteos son los suyos', () => {
   281	    montar()
   282	    const chips = screen.getByRole('group', { name: 'Filtrar por analista' })
   283	    // Solo analistas activos del equipo, sin conteos inventados en el cliente.
   284	    expect(within(chips).getAllByRole('button').map((b) => b.textContent)).toEqual(['Todos', 'Jorge', 'Karen'])
   285	    fireEvent.click(within(chips).getByRole('button', { name: 'KAREN ZAPATA' }))
   286	    expect(pedidoCola()?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: KAREN })
   287	    // Las decisiones siguen mirando a TODO el equipo.
   288	    expect(pedidoEquipo()?.filtros.analista_id).toBeNull()
   289	    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
   290	    expect(screen.getByRole('tab', { name: 'Para atender ahora: 2' })).toBeInTheDocument()
   291	    expect(screen.getByText('Mostrando los pendientes de Karen')).toHaveAttribute('aria-live', 'polite')
   292	    // Con el filtro, la columna del analista sobra.
   293	    const filas = within(screen.getByRole('list', { name: /Pendientes de Karen/ })).getAllByRole('listitem')
   294	    expect(filas).toHaveLength(2)
   295	    fireEvent.click(within(chips).getByRole('button', { name: 'Todos' }))
   296	    expect(pedidoCola()?.filtros.analista_id).toBeNull()
   297	  })
   298	
   299	  it('las flechas recorren las pestañas, mueven el foco y piden la señal al servidor', () => {
   300	    montar()
   301	    const primera = screen.getByRole('tab', { name: /Para atender ahora/ })
   302	    primera.focus()
   303	    fireEvent.keyDown(primera, { key: 'ArrowRight' })
   304	    const segunda = screen.getByRole('tab', { name: /Primera gestión/ })
   305	    expect(segunda).toHaveAttribute('aria-selected', 'true')
   306	    expect(segunda).toHaveFocus()
   307	    expect(pedidoCola()?.filtros.senal).toBe('primera_atencion')
   308	    fireEvent.keyDown(segunda, { key: 'End' })
   309	    expect(screen.getByRole('tab', { name: /^Todas/ })).toHaveAttribute('aria-selected', 'true')
   310	    // Con «Todas» abierta, su total sí es del servidor.
   311	    expect(screen.getByRole('tab', { name: 'Todas: 3' })).toBeInTheDocument()
   312	    fireEvent.keyDown(screen.getByRole('tab', { name: 'Todas: 3' }), { key: 'Home' })
   313	    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveFocus()
   314	  })
   315	
   316	  it('fail-closed: con error NO enseña la cola retenida y deja reintentar', () => {
   317	    RESPONDER = () => ({ data: pagina(colaTodo(), { totales: { pendientes: 3 } }), error: new Error('refetch caído'), isFetching: false })
   318	    montar()
   319	    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
   320	    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
   321	    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('No se pudo cargar la cola'))
   322	    expect(alerta).toBeDefined()
   323	    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
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
   348	  it('una respuesta que ya no es del modo activo no se pinta como vigente', () => {
   349	    RESPONDER = () => ({ data: pagina(colaTodo(), { modo: 'legado' }), error: null, isFetching: false })
   350	    montar()
   351	    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
   352	    expect(screen.getByText(/Las reglas del seguimiento cambiaron/)).toBeInTheDocument()
   353	  })
   354	
   355	  it('cargando: lo dice, sin filas ni ceros', () => {
   356	    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
   357	    montar()
   358	    expect(screen.getByText('Cargando los pendientes del equipo…')).toBeInTheDocument()
   359	    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
   360	  })
   361	
   362	  it('vacío honesto por pestaña y por analista', () => {
   363	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
   364	    montar()
   365	    expect(screen.getByText(/Nada para atender ahora/)).toBeInTheDocument()
   366	    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
   367	    expect(screen.getByText('Jorge no tiene casos aquí.')).toBeInTheDocument()
   368	  })
   369	
   370	  it('abrir una ficha llama al store; si falla, lo avisa', async () => {
   371	    abrirLead.mockResolvedValueOnce(false)
   372	    montar()
   373	    const fila = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')[0]!
   374	    await act(async () => {
   375	      fireEvent.click(within(fila).getByRole('button', { name: 'Abrir ficha de ROSA CHÁVEZ, de Karen: Primera gestión pendiente · venció hace 2 días, S/ 20k' }))
   376	    })
   377	    expect(abrirLead).toHaveBeenCalledWith('l-1')
   378	    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo abrir la ficha')
   379	  })
   380	})
   381	
   382	describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
   383	  it('UNA severidad por analista: el no-show repetido es rojo en el punto, la cabecera y el detalle', () => {
   384	    METRICAS_AGENDA = agenda([
   385	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, toques: 9, pct_completadas: 50 },
   386	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' },
   387	    ])
   388	    montar()
   389	    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
   390	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   391	    const karen = within(equipo).getByRole('button', { name: /KAREN ZAPATA/ })
   392	    expect(karen).toHaveTextContent('2 citas sin asistir')
   393	    expect(within(karen).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
   394	    expect(karen).toHaveAttribute('aria-expanded', 'false')
   395	    fireEvent.click(karen)
   396	    expect(karen).toHaveAttribute('aria-expanded', 'true')
   397	    const detalle = document.getElementById(karen.getAttribute('aria-controls')!)!
   398	    expect(detalle).toBeVisible()
   399	    // El detalle NO repite la señal principal: trae las demás y los hechos.
   400	    expect(detalle).not.toHaveTextContent('2 citas sin asistir')
   401	    expect(detalle).toHaveTextContent('1 tarea vencida')
   402	    expect(detalle).toHaveTextContent('9 toques en 7 días · 50 % completadas')
   403	    // Y filtra la cola a sus pendientes.
   404	    expect(pedidoCola()?.filtros.analista_id).toBe(KAREN)
   405	    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
   406	  })
   407	
   408	  it('«Al día» solo con la agenda confirmada; sin ella no se afirma', () => {
   409	    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
   410	    montar()
   411	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   412	    expect(within(equipo).getByRole('button', { name: /JORGE HUAMÁN/ })).toHaveTextContent('Al día')
   413	    // Karen no tiene actividad desde el 20/09: 6 días, rojo. Jorge no cuenta.
   414	    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
   415	  })
   416	
   417	  it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día» ni «Sin alertas»', () => {
   418	    AGENDA_ERROR = new Error('agenda caída')
   419	    // Todos con actividad fresca: sin agenda, cero señales es DESCONOCIDO.
   420	    LEADS = [
   421	      lead({ creado_en: '2026-09-26T14:00:00Z' }),
   422	      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
   423	    ]
   424	    montar()
   425	    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
   426	    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('La agenda del equipo no respondió'))
   427	    expect(alerta).toBeDefined()
   428	    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
   429	    expect(REFETCH_AGENDA).toHaveBeenCalledTimes(1)
   430	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   431	    expect(equipo).not.toHaveTextContent('Al día')
   432	  })
   433	
   434	  it('«Sin alertas» solo con la agenda confirmada y todos sin señal', () => {
   435	    LEADS = [
   436	      lead({ creado_en: '2026-09-26T14:00:00Z' }),
   437	      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
   438	    ]
   439	    montar()
   440	    expect(screen.getByText('Sin alertas en el equipo')).toBeInTheDocument()
   441	  })
   442	
   443	  it('mientras la agenda carga tampoco afirma «Sin alertas»', () => {
   444	    METRICAS_AGENDA = undefined
   445	    LEADS = [lead({ creado_en: '2026-09-26T14:00:00Z' })]
   446	    montar()
   447	    expect(screen.queryByText('Sin alertas en el equipo')).not.toBeInTheDocument()
   448	  })
   449	
   450	  it('un analista sin leads abiertos conserva su alerta roja de agenda', () => {
   451	    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', no_asistio: 3 }])
   452	    montar()
   453	    const jorge = within(screen.getByRole('list', { name: 'Analistas del equipo' })).getByRole('button', { name: /JORGE HUAMÁN/ })
   454	    expect(jorge).toHaveTextContent('3 citas sin asistir')
   455	    expect(within(jorge).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
   456	  })
   457	
   458	  it('el enlace de la cabecera lleva a «Mi equipo hoy»', () => {
   459	    montar()
   460	    expect(screen.getByRole('link', { name: 'Mi equipo hoy →' })).toHaveAttribute('href', '#/gestion-diaria')
   461	  })
   462	})
   463	
   464	describe('Hoy · supervisor — puesto de mando: decide primero (F2)', () => {
   465	  const conAgendaYReparto = () => {
   466	    METRICAS_AGENDA = agenda([
   467	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, leads_sin_accion: 1 },
   468	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', leads_sin_accion: 3 },
   469	    ])
   470	    // Un lead SIN analista: el reparto lo cuenta el resumen (espejo del RPC).
   471	    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
   472	  }
   473	
   474	  it('ESTADO DE PRODUCCIÓN: tres tarjetas, el rojo primero, cifra grande y la severidad en texto', () => {
   475	    conAgendaYReparto()
   476	    montar()
   477	    expect(screen.getByRole('heading', { name: 'Decide primero' })).toBeInTheDocument()
   478	    const tarjetas = document.querySelectorAll('[data-decision]')
   479	    // Rojo primero; entre los ámbar manda el peso fijo: el reparto antes que «sin próxima acción».
   480	    expect([...tarjetas].map((t) => t.getAttribute('data-decision'))).toEqual(['primera_gestion', 'no_asistio', 'por_repartir'])
   481	    const primera = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
   482	    expect(primera).toHaveTextContent('1')
   483	    expect(primera).toHaveTextContent('primera gestión vencida')
   484	    expect(screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })).toHaveTextContent('citas sin asistir · Karen')
   485	    // Lo que no entra en tres, a «Esta semana».
   486	    expect(screen.getByRole('button', { name: /Esta semana · 1/ })).toBeInTheDocument()
   487	  })
   488	
   489	  it('la primera gestión filtra la cola a ESA pestaña para todo el equipo; el segundo clic la devuelve', () => {
   490	    montar()
   491	    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
   492	    const tarjeta = screen.getByRole('button', { name: 'Hoy: 1 primera gestión vencida' })
   493	    fireEvent.click(tarjeta)
   494	    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
   495	    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!)).toHaveTextContent('Revisa la primera gestión con cada analista')
   496	    expect(screen.getByRole('tab', { name: /Primera gestión/ })).toHaveAttribute('aria-selected', 'true')
   497	    expect(pedidoCola()?.filtros).toEqual({ senal: 'primera_atencion', etapa: null, analista_id: null })
   498	    fireEvent.click(tarjeta)
   499	    expect(tarjeta).toHaveAttribute('aria-expanded', 'false')
   500	    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveAttribute('aria-selected', 'true')
   501	  })
   502	
   503	  it('«Ver» lleva a la cola y le pasa el foco a la pestaña', () => {
   504	    montar()
   505	    fireEvent.click(screen.getByRole('button', { name: 'Ver las 1 primera gestión vencida en la cola' }))
   506	    act(() => { vi.advanceTimersByTime(32) })
   507	    const pestana = screen.getByRole('tab', { name: /Primera gestión/ })
   508	    expect(pestana).toHaveAttribute('aria-selected', 'true')
   509	    expect(pestana).toHaveFocus()
   510	  })
   511	
   512	  it('citas sin asistir NO filtran la cola (no contiene esos casos): despliegan y llevan al día del equipo', () => {
   513	    conAgendaYReparto()
   514	    montar()
   515	    const antes = pedidoCola()?.filtros
   516	    const tarjeta = screen.getByRole('button', { name: 'Hoy: KAREN ZAPATA: 2 citas sin asistir' })
   517	    fireEvent.click(tarjeta)
   518	    expect(tarjeta).toHaveAttribute('aria-expanded', 'true')
   519	    expect(pedidoCola()?.filtros).toEqual(antes)
   520	    expect(document.getElementById(tarjeta.getAttribute('aria-controls')!))
   521	      .toHaveTextContent('En 7 días: 2 sin asistir · 1 tareas vencidas · 1 sin próxima acción.')
   522	    expect(screen.getByRole('link', { name: 'Ver su día: KAREN ZAPATA: 2 citas sin asistir' })).toHaveAttribute('href', '#/gestion-diaria')
   523	  })
   524	
   525	  it('«Esta semana» lista lo que no entró, con su acción; Esc lo cierra y devuelve el foco', () => {
   526	    conAgendaYReparto()
   527	    montar()
   528	    const disparador = screen.getByRole('button', { name: /Esta semana · 1/ })
   529	    fireEvent.click(disparador)
   530	    expect(disparador).toHaveAttribute('aria-expanded', 'true')
   531	    const lista = screen.getByRole('list', { name: 'Decisiones para esta semana' })
   532	    expect(lista).toHaveTextContent('Esta semana: JORGE HUAMÁN: 3 leads sin próxima acción')
   533	    const verDia = within(lista).getByRole('link', { name: 'Ver su día: JORGE HUAMÁN: 3 leads sin próxima acción' })
   534	    expect(verDia).toHaveAttribute('href', '#/gestion-diaria')
   535	    verDia.focus()
   536	    fireEvent.keyDown(document, { key: 'Escape' })
   537	    expect(disparador).toHaveAttribute('aria-expanded', 'false')
   538	    expect(disparador).toHaveFocus()
   539	  })
   540	
   541	  it('el reparto como tarjeta conserva la etiqueta accesible del servidor', () => {
   542	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
   543	    LEADS = [...LEADS, lead({ id: 'l-5', nombre_completo: 'SIN DUEÑO', vendedor_id: null })]
   544	    montar()
   545	    expect(screen.getByRole('link', { name: 'Repartir 1 lead pendiente' })).toHaveAttribute('href', '#/derivaciones')
   546	  })
   547	
   548	  it('con TODAS las fuentes confirmadas y nada pendiente dice «Nada que decidir»', () => {
   549	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
   550	    montar()
   551	    expect(screen.getByText('Nada que decidir ahora mismo.')).toBeInTheDocument()
   552	    expect(document.querySelectorAll('[data-decision]')).toHaveLength(0)
   553	  })
   554	
   555	  it('mientras el seguimiento carga no afirma que no hay nada: «Revisando…»', () => {
   556	    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
   557	    montar()
   558	    expect(screen.getByText('Revisando las decisiones del día…')).toBeInTheDocument()
   559	    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
   560	  })
   561	
   562	  it('fail-closed: con el seguimiento o la agenda caídos lo dice, deja reintentar y nunca «Nada que decidir»', () => {
   563	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: new Error('caído'), isFetching: false })
   564	    AGENDA_ERROR = new Error('agenda caída')
   565	    montar()
   566	    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('Algunas decisiones no se pudieron confirmar'))
   567	    expect(alerta).toHaveTextContent('no respondió el seguimiento ni la agenda')
   568	    expect(screen.queryByText('Nada que decidir ahora mismo.')).not.toBeInTheDocument()
   569	    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
   570	    expect(REFETCH_COLA).toHaveBeenCalled()
   571	    expect(REFETCH_AGENDA).toHaveBeenCalled()
   572	  })
   573	
   574	  it('sin el modo activo confirmado no hay banda de decisiones', () => {
   575	    MODO.activo = false
   576	    MODO.data = undefined
   577	    montar()
   578	    expect(screen.queryByRole('heading', { name: 'Decide primero' })).not.toBeInTheDocument()
   579	  })
   580	})
   581	
   582	describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () => {
   583	  it('ESTADO DE PRODUCCIÓN (sin metas publicadas): la franja da cifras con «—» donde no hay dato y sin jerga', () => {
   584	    METRICAS_AGENDA = agenda([
   585	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', toques: 6, completadas: 3, no_asistio: 1, pct_completadas: 75 },
   586	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', toques: 4, completadas: 0, no_asistio: 1 },
   587	    ])
   588	    montar()
   589	    const cifras = screen.getByRole('list', { name: 'Cifras del equipo' })
   590	    expect(cifras).toHaveTextContent('S/ 20k pronóstico · +US$ 15k aparte')
   591	    expect(cifras).toHaveTextContent('2 leads activos')
   592	    // Sin meta publicada no hay % de meta que inventar.
   593	    expect(cifras).toHaveTextContent('— de la meta')
   594	    expect(cifras).toHaveTextContent('— conversión del mes')
   595	    expect(cifras).toHaveTextContent('10 toques en 7 días')
   596	    expect(cifras).toHaveTextContent('60 % completadas')
   597	    // 2 no asistió en el equipo: el número va en rojo de TEXTO, con su palabra al lado.
   598	    const itemNoAsistio = within(cifras).getAllByRole('listitem').find((li) => li.textContent === '2 no asistió')!
   599	    expect(itemNoAsistio.querySelector('strong')).toHaveStyle({ color: 'var(--destructive-text)' })
   600	    expect(document.body).not.toHaveTextContent(/pipeline|suma÷suma|solo producción/i)
   601	  })
   602	
   603	  it('«Detalle» abre un diálogo con TODO lo que la pantalla clásica mostraba; Esc lo cierra y el foco vuelve', () => {
   604	    vi.useRealTimers()
   605	    montar()
   606	    const boton = screen.getByRole('button', { name: 'Detalle' })
   607	    boton.focus()
   608	    fireEvent.click(boton)
   609	    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
   610	    for (const kpi of ['Pronóstico de capital abierto', 'Leads activos del equipo', 'Primeras gestiones vencidas', 'Por repartir']) {
   611	      expect(within(dialogo).getByText(kpi)).toBeInTheDocument()
   612	    }
   613	    expect(within(dialogo).getByText('Revísalas con cada analista')).toBeInTheDocument()
   614	    expect(within(dialogo).getByRole('heading', { name: 'Cumplimiento del mes' })).toBeInTheDocument()
   615	    expect(within(dialogo).getAllByText('Sin meta fijada para este mes').length).toBeGreaterThan(0)
   616	    expect(within(dialogo).getByRole('region', { name: 'Agenda del equipo' })).toBeInTheDocument()
   617	    expect(within(dialogo).getByText(/Ves solo a tu equipo/)).toBeInTheDocument()
   618	    expect(within(dialogo).getByRole('link', { name: 'Ver derivaciones; bandeja sin pendientes' })).toHaveAttribute('href', '#/derivaciones')
   619	    fireEvent.keyDown(dialogo, { key: 'Escape' })
   620	    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
   621	  })
   622	
   623	  it('«Cerrar» también cierra el detalle', () => {
   624	    vi.useRealTimers()
   625	    montar()
   626	    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
   627	    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cerrar' }))
   628	    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
   629	  })
   630	})
```

## Contexto (sin cambios)

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
   354	    filasMeta,
   355	    hayErrorMensual,
   356	    reintentarMensual,
   357	    sesionReal,
   358	    datosAgenda,
   359	    agendaConfirmada,
   360	    errorAgenda,
   361	    cargandoAgenda,
   362	    recargarAgenda,
   363	    rezagosAgenda,
   364	  }
   365	}
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

### `app/src/screens/hoy/tres-cosas.tsx (franja clásica)`
```
     1	// Franja «Hoy, tres cosas» (F3, 2026-08-23) — el puesto de mando del
     2	// supervisor: el sistema absorbe la priorización del día (ley de Tesler) y
     3	// aquí solo llegan DECISIONES, cada una con su acción al lado.
     4	//
     5	// Navy a propósito: es la voz de autoridad/estructura del presupuesto de
     6	// color, no una alarma — los puntos de severidad (rojo/ámbar) son la única
     7	// señal cromática dentro. Sin cosas, la franja NO se pinta: el silencio
     8	// también es información.
     9	import type { JSX } from 'react'
    10	import { SEMAFORO_SOBRE_NAVY } from '@/lib/semaforo'
    11	import { hashDe } from '@/lib/router'
    12	import type { CosaDeHoy, PestanaColaDestino } from '@/lib/tres-cosas'
    13	
    14	const COLOR_SEV: Record<CosaDeHoy['severidad'], string> = {
    15	  critica: SEMAFORO_SOBRE_NAVY.critico,
    16	  atencion: SEMAFORO_SOBRE_NAVY.atencion,
    17	}
    18	
    19	// La severidad TAMBIÉN en texto (regla de la casa: el color nunca va solo).
    20	// Sin esto, un lector de pantalla oía «3 nuevos sin responder — Ver» sin
    21	// saber si era el rojo de HOY o el ámbar de la semana (a11y F3, A1).
    22	const SEV_TEXTO: Record<CosaDeHoy['severidad'], string> = {
    23	  critica: 'urgente hoy',
    24	  atencion: 'esta semana',
    25	}
    26	
    27	// Chip entero clicable (Fitts): texto + acción en UN solo objetivo cómodo.
    28	const CLASE_CHIP =
    29	  'flex min-h-9 cursor-pointer items-center gap-2 rounded-lg border border-white/15 bg-white/10 px-3 py-1.5 text-left text-xs font-semibold text-white transition-colors hover:bg-white/20 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-white/60'
    30	
    31	function ContenidoCosa({ cosa }: { cosa: CosaDeHoy }): JSX.Element {
    32	  return (
    33	    <>
    34	      <span
    35	        className="size-2 shrink-0 rounded-full"
    36	        style={{ background: COLOR_SEV[cosa.severidad] }}
    37	        aria-hidden
    38	      />
    39	      <span className="min-w-0">{cosa.texto}</span>
    40	      <span className="shrink-0 font-extrabold text-[#9cc0ff]">{cosa.accion} →</span>
    41	    </>
    42	  )
    43	}
    44	
    45	export function TresCosas({
    46	  cosas,
    47	  onIrAPestana,
    48	}: {
    49	  cosas: readonly CosaDeHoy[]
    50	  /** Salta a una pestaña de la Cola del equipo (y le lleva el foco). */
    51	  onIrAPestana: (pestana: PestanaColaDestino) => void
    52	}): JSX.Element | null {
    53	  if (cosas.length === 0) return null
    54	  return (
    55	    <section
    56	      aria-label="Hoy, tres cosas"
    57	      className="flex flex-wrap items-center gap-2 rounded-xl bg-primary px-4 py-3"
    58	    >
    59	      <h2 className="mr-1 text-[10px] font-bold uppercase tracking-[0.12em] text-white/60">
    60	        Hoy, tres cosas
    61	      </h2>
    62	      {cosas.map((cosa) => {
    63	        // Capturado ANTES del callback: el narrowing del discriminante no
    64	        // sobrevive dentro del onClick.
    65	        const destino = cosa.destino
    66	        return destino.tipo === 'vista' ? (
    67	          <a
    68	            key={cosa.id}
    69	            href={hashDe(destino.vista)}
    70	            aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto} — ${cosa.accion}`}
    71	            className={CLASE_CHIP}
    72	          >
    73	            <ContenidoCosa cosa={cosa} />
    74	          </a>
    75	        ) : (
    76	          <button
    77	            key={cosa.id}
    78	            type="button"
    79	            onClick={() => onIrAPestana(destino.pestana)}
    80	            aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto} — ${cosa.accion}`}
    81	            className={CLASE_CHIP}
    82	          >
    83	            <ContenidoCosa cosa={cosa} />
    84	          </button>
    85	        )
    86	      })}
    87	    </section>
    88	  )
    89	}
```

### `app/src/lib/sla-operacion.ts`
```
     1	import * as v from 'valibot'
     2	import type { Rol } from './roles'
     3	
     4	const fecha = v.nullable(v.string())
     5	const indicador = v.nullable(v.boolean())
     6	const numero = v.nullable(v.number())
     7	const tarea = v.nullable(v.object({ id: v.string(), tipo: v.string(), vence_en: v.string(), reprogramaciones: v.number() }))
     8	export const TipoAvisoSlaSchema = v.picklist(['primera_atencion', 'tarea_vencida', 'seguimiento', 'revision_comercial', 'datos_incompletos', 'por_repartir'])
     9	export const AvisoSlaSchema = v.object({ id: v.string(), bucket: TipoAvisoSlaSchema, severidad: v.picklist(['critica', 'media']),
    10	  referencia_en: fecha, tarea_id: v.nullable(v.string()) })
    11	export type AvisoSla = v.InferOutput<typeof AvisoSlaSchema>
    12	export const EstadoSlaV2Schema = v.pipe(v.object({
    13	  lead_id: v.string(), evaluacion: v.picklist(['completa', 'parcial', 'no_aplica']), motivos_datos: v.array(v.string()),
    14	  avisos: v.array(AvisoSlaSchema),
    15	  avisos_mostrados: v.optional(v.array(AvisoSlaSchema)),
    16	  operacion: v.optional(v.object({ modelo: v.literal(3), aviso_principal: v.nullable(AvisoSlaSchema),
    17	    proxima_accion: v.nullable(v.object({ id: v.string(), tipo: v.string(), titulo: v.string(), vence_en: v.string() })),
    18	    proximo_cambio_en: fecha })),
    19	  seguimiento: v.object({ referencia_en: fecha, ultima_gestion_en: fecha, limite_en: fecha, vencido: indicador, accion_pendiente: indicador }),
    20	  compromiso: v.object({ tarea, validez: v.string(), hasta_en: fecha, cobertura_activa: indicador }),
    21	  etapa: v.object({ limite_original_en: fecha, limite_prorrogado_en: fecha, limite_operativo_en: fecha, techo_en: fecha,
    22	    prorrogas_usadas: numero, prorrogas_restantes: numero, revision_requerida: indicador, motivos_revision: v.array(v.string()) }),
    23	}), v.check((estado) => !estado.operacion || (estado.avisos_mostrados !== undefined
    24	  && estado.avisos_mostrados.every((aviso) => estado.avisos.some((causa) => causa.id === aviso.id)))))
    25	export type EstadoSlaV2 = v.InferOutput<typeof EstadoSlaV2Schema>
    26	export const ModoSlaSchema = v.picklist(['legado', 'observacion', 'activo'])
    27	const sobre = { modelo_avisos: v.optional(v.literal(3)), proximo_cambio_en: v.optional(fecha), version: v.literal(2), modo: ModoSlaSchema, control_revision: v.number(), calculado_en: v.string() }
    28	export const EstadosSlaV2Schema = v.object({ ...sobre, filas: v.array(EstadoSlaV2Schema) })
    29	const conteo = v.pipe(v.number(), v.integer(), v.minValue(0))
    30	export const ResumenAvisosSlaSchema = v.pipe(v.object({ ...sobre,
    31	  total_oportunidades: conteo, total_avisos: conteo, criticas: conteo,
    32	  grupos: v.pipe(v.array(v.object({ bucket: TipoAvisoSlaSchema, total: v.pipe(conteo, v.minValue(1)) })), v.maxLength(6)),
    33	}), v.check((r) => r.total_oportunidades <= r.total_avisos && r.criticas <= r.total_avisos
    34	  && r.grupos.reduce((total, g) => total + g.total, 0) === r.total_avisos
    35	  && new Set(r.grupos.map((g) => g.bucket)).size === r.grupos.length
    36	  && (r.total_oportunidades > 0 || r.total_avisos === 0)))
    37	export type ResumenAvisosSla = v.InferOutput<typeof ResumenAvisosSlaSchema>
    38	export const SENALES_SLA = [
    39	  ['pendientes', 'Para atender ahora'], ['todas', 'Todas las acciones'], ['primera_atencion', 'Primera atención'], ['tareas_vencidas', 'Tareas vencidas'],
    40	  ['seguimientos_pendientes', 'Seguimiento pendiente'], ['revisiones', 'Revisión comercial'],
    41	  ['datos_incompletos', 'Datos incompletos'], ['por_repartir', 'Por repartir'],
    42	] as const
    43	export type SenalSla = typeof SENALES_SLA[number][0]
    44	export type FiltrosSla = { senal: SenalSla; etapa: string | null; analista_id: string | null }
    45	export type CursorSla = Record<string, unknown>
    46	const senales = v.object({ pendientes: v.boolean(), primera_atencion: v.boolean(), tareas_vencidas: v.boolean(), seguimientos_pendientes: v.boolean(),
    47	  revisiones: v.boolean(), datos_incompletos: v.boolean(), por_repartir: v.boolean() })
    48	const cursor = v.nullable(v.record(v.string(), v.unknown()))
    49	export const ColaSlaPaginaSchema = v.object({ ...sobre,
    50	  filtros: v.object({ senal: v.string(), etapa: v.nullable(v.string()), analista_id: v.nullable(v.string()) }),
    51	  limite: v.number(), total_items: v.number(), hay_mas: v.boolean(), cursor_siguiente: cursor,
    52	  rango: v.object({ desde: v.number(), hasta: v.number() }),
    53	  totales: v.object({ pendientes: v.number(), primera_atencion: v.number(), tareas_vencidas: v.number(), seguimientos_pendientes: v.number(), revisiones: v.number(), datos_incompletos: v.number(), por_repartir: v.number() }),
    54	  items: v.array(v.object({ lead_id: v.string(), bucket: v.string(), severidad: v.picklist(['critica', 'media', 'baja']),
    55	    prioridad: v.number(), referencia_en: fecha, tarea_id: v.nullable(v.string()),
    56	    lead: v.object({ id: v.string(), nombre_completo: v.string(), etapa: v.string(), analista_id: v.nullable(v.string()), analista_nombre: v.nullable(v.string()) }),
    57	    senales, estado: EstadoSlaV2Schema,
    58	  })),
    59	})
    60	export type ColaSlaPagina = v.InferOutput<typeof ColaSlaPaginaSchema>
```

### `app/src/data/sla-operacion-queries.ts`
```
     1	import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
     2	import { useAuth } from '@/lib/auth-context'
     3	import { crmQueryKeys } from './crm-queries'
     4	import { cambiarModoSla, publicarReglasSlaAprobadas, obtenerConfiguracionSlaV2, listarColaSla, obtenerEstadosSlaV2, obtenerResumenAvisosSla } from './sla-operacion-api'
     5	import { CrmApiError } from './crm-api'
     6	import type { CursorSla, FiltrosSla } from '@/lib/sla-operacion'
     7	import { intervaloReconsultaSla } from './sla-operacion-reloj'
     8	
     9	// Ambas lecturas heredan la invalidación existente de cada gestión, tarea y cambio de ámbito.
    10	export const slaOperacionKeys = {
    11	  raiz: () => [...crmQueryKeys.metricasAmbito(), 'sla-v2'] as const,
    12	  estado: (actor: string | null, ids: string[]) => [...slaOperacionKeys.raiz(), actor, 'estado', ids] as const,
    13	  cola: (actor: string | null, filtros: FiltrosSla, cursor: CursorSla | null, limite: number) => [...slaOperacionKeys.raiz(), actor, 'cola', filtros, cursor, limite] as const,
    14	  avisos: (actor: string | null) => [...slaOperacionKeys.raiz(), actor, 'avisos'] as const,
    15	}
    16	export function useResumenAvisosSla(habilitada: boolean) {
    17	  const { yo } = useAuth()
    18	  return useQuery({ queryKey: slaOperacionKeys.avisos(yo?.id ?? null),
    19	    queryFn: ({ signal }) => obtenerResumenAvisosSla(signal), enabled: Boolean(habilitada && yo && !yo.demo),
    20	    refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' })
    21	}
    22	export function useEstadosSlaV2(ids: string[]) {
    23	  const { yo } = useAuth()
    24	  return useQuery({ queryKey: slaOperacionKeys.estado(yo?.id ?? null, ids),
    25	    queryFn: ({ signal }) => obtenerEstadosSlaV2(ids, signal), enabled: Boolean(yo && !yo.demo), refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' })
    26	}
    27	export function useModoSla() {
    28	  const { yo } = useAuth()
    29	  const consulta = useEstadosSlaV2([])
    30	  return { ...consulta, legado: Boolean(yo?.demo || (!consulta.error && consulta.data && consulta.data.modo !== 'activo')),
    31	    activo: Boolean(!yo?.demo && !consulta.error && consulta.data?.modo === 'activo') }
    32	}
    33	export function useColaSlaPagina(filtros: FiltrosSla, cursor: CursorSla | null, limite: number, habilitada: boolean) {
    34	  const { yo } = useAuth()
    35	  return useQuery({ queryKey: slaOperacionKeys.cola(yo?.id ?? null, filtros, cursor, limite),
    36	    queryFn: ({ signal }) => listarColaSla(filtros, cursor, limite, signal), enabled: Boolean(habilitada && yo && !yo.demo),
    37	    refetchInterval: (query) => intervaloReconsultaSla(query.state.error ? undefined : query.state.data, query.state.dataUpdatedAt), refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
    38	  })
    39	}
    40	
```

### `app/src/screens/hoy/supervisor.tsx (pantalla clásica, estado actual)`
```
     1	import { SlaOperacionBoundary } from '@/components/app/sla-operacion'
     2	import { useModoSla } from '@/data/sla-operacion-queries'
     3	// Hoy · SUPERVISOR — puesto de mando de SU equipo (F1c). El ámbito del store
     4	// ya trae: sus leads + los de sus analistas + parkeados de SU bandeja.
     5	// Fuentes: useCRMData().ambito + lib/inteligencia + objetivos del contexto.
     6	// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626.
     7	import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
     8	import {
     9	  AlertTriangle,
    10	  ChevronRight,
    11	  Inbox,
    12	  ListChecks,
    13	  Target,
    14	  Users,
    15	  UsersRound,
    16	  Wallet,
    17	} from 'lucide-react'
    18	import { Card, CardContent } from '@/components/ui/card'
    19	import { Avatar } from '@/components/ui/avatar'
    20	import { Badge } from '@/components/ui/badge'
    21	import { Button } from '@/components/ui/button'
    22	import { Progress } from '@/components/ui/progress'
    23	import { KpiCard } from '@/components/common/kpi-card'
    24	import { SectionHead } from '@/components/common/section-head'
    25	import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
    26	import { AccionesContacto } from '@/components/app/contacto'
    27	import { AgendaEquipoPanel } from './agenda-equipo'
    28	import { useDatosSupervisor } from './datos-supervisor'
    29	import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
    30	import { TresCosas } from './tres-cosas'
    31	import { BUCKET_LABEL, colorMeta, haceTexto } from '@/lib/inteligencia'
    32	import { TOPE_ESTANCADOS } from '@/lib/cola-accion'
    33	import {
    34	  derivarNovedades,
    35	  fotoDeVisita,
    36	  guardarFotoVisita,
    37	  leerFotoVisita,
    38	  resumenNovedades,
    39	  type NovedadesVisita,
    40	} from '@/lib/visita-sin-movimiento'
    41	import { useSplashVisible } from '@/lib/splash-visible'
    42	import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
    43	import { useAuth } from '@/lib/auth-context'
    44	import { useCRMData, usePanelesActions } from '@/lib/store-context'
    45	import { moneyK, numero } from '@/lib/format'
    46	import { cn } from '@/lib/utils'
    47	import { hashDe } from '@/lib/router'
    48	import { tresCosasDeHoy } from '@/lib/tres-cosas'
    49	import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
    50	import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
    51	import { textoConversionOperativa } from '@/lib/metricas-vendedores'
    52	import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
    53	import { DesgloseMonedas } from '@/components/common/desglose-monedas'
    54	import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
    55	
    56	// Tope de la cola del equipo: los primeros son la plata (colaDe ya ordena por
    57	// severidad); el resto vive tras "Ver los N pendientes" para que la Agenda del
    58	// equipo (montada debajo) no quede varios pantallazos abajo.
    59	const COLA_VISIBLES = 8
    60	
    61	// Pestañas de la cola (2026-08-23, «una cosa se avisa en un solo lugar»):
    62	// «Leads sin movimiento» era una tercera tarjeta sobre los MISMOS leads
    63	// abiertos que la cola, así que un lead con 6 días salía dos veces en el mismo
    64	// pantallazo. Ahora es una pestaña de la misma tarjeta: mismo conteo, mismo
    65	// tope del RPC, un solo lugar. Urgente = severidad crítica y media.
    66	type PestanaCola = 'urgente' | 'sin_movimiento' | 'todo'
    67	const PESTANAS_COLA: ReadonlyArray<{ id: PestanaCola; label: string }> = [
    68	  { id: 'urgente', label: 'Urgente' },
    69	  { id: 'sin_movimiento', label: 'Sin movimiento' },
    70	  { id: 'todo', label: 'Todo' },
    71	]
    72	
    73	/** Semáforo por días sin actividad: azul <2 · ámbar 2–5 · rojo >5. */
    74	function semaforoDias(d: number): string {
    75	  if (d > 5) return SEMAFORO.critico
    76	  if (d >= 2) return SEMAFORO.atencion
    77	  return SEMAFORO.ok
    78	}
    79	
    80	export function HoySupervisor(): JSX.Element {
    81	  const modoSla = useModoSla()
    82	  const { ambito, actividades, tareas, equipo } = useCRMData()
    83	  const { abrirLead } = usePanelesActions()
    84	  const { yo } = useAuth()
    85	  // F1b: el reloj SLA solo alimenta el ESPEJO demo de la cola — en sesión real
    86	  // esos vencimientos ya llegan resueltos dentro de cola_accion_fn, así que el
    87	  // RPC de estado SLA ni se pide (habilitado = demo).
    88	  const estadoSla = useEstadoSlaOperativo(ambito.leads, actividades, yo?.demo === true)
    89	  // Meta, reparto, agenda y tipo de cambio: derivación COMPARTIDA con el
    90	  // puesto de mando (./datos-supervisor.ts). Aquí queda lo propio del modo
    91	  // legado: la cola cola_accion_fn, sus pestañas y la visita F4.3.
    92	  const {
    93	    resumenOp,
    94	    resumen,
    95	    vendedoresOp,
    96	    rank,
    97	    tc,
    98	    capitalPronostico,
    99	    esperaMasLargaReparto,
   100	    totalPorRepartir,
   101	    detalleReparto,
   102	    etiquetaAccesoReparto,
   103	    cumplimientoMensual,
   104	    filasMeta,
   105	    hayErrorMensual,
   106	    reintentarMensual,
   107	    datosAgenda,
   108	    agendaConfirmada,
   109	    errorAgenda,
   110	    cargandoAgenda,
   111	    recargarAgenda,
   112	    rezagosAgenda,
   113	  } = useDatosSupervisor()
   114	  // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
   115	  const [colaExpandida, setColaExpandida] = useState(false)
   116	  // Pestaña elegida a mano; `null` = automática (la primera con filas), así
   117	  // un supervisor que entra por la mañana aterriza donde hay trabajo.
   118	  const [pestanaElegida, setPestanaElegida] = useState<PestanaCola | null>(null)
   119	
   120	  // cola_accion_fn → cola + estancados + tile "sin responder".
   121	  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
   122	  const cola = colaOp.cola
   123	
   124	  // Nombres para los estancados del payload (el servidor no manda nombres de
   125	  // personas): join con el roster completo, una sola vez por render.
   126	  const nombrePorId = useMemo(
   127	    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
   128	    [equipo],
   129	  )
   130	
   131	  // Filas y conteos por pestaña. «Todo» cuenta el universo del RPC (`total`),
   132	  // no las filas recortadas por p_limite; «Urgente» solo puede contar lo que
   133	  // llegó. Con estancados al tope, el conteo dice «50+» y no miente.
   134	  const urgentes = useMemo(
   135	    () => (cola?.items ?? []).filter((i) => i.sev !== 'baja'),
   136	    [cola],
   137	  )
   138	  // El conteo de «Urgente» sale de porSev (el resumen COMPLETO del RPC), no de
   139	  // las filas: p_limite recorta items a 100 y con 120 urgentes la pestaña
   140	  // habría dicho 100 mientras «Todo» decía 120 (hallazgo de Codex).
   141	  const urgenteTotal = (cola?.porSev.critica ?? 0) + (cola?.porSev.media ?? 0)
   142	  const conteoPestana: Record<PestanaCola, string> = {
   143	    urgente: String(urgenteTotal),
   144	    sin_movimiento: cola && cola.estancados.length >= TOPE_ESTANCADOS
   145	      ? `${TOPE_ESTANCADOS}+`
   146	      : String(cola?.estancados.length ?? 0),
   147	    todo: String(cola?.total ?? 0),
   148	  }
   149	  const primeraConFilas: PestanaCola = urgentes.length > 0
   150	    ? 'urgente'
   151	    : (cola?.estancados.length ?? 0) > 0
   152	      ? 'sin_movimiento'
   153	      : 'todo'
   154	  const pestana = pestanaElegida ?? primeraConFilas
   155	  const elegirPestana = (siguiente: PestanaCola) => {
   156	    // F4.3: la visita la cierra el USUARIO al irse de la pestaña. Un vaivén
   157	    // automático de `primeraConFilas` (refetch caído que salta a «Todo» y
   158	    // vuelve al recuperarse) no borra las marcas ni fabrica otra visita.
   159	    if (pestana === 'sin_movimiento' && siguiente !== 'sin_movimiento') {
   160	      visitaAnotadaRef.current = null
   161	      setVisitaCongelada(null)
   162	    }
   163	    setPestanaElegida(siguiente)
   164	  }
   165	  // El colapso se reinicia con CUALQUIER cambio de pestaña — también el
   166	  // automático: la cola se refresca cada minuto y sin esto una pestaña recién
   167	  // aparecida heredaba la expansión de la anterior (hasta 100 filas de golpe).
   168	  useEffect(() => {
   169	    setColaExpandida(false)
   170	  }, [pestana])
   171	  // F4.3: qué EMPEORÓ en «Sin movimiento» desde la última visita. TODO se
   172	  // CONGELA en el instante de anotar: la foto anterior Y las marcas derivadas
   173	  // — una marca que aparece «bajo el cursor» porque la cola se refrescó
   174	  // debajo sería ruido, no memoria (la severidad de la tira sí sigue viva).
   175	  // La visita queda anotada en localStorage en ese mismo instante — anotar
   176	  // «al salir» exigiría un unload handler, y perder una anotación solo marca
   177	  // DE MÁS la próxima vez, la dirección segura. La anotación ESPERA a que el
   178	  // payload esté fresco (enVuelo: persistir una cola vieja podría CALLAR una
   179	  // novedad futura) y a que el workspace sea visible (splash: una «visita»
   180	  // que nadie vio también calla). El ref la hace idempotente (StrictMode
   181	  // ejecuta el efecto dos veces) y fiel a la identidad: si `yo` cambiara en
   182	  // caliente se anota de nuevo para el id nuevo.
   183	  const splashVisible = useSplashVisible()
   184	  const [visitaCongelada, setVisitaCongelada] = useState<{
   185	    novedades: NovedadesVisita | null
   186	    recortada: boolean
   187	  } | null>(null)
   188	  const visitaAnotadaRef = useRef<string | null>(null)
   189	  useEffect(() => {
   190	    if (pestana !== 'sin_movimiento' || yo?.id == null || cola == null) return
   191	    if (colaOp.enVuelo || splashVisible) return
   192	    if (visitaAnotadaRef.current === yo.id) return
   193	    visitaAnotadaRef.current = yo.id
   194	    const fotoAnterior = leerFotoVisita(yo.id)
   195	    guardarFotoVisita(yo.id, fotoDeVisita(cola.estancados, Date.now()))
   196	    setVisitaCongelada({
   197	      novedades: derivarNovedades(cola.estancados, fotoAnterior),
   198	      recortada: cola.estancados.length >= TOPE_ESTANCADOS,
   199	    })
   200	  }, [pestana, cola, colaOp.enVuelo, splashVisible, yo?.id])
   201	  const novedadesVisita = visitaCongelada?.novedades ?? null
   202	  const resumenVisita = resumenNovedades(
   203	    novedadesVisita,
   204	    visitaCongelada?.recortada === true ? TOPE_ESTANCADOS : undefined,
   205	  )
   206	  const filasCola = pestana === 'urgente' ? urgentes : (cola?.items ?? [])
   207	  // Total real de la pestaña activa, para que el botón de expandir no prometa
   208	  // menos de lo que existe cuando el RPC recortó las filas.
   209	  const totalPestanaActiva = pestana === 'todo' ? (cola?.total ?? 0) : urgenteTotal
   210	
   211	  const errorIndicadores = !yo?.demo
   212	    && Boolean(resumenOp.error || (modoSla.legado && colaOp.error) || vendedoresOp.error)
   213	  const reintentarIndicadores = () => {
   214	    if (resumenOp.error) void resumenOp.recargar()
   215	    if (colaOp.error) void colaOp.recargar()
   216	    if (vendedoresOp.error) void vendedoresOp.recargar()
   217	  }
   218	
   219	  // ── F3: «Hoy, tres cosas» — el sistema prioriza el día (ley de Tesler). ──
   220	  // Mismas fuentes que ya están en pantalla; sin dato no hay tarjeta.
   221	  const cosas = useMemo(
   222	    () => tresCosasDeHoy({
   223	      cola,
   224	      totalPorRepartir,
   225	      esperaMasLargaReparto,
   226	      // Para DECIDIR, solo la agenda confirmada: tras un refetch fallido
   227	      // TanStack conserva la respuesta anterior (Codex, F1 del puesto de mando).
   228	      vendedoresAgenda: agendaConfirmada?.vendedores ?? [],
   229	    }),
   230	    [cola, totalPorRepartir, esperaMasLargaReparto, agendaConfirmada],
   231	  )
   232	  // «Ver →» de la franja: selecciona la pestaña y le LLEVA el foco (el
   233	  // focus() también hace scroll hasta la tarjeta de la cola).
   234	  const irAPestanaCola = (destino: PestanaCola) => {
   235	    elegirPestana(destino)
   236	    requestAnimationFrame(() => {
   237	      document.getElementById(`tab-cola-${destino}`)?.focus()
   238	    })
   239	  }
   240	
   241	  return (
   242	    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
   243	      {/* ── F3: la franja manda — máximo tres intervenciones, luego consulta ── */}
   244	      {modoSla.legado && <TresCosas cosas={cosas} onIrAPestana={irAPestanaCola} />}
   245	
   246	      {/* ── KPIs del equipo — servidos por RPC (o espejo demo); sin dato: «—» ── */}
   247	      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   248	        {/* F2 (figura-fondo): los KPIs son CONSULTA, no alarma — iconos en
   249	            neutro. Desde F3 TODOS: la urgencia de «Nuevos sin responder»
   250	            vive en la franja, que es su reemplazo. */}
   251	        <KpiCard
   252	          label="Pronóstico de capital abierto"
   253	          // `capitalPrincipal` y NO `totalEnSoles`: esto es PRONÓSTICO, no
   254	          // cumplimiento, y no se convierte a una tasa que aquí no se rotula.
   255	          // Fijar PEN a mano titulaba «S/ 0» a un equipo que vende en dólares.
   256	          value={capitalPronostico ? capitalPronostico.valor : '—'}
   257	          icon={Wallet}
   258	          color={SEMAFORO.neutro}
   259	          sub={
   260	            capitalPronostico?.otra
   261	              ? `Pipeline (PEN) · +${capitalPronostico.otra} aparte`
   262	              : capitalPronostico?.soloDolares
   263	                ? 'Pipeline (USD)'
   264	                : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.asignados > 0
   265	                  ? 'Sin montos estimados — complétalos en cada ficha'
   266	                  : 'Pipeline (PEN) · abiertos con analista'
   267	          }
   268	          delay={0}
   269	        />
   270	        <KpiCard
   271	          label="Leads activos del equipo"
   272	          value={resumen ? String(resumen.totales.asignados) : '—'}
   273	          icon={Users}
   274	          color={SEMAFORO.neutro}
   275	          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
   276	          delay={60}
   277	        />
   278	        {/* Sin payload, los subs NO afirman estados positivos («todos
   279	            contactados», «bandeja vacía»): sin dato no hay afirmación. */}
   280	        <KpiCard
   281	          label="Nuevos sin responder"
   282	          value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
   283	          icon={AlertTriangle}
   284	          color={SEMAFORO.neutro}
   285	          sub={
   286	            cola == null
   287	              ? 'Sin dato por ahora'
   288	              : (cola.porBucket.sin_responder ?? 0) > 0
   289	                ? 'Sin primer contacto'
   290	                : 'Todos los nuevos fueron contactados'
   291	          }
   292	          delay={120}
   293	        />
   294	        <a
   295	          href={hashDe('derivaciones')}
   296	          aria-label={etiquetaAccesoReparto}
   297	          className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
   298	        >
   299	          {/* F2: fuera el acento ámbar — la urgencia del reparto vive en la
   300	              campana (grupo) y desde F3 en la franja; el KPI es el conteo. */}
   301	          <KpiCard
   302	            label="Por repartir"
   303	            value={totalPorRepartir == null ? '—' : String(totalPorRepartir)}
   304	            icon={Inbox}
   305	            color={SEMAFORO.neutro}
   306	            sub={detalleReparto}
   307	            delay={180}
   308	          />
   309	        </a>
   310	      </div>
   311	
   312	      <AvisoDegradacion
   313	        activo={errorIndicadores}
   314	        queReintenta="de los indicadores del equipo"
   315	        onReintentar={reintentarIndicadores}
   316	      >
   317	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   318	      </AvisoDegradacion>
   319	
   320	      <div className="grid gap-4 lg:grid-cols-5">
   321	        <div className="space-y-4 lg:col-span-3">
   322	          {/* ── Cola del equipo (con dueño de cada item) ── */}
   323	          <SlaOperacionBoundary legado={(
   324	          <Card className="overflow-hidden">
   325	            <SectionHead
   326	              icon={ListChecks}
   327	              title="Cola del equipo"
   328	              right={
   329	                cola ? (
   330	                  // Patrón tablist de la casa (ranking-vendedores): aria-selected
   331	                  // + aria-controls, tabindex itinerante y flechas. Sin el
   332	                  // conteo en el nombre accesible el lector de pantalla no
   333	                  // sabría cuál pestaña tiene trabajo.
   334	                  <div role="tablist" aria-label="Filtrar la cola" className="inline-flex rounded-lg bg-muted/60 p-0.5">
   335	                    {PESTANAS_COLA.map((p, indice) => (
   336	                      <button
   337	                        key={p.id}
   338	                        id={`tab-cola-${p.id}`}
   339	                        type="button"
   340	                        role="tab"
   341	                        aria-selected={pestana === p.id}
   342	                        aria-controls="panel-cola"
   343	                        aria-label={`${p.label}: ${conteoPestana[p.id]}`}
   344	                        tabIndex={pestana === p.id ? 0 : -1}
   345	                        onClick={() => elegirPestana(p.id)}
   346	                        onKeyDown={(e) => {
   347	                          // Flechas con vuelta + Home/End (patrón APG completo).
   348	                          const destino = e.key === 'ArrowRight'
   349	                            ? (indice + 1) % PESTANAS_COLA.length
   350	                            : e.key === 'ArrowLeft'
   351	                              ? (indice - 1 + PESTANAS_COLA.length) % PESTANAS_COLA.length
   352	                              : e.key === 'Home'
   353	                                ? 0
   354	                                : e.key === 'End'
   355	                                  ? PESTANAS_COLA.length - 1
   356	                                  : null
   357	                          if (destino == null) return
   358	                          e.preventDefault()
   359	                          const siguiente = PESTANAS_COLA[destino]
   360	                          if (!siguiente) return
   361	                          elegirPestana(siguiente.id)
   362	                          document.getElementById(`tab-cola-${siguiente.id}`)?.focus()
   363	                        }}
   364	                        className={cn(
   365	                          // Fitts: min-h para un objetivo táctil cómodo.
   366	                          'min-h-7 cursor-pointer rounded-md px-3 py-1.5 text-[11px] font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   367	                          pestana === p.id
   368	                            ? 'bg-card text-foreground shadow-sm'
   369	                            // Gris FUERTE: 11px sobre bg-muted no llega a 4.5:1
   370	                            // con el muted normal (revisor a11y, M1).
   371	                            : 'text-muted-foreground-strong hover:text-foreground',
   372	                        )}
   373	                      >
   374	                        {p.label} <span aria-hidden>{conteoPestana[p.id]}</span>
   375	                      </button>
   376	                    ))}
   377	                  </div>
   378	                ) : (
   379	                  <span className="text-xs text-muted-foreground">—</span>
   380	                )
   381	              }
   382	            />
   383	            {cola == null ? (
   384	              <CardContent className="pb-5 pt-0">
   385	                <p className="text-sm text-muted-foreground">
   386	                  {colaOp.error
   387	                    ? 'La cola del equipo no está disponible en este momento.'
   388	                    : 'Cargando la cola del equipo…'}
   389	                </p>
   390	              </CardContent>
   391	            ) : pestana === 'sin_movimiento' ? (
   392	              // ── Sin movimiento (≥5 días) — bloque estancados del RPC. El tope
   393	              //    de 50 es señal, no listado: con 50 justos la pestaña dice 50+.
   394	              //    tabIndex 0 SOLO en el panel vacío (patrón WAI-ARIA: el panel
   395	              //    sin interactivos debe ser enfocable para que Tab no lo salte). ──
   396	              <div
   397	                id="panel-cola"
   398	                role="tabpanel"
   399	                aria-labelledby="tab-cola-sin_movimiento"
   400	                tabIndex={cola.estancados.length === 0 ? 0 : undefined}
   401	              >
   402	                {cola.estancados.length === 0 ? (
   403	                  <CardContent className="pb-5 pt-0">
   404	                    <p className="text-sm text-muted-foreground">
   405	                      Ningún lead del equipo lleva 5 días o más sin actividad.
   406	                    </p>
   407	                  </CardContent>
   408	                ) : (
   409	                  <>
   410	                    {/* F4.3: el resumen de novedades va ANTES de la lista —
   411	                        es la razón para escanearla. Solo existe si hay algo
   412	                        que decir (el silencio también es información). */}
   413	                    {resumenVisita != null && (
   414	                      <p className="border-t border-border/60 px-5 py-2 text-[11px] font-semibold text-muted-foreground-strong">
   415	                        {resumenVisita}
   416	                      </p>
   417	                    )}
   418	                    <div className="divide-y divide-border/60 border-t border-border/60">
   419	                      {cola.estancados.map((a) => {
   420	                        // F2: la gravedad va UNA vez, en la tira (rojo desde 7
   421	                        // días, ámbar 5–6); el texto queda en gris de contexto.
   422	                        // F4.3: la novedad es CATEGÓRICA, no de severidad —
   423	                        // chip violeta para el que entró; el que cruzó a
   424	                        // crítico ya tiene la tira roja y lo dice el texto.
   425	                        const esNuevo = novedadesVisita?.nuevos.has(a.leadId) === true
   426	                        const cruzoACritico = novedadesVisita?.agravados.has(a.leadId) === true
   427	                        const vendedor = (a.vendedorId != null ? nombrePorId.get(a.vendedorId) : null) ?? 'sin asignar'
   428	                        return (
   429	                          <button
   430	                            key={a.leadId}
   431	                            type="button"
   432	                            onClick={() => abrirLead(a.leadId)}
   433	                            // El label DICTA todo lo visible: el aria-label
   434	                            // pisa el contenido para un SR, así que lleva al
   435	                            // analista (a11y M1: de quién es el lead es parte
   436	                            // de la decisión), los días (la criticidad no
   437	                            // puede vivir solo en la tira de color) y el
   438	                            // literal del chip («nuevo aquí») para que el
   439	                            // dictado por voz también lo alcance (2.5.3).
   440	                            aria-label={`Abrir ficha de ${a.nombre} (${vendedor}), sin actividad ${haceTexto(a.dias)}${
   441	                              esNuevo
   442	                                ? ', nuevo aquí desde tu última visita'
   443	                                : cruzoACritico ? ', crítico desde tu última visita' : ''
   444	                            }`}
   445	                            className="flex w-full cursor-pointer items-center gap-2.5 border-l-[3px] py-2.5 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   446	                            style={{ borderLeftColor: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
   447	                          >
   448	                            <div className="min-w-0 flex-1 leading-tight">
   449	                              <p className="truncate text-sm font-semibold">
   450	                                {a.nombre}{' '}
   451	                                <span className="text-xs font-medium text-muted-foreground">
   452	                                  ({vendedor})
   453	                                </span>
   454	                              </p>
   455	                              <p className="text-[11px] font-medium text-muted-foreground">
   456	                                Sin actividad {haceTexto(a.dias)}
   457	                                {/* Gris FUERTE (a11y F4.3 #2): es la única
   458	                                    señal textual del cruce y el gris débil a
   459	                                    11px roza el 4.5:1 en hover. */}
   460	                                {cruzoACritico && (
   461	                                  <span className="text-muted-foreground-strong"> · crítico desde tu última visita</span>
   462	                                )}
   463	                              </p>
   464	                            </div>
   465	                            {esNuevo && (
   466	                              <Badge color={SEMAFORO.violeta} variant="outline" className="shrink-0 whitespace-nowrap">
   467	                                Nuevo aquí
   468	                              </Badge>
   469	                            )}
   470	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   471	                          </button>
   472	                        )
   473	                      })}
   474	                    </div>
   475	                  </>
   476	                )}
   477	              </div>
   478	            ) : filasCola.length === 0 ? (
   479	              <CardContent id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} tabIndex={0} className="pb-5 pt-0">
   480	                <p className="text-sm text-muted-foreground">
   481	                  {pestana === 'urgente'
   482	                    ? 'Nada urgente — ninguna fila crítica ni media en la cola.'
   483	                    : 'Sin pendientes — el equipo está al día con todos sus leads abiertos.'}
   484	                </p>
   485	              </CardContent>
   486	            ) : (
   487	              <div id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} className="divide-y divide-border/60 border-t border-border/60">
   488	                {/* Fila = div role="button" (no <button>: contiene los links de
   489	                    AccionesContacto y un botón no puede anidar interactivos).
   490	                    F2 (pregnancia): la severidad se dice UNA vez — la tira de
   491	                    3 px. Fuera el punto, el badge de etapa y el azul del monto;
   492	                    la etapa va en texto plano delante del motivo. El pl de
   493	                    17 px compensa los 3 px de la tira: el contenido queda a
   494	                    20 px, alineado con la cabecera (Codex F2). */}
   495	                {(colaExpandida ? filasCola : filasCola.slice(0, COLA_VISIBLES)).map((i) => {
   496	                  const abrir = () => abrirLead(i.lead.id)
   497	                  return (
   498	                    <div
   499	                      key={i.lead.id}
   500	                      role="button"
   501	                      tabIndex={0}
   502	                      data-sev={i.sev}
   503	                      onClick={abrir}
   504	                      onKeyDown={(e) => {
   505	                        if (e.key === 'Enter' || e.key === ' ') {
   506	                          e.preventDefault()
   507	                          abrir()
   508	                        }
   509	                      }}
   510	                      aria-label={`Abrir ficha de ${i.lead.nombre_completo}`}
   511	                      className="flex w-full cursor-pointer items-center gap-3 border-l-[3px] py-3 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   512	                      style={{ borderLeftColor: i.sev === 'baja' ? 'transparent' : SEV_COLOR[i.sev] }}
   513	                    >
   514	                      <div className="min-w-0 flex-1 leading-tight">
   515	                        <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
   516	                        <p className="truncate text-xs text-muted-foreground">
   517	                          {BUCKET_LABEL[i.bucket]} · {i.motivo}
   518	                        </p>
   519	                      </div>
   520	                      {i.lead.monto_estimado != null && (
   521	                        <span className="hidden shrink-0 text-xs font-semibold tabular-nums text-muted-foreground sm:inline">
   522	                          {moneyK(i.lead.monto_estimado, i.lead.moneda)}
   523	                        </span>
   524	                      )}
   525	                      {i.lead.vendedor_nombre ? (
   526	                        <span className="flex shrink-0 items-center gap-1.5">
   527	                          <Avatar nombre={i.lead.vendedor_nombre} className="size-6 text-[9px]" />
   528	                          <span className="hidden max-w-[110px] truncate text-xs text-muted-foreground md:inline">
   529	                            {i.lead.vendedor_nombre}
   530	                          </span>
   531	                        </span>
   532	                      ) : (
   533	                        <span className="shrink-0 text-xs font-medium text-muted-foreground">sin asignar</span>
   534	                      )}
   535	                      <AccionesContacto lead={i.lead} compacto />
   536	                      <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   537	                    </div>
   538	                  )
   539	                })}
   540	                {filasCola.length > COLA_VISIBLES && (
   541	                  <button
   542	                    type="button"
   543	                    onClick={() => setColaExpandida((e) => !e)}
   544	                    aria-expanded={colaExpandida}
   545	                    className="flex w-full cursor-pointer items-center justify-center gap-1 px-5 py-2.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   546	                  >
   547	                    <ChevronRight
   548	                      className={cn('size-3.5 shrink-0 transition-transform', colaExpandida && 'rotate-90')}
   549	                      aria-hidden
   550	                    />
   551	                    {colaExpandida
   552	                      ? `Mostrar solo los ${COLA_VISIBLES} más urgentes`
   553	                      // Con más pendientes que el p_limite del RPC, el botón no
   554	                      // puede prometer el total de la pestaña: dice lo que muestra.
   555	                      : totalPestanaActiva > filasCola.length
   556	                        ? `Ver los ${filasCola.length} más urgentes de ${totalPestanaActiva}`
   557	                        : `Ver los ${filasCola.length} pendientes`}
   558	                  </button>
   559	                )}
   560	              </div>
   561	            )}
   562	          </Card>
   563	          )}>
   564	            <Card>
   565	              <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
   566	                <div className="space-y-1">
   567	                  <h2 className="text-sm font-bold">Seguimiento del equipo</h2>
   568	                  <p className="text-xs text-muted-foreground">Prioriza las gestiones y revisa los plazos de cada analista.</p>
   569	                </div>
   570	                <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   571	                  Abrir seguimiento <ChevronRight className="size-4" aria-hidden />
   572	                </a>
   573	              </CardContent>
   574	            </Card>
   575	          </SlaOperacionBoundary>
   576	
   577	          {/* Rentabilidad R3: tus solicitudes de tasa en curso (solo si hay). */}
   578	          <TasasAutorizadasAnalistaPanel />
   579	
   580	          {/* ── Agenda del equipo (Fase F — quién registra, cierra y arrastra) ── */}
   581	          <AgendaEquipoPanel
   582	            datos={datosAgenda}
   583	            cargando={cargandoAgenda}
   584	            error={errorAgenda}
   585	            modoDemo={yo?.demo === true}
   586	            onReintentar={recargarAgenda}
   587	            equipo={equipo}
   588	          />
   589	        </div>
   590	        <div className="space-y-4 lg:col-span-2">
   591	          {/* ── Tu equipo hoy (semáforo por analista) ── */}
   592	          <Card className="overflow-hidden">
   593	            <SectionHead
   594	              icon={UsersRound}
   595	              title="Tu equipo hoy"
   596	              right={tc ? (
   597	                <span className="text-xs text-muted-foreground">
   598	                  Capital en proceso · {rotuloTipoCambio(tc.promedio, tc.fuente)}
   599	                </span>
   600	              ) : undefined}
   601	            />
   602	            {rank == null ? (
   603	              <CardContent className="pb-5 pt-0">
   604	                <p className="text-sm text-muted-foreground">
   605	                  {vendedoresOp.error
   606	                    ? 'El resumen por analista no está disponible en este momento.'
   607	                    : 'Cargando el resumen por analista…'}
   608	                </p>
   609	              </CardContent>
   610	            ) : rank.length === 0 ? (
   611	              <CardContent className="pb-5 pt-0">
   612	                <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   613	              </CardContent>
   614	            ) : (
   615	              <div className="divide-y divide-border/60 border-t border-border/60">
   616	                {rank.map((r) => {
   617	                  const c = semaforoDias(r.diasSinActividadMax)
   618	                  // Rezago de agenda del miembro (mismos umbrales del panel
   619	                  // Agenda del equipo: ámbar por rezago, rojo solo no-shows ≥2).
   620	                  const rez = rezagosAgenda.get(r.m.perfil_id)
   621	                  // El rezago de agenda TAMBIÉN es señal: sin esto, quien tocó
   622	                  // ayer pero arrastra 10 vencidas quedaba sin ninguna marca
   623	                  // visual (hallazgo IMPORTANTE de Codex sobre F2).
   624	                  const conRezagoAgenda = rez != null && (rez.vencidas > 0 || rez.leads_sin_accion > 0)
   625	                  const colorPunto = r.activos === 0
   626	                    ? SEMAFORO.neutro
   627	                    : c !== SEMAFORO.ok
   628	                      ? c
   629	                      : SEMAFORO.atencion
   630	                  const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   631	                  return (
   632	                    <div key={r.m.perfil_id} className="px-5 py-3">
   633	                      <div className="flex items-center gap-2.5">
   634	                        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
   635	                        <div className="min-w-0 flex-1 leading-tight">
   636	                          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
   637	                          <p className="text-[11px] tabular-nums text-muted-foreground">
   638	                            {r.activos} activos · {r.conversion == null
   639	                              ? r.conversionDisponible && r.divisorConversion === 0
   640	                                ? 'sin divisor mensual'
   641	                                : 'dato de conversión no disponible'
   642	                              : `${textoConversionOperativa(r.conversion)} conversión`}
   643	                            {r.operacionesCartera != null && r.operacionesCartera > 0
   644	                              ? ` · ${numero(r.operacionesCartera)} de cartera`
   645	                              : ''}
   646	                            {r.sinTocar > 0 ? ` · ${r.sinTocar} sin tocar` : ''}
   647	                          </p>
   648	                        </div>
   649	                        {/* Decisión #10: el total unificado es el número grande y el
   650	                            desglose por moneda va debajo. Sin TC degrada al PEN de
   651	                            siempre — el USD no entra al total sin una tasa real. */}
   652	                        <div className="shrink-0 text-right leading-tight">
   653	                          <p className="text-sm font-extrabold tabular-nums text-foreground">
   654	                            {cap.total != null ? moneyK(cap.total) : '—'}
   655	                          </p>
   656	                          <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
   657	                        </div>
   658	                      </div>
   659	                      <div className="mt-1.5 flex flex-wrap items-center gap-x-1.5 gap-y-1 pl-[46px]">
   660	                        {/* F2: el punto solo cuando HAY señal (ámbar 2–5 d,
   661	                            rojo >5 d, neutro sin cartera). Pintar «al día» de
   662	                            azul en cada fila gastaba el color en nada. Sin
   663	                            leads abiertos no hay «al día» que celebrar:
   664	                            `semaforoDias(0)` devolvía azul y un analista sin
   665	                            cartera se pintaba como el que va al corriente. */}
   666	                        {(r.activos === 0 || c !== SEMAFORO.ok || conRezagoAgenda) && (
   667	                          <span
   668	                            data-testid="equipo-semaforo"
   669	                            className="size-2 shrink-0 rounded-full"
   670	                            style={{ background: colorPunto }}
   671	                            aria-hidden
   672	                          />
   673	                        )}
   674	                        <span className="text-[11px] text-muted-foreground">
   675	                          {r.activos === 0
   676	                            ? 'Sin leads abiertos'
   677	                            : `Última actividad ${haceTexto(r.diasSinActividadMax)}`}
   678	                          {/* El rezago va en TEXTO pegado a la persona (aquí se
   679	                              juzga, decisión 1 del 2026-08-23); el único chip
   680	                              es el no-show repetido — uno de los dos rojos del
   681	                              presupuesto de color. */}
   682	                          {rez != null && rez.vencidas > 0
   683	                            && ` · ${rez.vencidas} ${rez.vencidas === 1 ? 'vencida' : 'vencidas'}`}
   684	                          {rez != null && rez.leads_sin_accion > 0
   685	                            && ` · ${rez.leads_sin_accion} sin acción`}
   686	                        </span>
   687	                        {rez != null && rez.no_asistio >= 2 && (
   688	                          <span className="ml-auto">
   689	                            {/* solid: el soft (rojo sobre tinte) da 4.01:1 a 11px
   690	                                y no llega a AA (revisor a11y, M2). */}
   691	                            <Badge color={SEMAFORO.critico} variant="solid">{rez.no_asistio} no asistió</Badge>
   692	                          </span>
   693	                        )}
   694	                      </div>
   695	                    </div>
   696	                  )
   697	                })}
   698	              </div>
   699	            )}
   700	          </Card>
   701	
   702	          {/* ── Cumplimiento confirmado del equipo ── */}
   703	          <Card>
   704	            <SectionHead
   705	              icon={Target}
   706	              title="Cumplimiento del equipo"
   707	              right={<span className="text-xs text-muted-foreground">contratos confirmados · este mes</span>}
   708	            />
   709	            <CardContent className="space-y-4 pb-5 pt-0">
   710	              {filasMeta.map((f) => (
   711	                <div key={f.label}>
   712	                  <div className="mb-1.5 flex items-baseline justify-between gap-2">
   713	                    <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
   714	                    <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
   715	                  </div>
   716	                  {f.nota && (
   717	                    <p className="mb-1 text-[10.5px] tabular-nums text-muted-foreground">{f.nota}</p>
   718	                  )}
   719	                  {f.sinDato ? (
   720	                    <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p>
   721	                  ) : (
   722	                    <Progress value={f.pct} color={colorMeta(f.pct)} />
   723	                  )}
   724	                </div>
   725	              ))}
   726	              <p className="text-[10.5px] text-muted-foreground">
   727	                El capital en dólares entra al total convertido a tipo de cambio real. El capital abierto de arriba es pronóstico y no cuenta como cumplimiento.
   728	              </p>
   729	              {hayErrorMensual && (
   730	                <Button variant="ghost" size="sm" onClick={reintentarMensual}>
   731	                  Reintentar
   732	                </Button>
   733	              )}
   734	            </CardContent>
   735	          </Card>
   736	
   737	          {/* ── Por empresa: de dónde vino cada sol (Avance vs. COOPAC). Se
   738	               oculta solo si el mes no tiene cierres en cooperativas. ── */}
   739	          <DesglosePorEmpresa
   740	            demo={yo?.demo === true}
   741	            porVendedor={cumplimientoMensual?.porVendedor ?? null}
   742	          />
   743	        </div>
   744	      </div>
   745	
   746	      <p className="text-[11px] text-muted-foreground">
   747	        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
   748	      </p>
   749	    </div>
   750	  )
   751	}
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
