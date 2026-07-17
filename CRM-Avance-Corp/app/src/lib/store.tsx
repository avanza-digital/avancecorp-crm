// Store DEMO del CRM (F1b) — fuente de verdad de leads/actividades en memoria,
// sembrada desde lib/demo.ts y persistida en sessionStorage. JAMÁS escribe en
// Supabase. Write-gating con doble defensa: la UI oculta acciones y el store
// re-valida CADA mutación (toast.error + no-op si el rol no puede escribir).
// Debe montarse DENTRO de AuthProvider (usa useAuth para el gating y el autor).
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type JSX,
  type ReactNode,
} from 'react'
import { toast } from 'sonner'
import { useAuth } from './auth-context'
import { can, puedeEscribir } from './roles'
import {
  ETAPA_INFO,
  MOTIVOS_DESCARTE,
  TERMINALES_K,
  TIPOS_AUTO_K,
  type Actividad,
  type CategoriaInteres,
  type EtapaActiva,
  type Lead,
  type Miembro,
  type MotivoDescarte,
  type Origen,
  type TipoActividad,
  type TipoActividadManual,
} from './tipos'
import { esAbierto } from './inteligencia'
import type { Moneda } from './format'
import { DEMO_HABILITADO } from './config'
import { validarCamposLead, type CampoLead, type CodigoValidacion } from './validacion'
import { registrarError } from './observabilidad'
import {
  PanelActionsContext,
  PanelStateContext,
  StoreDataContext,
  StoreEstadoContext,
} from './store-context'
import {
  actualizarLead,
  CrmApiError,
  insertarActividad,
  insertarLead,
  listarActividadesDelAmbito,
  listarEquipo,
  listarLeadsDelAmbito,
} from '@/data/crm-api'

/**
 * Estado de la CARGA remota (solo sesión real). La app lo usa para decidir
 * entre splash, pantalla de error con reintento y el workspace: sin esto, un
 * fallo de red pintaba el CRM VACÍO como si "no hubiera leads" (hallazgo de la
 * revisión adversarial). En demo siempre es inerte (cargando/error = false).
 */
export interface StoreEstado {
  cargando: boolean
  error: boolean
  reintentar: () => void
}

// v2: F1c re-siembra (20 leads + asignado_supervisor_id) — la clave vieja se ignora.
const CLAVE = 'ac-crm-demo-datos-v2'

/** Códigos de fallo de una mutación (además de los de validación de campos). */
export type CodigoMut =
  | CodigoValidacion
  | 'sin_permiso'
  | 'fuente_no_habilitada'
  | 'no_encontrado'
  | 'duplicado_telefono'
  | 'duplicado_dni'
  | 'etapa_terminal_al_nacer'
  | 'lead_cerrado'
  | 'cerrar_con_flujo'
  | 'solo_reabrir_descartado'
  | 'vendedor_no_encontrado'
  | 'vendedor_fuera_ambito'
  | 'solo_autoasignar'
  | 'tipo_actividad_reservado'
  | 'sin_permiso_reasignar'

/**
 * Resultado de una mutación. `error` es el mensaje es-PE listo para mostrar;
 * `codigo` identifica el fallo de forma estable y `campo` (si aplica) ancla el
 * error a un campo del formulario — la UI NUNCA debe adivinar por regex sobre
 * el texto del mensaje.
 */
export interface ResultadoMut {
  ok: boolean
  error?: string
  codigo?: CodigoMut
  campo?: CampoLead
}

export interface NuevoLeadInput {
  nombre_completo: string
  telefono: string
  correo?: string | null
  dni?: string | null
  distrito?: string | null
  origen: Origen
  etapa?: EtapaActiva // default 'nuevo' — un lead NUNCA nace terminal
  monto_estimado?: number | null
  moneda: Moneda
  categoria_interes?: CategoriaInteres | null
  vendedor_id?: string | null
  nota?: string | null
}

/** Cambios editables de la ficha (espejo del contrato F1b). */
export type CambiosLead = Partial<
  Pick<
    Lead,
    | 'nombre_completo'
    | 'telefono'
    | 'correo'
    | 'monto_estimado'
    | 'moneda'
    | 'categoria_interes'
    | 'origen'
    | 'nota'
    | 'dni'
    | 'distrito'
  >
>

/**
 * Ámbito por rol (espejo de la RLS jerárquica de F0 — contrato F1c).
 * TODAS las pantallas (y la búsqueda del topbar) deben leer de aquí en vez
 * del `leads` global:
 *  - vendedor: leads con vendedor_id === yo.id
 *  - supervisor: los suyos + los de sus vendedores + parkeados con
 *    asignado_supervisor_id === yo.id (vendedor_id null)
 *  - gerencia y directorio: todos
 */
export interface Ambito {
  leads: Lead[] // recortado por rol
  vendedores: Miembro[] // vendedores visibles/filtrables (supervisor: los suyos; gerencia/directorio: todos)
  esGlobal: boolean // true para gerencia/directorio
}

export interface EventoAgenda {
  id: string
  lead_id: string
  titulo: string
  tipo: string
  cuando: string
  color: string
}

export interface ObjetivoComercial {
  capitalObjetivo: number
  ventasObjetivo: number
  conversionObjetivo: number
}

export type ObjetivosPorRol = Record<'vendedor' | 'supervisor' | 'gerencia', ObjetivoComercial>

export interface SeriesComerciales {
  capital: number[]
  leads: number[]
  propuestas: number[]
  conversion: number[]
}

export interface StoreDataApi {
  leads: Lead[] // todos, activos y terminales (legacy — preferir `ambito`)
  equipo: Miembro[]
  ambito: Ambito
  agenda: EventoAgenda[]
  objetivos: ObjetivosPorRol
  series: SeriesComerciales
  // Crudas, para lib/inteligencia (colaDe, estancados…). OJO: es el timeline
  // GLOBAL sin recorte (la RLS actividades_select SÍ recorta a leads visibles):
  // toda lista visible al usuario debe cruzarse con ambito.leads, nunca
  // iterarse directo — salvo el lector global (directorio).
  actividades: Actividad[]
  // Timeline YA recortado a los leads del ámbito (espejo de actividades_select).
  // Para cualquier lista visible al usuario, PREFERIR esto sobre `actividades`:
  // el recorte lo garantiza el store, no la disciplina de cada pantalla.
  actividadesDelAmbito: Actividad[]
  lead(id: string): Lead | undefined
  actividadesDe(leadId: string): Actividad[] // orden desc por creado_en
  // Mutaciones — TODAS write-gated dentro del store
  crearLead(input: NuevoLeadInput): ResultadoMut & { id?: string }
  editarLead(id: string, cambios: CambiosLead): ResultadoMut
  cambiarEtapa(id: string, etapa: EtapaActiva): ResultadoMut
  descartar(id: string, motivo: MotivoDescarte, nota?: string): ResultadoMut
  convertir(id: string): ResultadoMut
  reabrir(id: string): ResultadoMut
  registrarActividad(id: string, tipo: TipoActividadManual, detalle?: string): ResultadoMut
  reasignar(id: string, vendedorId: string | null): ResultadoMut
  // Refresco explícito desde el servidor (tras un flujo async que NO pasa por el
  // camino optimista: p. ej. la conversión lead→cliente vía edge). En demo es no-op.
  recargar(): Promise<boolean>
}

export interface PanelesState {
  leadAbiertoId: string | null
  nuevoLeadAbierto: boolean
  etapaInicial: EtapaActiva
}

export interface PanelesActions {
  abrirLead(id: string): void
  abrirNuevoLead(etapa?: EtapaActiva): void
  cerrarPaneles(): void
}

interface Datos {
  leads: Lead[]
  actividades: Actividad[]
}

const EQUIPO_VACIO: Miembro[] = []
const OBJETIVOS_VACIOS: ObjetivosPorRol = {
  vendedor: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
  supervisor: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
  gerencia: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
}
const SERIES_VACIAS: SeriesComerciales = {
  capital: [],
  leads: [],
  propuestas: [],
  conversion: [],
}

interface Auxiliares {
  equipo: Miembro[]
  agenda: EventoAgenda[]
  objetivos: ObjetivosPorRol
  series: SeriesComerciales
}

const AUXILIARES_VACIOS: Auxiliares = {
  equipo: EQUIPO_VACIO,
  agenda: [],
  objetivos: OBJETIVOS_VACIOS,
  series: SERIES_VACIAS,
}

function datosVacios(): Datos {
  return { leads: [], actividades: [] }
}

// ── Helpers puros ─────────────────────────────────────────────────────────────

function uid(): string {
  try {
    return crypto.randomUUID()
  } catch {
    return `id-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
  }
}

/** ¿El id local es un UUID válido para persistirlo tal cual en el servidor? */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Dedup vivo: teléfono/DNI no pueden repetirse entre leads abiertos. El índice
 * es GLOBAL (espejo del unique index parcial), pero el NOMBRE del lead en
 * conflicto solo se revela si el actor puede verlo (`visibles`) — sin esto, un
 * vendedor podía sondear teléfonos/DNIs ajenos y cosechar nombres de leads
 * fuera de su ámbito (fuga de PII detectada por los tests de auditoría).
 */
function conflictoDedup(
  leads: Lead[],
  telefono: string,
  dni: string | null | undefined,
  exceptoId?: string,
  visibles?: ReadonlySet<string>,
): ResultadoMut | null {
  const abiertos = leads.filter((l) => esAbierto(l) && l.id !== exceptoId)
  const nombreSeguro = (l: Lead): string | null => (visibles?.has(l.id) ? l.nombre_completo : null)
  const porTel = abiertos.find((l) => l.telefono === telefono)
  if (porTel) {
    const nombre = nombreSeguro(porTel)
    return {
      ok: false,
      codigo: 'duplicado_telefono',
      campo: 'telefono',
      error: nombre
        ? `Ese teléfono ya pertenece a un lead abierto: ${nombre}`
        : 'Ese teléfono ya pertenece a otro lead abierto de la empresa',
    }
  }
  if (dni) {
    const porDni = abiertos.find((l) => l.dni === dni)
    if (porDni) {
      const nombre = nombreSeguro(porDni)
      return {
        ok: false,
        codigo: 'duplicado_dni',
        campo: 'dni',
        error: nombre
          ? `Ese DNI ya pertenece a un lead abierto: ${nombre}`
          : 'Ese DNI ya pertenece a otro lead abierto de la empresa',
      }
    }
  }
  return null
}

function cargarDatos(semilla: Datos): Datos {
  try {
    const crudo = sessionStorage.getItem(CLAVE)
    if (crudo) {
      const d = JSON.parse(crudo) as Datos
      if (Array.isArray(d?.leads) && Array.isArray(d?.actividades)) return d
    }
  } catch {
    /* sesión privada o JSON corrupto → siembra fresca */
  }
  return structuredClone(semilla)
}

// ── Provider ──────────────────────────────────────────────────────────────────

export function StoreProvider({ children }: { children: ReactNode }): JSX.Element {
  const { yo } = useAuth()
  const demoSolicitado = DEMO_HABILITADO && yo?.demo === true
  // Sesión autenticada real (no demo): la capa de datos lee del servidor y la
  // RLS del esquema crm decide el ámbito; el navegador nunca recorta seguridad.
  const sesionReal = !!yo && yo.demo !== true
  // El store local solo contiene datos ficticios durante una sesión demo
  // explícita. Una sesión real nunca recibe ni persiste PII de demostración.
  const [datos, setDatos] = useState<Datos>(datosVacios)
  const [auxiliares, setAuxiliares] = useState<Auxiliares>(AUXILIARES_VACIOS)
  const [demoListo, setDemoListo] = useState(false)
  const [realListo, setRealListo] = useState(false)
  const [errorReal, setErrorReal] = useState(false)
  // Reintento manual desde la pantalla de error: cambiar este contador vuelve a
  // disparar el efecto de carga (misma sesión, otra época).
  const [intentoReal, setIntentoReal] = useState(0)
  const demoActivo = demoSolicitado && demoListo
  const realActivo = sesionReal && realListo
  const equipo = auxiliares.equipo

  // Época de la sesión/carga: se incrementa en CADA corrida del efecto de datos
  // (login, cambio de usuario, logout, reintento). Toda resincronización captura
  // su época y descarta el resultado si la época ya cambió — así una resync
  // rezagada de A no repuebla el store de B tras un cambio de sesión (fuga de PII
  // que detectó la revisión adversarial), ni pisa datos de una recarga posterior.
  const epocaRef = useRef(0)

  // Paneles globales
  const [leadAbiertoId, setLeadAbiertoId] = useState<string | null>(null)
  const [nuevoLeadAbierto, setNuevoLeadAbierto] = useState(false)
  const [etapaInicial, setEtapaInicial] = useState<EtapaActiva>('nuevo')

  const abrirLead = useCallback((id: string) => {
    setNuevoLeadAbierto(false)
    setLeadAbiertoId(id)
  }, [])
  const abrirNuevoLead = useCallback((etapa?: EtapaActiva) => {
    setLeadAbiertoId(null)
    setEtapaInicial(etapa ?? 'nuevo')
    setNuevoLeadAbierto(true)
  }, [])
  const cerrarPaneles = useCallback(() => {
    setLeadAbiertoId(null)
    setNuevoLeadAbierto(false)
  }, [])

  const panelState = useMemo<PanelesState>(() => ({
    leadAbiertoId,
    nuevoLeadAbierto,
    etapaInicial,
  }), [leadAbiertoId, nuevoLeadAbierto, etapaInicial])

  const panelActions = useMemo<PanelesActions>(() => ({
    abrirLead,
    abrirNuevoLead,
    cerrarPaneles,
  }), [abrirLead, abrirNuevoLead, cerrarPaneles])

  // Carga de la sesión REAL. La RLS del esquema crm decide el ámbito; el
  // vendedor_nombre se resuelve con el roster (crm.leads solo guarda el id).
  const cargarReal = useCallback(async (signal?: AbortSignal) => {
    const [leads, miembros, actividades] = await Promise.all([
      listarLeadsDelAmbito(signal),
      listarEquipo(signal),
      listarActividadesDelAmbito(signal),
    ])
    const nombrePorId = new Map(miembros.map((m) => [m.perfil_id, m.nombre_completo]))
    return {
      miembros,
      actividades,
      leads: leads.map((l) => ({
        ...l,
        vendedor_nombre: l.vendedor_id ? (nombrePorId.get(l.vendedor_id) ?? null) : null,
      })),
    }
  }, [])

  // Tras cada mutación real (éxito o rechazo) el SERVIDOR es la verdad: se
  // recargan leads/actividades/equipo para reflejar triggers y RLS (y, en un
  // rechazo, deshacer el espejo optimista). Devuelve `true` solo si el resultado
  // se APLICÓ (misma época): el llamador usa eso para no mentir en el toast de
  // rollback cuando el servidor está inalcanzable.
  const resincronizarReal = useCallback(async (): Promise<boolean> => {
    const miEpoca = epocaRef.current
    try {
      const { leads, actividades, miembros } = await cargarReal()
      // La sesión cambió (logout/otro usuario/recarga) mientras viajaba: se
      // descarta en vez de repoblar el store de otra sesión.
      if (epocaRef.current !== miEpoca) return false
      setDatos({ leads, actividades })
      setAuxiliares((prev) => ({ ...prev, equipo: miembros }))
      return true
    } catch (error: unknown) {
      registrarError('crm.resincronizacion_fallida', error)
      return false
    }
  }, [cargarReal])

  useEffect(() => {
    let cancelado = false
    const control = new AbortController()
    // Nueva corrida del efecto = nueva época: invalida cualquier resync en vuelo.
    epocaRef.current += 1
    setDemoListo(false)
    setRealListo(false)
    setErrorReal(false)

    // Sesión DEMO (solo DEV con flag). La condición usa flags de Vite directos
    // para que Rolldown elimine el chunk de fixtures en cualquier build de prod.
    if (demoSolicitado) {
      if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
        void import('./demo')
          .then((demo) => {
            if (cancelado) return
            setDatos(cargarDatos({ leads: demo.LEADS_DEMO, actividades: demo.ACTIVIDADES_DEMO }))
            setAuxiliares({
              equipo: demo.EQUIPO_DEMO,
              agenda: demo.AGENDA_DEMO,
              objetivos: demo.METAS_DEMO,
              series: demo.SPARKS_DEMO,
            })
            setDemoListo(true)
          })
          .catch((error: unknown) => {
            if (cancelado) return
            registrarError('demo.carga_fallida', error)
            setDatos(datosVacios())
            setAuxiliares(AUXILIARES_VACIOS)
          })
      }
      return () => { cancelado = true; control.abort() }
    }

    // Sesión REAL: lee del servidor.
    if (sesionReal) {
      void cargarReal(control.signal)
        .then(({ leads, actividades, miembros }) => {
          if (cancelado) return
          setDatos({ leads, actividades })
          setAuxiliares({ equipo: miembros, agenda: [], objetivos: OBJETIVOS_VACIOS, series: SERIES_VACIAS })
          setRealListo(true)
        })
        .catch((error: unknown) => {
          if (cancelado || control.signal.aborted) return
          registrarError('crm.carga_real_fallida', error)
          // Fallo de la carga inicial: NO se pinta el CRM vacío (parecería "no hay
          // leads"). Se marca error para que la app muestre reintento explícito.
          setDatos(datosVacios())
          setAuxiliares(AUXILIARES_VACIOS)
          setErrorReal(true)
        })
      return () => { cancelado = true; control.abort() }
    }

    // Ni demo ni sesión real: vacío.
    setDatos(datosVacios())
    setAuxiliares(AUXILIARES_VACIOS)
    return () => { cancelado = true; control.abort() }
  }, [demoSolicitado, sesionReal, yo?.id, intentoReal, cargarReal])

  // Persistencia demo (solo sessionStorage — jamás Supabase)
  useEffect(() => {
    if (!demoActivo) return
    try {
      sessionStorage.setItem(CLAVE, JSON.stringify(datos))
    } catch {
      /* storage lleno o no disponible: seguimos solo en memoria */
    }
  }, [datos, demoActivo])

  // Ámbito por rol (reglas EXACTAS del contrato F1c — espejo de la RLS F0).
  // useMemo PROPIO con deps [datos, yo]: abrir/cerrar paneles NO debe regenerar
  // las referencias de ambito.leads/vendedores (los useMemo de las pantallas
  // dependen de ellas y recalcularían colaDe/metricasPorVendedor sin motivo).
  const ambito = useMemo<Ambito>(() => {
    const rol = yo?.rol
    const miId = yo?.id ?? null
    if (can(rol, 'verTodo')) {
      // gerencia y directorio: todo el universo + todos los vendedores.
      // Espejo del filtro `activo = true` de leads_select: solo el lector
      // global (directorio) ve los soft-borrados; gerencia NO los ve.
      return {
        leads: can(rol, 'soloLecturaTotal') ? datos.leads : datos.leads.filter((l) => l.activo),
        vendedores: equipo.filter((m) => m.rol_crm === 'vendedor'),
        esGlobal: true,
      }
    }
    if (rol === 'supervisor' && miId) {
      // OJO espejo: aquí se usan reportes DIRECTOS (EQUIPO_DEMO es plano);
      // la RLS real usa un subárbol RECURSIVO (vendedor_ids_visibles) e
      // incluye parkeados de cualquier miembro del subárbol. Con supervisores
      // anidados este espejo mostraría MENOS que la RLS (infra-inclusivo, sin
      // fuga) — replicar la recursión al portar a datos reales.
      const mios = equipo.filter((m) => m.supervisor_id === miId)
      const ids = new Set<string>([miId, ...mios.map((m) => m.perfil_id)])
      return {
        leads: datos.leads.filter(
          (l) =>
            l.activo &&
            ((l.vendedor_id != null && ids.has(l.vendedor_id)) ||
              (l.vendedor_id == null && l.asignado_supervisor_id === miId)),
        ),
        vendedores: mios,
        esGlobal: false,
      }
    }
    // vendedor — o rol/sesión desconocidos: privilegio mínimo (solo lo propio)
    return {
      leads: miId ? datos.leads.filter((l) => l.activo && l.vendedor_id === miId) : [],
      vendedores: equipo.filter((m) => m.perfil_id === miId),
      esGlobal: false,
    }
  }, [datos, yo, equipo])

  const api = useMemo<StoreDataApi>(() => {
    const rol = yo?.rol
    const autor = yo?.nombre_completo ?? 'DEMO'

    const sinPermiso = (): ResultadoMut => {
      toast.error('Tu rol es de solo lectura — no puedes modificar datos')
      return { ok: false, codigo: 'sin_permiso', error: 'Sin permiso de escritura' }
    }

    const bloqueoEscritura = (): ResultadoMut | null => {
      // Demo y sesión real comparten el mismo gate de rol: la RLS + los triggers
      // del esquema crm son la autoridad server-side; el store solo replica el
      // permiso para dar feedback inmediato (doble defensa). `convertir` mantiene
      // su propio veto en real (necesita la RPC privilegiada del bloque 6).
      if (demoActivo || realActivo) return puedeEscribir(rol) ? null : sinPermiso()
      toast.error('La fuente de datos del CRM aún no está habilitada')
      return { ok: false, codigo: 'fuente_no_habilitada', error: 'Fuente de datos no habilitada' }
    }

    const noEncontrado = (): ResultadoMut => ({ ok: false, codigo: 'no_encontrado', error: 'Lead no encontrado' })

    const actividadAuto = (
      lead_id: string,
      tipo: TipoActividad,
      detalle: string | null,
    ): Actividad => ({
      id: uid(),
      lead_id,
      tipo,
      detalle,
      autor_nombre: autor,
      creado_en: new Date().toISOString(),
    })

    const aplicar = (id: string, parche: Partial<Lead>, actividad?: Actividad) => {
      setDatos((d) => ({
        leads: d.leads.map((l) => (l.id === id ? { ...l, ...parche } : l)),
        actividades: actividad ? [actividad, ...d.actividades] : d.actividades,
      }))
    }

    // Espejo del USING de leads_update/select: el objetivo de una lectura o
    // mutación debe estar DENTRO del ámbito del actor. Buscar en el universo
    // global permitía a un supervisor mutar leads del otro equipo (hallazgo de
    // los tests de auditoría). Fuera del ámbito → "no encontrado", igual que
    // RLS (0 filas), sin revelar existencia.
    const buscar = (id: string) => ambito.leads.find((l) => l.id === id)

    const miId = yo?.id ?? null

    // Recorte del timeline al ámbito (espejo de actividades_select).
    const idsDelAmbito = new Set(ambito.leads.map((l) => l.id))

    // Espejo del WITH CHECK de leads_insert/leads_update (F0): para supervisor
    // el vendedor destino debe estar dentro de SU subárbol (él mismo o sus
    // vendedores). Gerencia pasa siempre (vendedor_ids_visibles = todos) y el
    // vendedor nunca llega aquí con otro destino (gates de can/reasignar).
    const vendedorFueraDeAmbito = (vendedorId: string | null): boolean =>
      rol === 'supervisor' &&
      vendedorId != null &&
      vendedorId !== miId &&
      !ambito.vendedores.some((m) => m.perfil_id === vendedorId)

    // Persistencia REAL: la mutación ya se aplicó OPTIMISTA en el estado local
    // (contrato síncrono del store); aquí viaja al servidor y, pase lo que
    // pase, se resincroniza — los triggers (cambio_etapa/reasignacion) y la
    // verdad del servidor reemplazan el espejo optimista. Si el servidor la
    // rechaza (dedup global, RLS, regla de trigger): toast + rollback.
    const persistir = (op: () => Promise<void>): void => {
      if (!realActivo) return
      void op().then(
        () => { void resincronizarReal() },
        (causa: unknown) => {
          // Variante LOCAL de mensajeDeError (crm-api): además excluye
          // POSTGREST_ERROR — ese mensaje genérico es de LECTURA ("No se pudo
          // cargar…") y confundiría como feedback de una mutación rechazada.
          const mensaje = causa instanceof CrmApiError && causa.code !== 'POSTGREST_ERROR'
            ? causa.message
            : 'No se pudo guardar el cambio'
          registrarError('crm.mutacion_revertida', causa)
          // El toast NO puede prometer "se restauró" a ciegas: si el resync de
          // rollback también falla (sin conexión), el espejo optimista sigue
          // pintado. Solo se afirma la restauración cuando de verdad se aplicó.
          void resincronizarReal().then((restaurado) => {
            toast.error(
              restaurado
                ? `${mensaje} — se restauró el estado anterior`
                : `${mensaje}. Sin conexión con el servidor: recarga la página para ver el estado real.`,
            )
          })
        },
      )
    }

    return {
      leads: datos.leads,
      equipo,
      ambito,
      agenda: auxiliares.agenda,
      objetivos: auxiliares.objetivos,
      series: auxiliares.series,
      actividades: datos.actividades,
      actividadesDelAmbito: datos.actividades.filter((a) => idsDelAmbito.has(a.lead_id)),
      lead: (id) => buscar(id),
      actividadesDe: (leadId) =>
        // Espejo de actividades_select: solo el timeline de leads del ámbito.
        idsDelAmbito.has(leadId)
          ? datos.actividades
              .filter((a) => a.lead_id === leadId)
              .sort((a, b) => b.creado_en.localeCompare(a.creado_en))
          : [],

      crearLead: (input) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        // Validación compartida (espejo de los CHECK de crm.leads) — la misma
        // fuente que editarLead y, a futuro, las mutaciones reales de Supabase.
        const v = validarCamposLead({
          nombre_completo: input.nombre_completo,
          telefono: input.telefono,
          dni: input.dni ?? null,
          correo: input.correo ?? null,
          origen: input.origen,
          monto_estimado: input.monto_estimado ?? null,
        })
        if (!v.ok) return v
        const nombre = v.valores.nombre_completo ?? ''
        const telefono = v.valores.telefono ?? ''
        const dni = v.valores.dni ?? null
        const etapa: EtapaActiva = input.etapa ?? 'nuevo'
        if (TERMINALES_K.has(etapa)) {
          return { ok: false, codigo: 'etapa_terminal_al_nacer', error: 'Un lead no puede nacer en etapa terminal' }
        }
        // Espejo de la policy leads_insert: sin can('reasignar') el lead solo
        // puede nacer asignado a uno mismo (parkear es de supervisor/gerencia).
        // El gate de permisos corre ANTES del dedup: sin permiso no hay sondeo.
        if (!can(rol, 'reasignar') && (input.vendedor_id ?? null) !== (yo?.id ?? null)) {
          return { ok: false, codigo: 'solo_autoasignar', error: 'Solo puedes crear leads asignados a ti mismo' }
        }
        const choque = conflictoDedup(datos.leads, telefono, dni, undefined, idsDelAmbito)
        if (choque) return choque
        // Resuelve el vendedor SIN tragar ids inválidos (mismo criterio que reasignar()).
        let vendedor_id: string | null = null
        let vendedor_nombre: string | null = null
        if (input.vendedor_id) {
          const m = equipo.find((x) => x.perfil_id === input.vendedor_id)
          if (m) {
            vendedor_id = m.perfil_id
            vendedor_nombre = m.nombre_completo
          } else if (yo && input.vendedor_id === yo.id) {
            // Usuario (demo o sesión real) fuera de EQUIPO_DEMO: se auto-asigna igual.
            vendedor_id = yo.id
            vendedor_nombre = yo.nombre_completo
          } else {
            return { ok: false, codigo: 'vendedor_no_encontrado', error: 'Vendedor no encontrado' }
          }
        }
        // Espejo del WITH CHECK de leads_insert: supervisor solo dentro de su equipo.
        if (vendedorFueraDeAmbito(vendedor_id)) {
          return { ok: false, codigo: 'vendedor_fuera_ambito', error: 'Ese vendedor no pertenece a tu equipo' }
        }
        const id = uid()
        const lead: Lead = {
          id,
          nombre_completo: nombre,
          telefono,
          correo: v.valores.correo ?? null,
          etapa,
          origen: v.valores.origen ?? input.origen,
          monto_estimado: input.monto_estimado ?? null,
          moneda: input.moneda,
          categoria_interes: input.categoria_interes ?? null,
          vendedor_id,
          vendedor_nombre,
          // Parkeado por un supervisor → queda en SU bandeja (espejo F0: el
          // ámbito jerárquico lo mostrará como "por repartir" de ese supervisor).
          asignado_supervisor_id: vendedor_id == null && rol === 'supervisor' ? miId : null,
          creado_en: new Date().toISOString(),
          activo: true,
          dni,
          distrito: input.distrito?.trim() || null,
          nota: input.nota?.trim() || null,
          motivo_descarte: null,
        }
        setDatos((d) => ({ ...d, leads: [lead, ...d.leads] }))
        // El id viaja al servidor (si es UUID) para que el optimista y la fila
        // real sean LA MISMA identidad — un drawer abierto sobrevive al resync.
        persistir(() => insertarLead({
          ...(UUID_RE.test(id) ? { id } : {}),
          nombre_completo: nombre,
          telefono,
          correo: lead.correo ?? null,
          dni,
          distrito: lead.distrito ?? null,
          origen: lead.origen,
          etapa,
          monto_estimado: lead.monto_estimado ?? null,
          moneda: lead.moneda,
          categoria_interes: lead.categoria_interes ?? null,
          vendedor_id,
          asignado_supervisor_id: lead.asignado_supervisor_id ?? null,
          nota: lead.nota ?? null,
          creado_por: miId,
        }))
        return { ok: true, id }
      },

      editarLead: (id, cambios) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        // MISMA validación que crearLead (antes: dos copias divergentes; la
        // edición saltaba teléfono/correo/DNI si el texto cambiaba de forma).
        const v = validarCamposLead({
          ...(cambios.nombre_completo !== undefined ? { nombre_completo: cambios.nombre_completo } : {}),
          ...(cambios.telefono !== undefined ? { telefono: cambios.telefono } : {}),
          ...(cambios.dni !== undefined ? { dni: cambios.dni } : {}),
          ...(cambios.correo !== undefined ? { correo: cambios.correo } : {}),
          ...(cambios.origen !== undefined ? { origen: cambios.origen } : {}),
          ...(cambios.monto_estimado !== undefined ? { monto_estimado: cambios.monto_estimado } : {}),
        })
        if (!v.ok) return v
        const parche: CambiosLead = { ...cambios, ...v.valores }
        if (esAbierto(actual)) {
          const tel = parche.telefono ?? actual.telefono
          const dni = parche.dni !== undefined ? parche.dni : (actual.dni ?? null)
          const choque = conflictoDedup(datos.leads, tel, dni, id, idsDelAmbito)
          if (choque) return choque
        }
        aplicar(id, parche)
        persistir(() => actualizarLead(id, parche))
        return { ok: true }
      },

      cambiarEtapa: (id, etapa) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa)) {
          return { ok: false, codigo: 'lead_cerrado', error: 'El lead está cerrado — reábrelo para moverlo de etapa' }
        }
        if (TERMINALES_K.has(etapa)) {
          return { ok: false, codigo: 'cerrar_con_flujo', error: 'Usa convertir o descartar para cerrar un lead' }
        }
        if (actual.etapa === etapa) return { ok: true }
        aplicar(
          id,
          { etapa },
          actividadAuto(id, 'cambio_etapa', `${ETAPA_INFO[actual.etapa].label} → ${ETAPA_INFO[etapa].label}`),
        )
        // El trigger del servidor genera la actividad real; el resync la trae.
        persistir(() => actualizarLead(id, { etapa }))
        return { ok: true }
      },

      descartar: (id, motivo, nota) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa)) return { ok: false, codigo: 'lead_cerrado', error: 'El lead ya está cerrado' }
        const labelMotivo = MOTIVOS_DESCARTE.find((m) => m.k === motivo)?.label ?? motivo
        const notaLimpia = nota?.trim() || null
        const detalle = `${ETAPA_INFO[actual.etapa].label} → ${ETAPA_INFO.descartado.label} · Motivo: ${labelMotivo}${notaLimpia ? ` — ${notaLimpia}` : ''}`
        // La nota del descarte queda inmutable en la actividad del timeline;
        // NO pisa la nota original del lead (era destructivo y redundante).
        aplicar(
          id,
          { etapa: 'descartado', motivo_descarte: motivo },
          actividadAuto(id, 'cambio_etapa', detalle),
        )
        // En real el trigger escribe el cambio_etapa genérico (sin motivo ni
        // nota); la nota libre del descarte se preserva como actividad 'nota'
        // aparte (el motivo ya viaja en la columna motivo_descarte). Son dos
        // escrituras NO atómicas: el update es la acción primaria; si la nota
        // (secundaria) falla DESPUÉS de que el descarte ya persistió, NO se
        // revierte ni se miente con "se restauró" — se avisa puntualmente que la
        // nota no se guardó (el descarte es correcto). La atomicidad real (un
        // RPC crm.descartar_lead) llega con el bloque 6, que ya toca la BD.
        persistir(async () => {
          await actualizarLead(id, { etapa: 'descartado', motivo_descarte: motivo })
          if (notaLimpia) {
            try {
              await insertarActividad({
                lead_id: id,
                tipo: 'nota',
                detalle: `Descarte · ${labelMotivo} — ${notaLimpia}`,
                creado_por: miId,
              })
            } catch (causa) {
              registrarError('crm.descarte_nota_fallida', causa)
              toast.warning('Lead descartado, pero no se pudo guardar la nota del descarte')
            }
          }
        })
        return { ok: true }
      },

      convertir: (id) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa)) return { ok: false, codigo: 'lead_cerrado', error: 'El lead ya está cerrado' }
        if (realActivo) {
          // Red de seguridad: en real, convertir NO es marcar la etapa — hay que
          // crear la cuenta del cliente en el portal, y de eso se encarga la edge
          // `crm-convertir-lead` desde la ficha (DialogConvertir). Marcar la etapa
          // por aquí dejaría un "convertido" sin cliente detrás.
          toast.error('Usa "Convertir a cliente" en la ficha del lead')
          return { ok: false, codigo: 'fuente_no_habilitada', error: 'Conversión no disponible por esta vía' }
        }
        aplicar(
          id,
          { etapa: 'convertido', motivo_descarte: null },
          actividadAuto(id, 'conversion', `Convertido a cliente desde ${ETAPA_INFO[actual.etapa].label}${yo?.demo ? ' (demo)' : ''}`),
        )
        return { ok: true }
      },

      reabrir: (id) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (actual.etapa !== 'descartado') {
          return { ok: false, codigo: 'solo_reabrir_descartado', error: 'Solo se puede reabrir un lead descartado' }
        }
        const choque = conflictoDedup(datos.leads, actual.telefono, actual.dni ?? null, id, idsDelAmbito)
        if (choque) return choque
        aplicar(
          id,
          { etapa: 'nuevo', motivo_descarte: null },
          actividadAuto(id, 'cambio_etapa', `${ETAPA_INFO.descartado.label} → ${ETAPA_INFO.nuevo.label}`),
        )
        persistir(() => actualizarLead(id, { etapa: 'nuevo', motivo_descarte: null }))
        return { ok: true }
      },

      registrarActividad: (id, tipo, detalle) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        // Doble defensa (el tipo TS se borra en runtime): los tipos automáticos
        // los emite SOLO el store, y un lead cerrado no recibe actividad manual.
        if (TIPOS_AUTO_K.has(tipo)) {
          return { ok: false, codigo: 'tipo_actividad_reservado', error: 'Ese tipo de actividad lo genera el sistema — no se registra a mano' }
        }
        if (TERMINALES_K.has(actual.etapa)) {
          return { ok: false, codigo: 'lead_cerrado', error: 'El lead está cerrado — reábrelo para registrar actividad' }
        }
        const act = actividadAuto(id, tipo, detalle?.trim() || null)
        setDatos((d) => ({ ...d, actividades: [act, ...d.actividades] }))
        persistir(() => insertarActividad({
          lead_id: id,
          tipo,
          detalle: act.detalle,
          creado_por: miId,
        }))
        return { ok: true }
      },

      reasignar: (id, vendedorId) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        if (!can(rol, 'reasignar')) {
          toast.error('No tienes permiso para reasignar leads')
          return { ok: false, codigo: 'sin_permiso_reasignar', error: 'Sin permiso para reasignar' }
        }
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        const nuevo = vendedorId ? equipo.find((m) => m.perfil_id === vendedorId) : undefined
        if (vendedorId && !nuevo) return { ok: false, codigo: 'vendedor_no_encontrado', error: 'Vendedor no encontrado' }
        // Espejo del WITH CHECK de leads_update: supervisor solo dentro de su equipo.
        if (vendedorFueraDeAmbito(vendedorId)) {
          return { ok: false, codigo: 'vendedor_fuera_ambito', error: 'Ese vendedor no pertenece a tu equipo' }
        }
        if ((actual.vendedor_id ?? null) === (nuevo?.perfil_id ?? null)) return { ok: true }
        aplicar(
          id,
          {
            vendedor_id: nuevo?.perfil_id ?? null,
            vendedor_nombre: nuevo?.nombre_completo ?? null,
            // Al asignar vendedor sale de la bandeja; al parkear (null) un
            // supervisor lo retiene en la SUYA (gerencia parkea sin bandeja).
            asignado_supervisor_id: nuevo ? null : rol === 'supervisor' ? miId : null,
          },
          actividadAuto(
            id,
            'reasignacion',
            `${actual.vendedor_nombre ?? 'Sin asignar'} → ${nuevo?.nombre_completo ?? 'Sin asignar'}`,
          ),
        )
        // La actividad real la emite el trigger trg_leads_reasignacion.
        persistir(() => actualizarLead(id, {
          vendedor_id: nuevo?.perfil_id ?? null,
          asignado_supervisor_id: nuevo ? null : rol === 'supervisor' ? miId : null,
        }))
        return { ok: true }
      },

      // El flujo de conversión (edge) escribe server-side; aquí se trae la verdad.
      recargar: () => (realActivo ? resincronizarReal() : Promise.resolve(true)),
    }
  }, [datos, yo, ambito, demoActivo, realActivo, equipo, auxiliares, resincronizarReal])

  // Estado de la carga remota para la app (splash / error+reintento / workspace).
  const estado = useMemo<StoreEstado>(() => ({
    // Sesión real que aún no terminó de cargar y no falló: mostrar splash.
    cargando: sesionReal && !realActivo && !errorReal,
    error: sesionReal && errorReal,
    reintentar: () => setIntentoReal((n) => n + 1),
  }), [sesionReal, realActivo, errorReal])

  return (
    <StoreDataContext.Provider value={api}>
      <StoreEstadoContext.Provider value={estado}>
        <PanelActionsContext.Provider value={panelActions}>
          <PanelStateContext.Provider value={panelState}>
            {children}
          </PanelStateContext.Provider>
        </PanelActionsContext.Provider>
      </StoreEstadoContext.Provider>
    </StoreDataContext.Provider>
  )
}
