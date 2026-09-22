// F4.4: la decisión de presentar/reconocer/posponer procede del servidor.
import * as v from 'valibot'
import { AlertasDiariasSchema, ContextoDiarioSchema } from './gestion-diaria-alertas'

const Uuid = v.pipe(v.string(), v.uuid())
const Instante = v.pipe(v.string(), v.check((s) => Number.isFinite(Date.parse(s))))
const Natural = v.pipe(v.number(), v.integer(), v.minValue(0))
const Positivo = v.pipe(v.number(), v.integer(), v.minValue(1))

export const AvisoCorteSchema = v.pipe(v.strictObject({
  id: v.string(),
  tipo: v.picklist(['corte_manana', 'corte_tarde']),
  corte_en: Instante,
  fin_jornada: Instante,
  miembros: v.pipe(v.array(v.strictObject({
    analista_id: Uuid,
    nombre: v.string(),
    llamadas: Natural,
    objetivo: Positivo,
    llamadas_recuperacion: v.nullable(Natural),
  })), v.minLength(1)),
  estado: v.picklist(['pendiente', 'reconocido', 'pospuesto']),
  reconocido_en: v.nullable(Instante),
  pospuesto_hasta: v.nullable(Instante),
  puede_posponer: v.boolean(),
  puede_presentar: v.boolean(),
  entrega: v.picklist([0, 1]),
}), v.check((a) => Date.parse(a.corte_en) < Date.parse(a.fin_jornada)
  && new Set(a.miembros.map((m) => m.analista_id)).size === a.miembros.length
  && a.miembros.every((m) => m.llamadas < m.objetivo)
  && (a.estado === 'reconocido') === (a.reconocido_en !== null)
  && (a.estado !== 'pospuesto' || a.pospuesto_hasta !== null)
  && (!a.puede_presentar || a.estado === 'pendiente')
  && (!a.puede_posponer || (a.entrega === 0 && a.estado === 'pendiente')),
'El aviso tiene un estado incoherente'))

export const AvisosCortesSchema = v.pipe(v.strictObject({
  version: v.literal(1),
  supervisor_id: Uuid,
  dia: v.pipe(v.string(), v.isoDate()),
  generado_en: Instante,
  control_version: Positivo,
  avisos_habilitados: v.boolean(),
  estado_cortes: v.picklist(['desactivados', 'no_laborable', 'activo']),
  alertas: v.array(AvisoCorteSchema),
  diarias: v.optional(AlertasDiariasSchema),
  contexto: v.optional(ContextoDiarioSchema),
}), v.check((r) => r.alertas.length <= 2
  && (r.diarias === undefined) === (r.contexto === undefined)
  && (r.diarias?.alertas.every((a) => a.id === `grupo:${a.tipo}:${r.supervisor_id}`
    && (a.tipo !== 'parado_2h' || (r.contexto!.en_jornada && a.miembros.every((id) =>
      r.contexto!.equipo.some((e) => e.analista_id === id && e.sin_llamar_2h)
      && !r.alertas.some((c) => c.miembros.some((m) => m.analista_id === id)))))) ?? true)
  && new Set(r.alertas.map((a) => a.id)).size === r.alertas.length
  && (r.estado_cortes === 'activo' || r.alertas.length === 0)
  && r.alertas.every((a) => a.id === `grupo:${a.tipo}:${r.supervisor_id}:${r.dia}`
    && (r.avisos_habilitados || (!a.puede_presentar && !a.puede_posponer))
    && (!a.puede_presentar || (Date.parse(r.generado_en) >= Date.parse(a.corte_en)
      && Date.parse(r.generado_en) < Date.parse(a.fin_jornada)))),
'La respuesta no corresponde al supervisor y la jornada'))

export const PresentacionCorteSchema = v.strictObject({
  version: v.literal(1),
  solicitud_id: Uuid,
  aviso: v.nullable(AvisoCorteSchema),
})
export type AvisoCorte = v.InferOutput<typeof AvisoCorteSchema>
export type AvisosCortes = v.InferOutput<typeof AvisosCortesSchema>

export function tituloCorte(aviso: Pick<AvisoCorte, 'tipo'>): string {
  return aviso.tipo === 'corte_manana' ? 'Primer corte de llamadas' : 'Segundo corte de llamadas'
}

export function horaCorte(instante: string): string {
  return new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit',
    minute: '2-digit', hourCycle: 'h23' }).format(new Date(instante))
}

export function estadoCorte(aviso: AvisoCorte): string {
  if (aviso.estado === 'reconocido') return 'Reconocido; el resultado del corte se conserva.'
  if (aviso.estado === 'pospuesto' && aviso.pospuesto_hasta) {
    return Date.parse(aviso.pospuesto_hasta) >= Date.parse(aviso.fin_jornada)
      ? 'Pospuesto; sin reaviso antes del cierre. El pendiente sigue visible.'
      : `Pospuesto hasta las ${horaCorte(aviso.pospuesto_hasta)}; el pendiente sigue visible.`
  }
  return 'Pendiente de atención.'
}
