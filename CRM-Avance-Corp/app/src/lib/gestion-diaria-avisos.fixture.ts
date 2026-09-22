import type { AvisosCortes } from './gestion-diaria-avisos'

const supervisor = '00000000-0000-4000-8000-000000000001'
export function avisosFixture(): AvisosCortes {
  return {
    version: 1, supervisor_id: supervisor, dia: '2026-09-22', generado_en: '2026-09-22T17:00:00Z',
    control_version: 1, avisos_habilitados: true, estado_cortes: 'activo',
    alertas: [{ id: `grupo:corte_manana:${supervisor}:2026-09-22`, tipo: 'corte_manana',
      corte_en: '2026-09-22T16:30:00Z', fin_jornada: '2026-09-22T23:00:00Z',
      miembros: [{ analista_id: '00000000-0000-4000-8000-000000000002', nombre: 'Analista de prueba',
        llamadas: 0, objetivo: 3, llamadas_recuperacion: 1 }],
      estado: 'pendiente', reconocido_en: null, pospuesto_hasta: null,
      puede_posponer: true, puede_presentar: true, entrega: 0 }],
  }
}
