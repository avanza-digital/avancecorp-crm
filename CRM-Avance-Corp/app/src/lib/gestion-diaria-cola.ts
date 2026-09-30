// Contrato de la cola completa: se valida antes de convertirla en controles.
// El servidor decide orden, estado y alcance. La selección es una clave, nunca
// un índice persistido que pudiera apuntar a otra persona tras una recarga.
import * as v from 'valibot'
import { SenalCarteraSchema, horaLimaDe, cuandoLimaDe, type FiltroCola, type FilaDiaria } from './gestion-diaria-analista'
import { RESULTADOS_LLAMADA, etiquetaResultado } from './resultado-llamada'

export const FILTROS_TRABAJO = ['todo', 'primera_atencion', 'tarea_vencida', 'tarea_hoy', 'sin_conversacion'] as const
const entero = v.pipe(v.number(), v.integer(), v.minValue(0))
const instante = v.pipe(v.string(), v.check((s) => Number.isFinite(Date.parse(s)), 'Fecha inválida'))
const clave = v.pipe(v.string(), v.regex(/^(lead|tarea):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/))
export const UltimaGestionSchema = v.object({
  actividad_id: v.string(), en: instante, resultado: v.picklist(RESULTADOS_LLAMADA),
  tarea_id: v.nullable(v.string()), etapa_anterior: v.nullable(v.string()),
})
const proximaTarea = v.object({ tarea_id: v.string(), vence_en: instante, tipo: v.string(), creado_en: instante })
const comunes = {
  clave, nombre_completo: v.string(), grupo: v.picklist(['primera_atencion', 'tarea_vencida', 'tarea_hoy', 'sin_conversacion']),
  referencia_en: v.nullable(instante), severidad: v.picklist(['critica', 'media', 'baja']),
  estado_trabajo: v.picklist(['pendiente', 'gestionado', 'programado']),
  ultima_gestion: v.nullable(UltimaGestionSchema), proxima_tarea: v.nullable(proximaTarea),
}
export const FilaTrabajoSchema = v.variant('tipo', [
  v.object({ ...comunes, tipo: v.literal('lead'), lead_id: v.string(), etapa: v.string(),
    tarea_id: v.nullable(v.string()), senal: SenalCarteraSchema }),
  v.object({ ...comunes, tipo: v.literal('cliente'), lead_id: v.null(), etapa: v.null(), senal: v.null(),
    tarea_id: v.string(), perfil_id: v.nullable(v.string()), inversionista_id: v.nullable(v.string()) }),
])
export type FilaTrabajo = v.InferOutput<typeof FilaTrabajoSchema>
export type UltimaGestion = v.InferOutput<typeof UltimaGestionSchema>
export function textoGestion(fila: FilaDiaria): string | null {
  const f = fila as Partial<FilaTrabajo>
  const ultima = f.ultima_gestion ? `${etiquetaResultado(f.ultima_gestion.resultado)} · ${horaLimaDe(f.ultima_gestion.en)}` : null
  const proxima = f.estado_trabajo === 'programado' && f.proxima_tarea
    ? `Programado ${cuandoLimaDe(f.proxima_tarea.vence_en)}` : null
  return [ultima, proxima].filter(Boolean).join(' · ') || null
}
const conteo = v.object({ total: entero, pendientes: entero, gestionados: entero, programados: entero })
export const ColaTrabajoSchema = v.object({
  version: v.literal(1), dia: v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/)), zona: v.literal('America/Lima'),
  analista_id: v.string(), generado_en: instante, filtro: v.picklist(FILTROS_TRABAJO),
  pagina: entero, limite: v.pipe(entero, v.minValue(1), v.maxValue(200)), total: entero,
  totales: v.object({ todo: conteo, primera_atencion: conteo, tarea_vencida: conteo, tarea_hoy: conteo, sin_conversacion: conteo }),
  items: v.array(FilaTrabajoSchema), elegido: v.nullable(clave), siguiente: v.nullable(clave),
  vuelta_completa: v.boolean(), proximo_cambio_en: instante,
})
export type ColaTrabajo = v.InferOutput<typeof ColaTrabajoSchema>
export interface PedidoColaTrabajo { filtro: FiltroCola; pagina: number; limite: number; elegido: string | null }

/** Consistencia interna y eco: una respuesta ajena o parcial nunca es una cola vacía. */
export function colaTrabajoCoherente(c: ColaTrabajo, p: PedidoColaTrabajo, actor: string, dia: string): boolean {
  const n = c.totales[c.filtro]
  const claves = new Set(c.items.map((f) => f.clave))
  return c.analista_id === actor && c.dia === dia && c.limite === p.limite
    && (c.filtro === p.filtro || (p.filtro !== 'todo' && p.elegido !== null && c.elegido === p.elegido))
    && c.total === n.total && c.vuelta_completa === (n.pendientes === 0)
    && FILTROS_TRABAJO.every((f) => {
      const t = c.totales[f]
      return t.total === t.pendientes + t.gestionados + t.programados
    })
    && c.totales.todo.total === FILTROS_TRABAJO.filter((f) => f !== 'todo').reduce((s, f) => s + c.totales[f].total, 0)
    && c.pagina <= Math.max(0, Math.ceil(c.total / c.limite) - 1)
    && c.items.length === Math.min(c.limite, Math.max(0, c.total - c.pagina * c.limite))
    && (p.elegido !== null && c.elegido === p.elegido || (
      c.pagina === Math.min(p.pagina, Math.max(0, Math.ceil(c.total / c.limite) - 1))
      && c.elegido === (c.items.find((f) => f.estado_trabajo === 'pendiente')?.clave ?? null)))
    && claves.size === c.items.length && (c.elegido === null || claves.has(c.elegido))
    && (c.siguiente === null || (n.pendientes > 0 && c.siguiente !== c.elegido))
    && c.items.every((f) => (c.filtro === 'todo' || f.grupo === c.filtro)
      && f.clave === (f.tipo === 'lead' ? `lead:${f.lead_id}` : `tarea:${f.tarea_id}`)
      && (f.tipo !== 'lead' || f.senal.lead_id === f.lead_id)
      && (f.estado_trabajo !== 'gestionado' || f.ultima_gestion !== null)
      && (f.estado_trabajo !== 'programado' || f.proxima_tarea !== null))
}

export interface ContextoColaTrabajo { filtro: FiltroCola; elegido: string | null; pagina: number }
const ContextoSchema = v.object({ filtro: v.picklist(FILTROS_TRABAJO), elegido: v.nullable(clave), pagina: entero })
const inicial: ContextoColaTrabajo = { filtro: 'todo', elegido: null, pagina: 0 }
export const claveContextoCola = (actor: string, dia: string) => `crm:gestion-diaria:cola:v1:${actor}:${dia}`

/** Guarda sólo navegación, por actor y día. El avance se relee del servidor. */
export function leerContextoCola(actor: string, dia: string): ContextoColaTrabajo {
  try {
    const r = v.safeParse(ContextoSchema, JSON.parse(sessionStorage.getItem(claveContextoCola(actor, dia)) ?? 'null'))
    return r.success ? r.output : { ...inicial }
  } catch { return { ...inicial } }
}
export function guardarContextoCola(actor: string, dia: string, contexto: ContextoColaTrabajo): void {
  try { sessionStorage.setItem(claveContextoCola(actor, dia), JSON.stringify(contexto)) } catch { /* Navegación usable si el navegador bloquea el almacenamiento. */ }
}
