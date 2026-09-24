import { diaEquipoPrueba, filaEquipoPrueba } from './gestion-diaria-equipo.fixture'
import type { CortesJornada } from './gestion-diaria-cortes'
import type { AvisosCortes } from './gestion-diaria-avisos'

export const idH4 = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
export function jornadaH4(dia = '2026-09-24', supervisor = idH4(1)) {
  const nombres = ['ANA H4', 'BRUNO H4', 'CARLA H4', 'DAVID H4']
  const equipo = diaEquipoPrueba(nombres.map((nombre, i) => {
    const llamadas = [2, 5, 5, 2][i]!
    const fila = filaEquipoPrueba({ analista_id: idH4(i + 2), nombre_completo: nombre,
      gestiones_hoy: llamadas, ultima_gestion_en: `${dia}T11:45:00-05:00`,
      tareas_pendientes: i === 0 ? 1 : 0, tareas_vencidas: i === 0 ? 1 : 0,
      motivos_atencion: i === 0 ? ['tarea_vencida'] : [], requiere_atencion: i === 0,
      llamadas_por_lead: 1, minutos_sin_llamar: 15 })
    fila.marcador = { ...fila.marcador, llamadas, contestadas: 1, utiles: llamadas,
      tasa_contacto_pct: 100 / llamadas, nivel: llamadas >= 5 ? 'bajo' : null,
      leads_tocados: llamadas, primera_llamada_en: `${dia}T11:00:00-05:00`, ultima_llamada_en: fila.ultima_gestion_en,
      por_resultado: { conversacion: 1, no_contesto: llamadas - 1 },
      por_hora: Array.from({ length: 13 }, (_, h) => ({ hora: h + 8, llamadas: h === 3 ? llamadas : 0, contestadas: h === 3 ? 1 : 0 })) }
    return fila
  }))
  equipo.dia = dia; equipo.supervisor_id = supervisor
  equipo.generado_en = `${dia}T12:00:00-05:00`; equipo.pendientes_al = equipo.generado_en
  equipo.umbrales.politica_version = 2
  const estados = ['incumplido', 'cumplido', 'recuperado', 'sin_cartera'] as const
  const cortes: CortesJornada = { version: 1, politica_version: 2, estado: 'activo', cartera_referencia: 'consulta_actual',
    inicio_jornada: `${dia}T09:00:00-05:00`, fin_jornada: `${dia}T18:00:00-05:00`,
    primer_corte_en: `${dia}T11:30:00-05:00`, segundo_corte_en: `${dia}T16:00:00-05:00`,
    equipo: equipo.equipo.map((p, i) => ({ analista_id: p.analista_id, cartera_abierta: i !== 3,
      primer_corte: { estado: estados[i]!, llamadas: i === 1 ? 4 : 1, objetivo: 3, base: i === 1 ? 4 : 1,
        llamadas_recuperacion: i === 2 ? 4 : 1, aviso_pendiente: i === 0, puede_avisar: i === 0 },
      segundo_corte: { estado: i === 3 ? 'sin_cartera' : 'pendiente', llamadas: null, objetivo: 8, base: i === 1 ? 4 : 1,
        llamadas_recuperacion: null, aviso_pendiente: false, puede_avisar: false },
    })),
  }
  equipo.cortes = cortes
  const avisos: AvisosCortes = { version: 1, supervisor_id: supervisor, dia, generado_en: equipo.generado_en,
    control_version: 1, avisos_habilitados: true, estado_cortes: 'activo',
    alertas: [{ id: `grupo:corte_manana:${supervisor}:${dia}`, tipo: 'corte_manana',
      corte_en: cortes.primer_corte_en!, fin_jornada: cortes.fin_jornada!,
      miembros: [{ analista_id: idH4(2), nombre: nombres[0]!, llamadas: 1, objetivo: 3, llamadas_recuperacion: 1 }],
      estado: 'pendiente', reconocido_en: null, pospuesto_hasta: null, puede_posponer: true, puede_presentar: false, entrega: 0 }],
    diarias: { modo_sla: 'activo', alertas: [{ id: `grupo:tarea_vencida:${supervisor}`, tipo: 'tarea_vencida',
      severidad: 'atencion', miembros: [idH4(20)], total: 1 }] },
    contexto: { en_jornada: true, analistas: 4, con_llamadas: 4,
      equipo: equipo.equipo.map((p) => ({ analista_id: p.analista_id, nombre: p.nombre_completo,
        primera_llamada_en: p.marcador.primera_llamada_en, llamadas: p.marcador.llamadas, sin_llamar_2h: false })) },
  }
  return { equipo, avisos }
}
