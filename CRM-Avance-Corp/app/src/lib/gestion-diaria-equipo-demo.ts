import type { Actividad, Lead, Miembro, Tarea } from './tipos'
import { diaAnalistaDesdeDemo } from './gestion-diaria-analista'
import { fechaLima } from './agenda-derivada'
import { resumenEquipo, type DiaEquipo, type FilaEquipoDiario } from './gestion-diaria-equipo'

/** Subárbol de un supervisor; recorrer con Set evita ciclos. */
function subarbolDemo(supervisorId: string, miembros: readonly Miembro[]): Set<string> {
  const ids = new Set([supervisorId])
  let cambio = true
  while (cambio) {
    cambio = false
    for (const m of miembros) {
      if (m.supervisor_id && ids.has(m.supervisor_id) && !ids.has(m.perfil_id)) {
        ids.add(m.perfil_id); cambio = true
      }
    }
  }
  return ids
}

/**
 * Sólo demo: el roster no depende de tener leads. `null` = toda la operación
 * (gerencia), como `gestion_diaria_equipo_fn` sin `p_supervisor_id`.
 */
export function diaEquipoDesdeDemo(supervisorId: string | null, miembros: readonly Miembro[], leads: readonly Lead[],
  actividades: readonly Actividad[], tareas: readonly Tarea[], ahora: number, dia: string): DiaEquipo {
  const ids = supervisorId === null ? null : subarbolDemo(supervisorId, miembros)
  const equipo = miembros.filter((m) => m.activo && m.rol_crm === 'vendedor' && (ids === null || ids.has(m.perfil_id))).map((m): FilaEquipoDiario => {
    // El fixture demo identifica al autor por nombre, no por dueño actual del lead.
    const propias = actividades.filter((a) => a.autor_nombre === m.nombre_completo && !a.local)
    const { marcador } = diaAnalistaDesdeDemo(m.perfil_id, leads, propias, tareas, ahora, dia)
    if (marcador.utiles >= 5) {
      const tasa = 100 * marcador.contestadas / marcador.utiles
      marcador.nivel = tasa >= 45 ? 'bien' : tasa >= 25 ? 'atencion' : 'bajo'
    }
    const gestiones = propias.filter((a) => fechaLima(Date.parse(a.creado_en)) === dia
      && ['llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'reunion_realizada', 'nota', 'conversion'].includes(a.tipo))
    const pendientes = tareas.filter((t) => t.activo && t.estado === 'pendiente'
      && (t.vendedor_id ?? leads.find((l) => l.id === t.lead_id)?.vendedor_id) === m.perfil_id)
    const vencidas = pendientes.filter((t) => Date.parse(t.vence_en) < ahora).length
    const inicio = Date.parse(`${dia}T09:00:00-05:00`)
    const semana = new Date(`${dia}T12:00:00Z`).getUTCDay()
    const fin = Date.parse(`${dia}T${semana === 6 ? '13' : '18'}:00:00-05:00`)
    const ultima = marcador.ultima_llamada_en === null ? null : Date.parse(marcador.ultima_llamada_en)
    const parado = fechaLima(ahora) === dia && semana !== 0 && ahora >= inicio && ahora < fin
      && ahora - Math.max(ultima ?? inicio, inicio) > 7_200_000
    const motivos: FilaEquipoDiario['motivos_atencion'] = []
    if (vencidas > 0) motivos.push('tarea_vencida')
    if (parado) motivos.push('sin_llamar_2h')
    return {
      analista_id: m.perfil_id, nombre_completo: m.nombre_completo, marcador,
      gestiones_hoy: gestiones.length,
      ultima_gestion_en: gestiones.map((a) => a.creado_en).sort().at(-1) ?? null,
      llamadas_por_lead: marcador.leads_tocados > 0 ? Math.round(10 * marcador.llamadas / marcador.leads_tocados) / 10 : null,
      minutos_sin_llamar: ultima === null ? null : Math.max(0, Math.floor((ahora - ultima) / 60_000)),
      tareas_pendientes: pendientes.length, tareas_vencidas: vencidas,
      citas_hoy: pendientes.filter((t) => t.tipo === 'reunion' && fechaLima(Date.parse(t.vence_en)) === dia).length,
      primer_intento_vencido: null, datos_incompletos: null, sin_llamar_2h: parado,
      motivos_atencion: motivos, requiere_atencion: motivos.length > 0,
    }
  })
  return {
    version: 1, dia, zona: 'America/Lima', supervisor_id: supervisorId,
    generado_en: new Date(ahora).toISOString(), pendientes_al: new Date(ahora).toISOString(),
    umbrales: { version: 1, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 },
    // No se inventan vencimientos del servidor en el espejo.
    modo_sla: 'observacion', equipo, resumen: resumenEquipo(equipo),
  }
}
