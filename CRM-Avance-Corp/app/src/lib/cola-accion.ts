// lib/cola-accion.ts — contrato, mapper y espejo demo de crm.cola_accion_fn (F1b).
// En sesión real el SERVIDOR calcula la cola (cascada de buckets, severidad,
// relojes SLA, plan vigente/muerto) y manda items con INGREDIENTES
// (`datos_motivo`); el front redacta el motivo con redactarMotivoCola — la
// MISMA función que usa colaDe, así la campana de alertas (cliente hasta F3)
// y las pantallas no pueden contar historias distintas del mismo lead.
// En demo el shape completo se calcula del estado VIVO con colaDe/estancados.
import * as v from 'valibot'
import {
  colaDe,
  estancados,
  redactarMotivoCola,
  type BucketCola,
  type DatosMotivoCola,
  type ItemCola,
} from './inteligencia'
import { planPorLead } from './plan-lead'
import type { EstadoSlaLead } from './sla-versionado'
import {
  CATEGORIAS_INTERES,
  esGenero,
  esOrigen,
  type Actividad,
  type Lead,
  type Tarea,
} from './tipos'

/** Umbral y tope del bloque de estancados — fijados por el RPC (tanda 1). */
export const UMBRAL_ESTANCADOS_DIAS = 5
export const TOPE_ESTANCADOS = 50
/** p_limite por defecto — el default del propio RPC. */
export const LIMITE_COLA_ACCION = 100

const BUCKETS = [
  'por_repartir',
  'sin_responder',
  'sin_avance',
  'insistir',
  'propuesta_sin_respuesta',
  'seguimiento',
  'plan_vencido',
] as const

const SEVERIDADES = ['critica', 'media', 'baja'] as const

const DatosMotivoSchema = v.partial(v.object({
  espera_cliente_dias: v.number(),
  gestion_vencida: v.boolean(),
  contacto_vencido: v.boolean(),
  dias_en_etapa: v.number(),
  etapa_politica_version: v.nullable(v.number()),
  ultimo_intento_dias: v.number(),
  hablo: v.boolean(),
  dos_relojes: v.boolean(),
  tarea_titulo: v.string(),
  tarea_vence_en: v.string(),
}))

const LeadColaSchema = v.object({
  nombre_completo: v.string(),
  telefono: v.nullable(v.string()),
  correo: v.nullable(v.string()),
  genero: v.nullable(v.string()),
  no_contactar: v.boolean(),
  etapa: v.picklist(['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']),
  origen: v.nullable(v.string()),
  categoria_interes: v.nullable(v.string()),
  monto_estimado: v.number(),
  moneda: v.nullable(v.string()),
  creado_en: v.string(),
  tenencia_desde: v.nullable(v.string()),
  vendedor_id: v.nullable(v.string()),
  asignado_supervisor_id: v.nullable(v.string()),
  motivo_descarte: v.nullable(v.string()),
})

export const ColaAccionSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  p_limite: v.number(),
  resumen: v.object({
    total: v.number(),
    por_bucket: v.record(v.string(), v.number()),
    por_sev: v.record(v.string(), v.number()),
  }),
  items: v.array(v.object({
    lead_id: v.string(),
    bucket: v.picklist(BUCKETS),
    sev: v.picklist(SEVERIDADES),
    dias: v.number(),
    ultimo_contacto_en: v.nullable(v.string()),
    datos_motivo: DatosMotivoSchema,
    lead: LeadColaSchema,
  })),
  estancados: v.object({
    umbral_dias: v.number(),
    tope: v.number(),
    items: v.array(v.object({
      lead_id: v.string(),
      nombre_completo: v.string(),
      vendedor_id: v.nullable(v.string()),
      dias: v.number(),
    })),
  }),
})

export type ColaAccion = v.InferOutput<typeof ColaAccionSchema>

export interface EstancadoCola {
  leadId: string
  nombre: string
  vendedorId: string | null
  dias: number
}

/** La cola en el shape que consumen las pantallas (real y demo idénticos). */
export interface ColaAccionOperativa {
  /** Items YA ordenados (sev, días desc — el orden lo decide quien calcula). */
  items: ItemCola[]
  /** Total del universo SIN el recorte de p_limite (para el «+N más»). */
  total: number
  porBucket: Readonly<Partial<Record<BucketCola, number>>>
  porSev: Readonly<Partial<Record<ItemCola['sev'], number>>>
  estancados: EstancadoCola[]
  generadoEn: string
}

/**
 * Lead mínimo construido desde el payload del RPC — SOLO para el caso borde en
 * que el lead de un item no está en el ámbito cargado (p. ej. más allá del
 * tope de 2000 filas). Mientras el store viva (hasta F3), el camino normal es
 * re-unir por id con el Lead COMPLETO de memoria, que conserva hover/drawer
 * con toda su ficha.
 */
function leadDesdeItem(item: {
  lead_id: string
  lead: v.InferOutput<typeof LeadColaSchema>
}): Lead {
  const l = item.lead
  return {
    id: item.lead_id,
    nombre_completo: l.nombre_completo,
    telefono: l.telefono ?? '',
    correo: l.correo,
    genero: l.genero != null && esGenero(l.genero) ? l.genero : null,
    etapa: l.etapa,
    origen: l.origen != null && esOrigen(l.origen) ? l.origen : 'otro',
    monto_estimado: l.monto_estimado,
    moneda: l.moneda === 'USD' ? 'USD' : 'PEN',
    categoria_interes: CATEGORIAS_INTERES.some((c) => c.k === l.categoria_interes)
      ? (l.categoria_interes as (typeof CATEGORIAS_INTERES)[number]['k'])
      : null,
    vendedor_id: l.vendedor_id,
    asignado_supervisor_id: l.asignado_supervisor_id,
    creado_en: l.creado_en,
    tenencia_desde: l.tenencia_desde,
    activo: true, // el RPC solo trabaja abiertos
    no_contactar: l.no_contactar,
  }
}

function contar<K extends string>(claves: readonly K[], crudo: Record<string, number>): Partial<Record<K, number>> {
  const salida: Partial<Record<K, number>> = {}
  for (const k of claves) {
    const n = crudo[k]
    if (typeof n === 'number' && n > 0) salida[k] = n
  }
  return salida
}

/**
 * Payload del RPC → shape operativo. El ORDEN de los items se respeta tal cual
 * llega (el servidor ya ordenó por severidad y días con desempate por id);
 * re-ordenar aquí desharía el desempate determinista.
 */
export function mapearColaAccion(
  payload: ColaAccion,
  buscarLead: (id: string) => Lead | undefined,
): ColaAccionOperativa {
  return {
    items: payload.items.map((item) => ({
      lead: buscarLead(item.lead_id) ?? leadDesdeItem(item),
      bucket: item.bucket,
      sev: item.sev,
      dias: item.dias,
      motivo: redactarMotivoCola(
        item.bucket,
        item.dias,
        item.lead.etapa,
        item.datos_motivo as DatosMotivoCola,
      ),
    })),
    total: payload.resumen.total,
    porBucket: contar(BUCKETS, payload.resumen.por_bucket),
    porSev: contar(SEVERIDADES, payload.resumen.por_sev),
    estancados: payload.estancados.items.map((e) => ({
      leadId: e.lead_id,
      nombre: e.nombre_completo,
      vendedorId: e.vendedor_id,
      dias: e.dias,
    })),
    generadoEn: payload.generado_en,
  }
}

/**
 * Espejo demo sobre el estado VIVO del store: colaDe + planPorLead + estancados
 * — exactamente lo que las pantallas calculaban hasta F1b, empaquetado en el
 * MISMO shape que el mapper del RPC. Crear/mover un lead en demo mueve la cola
 * al instante (bloqueante del plan F1: el espejo jamás lee la semilla estática).
 */
export function colaAccionDesdeAmbito(
  leads: readonly Lead[],
  actividades: readonly Actividad[],
  tareas: readonly Tarea[],
  ahoraMs: number,
  indiceSla?: ReadonlyMap<string, EstadoSlaLead>,
  limite: number = LIMITE_COLA_ACCION,
): ColaAccionOperativa {
  const plan = planPorLead([...tareas], ahoraMs)
  // Los RESÚMENES se cuentan sobre la cola completa y los items se recortan al
  // MISMO límite que el RPC — si el espejo listara 150 donde real lista 100,
  // demo y real contarían películas distintas (revisión Codex).
  const completos = colaDe([...leads], [...actividades], ahoraMs, plan, indiceSla)
  const items = completos.slice(0, limite)
  const porBucket: Partial<Record<BucketCola, number>> = {}
  const porSev: Partial<Record<ItemCola['sev'], number>> = {}
  for (const item of completos) {
    porBucket[item.bucket] = (porBucket[item.bucket] ?? 0) + 1
    porSev[item.sev] = (porSev[item.sev] ?? 0) + 1
  }
  const estancamiento = estancados(
    [...leads],
    [...actividades],
    UMBRAL_ESTANCADOS_DIAS,
    ahoraMs,
    undefined,
    plan.vigente,
  )
  return {
    items,
    total: completos.length,
    porBucket,
    porSev,
    estancados: estancamiento.slice(0, TOPE_ESTANCADOS).map((e) => ({
      leadId: e.lead.id,
      nombre: e.lead.nombre_completo,
      vendedorId: e.lead.vendedor_id ?? null,
      dias: e.dias,
    })),
    generadoEn: new Date(ahoraMs).toISOString(),
  }
}
