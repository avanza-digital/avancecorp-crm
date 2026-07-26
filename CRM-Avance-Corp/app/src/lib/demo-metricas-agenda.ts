// Fixture DETERMINISTA del panel "Agenda del equipo" para el modo demo: el
// subárbol de SUPERVISOR UNO tal como lo devolvería crm.metricas_agenda_fn
// (mismos miembros demo de lib/demo.ts EQUIPO_DEMO, array ordenado por nombre
// como lo entrega la RPC). Los números son plausibles y coherentes entre sí:
// pct_completadas sale de los cierres y toques_por_dia de toques/días.
import type { MetricaAgendaVendedor, MetricasAgenda } from './metricas-agenda'

/** Días calendario INCLUSIVOS entre dos 'YYYY-MM-DD' (mínimo 1). */
function diasDelPeriodo(desde: string, hasta: string): number {
  const ms = Date.parse(`${hasta}T00:00:00Z`) - Date.parse(`${desde}T00:00:00Z`)
  if (!Number.isFinite(ms)) return 1
  return Math.max(1, Math.round(ms / 86_400_000) + 1)
}

/** Redondeo a 1 decimal (mismo criterio de presentación que la RPC). */
function unDecimal(valor: number): number {
  return Math.round(valor * 10) / 10
}

type NumerosAgenda = Omit<
  MetricaAgendaVendedor,
  'vendedor_id' | 'nombre' | 'rol' | 'activo' | 'toques_por_dia'
>

function miembro(
  vendedorId: string,
  nombre: string,
  rol: MetricaAgendaVendedor['rol'],
  dias: number,
  numeros: NumerosAgenda,
): MetricaAgendaVendedor {
  return {
    vendedor_id: vendedorId,
    nombre,
    rol,
    activo: true,
    toques_por_dia: unDecimal(numeros.toques / dias),
    ...numeros,
  }
}

export function metricasAgendaDemo(desde: string, hasta: string): MetricasAgenda {
  const dias = diasDelPeriodo(desde, hasta)
  return {
    version: 1,
    generado_en: new Date().toISOString(),
    periodo: { desde, hasta, dias, zona: 'America/Lima' },
    // Ordenado por nombre, como lo entrega la RPC.
    vendedores: [
      // El supervisor casi no registra agenda propia (gestiona, no vende).
      miembro('d-sup1', 'SUPERVISOR UNO', 'supervisor', dias, {
        toques: 2,
        reuniones_realizadas: 0,
        completadas: 1,
        no_asistio: 0,
        canceladas: 0,
        pct_completadas: 100,
        tareas_creadas: 1,
        reuniones_agendadas: 0,
        reprogramaciones: 0,
        pendientes: 1,
        vencidas: 0,
        leads_sin_accion: 0,
      }),
      // Menos volumen y más rezago: 2 no-shows (rojo) y vencidas acumuladas.
      miembro('d-v2', 'VENDEDOR DOS', 'vendedor', dias, {
        toques: 8,
        reuniones_realizadas: 2,
        completadas: 3,
        no_asistio: 2,
        canceladas: 0,
        pct_completadas: 60,
        tareas_creadas: 5,
        reuniones_agendadas: 2,
        reprogramaciones: 1,
        pendientes: 4,
        vencidas: 2,
        leads_sin_accion: 3,
      }),
      // El más activo: 14 toques y 5 de 7 cierres completados (71 %).
      // Es también el único que muestra la SEPARACIÓN de canceladas: 3 en total,
      // pero solo 1 la anuló él (esa sí cuenta en el denominador: 5+1+1 = 7) y
      // 2 las cerró el sistema al convertirse el lead — que no le penalizan.
      // Sin este caso el fixture no ejercitaría la mitad nueva del panel.
      miembro('d-v1', 'VENDEDOR UNO', 'vendedor', dias, {
        toques: 14,
        reuniones_realizadas: 4,
        completadas: 5,
        no_asistio: 1,
        canceladas: 3,
        canceladas_asesor: 1,
        canceladas_sistema: 2,
        pct_completadas: 71,
        tareas_creadas: 9,
        reuniones_agendadas: 3,
        reprogramaciones: 2,
        pendientes: 6,
        vencidas: 1,
        leads_sin_accion: 2,
      }),
    ],
  }
}
