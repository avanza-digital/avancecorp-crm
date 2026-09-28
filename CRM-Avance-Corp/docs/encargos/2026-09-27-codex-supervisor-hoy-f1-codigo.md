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

# Encargo: AUDITAR el código de la F1 del «Hoy» del supervisor (puesto de mando) — LEVEL 2

El dueño (Miguel) aprobó el plan (que tú refutaste antes: CHANGES_REQUESTED, 4 P1 + 6 P2, todos
aceptados) y pidió ejecutar TODAS las fases con Codex auditando TODO el código. Esta es la F1:
cola del seguimiento + «Equipo hoy». Aún NO está enrutada (hoy.tsx sigue apuntando a la pantalla
clásica); se conectará al final (F4) junto con el e2e. Busca bugs reales, regresiones de la
pantalla clásica por la extracción de `datos-supervisor.ts`, fallos fail-closed, a11y, y
desviaciones de lo que tus 10 hallazgos pedían. Si algo está bien, no lo menciones.

## Hechos de producción verificados (lecturas SQL de hoy)
- `crm.sla_operacion_control.modo = 'activo'` desde 2026-09-07 (revisión 1).
- `crm.cola_accion_v2_fn` VIVA (md5 prosrc 0a3ea253…): filtra por `p_analista_id` y `p_etapa`
  ANTES de calcular `totales`; los `totales` NO dependen de `p_senal`.
- `private.sla_operacion_leads` VIVA: la señal `primera_atencion` es
  `v_usable and coalesce(p_ahora>=v_primera,false)` (solo con el plazo VENCIDO) y su aviso se
  construye con severidad fija `'critica'`. Por eso `totales.primera_atencion > 0` ⇒ rojo, sin
  inferirlo del primer ítem (respuesta a tu P1 sobre `hayCritica`).

## Cómo se resolvieron tus hallazgos del plan (en esta F1)
- P1 semáforo del equipo → `lib/senal-equipo.ts`: una lectura por analista (rojo prevalece) que
  alimenta punto, cabecera y chips; `pct_completadas` se rotula «% completadas».
- P1 errores parciales → la cola usa `consulta.error ? undefined : data` y exige `pagina.modo === 'activo'`;
  la agenda para DECIDIR usa `agendaConfirmada` (sin datos retenidos tras error); aviso visible
  de agenda caída en «Equipo hoy».
- P2 filas → join por `lead_id` con el store; monto y contacto solo con lead completo;
  `referencia_en` null → «sin fecha confirmada»; apertura con estados como `ColaSlaPanel`; chips
  del roster `activo && rol_crm === 'vendedor'`; nombre accesible con dueño, estado y tiempo.
- P2 pestañas → «Primera gestión» es una PESTAÑA real (no un filtro contextual): 4 pestañas
  (Para atender ahora · Primera gestión · Tareas vencidas · Todas); título «Pendientes del equipo».
- P2 mezcla de modos → `HoySupervisorMando` elige: legado ⇒ pantalla clásica entera; si no ⇒
  `PuestoDeMando` remontado por `control_revision`. Un solo contrato de cola por componente.
- P2 coste → una consulta por (pestaña, analista); sin consulta extra `limite=1`.
- P2 a11y → botón de fila y acciones de contacto son HERMANOS; filas del equipo con
  `aria-expanded` + `aria-controls` (región con `hidden`); objetivos ≥36 px (min-h-9).
- Decisión propia: en modo legado (demo) se ve la pantalla clásica (la opción de menor riesgo que
  tú señalaste); el diseño nuevo se aprueba con sesión real.

## DIFF de la F1 (staged, frente a HEAD)
```diff
diff --git a/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts b/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts
index 520402d3..867012f7 100644
--- a/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/tres-cosas.test.ts
@@ -1,5 +1,5 @@
 import { describe, expect, it } from 'vitest'
-import { tresCosasDeHoy, type TresCosasInput } from './tres-cosas'
+import { candidatosDeHoy, tresCosasDeHoy, type TresCosasInput } from './tres-cosas'
 import type { ColaAccionOperativa } from './cola-accion'
 import type { ItemCola } from './inteligencia'
 import type { MetricaAgendaVendedor } from './metricas-agenda'
@@ -196,3 +196,50 @@ describe('tresCosasDeHoy', () => {
       .toEqual(tresCosasDeHoy(entrada({ vendedoresAgenda: [b, a] })))
   })
 })
+
+describe('candidatosDeHoy + seguimiento activo (27/09/2026)', () => {
+  it('ESTADO DE PRODUCCIÓN (seguimiento activo, cola legada null): la primera gestión vencida es roja', () => {
+    const cosas = tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: 4 }))
+    expect(cosas).toEqual([{
+      id: 'primera_gestion',
+      severidad: 'critica',
+      texto: '4 primeras gestiones vencidas',
+      accion: 'Ver',
+      destino: { tipo: 'vista', vista: 'seguimiento' },
+    }])
+  })
+
+  it('singular honesto y sin dato no hay tarjeta (null, ausente o cero)', () => {
+    expect(tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: 1 }))[0]?.texto)
+      .toBe('1 primera gestión vencida')
+    expect(tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: null }))).toEqual([])
+    expect(tresCosasDeHoy(entrada({ cola: null }))).toEqual([])
+    expect(tresCosasDeHoy(entrada({ cola: null, primeraGestionPendiente: 0 }))).toEqual([])
+  })
+
+  it('candidatosDeHoy NO recorta: lo que no entra en la franja queda para «Esta semana»', () => {
+    const entradaLlena = entrada({
+      cola: null,
+      primeraGestionPendiente: 2,
+      totalPorRepartir: 3,
+      vendedoresAgenda: [ven('v1', 'Ana', { no_asistio: 2, leads_sin_accion: 5 })],
+    })
+    const todos = candidatosDeHoy(entradaLlena)
+    expect(todos.map((c) => c.id)).toEqual(['primera_gestion', 'no_asistio', 'sin_accion', 'por_repartir'])
+    expect(tresCosasDeHoy(entradaLlena)).toEqual(todos.slice(0, 3))
+  })
+
+  it('la cosa de UN analista trae su dueño; la agrupada no señala a nadie', () => {
+    const [sola] = tresCosasDeHoy(entrada({ vendedoresAgenda: [ven('v1', 'Ana', { no_asistio: 2 })] }))
+    expect(sola).toMatchObject({ id: 'no_asistio', vendedorId: 'v1' })
+    const [accionSola] = tresCosasDeHoy(entrada({ vendedoresAgenda: [ven('v7', 'Eva', { leads_sin_accion: 3 })] }))
+    expect(accionSola).toMatchObject({ id: 'sin_accion', vendedorId: 'v7' })
+    const agrupadas = tresCosasDeHoy(entrada({
+      vendedoresAgenda: [
+        ven('v1', 'Ana', { no_asistio: 2, leads_sin_accion: 3 }),
+        ven('v2', 'Bea', { no_asistio: 2, leads_sin_accion: 3 }),
+      ],
+    }))
+    for (const cosa of agrupadas) expect(cosa).not.toHaveProperty('vendedorId')
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/lib/tres-cosas.ts b/CRM-Avance-Corp/app/src/lib/tres-cosas.ts
index 0a7eda48..beb042ab 100644
--- a/CRM-Avance-Corp/app/src/lib/tres-cosas.ts
+++ b/CRM-Avance-Corp/app/src/lib/tres-cosas.ts
@@ -17,6 +17,9 @@
 // · Degradación honesta: con cola null (cargando o error) el candidato NO
 //   existe y no se inventa urgencia desde el store local; el fallo se avisa
 //   en AvisoDegradacion, que es el canal de errores de la pantalla (F3 #4).
+// · Seguimiento ACTIVO (producción desde el 07/09/2026): la cola legada no se
+//   consulta y `cola` llega null. La interrupción del día sale entonces del
+//   conteo del seguimiento (`primeraGestionPendiente`, 27/09/2026).
 import type { MetricaAgendaVendedor } from './metricas-agenda'
 import { haceTexto } from './inteligencia'
 import { TOPE_ESTANCADOS, type ColaAccionOperativa } from './cola-accion'
@@ -26,15 +29,17 @@ export type PestanaColaDestino = 'urgente' | 'sin_movimiento' | 'todo'
 
 export type DestinoCosa =
   | { tipo: 'pestana'; pestana: PestanaColaDestino }
-  | { tipo: 'vista'; vista: 'derivaciones' | 'equipo' }
+  | { tipo: 'vista'; vista: 'derivaciones' | 'equipo' | 'seguimiento' }
 
 export interface CosaDeHoy {
-  id: 'sin_responder' | 'no_asistio' | 'por_repartir' | 'sin_accion' | 'sin_movimiento'
+  id: 'sin_responder' | 'primera_gestion' | 'no_asistio' | 'por_repartir' | 'sin_accion' | 'sin_movimiento'
   severidad: 'critica' | 'atencion'
   texto: string
   /** Etiqueta del enlace/botón — siempre hay UNA acción al lado del rojo. */
   accion: string
   destino: DestinoCosa
+  /** Dueño de la cosa cuando señala a UN analista (agrupada = ausente). */
+  vendedorId?: string
 }
 
 export interface TresCosasInput {
@@ -46,11 +51,19 @@ export interface TresCosasInput {
   esperaMasLargaReparto: number | null
   /** Métricas de agenda por analista (vacío = sin dato o sin rezago). */
   vendedoresAgenda: readonly MetricaAgendaVendedor[]
+  /**
+   * Seguimiento activo: leads cuya primera gestión ya venció, según
+   * `totales.primera_atencion` de crm.cola_accion_v2_fn (null/ausente = sin
+   * dato). La señal solo existe con el plazo vencido y su aviso es crítico
+   * por definición en private.sla_operacion_leads: si hay alguno, es rojo.
+   */
+  primeraGestionPendiente?: number | null
 }
 
 /** Peso del candidato dentro de su severidad (menor = primero). */
 const PESO: Record<CosaDeHoy['id'], number> = {
   sin_responder: 0,
+  primera_gestion: 0,
   no_asistio: 1,
   por_repartir: 2,
   sin_accion: 3,
@@ -64,11 +77,20 @@ const TOPE = 3
  * Devuelve [] cuando no hay nada que hacer O nada que decir con datos: la
  * franja entera no se pinta — el silencio también es información.
  */
-export function tresCosasDeHoy({
+export function tresCosasDeHoy(input: TresCosasInput): CosaDeHoy[] {
+  return candidatosDeHoy(input).slice(0, TOPE)
+}
+
+/**
+ * Todos los candidatos del día, ya ordenados (rojo primero, peso fijo), SIN
+ * el recorte a tres: lo que no entra en la franja va a «Esta semana».
+ */
+export function candidatosDeHoy({
   cola,
   totalPorRepartir,
   esperaMasLargaReparto,
   vendedoresAgenda,
+  primeraGestionPendiente,
 }: TresCosasInput): CosaDeHoy[] {
   const cosas: CosaDeHoy[] = []
 
@@ -91,6 +113,18 @@ export function tresCosasDeHoy({
     })
   }
 
+  // 1b · Seguimiento activo: la primera gestión vencida es la misma
+  //      interrupción del día, contada por el servidor.
+  if (primeraGestionPendiente != null && primeraGestionPendiente > 0) {
+    cosas.push({
+      id: 'primera_gestion',
+      severidad: 'critica',
+      texto: `${primeraGestionPendiente} ${primeraGestionPendiente === 1 ? 'primera gestión vencida' : 'primeras gestiones vencidas'}`,
+      accion: 'Ver',
+      destino: { tipo: 'vista', vista: 'seguimiento' },
+    })
+  }
+
   // 2 · No-show repetido — el otro rojo del presupuesto (≥2, umbral de la
   //     campana y de «Tu equipo hoy»). Con varios analistas se agrupa.
   // Solo ANALISTAS activos: el RPC también trae la fila del propio
@@ -110,6 +144,7 @@ export function tresCosasDeHoy({
         : `${conNoShow.length} analistas con citas sin asistir`,
       accion: 'Ver equipo',
       destino: { tipo: 'vista', vista: 'equipo' },
+      ...(conNoShow.length === 1 ? { vendedorId: peorNoShow.vendedor_id } : {}),
     })
   }
 
@@ -141,6 +176,7 @@ export function tresCosasDeHoy({
         : `${conSinAccion.length} analistas con leads sin próxima acción`,
       accion: 'Ver equipo',
       destino: { tipo: 'vista', vista: 'equipo' },
+      ...(conSinAccion.length === 1 ? { vendedorId: peorSinAccion.vendedor_id } : {}),
     })
   }
 
@@ -162,10 +198,8 @@ export function tresCosasDeHoy({
   }
 
   // Rojo primero, luego el peso fijo: el orden es una decisión, no un azar.
-  return cosas
-    .sort((a, b) => (
-      (a.severidad === b.severidad ? 0 : a.severidad === 'critica' ? -1 : 1)
-      || PESO[a.id] - PESO[b.id]
-    ))
-    .slice(0, TOPE)
+  return cosas.sort((a, b) => (
+    (a.severidad === b.severidad ? 0 : a.severidad === 'critica' ? -1 : 1)
+    || PESO[a.id] - PESO[b.id]
+  ))
 }
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
index b18f0e58..1fe60b1f 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor.tsx
@@ -25,19 +25,10 @@ import { SectionHead } from '@/components/common/section-head'
 import { DesglosePorEmpresa } from '@/components/app/cierres-externos-seccion'
 import { AccionesContacto } from '@/components/app/contacto'
 import { AgendaEquipoPanel } from './agenda-equipo'
+import { useDatosSupervisor } from './datos-supervisor'
 import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
 import { TresCosas } from './tres-cosas'
-import {
-  BUCKET_LABEL,
-  DIA_MS,
-  capitalPrincipal,
-  colorMeta,
-  diasSinActividad,
-  haceCortoTexto,
-  haceTexto,
-  indexarUltimaActividad,
-  pctMeta,
-} from '@/lib/inteligencia'
+import { BUCKET_LABEL, colorMeta, haceTexto } from '@/lib/inteligencia'
 import { TOPE_ESTANCADOS } from '@/lib/cola-accion'
 import {
   derivarNovedades,
@@ -49,37 +40,18 @@ import {
 } from '@/lib/visita-sin-movimiento'
 import { useSplashVisible } from '@/lib/splash-visible'
 import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
-import { fechaLima } from '@/lib/agenda-derivada'
-import {
-  capitalObjetivo,
-  metaVigente,
-  capitalReal,
-  metaConversionAplicable,
-  objetivosCero,
-  periodoLima,
-} from '@/lib/objetivos'
-import { useConversionMensual } from '@/data/crm-queries'
-import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'
-import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
-import { useAhora } from '@/lib/ahora'
-import { lecturaCobertura, totalConversionPublicable } from '@/lib/conversion-mensual'
 import { useAuth } from '@/lib/auth-context'
 import { useCRMData, usePanelesActions } from '@/lib/store-context'
-import { mensajeDeError } from '@/data/crm-api'
-import { useMetricasAgenda } from '@/data/crm-queries'
-import { money, moneyK, numero, porcentajeConversionCanonica } from '@/lib/format'
+import { moneyK, numero } from '@/lib/format'
 import { cn } from '@/lib/utils'
 import { hashDe } from '@/lib/router'
 import { tresCosasDeHoy } from '@/lib/tres-cosas'
 import { useEstadoSlaOperativo } from '@/data/use-estado-sla-operativo'
 import { useColaAccionOperativa } from '@/data/use-cola-accion-operativa'
-import { useMetricasVendedoresOperativas } from '@/data/use-metricas-vendedores-operativas'
 import { textoConversionOperativa } from '@/lib/metricas-vendedores'
-import { useResumenCarteraOperativo } from '@/data/use-resumen-cartera-operativo'
 import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
 import { DesgloseMonedas } from '@/components/common/desglose-monedas'
 import { rotuloTipoCambio, totalEnSoles } from '@/lib/capital-unificado'
-import { useTipoCambio } from '@/lib/tipo-cambio'
 
 // Tope de la cola del equipo: los primeros son la plata (colaDe ya ordena por
 // severidad); el resto vive tras "Ver los N pendientes" para que la Agenda del
@@ -98,9 +70,6 @@ const PESTANAS_COLA: ReadonlyArray<{ id: PestanaCola; label: string }> = [
   { id: 'todo', label: 'Todo' },
 ]
 
-// Texto neutro de una meta que gerencia todavía no fijó para el mes.
-const SIN_META = 'Sin meta fijada para este mes'
-
 /** Semáforo por días sin actividad: azul <2 · ámbar 2–5 · rojo >5. */
 function semaforoDias(d: number): string {
   if (d > 5) return SEMAFORO.critico
@@ -110,119 +79,46 @@ function semaforoDias(d: number): string {
 
 export function HoySupervisor(): JSX.Element {
   const modoSla = useModoSla()
-  const {
-    ambito,
-    actividades,
-    tareas,
-    objetivos,
-    objetivosError,
-    cumplimientoMetas,
-    cumplimientoMetasError,
-    recargar,
-    equipo,
-  } = useCRMData()
+  const { ambito, actividades, tareas, equipo } = useCRMData()
   const { abrirLead } = usePanelesActions()
   const { yo } = useAuth()
   // F1b: el reloj SLA solo alimenta el ESPEJO demo de la cola — en sesión real
   // esos vencimientos ya llegan resueltos dentro de cola_accion_fn, así que el
   // RPC de estado SLA ni se pide (habilitado = demo).
   const estadoSla = useEstadoSlaOperativo(ambito.leads, actividades, yo?.demo === true)
-  // Reloj vivo: tick por minuto y al volver a la pestaña — la bandeja y los
-  // "hace N" se refrescan solos al pasar el tiempo.
-  const ahora = useAhora()
-  const periodoVigente = periodoLima(ahora)
-  const periodoStoreIntentado = useRef<string | null>(null)
-  const [recargaPeriodoFallida, setRecargaPeriodoFallida] = useState(false)
-  const fotoMensualStoreVigente = yo?.demo === true || (
-    objetivos.periodo === periodoVigente
-    && (cumplimientoMetas == null || cumplimientoMetas.periodo === periodoVigente)
-  )
-  useEffect(() => {
-    if (yo?.demo || fotoMensualStoreVigente
-      || periodoStoreIntentado.current === periodoVigente) return
-    periodoStoreIntentado.current = periodoVigente
-    setRecargaPeriodoFallida(false)
-    void recargar().then((ok) => {
-      if (!ok) setRecargaPeriodoFallida(true)
-    })
-  }, [fotoMensualStoreVigente, periodoVigente, recargar, yo?.demo])
+  // Meta, reparto, agenda y tipo de cambio: derivación COMPARTIDA con el
+  // puesto de mando (./datos-supervisor.ts). Aquí queda lo propio del modo
+  // legado: la cola cola_accion_fn, sus pestañas y la visita F4.3.
+  const {
+    resumenOp,
+    resumen,
+    vendedoresOp,
+    rank,
+    tc,
+    capitalPronostico,
+    esperaMasLargaReparto,
+    totalPorRepartir,
+    detalleReparto,
+    etiquetaAccesoReparto,
+    cumplimientoMensual,
+    filasMeta,
+    hayErrorMensual,
+    reintentarMensual,
+    datosAgenda,
+    errorAgenda,
+    cargandoAgenda,
+    recargarAgenda,
+    rezagosAgenda,
+  } = useDatosSupervisor()
   // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
   const [colaExpandida, setColaExpandida] = useState(false)
   // Pestaña elegida a mano; `null` = automática (la primera con filas), así
   // un supervisor que entra por la mañana aterriza donde hay trabajo.
   const [pestanaElegida, setPestanaElegida] = useState<PestanaCola | null>(null)
 
-  // ── F1b: los agregados llegan del servidor (o del espejo demo vivo) ──
-  // resumen_cartera_fn → tiles de capital/activos/parkeados; cola_accion_fn →
-  // cola + estancados + tile "sin responder"; metricas_vendedores_fn → ranking.
-  const resumenOp = useResumenCarteraOperativo(ambito.leads, actividades)
-  const resumen = resumenOp.resumen
+  // cola_accion_fn → cola + estancados + tile "sin responder".
   const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
   const cola = colaOp.cola
-  const vendedoresOp = useMetricasVendedoresOperativas(ambito.vendedores, equipo, ambito.leads, actividades)
-  const rank = vendedoresOp.metricas?.filas ?? null
-  // TC izado UNA vez por pantalla: el hook no pasa por TanStack (sin cache ni
-  // dedupe), así que uno por fila multiplicaría las llamadas a la edge.
-  const { tc, recargar: recargarTipoCambio } = useTipoCambio()
-  const diaTipoCambio = fechaLima(ahora)
-  const diaTipoCambioAnterior = useRef(diaTipoCambio)
-  useEffect(() => {
-    if (diaTipoCambioAnterior.current === diaTipoCambio) return
-    diaTipoCambioAnterior.current = diaTipoCambio
-    recargarTipoCambio()
-  }, [diaTipoCambio, recargarTipoCambio])
-  // Pronóstico: `capitalPrincipal` (criterio compartido con Cartera/Pipeline),
-  // NUNCA un total mixto. Antes se fijaba PEN a mano y un equipo que vende en
-  // dólares se titulaba «S/ 0».
-  const capitalPronostico = resumen
-    ? capitalPrincipal(resumen.capital.asignado.pen, resumen.capital.asignado.usd)
-    : null
-  // HOY solo resume la bandeja; la operación completa vive en Derivar leads.
-  // Conservamos el índice local para resumir la espera observable del caso más
-  // rezagado sin añadir otra consulta; si no hubo actividad, parte del ingreso.
-  // Fase 3 «sin topes»: en sesión real el arranque ya no baja el registro de
-  // actividades, y sin él la «espera» de un parkeado caería a `creado_en`
-  // (un lead de 30 días parkeado hace una hora diría «30 días»; su
-  // `tenencia_desde` se anula al quedar sin analista). Antes que exagerar, en
-  // sesión real se omite la antigüedad: el conteo del RPC sigue siendo la
-  // verdad y el CTA lo dice sin cifra. En demo sigue el timeline del fixture.
-  const bandejaReparto = useMemo(() => {
-    const parkeados = ambito.leads.filter(
-      (l) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado' && l.vendedor_id == null,
-    )
-    const indice = indexarUltimaActividad(actividades)
-    return { parkeados, indice }
-  }, [ambito, actividades])
-
-  const esperaMasLargaReparto = useMemo(() => {
-    if (!yo?.demo) return null
-    if (bandejaReparto.parkeados.length === 0) return null
-    let maxima = 0
-    for (const lead of bandejaReparto.parkeados) {
-      maxima = Math.max(
-        maxima,
-        diasSinActividad(lead, actividades, ahora, bandejaReparto.indice),
-      )
-    }
-    return maxima
-  }, [actividades, ahora, bandejaReparto, yo?.demo])
-
-  // El conteo del RPC sigue siendo la autoridad. Si el detalle local aún no
-  // está disponible, el CTA conserva la verdad y omite la antigüedad.
-  const totalPorRepartir = resumen?.totales.parkeados ?? null
-  const hayPorRepartir = (totalPorRepartir ?? 0) > 0
-  const detalleReparto = totalPorRepartir == null
-    ? 'Sin dato por ahora · Ver derivaciones →'
-    : hayPorRepartir
-      ? esperaMasLargaReparto == null
-        ? 'Pendientes en tu bandeja · Repartir →'
-        : `Más rezagado: ${haceCortoTexto(esperaMasLargaReparto)} · Repartir →`
-      : 'Bandeja al día · Ver historial →'
-  const etiquetaAccesoReparto = totalPorRepartir == null
-    ? 'Ver derivaciones; total por repartir no disponible'
-    : hayPorRepartir
-      ? `Repartir ${totalPorRepartir} ${totalPorRepartir === 1 ? 'lead pendiente' : 'leads pendientes'}`
-      : 'Ver derivaciones; bandeja sin pendientes'
 
   // Nombres para los estancados del payload (el servidor no manda nombres de
   // personas): join con el roster completo, una sola vez por render.
@@ -319,178 +215,6 @@ export function HoySupervisor(): JSX.Element {
     if (vendedoresOp.error) void vendedoresOp.recargar()
   }
 
-  // La meta sale del snapshot cuando lo hay: si un analista se fue o cambió
-  // de equipo, su meta y su producción viajan juntas (ver `metaVigente`).
-  const fotoMensualStoreCargando = !yo?.demo
-    && !fotoMensualStoreVigente
-    && !recargaPeriodoFallida
-  const objetivosMensualesError = fotoMensualStoreVigente
-    ? objetivosError
-    : recargaPeriodoFallida
-  const cumplimientoMensualError = fotoMensualStoreVigente
-    ? cumplimientoMetasError
-    : recargaPeriodoFallida
-  const objetivosMensuales = fotoMensualStoreVigente
-    ? objetivos
-    : objetivosCero(periodoVigente)
-  const cumplimientoMensual = fotoMensualStoreVigente ? cumplimientoMetas : null
-  const meta = metaVigente(objetivosMensuales.supervisor, cumplimientoMensual?.supervisor ?? null)
-  const metaConversion = metaConversionAplicable(meta.conversionObjetivo, objetivosMensualesError)
-  const cumplimiento = cumplimientoMensual?.supervisor ?? null
-  const metaCapitalPen = capitalObjetivo(meta, 'PEN')
-  const metaCapitalUsd = capitalObjetivo(meta, 'USD')
-  const capitalConfirmadoPen = cumplimiento ? capitalReal(cumplimiento, 'PEN') : null
-  const capitalConfirmadoUsd = cumplimiento ? capitalReal(cumplimiento, 'USD') : null
-
-  // LA CONVERSIÓN DEL MES del EQUIPO — total del payload de alcance 'equipo'
-  // (crm.conversion_mensual_fn), no el cumplimiento: la definición acordada
-  // llega ya, sin esperar a la migración B (E1, plan §4bis). El total viene
-  // RECALCULADO del servidor (suma÷suma, jamás media de porcentajes).
-  const esDemoConversion = yo?.demo === true
-  const qConversionMensual = useConversionMensual(
-    !esDemoConversion,
-    periodoVigente,
-    'equipo',
-    yo?.id,
-  )
-  const conversionMensualCargando = !esDemoConversion
-    && qConversionMensual.isPending
-    && qConversionMensual.data === undefined
-  const conversionMensual = esDemoConversion
-    ? conversionMensualDemo(Date.now(), { alcance: 'equipo', actorId: yo?.id ?? 'd-sup1' })
-    : conversionMensualCargando
-      ? undefined
-      : (qConversionMensual.data ?? null)
-  const conversionMensualError = !esDemoConversion && qConversionMensual.isError
-  // Un mes INCOMPLETO se ve, marcado como provisional (decisión de Miguel
-  // 2026-08-14). La regla vive en `lecturaCobertura`, compartida con las otras
-  // tres pantallas que pintan esta misma cifra.
-  const lecturaConversion = lecturaCobertura(conversionMensual?.cobertura)
-  const totalConversion = totalConversionPublicable(conversionMensual)
-  const conversionConfirmada = totalConversion?.conversion_pct ?? null
-  const recibidosEquipo = totalConversion?.divisor ?? null
-  // ── Cumplimiento del mes ──────────────────────────────────────────────────
-  // PEN y USD ya NO van por separado: la meta se pacta en soles (el editor
-  // escribe todo en `nuevo/PEN`), así que la fila de dólares vivía en «Sin meta
-  // fijada» para siempre mientras el capital real en USD no movía ninguna
-  // barra. Se consolida con el MISMO tipo de cambio en numerador y denominador
-  // —comparar a tasas distintas es comparar peras con manzanas— igual que en el
-  // panel del analista y en el de gerencia.
-  const capitalConfirmado = totalEnSoles(capitalConfirmadoPen, capitalConfirmadoUsd, tc?.promedio)
-  const metaCapital = totalEnSoles(metaCapitalPen, metaCapitalUsd, tc?.promedio)
-  const hayDolares = (capitalConfirmadoUsd ?? 0) > 0 || metaCapitalUsd > 0
-  const tcEnVuelo = tc === undefined && hayDolares
-  const tcCaido = tc === null && hayDolares
-  const ajusteCierre = cumplimiento?.ajuste
-  const notaAjusteCierre = ajusteCierre != null && (
-    ajusteCierre.aplicadoPen > 0
-    || ajusteCierre.aplicadoUsd > 0
-    || ajusteCierre.contratosAplicados > 0
-  )
-    ? [
-        'Neto tras ajuste de cierre',
-        ajusteCierre.aplicadoPen > 0 ? `−${money(ajusteCierre.aplicadoPen, 'PEN')}` : null,
-        ajusteCierre.aplicadoUsd > 0 ? `−${money(ajusteCierre.aplicadoUsd, 'USD')}` : null,
-        ajusteCierre.contratosAplicados > 0
-          ? `−${numero(ajusteCierre.contratosAplicados)} ${ajusteCierre.contratosAplicados === 1 ? 'contrato' : 'contratos'}`
-          : null,
-      ].filter(Boolean).join(' · ')
-    : null
-  const notaCapitalMonedas = !tcEnVuelo && (capitalConfirmadoUsd ?? 0) > 0
-    ? `${moneyK(capitalConfirmadoPen ?? 0, 'PEN')} + ${moneyK(capitalConfirmadoUsd ?? 0, 'USD')}`
-      + (capitalConfirmado.tc == null
-        ? ' · sin tipo de cambio: el total NO incluye los dólares'
-        : ` · ${rotuloTipoCambio(capitalConfirmado.tc, tc?.fuente ?? 'TC del día')}`)
-    : null
-  const filasMeta: Array<{
-    label: string
-    txt: string
-    pct: number
-    sinDato: string | null
-    nota?: string | null
-  }> = [
-    {
-      label: 'Capital confirmado',
-      txt:
-        tcEnVuelo
-          ? 'Calculando…'
-          : (metaCapital.total ?? 0) > 0 && capitalConfirmado.total != null
-          ? `${moneyK(capitalConfirmado.total, 'PEN')} de ${moneyK(metaCapital.total ?? 0, 'PEN')}`
-          : capitalConfirmado.total == null ? '—' : moneyK(capitalConfirmado.total, 'PEN'),
-      pct: tcEnVuelo ? 0 : pctMeta(capitalConfirmado.total ?? 0, metaCapital.total ?? 0),
-      // El desglose solo aporta cuando hay dólares; si no, repetiría el total.
-      nota: [notaCapitalMonedas, notaAjusteCierre].filter(Boolean).join(' · ') || null,
-      sinDato: fotoMensualStoreCargando
-        ? 'Actualizando la meta y el cumplimiento de este mes…'
-        : objetivosMensualesError
-        ? 'Meta mensual no disponible'
-        : tcEnVuelo
-          ? 'Consultando el tipo de cambio para consolidar los dólares…'
-          : (metaCapital.total ?? 0) <= 0
-            ? SIN_META
-            : cumplimientoMensualError || capitalConfirmado.total == null
-              ? 'Cumplimiento confirmado no disponible'
-              : null,
-    },
-    {
-      label: 'Conversión del mes',
-      txt:
-        conversionMensualCargando
-          ? 'Calculando…'
-          : conversionConfirmada == null
-          ? '—'
-          : metaConversion != null
-            ? `${porcentajeConversionCanonica(conversionConfirmada)} de ${metaConversion}% · ${numero(recibidosEquipo)} recibidos`
-            : `${porcentajeConversionCanonica(conversionConfirmada)} · ${numero(recibidosEquipo)} recibidos`,
-      // El porqué de que la cifra no sea definitiva viaja PEGADO a ella. Antes
-      // esto la sustituía, y un mes con recibidos y cierres decía «sin datos».
-      nota: lecturaConversion.aviso,
-      pct: pctMeta(conversionConfirmada ?? 0, metaConversion ?? 0),
-      sinDato: conversionMensualCargando
-        ? 'Consultando la conversión del mes…'
-        : conversionMensualError
-          ? 'Conversión del mes no disponible'
-          : !lecturaConversion.mostrar
-          ? (lecturaConversion.aviso ?? 'Sin datos de asignación para este mes')
-          : conversionConfirmada == null
-            ? 'Sin leads recibidos este mes'
-            : fotoMensualStoreCargando
-              ? 'Actualizando la meta de este mes…'
-              : objetivosMensualesError
-              ? 'Meta mensual no disponible'
-              : metaConversion == null
-                ? SIN_META
-                : null,
-    },
-  ]
-
-  // ── Fase F — Agenda del equipo (RPC crm.metricas_agenda_fn) ──
-  // Periodo fijo: últimos 7 días con el reloj vivo (se corre solo al pasar la
-  // medianoche de Lima). En demo se alimenta del fixture sin tocar la red.
-  const sesionReal = Boolean(yo && !yo.demo)
-  const hastaMA = fechaLima(ahora)
-  const desdeMA = fechaLima(ahora - 6 * DIA_MS)
-  const consultaAgenda = useMetricasAgenda(sesionReal, desdeMA, hastaMA)
-  // En sesión real con data aún undefined y sin error, viaja undefined a
-  // propósito: el panel muestra su estado de carga.
-  const datosAgenda = sesionReal ? consultaAgenda.data : metricasAgendaDemo(desdeMA, hastaMA)
-  const errorAgenda =
-    sesionReal && consultaAgenda.error
-      ? mensajeDeError(
-          consultaAgenda.error,
-          'No pudimos consultar la agenda del equipo. Revisa tu conexión e inténtalo otra vez.',
-        )
-      : null
-  const cargandoAgenda =
-    sesionReal && (consultaAgenda.isPending || consultaAgenda.isFetching)
-  // Rezagos de agenda por miembro (vendedor_id → métrica) para que la señal de
-  // vencidas / sin acción / no-shows viva DENTRO de la fila de "Tu equipo hoy":
-  // la persona se juzga en un solo lugar, sin cruzar a la tabla de la izquierda.
-  const rezagosAgenda = useMemo(
-    () => new Map((datosAgenda?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
-    [datosAgenda],
-  )
-
   // ── F3: «Hoy, tres cosas» — el sistema prioriza el día (ley de Tesler). ──
   // Mismas fuentes que ya están en pantalla; sin dato no hay tarjeta.
   const cosas = useMemo(
@@ -856,9 +580,7 @@ export function HoySupervisor(): JSX.Element {
             cargando={cargandoAgenda}
             error={errorAgenda}
             modoDemo={yo?.demo === true}
-            onReintentar={() => {
-              if (sesionReal) void consultaAgenda.refetch()
-            }}
+            onReintentar={recargarAgenda}
             equipo={equipo}
           />
         </div>
@@ -1001,21 +723,8 @@ export function HoySupervisor(): JSX.Element {
               <p className="text-[10.5px] text-muted-foreground">
                 El capital en dólares entra al total convertido a tipo de cambio real. El capital abierto de arriba es pronóstico y no cuenta como cumplimiento.
               </p>
-              {(objetivosMensualesError || cumplimientoMensualError || conversionMensualError || tcCaido) && (
-                <Button
-                  variant="ghost"
-                  size="sm"
-                  onClick={() => {
-                    if (objetivosMensualesError || cumplimientoMensualError) {
-                      setRecargaPeriodoFallida(false)
-                      void recargar().then((ok) => {
-                        if (!ok && !fotoMensualStoreVigente) setRecargaPeriodoFallida(true)
-                      })
-                    }
-                    if (conversionMensualError) void qConversionMensual.refetch()
-                    if (tcCaido) recargarTipoCambio()
-                  }}
-                >
+              {hayErrorMensual && (
+                <Button variant="ghost" size="sm" onClick={reintentarMensual}>
                   Reintentar
                 </Button>
               )}
```

## `app/src/screens/hoy/supervisor-mando.tsx` (archivo NUEVO completo)
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
    14	import { useId, useMemo, useState, type JSX } from 'react'
    15	import { ChevronRight, ListChecks, RefreshCw, UsersRound } from 'lucide-react'
    16	import { Card, CardContent } from '@/components/ui/card'
    17	import { Avatar } from '@/components/ui/avatar'
    18	import { Badge } from '@/components/ui/badge'
    19	import { Button } from '@/components/ui/button'
    20	import { SectionHead } from '@/components/common/section-head'
    21	import { AccionesContacto } from '@/components/app/contacto'
    22	import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
    23	import { DesgloseMonedas } from '@/components/common/desglose-monedas'
    24	import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
    25	import { estadoCasoSupervision, momentoCaso } from '@/lib/cola-supervision'
    26	import { conteoSemaforoEquipo, lecturaAnalista, type LecturaAnalista } from '@/lib/senal-equipo'
    27	import { haceTexto } from '@/lib/inteligencia'
    28	import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
    29	import { textoConversionOperativa } from '@/lib/metricas-vendedores'
    30	import { totalEnSoles } from '@/lib/capital-unificado'
    31	import { moneyK, numero, primerNombre } from '@/lib/format'
    32	import { hashDe } from '@/lib/router'
    33	import { cn } from '@/lib/utils'
    34	import { usePanelesActions } from '@/lib/store-context'
    35	import type { FiltrosSla } from '@/lib/sla-operacion'
    36	import { HoySupervisor } from './supervisor'
    37	import { useDatosSupervisor } from './datos-supervisor'
    38	
    39	/** Filas de la vista previa: lo demás vive en el módulo Seguimiento. */
    40	const COLA_VISIBLES = 7
    41	
    42	type PestanaMando = 'pendientes' | 'primera_atencion' | 'tareas_vencidas' | 'todas'
    43	const PESTANAS: ReadonlyArray<{ id: PestanaMando; label: string }> = [
    44	  { id: 'pendientes', label: 'Para atender ahora' },
    45	  { id: 'primera_atencion', label: 'Primera gestión' },
    46	  { id: 'tareas_vencidas', label: 'Tareas vencidas' },
    47	  { id: 'todas', label: 'Todas' },
    48	]
    49	const VACIO_PESTANA: Record<PestanaMando, string> = {
    50	  pendientes: 'Nada para atender ahora: el equipo no tiene pendientes vencidos.',
    51	  primera_atencion: 'Ninguna primera gestión vencida.',
    52	  tareas_vencidas: 'Ninguna tarea vencida.',
    53	  todas: 'Sin oportunidades con acciones en el seguimiento.',
    54	}
    55	
    56	/** Chip de señal: el ámbar suave usa el token de TEXTO (el hex puro no llega a 4.5:1 sobre su tinte). */
    57	function ChipSenal({ texto, nivel }: { texto: string; nivel: 'critico' | 'atencion' }): JSX.Element {
    58	  return nivel === 'critico'
    59	    ? <Badge color={SEMAFORO.critico} variant="solid">{texto}</Badge>
    60	    : <Badge color="var(--warning-text)">{texto}</Badge>
    61	}
    62	
    63	const COLOR_NIVEL: Record<NonNullable<LecturaAnalista['nivel']>, string> = {
    64	  critico: SEMAFORO.critico,
    65	  atencion: SEMAFORO.atencion,
    66	  neutro: SEMAFORO.neutro,
    67	}
    68	
    69	export function HoySupervisorMando(): JSX.Element {
    70	  const modo = useModoSla()
    71	  if (modo.legado) return <HoySupervisor />
    72	  // Cambiar de revisión del seguimiento remonta la pantalla: ningún filtro ni
    73	  // selección de la revisión anterior sobrevive sobre datos de otra.
    74	  return <PuestoDeMando key={String(modo.data?.control_revision ?? 'sin-revision')} />
    75	}
    76	
    77	function PuestoDeMando(): JSX.Element {
    78	  const modo = useModoSla()
    79	  const datos = useDatosSupervisor()
    80	  const { abrirLead } = usePanelesActions()
    81	  const { ambito, rank, tc, ahora } = datos
    82	  const idPanelCola = useId()
    83	
    84	  const [pestana, setPestana] = useState<PestanaMando>('pendientes')
    85	  const [analistaId, setAnalistaId] = useState<string | null>(null)
    86	  const [anuncio, setAnuncio] = useState('')
    87	  const [abriendo, setAbriendo] = useState<string | null>(null)
    88	  const [errorApertura, setErrorApertura] = useState(false)
    89	
    90	  const filtros: FiltrosSla = { senal: pestana, etapa: null, analista_id: analistaId }
    91	  const consultaCola = useColaSlaPagina(filtros, null, COLA_VISIBLES, modo.activo)
    92	  // Fail-closed: TanStack conserva la última respuesta tras un refetch
    93	  // fallido; con error, la cola NO se muestra como vigente.
    94	  const pagina = consultaCola.error ? undefined : consultaCola.data
    95	  const paginaVigente = pagina?.modo === 'activo' ? pagina : undefined
    96	
    97	  // El store es caché PARCIAL: un lead ausente es «desconocido», no «sin
    98	  // monto» ni «sin teléfono». Contacto y monto solo con el lead completo.
    99	  const leadPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l] as const)), [ambito.leads])
   100	  // Analistas del equipo (no las filas cargadas): los chips no dependen de
   101	  // lo que haya traído la página y no prometen conteos del lado cliente.
   102	  const analistas = useMemo(
   103	    () => ambito.vendedores
   104	      .filter((m) => m.activo && m.rol_crm === 'vendedor')
   105	      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
   106	    [ambito.vendedores],
   107	  )
   108	  const nombreAnalista = analistaId != null
   109	    ? ambito.vendedores.find((m) => m.perfil_id === analistaId)?.nombre_completo ?? null
   110	    : null
   111	
   112	  const elegirAnalista = (id: string | null) => {
   113	    const siguiente = id === analistaId ? null : id
   114	    setAnalistaId(siguiente)
   115	    const nombre = siguiente == null ? null : ambito.vendedores.find((m) => m.perfil_id === siguiente)?.nombre_completo
   116	    setAnuncio(nombre ? `Mostrando los pendientes de ${primerNombre(nombre)}` : 'Mostrando los pendientes de todo el equipo')
   117	  }
   118	  const elegirPestana = (id: PestanaMando) => {
   119	    setPestana(id)
   120	    setErrorApertura(false)
   121	  }
   122	
   123	  async function abrirFicha(id: string) {
   124	    if (abriendo) return
   125	    setAbriendo(id)
   126	    setErrorApertura(false)
   127	    try {
   128	      if (await abrirLead(id) === false) setErrorApertura(true)
   129	    } catch {
   130	      setErrorApertura(true)
   131	    } finally {
   132	      setAbriendo(null)
   133	    }
   134	  }
   135	
   136	  const conteoPestana = (id: PestanaMando): number | null => {
   137	    if (!paginaVigente) return null
   138	    if (id === 'todas') return pestana === 'todas' ? paginaVigente.total_items : null
   139	    return paginaVigente.totales[id]
   140	  }
   141	
   142	  // ── Equipo hoy: UNA lectura por analista alimenta punto, cabecera y chips ──
   143	  const rezagosConfirmados = useMemo(
   144	    () => new Map((datos.agendaConfirmada?.vendedores ?? []).map((v) => [v.vendedor_id, v] as const)),
   145	    [datos.agendaConfirmada],
   146	  )
   147	  const lecturas = useMemo(
   148	    () => new Map((rank ?? []).map((r) => [r.m.perfil_id, lecturaAnalista(r, rezagosConfirmados.get(r.m.perfil_id))] as const)),
   149	    [rank, rezagosConfirmados],
   150	  )
   151	  const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])
   152	
   153	  const errorIndicadores = !datos.sesionReal
   154	    ? false
   155	    : Boolean(datos.resumenOp.error || datos.vendedoresOp.error)
   156	  const reintentarIndicadores = () => {
   157	    if (datos.resumenOp.error) void datos.resumenOp.recargar()
   158	    if (datos.vendedoresOp.error) void datos.vendedoresOp.recargar()
   159	  }
   160	
   161	  const tituloCola = nombreAnalista ? `Pendientes de ${primerNombre(nombreAnalista)}` : 'Pendientes del equipo'
   162	
   163	  return (
   164	    <div className="mx-auto flex max-w-[1376px] flex-col gap-4 ac-rise">
   165	      <p className="sr-only" role="status" aria-live="polite">{anuncio}</p>
   166	
   167	      <AvisoDegradacion
   168	        activo={errorIndicadores}
   169	        queReintenta="de los indicadores del equipo"
   170	        onReintentar={reintentarIndicadores}
   171	      >
   172	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   173	      </AvisoDegradacion>
   174	
   175	      {/* ── 2 · Cola del seguimiento + Equipo hoy ── */}
   176	      <div className="grid gap-4 lg:grid-cols-5">
   177	        <Card className="flex min-w-0 flex-col overflow-hidden lg:col-span-3">
   178	          <SectionHead icon={ListChecks} title={tituloCola} />
   179	          {!modo.activo ? (
   180	            <CardContent className="pb-5 pt-0">
   181	              {modo.error ? (
   182	                <div role="alert" className="flex flex-wrap items-center justify-between gap-3">
   183	                  <p className="text-sm">No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.</p>
   184	                  <Button variant="outline" size="sm" onClick={() => void modo.refetch()}>
   185	                    <RefreshCw aria-hidden /> Reintentar
   186	                  </Button>
   187	                </div>
   188	              ) : (
   189	                <p role="status" className="text-sm text-muted-foreground">Consultando el seguimiento comercial…</p>
   190	              )}
   191	            </CardContent>
   192	          ) : (
   193	            <>
   194	              <div className="flex flex-wrap items-center gap-2 px-5 pb-2.5">
   195	                <div role="tablist" aria-label="Filtrar los pendientes" className="inline-flex flex-wrap rounded-lg bg-muted/60 p-0.5">
   196	                  {PESTANAS.map((p, indice) => {
   197	                    const n = conteoPestana(p.id)
   198	                    return (
   199	                      <button
   200	                        key={p.id}
   201	                        id={`${idPanelCola}-tab-${p.id}`}
   202	                        type="button"
   203	                        role="tab"
   204	                        aria-selected={pestana === p.id}
   205	                        aria-controls={`${idPanelCola}-panel`}
   206	                        aria-label={n == null ? p.label : `${p.label}: ${numero(n)}`}
   207	                        tabIndex={pestana === p.id ? 0 : -1}
   208	                        onClick={() => elegirPestana(p.id)}
   209	                        onKeyDown={(e) => {
   210	                          const destino = e.key === 'ArrowRight' ? (indice + 1) % PESTANAS.length
   211	                            : e.key === 'ArrowLeft' ? (indice - 1 + PESTANAS.length) % PESTANAS.length
   212	                            : e.key === 'Home' ? 0 : e.key === 'End' ? PESTANAS.length - 1 : null
   213	                          if (destino == null) return
   214	                          e.preventDefault()
   215	                          const siguiente = PESTANAS[destino]
   216	                          if (!siguiente) return
   217	                          elegirPestana(siguiente.id)
   218	                          document.getElementById(`${idPanelCola}-tab-${siguiente.id}`)?.focus()
   219	                        }}
   220	                        className={cn(
   221	                          'min-h-9 cursor-pointer rounded-md px-3 text-xs font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   222	                          pestana === p.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground-strong hover:text-foreground',
   223	                        )}
   224	                      >
   225	                        {p.label}{n != null && <span aria-hidden> {numero(n)}</span>}
   226	                      </button>
   227	                    )
   228	                  })}
   229	                </div>
   230	              </div>
   231	
   232	              {analistas.length > 0 && (
   233	                <div role="group" aria-label="Filtrar por analista" className="flex flex-wrap items-center gap-1.5 px-5 pb-3">
   234	                  <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground-strong" aria-hidden>Analista</span>
   235	                  <button
   236	                    type="button"
   237	                    aria-pressed={analistaId == null}
   238	                    onClick={() => elegirAnalista(null)}
   239	                    className={cn(
   240	                      'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   241	                      analistaId == null ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   242	                    )}
   243	                  >
   244	                    Todos
   245	                  </button>
   246	                  {analistas.map((m) => (
   247	                    <button
   248	                      key={m.perfil_id}
   249	                      type="button"
   250	                      aria-pressed={analistaId === m.perfil_id}
   251	                      aria-label={m.nombre_completo}
   252	                      onClick={() => elegirAnalista(m.perfil_id)}
   253	                      className={cn(
   254	                        'min-h-9 cursor-pointer rounded-full px-3 text-xs font-semibold transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   255	                        analistaId === m.perfil_id ? 'bg-primary text-primary-foreground' : 'border border-border bg-card text-muted-foreground-strong hover:text-foreground',
   256	                      )}
   257	                    >
   258	                      {primerNombre(m.nombre_completo)}
   259	                    </button>
   260	                  ))}
   261	                </div>
   262	              )}
   263	
   264	              {abriendo && <p role="status" className="px-5 pb-2 text-xs text-muted-foreground">Abriendo ficha…</p>}
   265	              {errorApertura && <p role="alert" className="px-5 pb-2 text-xs text-destructive-text">No se pudo abrir la ficha. Vuelve a intentarlo.</p>}
   266	
   267	              <div
   268	                id={`${idPanelCola}-panel`}
   269	                role="tabpanel"
   270	                aria-labelledby={`${idPanelCola}-tab-${pestana}`}
   271	                tabIndex={paginaVigente && paginaVigente.items.length > 0 ? undefined : 0}
   272	                className="flex flex-1 flex-col"
   273	              >
   274	                {consultaCola.error ? (
   275	                  <div role="alert" className="flex flex-wrap items-center justify-between gap-3 border-t border-border/60 px-5 py-4">
   276	                    <p className="text-sm">No se pudo cargar la cola. Los pendientes todavía no están confirmados.</p>
   277	                    <Button variant="outline" size="sm" onClick={() => void consultaCola.refetch()}>
   278	                      <RefreshCw aria-hidden /> Reintentar
   279	                    </Button>
   280	                  </div>
   281	                ) : !pagina ? (
   282	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">Cargando los pendientes del equipo…</p>
   283	                ) : !paginaVigente ? (
   284	                  <p role="status" className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   285	                    Las reglas del seguimiento cambiaron. Actualiza la pantalla para ver el modo vigente.
   286	                  </p>
   287	                ) : paginaVigente.items.length === 0 ? (
   288	                  <p className="border-t border-border/60 px-5 py-4 text-sm text-muted-foreground">
   289	                    {nombreAnalista ? `${primerNombre(nombreAnalista)} no tiene casos aquí.` : VACIO_PESTANA[pestana]}
   290	                  </p>
   291	                ) : (
   292	                  <ul aria-label={`${tituloCola}: ${PESTANAS.find((p) => p.id === pestana)?.label ?? ''}`} aria-busy={consultaCola.isFetching || abriendo !== null}>
   293	                    {paginaVigente.items.map((item) => {
   294	                      const leadStore = leadPorId.get(item.lead_id)
   295	                      const colorTira = item.severidad === 'baja' ? 'transparent' : SEV_COLOR[item.severidad]
   296	                      const analistaFila = item.lead.analista_nombre ? primerNombre(item.lead.analista_nombre) : 'Sin analista'
   297	                      const estado = `${estadoCasoSupervision(item.bucket)} · ${momentoCaso(item.bucket, item.referencia_en, ahora)}`
   298	                      const monto = leadStore?.monto_estimado != null ? moneyK(leadStore.monto_estimado, leadStore.moneda) : null
   299	                      return (
   300	                        <li
   301	                          key={item.lead_id}
   302	                          data-sev={item.severidad}
   303	                          className="flex items-center gap-2 border-l-[3px] border-t border-t-border/60 pr-5"
   304	                          style={{ borderLeftColor: colorTira }}
   305	                        >
   306	                          <button
   307	                            type="button"
   308	                            disabled={abriendo !== null}
   309	                            onClick={() => void abrirFicha(item.lead_id)}
   310	                            // El nombre dicta TODO lo visible (dueño, estado, tiempo, monto):
   311	                            // un lector de pantalla no puede perder lo que se ve.
   312	                            aria-label={`Abrir ficha de ${item.lead.nombre_completo}, de ${analistaFila}: ${estado}${monto ? `, ${monto}` : ''}`}
   313	                            className="flex min-h-[52px] min-w-0 flex-1 cursor-pointer items-center gap-3.5 py-2 pl-[17px] text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40 disabled:cursor-wait"
   314	                          >
   315	                            {analistaId == null && (
   316	                              <span className="flex w-[118px] shrink-0 items-center gap-2">
   317	                                <span aria-hidden><Avatar nombre={item.lead.analista_nombre} className="size-[26px] text-[10px]" /></span>
   318	                                <span className="truncate text-xs font-semibold text-muted-foreground-strong">{analistaFila}</span>
   319	                              </span>
   320	                            )}
   321	                            <span className="min-w-0 flex-1 leading-tight">
   322	                              <span className="block truncate text-sm font-semibold">{item.lead.nombre_completo}</span>
   323	                              <span className="block truncate text-xs text-muted-foreground">{estado}</span>
   324	                            </span>
   325	                            {monto && <span className="shrink-0 text-right text-[13px] font-semibold tabular-nums">{monto}</span>}
   326	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   327	                          </button>
   328	                          {leadStore && <AccionesContacto lead={leadStore} compacto />}
   329	                        </li>
   330	                      )
   331	                    })}
   332	                  </ul>
   333	                )}
   334	                <div className="mt-auto flex items-center justify-between gap-3 border-t border-border/60 px-5 py-2.5 text-xs">
   335	                  <span className="tabular-nums text-muted-foreground-strong">
   336	                    {paginaVigente && paginaVigente.items.length > 0
   337	                      ? `${numero(paginaVigente.items.length)} de ${numero(paginaVigente.total_items)}`
   338	                      : ''}
   339	                  </span>
   340	                  <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-1 rounded-md px-2 font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   341	                    Ver todo en Seguimiento <ChevronRight className="size-3.5" aria-hidden />
   342	                  </a>
   343	                </div>
   344	              </div>
   345	            </>
   346	          )}
   347	        </Card>
   348	
   349	        {/* ── Equipo hoy: tocar a alguien filtra la cola y despliega sus señales ── */}
   350	        <Card className="min-w-0 overflow-hidden lg:col-span-2">
   351	          <SectionHead
   352	            icon={UsersRound}
   353	            title="Equipo hoy"
   354	            right={(
   355	              <a href={hashDe('gestion-diaria')} className="inline-flex min-h-9 items-center rounded-md px-1 text-xs font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   356	                Mi equipo hoy →
   357	              </a>
   358	            )}
   359	          />
   360	          {rank != null && rank.length > 0 && (
   361	            <p className="-mt-2 px-5 pb-2 text-xs text-muted-foreground-strong">
   362	              {semaforoEquipo.rojo === 0 && semaforoEquipo.ambar === 0
   363	                ? 'Sin alertas en el equipo'
   364	                : `${numero(semaforoEquipo.rojo)} en rojo · ${numero(semaforoEquipo.ambar)} en ámbar`}
   365	            </p>
   366	          )}
   367	          {datos.errorAgenda && (
   368	            <div role="alert" className="mx-5 mb-2 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-warning-text/30 bg-warning-text/5 px-3 py-2">
   369	              <p className="text-xs">La agenda del equipo no respondió: las citas y tareas de cada analista no se están midiendo.</p>
   370	              <Button variant="outline" size="sm" onClick={datos.recargarAgenda}>
   371	                <RefreshCw aria-hidden /> Reintentar
   372	              </Button>
   373	            </div>
   374	          )}
   375	          {rank == null ? (
   376	            <CardContent className="pb-5 pt-0">
   377	              <p className="text-sm text-muted-foreground">
   378	                {datos.vendedoresOp.error
   379	                  ? 'El resumen por analista no está disponible en este momento.'
   380	                  : 'Cargando el resumen por analista…'}
   381	              </p>
   382	            </CardContent>
   383	          ) : rank.length === 0 ? (
   384	            <CardContent className="pb-5 pt-0">
   385	              <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   386	            </CardContent>
   387	          ) : (
   388	            <ul aria-label="Analistas del equipo" className="border-t border-border/60">
   389	              {rank.map((r) => {
   390	                const id = r.m.perfil_id
   391	                const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
   392	                const rezago = rezagosConfirmados.get(id)
   393	                const abierto = analistaId === id
   394	                const principal = lectura.senales[0]?.texto
   395	                  ?? (r.activos === 0
   396	                    ? 'Sin leads abiertos'
   397	                    : rezago != null ? 'Al día' : `Última actividad ${haceTexto(r.diasSinActividadMax)}`)
   398	                const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   399	                const idDetalle = `${idPanelCola}-equipo-${id}`
   400	                const conversion = r.conversion == null
   401	                  ? r.conversionDisponible && r.divisorConversion === 0 ? 'sin divisor mensual' : 'conversión no disponible'
   402	                  : `${textoConversionOperativa(r.conversion)} conversión`
   403	                return (
   404	                  <li key={id} className="border-b border-border/60 last:border-b-0">
   405	                    <button
   406	                      type="button"
   407	                      aria-expanded={abierto}
   408	                      aria-controls={idDetalle}
   409	                      aria-label={`${r.m.nombre_completo}: ${principal}. Capital en proceso ${cap.total != null ? moneyK(cap.total) : 'sin dato'}. ${abierto ? 'Mostrando sus pendientes' : 'Ver sus pendientes'}`}
   410	                      onClick={() => elegirAnalista(id)}
   411	                      className={cn(
   412	                        'flex min-h-[52px] w-full cursor-pointer items-center gap-2.5 px-5 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40',
   413	                        abierto && 'bg-accent/[0.08]',
   414	                      )}
   415	                    >
   416	                      {lectura.nivel != null
   417	                        ? <span data-testid="equipo-semaforo" data-nivel={lectura.nivel} className="size-2 shrink-0 rounded-full" style={{ background: COLOR_NIVEL[lectura.nivel] }} aria-hidden />
   418	                        : <span className="size-2 shrink-0" aria-hidden />}
   419	                      <span aria-hidden><Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-[30px] text-[10px]" /></span>
   420	                      <span className="min-w-0 flex-1 leading-tight">
   421	                        <span className="block truncate text-[13.5px] font-bold">{r.m.nombre_completo}</span>
   422	                        <span className="block truncate text-xs text-muted-foreground-strong">{principal}</span>
   423	                      </span>
   424	                      <span className="shrink-0 text-right leading-tight">
   425	                        <span className="block text-[13.5px] font-extrabold tabular-nums">{cap.total != null ? moneyK(cap.total) : '—'}</span>
   426	                        <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
   427	                      </span>
   428	                      <ChevronRight className={cn('size-3.5 shrink-0 transition-transform', abierto ? '-rotate-90 text-accent' : 'rotate-90 text-muted-foreground')} aria-hidden />
   429	                    </button>
   430	                    <div id={idDetalle} hidden={!abierto} className="space-y-1.5 px-5 pb-3 pl-[62px]">
   431	                      {lectura.senales.length > 1 && (
   432	                        <div className="flex flex-wrap gap-1.5">
   433	                          {lectura.senales.slice(1).map((s) => <ChipSenal key={s.texto} texto={s.texto} nivel={s.nivel} />)}
   434	                        </div>
   435	                      )}
   436	                      <p className="text-xs tabular-nums text-muted-foreground-strong">
   437	                        {numero(r.activos)} activos · {conversion}
   438	                        {r.operacionesCartera != null && r.operacionesCartera > 0 ? ` · ${numero(r.operacionesCartera)} de cartera` : ''}
   439	                        {r.sinTocar > 0 ? ` · ${numero(r.sinTocar)} sin tocar` : ''}
   440	                      </p>
   441	                      {rezago != null && (
   442	                        <p className="text-xs tabular-nums text-muted-foreground-strong">
   443	                          {rezago.toques > 0
   444	                            ? `${numero(rezago.toques)} toques en 7 días${rezago.pct_completadas != null ? ` · ${Math.round(rezago.pct_completadas)} % completadas` : ''}`
   445	                            : 'Sin toques registrados en 7 días'}
   446	                        </p>
   447	                      )}
   448	                    </div>
   449	                  </li>
   450	                )
   451	              })}
   452	            </ul>
   453	          )}
   454	        </Card>
   455	      </div>
   456	    </div>
   457	  )
   458	}
```

## `app/src/screens/hoy/datos-supervisor.ts` (archivo NUEVO completo)
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

## `app/src/lib/senal-equipo.ts` (archivo NUEVO completo)
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
    13	// La severidad del analista es la PEOR de sus señales: nunca se rebaja.
    14	import type { MetricaAgendaVendedor } from './metricas-agenda'
    15	import { haceTexto } from './inteligencia'
    16	
    17	export type NivelSenal = 'critico' | 'atencion'
    18	
    19	export interface SenalAnalista {
    20	  texto: string
    21	  nivel: NivelSenal
    22	}
    23	
    24	export interface LecturaAnalista {
    25	  /** null = sin señal · 'neutro' = sin cartera abierta: no hay nada que medir. */
    26	  nivel: NivelSenal | 'neutro' | null
    27	  /** Rojas primero; dentro de cada nivel, el orden fijo de arriba. */
    28	  senales: SenalAnalista[]
    29	}
    30	
    31	export type RezagoAgenda = Pick<MetricaAgendaVendedor, 'no_asistio' | 'leads_sin_accion' | 'vencidas'>
    32	
    33	/**
    34	 * `rezago` null = la agenda no llegó (o el analista no tiene fila): solo se
    35	 * juzga lo que hay, sin inventar «al día».
    36	 */
    37	export function lecturaAnalista(
    38	  fila: { activos: number; diasSinActividadMax: number },
    39	  rezago: RezagoAgenda | null | undefined,
    40	): LecturaAnalista {
    41	  if (fila.activos === 0) return { nivel: 'neutro', senales: [] }
    42	  const senales: SenalAnalista[] = []
    43	  if (rezago != null && rezago.no_asistio >= 2) {
    44	    senales.push({ texto: `${rezago.no_asistio} citas sin asistir`, nivel: 'critico' })
    45	  }
    46	  if (rezago != null && rezago.leads_sin_accion > 0) {
    47	    const n = rezago.leads_sin_accion
    48	    senales.push({
    49	      texto: `${n} ${n === 1 ? 'lead' : 'leads'} sin próxima acción`,
    50	      nivel: n >= 5 ? 'critico' : 'atencion',
    51	    })
    52	  }
    53	  const dias = fila.diasSinActividadMax
    54	  if (dias >= 2) {
    55	    senales.push({ texto: `Un lead sin actividad ${haceTexto(dias)}`, nivel: dias > 5 ? 'critico' : 'atencion' })
    56	  }
    57	  if (rezago != null && rezago.vencidas > 0) {
    58	    const n = rezago.vencidas
    59	    senales.push({ texto: `${n} ${n === 1 ? 'tarea vencida' : 'tareas vencidas'}`, nivel: 'atencion' })
    60	  }
    61	  // sort estable: las rojas suben y cada nivel conserva el orden de arriba.
    62	  senales.sort((a, b) => (a.nivel === b.nivel ? 0 : a.nivel === 'critico' ? -1 : 1))
    63	  const nivel = senales.length === 0 ? null : senales[0]?.nivel ?? null
    64	  return { nivel, senales }
    65	}
    66	
    67	/** Conteo EXCLUSIVO de la cabecera: cada analista cuenta una sola vez. */
    68	export function conteoSemaforoEquipo(lecturas: readonly LecturaAnalista[]): { rojo: number; ambar: number } {
    69	  let rojo = 0
    70	  let ambar = 0
    71	  for (const l of lecturas) {
    72	    if (l.nivel === 'critico') rojo += 1
    73	    else if (l.nivel === 'atencion') ambar += 1
    74	  }
    75	  return { rojo, ambar }
    76	}
```

## `app/src/lib/cola-supervision.ts` (archivo NUEVO completo)
```
     1	// lib/cola-supervision.ts — cómo lee el SUPERVISOR una fila del seguimiento
     2	// activo (crm.cola_accion_v2_fn) en su pantalla Hoy (27/09/2026).
     3	//
     4	// ACCIONES_SLA habla al analista en imperativo («Contactar al cliente»); el
     5	// supervisor no gestiona el lead, lo revisa con su analista (textoAvisoSla con
     6	// supervision = true). Por eso aquí el bucket se nombra como un ESTADO del
     7	// caso, y el tiempo dice qué significa la fecha de referencia de ese bucket:
     8	// en unos es un plazo (vence / venció), en otros el inicio (desde).
     9	import { DIA_MS, duracionTexto, haceTexto } from './inteligencia'
    10	
    11	/** Estado del caso visto desde supervisión, por bucket del seguimiento. */
    12	export const ESTADO_CASO_SUPERVISION: Record<string, string> = {
    13	  primera_atencion: 'Primera gestión pendiente',
    14	  tarea_vencida: 'Actividad vencida',
    15	  tarea_hoy: 'Actividad para hoy',
    16	  seguimiento: 'Seguimiento pendiente',
    17	  revision_comercial: 'Revisión comercial',
    18	  datos_incompletos: 'Datos incompletos',
    19	  proxima_tarea: 'Próxima actividad',
    20	  por_repartir: 'Sin analista asignado',
    21	}
    22	
    23	export function estadoCasoSupervision(bucket: string): string {
    24	  return ESTADO_CASO_SUPERVISION[bucket] ?? 'Revisar oportunidad'
    25	}
    26	
    27	// En estos buckets `referencia_en` es un PLAZO (private.sla_operacion_leads):
    28	// el límite de la primera gestión, el vencimiento de la actividad o el límite
    29	// del seguimiento. En los demás es el inicio del caso (creado_en, etapa).
    30	const BUCKETS_CON_PLAZO = new Set(['primera_atencion', 'tarea_vencida', 'tarea_hoy', 'seguimiento', 'proxima_tarea'])
    31	
    32	/**
    33	 * «venció hace 2 días» / «vence en 3 horas» / «desde hace 5 días».
    34	 * Sin fecha confirmada lo dice: no se inventa un tiempo (referencia_en es nullable).
    35	 */
    36	export function momentoCaso(bucket: string, referenciaEn: string | null, ahora: number): string {
    37	  const ms = referenciaEn == null ? Number.NaN : Date.parse(referenciaEn)
    38	  if (!Number.isFinite(ms)) return 'sin fecha confirmada'
    39	  const dias = (ahora - ms) / DIA_MS
    40	  if (!BUCKETS_CON_PLAZO.has(bucket)) return `desde ${haceTexto(Math.max(0, dias))}`
    41	  return dias >= 0 ? `venció ${haceTexto(dias)}` : `vence en ${duracionTexto(-dias)}`
    42	}
```

## `app/src/screens/hoy/supervisor-mando.test.tsx` (archivo NUEVO completo)
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
    99	const KAREN = 'aaaaaaaa-0000-4000-8000-000000000001'
   100	const JORGE = 'aaaaaaaa-0000-4000-8000-000000000002'
   101	
   102	function miembro(id: string, nombre: string, over: Partial<Miembro> = {}): Miembro {
   103	  return { perfil_id: id, nombre_completo: nombre, rol_crm: 'vendedor', supervisor_id: 's-1', activo: true, ...over }
   104	}
   105	
   106	function lead(over: Partial<Lead> = {}): Lead {
   107	  return {
   108	    id: 'l-1', nombre_completo: 'ROSA CHÁVEZ', telefono: '+51987654321', etapa: 'contactado', origen: 'referido',
   109	    monto_estimado: 20_000, moneda: 'PEN', vendedor_id: KAREN, creado_en: '2026-09-20T15:00:00Z', activo: true, ...over,
   110	  }
   111	}
   112	
   113	type ItemCola = ColaSlaPagina['items'][number]
   114	function item(over: { lead_id: string; nombre: string; analistaId: string | null; analista: string | null; bucket?: string; severidad?: ItemCola['severidad']; referencia_en?: string | null }): ItemCola {
   115	  return {
   116	    lead_id: over.lead_id,
   117	    bucket: over.bucket ?? 'primera_atencion',
   118	    severidad: over.severidad ?? 'critica',
   119	    prioridad: 10,
   120	    referencia_en: over.referencia_en === undefined ? '2026-09-24T15:00:00Z' : over.referencia_en,
   121	    tarea_id: null,
   122	    lead: { id: over.lead_id, nombre_completo: over.nombre, etapa: 'nuevo', analista_id: over.analistaId, analista_nombre: over.analista },
   123	    senales: { pendientes: true, primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
   124	  } as unknown as ItemCola
   125	}
   126	
   127	const TOTALES_CERO = { pendientes: 0, primera_atencion: 0, tareas_vencidas: 0, seguimientos_pendientes: 0, revisiones: 0, datos_incompletos: 0, por_repartir: 0 }
   128	function pagina(items: ItemCola[], over: Partial<Omit<ColaSlaPagina, 'totales'>> & { totales?: Partial<ColaSlaPagina['totales']> } = {}): ColaSlaPagina {
   129	  const { totales, ...resto } = over
   130	  return {
   131	    version: 2, modo: 'activo', control_revision: 1, calculado_en: '2026-09-26T15:00:00Z', modelo_avisos: 3,
   132	    filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7,
   133	    total_items: items.length, hay_mas: false, cursor_siguiente: null, rango: { desde: 1, hasta: items.length },
   134	    totales: { ...TOTALES_CERO, ...totales },
   135	    items,
   136	    ...resto,
   137	  } as ColaSlaPagina
   138	}
   139	
   140	function agenda(vendedores: Array<Partial<MetricaAgendaVendedor> & { vendedor_id: string; nombre: string }>): MetricasAgenda {
   141	  return {
   142	    version: 1, generado_en: '2026-09-26T15:00:00Z',
   143	    periodo: { desde: '2026-09-20', hasta: '2026-09-26', dias: 7, zona: 'America/Lima' },
   144	    vendedores: vendedores.map((v) => ({
   145	      rol: 'vendedor', activo: true, toques: 0, toques_por_dia: 0, reuniones_realizadas: 0, completadas: 0, no_asistio: 0,
   146	      canceladas: 0, pct_completadas: null, tareas_creadas: 0, reuniones_agendadas: 0, reprogramaciones: 0, pendientes: 0,
   147	      vencidas: 0, leads_sin_accion: 0, ...v,
   148	    })),
   149	  } as MetricasAgenda
   150	}
   151	
   152	function montar(): ReturnType<typeof render> {
   153	  vi.setSystemTime(AHORA)
   154	  YO = { id: 's-1', nombre_completo: 'SUPERVISOR UNO', rol: 'supervisor', demo: false, puede_contratar: true }
   155	  return render(<HoySupervisorMando />)
   156	}
   157	
   158	const colaTodo = () => [
   159	  item({ lead_id: 'l-1', nombre: 'ROSA CHÁVEZ', analistaId: KAREN, analista: 'KAREN ZAPATA' }),
   160	  item({ lead_id: 'l-2', nombre: 'VÍCTOR PALOMINO', analistaId: JORGE, analista: 'JORGE HUAMÁN', bucket: 'tarea_vencida', severidad: 'critica', referencia_en: '2026-09-26T12:00:00Z' }),
   161	  item({ lead_id: 'l-3', nombre: 'MARTHA SOTO', analistaId: KAREN, analista: 'KAREN ZAPATA', bucket: 'seguimiento', severidad: 'media', referencia_en: '2026-09-26T18:00:00Z' }),
   162	]
   163	
   164	beforeEach(() => {
   165	  vi.useFakeTimers()
   166	  vi.clearAllMocks()
   167	  recargar.mockResolvedValue(true)
   168	  abrirLead.mockResolvedValue(true)
   169	  pedidosCola.length = 0
   170	  MODO.legado = false
   171	  MODO.activo = true
   172	  MODO.error = null
   173	  MODO.data = { control_revision: 1 }
   174	  VENDEDORES = [
   175	    miembro(KAREN, 'KAREN ZAPATA'),
   176	    miembro(JORGE, 'JORGE HUAMÁN'),
   177	    miembro('v-ex', 'EX ANALISTA', { activo: false }),
   178	  ]
   179	  LEADS = [lead(), lead({ id: 'l-3', nombre_completo: 'MARTHA SOTO', monto_estimado: 15_000, moneda: 'USD' })]
   180	  OBJETIVOS = objetivosCero('2026-09-01')
   181	  CUMPLIMIENTO = null
   182	  METRICAS_AGENDA = agenda([{ vendedor_id: KAREN, nombre: 'KAREN ZAPATA' }, { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' }])
   183	  AGENDA_ERROR = null
   184	  RESPONDER = (filtros) => {
   185	    const todas = colaTodo().filter((i) => filtros.analista_id == null || i.lead.analista_id === filtros.analista_id)
   186	    return {
   187	      data: pagina(todas, {
   188	        filtros: { ...filtros },
   189	        totales: { pendientes: todas.length, primera_atencion: todas.filter((i) => i.bucket === 'primera_atencion').length, tareas_vencidas: todas.filter((i) => i.bucket === 'tarea_vencida').length },
   190	      }),
   191	      error: null,
   192	      isFetching: false,
   193	    }
   194	  }
   195	})
   196	
   197	afterEach(() => {
   198	  vi.useRealTimers()
   199	})
   200	
   201	describe('Hoy · supervisor — puesto de mando: qué pantalla se elige', () => {
   202	  it('en modo LEGADO (demo o seguimiento apagado) sigue la pantalla clásica', () => {
   203	    MODO.legado = true
   204	    MODO.activo = false
   205	    montar()
   206	    expect(screen.getByText('Pantalla clásica del supervisor')).toBeInTheDocument()
   207	    expect(pedidosCola).toHaveLength(0)
   208	  })
   209	
   210	  it('mientras el modo se consulta no pide la cola ni inventa pendientes', () => {
   211	    MODO.activo = false
   212	    MODO.data = undefined
   213	    montar()
   214	    expect(screen.getByText('Consultando el seguimiento comercial…')).toHaveAttribute('role', 'status')
   215	    expect(screen.queryByRole('tablist')).not.toBeInTheDocument()
   216	    expect(pedidosCola.every((p) => !p.habilitada)).toBe(true)
   217	  })
   218	
   219	  it('si el modo falla lo dice y deja reintentar', () => {
   220	    MODO.activo = false
   221	    MODO.error = new Error('caído')
   222	    montar()
   223	    const alerta = screen.getByRole('alert')
   224	    expect(alerta).toHaveTextContent('No se pudo cargar el seguimiento')
   225	    fireEvent.click(within(alerta).getByRole('button', { name: /Reintentar/ }))
   226	    expect(REFETCH_MODO).toHaveBeenCalledTimes(1)
   227	  })
   228	})
   229	
   230	describe('Hoy · supervisor — puesto de mando: cola del seguimiento (F1)', () => {
   231	  it('ESTADO DE PRODUCCIÓN: la cola sale del seguimiento con 7 filas, conteos del servidor y enlace al módulo', () => {
   232	    montar()
   233	    expect(pedidosCola.at(-1)).toEqual({ filtros: { senal: 'pendientes', etapa: null, analista_id: null }, limite: 7, habilitada: true })
   234	    expect(screen.getByRole('heading', { name: 'Pendientes del equipo' })).toBeInTheDocument()
   235	    const pestanas = screen.getByRole('tablist', { name: 'Filtrar los pendientes' })
   236	    expect(within(pestanas).getByRole('tab', { name: 'Para atender ahora: 3' })).toHaveAttribute('aria-selected', 'true')
   237	    expect(within(pestanas).getByRole('tab', { name: 'Primera gestión: 1' })).toBeInTheDocument()
   238	    expect(within(pestanas).getByRole('tab', { name: 'Tareas vencidas: 1' })).toBeInTheDocument()
   239	    // «Todas» no tiene total en `totales`: sin número hasta que se abre.
   240	    expect(within(pestanas).getByRole('tab', { name: 'Todas' })).toBeInTheDocument()
   241	    expect(screen.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
   242	    expect(screen.getByText('3 de 3')).toBeInTheDocument()
   243	  })
   244	
   245	  it('cada fila dice de quién es, en qué estado está y desde cuándo, con la severidad en la tira', () => {
   246	    montar()
   247	    const lista = screen.getByRole('list', { name: /Pendientes del equipo/ })
   248	    const filas = within(lista).getAllByRole('listitem')
   249	    expect(filas).toHaveLength(3)
   250	    expect(filas[0]).toHaveAttribute('data-sev', 'critica')
   251	    expect(filas[0]).toHaveTextContent('Karen')
   252	    expect(filas[0]).toHaveTextContent('Primera gestión pendiente · venció hace 2 días')
   253	    expect(filas[1]).toHaveTextContent('Actividad vencida · venció hace 3 horas')
   254	    expect(filas[2]).toHaveAttribute('data-sev', 'media')
   255	    expect(filas[2]).toHaveTextContent('Seguimiento pendiente · vence en 3 horas')
   256	  })
   257	
   258	  it('monto y contacto SOLO con el lead completo del store (caché parcial: desconocido no es cero)', () => {
   259	    montar()
   260	    const filas = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')
   261	    expect(filas[0]).toHaveTextContent('S/ 20k')
   262	    expect(within(filas[0]!).getAllByRole('link', { name: /ROSA CHÁVEZ/ }).length + within(filas[0]!).queryAllByRole('button', { name: /número de ROSA CHÁVEZ|Llamar a ROSA CHÁVEZ/ }).length).toBeGreaterThan(0)
   263	    // VÍCTOR no está en el store: ni monto ni acciones de contacto.
   264	    expect(filas[1]).not.toHaveTextContent(/S\/|US\$/)
   265	    expect(within(filas[1]!).getAllByRole('button')).toHaveLength(1)
   266	    expect(filas[2]).toHaveTextContent('US$ 15k')
   267	  })
   268	
   269	  it('una fila sin fecha de referencia lo dice en vez de inventar un tiempo', () => {
   270	    RESPONDER = () => ({ data: pagina([item({ lead_id: 'l-9', nombre: 'SIN FECHA', analistaId: KAREN, analista: 'KAREN ZAPATA', referencia_en: null })], { totales: { pendientes: 1 } }), error: null, isFetching: false })
   271	    montar()
   272	    expect(screen.getByText(/Primera gestión pendiente · sin fecha confirmada/)).toBeInTheDocument()
   273	  })
   274	
   275	  it('el filtro por analista lo hace el SERVIDOR y los conteos son los suyos', () => {
   276	    montar()
   277	    const chips = screen.getByRole('group', { name: 'Filtrar por analista' })
   278	    // Solo analistas activos del equipo, sin conteos inventados en el cliente.
   279	    expect(within(chips).getAllByRole('button').map((b) => b.textContent)).toEqual(['Todos', 'Jorge', 'Karen'])
   280	    fireEvent.click(within(chips).getByRole('button', { name: 'KAREN ZAPATA' }))
   281	    expect(pedidosCola.at(-1)?.filtros).toEqual({ senal: 'pendientes', etapa: null, analista_id: KAREN })
   282	    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
   283	    expect(screen.getByRole('tab', { name: 'Para atender ahora: 2' })).toBeInTheDocument()
   284	    expect(screen.getByText('Mostrando los pendientes de Karen')).toHaveAttribute('aria-live', 'polite')
   285	    // Con el filtro, la columna del analista sobra.
   286	    const filas = within(screen.getByRole('list', { name: /Pendientes de Karen/ })).getAllByRole('listitem')
   287	    expect(filas).toHaveLength(2)
   288	    fireEvent.click(within(chips).getByRole('button', { name: 'Todos' }))
   289	    expect(pedidosCola.at(-1)?.filtros.analista_id).toBeNull()
   290	  })
   291	
   292	  it('las flechas recorren las pestañas, mueven el foco y piden la señal al servidor', () => {
   293	    montar()
   294	    const primera = screen.getByRole('tab', { name: /Para atender ahora/ })
   295	    primera.focus()
   296	    fireEvent.keyDown(primera, { key: 'ArrowRight' })
   297	    const segunda = screen.getByRole('tab', { name: /Primera gestión/ })
   298	    expect(segunda).toHaveAttribute('aria-selected', 'true')
   299	    expect(segunda).toHaveFocus()
   300	    expect(pedidosCola.at(-1)?.filtros.senal).toBe('primera_atencion')
   301	    fireEvent.keyDown(segunda, { key: 'End' })
   302	    expect(screen.getByRole('tab', { name: /^Todas/ })).toHaveAttribute('aria-selected', 'true')
   303	    // Con «Todas» abierta, su total sí es del servidor.
   304	    expect(screen.getByRole('tab', { name: 'Todas: 3' })).toBeInTheDocument()
   305	    fireEvent.keyDown(screen.getByRole('tab', { name: 'Todas: 3' }), { key: 'Home' })
   306	    expect(screen.getByRole('tab', { name: /Para atender ahora/ })).toHaveFocus()
   307	  })
   308	
   309	  it('fail-closed: con error NO enseña la cola retenida y deja reintentar', () => {
   310	    RESPONDER = () => ({ data: pagina(colaTodo(), { totales: { pendientes: 3 } }), error: new Error('refetch caído'), isFetching: false })
   311	    montar()
   312	    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
   313	    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
   314	    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('No se pudo cargar la cola'))
   315	    expect(alerta).toBeDefined()
   316	    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
   317	    expect(REFETCH_COLA).toHaveBeenCalledTimes(1)
   318	  })
   319	
   320	  it('una respuesta que ya no es del modo activo no se pinta como vigente', () => {
   321	    RESPONDER = () => ({ data: pagina(colaTodo(), { modo: 'legado' }), error: null, isFetching: false })
   322	    montar()
   323	    expect(screen.queryByText('ROSA CHÁVEZ')).not.toBeInTheDocument()
   324	    expect(screen.getByText(/Las reglas del seguimiento cambiaron/)).toBeInTheDocument()
   325	  })
   326	
   327	  it('cargando: lo dice, sin filas ni ceros', () => {
   328	    RESPONDER = () => ({ data: undefined, error: null, isFetching: true })
   329	    montar()
   330	    expect(screen.getByText('Cargando los pendientes del equipo…')).toBeInTheDocument()
   331	    expect(screen.getByRole('tab', { name: 'Para atender ahora' })).toBeInTheDocument()
   332	  })
   333	
   334	  it('vacío honesto por pestaña y por analista', () => {
   335	    RESPONDER = (filtros) => ({ data: pagina([], { filtros: { ...filtros } }), error: null, isFetching: false })
   336	    montar()
   337	    expect(screen.getByText(/Nada para atender ahora/)).toBeInTheDocument()
   338	    fireEvent.click(screen.getByRole('button', { name: 'JORGE HUAMÁN' }))
   339	    expect(screen.getByText('Jorge no tiene casos aquí.')).toBeInTheDocument()
   340	  })
   341	
   342	  it('abrir una ficha llama al store; si falla, lo avisa', async () => {
   343	    abrirLead.mockResolvedValueOnce(false)
   344	    montar()
   345	    const fila = within(screen.getByRole('list', { name: /Pendientes del equipo/ })).getAllByRole('listitem')[0]!
   346	    await act(async () => {
   347	      fireEvent.click(within(fila).getByRole('button', { name: 'Abrir ficha de ROSA CHÁVEZ, de Karen: Primera gestión pendiente · venció hace 2 días, S/ 20k' }))
   348	    })
   349	    expect(abrirLead).toHaveBeenCalledWith('l-1')
   350	    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo abrir la ficha')
   351	  })
   352	})
   353	
   354	describe('Hoy · supervisor — puesto de mando: equipo hoy (F1)', () => {
   355	  it('UNA severidad por analista: el no-show repetido es rojo en el punto, la cabecera y el detalle', () => {
   356	    METRICAS_AGENDA = agenda([
   357	      { vendedor_id: KAREN, nombre: 'KAREN ZAPATA', no_asistio: 2, vencidas: 1, toques: 9, pct_completadas: 50 },
   358	      { vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' },
   359	    ])
   360	    montar()
   361	    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
   362	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   363	    const karen = within(equipo).getByRole('button', { name: /KAREN ZAPATA/ })
   364	    expect(karen).toHaveTextContent('2 citas sin asistir')
   365	    expect(within(karen).getByTestId('equipo-semaforo')).toHaveAttribute('data-nivel', 'critico')
   366	    expect(karen).toHaveAttribute('aria-expanded', 'false')
   367	    fireEvent.click(karen)
   368	    expect(karen).toHaveAttribute('aria-expanded', 'true')
   369	    const detalle = document.getElementById(karen.getAttribute('aria-controls')!)!
   370	    expect(detalle).toBeVisible()
   371	    // El detalle NO repite la señal principal: trae las demás y los hechos.
   372	    expect(detalle).not.toHaveTextContent('2 citas sin asistir')
   373	    expect(detalle).toHaveTextContent('1 tarea vencida')
   374	    expect(detalle).toHaveTextContent('9 toques en 7 días · 50 % completadas')
   375	    // Y filtra la cola a sus pendientes.
   376	    expect(pedidosCola.at(-1)?.filtros.analista_id).toBe(KAREN)
   377	    expect(screen.getByRole('heading', { name: 'Pendientes de Karen' })).toBeInTheDocument()
   378	  })
   379	
   380	  it('«Al día» solo con la agenda confirmada; sin ella no se afirma', () => {
   381	    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
   382	    montar()
   383	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   384	    expect(within(equipo).getByRole('button', { name: /JORGE HUAMÁN/ })).toHaveTextContent('Al día')
   385	    // Karen no tiene actividad desde el 20/09: 6 días, rojo. Jorge no cuenta.
   386	    expect(screen.getByText('1 en rojo · 0 en ámbar')).toBeInTheDocument()
   387	  })
   388	
   389	  it('con la agenda CAÍDA avisa en la tarjeta, deja reintentar y no dice «Al día»', () => {
   390	    AGENDA_ERROR = new Error('agenda caída')
   391	    montar()
   392	    LEADS = [...LEADS, lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' })]
   393	    const alerta = screen.getAllByRole('alert').find((a) => a.textContent?.includes('La agenda del equipo no respondió'))
   394	    expect(alerta).toBeDefined()
   395	    fireEvent.click(within(alerta!).getByRole('button', { name: /Reintentar/ }))
   396	    expect(REFETCH_AGENDA).toHaveBeenCalledTimes(1)
   397	    const equipo = screen.getByRole('list', { name: 'Analistas del equipo' })
   398	    expect(equipo).not.toHaveTextContent('Al día')
   399	  })
   400	
   401	  it('el enlace de la cabecera lleva a «Mi equipo hoy»', () => {
   402	    montar()
   403	    expect(screen.getByRole('link', { name: 'Mi equipo hoy →' })).toHaveAttribute('href', '#/gestion-diaria')
   404	  })
   405	})
```

## `app/src/lib/senal-equipo.test.ts` (archivo NUEVO completo)
```
     1	import { describe, expect, it } from 'vitest'
     2	import { conteoSemaforoEquipo, lecturaAnalista } from './senal-equipo'
     3	
     4	const sinRezago = { no_asistio: 0, leads_sin_accion: 0, vencidas: 0 }
     5	
     6	describe('lecturaAnalista', () => {
     7	  it('sin cartera abierta es NEUTRO y no enseña señales (no hay nada que medir)', () => {
     8	    expect(lecturaAnalista({ activos: 0, diasSinActividadMax: 9 }, { no_asistio: 3, leads_sin_accion: 2, vencidas: 1 }))
     9	      .toEqual({ nivel: 'neutro', senales: [] })
    10	  })
    11	
    12	  it('con actividad fresca y sin rezago no hay señal', () => {
    13	    expect(lecturaAnalista({ activos: 4, diasSinActividadMax: 1.5 }, sinRezago)).toEqual({ nivel: null, senales: [] })
    14	  })
    15	
    16	  it('un no-show repetido es ROJO en el nivel del analista, no solo en su chip', () => {
    17	    const l = lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, no_asistio: 2 })
    18	    expect(l.nivel).toBe('critico')
    19	    expect(l.senales).toEqual([{ texto: '2 citas sin asistir', nivel: 'critico' }])
    20	  })
    21	
    22	  it('una sola cita sin asistir no es patrón', () => {
    23	    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, no_asistio: 1 }).nivel).toBeNull()
    24	  })
    25	
    26	  it('sin próxima acción: ámbar desde 1, rojo desde 5 (umbral de la campana)', () => {
    27	    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, leads_sin_accion: 1 }).senales)
    28	      .toEqual([{ texto: '1 lead sin próxima acción', nivel: 'atencion' }])
    29	    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, leads_sin_accion: 4 }).nivel).toBe('atencion')
    30	    expect(lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, { ...sinRezago, leads_sin_accion: 5 }).nivel).toBe('critico')
    31	  })
    32	
    33	  it('días sin actividad: 2–5 ámbar, más de 5 rojo', () => {
    34	    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 2 }, sinRezago).senales)
    35	      .toEqual([{ texto: 'Un lead sin actividad hace 2 días', nivel: 'atencion' }])
    36	    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 5 }, sinRezago).nivel).toBe('atencion')
    37	    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 6 }, sinRezago).nivel).toBe('critico')
    38	  })
    39	
    40	  it('tareas vencidas son ámbar y con singular honesto', () => {
    41	    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 0 }, { ...sinRezago, vencidas: 1 }).senales)
    42	      .toEqual([{ texto: '1 tarea vencida', nivel: 'atencion' }])
    43	  })
    44	
    45	  it('la severidad es la PEOR y las rojas van primero', () => {
    46	    const l = lecturaAnalista({ activos: 5, diasSinActividadMax: 3 }, { no_asistio: 0, leads_sin_accion: 6, vencidas: 2 })
    47	    expect(l.nivel).toBe('critico')
    48	    expect(l.senales.map((s) => s.nivel)).toEqual(['critico', 'atencion', 'atencion'])
    49	    expect(l.senales[0]?.texto).toBe('6 leads sin próxima acción')
    50	  })
    51	
    52	  it('sin agenda (null) juzga solo los días y no inventa «al día»', () => {
    53	    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 7 }, null)).toEqual({
    54	      nivel: 'critico',
    55	      senales: [{ texto: 'Un lead sin actividad hace 7 días', nivel: 'critico' }],
    56	    })
    57	    expect(lecturaAnalista({ activos: 2, diasSinActividadMax: 0 }, undefined).nivel).toBeNull()
    58	  })
    59	})
    60	
    61	describe('conteoSemaforoEquipo', () => {
    62	  it('cuenta a cada analista UNA vez, en su peor nivel; neutro y sin señal no cuentan', () => {
    63	    const lecturas = [
    64	      lecturaAnalista({ activos: 3, diasSinActividadMax: 3 }, { no_asistio: 2, leads_sin_accion: 1, vencidas: 1 }),
    65	      lecturaAnalista({ activos: 3, diasSinActividadMax: 3 }, sinRezago),
    66	      lecturaAnalista({ activos: 3, diasSinActividadMax: 0 }, sinRezago),
    67	      lecturaAnalista({ activos: 0, diasSinActividadMax: 0 }, null),
    68	    ]
    69	    expect(conteoSemaforoEquipo(lecturas)).toEqual({ rojo: 1, ambar: 1 })
    70	  })
    71	})
```

## `app/src/lib/cola-supervision.test.ts` (archivo NUEVO completo)
```
     1	import { describe, expect, it } from 'vitest'
     2	import { estadoCasoSupervision, momentoCaso } from './cola-supervision'
     3	
     4	const AHORA = Date.parse('2026-09-27T15:00:00Z')
     5	
     6	describe('estadoCasoSupervision', () => {
     7	  it('nombra el ESTADO del caso, no la orden al analista', () => {
     8	    expect(estadoCasoSupervision('primera_atencion')).toBe('Primera gestión pendiente')
     9	    expect(estadoCasoSupervision('tarea_vencida')).toBe('Actividad vencida')
    10	    expect(estadoCasoSupervision('por_repartir')).toBe('Sin analista asignado')
    11	  })
    12	
    13	  it('un bucket desconocido no rompe la fila', () => {
    14	    expect(estadoCasoSupervision('algo_nuevo')).toBe('Revisar oportunidad')
    15	  })
    16	})
    17	
    18	describe('momentoCaso', () => {
    19	  it('en un bucket con PLAZO pasado dice cuánto hace que venció', () => {
    20	    expect(momentoCaso('primera_atencion', '2026-09-25T15:00:00Z', AHORA)).toBe('venció hace 2 días')
    21	    expect(momentoCaso('tarea_vencida', '2026-09-27T12:00:00Z', AHORA)).toBe('venció hace 3 horas')
    22	  })
    23	
    24	  it('con el plazo por delante dice cuánto falta', () => {
    25	    expect(momentoCaso('seguimiento', '2026-09-27T18:30:00Z', AHORA)).toBe('vence en 3 horas')
    26	  })
    27	
    28	  it('en un bucket SIN plazo la fecha es el inicio del caso', () => {
    29	    expect(momentoCaso('por_repartir', '2026-09-24T15:00:00Z', AHORA)).toBe('desde hace 3 días')
    30	    expect(momentoCaso('revision_comercial', '2026-09-27T14:20:00Z', AHORA)).toBe('desde hace 40 minutos')
    31	  })
    32	
    33	  it('sin fecha (null o ilegible) lo dice en vez de inventar un tiempo', () => {
    34	    expect(momentoCaso('primera_atencion', null, AHORA)).toBe('sin fecha confirmada')
    35	    expect(momentoCaso('seguimiento', 'no-es-fecha', AHORA)).toBe('sin fecha confirmada')
    36	  })
    37	})
```

## Contexto (sin cambios)

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
    61	export const ACCIONES_SLA: Record<string, string> = {
    62	  primera_atencion: 'Contactar al cliente', tarea_vencida: 'Revisar actividad pendiente', tarea_hoy: 'Actividad de hoy',
    63	  seguimiento: 'Retomar el contacto', revision_comercial: 'Definir el siguiente paso', datos_incompletos: 'Revisar datos',
    64	  proxima_tarea: 'Próxima tarea', por_repartir: 'Asignar analista',
    65	}
    66	/**
    67	 * La gestión manual desde la ficha pertenece al analista asignado. Supervisión
    68	 * y Gerencia revisan el seguimiento, pero no deben registrar una actividad como
    69	 * si la hubieran realizado ellas. Es una regla de interfaz, no autorización.
    70	 */
    71	export function puedeRegistrarGestionSla(rol: Rol | null | undefined): boolean {
    72	  return rol === 'vendedor'
    73	}
    74	
    75	// Solo presentación: el servidor decide qué avisos corresponden al actor y cuándo.
    76	// `boton: null` hace inseparables el texto de revisión de supervisión y la
    77	// ausencia de una acción que fingiría una gestión del analista.
    78	export function textoAvisoSla(aviso: AvisoSla, supervision: boolean, modelo?: number) {
    79	  if (modelo === 3 && aviso.bucket === 'primera_atencion') return {
    80	    titulo: supervision ? 'Revisa la primera gestión con el analista' : 'Realiza el primer intento y registra el resultado', boton: supervision ? null : 'Registrar gestión',
    81	  }
    82	  if (modelo === 3 && aviso.bucket === 'seguimiento') return {
    83	    titulo: supervision ? 'Revisa el seguimiento con el analista' : 'Retoma el seguimiento', boton: supervision ? null : 'Registrar gestión',
    84	  }
    85	  switch (aviso.bucket) {
    86	    case 'tarea_vencida': return { titulo: 'Revisa la actividad pendiente', boton: 'Revisar actividad' }
    87	    case 'primera_atencion': return { titulo: supervision ? 'Revisa el contacto inicial con el cliente' : 'Contacta al cliente y registra el resultado', boton: supervision ? null : 'Registrar gestión' }
    88	    case 'seguimiento': return { titulo: supervision ? 'Revisa el seguimiento con el analista' : 'Retoma el contacto y registra el resultado', boton: supervision ? null : 'Registrar gestión' }
    89	    case 'revision_comercial': return { titulo: 'Revisa el caso y define el siguiente paso', boton: 'Revisar caso' }
    90	    case 'por_repartir': return { titulo: 'Asigna un analista a esta oportunidad', boton: 'Ver asignación' }
    91	    case 'datos_incompletos': return { titulo: supervision ? 'Revisa los datos de esta oportunidad' : 'Pide al supervisor revisar los datos', boton: 'Ver datos' }
    92	  }
    93	}
    94	export const MOTIVOS_REVISION_SLA: Record<string, string> = {
    95	  limite_operativo_agotado: 'Se venció el plazo de esta etapa',
    96	  reprogramaciones_agotadas: 'La actividad se reprogramó tres veces o más',
    97	  reingreso_etapa: 'La oportunidad ingresó a esta etapa tres veces o más en este proceso comercial',
    98	}
    99	export function fechaSla(valor: string | null, formato: 'breve' | 'completa' = 'breve'): string {
   100	  if (!valor || !Number.isFinite(Date.parse(valor))) return 'Sin fecha confirmada'
   101	  return new Intl.DateTimeFormat('es-PE', {
   102	    timeZone: 'America/Lima', day: formato === 'completa' ? 'numeric' : '2-digit',
   103	    month: formato === 'completa' ? 'long' : 'short', ...(formato === 'completa' ? { year: 'numeric' as const } : {}),
   104	    hour: '2-digit', minute: '2-digit',
   105	  }).format(new Date(valor))
   106	}
   107	
   108	const reglaOperacion = v.object({ etapa: v.picklist(['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']),
   109	  seguimiento_minutos: v.number(), prorroga_minutos: v.number(), prorroga_max: v.number(),
   110	  tope_extra_minutos: v.number(), pausa_habilitada: v.boolean(), pausa_margen_minutos: v.number() })
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

### `app/src/components/app/sla-operacion.tsx (ColaSlaPanel, referencia de patrones)`
```
     1	import { Fragment, useEffect, useId, useRef, useState, type ReactNode } from 'react'
     2	import { GuardadosSlaPendientes } from './guardados-sla-pendientes'
     3	import { useQueryClient } from '@tanstack/react-query'
     4	import { ChevronLeft, ChevronRight, RefreshCw, ArrowUpRight, ListFilter, X } from 'lucide-react'
     5	import './sla-operacion.css'
     6	import { CrmApiError } from '@/data/crm-api'
     7	import { Button } from '@/components/ui/button'
     8	import { Select } from '@/components/ui/select'
     9	import { useAuth } from '@/lib/auth-context'
    10	import { useCRMData, usePanelesActions } from '@/lib/store-context'
    11	import { ETAPA_INFO, ETAPAS } from '@/lib/tipos'
    12	import { slaOperacionKeys, useColaSlaPagina, useEstadosSlaV2, useModoSla } from '@/data/sla-operacion-queries'
    13	import { ACCIONES_SLA, MOTIVOS_REVISION_SLA, SENALES_SLA, fechaSla, puedeRegistrarGestionSla, textoAvisoSla, type AvisoSla, type CursorSla, type EstadoSlaV2, type FiltrosSla, type SenalSla } from '@/lib/sla-operacion'
    14	
    15	export function SlaOperacionBoundary({ children, legado }: { children: ReactNode; legado?: ReactNode }) {
    16	  const modo = useModoSla()
    17	  const { yo } = useAuth()
    18	  if (modo.legado) return legado ?? null
    19	  if (modo.error) return <FalloSla onReintentar={() => void modo.refetch()} />
    20	  if (!modo.activo) return <p role="status" className="rounded-xl border p-4 text-sm">Consultando el seguimiento comercial…</p>
    21	  return <Fragment key={`${yo?.id}|${yo?.rol}|${modo.data?.control_revision}`}>{children}</Fragment>
    22	}
    23	function FalloSla({ onReintentar }: { onReintentar: () => void }) {
    24	  return <div role="alert" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 p-4">
    25	    <p className="text-sm">No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.</p>
    26	    <Button variant="outline" size="sm" onClick={onReintentar}><RefreshCw aria-hidden /> Reintentar</Button>
    27	  </div>
    28	}
    29	export function ColaSlaPanel() {
    30	  const { yo } = useAuth()
    31	  const { equipo } = useCRMData()
    32	  const { abrirLead } = usePanelesActions()
    33	  const [filtros, setFiltros] = useState<FiltrosSla>({ senal: 'pendientes', etapa: null, analista_id: null })
    34	  const [limite, setLimite] = useState(10)
    35	  const [abriendo, setAbriendo] = useState<string | null>(null)
    36	  const [errorApertura, setErrorApertura] = useState(false)
    37	  const [cursores, setCursores] = useState<(CursorSla | null)[]>([null])
    38	  const cursor = cursores[cursores.length - 1] ?? null
    39	  const consulta = useColaSlaPagina(filtros, cursor, limite, true)
    40	  const pagina = consulta.error ? undefined : consulta.data
    41	  const encabezado = useRef<HTMLHeadingElement>(null)
    42	  const queryClient = useQueryClient()
    43	  const prefijo = JSON.stringify(slaOperacionKeys.raiz()).slice(0, -1)
    44	  // Cada gestión confirmada invalida esta raíz: el orden anterior ya no sirve.
    45	  useEffect(() => queryClient.getQueryCache().subscribe((evento) => {
    46	    if (evento.type === 'updated' && evento.action.type === 'invalidate'
    47	      && JSON.stringify(evento.query.queryKey).startsWith(prefijo)) setCursores([null])
    48	  }), [prefijo, queryClient])
    49	  // Una frontera temporal o un cambio de cartera invalida la posición anterior.
    50	  useEffect(() => {
    51	    if (cursor && consulta.error instanceof CrmApiError && consulta.error.code === '22023') setCursores([null])
    52	  }, [cursor, consulta.error])
    53	  const esSupervisor = yo?.rol === 'supervisor' || yo?.rol === 'gerencia' || yo?.rol === 'directorio'
    54	  const id = useId()
    55	  function filtrar(cambio: Partial<FiltrosSla>) { setFiltros((actual) => ({ ...actual, ...cambio })); setCursores([null]) }
    56	  function navegar(siguiente: boolean) {
    57	    if (consulta.isFetching) return
    58	    if (siguiente && pagina?.cursor_siguiente) setCursores((actual) => [...actual, pagina.cursor_siguiente])
    59	    else if (!siguiente) setCursores((actual) => actual.length > 1 ? actual.slice(0, -1) : actual)
    60	    encabezado.current?.focus()
    61	  }
    62	  const reiniciar = () => { setCursores([null]); if (cursor === null) void consulta.refetch() }
    63	  async function abrirFicha(id: string) {
    64	    if (abriendo) return
    65	    setAbriendo(id)
    66	    setErrorApertura(false)
    67	    try {
    68	      if (await abrirLead(id) === false) setErrorApertura(true)
    69	    } catch {
    70	      setErrorApertura(true)
    71	    } finally {
    72	      setAbriendo(null)
    73	    }
    74	  }
    75	  const senales = SENALES_SLA.filter(([key]) => esSupervisor || (key !== 'por_repartir' && key !== 'revisiones'))
    76	    .map(([key, label]) => [key, pagina?.modelo_avisos === 3 && key === 'primera_atencion' ? 'Primera gestión pendiente' : label] as const)
    77	  const hayFiltros = filtros.senal !== 'pendientes' || filtros.etapa !== null || filtros.analista_id !== null
    78	  const limpiar = () => { setFiltros({ senal: 'pendientes', etapa: null, analista_id: null }); setCursores([null]); setErrorApertura(false) }
    79	  return <section className="sla-bandeja" aria-label="Seguimiento comercial">
    80	    <header className="sla-cabecera">
    81	      <div>
    82	        <h2 ref={encabezado} tabIndex={-1} className="sla-titulo">Seguimiento comercial</h2>
    83	        <p>{yo?.rol === 'gerencia' ? 'Las oportunidades de todo el equipo que necesitan atención.' : esSupervisor ? 'Los pendientes de tu equipo y los casos que necesitan tu decisión.' : 'Tus oportunidades pendientes, ordenadas para la próxima gestión.'}</p>
    84	      </div>
    85	      <Button variant="outline" size="sm" disabled={consulta.isFetching} onClick={reiniciar}><RefreshCw aria-hidden className={consulta.isFetching ? 'motion-safe:animate-spin' : ''} /> Actualizar</Button>
    86	    </header>
    87	
    88	    <div className="sla-prioridades" role="group" aria-label="Prioridades de seguimiento">
    89	      {senales.filter(([key]) => key !== 'todas' && key !== 'pendientes').map(([key, label]) => <button key={key} type="button"
    90	        aria-label={`${label} ${pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : 'sin confirmar'}`}
    91	        aria-pressed={filtros.senal === key} onClick={() => filtrar({ senal: key })}>
    92	        <span>{label}</span><strong>{pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : '—'}</strong>
    93	      </button>)}
    94	    </div>
    95	
    96	    <div className="sla-herramientas">
    97	      <div className="sla-todas"><button type="button" aria-pressed={filtros.senal === 'pendientes'} onClick={() => filtrar({ senal: 'pendientes' })}>Para atender ahora</button><button type="button" aria-pressed={filtros.senal === 'todas'} onClick={() => filtrar({ senal: 'todas' })}><ListFilter aria-hidden /> Todas las acciones</button></div>
    98	      <label htmlFor={`${id}-senal`} className="sla-mostrar">Mostrar
    99	        <Select id={`${id}-senal`} value={filtros.senal} onChange={(e) => filtrar({ senal: e.target.value as SenalSla })}>
   100	          {senales.map(([key, label]) => <option key={key} value={key}>{label}{key !== 'todas' && pagina ? ` (${pagina.totales[key]})` : ''}</option>)}
   101	        </Select>
   102	      </label>
   103	      <label htmlFor={`${id}-etapa`}>Etapa
   104	        <Select id={`${id}-etapa`} value={filtros.etapa ?? ''} onChange={(e) => filtrar({ etapa: e.target.value || null })}>
   105	          <option value="">Todas las etapas</option>{ETAPAS.map((etapa) => <option key={etapa.k} value={etapa.k}>{etapa.label}</option>)}
   106	        </Select>
   107	      </label>
   108	      {esSupervisor && <label htmlFor={`${id}-analista`}>Analista
   109	        <Select id={`${id}-analista`} value={filtros.analista_id ?? ''} onChange={(e) => filtrar({ analista_id: e.target.value || null })}>
   110	          <option value="">Todos los analistas</option>{equipo.filter((miembro) => miembro.activo && miembro.rol_crm === 'vendedor').map((miembro) => <option key={miembro.perfil_id} value={miembro.perfil_id}>{miembro.nombre_completo}</option>)}
   111	        </Select>
   112	      </label>}
   113	      {hayFiltros && <Button variant="ghost" size="sm" onClick={limpiar}><X aria-hidden /> Limpiar filtros</Button>}
   114	    </div>
   115	
   116	    {abriendo && <p role="status" className="sla-aviso">Abriendo ficha…</p>}
   117	    {errorApertura && <p role="alert" className="sla-aviso text-destructive">No se pudo abrir la ficha. Actualiza la lista o vuelve a intentarlo.</p>}
   118	    {consulta.error ? <div className="sla-estado"><FalloSla onReintentar={reiniciar} />{cursores.length > 1 && <Button variant="outline" size="sm" onClick={() => setCursores([null])}>Volver a la primera página</Button>}</div>
   119	      : !pagina ? <p role="status" className="sla-estado">Cargando oportunidades…</p>
   120	      : pagina.modo !== 'activo' ? <p role="status" className="sla-estado">Las reglas operativas están desactivadas. Actualiza la pantalla para ver el modo vigente.</p>
   121	      : <>
   122	        <div className="sla-resultados">
   123	          <p role="status" aria-live="polite">{pagina.rango.desde}–{pagina.rango.hasta} de {pagina.total_items} oportunidades · Página {cursores.length}{consulta.isFetching ? ' · Actualizando…' : ''}</p>
   124	          <label htmlFor={`${id}-limite`}>Por página
   125	            <Select id={`${id}-limite`} value={limite} onChange={(e) => { setLimite(Number(e.target.value)); setCursores([null]) }}>
   126	              {[10, 25, 50].map((n) => <option key={n} value={n}>{n} oportunidades</option>)}
   127	            </Select>
   128	          </label>
   129	        </div>
   130	        {pagina.items.length === 0 ? <div className="sla-vacio"><ListFilter aria-hidden /><p>No hay oportunidades con estos filtros.</p><span>{filtros.senal === 'pendientes' ? 'Las próximas actividades siguen en Agenda.' : 'Puedes elegir otra señal o etapa.'}</span>{hayFiltros && <Button variant="outline" size="sm" onClick={limpiar}>Ver todas las acciones</Button>}</div>
   131	          : <>
   132	            <div className="sla-columnas" aria-hidden="true"><span>Oportunidad{esSupervisor ? ' y analista' : ''}</span><span>Acción pendiente</span><span>Fecha de referencia</span><span>Ficha</span></div>
   133	            <ul className="sla-lista" aria-label="Oportunidades de esta página" aria-busy={consulta.isFetching || abriendo !== null}>
   134	              {pagina.items.map((item) => <li key={item.lead_id}>
   135	                <button type="button" disabled={abriendo !== null} onClick={() => void abrirFicha(item.lead_id)} className="sla-fila">
   136	                  <span className="sla-oportunidad">
   137	                    <strong>{item.lead.nombre_completo}</strong>
   138	                    <span className="sla-meta"><span>{ETAPA_INFO[item.lead.etapa as keyof typeof ETAPA_INFO]?.label ?? item.lead.etapa}</span>{esSupervisor && <span>{item.lead.analista_nombre ?? 'Sin analista'}</span>}</span>
   139	                  </span>
   140	                  <span className="sla-accion">
   141	                    <span className={`sla-etiqueta sla-etiqueta-${item.severidad}`}>{pagina.modelo_avisos === 3 && item.bucket === 'primera_atencion' ? 'Realizar la primera gestión' : ACCIONES_SLA[item.bucket] ?? 'Revisar oportunidad'}</span>
   142	                    {esSupervisor && item.senales.revisiones && item.bucket !== 'revision_comercial' && <span className="sla-revision">Revisión comercial</span>}
   143	                    {esSupervisor && item.senales.revisiones && <span className="sla-motivo">{item.estado.etapa.motivos_revision.map((motivo) => MOTIVOS_REVISION_SLA[motivo] ?? 'Revisión requerida').join(' · ')}</span>}
   144	                  </span>
   145	                  <span className="sla-fecha"><span>Referencia</span>{fechaSla(item.referencia_en)} <span>(Lima)</span></span>
   146	                  <span className="sla-abrir"><span>Abrir ficha</span><ArrowUpRight aria-hidden /></span>
   147	                </button>
   148	              </li>)}
   149	            </ul>
   150	          </>}
```

### `app/src/screens/hoy/supervisor.tsx (DESPUÉS del cambio, completo)`
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
   108	    errorAgenda,
   109	    cargandoAgenda,
   110	    recargarAgenda,
   111	    rezagosAgenda,
   112	  } = useDatosSupervisor()
   113	  // Cola del equipo expandida más allá del tope de COLA_VISIBLES.
   114	  const [colaExpandida, setColaExpandida] = useState(false)
   115	  // Pestaña elegida a mano; `null` = automática (la primera con filas), así
   116	  // un supervisor que entra por la mañana aterriza donde hay trabajo.
   117	  const [pestanaElegida, setPestanaElegida] = useState<PestanaCola | null>(null)
   118	
   119	  // cola_accion_fn → cola + estancados + tile "sin responder".
   120	  const colaOp = useColaAccionOperativa(ambito.leads, actividades, tareas, estadoSla.indice, modoSla.legado)
   121	  const cola = colaOp.cola
   122	
   123	  // Nombres para los estancados del payload (el servidor no manda nombres de
   124	  // personas): join con el roster completo, una sola vez por render.
   125	  const nombrePorId = useMemo(
   126	    () => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])),
   127	    [equipo],
   128	  )
   129	
   130	  // Filas y conteos por pestaña. «Todo» cuenta el universo del RPC (`total`),
   131	  // no las filas recortadas por p_limite; «Urgente» solo puede contar lo que
   132	  // llegó. Con estancados al tope, el conteo dice «50+» y no miente.
   133	  const urgentes = useMemo(
   134	    () => (cola?.items ?? []).filter((i) => i.sev !== 'baja'),
   135	    [cola],
   136	  )
   137	  // El conteo de «Urgente» sale de porSev (el resumen COMPLETO del RPC), no de
   138	  // las filas: p_limite recorta items a 100 y con 120 urgentes la pestaña
   139	  // habría dicho 100 mientras «Todo» decía 120 (hallazgo de Codex).
   140	  const urgenteTotal = (cola?.porSev.critica ?? 0) + (cola?.porSev.media ?? 0)
   141	  const conteoPestana: Record<PestanaCola, string> = {
   142	    urgente: String(urgenteTotal),
   143	    sin_movimiento: cola && cola.estancados.length >= TOPE_ESTANCADOS
   144	      ? `${TOPE_ESTANCADOS}+`
   145	      : String(cola?.estancados.length ?? 0),
   146	    todo: String(cola?.total ?? 0),
   147	  }
   148	  const primeraConFilas: PestanaCola = urgentes.length > 0
   149	    ? 'urgente'
   150	    : (cola?.estancados.length ?? 0) > 0
   151	      ? 'sin_movimiento'
   152	      : 'todo'
   153	  const pestana = pestanaElegida ?? primeraConFilas
   154	  const elegirPestana = (siguiente: PestanaCola) => {
   155	    // F4.3: la visita la cierra el USUARIO al irse de la pestaña. Un vaivén
   156	    // automático de `primeraConFilas` (refetch caído que salta a «Todo» y
   157	    // vuelve al recuperarse) no borra las marcas ni fabrica otra visita.
   158	    if (pestana === 'sin_movimiento' && siguiente !== 'sin_movimiento') {
   159	      visitaAnotadaRef.current = null
   160	      setVisitaCongelada(null)
   161	    }
   162	    setPestanaElegida(siguiente)
   163	  }
   164	  // El colapso se reinicia con CUALQUIER cambio de pestaña — también el
   165	  // automático: la cola se refresca cada minuto y sin esto una pestaña recién
   166	  // aparecida heredaba la expansión de la anterior (hasta 100 filas de golpe).
   167	  useEffect(() => {
   168	    setColaExpandida(false)
   169	  }, [pestana])
   170	  // F4.3: qué EMPEORÓ en «Sin movimiento» desde la última visita. TODO se
   171	  // CONGELA en el instante de anotar: la foto anterior Y las marcas derivadas
   172	  // — una marca que aparece «bajo el cursor» porque la cola se refrescó
   173	  // debajo sería ruido, no memoria (la severidad de la tira sí sigue viva).
   174	  // La visita queda anotada en localStorage en ese mismo instante — anotar
   175	  // «al salir» exigiría un unload handler, y perder una anotación solo marca
   176	  // DE MÁS la próxima vez, la dirección segura. La anotación ESPERA a que el
   177	  // payload esté fresco (enVuelo: persistir una cola vieja podría CALLAR una
   178	  // novedad futura) y a que el workspace sea visible (splash: una «visita»
   179	  // que nadie vio también calla). El ref la hace idempotente (StrictMode
   180	  // ejecuta el efecto dos veces) y fiel a la identidad: si `yo` cambiara en
   181	  // caliente se anota de nuevo para el id nuevo.
   182	  const splashVisible = useSplashVisible()
   183	  const [visitaCongelada, setVisitaCongelada] = useState<{
   184	    novedades: NovedadesVisita | null
   185	    recortada: boolean
   186	  } | null>(null)
   187	  const visitaAnotadaRef = useRef<string | null>(null)
   188	  useEffect(() => {
   189	    if (pestana !== 'sin_movimiento' || yo?.id == null || cola == null) return
   190	    if (colaOp.enVuelo || splashVisible) return
   191	    if (visitaAnotadaRef.current === yo.id) return
   192	    visitaAnotadaRef.current = yo.id
   193	    const fotoAnterior = leerFotoVisita(yo.id)
   194	    guardarFotoVisita(yo.id, fotoDeVisita(cola.estancados, Date.now()))
   195	    setVisitaCongelada({
   196	      novedades: derivarNovedades(cola.estancados, fotoAnterior),
   197	      recortada: cola.estancados.length >= TOPE_ESTANCADOS,
   198	    })
   199	  }, [pestana, cola, colaOp.enVuelo, splashVisible, yo?.id])
   200	  const novedadesVisita = visitaCongelada?.novedades ?? null
   201	  const resumenVisita = resumenNovedades(
   202	    novedadesVisita,
   203	    visitaCongelada?.recortada === true ? TOPE_ESTANCADOS : undefined,
   204	  )
   205	  const filasCola = pestana === 'urgente' ? urgentes : (cola?.items ?? [])
   206	  // Total real de la pestaña activa, para que el botón de expandir no prometa
   207	  // menos de lo que existe cuando el RPC recortó las filas.
   208	  const totalPestanaActiva = pestana === 'todo' ? (cola?.total ?? 0) : urgenteTotal
   209	
   210	  const errorIndicadores = !yo?.demo
   211	    && Boolean(resumenOp.error || (modoSla.legado && colaOp.error) || vendedoresOp.error)
   212	  const reintentarIndicadores = () => {
   213	    if (resumenOp.error) void resumenOp.recargar()
   214	    if (colaOp.error) void colaOp.recargar()
   215	    if (vendedoresOp.error) void vendedoresOp.recargar()
   216	  }
   217	
   218	  // ── F3: «Hoy, tres cosas» — el sistema prioriza el día (ley de Tesler). ──
   219	  // Mismas fuentes que ya están en pantalla; sin dato no hay tarjeta.
   220	  const cosas = useMemo(
   221	    () => tresCosasDeHoy({
   222	      cola,
   223	      totalPorRepartir,
   224	      esperaMasLargaReparto,
   225	      vendedoresAgenda: datosAgenda?.vendedores ?? [],
   226	    }),
   227	    [cola, totalPorRepartir, esperaMasLargaReparto, datosAgenda],
   228	  )
   229	  // «Ver →» de la franja: selecciona la pestaña y le LLEVA el foco (el
   230	  // focus() también hace scroll hasta la tarjeta de la cola).
   231	  const irAPestanaCola = (destino: PestanaCola) => {
   232	    elegirPestana(destino)
   233	    requestAnimationFrame(() => {
   234	      document.getElementById(`tab-cola-${destino}`)?.focus()
   235	    })
   236	  }
   237	
   238	  return (
   239	    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
   240	      {/* ── F3: la franja manda — máximo tres intervenciones, luego consulta ── */}
   241	      {modoSla.legado && <TresCosas cosas={cosas} onIrAPestana={irAPestanaCola} />}
   242	
   243	      {/* ── KPIs del equipo — servidos por RPC (o espejo demo); sin dato: «—» ── */}
   244	      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
   245	        {/* F2 (figura-fondo): los KPIs son CONSULTA, no alarma — iconos en
   246	            neutro. Desde F3 TODOS: la urgencia de «Nuevos sin responder»
   247	            vive en la franja, que es su reemplazo. */}
   248	        <KpiCard
   249	          label="Pronóstico de capital abierto"
   250	          // `capitalPrincipal` y NO `totalEnSoles`: esto es PRONÓSTICO, no
   251	          // cumplimiento, y no se convierte a una tasa que aquí no se rotula.
   252	          // Fijar PEN a mano titulaba «S/ 0» a un equipo que vende en dólares.
   253	          value={capitalPronostico ? capitalPronostico.valor : '—'}
   254	          icon={Wallet}
   255	          color={SEMAFORO.neutro}
   256	          sub={
   257	            capitalPronostico?.otra
   258	              ? `Pipeline (PEN) · +${capitalPronostico.otra} aparte`
   259	              : capitalPronostico?.soloDolares
   260	                ? 'Pipeline (USD)'
   261	                : resumen && resumen.capital.asignado.pen === 0 && resumen.totales.asignados > 0
   262	                  ? 'Sin montos estimados — complétalos en cada ficha'
   263	                  : 'Pipeline (PEN) · abiertos con analista'
   264	          }
   265	          delay={0}
   266	        />
   267	        <KpiCard
   268	          label="Leads activos del equipo"
   269	          value={resumen ? String(resumen.totales.asignados) : '—'}
   270	          icon={Users}
   271	          color={SEMAFORO.neutro}
   272	          sub={`${ambito.vendedores.length} ${ambito.vendedores.length === 1 ? 'analista' : 'analistas'} a cargo`}
   273	          delay={60}
   274	        />
   275	        {/* Sin payload, los subs NO afirman estados positivos («todos
   276	            contactados», «bandeja vacía»): sin dato no hay afirmación. */}
   277	        <KpiCard
   278	          label="Nuevos sin responder"
   279	          value={cola ? String(cola.porBucket.sin_responder ?? 0) : '—'}
   280	          icon={AlertTriangle}
   281	          color={SEMAFORO.neutro}
   282	          sub={
   283	            cola == null
   284	              ? 'Sin dato por ahora'
   285	              : (cola.porBucket.sin_responder ?? 0) > 0
   286	                ? 'Sin primer contacto'
   287	                : 'Todos los nuevos fueron contactados'
   288	          }
   289	          delay={120}
   290	        />
   291	        <a
   292	          href={hashDe('derivaciones')}
   293	          aria-label={etiquetaAccesoReparto}
   294	          className="relative block h-full rounded-xl text-inherit no-underline outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 focus-visible:ring-offset-2 focus-visible:ring-offset-background"
   295	        >
   296	          {/* F2: fuera el acento ámbar — la urgencia del reparto vive en la
   297	              campana (grupo) y desde F3 en la franja; el KPI es el conteo. */}
   298	          <KpiCard
   299	            label="Por repartir"
   300	            value={totalPorRepartir == null ? '—' : String(totalPorRepartir)}
   301	            icon={Inbox}
   302	            color={SEMAFORO.neutro}
   303	            sub={detalleReparto}
   304	            delay={180}
   305	          />
   306	        </a>
   307	      </div>
   308	
   309	      <AvisoDegradacion
   310	        activo={errorIndicadores}
   311	        queReintenta="de los indicadores del equipo"
   312	        onReintentar={reintentarIndicadores}
   313	      >
   314	        No se pudieron cargar algunos indicadores del equipo. Se muestran «—» para no inventar cifras.
   315	      </AvisoDegradacion>
   316	
   317	      <div className="grid gap-4 lg:grid-cols-5">
   318	        <div className="space-y-4 lg:col-span-3">
   319	          {/* ── Cola del equipo (con dueño de cada item) ── */}
   320	          <SlaOperacionBoundary legado={(
   321	          <Card className="overflow-hidden">
   322	            <SectionHead
   323	              icon={ListChecks}
   324	              title="Cola del equipo"
   325	              right={
   326	                cola ? (
   327	                  // Patrón tablist de la casa (ranking-vendedores): aria-selected
   328	                  // + aria-controls, tabindex itinerante y flechas. Sin el
   329	                  // conteo en el nombre accesible el lector de pantalla no
   330	                  // sabría cuál pestaña tiene trabajo.
   331	                  <div role="tablist" aria-label="Filtrar la cola" className="inline-flex rounded-lg bg-muted/60 p-0.5">
   332	                    {PESTANAS_COLA.map((p, indice) => (
   333	                      <button
   334	                        key={p.id}
   335	                        id={`tab-cola-${p.id}`}
   336	                        type="button"
   337	                        role="tab"
   338	                        aria-selected={pestana === p.id}
   339	                        aria-controls="panel-cola"
   340	                        aria-label={`${p.label}: ${conteoPestana[p.id]}`}
   341	                        tabIndex={pestana === p.id ? 0 : -1}
   342	                        onClick={() => elegirPestana(p.id)}
   343	                        onKeyDown={(e) => {
   344	                          // Flechas con vuelta + Home/End (patrón APG completo).
   345	                          const destino = e.key === 'ArrowRight'
   346	                            ? (indice + 1) % PESTANAS_COLA.length
   347	                            : e.key === 'ArrowLeft'
   348	                              ? (indice - 1 + PESTANAS_COLA.length) % PESTANAS_COLA.length
   349	                              : e.key === 'Home'
   350	                                ? 0
   351	                                : e.key === 'End'
   352	                                  ? PESTANAS_COLA.length - 1
   353	                                  : null
   354	                          if (destino == null) return
   355	                          e.preventDefault()
   356	                          const siguiente = PESTANAS_COLA[destino]
   357	                          if (!siguiente) return
   358	                          elegirPestana(siguiente.id)
   359	                          document.getElementById(`tab-cola-${siguiente.id}`)?.focus()
   360	                        }}
   361	                        className={cn(
   362	                          // Fitts: min-h para un objetivo táctil cómodo.
   363	                          'min-h-7 cursor-pointer rounded-md px-3 py-1.5 text-[11px] font-semibold tabular-nums transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
   364	                          pestana === p.id
   365	                            ? 'bg-card text-foreground shadow-sm'
   366	                            // Gris FUERTE: 11px sobre bg-muted no llega a 4.5:1
   367	                            // con el muted normal (revisor a11y, M1).
   368	                            : 'text-muted-foreground-strong hover:text-foreground',
   369	                        )}
   370	                      >
   371	                        {p.label} <span aria-hidden>{conteoPestana[p.id]}</span>
   372	                      </button>
   373	                    ))}
   374	                  </div>
   375	                ) : (
   376	                  <span className="text-xs text-muted-foreground">—</span>
   377	                )
   378	              }
   379	            />
   380	            {cola == null ? (
   381	              <CardContent className="pb-5 pt-0">
   382	                <p className="text-sm text-muted-foreground">
   383	                  {colaOp.error
   384	                    ? 'La cola del equipo no está disponible en este momento.'
   385	                    : 'Cargando la cola del equipo…'}
   386	                </p>
   387	              </CardContent>
   388	            ) : pestana === 'sin_movimiento' ? (
   389	              // ── Sin movimiento (≥5 días) — bloque estancados del RPC. El tope
   390	              //    de 50 es señal, no listado: con 50 justos la pestaña dice 50+.
   391	              //    tabIndex 0 SOLO en el panel vacío (patrón WAI-ARIA: el panel
   392	              //    sin interactivos debe ser enfocable para que Tab no lo salte). ──
   393	              <div
   394	                id="panel-cola"
   395	                role="tabpanel"
   396	                aria-labelledby="tab-cola-sin_movimiento"
   397	                tabIndex={cola.estancados.length === 0 ? 0 : undefined}
   398	              >
   399	                {cola.estancados.length === 0 ? (
   400	                  <CardContent className="pb-5 pt-0">
   401	                    <p className="text-sm text-muted-foreground">
   402	                      Ningún lead del equipo lleva 5 días o más sin actividad.
   403	                    </p>
   404	                  </CardContent>
   405	                ) : (
   406	                  <>
   407	                    {/* F4.3: el resumen de novedades va ANTES de la lista —
   408	                        es la razón para escanearla. Solo existe si hay algo
   409	                        que decir (el silencio también es información). */}
   410	                    {resumenVisita != null && (
   411	                      <p className="border-t border-border/60 px-5 py-2 text-[11px] font-semibold text-muted-foreground-strong">
   412	                        {resumenVisita}
   413	                      </p>
   414	                    )}
   415	                    <div className="divide-y divide-border/60 border-t border-border/60">
   416	                      {cola.estancados.map((a) => {
   417	                        // F2: la gravedad va UNA vez, en la tira (rojo desde 7
   418	                        // días, ámbar 5–6); el texto queda en gris de contexto.
   419	                        // F4.3: la novedad es CATEGÓRICA, no de severidad —
   420	                        // chip violeta para el que entró; el que cruzó a
   421	                        // crítico ya tiene la tira roja y lo dice el texto.
   422	                        const esNuevo = novedadesVisita?.nuevos.has(a.leadId) === true
   423	                        const cruzoACritico = novedadesVisita?.agravados.has(a.leadId) === true
   424	                        const vendedor = (a.vendedorId != null ? nombrePorId.get(a.vendedorId) : null) ?? 'sin asignar'
   425	                        return (
   426	                          <button
   427	                            key={a.leadId}
   428	                            type="button"
   429	                            onClick={() => abrirLead(a.leadId)}
   430	                            // El label DICTA todo lo visible: el aria-label
   431	                            // pisa el contenido para un SR, así que lleva al
   432	                            // analista (a11y M1: de quién es el lead es parte
   433	                            // de la decisión), los días (la criticidad no
   434	                            // puede vivir solo en la tira de color) y el
   435	                            // literal del chip («nuevo aquí») para que el
   436	                            // dictado por voz también lo alcance (2.5.3).
   437	                            aria-label={`Abrir ficha de ${a.nombre} (${vendedor}), sin actividad ${haceTexto(a.dias)}${
   438	                              esNuevo
   439	                                ? ', nuevo aquí desde tu última visita'
   440	                                : cruzoACritico ? ', crítico desde tu última visita' : ''
   441	                            }`}
   442	                            className="flex w-full cursor-pointer items-center gap-2.5 border-l-[3px] py-2.5 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   443	                            style={{ borderLeftColor: a.dias >= 7 ? SEMAFORO.critico : SEMAFORO.atencion }}
   444	                          >
   445	                            <div className="min-w-0 flex-1 leading-tight">
   446	                              <p className="truncate text-sm font-semibold">
   447	                                {a.nombre}{' '}
   448	                                <span className="text-xs font-medium text-muted-foreground">
   449	                                  ({vendedor})
   450	                                </span>
   451	                              </p>
   452	                              <p className="text-[11px] font-medium text-muted-foreground">
   453	                                Sin actividad {haceTexto(a.dias)}
   454	                                {/* Gris FUERTE (a11y F4.3 #2): es la única
   455	                                    señal textual del cruce y el gris débil a
   456	                                    11px roza el 4.5:1 en hover. */}
   457	                                {cruzoACritico && (
   458	                                  <span className="text-muted-foreground-strong"> · crítico desde tu última visita</span>
   459	                                )}
   460	                              </p>
   461	                            </div>
   462	                            {esNuevo && (
   463	                              <Badge color={SEMAFORO.violeta} variant="outline" className="shrink-0 whitespace-nowrap">
   464	                                Nuevo aquí
   465	                              </Badge>
   466	                            )}
   467	                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   468	                          </button>
   469	                        )
   470	                      })}
   471	                    </div>
   472	                  </>
   473	                )}
   474	              </div>
   475	            ) : filasCola.length === 0 ? (
   476	              <CardContent id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} tabIndex={0} className="pb-5 pt-0">
   477	                <p className="text-sm text-muted-foreground">
   478	                  {pestana === 'urgente'
   479	                    ? 'Nada urgente — ninguna fila crítica ni media en la cola.'
   480	                    : 'Sin pendientes — el equipo está al día con todos sus leads abiertos.'}
   481	                </p>
   482	              </CardContent>
   483	            ) : (
   484	              <div id="panel-cola" role="tabpanel" aria-labelledby={`tab-cola-${pestana}`} className="divide-y divide-border/60 border-t border-border/60">
   485	                {/* Fila = div role="button" (no <button>: contiene los links de
   486	                    AccionesContacto y un botón no puede anidar interactivos).
   487	                    F2 (pregnancia): la severidad se dice UNA vez — la tira de
   488	                    3 px. Fuera el punto, el badge de etapa y el azul del monto;
   489	                    la etapa va en texto plano delante del motivo. El pl de
   490	                    17 px compensa los 3 px de la tira: el contenido queda a
   491	                    20 px, alineado con la cabecera (Codex F2). */}
   492	                {(colaExpandida ? filasCola : filasCola.slice(0, COLA_VISIBLES)).map((i) => {
   493	                  const abrir = () => abrirLead(i.lead.id)
   494	                  return (
   495	                    <div
   496	                      key={i.lead.id}
   497	                      role="button"
   498	                      tabIndex={0}
   499	                      data-sev={i.sev}
   500	                      onClick={abrir}
   501	                      onKeyDown={(e) => {
   502	                        if (e.key === 'Enter' || e.key === ' ') {
   503	                          e.preventDefault()
   504	                          abrir()
   505	                        }
   506	                      }}
   507	                      aria-label={`Abrir ficha de ${i.lead.nombre_completo}`}
   508	                      className="flex w-full cursor-pointer items-center gap-3 border-l-[3px] py-3 pl-[17px] pr-5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   509	                      style={{ borderLeftColor: i.sev === 'baja' ? 'transparent' : SEV_COLOR[i.sev] }}
   510	                    >
   511	                      <div className="min-w-0 flex-1 leading-tight">
   512	                        <p className="truncate text-sm font-semibold">{i.lead.nombre_completo}</p>
   513	                        <p className="truncate text-xs text-muted-foreground">
   514	                          {BUCKET_LABEL[i.bucket]} · {i.motivo}
   515	                        </p>
   516	                      </div>
   517	                      {i.lead.monto_estimado != null && (
   518	                        <span className="hidden shrink-0 text-xs font-semibold tabular-nums text-muted-foreground sm:inline">
   519	                          {moneyK(i.lead.monto_estimado, i.lead.moneda)}
   520	                        </span>
   521	                      )}
   522	                      {i.lead.vendedor_nombre ? (
   523	                        <span className="flex shrink-0 items-center gap-1.5">
   524	                          <Avatar nombre={i.lead.vendedor_nombre} className="size-6 text-[9px]" />
   525	                          <span className="hidden max-w-[110px] truncate text-xs text-muted-foreground md:inline">
   526	                            {i.lead.vendedor_nombre}
   527	                          </span>
   528	                        </span>
   529	                      ) : (
   530	                        <span className="shrink-0 text-xs font-medium text-muted-foreground">sin asignar</span>
   531	                      )}
   532	                      <AccionesContacto lead={i.lead} compacto />
   533	                      <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
   534	                    </div>
   535	                  )
   536	                })}
   537	                {filasCola.length > COLA_VISIBLES && (
   538	                  <button
   539	                    type="button"
   540	                    onClick={() => setColaExpandida((e) => !e)}
   541	                    aria-expanded={colaExpandida}
   542	                    className="flex w-full cursor-pointer items-center justify-center gap-1 px-5 py-2.5 text-xs font-semibold text-muted-foreground transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/40"
   543	                  >
   544	                    <ChevronRight
   545	                      className={cn('size-3.5 shrink-0 transition-transform', colaExpandida && 'rotate-90')}
   546	                      aria-hidden
   547	                    />
   548	                    {colaExpandida
   549	                      ? `Mostrar solo los ${COLA_VISIBLES} más urgentes`
   550	                      // Con más pendientes que el p_limite del RPC, el botón no
   551	                      // puede prometer el total de la pestaña: dice lo que muestra.
   552	                      : totalPestanaActiva > filasCola.length
   553	                        ? `Ver los ${filasCola.length} más urgentes de ${totalPestanaActiva}`
   554	                        : `Ver los ${filasCola.length} pendientes`}
   555	                  </button>
   556	                )}
   557	              </div>
   558	            )}
   559	          </Card>
   560	          )}>
   561	            <Card>
   562	              <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
   563	                <div className="space-y-1">
   564	                  <h2 className="text-sm font-bold">Seguimiento del equipo</h2>
   565	                  <p className="text-xs text-muted-foreground">Prioriza las gestiones y revisa los plazos de cada analista.</p>
   566	                </div>
   567	                <a href={hashDe('seguimiento')} className="inline-flex min-h-9 items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
   568	                  Abrir seguimiento <ChevronRight className="size-4" aria-hidden />
   569	                </a>
   570	              </CardContent>
   571	            </Card>
   572	          </SlaOperacionBoundary>
   573	
   574	          {/* Rentabilidad R3: tus solicitudes de tasa en curso (solo si hay). */}
   575	          <TasasAutorizadasAnalistaPanel />
   576	
   577	          {/* ── Agenda del equipo (Fase F — quién registra, cierra y arrastra) ── */}
   578	          <AgendaEquipoPanel
   579	            datos={datosAgenda}
   580	            cargando={cargandoAgenda}
   581	            error={errorAgenda}
   582	            modoDemo={yo?.demo === true}
   583	            onReintentar={recargarAgenda}
   584	            equipo={equipo}
   585	          />
   586	        </div>
   587	        <div className="space-y-4 lg:col-span-2">
   588	          {/* ── Tu equipo hoy (semáforo por analista) ── */}
   589	          <Card className="overflow-hidden">
   590	            <SectionHead
   591	              icon={UsersRound}
   592	              title="Tu equipo hoy"
   593	              right={tc ? (
   594	                <span className="text-xs text-muted-foreground">
   595	                  Capital en proceso · {rotuloTipoCambio(tc.promedio, tc.fuente)}
   596	                </span>
   597	              ) : undefined}
   598	            />
   599	            {rank == null ? (
   600	              <CardContent className="pb-5 pt-0">
   601	                <p className="text-sm text-muted-foreground">
   602	                  {vendedoresOp.error
   603	                    ? 'El resumen por analista no está disponible en este momento.'
   604	                    : 'Cargando el resumen por analista…'}
   605	                </p>
   606	              </CardContent>
   607	            ) : rank.length === 0 ? (
   608	              <CardContent className="pb-5 pt-0">
   609	                <p className="text-sm text-muted-foreground">Sin analistas a cargo.</p>
   610	              </CardContent>
   611	            ) : (
   612	              <div className="divide-y divide-border/60 border-t border-border/60">
   613	                {rank.map((r) => {
   614	                  const c = semaforoDias(r.diasSinActividadMax)
   615	                  // Rezago de agenda del miembro (mismos umbrales del panel
   616	                  // Agenda del equipo: ámbar por rezago, rojo solo no-shows ≥2).
   617	                  const rez = rezagosAgenda.get(r.m.perfil_id)
   618	                  // El rezago de agenda TAMBIÉN es señal: sin esto, quien tocó
   619	                  // ayer pero arrastra 10 vencidas quedaba sin ninguna marca
   620	                  // visual (hallazgo IMPORTANTE de Codex sobre F2).
   621	                  const conRezagoAgenda = rez != null && (rez.vencidas > 0 || rez.leads_sin_accion > 0)
   622	                  const colorPunto = r.activos === 0
   623	                    ? SEMAFORO.neutro
   624	                    : c !== SEMAFORO.ok
   625	                      ? c
   626	                      : SEMAFORO.atencion
   627	                  const cap = totalEnSoles(r.capitalPEN, r.capitalUSD, tc?.promedio)
   628	                  return (
   629	                    <div key={r.m.perfil_id} className="px-5 py-3">
   630	                      <div className="flex items-center gap-2.5">
   631	                        <Avatar nombre={r.m.nombre_completo} color={SEMAFORO.ok} className="size-9" />
   632	                        <div className="min-w-0 flex-1 leading-tight">
   633	                          <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
   634	                          <p className="text-[11px] tabular-nums text-muted-foreground">
   635	                            {r.activos} activos · {r.conversion == null
   636	                              ? r.conversionDisponible && r.divisorConversion === 0
   637	                                ? 'sin divisor mensual'
   638	                                : 'dato de conversión no disponible'
   639	                              : `${textoConversionOperativa(r.conversion)} conversión`}
   640	                            {r.operacionesCartera != null && r.operacionesCartera > 0
   641	                              ? ` · ${numero(r.operacionesCartera)} de cartera`
   642	                              : ''}
   643	                            {r.sinTocar > 0 ? ` · ${r.sinTocar} sin tocar` : ''}
   644	                          </p>
   645	                        </div>
   646	                        {/* Decisión #10: el total unificado es el número grande y el
   647	                            desglose por moneda va debajo. Sin TC degrada al PEN de
   648	                            siempre — el USD no entra al total sin una tasa real. */}
   649	                        <div className="shrink-0 text-right leading-tight">
   650	                          <p className="text-sm font-extrabold tabular-nums text-foreground">
   651	                            {cap.total != null ? moneyK(cap.total) : '—'}
   652	                          </p>
   653	                          <DesgloseMonedas pen={r.capitalPEN} usd={r.capitalUSD} tc={cap.tc} compacto />
   654	                        </div>
   655	                      </div>
   656	                      <div className="mt-1.5 flex flex-wrap items-center gap-x-1.5 gap-y-1 pl-[46px]">
   657	                        {/* F2: el punto solo cuando HAY señal (ámbar 2–5 d,
   658	                            rojo >5 d, neutro sin cartera). Pintar «al día» de
   659	                            azul en cada fila gastaba el color en nada. Sin
   660	                            leads abiertos no hay «al día» que celebrar:
   661	                            `semaforoDias(0)` devolvía azul y un analista sin
   662	                            cartera se pintaba como el que va al corriente. */}
   663	                        {(r.activos === 0 || c !== SEMAFORO.ok || conRezagoAgenda) && (
   664	                          <span
   665	                            data-testid="equipo-semaforo"
   666	                            className="size-2 shrink-0 rounded-full"
   667	                            style={{ background: colorPunto }}
   668	                            aria-hidden
   669	                          />
   670	                        )}
   671	                        <span className="text-[11px] text-muted-foreground">
   672	                          {r.activos === 0
   673	                            ? 'Sin leads abiertos'
   674	                            : `Última actividad ${haceTexto(r.diasSinActividadMax)}`}
   675	                          {/* El rezago va en TEXTO pegado a la persona (aquí se
   676	                              juzga, decisión 1 del 2026-08-23); el único chip
   677	                              es el no-show repetido — uno de los dos rojos del
   678	                              presupuesto de color. */}
   679	                          {rez != null && rez.vencidas > 0
   680	                            && ` · ${rez.vencidas} ${rez.vencidas === 1 ? 'vencida' : 'vencidas'}`}
   681	                          {rez != null && rez.leads_sin_accion > 0
   682	                            && ` · ${rez.leads_sin_accion} sin acción`}
   683	                        </span>
   684	                        {rez != null && rez.no_asistio >= 2 && (
   685	                          <span className="ml-auto">
   686	                            {/* solid: el soft (rojo sobre tinte) da 4.01:1 a 11px
   687	                                y no llega a AA (revisor a11y, M2). */}
   688	                            <Badge color={SEMAFORO.critico} variant="solid">{rez.no_asistio} no asistió</Badge>
   689	                          </span>
   690	                        )}
   691	                      </div>
   692	                    </div>
   693	                  )
   694	                })}
   695	              </div>
   696	            )}
   697	          </Card>
   698	
   699	          {/* ── Cumplimiento confirmado del equipo ── */}
   700	          <Card>
   701	            <SectionHead
   702	              icon={Target}
   703	              title="Cumplimiento del equipo"
   704	              right={<span className="text-xs text-muted-foreground">contratos confirmados · este mes</span>}
   705	            />
   706	            <CardContent className="space-y-4 pb-5 pt-0">
   707	              {filasMeta.map((f) => (
   708	                <div key={f.label}>
   709	                  <div className="mb-1.5 flex items-baseline justify-between gap-2">
   710	                    <span className="text-xs font-semibold text-foreground/80">{f.label}</span>
   711	                    <span className="text-xs font-bold tabular-nums text-primary">{f.txt}</span>
   712	                  </div>
   713	                  {f.nota && (
   714	                    <p className="mb-1 text-[10.5px] tabular-nums text-muted-foreground">{f.nota}</p>
   715	                  )}
   716	                  {f.sinDato ? (
   717	                    <p className="text-[10.5px] text-muted-foreground">{f.sinDato}</p>
   718	                  ) : (
   719	                    <Progress value={f.pct} color={colorMeta(f.pct)} />
   720	                  )}
   721	                </div>
   722	              ))}
   723	              <p className="text-[10.5px] text-muted-foreground">
   724	                El capital en dólares entra al total convertido a tipo de cambio real. El capital abierto de arriba es pronóstico y no cuenta como cumplimiento.
   725	              </p>
   726	              {hayErrorMensual && (
   727	                <Button variant="ghost" size="sm" onClick={reintentarMensual}>
   728	                  Reintentar
   729	                </Button>
   730	              )}
   731	            </CardContent>
   732	          </Card>
   733	
   734	          {/* ── Por empresa: de dónde vino cada sol (Avance vs. COOPAC). Se
   735	               oculta solo si el mes no tiene cierres en cooperativas. ── */}
   736	          <DesglosePorEmpresa
   737	            demo={yo?.demo === true}
   738	            porVendedor={cumplimientoMensual?.porVendedor ?? null}
   739	          />
   740	        </div>
   741	      </div>
   742	
   743	      <p className="text-[11px] text-muted-foreground">
   744	        {yo?.demo ? 'Demo — ves' : 'Ves'} solo a tu equipo y tu bandeja de reparto; cada rol ve únicamente lo que le corresponde.
   745	      </p>
   746	    </div>
   747	  )
   748	}
```

### `app/src/lib/metricas-agenda.ts (esquema)`
```
    40	const IdMiembroSchema = v.pipe(v.string(), v.minLength(1))
    41	const TextoNoVacioSchema = v.pipe(v.string(), v.minLength(1))
    42	const FechaSchema = v.pipe(v.string(), v.isoDate())
    43	const FechaHoraSchema = v.pipe(
    44	  v.string(),
    45	  v.check((valor) => Number.isFinite(Date.parse(valor)), 'Fecha/hora inválida'),
    46	)
    47	const EnteroNoNegativoSchema = v.pipe(v.number(), v.integer(), v.minValue(0))
    48	const NumeroNoNegativoSchema = v.pipe(v.number(), v.finite(), v.minValue(0))
    49	
    50	const VendedorAgendaSchema = v.strictObject({
    51	  vendedor_id: IdMiembroSchema,
    52	  nombre: TextoNoVacioSchema,
    53	  rol: v.picklist(['vendedor', 'supervisor']),
    54	  activo: v.boolean(),
    55	  toques: EnteroNoNegativoSchema,
    56	  toques_por_dia: NumeroNoNegativoSchema,
    57	  reuniones_realizadas: EnteroNoNegativoSchema,
    58	  completadas: EnteroNoNegativoSchema,
    59	  no_asistio: EnteroNoNegativoSchema,
    60	  canceladas: EnteroNoNegativoSchema,
    61	  // OPCIONALES A PROPÓSITO, aunque el servidor nuevo SIEMPRE las manda. Este
    62	  // objeto es `strictObject`: una clave que sobra hace fallar la pantalla
    63	  // entera. Declararlas opcionales es lo que permite que la migración y el
    64	  // deploy del front no tengan que ser simultáneos — en cualquiera de los dos
    65	  // órdenes el panel sigue en pie, y con la BD vieja simplemente no hay
    66	  // desglose que pintar. `?? 0` en los consumidores, nunca `!`.
    67	  canceladas_asesor: v.optional(EnteroNoNegativoSchema),
    68	  canceladas_sistema: v.optional(EnteroNoNegativoSchema),
    69	  canceladas_ajenas: v.optional(EnteroNoNegativoSchema),
    70	  pct_completadas: v.nullable(v.number()),
    71	  tareas_creadas: EnteroNoNegativoSchema,
    72	  reuniones_agendadas: EnteroNoNegativoSchema,
    73	  reprogramaciones: EnteroNoNegativoSchema,
    74	  pendientes: EnteroNoNegativoSchema,
    75	  vencidas: EnteroNoNegativoSchema,
    76	  leads_sin_accion: EnteroNoNegativoSchema,
    77	})
    78	
    79	export const MetricasAgendaSchema = v.strictObject({
    80	  version: v.literal(1),
```

### `app/src/components/ui/avatar.tsx`
```
     1	import type { JSX } from 'react'
     2	import { cn } from '@/lib/utils'
     3	import { iniciales } from '@/lib/format'
     4	import type { Genero } from '@/lib/tipos'
     5	
     6	// Siluetas humanas — diseño Claude Design v2 (Avatares Silueta v2). Todas
     7	// `fill="currentColor"`, viewBox 0 0 24 24, fondo transparente → se tiñen por CSS.
     8	// Hay 3 PEINADOS por género: se elige uno por hash del nombre, así cada persona
     9	// tiene su variante y no se ven todas iguales, sin perder la lectura de género.
    10	const SILUETAS: Record<Genero, string[][]> = {
    11	  F: [
    12	    // ondas a los hombros
    13	    [
    14	      'M12 2.8c-3.5 0-5.8 2.5-5.8 5.9 0 2.2-.4 3.9-1.2 5.4-.4.8 0 1.8 1 1.9 1.5.2 2.8-.1 3.8-.8.7.3 1.4.5 2.2.5s1.5-.2 2.2-.5c1 .7 2.3 1 3.8.8 1-.1 1.4-1.1 1-1.9-.8-1.5-1.2-3.2-1.2-5.4 0-3.4-2.3-5.9-5.8-5.9z',
    15	      'M12 15.1c-3 0-5.6 1-6.9 2.6-.7.9-.1 2.2 1.1 2.2h11.6c1.2 0 1.8-1.3 1.1-2.2-1.3-1.6-3.9-2.6-6.9-2.6z',
    16	    ],
    17	    // bob
    18	    [
    19	      'M12 3c-3.3 0-5.5 2.4-5.5 5.6 0 1.6-.15 2.9-.5 4.1-.3 1 .45 2 1.5 2h9c1.05 0 1.8-1 1.5-2-.35-1.2-.5-2.5-.5-4.1C17.5 5.4 15.3 3 12 3z',
    20	      'M12 14c-4.5 0-7.6 2.3-7.6 5.4v.2c0 .8.6 1.4 1.4 1.4h12.4c.8 0 1.4-.6 1.4-1.4v-.2c0-3.1-3.1-5.4-7.6-5.4z',
    21	    ],
    22	    // moño / recogido
    23	    [
    24	      'M12 1.6a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z',
    25	      'M12 4.4a3.7 3.7 0 1 1 0 7.4 3.7 3.7 0 0 1 0-7.4z',
    26	      'M12 14.2c-4.4 0-7.4 2.3-7.4 5.3v.2c0 .8.6 1.4 1.4 1.4h12c.8 0 1.4-.6 1.4-1.4v-.2c0-3-3-5.3-7.4-5.3z',
    27	    ],
    28	  ],
    29	  M: [
    30	    // corto clásico (con cuello)
    31	    [
    32	      'M12 3.7a3.9 3.9 0 1 1 0 7.8 3.9 3.9 0 0 1 0-7.8z',
    33	      'M10.6 11v2.1c-3.3.5-5.9 2.1-6.7 4.3-.4 1 .3 2.1 1.4 2.1h13.4c1.1 0 1.8-1.1 1.4-2.1-.8-2.2-3.4-3.8-6.7-4.3V11c-.45.19-.92.29-1.4.29-.48 0-.95-.1-1.4-.29z',
    34	    ],
    35	    // con volumen / texturizado
    36	    [
    37	      'M12 2.7c-2.9 0-5 2-5.2 4.8 0 .4.3.6.7.5 1.6-.5 4-1.4 5.3-2.8.9.9 2.6 1.9 4.4 2.4.4.1.8-.2.7-.6C17.5 4.5 14.9 2.7 12 2.7z',
    38	      'M12 4.4a3.7 3.7 0 1 1 0 7.4 3.7 3.7 0 0 1 0-7.4z',
    39	      'M10.6 11.2v1.9c-3.3.5-5.9 2.1-6.7 4.3-.4 1 .3 2.1 1.4 2.1h13.4c1.1 0 1.8-1.1 1.4-2.1-.8-2.2-3.4-3.8-6.7-4.3v-1.9c-.45.19-.92.29-1.4.29-.48 0-.95-.1-1.4-.29z',
    40	    ],
    41	    // rapado (hombros anchos)
    42	    [
    43	      'M12 3.7a3.9 3.9 0 1 1 0 7.8 3.9 3.9 0 0 1 0-7.8z',
    44	      'M12 13.6c-4.6 0-7.8 2.4-7.8 5.6v.2c0 .8.6 1.4 1.4 1.4h12.8c.8 0 1.4-.6 1.4-1.4v-.2c0-3.2-3.2-5.6-7.8-5.6z',
    45	    ],
    46	  ],
    47	}
    48	
    49	const COLOR_GENERO: Record<Genero, string> = { F: '#7c3aed', M: '#2563eb' }
    50	
    51	/** Hash estable del nombre → índice de peinado dentro del set del género. */
    52	function indicePeinado(nombre: string | null | undefined, n: number): number {
    53	  let h = 0
    54	  for (const c of nombre ?? '') h = (h * 31 + c.charCodeAt(0)) >>> 0
    55	  return n > 0 ? h % n : 0
    56	}
    57	
    58	const BASE = 'inline-flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-full'
    59	
    60	/**
    61	 * Avatar de persona o de equipo.
    62	 * - Con género conocido (F/M) → silueta HUMANA tinteada por género, con su peinado
    63	 *   por hash del nombre.
    64	 * - Sin género (null o prop ausente) → INICIALES: distinguen a cada persona cuando
    65	 *   no hay dato (mejor que una silueta neutra idéntica para todos). Cuando el campo
    66	 *   género exista en la BD, cada lead pasa por sí solo a su silueta.
    67	 */
    68	export function Avatar({
    69	  nombre,
    70	  genero,
    71	  color = 'var(--accent)',
    72	  relleno = false,
    73	  className,
    74	}: {
    75	  nombre: string | null | undefined
    76	  genero?: Genero | null
    77	  color?: string | undefined
    78	  /**
    79	   * Iniciales en blanco sobre el color pleno: marca a la persona ELEGIDA en una
    80	   * lista (Gestión Diaria, 27/09/2026). Nunca va sola: la fila lo dice también
    81	   * con `aria-current` y con texto.
    82	   */
    83	  relleno?: boolean | undefined
    84	  className?: string | undefined
    85	}): JSX.Element {
    86	  // Silueta SOLO con género conocido; sin dato (null/ausente) → iniciales.
    87	  if (genero === 'F' || genero === 'M') {
    88	    const c = COLOR_GENERO[genero]
    89	    const set = SILUETAS[genero]
    90	    const paths = set[indicePeinado(nombre, set.length)] ?? []
    91	    return (
    92	      <span
    93	        className={cn(BASE, className)}
    94	        style={{ background: `color-mix(in srgb, ${c} 14%, transparent)`, color: c }}
    95	        aria-hidden
    96	      >
    97	        <svg viewBox="0 0 24 24" fill="currentColor" className="size-full" aria-hidden>
    98	          {paths.map((d, i) => (
    99	            <path key={i} d={d} />
   100	          ))}
   101	        </svg>
   102	      </span>
   103	    )
   104	  }
   105	
   106	  // Modo iniciales (equipo, o cuando no aplica el género de una persona).
   107	  return (
   108	    <span
   109	      className={cn(BASE, 'text-[11px] font-bold', className)}
   110	      style={relleno ? { background: color, color: '#fff' } : { background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
   111	      aria-hidden
   112	    >
   113	      {iniciales(nombre)}
   114	    </span>
   115	  )
   116	}
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
