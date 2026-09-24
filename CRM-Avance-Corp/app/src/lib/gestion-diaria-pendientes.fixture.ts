import type { PaginaPendientes, PedidoPendientes, PendienteSupervisor } from './gestion-diaria-pendientes'

export const idPendiente = (n: number) => `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`
export const pedidoPendientes: PedidoPendientes = { supervisor: idPendiente(1), analista: idPendiente(2), soloVencidas: false, limite: 25, cursor: null }
export const tareaPendiente = (n = 10, cambios: Partial<PendienteSupervisor> = {}): PendienteSupervisor => ({
  id: idPendiente(n), vendedor_id: pedidoPendientes.analista, tipo: 'llamada', titulo: `Tarea ${n}`,
  vence_en: '2026-09-23T15:00:00.000001+00:00', estado: 'pendiente', referencia_tipo: 'lead', lead_id: idPendiente(3), lead_nombre: 'Lead visible', ...cambios,
})
export function paginaPendientes(items: PendienteSupervisor[] = [tareaPendiente()], cambios: Partial<PaginaPendientes> = {}): PaginaPendientes {
  return { version: 1, zona: 'America/Lima', supervisor_id: pedidoPendientes.supervisor, analista_id: pedidoPendientes.analista,
    generado_en: '2026-09-23T17:00:00.000001+00:00', pendientes_al: '2026-09-23T17:00:00.000001+00:00',
    solo_vencidas: false, limite: 25, resumen: { tareas_pendientes: items.length, tareas_vencidas: items.length },
    items, hay_mas: false, siguiente_cursor: null, ...cambios }
}
