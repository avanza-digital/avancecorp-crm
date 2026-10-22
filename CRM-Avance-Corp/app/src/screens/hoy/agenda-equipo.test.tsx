// D-48 (bloque 2.12): el panel «Agenda del equipo» pinta «de baja» y «suspendido» junto al nombre de quien los trae, con
// la respuesta nueva; con la de antes (sin marcas), igual que siempre. El mismo estilo que en Citas de Gerencia: «de baja»
// apagado (como «inactivo» de Mi cartera) y «suspendido» con el color de «Suspendido en Portal» (config-usuarios.tsx:75).
import { render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { metricasAgendaDemo } from '@/lib/demo-metricas-agenda'
import type { MetricasAgendaConMarcas, VendedorAgenda } from '@/data/crm-api'
import { AgendaEquipoPanel } from './agenda-equipo'

const DESDE = '2026-10-03'
const HASTA = '2026-10-09'

/** Un miembro con actividad (cierres y tareas creadas en el período). */
function miembro(id: string, nombre: string, extra: Partial<VendedorAgenda>): VendedorAgenda {
  return {
    vendedor_id: id, nombre, rol: 'vendedor', activo: true, toques: 4, toques_por_dia: 0.6, reuniones_realizadas: 1,
    completadas: 3, no_asistio: 1, canceladas: 0, pct_completadas: 75, tareas_creadas: 6, reuniones_agendadas: 6,
    reprogramaciones: 0, pendientes: 0, vencidas: 0, leads_sin_accion: 0, ...extra,
  }
}

/** La respuesta nueva: un analista de baja y una suspendida con actividad, en su sitio (por nombre). */
function conMarcas(extra: VendedorAgenda[] = []): MetricasAgendaConMarcas {
  const datos = metricasAgendaDemo(DESDE, HASTA)
  return {
    ...datos,
    vendedores: [
      miembro('d-baja', 'ALEJANDRO DE BAJA', { activo: false, de_baja: true }),
      ...datos.vendedores,
      miembro('d-susp', 'SARA SUSPENDIDA', { suspendido: true }),
      ...extra,
    ],
  }
}

const props = { cargando: false, error: null, onReintentar: vi.fn() }

describe('Agenda del equipo · D-48: de baja y suspendidos con actividad', () => {
  it('con la respuesta nueva: «de baja» y «suspendido» junto al nombre, solo en sus filas, y se explica', () => {
    render(<AgendaEquipoPanel {...props} datos={conMarcas()} />)

    const baja = screen.getByText('ALEJANDRO DE BAJA').closest('tr') as HTMLElement
    const marcaBaja = within(baja).getByText('de baja')
    expect(marcaBaja).toHaveAttribute('title', expect.stringMatching(/dado de baja/i))
    // Codex r1 (P3-3): «pendientes» es una foto actual, no del período; el texto no puede decir solo «actividad en el período».
    expect(marcaBaja).toHaveAttribute('title', expect.stringContaining('actividad registrada en el período o tareas pendientes actuales'))
    expect(marcaBaja.style.getPropertyValue('--c')).toBe('var(--muted-foreground)')
    const susp = screen.getByText('SARA SUSPENDIDA').closest('tr') as HTMLElement
    const marcaSusp = within(susp).getByText('suspendido')
    expect(marcaSusp).toHaveAttribute('title', expect.stringMatching(/suspendido en el Portal/i))
    expect(marcaSusp).toHaveAttribute('title', expect.stringContaining('actividad registrada en el período o tareas pendientes actuales'))
    expect(marcaSusp.style.getPropertyValue('--c')).toBe('var(--destructive)')
    // Los demás, sin marca.
    const uno = screen.getByText('ANALISTA UNO').closest('tr') as HTMLElement
    expect(within(uno).queryByText('de baja')).not.toBeInTheDocument()
    expect(within(uno).queryByText('suspendido')).not.toBeInTheDocument()
    expect(screen.getAllByText('de baja')).toHaveLength(1)
    expect(screen.getAllByText('suspendido')).toHaveLength(1)
    expect(screen.getByText(/aparecen porque tienen actividad registrada en el período o tareas pendientes actuales\./)).toBeInTheDocument()
  })

  it('con la respuesta de antes: ningún miembro lleva marca ni se explica', () => {
    render(<AgendaEquipoPanel {...props} datos={metricasAgendaDemo(DESDE, HASTA)} />)

    expect(screen.getByText('ANALISTA UNO')).toBeInTheDocument()
    expect(screen.queryByText('de baja')).not.toBeInTheDocument()
    expect(screen.queryByText('suspendido')).not.toBeInTheDocument()
    expect(screen.queryByText(/aparecen porque tienen actividad/)).not.toBeInTheDocument()
  })

  it('un marcado cuya única «actividad» son tareas pendientes actuales: el texto lo dice, no lo atribuye al período', () => {
    const conPendientes = miembro('d-pend', 'PABLO PENDIENTES', {
      activo: false, de_baja: true, toques: 0, toques_por_dia: 0, reuniones_realizadas: 0, completadas: 0, no_asistio: 0,
      pct_completadas: null, tareas_creadas: 0, reuniones_agendadas: 0, pendientes: 2, vencidas: 2,
    })
    render(<AgendaEquipoPanel {...props} datos={conMarcas([conPendientes])} />)

    const fila = screen.getByText('PABLO PENDIENTES').closest('tr') as HTMLElement
    expect(within(fila).getByText('de baja')).toHaveAttribute('title', expect.stringContaining('o tareas pendientes actuales'))
    expect(within(fila).getByText(/2 pendientes/)).toBeInTheDocument()
    expect(screen.queryByText(/aparecen porque tienen actividad en el período\./)).not.toBeInTheDocument()
  })

  it('un marcado sin actividad (que el servidor no manda, pero si llegara) conserva su marca en la línea colapsada', () => {
    const quieto = miembro('d-quieto', 'BRUNO QUIETO', {
      activo: false, de_baja: true, toques: 0, toques_por_dia: 0, reuniones_realizadas: 0, completadas: 0, no_asistio: 0,
      pct_completadas: null, tareas_creadas: 0, reuniones_agendadas: 0,
    })
    render(<AgendaEquipoPanel {...props} datos={conMarcas([quieto])} />)

    const chip = screen.getByText(/BRUNO QUIETO/).closest('li') as HTMLElement
    expect(chip).toHaveTextContent(/BRUNO QUIETO.*de baja/)
  })
})
