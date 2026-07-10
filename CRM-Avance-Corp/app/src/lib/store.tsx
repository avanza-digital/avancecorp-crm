// Store DEMO del CRM (F1b) — fuente de verdad de leads/actividades en memoria,
// sembrada desde lib/demo.ts y persistida en sessionStorage. JAMÁS escribe en
// Supabase. Write-gating con doble defensa: la UI oculta acciones y el store
// re-valida CADA mutación (toast.error + no-op si el rol no puede escribir).
// Debe montarse DENTRO de AuthProvider (usa useAuth para el gating y el autor).
import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type JSX,
  type ReactNode,
} from 'react'
import { toast } from 'sonner'
import { useAuth } from './auth'
import { can, puedeEscribir } from './roles'
import {
  ETAPA_INFO,
  MOTIVOS_DESCARTE,
  ORIGENES,
  type Actividad,
  type EtapaActiva,
  type Lead,
  type Miembro,
  type MotivoDescarte,
  type TipoActividad,
  type TipoActividadManual,
} from './tipos'
import type { Moneda } from './format'
import { ACTIVIDADES_DEMO, EQUIPO_DEMO, LEADS_DEMO } from './demo'

// v2: F1c re-siembra (20 leads + asignado_supervisor_id) — la clave vieja se ignora.
const CLAVE = 'ac-crm-demo-datos-v2'
const TERMINALES_K = new Set<string>(['convertido', 'descartado'])
// Tipos que SOLO emite el store al mutar (espejo del veto de actividades_insert).
const TIPOS_AUTO = new Set<string>(['cambio_etapa', 'reasignacion', 'conversion'])

export interface ResultadoMut {
  ok: boolean
  error?: string
}

export interface NuevoLeadInput {
  nombre_completo: string
  telefono: string
  correo?: string | null
  dni?: string | null
  distrito?: string | null
  origen: string
  etapa?: EtapaActiva // default 'nuevo' — un lead NUNCA nace terminal
  monto_estimado?: number | null
  moneda: Moneda
  categoria_interes?: 'nuevo' | 'renovacion' | 'upgrade' | null
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

export interface StoreApi {
  leads: Lead[] // todos, activos y terminales (legacy — preferir `ambito`)
  equipo: Miembro[]
  ambito: Ambito
  // Crudas, para lib/inteligencia (colaDe, estancados…). OJO: es el timeline
  // GLOBAL sin recorte (la RLS actividades_select SÍ recorta a leads visibles):
  // toda lista visible al usuario debe cruzarse con ambito.leads, nunca
  // iterarse directo — salvo el lector global (directorio).
  actividades: Actividad[]
  lead(id: string): Lead | undefined
  actividadesDe(leadId: string): Actividad[] // orden desc por creado_en
  // Paneles globales (drawer + modal se montan UNA vez en App.tsx)
  leadAbiertoId: string | null
  nuevoLeadAbierto: boolean
  etapaInicial: EtapaActiva
  abrirLead(id: string): void
  abrirNuevoLead(etapa?: EtapaActiva): void
  cerrarPaneles(): void
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

interface Datos {
  leads: Lead[]
  actividades: Actividad[]
}

// ── Helpers puros ─────────────────────────────────────────────────────────────

function uid(): string {
  try {
    return crypto.randomUUID()
  } catch {
    return `id-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
  }
}

/** Normaliza un celular peruano a +519######## (o null si no es válido). */
export function normalizarTelefono(v: string): string | null {
  const limpio = v.replace(/[\s\-().]/g, '')
  const sinMas = limpio.startsWith('+') ? limpio.slice(1) : limpio
  if (/^9\d{8}$/.test(sinMas)) return `+51${sinMas}`
  if (/^519\d{8}$/.test(sinMas)) return `+${sinMas}`
  return null
}

const esAbierto = (l: Lead) => l.activo && !TERMINALES_K.has(l.etapa)

/** Dedup vivo: teléfono/DNI no pueden repetirse entre leads abiertos. */
function conflictoDedup(
  leads: Lead[],
  telefono: string,
  dni: string | null | undefined,
  exceptoId?: string,
): string | null {
  const abiertos = leads.filter((l) => esAbierto(l) && l.id !== exceptoId)
  const porTel = abiertos.find((l) => l.telefono === telefono)
  if (porTel) return `Ese teléfono ya pertenece a un lead abierto: ${porTel.nombre_completo}`
  if (dni) {
    const porDni = abiertos.find((l) => l.dni === dni)
    if (porDni) return `Ese DNI ya pertenece a un lead abierto: ${porDni.nombre_completo}`
  }
  return null
}

function cargarDatos(): Datos {
  try {
    const crudo = sessionStorage.getItem(CLAVE)
    if (crudo) {
      const d = JSON.parse(crudo) as Datos
      if (Array.isArray(d?.leads) && Array.isArray(d?.actividades)) return d
    }
  } catch {
    /* sesión privada o JSON corrupto → siembra fresca */
  }
  return {
    leads: structuredClone(LEADS_DEMO),
    actividades: structuredClone(ACTIVIDADES_DEMO),
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

const Ctx = createContext<StoreApi | null>(null)

export function StoreProvider({ children }: { children: ReactNode }): JSX.Element {
  const { yo } = useAuth()
  const [datos, setDatos] = useState<Datos>(cargarDatos)

  // Paneles globales
  const [leadAbiertoId, setLeadAbiertoId] = useState<string | null>(null)
  const [nuevoLeadAbierto, setNuevoLeadAbierto] = useState(false)
  const [etapaInicial, setEtapaInicial] = useState<EtapaActiva>('nuevo')

  // Persistencia demo (solo sessionStorage — jamás Supabase)
  useEffect(() => {
    try {
      sessionStorage.setItem(CLAVE, JSON.stringify(datos))
    } catch {
      /* storage lleno o no disponible: seguimos solo en memoria */
    }
  }, [datos])

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
        vendedores: EQUIPO_DEMO.filter((m) => m.rol_crm === 'vendedor'),
        esGlobal: true,
      }
    }
    if (rol === 'supervisor' && miId) {
      // OJO espejo: aquí se usan reportes DIRECTOS (EQUIPO_DEMO es plano);
      // la RLS real usa un subárbol RECURSIVO (vendedor_ids_visibles) e
      // incluye parkeados de cualquier miembro del subárbol. Con supervisores
      // anidados este espejo mostraría MENOS que la RLS (infra-inclusivo, sin
      // fuga) — replicar la recursión al portar a datos reales.
      const mios = EQUIPO_DEMO.filter((m) => m.supervisor_id === miId)
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
      vendedores: EQUIPO_DEMO.filter((m) => m.perfil_id === miId),
      esGlobal: false,
    }
  }, [datos, yo])

  const api = useMemo<StoreApi>(() => {
    const rol = yo?.rol
    const autor = yo?.nombre_completo ?? 'DEMO'

    const sinPermiso = (): ResultadoMut => {
      toast.error('Tu rol es de solo lectura — no puedes modificar datos')
      return { ok: false, error: 'Sin permiso de escritura' }
    }

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
      equipo: EQUIPO_DEMO,
      ambito,
      actividades: datos.actividades,
      lead: (id) => buscar(id),
      actividadesDe: (leadId) =>
        datos.actividades
          .filter((a) => a.lead_id === leadId)
          .sort((a, b) => b.creado_en.localeCompare(a.creado_en)),

      leadAbiertoId,
      nuevoLeadAbierto,
      etapaInicial,
      abrirLead: (id) => {
        setNuevoLeadAbierto(false)
        setLeadAbiertoId(id)
      },
      abrirNuevoLead: (etapa) => {
        setLeadAbiertoId(null)
        setEtapaInicial(etapa ?? 'nuevo')
        setNuevoLeadAbierto(true)
      },
      cerrarPaneles: () => {
        setLeadAbiertoId(null)
        setNuevoLeadAbierto(false)
      },

      crearLead: (input) => {
        if (!puedeEscribir(rol)) return sinPermiso()
        const nombre = input.nombre_completo.trim()
        if (!nombre) return { ok: false, error: 'El nombre es obligatorio' }
        const telefono = normalizarTelefono(input.telefono)
        if (!telefono) {
          return { ok: false, error: 'Teléfono inválido — usa un celular peruano 9######## (se guarda como +51…)' }
        }
        const dni = input.dni?.trim() || null
        if (dni && !/^\d{8}$/.test(dni)) {
          return { ok: false, error: 'El DNI debe tener exactamente 8 dígitos' }
        }
        const etapa: EtapaActiva = input.etapa ?? 'nuevo'
        if (TERMINALES_K.has(etapa)) {
          return { ok: false, error: 'Un lead no puede nacer en etapa terminal' }
        }
        // Espejos de los CHECK de crm.leads (origen y monto_estimado >= 0).
        if (!ORIGENES.some((o) => o.k === input.origen)) {
          return { ok: false, error: 'Origen inválido' }
        }
        if (
          input.monto_estimado != null &&
          (!Number.isFinite(input.monto_estimado) || input.monto_estimado < 0)
        ) {
          return { ok: false, error: 'El monto estimado debe ser un número mayor o igual a 0' }
        }
        const choque = conflictoDedup(datos.leads, telefono, dni)
        if (choque) return { ok: false, error: choque }
        // Espejo de la policy leads_insert: sin can('reasignar') el lead solo
        // puede nacer asignado a uno mismo (parkear es de supervisor/gerencia).
        if (!can(rol, 'reasignar') && (input.vendedor_id ?? null) !== (yo?.id ?? null)) {
          return { ok: false, error: 'Solo puedes crear leads asignados a ti mismo' }
        }
        // Resuelve el vendedor SIN tragar ids inválidos (mismo criterio que reasignar()).
        let vendedor_id: string | null = null
        let vendedor_nombre: string | null = null
        if (input.vendedor_id) {
          const m = EQUIPO_DEMO.find((x) => x.perfil_id === input.vendedor_id)
          if (m) {
            vendedor_id = m.perfil_id
            vendedor_nombre = m.nombre_completo
          } else if (yo && input.vendedor_id === yo.id) {
            // Usuario (demo o sesión real) fuera de EQUIPO_DEMO: se auto-asigna igual.
            vendedor_id = yo.id
            vendedor_nombre = yo.nombre_completo
          } else {
            return { ok: false, error: 'Vendedor no encontrado' }
          }
        }
        // Espejo del WITH CHECK de leads_insert: supervisor solo dentro de su equipo.
        if (vendedorFueraDeAmbito(vendedor_id)) {
          return { ok: false, error: 'Ese vendedor no pertenece a tu equipo' }
        }
        const id = uid()
        const lead: Lead = {
          id,
          nombre_completo: nombre,
          telefono,
          correo: input.correo?.trim() || null,
          etapa,
          origen: input.origen,
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
        if (!puedeEscribir(rol)) return sinPermiso()
        const actual = buscar(id)
        if (!actual) return { ok: false, error: 'Lead no encontrado' }
        const parche: CambiosLead = { ...cambios }
        if (parche.nombre_completo !== undefined) {
          const n = (parche.nombre_completo ?? '').trim()
          if (!n) return { ok: false, error: 'El nombre es obligatorio' }
          parche.nombre_completo = n
        }
        if (parche.telefono !== undefined) {
          const tel = normalizarTelefono(parche.telefono ?? '')
          if (!tel) {
            return { ok: false, error: 'Teléfono inválido — usa un celular peruano 9######## (se guarda como +51…)' }
          }
          parche.telefono = tel
        }
        if (parche.dni !== undefined) {
          const dni = (parche.dni ?? '').trim()
          if (dni && !/^\d{8}$/.test(dni)) {
            return { ok: false, error: 'El DNI debe tener exactamente 8 dígitos' }
          }
          parche.dni = dni || null
        }
        if (parche.origen !== undefined && !ORIGENES.some((o) => o.k === parche.origen)) {
          return { ok: false, error: 'Origen inválido' }
        }
        if (
          parche.monto_estimado != null &&
          (!Number.isFinite(parche.monto_estimado) || parche.monto_estimado < 0)
        ) {
          return { ok: false, error: 'El monto estimado debe ser un número mayor o igual a 0' }
        }
        if (esAbierto(actual)) {
          const tel = parche.telefono ?? actual.telefono
          const dni = parche.dni !== undefined ? parche.dni : (actual.dni ?? null)
          const choque = conflictoDedup(datos.leads, tel, dni, id)
          if (choque) return { ok: false, error: choque }
        }
        aplicar(id, parche)
        return { ok: true }
      },

      cambiarEtapa: (id, etapa) => {
        if (!puedeEscribir(rol)) return sinPermiso()
        const actual = buscar(id)
        if (!actual) return { ok: false, error: 'Lead no encontrado' }
        if (TERMINALES_K.has(actual.etapa)) {
          return { ok: false, error: 'El lead está cerrado — reábrelo para moverlo de etapa' }
        }
        if (TERMINALES_K.has(etapa)) {
          return { ok: false, error: 'Usa convertir o descartar para cerrar un lead' }
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
        if (!puedeEscribir(rol)) return sinPermiso()
        const actual = buscar(id)
        if (!actual) return { ok: false, error: 'Lead no encontrado' }
        if (TERMINALES_K.has(actual.etapa)) return { ok: false, error: 'El lead ya está cerrado' }
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
        if (!puedeEscribir(rol)) return sinPermiso()
        const actual = buscar(id)
        if (!actual) return { ok: false, error: 'Lead no encontrado' }
        if (TERMINALES_K.has(actual.etapa)) return { ok: false, error: 'El lead ya está cerrado' }
        aplicar(
          id,
          { etapa: 'convertido', motivo_descarte: null },
          actividadAuto(id, 'conversion', `Convertido a cliente desde ${ETAPA_INFO[actual.etapa].label} (demo)`),
        )
        return { ok: true }
      },

      reabrir: (id) => {
        if (!puedeEscribir(rol)) return sinPermiso()
        const actual = buscar(id)
        if (!actual) return { ok: false, error: 'Lead no encontrado' }
        if (actual.etapa !== 'descartado') {
          return { ok: false, error: 'Solo se puede reabrir un lead descartado' }
        }
        const choque = conflictoDedup(datos.leads, actual.telefono, actual.dni ?? null, id)
        if (choque) return { ok: false, error: choque }
        aplicar(
          id,
          { etapa: 'nuevo', motivo_descarte: null },
          actividadAuto(id, 'cambio_etapa', `${ETAPA_INFO.descartado.label} → ${ETAPA_INFO.nuevo.label}`),
        )
        return { ok: true }
      },

      registrarActividad: (id, tipo, detalle) => {
        if (!puedeEscribir(rol)) return sinPermiso()
        const actual = buscar(id)
        if (!actual) return { ok: false, error: 'Lead no encontrado' }
        // Doble defensa (el tipo TS se borra en runtime): los tipos automáticos
        // los emite SOLO el store, y un lead cerrado no recibe actividad manual.
        if (TIPOS_AUTO.has(tipo)) {
          return { ok: false, error: 'Ese tipo de actividad lo genera el sistema — no se registra a mano' }
        }
        if (TERMINALES_K.has(actual.etapa)) {
          return { ok: false, error: 'El lead está cerrado — reábrelo para registrar actividad' }
        }
        const act = actividadAuto(id, tipo, detalle?.trim() || null)
        setDatos((d) => ({ ...d, actividades: [act, ...d.actividades] }))
        return { ok: true }
      },

      reasignar: (id, vendedorId) => {
        if (!puedeEscribir(rol)) return sinPermiso()
        if (!can(rol, 'reasignar')) {
          toast.error('No tienes permiso para reasignar leads')
          return { ok: false, error: 'Sin permiso para reasignar' }
        }
        const actual = buscar(id)
        if (!actual) return { ok: false, error: 'Lead no encontrado' }
        const nuevo = vendedorId ? EQUIPO_DEMO.find((m) => m.perfil_id === vendedorId) : undefined
        if (vendedorId && !nuevo) return { ok: false, error: 'Vendedor no encontrado' }
        // Espejo del WITH CHECK de leads_update: supervisor solo dentro de su equipo.
        if (vendedorFueraDeAmbito(vendedorId)) {
          return { ok: false, error: 'Ese vendedor no pertenece a tu equipo' }
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
  }, [datos, yo, ambito, leadAbiertoId, nuevoLeadAbierto, etapaInicial])

  return <Ctx.Provider value={api}>{children}</Ctx.Provider>
}

export function useStore(): StoreApi {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useStore fuera de StoreProvider')
  return ctx
}
