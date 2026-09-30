// Espejo exclusivo del modo demo. En real, el servidor devuelve la página y
// los conteos completos: ninguna selección de negocio se calcula aquí.
import { filasDiariasDemo, type DiaAnalista, type FilaDiaria } from './gestion-diaria-analista'
import { FILTROS_TRABAJO, type ColaTrabajo, type FilaTrabajo, type PedidoColaTrabajo } from './gestion-diaria-cola'
import { esResultadoLlamada } from './resultado-llamada'
import type { Actividad, Tarea } from './tipos'
import { fechaLima } from './agenda-derivada'

export function paginarTrabajoDemo(filas: readonly FilaTrabajo[], p: PedidoColaTrabajo, actor: string, dia: string, ahora: number): ColaTrabajo {
  const ancla = filas.find((f) => f.clave === p.elegido)
  const filtro = ancla && p.filtro !== 'todo' ? ancla.grupo : p.filtro
  const totales = Object.fromEntries(FILTROS_TRABAJO.map((clave) => {
    const grupo = filas.filter((f) => clave === 'todo' || f.grupo === clave)
    return [clave, { total: grupo.length, pendientes: grupo.filter((f) => f.estado_trabajo === 'pendiente').length,
      gestionados: grupo.filter((f) => f.estado_trabajo === 'gestionado').length,
      programados: grupo.filter((f) => f.estado_trabajo === 'programado').length }]
  })) as ColaTrabajo['totales']
  const ordenadas = filas.filter((f) => filtro === 'todo' || f.grupo === filtro).sort((a, b) => {
    const ap = a.estado_trabajo === 'pendiente', bp = b.estado_trabajo === 'pendiente'
    if (ap !== bp) return ap ? -1 : 1
    const grupo = ap ? FILTROS_TRABAJO.indexOf(a.grupo) - FILTROS_TRABAJO.indexOf(b.grupo) : 0
    const t = (f: FilaTrabajo) => ap ? f.referencia_en ? Date.parse(f.referencia_en) : Infinity
      : f.ultima_gestion ? Date.parse(f.ultima_gestion.en) : 0
    return grupo || t(a) - t(b) || a.clave.localeCompare(b.clave)
  })
  const posicion = ordenadas.findIndex((f) => f.clave === p.elegido)
  const pagina = posicion >= 0 ? Math.floor(posicion / p.limite) : Math.min(p.pagina, Math.max(0, Math.ceil(ordenadas.length / p.limite) - 1))
  const items = ordenadas.slice(pagina * p.limite, (pagina + 1) * p.limite)
  const elegido = posicion >= 0 ? p.elegido : items.find((f) => f.estado_trabajo === 'pendiente')?.clave ?? null
  const despues = posicion >= 0 ? posicion : pagina * p.limite
  const recorrido = [...ordenadas.slice(despues + 1), ...ordenadas.slice(0, despues + 1)]
  return { version: 1, analista_id: actor, dia, zona: 'America/Lima', generado_en: new Date(ahora).toISOString(),
    filtro, pagina, limite: p.limite, total: ordenadas.length, totales, items, elegido,
    siguiente: recorrido.find((f) => f.clave !== elegido && f.estado_trabajo === 'pendiente')?.clave ?? null,
    vuelta_completa: totales[filtro].pendientes === 0, proximo_cambio_en: new Date(ahora + 60_000).toISOString() }
}

export function filasTrabajoDemo(dia: DiaAnalista, tareas: readonly Tarea[], actividades: readonly Actividad[], ahora: number): FilaTrabajo[] {
  const filas = filasDiariasDemo(dia.cartera, ahora, dia.dia, tareas, dia.analista_id)
  const porLead = new Map(filas.filter((f) => f.tipo === 'lead').map((f) => [f.lead_id, f]))
  const resultado: FilaTrabajo[] = filas.filter((f) => f.tipo === 'cliente').map((f) => ({ ...f,
    estado_trabajo: 'pendiente', ultima_gestion: null, proxima_tarea: null }))
  for (const senal of dia.cartera) {
    const desde = Math.max(Date.parse(senal.tenencia_desde ?? '' ) || 0, Date.parse(senal.ciclo_desde ?? '') || 0)
    const g = actividades.filter((a) => a.lead_id === senal.lead_id && a.metadata?.evento === 'resultado_llamada'
      && !a.metadata.deshecho_en && fechaLima(Date.parse(a.creado_en)) === dia.dia && Date.parse(a.creado_en) >= desde)
      .sort((a, b) => Date.parse(b.creado_en) - Date.parse(a.creado_en))[0]
    const meta = g?.metadata
    const ultima = g && meta && typeof meta.resultado === 'string' && esResultadoLlamada(meta.resultado) ? {
      actividad_id: g.id, en: g.creado_en, resultado: meta.resultado,
      tarea_id: typeof meta.tarea_id === 'string' ? meta.tarea_id : null,
      etapa_anterior: typeof meta.etapa_anterior === 'string' ? meta.etapa_anterior : null,
    } : null
    const t = tareas.filter((t) => t.lead_id === senal.lead_id && t.vendedor_id === dia.analista_id && t.activo && t.estado === 'pendiente')
      .sort((a, b) => Date.parse(a.vence_en) - Date.parse(b.vence_en))[0]
    const cerrada = ultima?.tarea_id ? tareas.find((t) => t.id === ultima.tarea_id) : null
    const fila: FilaDiaria | undefined = porLead.get(senal.lead_id) ?? (ultima ? {
      tipo: 'lead', clave: `lead:${senal.lead_id}`, lead_id: senal.lead_id, nombre_completo: senal.nombre_completo,
      etapa: senal.etapa, tarea_id: null, senal, severidad: 'media', referencia_en: cerrada?.vence_en ?? senal.ultima_conversacion_en,
      grupo: cerrada ? Date.parse(cerrada.vence_en) < Date.parse(ultima.en) ? 'tarea_vencida' : 'tarea_hoy'
        : ultima.etapa_anterior === 'nuevo' ? 'primera_atencion' : 'sin_conversacion',
    } : undefined)
    if (!fila || fila.tipo !== 'lead') continue
    const estado = ultima && (!t || Date.parse(t.vence_en) <= Date.parse(ultima.en)) ? 'gestionado'
      : t && Date.parse(t.vence_en) > ahora ? 'programado' : 'pendiente'
    resultado.push({ ...fila, senal, estado_trabajo: estado, ultima_gestion: ultima,
      tarea_id: estado === 'pendiente' ? fila.tarea_id ?? t?.id ?? null : null,
      proxima_tarea: t ? { tarea_id: t.id, vence_en: t.vence_en, tipo: t.tipo, creado_en: t.creado_en } : null })
  }
  return resultado
}
