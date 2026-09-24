import type { DiaEquipo } from './gestion-diaria-equipo'
import { horaCorte } from './gestion-diaria-avisos'

export const ESTADO_RESULTADO_CORTE = {
  pendiente: 'Sin evaluar', sin_cartera: 'Sin cartera abierta', cumplido: 'Cumplido',
  recuperado: 'Recuperado', incumplido: 'Bajo el mínimo',
} as const

/** Presenta la foto autorizada. No calcula objetivos, recuperación ni avisos. */
export function presentarCortesJornada(dia: DiaEquipo | null) {
  const cortes = dia?.cortes
  if (!dia || !cortes || cortes.estado !== 'activo') return []
  const nombres = new Map(dia.equipo.map((f) => [f.analista_id, f.nombre_completo]))
  return (['primer_corte', 'segundo_corte'] as const).flatMap((clave, indice) => {
    const instante = clave === 'primer_corte' ? cortes.primer_corte_en : cortes.segundo_corte_en
    if (!instante) return []
    const personas = cortes.equipo.flatMap((f) => f[clave] ? [{
      ...f[clave], analista: f.analista_id, nombre: nombres.get(f.analista_id)!,
    }] : [])
    const programado = Date.parse(dia.generado_en) < Date.parse(instante)
    const sinEvaluar = personas.filter((p) => p.estado === 'pendiente').length
    const estado = programado ? 'Programado' : sinEvaluar ? 'Evaluación pendiente' : 'Evaluado'
    const bajoMinimo = personas.filter((p) => p.estado === 'incumplido').length
    return [{ clave, titulo: indice === 0 ? 'Primer corte' : 'Segundo corte', instante,
      hora: horaCorte(instante), estado, personas, bajoMinimo,
      cumplidos: personas.filter((p) => p.estado === 'cumplido').length,
      recuperados: personas.filter((p) => p.estado === 'recuperado').length,
      sinCartera: personas.filter((p) => p.estado === 'sin_cartera').length,
      sinEvaluar,
    }]
  })
}
