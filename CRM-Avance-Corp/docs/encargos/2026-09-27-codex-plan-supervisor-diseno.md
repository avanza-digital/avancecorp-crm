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

# Encargo: REFUTAR el plan de rediseño de la pantalla del SUPERVISOR («Mi equipo hoy») — LEVEL 2

Todavía NO hay código: se revisa el PLAN antes de que el dueño (Miguel, no desarrollador) lo
apruebe. Tu trabajo es encontrar lo que el plan rompe, olvida o subestima: funciones en
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

## Reglas vigentes del proyecto que el plan debe respetar
- Presupuesto de color: rojo solo para «requiere intervención hoy» (lo vencido); ámbar para
  «Bajo»/«Atención» (decisión 21/09, blindada por tests); «Bien» en navy sobre fondo tenue; el color
  nunca va solo (texto + forma). Tokens de TEXTO para chips (`--accent-press`, `--destructive-text`,
  `--warning-text`): el color puro sobre su tinte al 12 % no pasa 4.5:1. Nada de la sigla «SLA».
- Los números vienen del servidor en UNA foto autorizada (`gestion_diaria_equipo_fn`); el front
  valida, busca, ordena y presenta; nunca completa con ceros un dato desconocido («desconocido» no es
  «0»; «No evaluado» no es cero cuando `modo_sla !== 'activo'`).
- Accesibilidad: anillo de foco de la casa (`outline-2 outline-offset-2 outline-ring`); `aria-disabled`
  y no `disabled` en un botón que puede tener el foco; tabla semántica con `aria-sort`; anuncios
  `role=status`; contenedores con scroll alcanzables con teclado; objetivos ≥44 px en táctil.
- Gate de realidad: probar también el ESTADO DE PRODUCCIÓN (equipo vacío, sin actividad, sin cortes,
  `modo_sla` no activo, sin permiso 42501), no solo el fixture lleno. E2E SIEMPRE en local con Docker.
- Verificación por fase: `npm run check`, E2E Docker, subagente `revisor-a11y`, review Codex del
  código. Implementar ≠ verificar.
- Lección del analista (27/09): al cambiar la ESTRUCTURA de una pantalla, correr la suite E2E completa
  o buscar sus selectores en TODOS los specs (el rediseño del analista rompió
  `foco-alto-contraste.spec.ts`, que no era de esa pantalla).

## EL PLAN A REVISAR (texto que verá el dueño, más anclas técnicas)

**Objetivo.** Que el supervisor vea en una pantalla limpia quién de su equipo necesita atención hoy
y por qué, y revise a cada analista sin ventanas encima, con el diseño y las piezas del analista.

**S1 · Cabecera, cifras y tabla** (publicable sola)
- Cabecera: «Mi equipo hoy» + subtítulo del diseño; a la derecha fecha larga + «Actualizado HH:MM»
  (`horaLimaDe(dia.generado_en)`), «Seguimiento completo», «Actualizar», «i»; el selector de fecha
  (hasta 365 días) y «Hoy» se conservan compactos junto a la fecha. «Lima · Demo» pasa a la ventana
  «i» (en demo, un chip «Demo»). Se conserva el `aria-label` de la región («Mi equipo hoy» / «Mi
  equipo por fecha») y el h2 enfocable.
- Franja: `FranjaCifras etiqueta="Resumen del equipo"` con las 5 cifras actuales (Analistas, Con
  registro, Sin registro, Con pendientes, Necesitan atención con `tono:'alerta'` si >0). Mientras
  carga o si falla: el mismo texto de hoy («Consultando indicadores…» / «Resumen no disponible»).
- Barra de la tabla: buscador, selector de estado, píldora «Con atención (N)» (`aria-pressed`) y
  «Registro del equipo» (se MUEVE desde la cabecera a la barra, como en el diseño).
- `TablaEquipoDiaria` restilizada: `Avatar` de iniciales + nombre (el botón de selección y la flecha
  «Ir al detalle» se conservan), Llamadas, Contacto (% + chip de nivel con tokens de texto; «N útiles»
  sin nivel; «—» con 0 útiles; el texto sr-only de contexto se conserva), **Citas**
  (`marcador.citas_agendadas`, agendadas hoy; NO `citas_hoy`) en lugar de «Pendientes» (Pendientes
  sigue en la franja y en el panel), Vencidas (rojo si >0), **Atención en palabras**: el motivo de
  mayor prioridad dicho con su número («4 vencidas», «2 fuera de plazo», «Corte pendiente», «Sin
  llamar hace 2 h», «Datos por revisar») + «+N» si hay más; sr-only con la lista completa
  (`MOTIVOS_EQUIPO`). Nuevo `OrdenEquipo` 'citas' (se quita 'pendientes' de la tabla). Pie: «N de N
  analistas · Actualizado HH:MM» (`aria-live=polite`, antes en la barra) y «La actividad registrada
  no acredita presencia.»
- Escala: filas ~52 px, nombre 14 px, cifras 14 px, cabeceras 11–12 px; 44 px en táctil.
- **También cambia, a propósito:** gerencia reutiliza `TablaEquipoDiaria` en su «pulso» del equipo
  (`espacio-pulso-gerencia.tsx:118`): verá la misma tabla nueva (una sola pieza, sin copias). El plan
  de gerencia ya preveía que «dentro del equipo» se vea la vista del supervisor.

**S2 · Panel al lado con quien más atención necesita** (publicable sola, tras S1)
- Umbral del panel en línea: de `clientWidth < 1236` a ~1100 px (a 1440 con el menú abierto la
  pantalla mide ~1150): tabla + panel de ~390 px lado a lado. Por debajo, o con «Ampliar», sigue la
  ventana encima (`PanelSupervisorAdaptable`, sin cambios de mecánica).
- Selección automática: al llegar la foto, si no hay selección y el panel está EN LÍNEA, se elige la
  primera fila del orden por atención SOLO si `requiere_atencion`; sin mover el foco (`enfocar:false`),
  sin anunciarla como acción del usuario, y NUNCA abre la ventana en pantallas estrechas. Si el
  supervisor cierra el panel, no se vuelve a abrir solo en esa sesión de la pantalla. Si nadie
  necesita atención: el panel muestra «Nadie necesita atención ahora. Elige un analista para ver su
  día.»
- Cabecera del panel: iniciales + nombre + «Analista de tu equipo»; se conservan «Ampliar/Restaurar»
  y «Cerrar». Pestañas `Tabs variante="subrayado"` Resumen · Registro · Pendientes (mismas
  pestañas y lógica de `ContenidoSeleccionado`).
- Resumen: aviso rojo suave «N tareas vencidas ›» (abre Pendientes con solo vencidas) y debajo los
  demás motivos en palabras; 4 cuadros 2×2: Llamadas (+ «M contestaron»), Contacto (% + «de N
  llamadas útiles · Nivel» o «Sin muestra: se juzga desde N útiles»), Citas agendadas, **Pendientes**
  (el diseño pone WhatsApp, pero no existe ese conteo por analista en la foto; el cuadro Pendientes
  es botón → pestaña Pendientes); `BarrasPorHora` (con la guarda `horarioConfirmado`: si el desglose
  no cuadra se dice, no se pintan ceros) con «Última llamada HH:MM · hace X»; una línea compacta con
  lo que hoy muestra `DetalleAnalista` y el diseño no dibuja (primera llamada, leads distintos,
  llamadas por lead, tiempo sin llamar, última gestión); «Últimas gestiones» (3, misma consulta de
  25 compartida con Registro) con hora, chip del resultado y nombre del lead (abre la ficha); botón
  azul «Ver el registro del día».
- Nueva pieza `ResumenAnalista` (cuadros + barras + línea compacta) que SUSTITUYE a `DetalleAnalista`
  en el panel del supervisor Y en el pulso de gerencia (`espacio-pulso-gerencia.tsx:168`);
  `DetalleAnalista` y su gráfico propio `gd-grafico-horas` se retiran (sin copias).

**S3 · El resto con el mismo estilo y limpieza**
- Registro (normal, con sus filtros; en el panel NO se usa el modo compacto del analista porque
  perdería el filtro de etapa), Pendientes, «Registro del equipo» (panel en modo equipo), franja y
  ventana «Cortes y avisos» (`FranjaCortesSupervisor`, `AvisosEquipo`, `EstadoCortesEquipo`), ventana
  «i», estados de error/carga/vacío/sin permiso con el estilo nuevo.
- Retirar de `supervisor.css` solo las reglas que ya no use NADIE (gerencia importa ese archivo:
  `gerencia.tsx:22`).

**Qué NO cambia:** base de datos, permisos, consultas y reglas (contacto = contestaron ÷ útiles;
nivel desde el mínimo de útiles; «vencida» y los motivos los decide el servidor); fecha hasta 365
días; el refresco de cada minuto; la ruta `#/gestion-diaria` y el nombre «Mi equipo hoy» (el Hoy del
supervisor enlaza aquí); el Hoy del supervisor de la otra sesión (no se toca `screens/hoy/*`,
`lib/senal-equipo.ts`, `lib/cola-supervision.ts`, `lib/tres-cosas.ts`, ni la API de `Avatar`); la
pantalla del analista; lo que se guarda.

**Decisiones que toma el agente (el dueño puede revertirlas):** Citas en lugar de Pendientes en la
tabla; cuarto cuadro = Pendientes (no WhatsApp); gerencia-dentro-del-equipo usa las mismas piezas;
selección automática solo en línea y solo si alguien necesita atención; se mantiene el vocabulario
del servidor («Primer intento fuera de plazo»).

**Diferidos:** enlace «Ver su día» del Hoy del supervisor que abra al analista directo (requiere
tocar el archivo de esa sesión; el router ya admite `{tipo:'analista', id}`); alinear el vocabulario
de atención entre las dos pantallas.

**Comprobación:** `npm run check`; E2E Docker de `gestion-diaria-equipo`, `-fecha`, `-pulso`
(gerencia), `-pendientes`, `-cortes`, `-horizontal-h5` (inestable por carreras de consultas en
paralelo; comparar con su historial), `gerencia-*`, `equipo`, y búsqueda de selectores cambiados en
todos los specs; `revisor-a11y`; Codex sobre el código; recorrido en demo como SUPERVISOR UNO y en
estado de producción (equipo vacío, sin actividad, sin cortes, `modo_sla` no activo, 42501).

## Preguntas concretas (además de lo que encuentres)
1. ¿Qué función viva se pierde o se esconde (selector de fecha y «Hoy», «Lima · Demo», textos de la
   ventana «i», semántica «Sin muestra», contextos sr-only, `aria-sort`, flecha «Ir al detalle»,
   «La selección está fuera de los filtros», flujo `registroPedido` de avisos que abre el registro de
   un analista, «Cortes del día» en otra fecha)?
2. La selección automática: ¿choca con `fueraDeAmbito`, con el cambio de fecha (que limpia la
   selección), con `registroPedido`, con el `key` que remonta `VistaSupervisor`, con el foco y los
   anuncios, o con el paso en línea ↔ ventana del panel adaptable?
3. Bajar el umbral de 1236 a ~1100: ¿riesgos con `.gd-tabla-scroll`, anchos mínimos de columnas,
   zoom 200 %, 1280 px con menú, y con `panel-gerencia.tsx`, que calcula su propio `estrecho`?
4. Sustituir columnas (Pendientes → Citas) y `DetalleAnalista` → `ResumenAnalista` en GERENCIA: ¿qué
   rompe (tests, e2e `gestion-diaria-pulso`, textos que gerencia usa)? ¿Es mejor una pieza común o
   variantes?
5. «Atención en palabras»: ¿qué motivo mostrar primero y cómo evitar mentir (p. ej., `null` en
   `primer_intento_vencido` cuando `modo_sla` no está activo, cortes solo en la jornada)?
6. ¿Faltan pruebas o estados en el plan?

## CÓDIGO ACTUAL EN `main` (transcrito; numeración real del archivo)

### src/screens/gestion-diaria/supervisor.tsx (242 líneas)
```tsx
   1  import { useEffect, useId, useLayoutEffect, useRef, useState, type JSX, type ReactNode } from 'react'
   2  import { Info, ListFilter, RefreshCw, Search, Users, X } from 'lucide-react'
   3  import { useAlertasCRM } from '@/lib/alertas-context'
   4  import { useAuth } from '@/lib/auth-context'
   5  import { useAhora } from '@/lib/ahora'
   6  import { fechaLima } from '@/lib/agenda-derivada'
   7  import { horaLimaDe } from '@/lib/gestion-diaria-analista'
   8  import { filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo, type OrdenEquipo, type FilaEquipoPresentada, type EstadoEquipo } from '@/lib/gestion-diaria-equipo'
   9  import { useDiaEquipo } from '@/data/gestion-diaria-equipo-queries'
  10  import { CrmApiError } from '@/data/crm-api'
  11  import { TablaEquipoDiaria } from '@/components/gestion-diaria/tabla-equipo-diaria'
  12  import { PanelAnalistaSupervisor, type SeleccionSupervisor } from '@/components/gestion-diaria/panel-analista-supervisor'
  13  import { PanelSupervisorAdaptable } from '@/components/gestion-diaria/panel-supervisor-adaptable'
  14  import { PanelVacio } from '@/components/common/estado-panel'
  15  import { Button } from '@/components/ui/button'
  16  import { Input } from '@/components/ui/input'
  17  import { Select } from '@/components/ui/select'
  18  import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
  19  import { FranjaCortesSupervisor } from '@/components/gestion-diaria/franja-cortes-supervisor'
  20  import { AvisosEquipo } from '@/components/gestion-diaria/avisos-equipo'
  21  import { EstadoCortesEquipo } from '@/components/gestion-diaria/estado-cortes-equipo'
  22  import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
  23  import './supervisor.css'
  24  
  25  const FECHA_JORNADA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })
  26  const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false }
  27  
  28  export function GestionDiariaSupervisor({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode } = {}): JSX.Element {
  29    const { yo } = useAuth()
  30    const hoy = fechaLima(useAhora())
  31    if (yo?.rol !== 'supervisor') return <p role="alert">Esta vista está disponible para supervisores autorizados.</p>
  32    // Desmontar el propietario entero limpia selección y listas antes de pintar
  33    // cualquier cambio de actor, rol, demo o jornada, incluidas respuestas tardías.
  34    return <VistaSupervisor key={JSON.stringify([yo.id, yo.rol, yo.demo, hoy])} hoy={hoy} actor={yo.id} demo={yo.demo} accesoSeguimiento={accesoSeguimiento} />
  35  }
  36  
  37  function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string; actor: string; demo: boolean; accesoSeguimiento?: ReactNode }) {
  38    const [fecha, setFecha] = useState(hoy)
  39    const entradaFecha = useRef<HTMLInputElement>(null)
  40    const consulta = useDiaEquipo(fecha)
  41    const esHoy = fecha === hoy
  42    // Mismo intervalo inclusivo que gestion_diaria_equipo_fn: 365 días Lima.
  43    const primeraFecha = fechaLima(Date.parse(`${hoy}T12:00:00-05:00`) - 365 * 86_400_000)
  44    const avisos = useGestionDiariaAvisos()
  45    const alertas = useAlertasCRM()
  46    const panelId = useId()
  47    const [filtros, setFiltros] = useState(FILTROS_INICIALES)
  48    const [seleccion, setSeleccion] = useState<SeleccionSupervisor | null>(null)
  49    const [anuncio, setAnuncio] = useState('')
  50    const [actualizacion, setActualizacion] = useState(0)
  51    const [ampliado, setAmpliado] = useState(false)
  52    const [estrecho, setEstrecho] = useState(false)
  53    const [auxiliar, setAuxiliar] = useState<'info' | 'avisos' | null>(null)
  54    const [devolverFocoAuxiliar, setDevolverFocoAuxiliar] = useState(true)
  55    const pantalla = useRef<HTMLElement>(null)
  56    const tituloEquipo = useRef<HTMLHeadingElement>(null)
  57    const tituloPanel = useRef<HTMLHeadingElement>(null)
  58    const origen = useRef<HTMLElement | null>(null)
  59    const focoEnPanel = useRef(false)
  60    const apertura = useRef(0)
  61    const dia = consulta.error ? null : consulta.dia
  62    const equipo = dia ? presentarEquipo(dia) : []
  63    const filas = filtrarOrdenarEquipo(equipo, filtros)
  64    const fila = equipo.find((f) => f.analista_id === seleccion?.analista)
  65    const atencion = equipo.filter((f) => f.requiere_atencion).length
  66    const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  67    const fueraDeAmbito = seleccion !== null && (sinPermiso || (dia !== null && seleccion.analista !== null && !fila))
  68    useLayoutEffect(() => {
  69      const nodo = pantalla.current
  70      if (!nodo || typeof ResizeObserver === 'undefined') return
  71      const medir = () => {
  72        const tabla = nodo.querySelector('.gd-tabla-scroll')
  73        const scrollbar = tabla instanceof HTMLElement ? tabla.offsetWidth - tabla.clientWidth : 0
  74        setEstrecho(nodo.clientWidth < 1236 + Math.max(0, scrollbar - 16))
  75      }
  76      const observador = new ResizeObserver(medir)
  77      observador.observe(nodo)
  78      medir()
  79      return () => observador.disconnect()
  80    }, [])
  81    useEffect(() => {
  82      const recordarFoco = (e: FocusEvent) => {
  83        focoEnPanel.current = e.target instanceof Node && Boolean(document.getElementById(panelId)?.contains(e.target))
  84      }
  85      document.addEventListener('focusin', recordarFoco)
  86      return () => document.removeEventListener('focusin', recordarFoco)
  87    }, [panelId])
  88    useLayoutEffect(() => {
  89      if (!fueraDeAmbito) return
  90      const focoDentro = focoEnPanel.current
  91      setSeleccion(null)
  92      setAmpliado(false)
  93      setAnuncio('Se cerró el detalle porque su ámbito ya no está autorizado. Revisa el equipo antes de abrir otro.')
  94      if (focoDentro) tituloEquipo.current?.focus()
  95    }, [fueraDeAmbito, panelId])
  96    useEffect(() => {
  97      const pedido = avisos?.registroPedido
  98      if (!pedido) return
  99      // Un aviso vigente abre su jornada; nunca usa las cifras del día consultado.
 100      if (pedido.actor === actor && pedido.dia === hoy && !esHoy) {
 101        setFecha(hoy)
 102        if (entradaFecha.current) entradaFecha.current.value = hoy
 103        setSeleccion(null)
 104        setAmpliado(false)
 105        setAuxiliar(null)
 106        return
 107      }
 108      if (sinPermiso) {
 109        setAnuncio('El registro solicitado ya no está autorizado.')
 110        avisos?.consumirRegistro()
 111        return
 112      }
 113      if (!dia) return
 114      if (pedido.actor === actor && pedido.dia === hoy && esHoy && dia.equipo.some((f) => f.analista_id === pedido.analista)) {
 115        origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
 116        setSeleccion({ analista: pedido.analista, nombre: dia.equipo.find((f) => f.analista_id === pedido.analista)!.nombre_completo,
 117          pestana: 'llamadas', apertura: ++apertura.current, enfocar: true })
 118        setDevolverFocoAuxiliar(false)
 119        setAuxiliar(null)
 120        setAnuncio('Abierto el registro de llamadas solicitado.')
 121      } else setAnuncio('El registro solicitado ya no corresponde a tu equipo o jornada actuales.')
 122      avisos?.consumirRegistro()
 123    }, [avisos, dia, hoy, fecha, esHoy, actor, sinPermiso])
 124    const cambiarFecha = (valor: string) => {
 125      if (!valor || valor < primeraFecha || valor > hoy) return
 126      if (entradaFecha.current && entradaFecha.current.value !== valor) entradaFecha.current.value = valor
 127      if (valor === fecha) return
 128      setFecha(valor)
 129      setSeleccion(null)
 130      setAmpliado(false)
 131      setAuxiliar(null)
 132      setAnuncio(`Fecha seleccionada: ${FECHA_JORNADA.format(new Date(`${valor}T12:00:00-05:00`))}.`)
 133    }
 134    const abrirLlamadas = (id: string) => {
 135      const persona = dia?.equipo.find((f) => f.analista_id === id)
 136      if (!persona || sinPermiso) return
 137      origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
 138      setSeleccion({ analista: id, nombre: persona.nombre_completo, pestana: 'llamadas', apertura: ++apertura.current, enfocar: true })
 139      setDevolverFocoAuxiliar(false); setAuxiliar(null)
 140      setAnuncio('Abierto el registro de llamadas solicitado.')
 141    }
 142    const seleccionar = (persona: FilaEquipoPresentada) => {
 143      origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
 144      if (seleccion?.analista === persona.analista_id) return
 145      setSeleccion({ analista: persona.analista_id, nombre: persona.nombre_completo, pestana: 'todo', apertura: ++apertura.current, enfocar: false })
 146      setAnuncio(`Seleccionado ${persona.nombre_completo}. Detalle disponible.`)
 147    }
 148    const cerrar = () => {
 149      setSeleccion(null); setAmpliado(false)
 150      requestAnimationFrame(() => {
 151        if (origen.current?.isConnected && origen.current.getClientRects().length) origen.current.focus({ preventScroll: true })
 152        else tituloEquipo.current?.focus({ preventScroll: true })
 153      })
 154    }
 155    const ordenar = (orden: OrdenEquipo) => setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : orden === 'nombre' }))
 156    const modal = seleccion !== null && !fueraDeAmbito && (estrecho || ampliado)
 157    return (
 158      <section ref={pantalla} aria-label={esHoy ? 'Mi equipo hoy' : 'Mi equipo por fecha'} className="gd-supervisor" data-estrecho={estrecho}>
 159        <header className="gd-cabecera">
 160          <h2 ref={tituloEquipo} tabIndex={-1}>{esHoy ? 'Mi equipo hoy' : 'Mi equipo'}</h2>
 161          <div className="gd-selector-fecha">
 162            <label><span className="sr-only">Fecha de gestión</span>
 163              <Input ref={entradaFecha} type="date" defaultValue={hoy} min={primeraFecha} max={hoy} className="min-h-11 text-base"
 164                onChange={(e) => {
 165                  // El campo nativo conserva la escritura por segmentos. Volver a
 166                  // asignar value en cada tecla reinicia el año en Chromium.
 167                  if (e.currentTarget.validity.valid) cambiarFecha(e.currentTarget.value)
 168                }} onBlur={(e) => { e.currentTarget.value = fecha }} />
 169            </label>
 170            <Button variant="outline" className="min-h-11 text-base" disabled={esHoy} onClick={() => cambiarFecha(hoy)}>Hoy</Button>
 171            <span className="gd-fecha">Lima{demo ? ' · Demo' : ''}</span>
 172          </div>
 173          <div className="gd-acciones-cabecera">
 174            {accesoSeguimiento}
 175            <Button variant="ghost" className="min-h-11 text-base" disabled={!dia || sinPermiso} onClick={() => {
 176              origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
 177              setSeleccion({ analista: null, nombre: null, pestana: 'todo', apertura: ++apertura.current, enfocar: true })
 178            }}>Registro del equipo</Button>
 179            <Button variant="outline" className="min-h-11 text-base" disabled={consulta.enVuelo || alertas.cargando} onClick={() => { void consulta.recargar(); alertas.reintentar(); setActualizacion((n) => n + 1) }}>
 180              <RefreshCw className="size-4" aria-hidden />{consulta.enVuelo || alertas.cargando ? 'Actualizando…' : 'Actualizar'}
 181            </Button>
 182            <Button variant="ghost" size="icon" className="size-11" aria-label="Información de esta vista" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('info') }}><Info aria-hidden /></Button>
 183          </div>
 184        </header>
 185        <div role="group" aria-label="Resumen del equipo" className="gd-indicadores">
 186          {dia ? <dl>{[
 187            ['Analistas', dia.resumen.analistas], ['Con registro', dia.resumen.con_actividad], ['Sin registro', dia.resumen.sin_actividad],
 188            ['Con pendientes', dia.resumen.con_pendientes], ['Necesitan atención', atencion],
 189          ].map(([etiqueta, valor]) => <div key={etiqueta}><dt>{etiqueta}</dt><dd>{valor}</dd></div>)}</dl>
 190            : <p>{consulta.error ? 'Resumen no disponible' : 'Consultando indicadores…'}</p>}
 191        </div>
 192        <div className="gd-espacio">
 193          <div className="gd-equipo">
 194            {consulta.error ? <div role="alert" className="gd-estado">
 195              <h3 className="font-semibold">{sinPermiso ? 'Ya no tienes autorización para ver este equipo' : 'No pudimos consultar la actividad y los pendientes del equipo'}</h3>
 196              <p>{sinPermiso ? 'Revisa tu acceso con gerencia. No se muestran los datos anteriores.' : 'Los datos no están disponibles; esto no significa que el equipo no tenga actividad o pendientes.'}</p>
 197              {!sinPermiso && <Button className="min-h-11 text-base" disabled={consulta.enVuelo} onClick={() => { void consulta.recargar() }}>Reintentar</Button>}
 198            </div> : consulta.cargando || !dia ? <p role="status" aria-busy="true" className="gd-estado">Consultando el equipo completo…</p>
 199              : dia.equipo.length === 0 ? <PanelVacio icono={Users} tamano="grande" titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
 200                : <>
 201                  <div className="gd-filtros">
 202                    <label className="gd-busqueda"><span className="sr-only">Buscar analista</span><Search aria-hidden />
 203                      <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista" className="min-h-11 pl-9 text-base" /></label>
 204                    <Select aria-label="Estado de actividad" value={filtros.estado} onChange={(e) => setFiltros((f) => ({ ...f, estado: e.target.value as EstadoEquipo }))} className="min-h-11 text-base">
 205                      <option value="todos">Todos</option><option value="con_registro">Con registro</option><option value="sin_registro">Sin registro</option><option value="con_pendientes">Con pendientes</option>
 206                    </Select>
 207                    <Button variant={filtros.soloProblemas ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={filtros.soloProblemas} onClick={() => setFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}><ListFilter aria-hidden />Con atención ({atencion})</Button>
 208                    <p aria-live="polite" className="gd-conteo">{filas.length} de {dia.resumen.analistas}</p>
 209                  </div>
 210                  <TablaEquipoDiaria filas={filas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null} seleccionar={seleccionar}
 211                    panelId={panelId} minimo={dia.umbrales.minimo_llamadas_utiles} irAlDetalle={() => tituloPanel.current?.focus({ preventScroll: true })} />
 212                </>}
 213          </div>
 214          <PanelSupervisorAdaptable modal={modal} cerrar={cerrar} tituloRef={tituloPanel}>
 215            <PanelAnalistaSupervisor key={fecha} id={panelId} seleccion={fueraDeAmbito ? null : seleccion} fila={fila} dia={fecha} minimo={dia?.umbrales.minimo_llamadas_utiles} tituloRef={tituloPanel}
 216              ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => setAmpliado((v) => !v)} cerrar={cerrar} oculta={Boolean(dia && seleccion?.analista && !filas.some((f) => f.analista_id === seleccion.analista))}
 217              limpiar={() => setFiltros(FILTROS_INICIALES)} actualizacion={actualizacion} revalidar={() => { void consulta.recargar() }} />
 218          </PanelSupervisorAdaptable>
 219        </div>
 220        {esHoy ? <FranjaCortesSupervisor consulta={consulta} abrir={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }} />
 221          : <section className="gd-cortes" aria-label="Consulta de otra fecha">
 222            <Button variant="ghost" className="min-h-11 shrink-0 text-base" aria-haspopup="dialog" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }}>Cortes del día</Button>
 223            <p className="gd-cortes-resumen">Actividad del día elegido. El equipo y los pendientes reflejan su estado actual.</p>
 224          </section>}
 225        <p className="sr-only" role="status">{anuncio}</p>
 226        <Dialog focoAlCerrar={devolverFocoAuxiliar ? undefined : tituloPanel} open={auxiliar !== null} onClose={() => setAuxiliar(null)} className={auxiliar === 'info' ? 'gd-dialogo-info' : 'gd-dialogo-avisos'}>
 227          <DialogHeader className="flex-row items-center justify-between"><DialogTitle className="text-base">{auxiliar === 'info' ? 'Información de esta vista' : esHoy ? 'Cortes de llamadas y otros avisos' : 'Cortes del día seleccionado'}</DialogTitle>
 228            <Button variant="ghost" size="icon" className="size-11 shrink-0" aria-label={auxiliar === 'info' ? 'Cerrar información' : 'Cerrar avisos'} onClick={() => setAuxiliar(null)}><X aria-hidden /></Button></DialogHeader>
 229          <DialogBody className="space-y-3 text-base">{auxiliar === 'info' ? <>
 230            <p>{fecha} · Hora de Lima. {dia ? `Datos consultados a las ${horaLimaDe(dia.generado_en)}.` : 'Sin datos confirmados.'} Actualización cada minuto.</p>
 231            <p>Puedes consultar desde hoy hasta 365 días atrás. Las llamadas y el registro corresponden a la fecha elegida; el equipo y los pendientes reflejan su estado actual.</p>
 232            <p>Los indicadores cuentan personas del equipo completo, incluso cuando filtras la tabla.</p>
 233            <p>La tasa usa llamadas útiles; número errado y otra persona quedan fuera. Se califica desde {dia?.umbrales.minimo_llamadas_utiles ?? 'el mínimo vigente de'} llamadas útiles.</p>
 234            <p>Los pendientes reflejan su estado actual. La actividad registrada no acredita presencia ni explica una ausencia. Los cortes conservan su foto de llamadas y solo avisan durante la jornada.</p>
 235            {dia?.modo_sla !== 'activo' && <p>Los primeros intentos fuera de plazo no se evalúan con el control actual. «No evaluado» no significa cero.</p>}
 236          </> : auxiliar === 'avisos' ? esHoy
 237            ? <AvisosEquipo consulta={consulta} abrirAnalista={abrirLlamadas} alNavegar={() => { setAuxiliar(null); setSeleccion(null); setAmpliado(false) }} />
 238            : <EstadoCortesEquipo consulta={consulta} abrirAnalista={abrirLlamadas} /> : null}</DialogBody>
 239        </Dialog>
 240      </section>
 241    )
 242  }
```

### src/screens/gestion-diaria/supervisor.css (122 líneas)
```css
   1  /* Shell vigente: Topbar64 + padding vertical48 =112px (AreaConsultaGerencia).
   2   * E2E comprueba scroll de página al cambiar el shell. Presupuesto H1: 44 + 8 + 44 + 8 + cuerpo + 8 + 44. Sólo el cuerpo desplaza. */
   3  .gd-supervisor { container-type:inline-size; display:flex; flex-direction:column; gap:8px; width:100%; max-width:1440px; height:calc(100svh - 112px); min-height:520px; margin-inline:auto; font-size:16px; line-height:1.375; color:var(--foreground); }
   4  .gd-cabecera { display:flex; align-items:center; gap:16px; min-height:44px; flex-shrink:0; }
   5  .gd-cabecera h2 { font-size:24px; font-weight:750; letter-spacing:-.035em; color:var(--primary); }
   6  .gd-fecha { color:var(--muted-foreground-strong); }
   7  .gd-selector-fecha { display:flex; align-items:center; gap:8px; }
   8  .gd-selector-fecha input { width:168px; }
   9  .gd-acciones-cabecera { margin-left:auto; display:flex; align-items:center; gap:8px; }
  10  .gd-indicadores { flex-shrink:0; border-radius:10px; background:var(--card); box-shadow:inset 0 0 0 1px var(--border); }
  11  .gd-indicadores dl { display:grid; grid-template-columns:repeat(5,1fr); min-height:44px; }
  12  .gd-indicadores dl>div { display:flex; align-items:center; justify-content:space-between; gap:8px; padding:8px 16px; border-right:1px solid var(--border); }
  13  .gd-indicadores dl>div:last-child { border:0; }
  14  .gd-indicadores dt { color:var(--muted-foreground-strong); }
  15  .gd-indicadores dd { font-weight:750; font-variant-numeric:tabular-nums; color:var(--primary); font-size:20px; line-height:28px; }
  16  .gd-indicadores>p { padding:11px 16px; }
  17  .gd-espacio { display:grid; grid-template-columns:minmax(840px,1fr) clamp(380px,30%,414px); gap:16px; flex:1; min-height:0; }
  18  .gd-equipo { container-type:inline-size; display:flex; flex-direction:column; min-width:0; min-height:0; background:var(--card); border-radius:10px; box-shadow:inset 0 0 0 1px var(--border); overflow:hidden; }
  19  .gd-filtros { display:flex; align-items:center; gap:8px; min-height:52px; padding:4px 8px; flex-shrink:0; }
  20  .gd-busqueda { position:relative; flex:1; min-width:160px; max-width:280px; }
  21  .gd-busqueda>svg { position:absolute; left:10px; top:13px; width:18px; height:18px; pointer-events:none; color:var(--muted-foreground); }
  22  .gd-filtros>div:has(select) { width:174px; flex-shrink:0; }
  23  .gd-conteo { margin-left:auto; white-space:nowrap; color:var(--muted-foreground-strong); }
  24  .gd-tabla-scroll { flex:1; min-height:0; overflow:auto; scrollbar-gutter:stable; }
  25  .gd-tabla { width:100%; table-layout:fixed; border-spacing:0; border-collapse:separate; font-size:16px; }
  26  .gd-col-nombre { width:auto; }.gd-col-llamadas { width:104px; }.gd-col-contacto { width:132px; }.gd-col-pendientes { width:120px; }.gd-col-vencidas { width:104px; }.gd-col-atencion { width:160px; }
  27  .gd-tabla thead { position:sticky; top:0; z-index:1; background:var(--muted); }
  28  .gd-tabla th,.gd-tabla td { padding:0 8px; text-align:left; vertical-align:middle; height:44px; font-variant-numeric:tabular-nums; box-shadow:inset 0 -1px var(--border); overflow-wrap:anywhere; }
  29  .gd-tabla thead button { display:flex; align-items:center; gap:4px; min-height:44px; width:100%; font-weight:600; cursor:pointer; white-space:nowrap; }
  30  .gd-tabla thead svg { width:14px; height:14px; flex-shrink:0; }
  31  .gd-tabla .gd-nombre { font-weight:600; color:var(--primary); }
  32  .gd-nombre>div { display:flex; align-items:center; }
  33  .gd-nombre button { min-height:44px; min-width:0; text-align:left; overflow-wrap:anywhere; cursor:pointer; flex:1; }
  34  .gd-nombre .gd-ir-detalle { flex:0 0 44px; display:grid; place-items:center; }
  35  .gd-ir-detalle svg { width:18px; height:18px; }
  36  .gd-tabla [data-activa=true] { background:color-mix(in srgb,var(--accent) 9%,var(--card)); }
  37  .gd-tabla [data-activa=true] .gd-nombre { box-shadow:inset 3px 0 var(--accent),inset 0 -1px var(--border); }
  38  .gd-tabla button:focus-visible,.gd-panel :focus-visible,.gd-cabecera h2:focus-visible { outline:2px solid var(--accent); outline-offset:-2px; border-radius:4px; }
  39  .gd-motivos { color:var(--warning-text); font-weight:600; }
  40  .gd-tabla .gd-sin-filas { padding:24px; }
  41  .gd-estado { padding:24px; display:flex; flex-direction:column; gap:16px; align-items:start; }
  42  .gd-panel-alojamiento,.gd-panel-host { min-width:0; min-height:0; height:100%; }
  43  .gd-panel-host { display:flex; flex-direction:column; }
  44  .gd-panel { display:flex; flex:1; flex-direction:column; min-height:0; min-width:0; border-radius:10px; background:var(--card); box-shadow:inset 0 0 0 1px var(--border); font-size:16px; line-height:1.375; overflow:hidden; }
  45  .gd-panel-cabecera { display:flex; align-items:center; gap:8px; padding:8px 12px; flex-shrink:0; border-bottom:1px solid var(--border); }
  46  .gd-panel-cabecera h3 { flex:1; min-width:0; overflow-wrap:anywhere; font-size:18px; line-height:1.35; font-weight:700; color:var(--primary); }
  47  .gd-panel-inicial { display:flex; flex:1; flex-direction:column; align-items:center; justify-content:center; text-align:center; padding:32px; gap:16px; color:var(--muted-foreground-strong); }
  48  .gd-pestanas-panel { display:flex; flex:1; flex-direction:column; min-height:0; gap:0; }
  49  .gd-pestanas-panel>[role=tablist] { width:100%; border-radius:0; display:flex; flex-direction:row; margin:0; flex-shrink:0; background:transparent; padding:4px 8px; }
  50  .gd-pestanas-panel>[role=tablist]>button { flex:1; min-height:44px; padding:8px; font-size:16px; }
  51  .gd-pestanas-panel>[role=tabpanel] { display:flex; flex:1; min-height:0; margin:0; }
  52  .gd-panel-cuerpo { container-type:inline-size; min-width:0; flex:1; overflow:auto; padding:16px; overflow-wrap:anywhere; }
  53  .gd-panel-cuerpo[hidden],.gd-panel-alojamiento[hidden] { display:none; }
  54  .gd-resumen-principal { display:flex; gap:12px; align-items:baseline; color:var(--primary); }
  55  .gd-resumen-principal strong { font-size:36px; font-weight:750; line-height:1.2; }
  56  .gd-atencion-detalle { margin-top:12px; padding:12px; border-radius:8px; background:color-mix(in srgb,var(--warning) 10%,var(--card)); color:var(--warning-text); }
  57  .gd-seleccion-oculta { padding:8px 12px; background:var(--muted); flex-shrink:0; }
  58  .gd-cortes { display:flex; align-items:center; justify-content:space-between; gap:8px; min-height:44px; flex-shrink:0; border-radius:10px; background:var(--card); box-shadow:inset 0 0 0 1px var(--border); }
  59  .gd-cortes-resumen { display:flex; flex:1; flex-wrap:wrap; align-items:center; gap:2px 16px; min-width:0; }
  60  .gd-cortes-resumen>span { overflow-wrap:anywhere; }
  61  .gd-cortes-resumen strong { color:var(--warning-text); font-weight:600; }
  62  .gd-cortes-consulta { color:var(--muted-foreground-strong); padding-right:12px; white-space:nowrap; }
  63  .gd-resultado-corte { border:1px solid var(--border); border-radius:8px; }
  64  .gd-resultado-corte summary { cursor:pointer; min-height:44px; padding:10px 12px; display:flex; flex-wrap:wrap; align-items:center; gap:4px 16px; list-style:none; }
  65  .gd-resultado-corte summary::-webkit-details-marker { display:none; }
  66  .gd-corte-indicador { width:16px; height:20px; flex-shrink:0; }
  67  .gd-resultado-corte[open] .gd-corte-indicador { transform:rotate(90deg); }
  68  .gd-resultado-corte summary:focus-visible { outline:2px solid var(--accent); outline-offset:-2px; }
  69  .gd-persona-corte { display:flex; flex-wrap:wrap; align-items:center; justify-content:space-between; gap:12px; padding-block:12px; overflow-wrap:anywhere; }
  70  .gd-persona-corte>div { flex:1 1 240px; min-width:0; }
  71  .gd-persona-corte>button { flex:0 1 auto; max-width:100%; }
  72  .gd-panel-modal { position:fixed; z-index:50; left:50%; top:50%; transform:translate(-50%,-50%); width:min(1200px,calc(100vw - 48px)); height:calc(100svh - 48px); display:flex; flex-direction:column; border-radius:12px; background:var(--card); box-shadow:var(--shadow-pop); outline:none; }
  73  .gd-panel-modal>.gd-panel-host { flex:1; }
  74  .gd-dialogo-info { width:480px; max-height:70svh; }.gd-dialogo-avisos { width:960px; max-height:calc(100svh - 48px); }
  75  .gd-metricas-detalle { display:grid; gap:12px 16px; padding-block:12px; grid-template-columns:repeat(auto-fit,minmax(min(140px,100%),1fr)); }
  76  .gd-grafico-horas { display:grid; grid-template-columns:repeat(13,minmax(0,1fr)); gap:4px; }
  77  .gd-cifras-horas summary { display:flex; align-items:center; cursor:pointer; min-height:44px; text-decoration:underline; }
  78  .gd-cifras-horas li { padding-block:6px; }
  79  @container (max-width:1235px) {
  80    .gd-cabecera { flex-wrap:wrap; gap:8px 16px; }
  81    .gd-acciones-cabecera { flex-wrap:wrap; }
  82    .gd-indicadores dl { grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); }
  83    .gd-espacio { grid-template-columns:minmax(0,1fr); }
  84    .gd-panel-alojamiento { display:none; }
  85  }
  86  .gd-supervisor[data-estrecho=true] .gd-espacio { grid-template-columns:minmax(0,1fr); }
  87  .gd-supervisor[data-estrecho=true] .gd-panel-alojamiento { display:none; }
  88  @container (max-width:839px) {
  89    .gd-filtros { flex-wrap:wrap; padding:8px; }
  90    .gd-busqueda { max-width:none; }
  91    .gd-tabla-scroll { scrollbar-gutter:auto; }
  92    .gd-tabla colgroup { display:none; }
  93    .gd-tabla thead { display:block; position:static; }
  94    .gd-tabla thead tr { display:flex; flex-wrap:wrap; }
  95    .gd-tabla thead th { height:auto; box-shadow:none; }
  96    .gd-tabla tbody { display:block; }
  97    .gd-tabla tbody tr { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); padding:8px; border-bottom:1px solid var(--border); }
  98    .gd-tabla tbody th { grid-column:1/-1; }
  99    .gd-tabla tbody td,.gd-tabla tbody th { height:auto; min-height:44px; box-shadow:none; padding:4px 8px; }
 100    .gd-tabla tbody td::before { content:attr(data-etiqueta); display:block; color:var(--muted-foreground-strong); font-size:16px; margin-bottom:4px; }
 101    .gd-tabla [data-activa=true] .gd-nombre { box-shadow:none; }
 102    .gd-cortes { flex-wrap:wrap; }
 103    .gd-cortes-resumen { flex-basis:100%; padding:0 12px; }
 104    .gd-cortes-consulta { padding:0 12px 8px; }
 105  }
 106  @media (max-height:650px), (max-width:900px) {
 107    .gd-supervisor { height:auto; min-height:0; }
 108    .gd-espacio { min-height:400px; }
 109    .gd-tabla-scroll { max-height:65svh; }
 110    .gd-panel-alojamiento { min-height:400px; }
 111  }
 112  @media (max-width:639px) {
 113    .gd-panel-modal { width:calc(100vw - 32px); height:calc(100svh - 32px); }
 114    .gd-acciones-cabecera { margin-left:0; }
 115    .gd-panel-cabecera { align-items:start; }
 116  }
 117  @media (forced-colors:active) {
 118    .gd-tabla [data-activa=true] .gd-nombre { border-left:3px solid Highlight; }
 119    .gd-tabla th,.gd-tabla td { border-bottom:1px solid CanvasText; }
 120  }
 121  
 122  .gd-nivel-contacto { display:block; font-size:16px; line-height:20px; }
```

### src/components/gestion-diaria/tabla-equipo-diaria.tsx (62 líneas)
```tsx
   1  import { ArrowDown, ArrowUp, ArrowRight } from 'lucide-react'
   2  import { COLOR_NIVEL, ETIQUETA_NIVEL, textoTasa } from '@/lib/gestion-diaria-analista'
   3  import { MOTIVOS_EQUIPO, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
   4  
   5  const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
   6    { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
   7    { orden: 'contacto', titulo: 'Contacto' }, { orden: 'pendientes', titulo: 'Pendientes' },
   8    { orden: 'vencidas', titulo: 'Vencidas' }, { orden: 'atencion', titulo: 'Atención' },
   9  ]
  10  
  11  /** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. */
  12  export function TablaEquipoDiaria({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: {
  13    filas: readonly FilaEquipoPresentada[]
  14    filtros: FiltrosEquipo
  15    ordenar: (orden: OrdenEquipo) => void
  16    seleccion: string | null
  17    seleccionar: (fila: FilaEquipoPresentada) => void
  18    panelId: string
  19    irAlDetalle: () => void
  20    minimo: number
  21  }) {
  22    return (
  23      <div className="gd-tabla-scroll ac-scroll">
  24        <table aria-label="Actividad y pendientes por analista" className="gd-tabla">
  25          <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={`gd-col-${c.orden}`} />)}</colgroup>
  26          <thead><tr>{COLUMNAS.map((c) => (
  27            <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}>
  28              <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}>
  29                {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />)}
  30              </button>
  31            </th>
  32          ))}</tr></thead>
  33          <tbody>
  34            {filas.length === 0 && <tr><td colSpan={6} className="gd-sin-filas">Ningún analista coincide con estos filtros.</td></tr>}
  35            {filas.map((f) => {
  36              const activa = f.analista_id === seleccion
  37              const sinMuestra = f.marcador.nivel === null
  38              const contacto = f.marcador.utiles === 0 ? '—' : sinMuestra ? 'Sin muestra' : `${f.marcador.tasa_contacto_pct} %`
  39              const contextoContacto = f.marcador.utiles === 0 ? 'Sin llamadas útiles' : `${textoTasa(f.marcador)}; ${f.marcador.contestadas} de ${f.marcador.utiles} útiles; mínimo ${minimo}${sinMuestra ? '; sin muestra suficiente' : `; nivel ${ETIQUETA_NIVEL[f.marcador.nivel!]}`}`
  40              return (
  41                <tr key={f.analista_id} data-analista={f.analista_id} data-activa={activa}>
  42                  <th scope="row" className="gd-nombre"><div>
  43                    <button type="button" aria-label={`Seleccionar a ${f.nombre_completo}`} aria-current={activa ? 'true' : undefined}
  44                      aria-controls={panelId} onClick={() => seleccionar(f)}>{f.nombre_completo}</button>
  45                    {activa && <button type="button" className="gd-ir-detalle" aria-label={`Ir al detalle de ${f.nombre_completo}`} onClick={irAlDetalle}><ArrowRight aria-hidden /></button>}
  46                  </div></th>
  47                  <td data-etiqueta="Llamadas">{f.marcador.llamadas}</td>
  48                  <td data-etiqueta="Contacto"><span style={f.marcador.nivel ? { color: COLOR_NIVEL[f.marcador.nivel] } : undefined}><span aria-hidden>{contacto}{f.marcador.nivel && <span className="gd-nivel-contacto">{ETIQUETA_NIVEL[f.marcador.nivel]}</span>}</span><span className="sr-only">{contextoContacto}</span></span></td>
  49                  <td data-etiqueta="Pendientes">{f.tareas_pendientes}</td>
  50                  <td data-etiqueta="Vencidas"><span className={f.tareas_vencidas > 0 ? 'text-[var(--danger-text)] font-semibold' : ''}>{f.tareas_vencidas}</span></td>
  51                  <td data-etiqueta="Atención"><span className={f.requiere_atencion ? 'gd-motivos' : 'text-[var(--muted-foreground-strong)]'}>
  52                    {f.motivos_atencion.length ? `${f.motivos_atencion.length} ${f.motivos_atencion.length === 1 ? 'motivo' : 'motivos'}` : f.gestiones_hoy === 0 ? 'Sin registro' : 'Sin alertas'}
  53                    {f.motivos_atencion.length > 0 && <span className="sr-only">: {f.motivos_atencion.map((m) => MOTIVOS_EQUIPO[m]).join('; ')}</span>}
  54                  </span></td>
  55                </tr>
  56              )
  57            })}
  58          </tbody>
  59        </table>
  60      </div>
  61    )
  62  }
```

### src/components/gestion-diaria/panel-analista-supervisor.tsx (115 líneas)
```tsx
   1  import { useLayoutEffect, useRef, useState, type RefObject } from 'react'
   2  import { Title as TituloDialogo } from '@radix-ui/react-dialog'
   3  import { Maximize2, Minimize2, X, Users } from 'lucide-react'
   4  import { Button } from '@/components/ui/button'
   5  import { Tabs } from '@/components/ui/tabs'
   6  import { DetalleAnalista } from './detalle-analista'
   7  import { RegistroActividad } from './registro-actividad'
   8  import { PendientesSupervisor } from './pendientes-supervisor'
   9  import { UltimasGestionesSupervisor } from './ultimas-gestiones-supervisor'
  10  import { MOTIVOS_EQUIPO, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
  11  import type { PestanaRegistro } from '@/lib/gestion-diaria'
  12  import { textoTasa } from '@/lib/gestion-diaria-analista'
  13  
  14  export interface SeleccionSupervisor { analista: string | null; nombre: string | null; apertura: number; pestana: PestanaRegistro; enfocar: boolean }
  15  type PestanaPanel = 'resumen' | 'registro' | 'pendientes'
  16  
  17  export function PanelAnalistaSupervisor({ id, seleccion, fila, dia, minimo, tituloRef, ampliado, ampliar, cerrar, puedeAmpliar, oculta, limpiar, actualizacion, revalidar }: {
  18    id: string
  19    seleccion: SeleccionSupervisor | null
  20    fila: FilaEquipoPresentada | undefined
  21    dia: string
  22    minimo: number | undefined
  23    tituloRef: RefObject<HTMLHeadingElement | null>
  24    ampliado: boolean
  25    puedeAmpliar: boolean
  26    ampliar: () => void
  27    cerrar: () => void
  28    oculta: boolean
  29    limpiar: () => void
  30    actualizacion: number
  31    revalidar: () => void
  32  }) {
  33    const titulo = seleccion ? seleccion.analista === null ? 'Registro del equipo' : `Detalle de ${fila?.nombre_completo ?? seleccion.nombre}` : 'Detalle del analista'
  34    return (
  35      <section id={id} aria-label={titulo} className="gd-panel">
  36        <header className="gd-panel-cabecera">
  37          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1}>{titulo}</h3></TituloDialogo>
  38          {seleccion && <div className="flex shrink-0">
  39            {puedeAmpliar && <Button variant="ghost" size="icon" className="size-11" aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden /> : <Maximize2 aria-hidden />}</Button>}
  40            <Button variant="ghost" size="icon" className="size-11" aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden /></Button>
  41          </div>}
  42        </header>
  43        {!seleccion ? <div className="gd-panel-inicial"><Users className="size-10 text-muted-foreground" aria-hidden /><p>Selecciona un analista de la tabla para consultar su día.</p></div>
  44          : <ContenidoSeleccionado key={`${seleccion.analista ?? 'equipo'}:${seleccion.apertura}`} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo}
  45            tituloRef={tituloRef} oculta={oculta} limpiar={limpiar} actualizacion={actualizacion} revalidar={revalidar} />}
  46      </section>
  47    )
  48  }
  49  
  50  function ContenidoSeleccionado({ seleccion, fila, dia, minimo, tituloRef, oculta, limpiar, actualizacion, revalidar }: Pick<Parameters<typeof PanelAnalistaSupervisor>[0], 'seleccion' | 'fila' | 'dia' | 'minimo' | 'tituloRef' | 'oculta' | 'limpiar' | 'actualizacion' | 'revalidar'> & { seleccion: SeleccionSupervisor }) {
  51    const equipo = seleccion.analista === null
  52    const [pestana, setPestana] = useState<PestanaPanel>(equipo || seleccion.enfocar ? 'registro' : 'resumen')
  53    const [registro, setRegistro] = useState<{ pestana: PestanaRegistro; apertura: number } | null>(equipo || seleccion.enfocar ? { pestana: seleccion.pestana, apertura: 0 } : null)
  54    const [pendientes, setPendientes] = useState<{ soloVencidas: boolean; apertura: number; enfocar: boolean } | null>(null)
  55    const tituloRegistro = useRef<HTMLHeadingElement>(null)
  56    const [focoRegistro, setFocoRegistro] = useState(0)
  57    useLayoutEffect(() => {
  58      if (seleccion.enfocar) tituloRef.current?.focus({ preventScroll: true })
  59    }, [seleccion.enfocar, tituloRef])
  60    useLayoutEffect(() => {
  61      if (focoRegistro) tituloRegistro.current?.focus({ preventScroll: true })
  62    }, [focoRegistro])
  63    const cambiar = (valor: PestanaPanel) => {
  64      setPestana(valor)
  65      if (valor === 'registro' && !registro) setRegistro({ pestana: 'todo', apertura: 0 })
  66      if (valor === 'pendientes' && !pendientes) setPendientes({ soloVencidas: false, apertura: 0, enfocar: false })
  67    }
  68    const abrirRegistro = (inicial: PestanaRegistro) => {
  69      setRegistro((r) => ({ pestana: inicial, apertura: (r?.apertura ?? 0) + 1 }))
  70      setPestana('registro')
  71      setFocoRegistro((n) => n + 1)
  72    }
  73    const abrirPendientes = (soloVencidas: boolean) => {
  74      setPendientes(p => ({ soloVencidas, apertura: (p?.apertura ?? 0) + 1, enfocar: true }))
  75      setPestana('pendientes')
  76    }
  77    const contenido = <>
  78      <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
  79        {!fila ? <p role="status">El resumen no está disponible. El registro conserva su consulta independiente.</p> : <>
  80          <div className="gd-resumen-principal"><strong>{fila.marcador.llamadas}</strong><span>Llamadas registradas</span></div>
  81          <p className="mb-3 text-[var(--muted-foreground-strong)]">{fila.gestiones_hoy} gestiones · {dia} · Lima</p>
  82          <p><strong>Contacto: {textoTasa(fila.marcador)}</strong> · {fila.marcador.contestadas} de {fila.marcador.utiles} llamadas útiles. {fila.marcador.utiles === 0 ? 'Sin llamadas útiles.' : fila.marcador.nivel === null ? 'Sin muestra suficiente.' : ''} Mínimo: {minimo ?? 'no disponible'}.</p>
  83          <p className="mt-2 text-[var(--muted-foreground-strong)]">Número errado y otra persona quedan fuera del contacto útil.</p>
  84          {fila.motivos_atencion.length > 0 && <div className="gd-atencion-detalle"><h4 className="font-semibold">Necesita atención</h4><ul className="list-disc pl-5">{fila.motivos_atencion.map((m) => <li key={m}>{MOTIVOS_EQUIPO[m]}</li>)}</ul></div>}
  85          <div className="my-3 flex flex-wrap gap-2">
  86            <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirPendientes(false)}>Ver pendientes ({fila.tareas_pendientes})</Button>
  87            {fila.tareas_vencidas > 0 && <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirPendientes(true)}>{fila.tareas_vencidas} tareas vencidas</Button>}
  88          </div>
  89          <DetalleAnalista fila={fila} dia={dia} abrirLlamadas={() => abrirRegistro('llamadas')} />
  90        </>}
  91        {seleccion.analista !== null && <>
  92          <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} />
  93          <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirRegistro('todo')}>Ver registro</Button>
  94        </>}
  95      </div>
  96      <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
  97        {registro && <section aria-label="Registro seleccionado">
  98          <h4 ref={tituloRegistro} tabIndex={-1} className="mb-3 font-semibold">{equipo ? 'Registro del equipo' : `Registro de ${seleccion.nombre}`}</h4>
  99          <RegistroActividad key={registro.apertura} dia={dia} pestanaInicial={registro.pestana}
 100            analistaIds={seleccion.analista === null ? null : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
 101        </section>}
 102      </div>
 103      <div className="gd-panel-cuerpo ac-scroll" hidden={pestana !== 'pendientes'} inert={pestana !== 'pendientes'}>
 104        {pendientes && seleccion.analista !== null && <PendientesSupervisor key={pendientes.apertura}
 105          analista={seleccion.analista} nombre={fila?.nombre_completo ?? seleccion.nombre ?? 'Analista'} dia={dia} fila={fila}
 106          visible={pestana === 'pendientes'} soloVencidasInicial={pendientes.soloVencidas} apertura={pendientes.apertura}
 107          enfocar={pendientes.enfocar} actualizacion={actualizacion} revalidar={revalidar} />}
 108      </div>
 109    </>
 110    return <>
 111      {oculta && <div className="gd-seleccion-oculta">La selección está fuera de los filtros.<Button variant="ghost" className="min-h-11 text-base" onClick={limpiar}>Limpiar filtros</Button></div>}
 112      {equipo ? contenido : <Tabs className="gd-pestanas-panel" tamano="grande" etiqueta="Detalle del analista" valor={pestana} onCambio={cambiar}
 113        pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, { valor: 'pendientes', etiqueta: 'Pendientes' }]}>{contenido}</Tabs>}
 114    </>
 115  }
```

### src/components/gestion-diaria/panel-supervisor-adaptable.tsx (69 líneas)
```tsx
   1  import { useCallback, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
   2  import { createPortal } from 'react-dom'
   3  import * as Dialog from '@radix-ui/react-dialog'
   4  import { protegerEscapeAnidado } from '@/components/ui/escape-dialogo'
   5  
   6  /** El portal conserva SIEMPRE el mismo destino DOM. Mover su contenedor entre
   7   * región y diálogo mantiene filtros, páginas, scroll e instancias React.
   8   * Radix conserva la modalidad, capas y foco, también sobre la ficha del lead.
   9   * Content no debe tener animación de salida: el destino se traslada en el commit. */
  10  export function PanelSupervisorAdaptable({ modal, cerrar, tituloRef, children }: {
  11    modal: boolean
  12    cerrar: () => void
  13    tituloRef: RefObject<HTMLHeadingElement | null>
  14    children: ReactNode
  15  }) {
  16    const [destino] = useState(() => {
  17      const nodo = document.createElement('div')
  18      nodo.className = 'gd-panel-host'
  19      return nodo
  20    })
  21    const contenido = useRef<HTMLDivElement | null>(null)
  22    const focoInterno = useRef<HTMLElement | null>(null)
  23    useLayoutEffect(() => {
  24      // Guardar al enfocar, antes de que React pueda retirar el alojamiento modal.
  25      // Leer activeElement después de retirarlo devolvería body en algunos ciclos.
  26      const recordar = (e: FocusEvent) => { if (e.target instanceof HTMLElement) focoInterno.current = e.target }
  27      destino.addEventListener('focusin', recordar)
  28      return () => destino.removeEventListener('focusin', recordar)
  29    }, [destino])
  30    const mover = useCallback((nodo: HTMLDivElement) => {
  31      const activo = document.activeElement
  32      if (activo instanceof HTMLElement && destino.contains(activo)) focoInterno.current = activo
  33      nodo.appendChild(destino)
  34    }, [destino])
  35    const alojarEnLinea = useCallback((nodo: HTMLDivElement | null) => {
  36      if (nodo && !modal) mover(nodo)
  37    }, [modal, mover])
  38    const alojarEnDialogo = useCallback((nodo: HTMLDivElement | null) => {
  39      contenido.current = nodo
  40      if (nodo) mover(nodo)
  41    }, [mover])
  42    useLayoutEffect(() => {
  43      if (!modal && focoInterno.current?.isConnected) {
  44        focoInterno.current.focus({ preventScroll: true })
  45      }
  46    }, [modal])
  47    return (
  48      <Dialog.Root open={modal} onOpenChange={(abierto) => { if (!abierto) cerrar() }}>
  49        <div ref={alojarEnLinea} className="gd-panel-alojamiento" hidden={modal} />
  50        <Dialog.Portal>
  51          <Dialog.Overlay className="fixed inset-0 z-50 bg-primary/25 backdrop-blur-[2px]" />
  52          <Dialog.Content ref={alojarEnDialogo} className="gd-panel-modal" data-slot="dialog" aria-describedby={undefined}
  53            onEscapeKeyDown={(e) => protegerEscapeAnidado(e, contenido.current)}
  54            onInteractOutside={(e) => {
  55              // Los eventos de React del portal conservan su ascendencia lógica,
  56              // distinta de Content. El DOM decide si el clic pertenece al panel.
  57              if (e.target instanceof Node && destino.contains(e.target)) e.preventDefault()
  58            }}
  59            onOpenAutoFocus={(e) => {
  60              e.preventDefault()
  61              ;(focoInterno.current?.isConnected ? focoInterno.current : tituloRef.current)?.focus({ preventScroll: true })
  62            }}
  63            onCloseAutoFocus={(e) => { e.preventDefault() }}>
  64          </Dialog.Content>
  65        </Dialog.Portal>
  66        {createPortal(children, destino)}
  67      </Dialog.Root>
  68    )
  69  }
```

### src/components/gestion-diaria/detalle-analista.tsx (67 líneas)
```tsx
   1  import { useId } from 'react'
   2  import { Button } from '@/components/ui/button'
   3  import { FRANJA_LLAMADAS, barrasPorHora, horaLimaDe } from '@/lib/gestion-diaria-analista'
   4  import { horarioConfirmado, tiempoSinLlamar, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
   5  
   6  /** F4.2: explica la foto del servidor; no reconstruye cifras desde el store. */
   7  export function DetalleAnalista({ fila: f, dia, abrirLlamadas }: {
   8    fila: FilaEquipoPresentada
   9    dia: string
  10    abrirLlamadas: () => void
  11  }) {
  12    const id = useId()
  13    const barras = barrasPorHora(f.marcador)
  14    const contestadasPorHora = f.marcador.por_hora.reduce((total, h) => total + h.contestadas, 0)
  15    const fuera = f.marcador.por_hora.filter((h) => h.hora < FRANJA_LLAMADAS.desde || h.hora > FRANJA_LLAMADAS.hasta).toSorted((a, b) => a.hora - b.hora)
  16    return (
  17      <div className="space-y-5 pb-3 text-base">
  18        <dl className="gd-metricas-detalle">
  19          {[
  20            ['Llamadas útiles', f.marcador.utiles], ['Leads distintos', f.marcador.leads_tocados],
  21            ['Llamadas por lead', f.llamadas_por_lead ?? '—'], ['Citas pendientes del día', f.citas_hoy],
  22            ['Primera llamada', horaLimaDe(f.marcador.primera_llamada_en)], ['Última llamada', horaLimaDe(f.marcador.ultima_llamada_en)],
  23            ['Tiempo sin llamar', tiempoSinLlamar(f.minutos_sin_llamar)], ['Última gestión', horaLimaDe(f.ultima_gestion_en)],
  24          ].map(([titulo, valor]) => <div key={titulo}><dt className="text-[var(--muted-foreground-strong)]">{titulo}</dt><dd className="mt-1 font-semibold tabular-nums">{valor}</dd></div>)}
  25        </dl>
  26        <div className="space-y-3 border-t border-border pt-4">
  27          <h3 id={`${id}-horas`} className="font-semibold text-primary">Llamadas por hora de {f.nombre_completo}</h3>
  28          <p className="text-[var(--muted-foreground-strong)]">{dia} · Hora de Lima. Llamadas / contestadas en cada hora.</p>
  29          {!horarioConfirmado(f.marcador) ? (
  30            <p role="status">No se pudo confirmar el desglose por hora. Consulta las llamadas en el registro; no se muestran ceros como sustituto.</p>
  31          ) : f.marcador.llamadas === 0 ? (
  32            <p>No hay llamadas registradas ese día. Esto no indica ausencia ni descarta otras gestiones.</p>
  33          ) : (
  34            <>
  35              <div role="img" aria-label="Llamadas y contestadas de 08 a 20 horas. Cifras completas en el desplegable siguiente.">
  36                <div aria-hidden className="gd-grafico-horas">
  37                  {barras.map((b) => <div key={b.hora} className="relative flex h-20 items-end border-b border-border">
  38                    <span className="w-full rounded-t bg-primary" style={{ height: `${b.llamadas / b.maximo * 100}%` }} />
  39                    <span className="absolute bottom-0 left-1/4 w-1/2 rounded-t bg-accent" style={{ height: `${b.contestadas / b.maximo * 100}%` }} />
  40                  </div>)}
  41                </div>
  42                <div aria-hidden className="mt-2 flex justify-between tabular-nums"><span>08 h</span><span>14 h</span><span>20 h</span></div>
  43              </div>
  44              <p>Llamadas: azul oscuro · Contestadas: azul</p>
  45              <details className="gd-cifras-horas">
  46                <summary>Ver cifras por hora</summary>
  47                <ol aria-labelledby={`${id}-horas`}>
  48                  {barras.map((b) => <li key={b.hora}>De {b.hora}:00 a {b.hora}:59: {b.llamadas} llamadas, {b.contestadas} contestadas</li>)}
  49                </ol>
  50              </details>
  51              {contestadasPorHora !== f.marcador.contestadas && (
  52                <p className="text-[var(--muted-foreground-strong)]">Las contestadas por hora incluyen registros de «Número errado» o «No es la persona» que el total de contacto útil excluye.</p>
  53              )}
  54              {fuera.length > 0 && (
  55                <p className="text-[var(--muted-foreground-strong)]">Fuera de la franja 08–20: {fuera.map((h) => `${String(h.hora).padStart(2, '0')} h: ${h.llamadas} ${h.llamadas === 1 ? 'llamada' : 'llamadas'} / ${h.contestadas} ${h.contestadas === 1 ? 'contestada' : 'contestadas'}`).join('; ')}.</p>
  56              )}
  57            </>
  58          )}
  59          <div className="flex flex-wrap items-center gap-4">
  60            <Button variant="outline" className="min-h-11 text-base" onClick={abrirLlamadas}
  61              aria-label={`Ver llamadas del día de ${f.nombre_completo}`}>Ver llamadas del día</Button>
  62            <p className="max-w-2xl text-[var(--muted-foreground-strong)]">En el registro puedes leer cada resultado y abrir la ficha del lead. Se consulta al abrirlo y sólo muestra actividades cuyos leads siguen visibles para tu sesión; puede diferir de esta foto.</p>
  63          </div>
  64        </div>
  65      </div>
  66    )
  67  }
```

### src/components/gestion-diaria/ultimas-gestiones-supervisor.tsx (36 líneas)
```tsx
   1  import { useEffect, useEffectEvent, useMemo, useRef } from 'react'
   2  import { useRegistroActividadOperativo } from '@/data/gestion-diaria-queries'
   3  import { CrmApiError } from '@/data/crm-api'
   4  import { usePanelesActions } from '@/lib/store-context'
   5  import { ETIQUETA_CORTA, horaDeItem, type FiltrosRegistro } from '@/lib/gestion-diaria'
   6  import { Button } from '@/components/ui/button'
   7  
   8  export function UltimasGestionesSupervisor({ analista, dia, visible, actualizacion, revalidar }: {
   9    analista: string; dia: string; visible: boolean; actualizacion: number; revalidar: () => void
  10  }) {
  11    const filtros = useMemo<FiltrosRegistro>(() => ({ dia, analistaIds: [analista], pestana: 'todo', etapa: null }), [dia, analista])
  12    // Misma clave y tamaño que Registro → Todo, primera página sin filtro.
  13    const consulta = useRegistroActividadOperativo(filtros, null, 25, visible, true)
  14    const { abrirLead } = usePanelesActions()
  15    const revision = useRef(actualizacion)
  16    const refrescar = useEffectEvent(() => { void consulta.recargar() })
  17    const revocar = useEffectEvent(revalidar)
  18    const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  19    useEffect(() => {
  20      if (revision.current === actualizacion) return
  21      revision.current = actualizacion; refrescar()
  22    }, [actualizacion])
  23    useEffect(() => { if (sinPermiso) revocar() }, [sinPermiso])
  24    return <section className="space-y-2 mt-4" aria-label="Últimas gestiones del analista">
  25      <h4 className="font-semibold">Últimas gestiones</h4>
  26      {consulta.pagina && <p className="text-[var(--muted-foreground-strong)]">Consulta: {new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(consulta.pagina.generado_en))} · Lima.</p>}
  27      {consulta.cargando && <p role="status">Consultando las últimas gestiones…</p>}
  28      {consulta.error ? <div role="alert"><p>No se pudieron confirmar las últimas gestiones.</p>
  29        {!sinPermiso && <Button className="min-h-11 text-base" variant="outline" onClick={() => { void consulta.recargar() }} disabled={consulta.enVuelo}>Reintentar últimas gestiones</Button>}</div>
  30        : consulta.pagina && consulta.pagina.items.length === 0 ? <p>No hay gestiones visibles de este analista en el día.</p>
  31          : <ol>{consulta.pagina?.items.slice(0, 3).map(item => <li key={item.id} className="py-2">
  32            <p><time dateTime={new Date(item.creado_en).toISOString()}>{horaDeItem(item)}</time> · {ETIQUETA_CORTA[item.tipo]}</p>
  33            <Button variant="link" className="min-h-11 h-auto max-w-full whitespace-normal px-0 text-left text-base" onClick={() => abrirLead(item.lead_id)}>{item.lead_nombre}</Button>
  34          </li>)}</ol>}
  35    </section>
  36  }
```

### src/components/gestion-diaria/pendientes-supervisor.tsx (69 líneas)
```tsx
   1  import { useEffect, useEffectEvent, useId, useRef, useState } from 'react'
   2  import { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
   3  import { CrmApiError } from '@/data/crm-api'
   4  import { usePanelesActions } from '@/lib/store-context'
   5  import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
   6  import { Button } from '@/components/ui/button'
   7  import { TIPO_EVENTO } from '@/lib/tipos'
   8  
   9  const FECHA = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })
  10  
  11  export function PendientesSupervisor({ analista, nombre, dia, fila, visible, soloVencidasInicial, apertura, enfocar, actualizacion, revalidar }: {
  12    analista: string; nombre: string; dia: string; fila: FilaEquipoPresentada | undefined; visible: boolean
  13    soloVencidasInicial: boolean; apertura: number; enfocar: boolean; actualizacion: number; revalidar: () => void
  14  }) {
  15    const [soloVencidas, setSoloVencidas] = useState(soloVencidasInicial)
  16    const lista = usePendientesSupervisor(dia, analista, soloVencidas, visible, apertura)
  17    const { abrirLead } = usePanelesActions()
  18    const titulo = useRef<HTMLHeadingElement>(null)
  19    const tituloId = useId()
  20    const revision = useRef(actualizacion)
  21    const refrescar = useEffectEvent(() => { void lista.recargar() })
  22    const revocar = useEffectEvent(revalidar)
  23    useEffect(() => { if (enfocar) titulo.current?.focus({ preventScroll: true }) }, [enfocar])
  24    useEffect(() => {
  25      if (revision.current === actualizacion) return
  26      revision.current = actualizacion; refrescar()
  27    }, [actualizacion])
  28    useEffect(() => { if (lista.sinPermiso) revocar() }, [lista.sinPermiso])
  29    const noInstalada = lista.error instanceof CrmApiError && lista.error.code === 'PGRST202'
  30    const resumen = lista.pagina?.resumen ?? (fila && !lista.sinPermiso ? fila : null)
  31    return <section aria-labelledby={tituloId} className="space-y-3">
  32      <h4 id={tituloId} ref={titulo} tabIndex={-1} className="font-semibold">Pendientes de {nombre}</h4>
  33      {resumen && <p><strong>{resumen.tareas_pendientes}</strong> tareas pendientes · <strong>{resumen.tareas_vencidas}</strong> vencidas.
  34        {lista.pagina ? ' Foto de la consulta de tareas.' : ' Último resumen confirmado del equipo.'}</p>}
  35      {fila && !lista.sinPermiso && <p className="text-[var(--muted-foreground-strong)]">Primer intento fuera de plazo: {fila.primer_intento_vencido ?? 'no evaluado'}. Datos incompletos: {fila.datos_incompletos ?? 'no evaluado'}.
  36        {' '}Estas señales corresponden a leads y no se suman como tareas.</p>}
  37      <div className="flex flex-wrap gap-2" role="group" aria-label="Filtro de tareas">
  38        <Button className="min-h-11 text-base" variant={!soloVencidas ? 'default' : 'outline'} aria-pressed={!soloVencidas} onClick={() => setSoloVencidas(false)}>Todas</Button>
  39        <Button className="min-h-11 text-base" variant={soloVencidas ? 'default' : 'outline'} aria-pressed={soloVencidas} onClick={() => setSoloVencidas(true)}>Vencidas</Button>
  40      </div>
  41      {lista.cargando && <p role="status">Consultando las tareas de este analista…</p>}
  42      {lista.error && <div role="alert" className="space-y-2">
  43        <p>{lista.sinPermiso ? 'Ya no tienes acceso a estas tareas. Se retiraron los datos anteriores.'
  44          : noInstalada ? 'Detalle de tareas no disponible. La consulta aún no está instalada.'
  45            : 'No se pudo confirmar la lista de tareas. Esto no significa que esté vacía.'}</p>
  46        {!lista.sinPermiso && <Button className="min-h-11 text-base" variant="outline" disabled={lista.enVuelo} onClick={() => { void lista.recargar() }}>Reintentar desde el inicio</Button>}
  47      </div>}
  48      {lista.pagina && <p className="text-[var(--muted-foreground-strong)]">
  49        Consulta: {FECHA.format(new Date(lista.pagina.generado_en))} · Lima.
  50        {lista.error ? ' Datos anteriores; la actualización falló.' : lista.congelada ? ' Actualización automática pausada: hay varias páginas cargadas.' : ' Actualización cada minuto mientras esta pestaña está visible.'}
  51      </p>}
  52      {lista.congelada && lista.consultadoDesde && <p className="text-[var(--muted-foreground-strong)]">Primera página consultada: {FECHA.format(new Date(lista.consultadoDesde))}. Las tareas pueden cambiar; actualizar comienza una nueva consulta.</p>}
  53      {!lista.error && lista.pagina && lista.items.length === 0 && <p>{soloVencidas ? 'No hay tareas vencidas en esta consulta.' : 'Sin tareas pendientes.'}</p>}
  54      <ul className="divide-y divide-border" aria-label="Lista de tareas pendientes">
  55        {lista.items.map(tarea => <li key={tarea.id} className="space-y-1 py-3 break-words">
  56          <p className="font-semibold">{tarea.titulo.trim() || 'Sin título'}</p>
  57          <p>{TIPO_EVENTO[tarea.tipo] ?? tarea.tipo} · <time dateTime={new Date(tarea.vence_en).toISOString()}>{FECHA.format(new Date(tarea.vence_en))}</time> · Lima</p>
  58          {tarea.lead_id && tarea.lead_nombre
  59            ? <Button variant="link" className="min-h-11 h-auto max-w-full whitespace-normal px-0 text-left text-base" onClick={() => abrirLead(tarea.lead_id!)}>{tarea.lead_nombre}</Button>
  60            : <p className="text-[var(--muted-foreground-strong)]">{tarea.referencia_tipo === 'perfil' ? 'Tarea de perfil' : tarea.referencia_tipo === 'postventa' ? 'Tarea de postventa' : 'Referencia no disponible'}</p>}
  61        </li>)}
  62      </ul>
  63      {lista.pagina && <p role="status">{lista.items.length} tareas cargadas{lista.hayMas ? ' · Hay más por consultar.' : lista.error ? ' · Consulta incompleta.' : ' · Fin de las páginas consultadas.'}</p>}
  64      <div className="flex flex-wrap gap-2">
  65        {lista.hayMas && <Button className="min-h-11 text-base" disabled={lista.enVuelo} onClick={() => { void lista.cargarMas() }}>{lista.enVuelo ? 'Consultando…' : 'Cargar más tareas'}</Button>}
  66        {!lista.sinPermiso && !noInstalada && <Button className="min-h-11 text-base" variant="outline" disabled={lista.enVuelo} onClick={() => { void lista.recargar() }}>Actualizar desde el inicio</Button>}
  67      </div>
  68    </section>
  69  }
```

### src/components/gestion-diaria/franja-cortes-supervisor.tsx (38 líneas)
```tsx
   1  import { useRef } from 'react'
   2  import { Bell } from 'lucide-react'
   3  import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
   4  import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
   5  import { useAlertasCRM } from '@/lib/alertas-context'
   6  import { presentarCortesJornada } from '@/lib/gestion-diaria-cortes-presentacion'
   7  import { horaCorte } from '@/lib/gestion-diaria-avisos'
   8  import { Button } from '@/components/ui/button'
   9  
  10  export function FranjaCortesSupervisor({ consulta, abrir }: { consulta: DiaEquipoHook; abrir: () => void }) {
  11    const avisos = useGestionDiariaAvisos()
  12    const otros = useAlertasCRM()
  13    const dia = consulta.error ? null : consulta.dia
  14    const cortes = presentarCortesJornada(dia)
  15    const estado = consulta.error ? 'Cortes no disponibles' : consulta.cargando ? 'Consultando cortes…'
  16      : !dia?.cortes ? 'Sin detalle de cortes' : dia.cortes.estado === 'desactivados' ? 'Cortes desactivados'
  17        : dia.cortes.estado === 'no_laborable' ? 'Día no laborable' : null
  18    const ultimoConteo = useRef<number | null>(null)
  19    if (avisos?.error || !avisos?.datos || otros.errores.length) ultimoConteo.current = null
  20    else if (!otros.cargando) ultimoConteo.current = otros.alertas.filter((a) => !a.corte && !a.reconocimiento).length
  21    return <section className="gd-cortes" aria-label="Estado de cortes y avisos">
  22      <Button variant="ghost" className="min-h-11 shrink-0 text-base" aria-haspopup="dialog" onClick={abrir}>
  23        <Bell aria-hidden />Cortes y avisos
  24      </Button>
  25      <div className="gd-cortes-resumen">
  26        {estado ? <span>{estado}</span> : cortes.map((c) => <span key={c.clave}>
  27          <time dateTime={c.instante}>{c.hora}</time> {c.estado}
  28          {c.bajoMinimo > 0 && <strong> · {c.bajoMinimo} bajo el mínimo</strong>}
  29        </span>)}
  30        {avisos?.error ? <span>Avisos no disponibles</span> : avisos?.cargando ? <span>Consultando avisos…</span>
  31          : avisos?.datos && <>
  32            {!avisos.datos.avisos_habilitados && <span>Avisos pausados</span>}
  33            <span>{otros.errores.length ? 'Otros avisos sin confirmar' : ultimoConteo.current === null ? 'Consultando otros avisos…' : `Otros sin reconocer: ${ultimoConteo.current}`}</span>
  34          </>}
  35      </div>
  36      <p className="gd-cortes-consulta">{dia ? `Consulta ${horaCorte(dia.generado_en)} · Lima` : 'Sin consulta confirmada'}</p>
  37    </section>
  38  }
```

### src/components/gestion-diaria/espacio-pulso-gerencia.tsx (179 líneas)
```tsx
   1  import { useEffect, useId, useRef, useState, type RefObject, type MouseEvent } from 'react'
   2  import { ArrowLeft, ListFilter, Search } from 'lucide-react'
   3  import { type PulsoGerencia, type EquipoPulso, cifraPulso } from '@/lib/gestion-diaria-pulso'
   4  import { filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
   5  import { hashDe } from '@/lib/router'
   6  import type { useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
   7  import { Button } from '@/components/ui/button'
   8  import { Input } from '@/components/ui/input'
   9  import { Tabs } from '@/components/ui/tabs'
  10  import { PanelCargando } from '@/components/common/estado-panel'
  11  import { TablaEquipoDiaria } from './tabla-equipo-diaria'
  12  import { DetalleAnalista } from './detalle-analista'
  13  import { RegistroActividad } from './registro-actividad'
  14  import { PanelGerencia } from './panel-gerencia'
  15  import { ComparacionEquiposGerencia } from './comparacion-equipos-gerencia'
  16  import { ErrorConsultaGerencia } from './error-consulta-gerencia'
  17  
  18  type Ruta = { tipo: 'equipo' | 'analista'; id: string } | undefined
  19  type Consulta = ReturnType<typeof useDetallePulso>
  20  const FILTROS: FiltrosEquipo = { busqueda: '', soloProblemas: false, orden: 'atencion', ascendente: false }
  21  const PESTANAS = [{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }] as const
  22  const rutaEquipo = (grupo: EquipoPulso) => hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: grupo.clave })
  23  const navegarEnVentana = (e: MouseEvent<HTMLAnchorElement>) => !e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey
  24  
  25  /** La tabla conserva su estado al cambiar de analista y al abrir la ficha de un lead. */
  26  export function EspacioPulsoGerencia({ datos, ruta, consulta, actualizacion, estrecho, general, cerrarGeneral, abrirGeneral, rutaEnfocada, oculto, setOculto, origenGeneral, sinPermiso }: {
  27    datos: PulsoGerencia; ruta: Ruta; consulta: Consulta; actualizacion: number; estrecho: boolean
  28    general: boolean; cerrarGeneral: () => void; abrirGeneral: () => void
  29    rutaEnfocada: RefObject<string | null>
  30    oculto: string | null; setOculto: (clave: string | null) => void
  31    origenGeneral: RefObject<HTMLButtonElement | null>
  32    sinPermiso: () => void
  33  }) {
  34    const grupo = datos.equipos.find((e) => ruta?.tipo === 'equipo' ? e.clave === ruta.id : e.personas.some((p) => p.analista_id === ruta?.id))
  35    const persona = ruta?.tipo === 'analista' ? grupo?.personas.find((p) => p.analista_id === ruta.id) : null
  36    const [filtrosPorEquipo, setFiltrosPorEquipo] = useState<Record<string, FiltrosEquipo>>({})
  37    const filtros = grupo ? filtrosPorEquipo[grupo.clave] ?? FILTROS : FILTROS
  38    const cambiarFiltros = (cambio: (actual: FiltrosEquipo) => FiltrosEquipo) => {
  39      if (grupo) setFiltrosPorEquipo((todos) => ({ ...todos, [grupo.clave]: cambio(todos[grupo.clave] ?? FILTROS) }))
  40    }
  41    const [ampliado, setAmpliado] = useState(false)
  42    const [generalVisitado, setGeneralVisitado] = useState(general)
  43    if (general && !generalVisitado) setGeneralVisitado(true)
  44    const titulo = useRef<HTMLHeadingElement>(null)
  45    const tituloTabla = useRef<HTMLHeadingElement>(null)
  46    const origen = useRef<HTMLElement | null>(null)
  47    const clave = ruta ? `${ruta.tipo}:${ruta.id}` : null
  48    const abierto = general || Boolean(ruta && oculto !== clave)
  49    const anchoAnterior = useRef(estrecho)
  50    const id = useId()
  51    useEffect(() => {
  52      const ampliarDesdeMovil = anchoAnterior.current && !estrecho
  53      anchoAnterior.current = estrecho
  54      if (ampliarDesdeMovil && ruta?.tipo === 'equipo' && oculto === clave) setOculto(null)
  55    }, [estrecho, ruta?.tipo, oculto, clave, setOculto])
  56    useEffect(() => {
  57      if (clave && clave !== rutaEnfocada.current && abierto) titulo.current?.focus({ preventScroll: true })
  58      rutaEnfocada.current = clave
  59    }, [clave, abierto, rutaEnfocada])
  60    useEffect(() => { if (general) titulo.current?.focus({ preventScroll: true }) }, [general])
  61    const recordarOrigen = (control?: HTMLElement | null) => {
  62      const activo = control ?? document.activeElement
  63      origen.current = activo instanceof HTMLElement && activo !== document.body ? activo : null
  64    }
  65    const devolverFoco = (registroGeneral: boolean) => requestAnimationFrame(() => {
  66      // Una interacción posterior tiene prioridad sobre el retorno pendiente.
  67      const activo = document.activeElement
  68      if (activo instanceof HTMLElement && activo !== document.body && activo.matches('input,select,textarea')) return
  69      const destino = registroGeneral ? origenGeneral.current : origen.current?.isConnected ? origen.current : tituloTabla.current
  70      destino?.focus({ preventScroll: true })
  71      if (document.activeElement !== destino) tituloTabla.current?.focus({ preventScroll: true })
  72    })
  73    const cerrar = () => {
  74      setAmpliado(false)
  75      if (general) cerrarGeneral()
  76      else if (ruta?.tipo === 'analista' && grupo) { setOculto(`equipo:${grupo.clave}`); window.location.hash = rutaEquipo(grupo) }
  77      else setOculto(clave)
  78      devolverFoco(general)
  79    }
  80    const abrirEquipo = (e: EquipoPulso, control?: HTMLElement) => {
  81      recordarOrigen(control); cerrarGeneral(); setAmpliado(false)
  82      setOculto(estrecho ? `equipo:${e.clave}` : null)
  83      rutaEnfocada.current = `equipo:${e.clave}`
  84      window.location.hash = rutaEquipo(e)
  85      requestAnimationFrame(() => tituloTabla.current?.focus({ preventScroll: true }))
  86    }
  87    const volverOperacion = (e: MouseEvent<HTMLAnchorElement>) => {
  88      if (!navegarEnVentana(e)) return
  89      e.preventDefault(); cerrarGeneral(); setOculto(null); setAmpliado(false)
  90      window.location.hash = hashDe('gestion-diaria')
  91      requestAnimationFrame(() => tituloTabla.current?.focus({ preventScroll: true }))
  92    }
  93    const abrirAnalista = (analista: string, control?: HTMLElement) => {
  94      const fila = Array.from(tituloTabla.current?.closest('section')?.querySelectorAll<HTMLElement>('tr[data-analista]') ?? []).find((n) => n.dataset.analista === analista)
  95      recordarOrigen(control ?? fila?.querySelector<HTMLElement>('button')); cerrarGeneral(); setOculto(null)
  96      rutaEnfocada.current = `analista:${analista}`
  97      window.location.hash = hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: analista })
  98    }
  99    const filas = consulta.datos && grupo ? presentarEquipo(consulta.datos).filter((f) => grupo.personas.some((p) => p.analista_id === f.analista_id)) : []
 100    const mostradas = filtrarOrdenarEquipo(filas, filtros)
 101    const nombre = persona ? persona.nombre_completo ?? 'Autor no disponible' : grupo?.nombre ?? 'Detalle no disponible'
 102    return <div className="gd-espacio gp-espacio" data-estrecho={estrecho}>
 103      <section className="gd-equipo" aria-label={grupo ? 'Analistas del equipo' : 'Equipos de la operación'}>
 104        <div className="gp-tabla-cabecera">
 105          <div>{grupo && <a className="gp-volver" href={hashDe('gestion-diaria')} onClick={volverOperacion}><ArrowLeft aria-hidden />Toda la operación</a>}
 106            <h3 ref={tituloTabla} tabIndex={-1}>{grupo?.nombre ?? 'Equipos y atención actual'}</h3></div>
 107          {grupo && <Button variant="outline" className="min-h-11 text-base" onClick={() => { recordarOrigen(); cerrarGeneral(); setOculto(null); titulo.current?.focus() }}>Ver detalle</Button>}
 108        </div>
 109        <div className="gp-comparacion" hidden={Boolean(grupo)} inert={Boolean(grupo)}><ComparacionEquiposGerencia equipos={datos.equipos} abrir={abrirEquipo} /></div>
 110        {grupo && <>
 111          <div className="gd-filtros gp-filtros">
 112            <div className="gd-busqueda"><Search aria-hidden /><Input type="search" aria-label="Buscar analista del equipo" placeholder="Buscar analista" className="min-h-11 pl-9 text-base" value={filtros.busqueda} onChange={(e) => cambiarFiltros((f) => ({ ...f, busqueda: e.target.value }))} /></div>
 113            <Button variant={filtros.soloProblemas ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={filtros.soloProblemas} onClick={() => cambiarFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}><ListFilter aria-hidden />Con atención ({filas.filter((f) => f.requiere_atencion).length})</Button>
 114            <span className="gd-conteo">{mostradas.length} de {filas.length} analistas</span>
 115          </div>
 116          {consulta.error ? <ErrorConsultaGerencia error={consulta.error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} /> : consulta.cargando ? <PanelCargando /> : <>
 117            {persona?.activo && !mostradas.some((f) => f.analista_id === persona.analista_id) && <p className="gd-seleccion-oculta">La selección no aparece con los filtros actuales.</p>}
 118            <TablaEquipoDiaria filas={mostradas} filtros={filtros} ordenar={(orden) => cambiarFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : true }))}
 119              seleccion={persona?.analista_id ?? null} seleccionar={(f) => abrirAnalista(f.analista_id)} panelId={id} irAlDetalle={() => { setOculto(null); titulo.current?.focus() }} minimo={datos.minimo_llamadas_utiles} />
 120            {grupo.personas.some((p) => !p.activo) && <div className="gp-otros-autores"><h4>Otros autores de los registros</h4><ul>{grupo.personas.filter((p) => !p.activo).map((p) => <li key={p.analista_id ?? 'sin-autor'}>{p.analista_id
 121              ? <button type="button" onClick={(e) => abrirAnalista(p.analista_id!, e.currentTarget)}>{p.nombre_completo ?? 'Autor no disponible'}</button> : 'Sin autor'}: {p.llamadas} llamadas · {p.citas_agendadas} citas agendadas</li>)}</ul>
 122              {grupo.personas.some((p) => p.analista_id === null) && <Button variant="outline" className="min-h-11 text-base" onClick={abrirGeneral}>Ver registros sin autor en el registro general</Button>}
 123            </div>}
 124          </>}
 125        </>}
 126      </section>
 127      <PanelGerencia id={id} titulo={general ? 'Registro general del día' : ruta ? nombre : 'Detalle de la operación'} abierto={abierto} estrecho={estrecho} ampliado={ampliado}
 128        ampliar={() => setAmpliado((v) => !v)} cerrar={cerrar} tituloRef={titulo} vacio="Elige un equipo para comparar a sus analistas y consultar sus registros.">
 129        {generalVisitado && <section className="gd-panel-cuerpo gp-registro" hidden={!general} inert={!general} aria-label="Registro general de la operación">
 130          <RegistroActividad dia={datos.dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial="todo" actualizacion={actualizacion} onSinPermiso={sinPermiso} />
 131        </section>}
 132        {ruta && <div className="gp-detalle-contenido" hidden={general} inert={general}>
 133          <nav aria-label="Ruta de la operación" className="gp-ruta"><a href={hashDe('gestion-diaria')} onClick={volverOperacion}>Toda la operación</a>{ruta.tipo === 'analista' && grupo && <a href={rutaEquipo(grupo)} onClick={(e) => { if (navegarEnVentana(e)) { e.preventDefault(); abrirEquipo(grupo, e.currentTarget) } }}>{grupo.nombre}</a>}</nav>
 134          <DetallePulsoGerencia key={`${ruta.tipo}:${ruta.id}`} datos={datos} grupo={grupo} seleccion={ruta} consulta={consulta} actualizacion={actualizacion} abrirGeneral={abrirGeneral} sinPermiso={sinPermiso} />
 135        </div>}
 136      </PanelGerencia>
 137    </div>
 138  }
 139  
 140  function DetallePulsoGerencia({ datos, grupo, seleccion, consulta, actualizacion, abrirGeneral, sinPermiso }: {
 141    datos: PulsoGerencia; grupo: EquipoPulso | undefined; seleccion: NonNullable<Ruta>; consulta: Consulta; actualizacion: number; abrirGeneral: () => void; sinPermiso: () => void
 142  }) {
 143    const persona = seleccion.tipo === 'analista' ? grupo?.personas.find((p) => p.analista_id === seleccion.id) : null
 144    const personas = seleccion.tipo === 'equipo' ? grupo?.personas ?? [] : persona ? [persona] : []
 145    const ids = personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id])
 146    const fila = consulta.datos && persona ? presentarEquipo(consulta.datos).find((f) => f.analista_id === persona.analista_id) : undefined
 147    const [pestana, setPestana] = useState<'resumen' | 'registro'>('resumen')
 148    const [registroVisitado, setRegistroVisitado] = useState(false)
 149    const abrirRegistro = () => { setPestana('registro'); setRegistroVisitado(true) }
 150    if (!grupo || (seleccion.tipo === 'analista' && !persona)) return <p role="status" className="gd-panel-cuerpo">Este equipo o autor ya no aparece en el ámbito actual. Vuelve a toda la operación.</p>
 151    if (consulta.error) return <ErrorConsultaGerencia error={consulta.error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} />
 152    if (consulta.cargando) return <PanelCargando />
 153    return <Tabs etiqueta="Detalle gerencial" className="gd-pestanas-panel" tamano="grande" pestanas={PESTANAS} valor={pestana} onCambio={(v) => { setPestana(v); if (v === 'registro') setRegistroVisitado(true) }}>
 154      <div className="gd-panel-cuerpo" hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
 155        {seleccion.tipo === 'equipo' && <>
 156          <p>{grupo.metricas.analistas_activos} analistas activos · {datos.dia}</p>
 157          <dl className="gd-metricas-detalle">{[
 158            ['Llamadas', grupo.metricas.llamadas], ['Contacto', cifraPulso(grupo.metricas.tasa_contacto, true)],
 159            ['Llamadas útiles', grupo.metricas.utiles], ['Contestadas', grupo.metricas.contestadas],
 160            ['Sin actividad', grupo.metricas.sin_actividad], ['Leads distintos', grupo.metricas.leads_unicos],
 161            ['Llamadas por lead', cifraPulso(grupo.metricas.llamadas_por_lead)], ['Citas agendadas', grupo.metricas.citas_agendadas],
 162            ['Tareas vencidas actuales', grupo.tareas_vencidas], ['Primer intento vencido', grupo.primer_intento_vencido ?? 'SLA no activo'],
 163          ].map(([etiqueta, valor]) => <div key={etiqueta}><dt>{etiqueta}</dt><dd className="font-semibold">{valor}</dd></div>)}</dl>
 164          <Button variant="outline" className="min-h-11 text-base" onClick={abrirRegistro}>Ver registro del equipo</Button>
 165        </>}
 166        {persona && <>
 167          <p className="gd-resumen-principal"><strong>{persona.llamadas}</strong> llamadas del día</p>
 168          {fila && <DetalleAnalista fila={fila} dia={datos.dia} abrirLlamadas={abrirRegistro} />}
 169          {!persona.activo && <p>Autor fuera del organigrama comercial activo: {persona.llamadas} llamadas, {persona.utiles} útiles, {persona.contestadas} contestadas.</p>}
 170          {persona.activo && !fila && <p role="status">El analista ya no aparece en la consulta actual del equipo. Actualiza la operación para confirmar su ámbito.</p>}
 171        </>}
 172        {personas.some((p) => p.analista_id === null) && <p className="mt-4">Los registros sin autor se consultan en el <button type="button" className="gp-enlace" onClick={abrirGeneral}>registro general del día</button>.</p>}
 173      </div>
 174      {registroVisitado && <div className="gd-panel-cuerpo gp-registro" hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
 175        {ids.length ? <RegistroActividad dia={datos.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial="llamadas" actualizacion={actualizacion} onSinPermiso={sinPermiso} />
 176          : <p>Consulta estos registros desde el <button type="button" className="gp-enlace" onClick={abrirGeneral}>registro general del día</button>.</p>}
 177      </div>}
 178    </Tabs>
 179  }
```

### src/components/gestion-diaria/panel-gerencia.tsx (32 líneas)
```tsx
   1  import { type ReactNode, type RefObject } from 'react'
   2  import { Title as TituloDialogo } from '@radix-ui/react-dialog'
   3  import { Maximize2, Minimize2, Users, X } from 'lucide-react'
   4  import { Button } from '@/components/ui/button'
   5  import { PanelSupervisorAdaptable } from './panel-supervisor-adaptable'
   6  
   7  export function PanelGerencia({ id, titulo, abierto, estrecho, ampliado, ampliar, cerrar, tituloRef, children, vacio, etiqueta = 'Detalle de la operación' }: {
   8    id: string
   9    titulo: string
  10    abierto: boolean
  11    estrecho: boolean
  12    ampliado: boolean
  13    ampliar: () => void
  14    cerrar: () => void
  15    tituloRef: RefObject<HTMLHeadingElement | null>
  16    children: ReactNode
  17    vacio: string
  18    etiqueta?: string
  19  }) {
  20    return <PanelSupervisorAdaptable modal={abierto && (estrecho || ampliado)} cerrar={cerrar} tituloRef={tituloRef}>
  21      <section id={id} className="gd-panel gp-detalle" aria-label={etiqueta}>
  22        <header className="gd-panel-cabecera">
  23          <TituloDialogo asChild><h3 ref={tituloRef} tabIndex={-1}>{titulo}</h3></TituloDialogo>
  24          {abierto && <div className="flex shrink-0">
  25            {!estrecho && <Button variant="ghost" size="icon" className="size-11" aria-label={ampliado ? 'Restaurar panel' : 'Ampliar panel'} onClick={ampliar}>{ampliado ? <Minimize2 aria-hidden /> : <Maximize2 aria-hidden />}</Button>}
  26            <Button variant="ghost" size="icon" className="size-11" aria-label="Cerrar detalle" onClick={cerrar}><X aria-hidden /></Button>
  27          </div>}
  28        </header>
  29        {abierto ? children : <div className="gd-panel-inicial"><Users className="size-10" aria-hidden /><p>{vacio}</p></div>}
  30      </section>
  31    </PanelSupervisorAdaptable>
  32  }
```

### src/lib/gestion-diaria-equipo.ts (159 líneas)
```ts
   1  // Contrato de F4. En real, todos los indicadores proceden de una sola foto
   2  // autorizada del servidor. Aquí sólo se valida, busca, ordena y presenta.
   3  import * as v from 'valibot'
   4  import { MarcadorSchema, UmbralesSchema, type Marcador } from './gestion-diaria-analista'
   5  import { CortesJornadaSchema } from './gestion-diaria-cortes'
   6  
   7  const Natural = v.pipe(v.number(), v.integer(), v.minValue(0))
   8  export const MOTIVOS_EQUIPO = {
   9    tarea_vencida: 'Tareas vencidas',
  10    primer_intento_vencido: 'Primer intento fuera de plazo',
  11    datos_incompletos: 'Datos pendientes de revisar',
  12    sin_llamar_2h: 'Más de 2 h sin llamar en la jornada',
  13    corte_manana: 'Primer corte de llamadas pendiente',
  14    corte_tarde: 'Segundo corte de llamadas pendiente',
  15  } as const
  16  const FilaEquipoSchema = v.object({
  17    analista_id: v.string(),
  18    nombre_completo: v.string(),
  19    gestiones_hoy: Natural,
  20    ultima_gestion_en: v.nullable(v.string()),
  21    marcador: MarcadorSchema,
  22    llamadas_por_lead: v.nullable(v.pipe(v.number(), v.minValue(0))),
  23    minutos_sin_llamar: v.nullable(Natural),
  24    tareas_pendientes: Natural,
  25    tareas_vencidas: Natural,
  26    citas_hoy: Natural,
  27    primer_intento_vencido: v.nullable(Natural),
  28    datos_incompletos: v.nullable(Natural),
  29    sin_llamar_2h: v.boolean(),
  30    motivos_atencion: v.array(v.picklist(['tarea_vencida', 'primer_intento_vencido', 'datos_incompletos', 'sin_llamar_2h'])),
  31    requiere_atencion: v.boolean(),
  32  })
  33  export type FilaEquipoDiario = v.InferOutput<typeof FilaEquipoSchema>
  34  
  35  export const DiaEquipoSchema = v.pipe(v.object({
  36    version: v.literal(1),
  37    generado_en: v.string(),
  38    dia: v.string(),
  39    zona: v.literal('America/Lima'),
  40    supervisor_id: v.nullable(v.string()),
  41    umbrales: UmbralesSchema,
  42    /** Ausente en servidores anteriores: desconocido, no completar con ceros. */
  43    cortes: v.optional(CortesJornadaSchema),
  44    pendientes_al: v.string(),
  45    modo_sla: v.string(),
  46    equipo: v.array(FilaEquipoSchema),
  47    resumen: v.object({
  48      analistas: Natural,
  49      con_actividad: Natural,
  50      sin_actividad: Natural,
  51      con_pendientes: Natural,
  52      requieren_atencion: Natural,
  53    }),
  54  }), v.check((d) => {
  55    const r = resumenEquipo(d.equipo)
  56    return new Set(d.equipo.map((f) => f.analista_id)).size === d.equipo.length
  57      && (d.cortes === undefined || (d.cortes.politica_version === d.umbrales.politica_version
  58        && (d.cortes.estado !== 'activo' || (d.cortes.equipo.length === d.equipo.length
  59          && d.cortes.equipo.every((f) => d.equipo.some((e) => e.analista_id === f.analista_id))))))
  60      && Object.keys(r).every((k) => r[k as keyof typeof r] === d.resumen[k as keyof typeof r])
  61      && d.equipo.every((f) => f.tareas_vencidas <= f.tareas_pendientes
  62        && f.requiere_atencion === (f.motivos_atencion.length > 0)
  63        && f.marcador.contestadas <= f.marcador.utiles && f.marcador.utiles <= f.marcador.llamadas
  64        && (f.marcador.utiles >= d.umbrales.minimo_llamadas_utiles || f.marcador.nivel === null)
  65        && (d.modo_sla === 'activo' || (f.primer_intento_vencido === null && f.datos_incompletos === null)))
  66  }, 'El resumen del equipo no corresponde a sus filas'))
  67  export type DiaEquipo = v.InferOutput<typeof DiaEquipoSchema>
  68  
  69  export type FilaEquipoPresentada = Omit<FilaEquipoDiario, 'motivos_atencion'> & {
  70    motivos_atencion: (keyof typeof MOTIVOS_EQUIPO)[]
  71  }
  72  
  73  /** Une resultados ya confirmados en la misma foto; no calcula cortes ni horarios. */
  74  export function presentarEquipo(dia: DiaEquipo): FilaEquipoPresentada[] {
  75    const cortes = new Map(dia.cortes?.estado === 'activo'
  76      ? dia.cortes.equipo.map((f) => [f.analista_id, f]) : [])
  77    return dia.equipo.map((fila) => {
  78      const corte = cortes.get(fila.analista_id)
  79      const motivos: FilaEquipoPresentada['motivos_atencion'] = [...fila.motivos_atencion]
  80      if (corte?.primer_corte.aviso_pendiente) motivos.push('corte_manana')
  81      if (corte?.segundo_corte?.aviso_pendiente) motivos.push('corte_tarde')
  82      const confirmados = corte?.primer_corte.aviso_pendiente || corte?.segundo_corte?.aviso_pendiente
  83        ? motivos.filter((m) => m !== 'sin_llamar_2h') : motivos
  84      return { ...fila, motivos_atencion: confirmados, requiere_atencion: confirmados.length > 0 }
  85    })
  86  }
  87  
  88  /** Resumen para el espejo demo y validación, nunca para completar una lista parcial. */
  89  export function resumenEquipo(equipo: readonly FilaEquipoDiario[]) {
  90    return {
  91      analistas: equipo.length,
  92      con_actividad: equipo.filter((f) => f.gestiones_hoy > 0).length,
  93      sin_actividad: equipo.filter((f) => f.gestiones_hoy === 0).length,
  94      con_pendientes: equipo.filter((f) => f.tareas_pendientes > 0 || (f.primer_intento_vencido ?? 0) > 0).length,
  95      requieren_atencion: equipo.filter((f) => f.requiere_atencion).length,
  96    }
  97  }
  98  
  99  export type OrdenEquipo = 'nombre' | 'llamadas' | 'contacto' | 'pendientes' | 'vencidas' | 'atencion'
 100  export type EstadoEquipo = 'todos' | 'con_registro' | 'sin_registro' | 'con_pendientes'
 101  export interface FiltrosEquipo { busqueda: string; soloProblemas: boolean; estado?: EstadoEquipo; orden: OrdenEquipo; ascendente: boolean }
 102  const normalizar = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es').trim()
 103  
 104  export function filtrarOrdenarEquipo<T extends FilaEquipoPresentada>(equipo: readonly T[], filtros: FiltrosEquipo): T[] {
 105    const q = normalizar(filtros.busqueda)
 106    return equipo.filter((f) => (!filtros.soloProblemas || f.requiere_atencion) && normalizar(f.nombre_completo).includes(q)
 107      && (filtros.estado === 'con_registro' ? f.gestiones_hoy > 0
 108        : filtros.estado === 'sin_registro' ? f.gestiones_hoy === 0
 109          : filtros.estado === 'con_pendientes' ? f.tareas_pendientes > 0 || (f.primer_intento_vencido ?? 0) > 0 : true))
 110      .sort((a, b) => {
 111        let diferencia = 0
 112        switch (filtros.orden) {
 113          case 'nombre': diferencia = a.nombre_completo.localeCompare(b.nombre_completo, 'es'); break
 114          case 'llamadas': diferencia = a.marcador.llamadas - b.marcador.llamadas; break
 115          case 'pendientes': diferencia = a.tareas_pendientes - b.tareas_pendientes; break
 116          case 'vencidas': diferencia = a.tareas_vencidas - b.tareas_vencidas; break
 117          case 'atencion': {
 118            diferencia = a.motivos_atencion.length - b.motivos_atencion.length
 119            if (!diferencia) return b.tareas_vencidas - a.tareas_vencidas
 120              || a.nombre_completo.localeCompare(b.nombre_completo, 'es') || a.analista_id.localeCompare(b.analista_id)
 121            break
 122          }
 123          case 'contacto': {
 124            // Muestra insuficiente (no sólo denominador cero) al final en ambos
 125            // sentidos. El servidor aplica el mínimo vigente al producir nivel.
 126            const sinMuestraA = a.marcador.nivel === null || a.marcador.tasa_contacto_pct === null
 127            const sinMuestraB = b.marcador.nivel === null || b.marcador.tasa_contacto_pct === null
 128            if (sinMuestraA || sinMuestraB) return sinMuestraA === sinMuestraB
 129              ? a.nombre_completo.localeCompare(b.nombre_completo, 'es') || a.analista_id.localeCompare(b.analista_id)
 130              : sinMuestraA ? 1 : -1
 131            diferencia = a.marcador.tasa_contacto_pct! - b.marcador.tasa_contacto_pct!
 132          }
 133        }
 134        return (filtros.ascendente ? diferencia : -diferencia)
 135          || a.nombre_completo.localeCompare(b.nombre_completo, 'es') || a.analista_id.localeCompare(b.analista_id)
 136      })
 137  }
 138  
 139  export function tiempoSinLlamar(minutos: number | null): string {
 140    if (minutos === null) return 'Sin llamadas hoy'
 141    if (minutos === 0) return 'Menos de 1 min'
 142    return minutos < 60 ? `${minutos} min` : `${Math.floor(minutos / 60)} h ${minutos % 60} min`
 143  }
 144  
 145  /** No pintar barras a cero si llegó un desglose parcial o inconsistente. */
 146  export function horarioConfirmado(marcador: Marcador): boolean {
 147    const horas = marcador.por_hora
 148    const contestadasPorHora = horas.reduce((total, h) => total + h.contestadas, 0)
 149    return new Set(horas.map((h) => h.hora)).size === horas.length
 150      && horas.every((h) => Number.isInteger(h.hora) && h.hora >= 0 && h.hora <= 23
 151        && Number.isInteger(h.llamadas) && h.llamadas >= 0
 152        && Number.isInteger(h.contestadas) && h.contestadas >= 0 && h.contestadas <= h.llamadas)
 153      && horas.reduce((total, h) => total + h.llamadas, 0) === marcador.llamadas
 154      // gestion_diaria_llamadas cuenta por hora todas las llamada_realizada;
 155      // el total para la tasa excluye numero_errado/no_es_la_persona. Admitir
 156      // esa diferencia histórica sólo dentro del número de llamadas no útiles.
 157      && contestadasPorHora >= marcador.contestadas
 158      && contestadasPorHora - marcador.contestadas <= marcador.llamadas - marcador.utiles
 159  }
```

### src/components/gestion-diaria/franja-cifras.tsx (63 líneas)
```tsx
   1  // La franja de cifras del día (diseño de Gestión Diaria, 27/09/2026): UNA
   2  // tarjeta plana con las cifras separadas por rayas finas, la etiqueta en
   3  // versalitas arriba, el número grande y su apoyo al lado. Nace para «Mi día»
   4  // del analista y la reusan supervisor y gerencia, así que no sabe de negocio:
   5  // recibe las cifras ya calculadas por el servidor.
   6  //
   7  // Escala y aire: los del diseño (Miguel, 27/09/2026: «que prevalezca el diseño,
   8  // lo limpio que se ve»). Etiqueta 11 px, número 28 px, apoyo 12 px.
   9  import type { JSX, ReactNode } from 'react'
  10  import { cn } from '@/lib/utils'
  11  
  12  export interface CifraDelDia {
  13    etiqueta: string
  14    valor: string
  15    /** Lo que debe OÍR un lector de pantalla cuando el valor es un símbolo mudo («—»). */
  16    valorAccesible?: string | undefined
  17    /** Texto o chip que acompaña al número («de 18», «hoy», el nivel). */
  18    apoyo?: ReactNode
  19    /** `alerta` pinta el número en el rojo de TEXTO: solo para «requiere intervención hoy». */
  20    tono?: 'normal' | 'alerta' | undefined
  21  }
  22  
  23  // Clases escritas enteras: Tailwind no ve las que se arman con plantillas.
  24  const COLUMNAS: Record<number, string> = {
  25    1: 'sm:grid-cols-1', 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-4', 5: 'sm:grid-cols-5', 6: 'sm:grid-cols-6',
  26  }
  27  
  28  export function FranjaCifras({ etiqueta, cifras, className }: {
  29    /** Nombre del grupo para el lector de pantalla («Tu día en cifras»). */
  30    etiqueta: string
  31    cifras: readonly CifraDelDia[]
  32    className?: string | undefined
  33  }): JSX.Element {
  34    return (
  35      // Grupo con nombre, no una región más: la pantalla ya tiene las suyas.
  36      <section role="group" aria-label={etiqueta} className={cn('rounded-2xl border border-border bg-card', className)}>
  37        <dl className={cn('grid grid-cols-2 gap-y-4 py-4', COLUMNAS[cifras.length] ?? 'sm:grid-cols-4')}>
  38          {cifras.map((c, i) => (
  39            // En el celular son 2 por fila (raya solo en la segunda); desde tablet,
  40            // raya a la izquierda de todas menos la primera.
  41            <div key={c.etiqueta} className={cn('flex min-w-0 flex-col gap-1 px-5', i % 2 === 1 ? 'border-l border-border' : i > 0 && 'sm:border-l sm:border-border')}>
  42              <dt className="text-[11px] font-extrabold uppercase tracking-[0.06em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
  43              <dd className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
  44                <span className={cn('text-[28px] font-extrabold leading-tight tracking-[-0.02em] tabular-nums', c.tono === 'alerta' ? 'text-[var(--destructive-text)]' : 'text-primary')}>
  45                  {c.valorAccesible !== undefined ? (
  46                    <>
  47                      <span aria-hidden="true">{c.valor}</span>
  48                      <span className="sr-only">{c.valorAccesible}</span>
  49                    </>
  50                  ) : c.valor}
  51                </span>
  52                {c.apoyo !== undefined && c.apoyo !== null && (
  53                  typeof c.apoyo === 'string'
  54                    ? <span className="text-xs text-[var(--muted-foreground-strong)]">{c.apoyo}</span>
  55                    : c.apoyo
  56                )}
  57              </dd>
  58            </div>
  59          ))}
  60        </dl>
  61      </section>
  62    )
  63  }
```

### src/components/gestion-diaria/barras-por-hora.tsx (71 líneas)
```tsx
   1  // Llamadas por hora, 08–20 Lima (decisión #8 de Miguel): UNA pieza para el
   2  // analista, el supervisor y gerencia (diseño del 27/09/2026). Cada columna
   3  // apila lo que contestaron (azul) debajo de lo que no (azul tenue) y lleva su
   4  // número encima: se lee sin pasar el ratón. Antes eran barras navy macizas con
   5  // el azul dentro, que no se distinguían.
   6  //
   7  // Accesible: el dibujo es decorativo (`aria-hidden`) y el dato viaja en una
   8  // lista de solo lectura para el lector de pantalla, con las horas que tuvieron
   9  // llamadas. La escala de letra es la del diseño (Miguel, 27/09/2026).
  10  import { useId, type JSX } from 'react'
  11  import { barrasPorHora, llamadasFueraDeFranja, type Marcador } from '@/lib/gestion-diaria-analista'
  12  import { cn } from '@/lib/utils'
  13  
  14  const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`
  15  
  16  export function BarrasPorHora({ porHora, titulo, apoyo, alto = 110, className }: {
  17    porHora: Marcador['por_hora']
  18    titulo: string
  19    /** Texto a la derecha del título («Última llamada 16:05»). */
  20    apoyo?: string | undefined
  21    /** Alto del dibujo en px, sin contar números ni horas. */
  22    alto?: number | undefined
  23    className?: string | undefined
  24  }): JSX.Element {
  25    const id = useId()
  26    const barras = barrasPorHora({ por_hora: porHora })
  27    const conLlamadas = barras.filter((b) => b.llamadas > 0)
  28    const fuera = llamadasFueraDeFranja({ por_hora: porHora })
  29    return (
  30      <div className={cn('space-y-2', className)}>
  31        <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
  32          <h4 id={`${id}-titulo`} className="text-[15px] font-extrabold text-primary">{titulo}</h4>
  33          {apoyo !== undefined && <p className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">{apoyo}</p>}
  34        </div>
  35        {conLlamadas.length === 0 ? (
  36          <p className="text-[13px] text-[var(--muted-foreground-strong)]">
  37            {fuera > 0 ? `Sin llamadas entre las 08 y las 20; ${plural(fuera, 'llamada', 'llamadas')} fuera de esa franja.` : 'Todavía no hay llamadas hoy.'}
  38          </p>
  39        ) : (
  40          <>
  41            <div aria-hidden="true" className="flex items-end gap-1.5" style={{ height: alto + 40 }}>
  42              {barras.map((b) => {
  43                const noContestadas = Math.round(((b.llamadas - b.contestadas) / b.maximo) * alto)
  44                const contestadas = Math.round((b.contestadas / b.maximo) * alto)
  45                return (
  46                  <div key={b.hora} className="flex h-full min-w-0 flex-1 flex-col items-center justify-end">
  47                    <span className={cn('mb-[3px] text-[11px] font-bold tabular-nums text-foreground/80', b.llamadas === 0 && 'invisible')}>{b.llamadas}</span>
  48                    {/* El tenue lleva un filo: solo, contra el blanco, apenas se veía (1,4:1). */}
  49                    <span className={cn('w-full max-w-[22px] bg-accent/25', noContestadas > 0 && 'rounded-t ring-1 ring-inset ring-accent/45')} style={{ height: noContestadas }} />
  50                    <span className={cn('w-full max-w-[22px] bg-accent', noContestadas === 0 && contestadas > 0 && 'rounded-t')} style={{ height: contestadas }} />
  51                    <span className="mt-[5px] text-[11px] tabular-nums text-[var(--muted-foreground-strong)]">{String(b.hora).padStart(2, '0')}</span>
  52                  </div>
  53                )
  54              })}
  55            </div>
  56            {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
  57            <ul role="list" aria-labelledby={`${id}-titulo`} className="sr-only">
  58              {conLlamadas.map((b) => (
  59                <li key={b.hora}>{b.hora}:00 — {plural(b.llamadas, 'llamada', 'llamadas')}, {plural(b.contestadas, 'contestada', 'contestadas')}</li>
  60              ))}
  61            </ul>
  62            <div className="flex flex-wrap items-center gap-x-3.5 gap-y-1 text-xs text-foreground/80">
  63              <span className="inline-flex items-center gap-1.5"><span aria-hidden="true" className="size-2.5 rounded-[3px] bg-accent" />Contestaron</span>
  64              <span className="inline-flex items-center gap-1.5"><span aria-hidden="true" className="size-2.5 rounded-[3px] bg-accent/25 ring-1 ring-inset ring-accent/45" />No contestaron</span>
  65              {fuera > 0 && <span>{plural(fuera, 'llamada', 'llamadas')} fuera de la franja 08–20.</span>}
  66            </div>
  67          </>
  68        )}
  69      </div>
  70    )
  71  }
```

### src/components/ui/tabs.tsx (148 líneas)
```tsx
   1  // Pestañas accesibles (patrón WAI-ARIA APG «tabs» con activación automática).
   2  // Nace en la Fase 0 de Gestión Diaria como PRIMITIVA: hasta ahora el tablist se
   3  // copiaba a mano en cada pantalla (ranking, supervisor, repartir, rentabilidad).
   4  // Contrato: flechas con vuelta, Home/End, `tabIndex` móvil (roving) y el panel
   5  // activo enlazado por `aria-labelledby`. Los objetivos miden 44–48 px en
   6  // `segmentado`; las variantes del diseño de Gestión Diaria son más compactas
   7  // (decisión de Miguel del 27/09/2026) y crecen a 44 px en pantallas táctiles.
   8  import { useId, type KeyboardEvent, type ReactNode } from 'react'
   9  import { cn } from '@/lib/utils'
  10  
  11  export interface PestanaTabs<V extends string> {
  12    valor: V
  13    etiqueta: ReactNode
  14    /** Contador o marca corta junto a la etiqueta (p. ej. «12»). */
  15    extra?: ReactNode | undefined
  16  }
  17  
  18  interface TabsProps<V extends string> {
  19    /** Nombre del grupo para el lector de pantalla (obligatorio). */
  20    etiqueta: string
  21    pestanas: readonly PestanaTabs<V>[]
  22    valor: V
  23    onCambio: (valor: V) => void
  24    /** Contenido del panel activo (un solo `tabpanel`, enlazado al tab seleccionado). */
  25    children?: ReactNode | undefined
  26    className?: string | undefined
  27    /**
  28     * `grande` para pantallas de trabajo donde la letra no puede bajar de 16 px
  29     * y el objetivo táctil es de 48 (queja de los analistas del 20/09/2026:
  30     * «muchas letras pequeñas»). El default `normal` deja intacto lo que ya
  31     * usaba esta primitiva: ranking, supervisor, repartir y rentabilidad.
  32     */
  33    tamano?: 'normal' | 'grande' | undefined
  34    /**
  35     * Aspecto del tablist (27/09/2026, diseño de Gestión Diaria). `segmentado`
  36     * es el de siempre y el default: nadie que ya lo use cambia. `subrayado`
  37     * separa las vistas de una tarjeta con una raya bajo la activa; `pastilla`
  38     * pinta filtros redondos con el activo relleno. El patrón APG no cambia:
  39     * siguen siendo `tab`/`tabpanel`, para el lector de pantalla y las pruebas.
  40     */
  41    variante?: 'segmentado' | 'subrayado' | 'pastilla' | undefined
  42    /** Clases del `tabpanel` (p. ej. para que herede la altura de la tarjeta). */
  43    clasePanel?: string | undefined
  44    /**
  45     * El panel es una parada del tabulador (default: sí, como siempre). `false`
  46     * cuando el panel ARRANCA con controles: la parada vacía sobra, y con
  47     * pestañas anidadas se suman dos antes de llegar a algo útil (a11y, 27/09).
  48     */
  49    panelEnfocable?: boolean | undefined
  50  }
  51  
  52  const CLASES_TAMANO = {
  53    normal: { tab: 'min-h-11 px-3 py-2 text-xs font-semibold', extra: 'text-[11px]' },
  54    grande: { tab: 'min-h-12 px-4 py-2 text-base font-normal', extra: 'text-base' },
  55  } as const
  56  
  57  const CLASES_VARIANTE = {
  58    segmentado: {
  59      lista: 'flex w-full flex-col rounded-xl bg-muted p-1 min-[380px]:flex-row sm:w-fit',
  60      tab: 'flex-1 justify-center rounded-lg sm:flex-none',
  61      activa: 'bg-white text-primary shadow-sm',
  62      inactiva: 'text-[var(--muted-foreground-strong)] hover:text-primary',
  63      extra: 'text-[var(--muted-foreground-strong)]',
  64    },
  65    // La raya de la activa es una sombra INTERIOR y no un borde con margen
  66    // negativo: con `overflow-x-auto` ese margen se recortaba (1 de los 2 px) y
  67    // también el foco; por lo mismo el contorno del foco va hacia adentro.
  68    subrayado: {
  69      lista: 'flex w-full gap-6 overflow-x-auto border-b border-border',
  70      tab: 'shrink-0 justify-center whitespace-nowrap !px-0.5 font-semibold focus-visible:!-outline-offset-2',
  71      activa: 'font-bold text-[var(--accent-press)] shadow-[inset_0_-2px_0_var(--color-accent)]',
  72      inactiva: 'text-[var(--muted-foreground-strong)] hover:text-primary',
  73      extra: '',
  74    },
  75    pastilla: {
  76      lista: 'flex w-full flex-wrap gap-2',
  77      tab: 'shrink-0 justify-center whitespace-nowrap rounded-full border font-semibold',
  78      activa: 'border-accent bg-accent text-accent-foreground',
  79      inactiva: 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-border-strong hover:text-primary',
  80      extra: '',
  81    },
  82  } as const
  83  
  84  // Ids del tab y del panel de un valor (interno: el panel activo vive dentro del componente).
  85  function idsDeTab(idBase: string, valor: string): { tab: string; panel: string } {
  86    return { tab: `${idBase}-tab-${valor}`, panel: `${idBase}-panel-${valor}` }
  87  }
  88  
  89  export function Tabs<V extends string>({ etiqueta, pestanas, valor, onCambio, children, className, tamano = 'normal', variante = 'segmentado', clasePanel, panelEnfocable = true }: TabsProps<V>) {
  90    const medidas = CLASES_TAMANO[tamano]
  91    const aspecto = CLASES_VARIANTE[variante]
  92    const idAuto = useId()
  93    const base = `tabs${idAuto.replaceAll(':', '')}`
  94    const valores = pestanas.map((p) => p.valor)
  95  
  96    const alTecla = (evento: KeyboardEvent<HTMLButtonElement>) => {
  97      const indice = valores.indexOf(valor)
  98      if (indice < 0 || valores.length === 0) return
  99      const siguiente = evento.key === 'ArrowRight' ? valores[(indice + 1) % valores.length]
 100        : evento.key === 'ArrowLeft' ? valores[(indice + valores.length - 1) % valores.length]
 101        : evento.key === 'Home' ? valores[0]
 102        : evento.key === 'End' ? valores[valores.length - 1]
 103        : undefined
 104      if (siguiente === undefined) return
 105      evento.preventDefault()
 106      onCambio(siguiente)
 107      document.getElementById(idsDeTab(base, siguiente).tab)?.focus()
 108    }
 109  
 110    const activo = idsDeTab(base, valor)
 111    return (
 112      <div className={cn('space-y-3', className)}>
 113        <div role="tablist" aria-label={etiqueta} className={aspecto.lista}>
 114          {pestanas.map((p) => {
 115            const ids = idsDeTab(base, p.valor)
 116            const seleccionada = p.valor === valor
 117            return (
 118              <button
 119                key={p.valor}
 120                id={ids.tab}
 121                type="button"
 122                role="tab"
 123                aria-selected={seleccionada}
 124                aria-controls={ids.panel}
 125                tabIndex={seleccionada ? 0 : -1}
 126                onClick={() => onCambio(p.valor)}
 127                onKeyDown={alTecla}
 128                className={cn(
 129                  'inline-flex min-w-0 cursor-pointer items-center gap-1.5 transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40',
 130                  medidas.tab,
 131                  aspecto.tab,
 132                  seleccionada ? aspecto.activa : aspecto.inactiva,
 133                )}
 134              >
 135                {p.etiqueta}
 136                {p.extra !== undefined && <span className={cn('tabular-nums font-bold', aspecto.extra, medidas.extra)}>{p.extra}</span>}
 137              </button>
 138            )
 139          })}
 140        </div>
 141        {children !== undefined && (
 142          <div role="tabpanel" id={activo.panel} aria-labelledby={activo.tab} tabIndex={panelEnfocable ? 0 : undefined} className={cn('focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40', clasePanel)}>
 143            {children}
 144          </div>
 145        )}
 146      </div>
 147    )
 148  }
```

### src/components/ui/avatar.tsx (116 líneas)
```tsx
   1  import type { JSX } from 'react'
   2  import { cn } from '@/lib/utils'
   3  import { iniciales } from '@/lib/format'
   4  import type { Genero } from '@/lib/tipos'
   5  
   6  // Siluetas humanas — diseño Claude Design v2 (Avatares Silueta v2). Todas
   7  // `fill="currentColor"`, viewBox 0 0 24 24, fondo transparente → se tiñen por CSS.
   8  // Hay 3 PEINADOS por género: se elige uno por hash del nombre, así cada persona
   9  // tiene su variante y no se ven todas iguales, sin perder la lectura de género.
  10  const SILUETAS: Record<Genero, string[][]> = {
  11    F: [
  12      // ondas a los hombros
  13      [
  14        'M12 2.8c-3.5 0-5.8 2.5-5.8 5.9 0 2.2-.4 3.9-1.2 5.4-.4.8 0 1.8 1 1.9 1.5.2 2.8-.1 3.8-.8.7.3 1.4.5 2.2.5s1.5-.2 2.2-.5c1 .7 2.3 1 3.8.8 1-.1 1.4-1.1 1-1.9-.8-1.5-1.2-3.2-1.2-5.4 0-3.4-2.3-5.9-5.8-5.9z',
  15        'M12 15.1c-3 0-5.6 1-6.9 2.6-.7.9-.1 2.2 1.1 2.2h11.6c1.2 0 1.8-1.3 1.1-2.2-1.3-1.6-3.9-2.6-6.9-2.6z',
  16      ],
  17      // bob
  18      [
  19        'M12 3c-3.3 0-5.5 2.4-5.5 5.6 0 1.6-.15 2.9-.5 4.1-.3 1 .45 2 1.5 2h9c1.05 0 1.8-1 1.5-2-.35-1.2-.5-2.5-.5-4.1C17.5 5.4 15.3 3 12 3z',
  20        'M12 14c-4.5 0-7.6 2.3-7.6 5.4v.2c0 .8.6 1.4 1.4 1.4h12.4c.8 0 1.4-.6 1.4-1.4v-.2c0-3.1-3.1-5.4-7.6-5.4z',
  21      ],
  22      // moño / recogido
  23      [
  24        'M12 1.6a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z',
  25        'M12 4.4a3.7 3.7 0 1 1 0 7.4 3.7 3.7 0 0 1 0-7.4z',
  26        'M12 14.2c-4.4 0-7.4 2.3-7.4 5.3v.2c0 .8.6 1.4 1.4 1.4h12c.8 0 1.4-.6 1.4-1.4v-.2c0-3-3-5.3-7.4-5.3z',
  27      ],
  28    ],
  29    M: [
  30      // corto clásico (con cuello)
  31      [
  32        'M12 3.7a3.9 3.9 0 1 1 0 7.8 3.9 3.9 0 0 1 0-7.8z',
  33        'M10.6 11v2.1c-3.3.5-5.9 2.1-6.7 4.3-.4 1 .3 2.1 1.4 2.1h13.4c1.1 0 1.8-1.1 1.4-2.1-.8-2.2-3.4-3.8-6.7-4.3V11c-.45.19-.92.29-1.4.29-.48 0-.95-.1-1.4-.29z',
  34      ],
  35      // con volumen / texturizado
  36      [
  37        'M12 2.7c-2.9 0-5 2-5.2 4.8 0 .4.3.6.7.5 1.6-.5 4-1.4 5.3-2.8.9.9 2.6 1.9 4.4 2.4.4.1.8-.2.7-.6C17.5 4.5 14.9 2.7 12 2.7z',
  38        'M12 4.4a3.7 3.7 0 1 1 0 7.4 3.7 3.7 0 0 1 0-7.4z',
  39        'M10.6 11.2v1.9c-3.3.5-5.9 2.1-6.7 4.3-.4 1 .3 2.1 1.4 2.1h13.4c1.1 0 1.8-1.1 1.4-2.1-.8-2.2-3.4-3.8-6.7-4.3v-1.9c-.45.19-.92.29-1.4.29-.48 0-.95-.1-1.4-.29z',
  40      ],
  41      // rapado (hombros anchos)
  42      [
  43        'M12 3.7a3.9 3.9 0 1 1 0 7.8 3.9 3.9 0 0 1 0-7.8z',
  44        'M12 13.6c-4.6 0-7.8 2.4-7.8 5.6v.2c0 .8.6 1.4 1.4 1.4h12.8c.8 0 1.4-.6 1.4-1.4v-.2c0-3.2-3.2-5.6-7.8-5.6z',
  45      ],
  46    ],
  47  }
  48  
  49  const COLOR_GENERO: Record<Genero, string> = { F: '#7c3aed', M: '#2563eb' }
  50  
  51  /** Hash estable del nombre → índice de peinado dentro del set del género. */
  52  function indicePeinado(nombre: string | null | undefined, n: number): number {
  53    let h = 0
  54    for (const c of nombre ?? '') h = (h * 31 + c.charCodeAt(0)) >>> 0
  55    return n > 0 ? h % n : 0
  56  }
  57  
  58  const BASE = 'inline-flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-full'
  59  
  60  /**
  61   * Avatar de persona o de equipo.
  62   * - Con género conocido (F/M) → silueta HUMANA tinteada por género, con su peinado
  63   *   por hash del nombre.
  64   * - Sin género (null o prop ausente) → INICIALES: distinguen a cada persona cuando
  65   *   no hay dato (mejor que una silueta neutra idéntica para todos). Cuando el campo
  66   *   género exista en la BD, cada lead pasa por sí solo a su silueta.
  67   */
  68  export function Avatar({
  69    nombre,
  70    genero,
  71    color = 'var(--accent)',
  72    relleno = false,
  73    className,
  74  }: {
  75    nombre: string | null | undefined
  76    genero?: Genero | null
  77    color?: string | undefined
  78    /**
  79     * Iniciales en blanco sobre el color pleno: marca a la persona ELEGIDA en una
  80     * lista (Gestión Diaria, 27/09/2026). Nunca va sola: la fila lo dice también
  81     * con `aria-current` y con texto.
  82     */
  83    relleno?: boolean | undefined
  84    className?: string | undefined
  85  }): JSX.Element {
  86    // Silueta SOLO con género conocido; sin dato (null/ausente) → iniciales.
  87    if (genero === 'F' || genero === 'M') {
  88      const c = COLOR_GENERO[genero]
  89      const set = SILUETAS[genero]
  90      const paths = set[indicePeinado(nombre, set.length)] ?? []
  91      return (
  92        <span
  93          className={cn(BASE, className)}
  94          style={{ background: `color-mix(in srgb, ${c} 14%, transparent)`, color: c }}
  95          aria-hidden
  96        >
  97          <svg viewBox="0 0 24 24" fill="currentColor" className="size-full" aria-hidden>
  98            {paths.map((d, i) => (
  99              <path key={i} d={d} />
 100            ))}
 101          </svg>
 102        </span>
 103      )
 104    }
 105  
 106    // Modo iniciales (equipo, o cuando no aplica el género de una persona).
 107    return (
 108      <span
 109        className={cn(BASE, 'text-[11px] font-bold', className)}
 110        style={relleno ? { background: color, color: '#fff' } : { background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
 111        aria-hidden
 112      >
 113        {iniciales(nombre)}
 114      </span>
 115    )
 116  }
```

### src/components/app/actividad-visual.ts (36 líneas)
```ts
   1  // Cómo se VE una gestión del lead: su icono y el «hace X» del timeline. Una sola
   2  // definición para la ficha, el directorio y «Ahora» de Gestión Diaria (antes el
   3  // mapa de iconos vivía copiado en la ficha y en el directorio).
   4  import type { LucideIcon } from 'lucide-react'
   5  import { ArrowRightLeft, BadgeCheck, CalendarCheck, MessageCircle, MessageSquare, PhoneCall, PhoneMissed, StickyNote, Users } from 'lucide-react'
   6  import { fmtFecha } from '@/lib/format'
   7  import type { TipoActividad } from '@/lib/tipos'
   8  
   9  export const ICONO_ACTIVIDAD: Record<TipoActividad, LucideIcon> = {
  10    llamada_realizada: PhoneCall,
  11    llamada_no_contestada: PhoneMissed,
  12    whatsapp_enviado: MessageCircle,
  13    whatsapp_recibido: MessageSquare,
  14    reunion_realizada: CalendarCheck,
  15    nota: StickyNote,
  16    cambio_etapa: ArrowRightLeft,
  17    reasignacion: Users,
  18    conversion: BadgeCheck,
  19  }
  20  
  21  /** "hace X" legible; para fechas viejas cae a fmtFecha. Formato propio del timeline
  22   * (min/h/'ayer'), más fino que haceTexto() de lib/inteligencia — NO sustituir.
  23   * `ahora` viene del reloj vivo useAhora() para que refresque sin remontar. */
  24  export function haceRelativo(iso: string, ahora: number): string {
  25    const ms = ahora - new Date(iso).getTime()
  26    if (!Number.isFinite(ms) || ms < 0) return fmtFecha(iso)
  27    const min = Math.floor(ms / 60_000)
  28    if (min < 1) return 'ahora'
  29    if (min < 60) return `hace ${min} min`
  30    const h = Math.floor(min / 60)
  31    if (h < 24) return `hace ${h} h`
  32    const d = Math.floor(h / 24)
  33    if (d === 1) return 'ayer'
  34    if (d < 7) return `hace ${d} d`
  35    return fmtFecha(iso)
  36  }
```

### e2e/gestion-diaria-equipo.spec.ts (311 líneas)
```ts
   1  import { expect, test } from '@playwright/test'
   2  import { writeFile } from 'node:fs/promises'
   3  import { entrarDemo, leadReal, loginReal, montarBackendReal, UID } from './_helpers'
   4  import { diaEquipoPrueba, filaEquipoPrueba } from '../src/lib/gestion-diaria-equipo.fixture'
   5  import { fechaLima } from '../src/lib/agenda-derivada'
   6  
   7  test('Supervisor: roster demo, búsqueda y detalle con texto de al menos 16 px', async ({ page }, info) => {
   8    await page.setViewportSize({ width: 1512, height: 805 })
   9    await entrarDemo(page, 'Supervisor')
  10    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
  11    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  12    const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  13    const tabla = vista.getByRole('table')
  14    await expect(tabla).toBeVisible()
  15    const analistas = tabla.locator('tr[data-analista]')
  16    expect(await analistas.count()).toBeGreaterThan(0)
  17    const nombre = (await analistas.first().getByRole('rowheader').getByRole('button').first().textContent())!
  18    await vista.getByRole('searchbox').fill(nombre)
  19    await expect(analistas).toHaveCount(1)
  20    // El contorno debe sobrevivir al alto contraste: el ring de box-shadow no.
  21    await page.emulateMedia({ forcedColors: 'active' })
  22    await page.keyboard.press('Tab')
  23    for (const control of [tabla.getByRole('button', { name: `Seleccionar a ${nombre}` })]) {
  24      await control.focus()
  25      await expect(control).toBeFocused()
  26      await expect(control).not.toHaveCSS('outline-style', 'none')
  27      expect(await control.evaluate((el) => Number.parseFloat(getComputedStyle(el).outlineWidth))).toBeGreaterThanOrEqual(2)
  28    }
  29    await page.emulateMedia({ forcedColors: 'none' })
  30    await tabla.getByRole('button', { name: /^Seleccionar a / }).click()
  31    await expect(vista.getByText('Llamadas por lead', { exact: true })).toBeVisible()
  32    const chicos = await vista.evaluate((raiz) => Array.from(raiz.querySelectorAll<HTMLElement>('*')).filter((el) =>
  33      el.getClientRects().length > 0 && Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim())
  34        && Number.parseFloat(getComputedStyle(el).fontSize) < 16).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
  35    expect(chicos).toEqual([])
  36    await page.evaluate(() => document.fonts.ready)
  37    expect(await page.evaluate(() => [...document.fonts].some((f) => f.family.includes('Jakarta') && f.status === 'loaded'))).toBe(true)
  38    const abrir = vista.getByRole('button', { name: `Ir al detalle de ${nombre}` })
  39    await abrir.focus()
  40    await page.keyboard.press('Enter')
  41    await expect(page.getByRole('heading', { name: `Detalle de ${nombre}`, exact: true })).toBeFocused()
  42    await page.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
  43    await expect(tabla.getByRole('button', { name: `Seleccionar a ${nombre}` })).toBeFocused()
  44    await vista.getByRole('heading', { level: 2 }).scrollIntoViewIfNeeded()
  45    await page.screenshot({ path: info.outputPath('equipo-escritorio.png'), fullPage: true })
  46    await page.setViewportSize({ width: 390, height: 844 })
  47    await vista.getByRole('heading', { level: 2 }).scrollIntoViewIfNeeded()
  48    await expect(vista.getByRole('searchbox')).toBeVisible()
  49    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  50    await page.screenshot({ path: info.outputPath('equipo-movil.png'), fullPage: true })
  51  })
  52  
  53  test('Ruta real con store vacío: cero actividad, 270 pendientes, error y revocación', async ({ page }, info) => {
  54    await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
  55    const d = diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO',
  56      tareas_pendientes: 270, tareas_vencidas: 270, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })])
  57    d.dia = fechaLima(Date.now()); d.supervisor_id = UID
  58    d.generado_en = new Date().toISOString(); d.pendientes_al = d.generado_en
  59    let estado: 'ok' | 'error' | 'revocado' = 'ok'
  60    await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', async (route) => {
  61      expect(route.request().postDataJSON()).toEqual({ p_dia: d.dia, p_supervisor_id: UID })
  62      if (estado === 'error') return route.fulfill({ status: 400, json: { code: 'XX000', message: 'Error controlado de lectura' } })
  63      if (estado === 'revocado') return route.fulfill({ status: 403, json: { code: '42501', message: 'Acceso revocado' } })
  64      return route.fulfill({ json: d })
  65    })
  66    await loginReal(page)
  67    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
  68    const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
  69    await expect(vista.getByText('ANA PÉREZ', { exact: true })).toBeVisible()
  70    await expect(vista.getByRole('cell', { name: '270', exact: true }).first()).toBeVisible()
  71    await vista.getByRole('button', { name: /Con atención/ }).click()
  72    await expect(vista.getByText('ANA PÉREZ', { exact: true })).toHaveCount(0)
  73    await expect(vista.getByText('BRUNO', { exact: true })).toBeVisible()
  74    await page.screenshot({ path: info.outputPath('equipo-ruta-real.png'), fullPage: true })
  75    estado = 'error'
  76    await vista.getByRole('button', { name: 'Actualizar', exact: true }).click()
  77    await expect(vista.getByRole('alert')).toContainText('no significa que el equipo no tenga actividad')
  78    await expect(vista.getByRole('table')).toHaveCount(0)
  79    estado = 'ok'
  80    await vista.getByRole('button', { name: 'Reintentar', exact: true }).click()
  81    await expect(vista.getByRole('table')).toBeVisible()
  82    estado = 'revocado'
  83    await vista.getByRole('button', { name: 'Actualizar', exact: true }).click()
  84    await expect(vista.getByRole('alert')).toContainText('Ya no tienes autorización')
  85    await expect(vista.getByRole('table')).toHaveCount(0)
  86  })
  87  
  88  test('F4.2: detalle → llamadas → ficha fuera del boot → regreso; paginación revocada', async ({ page }, info) => {
  89    await page.setViewportSize({ width: 1512, height: 805 })
  90    const hoy = fechaLima(Date.now())
  91    const lead = leadReal({ nombre_completo: 'LEAD FUERA DE LA CACHÉ', fueraDelBoot: true, asignado_supervisor_id: UID })
  92    const backend = await montarBackendReal(page, { rolCrm: 'supervisor', leads: [lead], tareas: [] })
  93    const fila = filaEquipoPrueba({ analista_id: 'vend-1', nombre_completo: 'Analista Real Uno', gestiones_hoy: 26,
  94      minutos_sin_llamar: 60, llamadas_por_lead: 26, ultima_gestion_en: `${hoy}T15:25:00Z`,
  95      marcador: { ...filaEquipoPrueba().marcador, llamadas: 26, contestadas: 26, utiles: 26, tasa_contacto_pct: 100, nivel: 'bien',
  96        leads_tocados: 1, primera_llamada_en: `${hoy}T15:00:00Z`, ultima_llamada_en: `${hoy}T15:25:00Z`,
  97        por_hora: [{ hora: 10, llamadas: 26, contestadas: 26 }] } })
  98    const equipo = { ...diaEquipoPrueba([fila]), dia: hoy, supervisor_id: UID }
  99    await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', (route) => route.fulfill({ json: equipo }))
 100    let revocado = false
 101    const items = Array.from({ length: 26 }, (_, i) => ({
 102      id: `gestion-${i}`, lead_id: lead.id, lead_nombre: lead.nombre_completo, lead_etapa: 'nuevo', etapa_en_ese_momento: 'nuevo',
 103      tipo: 'llamada_realizada', detalle: `Conversación completa ${i}: solicita revisar el seguimiento.`, metadata: { resultado: 'volver_a_llamar' },
 104      creado_por: 'vend-1', autor_nombre: 'Analista Real Uno', creado_en: `${hoy}T15:${String(25 - i).padStart(2, '0')}:00.000Z`,
 105    }))
 106    await page.route('**/rest/v1/rpc/registro_actividad_fn', async (route) => {
 107      const pedido = route.request().postDataJSON()
 108      expect(pedido).toMatchObject({ p_desde: hoy, p_hasta: hoy, p_analista_ids: ['vend-1'], p_limite: 26 })
 109      // Main (#80) omite p_tipos en «Todo»; cuando se filtra, exige ambos tipos.
 110      if (pedido.p_tipos !== undefined) expect(pedido.p_tipos).toEqual(['llamada_realizada', 'llamada_no_contestada'])
 111      if (revocado) return route.fulfill({ status: 403, json: { code: '42501', message: 'Acceso revocado' } })
 112      return route.fulfill({ json: { version: 1, generado_en: `${hoy}T18:00:00Z`, desde: hoy, hasta: hoy, zona: 'America/Lima', limite: 26,
 113        items: pedido.p_antes_de ? [items[25]] : items } })
 114    })
 115    await loginReal(page)
 116    await page.getByRole('button', { name: 'Gestión Diaria' }).click()
 117    const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
 118    await vista.getByRole('searchbox').fill('Real Uno')
 119    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
 120    await expect(vista).toHaveAttribute('data-estrecho', 'false')
 121    const abrirDetalle = vista.getByRole('button', { name: 'Seleccionar a Analista Real Uno', exact: true })
 122    const detalle = page.getByRole('region', { name: 'Detalle de Analista Real Uno', exact: true })
 123    await abrirDetalle.focus()
 124    await page.keyboard.press('Enter')
 125    await expect(abrirDetalle).toHaveAttribute('aria-current', 'true')
 126    await expect(abrirDetalle).toBeFocused()
 127    await expect(detalle).toBeVisible()
 128    await detalle.getByText('Ver cifras por hora').click()
 129    await expect(detalle.getByText('De 10:00 a 10:59: 26 llamadas, 26 contestadas')).toBeVisible()
 130    await detalle.screenshot({ path: info.outputPath('detalle-horario.png') })
 131    const abrirRegistro = detalle.getByRole('button', { name: 'Ver llamadas del día de Analista Real Uno' })
 132    await abrirRegistro.focus()
 133    await page.keyboard.press('Enter')
 134    const registro = page.getByRole('region', { name: 'Registro seleccionado', exact: true })
 135    await expect(registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true })).toBeFocused()
 136    await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
 137    await expect(registro.getByRole('combobox', { name: 'Analista', exact: true })).toHaveCount(0)
 138    await registro.getByRole('tab', { name: 'Todo', exact: true }).click()
 139    await detalle.getByRole('tab', { name: 'Resumen', exact: true }).click()
 140    await abrirRegistro.click()
 141    await expect(registro.getByRole('tab', { name: 'Llamadas', exact: true })).toHaveAttribute('aria-selected', 'true')
 142    await detalle.getByRole('button', { name: 'Ampliar panel' }).click()
 143    await expect(page.getByRole('dialog', { name: 'Detalle de Analista Real Uno' })).toBeVisible()
 144    const enlace = registro.getByRole('button', { name: lead.nombre_completo }).first()
 145    const cargasAntes = backend.llamadas.getLeads
 146    await enlace.focus()
 147    await page.keyboard.press('Enter')
 148    await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toBeVisible()
 149    expect(backend.llamadas.getLeads).toBeGreaterThan(cargasAntes)
 150    await page.keyboard.press('Escape')
 151    await expect(enlace).toBeFocused()
 152    await expect(page.getByRole('dialog', { name: 'Detalle de Analista Real Uno' })).toBeVisible()
 153    await detalle.getByRole('button', { name: 'Restaurar panel' }).click()
 154    await expect(detalle.getByRole('button', { name: 'Ampliar panel' })).toBeFocused()
 155    await expect(registro.getByRole('listitem')).toHaveCount(25)
 156    await expect(registro.getByText('Conversación completa 0: solicita revisar el seguimiento.')).toBeVisible()
 157    // La ficha vuelve a consultar RLS aun si el lead ya fue hidratado.
 158    backend.leads = []
 159    await enlace.click()
 160    await expect(page.getByText('La oportunidad ya no está disponible en tu cartera.')).toBeVisible()
 161    await expect(page.getByRole('dialog', { name: lead.nombre_completo })).toHaveCount(0)
 162    await registro.getByRole('button', { name: 'Ver más' }).click()
 163    await expect(registro.getByRole('listitem')).toHaveCount(26)
 164    await registro.getByRole('combobox', { name: 'Etapa actual del lead' }).focus()
 165    await page.setViewportSize({ width: 1512, height: 805 })
 166    await expect(page.getByRole('dialog', { name: 'Detalle de Analista Real Uno' })).toHaveCount(0)
 167    await expect(registro.getByRole('combobox', { name: 'Etapa actual del lead' })).toBeFocused()
 168    await expect(registro.getByRole('listitem')).toHaveCount(26)
 169    await page.setViewportSize({ width: 390, height: 844 })
 170    await registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true }).scrollIntoViewIfNeeded()
 171    await page.screenshot({ path: info.outputPath('registro-detalle.png') })
 172    await page.setViewportSize({ width: 390, height: 844 })
 173    await expect(registro.getByRole('listitem')).toHaveCount(26)
 174    await registro.getByRole('heading', { name: 'Registro de Analista Real Uno', exact: true }).scrollIntoViewIfNeeded()
 175    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
 176    await page.screenshot({ path: info.outputPath('registro-detalle-movil.png') })
 177    const pestañas = registro.getByRole('tablist', { name: 'Tipo de actividad' })
 178    await pestañas.scrollIntoViewIfNeeded()
 179    const etiquetasRecortadas = await pestañas.getByRole('tab').evaluateAll((botones) => botones.filter((boton) => {
 180      const texto = document.createRange()
 181      texto.selectNodeContents(boton)
 182      const caja = boton.getBoundingClientRect()
 183      const etiqueta = texto.getBoundingClientRect()
 184      return etiqueta.left < caja.left || etiqueta.right > caja.right
 185    }).map((boton) => boton.textContent))
 186    expect(etiquetasRecortadas).toEqual([])
 187    await page.screenshot({ path: info.outputPath('registro-actividad-movil.png') })
 188    await page.setViewportSize({ width: 1280, height: 720 })
 189    const pequenos = await registro.evaluate((raiz) => Array.from(raiz.querySelectorAll<HTMLElement>('*')).filter((el) =>
 190      el.getClientRects().length > 0 && Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim())
 191        && Number.parseFloat(getComputedStyle(el).fontSize) < 16).map((el) => `${el.tagName}: ${el.textContent?.slice(0, 60)}`))
 192    expect(pequenos).toEqual([])
 193    revocado = true
 194    await registro.getByRole('button', { name: 'Actualizar', exact: true }).click()
 195    await expect(registro.getByRole('alert')).toContainText('Ya no tienes autorización')
 196    await expect(registro.getByRole('listitem')).toHaveCount(0)
 197    await detalle.getByRole('button', { name: 'Cerrar detalle', exact: true }).click()
 198    await expect(abrirDetalle).toBeFocused()
 199    await expect(vista.getByRole('searchbox')).toHaveValue('Real Uno')
 200    await expect(abrirDetalle).not.toHaveAttribute('aria-current')
 201  })
 202  
 203  for (const medida of [{ width: 1512, height: 805, filas: 10 }, { width: 1366, height: 768, filas: 9 }]) {
 204    test(`H2 densidad ${medida.width}: ${medida.filas} filas, seis columnas y texto completo`, async ({ page }, info) => {
 205      await page.setViewportSize(medida)
 206      await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
 207      const nombres = ['ANA PÉREZ', 'BRUNO DÍAZ', 'CARLA LEÓN', 'DAVID ROJAS', 'ELENA PAZ', 'FABIO VEGA', 'GINA SOTO', 'HUGO RUIZ', 'INES TORRES', 'JOSÉ LUNA', 'KARLA SOL']
 208      const d = diaEquipoPrueba(nombres.map((nombre, i) => filaEquipoPrueba({ analista_id: `a-${i}`, nombre_completo: nombre,
 209        tareas_pendientes: 270, tareas_vencidas: 108, requiere_atencion: true, motivos_atencion: ['tarea_vencida'],
 210        gestiones_hoy: 2, marcador: { ...filaEquipoPrueba().marcador, llamadas: 2, utiles: 2, contestadas: 1, tasa_contacto_pct: 50, por_hora: [{ hora: 10, llamadas: 2, contestadas: 1 }] },
 211      })))
 212      d.dia = fechaLima(Date.now()); d.supervisor_id = UID
 213      await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', (route) => route.fulfill({ json: d }))
 214      await loginReal(page)
 215      await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
 216      await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
 217      await page.mouse.move(900, 90)
 218      const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
 219      await expect(vista).toHaveAttribute('data-estrecho', 'false')
 220      await page.evaluate(() => document.fonts.ready)
 221      const primera = vista.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' })
 222      await primera.click()
 223      await expect(primera).toBeFocused()
 224      const geometria = await vista.evaluate((nodo) => {
 225        const tabla = nodo.querySelector('.gd-tabla-scroll')!
 226        const caja = tabla.getBoundingClientRect()
 227        const filas = [...tabla.querySelectorAll<HTMLElement>('tr[data-analista]')].map((f) => f.getBoundingClientRect().toJSON())
 228        const fuentesPequenas = [...nodo.querySelectorAll<HTMLElement>('*')].filter((e) => e.getClientRects().length && !e.closest('[hidden],.sr-only')
 229          && [...e.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.trim()) && parseFloat(getComputedStyle(e).fontSize) < 16).map((e) => e.textContent)
 230        const controlesBajos = [...nodo.querySelectorAll<HTMLElement>('button,input,select')].filter((e) => e.getClientRects().length && e.getBoundingClientRect().height < 43.9).map((e) => e.textContent)
 231        const contenedor = nodo.closest<HTMLElement>('[data-vista-scroll]')!
 232        return { viewport: [innerWidth, innerHeight], ancho: nodo.clientWidth, tabla: caja.toJSON(), filas,
 233          completas: filas.filter((f) => f.bottom <= caja.bottom + .5).length, fuentesPequenas, controlesBajos,
 234          scrollPagina: contenedor.scrollHeight - contenedor.clientHeight, overflowTabla: tabla.scrollWidth - tabla.clientWidth }
 235      })
 236      expect(geometria.completas).toBeGreaterThanOrEqual(medida.filas)
 237      expect(geometria.filas.slice(0, medida.filas).every((f) => Math.abs(f.height - 44) < .5)).toBe(true)
 238      expect(geometria.fuentesPequenas).toEqual([])
 239      expect(geometria.controlesBajos).toEqual([])
 240      expect(geometria.scrollPagina).toBeLessThanOrEqual(1)
 241      expect(geometria.overflowTabla).toBe(0)
 242      await writeFile(info.outputPath('medidas-h2.json'), JSON.stringify(geometria, null, 2))
 243      await info.attach('medidas-h2.json', { body: JSON.stringify(geometria, null, 2), contentType: 'application/json' })
 244      await page.screenshot({ path: info.outputPath(`horizontal-${medida.width}.png`) })
 245      // Las filas restantes siguen alcanzables en su región, sin mover la página.
 246      await vista.getByRole('button', { name: 'Seleccionar a KARLA SOL' }).focus()
 247      await expect(vista.getByRole('button', { name: 'Seleccionar a KARLA SOL' })).toBeInViewport()
 248      if (medida.width === 1512) {
 249        const indicadores = await vista.getByRole('group', { name: 'Resumen del equipo' }).textContent()
 250        await vista.getByRole('searchbox').fill('KARLA')
 251        await expect(vista.getByRole('group', { name: 'Resumen del equipo' })).toHaveText(indicadores!)
 252        await expect(page.getByText('La selección está fuera de los filtros.')).toBeVisible()
 253        await page.getByRole('button', { name: 'Limpiar filtros' }).click()
 254        await page.setViewportSize({ width: 756, height: 402 }) // espacio CSS de 1512×805 al 200 %
 255        const dialogo = page.getByRole('dialog', { name: 'Detalle de ANA PÉREZ' })
 256        await expect(dialogo).toBeVisible()
 257        await expect(dialogo.getByRole('heading', { name: 'Detalle de ANA PÉREZ', exact: true }).last()).toBeFocused()
 258        await page.screenshot({ path: info.outputPath('horizontal-200-por-ciento.png') })
 259        await page.keyboard.press('Escape')
 260        await expect(dialogo).toHaveCount(0)
 261        await page.setViewportSize({ width: 390, height: 844 })
 262        await vista.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' }).click()
 263        await expect(dialogo).toBeVisible()
 264        await dialogo.getByRole('tab', { name: 'Pendientes', exact: true }).click()
 265        await expect(dialogo.getByText('270', { exact: true })).toBeVisible()
 266        expect(await dialogo.evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true)
 267        await page.screenshot({ path: info.outputPath('horizontal-movil.png') })
 268        await page.keyboard.press('Escape')
 269        await expect(dialogo).toHaveCount(0)
 270        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
 271      }
 272    })
 273  }
 274  
 275  test('H2 nombre largo, varios motivos, control de foco y cambio de ruta', async ({ page }, info) => {
 276    await page.setViewportSize({ width: 1512, height: 805 })
 277    await montarBackendReal(page, { rolCrm: 'supervisor', leads: [], tareas: [] })
 278    const nombre = 'MARÍA ALEJANDRA DE LOS ÁNGELES FERNÁNDEZ DEL CASTILLO'
 279    const d = diaEquipoPrueba([filaEquipoPrueba({ analista_id: 'larga', nombre_completo: nombre,
 280      tareas_pendientes: 999, tareas_vencidas: 321, primer_intento_vencido: 8, datos_incompletos: 2,
 281      requiere_atencion: true, motivos_atencion: ['tarea_vencida', 'primer_intento_vencido', 'datos_incompletos'] })])
 282    d.dia = fechaLima(Date.now()); d.supervisor_id = UID
 283    await page.route('**/rest/v1/rpc/gestion_diaria_equipo_fn', (route) => route.fulfill({ json: d }))
 284    await loginReal(page)
 285    await page.getByRole('button', { name: 'Ocultar menú', exact: true }).click()
 286    await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
 287    await page.mouse.move(900, 90)
 288    const vista = page.getByRole('region', { name: 'Mi equipo hoy', exact: true })
 289    await expect(vista).toHaveAttribute('data-estrecho', 'false')
 290    const seleccion = vista.getByRole('button', { name: `Seleccionar a ${nombre}` })
 291    await seleccion.click()
 292    await expect(seleccion).toHaveText(nombre)
 293    const panel = page.getByRole('region', { name: `Detalle de ${nombre}` })
 294    for (const motivo of ['Tareas vencidas', 'Primer intento fuera de plazo', 'Datos pendientes de revisar']) await expect(panel.getByText(motivo, { exact: true })).toBeVisible()
 295    expect(await seleccion.evaluate((e) => e.scrollHeight <= e.clientHeight && e.scrollWidth <= e.clientWidth)).toBe(true)
 296    await panel.getByRole('button', { name: 'Ampliar panel' }).click()
 297    const dialogo = page.getByRole('dialog', { name: `Detalle de ${nombre}` })
 298    await expect(dialogo).toBeVisible()
 299    await panel.getByRole('button', { name: 'Cerrar detalle' }).focus()
 300    for (let n = 0; n < 18; n++) {
 301      await page.keyboard.press('Tab')
 302      expect(await dialogo.evaluate((e) => e.contains(document.activeElement))).toBe(true)
 303    }
 304    await page.screenshot({ path: info.outputPath('horizontal-nombre-largo.png') })
 305    await page.keyboard.press('Escape')
 306    await expect(dialogo).toHaveCount(0)
 307    await expect(seleccion).toBeFocused()
 308    await page.getByRole('button', { name: 'Agenda', exact: true }).click()
 309    await page.getByRole('button', { name: 'Gestión Diaria', exact: true }).click()
 310    await expect(page.getByText('Selecciona un analista de la tabla para consultar su día.')).toBeVisible()
 311  })
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
