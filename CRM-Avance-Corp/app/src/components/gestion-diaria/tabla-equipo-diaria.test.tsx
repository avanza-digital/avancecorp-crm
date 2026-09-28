// La tabla del equipo tiene DOS contextos (plan supervisor v2, 27/09/2026):
// gerencia la conserva como estaba (con Pendientes) y el supervisor estrena el
// diseño: iniciales, Citas, contacto en tres estados y atención en palabras.
import { describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { TablaEquipoDiaria } from './tabla-equipo-diaria'
import { filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import type { FilaEquipoPresentada, FiltrosEquipo } from '@/lib/gestion-diaria-equipo'

const FILTROS: FiltrosEquipo = { busqueda: '', soloProblemas: false, orden: 'atencion', ascendente: false }
const filas = [
  filaEquipoPrueba({ analista_id: 'k', nombre_completo: 'KAREN DÍAZ', gestiones_hoy: 5, tareas_pendientes: 6, tareas_vencidas: 4,
    requiere_atencion: true, motivos_atencion: ['tarea_vencida', 'sin_llamar_2h'],
    marcador: { ...filaEquipoPrueba().marcador, llamadas: 12, utiles: 11, contestadas: 2, tasa_contacto_pct: 18, nivel: 'bajo', citas_agendadas: 1 } }),
  filaEquipoPrueba({ analista_id: 'a', nombre_completo: 'ANDREA MORALES', gestiones_hoy: 3,
    marcador: { ...filaEquipoPrueba().marcador, llamadas: 3, utiles: 3, contestadas: 2, tasa_contacto_pct: 67, nivel: null } }),
  filaEquipoPrueba({ analista_id: 'r', nombre_completo: 'RENATO FLORES' }),
] as FilaEquipoPresentada[]

function montar(contexto?: 'supervisor') {
  render(<TablaEquipoDiaria filas={filas} filtros={FILTROS} ordenar={vi.fn()} seleccion="k" seleccionar={vi.fn()}
    panelId="panel" irAlDetalle={vi.fn()} minimo={5} {...(contexto ? { contexto } : {})} />)
  return screen.getByRole('table')
}

describe('TablaEquipoDiaria', () => {
  it('gerencia (por defecto) no cambia: Pendientes y «N motivos»', () => {
    const tabla = montar()
    expect(within(tabla).getAllByRole('columnheader').map((c) => c.textContent)).toEqual(['Analista', 'Llamadas', 'Contacto', 'Pendientes', 'Vencidas', 'Atención'])
    expect(within(tabla).getByText('2 motivos')).toBeInTheDocument()
  })
  it('supervisor: Citas en lugar de Pendientes, orden comunicado y la fila elegida marcada', () => {
    const tabla = montar('supervisor')
    const cabeceras = within(tabla).getAllByRole('columnheader')
    expect(cabeceras.map((c) => c.textContent)).toEqual(['Analista', 'Llamadas', 'Contacto', 'Citas', 'Vencidas', 'Atención'])
    expect(cabeceras[5]).toHaveAttribute('aria-sort', 'descending')
    expect(within(tabla).getByRole('button', { name: 'Seleccionar a KAREN DÍAZ' })).toHaveAttribute('aria-current', 'true')
    expect(within(tabla).getByRole('button', { name: 'Ir al detalle de KAREN DÍAZ' })).toBeInTheDocument()
  })
  it('supervisor: la atención se dice en palabras, en rojo si es vencido, con «+N» y la lista para el lector', () => {
    const tabla = montar('supervisor')
    const fila = within(tabla).getByRole('button', { name: 'Seleccionar a KAREN DÍAZ' }).closest('tr')!
    const atencion = within(fila).getByText('4 vencidas')
    expect(atencion).toHaveStyle({ color: 'var(--destructive-text)' })
    expect(within(fila).getByText('+1')).toBeInTheDocument()
    expect(within(fila).getByText(': Tareas vencidas; Más de 2 h sin llamar en la jornada')).toHaveClass('sr-only')
    const sinActividad = within(tabla).getByRole('button', { name: 'Seleccionar a RENATO FLORES' }).closest('tr')!
    expect(within(sinActividad).getByText('Sin registro')).toBeInTheDocument()
  })
  it('supervisor: el contacto sin muestra suficiente dice útiles y mínimo; el evaluado, % y nivel', () => {
    const tabla = montar('supervisor')
    const andrea = within(tabla).getByRole('button', { name: 'Seleccionar a ANDREA MORALES' }).closest('tr')!
    expect(within(andrea).getByText('Sin muestra')).toBeInTheDocument()
    expect(within(andrea).getByText('3 útiles · mínimo 5')).toBeInTheDocument()
    expect(within(andrea).queryByText('67 %')).not.toBeInTheDocument()
    const karen = within(tabla).getByRole('button', { name: 'Seleccionar a KAREN DÍAZ' }).closest('tr')!
    expect(within(karen).getByText('18 %')).toBeInTheDocument()
    expect(within(karen).getByText('Bajo')).toBeInTheDocument()
  })
})
