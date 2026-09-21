import { resumenEquipo, type DiaEquipo, type FilaEquipoDiario } from './gestion-diaria-equipo'

export function filaEquipoPrueba(cambios: Partial<FilaEquipoDiario> = {}): FilaEquipoDiario {
  return {
    analista_id: 'a1', nombre_completo: 'ANA PÉREZ', gestiones_hoy: 0, ultima_gestion_en: null,
    marcador: { llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null,
      leads_tocados: 0, citas_agendadas: 0, primera_llamada_en: null, ultima_llamada_en: null, por_resultado: {}, por_hora: [] },
    llamadas_por_lead: null, minutos_sin_llamar: null, tareas_pendientes: 0, tareas_vencidas: 0,
    citas_hoy: 0, primer_intento_vencido: 0, datos_incompletos: 0, sin_llamar_2h: false,
    motivos_atencion: [], requiere_atencion: false, ...cambios,
  }
}
export function diaEquipoPrueba(equipo: FilaEquipoDiario[] = [filaEquipoPrueba()]): DiaEquipo {
  return {
    version: 1, dia: '2026-09-21', generado_en: '2026-09-21T15:00:00Z', zona: 'America/Lima',
    supervisor_id: 's1', pendientes_al: '2026-09-21T15:00:00Z', modo_sla: 'activo',
    umbrales: { version: 1, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 },
    equipo, resumen: resumenEquipo(equipo),
  }
}
