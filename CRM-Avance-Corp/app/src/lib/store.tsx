// Store DEMO del CRM (F1b) — fuente de verdad de leads/actividades en memoria,
// sembrada desde lib/demo.ts y persistida en sessionStorage. JAMÁS escribe en
// Supabase. Write-gating con doble defensa: la UI oculta acciones y el store
// re-valida CADA mutación (toast.error + no-op si el rol no puede escribir).
// Debe montarse DENTRO de AuthProvider (usa useAuth para el gating y el autor).
import {
  useCallback,
  useEffect,
  useMemo,
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
} from './store-context'

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

/** Dedup vivo: teléfono/DNI no pueden repetirse entre leads abiertos. */
function conflictoDedup(
  leads: Lead[],
  telefono: string,
  dni: string | null | undefined,
  exceptoId?: string,
): ResultadoMut | null {
  const abiertos = leads.filter((l) => esAbierto(l) && l.id !== exceptoId)
  const porTel = abiertos.find((l) => l.telefono === telefono)
  if (porTel) {
    return {
      ok: false,
      codigo: 'duplicado_telefono',
      campo: 'telefono',
      error: `Ese teléfono ya pertenece a un lead abierto: ${porTel.nombre_completo}`,
    }
  }
  if (dni) {
    const porDni = abiertos.find((l) => l.dni === dni)
    if (porDni) {
      return {
        ok: false,
        codigo: 'duplicado_dni',
        campo: 'dni',
        error: `Ese DNI ya pertenece a un lead abierto: ${porDni.nombre_completo}`,
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
  // El store local solo contiene datos ficticios durante una sesión demo
  // explícita. Una sesión real nunca recibe ni persiste PII de demostración.
  const [datos, setDatos] = useState<Datos>(datosVacios)
  const [auxiliares, setAuxiliares] = useState<Auxiliares>(AUXILIARES_VACIOS)
  const [demoListo, setDemoListo] = useState(false)
  const demoActivo = demoSolicitado && demoListo
  const equipo = auxiliares.equipo

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

  useEffect(() => {
    let cancelado = false
    setDemoListo(false)

    if (!demoSolicitado) {
      setDatos(datosVacios())
      setAuxiliares(AUXILIARES_VACIOS)
      return () => { cancelado = true }
    }

    // La condición usa flags de Vite directamente para que Rolldown elimine
    // incluso el chunk con fixtures en cualquier build de producción.
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('./demo')
        .then((demo) => {
          if (cancelado) return
          setDatos(cargarDatos({
            leads: demo.LEADS_DEMO,
            actividades: demo.ACTIVIDADES_DEMO,
          }))
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

    return () => { cancelado = true }
  }, [demoSolicitado])

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
      if (!demoActivo) {
        toast.error('La fuente de datos del CRM aún no está habilitada')
        return { ok: false, codigo: 'fuente_no_habilitada', error: 'Fuente de datos no habilitada' }
      }
      return puedeEscribir(rol) ? null : sinPermiso()
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

    const buscar = (id: string) => datos.leads.find((l) => l.id === id)

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
        datos.actividades
          .filter((a) => a.lead_id === leadId)
          .sort((a, b) => b.creado_en.localeCompare(a.creado_en)),

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
        const choque = conflictoDedup(datos.leads, telefono, dni)
        if (choque) return choque
        // Espejo de la policy leads_insert: sin can('reasignar') el lead solo
        // puede nacer asignado a uno mismo (parkear es de supervisor/gerencia).
        if (!can(rol, 'reasignar') && (input.vendedor_id ?? null) !== (yo?.id ?? null)) {
          return { ok: false, codigo: 'solo_autoasignar', error: 'Solo puedes crear leads asignados a ti mismo' }
        }
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
          const choque = conflictoDedup(datos.leads, tel, dni, id)
          if (choque) return choque
        }
        aplicar(id, parche)
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
        return { ok: true }
      },

      convertir: (id) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa)) return { ok: false, codigo: 'lead_cerrado', error: 'El lead ya está cerrado' }
        aplicar(
          id,
          { etapa: 'convertido', motivo_descarte: null },
          actividadAuto(id, 'conversion', `Convertido a cliente desde ${ETAPA_INFO[actual.etapa].label} (demo)`),
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
        const choque = conflictoDedup(datos.leads, actual.telefono, actual.dni ?? null, id)
        if (choque) return choque
        aplicar(
          id,
          { etapa: 'nuevo', motivo_descarte: null },
          actividadAuto(id, 'cambio_etapa', `${ETAPA_INFO.descartado.label} → ${ETAPA_INFO.nuevo.label}`),
        )
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
        return { ok: true }
      },
    }
  }, [datos, yo, ambito, demoActivo, equipo, auxiliares])

  return (
    <StoreDataContext.Provider value={api}>
      <PanelActionsContext.Provider value={panelActions}>
        <PanelStateContext.Provider value={panelState}>
          {children}
        </PanelStateContext.Provider>
      </PanelActionsContext.Provider>
    </StoreDataContext.Provider>
  )
}
