ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 2, una pasada): REFUTA la conexión de las reuniones con clientes sin lead en la pestaña «Proyección» (front)

Contexto. CRM Avance Corp (React 19 + TS + Valibot + TanStack Query). La pestaña «Proyección» de Citas (en producción, PR #340) es una hoja por analista sobre un rango Desde–Hasta; cohorte = citas CREADAS en el rango; % Entrev. y % Conv. con las reglas de Resultados (`app/src/components/citas/atribucion.ts`, `avance.ts`). Regla del dueño: «no puede haber data distinta».

Novedad: el servidor ya tiene (instalado y verificado hoy en producción) `crm.citas_clientes_proyeccion_fn(p_desde, p_hasta)`: reuniones activas con CLIENTES SIN lead, creadas en el rango y cortadas en `generado_en`, con `analista_*`/`supervisor_*` iguales al lector de Citas, `estado` (pendiente/completada/no_show/reprogramada/cancelada), `asistencia_registrada_en`, `identidad_persona` (o `oculta:<id>`). Producción: 37 reuniones del 1 al 19/10. Errores declarados: 54000 (más de 10 000) y 57014 (tiempo, con más de ~1 000 clientes de tipo perfil).

Reglas decididas para la pantalla: una reunión con cliente sin lead es una cita de origen Cliente. CUENTA en Citas, Clientes, columnas de tiempo (por día de creación) y % Entrev. (completada = entrevista; no_show = resuelta). NO cuenta en Monto S/, Ticket cita S/ (= Monto ÷ citas con lead), % Conv. (base = personas entrevistadas de citas con lead) ni Proyectado citas S/ (se proyecta sobre las citas con lead, con sus propias tasas). Para las citas con lead todo debe seguir igual. Una sola llamada por rango; sin cifras parciales mientras cargue o si falla; en demo no se llama; con el filtro de moneda activo quedan fuera (no tienen moneda); en el embudo de Clientes salen por `identidad_persona` (las ocultas como «Cliente fuera de tu cartera»); en la lista lateral sin botón de ficha de lead.

Ejemplo del implementador: 3 citas con lead (2 entrevistas, 1 no asistió; Monto 60 000; 1 venta) + 2 reuniones de cliente (1 entrevista, 1 no asistió): Citas 5, Clientes 2, Monto 60 000, Ticket 20 000, % Entrev. 60 % (3/5), % Conv. 50 % (1/2), Proyectado = 93/19 × 66,7 % (Entrev. solo con lead) × 50 % × 20 000.

Busca con evidencia (archivo:línea del diff, caso concreto): (a) cifras que contradigan estas reglas o que cambien las de las citas con lead; (b) dobles conteos (una reunión que llegue también por el lector de Citas; claves de persona compartidas con leads que crucen ventas o entrevistas); (c) estados que mientan (carga, error, demo, rango grande, PGRST202 si la función faltara); (d) caché/refresco (clave de consulta, cadencia, una sola llamada por rango); (e) que el Proyectado use un % Entrev. distinto del que muestra la columna: ¿es defendible o confunde al usuario?; (f) pruebas que no prueben lo que dicen.

Verificación reportada (NOT RUN por ti): 7 450 pruebas en verde; 4/4 mutantes muertos (reuniones en la base de % Conv.; en las entrevistas que cierran cliente; Proyectado con el % Entrev. que las incluye; ticket y ritmo sobre todas las citas). E2E y check finales en curso.

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Diff (código)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/citas/contexto.ts b/CRM-Avance-Corp/app/src/components/citas/contexto.ts
index a4311449..f99a86f8 100644
--- a/CRM-Avance-Corp/app/src/components/citas/contexto.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/contexto.ts
@@ -3,9 +3,13 @@ import { equipoCitas } from './modelo'
 import type { CitaConLead } from './datos'
 import type { DepositoEjemplo } from './depositos'
 import type { GestionCitas } from './metas'
-/** Citas fusionadas de los meses del rango de Proyección (lo provee la pantalla). */
+import type { ReunionClienteProyeccion } from './proyeccion'
+import type { RangoProyeccion } from './proyeccion-rango'
+/** Citas fusionadas de los meses del rango de Proyección y las reuniones con clientes sin lead de ese rango (lo provee la pantalla). */
 export interface DatosProyeccionCitas {
   meses: string[]; citas: CitaConLead[]; gestion: GestionCitas | undefined; corte: string;
+  /** Rango al que corresponden `reunionesClientes` (null: aún no se pidió ninguno). */
+  rango: RangoProyeccion | null; reunionesClientes: ReunionClienteProyeccion[];
   cargando: boolean; error: string | null; onReintentar: () => void;
 }
 export interface DatosCitas {
@@ -15,8 +19,9 @@ export interface DatosCitas {
   mesInicial: string; modoDemo: boolean; meses: string[];
   cargando?: boolean; error?: string | null; onReintentar?: () => void;
   onMes?: (mes: string) => void; onAbrirLead?: (id: string, tareaId: string) => void;
-  /** Proyección avisa qué meses necesita su rango; sin cargador usa las citas de arriba. */
-  onMesesProyeccion?: (meses: string[]) => void; proyeccion?: DatosProyeccionCitas;
+  /** Proyección avisa qué meses y qué rango necesita (null o vacío: ninguno); sin cargador usa las citas de arriba. */
+  onMesesProyeccion?: (meses: string[]) => void; onRangoProyeccion?: (rango: RangoProyeccion | null) => void;
+  proyeccion?: DatosProyeccionCitas;
 }
 export const ContextoCitas = createContext<DatosCitas | null>(null)
 export function useDatosCitas() {
diff --git a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
index 540157ef..e6de2df0 100644
--- a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
@@ -80,7 +80,7 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   const consultaSesion = useConsultaGerencia()
   const guardarConsulta = conservarConsulta ? consultaSesion?.setConsulta : undefined
   const guardada = conservarConsulta ? consultaSesion?.consulta.citas : undefined
-  const { citas: CITAS, equipo: EQUIPO, gestion, corte, modoDemo, mesInicial, cargando, error: errorCarga, onReintentar, onMes, onMesesProyeccion, proyeccion } = useDatosCitas()
+  const { citas: CITAS, equipo: EQUIPO, gestion, corte, modoDemo, mesInicial, cargando, error: errorCarga, onReintentar, onMes, onMesesProyeccion, onRangoProyeccion, proyeccion } = useDatosCitas()
   const inicial = () => defaults(mesInicial)
   const desdeEnlace = () => {
     const consulta = leerHash().consultaCitas
@@ -111,6 +111,12 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   const rangoProyeccion = { desde: rangoMes.desde, hasta: rangoMes.hasta }
   const mesesProyeccion = vista === 'proyeccion' && !errorRango(rangoProyeccion) ? mesesDelRango(rangoProyeccion).join(',') : ''
   useEffect(() => { onMesesProyeccion?.(mesesProyeccion ? mesesProyeccion.split(',') : []) }, [mesesProyeccion, onMesesProyeccion])
+  // Y el rango exacto, para las reuniones con clientes sin lead (una consulta por rango).
+  const rangoPedido = mesesProyeccion ? `${rangoProyeccion.desde}|${rangoProyeccion.hasta}` : ''
+  useEffect(() => {
+    const [desde = '', hasta = ''] = rangoPedido.split('|')
+    onRangoProyeccion?.(rangoPedido ? { desde, hasta } : null)
+  }, [rangoPedido, onRangoProyeccion])
   useEffect(() => {
     guardarConsulta?.(anterior => ({ ...anterior, citas: { filtros, vista, pagina, rango: { ...rangoMes, tiempo } } }))
   }, [filtros, vista, pagina, rangoMes, tiempo, guardarConsulta])
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
index f6f3e50f..252fa7d4 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx
@@ -19,11 +19,19 @@ function MontoCita({ c }: { c: CitaProyectada }) {
   return <><span className="pc-m">{money(c.cita.monto, 'USD')} ·</span>{c.enSoles === null ? 'Pendiente de TC' : `S/ ${numero(c.enSoles)}`}</>
 }
 
+/** La persona abre su ficha de lead; una reunión con un cliente sin lead no tiene ficha que abrir. */
+function PersonaCita({ c, onAbrir }: { c: CitaProyectada; onAbrir: ((leadId: string, tareaId: string) => void) | undefined }) {
+  const leadId = c.cita.leadId
+  if (!onAbrir || leadId === null) return <span className="pc-persona">{c.cita.nombre}</span>
+  return <button type="button" className="pc-persona" onClick={() => onAbrir(leadId, c.cita.id)}>{c.cita.nombre}</button>
+}
+
 export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle: ListaProyeccion | null; onCerrar: () => void; focoRespaldo: () => HTMLElement | null }) {
   const { onAbrirLead } = useDatosCitas()
   const [aviso, setAviso] = useState('')
   const n = detalle?.lista.length ?? 0
   const cerrar = () => { setAviso(''); onCerrar() }
+  const abrirFicha = onAbrirLead && ((leadId: string, tareaId: string) => { cerrar(); requestAnimationFrame(() => requestAnimationFrame(() => onAbrirLead(leadId, tareaId))) })
   function exportar() {
     if (!detalle) return
     setAviso(descargarCsv(detalle.archivo, csvCitasProyeccion(detalle.lista)) ? `Se descargó el CSV con ${n} ${n === 1 ? 'cita' : 'citas'}.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
@@ -41,7 +49,7 @@ export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle
           <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
             <td>{c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'}</td>
             <td>{fmtFecha(c.cita.fecha)} · {c.cita.hora}</td>
-            <th scope="row">{onAbrirLead ? <button type="button" className="pc-persona" onClick={() => { cerrar(); requestAnimationFrame(() => requestAnimationFrame(() => onAbrirLead(c.cita.leadId, c.cita.id))) }}>{c.cita.nombre}</button> : <span className="pc-persona">{c.cita.nombre}</span>}</th>
+            <th scope="row"><PersonaCita c={c} onAbrir={abrirFicha} /></th>
             {detalle.conAnalista && <td>{c.cita.analistaNombre}</td>}
             <td><span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span></td>
             <td className="pc-num"><MontoCita c={c} /></td>
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
index 306c5fa4..46b3116f 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.tsx
@@ -14,7 +14,7 @@ import { fechaLocalCitas } from './fecha-comercial'
 import {
   COLUMNA_DE_ORIGEN, ORDEN_INICIAL, ORIGENES, calcularProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas,
   opcionesPersonas, type ColumnaNumerica, type ColumnaProyeccion, type FiltrosColumnas,
-  type MetricasProyeccion, type OrdenProyeccion, type OrigenCita,
+  type MetricasProyeccion, type OrdenProyeccion, type OrigenCita, type ReunionClienteProyeccion,
 } from './proyeccion'
 import {
   diasPermitidos, mesesDelRango, rotuloRango, tiempoEfectivo, type RangoProyeccion, type TiempoProyeccion, type TramoProyeccion,
@@ -53,6 +53,7 @@ const ETIQUETAS_CITAS: Record<'citas' | OrigenCita, [string, string]> = {
 }
 const etiquetaCitas = (tipo: 'citas' | OrigenCita, n: number) => ETIQUETAS_CITAS[tipo][n === 1 ? 0 : 1]
 const SIN_CITAS: never[] = []
+const SIN_REUNIONES: readonly ReunionClienteProyeccion[] = []
 const listaDe = (m: MetricasProyeccion, tipo: TipoLista) => tipo === 'citas' ? m.citas : tipo === 'monto' ? m.conMonto
   : tipo === 'entrevistas' ? m.entrevistas : tipo === 'conversion' ? m.convertidas : m[COLUMNA_DE_ORIGEN[tipo]]
 const soles = (valor: number | null) => valor === null ? '—' : `S/ ${numero(valor)}`
@@ -116,12 +117,15 @@ export interface PropsProyeccion {
 
 export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEquipo }: PropsProyeccion) {
   const datos = useDatosCitas()
-  // Con cargador, las citas son las de los meses del rango ya fusionados; sin él
-  // (ejemplo y pruebas), las de arriba. Mientras falte un mes no hay cifras.
+  // Con cargador, las citas son las de los meses del rango ya fusionados más las
+  // reuniones con clientes sin lead de ESE rango; sin él (ejemplo y pruebas), las
+  // de arriba. Mientras falte un mes o esas reuniones no hay cifras.
   const meses = mesesDelRango(rango).join(',')
   const delRango = datos.proyeccion
-  const preparado = !delRango || (delRango.meses.join(',') === meses && !delRango.cargando && !delRango.error)
+  const preparado = !delRango || (delRango.meses.join(',') === meses && delRango.rango?.desde === rango.desde
+    && delRango.rango.hasta === rango.hasta && !delRango.cargando && !delRango.error)
   const citas = preparado ? (delRango ?? datos).citas : SIN_CITAS
+  const reunionesClientes = preparado && delRango ? delRango.reunionesClientes : SIN_REUNIONES
   const gestion = (delRango ?? datos).gestion
   const corte = delRango?.corte || datos.corte
   const avance = gestion?.avance
@@ -143,9 +147,9 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
   const hoy = fechaLocalCitas(corte)
   const { tc, recargar } = useTipoCambio(citas.some(c => c.moneda === 'USD' && (c.monto ?? 0) > 0), hasta < hoy ? hasta : hoy)
   const hoja = useMemo(() => calcularProyeccion({
-    citas, filtros: { equipo }, rango: { desde, hasta }, tiempo, corte, tipoCambio: tc?.promedio,
+    citas, reunionesClientes, filtros: { equipo }, rango: { desde, hasta }, tiempo, corte, tipoCambio: tc?.promedio,
     conversiones: avance?.conversiones ?? null, poblacion: avance?.poblacion, analistaResultado: avance?.control.configuracion.analista_resultado,
-  }, columnas, orden), [citas, equipo, desde, hasta, tiempo, corte, tc?.promedio, avance, columnas, orden])
+  }, columnas, orden), [citas, reunionesClientes, equipo, desde, hasta, tiempo, corte, tc?.promedio, avance, columnas, orden])
   const vistaTiempo = tiempoEfectivo(tiempo, rango)
   const objetivos = {
     entrevistas: avance?.control.configuracion.entrevistas_porcentaje ?? gestion?.entrevistasPorcentaje ?? METAS_CITAS_INICIALES.entrevistas_porcentaje,
@@ -207,7 +211,7 @@ export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEq
   const origenMenu = menu ? ORIGEN_DE_COLUMNA[menu.columna] : undefined
 
   // Barra única: Supervisor · periodo · columnas de tiempo · acciones (estas, solo con la hoja lista).
-  const supervisores = supervisoresDe([datos.equipo, citas], equipo)
+  const supervisores = supervisoresDe([datos.equipo, citas, reunionesClientes], equipo)
   const barra = (conAcciones: boolean) => <BarraRango rango={rango} hoy={hoy} onRango={onRango}
     antes={<label className="pc-fecha pc-supervisor">Supervisor<Select aria-label="Supervisor" className="h-8" value={equipo} onChange={e => onEquipo(e.target.value)}>
       <option value="">Todos</option>{supervisores.map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
index 0171afc5..3eae0e3b 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts
@@ -11,6 +11,11 @@
 // las MISMAS reglas que Resultados (`calcularAvanceCitas`): entrevistas ÷ citas
 // resueltas y el vínculo entrevista → venta por fecha comercial y por DUEÑO de la
 // venta (`atribucion.ts`, compartido con Resultados).
+//
+// Reuniones con CLIENTES sin lead (Fase 0b, decisión de Miguel 19/10/2026): son
+// citas de origen Cliente. Cuentan en Citas, Clientes, las columnas de tiempo y
+// % Entrev.; no tienen monto ni se «convierten», así que Monto, Ticket cita,
+// % Conv. y Proyectado siguen siendo los de las citas con lead, sin cambio.
 import type { ControlCitas } from '@/lib/control-citas'
 import { tcAplicable } from '@/lib/capital-unificado'
 import { usdAPen } from '@/lib/tipo-cambio'
@@ -42,8 +47,23 @@ export interface PersonaProyeccion {
   /** Analista (y su supervisor) de origen del lead: dueño de sus ventas con la regla «asignacion». */
   analista_origen_id?: string | null | undefined; supervisor_origen_id?: string | null | undefined
 }
+/**
+ * Reunión con un cliente que no tiene lead (lector `crm.citas_clientes_proyeccion_fn`): sin lead, monto ni moneda.
+ * Analista y supervisor son los del lector; el estado, el de Citas (`ESTADOS`).
+ */
+export interface ReunionClienteProyeccion extends Pick<CitaEjemplo, 'id' | 'nombre' | 'analista' | 'analistaNombre' | 'supervisor'
+  | 'supervisorId' | 'fecha' | 'hora' | 'estado' | 'asistioEn' | 'creadoEn'> {
+  leadId: null; moneda: null; monto: null
+  /** `identidad_persona` del servidor (`oculta:<id>` si no es visible). Nunca decide ventas ni entrevistas de los leads. */
+  persona: string
+}
+/** Una cita de la hoja: del lector de Citas (con lead) o una reunión con un cliente sin lead. */
+export type CitaHoja = CitaEjemplo | ReunionClienteProyeccion
+
 export interface FuenteProyeccion {
   citas: readonly CitaEjemplo[]
+  /** Reuniones con clientes sin lead del rango; sin ellas, solo las citas con lead. */
+  reunionesClientes?: readonly ReunionClienteProyeccion[] | undefined
   /** Solo el supervisor: los demás filtros de la consulta de arriba no aplican aquí. */
   filtros: Pick<FiltrosCitas, 'equipo'>
   rango: RangoProyeccion
@@ -60,7 +80,7 @@ export interface FuenteProyeccion {
 }
 
 export interface CitaProyectada {
-  cita: CitaEjemplo
+  cita: CitaHoja
   /** Día de Lima en que se creó la cita (la cohorte y los tramos se cortan por él). */
   creada: string
   /** Identidad de la persona (misma regla que el avance mensual). */
@@ -69,11 +89,15 @@ export interface CitaProyectada {
   /** Monto en soles; null si la cita no trae monto o está en dólares sin tipo de cambio. */
   enSoles: number | null
 }
+/** Cita del lector de Citas: solo estas cuentan en Monto, Ticket cita, % Conv. y Proyectado. */
+export const conLead = (c: CitaProyectada): boolean => c.cita.leadId !== null
 
 export interface PeriodoProyeccion { desde: string; hasta: string; hoy: string; dias: number; transcurridos: number; cerrado: boolean }
 
 export interface MetricasProyeccion {
   citas: CitaProyectada[]; conMonto: CitaProyectada[]; entrevistas: CitaProyectada[]
+  /** Las citas con lead: la base de Monto, Ticket cita, % Conv. y Proyectado. */
+  citasConLead: CitaProyectada[]
   /** Base de % Entrev., como en Resultados: realizadas + no asistió. */
   resueltas: CitaProyectada[]
   /**
@@ -83,10 +107,13 @@ export interface MetricasProyeccion {
   convertidas: CitaProyectada[]
   referidos: CitaProyectada[]; clientes: CitaProyectada[]; leads: CitaProyectada[]
   montoPen: number; montoUsd: number; pendienteTc: boolean
-  /** «Ticket cita»: monto en citas ÷ citas. No es el «Ticket del mes» de Resultados (capital real ÷ clientes). */
+  /** «Ticket cita»: monto en citas ÷ citas con lead. No es el «Ticket del mes» de Resultados (capital real ÷ clientes). */
   monto: number | null; ticket: number | null
-  pctEntrevistas: number | null; pctConversion: number | null
+  /** % Entrev. de la hoja (todas las citas) y el de las citas con lead, que es el que proyecta. */
+  pctEntrevistas: number | null; pctEntrevistasConLead: number | null; pctConversion: number | null
+  /** Personas de las entrevistas CON LEAD: la base de % Conv. */
   personasEntrevistadas: number; personasClientes: number
+  /** Citas con lead esperadas al cierre del rango. */
   citasEsperadas: number | null; proyectado: number | null
   /** Las citas de cada columna de tiempo, en el orden de `HojaProyeccion.tramos`. */
   porTramo: CitaProyectada[][]
@@ -218,11 +245,21 @@ function cohorte(fuente: FuenteProyeccion, persona: (lead: string) => string, co
   const periodo = contexto.periodo
   if (!periodo) return []
   const { equipo } = fuente.filtros
+  /** Día de creación si la cita entra en la cohorte (rango y supervisor); si no, null. */
+  const creadaEnRango = (c: CitaHoja) => {
+    if (!c.creadoEn || !Number.isFinite(Date.parse(c.creadoEn)) || (equipo && c.supervisorId !== equipo)) return null
+    const creada = fechaLocalCitas(c.creadoEn)
+    return creada >= periodo.desde && creada <= periodo.hasta ? creada : null
+  }
   const lista: CitaProyectada[] = []
   for (const c of fuente.citas) {
-    if (!c.creadoEn || !Number.isFinite(Date.parse(c.creadoEn)) || (equipo && c.supervisorId !== equipo)) continue
-    const creada = fechaLocalCitas(c.creadoEn)
-    if (creada >= periodo.desde && creada <= periodo.hasta) lista.push(proyectar(c, creada, persona(c.leadId), contexto))
+    const creada = creadaEnRango(c)
+    if (creada) lista.push(proyectar(c, creada, persona(c.leadId), contexto))
+  }
+  // Las reuniones con clientes sin lead son de origen Cliente y no tienen monto.
+  for (const r of fuente.reunionesClientes ?? []) {
+    const creada = creadaEnRango(r)
+    if (creada) lista.push({ cita: r, creada, persona: r.persona, origen: 'cliente', enSoles: null })
   }
   return lista
 }
@@ -240,41 +277,50 @@ export function repartirEnTramos(lista: readonly CitaProyectada[], tramos: reado
 const suma = (lista: readonly CitaProyectada[], moneda: Moneda) =>
   lista.reduce((n, c) => n + (c.cita.moneda === moneda && c.cita.monto != null ? c.cita.monto : 0), 0)
 
+const realizada = (c: CitaProyectada) => c.cita.estado === 'realizada'
+// Como Resultados: las programadas, canceladas o aún sin resultado no son base.
+const resuelta = (c: CitaProyectada) => realizada(c) || c.cita.estado === 'no_show'
+const tasa = (parte: number, base: number) => base ? parte / base * 100 : null
+
 /** `fila`: el analista de la fila; null, el total de la hoja. */
 function medir(lista: CitaProyectada[], contexto: Contexto, fila: string | null): MetricasProyeccion {
-  const n = lista.length
-  const conMonto = lista.filter(c => c.cita.monto != null)
-  const montoPen = suma(lista, 'PEN')
-  const montoUsd = suma(lista, 'USD')
+  // Métricas de prospectos: solo las citas con lead (las reuniones con clientes sin lead no tienen monto ni se convierten).
+  const citasConLead = lista.filter(conLead)
+  const n = citasConLead.length
+  const conMonto = citasConLead.filter(c => c.cita.monto != null)
+  const montoPen = suma(citasConLead, 'PEN')
+  const montoUsd = suma(citasConLead, 'USD')
   const pendienteTc = montoUsd > 0 && contexto.tc === null
   const monto = pendienteTc ? null : montoPen + (contexto.tc === null ? 0 : usdAPen(montoUsd, contexto.tc))
   const ticket = monto !== null && n ? monto / n : null
-  const entrevistas = lista.filter(c => c.cita.estado === 'realizada')
-  // Como Resultados: las programadas, canceladas o aún sin resultado no son base.
-  const resueltas = lista.filter(c => c.cita.estado === 'realizada' || c.cita.estado === 'no_show')
+  // % Entrev. de la hoja: también las reuniones con clientes (completada = entrevista, no asistió = resuelta).
+  const entrevistas = lista.filter(realizada)
+  const resueltas = lista.filter(resuelta)
+  const entrevistasConLead = citasConLead.filter(realizada)
   // Vínculo entrevista → cliente: la MISMA regla de Resultados, importada, no copiada.
   // En la fila, solo una venta de ese analista; en el total, la de cualquier dueño
   // del ámbito (dos analistas que entrevistan a la misma persona colaboran).
-  const convertidas = entrevistas.filter(c => contexto.ventasDe(c.persona)
+  const convertidas = entrevistasConLead.filter(c => contexto.ventasDe(c.persona)
     .some(v => (fila !== null || v.enAmbito) && ventaCierraEntrevista(c.cita.asistioEn, v, fila)))
-  const personasEntrevistadas = new Set(entrevistas.map(c => c.persona)).size
+  const personasEntrevistadas = new Set(entrevistasConLead.map(c => c.persona)).size
   const personasClientes = new Set(convertidas.map(c => c.persona)).size
-  const pctEntrevistas = resueltas.length ? entrevistas.length / resueltas.length * 100 : null
-  const pctConversion = contexto.conocidas && personasEntrevistadas ? personasClientes / personasEntrevistadas * 100 : null
+  const pctEntrevistas = tasa(entrevistas.length, resueltas.length)
+  const pctEntrevistasConLead = tasa(entrevistasConLead.length, citasConLead.filter(resuelta).length)
+  const pctConversion = contexto.conocidas ? tasa(personasClientes, personasEntrevistadas) : null
   const periodo = contexto.periodo
-  const hastaHoy = periodo ? lista.filter(c => c.creada <= periodo.hoy).length : n
+  const hastaHoy = periodo ? citasConLead.filter(c => c.creada <= periodo.hoy).length : n
   // Citas esperadas al cierre: el ritmo de los días transcurridos llevado al periodo entero.
   const citasEsperadas = !n || !periodo ? null : periodo.cerrado || !periodo.transcurridos ? n
     : Math.max(n, hastaHoy / periodo.transcurridos * periodo.dias)
-  // Como Resultados: citas esperadas × tasa de entrevistas × conversión × ticket.
+  // Como Resultados: citas esperadas × tasa de entrevistas × conversión × ticket, todo de las citas con lead.
   // Sin citas resueltas, o sin personas entrevistadas para la conversión, queda «sin base», nunca 0.
-  const proyectado = citasEsperadas !== null && pctEntrevistas !== null && pctConversion !== null && ticket !== null
-    ? citasEsperadas * (pctEntrevistas / 100) * (pctConversion / 100) * ticket : null
+  const proyectado = citasEsperadas !== null && pctEntrevistasConLead !== null && pctConversion !== null && ticket !== null
+    ? citasEsperadas * (pctEntrevistasConLead / 100) * (pctConversion / 100) * ticket : null
   return {
-    citas: lista, conMonto, entrevistas, resueltas, convertidas,
+    citas: lista, citasConLead, conMonto, entrevistas, resueltas, convertidas,
     referidos: lista.filter(c => c.origen === 'referido'), clientes: lista.filter(c => c.origen === 'cliente'),
     leads: lista.filter(c => c.origen === 'lead'),
-    montoPen, montoUsd, pendienteTc, monto, ticket, pctEntrevistas, pctConversion,
+    montoPen, montoUsd, pendienteTc, monto, ticket, pctEntrevistas, pctEntrevistasConLead, pctConversion,
     personasEntrevistadas, personasClientes, citasEsperadas, proyectado, porTramo: repartirEnTramos(lista, contexto.tramos),
   }
 }
@@ -285,7 +331,8 @@ function recortar(lista: readonly CitaProyectada[], columnas: FiltrosColumnas, i
   const analistas = ignorar === 'analistas' || !columnas.analistas ? null : new Set(columnas.analistas)
   const monedas = ignorar === 'monedas' || !columnas.monedas ? null : new Set(columnas.monedas)
   const personas = new Map(ORIGENES.filter(o => o !== ignorar && columnas.personas?.[o]).map(o => [o, new Set(columnas.personas![o])]))
-  return lista.filter(c => (!analistas || analistas.has(c.cita.analista)) && (!monedas || monedas.has(c.cita.moneda))
+  // Una reunión con un cliente sin lead no tiene moneda: un filtro de moneda la deja fuera.
+  return lista.filter(c => (!analistas || analistas.has(c.cita.analista)) && (!monedas || (c.cita.moneda !== null && monedas.has(c.cita.moneda)))
     && (!personas.has(c.origen) || personas.get(c.origen)!.has(c.persona)))
 }
 
diff --git a/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.ts b/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.ts
index 9602c87e..41e5f9b5 100644
--- a/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.ts
+++ b/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.ts
@@ -1,14 +1,19 @@
 import * as v from 'valibot'
 import { sb } from '@/lib/supabase'
 import { CrmApiError } from './crm-api'
+import { crmQueryKeys } from './crm-queries'
+import { CADENCIA_CITAS, estadoDeCita, fechaLima } from './citas-gerencia'
 import { camposIdentidadCliente, identidadClienteValida } from '@/lib/sujeto-gestion'
 import { FechaSchema } from '@/lib/esquemas-rpc'
+import { horaLima } from '@/components/citas/contexto'
+import type { ReunionClienteProyeccion } from '@/components/citas/proyeccion'
+import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'
 
 /**
  * Proyección de citas, Fase 0b (19/10/2026): reuniones con CLIENTES que no tienen lead,
  * contadas por fecha de CREACIÓN (día de Lima), sin paginar. Puerta
  * `crm.citas_clientes_proyeccion_fn` → núcleo `private.citas_clientes_proyeccion`
- * (migración 20261019213516 + enmienda 20261019224227). BORRADOR: todavía no lo usa ninguna pantalla.
+ * (migración 20261019213516 + enmienda 20261019224227). La usa la pestaña Proyección de Citas.
  *
  * `generado_en` es el CORTE (enmienda 20261019224227): el servidor sólo devuelve reuniones
  * creadas, y asistencias registradas, hasta ese instante; por eso el validador lo exige.
@@ -62,9 +67,6 @@ export const CitasClientesProyeccionSchema = v.object({
 export type CitasClientesProyeccionRpc = v.InferOutput<typeof CitasClientesProyeccionSchema>
 export type CitaClienteProyeccion = CitasClientesProyeccionRpc['citas'][number]
 
-const fechaLima = (instante: string) => new Intl.DateTimeFormat('en-CA', {
-  timeZone:'America/Lima', year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date(instante))
-
 /** El payload corresponde a lo pedido: mismo período, ids únicos y cada cita GENERADA dentro del rango. */
 export function citasClientesProyeccionCoherentes(d: CitasClientesProyeccionRpc, desde: string, hasta: string): boolean {
   if (d.periodo.desde !== desde || d.periodo.hasta !== hasta) return false
@@ -77,33 +79,63 @@ export function citasClientesProyeccionCoherentes(d: CitasClientesProyeccionRpc,
   })
 }
 
-type RespuestaSinTipos = { data: unknown; error: { code?: string | null; message?: string | null } | null }
-type ConsultaSinTipos = PromiseLike<RespuestaSinTipos> & { abortSignal: (s: AbortSignal) => PromiseLike<RespuestaSinTipos> }
-
-/**
- * La puerta todavía no sale de `gen:types` (se instala con la migración 20261019213516).
- * Misma llamada que `.rpc()` tipado; la respuesta se valida siempre con su esquema.
- * Se retira el cast cuando los tipos generados la conozcan.
- */
-function rpcProyeccionClientes(args: { p_desde: string; p_hasta: string }, signal?: AbortSignal): PromiseLike<RespuestaSinTipos> {
+/** Puerta tipada (tipos generados tras instalar 20261019213516 y su enmienda); la respuesta se valida siempre con su esquema. */
+async function rpcProyeccionClientes(args: { p_desde: string; p_hasta: string }, signal?: AbortSignal) {
   if (!sb) throw new CrmApiError('No se pudo conectar con el CRM.', 'CITAS_SIN_CONEXION')
-  const crm = sb.schema('crm') as unknown as { rpc: (fn: string, a: Record<string, unknown>) => ConsultaSinTipos }
-  const consulta = crm.rpc('citas_clientes_proyeccion_fn', args)
+  const consulta = sb.schema('crm').rpc('citas_clientes_proyeccion_fn', args)
   return signal ? consulta.abortSignal(signal) : consulta
 }
 
+/** Más de 10 000 reuniones (54000) o la consulta agotó su tiempo (57014): el rango es demasiado grande. */
+const RANGO_DEMASIADO_GRANDE = new Set(['54000', '57014'])
+export const esRangoDemasiadoGrande = (error: unknown) => error instanceof CrmApiError && RANGO_DEMASIADO_GRANDE.has(error.code)
+
+function mensajeDeError(code: string | null | undefined): string {
+  if (code === 'PGRST202') return 'Las reuniones con clientes de la Proyección aún no están habilitadas en este servidor.'
+  if (code && RANGO_DEMASIADO_GRANDE.has(code)) return 'El rango es demasiado grande. Acorta las fechas.'
+  return 'No se pudieron cargar las reuniones con clientes. Reintenta la consulta.'
+}
+
 /** Reuniones con clientes sin lead generadas entre `desde` y `hasta` (YYYY-MM-DD, día de Lima; hasta un año). */
 export async function cargarCitasClientesProyeccion(desde: string, hasta: string, signal?: AbortSignal): Promise<CitasClientesProyeccionRpc> {
   if (!v.is(FechaSchema, desde) || !v.is(FechaSchema, hasta) || desde > hasta) {
     throw new CrmApiError('Selecciona un rango válido.', 'CITAS_PERIODO')
   }
   const { data, error } = await rpcProyeccionClientes({ p_desde: desde, p_hasta: hasta }, signal)
-  if (error) throw new CrmApiError(error.code === 'PGRST202'
-    ? 'Las reuniones con clientes de la Proyección aún no están habilitadas en este servidor.'
-    : 'No se pudieron cargar las reuniones con clientes. Reintenta la consulta.', error.code ?? undefined)
+  if (error) throw new CrmApiError(mensajeDeError(error.code), error.code ?? undefined)
   const resultado = v.safeParse(CitasClientesProyeccionSchema, data)
   if (!resultado.success || !citasClientesProyeccionCoherentes(resultado.output, desde, hasta)) {
     throw new CrmApiError('La respuesta de reuniones con clientes está incompleta o no corresponde al rango.', 'CITAS_CONTRATO')
   }
   return resultado.output
 }
+
+/**
+ * Cada reunión como cita de la hoja: origen Cliente, sin lead, monto ni moneda; analista y supervisor del
+ * lector (con los mismos «sin analista» / «sin supervisor» que Citas) y el estado en el vocabulario de Citas.
+ */
+export function adaptarCitasClientesProyeccion(datos: CitasClientesProyeccionRpc): ReunionClienteProyeccion[] {
+  return datos.citas.map(c => ({
+    id: c.id, leadId: null, moneda: null, monto: null, persona: c.identidad_persona, nombre: c.sujeto_nombre,
+    analista: c.analista_id ?? 'sin_analista', analistaNombre: c.analista_nombre,
+    supervisor: c.supervisor_nombre, supervisorId: c.supervisor_id ?? 'sin_supervisor',
+    fecha: fechaLima(c.vence_en), hora: horaLima(c.vence_en), estado: estadoDeCita(c, datos.generado_en), creadoEn: c.creado_en,
+    ...(c.asistencia_registrada_en ? { asistioEn: c.asistencia_registrada_en } : {}),
+  }))
+}
+
+/**
+ * Una consulta por rango, con la cadencia y la caché de los meses de Citas. Sin rango (otra pestaña) o en
+ * demostración no consulta. Un rango demasiado grande no se reintenta ni se refresca solo: fallaría igual.
+ */
+export function opcionesCitasClientesProyeccion(rango: RangoProyeccion | null, actorId: string | null, habilitada: boolean) {
+  const desde = rango?.desde ?? '', hasta = rango?.hasta ?? ''
+  return {
+    queryKey: crmQueryKeys.citasClientesProyeccion(actorId, desde, hasta),
+    queryFn: ({ signal }: { signal: AbortSignal }) => cargarCitasClientesProyeccion(desde, hasta, signal),
+    enabled: habilitada && Boolean(actorId) && rango !== null,
+    ...CADENCIA_CITAS,
+    refetchInterval: (consulta: { state: { error: unknown } }) => esRangoDemasiadoGrande(consulta.state.error) ? false : CADENCIA_CITAS.refetchInterval,
+    retry: (fallos: number, error: Error) => fallos < 1 && !esRangoDemasiadoGrande(error),
+  }
+}
diff --git a/CRM-Avance-Corp/app/src/data/citas-gerencia.ts b/CRM-Avance-Corp/app/src/data/citas-gerencia.ts
index 6dc953f2..a5fec626 100644
--- a/CRM-Avance-Corp/app/src/data/citas-gerencia.ts
+++ b/CRM-Avance-Corp/app/src/data/citas-gerencia.ts
@@ -3,7 +3,7 @@ import { useQuery } from '@tanstack/react-query'
 import { sb } from '@/lib/supabase'
 import { crmQueryKeys } from './crm-queries'
 import { CrmApiError } from './crm-api'
-import { defaults, rango } from '@/components/citas/modelo'
+import { defaults, rango, type EstadoCita } from '@/components/citas/modelo'
 import type { CitaConLead } from '@/components/citas/datos'
 import type { DepositoEjemplo } from '@/components/citas/depositos'
 import type { GestionCitas } from '@/components/citas/metas'
@@ -63,13 +63,14 @@ export const ConsultaCitasSchema = v.variant('version',[
     conversiones:v.pipe(v.array(v.object({lead_id:Id,perfil_id:Id,convertido_en:Instante,fecha_comercial:v.nullable(FechaSchema)})),v.maxLength(10000)) }),
 ])
 export type ConsultaCitasRpc = v.InferOutput<typeof ConsultaCitasSchema>
+type TareaCita = v.InferOutput<typeof CitaSchema>
 export function adaptarDepositos(datos: ConsultaCitasRpc): DepositoEjemplo[] {
   return datos.version===2 ? datos.conversiones.filter(c => c.fecha_comercial !== null).map(c => ({
     id:`conversion-${c.lead_id}`,leadId:c.lead_id,fuente:'conversion_cliente',
     depositadoEn:c.convertido_en,confirmadoEn:c.convertido_en,fechaComercial:c.fecha_comercial!,monto:null,moneda:null,
   })) : []
 }
-const fechaLima = (fecha: string) => new Intl.DateTimeFormat('en-CA', {timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(fecha))
+export const fechaLima = (fecha: string) => new Intl.DateTimeFormat('en-CA', {timeZone:'America/Lima',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(fecha))
 const rotulo = (valor: string) => valor === 'sin_clasificar' ? 'Sin clasificar' : valor.replaceAll('_',' ').replace(/^./,c => c.toUpperCase())
 
 export function adaptarGestion(datos: ConsultaCitasRpc): GestionCitas | undefined {
@@ -91,6 +92,14 @@ export function adaptarGestion(datos: ConsultaCitasRpc): GestionCitas | undefine
   }
 }
 
+/** Estado de la tarea en el vocabulario de Citas (`ESTADOS`): una pendiente ya vencida al corte es «vencida» y
+ * una cancelada que no canceló el asesor es «sistema». Lo comparten las citas con lead y las reuniones con
+ * clientes sin lead de la Proyección (Fase 0b). */
+export function estadoDeCita(c: { estado: TareaCita['estado']; vence_en: string; cancelada_por: string | null }, generadoEn: string): EstadoCita {
+  return c.estado==='pendiente' ? Date.parse(c.vence_en)<=Date.parse(generadoEn) ? 'vencida' : 'programada'
+    : c.estado==='completada' ? 'realizada' : c.estado==='cancelada' && c.cancelada_por!=='asesor' ? 'sistema' : c.estado
+}
+
 export function adaptarCitas(datos: ConsultaCitasRpc): CitaConLead[] {
   const comerciales = new Map(datos.version === 2 ? datos.conversiones.map(c => [c.lead_id, c.fecha_comercial]) : [])
   // La marca heredada comparaba el último cierre con vence_en por instante.
@@ -109,8 +118,7 @@ export function adaptarCitas(datos: ConsultaCitasRpc): CitaConLead[] {
     id:c.id,leadId:c.lead_id,nombre:c.nombre,telefono:c.telefono,analista:c.analista_id ?? 'sin_analista',
     analistaNombre:c.analista_nombre,supervisor:c.supervisor_nombre,supervisorId:c.supervisor_id ?? 'sin_supervisor',
     fecha:fechaLima(c.vence_en),hora:horaLima(c.vence_en),
-    estado:c.estado_comercial ?? (c.estado==='pendiente' ? Date.parse(c.vence_en)<=Date.parse(datos.generado_en) ? 'vencida' : 'programada'
-      : c.estado==='completada' ? 'realizada' : c.estado==='cancelada' && c.cancelada_por!=='asesor' ? 'sistema' : c.estado),
+    estado:c.estado_comercial ?? estadoDeCita(c,datos.generado_en),
     modalidad:rotulo(c.modalidad),origen:rotulo(c.origen),moneda:c.moneda,monto:c.monto_estimado,
     resultado:rotulo(c.resultado),nota:c.nota,cerrado:cierreCompatible(c),
     seguimiento:c.estado==='completada' && !cierreCompatible(c),
@@ -193,6 +201,16 @@ export async function cargarCitasGerencia(mes: string, signal?: AbortSignal): Pr
   return resultado.output
 }
 
+/** Cadencia y caché de las lecturas de Citas; la comparten las reuniones con clientes de la Proyección. */
+export const CADENCIA_CITAS = {
+  staleTime:30_000,
+  // Incluye cambios de otros analistas y el paso de programada a vencida.
+  refetchInterval:60_000,
+  refetchIntervalInBackground:false,
+  refetchOnWindowFocus:true,
+  refetchOnReconnect:true,
+} as const
+
 /** Opciones de la consulta mensual: las comparten el mes de la pantalla y los meses del rango de Proyección. */
 export function opcionesCitasGerencia(mes: string, actorId: string | null, habilitada: boolean) {
   // Clave por actor/mes y sin placeholderData: nunca presenta otro período.
@@ -200,12 +218,7 @@ export function opcionesCitasGerencia(mes: string, actorId: string | null, habil
     queryKey:crmQueryKeys.citasGerencia(actorId,mes),
     queryFn:({signal}: {signal: AbortSignal}) => cargarCitasGerencia(mes,signal),
     enabled:habilitada && Boolean(actorId) && Boolean(rango(defaults(mes))[0]),
-    staleTime:30_000,
-    // Incluye cambios de otros analistas y el paso de programada a vencida.
-    refetchInterval:60_000,
-    refetchIntervalInBackground:false,
-    refetchOnWindowFocus:true,
-    refetchOnReconnect:true,
+    ...CADENCIA_CITAS,
     retry:1,
   }
 }
diff --git a/CRM-Avance-Corp/app/src/data/crm-queries.ts b/CRM-Avance-Corp/app/src/data/crm-queries.ts
index e82888f1..b01f563c 100644
--- a/CRM-Avance-Corp/app/src/data/crm-queries.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-queries.ts
@@ -240,6 +240,10 @@ export const crmQueryKeys = {
   citasGerenciaPrefijo: () => [...crmQueryKeys.metricasReunionesPrefijo(), 'detalle'] as const,
   citasGerencia: (actorId: string | null, mes: string) =>
     [...crmQueryKeys.citasGerenciaPrefijo(), actorId, mes] as const,
+  // Reuniones con clientes sin lead de un rango de la Proyección (Fase 0b): bajo el detalle de
+  // citas, para que lo que lo invalida (control de citas, escrituras comerciales) también las refresque.
+  citasClientesProyeccion: (actorId: string | null, desde: string, hasta: string) =>
+    [...crmQueryKeys.citasGerenciaPrefijo(), 'clientes-proyeccion', actorId, desde, hasta] as const,
   // Métricas del ÁMBITO OPERATIVO (RPC de F1: los tiles dejan de contar filas).
   // Prefijo PROPIO, separado de metricas(): el puente transitorio del store
   // (persistir/resincronizarReal) las invalida tras CADA mutación de leads, y
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx b/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx
index ee2f7c82..a7c9c114 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx
@@ -5,10 +5,11 @@ import { usePanelesActions } from '@/lib/store-context'
 import { adaptarDepositos, adaptarGestion } from '@/data/citas-gerencia'
 import { leerHash } from '@/lib/router'
 import { consultaCitasValida, mesConsultaCitas } from '@/lib/enlace-citas'
-import { useDatosCitasGerencia, useMesesCitasGerencia } from './use-datos-citas-gerencia'
+import { useDatosCitasGerencia, useDatosProyeccionCitas } from './use-datos-citas-gerencia'
 import { ContextoCitas } from '@/components/citas/contexto'
 import { TableroCitas } from '@/components/citas/propuesta'
 import { mesLima } from '@/components/citas/modelo'
+import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'
 import '@/components/citas/presentacion.css'
 
 export function CitasGerencia() {
@@ -21,10 +22,13 @@ export function CitasGerencia() {
   })
   const { yo, ahora, datos, citas, consulta } = useDatosCitasGerencia(mes)
   const { abrirLead } = usePanelesActions()
-  // Meses que pide el rango de Proyección (vacío en las otras pestañas).
+  // Meses y rango que pide la Proyección (vacío y null en las otras pestañas).
   const [mesesProyeccion, setMesesProyeccion] = useState<string[]>([])
   const pedirMeses = useCallback((meses: string[]) => setMesesProyeccion(actual => actual.join() === meses.join() ? actual : meses), [])
-  const proyeccion = useMesesCitasGerencia(mesesProyeccion)
+  const [rangoProyeccion, setRangoProyeccion] = useState<RangoProyeccion | null>(null)
+  const pedirRango = useCallback((rango: RangoProyeccion | null) => setRangoProyeccion(actual =>
+    actual?.desde === rango?.desde && actual?.hasta === rango?.hasta ? actual : rango), [])
+  const proyeccion = useDatosProyeccionCitas(mesesProyeccion, rangoProyeccion)
   const depositos = useMemo(() => datos ? adaptarDepositos(datos) : [],[datos])
   const gestion = useMemo(() => datos ? adaptarGestion(datos) : undefined,[datos])
   const error = consulta.error instanceof Error ? consulta.error.message : 'No se pudieron cargar las citas.'
@@ -37,7 +41,7 @@ export function CitasGerencia() {
     onMes:setMes,onReintentar:() => { if (!yo?.demo) void consulta.refetch() },
     onAbrirLead:(id) => { void abrirLead(id) },
     // En demostración las citas de arriba ya traen todos los meses del ejemplo.
-    onMesesProyeccion:pedirMeses,...(yo?.demo || !mesesProyeccion.length ? {} : {proyeccion}),
+    onMesesProyeccion:pedirMeses,onRangoProyeccion:pedirRango,...(yo?.demo || !mesesProyeccion.length ? {} : {proyeccion}),
   }}>
     <TableroCitas conservarConsulta={yo?.rol === 'gerencia'} />
     <CitasClientes mes={mes} />
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts b/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts
index 40377833..60a6bdc1 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts
+++ b/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts
@@ -1,11 +1,13 @@
 import { useMemo } from 'react'
-import { useQueries, type UseQueryResult } from '@tanstack/react-query'
+import { useQueries, useQuery, type UseQueryResult } from '@tanstack/react-query'
 import { useAuth } from '@/lib/auth-context'
 import { can } from '@/lib/roles'
 import { useCRMData } from '@/lib/store-context'
 import { useAhora } from '@/lib/ahora'
 import { useCitasGerencia, adaptarCitas, fusionarConsultasCitas, opcionesCitasGerencia, type ConsultaCitasRpc } from '@/data/citas-gerencia'
+import { adaptarCitasClientesProyeccion, opcionesCitasClientesProyeccion } from '@/data/citas-clientes-proyeccion'
 import type { DatosProyeccionCitas } from '@/components/citas/contexto'
+import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'
 import { defaults, rango } from '@/components/citas/modelo'
 
 /** La misma lectura y adaptación para el módulo Citas y el Resumen móvil. */
@@ -50,9 +52,12 @@ const combinarMeses = (resultados: UseQueryResult<ConsultaCitasRpc>[]) => ({
   reintentar: () => { for (const r of resultados) if (r.isError) void r.refetch() },
 })
 
+type MesesProyeccion = Omit<DatosProyeccionCitas, 'rango' | 'reunionesClientes'>
+const mensaje = (error: unknown, respaldo: string) => error instanceof Error ? error.message : respaldo
+
 /** Meses completos de un rango de Proyección: misma consulta y caché que el mes de
  * la pantalla. Mientras falte alguno no hay datos (nunca cifras parciales). */
-export function useMesesCitasGerencia(meses: readonly string[]): DatosProyeccionCitas {
+export function useMesesCitasGerencia(meses: readonly string[]): MesesProyeccion {
   const { yo } = useAuth()
   const habilitada = can(yo?.rol, 'verCitasEquipo') && !yo?.demo
   const estado = useQueries({
@@ -63,7 +68,26 @@ export function useMesesCitasGerencia(meses: readonly string[]): DatosProyeccion
   return {
     meses: [...meses], ...(fusion ?? { citas: [], gestion: undefined, corte: '' }),
     cargando: !fusion && !estado.error,
-    error: estado.error ? (estado.error instanceof Error ? estado.error.message : 'No se pudieron cargar las citas.') : null,
+    error: estado.error ? mensaje(estado.error, 'No se pudieron cargar las citas.') : null,
     onReintentar: estado.reintentar,
   }
 }
+
+/** Datos de la Proyección: los meses del rango y, en UNA consulta por rango, sus
+ * reuniones con clientes sin lead (Fase 0b). Mientras falte cualquiera, o si una
+ * falla, no hay datos: nunca cifras parciales. En demostración no consulta. */
+export function useDatosProyeccionCitas(meses: readonly string[], rango: RangoProyeccion | null): DatosProyeccionCitas {
+  const { yo } = useAuth()
+  const habilitada = can(yo?.rol, 'verCitasEquipo') && !yo?.demo
+  const delRango = useMesesCitasGerencia(meses)
+  const consulta = useQuery(opcionesCitasClientesProyeccion(rango, yo?.id ?? null, habilitada))
+  const reuniones = useMemo(() => consulta.data ? adaptarCitasClientesProyeccion(consulta.data) : null, [consulta.data])
+  const error = delRango.error ?? (consulta.isError ? mensaje(consulta.error, 'No se pudieron cargar las reuniones con clientes.') : null)
+  const listo = !error && !delRango.cargando && reuniones !== null
+  return {
+    ...delRango, rango,
+    citas: listo ? delRango.citas : [], reunionesClientes: listo ? reuniones : [],
+    cargando: !error && !listo, error,
+    onReintentar: () => { delRango.onReintentar(); if (consulta.isError) void consulta.refetch() },
+  }
+}
```

## Diff (pruebas y e2e)
```diff
diff --git a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
index 138aecec..bed1d02e 100644
--- a/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts
@@ -2,9 +2,10 @@ import { expect, test, type Page } from '@playwright/test'
 import { loginReal, montarBackendReal } from './_helpers'
 
 // Datos ficticios: tres analistas en dos equipos, citas creadas en octubre (y dos
-// a fines de septiembre, una con fecha en octubre) y una conversión posterior a su
+// a fines de septiembre, una con fecha en octubre) y dos conversiones posteriores a su
 // entrevista. El servidor entrega cada mes por la fecha prevista de la cita. La consulta V2 no está instalada en el
-// backend simulado y la pantalla cae a la consulta V1, que responde este mock.
+// backend simulado y la pantalla cae a la consulta V1, que responde este mock. Además, tres reuniones de
+// ANALISTA TRES con clientes SIN lead (Fase 0b), del lector propio de la Proyección.
 const id = (n: number) => `85000000-0000-4000-8000-${String(n).padStart(12, '0')}`
 const ANALISTAS = [
   { n: 20, nombre: 'ANALISTA UNO', sup: 30, supNombre: 'SUPERVISORA NORTE' },
@@ -19,8 +20,29 @@ const CITAS = [
   [2, 106, 'realizada', '2026-10-08', '2026-10-08', 'PEN', 50000, 'formulario'], [2, 107, 'cancelada', '2026-10-15', '2026-10-15', 'PEN', 30000, 'referido'],
   [0, 109, 'programada', '2026-09-30', '2026-10-05', 'PEN', 8000, 'formulario'], [2, 108, 'programada', '2026-09-28', '2026-09-29', 'PEN', 7000, 'formulario'],
 ] as const
+// [tarea, persona, creada, prevista, estado, asistencia] de ANALISTA TRES (SUPERVISOR SUR).
+const REUNIONES_CLIENTES = [
+  [201, 'persona', '2026-10-06', '2026-10-07', 'completada', '2026-10-07T16:00:00Z'],
+  [202, 'perfil', '2026-10-09', '2026-10-10', 'no_show', null],
+  [203, 'oculta', '2026-10-11', '2026-10-25', 'pendiente', null],
+] as const
 
 async function montarProyeccion(page: Page) {
+  // Una llamada por rango: las reuniones con clientes sin lead CREADAS (día de Lima) en él.
+  await page.route('**/rest/v1/rpc/citas_clientes_proyeccion_fn', async route => {
+    const { p_desde: desde, p_hasta: hasta } = route.request().postDataJSON() as { p_desde: string; p_hasta: string }
+    const citas = REUNIONES_CLIENTES.filter(([, , creada]) => creada >= desde && creada <= hasta).map(([n, persona, creada, prevista, estado, asistencia]) => {
+      const cliente = id(n + 100)
+      const identidad = persona === 'oculta'
+        ? { sujeto_tipo: 'inversionista', sujeto_id: null, sujeto_nombre: 'Cliente fuera de tu cartera', inversionista_id: null, perfil_id: null, identidad_visible: false, identidad_persona: `oculta:${id(n)}` }
+        : persona === 'persona'
+          ? { sujeto_tipo: 'inversionista', sujeto_id: cliente, sujeto_nombre: 'CLIENTE SIN LEAD UNO', inversionista_id: cliente, perfil_id: null, identidad_visible: true, identidad_persona: `persona:${cliente}` }
+          : { sujeto_tipo: 'perfil', sujeto_id: cliente, sujeto_nombre: 'CLIENTE SIN LEAD DOS', inversionista_id: null, perfil_id: cliente, identidad_visible: true, identidad_persona: `perfil:${cliente}` }
+      return { id: id(n), creado_en: `${creada}T15:00:00Z`, vence_en: `${prevista}T15:00:00Z`, estado, cancelada_por: null, asistencia_registrada_en: asistencia,
+        analista_id: id(22), analista_nombre: 'ANALISTA TRES', supervisor_id: id(31), supervisor_nombre: 'SUPERVISOR SUR', ...identidad }
+    })
+    await route.fulfill({ json: { version: 1, periodo: { desde, hasta }, criterio: 'creado_en', generado_en: '2026-10-19T17:00:00Z', citas } })
+  })
   await page.route('**/rest/v1/rpc/citas_gerencia_consulta_fn', async route => {
     const { p_desde: desde, p_hasta: hasta } = route.request().postDataJSON() as { p_desde: string; p_hasta: string }
     const mes = desde.slice(0, 7)
@@ -39,12 +61,14 @@ async function montarProyeccion(page: Page) {
     })
     const leads = citas.map(c => c.lead_id)
     const conversion = { lead_id: id(101), perfil_id: id(501), convertido_en: `${mes}-06T15:00:00Z`, fecha_comercial: `${mes}-06` }
+    // ANALISTA TRES vende a quien entrevistó el 08/10 (lead 106): su fila tiene % Conv. y Proyectado.
+    const conversionTres = { lead_id: id(106), perfil_id: id(506), convertido_en: `${mes}-10T15:00:00Z`, fecha_comercial: `${mes}-10` }
     const configuracion = { citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70, excluir_manuales_base: false,
       actividad_manuales: 'incluir', conteo_entrevistas: 'citas_realizadas', base_avance: 'actividad_real', base_depositos: 'personas_entrevistadas',
       mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: mes, mostrar_meta_citas: false }
     await route.fulfill({ json: {
       version: 2, periodo: { desde, hasta }, generado_en: '2026-10-19T17:00:00Z', citas, citas_clientes: 0,
-      disponibilidad_depositos: 'conversion_cliente', criterio_depositos: 'fecha_comercial', conversiones: delMes ? [conversion] : [],
+      disponibilidad_depositos: 'conversion_cliente', criterio_depositos: 'fecha_comercial', conversiones: delMes ? [conversion, conversionTres] : [],
       gestion: { version: 2, citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70, actividad_manuales: 'incluir',
         control: { version: 1, mes_inicio: mes, configuracion }, asignaciones: [], capital: [],
         poblacion: citas.map((c, i) => ({ lead_id: leads[i], nombre: c.nombre, telefono: c.telefono, origen: c.origen, moneda: c.moneda,
@@ -52,7 +76,8 @@ async function montarProyeccion(page: Page) {
           primera_asignacion_en: `${mes}-01T15:00:00Z`, analista_origen_nombre: c.analista_nombre, supervisor_origen_id: c.supervisor_id,
           supervisor_origen_nombre: c.supervisor_nombre })),
         conversiones: delMes ? [{ ...conversion, analista_id: id(20), analista_nombre: 'ANALISTA UNO', supervisor_id: id(30),
-          supervisor_nombre: 'SUPERVISORA NORTE', contrato_id: null }] : [] },
+          supervisor_nombre: 'SUPERVISORA NORTE', contrato_id: null }, { ...conversionTres, analista_id: id(22), analista_nombre: 'ANALISTA TRES',
+          supervisor_id: id(31), supervisor_nombre: 'SUPERVISOR SUR', contrato_id: null }] : [] },
     } })
   })
 }
@@ -123,7 +148,8 @@ test('Proyección: la hoja pinta una fila por analista, un número abre su lista
   await page.getByLabel('Desde', { exact: true }).fill('2026-09-25')
   await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('25 set – 19 oct 2026')
   await expect(hoja.getByRole('button', { name: '5 citas de ANALISTA UNO' })).toBeVisible()
-  await expect(hoja.getByRole('button', { name: '3 citas de ANALISTA TRES' })).toBeVisible()
+  // ANALISTA TRES: 3 citas con lead (una de septiembre) + 3 reuniones con clientes sin lead.
+  await expect(hoja.getByRole('button', { name: '6 citas de ANALISTA TRES' })).toBeVisible()
   await atajo(page, 'S3').click()
   await expect(page.getByTestId('pc-rotulo-rango')).toHaveText('15–21 oct 2026')
   await expect(hoja.locator('tr.pc-fila')).toHaveCount(2)
@@ -226,3 +252,44 @@ test('Proyección: el mes sin citas muestra la hoja vacía sin errores y en el c
   }
   await page.screenshot({ path: info.outputPath('proyeccion-320.png') })
 })
+
+test('Proyección: las reuniones con clientes sin lead cuentan en Citas, Clientes y % Entrev., no en Monto, Ticket ni Proyectado', async ({ page }, info) => {
+  await page.setViewportSize({ width: 1440, height: 1000 })
+  const hoja = await abrirProyeccion(page)
+  const tres = hoja.getByRole('row', { name: /ANALISTA TRES/ })
+  // 2 citas con lead (106 realizada, 107 cancelada) + 3 reuniones (completada, no asistió, pendiente).
+  await expect(tres.getByRole('button', { name: '5 citas de ANALISTA TRES' })).toBeVisible()
+  await expect(tres.getByRole('button', { name: '3 citas con clientes de ANALISTA TRES' })).toBeVisible()
+  // Monto y Ticket cita: solo las 2 citas con lead (S/ 80,000 ÷ 2).
+  await expect(tres.getByRole('button', { name: 'S/ 80,000 en citas de ANALISTA TRES' })).toBeVisible()
+  await expect(tres.locator('td').nth(3)).toHaveText('S/40,000')
+  // % Entrev.: (1 + 1) entrevistas ÷ (1 + 2) resueltas. % Conv. y Proyectado, de las citas con lead: 2 × 100 % × 100 % × S/ 40,000.
+  await expect(tres.getByRole('button', { name: /^% Entrev\. de ANALISTA TRES: 66\.7%/ })).toBeVisible()
+  await expect(tres.getByRole('button', { name: /^% Conv\. de ANALISTA TRES: 100%/ })).toBeVisible()
+  await expect(tres.locator('td.pc-proyectado')).toHaveText('S/80,000')
+  await page.screenshot({ path: info.outputPath('proyeccion-clientes-1440.png'), fullPage: true })
+
+  // Embudo de Clientes: estas personas, la redactada con el texto del servidor.
+  await hoja.getByRole('button', { name: 'Filtrar Clientes' }).click()
+  const menu = page.getByRole('dialog', { name: 'Filtrar Clientes' })
+  await expect(menu.getByRole('checkbox')).toHaveCount(4)
+  for (const nombre of ['Cliente fuera de tu cartera · 1 cita', 'CLIENTE SIN LEAD DOS · 1 cita', 'CLIENTE SIN LEAD UNO · 1 cita']) {
+    await expect(menu.getByRole('checkbox', { name: nombre })).toBeChecked()
+  }
+  await page.keyboard.press('Escape')
+  await expect(menu).toHaveCount(0)
+
+  // Lista de Clientes: sin botón de ficha (no tienen lead), monto «—» y origen Cliente.
+  await tres.getByRole('button', { name: '3 citas con clientes de ANALISTA TRES' }).click()
+  const lista = page.getByRole('dialog', { name: 'Citas con clientes · ANALISTA TRES' })
+  await expect(lista.getByTestId('pc-detalle-conteo')).toHaveText('1–19 oct 2026 · 3 citas')
+  await expect(lista.locator('tbody tr')).toHaveCount(3)
+  await expect(lista.locator('tbody button')).toHaveCount(0)
+  await expect(lista.getByRole('row', { name: /CLIENTE SIN LEAD UNO/ })).toContainText('Realizada')
+  await expect(lista.getByRole('row', { name: /CLIENTE SIN LEAD DOS/ })).toContainText('No asistió')
+  await expect(lista.getByRole('row', { name: /Cliente fuera de tu cartera/ })).toContainText('Programada')
+  await expect(lista.locator('tbody td.pc-num')).toHaveText(['—', '—', '—'])
+  await expect(lista.locator('tbody .pc-origen')).toHaveText(['Cliente', 'Cliente', 'Cliente'])
+  await page.keyboard.press('Escape')
+  await expect(lista).toHaveCount(0)
+})
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
index 663d4f20..5f4ab343 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx
@@ -6,6 +6,7 @@ import { ContextoCitas, type DatosCitas } from './contexto'
 import { TableroCitas } from './propuesta'
 import type { CitaEjemplo } from './modelo'
 import type { GestionCitas } from './metas'
+import type { ReunionClienteProyeccion } from './proyeccion'
 
 const cotizacion = vi.hoisted(() => ({ tc: { promedio: 3.75, fuente: 'Fuente de prueba' } as { promedio: number; fuente: string } | null, recargar: vi.fn() }))
 vi.mock('@/lib/tipo-cambio', async importOriginal => ({ ...await importOriginal<typeof import('@/lib/tipo-cambio')>(),
@@ -260,7 +261,7 @@ describe('Pestaña Proyección de Citas', () => {
   it('un rango que cruza meses pide esos meses, espera sin cifras parciales y pinta lo fusionado', async () => {
     const pedir = vi.fn()
     const septiembre = cita('s1', 'diego', { creadoEn: '2026-09-28T15:00:00Z', fecha: '2026-09-29' })
-    const base = { onMesesProyeccion: pedir, proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, cargando: false, error: null, onReintentar: vi.fn() } }
+    const base = { onMesesProyeccion: pedir, proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: { desde: '2026-10-01', hasta: '2026-10-19' }, reunionesClientes: [], cargando: false, error: null, onReintentar: vi.fn() } }
     const { usuario, vista } = await abrirProyeccion(base)
     expect(pedir).toHaveBeenLastCalledWith(['2026-10'])
     fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-09-25' } })
@@ -272,7 +273,7 @@ describe('Pestaña Proyección de Citas', () => {
     expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las citas.')
     await usuario.click(screen.getByRole('button', { name: 'Reintentar' }))
     expect(base.proyeccion.onReintentar).toHaveBeenCalledTimes(1)
-    rehacer({ meses: ['2026-09', '2026-10'], citas: [...CITAS, septiembre] })
+    rehacer({ meses: ['2026-09', '2026-10'], rango: { desde: '2026-09-25', hasta: '2026-10-19' }, citas: [...CITAS, septiembre] })
     const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
     expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('25 set – 19 oct 2026')
     expect(within(fila(hoja, 'Diego Salas')).getByRole('button', { name: '3 citas de Diego Salas' })).toBeVisible()
@@ -283,7 +284,7 @@ describe('Pestaña Proyección de Citas', () => {
   it('con el mes de arriba cargando o en error, la Proyección se pinta con los meses de su propio rango', async () => {
     // Codex (19/10): el mes de arriba puede quedar fuera del rango; su carga o su
     // error no deben tapar una hoja cuyos meses ya llegaron.
-    const propia = { onMesesProyeccion: vi.fn(), proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, cargando: false, error: null, onReintentar: vi.fn() } }
+    const propia = { onMesesProyeccion: vi.fn(), proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: { desde: '2026-10-01', hasta: '2026-10-19' }, reunionesClientes: [], cargando: false, error: null, onReintentar: vi.fn() } }
     const { hoja, vista } = await abrirProyeccion({ ...propia, cargando: true })
     expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(3)
     expect(screen.getByRole('tabpanel')).not.toHaveTextContent('Cargando las citas de tu consulta…')
@@ -411,7 +412,7 @@ describe('Pestaña Proyección de Citas', () => {
 
   it('Actualizar recarga los meses del rango cuando la Proyección tiene cargador propio', async () => {
     const recargarMes = vi.fn()
-    const propia = { onMesesProyeccion: vi.fn(), proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, cargando: false, error: null, onReintentar: vi.fn() } }
+    const propia = { onMesesProyeccion: vi.fn(), proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: { desde: '2026-10-01', hasta: '2026-10-19' }, reunionesClientes: [], cargando: false, error: null, onReintentar: vi.fn() } }
     const { usuario } = await abrirProyeccion({ ...propia, onReintentar: recargarMes })
     await usuario.click(screen.getByRole('button', { name: 'Actualizar' }))
     expect(propia.proyeccion.onReintentar).toHaveBeenCalledTimes(1)
@@ -480,3 +481,102 @@ describe('Pestaña Proyección de Citas', () => {
     expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-19')
   })
 })
+
+// Fase 0b: reuniones con clientes sin lead, del lector propio de la Proyección.
+describe('Proyección con reuniones con clientes sin lead', () => {
+  const OCTUBRE_19 = { desde: '2026-10-01', hasta: '2026-10-19' }
+  const reunion = (id: string, cambios: Partial<ReunionClienteProyeccion>): ReunionClienteProyeccion => ({
+    id, leadId: null, moneda: null, monto: null, persona: `persona:${id}`, nombre: `CLIENTE ${id.toUpperCase()}`, analista: 'ana', analistaNombre: 'Ana Torres',
+    supervisor: 'Claudia Ríos', supervisorId: 'sup-1', fecha: '2026-10-10', hora: '10:00', estado: 'programada', creadoEn: '2026-10-08T15:00:00Z', ...cambios,
+  })
+  const REUNIONES = [
+    reunion('r1', { estado: 'realizada', asistioEn: '2026-10-10T16:00:00Z', nombre: 'CLIENTE UNO' }),
+    reunion('r2', { estado: 'no_show', persona: 'oculta:r2', nombre: 'Cliente fuera de tu cartera', creadoEn: '2026-10-11T15:00:00Z' }),
+  ]
+  const cargador = (cambios: Partial<NonNullable<DatosCitas['proyeccion']>> = {}) => ({ onMesesProyeccion: vi.fn(), onAbrirLead: vi.fn(), proyeccion: {
+    meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: OCTUBRE_19, reunionesClientes: REUNIONES,
+    cargando: false, error: null, onReintentar: vi.fn(), ...cambios } })
+
+  it('cuentan en Citas, Clientes y % Entrev.; Monto, Ticket cita, % Conv. y Proyectado quedan los de las citas con lead', async () => {
+    const { hoja: sinReuniones, vista } = await abrirProyeccion(cargador({ reunionesClientes: [] }))
+    // La señal añade su estado para el lector («60% · Por mejorar»): cuenta la cifra.
+    const cifras = (tr: HTMLElement) => within(tr).getAllByRole('cell').slice(1).map(td => td.textContent!.replace(/ · .*$/, ''))
+    let ana = fila(sinReuniones, 'Ana Torres')
+    expect(cifras(ana)).toEqual(['4', 'S/37,500', 'S/9,375', '66.7%', '50%', 'S/12,500', '1', '0', '3'])
+    vista.unmount()
+    const { hoja } = await abrirProyeccion(cargador())
+    ana = fila(hoja, 'Ana Torres')
+    // 4 citas con lead + 2 reuniones = 6 · % Entrev. (2 + 1) ÷ (3 + 2) = 60 % · lo demás, igual.
+    expect(cifras(ana)).toEqual(['6', 'S/37,500', 'S/9,375', '60%', '50%', 'S/12,500', '1', '2', '3'])
+    expect(within(ana).getByRole('button', { name: '6 citas de Ana Torres' })).toBeVisible()
+    expect(within(filaTotal(hoja)).getByRole('button', { name: '3 citas con clientes de todos los analistas' })).toBeVisible()
+  })
+
+  it('el embudo de Clientes lista estas personas (la redactada con su texto) y la lista lateral las muestra sin ficha, con su CSV', async () => {
+    const blobs: Blob[] = []
+    const original = { crear: URL.createObjectURL, revocar: URL.revokeObjectURL }
+    URL.createObjectURL = vi.fn((blob: Blob) => { blobs.push(blob); return 'blob:proyeccion' })
+    URL.revokeObjectURL = vi.fn()
+    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
+    try {
+      const { usuario, hoja } = await abrirProyeccion(cargador())
+      await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Clientes' }))
+      const menu = screen.getByRole('dialog', { name: 'Filtrar Clientes' })
+      expect(within(menu).getAllByRole('checkbox').map(c => c.getAttribute('aria-label'))).toEqual(
+        ['Seleccionar todo', 'Cliente fuera de tu cartera · 1 cita', 'CLIENTE UNO · 1 cita', 'Persona d1 · 1 cita'])
+      await usuario.click(within(menu).getByRole('checkbox', { name: 'Persona d1 · 1 cita' }))
+      await usuario.click(within(menu).getByRole('checkbox', { name: 'Cliente fuera de tu cartera · 1 cita' }))
+      await usuario.click(within(menu).getByRole('button', { name: 'Aplicar' }))
+      expect(screen.getByRole('group', { name: 'Filtros de columna' })).toHaveTextContent('Clientes CLIENTE UNO')
+      expect(within(filaTotal(hoja)).getByRole('button', { name: '1 cita con cliente de todos los analistas' })).toBeVisible()
+      await usuario.click(screen.getByRole('button', { name: 'Quitar filtro de Clientes' }))
+      await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '2 citas con clientes de Ana Torres' }))
+      const lista = screen.getByRole('dialog', { name: 'Citas con clientes · Ana Torres' })
+      expect(within(lista).getAllByRole('row')).toHaveLength(3)
+      // Sin lead no hay ficha que abrir: la persona es texto, no botón.
+      expect(within(lista).queryByRole('button', { name: 'CLIENTE UNO' })).not.toBeInTheDocument()
+      expect(within(lista).getByRole('row', { name: /CLIENTE UNO/ })).toHaveTextContent('Realizada—Cliente')
+      expect(within(lista).getByRole('row', { name: /Cliente fuera de tu cartera/ })).toHaveTextContent('No asistió—Cliente')
+      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
+      const texto = await blobs[0]!.text()
+      expect(texto.split('\r\n')[1]).toBe('"r1","2026-10-10","10:00","CLIENTE UNO","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
+      await usuario.click(within(lista).getByRole('button', { name: 'Cerrar lista' }))
+      // Las citas con lead siguen abriendo su ficha.
+      await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '6 citas de Ana Torres' }))
+      expect(within(screen.getByRole('dialog', { name: 'Citas · Ana Torres' })).getByRole('button', { name: 'Persona a1' })).toBeVisible()
+      expect(within(screen.getByRole('dialog', { name: 'Citas · Ana Torres' })).queryByRole('button', { name: 'CLIENTE UNO' })).not.toBeInTheDocument()
+    } finally {
+      URL.createObjectURL = original.crear
+      URL.revokeObjectURL = original.revocar
+      click.mockRestore()
+    }
+  })
+
+  it('pide el rango a la pantalla y, mientras sus reuniones no lleguen o si fallan, no pinta cifras parciales', async () => {
+    const pedirRango = vi.fn()
+    const datos = { ...cargador({ rango: null }), onRangoProyeccion: pedirRango }
+    const usuario = userEvent.setup()
+    const vista = render(<ContextoCitas value={{ ...fuente, ...datos }}><TableroCitas /></ContextoCitas>)
+    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
+    expect(pedirRango).toHaveBeenLastCalledWith(OCTUBRE_19)
+    // Las reuniones aún son de otro rango (o de ninguno): espera.
+    expect(screen.getByText('Cargando las citas del rango…')).toBeVisible()
+    expect(screen.queryByRole('table', { name: /Proyección de citas por analista/ })).not.toBeInTheDocument()
+    const rehacer = (cambios: Partial<NonNullable<DatosCitas['proyeccion']>>) =>
+      vista.rerender(<ContextoCitas value={{ ...fuente, ...datos, proyeccion: { ...datos.proyeccion, ...cambios } }}><TableroCitas /></ContextoCitas>)
+    rehacer({ rango: OCTUBRE_19, cargando: true })
+    expect(screen.getByText('Cargando las citas del rango…')).toBeVisible()
+    rehacer({ rango: OCTUBRE_19, error: 'El rango es demasiado grande. Acorta las fechas.' })
+    expect(screen.getByRole('alert')).toHaveTextContent(/^El rango es demasiado grande\. Acorta las fechas\.Reintentar$/)
+    expect(screen.queryByRole('table', { name: /Proyección de citas por analista/ })).not.toBeInTheDocument()
+    await usuario.click(screen.getByRole('button', { name: 'Reintentar' }))
+    expect(datos.proyeccion.onReintentar).toHaveBeenCalledTimes(1)
+    rehacer({ rango: OCTUBRE_19 })
+    expect(within(fila(screen.getByRole('table', { name: /Proyección de citas por analista/ }), 'Ana Torres')).getByRole('button', { name: '6 citas de Ana Torres' })).toBeVisible()
+    await usuario.click(atajo('S3'))
+    expect(pedirRango).toHaveBeenLastCalledWith({ desde: '2026-10-15', hasta: '2026-10-21' })
+    expect(screen.getByText('Cargando las citas del rango…')).toBeVisible()
+    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
+    expect(pedirRango).toHaveBeenLastCalledWith(null)
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion-invariantes.test.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion-invariantes.test.ts
index 4b7b7dee..46d41dd7 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion-invariantes.test.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion-invariantes.test.ts
@@ -9,7 +9,9 @@ import { calcularAvanceCitas } from './avance'
 import { fechaLocalCitas } from './fecha-comercial'
 import type { GestionCitas } from './metas'
 import { defaults, type CitaEjemplo } from './modelo'
-import { calcularProyeccion, type FuenteProyeccion, type HojaProyeccion, type MetricasProyeccion } from './proyeccion'
+import {
+  calcularProyeccion, type FiltrosColumnas, type FuenteProyeccion, type HojaProyeccion, type MetricasProyeccion, type ReunionClienteProyeccion,
+} from './proyeccion'
 import { sumarDias, type RangoProyeccion, type TiempoProyeccion } from './proyeccion-rango'
 
 const HOY = '2026-10-19T17:00:00Z' // lunes 19/10/2026, 12:00 de Lima
@@ -81,7 +83,7 @@ const ventasDeSeptiembre = (citas: readonly CitaEjemplo[], vendedor: (c: CitaEje
 const fuente = (rango: RangoProyeccion, cambios: Partial<FuenteProyeccion> = {}): FuenteProyeccion =>
   ({ ...lote(), filtros: { equipo: '' }, rango, corte: HOY, tipoCambio: TC, ...cambios })
 const filasYTotal = (h: HojaProyeccion): MetricasProyeccion[] => [...h.filas, h.total]
-const ids = (lista: readonly { cita: CitaEjemplo }[]) => lista.map(c => c.cita.id).sort()
+const ids = (lista: readonly { cita: { id: string } }[]) => lista.map(c => c.cita.id).sort()
 const RANGOS: RangoProyeccion[] = [
   { desde: '2026-10-01', hasta: '2026-10-07' }, { desde: '2026-10-01', hasta: '2026-10-19' }, OCTUBRE,
   { desde: '2026-09-25', hasta: '2026-10-19' }, { desde: '2026-10-19', hasta: '2026-10-19' },
@@ -228,7 +230,7 @@ describe('Proyección ↔ Resultados (avance mensual)', () => {
   it('diferencia a propósito: una venta del mes siguiente cuenta en la Proyección (sigue su cohorte hasta el corte) y no en Resultados del mes', () => {
     const base = escenario()
     const sinVenta = base.proyeccion.total.entrevistas.find(e => !base.proyeccion.total.convertidas.includes(e))!
-    const tardia = venta(sinVenta.cita, '2026-10-05T15:00:00Z', '2026-10-05')
+    const tardia = venta(sinVenta.cita as CitaEjemplo, '2026-10-05T15:00:00Z', '2026-10-05')
     const { resultados, proyeccion } = escenario([tardia])
     expect(proyeccion.total.personasClientes).toBe(base.proyeccion.total.personasClientes + 1)
     expect(resultados.total.clientes).toBe(base.resultados.total.clientes)
@@ -366,3 +368,112 @@ describe('Fusión de meses del rango', () => {
     expect(hoja.total.porTramo.map(l => l.length)).toEqual([1, 2, 0, 0])
   })
 })
+
+// Reuniones con CLIENTES sin lead (Fase 0b, decisión de Miguel 19/10/2026): citas de
+// origen Cliente que suman a Citas, Clientes, columnas de tiempo y % Entrev., y que
+// NO tocan ninguna métrica de prospectos (Monto, Ticket cita, % Conv., Proyectado).
+describe('Invariantes con reuniones con clientes sin lead', () => {
+  const RESPONSABLES = [...ANALISTAS, ['sofia', 'sup-1']] as const
+  /** 45 días de reuniones: todos los estados, una analista que solo tiene reuniones, personas repetidas,
+   * redactadas y una clave idéntica a la de un lead del lote (nunca debe emparejarse con él). */
+  function loteReuniones(): ReunionClienteProyeccion[] {
+    const estados = ['realizada', 'no_show', 'programada', 'realizada', 'vencida', 'cancelada', 'sistema', 'reprogramada', 'no_show'] as const
+    return Array.from({ length: 45 }, (_, d) => {
+      const dia = sumarDias('2026-09-20', d)
+      const [analista, supervisorId] = RESPONSABLES[d % RESPONSABLES.length]!
+      const estado = estados[d % estados.length]!
+      const persona = d % 5 === 0 ? `oculta:r${d}` : d % 5 === 1 ? `lead:lead-${3 * d + 1}` : `persona:p${d % 7}`
+      return {
+        id: `r${d}`, leadId: null, moneda: null, monto: null, persona, nombre: persona.startsWith('oculta:') ? 'Cliente fuera de tu cartera' : `CLIENTE ${persona}`,
+        analista, analistaNombre: analista, supervisor: supervisorId, supervisorId, fecha: sumarDias(dia, 2), hora: '11:00', estado,
+        creadoEn: `${dia}T${d % 2 ? '05' : '18'}:45:00Z`, ...(estado === 'realizada' ? { asistioEn: `${sumarDias(dia, 2)}T16:00:00Z` } : {}),
+      }
+    })
+  }
+  const conReuniones = (rango: RangoProyeccion, cambios: Partial<FuenteProyeccion> = {}): FuenteProyeccion =>
+    ({ ...fuente(rango, cambios), reunionesClientes: loteReuniones() })
+  const enCohorte = (rango: RangoProyeccion, equipo = '') => loteReuniones().filter(r => {
+    const dia = fechaLocalCitas(r.creadoEn!)
+    return dia >= rango.desde && dia <= rango.hasta && (!equipo || r.supervisorId === equipo)
+  })
+  /** Todo lo que es de prospectos: no puede moverse por una reunión con un cliente sin lead. */
+  const prospectos = (m: MetricasProyeccion) => ({
+    montoPen: m.montoPen, montoUsd: m.montoUsd, monto: m.monto, ticket: m.ticket, pendienteTc: m.pendienteTc,
+    conMonto: ids(m.conMonto), citasConLead: ids(m.citasConLead), referidos: ids(m.referidos), leads: ids(m.leads),
+    entrevistasConLead: ids(m.entrevistas.filter(c => c.cita.leadId !== null)), pctEntrevistasConLead: m.pctEntrevistasConLead,
+    convertidas: ids(m.convertidas), personasEntrevistadas: m.personasEntrevistadas, personasClientes: m.personasClientes,
+    pctConversion: m.pctConversion, citasEsperadas: m.citasEsperadas, proyectado: m.proyectado,
+  })
+  const CONSULTAS: { filtros: { equipo: string }; columnas: FiltrosColumnas; tipoCambio?: number | null }[] = [
+    { filtros: { equipo: '' }, columnas: {} }, { filtros: { equipo: 'sup-1' }, columnas: {} }, { filtros: { equipo: 'sup-2' }, columnas: {} },
+    { filtros: { equipo: '' }, columnas: { analistas: ['ana', 'diego', 'sofia'] } },
+    { filtros: { equipo: '' }, columnas: { personas: { cliente: ['persona:p2', 'persona:p3', 'oculta:r10', 'lead:lead-1'] } } },
+    { filtros: { equipo: '' }, columnas: {}, tipoCambio: null },
+  ]
+
+  it('el lote ejercita lo que importa: reuniones en la cohorte, una tasa de entrevistas distinta y una fila solo de reuniones', () => {
+    const hoja = calcularProyeccion(conReuniones(OCTUBRE))
+    expect(enCohorte(OCTUBRE).length).toBeGreaterThan(20)
+    expect(hoja.filas.some(f => f.pctEntrevistas !== null && f.pctEntrevistasConLead !== null && Math.abs(f.pctEntrevistas - f.pctEntrevistasConLead) > 1)).toBe(true)
+    expect(hoja.filas.find(f => f.id === 'sofia')).toMatchObject({ citasConLead: [], ticket: null, pctConversion: null, proyectado: null })
+    expect(hoja.total.convertidas.length).toBeGreaterThan(0)
+  })
+
+  it.each(RANGOS)('Citas = Referidos + Clientes + Leads y las columnas de tiempo suman Citas, con reuniones ($desde → $hasta)', rango => {
+    for (const tiempo of TIEMPOS) {
+      for (const m of filasYTotal(calcularProyeccion(conReuniones(rango, { tiempo })))) {
+        expect(m.referidos.length + m.clientes.length + m.leads.length).toBe(m.citas.length)
+        expect(new Set([...m.referidos, ...m.clientes, ...m.leads].map(c => c.cita.id)).size).toBe(m.citas.length)
+        if (tiempo !== 'mes') expect(m.porTramo.reduce((s, l) => s + l.length, 0)).toBe(m.citas.length)
+      }
+    }
+  })
+
+  it.each(RANGOS)('Citas de la Proyección = citas con lead + reuniones con clientes del rango, por fila y en el total ($desde → $hasta)', rango => {
+    for (const equipo of ['', 'sup-1', 'sup-2']) {
+      const sin = calcularProyeccion(fuente(rango, { filtros: { equipo } }))
+      const con = calcularProyeccion(conReuniones(rango, { filtros: { equipo } }))
+      const reuniones = enCohorte(rango, equipo)
+      expect(ids(con.total.citas)).toEqual(ids([...sin.total.citas, ...reuniones.map(r => ({ cita: r }))]))
+      expect(ids(con.total.clientes)).toEqual(ids([...sin.total.clientes, ...reuniones.map(r => ({ cita: r }))]))
+      for (const f of con.filas) {
+        const deFila = reuniones.filter(r => r.analista === f.id)
+        expect(f.citas.length, `${equipo} · ${f.id}`).toBe((sin.filas.find(x => x.id === f.id)?.citas.length ?? 0) + deFila.length)
+      }
+    }
+  })
+
+  it.each(RANGOS)('las métricas de prospectos no cambian al añadir o quitar las reuniones, por fila y en el total ($desde → $hasta)', rango => {
+    for (const { filtros, columnas, tipoCambio = TC } of CONSULTAS) {
+      const sin = calcularProyeccion(fuente(rango, { filtros, tipoCambio }), columnas)
+      const con = calcularProyeccion(conReuniones(rango, { filtros, tipoCambio }), columnas)
+      const consulta = `${filtros.equipo} · ${JSON.stringify(columnas)} · TC ${tipoCambio}`
+      expect(prospectos(con.total), consulta).toEqual(prospectos(sin.total))
+      for (const f of con.filas) {
+        const antes = sin.filas.find(x => x.id === f.id)
+        // Una fila que solo existe por sus reuniones no tiene nada de prospectos.
+        if (!antes) expect([f.citasConLead.length, f.ticket, f.pctConversion, f.proyectado], `${consulta} · ${f.id}`).toEqual([0, null, null, null])
+        else expect(prospectos(f), `${consulta} · ${f.id}`).toEqual(prospectos(antes))
+      }
+      expect(sin.filas.every(f => con.filas.some(x => x.id === f.id))).toBe(true)
+    }
+  })
+
+  it.each(RANGOS)('aritmética con reuniones: % Entrev. de todas; Ticket cita × citas con lead = Monto; Proyectado con lo de las citas con lead ($desde → $hasta)', rango => {
+    const hoja = calcularProyeccion(conReuniones(rango))
+    for (const m of filasYTotal(hoja)) {
+      if (!m.citas.length) continue
+      expect(m.pctEntrevistas).toEqual(m.resueltas.length ? expect.closeTo(m.entrevistas.length / m.resueltas.length * 100, 9) : null)
+      expect(m.entrevistas.filter(c => c.cita.leadId === null)).toEqual(m.clientes.filter(c => c.cita.leadId === null && c.cita.estado === 'realizada'))
+      if (m.ticket !== null) expect(m.ticket * m.citasConLead.length).toBeCloseTo(m.monto!, 6)
+      expect(m.convertidas.every(c => c.cita.leadId !== null)).toBe(true)
+    }
+    for (const f of hoja.filas) {
+      if (f.proyectado === null) continue
+      expect(f.proyectado).toBeCloseTo(f.citasEsperadas! * (f.pctEntrevistasConLead! / 100) * (f.pctConversion! / 100) * f.ticket!, 6)
+    }
+    const suma = (f: (m: MetricasProyeccion) => number) => hoja.filas.reduce((s, m) => s + f(m), 0)
+    expect([suma(m => m.citas.length), suma(m => m.resueltas.length), suma(m => m.entrevistas.length)])
+      .toEqual([hoja.total.citas.length, hoja.total.resueltas.length, hoja.total.entrevistas.length])
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts b/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
index f42ddc76..52b20975 100644
--- a/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/proyeccion.test.ts
@@ -3,6 +3,7 @@ import { defaults, type CitaEjemplo, type FiltrosCitas } from './modelo'
 import {
   calcularProyeccion, csvCitasProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas, opcionesPersonas,
   periodoProyeccion, repartirEnTramos, type ConversionProyeccion, type FiltrosColumnas, type FuenteProyeccion, type PersonaProyeccion,
+  type ReunionClienteProyeccion,
 } from './proyeccion'
 import {
   atajosRango, diasPermitidos, errorRango, mesesDelRango, rangoInicial, rotuloRango, tiempoEfectivo, tramosDelRango, type RangoProyeccion,
@@ -46,7 +47,7 @@ function mesLleno() {
   return { citas, conversiones, fuente }
 }
 const fila = (hoja: ReturnType<typeof calcularProyeccion>, id: string) => hoja.filas.find(f => f.id === id)
-const ids = (lista: { cita: CitaEjemplo }[]) => lista.map(c => c.cita.id).sort()
+const ids = (lista: readonly { cita: { id: string } }[]) => lista.map(c => c.cita.id).sort()
 const con = (fuente: FuenteProyeccion, filtros: Partial<FiltrosCitas>): FuenteProyeccion => ({ ...fuente, filtros: { ...fuente.filtros, ...filtros } })
 const en = (fuente: FuenteProyeccion, desde: string, hasta: string): FuenteProyeccion => ({ ...fuente, rango: { desde, hasta } })
 
@@ -446,3 +447,109 @@ describe('Proyección de citas: % Entrev. y % Conv. con las reglas de Resultados
     expect(sinAsistencia.filas[0]).toMatchObject({ personasEntrevistadas: 1, personasClientes: 0, pctConversion: 0 })
   })
 })
+
+// Fase 0b (decisión de Miguel, 19/10/2026): las reuniones con CLIENTES sin lead son
+// citas de origen Cliente. Cuentan en Citas, Clientes, columnas de tiempo y % Entrev.;
+// Monto, Ticket cita, % Conv. y Proyectado siguen siendo los de las citas con lead.
+describe('Proyección de citas: reuniones con clientes sin lead', () => {
+  function reunion(id: string, analista: keyof typeof EQUIPOS, cambios: Partial<ReunionClienteProyeccion>): ReunionClienteProyeccion {
+    const [analistaNombre, supervisorId, supervisor] = EQUIPOS[analista]
+    return { id, leadId: null, moneda: null, monto: null, persona: `persona:${id}`, nombre: `CLIENTE ${id.toUpperCase()}`, analista, analistaNombre,
+      supervisor, supervisorId, fecha: '2026-10-12', hora: '11:00', estado: 'programada', creadoEn: '2026-10-08T15:00:00Z', ...cambios }
+  }
+  /** Ana: 3 citas con lead (2 entrevistas, 1 no asistió, una venta) y 2 reuniones con clientes (1 entrevista, 1 no asistió). */
+  function ejemplo(reuniones = true) {
+    const citas = [
+      cita('a1', 'ana', { leadId: 'lead-1', estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z', monto: 10_000, creadoEn: '2026-10-02T15:00:00Z' }),
+      cita('a2', 'ana', { leadId: 'lead-2', estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z', monto: 20_000, creadoEn: '2026-10-03T15:00:00Z' }),
+      cita('a3', 'ana', { leadId: 'lead-3', estado: 'no_show', monto: 30_000, creadoEn: '2026-10-04T15:00:00Z' }),
+    ]
+    const reunionesClientes = reuniones ? [
+      reunion('r1', 'ana', { estado: 'realizada', asistioEn: '2026-10-09T16:00:00Z', creadoEn: '2026-10-08T15:00:00Z' }),
+      reunion('r2', 'ana', { estado: 'no_show', persona: 'oculta:r2', nombre: 'Cliente fuera de tu cartera', creadoEn: '2026-10-11T15:00:00Z' }),
+    ] : []
+    const conversiones: ConversionProyeccion[] = [{ lead_id: 'lead-1', perfil_id: 'perfil-1', convertido_en: '2026-10-08T15:00:00Z', fecha_comercial: '2026-10-08', analista_id: 'ana', supervisor_id: 'sup-1' }]
+    return { citas, reunionesClientes, filtros: { equipo: '' }, rango: OCTUBRE, corte: HOY, tipoCambio: TC, conversiones } satisfies FuenteProyeccion
+  }
+
+  it('ejemplo: 3 citas con lead + 2 reuniones con clientes → 5 citas y 60 % Entrev.; Monto, Ticket, % Conv. y Proyectado de las 3 con lead', () => {
+    const ana = fila(calcularProyeccion(ejemplo()), 'ana')!
+    expect(ids(ana.citas)).toEqual(['a1', 'a2', 'a3', 'r1', 'r2'])
+    expect(ids(ana.citasConLead)).toEqual(['a1', 'a2', 'a3'])
+    expect([ana.referidos.length, ana.clientes.length, ana.leads.length]).toEqual([0, 2, 3])
+    // Monto 60 000 entre las 3 citas con lead (no entre 5): Ticket cita 20 000.
+    expect(ana).toMatchObject({ montoPen: 60_000, monto: 60_000, ticket: 20_000, personasEntrevistadas: 2, personasClientes: 1, pctConversion: 50 })
+    expect(ids(ana.conMonto)).toEqual(['a1', 'a2', 'a3'])
+    // % Entrev. de la hoja: (2 + 1) entrevistas ÷ (3 + 2) resueltas. El que proyecta: 2 ÷ 3.
+    expect(ids(ana.entrevistas)).toEqual(['a1', 'a2', 'r1'])
+    expect(ids(ana.resueltas)).toEqual(['a1', 'a2', 'a3', 'r1', 'r2'])
+    expect(ana.pctEntrevistas).toBeCloseTo(60, 10)
+    expect(ana.pctEntrevistasConLead).toBeCloseTo(200 / 3, 10)
+    expect(ids(ana.convertidas)).toEqual(['a1'])
+    // Ritmo de las 3 con lead: 3 en 19 de 31 días → 93/19 × 2/3 × 50 % × S/ 20 000 = S/ 32 631,58.
+    expect(ana.citasEsperadas).toBeCloseTo(93 / 19, 10)
+    expect(ana.proyectado).toBeCloseTo(93 / 19 * (2 / 3) * 0.5 * 20_000, 6)
+    expect(Math.round(ana.proyectado! * 100) / 100).toBe(32_631.58)
+    // Sin las reuniones, lo único que cambia es Citas, Clientes y % Entrev.
+    const sin = fila(calcularProyeccion(ejemplo(false)), 'ana')!
+    expect(sin).toMatchObject({ monto: ana.monto, ticket: ana.ticket, pctConversion: ana.pctConversion, proyectado: ana.proyectado, citasEsperadas: ana.citasEsperadas })
+    expect([sin.citas.length, sin.clientes.length, sin.pctEntrevistas]).toEqual([3, 0, ana.pctEntrevistasConLead])
+  })
+
+  it('un analista con solo reuniones con clientes tiene fila, sin monto, ticket, conversión ni proyectado; el total no cambia su proyectado', () => {
+    const fuente: FuenteProyeccion = { ...mesLleno().fuente, reunionesClientes: [reunion('m2', 'mateo', { estado: 'realizada', asistioEn: '2026-10-09T16:00:00Z' })] }
+    const con = calcularProyeccion(fuente)
+    const mateo = fila(con, 'mateo')!
+    expect(mateo).toMatchObject({ ticket: null, pctEntrevistas: 100, pctEntrevistasConLead: null, pctConversion: null, citasEsperadas: null, proyectado: null })
+    expect([mateo.citas.length, mateo.clientes.length, mateo.conMonto.length, mateo.citasConLead.length]).toEqual([1, 1, 0, 0])
+    const sin = calcularProyeccion(mesLleno().fuente)
+    expect(con.total).toMatchObject({ proyectado: sin.total.proyectado, monto: sin.total.monto, ticket: sin.total.ticket, pctConversion: sin.total.pctConversion })
+    expect(con.total.citas.length).toBe(sin.total.citas.length + 1)
+  })
+
+  it('el Supervisor, el embudo de Analista y el de Clientes las recortan como a las demás; un filtro de moneda las deja fuera', () => {
+    const fuente: FuenteProyeccion = { ...mesLleno().fuente, reunionesClientes: [
+      reunion('r1', 'ana', {}), reunion('r2', 'ana', { persona: 'persona:r1' }), reunion('r3', 'diego', { persona: 'oculta:r3', nombre: 'Cliente fuera de tu cartera' }),
+      reunion('r4', 'luis', { creadoEn: '2026-09-30T15:00:00Z' }), // creada fuera del rango: no entra
+    ] }
+    const hoja = calcularProyeccion(fuente)
+    expect(ids(hoja.cohorte.filter(c => c.cita.leadId === null))).toEqual(['r1', 'r2', 'r3'])
+    expect(ids(fila(calcularProyeccion(con(fuente, { equipo: 'sup-2' })), 'diego')!.clientes)).toEqual(['d1', 'r3'])
+    expect(calcularProyeccion(con(fuente, { equipo: 'sup-2' })).cohorte.some(c => c.cita.id === 'r1')).toBe(false)
+    expect(opcionesAnalistas(hoja, {}).map(o => [o.id, o.citas])).toEqual([['ana', 6], ['diego', 3], ['luis', 1]])
+    // Embudo de Clientes: por persona (las dos reuniones de r1 juntas); la redactada con el texto del servidor.
+    expect(opcionesPersonas(hoja, {}, 'cliente').map(o => [o.id, o.nombre, o.citas])).toEqual([
+      ['oculta:r3', 'Cliente fuera de tu cartera', 1], ['persona:r1', 'CLIENTE R1', 2], ['lead:lead-5', 'Persona d1', 1],
+    ])
+    const soloR1 = calcularProyeccion(fuente, { personas: { cliente: ['persona:r1'] } })
+    expect(ids(soloR1.total.clientes)).toEqual(['r1', 'r2'])
+    expect(soloR1.total.leads.length).toBe(hoja.total.leads.length)
+    // Sin moneda: un filtro de moneda las deja fuera, y no cuentan en las monedas del embudo.
+    expect(calcularProyeccion(fuente, { monedas: ['PEN'] }).cohorte.some(c => c.cita.leadId === null)).toBe(true)
+    expect(calcularProyeccion(fuente, { monedas: ['PEN'] }).total.citas.some(c => c.cita.leadId === null)).toBe(false)
+    expect(opcionesMonedas(hoja, {})).toEqual(opcionesMonedas(calcularProyeccion(mesLleno().fuente), {}))
+  })
+
+  it('una clave de persona igual a la de un lead no las empareja: la venta del lead no cierra la reunión', () => {
+    const base = ejemplo(false)
+    const poblacion: PersonaProyeccion[] = [{ lead_id: 'lead-1', identidad_persona: 'persona:p1' }]
+    const misma = reunion('r1', 'ana', { persona: 'persona:p1', estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z' })
+    const con = fila(calcularProyeccion({ ...base, poblacion, reunionesClientes: [misma] }), 'ana')!
+    const sin = fila(calcularProyeccion({ ...base, poblacion }), 'ana')!
+    expect(ids(con.convertidas)).toEqual(['a1'])
+    expect([con.personasEntrevistadas, con.personasClientes, con.pctConversion, con.proyectado]).toEqual([sin.personasEntrevistadas, sin.personasClientes, sin.pctConversion, sin.proyectado])
+  })
+
+  it('columnas de tiempo por su día de creación; la lista y su CSV llevan la fila sin monto ni moneda y con origen Cliente', () => {
+    const hoja = calcularProyeccion({ ...ejemplo(), tiempo: 'semanas' })
+    const ana = fila(hoja, 'ana')!
+    // S1 1–7: a1 a2 a3 · S2 8–14: r1 r2 · S3 · S4.
+    expect(ana.porTramo.map(ids)).toEqual([['a1', 'a2', 'a3'], ['r1', 'r2'], [], []])
+    const csv = csvCitasProyeccion(ana.clientes).split('\r\n')
+    expect(csv[1]).toBe('"r1","2026-10-12","11:00","CLIENTE R1","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
+    expect(csv[2]).toBe('"r2","2026-10-12","11:00","Cliente fuera de tu cartera","Ana Torres","Claudia Ríos","No asistió","","","","Cliente"')
+    const hojaCsv = csvProyeccion(calcularProyeccion(ejemplo()), 'Octubre').split('\r\n')
+    // Citas 5 · Monto 60 000 · Ticket 20 000 · % Entrev. 60 · % Conv. 50 · Proyectado · Referidos 0 · Clientes 2 · Leads 3.
+    expect(hojaCsv[1]).toBe('"Octubre","Claudia Ríos","Ana Torres","5","60000","20000","60","50","32631.58","0","2","3"')
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.test.ts b/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.test.ts
index 7ce7fa6b..278c0453 100644
--- a/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.test.ts
+++ b/CRM-Avance-Corp/app/src/data/citas-clientes-proyeccion.test.ts
@@ -3,9 +3,11 @@ import * as v from 'valibot'
 const mocks = vi.hoisted(() => ({ rpc: vi.fn(), schema: vi.fn(), abortSignal: vi.fn() }))
 vi.mock('@/lib/supabase', () => ({ sb: { schema: mocks.schema } }))
 import {
-  cargarCitasClientesProyeccion, citasClientesProyeccionCoherentes, CitasClientesProyeccionSchema,
-  type CitasClientesProyeccionRpc,
+  adaptarCitasClientesProyeccion, cargarCitasClientesProyeccion, citasClientesProyeccionCoherentes, CitasClientesProyeccionSchema,
+  esRangoDemasiadoGrande, opcionesCitasClientesProyeccion, type CitasClientesProyeccionRpc,
 } from './citas-clientes-proyeccion'
+import { CrmApiError } from './crm-api'
+import { crmQueryKeys } from './crm-queries'
 
 // Payload EJECUTADO en el banco Docker (19/10/2026) por crm.citas_clientes_proyeccion_fn como el
 // vendedor sintético V1, F6 encendida: datos inventados. Incluye perfil visible, persona F6
@@ -198,3 +200,70 @@ describe('carga de la proyección de reuniones con clientes', () => {
     await expect(cargarCitasClientesProyeccion('2026-09-01', '2026-09-30')).rejects.toMatchObject({ code: 'CITAS_CONTRATO' })
   })
 })
+
+describe('reuniones con clientes como citas de la Proyección', () => {
+  it('cada reunión es una cita sin lead, monto ni moneda, con la persona del servidor y el estado de Citas', () => {
+    const reuniones = adaptarCitasClientesProyeccion(copia())
+    expect(reuniones.map(r => [r.id.slice(-2), r.estado, r.persona.split(':')[0], r.nombre])).toEqual([
+      // Pendientes con fecha anterior al corte: «vencida», como en Citas.
+      ['f4', 'vencida', 'perfil', 'CLIENTE PERFIL TRES'], ['d1', 'realizada', 'perfil', 'CLIENTE PERFIL TRES'],
+      ['d2', 'realizada', 'persona', 'CLIENTE PERSONA UNO'], ['d4', 'no_show', 'oculta', 'Cliente fuera de tu cartera'],
+      ['dc', 'vencida', 'persona', 'CLIENTE PERSONA UNO'],
+    ])
+    const d1 = reuniones.find(r => r.id.endsWith('d1'))!
+    expect(d1).toEqual({
+      id: '00000000-0000-0000-0000-0000000000d1', leadId: null, moneda: null, monto: null,
+      persona: 'perfil:00000000-0000-0000-0000-0000000000c3', nombre: 'CLIENTE PERFIL TRES',
+      analista: '00000000-0000-0000-0000-0000000000e3', analistaNombre: 'VENDEDOR UNO',
+      supervisor: 'SUPERVISOR UNO', supervisorId: '00000000-0000-0000-0000-0000000000e2',
+      fecha: '2026-10-07', hora: '10:00', estado: 'realizada', creadoEn: '2026-10-05T10:00:00-05:00',
+      asistioEn: '2026-10-07T11:00:00-05:00',
+    })
+    // La persona redactada conserva su clave propia y el texto del servidor, sin datos personales.
+    expect(reuniones.find(r => r.id.endsWith('d4'))).toMatchObject({ persona: 'oculta:00000000-0000-0000-0000-0000000000d4', nombre: 'Cliente fuera de tu cartera' })
+    expect(reuniones.find(r => r.id.endsWith('d4'))).not.toHaveProperty('asistioEn')
+  })
+
+  it('mapea todos los estados y los responsables vacíos igual que Citas', () => {
+    const d = copia()
+    const [f4, d1, d2, d4, dc] = d.citas
+    Object.assign(f4!, { vence_en: '2026-10-25T10:00:00-05:00' })
+    Object.assign(d1!, { estado: 'cancelada', cancelada_por: 'asesor', asistencia_registrada_en: null })
+    Object.assign(d2!, { estado: 'cancelada', cancelada_por: 'sistema', asistencia_registrada_en: null })
+    Object.assign(d4!, { estado: 'reprogramada', analista_id: null, analista_nombre: 'Sin analista', supervisor_id: null, supervisor_nombre: 'Sin supervisor' })
+    Object.assign(dc!, { estado: 'no_show' })
+    const reuniones = adaptarCitasClientesProyeccion(d)
+    expect(reuniones.map(r => r.estado)).toEqual(['programada', 'cancelada', 'sistema', 'reprogramada', 'no_show'])
+    expect(reuniones[3]).toMatchObject({ analista: 'sin_analista', analistaNombre: 'Sin analista', supervisor: 'Sin supervisor', supervisorId: 'sin_supervisor' })
+  })
+
+  it('un rango demasiado grande (54000 o 57014) da un mensaje claro y no se reintenta solo', async () => {
+    for (const code of ['54000', '57014']) {
+      responder(null, { code, message: 'canceling statement due to statement timeout' })
+      const error = await cargarCitasClientesProyeccion('2026-10-01', '2026-10-31').catch((e: unknown) => e)
+      expect(error).toMatchObject({ code, message: 'El rango es demasiado grande. Acorta las fechas.' })
+      expect(esRangoDemasiadoGrande(error)).toBe(true)
+    }
+    expect(esRangoDemasiadoGrande(new CrmApiError('No autorizado', '42501'))).toBe(false)
+    const { retry, refetchInterval } = opcionesCitasClientesProyeccion({ desde: '2026-10-01', hasta: '2026-10-31' }, 'actor', true)
+    expect(refetchInterval({ state: { error: new CrmApiError('x', '57014') } })).toBe(false)
+    expect(refetchInterval({ state: { error: null } })).toBe(60_000)
+    expect(retry(0, new CrmApiError('x', '54000'))).toBe(false)
+    expect(retry(0, new CrmApiError('x', '57014'))).toBe(false)
+    expect(retry(0, new CrmApiError('x', '08006'))).toBe(true)
+    expect(retry(1, new CrmApiError('x', '08006'))).toBe(false)
+  })
+
+  it('una consulta por rango y actor, bajo el detalle de Citas; sin rango, sin actor o en demostración no consulta', async () => {
+    const rango = { desde: '2026-10-01', hasta: '2026-10-19' }
+    const opciones = opcionesCitasClientesProyeccion(rango, 'actor', true)
+    expect(opciones.queryKey).toEqual([...crmQueryKeys.citasGerenciaPrefijo(), 'clientes-proyeccion', 'actor', '2026-10-01', '2026-10-19'])
+    expect(opciones).toMatchObject({ enabled: true, staleTime: 30_000, refetchIntervalInBackground: false, refetchOnWindowFocus: true, refetchOnReconnect: true })
+    expect(opcionesCitasClientesProyeccion(null, 'actor', true).enabled).toBe(false)
+    expect(opcionesCitasClientesProyeccion(rango, null, true).enabled).toBe(false)
+    expect(opcionesCitasClientesProyeccion(rango, 'actor', false).enabled).toBe(false)
+    responder({ ...copia(), periodo: { desde: '2026-10-01', hasta: '2026-10-19' } })
+    await expect(opciones.queryFn({ signal: new AbortController().signal })).resolves.toMatchObject({ periodo: rango })
+    expect(mocks.rpc).toHaveBeenCalledWith('citas_clientes_proyeccion_fn', { p_desde: '2026-10-01', p_hasta: '2026-10-19' })
+  })
+})
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.test.tsx
index 7ec96564..8304a928 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.test.tsx
@@ -4,9 +4,15 @@ import { renderHook, waitFor } from '@testing-library/react'
 import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
 import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
 import type { ConsultaCitasRpc } from '@/data/citas-gerencia'
-import { useMesesCitasGerencia } from './use-datos-citas-gerencia'
+import type { CitasClientesProyeccionRpc } from '@/data/citas-clientes-proyeccion'
+import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'
+import { useDatosProyeccionCitas, useMesesCitasGerencia } from './use-datos-citas-gerencia'
 
-const servidor = vi.hoisted(() => ({ fallar: new Set<string>(), llamadas: [] as string[] }))
+const servidor = vi.hoisted(() => ({
+  fallar: new Set<string>(), llamadas: [] as string[],
+  // Reuniones con clientes: una llamada por rango; `pendiente` retiene la respuesta hasta resolverla.
+  clientes: [] as string[], fallarClientes: false, pendiente: null as Promise<void> | null,
+}))
 const consulta = (mes: string, cita: string): ConsultaCitasRpc => ({
   version: 1, periodo: { desde: `${mes}-01`, hasta: `${mes}-28` }, generado_en: `${mes}-28T15:00:00Z`, citas_clientes: 0,
   disponibilidad_depositos: 'sin_registro', depositos: [],
@@ -25,6 +31,24 @@ vi.mock('@/data/citas-gerencia', async importOriginal => ({ ...await importOrigi
     },
   }) }))
 
+const reuniones = (rango: RangoProyeccion): CitasClientesProyeccionRpc => ({
+  version: 1, periodo: rango, criterio: 'creado_en', generado_en: '2026-10-19T17:00:00Z',
+  citas: [{ id: 'reunion-1', creado_en: `${rango.desde}T15:00:00Z`, vence_en: '2026-10-10T15:00:00Z', estado: 'completada', cancelada_por: null,
+    asistencia_registrada_en: '2026-10-10T16:00:00Z', analista_id: 'ana', analista_nombre: 'ANA', supervisor_id: 'sup', supervisor_nombre: 'SUP',
+    sujeto_tipo: 'inversionista', sujeto_id: 'p1', sujeto_nombre: 'CLIENTE', inversionista_id: 'p1', perfil_id: null, identidad_visible: true,
+    identidad_persona: 'persona:p1' }],
+})
+vi.mock('@/data/citas-clientes-proyeccion', async importOriginal => ({ ...await importOriginal<typeof import('@/data/citas-clientes-proyeccion')>(),
+  opcionesCitasClientesProyeccion: (rango: RangoProyeccion | null, actorId: string | null, habilitada: boolean) => ({
+    queryKey: ['clientes-prueba', actorId, rango?.desde, rango?.hasta], enabled: habilitada && rango !== null, retry: false,
+    queryFn: async () => {
+      servidor.clientes.push(`${rango!.desde}|${rango!.hasta}`)
+      await servidor.pendiente
+      if (servidor.fallarClientes) throw new Error('El rango es demasiado grande. Acorta las fechas.')
+      return reuniones(rango!)
+    },
+  }) }))
+
 function montar(meses: string[], demo = false) {
   const cliente = new QueryClient()
   const sesion = { fase: 'listo', error: null, yo: { id: 'gerente', nombre_completo: 'GERENTE', rol: 'gerencia', demo, puede_contratar: false } } as unknown as AuthContextValue
@@ -62,3 +86,63 @@ describe('useMesesCitasGerencia: meses del rango de Proyección', () => {
     expect(servidor.llamadas).toEqual([])
   })
 })
+
+describe('useDatosProyeccionCitas: meses y reuniones con clientes del rango', () => {
+  const OCTUBRE = { desde: '2026-10-01', hasta: '2026-10-19' }
+  function montarRango(meses: string[], rango: RangoProyeccion | null, demo = false) {
+    const cliente = new QueryClient()
+    const sesion = { fase: 'listo', error: null, yo: { id: 'gerente', nombre_completo: 'GERENTE', rol: 'gerencia', demo, puede_contratar: false } } as unknown as AuthContextValue
+    const envoltorio = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}><AuthContext.Provider value={sesion}>{children}</AuthContext.Provider></QueryClientProvider>
+    return renderHook(({ m, r }) => useDatosProyeccionCitas(m, r), { wrapper: envoltorio, initialProps: { m: meses, r: rango } })
+  }
+  const reiniciar = () => { servidor.fallar.clear(); servidor.llamadas = []; servidor.clientes = []; servidor.fallarClientes = false; servidor.pendiente = null }
+
+  it('una sola llamada por rango; mientras falten sus reuniones no hay cifras, aunque los meses ya llegaran', async () => {
+    reiniciar()
+    let soltar = () => {}
+    servidor.pendiente = new Promise<void>(resolve => { soltar = resolve })
+    const { result, rerender } = montarRango(['2026-10'], OCTUBRE)
+    await waitFor(() => expect(servidor.llamadas).toEqual(['2026-10']))
+    await new Promise(resolve => setTimeout(resolve, 20))
+    expect(result.current).toMatchObject({ cargando: true, citas: [], reunionesClientes: [], error: null, rango: OCTUBRE })
+    soltar()
+    await waitFor(() => expect(result.current.cargando).toBe(false))
+    expect(result.current.citas.map(c => c.id)).toEqual(['cita-2026-10'])
+    expect(result.current.reunionesClientes).toEqual([expect.objectContaining({ id: 'reunion-1', leadId: null, monto: null, moneda: null,
+      persona: 'persona:p1', estado: 'realizada', analista: 'ana', supervisorId: 'sup' })])
+    expect(servidor.clientes).toEqual(['2026-10-01|2026-10-19'])
+    // Otro rango del mismo mes: nueva llamada de reuniones, sin volver a pedir el mes; mientras tanto, sin cifras.
+    rerender({ m: ['2026-10'], r: { desde: '2026-10-15', hasta: '2026-10-19' } })
+    expect(result.current).toMatchObject({ cargando: true, citas: [], reunionesClientes: [] })
+    await waitFor(() => expect(result.current.cargando).toBe(false))
+    expect(servidor.clientes).toEqual(['2026-10-01|2026-10-19', '2026-10-15|2026-10-19'])
+    expect(servidor.llamadas).toEqual(['2026-10'])
+  })
+
+  it('si fallan las reuniones no hay cifras parciales; Reintentar vuelve a pedir solo las reuniones', async () => {
+    reiniciar()
+    servidor.fallarClientes = true
+    const { result } = montarRango(['2026-10'], OCTUBRE)
+    await waitFor(() => expect(result.current.error).toBe('El rango es demasiado grande. Acorta las fechas.'))
+    expect(result.current).toMatchObject({ cargando: false, citas: [], reunionesClientes: [] })
+    servidor.fallarClientes = false
+    result.current.onReintentar()
+    await waitFor(() => expect(result.current.reunionesClientes).toHaveLength(1))
+    expect(result.current).toMatchObject({ cargando: false, error: null })
+    expect(servidor.clientes).toHaveLength(2)
+    expect(servidor.llamadas).toEqual(['2026-10'])
+  })
+
+  it('sin rango o en demostración no pide las reuniones', async () => {
+    reiniciar()
+    const sinRango = montarRango(['2026-10'], null)
+    await waitFor(() => expect(servidor.llamadas).toEqual(['2026-10']))
+    expect(sinRango.result.current).toMatchObject({ cargando: true, citas: [], rango: null })
+    expect(servidor.clientes).toEqual([])
+    reiniciar()
+    const demo = montarRango(['2026-10'], OCTUBRE, true)
+    expect(demo.result.current.cargando).toBe(true)
+    await new Promise(resolve => setTimeout(resolve, 20))
+    expect([servidor.llamadas, servidor.clientes]).toEqual([[], []])
+  })
+})
```

## Archivo completo: app/src/data/citas-clientes-proyeccion.ts
```ts
import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { crmQueryKeys } from './crm-queries'
import { CADENCIA_CITAS, estadoDeCita, fechaLima } from './citas-gerencia'
import { camposIdentidadCliente, identidadClienteValida } from '@/lib/sujeto-gestion'
import { FechaSchema } from '@/lib/esquemas-rpc'
import { horaLima } from '@/components/citas/contexto'
import type { ReunionClienteProyeccion } from '@/components/citas/proyeccion'
import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'

/**
 * Proyección de citas, Fase 0b (19/10/2026): reuniones con CLIENTES que no tienen lead,
 * contadas por fecha de CREACIÓN (día de Lima), sin paginar. Puerta
 * `crm.citas_clientes_proyeccion_fn` → núcleo `private.citas_clientes_proyeccion`
 * (migración 20261019213516 + enmienda 20261019224227). La usa la pestaña Proyección de Citas.
 *
 * `generado_en` es el CORTE (enmienda 20261019224227): el servidor sólo devuelve reuniones
 * creadas, y asistencias registradas, hasta ese instante; por eso el validador lo exige.
 * Coste medido en el banco: ~0,7 ms por persona F6 distinta y ~6 ms por perfil distinto; con
 * el `statement_timeout` de 8 s, un rango con más de ~1 000 perfiles distintos da 57014
 * (en producción no hay reuniones de perfil: las 39 históricas son de persona F6).
 *
 * Para la pantalla:
 * - Estas reuniones NO están en `crm.citas_gerencia_consulta[_v2]_fn` (que sólo recorre
 *   tareas con lead): se suman sin duplicar. El total `citas_clientes` de ese lector
 *   cuenta otra población (perfil, por fecha programada): no sumar ambos.
 * - Todas son citas con quien ya es cliente (perfil o persona F6).
 * - `identidad_persona` sólo nombra a la persona si su identidad es visible; si no, es
 *   `oculta:<id de la tarea>` (una por cita). No sirve para emparejar con el
 *   `identidad_persona` del lector de leads.
 */
const Instante = v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s))))
const Id = v.pipe(v.string(), v.uuid())
const UUID_TEXTO = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

const CitaClienteProyeccionCampos = v.object({
  ...camposIdentidadCliente,
  id: Id, creado_en: Instante, vence_en: Instante,
  estado: v.picklist(['pendiente','completada','no_show','cancelada','reprogramada']),
  cancelada_por: v.nullable(v.string()),
  asistencia_registrada_en: v.nullable(Instante),
  analista_id: v.nullable(Id), analista_nombre: v.string(),
  supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
  identidad_persona: v.pipe(v.string(), v.regex(new RegExp(`^(persona|perfil|oculta):${UUID_TEXTO}$`))),
})
type CitaClienteProyeccionCruda = v.InferOutput<typeof CitaClienteProyeccionCampos>

/** La clave de persona tiene que salir de la identidad que el servidor dejó ver, y de nada más. */
function identidadPersonaCoherente(c: CitaClienteProyeccionCruda): boolean {
  if (!c.identidad_visible) return c.identidad_persona === `oculta:${c.id}`
  if (c.inversionista_id) return c.identidad_persona === `persona:${c.inversionista_id}`
  return c.perfil_id !== null && c.identidad_persona === `perfil:${c.perfil_id}`
}

export const CitaClienteProyeccionSchema = v.pipe(CitaClienteProyeccionCampos, v.check(c =>
  identidadClienteValida(c) && identidadPersonaCoherente(c)
  && (c.asistencia_registrada_en === null || c.estado === 'completada')))

export const CitasClientesProyeccionSchema = v.object({
  version: v.literal(1),
  periodo: v.object({ desde: FechaSchema, hasta: FechaSchema }),
  criterio: v.literal('creado_en'),
  generado_en: Instante,
  citas: v.pipe(v.array(CitaClienteProyeccionSchema), v.maxLength(10000)),
})
export type CitasClientesProyeccionRpc = v.InferOutput<typeof CitasClientesProyeccionSchema>
export type CitaClienteProyeccion = CitasClientesProyeccionRpc['citas'][number]

/** El payload corresponde a lo pedido: mismo período, ids únicos y cada cita GENERADA dentro del rango. */
export function citasClientesProyeccionCoherentes(d: CitasClientesProyeccionRpc, desde: string, hasta: string): boolean {
  if (d.periodo.desde !== desde || d.periodo.hasta !== hasta) return false
  if (new Set(d.citas.map(c => c.id)).size !== d.citas.length) return false
  const generado = Date.parse(d.generado_en)
  return d.citas.every(c => {
    const dia = fechaLima(c.creado_en)
    return dia >= desde && dia <= hasta && Date.parse(c.creado_en) <= generado
      && (c.asistencia_registrada_en === null || Date.parse(c.asistencia_registrada_en) <= generado)
  })
}

/** Puerta tipada (tipos generados tras instalar 20261019213516 y su enmienda); la respuesta se valida siempre con su esquema. */
async function rpcProyeccionClientes(args: { p_desde: string; p_hasta: string }, signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No se pudo conectar con el CRM.', 'CITAS_SIN_CONEXION')
  const consulta = sb.schema('crm').rpc('citas_clientes_proyeccion_fn', args)
  return signal ? consulta.abortSignal(signal) : consulta
}

/** Más de 10 000 reuniones (54000) o la consulta agotó su tiempo (57014): el rango es demasiado grande. */
const RANGO_DEMASIADO_GRANDE = new Set(['54000', '57014'])
export const esRangoDemasiadoGrande = (error: unknown) => error instanceof CrmApiError && RANGO_DEMASIADO_GRANDE.has(error.code)

function mensajeDeError(code: string | null | undefined): string {
  if (code === 'PGRST202') return 'Las reuniones con clientes de la Proyección aún no están habilitadas en este servidor.'
  if (code && RANGO_DEMASIADO_GRANDE.has(code)) return 'El rango es demasiado grande. Acorta las fechas.'
  return 'No se pudieron cargar las reuniones con clientes. Reintenta la consulta.'
}

/** Reuniones con clientes sin lead generadas entre `desde` y `hasta` (YYYY-MM-DD, día de Lima; hasta un año). */
export async function cargarCitasClientesProyeccion(desde: string, hasta: string, signal?: AbortSignal): Promise<CitasClientesProyeccionRpc> {
  if (!v.is(FechaSchema, desde) || !v.is(FechaSchema, hasta) || desde > hasta) {
    throw new CrmApiError('Selecciona un rango válido.', 'CITAS_PERIODO')
  }
  const { data, error } = await rpcProyeccionClientes({ p_desde: desde, p_hasta: hasta }, signal)
  if (error) throw new CrmApiError(mensajeDeError(error.code), error.code ?? undefined)
  const resultado = v.safeParse(CitasClientesProyeccionSchema, data)
  if (!resultado.success || !citasClientesProyeccionCoherentes(resultado.output, desde, hasta)) {
    throw new CrmApiError('La respuesta de reuniones con clientes está incompleta o no corresponde al rango.', 'CITAS_CONTRATO')
  }
  return resultado.output
}

/**
 * Cada reunión como cita de la hoja: origen Cliente, sin lead, monto ni moneda; analista y supervisor del
 * lector (con los mismos «sin analista» / «sin supervisor» que Citas) y el estado en el vocabulario de Citas.
 */
export function adaptarCitasClientesProyeccion(datos: CitasClientesProyeccionRpc): ReunionClienteProyeccion[] {
  return datos.citas.map(c => ({
    id: c.id, leadId: null, moneda: null, monto: null, persona: c.identidad_persona, nombre: c.sujeto_nombre,
    analista: c.analista_id ?? 'sin_analista', analistaNombre: c.analista_nombre,
    supervisor: c.supervisor_nombre, supervisorId: c.supervisor_id ?? 'sin_supervisor',
    fecha: fechaLima(c.vence_en), hora: horaLima(c.vence_en), estado: estadoDeCita(c, datos.generado_en), creadoEn: c.creado_en,
    ...(c.asistencia_registrada_en ? { asistioEn: c.asistencia_registrada_en } : {}),
  }))
}

/**
 * Una consulta por rango, con la cadencia y la caché de los meses de Citas. Sin rango (otra pestaña) o en
 * demostración no consulta. Un rango demasiado grande no se reintenta ni se refresca solo: fallaría igual.
 */
export function opcionesCitasClientesProyeccion(rango: RangoProyeccion | null, actorId: string | null, habilitada: boolean) {
  const desde = rango?.desde ?? '', hasta = rango?.hasta ?? ''
  return {
    queryKey: crmQueryKeys.citasClientesProyeccion(actorId, desde, hasta),
    queryFn: ({ signal }: { signal: AbortSignal }) => cargarCitasClientesProyeccion(desde, hasta, signal),
    enabled: habilitada && Boolean(actorId) && rango !== null,
    ...CADENCIA_CITAS,
    refetchInterval: (consulta: { state: { error: unknown } }) => esRangoDemasiadoGrande(consulta.state.error) ? false : CADENCIA_CITAS.refetchInterval,
    retry: (fallos: number, error: Error) => fallos < 1 && !esRangoDemasiadoGrande(error),
  }
}
```
