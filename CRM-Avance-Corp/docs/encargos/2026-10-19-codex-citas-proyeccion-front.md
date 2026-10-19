ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 2, una sola pasada): REFUTA la pestaña «Proyección» del módulo Citas del CRM (front, React + TypeScript)

Contexto. CRM de Avance Corp (`CRM-Avance-Corp/app`, React 19 + Vite + Valibot + TanStack Query + Vitest + Playwright). El módulo Citas (Gerencia/Supervisión) lee un JSON mensual del servidor (`crm.citas_gerencia_consulta_fn(p_desde, p_hasta)`, sólo meses completos, recorte por rol en servidor) y lo adapta a `CitaEjemplo` (`src/components/citas/modelo.ts`). Hoy tiene tres pestañas (Bandeja comercial · Agenda · Resultados). Se añade la cuarta, **«Proyección»**: una hoja tipo Excel por analista, a todo el ancho, aprobada visualmente por el dueño.

Decisiones del dueño (19/10/2026) que la pantalla debe cumplir:
- Columnas: # · Analista · Citas · Monto S/ · Ticket S/ · % Entrev. · % Conv. · Proyectado S/ · Referidos · Clientes · Leads. Pastillas pequeñas arriba. Filas agrupadas por equipo (plegables), numeración continua, fila Σ fija abajo.
- Periodo por **rango Desde–Hasta** (control propio de la pestaña; atajos Hoy · Esta semana · Mes · Mes pasado · S1–S4; tope 6 meses). Cohorte = citas cuya FECHA DE CREACIÓN (día Lima) cae en el rango; los filtros de arriba Supervisor/Analista/búsqueda se respetan; `semana`/`dia` de arriba no aplican.
- Si el rango cruza meses, la pantalla carga cada mes (misma consulta y caché) y fusiona: citas sin repetir id; población/conversiones/asignaciones deduplicadas por lead (gana el mes más reciente); mientras falte un mes no hay cifras parciales.
- Reglas de cálculo: Monto S/ = Σ monto estimado (USD al TC del día; sin TC con USD → «Pendiente de TC»); Ticket = Monto ÷ Citas; % Entrev. = citas realizadas ÷ citas; % Conv. = personas convertidas ÷ personas entrevistadas (conversión posterior o igual a la asistencia; identidad de persona como `avance.ts`); Proyectado = citas esperadas (max(citas, citas hasta hoy ÷ días transcurridos × días del rango); rango cerrado → citas) × %Entrev × %Conv × Ticket; la fila Σ recalcula sobre todas las citas y SUMA los proyectados con base (nunca promedia tasas).
- Origen: Referidos (lead `origen = 'referido'`), Clientes (`es_cliente` del servidor, Fase 0 aún no instalada; respaldo: la persona ya se había convertido ANTES de crearse la cita), Leads = resto; Referidos + Clientes + Leads = Citas.
- «Todo número se abre» (lista lateral exacta con CSV; un 0 no es botón). Embudos tipo Excel por cabecera (ordenar; Analista con casillas y buscador; Referidos/Clientes/Leads con lista de personas que recorta sólo las citas de ese origen; Monto con Soles/Dólares + Mín/Máx en soles; numéricas Mín/Máx; chips con × y Limpiar). Sin textos explicativos. Nombre ≥16 px, celdas 14 px, cabecera 13 px, `tabular-nums`, sin scroll horizontal a 1440 px, no se rompe en celular.
- Campo nuevo opcional `es_cliente` en el esquema Valibot (`v.object` ignora claves desconocidas), mapeado a `esCliente`.

Tu trabajo: REFUTAR. Busca (a) cifras mal calculadas frente a estas reglas (cohorte, rango, ritmo, dedupe multi-mes, identidad, TC, respaldo de Clientes, Σ), (b) estados que mientan (cargas parciales, mes vacío, sin TC, sin conversiones), (c) roturas de las otras pestañas o del hook mensual compartido (`useDatosCitasGerencia`, `useCitasGerencia`, `filtrar`), (d) fugas de datos entre roles en la pantalla (el recorte es del servidor; la pantalla no debe ampliar nada), (e) accesibilidad y teclado de los embudos/lista lateral, (f) pruebas vacías o que no prueben lo que dicen (hay 14 mutantes declarados por el implementador: ¿cuál NO está cubierto de verdad?), (g) coste: hasta 6 consultas abiertas con refresco de 60 s.

Puedes LEER el árbol del worktree (sandbox de solo lectura; cwd = raíz del repo `CRM-Avance-Corp`). Archivos NUEVOS, léelos directamente:
- `app/src/components/citas/proyeccion.ts` (cálculo puro), `proyeccion-rango.ts`, `proyeccion-hoja.tsx`, `proyeccion-embudo.tsx`, `proyeccion-detalle.tsx`, `proyeccion-barra-rango.tsx`, `proyeccion-descarga.ts`, `proyeccion.css`
- pruebas: `app/src/components/citas/proyeccion.test.ts`, `proyeccion-hoja.test.tsx`, `app/src/data/citas-gerencia-meses.test.ts`, `app/src/screens/hoy/use-datos-citas-gerencia.test.tsx`, `app/e2e/citas-proyeccion.spec.ts`
- contexto que ya existía: `app/src/components/citas/avance.ts` (reglas de identidad/vínculo), `modelo.ts`, `contexto.ts`, `propuesta.tsx`, `app/src/data/citas-gerencia.ts`, `app/src/screens/hoy/use-datos-citas-gerencia.ts`, `app/src/lib/tipo-cambio.ts`, `app/src/lib/capital-unificado.ts`.

Verificación ya hecha por el implementador (PASS reportado, no ejecutado por ti): `npm run check` (lint, typecheck, 7 351 pruebas, cobertura por encima de umbrales, build, jscpd 0,74 %), E2E Docker 7/7, `revisor-a11y` sin P0/P1 (P2 aplicados).

## Diff de los archivos MODIFICADOS (transcrito; los nuevos están en el árbol)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/citas/contexto.ts b/CRM-Avance-Corp/app/src/components/citas/contexto.ts
index d6742ef3..a4311449 100644
--- a/CRM-Avance-Corp/app/src/components/citas/contexto.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/contexto.ts
@@ -3,6 +3,11 @@ import { equipoCitas } from './modelo'
 import type { CitaConLead } from './datos'
 import type { DepositoEjemplo } from './depositos'
 import type { GestionCitas } from './metas'
+/** Citas fusionadas de los meses del rango de Proyección (lo provee la pantalla). */
+export interface DatosProyeccionCitas {
+  meses: string[]; citas: CitaConLead[]; gestion: GestionCitas | undefined; corte: string;
+  cargando: boolean; error: string | null; onReintentar: () => void;
+}
 export interface DatosCitas {
   citas: CitaConLead[]; corte: string; depositos: DepositoEjemplo[]; depositosDisponibles: boolean;
   depositoPorConversion?: boolean;
@@ -10,6 +15,8 @@ export interface DatosCitas {
   mesInicial: string; modoDemo: boolean; meses: string[];
   cargando?: boolean; error?: string | null; onReintentar?: () => void;
   onMes?: (mes: string) => void; onAbrirLead?: (id: string, tareaId: string) => void;
+  /** Proyección avisa qué meses necesita su rango; sin cargador usa las citas de arriba. */
+  onMesesProyeccion?: (meses: string[]) => void; proyeccion?: DatosProyeccionCitas;
 }
 export const ContextoCitas = createContext<DatosCitas | null>(null)
 export function useDatosCitas() {
diff --git a/CRM-Avance-Corp/app/src/components/citas/modelo.ts b/CRM-Avance-Corp/app/src/components/citas/modelo.ts
index 652f1cd3..36b0fdf9 100644
--- a/CRM-Avance-Corp/app/src/components/citas/modelo.ts
+++ b/CRM-Avance-Corp/app/src/components/citas/modelo.ts
@@ -11,6 +11,8 @@ export interface CitaEjemplo {
   citaAnteriorId?: string; reprogramadaEn?: string; asistioEn?: string;
   manualPropio?: boolean;
   registroManual?: boolean; creadoEn?: string;
+  /** La persona YA era cliente al crearse la cita (servidor, Fase 0). Ausente: la Proyección usa su respaldo. */
+  esCliente?: boolean;
 }
 export interface FiltrosCitas {
   q: string; equipo: string; analista: string; mes: string; semana: string; leadId?: string;
@@ -54,14 +56,18 @@ export function errorFiltros(f: FiltrosCitas) {
   if (f.moneda && f.min !== '' && f.max !== '' && Number(f.min) > Number(f.max)) return 'El monto mínimo debe ser menor o igual al máximo.'
   return ''
 }
+/** Búsqueda libre de la consulta: todas las palabras en prospecto, teléfono o código; o los dígitos del teléfono. */
+export function coincideBusqueda(c: Pick<CitaEjemplo, 'nombre' | 'telefono' | 'id'>, q: string) {
+  const palabras = normalizar(q).split(/\s+/).filter(Boolean)
+  const numeros = q.replace(/\D/g, '')
+  const texto = normalizar(`${c.nombre} ${c.telefono} ${c.id}`)
+  return palabras.every((p) => texto.includes(p)) || (numeros.length > 2 && /^[\d\s+()-]+$/.test(q) && c.telefono.replace(/\D/g, '').includes(numeros))
+}
 export function filtrar<T extends CitaEjemplo>(f: FiltrosCitas, citas: T[]) {
   if (errorFiltros(f)) return []
   const [desde, hasta] = rango(f)
-  const palabras = normalizar(f.q).split(/\s+/).filter(Boolean)
-  const numeros = f.q.replace(/\D/g, '')
   return citas.filter((c) => {
-    const texto = normalizar(`${c.nombre} ${c.telefono} ${c.id}`)
-    const busqueda = palabras.every((p) => texto.includes(p)) || (numeros.length > 2 && /^[\d\s+()-]+$/.test(f.q) && c.telefono.replace(/\D/g, '').includes(numeros))
+    const busqueda = coincideBusqueda(c, f.q)
     return (!f.leadId || c.leadId === f.leadId) && busqueda && (!desde || c.fecha >= desde) && (!hasta || c.fecha <= hasta)
       && (!f.equipo || c.supervisorId === f.equipo) && (!f.analista || c.analista === f.analista)
       && (!f.estados.length || f.estados.includes(c.estado)) && (!f.modalidad || c.modalidad === f.modalidad)
diff --git a/CRM-Avance-Corp/app/src/components/citas/presentacion.css b/CRM-Avance-Corp/app/src/components/citas/presentacion.css
index 3fa7a998..7910981a 100644
--- a/CRM-Avance-Corp/app/src/components/citas/presentacion.css
+++ b/CRM-Avance-Corp/app/src/components/citas/presentacion.css
@@ -131,8 +131,9 @@
   .citas-filtros-fila { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px 8px; padding: 12px; }
   .citas-filtros-fila > label:first-child { grid-column: span 2; }
   .citas-filtros-fila > button:last-child { justify-self: end; }
-  .citas-vistas { width: 100%; gap: 0; }
-  .citas-vistas .citas-pestana { flex: 1; padding-inline: 8px; font-size: 12px; }
+  /* Cuatro pestañas: si no caben en una línea (320–375 px), pasan a la siguiente. */
+  .citas-vistas { width: 100%; flex-wrap: wrap; gap: 0; }
+  .citas-vistas .citas-pestana { flex: 1 1 auto; padding-inline: 8px; font-size: 12px; }
   .citas-vistas .citas-pestana svg { display: none; }
   .citas-corte { font-size: 11px; }
   .citas-corte span { display: block; margin-left: 0; }
diff --git a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
index af93ff49..37e5ea56 100644
--- a/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
+++ b/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx
@@ -1,7 +1,7 @@
 import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'
 import { useDatosCitas, corteLima } from './contexto'
 import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
-import { CalendarDays, ChartNoAxesCombined, ChevronLeft, ChevronRight, CircleHelp, Download, List, SearchX, X } from 'lucide-react'
+import { CalendarDays, ChartNoAxesCombined, ChevronLeft, ChevronRight, CircleHelp, Download, List, SearchX, Table2, X } from 'lucide-react'
 import { Button } from '@/components/ui/button'
 import { Select } from '@/components/ui/select'
 import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
@@ -12,6 +12,9 @@ import { consultaInicial as defaults, consultarCitas as filtrar, rangoConsulta,
 import { Filtros } from './filtros'
 import { Agenda, Bandeja, Estado } from './vistas'
 import { Resultados, DetalleLeads } from './resultados'
+import { ProyeccionCitas } from './proyeccion-hoja'
+import { errorRango, mesesDelRango, rangoInicial, rotuloRango, type RangoProyeccion } from './proyeccion-rango'
+import { fechaLocalCitas } from './fecha-comercial'
 import { siguientePaso, contextoCita } from './presentacion'
 import { baseCitasFiltrada } from './metas'
 import { escribirHash, leerHash } from '@/lib/router'
@@ -21,11 +24,12 @@ function filtrosDelEnlace(consulta: ConsultaCitasEnlace): FiltrosCitas {
   return { ...defaults(mesConsultaCitas(consulta)), ...(consulta.dia ? { dia: consulta.dia } : {}), semana: consulta.semana ?? '', equipo: consulta.equipo ?? '' }
 }
 
-type VistaCitas = 'bandeja' | 'agenda' | 'resultados'
+type VistaCitas = 'bandeja' | 'agenda' | 'resultados' | 'proyeccion'
 const VISTAS = [
   { id: 'bandeja', titulo: 'Bandeja comercial', icono: List },
   { id: 'agenda', titulo: 'Agenda', icono: CalendarDays },
   { id: 'resultados', titulo: 'Resultados', icono: ChartNoAxesCombined },
+  { id: 'proyeccion', titulo: 'Proyección', icono: Table2 },
 ] as const
 const ATAJOS: (EstadoCita | '')[] = ['', 'vencida', 'programada', 'realizada', 'no_show']
 const POR_PAGINA = 8
@@ -67,7 +71,7 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   const consultaSesion = useConsultaGerencia()
   const guardarConsulta = conservarConsulta ? consultaSesion?.setConsulta : undefined
   const guardada = conservarConsulta ? consultaSesion?.consulta.citas : undefined
-  const { citas: CITAS, equipo: EQUIPO, gestion, corte, modoDemo, mesInicial, cargando, error: errorCarga, onReintentar, onMes } = useDatosCitas()
+  const { citas: CITAS, equipo: EQUIPO, gestion, corte, modoDemo, mesInicial, cargando, error: errorCarga, onReintentar, onMes, onMesesProyeccion } = useDatosCitas()
   const inicial = () => defaults(mesInicial)
   const desdeEnlace = () => {
     const consulta = leerHash().consultaCitas
@@ -77,9 +81,18 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   const [vista, setVista] = useState<VistaCitas>(() => leerHash().consultaCitas ? 'agenda' : guardada?.vista ?? 'resultados')
   const enlaceAnterior = useRef(JSON.stringify(leerHash().consultaCitas ?? null))
   const [pagina, setPagina] = useState(() => leerHash().consultaCitas ? 1 : guardada?.pagina ?? 1)
+  // Rango Desde–Hasta de Proyección: propio de esa pestaña. Nace del mes de arriba
+  // y vuelve a nacer si ese mes cambia; no toca los filtros de las otras vistas.
+  const rangoDelMes = (mes: string) => ({ mes, ...rangoInicial(mes, fechaLocalCitas(corte)) })
+  const [rangoMes, setRangoMes] = useState<{ mes: string } & RangoProyeccion>(() =>
+    guardada?.rango && guardada.rango.mes === filtros.mes && !errorRango(guardada.rango) ? guardada.rango : rangoDelMes(filtros.mes))
+  if (rangoMes.mes !== filtros.mes && rangoConsulta(defaults(filtros.mes))[0]) setRangoMes(rangoDelMes(filtros.mes))
+  const rangoProyeccion = { desde: rangoMes.desde, hasta: rangoMes.hasta }
+  const mesesProyeccion = vista === 'proyeccion' && !errorRango(rangoProyeccion) ? mesesDelRango(rangoProyeccion).join(',') : ''
+  useEffect(() => { onMesesProyeccion?.(mesesProyeccion ? mesesProyeccion.split(',') : []) }, [mesesProyeccion, onMesesProyeccion])
   useEffect(() => {
-    guardarConsulta?.(anterior => ({ ...anterior, citas: { filtros, vista, pagina } }))
-  }, [filtros, vista, pagina, guardarConsulta])
+    guardarConsulta?.(anterior => ({ ...anterior, citas: { filtros, vista, pagina, rango: rangoMes } }))
+  }, [filtros, vista, pagina, rangoMes, guardarConsulta])
   const [detalle, setDetalle] = useState<CitaEjemplo | null>(null)
   const [desglose, setDesglose] = useState<string | null>(null)
   const [leadAbierto, setLeadAbierto] = useState<string | null>(null)
@@ -95,6 +108,8 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
   const paginaActual = Math.min(pagina, paginas)
   const visibles = ordenar(citas, filtros.sort).slice((paginaActual - 1) * POR_PAGINA, paginaActual * POR_PAGINA)
   const [desde, hasta] = rangoConsulta(filtros)
+  // Resultados y Proyección van a todo el ancho, sin la tarjeta de las vistas operativas.
+  const analitica = vista === 'resultados' || vista === 'proyeccion'
   const textoConteo = cargando ? 'Cargando las citas de tu consulta…' : errorCarga ? 'Consulta no disponible. Vuelve a intentarlo.' : error ? 'Revisa los filtros para consultar las citas.' : citas.length + (modoDemo ? ' de ' + CITAS.length + ' citas del ejemplo' : ' citas de tu consulta') + (vista === 'agenda' ? ' · orden cronológico · hora de Lima' : ' · según tus filtros')
 
   useEffect(() => { if (rangoConsulta(filtros)[0]) onMes?.(filtros.mes) }, [filtros, onMes])
@@ -204,15 +219,15 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
             variant="ghost" className={cn('citas-pestana', vista === item.id && 'citas-pestana-activa')} onClick={() => cambiarVista(item.id)}>
             <item.icono aria-hidden />{item.titulo}
           </Button>)}
-        </div><p className="citas-corte">Citas: {fmtFecha(desde)}–{fmtFecha(hasta)}<span>Seguimiento al {corteLima(corte)}</span></p></div>
-        <section className={vista === 'resultados' ? undefined : 'gi-card citas-vista-operativa'} aria-label="Resultados de la consulta">
-          <div className={vista === 'resultados' ? 'sr-only' : 'flex flex-wrap items-center justify-between gap-3 py-4'}>
-            <div><h2 className="text-base font-semibold">{vista === 'agenda' ? 'Agenda por día' : vista === 'resultados' ? 'Resultados por analista' : 'Todas las citas de tu consulta'}</h2>
+        </div><p className="citas-corte">Citas: {vista === 'proyeccion' ? rotuloRango(rangoProyeccion) : `${fmtFecha(desde)}–${fmtFecha(hasta)}`}<span>Seguimiento al {corteLima(corte)}</span></p></div>
+        <section className={analitica ? undefined : 'gi-card citas-vista-operativa'} aria-label="Resultados de la consulta">
+          <div className={analitica ? 'sr-only' : 'flex flex-wrap items-center justify-between gap-3 py-4'}>
+            <div><h2 className="text-base font-semibold">{vista === 'agenda' ? 'Agenda por día' : vista === 'resultados' ? 'Resultados por analista' : vista === 'proyeccion' ? 'Proyección por analista' : 'Todas las citas de tu consulta'}</h2>
               <p className="citas-nota" data-testid="conteo-citas">{textoConteo}</p>
             </div>
             {vista === 'bandeja' && <label className="flex items-center gap-2 whitespace-nowrap text-xs text-muted-foreground-strong">Ordenar por<Select value={filtros.sort} onChange={e => cambiar({ sort: e.target.value })}><option value="prioridad">Pendientes primero</option><option value="fecha">Más antiguas primero</option><option value="reciente">Más recientes primero</option><option value="nombre">Prospecto A–Z</option></Select></label>}
           </div>
-          {vista !== 'resultados' && <div className="flex flex-wrap items-center gap-2 pb-4" role="group" aria-label="Consultas rápidas por estado">
+          {!analitica && <div className="flex flex-wrap items-center gap-2 pb-4" role="group" aria-label="Consultas rápidas por estado">
             <span className="mr-1 text-xs text-muted-foreground-strong">Ver por estado</span>{ATAJOS.map(estado => {
               const seleccionado = estado ? filtros.estados.includes(estado) : !filtros.estados.length
               const cantidad = estado ? sinEstado.filter(cita => cita.estado === estado).length : sinEstado.length
@@ -222,10 +237,11 @@ export function TableroCitas({ conservarConsulta = false }: { conservarConsulta?
             })}
           </div>}
           <div id="citas-panel" role="tabpanel" aria-labelledby={'citas-tab-' + vista} tabIndex={0} className="outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent">
-            {cargando ? <p role="status" className="p-8">Cargando las citas de tu consulta…</p> : errorCarga ? <div role="alert" className="space-y-3 p-8"><p>{errorCarga}</p><Button variant="outline" onClick={onReintentar}>Reintentar</Button></div> : error || (citas.length === 0 && !(vista === 'resultados' && hayBase)) ? <div className="space-y-3 px-4 py-12 text-center">
+            {cargando ? <p role="status" className="p-8">Cargando las citas de tu consulta…</p> : errorCarga ? <div role="alert" className="space-y-3 p-8"><p>{errorCarga}</p><Button variant="outline" onClick={onReintentar}>Reintentar</Button></div> : error || (citas.length === 0 && vista !== 'proyeccion' && !(vista === 'resultados' && hayBase)) ? <div className="space-y-3 px-4 py-12 text-center">
               <SearchX aria-hidden className="mx-auto size-7 text-muted-foreground" /><h3 className="font-semibold">{error ? 'Revisa los filtros de la consulta' : 'No hay citas con esta combinación'}</h3>
               <p className="text-sm text-muted-foreground-strong">{error || 'Quita algún filtro o elige otro período.'}</p><Button variant="outline" onClick={restablecer}>Limpiar filtros</Button>
             </div> : vista === 'bandeja' ? <Bandeja citas={visibles} onDetalle={setDetalle} /> : vista === 'agenda' ? <Agenda citas={citas} onDetalle={setDetalle} />
+              : vista === 'proyeccion' ? <ProyeccionCitas filtros={filtros} rango={rangoProyeccion} onRango={r => setRangoMes({ mes: filtros.mes, ...r })} />
               : <Resultados citas={citas} filtros={filtros} onAnalista={verAnalista} onDesglose={id => { setLeadAbierto(null); setDesglose(id) }} onDetalle={abrirCitaDelRecorrido} leadAbierto={leadAbierto} onLead={setLeadAbierto} />}
           </div>
           {vista === 'bandeja' && !error && !errorCarga && !cargando && citas.length > 0 && <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border py-3">
diff --git a/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts b/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts
index a2c5831d..bce40ffe 100644
--- a/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts
+++ b/CRM-Avance-Corp/app/src/components/gerencia/consulta-context.ts
@@ -7,7 +7,7 @@ export type TipoRankingGerencia = 'conversion' | 'capital-total' | 'cosecha'
 
 export interface ConsultaGerencia {
   alertas?: ConsultaAlertas
-  citas?: { filtros: ConsultaCitas; vista: 'bandeja' | 'agenda' | 'resultados'; pagina: number }
+  citas?: { filtros: ConsultaCitas; vista: 'bandeja' | 'agenda' | 'resultados' | 'proyeccion'; pagina: number; rango?: { mes: string; desde: string; hasta: string } }
   gestionAnalista: { id: string; nombre: string } | null
   administrarMetasPeriodo: string | null
   rendimientoEquipo: string | null
diff --git a/CRM-Avance-Corp/app/src/data/citas-gerencia.ts b/CRM-Avance-Corp/app/src/data/citas-gerencia.ts
index 71378375..6dc953f2 100644
--- a/CRM-Avance-Corp/app/src/data/citas-gerencia.ts
+++ b/CRM-Avance-Corp/app/src/data/citas-gerencia.ts
@@ -28,6 +28,8 @@ const CitaSchema = v.object({
   asistencia_registrada_en: v.nullable(Instante), cierre_posterior: v.boolean(),
   manual_propio: v.optional(v.boolean()),
   registro_manual: v.optional(v.boolean()),
+  // Fase 0 de la Proyección: opcional para leer también al servidor que aún no lo envía.
+  es_cliente: v.optional(v.boolean()),
 })
 const CamposGestion = {
   citas_por_lead: v.pipe(v.number(),v.finite(),v.minValue(0.01),v.maxValue(10)),
@@ -117,6 +119,7 @@ export function adaptarCitas(datos: ConsultaCitasRpc): CitaConLead[] {
     ...(c.asistencia_registrada_en ? {asistioEn:c.asistencia_registrada_en} : {}),
     ...(c.manual_propio !== undefined ? {manualPropio:c.manual_propio} : {}),
     creadoEn:c.creado_en,registroManual:c.registro_manual ?? c.manual_propio ?? false,
+    ...(c.es_cliente !== undefined ? {esCliente:c.es_cliente} : {}),
   }))
 }
 
@@ -190,11 +193,12 @@ export async function cargarCitasGerencia(mes: string, signal?: AbortSignal): Pr
   return resultado.output
 }
 
-export function useCitasGerencia(mes: string, actorId: string | null, habilitada: boolean) {
+/** Opciones de la consulta mensual: las comparten el mes de la pantalla y los meses del rango de Proyección. */
+export function opcionesCitasGerencia(mes: string, actorId: string | null, habilitada: boolean) {
   // Clave por actor/mes y sin placeholderData: nunca presenta otro período.
-  return useQuery({
+  return {
     queryKey:crmQueryKeys.citasGerencia(actorId,mes),
-    queryFn:({signal}) => cargarCitasGerencia(mes,signal),
+    queryFn:({signal}: {signal: AbortSignal}) => cargarCitasGerencia(mes,signal),
     enabled:habilitada && Boolean(actorId) && Boolean(rango(defaults(mes))[0]),
     staleTime:30_000,
     // Incluye cambios de otros analistas y el paso de programada a vencida.
@@ -203,5 +207,34 @@ export function useCitasGerencia(mes: string, actorId: string | null, habilitada
     refetchOnWindowFocus:true,
     refetchOnReconnect:true,
     retry:1,
-  })
+  }
+}
+
+export function useCitasGerencia(mes: string, actorId: string | null, habilitada: boolean) {
+  return useQuery(opcionesCitasGerencia(mes, actorId, habilitada))
+}
+
+const ultimoPorLead = <T,>(listas: T[][], clave: (fila: T) => string) => [...new Map(listas.flat().map(fila => [clave(fila), fila])).values()]
+
+/** Fusiona meses completos (en orden) para un rango que cruza meses. Las citas se
+ * concatenan sin repetir id; población, conversiones y asignaciones se deduplican
+ * por lead (gana el mes más reciente); la configuración es la del último mes. */
+export function fusionarConsultasCitas(consultas: ConsultaCitasRpc[]): { citas: CitaConLead[]; gestion: GestionCitas | undefined; corte: string } {
+  const citas = [...new Map(consultas.flatMap(adaptarCitas).map(c => [c.id, c])).values()]
+  const corte = consultas.map(c => c.generado_en).reduce((a, b) => Date.parse(b) > Date.parse(a) ? b : a, consultas[0]?.generado_en ?? new Date(0).toISOString())
+  const gestiones = consultas.map(adaptarGestion).filter((g): g is GestionCitas => g !== undefined)
+  const ultima = gestiones.at(-1)
+  if (!ultima) return { citas, gestion: undefined, corte }
+  const avances = gestiones.flatMap(g => g.avance ? [g.avance] : [])
+  const gestion: GestionCitas = {
+    ...ultima,
+    asignaciones: ultimoPorLead(gestiones.map(g => g.asignaciones), l => l.leadId),
+    ...(ultima.avance ? { avance: {
+      ...ultima.avance,
+      poblacion: ultimoPorLead(avances.map(a => a.poblacion), p => p.lead_id),
+      conversiones: ultimoPorLead(avances.map(a => a.conversiones), c => c.lead_id),
+      capital: ultimoPorLead(avances.map(a => a.capital), k => k.contrato_id ?? k.cierre_externo_id ?? `${k.lead_id}|${k.fecha}`),
+    } } : {}),
+  }
+  return { citas, gestion, corte }
 }
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx b/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx
index e43da75b..ee2f7c82 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx
@@ -1,11 +1,11 @@
 import { CitasClientes } from '@/components/citas/citas-clientes'
 import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'
-import { useMemo, useState } from 'react'
+import { useCallback, useMemo, useState } from 'react'
 import { usePanelesActions } from '@/lib/store-context'
 import { adaptarDepositos, adaptarGestion } from '@/data/citas-gerencia'
 import { leerHash } from '@/lib/router'
 import { consultaCitasValida, mesConsultaCitas } from '@/lib/enlace-citas'
-import { useDatosCitasGerencia } from './use-datos-citas-gerencia'
+import { useDatosCitasGerencia, useMesesCitasGerencia } from './use-datos-citas-gerencia'
 import { ContextoCitas } from '@/components/citas/contexto'
 import { TableroCitas } from '@/components/citas/propuesta'
 import { mesLima } from '@/components/citas/modelo'
@@ -21,6 +21,10 @@ export function CitasGerencia() {
   })
   const { yo, ahora, datos, citas, consulta } = useDatosCitasGerencia(mes)
   const { abrirLead } = usePanelesActions()
+  // Meses que pide el rango de Proyección (vacío en las otras pestañas).
+  const [mesesProyeccion, setMesesProyeccion] = useState<string[]>([])
+  const pedirMeses = useCallback((meses: string[]) => setMesesProyeccion(actual => actual.join() === meses.join() ? actual : meses), [])
+  const proyeccion = useMesesCitasGerencia(mesesProyeccion)
   const depositos = useMemo(() => datos ? adaptarDepositos(datos) : [],[datos])
   const gestion = useMemo(() => datos ? adaptarGestion(datos) : undefined,[datos])
   const error = consulta.error instanceof Error ? consulta.error.message : 'No se pudieron cargar las citas.'
@@ -32,6 +36,8 @@ export function CitasGerencia() {
     cargando:!yo?.demo && consulta.isPending,error:!yo?.demo && consulta.isError ? error : null,
     onMes:setMes,onReintentar:() => { if (!yo?.demo) void consulta.refetch() },
     onAbrirLead:(id) => { void abrirLead(id) },
+    // En demostración las citas de arriba ya traen todos los meses del ejemplo.
+    onMesesProyeccion:pedirMeses,...(yo?.demo || !mesesProyeccion.length ? {} : {proyeccion}),
   }}>
     <TableroCitas conservarConsulta={yo?.rol === 'gerencia'} />
     <CitasClientes mes={mes} />
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts b/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts
index 214631c8..40377833 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts
+++ b/CRM-Avance-Corp/app/src/screens/hoy/use-datos-citas-gerencia.ts
@@ -1,9 +1,11 @@
 import { useMemo } from 'react'
+import { useQueries, type UseQueryResult } from '@tanstack/react-query'
 import { useAuth } from '@/lib/auth-context'
 import { can } from '@/lib/roles'
 import { useCRMData } from '@/lib/store-context'
 import { useAhora } from '@/lib/ahora'
-import { useCitasGerencia, adaptarCitas, type ConsultaCitasRpc } from '@/data/citas-gerencia'
+import { useCitasGerencia, adaptarCitas, fusionarConsultasCitas, opcionesCitasGerencia, type ConsultaCitasRpc } from '@/data/citas-gerencia'
+import type { DatosProyeccionCitas } from '@/components/citas/contexto'
 import { defaults, rango } from '@/components/citas/modelo'
 
 /** La misma lectura y adaptación para el módulo Citas y el Resumen móvil. */
@@ -40,3 +42,28 @@ export function useDatosCitasGerencia(mes: string) {
   const citas = useMemo(() => datos ? adaptarCitas(datos) : [],[datos])
   return { yo, ahora, datos, citas, consulta, equipo }
 }
+
+// Fuera del componente: una referencia estable evita recombinar en cada render.
+const combinarMeses = (resultados: UseQueryResult<ConsultaCitasRpc>[]) => ({
+  datos: resultados.every(r => r.data) ? resultados.map(r => r.data!) : null,
+  error: resultados.find(r => r.isError)?.error ?? null,
+  reintentar: () => { for (const r of resultados) if (r.isError) void r.refetch() },
+})
+
+/** Meses completos de un rango de Proyección: misma consulta y caché que el mes de
+ * la pantalla. Mientras falte alguno no hay datos (nunca cifras parciales). */
+export function useMesesCitasGerencia(meses: readonly string[]): DatosProyeccionCitas {
+  const { yo } = useAuth()
+  const habilitada = can(yo?.rol, 'verCitasEquipo') && !yo?.demo
+  const estado = useQueries({
+    queries: meses.map(mes => opcionesCitasGerencia(mes, yo?.id ?? null, habilitada)),
+    combine: combinarMeses,
+  })
+  const fusion = useMemo(() => estado.datos ? fusionarConsultasCitas(estado.datos) : null, [estado.datos])
+  return {
+    meses: [...meses], ...(fusion ?? { citas: [], gestion: undefined, corte: '' }),
+    cargando: !fusion && !estado.error,
+    error: estado.error ? (estado.error instanceof Error ? estado.error.message : 'No se pudieron cargar las citas.') : null,
+    onReintentar: estado.reintentar,
+  }
+}
```

## Protocolo de revisión (global)

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


## Formato de respuesta
VERDICT (APPROVE / CHANGES_REQUESTED / REJECT) · SUMMARY · FINDINGS P0–P3 (archivo:línea, evidencia, hipótesis separadas) · RISKS / TEST GAPS · NEXT ACTIONS · CONFIDENCE. Responde en español.
