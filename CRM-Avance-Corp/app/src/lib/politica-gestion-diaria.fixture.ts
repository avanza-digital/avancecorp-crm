import type { PoliticaGestionDiaria, ConfiguracionGestionDiaria } from './politica-gestion-diaria'

export const politicaFixture: PoliticaGestionDiaria = {
  cortes_activos: false, corte_1_hora: '11:30', corte_1_minimo: 3,
  corte_2_hora: '16:00', corte_2_incremento_pct: 150, corte_2_piso: 8, corte_2_techo: 30,
  sabado_minimo: 3, bien_min_pct: 45, atencion_min_pct: 25,
  minimo_llamadas_utiles: 5, tasa_baja_diferencia_pp: null,
}

export function configuracionFixture(): ConfiguracionGestionDiaria {
  const vigente = { version: 1, vigente_desde: '-infinity', creado_en: '2026-09-22T16:00:00Z',
    creado_por: null, motivo: 'Histórica OFF', configuracion: { ...politicaFixture } }
  return { version: 1, dia: '2026-09-22', zona: 'America/Lima', puede_editar: true,
    expected_version: 1, vigente, revisiones_pendientes: [], historial: [vigente],
    control_avisos: { version: 1, habilitados: true, motivo: 'Canal inicial', creado_por: null, creado_en: '2026-09-22T16:00:00Z' } }
}
