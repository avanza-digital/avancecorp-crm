ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia, TEST GAPS, REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE.
Sin hallazgo sin evidencia. Omite secciones vacías.

# Encargo: AUDITAR «todo número se abre» en el Hoy del supervisor (commit 02e88946) — LEVEL 2

Regla nueva del dueño: todo número en pantalla debe poder pulsarse y enseñar la lista que hay
detrás. Cambios (diff abajo): cifras de la franja «Consulta» como enlaces (pronóstico → #/pipeline,
leads activos → #/cartera, que es la vista «Leads») o botones que abren «Detalle»; en «Detalle», los
KPI de pronóstico y leads son enlaces y «Primeras gestiones vencidas» cierra el diálogo, pone la
cola en esa pestaña y lleva el foco a ella (vía `focoAlCerrar` del Dialog de la casa, condicionado
a un estado); en la pantalla clásica (modo legado/demo), «Nuevos sin responder» es un botón que
salta a la pestaña Urgente (sin filtro por bucket: la cola legada no lo tiene), y pronóstico/leads
son enlaces.

Verificación del PRIMARY: `tsc -b` + `oxlint` PASS (pre-commit); vitest `src/screens/hoy/` 436/436
PASS (incluye el foco a la pestaña al cerrar el diálogo).

Busca: HTML/ARIA inválido (KpiCard = div dentro de <a>/<button>), nombres accesibles, carreras de
foco entre el cierre del diálogo y `verPrimeraGestion` (rAF), permisos de las vistas enlazadas para
el rol supervisor, y si algún número quedó sin abrirse. Si algo está bien, no lo menciones.

## DIFF del commit 02e88946
```diff
commit 02e889466ad836c94872e2d367776e6deaa0397f
Author: Miguel Briceño <avancecorp26@gmail.com>
Date:   Sun Sep 27 14:31:38 2026 -0500

    CRM: Hoy del supervisor — todo número se abre y enseña su lista
    
    Regla de Miguel (27/09): «para qué quiero saber si no puedo verlo».
    - Franja Consulta: pronóstico → Pipeline, leads activos → Leads; meta,
      conversión, toques, completadas y citas sin asistir abren el Detalle.
    - Detalle: los KPI de pronóstico y leads son enlaces; «Primeras gestiones
      vencidas» cierra el diálogo y deja la cola en esa pestaña con el foco.
    - Pantalla clásica: «Nuevos sin responder» abre la cola urgente;
      pronóstico y leads activos, sus vistas.
    
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
index 4345e0fc..e0769287 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
@@ -629,7 +629,7 @@ describe('Hoy · supervisor — puesto de mando: consulta y detalle (F3)', () =>
     for (const kpi of ['Pronóstico de capital abierto', 'Leads activos del equipo', 'Primeras gestiones vencidas', 'Por repartir']) {
       expect(within(dialogo).getByText(kpi)).toBeInTheDocument()
     }
-    expect(within(dialogo).getByText('Revísalas con cada analista')).toBeInTheDocument()
+    expect(within(dialogo).getByText('Ver cuáles son →')).toBeInTheDocument()
     expect(within(dialogo).getByRole('heading', { name: 'Cumplimiento del mes' })).toBeInTheDocument()
     expect(within(dialogo).getAllByText('Sin meta fijada para este mes').length).toBeGreaterThan(0)
     expect(within(dialogo).getByRole('region', { name: 'Agenda del equipo' })).toBeInTheDocument()
@@ -720,3 +720,33 @@ describe('Hoy · supervisor — puesto de mando: arreglos de la revisión F2/F3'
     expect(disparador).toHaveAttribute('aria-expanded', 'false')
   })
 })
+
+describe('Hoy · supervisor — puesto de mando: todo número se abre (Miguel, 27/09)', () => {
+  it('cada cifra de la franja lleva a su lista: pipeline, leads o el detalle', () => {
+    vi.useRealTimers()
+    montar()
+    const cifras = screen.getByRole('list', { name: 'Cifras del equipo' })
+    expect(within(cifras).getByRole('link', { name: /pronóstico/ })).toHaveAttribute('href', '#/pipeline')
+    expect(within(cifras).getByRole('link', { name: /leads activos/ })).toHaveAttribute('href', '#/cartera')
+    for (const nombre of [/de la meta/, /conversión del mes/, /toques en 7 días/, /completadas/, /sin asistir/]) {
+      expect(within(cifras).getByRole('button', { name: nombre })).toBeInTheDocument()
+    }
+    fireEvent.click(within(cifras).getByRole('button', { name: /sin asistir/ }))
+    expect(screen.getByRole('dialog', { name: 'Detalle del equipo' })).toBeInTheDocument()
+  })
+
+  it('«Primeras gestiones vencidas» del detalle cierra el diálogo y deja la cola en esa pestaña, con el foco en ella', async () => {
+    vi.useRealTimers()
+    montar()
+    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
+    const dialogo = screen.getByRole('dialog', { name: 'Detalle del equipo' })
+    expect(within(dialogo).getByRole('link', { name: /Pronóstico de capital abierto/ })).toHaveAttribute('href', '#/pipeline')
+    expect(within(dialogo).getByRole('link', { name: /Leads activos del equipo/ })).toHaveAttribute('href', '#/cartera')
+    fireEvent.click(within(dialogo).getByRole('button', { name: /Primeras gestiones vencidas/ }))
+    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
+    const pestana = screen.getByRole('tab', { name: /Primera gestión/ })
+    expect(pestana).toHaveAttribute('aria-selected', 'true')
+    expect(pedidoCola()?.filtros.senal).toBe('primera_atencion')
+    await waitFor(() => expect(pestana).toHaveFocus())
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
index f6956eb0..d221de80 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
@@ -67,6 +67,11 @@ const SEV_TEXTO: Record<CosaDeHoy['severidad'], string> = { critica: 'Hoy', aten
 const SEV_TEXTO_COLOR: Record<CosaDeHoy['severidad'], string> = { critica: 'var(--destructive-text)', atencion: 'var(--warning-text)' }
 const SEV_BORDE: Record<CosaDeHoy['severidad'], string> = { critica: SEMAFORO.critico, atencion: SEMAFORO.atencion }
 
+// Regla de Miguel (27/09/2026): «para qué quiero saber si no puedo verlo».
+// TODO número de esta pantalla se abre y enseña la lista que hay detrás.
+const CLASE_CIFRA = 'inline-flex min-h-9 cursor-pointer items-center gap-1 rounded-md px-1 -mx-1 text-left underline-offset-4 decoration-muted-foreground/60 hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
+const CLASE_KPI_ENLACE = 'relative block h-full w-full cursor-pointer rounded-xl text-left text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background'
+
 /** Chip de señal: el ámbar suave usa el token de TEXTO (el hex puro no llega a 4.5:1 sobre su tinte). */
 function ChipSenal({ texto, nivel }: { texto: string; nivel: 'critico' | 'atencion' }): JSX.Element {
   return nivel === 'critico'
@@ -144,6 +149,14 @@ function PuestoDeMando(): JSX.Element {
   const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
   const [detalleAbierto, setDetalleAbierto] = useState(false)
   const tituloDetalle = useRef<HTMLSpanElement>(null)
+  // Si el detalle se cierra PARA ir a la cola, el foco va a la pestaña (y no
+  // vuelve al botón «Detalle», que es lo que Radix haría por defecto).
+  const focoTrasDetalle = useRef<HTMLElement | null>(null)
+  const [focoALaCola, setFocoALaCola] = useState(false)
+  const abrirDetalle = () => {
+    setFocoALaCola(false)
+    setDetalleAbierto(true)
+  }
 
   const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
   const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
@@ -691,28 +704,52 @@ function PuestoDeMando(): JSX.Element {
         {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
         <ul role="list" aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
           <li>
-            <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
-            {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
+            <a href={hashDe('pipeline')} className={CLASE_CIFRA}>
+              <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
+              {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
+            </a>
+          </li>
+          <li>
+            <a href={hashDe('cartera')} className={CLASE_CIFRA}>
+              <strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos
+            </a>
+          </li>
+          <li>
+            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
+              <strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta
+            </button>
+          </li>
+          <li>
+            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
+              <strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes
+            </button>
           </li>
-          <li><strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos</li>
-          <li><strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta</li>
-          <li><strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes</li>
           <li aria-hidden className="h-[18px] w-px bg-border" />
-          <li><strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días</li>
-          <li><strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas</li>
-          <li className="inline-flex items-center gap-1">
-            {agendaResumen && agendaResumen.noAsistio >= 2 && (
-              <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />
-            )}
-            <strong
-              className="font-extrabold"
-              style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
-            >
-              {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
-            </strong> {agendaResumen?.noAsistio === 1 ? 'cita sin asistir' : 'citas sin asistir'}
+          <li>
+            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
+              <strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días
+            </button>
+          </li>
+          <li>
+            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
+              <strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas
+            </button>
+          </li>
+          <li>
+            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
+              {agendaResumen && agendaResumen.noAsistio >= 2 && (
+                <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />
+              )}
+              <strong
+                className="font-extrabold"
+                style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
+              >
+                {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
+              </strong> {agendaResumen?.noAsistio === 1 ? 'cita sin asistir' : 'citas sin asistir'}
+            </button>
           </li>
         </ul>
-        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent pointer-coarse:min-h-10" onClick={() => setDetalleAbierto(true)}>
+        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent pointer-coarse:min-h-10" onClick={abrirDetalle}>
           Detalle
         </Button>
       </section>
@@ -721,6 +758,7 @@ function PuestoDeMando(): JSX.Element {
         open={detalleAbierto}
         onClose={() => setDetalleAbierto(false)}
         focoInicial={tituloDetalle}
+        focoAlCerrar={focoALaCola ? focoTrasDetalle : undefined}
         className="w-[1180px] max-h-[88vh] max-w-[94vw]"
       >
         <DialogHeader>
@@ -731,6 +769,7 @@ function PuestoDeMando(): JSX.Element {
         <DialogBody className="space-y-4">
           <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
             {/* Pronóstico: `capitalPrincipal`, NUNCA un total mixto con los dólares. */}
+            <a href={hashDe('pipeline')} className={CLASE_KPI_ENLACE}>
             <KpiCard
               label="Pronóstico de capital abierto"
               value={pronostico ? pronostico.valor : '—'}
@@ -746,6 +785,8 @@ function PuestoDeMando(): JSX.Element {
                       : 'En soles · abiertos con analista'
               }
             />
+            </a>
+            <a href={hashDe('cartera')} className={CLASE_KPI_ENLACE}>
             <KpiCard
               label="Leads activos del equipo"
               value={datos.resumen ? String(datos.resumen.totales.asignados) : '—'}
@@ -754,16 +795,29 @@ function PuestoDeMando(): JSX.Element {
               sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
               delay={60}
             />
-            <KpiCard
-              label="Primeras gestiones vencidas"
-              value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
-              icon={AlertTriangle}
-              color={SEMAFORO.neutro}
-              sub={primeraGestionPendiente == null
-                ? 'Sin dato por ahora'
-                : primeraGestionPendiente > 0 ? 'Revísalas con cada analista' : 'Ninguna vencida'}
-              delay={120}
-            />
+            </a>
+            {/* Abre la cola en su pestaña: cierra el detalle y deja el foco en ella. */}
+            <button
+              type="button"
+              className={CLASE_KPI_ENLACE}
+              onClick={() => {
+                focoTrasDetalle.current = document.getElementById(`${idPanelCola}-tab-primera_atencion`)
+                setFocoALaCola(true)
+                setDetalleAbierto(false)
+                verPrimeraGestion()
+              }}
+            >
+              <KpiCard
+                label="Primeras gestiones vencidas"
+                value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
+                icon={AlertTriangle}
+                color={SEMAFORO.neutro}
+                sub={primeraGestionPendiente == null
+                  ? 'Sin dato por ahora'
+                  : primeraGestionPendiente > 0 ? 'Ver cuáles son →' : 'Ninguna vencida'}
+                delay={120}
+              />
+            </button>
             <a
               href={hashDe('derivaciones')}
               aria-label={`Por repartir: ${datos.etiquetaAccesoReparto}`}
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx
index fcf899ca..5418bc2d 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.test.tsx
@@ -533,6 +533,19 @@ describe('Hoy · supervisor — «Hoy, tres cosas» (F3)', () => {
     expect(screen.queryByText(/citas sin asistir/)).not.toBeInTheDocument()
   })
 
+  it('los números se abren: «Nuevos sin responder» lleva a la cola urgente y el pronóstico al pipeline (Miguel, 27/09)', () => {
+    vi.useFakeTimers({ toFake: ['setTimeout', 'setInterval', 'Date', 'requestAnimationFrame'] })
+    montar({ leads: [viejo, nuevoLead] })
+    fireEvent.click(screen.getByRole('tab', { name: 'Todo: 2' }))
+    fireEvent.click(screen.getByRole('button', { name: 'Nuevos sin responder: 1. Ver en la cola urgente' }))
+    vi.advanceTimersByTime(50)
+    const urgente = screen.getByRole('tab', { name: 'Urgente: 1' })
+    expect(urgente).toHaveAttribute('aria-selected', 'true')
+    expect(document.activeElement).toBe(urgente)
+    expect(screen.getByRole('link', { name: /Pronóstico de capital abierto/ })).toHaveAttribute('href', '#/pipeline')
+    expect(screen.getByRole('link', { name: /Leads activos del equipo/ })).toHaveAttribute('href', '#/cartera')
+  })
+
   it('ESTADO DE PRODUCCIÓN (sin nada que hacer): la franja NO se pinta', () => {
     montar({ leads: [] })
     expect(screen.queryByRole('region', { name: 'Hoy, tres cosas' })).not.toBeInTheDocument()
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
index b3fc57c1..b729018a 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
@@ -248,6 +248,8 @@ export function HoySupervisor(): JSX.Element {
         {/* F2 (figura-fondo): los KPIs son CONSULTA, no alarma — iconos en
             neutro. Desde F3 TODOS: la urgencia de «Nuevos sin responder»
             vive en la franja, que es su reemplazo. */}
+        {/* Regla de Miguel (27/09/2026): todo número se abre y enseña su lista. */}
+        <a href={hashDe('pipeline')} className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background">
         <KpiCard
           label="Pronóstico de capital abierto"
           // `capitalPrincipal` y NO `totalEnSoles`: esto es PRONÓSTICO, no
@@ -267,6 +269,8 @@ export function HoySupervisor(): JSX.Element {
           }
           delay={0}
         />
+        </a>
+        <a href={hashDe('cartera')} className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background">
         <KpiCard
           label="Leads activos del equipo"
           value={resumen ? String(resumen.totales.asignados) : '—'}
@@ -275,8 +279,17 @@ export function HoySupervisor(): JSX.Element {
           sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
           delay={60}
         />
+        </a>
         {/* Sin payload, los subs NO afirman estados positivos («todos
-            contactados», «bandeja vacía»): sin dato no hay afirmación. */}
+            contactados», «bandeja vacía»): sin dato no hay afirmación.
+            Abre la pestaña Urgente de la cola, donde van esos leads. */}
+        <button
+          type="button"
+          aria-label={cola ? `Nuevos sin responder: ${cola.porBucket.sin_responder ?? 0}. Ver en la cola urgente` : 'Nuevos sin responder: sin dato'}
+          onClick={() => irAPestanaCola('urgente')}
+          disabled={cola == null}
+          className="relative block h-full w-full cursor-pointer rounded-xl text-left text-inherit outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-default"
+        >
         <KpiCard
           label="Nuevos sin responder"
           value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
@@ -291,6 +304,7 @@ export function HoySupervisor(): JSX.Element {
           }
           delay={120}
         />
+        </button>
         <a
           href={hashDe('derivaciones')}
           aria-label={etiquetaAccesoReparto}
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

### `app/src/components/common/kpi-card.tsx`
```
     1	// KpiCard — card-hero de KPI reutilizable (extraída de la pantalla Hoy, F1c).
     2	// Anatomía: icono en tile (ac-chip), valor grande animado (AnimatedValue),
     3	// label y sub. Las 4 variantes de "Hoy" (vendedor/supervisor/gerencia/
     4	// directorio) la comparten para no duplicar el mismo markup.
     5	//
     6	// Sprint A (A3, honestidad): el sparkline y el chip de tendencia (±%) NO se
     7	// renderizan — sus series eran datos de demostración junto a cifras reales, y
     8	// las props `spark`/`tendencia` ya se retiraron de la firma (estaban muertas).
     9	// Cuando existan series reales, reintroducirlas junto con su render (la base
    10	// del chip sigue viva en lib/inteligencia.tendenciaDe, marcada @deprecated).
    11	import type { CSSProperties, JSX } from 'react'
    12	import type { LucideIcon } from 'lucide-react'
    13	import { Card, CardContent } from '@/components/ui/card'
    14	import { AnimatedValue } from '@/components/common/animated-value'
    15	
    16	export interface KpiCardProps {
    17	  label: string
    18	  /** Valor ya formateado (money/moneyK/String) — AnimatedValue anima su parte numérica. */
    19	  value: string
    20	  icon: LucideIcon
    21	  /** Color CSS del tile (ej. 'var(--chart-1)' o '#2563eb'). */
    22	  color: string
    23	  /** Línea secundaria bajo el label (ej. 'Pipeline activo (PEN) · +US$ 25k'). */
    24	  sub?: string | undefined
    25	  /** animationDelay del pop de entrada, en ms (escalonar: i * 60). */
    26	  delay?: number | undefined
    27	}
    28	
    29	export function KpiCard({ label, value, icon: Icon, color, sub, delay = 0 }: KpiCardProps): JSX.Element {
    30	  return (
    31	    <Card
    32	      className="ac-lift ac-pop h-full overflow-hidden border-border/80 bg-card/95 shadow-[0_12px_28px_-24px_rgba(15,31,61,0.8)]"
    33	      style={{ animationDelay: `${delay}ms` }}
    34	    >
    35	      <CardContent className="p-4">
    36	        <div className="flex items-start justify-between gap-3">
    37	          <div className="min-w-0 text-[11px] font-bold uppercase tracking-[0.08em] text-foreground/65">
    38	            {label}
    39	          </div>
    40	          <span
    41	            className="ac-chip grid size-10 shrink-0 place-items-center rounded-xl"
    42	            style={{ '--c': color } as CSSProperties}
    43	          >
    44	            <Icon className="size-5" />
    45	          </span>
    46	        </div>
    47	        <div className="mt-3 whitespace-nowrap text-[clamp(1.35rem,2.2vw,1.75rem)] font-extrabold leading-none tracking-tight tabular-nums text-primary">
    48	          <AnimatedValue value={value} />
    49	        </div>
    50	        {sub && (
    51	          <div className="mt-3 border-t border-border/70 pt-2.5 text-xs font-medium leading-relaxed text-muted-foreground">
    52	            {sub}
    53	          </div>
    54	        )}
    55	      </CardContent>
    56	    </Card>
    57	  )
    58	}
```

### `app/src/lib/vistas.ts`
```
     1	// Política única de acceso a vistas para la UX. Sidebar y App consumen estas
     2	// funciones; la seguridad real permanece en la RLS del esquema crm.
     3	import { can, esRol, type Accion, type Rol } from '@/lib/roles'
     4	import { esVistaConfiguracion, esVistaGerencia, esVistaLeads, type Vista } from '@/lib/router'
     5	
     6	type EstadoGateLeads = 'abierto' | 'cerrado'
     7	
     8	/** Landing exhaustiva por rol; no concede acceso a ninguna otra vista. */
     9	const VISTA_BASE_POR_ROL = {
    10	  vendedor: { abierto: 'hoy', cerrado: 'mi-cartera' },
    11	  supervisor: { abierto: 'hoy', cerrado: 'mi-cartera' },
    12	  gerencia: { abierto: 'hoy', cerrado: 'hoy' },
    13	  directorio: { abierto: 'hoy', cerrado: 'mi-cartera' },
    14	  coordinador: { abierto: 'repartir', cerrado: 'repartir' },
    15	} as const satisfies Record<Rol, Record<EstadoGateLeads, Vista>>
    16	
    17	/**
    18	 * Capacidad exigida por cada vista. `hoy` conserva su acceso histórico por rol
    19	 * y gate; el contenido interno continúa aplicando sus capacidades específicas.
    20	 */
    21	const CAPACIDAD_POR_VISTA = {
    22	  hoy: null,
    23	  alertas: 'verAlertas',
    24	  seguimiento: 'verLeads',
    25	  'gestion-diaria': 'verLeads',
    26	  conversiones: null,
    27	  'ranking-vendedores': null,
    28	  // Gerencia ve el universo y Supervisión solo su equipo; la RPC impone el alcance.
    29	  reuniones: 'verCitasEquipo',
    30	  metas: null,
    31	  rendimiento: null,
    32	  // Gerencia y Supervisión (su equipo), 16/09/2026. El servidor recorta el ámbito.
    33	  facturacion: 'verFacturacion',
    34	  'informes-empresas': null,
    35	  pipeline: 'verPipeline',
    36	  cartera: 'verLeads',
    37	  agenda: 'verAgenda',
    38	  'mi-cartera': 'verCartera',
    39	  repartir: 'repartirCola',
    40	  rescate: 'repartirLeads',
    41	  'rescate-carpeta': 'repartirLeads',
    42	  derivaciones: 'verDerivacionesEquipo',
    43	  equipo: 'verGestionEquipo',
    44	  config: 'verConfiguracion',
    45	  'config-usuarios': null,
    46	  'config-productos': null,
    47	  'config-metas': null,
    48	  'config-sla': null,
    49	  'config-gestion-diaria': null,
    50	  'config-rentabilidad': null,
    51	  'config-citas': null,
    52	} as const satisfies Record<Vista, Accion | null>
    53	
    54	/** Dónde aterriza un rol cuando la ruta pedida no existe o no está permitida. */
    55	export function vistaBase(
    56	  rol: Rol | null | undefined,
    57	  leadsVisibles: boolean,
    58	  rolPortal?: string | null,
    59	): Vista {
    60	  // Compatibilidad defensiva: Workspace solo se monta con un perfil enrolado,
    61	  // pero los callers históricos conservan el mismo fallback para un rol ausente.
    62	  if (!esRol(rol)) return leadsVisibles ? 'hoy' : 'mi-cartera'
    63	  // La autoridad Portal para gobernar roles no convierte a Superadmin en un
    64	  // lector/operador CRM. Gerencia + Superadmin conserva la landing de Gerencia.
    65	  if (rolPortal === 'superadmin' && rol !== 'gerencia') return 'config-usuarios'
    66	  const estado: EstadoGateLeads = leadsVisibles ? 'abierto' : 'cerrado'
    67	  return VISTA_BASE_POR_ROL[rol][estado]
    68	}
    69	
    70	/**
    71	 * Única decisión de acceso a una vista. Es fail-closed para identidades ajenas
    72	 * al catálogo y mantiene la landing de Gerencia en Hoy aun si el gate se cierra.
    73	 */
    74	export function vistaPermitida(
    75	  vista: Vista,
    76	  rol: Rol | null | undefined,
    77	  leadsVisibles: boolean,
    78	  rolPortal?: string | null,
    79	): boolean {
    80	  if (!esRol(rol)) return false
    81	  if (vista === 'config-citas') return rolPortal === 'superadmin'
    82	  if (rolPortal === 'superadmin' && rol !== 'gerencia') {
    83	    return vista === 'config-usuarios'
    84	  }
    85	  if (vista === vistaBase(rol, leadsVisibles, rolPortal)) return true
    86	  // La bandeja es transversal, pero sus fuentes operativas dependen del gate
    87	  // de leads. Gerencia conserva siempre sus alertas ejecutivas agregadas.
    88	  if (vista === 'alertas') {
    89	    return can(rol, 'verAlertas') && (rol === 'gerencia' || leadsVisibles)
    90	  }
    91	  if (esVistaConfiguracion(vista)) {
    92	    if (vista === 'config-usuarios' && rolPortal === 'superadmin') return true
    93	    return rol === 'gerencia' || rol === 'directorio'
    94	  }
    95	  // Citas comparte el patrón de Facturación: Supervisión tiene una lectura de
    96	  // su subárbol, y Gerencia conserva el universo. Las demás vistas ejecutivas
    97	  // continúan siendo exclusivas de Gerencia.
    98	  if (vista === 'reuniones') return can(rol, 'verCitasEquipo')
    99	  if (esVistaGerencia(vista)) return rol === 'gerencia'
   100	  // El mundo leads se cierra por la llave general y, SIEMPRE, para el
   101	  // coordinador: su ámbito de leads es ∅ y su único destino es «Repartir».
   102	  // «hoy» no exige capacidad, así que sin este corte la llave abierta se la
   103	  // regalaría. Defensa en profundidad: config.ts tampoco la enciende para él.
   104	  if (esVistaLeads(vista) && (!leadsVisibles || rol === 'coordinador')) return false
   105	  // La cola operativa se ofrece a quienes ya la tenían en Hoy. Directorio
   106	  // conserva su auditoría ejecutiva y no incorpora este módulo de gestión.
   107	  if (vista === 'seguimiento') return rol === 'gerencia' || rol === 'supervisor' || rol === 'vendedor'
   108	  // Gestión Diaria: los mismos tres roles operativos. Directorio tiene `verLeads`
   109	  // pero es lector: no entra a un módulo de gestión (decisión de Miguel, 19/09/2026).
   110	  if (vista === 'gestion-diaria') return rol === 'gerencia' || rol === 'supervisor' || rol === 'vendedor'
   111	
   112	  const capacidad = CAPACIDAD_POR_VISTA[vista]
   113	  return capacidad === null || can(rol, capacidad)
   114	}
   115	
   116	/** Corrige una vista pedida (hash/estado) a una que el rol SÍ puede ver. */
   117	export function sanearVista(
   118	  vista: Vista,
   119	  rol: Rol | null | undefined,
   120	  leadsVisibles: boolean,
   121	  rolPortal?: string | null,
   122	): Vista {
   123	  return vistaPermitida(vista, rol, leadsVisibles, rolPortal)
   124	    ? vista
   125	    : vistaBase(rol, leadsVisibles, rolPortal)
   126	}
```

### `app/src/lib/roles.ts (capacidades)`
```
     1	// Fuente única de capacidades por rol (patrón VITANOVA, 4 niveles).
     2	// NO es seguridad (eso vive en la RLS del esquema crm) — es la UX.
     3	// Regla de oro: lo que can() oculta, la RLS también lo niega.
     4	
     5	/** Catálogo runtime de roles CRM — fuente única: el tipo `Rol` se deriva de aquí.
     6	 * `coordinador` (C1, 2026-07-22) es OFF-ROSTER como `directorio`: existe como
     7	 * identidad y como fila real de crm.equipo (para que las RPC lo gateen), pero
     8	 * NUNCA como fila de roster visible (ver Miembro.rol_crm en tipos.ts). */
     9	export const ROLES = ['vendedor', 'supervisor', 'gerencia', 'directorio', 'coordinador'] as const
    10	
    11	export type Rol = (typeof ROLES)[number]
    12	
    13	/** Type guard para datos externos (Supabase/JSON): ¿es un rol CRM válido? */
    14	export function esRol(valor: unknown): valor is Rol {
    15	  return typeof valor === 'string' && (ROLES as readonly string[]).includes(valor)
    16	}
    17	
    18	/** Catálogo runtime de capacidades. El tipo y las pruebas se derivan de aquí. */
    19	export const ACCIONES = [
    20	  'verTodo',            // ámbito completo de la empresa
    21	  'verEquipo',          // ver a otros miembros del equipo
    22	  'filtrarPorVendedor',
    23	  'reasignar',
    24	  'repartirLeads',      // supervisor: baja leads de su bandeja a sus analistas
    25	  'repartirCola',       // coordinador: reparte la COLA GLOBAL a las bandejas (C1)
    26	  'verPipeline',
    27	  'verLeads',
    28	  'verAgenda',
    29	  'verGestionEquipo',
    30	  'verDerivacionesEquipo', // módulo de reparto propio del supervisor
    31	  'verFacturacion',     // tablero Facturación: Gerencia ve la empresa, Supervisión
    32	                        // SU equipo (Miguel, 16/09/2026); espejo de la verja de
    33	                        // crm.facturacion_diaria_fn, que a los demás les da vacío
    34	  'verCitasEquipo',     // Citas: Gerencia ve la empresa; Supervisión, su subárbol.
    35	  'verAlertas',         // bandeja por destinatario (propia, equipo o ejecutiva)
    36	  'tomarLeadDirecto',   // F2 lead libre: tomar para SÍ un contacto en bolsa o
    37	                        // reutilizable tras verificar — SOLO analista (espejo
    38	                        // del guard de crm.tomar_lead_libre: supervisión
    39	                        // asigna por el reparto, jamás por esta puerta)
    40	  'verCartera',         // pantalla unificada Clientes+Contratos ('mi-cartera')
    41	  'altaDirectaCliente', // «Nuevo cliente» en Mi cartera = alta SIN lead. Cerrada
    42	                        // al analista (decisión de Miguel, 15/09/2026): su
    43	                        // cliente nuevo nace CONVIRTIENDO un lead, para que el
    44	                        // capital del ranking no entre por fuera de la
    45	                        // conversión (caso real: S/ 222 450 en el puesto 1 del
    46	                        // ranking con 0 % de conversión, todo por esta puerta).
    47	                        // Supervisión y Gerencia la conservan: no rankean.
    48	  'verConfiguracion',   // pantalla 'config' — incluye la suscripción ICS PROPIA
    49	  'editarConfiguracion',
    50	  'verReportes',
    51	  'editarMetas',
    52	  'editarCapacidad',
    53	  'soloLecturaTotal',   // directorio/auditoría: NO escribe NADA (ni lo propio)
    54	] as const
    55	
    56	export type Accion = (typeof ACCIONES)[number]
    57	
    58	export type Caps = Record<Accion, boolean>
    59	
    60	export const CAPS: Record<Rol, Caps> = {
    61	  // El analista VE Configuración (no la edita): ahí vive "Mi calendario de
    62	  // Google", la suscripción ICS que lleva SU agenda al celular, y con
    63	  // verConfiguracion:false esa pantalla no existía para él — ni en el nav ni por
    64	  // URL (sanearVista lo expulsaba) — justo para el único rol que trabaja en la
    65	  // calle. No se abre nada más: editarConfiguracion sigue en false (las metas
    66	  // del mes y toda escritura de configuración siguen siendo de gerencia) y la
    67	  // tarjeta ICS pide SIEMPRE el perfil propio (perfil_id = yo.id, espejo de la
    68	  // RLS "cada quien SU fila" en crm.agenda_ics): nadie exporta agenda ajena.
    69	  vendedor: {
    70	    verTodo: false, verEquipo: false, filtrarPorVendedor: false,
    71	    altaDirectaCliente: false,
    72	    reasignar: false, repartirLeads: false, repartirCola: false, verCartera: true,
    73	    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: false,
    74	    verDerivacionesEquipo: false,
    75	    verFacturacion: false,
    76	    verCitasEquipo: false,
    77	    verAlertas: true, tomarLeadDirecto: true,
    78	    verConfiguracion: true, editarConfiguracion: false,
    79	    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
    80	  },
    81	  supervisor: {
    82	    verTodo: false, verEquipo: true, filtrarPorVendedor: true,
    83	    altaDirectaCliente: true,
    84	    reasignar: true, repartirLeads: true, repartirCola: false, verCartera: true,
    85	    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    86	    verDerivacionesEquipo: true,
    87	    verFacturacion: true,
    88	    verCitasEquipo: true,
    89	    verAlertas: true, tomarLeadDirecto: false,
    90	    verConfiguracion: false, editarConfiguracion: false,
    91	    verReportes: true, editarMetas: false, editarCapacidad: false, soloLecturaTotal: false,
    92	  },
    93	  gerencia: {
    94	    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
    95	    altaDirectaCliente: true,
    96	    reasignar: true, repartirLeads: true, repartirCola: true, verCartera: true,
    97	    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
    98	    verDerivacionesEquipo: false,
    99	    verFacturacion: true,
   100	    verCitasEquipo: true,
   101	    verAlertas: true, tomarLeadDirecto: false,
   102	    verConfiguracion: true, editarConfiguracion: true,
   103	    verReportes: true, editarMetas: true, editarCapacidad: true, soloLecturaTotal: false,
   104	  },
   105	  directorio: {
   106	    verTodo: true, verEquipo: true, filtrarPorVendedor: true,
   107	    altaDirectaCliente: false,
   108	    reasignar: false, repartirLeads: false, repartirCola: false, verCartera: true,
   109	    verPipeline: true, verLeads: true, verAgenda: true, verGestionEquipo: true,
   110	    verDerivacionesEquipo: false,
```

### `app/src/screens/hoy/supervisor-mando.tsx (estado final)`
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
    70	// Regla de Miguel (27/09/2026): «para qué quiero saber si no puedo verlo».
    71	// TODO número de esta pantalla se abre y enseña la lista que hay detrás.
    72	const CLASE_CIFRA = 'inline-flex min-h-9 cursor-pointer items-center gap-1 rounded-md px-1 -mx-1 text-left underline-offset-4 decoration-muted-foreground/60 hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
    73	const CLASE_KPI_ENLACE = 'relative block h-full w-full cursor-pointer rounded-xl text-left text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background'
    74	
    75	/** Chip de señal: el ámbar suave usa el token de TEXTO (el hex puro no llega a 4.5:1 sobre su tinte). */
    76	function ChipSenal({ texto, nivel }: { texto: string; nivel: 'critico' | 'atencion' }): JSX.Element {
    77	  return nivel === 'critico'
    78	    ? <Badge color={SEMAFORO.critico} variant="solid">{texto}</Badge>
    79	    : <Badge color="var(--warning-text)">{texto}</Badge>
    80	}
    81	
    82	const COLOR_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
    83	  critico: SEMAFORO.critico,
    84	  atencion: SEMAFORO.atencion,
    85	  neutro: SEMAFORO.neutro,
    86	}
    87	const TEXTO_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
    88	  critico: 'En rojo',
    89	  atencion: 'En ámbar',
    90	  neutro: 'Sin cartera abierta',
    91	}
    92	
    93	/**
    94	 * Marca del nivel con FORMA además de color (rojo y ámbar se confunden con
    95	 * protanopia): triángulo = rojo, punto lleno = ámbar, aro = neutro.
    96	 */
    97	function MarcaNivel({ nivel }: { nivel: LecturaAnalista['nivel'] }): JSX.Element {
    98	  if (nivel == null) return <span className="size-3 shrink-0" aria-hidden />
    99	  if (nivel === 'critico') {
   100	    return <AlertTriangle data-testid="equipo-semaforo" data-nivel={nivel} className="size-3 shrink-0" style={{ color: SEMAFORO.critico }} aria-hidden />
   101	  }
   102	  return (
   103	    <span
   104	      data-testid="equipo-semaforo"
   105	      data-nivel={nivel}
   106	      className={cn('size-2 shrink-0 rounded-full', nivel === 'neutro' && 'border-2 bg-transparent')}
   107	      style={nivel === 'neutro' ? { borderColor: COLOR_NIVEL.neutro } : { background: COLOR_NIVEL[nivel] }}
   108	      aria-hidden
   109	    />
   110	  )
   111	}
   112	
   113	export function HoySupervisorMando(): JSX.Element {
   114	  const modo = useModoSla()
   115	  const { yo } = useAuth()
   116	  if (modo.legado) return <HoySupervisor />
   117	  // Cambiar de identidad o de revisión del seguimiento remonta la pantalla:
   118	  // ningún filtro ni selección sobrevive sobre datos de otra (como
   119	  // SlaOperacionBoundary).
   120	  return <PuestoDeMando key={`${yo?.id ?? ''}|${yo?.rol ?? ''}|${modo.data?.control_revision ?? 'sin-revision'}`} />
   121	}
   122	
   123	function PuestoDeMando(): JSX.Element {
   124	  const modo = useModoSla()
   125	  const datos = useDatosSupervisor()
   126	  const { abrirLead } = usePanelesActions()
   127	  const { yo } = useAuth()
   128	  const { ambito, rank, tc, ahora } = datos
   129	  const idPanelCola = useId()
   130	
   131	  const [pestana, setPestana] = useState<PestanaMando>('pendientes')
   132	  const [analistaElegido, setAnalistaId] = useState<string | null>(null)
   133	  // Analistas SELECCIONABLES del equipo (no las filas cargadas): los chips no
   134	  // dependen de lo que haya traído la página ni prometen conteos del cliente.
   135	  const analistas = useMemo(
   136	    () => ambito.vendedores
   137	      .filter((m) => m.activo && m.rol_crm === 'vendedor')
   138	      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
   139	    [ambito.vendedores],
   140	  )
   141	  // El filtro vale solo para quien sigue siendo seleccionable: quien sale, se
   142	  // desactiva o cambia de rol no deja la cola filtrada por un id sin chip.
   143	  const analistaId = analistaElegido != null && analistas.some((m) => m.perfil_id === analistaElegido)
   144	    ? analistaElegido
   145	    : null
   146	  const [anuncio, setAnuncio] = useState('')
   147	  const [abriendo, setAbriendo] = useState<string | null>(null)
   148	  const [errorApertura, setErrorApertura] = useState(false)
   149	  const [decisionAbierta, setDecisionAbierta] = useState<CosaDeHoy['id'] | null>(null)
   150	  const [detalleAbierto, setDetalleAbierto] = useState(false)
   151	  const tituloDetalle = useRef<HTMLSpanElement>(null)
   152	  // Si el detalle se cierra PARA ir a la cola, el foco va a la pestaña (y no
   153	  // vuelve al botón «Detalle», que es lo que Radix haría por defecto).
   154	  const focoTrasDetalle = useRef<HTMLElement | null>(null)
   155	  const [focoALaCola, setFocoALaCola] = useState(false)
   156	  const abrirDetalle = () => {
   157	    setFocoALaCola(false)
   158	    setDetalleAbierto(true)
   159	  }
   160	
   161	  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
   162	  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
   163	  // Fail-closed: TanStack conserva la última respuesta tras un refetch
   164	  // fallido; con error, la cola NO se muestra como vigente.
   165	  const pagina = consultaCola.error ? undefined : consultaCola.data
   166	  // Vigente = modo activo Y la MISMA revisión de reglas que el modo: la caché
   167	  // de TanStack no conoce la revisión y, al remontar, podría servir una página
   168	  // calculada con las reglas anteriores mientras refresca.
   169	  const revisionVigente = modo.data?.control_revision
   170	  const esVigente = (p: typeof pagina) => p != null && p.modo === 'activo' && p.control_revision === revisionVigente
   171	  const paginaVigente = esVigente(pagina) ? pagina : undefined
   172	  // Las decisiones del día miran a TODO el equipo y a una clave ESTABLE: los
   173	  // `totales` no dependen de la señal (cola_accion_v2_fn filtra por etapa y
   174	  // analista antes de contarlos), así que cambiar de pestaña no deja la
   175	  // banda sin su fuente mientras llega otra respuesta. Con «Para atender
   176	  // ahora» y sin analista, es la misma clave que la cola: TanStack la comparte.
   177	  const consultaEquipo = useColaSlaPagina({ senal: 'pendientes', etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
   178	  const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
   179	  const paginaEquipoVigente = esVigente(paginaEquipo) ? paginaEquipo : undefined
   180	
   181	  // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
   182	  // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
   183	  const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
   184	  // Nombres cortos sin ambigüedad para chips y la columna del analista.
   185	  const cortos = useMemo(
   186	    () => nombresCortos([
   187	      ...analistas.map((m) => m.nombre_completo),
   188	      ...(paginaVigente?.items ?? []).map((i) => i.lead.analista_nombre ?? ''),
   189	    ]),
   190	    [analistas, paginaVigente],
   191	  )
   192	  const corto = (nombre: string | null | undefined) => (nombre ? cortos.get(nombre.trim()) ?? primerNombre(nombre) : '')
   193	  const nombreAnalista = analistaId != null
   194	    ? ambito.vendedores.find((m) => m.perfil_id === analistaId)?.nombre_completo ?? null
   195	    : null
   196	
   197	  const elegirAnalista = (id: string | null) => {
   198	    const siguiente = id === analistaId ? null : id
   199	    setAnalistaId(siguiente)
   200	    const nombre = siguiente == null ? null : ambito.vendedores.find((m) => m.perfil_id === siguiente)?.nombre_completo
   201	    setAnuncio(nombre ? `Mostrando los pendientes de ${primerNombre(nombre)}` : 'Mostrando los pendientes de todo el equipo')
   202	  }
   203	  const elegirPestana = (id: PestanaMando) => {
   204	    setPestana(id)
   205	    setErrorApertura(false)
   206	    // La tarjeta de primera gestión ES esa pestaña: si se va de ella, se cierra.
   207	    if (id !== 'primera_atencion' && decisionAbierta === 'primera_gestion') setDecisionAbierta(null)
   208	  }
   209	
   210	  async function abrirFicha(id: string) {
   211	    if (abriendo) return
   212	    setAbriendo(id)
   213	    setErrorApertura(false)
   214	    try {
   215	      if (await abrirLead(id) === false) setErrorApertura(true)
   216	    } catch {
   217	      setErrorApertura(true)
   218	    } finally {
   219	      setAbriendo(null)
   220	    }
   221	  }
   222	
   223	  const conteoPestana = (id: PestanaMando): number | null => {
   224	    if (!paginaVigente) return null
   225	    if (id === 'todas') return pestana === 'todas' ? paginaVigente.total_items : null
   226	    return paginaVigente.totales[id]
   227	  }
   228	
   229	  // ── Equipo hoy: UNA lectura por analista alimenta punto, cabecera y chips ──
   230	  const rezagosConfirmados = useMemo(
   231	    () => new Map((datos.agendaConfirmada?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
   232	    [datos.agendaConfirmada],
   233	  )
   234	  const lecturas = useMemo(
   235	    () => new Map((rank ?? []).map((r) => [r.m.perfil_id, lecturaAnalista(r, rezagosConfirmados.get(r.m.perfil_id))] as const)),
   236	    [rank, rezagosConfirmados],
   237	  )
   238	  const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])
   239	
   240	  // ── 1 · Decide primero: las mismas reglas de la franja clásica ──
   241	  // Fail-closed por fuente: un candidato solo existe si su fuente llegó bien,
   242	  // y «Nada que decidir» solo se afirma con TODAS las fuentes confirmadas.
   243	  const primeraGestionPendiente = paginaEquipoVigente?.totales.primera_atencion ?? null
   244	  const entradaCosas = {
   245	    cola: null,
   246	    totalPorRepartir: datos.resumenOp.error ? null : datos.totalPorRepartir,
   247	    esperaMasLargaReparto: datos.esperaMasLargaReparto,
   248	    vendedoresAgenda: datos.agendaConfirmada?.vendedores ?? [],
   249	    primeraGestionPendiente,
   250	  }
   251	  const candidatos = candidatosDeHoy(entradaCosas)
   252	  const cosas = tresCosasDeHoy(entradaCosas)
   253	  const estaSemana = candidatos.slice(cosas.length)
   254	  const fuentesCaidas = [
   255	    consultaEquipo.error ? 'el seguimiento' : null,
   256	    datos.errorAgenda ? 'la agenda' : null,
   257	    datos.resumenOp.error ? 'el reparto' : null,
   258	  ].filter((f): f is string => f != null)
   259	  const fuentesListas = paginaEquipoVigente != null
   260	    && datos.agendaConfirmada != null
   261	    && datos.resumen != null
   262	  const reintentarDecisiones = () => {
   263	    if (consultaEquipo.error) void consultaEquipo.refetch()
   264	    if (datos.errorAgenda) datos.recargarAgenda()
   265	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   266	  }
   267	
   268	  const alternarDecision = (cosa: CosaDeHoy) => {
   269	    const abrir = decisionAbierta !== cosa.id
   270	    setDecisionAbierta(abrir ? cosa.id : null)
   271	    if (cosa.id !== 'primera_gestion') return
   272	    // Primera gestión: la cola de abajo pasa a ESA pestaña, para todo el equipo.
   273	    if (abrir) {
   274	      setPestana('primera_atencion')
   275	      setAnalistaId(null)
   276	      setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   277	    } else if (pestana === 'primera_atencion') {
   278	      setPestana('pendientes')
   279	      setAnuncio('Mostrando los pendientes de todo el equipo')
   280	    }
   281	  }
   282	  const verPrimeraGestion = () => {
   283	    setDecisionAbierta('primera_gestion')
   284	    setPestana('primera_atencion')
   285	    setAnalistaId(null)
   286	    setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   287	    requestAnimationFrame(() => document.getElementById(`${idPanelCola}-tab-primera_atencion`)?.focus())
   288	  }
   289	
   290	  /** Una línea de contexto con datos YA confirmados; sin dato, nada. */
   291	  const contextoDe = (cosa: CosaDeHoy): string | null => {
   292	    switch (cosa.id) {
   293	      case 'primera_gestion':
   294	        return 'Revisa la primera gestión con cada analista: abajo quedan solo esos casos.'
   295	      case 'no_asistio':
   296	      case 'sin_accion': {
   297	        if (cosa.vendedorId != null) {
   298	          const r = rezagosConfirmados.get(cosa.vendedorId)
   299	          if (!r) return null
   300	          const plural = (n: number, uno: string, varios: string) => `${numero(n)} ${n === 1 ? uno : varios}`
   301	          return `En 7 días: ${plural(r.no_asistio, 'cita sin asistir', 'citas sin asistir')} · ${plural(r.vencidas, 'tarea vencida', 'tareas vencidas')} · ${plural(r.leads_sin_accion, 'lead sin próxima acción', 'leads sin próxima acción')}.`
   302	        }
   303	        const nombres = (datos.agendaConfirmada?.vendedores ?? [])
   304	          .filter((v) => v.rol === 'vendedor' && v.activo
   305	            && (cosa.id === 'no_asistio' ? v.no_asistio >= 2 : v.leads_sin_accion >= 3))
   306	          .map((v) => `${primerNombre(v.nombre)} (${cosa.id === 'no_asistio' ? v.no_asistio : v.leads_sin_accion})`)
   307	        return nombres.length > 0 ? nombres.join(' · ') : null
   308	      }
   309	      case 'por_repartir':
   310	        return 'Leads sin analista en tu bandeja. El reparto se hace en Derivar leads.'
   311	      default:
   312	        return null
   313	    }
   314	  }
   315	
   316	  // Los errores del mes (meta, cumplimiento, conversión, TC) también se
   317	  // avisan aquí: la franja muestra «—» y el aviso no espera a abrir «Detalle».
   318	  const errorIndicadores = !datos.sesionReal
   319	    ? false
   320	    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error || datos.hayErrorMensual)
   321	  const reintentarIndicadores = () => {
   322	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   323	    if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
   324	    if (datos.hayErrorMensual) datos.reintentarMensual()
   325	  }
   326	
   327	  // ── 3 · Consulta: las cifras de siempre, en una línea; el detalle, encima ──
   328	  const agendaResumen = datos.agendaConfirmada ? resumenAgenda(datos.agendaConfirmada.vendedores) : null
   329	  const filaCapital = datos.filasMeta[0]
   330	  const metaTexto = filaCapital == null || filaCapital.sinDato ? '—' : `${Math.round(filaCapital.pct)} %`
   331	  const conversionTexto = datos.conversionMensualError || datos.conversionConfirmada == null
   332	    ? '—'
   333	    : porcentajeConversionCanonica(datos.conversionConfirmada)
   334	  const pronostico = datos.capitalPronostico
   335	  // En la franja, compacto (S/ 1.48 M); la cifra exacta vive en el KPI del detalle.
   336	  const pronosticoCorto = pronostico && datos.resumen
   337	    ? moneyCompacta(pronostico.soloDolares ? datos.resumen.capital.asignado.usd : datos.resumen.capital.asignado.pen, pronostico.moneda)
   338	    : '—'
   339	
   340	  const tituloCola = nombreAnalista ? `Pendientes de ${corto(nombreAnalista)}` : 'Pendientes del equipo'
   341	
   342	  return (
   343	    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
   344	      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>
   345	
   346	      {modo.activo && (
   347	        <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
   348	          <div className="flex items-center justify-between gap-4">
   349	            <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
   350	            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} etiquetaReparto={datos.etiquetaAccesoReparto} />}
   351	          </div>
   352	          <AvisoDegradacion activo={fuentesCaidas.length > 0} queReintenta="de las decisiones del día" onReintentar={reintentarDecisiones}>
   353	            Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
   354	          </AvisoDegradacion>
   355	          {/* Sin todas las fuentes no se ORDENA: una tarjeta ámbar no ocupa el
   356	              puesto de una roja que aún no llegó. Con una fuente caída sí se
   357	              muestra lo confirmado, bajo el aviso de que está incompleto. */}
   358	          {!fuentesListas && fuentesCaidas.length === 0 ? (
   359	            <Card>
   360	              <CardContent className="py-4">
   361	                <p role="status" className="text-sm text-muted-foreground">Revisando las decisiones del día…</p>
   362	              </CardContent>
   363	            </Card>
   364	          ) : cosas.length === 0 ? (
   365	            fuentesCaidas.length > 0 ? null : (
   366	              <Card>
   367	                <CardContent className="py-4">
   368	                  <p role="status" className="text-sm text-muted-foreground">Nada que decidir ahora mismo.</p>
   369	                </CardContent>
   370	              </Card>
   371	            )
   372	          ) : (
   373	            <div className="grid gap-3.5 lg:grid-cols-3">
   374	              {cosas.map((cosa) => (
   375	                <TarjetaDecision
   376	                  key={cosa.id}
   377	                  cosa={cosa}
   378	                  abierta={decisionAbierta === cosa.id}
   379	                  contexto={contextoDe(cosa)}
   380	                  idContexto={`${idPanelCola}-decision-${cosa.id}`}
   381	                  onAlternar={() => alternarDecision(cosa)}
   382	                  onVerPrimeraGestion={verPrimeraGestion}
   383	                  etiquetaReparto={datos.etiquetaAccesoReparto}
   384	                />
   385	              ))}
   386	            </div>
   387	          )}
   388	        </section>
   389	      )}
   390	
   391	      <AvisoDegradacion
   392	        activo={errorIndicadores}
   393	        queReintenta="de los indicadores del equipo"
   394	        onReintentar={reintentarIndicadores}
   395	      >
   396	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   397	      </AvisoDegradacion>
   398	
   399	      {/* ── 2 · Cola del seguimiento + Equipo hoy ── */}
   400	      <h2 className="sr-only">Pendientes y equipo</h2>
   401	      <div className="grid gap-4 lg:grid-cols-5">
   402	        <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
   403	          <SectionHead
   404	            icon={ListChecks}
   405	            title={tituloCola}
   406	            className="flex-wrap gap-y-2"
   407	            right={modo.activo ? (
   408	              <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
   409	                {PESTANAS.map((p, indice) => {
   410	                  const n = conteoPestana(p.id)
   411	                  return (
   412	                    <button
   413	                      key={p.id}
   414	                      id={`${idPanelCola}-tab-${p.id}`}
   415	                      type="button"
   416	                      role="tab"
   417	                      aria-selected={pestana === p.id}
   418	                      aria-controls={`${idPanelCola}-panel`}
   419	                      aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
   420	                      tabIndex={pestana === p.id ? 0 : -1}
   421	                      onClick={() => elegirPestana(p.id)}
   422	                      onKeyDown={(e) => {
   423	                        const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
   424	                          : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
   425	                          : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
   426	                        if (destino == null) return
   427	                        e.preventDefault()
   428	                        const siguiente = PESTANAS[destino]
   429	                        if (!siguiente) return
   430	                        elegirPestana(siguiente.id)
   431	                        document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
   432	                      }}
   433	                      className={cn(
   434	                        'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   435	                        pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
   436	                      )}
   437	                    >
   438	                      {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
   439	                    </button>
   440	                  )
   441	                })}
   442	              </div>
   443	            ) : undefined}
   444	          />
   445	          {!modo.activo ? (
   446	            <CardContent className="pb-5 pt-0">
   447	              <AvisoDegradacion activo={modo.error != null} queReintenta="del seguimiento" onReintentar={() => void modo.refetch()}>
   448	                No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.
   449	              </AvisoDegradacion>
   450	              {modo.error == null && (
   451	                <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
   452	              )}
   453	            </CardContent>
   454	          ) : (
   455	            <>
   456	              {analistas.length > 0 && (
   457	                <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
   458	                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
   459	                  <button
   460	                    type="button"
   461	                    aria-pressed={analistaId == null}
   462	                    onClick={() => elegirAnalista(null)}
   463	                    className={cn(
   464	                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   465	                      analistaId == null ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   466	                    )}
   467	                  >
   468	                    Todos
   469	                  </button>
   470	                  {analistas.map((m) => (
   471	                    <button
   472	                      key={m.perfil_id}
   473	                      type="button"
   474	                      aria-pressed={analistaId === m.perfil_id}
   475	                      aria-label={m.nombre_completo}
   476	                      onClick={() => elegirAnalista(m.perfil_id)}
   477	                      className={cn(
   478	                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   479	                        analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   480	                      )}
   481	                    >
   482	                      {corto(m.nombre_completo)}
   483	                    </button>
   484	                  ))}
   485	                </div>
   486	              )}
   487	
   488	              {abriendo && <p role="status" className="px-5 pb-2 text-xs text-muted-foreground">Abriendo ficha…</p>}
   489	              {errorApertura && <p role="alert" className="px-5 pb-2 text-xs text-destructive-text">No se pudo abrir la ficha. Vuelve a intentarlo.</p>}
   490	
   491	              <div
   492	                id={`${idPanelCola}-panel`}
   493	                role="tabpanel"
   494	                aria-labelledby={`${idPanelCola}-tab-${pestana}`}
   495	                tabIndex={paginaVigente && paginaVigente.items.length > 0 ? undefined : 0}
   496	                className="flex flex-1 flex-col"
   497	              >
   498	                <div className={cn(consultaCola.error && 'border-t border-border/60 px-5 py-4')}>
   499	                  <AvisoDegradacion activo={consultaCola.error != null} queReintenta="de los pendientes del equipo" onReintentar={() => void consultaCola.refetch()}>
   500	                    No se pudo cargar la cola. Los pendientes todavía no están confirmados.
   501	                  </AvisoDegradacion>
   502	                </div>
   503	                {consultaCola.error ? null : !pagina ? (
   504	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
   505	                ) : !paginaVigente ? (
   506	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   507	                    {pagina.modo !== 'activo'
   508	                      ? 'Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.'
   509	                      : 'Actualizando los pendientes con las reglas vigentes…'}
   510	                  </p>
   511	                ) : paginaVigente.items.length === 0 ? (
   512	                  <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   513	                    {nombreAnalista ? `${corto(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
   514	                  </p>
   515	                ) : (
   516	                  // oxlint-disable-next-line jsx-a11y/no-redundant-roles
   517	                  <ul role="list" aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
   518	                    {paginaVigente.items.map((item) => {
   519	                      const leadStore = leadPorId.get(item.lead_id)
   520	                      const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
   521	                      const analistaFila = item.lead.analista_nombre ? corto(item.lead.analista_nombre) : 'Sin analista'
   522	                      const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
   523	                      const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
   524	                      const urgente = item.severidad === 'critica'
   525	                      return (
   526	                        <li
   527	                          key={item.lead_id}
   528	                          data-sev={item.severidad}
   529	                          className="flex items-center gap-2 border-l-[3px] border-t border-t-border/60 pr-5"
   530	                          style={{ borderLeftColor: colorTira }}
   531	                        >
   532	                          <button
   533	                            type="button"
   534	                            // aria-disabled y NO disabled: un botón enfocado que se deshabilita
   535	                            // suelta el foco a <body> y la ficha lo devolvía ahí al cerrarse.
   536	                            // La guarda de abrirFicha ya evita el doble envío.
   537	                            aria-disabled={abriendo !== null || undefined}
   538	                            onClick={() => void abrirFicha(item.lead_id)}
   539	                            // El nombre dicta TODO lo visible (dueño, urgencia, estado,
   540	                            // tiempo, monto): un lector de pantalla no puede perder lo que se ve.
   541	                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}${urgente ? ', urgente' : ''}: ${estado}${monto ? `, ${monto}` : ''}`}
   542	                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 aria-disabled:cursor-wait"
   543	                          >
   544	                            {analistaId == null && (
   545	                              <span className="hidden w-[118px] shrink-0 items-center gap-2 sm:flex">
   546	                                <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
   547	                                <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
   548	                              </span>
   549	                            )}
   550	                            <span className="min-w-0 flex-1 leading-tight">
   551	                              <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
   552	                              <span className="flex min-w-0 items-center gap-1 text-xs text-muted-foreground-strong">
   553	                                {urgente && <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />}
   554	                                <span className="truncate">
   555	                                  {analistaId == null && <span className="sm:hidden">{analistaFila} · </span>}
   556	                                  {estado}
   557	                                </span>
   558	                              </span>
   559	                            </span>
   560	                            {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
   561	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   562	                          </button>
   563	                          {leadStore && (
   564	                            // Las acciones compactas miden 28 px: se llevan al mínimo de 36 (40 táctil), alto Y ancho.
   565	                            <div className="[&_a]:min-h-9 [&_a]:min-w-9 [&_button]:min-h-9 [&_button]:min-w-9 pointer-coarse:[&_a]:min-h-10 pointer-coarse:[&_a]:min-w-10 pointer-coarse:[&_button]:min-h-10 pointer-coarse:[&_button]:min-w-10">
   566	                              <AccionesContacto lead={leadStore} compacto />
   567	                            </div>
   568	                          )}
   569	                        </li>
   570	                      )
   571	                    })}
   572	                  </ul>
   573	                )}
   574	                <div className="mt-auto flex items-center justify-between gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
   575	                  <span className="tabular-nums text-muted-foreground-strong">
   576	                    {paginaVigente && paginaVigente.items.length > 0
   577	                      ? `${numero(paginaVigente.items.length)} de ${numero(paginaVigente.total_items)}`
   578	                      : ''}
   579	                  </span>
   580	                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   581	                    Ver todo en Seguimiento <ChevronRight className="size-3.5" aria-hidden />
   582	                  </a>
   583	                </div>
   584	              </div>
   585	            </>
   586	          )}
   587	        </Card>
   588	
   589	        {/* ── Equipo hoy: tocar a alguien filtra la cola y despliega sus señales ── */}
   590	        <Card className="min-w-0 overflow-hidden lg:col-span-2">
   591	          <SectionHead
   592	            icon={UsersRound}
   593	            title="Equipo hoy"
   594	            right={(
   595	              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-1 text-xs font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   596	                Mi equipo hoy <span aria-hidden>→</span>
   597	              </a>
   598	            )}
   599	          />
   600	          {rank != null && rank.length > 0 && (semaforoEquipo.rojo > 0 || semaforoEquipo.ambar > 0 || datos.agendaConfirmada != null) && (
   601	            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
   602	              {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
   603	                // Solo con la agenda confirmada: sin ella, cero señales es desconocido.
   604	                ? 'Sin alertas en el equipo'
   605	                : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
   606	            </p>
   607	          )}
   608	          <div className={cn(datos.errorAgenda && 'mx-5 mb-2')}>
   609	            <AvisoDegradacion activo={datos.errorAgenda != null} queReintenta="de la agenda del equipo" onReintentar={datos.recargarAgenda}>
   610	              La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.
   611	            </AvisoDegradacion>
   612	          </div>
   613	          {rank == null ? (
   614	            <CardContent className="pb-5 pt-0">
   615	              <p className="text-sm text-muted-foreground">
   616	                {datos.vendedoresOp.error
   617	                  ? 'El resumen por analista no está disponible en este momento.'
   618	                  : 'Cargando el resumen por analista…'}
   619	              </p>
   620	            </CardContent>
   621	          ) : rank.length === 0 ? (
   622	            <CardContent className="pb-5 pt-0">
   623	              <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   624	            </CardContent>
   625	          ) : (
   626	            // oxlint-disable-next-line jsx-a11y/no-redundant-roles
   627	            <ul role="list" aria-label="Analistas del equipo" className="border-t border-border/60">
   628	              {rank.map((r) => {
   629	                const id = r.m.perfil_id
   630	                const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
   631	                const rezago = rezagosConfirmados.get(id)
   632	                const abierto = analistaId === id
   633	                const principal = lectura.senales[0]?.texto
   634	                  ?? (r.activos === 0
   635	                    ? 'Sin leads abiertos'
   636	                    : rezago != null ? 'Al día' : `Última actividad ${haceTexto(r.diasSinActividadMax)}`)
   637	                const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   638	                const idDetalle = `${idPanelCola}-equipo-${id}`
   639	                // PEN y USD jamás se suman sin decirlo: el nombre lleva el desglose.
   640	                const desglose = r.capitalUSD > 0
   641	                  ? cap.tc != null
   642	                    ? ` (${moneyK(r.capitalPEN, 'PEN')} más ${moneyK(r.capitalUSD, 'USD')})`
   643	                    : `, más ${moneyK(r.capitalUSD, 'USD')} aparte sin tipo de cambio`
   644	                  : ''
   645	                const nivelTexto = lectura.nivel != null ? `${TEXTO_NIVEL[lectura.nivel]}. ` : ''
   646	                const conversion = r.conversion == null
   647	                  ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
   648	                  : `${textoConversionOperativa(r.conversion)} conversión`
   649	                return (
   650	                  <li key={id} className="border-b border-border/60 last:border-b-0">
   651	                    <button
   652	                      type="button"
   653	                      aria-expanded={abierto}
   654	                      aria-controls={idDetalle}
   655	                      aria-label={`${r.m.nombre_completo}: ${nivelTexto}${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}${desglose}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
   656	                      onClick={() => elegirAnalista(id)}
   657	                      className={cn(
   658	                        'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
   659	                        abierto && 'bg-accent/[0.08]',
   660	                      )}
   661	                    >
   662	                      <MarcaNivel nivel={lectura.nivel} />
   663	                      <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
   664	                      <span className="min-w-0 flex-1 leading-tight">
   665	                        <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
   666	                        <span className="block truncate text-xs text-muted-foreground-strong">{principal}</span>
   667	                      </span>
   668	                      <span className="shrink-0 text-right leading-tight">
   669	                        <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
   670	                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto tono="fuerte" />
   671	                      </span>
   672	                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierto ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
   673	                    </button>
   674	                    <div id={idDetalle} hidden={!abierto} className="space-y-1.5 px-5 pb-3 pl-[62px]">
   675	                      {lectura.senales.length > 1 && (
   676	                        <div className="flex flex-wrap gap-1.5">
   677	                          {lectura.senales.slice(1).map((s) => <ChipSenal key={s.texto} texto={s.texto} nivel={s.nivel} />)}
   678	                        </div>
   679	                      )}
   680	                      <p className="text-xs tabular-nums text-muted-foreground-strong">
   681	                        {numero(r.activos)} activos · {conversion}
   682	                        {r.operacionesCartera != null && r.operacionesCartera > 0 ? ` · ${numero(r.operacionesCartera)} de cartera` : ''}
   683	                        {r.sinTocar > 0 ? ` · ${numero(r.sinTocar)} sin tocar` : ''}
   684	                      </p>
   685	                      {rezago != null && (
   686	                        <p className="text-xs tabular-nums text-muted-foreground-strong">
   687	                          {rezago.toques > 0
   688	                            ? `${numero(rezago.toques)} toques en 7 días${rezago.pct_completadas != null ? ` · ${Math.round(rezago.pct_completadas)} % completadas` : ''}`
   689	                            : 'Sin toques registrados en 7 días'}
   690	                        </p>
   691	                      )}
   692	                    </div>
   693	                  </li>
   694	                )
   695	              })}
   696	            </ul>
   697	          )}
   698	        </Card>
   699	      </div>
   700	
   701	      {/* ── 3 · Consulta: cifras en una línea; «Detalle» abre todo lo demás ── */}
   702	      <section aria-label="Consulta" className="flex min-h-12 flex-wrap items-center gap-x-5 gap-y-1.5 rounded-xl border border-border bg-card px-5 py-2">
   703	        <span className="text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground-strong" aria-hidden>Consulta</span>
   704	        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
   705	        <ul role="list" aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
   706	          <li>
   707	            <a href={hashDe('pipeline')} className={CLASE_CIFRA}>
   708	              <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
   709	              {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
   710	            </a>
   711	          </li>
   712	          <li>
   713	            <a href={hashDe('cartera')} className={CLASE_CIFRA}>
   714	              <strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos
   715	            </a>
   716	          </li>
   717	          <li>
   718	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   719	              <strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta
   720	            </button>
   721	          </li>
   722	          <li>
   723	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   724	              <strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes
   725	            </button>
   726	          </li>
   727	          <li aria-hidden className="h-[18px] w-px bg-border" />
   728	          <li>
   729	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   730	              <strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días
   731	            </button>
   732	          </li>
   733	          <li>
   734	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   735	              <strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas
   736	            </button>
   737	          </li>
   738	          <li>
   739	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   740	              {agendaResumen && agendaResumen.noAsistio >= 2 && (
   741	                <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />
   742	              )}
   743	              <strong
   744	                className="font-extrabold"
   745	                style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
   746	              >
   747	                {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
   748	              </strong> {agendaResumen?.noAsistio === 1 ? 'cita sin asistir' : 'citas sin asistir'}
   749	            </button>
   750	          </li>
   751	        </ul>
   752	        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent pointer-coarse:min-h-10" onClick={abrirDetalle}>
   753	          Detalle
   754	        </Button>
   755	      </section>
   756	
   757	      <Dialog
   758	        open={detalleAbierto}
   759	        onClose={() => setDetalleAbierto(false)}
   760	        focoInicial={tituloDetalle}
   761	        focoAlCerrar={focoALaCola ? focoTrasDetalle : undefined}
   762	        className="w-[1180px] max-h-[88vh] max-w-[94vw]"
   763	      >
   764	        <DialogHeader>
   765	          {/* El foco entra por el título, no en mitad de la rejilla de indicadores. */}
   766	          <DialogTitle><span ref={tituloDetalle} tabIndex={-1} className="outline-none">Detalle del equipo</span></DialogTitle>
   767	          <DialogDescription>Indicadores, cumplimiento del mes y agenda de los últimos 7 días.</DialogDescription>
   768	        </DialogHeader>
   769	        <DialogBody className="space-y-4">
   770	          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   771	            {/* Pronóstico: `capitalPrincipal`, NUNCA un total mixto con los dólares. */}
   772	            <a href={hashDe('pipeline')} className={CLASE_KPI_ENLACE}>
   773	            <KpiCard
   774	              label="Pronóstico de capital abierto"
   775	              value={pronostico ? pronostico.valor : '—'}
   776	              icon={Wallet}
   777	              color={SEMAFORO.neutro}
   778	              sub={
   779	                pronostico?.otra
   780	                  ? `En soles · +${pronostico.otra} aparte`
   781	                  : pronostico?.soloDolares
   782	                    ? 'En dólares · abiertos con analista'
   783	                    : datos.resumen && datos.resumen.capital.asignado.pen === 0 && datos.resumen.totales.asignados > 0
   784	                      ? 'Sin montos estimados — complétalos en cada ficha'
   785	                      : 'En soles · abiertos con analista'
   786	              }
   787	            />
   788	            </a>
   789	            <a href={hashDe('cartera')} className={CLASE_KPI_ENLACE}>
   790	            <KpiCard
   791	              label="Leads activos del equipo"
   792	              value={datos.resumen ? String(datos.resumen.totales.asignados) : '—'}
   793	              icon={Users}
   794	              color={SEMAFORO.neutro}
   795	              sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
   796	              delay={60}
   797	            />
   798	            </a>
   799	            {/* Abre la cola en su pestaña: cierra el detalle y deja el foco en ella. */}
   800	            <button
   801	              type="button"
   802	              className={CLASE_KPI_ENLACE}
   803	              onClick={() => {
   804	                focoTrasDetalle.current = document.getElementById(`${idPanelCola}-tab-primera_atencion`)
   805	                setFocoALaCola(true)
   806	                setDetalleAbierto(false)
   807	                verPrimeraGestion()
   808	              }}
   809	            >
   810	              <KpiCard
   811	                label="Primeras gestiones vencidas"
   812	                value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
   813	                icon={AlertTriangle}
   814	                color={SEMAFORO.neutro}
   815	                sub={primeraGestionPendiente == null
   816	                  ? 'Sin dato por ahora'
   817	                  : primeraGestionPendiente > 0 ? 'Ver cuáles son →' : 'Ninguna vencida'}
   818	                delay={120}
   819	              />
   820	            </button>
   821	            <a
   822	              href={hashDe('derivaciones')}
   823	              aria-label={`Por repartir: ${datos.etiquetaAccesoReparto}`}
   824	              className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
   825	            >
   826	              <KpiCard
   827	                label="Por repartir"
   828	                value={datos.totalPorRepartir == null ? '—' : String(datos.totalPorRepartir)}
   829	                icon={Inbox}
   830	                color={SEMAFORO.neutro}
   831	                sub={datos.detalleReparto}
   832	                delay={180}
   833	              />
   834	            </a>
   835	          </div>
   836	
   837	          <div className="grid gap-4 lg:grid-cols-5">
   838	            <Card className="lg:col-span-2">
   839	              <SectionHead
   840	                icon={Target}
   841	                title="Cumplimiento del mes"
   842	                right={tc ? <span className="text-xs text-muted-foreground-strong">{rotuloTipoCambio(tc.promedio, tc.fuente)}</span> : undefined}
   843	              />
   844	              <CardContent className="space-y-4 pb-5 pt-0">
   845	                {datos.filasMeta.map((f) => (
   846	                  <div key={f.label}>
   847	                    <div className="mb-1.5 flex items-baseline justify-between gap-2">
   848	                      <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
   849	                      <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
   850	                    </div>
   851	                    {f.nota && <p className="mb-1 text-[11px] tabular-nums text-muted-foreground-strong">{f.nota}</p>}
   852	                    {f.sinDato
   853	                      ? <p className="text-[11px] text-muted-foreground-strong">{f.sinDato}</p>
   854	                      : <Progress value={f.pct} color={colorMeta(f.pct)} />}
   855	                  </div>
   856	                ))}
   857	                <p className="text-[11px] text-muted-foreground-strong">
   858	                  El capital en dólares entra al total convertido a tipo de cambio real. El pronóstico no cuenta como cumplimiento.
   859	                </p>
   860	                <AvisoDegradacion activo={datos.hayErrorMensual} queReintenta="de la meta y el cumplimiento del mes" onReintentar={datos.reintentarMensual}>
   861	                  Parte del cumplimiento del mes no se pudo cargar: se muestra «—» donde falta el dato.
   862	                </AvisoDegradacion>
   863	              </CardContent>
   864	            </Card>
   865	            <div className="min-w-0 lg:col-span-3">
   866	              <AgendaEquipoPanel
   867	                datos={datos.datosAgenda}
   868	                cargando={datos.cargandoAgenda}
   869	                error={datos.errorAgenda}
   870	                modoDemo={yo?.demo === true}
   871	                onReintentar={datos.recargarAgenda}
   872	                equipo={datos.equipo}
   873	              />
   874	            </div>
   875	          </div>
   876	
   877	          {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC). */}
   878	          <DesglosePorEmpresa demo={yo?.demo === true} porVendedor={datos.cumplimientoMensual?.porVendedor ?? null} />
   879	          {/* Rentabilidad R3: las solicitudes de tasa propias en curso (solo si hay). */}
   880	          <TasasAutorizadasAnalistaPanel />
   881	          <p className="text-[11px] text-muted-foreground-strong">
   882	            Ves solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
   883	          </p>
   884	        </DialogBody>
   885	        <DialogFooter>
   886	          <Button variant="outline" size="sm" className="min-h-9 pointer-coarse:min-h-10" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
   887	        </DialogFooter>
   888	      </Dialog>
   889	    </div>
   890	  )
   891	}
   892	
   893	/** El botón de acción de una decisión. Nunca va DENTRO del botón que la despliega. */
   894	function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
   895	  cosa: CosaDeHoy
   896	  onVerPrimeraGestion: () => void
   897	  etiquetaReparto: string
   898	}): JSX.Element {
   899	  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
   900	  if (cosa.id === 'primera_gestion') {
   901	    return (
   902	      <button type="button" className={clase} aria-label={`Ver en la cola: ${cosa.texto}`} onClick={onVerPrimeraGestion}>
   903	        Ver <ChevronRight className="size-3.5" aria-hidden />
   904	      </button>
   905	    )
   906	  }
   907	  if (cosa.id === 'por_repartir') {
   908	    return (
   909	      <a href={hashDe('derivaciones')} className={clase} aria-label={etiquetaReparto}>
   910	        Repartir <ChevronRight className="size-3.5" aria-hidden />
   911	      </a>
   912	    )
   913	  }
   914	  if (cosa.id === 'no_asistio' || cosa.id === 'sin_accion') {
   915	    // La cola no contiene citas ni leads «sin próxima acción»: filtrarla
   916	    // enseñaría OTROS casos. La decisión se toma viendo el día del equipo.
   917	    const label = cosa.vendedorId != null ? 'Ver su día' : 'Ver el equipo'
   918	    return (
   919	      <a href={hashDe('gestion-diaria')} className={clase} aria-label={`${label}: ${cosa.texto}`}>
   920	        {label} <ChevronRight className="size-3.5" aria-hidden />
   921	      </a>
   922	    )
   923	  }
   924	  // Candidatos del modo legado: aquí no aparecen (la cola legada llega null),
   925	  // pero si algún día lo hicieran, su lugar es el módulo de seguimiento.
   926	  return (
   927	    <a href={hashDe('seguimiento')} className={clase} aria-label={`${cosa.accion}: ${cosa.texto}`}>
   928	      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
   929	    </a>
   930	  )
   931	}
   932	
   933	function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVerPrimeraGestion, etiquetaReparto }: {
   934	  cosa: CosaDeHoy
   935	  abierta: boolean
   936	  contexto: string | null
   937	  idContexto: string
   938	  onAlternar: () => void
   939	  onVerPrimeraGestion: () => void
   940	  etiquetaReparto: string
   941	}): JSX.Element {
   942	  const { cifra, resto } = partesDeCosa(cosa.texto)
   943	  return (
   944	    <Card
   945	      data-decision={cosa.id}
   946	      className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')}
   947	      style={{ borderLeftColor: SEV_BORDE[cosa.severidad] }}
   948	    >
   949	      <div className="flex flex-wrap items-center gap-2 py-2 pl-4 pr-3">
   950	        <button
   951	          type="button"
   952	          aria-expanded={abierta}
   953	          aria-controls={idContexto}
   954	          aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto}`}
   955	          onClick={onAlternar}
   956	          className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 rounded-md text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
   957	        >
   958	          {cifra && (
   959	            <span className="min-w-10 text-[32px] font-extrabold leading-none tracking-tight tabular-nums text-primary">{cifra}</span>
   960	          )}
   961	          <span className="min-w-0 flex-1 leading-tight">
   962	            <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: SEV_TEXTO_COLOR[cosa.severidad] }}>
   963	              {SEV_TEXTO[cosa.severidad]}
   964	            </span>
   965	            <span className="line-clamp-2 break-words text-[15px] font-bold">{resto}</span>
   966	          </span>
   967	          <ChevronRight
   968	            className={cn('size-4 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')}
   969	            aria-hidden
   970	          />
   971	        </button>
   972	        <AccionDecision cosa={cosa} onVerPrimeraGestion={onVerPrimeraGestion} etiquetaReparto={etiquetaReparto} />
   973	      </div>
   974	      <p id={idContexto} hidden={!abierta} className="border-t border-border/60 px-4 py-2.5 text-xs text-muted-foreground-strong">
   975	        {contexto ?? 'Sin más detalle confirmado por ahora.'}
   976	      </p>
   977	    </Card>
   978	  )
   979	}
   980	
   981	/** «Esta semana · N»: lo que no entró en las tres tarjetas. Esc y clic fuera lo cierran. */
   982	function EstaSemana({ cosas, onVerPrimeraGestion, etiquetaReparto }: {
   983	  cosas: CosaDeHoy[]
   984	  onVerPrimeraGestion: () => void
   985	  etiquetaReparto: string
   986	}): JSX.Element {
   987	  const [abierto, setAbierto] = useState(false)
   988	  const contenedor = useRef<HTMLDivElement>(null)
   989	  const disparador = useRef<HTMLButtonElement>(null)
   990	  const idLista = useId()
   991	  useEffect(() => {
   992	    if (!abierto) return
   993	    const fuera = (e: PointerEvent) => {
   994	      if (!contenedor.current?.contains(e.target as Node)) setAbierto(false)
   995	    }
   996	    // Esc cierra y devuelve el foco al disparador, esté donde esté el foco
   997	    // dentro de la lista (y también si quedó fuera: el popover no atrapa).
   998	    const escape = (e: KeyboardEvent) => {
   999	      if (e.key !== 'Escape') return
  1000	      setAbierto(false)
  1001	      if (contenedor.current?.contains(document.activeElement)) disparador.current?.focus()
  1002	    }
  1003	    // Tabular fuera del popover lo cierra: si no, quedaría encima de las
  1004	    // tarjetas que reciben el foco a continuación (WCAG 2.4.11).
  1005	    const nodo = contenedor.current
  1006	    const salida = (e: FocusEvent) => {
  1007	      if (e.relatedTarget instanceof Node && !nodo?.contains(e.relatedTarget)) setAbierto(false)
  1008	    }
  1009	    document.addEventListener('pointerdown', fuera)
  1010	    document.addEventListener('keydown', escape)
  1011	    nodo?.addEventListener('focusout', salida)
  1012	    return () => {
  1013	      document.removeEventListener('pointerdown', fuera)
  1014	      document.removeEventListener('keydown', escape)
  1015	      nodo?.removeEventListener('focusout', salida)
  1016	    }
  1017	  }, [abierto])
  1018	  return (
  1019	    <div ref={contenedor} className="relative">
  1020	      <button
  1021	        ref={disparador}
  1022	        type="button"
  1023	        aria-expanded={abierto}
  1024	        aria-controls={idLista}
  1025	        onClick={() => setAbierto((v) => !v)}
  1026	        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
  1027	      >
  1028	        <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
  1029	        Esta semana · {cosas.length}
  1030	        <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
  1031	      </button>
  1032	      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
  1033	      <ul role="list"
  1034	        id={idLista}
  1035	        hidden={!abierto}
  1036	        aria-label="Decisiones para esta semana"
  1037	        className="ac-pop absolute right-0 top-11 z-20 w-[340px] max-w-[90vw] rounded-xl border border-border bg-card p-2 shadow-[var(--shadow-pop)]"
  1038	      >
  1039	        {cosas.map((c) => (
  1040	          <li key={c.id} className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-xs font-semibold">
  1041	            <span className="size-2 shrink-0 rounded-full" style={{ background: SEV_BORDE[c.severidad] }} aria-hidden />
  1042	            <span className="min-w-0 flex-1">
  1043	              <span className="sr-only">{SEV_TEXTO[c.severidad]}: </span>{c.texto}
  1044	            </span>
  1045	            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={etiquetaReparto} />
  1046	          </li>
  1047	        ))}
  1048	      </ul>
  1049	    </div>
  1050	  )
  1051	}
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
