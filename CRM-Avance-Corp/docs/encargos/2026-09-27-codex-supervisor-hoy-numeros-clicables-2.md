ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia, TEST GAPS, REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE.
Sin hallazgo sin evidencia. Omite secciones vacías.

# Encargo: CONFIRMAR el cierre de tu revisión de «todo número se abre» (commit 1f5918bb) — LEVEL 2

Tu revisión anterior (CHANGES_REQUESTED: 1 P1 + 2 P2) se atendió así (diff abajo):
- P1: cabecera «N en rojo · N en ámbar» → botones que filtran la lista del equipo (aria-pressed,
  «Ver todos»); contador de la cola dentro del enlace («Ver los N en Seguimiento»); hechos del
  analista → enlace a Gestión diaria («Ver su día») y toques → abre el Detalle (agenda); capital
  confirmado → #/facturacion (Facturación = el mes día a día por analista; supervisor tiene
  `verFacturacion`). EXCEPCIÓN declarada: la conversión del mes no se abre porque la única lista
  (vista Conversiones) es exclusiva de gerencia; se le informará al dueño.
- P2 HTML inválido: patrón de botón ESTIRADO (`absolute inset-0`) hermano de `KpiCard` dentro de un
  `div.relative`, en el mando y en la pantalla clásica.
- P2 foco: la acción solo existe con `modo.activo` y `primeraGestionPendiente != null`; el foco solo
  se desvía (`focoAlCerrar`) si la pestaña existe.
Verificación: `tsc -b` + `oxlint` PASS; vitest `src/screens/hoy/` 441/441 PASS.

¿Quedan cerrados? ¿Algún número visible que aún no se abra, además de la excepción declarada?
No repitas lo ya cerrado.

## DIFF del commit 1f5918bb
```diff
commit 1f5918bbd4ff4361ab838feb886fe7a8c8e0f515
Author: Miguel Briceño <avancecorp26@gmail.com>
Date:   Sun Sep 27 14:38:01 2026 -0500

    CRM: Hoy del supervisor — el resto de los números se abre + arreglos de Codex
    
    - «N en rojo · N en ámbar» filtra la lista del equipo a esos analistas.
    - El conteo de la cola va dentro del enlace: «Ver los N en Seguimiento».
    - Hechos del analista → su día (Gestión diaria); toques → agenda del equipo.
    - Capital confirmado → Facturación (el mes día a día, por analista).
    - KPI con acción en la página: botón estirado encima de la tarjeta (HTML
      válido: nada de <div> dentro de <button>), también en la pantalla clásica.
    - Sin cola visible (modo no activo) la tarjeta no tiene acción y el foco
      solo se desvía si la pestaña existe.
    La conversión del mes queda sin lista: la vista Conversiones es de gerencia.
    
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
index e0769287..288ef4c2 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
@@ -245,7 +245,8 @@ describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', ()
     // «Todas» no tiene total en `totales`: sin número hasta que se abre.
     expect(within(pestanas).getByRole('tab', { name: 'Todas' })).toBeInTheDocument()
     expect(screen.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
-    expect(screen.getByText('3 de 3')).toBeInTheDocument()
+    // Con todo a la vista, el enlace no promete más filas de las que hay.
+    expect(screen.getByRole('link', { name: 'Ver todo en Seguimiento' })).toBeInTheDocument()
   })
 
   it('cada fila dice de quién es, en qué estado está y desde cuándo, con la severidad en la tira', () => {
@@ -396,7 +397,8 @@ describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
       { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' },
     ])
     montar()
-    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
+    expect(screen.getByRole('button', { name: '1 en rojo' })).toBeInTheDocument()
+    expect(screen.getByRole('button', { name: '0 en ámbar' })).toBeDisabled()
     const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
     const karen = within(equipo).getByRole('button', { name: /KAREN ZAPATA/ })
     expect(karen).toHaveTextContent('2 citas sin asistir')
@@ -421,7 +423,7 @@ describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
     const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
     expect(within(equipo).getByRole('button', { name: /JORGE HUAMÁN/ })).toHaveTextContent('Al día')
     // Karen no tiene actividad desde el 20/09: 6 días, rojo. Jorge no cuenta.
-    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
+    expect(screen.getByRole('button', { name: '1 en rojo' })).toBeInTheDocument()
   })
 
   it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día» ni «Sin alertas»', () => {
@@ -750,3 +752,51 @@ describe('Hoy · supervisor — puesto de mando: todo número se abre (Miguel, 2
     await waitFor(() => expect(pestana).toHaveFocus())
   })
 })
+
+describe('Hoy · supervisor — puesto de mando: todo número se abre, segunda tanda (Codex)', () => {
+  it('«N en rojo» deja en la lista solo a esos analistas; «Ver todos» los devuelve', () => {
+    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
+    montar()
+    const equipo = () => screen.getByRole('list', { name: 'Analistas del equipo' })
+    // El roster trae también al ex analista (sin cartera): 3 filas.
+    const todas = within(equipo()).getAllByRole('listitem').length
+    fireEvent.click(screen.getByRole('button', { name: '1 en rojo' }))
+    expect(screen.getByRole('button', { name: '1 en rojo' })).toHaveAttribute('aria-pressed', 'true')
+    expect(within(equipo()).getAllByRole('listitem')).toHaveLength(1)
+    expect(equipo()).toHaveTextContent('KAREN ZAPATA')
+    fireEvent.click(screen.getByRole('button', { name: 'Ver todos' }))
+    expect(within(equipo()).getAllByRole('listitem')).toHaveLength(todas)
+  })
+
+  it('con más casos que filas, el enlace dice cuántos hay y lleva a Seguimiento', () => {
+    RESPONDER = (filtros) => ({ data: pagina(colaTodo(), { filtros: { ...filtros }, total_items: 12, totales: { pendientes: 12 } }), error: null, isFetching: false })
+    montar()
+    expect(screen.getByRole('link', { name: 'Ver los 12 en Seguimiento' })).toHaveAttribute('href', '#/seguimiento')
+  })
+
+  it('los hechos del analista llevan a su día y a la agenda del equipo', () => {
+    METRICAS_AGENDA = agenda([{ vendedor_id: KAREN, nombre: 'KAREN ZAPATA', toques: 9, pct_completadas: 50 }])
+    vi.useRealTimers()
+    montar()
+    fireEvent.click(within(screen.getByRole('list', { name: 'Analistas del equipo' })).getByRole('button', { name: /KAREN ZAPATA/ }))
+    expect(screen.getByRole('link', { name: /activos .* Ver su día/ })).toHaveAttribute('href', '#/gestion-diaria')
+    fireEvent.click(screen.getByRole('button', { name: /9 toques en 7 días .* Ver agenda/ }))
+    expect(screen.getByRole('dialog', { name: 'Detalle del equipo' })).toBeInTheDocument()
+  })
+
+  it('el capital confirmado del detalle se abre en Facturación', () => {
+    vi.useRealTimers()
+    montar()
+    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
+    expect(within(screen.getByRole('dialog')).getByRole('link', { name: /→$/ })).toHaveAttribute('href', '#/facturacion')
+  })
+
+  it('sin el modo activo la tarjeta «Primeras gestiones vencidas» no tiene acción (no hay cola a la que ir)', () => {
+    vi.useRealTimers()
+    MODO.activo = false
+    MODO.data = undefined
+    montar()
+    fireEvent.click(screen.getByRole('button', { name: 'Detalle' }))
+    expect(within(screen.getByRole('dialog')).queryByRole('button', { name: /Primeras gestiones vencidas/ })).not.toBeInTheDocument()
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
index d221de80..563c0dd6 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
@@ -153,6 +153,8 @@ function PuestoDeMando(): JSX.Element {
   // vuelve al botón «Detalle», que es lo que Radix haría por defecto).
   const focoTrasDetalle = useRef<HTMLElement | null>(null)
   const [focoALaCola, setFocoALaCola] = useState(false)
+  // «1 en rojo · 3 en ámbar» se abre: deja en la lista solo a esos analistas.
+  const [nivelEquipo, setNivelEquipo] = useState<'critico' | 'atencion' | null>(null)
   const abrirDetalle = () => {
     setFocoALaCola(false)
     setDetalleAbierto(true)
@@ -571,14 +573,13 @@ function PuestoDeMando(): JSX.Element {
                     })}
                   </ul>
                 )}
-                <div className="mt-auto flex items-center justify-between gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
-                  <span className="tabular-nums text-muted-foreground-strong">
-                    {paginaVigente && paginaVigente.items.length > 0
-                      ? `${numero(paginaVigente.items.length)} de ${numero(paginaVigente.total_items)}`
-                      : ''}
-                  </span>
-                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
-                    Ver todo en Seguimiento <ChevronRight className="size-3.5" aria-hidden />
+                <div className="mt-auto flex items-center justify-end gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
+                  {/* El conteo va DENTRO del enlace: el número abre su lista. */}
+                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold tabular-nums text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
+                    {paginaVigente && paginaVigente.total_items > paginaVigente.items.length
+                      ? `Ver los ${numero(paginaVigente.total_items)} en Seguimiento`
+                      : 'Ver todo en Seguimiento'}
+                    <ChevronRight className="size-3.5" aria-hidden />
                   </a>
                 </div>
               </div>
@@ -598,12 +599,32 @@ function PuestoDeMando(): JSX.Element {
             )}
           />
           {rank != null && rank.length > 0 && (semaforoEquipo.rojo > 0 || semaforoEquipo.ambar > 0 || datos.agendaConfirmada != null) && (
-            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
+            <div className="-mt-2 flex flex-wrap items-center gap-1 px-5 pb-2 text-xs text-muted-foreground-strong">
               {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
                 // Solo con la agenda confirmada: sin ella, cero señales es desconocido.
-                ? 'Sin alertas en el equipo'
-                : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
-            </p>
+                ? <p>Sin alertas en el equipo</p>
+                : (
+                  <div role="group" aria-label="Ver analistas por nivel" className="flex flex-wrap items-center gap-1">
+                    {([['critico', semaforoEquipo.rojo, 'en rojo'], ['atencion', semaforoEquipo.ambar, 'en ámbar']] as const).map(([nivel, n, texto], i) => (
+                      <span key={nivel} className="inline-flex items-center gap-1">
+                        {i > 0 && <span aria-hidden>·</span>}
+                        <button
+                          type="button"
+                          aria-pressed={nivelEquipo === nivel}
+                          disabled={n === 0}
+                          onClick={() => setNivelEquipo((actual) => (actual === nivel ? null : nivel))}
+                          className={cn(CLASE_CIFRA, 'disabled:cursor-default disabled:no-underline', nivelEquipo === nivel && 'font-bold text-foreground underline')}
+                        >
+                          {numero(n)} {texto}
+                        </button>
+                      </span>
+                    ))}
+                    {nivelEquipo != null && (
+                      <button type="button" className={cn(CLASE_CIFRA, 'ml-1 text-accent')} onClick={() => setNivelEquipo(null)}>Ver todos</button>
+                    )}
+                  </div>
+                )}
+            </div>
           )}
           <div className={cn(datos.errorAgenda && 'mx-5 mb-2')}>
             <AvisoDegradacion activo={datos.errorAgenda != null} queReintenta="de la agenda del equipo" onReintentar={datos.recargarAgenda}>
@@ -625,7 +646,7 @@ function PuestoDeMando(): JSX.Element {
           ) : (
             // oxlint-disable-next-line jsx-a11y/no-redundant-roles
             <ul role="list" aria-label="Analistas del equipo" className="border-t border-border/60">
-              {rank.map((r) => {
+              {rank.filter((r) => nivelEquipo == null || lecturas.get(r.m.perfil_id)?.nivel === nivelEquipo).map((r) => {
                 const id = r.m.perfil_id
                 const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
                 const rezago = rezagosConfirmados.get(id)
@@ -677,17 +698,19 @@ function PuestoDeMando(): JSX.Element {
                           {lectura.senales.slice(1).map((s) => <ChipSenal key={s.texto} texto={s.texto} nivel={s.nivel} />)}
                         </div>
                       )}
-                      <p className="text-xs tabular-nums text-muted-foreground-strong">
+                      <a href={hashDe('gestion-diaria')} className={cn(CLASE_CIFRA, 'text-xs tabular-nums text-muted-foreground-strong')}>
                         {numero(r.activos)} activos · {conversion}
                         {r.operacionesCartera != null && r.operacionesCartera > 0 ? ` · ${numero(r.operacionesCartera)} de cartera` : ''}
                         {r.sinTocar > 0 ? ` · ${numero(r.sinTocar)} sin tocar` : ''}
-                      </p>
+                        <span className="font-semibold text-accent"> · Ver su día →</span>
+                      </a>
                       {rezago != null && (
-                        <p className="text-xs tabular-nums text-muted-foreground-strong">
+                        <button type="button" onClick={abrirDetalle} className={cn(CLASE_CIFRA, 'block text-xs tabular-nums text-muted-foreground-strong')}>
                           {rezago.toques > 0
                             ? `${numero(rezago.toques)} toques en 7 días${rezago.pct_completadas != null ? ` · ${Math.round(rezago.pct_completadas)} % completadas` : ''}`
                             : 'Sin toques registrados en 7 días'}
-                        </p>
+                          <span className="font-semibold text-accent"> · Ver agenda</span>
+                        </button>
                       )}
                     </div>
                   </li>
@@ -796,17 +819,10 @@ function PuestoDeMando(): JSX.Element {
               delay={60}
             />
             </a>
-            {/* Abre la cola en su pestaña: cierra el detalle y deja el foco en ella. */}
-            <button
-              type="button"
-              className={CLASE_KPI_ENLACE}
-              onClick={() => {
-                focoTrasDetalle.current = document.getElementById(`${idPanelCola}-tab-primera_atencion`)
-                setFocoALaCola(true)
-                setDetalleAbierto(false)
-                verPrimeraGestion()
-              }}
-            >
+            {/* Abre la cola en su pestaña: cierra el detalle y deja el foco en ella.
+                Botón ESTIRADO encima de la tarjeta (un <button> no puede
+                contener los <div> de KpiCard). Sin cola visible, no hay acción. */}
+            <div className="relative h-full">
               <KpiCard
                 label="Primeras gestiones vencidas"
                 value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
@@ -817,7 +833,23 @@ function PuestoDeMando(): JSX.Element {
                   : primeraGestionPendiente > 0 ? 'Ver cuáles son →' : 'Ninguna vencida'}
                 delay={120}
               />
-            </button>
+              {modo.activo && primeraGestionPendiente != null && (
+                <button
+                  type="button"
+                  aria-label={`Primeras gestiones vencidas: ${numero(primeraGestionPendiente)}. Verlas en la cola`}
+                  className={cn(CLASE_KPI_ENLACE, 'absolute inset-0')}
+                  onClick={() => {
+                    const destino = document.getElementById(`${idPanelCola}-tab-primera_atencion`)
+                    // Solo se desvía el foco si la pestaña existe; si no, Radix lo
+                    // devuelve a «Detalle» como siempre.
+                    focoTrasDetalle.current = destino
+                    setFocoALaCola(destino != null)
+                    setDetalleAbierto(false)
+                    verPrimeraGestion()
+                  }}
+                />
+              )}
+            </div>
             <a
               href={hashDe('derivaciones')}
               aria-label={`Por repartir: ${datos.etiquetaAccesoReparto}`}
@@ -846,7 +878,10 @@ function PuestoDeMando(): JSX.Element {
                   <div key={f.label}>
                     <div className="mb-1.5 flex items-baseline justify-between gap-2">
                       <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
-                      <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
+                      {f.label === 'Capital confirmado'
+                        // El capital confirmado se abre en Facturación: el mes día a día, por analista.
+                        ? <a href={hashDe('facturacion')} className={cn(CLASE_CIFRA, 'text-xs font-bold tabular-nums text-primary')}>{f.txt} →</a>
+                        : <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>}
                     </div>
                     {f.nota && <p className="mb-1 text-[11px] tabular-nums text-muted-foreground-strong">{f.nota}</p>}
                     {f.sinDato
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
index b729018a..c566ea2b 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
@@ -283,13 +283,7 @@ export function HoySupervisor(): JSX.Element {
         {/* Sin payload, los subs NO afirman estados positivos («todos
             contactados», «bandeja vacía»): sin dato no hay afirmación.
             Abre la pestaña Urgente de la cola, donde van esos leads. */}
-        <button
-          type="button"
-          aria-label={cola ? `Nuevos sin responder: ${cola.porBucket.sin_responder ?? 0}. Ver en la cola urgente` : 'Nuevos sin responder: sin dato'}
-          onClick={() => irAPestanaCola('urgente')}
-          disabled={cola == null}
-          className="relative block h-full w-full cursor-pointer rounded-xl text-left text-inherit outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-default"
-        >
+        <div className="relative h-full">
         <KpiCard
           label="Nuevos sin responder"
           value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
@@ -304,7 +298,16 @@ export function HoySupervisor(): JSX.Element {
           }
           delay={120}
         />
-        </button>
+        {/* Botón ESTIRADO encima (un <button> no puede contener los <div> de KpiCard). */}
+        {cola != null && (
+          <button
+            type="button"
+            aria-label={`Nuevos sin responder: ${cola.porBucket.sin_responder ?? 0}. Ver en la cola urgente`}
+            onClick={() => irAPestanaCola('urgente')}
+            className="absolute inset-0 cursor-pointer rounded-xl outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
+          />
+        )}
+        </div>
         <a
           href={hashDe('derivaciones')}
           aria-label={etiquetaAccesoReparto}
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
   156	  // «1 en rojo · 3 en ámbar» se abre: deja en la lista solo a esos analistas.
   157	  const [nivelEquipo, setNivelEquipo] = useState<'critico' | 'atencion' | null>(null)
   158	  const abrirDetalle = () => {
   159	    setFocoALaCola(false)
   160	    setDetalleAbierto(true)
   161	  }
   162	
   163	  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
   164	  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
   165	  // Fail-closed: TanStack conserva la última respuesta tras un refetch
   166	  // fallido; con error, la cola NO se muestra como vigente.
   167	  const pagina = consultaCola.error ? undefined : consultaCola.data
   168	  // Vigente = modo activo Y la MISMA revisión de reglas que el modo: la caché
   169	  // de TanStack no conoce la revisión y, al remontar, podría servir una página
   170	  // calculada con las reglas anteriores mientras refresca.
   171	  const revisionVigente = modo.data?.control_revision
   172	  const esVigente = (p: typeof pagina) => p != null && p.modo === 'activo' && p.control_revision === revisionVigente
   173	  const paginaVigente = esVigente(pagina) ? pagina : undefined
   174	  // Las decisiones del día miran a TODO el equipo y a una clave ESTABLE: los
   175	  // `totales` no dependen de la señal (cola_accion_v2_fn filtra por etapa y
   176	  // analista antes de contarlos), así que cambiar de pestaña no deja la
   177	  // banda sin su fuente mientras llega otra respuesta. Con «Para atender
   178	  // ahora» y sin analista, es la misma clave que la cola: TanStack la comparte.
   179	  const consultaEquipo = useColaSlaPagina({ senal: 'pendientes', etapa: null, analista_id: null }, null, COLA_VISIBLES, modo.activo)
   180	  const paginaEquipo = consultaEquipo.error ? undefined : consultaEquipo.data
   181	  const paginaEquipoVigente = esVigente(paginaEquipo) ? paginaEquipo : undefined
   182	
   183	  // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
   184	  // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
   185	  const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
   186	  // Nombres cortos sin ambigüedad para chips y la columna del analista.
   187	  const cortos = useMemo(
   188	    () => nombresCortos([
   189	      ...analistas.map((m) => m.nombre_completo),
   190	      ...(paginaVigente?.items ?? []).map((i) => i.lead.analista_nombre ?? ''),
   191	    ]),
   192	    [analistas, paginaVigente],
   193	  )
   194	  const corto = (nombre: string | null | undefined) => (nombre ? cortos.get(nombre.trim()) ?? primerNombre(nombre) : '')
   195	  const nombreAnalista = analistaId != null
   196	    ? ambito.vendedores.find((m) => m.perfil_id === analistaId)?.nombre_completo ?? null
   197	    : null
   198	
   199	  const elegirAnalista = (id: string | null) => {
   200	    const siguiente = id === analistaId ? null : id
   201	    setAnalistaId(siguiente)
   202	    const nombre = siguiente == null ? null : ambito.vendedores.find((m) => m.perfil_id === siguiente)?.nombre_completo
   203	    setAnuncio(nombre ? `Mostrando los pendientes de ${primerNombre(nombre)}` : 'Mostrando los pendientes de todo el equipo')
   204	  }
   205	  const elegirPestana = (id: PestanaMando) => {
   206	    setPestana(id)
   207	    setErrorApertura(false)
   208	    // La tarjeta de primera gestión ES esa pestaña: si se va de ella, se cierra.
   209	    if (id !== 'primera_atencion' && decisionAbierta === 'primera_gestion') setDecisionAbierta(null)
   210	  }
   211	
   212	  async function abrirFicha(id: string) {
   213	    if (abriendo) return
   214	    setAbriendo(id)
   215	    setErrorApertura(false)
   216	    try {
   217	      if (await abrirLead(id) === false) setErrorApertura(true)
   218	    } catch {
   219	      setErrorApertura(true)
   220	    } finally {
   221	      setAbriendo(null)
   222	    }
   223	  }
   224	
   225	  const conteoPestana = (id: PestanaMando): number | null => {
   226	    if (!paginaVigente) return null
   227	    if (id === 'todas') return pestana === 'todas' ? paginaVigente.total_items : null
   228	    return paginaVigente.totales[id]
   229	  }
   230	
   231	  // ── Equipo hoy: UNA lectura por analista alimenta punto, cabecera y chips ──
   232	  const rezagosConfirmados = useMemo(
   233	    () => new Map((datos.agendaConfirmada?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
   234	    [datos.agendaConfirmada],
   235	  )
   236	  const lecturas = useMemo(
   237	    () => new Map((rank ?? []).map((r) => [r.m.perfil_id, lecturaAnalista(r, rezagosConfirmados.get(r.m.perfil_id))] as const)),
   238	    [rank, rezagosConfirmados],
   239	  )
   240	  const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])
   241	
   242	  // ── 1 · Decide primero: las mismas reglas de la franja clásica ──
   243	  // Fail-closed por fuente: un candidato solo existe si su fuente llegó bien,
   244	  // y «Nada que decidir» solo se afirma con TODAS las fuentes confirmadas.
   245	  const primeraGestionPendiente = paginaEquipoVigente?.totales.primera_atencion ?? null
   246	  const entradaCosas = {
   247	    cola: null,
   248	    totalPorRepartir: datos.resumenOp.error ? null : datos.totalPorRepartir,
   249	    esperaMasLargaReparto: datos.esperaMasLargaReparto,
   250	    vendedoresAgenda: datos.agendaConfirmada?.vendedores ?? [],
   251	    primeraGestionPendiente,
   252	  }
   253	  const candidatos = candidatosDeHoy(entradaCosas)
   254	  const cosas = tresCosasDeHoy(entradaCosas)
   255	  const estaSemana = candidatos.slice(cosas.length)
   256	  const fuentesCaidas = [
   257	    consultaEquipo.error ? 'el seguimiento' : null,
   258	    datos.errorAgenda ? 'la agenda' : null,
   259	    datos.resumenOp.error ? 'el reparto' : null,
   260	  ].filter((f): f is string => f != null)
   261	  const fuentesListas = paginaEquipoVigente != null
   262	    && datos.agendaConfirmada != null
   263	    && datos.resumen != null
   264	  const reintentarDecisiones = () => {
   265	    if (consultaEquipo.error) void consultaEquipo.refetch()
   266	    if (datos.errorAgenda) datos.recargarAgenda()
   267	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   268	  }
   269	
   270	  const alternarDecision = (cosa: CosaDeHoy) => {
   271	    const abrir = decisionAbierta !== cosa.id
   272	    setDecisionAbierta(abrir ? cosa.id : null)
   273	    if (cosa.id !== 'primera_gestion') return
   274	    // Primera gestión: la cola de abajo pasa a ESA pestaña, para todo el equipo.
   275	    if (abrir) {
   276	      setPestana('primera_atencion')
   277	      setAnalistaId(null)
   278	      setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   279	    } else if (pestana === 'primera_atencion') {
   280	      setPestana('pendientes')
   281	      setAnuncio('Mostrando los pendientes de todo el equipo')
   282	    }
   283	  }
   284	  const verPrimeraGestion = () => {
   285	    setDecisionAbierta('primera_gestion')
   286	    setPestana('primera_atencion')
   287	    setAnalistaId(null)
   288	    setAnuncio('Mostrando las primeras gestiones vencidas de todo el equipo')
   289	    requestAnimationFrame(() => document.getElementById(`${idPanelCola}-tab-primera_atencion`)?.focus())
   290	  }
   291	
   292	  /** Una línea de contexto con datos YA confirmados; sin dato, nada. */
   293	  const contextoDe = (cosa: CosaDeHoy): string | null => {
   294	    switch (cosa.id) {
   295	      case 'primera_gestion':
   296	        return 'Revisa la primera gestión con cada analista: abajo quedan solo esos casos.'
   297	      case 'no_asistio':
   298	      case 'sin_accion': {
   299	        if (cosa.vendedorId != null) {
   300	          const r = rezagosConfirmados.get(cosa.vendedorId)
   301	          if (!r) return null
   302	          const plural = (n: number, uno: string, varios: string) => `${numero(n)} ${n === 1 ? uno : varios}`
   303	          return `En 7 días: ${plural(r.no_asistio, 'cita sin asistir', 'citas sin asistir')} · ${plural(r.vencidas, 'tarea vencida', 'tareas vencidas')} · ${plural(r.leads_sin_accion, 'lead sin próxima acción', 'leads sin próxima acción')}.`
   304	        }
   305	        const nombres = (datos.agendaConfirmada?.vendedores ?? [])
   306	          .filter((v) => v.rol === 'vendedor' && v.activo
   307	            && (cosa.id === 'no_asistio' ? v.no_asistio >= 2 : v.leads_sin_accion >= 3))
   308	          .map((v) => `${primerNombre(v.nombre)} (${cosa.id === 'no_asistio' ? v.no_asistio : v.leads_sin_accion})`)
   309	        return nombres.length > 0 ? nombres.join(' · ') : null
   310	      }
   311	      case 'por_repartir':
   312	        return 'Leads sin analista en tu bandeja. El reparto se hace en Derivar leads.'
   313	      default:
   314	        return null
   315	    }
   316	  }
   317	
   318	  // Los errores del mes (meta, cumplimiento, conversión, TC) también se
   319	  // avisan aquí: la franja muestra «—» y el aviso no espera a abrir «Detalle».
   320	  const errorIndicadores = !datos.sesionReal
   321	    ? false
   322	    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error || datos.hayErrorMensual)
   323	  const reintentarIndicadores = () => {
   324	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   325	    if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
   326	    if (datos.hayErrorMensual) datos.reintentarMensual()
   327	  }
   328	
   329	  // ── 3 · Consulta: las cifras de siempre, en una línea; el detalle, encima ──
   330	  const agendaResumen = datos.agendaConfirmada ? resumenAgenda(datos.agendaConfirmada.vendedores) : null
   331	  const filaCapital = datos.filasMeta[0]
   332	  const metaTexto = filaCapital == null || filaCapital.sinDato ? '—' : `${Math.round(filaCapital.pct)} %`
   333	  const conversionTexto = datos.conversionMensualError || datos.conversionConfirmada == null
   334	    ? '—'
   335	    : porcentajeConversionCanonica(datos.conversionConfirmada)
   336	  const pronostico = datos.capitalPronostico
   337	  // En la franja, compacto (S/ 1.48 M); la cifra exacta vive en el KPI del detalle.
   338	  const pronosticoCorto = pronostico && datos.resumen
   339	    ? moneyCompacta(pronostico.soloDolares ? datos.resumen.capital.asignado.usd : datos.resumen.capital.asignado.pen, pronostico.moneda)
   340	    : '—'
   341	
   342	  const tituloCola = nombreAnalista ? `Pendientes de ${corto(nombreAnalista)}` : 'Pendientes del equipo'
   343	
   344	  return (
   345	    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
   346	      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>
   347	
   348	      {modo.activo && (
   349	        <section aria-labelledby={`${idPanelCola}-decide`} className="flex flex-col gap-3">
   350	          <div className="flex items-center justify-between gap-4">
   351	            <h2 id={`${idPanelCola}-decide`} className="text-lg font-extrabold tracking-tight text-primary">Decide primero</h2>
   352	            {estaSemana.length > 0 && <EstaSemana cosas={estaSemana} onVerPrimeraGestion={verPrimeraGestion} etiquetaReparto={datos.etiquetaAccesoReparto} />}
   353	          </div>
   354	          <AvisoDegradacion activo={fuentesCaidas.length > 0} queReintenta="de las decisiones del día" onReintentar={reintentarDecisiones}>
   355	            Algunas decisiones no se pudieron confirmar: no respondió {fuentesCaidas.join(', ').replace(/, ([^,]*)$/, ' ni $1')}.
   356	          </AvisoDegradacion>
   357	          {/* Sin todas las fuentes no se ORDENA: una tarjeta ámbar no ocupa el
   358	              puesto de una roja que aún no llegó. Con una fuente caída sí se
   359	              muestra lo confirmado, bajo el aviso de que está incompleto. */}
   360	          {!fuentesListas && fuentesCaidas.length === 0 ? (
   361	            <Card>
   362	              <CardContent className="py-4">
   363	                <p role="status" className="text-sm text-muted-foreground">Revisando las decisiones del día…</p>
   364	              </CardContent>
   365	            </Card>
   366	          ) : cosas.length === 0 ? (
   367	            fuentesCaidas.length > 0 ? null : (
   368	              <Card>
   369	                <CardContent className="py-4">
   370	                  <p role="status" className="text-sm text-muted-foreground">Nada que decidir ahora mismo.</p>
   371	                </CardContent>
   372	              </Card>
   373	            )
   374	          ) : (
   375	            <div className="grid gap-3.5 lg:grid-cols-3">
   376	              {cosas.map((cosa) => (
   377	                <TarjetaDecision
   378	                  key={cosa.id}
   379	                  cosa={cosa}
   380	                  abierta={decisionAbierta === cosa.id}
   381	                  contexto={contextoDe(cosa)}
   382	                  idContexto={`${idPanelCola}-decision-${cosa.id}`}
   383	                  onAlternar={() => alternarDecision(cosa)}
   384	                  onVerPrimeraGestion={verPrimeraGestion}
   385	                  etiquetaReparto={datos.etiquetaAccesoReparto}
   386	                />
   387	              ))}
   388	            </div>
   389	          )}
   390	        </section>
   391	      )}
   392	
   393	      <AvisoDegradacion
   394	        activo={errorIndicadores}
   395	        queReintenta="de los indicadores del equipo"
   396	        onReintentar={reintentarIndicadores}
   397	      >
   398	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   399	      </AvisoDegradacion>
   400	
   401	      {/* ── 2 · Cola del seguimiento + Equipo hoy ── */}
   402	      <h2 className="sr-only">Pendientes y equipo</h2>
   403	      <div className="grid gap-4 lg:grid-cols-5">
   404	        <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
   405	          <SectionHead
   406	            icon={ListChecks}
   407	            title={tituloCola}
   408	            className="flex-wrap gap-y-2"
   409	            right={modo.activo ? (
   410	              <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
   411	                {PESTANAS.map((p, indice) => {
   412	                  const n = conteoPestana(p.id)
   413	                  return (
   414	                    <button
   415	                      key={p.id}
   416	                      id={`${idPanelCola}-tab-${p.id}`}
   417	                      type="button"
   418	                      role="tab"
   419	                      aria-selected={pestana === p.id}
   420	                      aria-controls={`${idPanelCola}-panel`}
   421	                      aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
   422	                      tabIndex={pestana === p.id ? 0 : -1}
   423	                      onClick={() => elegirPestana(p.id)}
   424	                      onKeyDown={(e) => {
   425	                        const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
   426	                          : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
   427	                          : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
   428	                        if (destino == null) return
   429	                        e.preventDefault()
   430	                        const siguiente = PESTANAS[destino]
   431	                        if (!siguiente) return
   432	                        elegirPestana(siguiente.id)
   433	                        document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
   434	                      }}
   435	                      className={cn(
   436	                        'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   437	                        pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
   438	                      )}
   439	                    >
   440	                      {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
   441	                    </button>
   442	                  )
   443	                })}
   444	              </div>
   445	            ) : undefined}
   446	          />
   447	          {!modo.activo ? (
   448	            <CardContent className="pb-5 pt-0">
   449	              <AvisoDegradacion activo={modo.error != null} queReintenta="del seguimiento" onReintentar={() => void modo.refetch()}>
   450	                No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.
   451	              </AvisoDegradacion>
   452	              {modo.error == null && (
   453	                <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
   454	              )}
   455	            </CardContent>
   456	          ) : (
   457	            <>
   458	              {analistas.length > 0 && (
   459	                <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
   460	                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
   461	                  <button
   462	                    type="button"
   463	                    aria-pressed={analistaId == null}
   464	                    onClick={() => elegirAnalista(null)}
   465	                    className={cn(
   466	                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   467	                      analistaId == null ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   468	                    )}
   469	                  >
   470	                    Todos
   471	                  </button>
   472	                  {analistas.map((m) => (
   473	                    <button
   474	                      key={m.perfil_id}
   475	                      type="button"
   476	                      aria-pressed={analistaId === m.perfil_id}
   477	                      aria-label={m.nombre_completo}
   478	                      onClick={() => elegirAnalista(m.perfil_id)}
   479	                      className={cn(
   480	                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   481	                        analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   482	                      )}
   483	                    >
   484	                      {corto(m.nombre_completo)}
   485	                    </button>
   486	                  ))}
   487	                </div>
   488	              )}
   489	
   490	              {abriendo && <p role="status" className="px-5 pb-2 text-xs text-muted-foreground">Abriendo ficha…</p>}
   491	              {errorApertura && <p role="alert" className="px-5 pb-2 text-xs text-destructive-text">No se pudo abrir la ficha. Vuelve a intentarlo.</p>}
   492	
   493	              <div
   494	                id={`${idPanelCola}-panel`}
   495	                role="tabpanel"
   496	                aria-labelledby={`${idPanelCola}-tab-${pestana}`}
   497	                tabIndex={paginaVigente && paginaVigente.items.length > 0 ? undefined : 0}
   498	                className="flex flex-1 flex-col"
   499	              >
   500	                <div className={cn(consultaCola.error && 'border-t border-border/60 px-5 py-4')}>
   501	                  <AvisoDegradacion activo={consultaCola.error != null} queReintenta="de los pendientes del equipo" onReintentar={() => void consultaCola.refetch()}>
   502	                    No se pudo cargar la cola. Los pendientes todavía no están confirmados.
   503	                  </AvisoDegradacion>
   504	                </div>
   505	                {consultaCola.error ? null : !pagina ? (
   506	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
   507	                ) : !paginaVigente ? (
   508	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   509	                    {pagina.modo !== 'activo'
   510	                      ? 'Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.'
   511	                      : 'Actualizando los pendientes con las reglas vigentes…'}
   512	                  </p>
   513	                ) : paginaVigente.items.length === 0 ? (
   514	                  <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   515	                    {nombreAnalista ? `${corto(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
   516	                  </p>
   517	                ) : (
   518	                  // oxlint-disable-next-line jsx-a11y/no-redundant-roles
   519	                  <ul role="list" aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
   520	                    {paginaVigente.items.map((item) => {
   521	                      const leadStore = leadPorId.get(item.lead_id)
   522	                      const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
   523	                      const analistaFila = item.lead.analista_nombre ? corto(item.lead.analista_nombre) : 'Sin analista'
   524	                      const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
   525	                      const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
   526	                      const urgente = item.severidad === 'critica'
   527	                      return (
   528	                        <li
   529	                          key={item.lead_id}
   530	                          data-sev={item.severidad}
   531	                          className="flex items-center gap-2 border-l-[3px] border-t border-t-border/60 pr-5"
   532	                          style={{ borderLeftColor: colorTira }}
   533	                        >
   534	                          <button
   535	                            type="button"
   536	                            // aria-disabled y NO disabled: un botón enfocado que se deshabilita
   537	                            // suelta el foco a <body> y la ficha lo devolvía ahí al cerrarse.
   538	                            // La guarda de abrirFicha ya evita el doble envío.
   539	                            aria-disabled={abriendo !== null || undefined}
   540	                            onClick={() => void abrirFicha(item.lead_id)}
   541	                            // El nombre dicta TODO lo visible (dueño, urgencia, estado,
   542	                            // tiempo, monto): un lector de pantalla no puede perder lo que se ve.
   543	                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}${urgente ? ', urgente' : ''}: ${estado}${monto ? `, ${monto}` : ''}`}
   544	                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 aria-disabled:cursor-wait"
   545	                          >
   546	                            {analistaId == null && (
   547	                              <span className="hidden w-[118px] shrink-0 items-center gap-2 sm:flex">
   548	                                <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
   549	                                <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
   550	                              </span>
   551	                            )}
   552	                            <span className="min-w-0 flex-1 leading-tight">
   553	                              <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
   554	                              <span className="flex min-w-0 items-center gap-1 text-xs text-muted-foreground-strong">
   555	                                {urgente && <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />}
   556	                                <span className="truncate">
   557	                                  {analistaId == null && <span className="sm:hidden">{analistaFila} · </span>}
   558	                                  {estado}
   559	                                </span>
   560	                              </span>
   561	                            </span>
   562	                            {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
   563	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   564	                          </button>
   565	                          {leadStore && (
   566	                            // Las acciones compactas miden 28 px: se llevan al mínimo de 36 (40 táctil), alto Y ancho.
   567	                            <div className="[&_a]:min-h-9 [&_a]:min-w-9 [&_button]:min-h-9 [&_button]:min-w-9 pointer-coarse:[&_a]:min-h-10 pointer-coarse:[&_a]:min-w-10 pointer-coarse:[&_button]:min-h-10 pointer-coarse:[&_button]:min-w-10">
   568	                              <AccionesContacto lead={leadStore} compacto />
   569	                            </div>
   570	                          )}
   571	                        </li>
   572	                      )
   573	                    })}
   574	                  </ul>
   575	                )}
   576	                <div className="mt-auto flex items-center justify-end gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
   577	                  {/* El conteo va DENTRO del enlace: el número abre su lista. */}
   578	                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold tabular-nums text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   579	                    {paginaVigente && paginaVigente.total_items > paginaVigente.items.length
   580	                      ? `Ver los ${numero(paginaVigente.total_items)} en Seguimiento`
   581	                      : 'Ver todo en Seguimiento'}
   582	                    <ChevronRight className="size-3.5" aria-hidden />
   583	                  </a>
   584	                </div>
   585	              </div>
   586	            </>
   587	          )}
   588	        </Card>
   589	
   590	        {/* ── Equipo hoy: tocar a alguien filtra la cola y despliega sus señales ── */}
   591	        <Card className="min-w-0 overflow-hidden lg:col-span-2">
   592	          <SectionHead
   593	            icon={UsersRound}
   594	            title="Equipo hoy"
   595	            right={(
   596	              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-1 text-xs font-bold text-accent hover:underline pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   597	                Mi equipo hoy <span aria-hidden>→</span>
   598	              </a>
   599	            )}
   600	          />
   601	          {rank != null && rank.length > 0 && (semaforoEquipo.rojo > 0 || semaforoEquipo.ambar > 0 || datos.agendaConfirmada != null) && (
   602	            <div className="-mt-2 flex flex-wrap items-center gap-1 px-5 pb-2 text-xs text-muted-foreground-strong">
   603	              {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
   604	                // Solo con la agenda confirmada: sin ella, cero señales es desconocido.
   605	                ? <p>Sin alertas en el equipo</p>
   606	                : (
   607	                  <div role="group" aria-label="Ver analistas por nivel" className="flex flex-wrap items-center gap-1">
   608	                    {([['critico', semaforoEquipo.rojo, 'en rojo'], ['atencion', semaforoEquipo.ambar, 'en ámbar']] as const).map(([nivel, n, texto], i) => (
   609	                      <span key={nivel} className="inline-flex items-center gap-1">
   610	                        {i > 0 && <span aria-hidden>·</span>}
   611	                        <button
   612	                          type="button"
   613	                          aria-pressed={nivelEquipo === nivel}
   614	                          disabled={n === 0}
   615	                          onClick={() => setNivelEquipo((actual) => (actual === nivel ? null : nivel))}
   616	                          className={cn(CLASE_CIFRA, 'disabled:cursor-default disabled:no-underline', nivelEquipo === nivel && 'font-bold text-foreground underline')}
   617	                        >
   618	                          {numero(n)} {texto}
   619	                        </button>
   620	                      </span>
   621	                    ))}
   622	                    {nivelEquipo != null && (
   623	                      <button type="button" className={cn(CLASE_CIFRA, 'ml-1 text-accent')} onClick={() => setNivelEquipo(null)}>Ver todos</button>
   624	                    )}
   625	                  </div>
   626	                )}
   627	            </div>
   628	          )}
   629	          <div className={cn(datos.errorAgenda && 'mx-5 mb-2')}>
   630	            <AvisoDegradacion activo={datos.errorAgenda != null} queReintenta="de la agenda del equipo" onReintentar={datos.recargarAgenda}>
   631	              La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.
   632	            </AvisoDegradacion>
   633	          </div>
   634	          {rank == null ? (
   635	            <CardContent className="pb-5 pt-0">
   636	              <p className="text-sm text-muted-foreground">
   637	                {datos.vendedoresOp.error
   638	                  ? 'El resumen por analista no está disponible en este momento.'
   639	                  : 'Cargando el resumen por analista…'}
   640	              </p>
   641	            </CardContent>
   642	          ) : rank.length === 0 ? (
   643	            <CardContent className="pb-5 pt-0">
   644	              <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   645	            </CardContent>
   646	          ) : (
   647	            // oxlint-disable-next-line jsx-a11y/no-redundant-roles
   648	            <ul role="list" aria-label="Analistas del equipo" className="border-t border-border/60">
   649	              {rank.filter((r) => nivelEquipo == null || lecturas.get(r.m.perfil_id)?.nivel === nivelEquipo).map((r) => {
   650	                const id = r.m.perfil_id
   651	                const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
   652	                const rezago = rezagosConfirmados.get(id)
   653	                const abierto = analistaId === id
   654	                const principal = lectura.senales[0]?.texto
   655	                  ?? (r.activos === 0
   656	                    ? 'Sin leads abiertos'
   657	                    : rezago != null ? 'Al día' : `Última actividad ${haceTexto(r.diasSinActividadMax)}`)
   658	                const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   659	                const idDetalle = `${idPanelCola}-equipo-${id}`
   660	                // PEN y USD jamás se suman sin decirlo: el nombre lleva el desglose.
   661	                const desglose = r.capitalUSD > 0
   662	                  ? cap.tc != null
   663	                    ? ` (${moneyK(r.capitalPEN, 'PEN')} más ${moneyK(r.capitalUSD, 'USD')})`
   664	                    : `, más ${moneyK(r.capitalUSD, 'USD')} aparte sin tipo de cambio`
   665	                  : ''
   666	                const nivelTexto = lectura.nivel != null ? `${TEXTO_NIVEL[lectura.nivel]}. ` : ''
   667	                const conversion = r.conversion == null
   668	                  ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
   669	                  : `${textoConversionOperativa(r.conversion)} conversión`
   670	                return (
   671	                  <li key={id} className="border-b border-border/60 last:border-b-0">
   672	                    <button
   673	                      type="button"
   674	                      aria-expanded={abierto}
   675	                      aria-controls={idDetalle}
   676	                      aria-label={`${r.m.nombre_completo}: ${nivelTexto}${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}${desglose}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
   677	                      onClick={() => elegirAnalista(id)}
   678	                      className={cn(
   679	                        'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
   680	                        abierto && 'bg-accent/[0.08]',
   681	                      )}
   682	                    >
   683	                      <MarcaNivel nivel={lectura.nivel} />
   684	                      <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
   685	                      <span className="min-w-0 flex-1 leading-tight">
   686	                        <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
   687	                        <span className="block truncate text-xs text-muted-foreground-strong">{principal}</span>
   688	                      </span>
   689	                      <span className="shrink-0 text-right leading-tight">
   690	                        <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
   691	                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto tono="fuerte" />
   692	                      </span>
   693	                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierto ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
   694	                    </button>
   695	                    <div id={idDetalle} hidden={!abierto} className="space-y-1.5 px-5 pb-3 pl-[62px]">
   696	                      {lectura.senales.length > 1 && (
   697	                        <div className="flex flex-wrap gap-1.5">
   698	                          {lectura.senales.slice(1).map((s) => <ChipSenal key={s.texto} texto={s.texto} nivel={s.nivel} />)}
   699	                        </div>
   700	                      )}
   701	                      <a href={hashDe('gestion-diaria')} className={cn(CLASE_CIFRA, 'text-xs tabular-nums text-muted-foreground-strong')}>
   702	                        {numero(r.activos)} activos · {conversion}
   703	                        {r.operacionesCartera != null && r.operacionesCartera > 0 ? ` · ${numero(r.operacionesCartera)} de cartera` : ''}
   704	                        {r.sinTocar > 0 ? ` · ${numero(r.sinTocar)} sin tocar` : ''}
   705	                        <span className="font-semibold text-accent"> · Ver su día →</span>
   706	                      </a>
   707	                      {rezago != null && (
   708	                        <button type="button" onClick={abrirDetalle} className={cn(CLASE_CIFRA, 'block text-xs tabular-nums text-muted-foreground-strong')}>
   709	                          {rezago.toques > 0
   710	                            ? `${numero(rezago.toques)} toques en 7 días${rezago.pct_completadas != null ? ` · ${Math.round(rezago.pct_completadas)} % completadas` : ''}`
   711	                            : 'Sin toques registrados en 7 días'}
   712	                          <span className="font-semibold text-accent"> · Ver agenda</span>
   713	                        </button>
   714	                      )}
   715	                    </div>
   716	                  </li>
   717	                )
   718	              })}
   719	            </ul>
   720	          )}
   721	        </Card>
   722	      </div>
   723	
   724	      {/* ── 3 · Consulta: cifras en una línea; «Detalle» abre todo lo demás ── */}
   725	      <section aria-label="Consulta" className="flex min-h-12 flex-wrap items-center gap-x-5 gap-y-1.5 rounded-xl border border-border bg-card px-5 py-2">
   726	        <span className="text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground-strong" aria-hidden>Consulta</span>
   727	        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
   728	        <ul role="list" aria-label="Cifras del equipo" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-[12.5px] tabular-nums text-muted-foreground-strong">
   729	          <li>
   730	            <a href={hashDe('pipeline')} className={CLASE_CIFRA}>
   731	              <strong className="font-extrabold text-primary">{pronosticoCorto}</strong> pronóstico
   732	              {pronostico?.otra ? ` · +${pronostico.otra} aparte` : ''}
   733	            </a>
   734	          </li>
   735	          <li>
   736	            <a href={hashDe('cartera')} className={CLASE_CIFRA}>
   737	              <strong className="font-extrabold text-primary">{datos.resumen ? numero(datos.resumen.totales.asignados) : '—'}</strong> leads activos
   738	            </a>
   739	          </li>
   740	          <li>
   741	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   742	              <strong className="font-extrabold text-primary">{metaTexto}</strong> de la meta
   743	            </button>
   744	          </li>
   745	          <li>
   746	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   747	              <strong className="font-extrabold text-primary">{conversionTexto}</strong> conversión del mes
   748	            </button>
   749	          </li>
   750	          <li aria-hidden className="h-[18px] w-px bg-border" />
   751	          <li>
   752	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   753	              <strong className="font-extrabold text-primary">{agendaResumen ? numero(agendaResumen.toques) : '—'}</strong> toques en 7 días
   754	            </button>
   755	          </li>
   756	          <li>
   757	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   758	              <strong className="font-extrabold text-primary">{agendaResumen?.pctCompletadas != null ? `${agendaResumen.pctCompletadas} %` : '—'}</strong> completadas
   759	            </button>
   760	          </li>
   761	          <li>
   762	            <button type="button" className={CLASE_CIFRA} onClick={abrirDetalle}>
   763	              {agendaResumen && agendaResumen.noAsistio >= 2 && (
   764	                <AlertTriangle className="size-3 shrink-0" style={{ color: 'var(--destructive-text)' }} aria-hidden />
   765	              )}
   766	              <strong
   767	                className="font-extrabold"
   768	                style={{ color: agendaResumen && agendaResumen.noAsistio >= 2 ? 'var(--destructive-text)' : 'var(--primary)' }}
   769	              >
   770	                {agendaResumen ? numero(agendaResumen.noAsistio) : '—'}
   771	              </strong> {agendaResumen?.noAsistio === 1 ? 'cita sin asistir' : 'citas sin asistir'}
   772	            </button>
   773	          </li>
   774	        </ul>
   775	        <Button type="button" variant="outline" size="sm" className="ml-auto min-h-9 text-accent pointer-coarse:min-h-10" onClick={abrirDetalle}>
   776	          Detalle
   777	        </Button>
   778	      </section>
   779	
   780	      <Dialog
   781	        open={detalleAbierto}
   782	        onClose={() => setDetalleAbierto(false)}
   783	        focoInicial={tituloDetalle}
   784	        focoAlCerrar={focoALaCola ? focoTrasDetalle : undefined}
   785	        className="w-[1180px] max-h-[88vh] max-w-[94vw]"
   786	      >
   787	        <DialogHeader>
   788	          {/* El foco entra por el título, no en mitad de la rejilla de indicadores. */}
   789	          <DialogTitle><span ref={tituloDetalle} tabIndex={-1} className="outline-none">Detalle del equipo</span></DialogTitle>
   790	          <DialogDescription>Indicadores, cumplimiento del mes y agenda de los últimos 7 días.</DialogDescription>
   791	        </DialogHeader>
   792	        <DialogBody className="space-y-4">
   793	          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   794	            {/* Pronóstico: `capitalPrincipal`, NUNCA un total mixto con los dólares. */}
   795	            <a href={hashDe('pipeline')} className={CLASE_KPI_ENLACE}>
   796	            <KpiCard
   797	              label="Pronóstico de capital abierto"
   798	              value={pronostico ? pronostico.valor : '—'}
   799	              icon={Wallet}
   800	              color={SEMAFORO.neutro}
   801	              sub={
   802	                pronostico?.otra
   803	                  ? `En soles · +${pronostico.otra} aparte`
   804	                  : pronostico?.soloDolares
   805	                    ? 'En dólares · abiertos con analista'
   806	                    : datos.resumen && datos.resumen.capital.asignado.pen === 0 && datos.resumen.totales.asignados > 0
   807	                      ? 'Sin montos estimados — complétalos en cada ficha'
   808	                      : 'En soles · abiertos con analista'
   809	              }
   810	            />
   811	            </a>
   812	            <a href={hashDe('cartera')} className={CLASE_KPI_ENLACE}>
   813	            <KpiCard
   814	              label="Leads activos del equipo"
   815	              value={datos.resumen ? String(datos.resumen.totales.asignados) : '—'}
   816	              icon={Users}
   817	              color={SEMAFORO.neutro}
   818	              sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
   819	              delay={60}
   820	            />
   821	            </a>
   822	            {/* Abre la cola en su pestaña: cierra el detalle y deja el foco en ella.
   823	                Botón ESTIRADO encima de la tarjeta (un <button> no puede
   824	                contener los <div> de KpiCard). Sin cola visible, no hay acción. */}
   825	            <div className="relative h-full">
   826	              <KpiCard
   827	                label="Primeras gestiones vencidas"
   828	                value={primeraGestionPendiente == null ? '—' : String(primeraGestionPendiente)}
   829	                icon={AlertTriangle}
   830	                color={SEMAFORO.neutro}
   831	                sub={primeraGestionPendiente == null
   832	                  ? 'Sin dato por ahora'
   833	                  : primeraGestionPendiente > 0 ? 'Ver cuáles son →' : 'Ninguna vencida'}
   834	                delay={120}
   835	              />
   836	              {modo.activo && primeraGestionPendiente != null && (
   837	                <button
   838	                  type="button"
   839	                  aria-label={`Primeras gestiones vencidas: ${numero(primeraGestionPendiente)}. Verlas en la cola`}
   840	                  className={cn(CLASE_KPI_ENLACE, 'absolute inset-0')}
   841	                  onClick={() => {
   842	                    const destino = document.getElementById(`${idPanelCola}-tab-primera_atencion`)
   843	                    // Solo se desvía el foco si la pestaña existe; si no, Radix lo
   844	                    // devuelve a «Detalle» como siempre.
   845	                    focoTrasDetalle.current = destino
   846	                    setFocoALaCola(destino != null)
   847	                    setDetalleAbierto(false)
   848	                    verPrimeraGestion()
   849	                  }}
   850	                />
   851	              )}
   852	            </div>
   853	            <a
   854	              href={hashDe('derivaciones')}
   855	              aria-label={`Por repartir: ${datos.etiquetaAccesoReparto}`}
   856	              className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
   857	            >
   858	              <KpiCard
   859	                label="Por repartir"
   860	                value={datos.totalPorRepartir == null ? '—' : String(datos.totalPorRepartir)}
   861	                icon={Inbox}
   862	                color={SEMAFORO.neutro}
   863	                sub={datos.detalleReparto}
   864	                delay={180}
   865	              />
   866	            </a>
   867	          </div>
   868	
   869	          <div className="grid gap-4 lg:grid-cols-5">
   870	            <Card className="lg:col-span-2">
   871	              <SectionHead
   872	                icon={Target}
   873	                title="Cumplimiento del mes"
   874	                right={tc ? <span className="text-xs text-muted-foreground-strong">{rotuloTipoCambio(tc.promedio, tc.fuente)}</span> : undefined}
   875	              />
   876	              <CardContent className="space-y-4 pb-5 pt-0">
   877	                {datos.filasMeta.map((f) => (
   878	                  <div key={f.label}>
   879	                    <div className="mb-1.5 flex items-baseline justify-between gap-2">
   880	                      <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
   881	                      {f.label === 'Capital confirmado'
   882	                        // El capital confirmado se abre en Facturación: el mes día a día, por analista.
   883	                        ? <a href={hashDe('facturacion')} className={cn(CLASE_CIFRA, 'text-xs font-bold tabular-nums text-primary')}>{f.txt} →</a>
   884	                        : <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>}
   885	                    </div>
   886	                    {f.nota && <p className="mb-1 text-[11px] tabular-nums text-muted-foreground-strong">{f.nota}</p>}
   887	                    {f.sinDato
   888	                      ? <p className="text-[11px] text-muted-foreground-strong">{f.sinDato}</p>
   889	                      : <Progress value={f.pct} color={colorMeta(f.pct)} />}
   890	                  </div>
   891	                ))}
   892	                <p className="text-[11px] text-muted-foreground-strong">
   893	                  El capital en dólares entra al total convertido a tipo de cambio real. El pronóstico no cuenta como cumplimiento.
   894	                </p>
   895	                <AvisoDegradacion activo={datos.hayErrorMensual} queReintenta="de la meta y el cumplimiento del mes" onReintentar={datos.reintentarMensual}>
   896	                  Parte del cumplimiento del mes no se pudo cargar: se muestra «—» donde falta el dato.
   897	                </AvisoDegradacion>
   898	              </CardContent>
   899	            </Card>
   900	            <div className="min-w-0 lg:col-span-3">
   901	              <AgendaEquipoPanel
   902	                datos={datos.datosAgenda}
   903	                cargando={datos.cargandoAgenda}
   904	                error={datos.errorAgenda}
   905	                modoDemo={yo?.demo === true}
   906	                onReintentar={datos.recargarAgenda}
   907	                equipo={datos.equipo}
   908	              />
   909	            </div>
   910	          </div>
   911	
   912	          {/* Por empresa: de dónde vino cada sol (Avance vs. COOPAC). */}
   913	          <DesglosePorEmpresa demo={yo?.demo === true} porVendedor={datos.cumplimientoMensual?.porVendedor ?? null} />
   914	          {/* Rentabilidad R3: las solicitudes de tasa propias en curso (solo si hay). */}
   915	          <TasasAutorizadasAnalistaPanel />
   916	          <p className="text-[11px] text-muted-foreground-strong">
   917	            Ves solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
   918	          </p>
   919	        </DialogBody>
   920	        <DialogFooter>
   921	          <Button variant="outline" size="sm" className="min-h-9 pointer-coarse:min-h-10" onClick={() => setDetalleAbierto(false)}>Cerrar</Button>
   922	        </DialogFooter>
   923	      </Dialog>
   924	    </div>
   925	  )
   926	}
   927	
   928	/** El botón de acción de una decisión. Nunca va DENTRO del botón que la despliega. */
   929	function AccionDecision({ cosa, onVerPrimeraGestion, etiquetaReparto }: {
   930	  cosa: CosaDeHoy
   931	  onVerPrimeraGestion: () => void
   932	  etiquetaReparto: string
   933	}): JSX.Element {
   934	  const clase = 'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg bg-primary px-3 text-xs font-bold text-primary-foreground hover:bg-primary-press pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
   935	  if (cosa.id === 'primera_gestion') {
   936	    return (
   937	      <button type="button" className={clase} aria-label={`Ver en la cola: ${cosa.texto}`} onClick={onVerPrimeraGestion}>
   938	        Ver <ChevronRight className="size-3.5" aria-hidden />
   939	      </button>
   940	    )
   941	  }
   942	  if (cosa.id === 'por_repartir') {
   943	    return (
   944	      <a href={hashDe('derivaciones')} className={clase} aria-label={etiquetaReparto}>
   945	        Repartir <ChevronRight className="size-3.5" aria-hidden />
   946	      </a>
   947	    )
   948	  }
   949	  if (cosa.id === 'no_asistio' || cosa.id === 'sin_accion') {
   950	    // La cola no contiene citas ni leads «sin próxima acción»: filtrarla
   951	    // enseñaría OTROS casos. La decisión se toma viendo el día del equipo.
   952	    const label = cosa.vendedorId != null ? 'Ver su día' : 'Ver el equipo'
   953	    return (
   954	      <a href={hashDe('gestion-diaria')} className={clase} aria-label={`${label}: ${cosa.texto}`}>
   955	        {label} <ChevronRight className="size-3.5" aria-hidden />
   956	      </a>
   957	    )
   958	  }
   959	  // Candidatos del modo legado: aquí no aparecen (la cola legada llega null),
   960	  // pero si algún día lo hicieran, su lugar es el módulo de seguimiento.
   961	  return (
   962	    <a href={hashDe('seguimiento')} className={clase} aria-label={`${cosa.accion}: ${cosa.texto}`}>
   963	      {cosa.accion} <ChevronRight className="size-3.5" aria-hidden />
   964	    </a>
   965	  )
   966	}
   967	
   968	function TarjetaDecision({ cosa, abierta, contexto, idContexto, onAlternar, onVerPrimeraGestion, etiquetaReparto }: {
   969	  cosa: CosaDeHoy
   970	  abierta: boolean
   971	  contexto: string | null
   972	  idContexto: string
   973	  onAlternar: () => void
   974	  onVerPrimeraGestion: () => void
   975	  etiquetaReparto: string
   976	}): JSX.Element {
   977	  const { cifra, resto } = partesDeCosa(cosa.texto)
   978	  return (
   979	    <Card
   980	      data-decision={cosa.id}
   981	      className={cn('overflow-hidden border-l-4', abierta && 'ring-2 ring-accent')}
   982	      style={{ borderLeftColor: SEV_BORDE[cosa.severidad] }}
   983	    >
   984	      <div className="flex flex-wrap items-center gap-2 py-2 pl-4 pr-3">
   985	        <button
   986	          type="button"
   987	          aria-expanded={abierta}
   988	          aria-controls={idContexto}
   989	          aria-label={`${SEV_TEXTO[cosa.severidad]}: ${cosa.texto}`}
   990	          onClick={onAlternar}
   991	          className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 rounded-md text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
   992	        >
   993	          {cifra && (
   994	            <span className="min-w-10 text-[32px] font-extrabold leading-none tracking-tight tabular-nums text-primary">{cifra}</span>
   995	          )}
   996	          <span className="min-w-0 flex-1 leading-tight">
   997	            <span className="block text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: SEV_TEXTO_COLOR[cosa.severidad] }}>
   998	              {SEV_TEXTO[cosa.severidad]}
   999	            </span>
  1000	            <span className="line-clamp-2 break-words text-[15px] font-bold">{resto}</span>
  1001	          </span>
  1002	          <ChevronRight
  1003	            className={cn('size-4 shrink-0 transition-transform', abierta ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')}
  1004	            aria-hidden
  1005	          />
  1006	        </button>
  1007	        <AccionDecision cosa={cosa} onVerPrimeraGestion={onVerPrimeraGestion} etiquetaReparto={etiquetaReparto} />
  1008	      </div>
  1009	      <p id={idContexto} hidden={!abierta} className="border-t border-border/60 px-4 py-2.5 text-xs text-muted-foreground-strong">
  1010	        {contexto ?? 'Sin más detalle confirmado por ahora.'}
  1011	      </p>
  1012	    </Card>
  1013	  )
  1014	}
  1015	
  1016	/** «Esta semana · N»: lo que no entró en las tres tarjetas. Esc y clic fuera lo cierran. */
  1017	function EstaSemana({ cosas, onVerPrimeraGestion, etiquetaReparto }: {
  1018	  cosas: CosaDeHoy[]
  1019	  onVerPrimeraGestion: () => void
  1020	  etiquetaReparto: string
  1021	}): JSX.Element {
  1022	  const [abierto, setAbierto] = useState(false)
  1023	  const contenedor = useRef<HTMLDivElement>(null)
  1024	  const disparador = useRef<HTMLButtonElement>(null)
  1025	  const idLista = useId()
  1026	  useEffect(() => {
  1027	    if (!abierto) return
  1028	    const fuera = (e: PointerEvent) => {
  1029	      if (!contenedor.current?.contains(e.target as Node)) setAbierto(false)
  1030	    }
  1031	    // Esc cierra y devuelve el foco al disparador, esté donde esté el foco
  1032	    // dentro de la lista (y también si quedó fuera: el popover no atrapa).
  1033	    const escape = (e: KeyboardEvent) => {
  1034	      if (e.key !== 'Escape') return
  1035	      setAbierto(false)
  1036	      if (contenedor.current?.contains(document.activeElement)) disparador.current?.focus()
  1037	    }
  1038	    // Tabular fuera del popover lo cierra: si no, quedaría encima de las
  1039	    // tarjetas que reciben el foco a continuación (WCAG 2.4.11).
  1040	    const nodo = contenedor.current
  1041	    const salida = (e: FocusEvent) => {
  1042	      if (e.relatedTarget instanceof Node && !nodo?.contains(e.relatedTarget)) setAbierto(false)
  1043	    }
  1044	    document.addEventListener('pointerdown', fuera)
  1045	    document.addEventListener('keydown', escape)
  1046	    nodo?.addEventListener('focusout', salida)
  1047	    return () => {
  1048	      document.removeEventListener('pointerdown', fuera)
  1049	      document.removeEventListener('keydown', escape)
  1050	      nodo?.removeEventListener('focusout', salida)
  1051	    }
  1052	  }, [abierto])
  1053	  return (
  1054	    <div ref={contenedor} className="relative">
  1055	      <button
  1056	        ref={disparador}
  1057	        type="button"
  1058	        aria-expanded={abierto}
  1059	        aria-controls={idLista}
  1060	        onClick={() => setAbierto((v) => !v)}
  1061	        className="inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-full border border-border bg-card px-3 text-xs font-semibold text-muted-foreground-strong hover:text-foreground pointer-coarse:min-h-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
  1062	      >
  1063	        <span className="size-2 rounded-full" style={{ background: SEMAFORO.atencion }} aria-hidden />
  1064	        Esta semana · {cosas.length}
  1065	        <ChevronRight className={cn('size-3.5 transition-transform', abierto ? '-rotate-90' : 'rotate-90')} aria-hidden />
  1066	      </button>
  1067	      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
  1068	      <ul role="list"
  1069	        id={idLista}
  1070	        hidden={!abierto}
  1071	        aria-label="Decisiones para esta semana"
  1072	        className="ac-pop absolute right-0 top-11 z-20 w-[340px] max-w-[90vw] rounded-xl border border-border bg-card p-2 shadow-[var(--shadow-pop)]"
  1073	      >
  1074	        {cosas.map((c) => (
  1075	          <li key={c.id} className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-xs font-semibold">
  1076	            <span className="size-2 shrink-0 rounded-full" style={{ background: SEV_BORDE[c.severidad] }} aria-hidden />
  1077	            <span className="min-w-0 flex-1">
  1078	              <span className="sr-only">{SEV_TEXTO[c.severidad]}: </span>{c.texto}
  1079	            </span>
  1080	            <AccionDecision cosa={c} onVerPrimeraGestion={() => { setAbierto(false); onVerPrimeraGestion() }} etiquetaReparto={etiquetaReparto} />
  1081	          </li>
  1082	        ))}
  1083	      </ul>
  1084	    </div>
  1085	  )
  1086	}
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
