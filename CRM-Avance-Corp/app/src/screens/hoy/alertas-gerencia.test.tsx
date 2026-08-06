import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { ComponentProps } from 'react'
import type { AlertaGerencia } from '@/lib/alertas-gerencia'
import { AlertasGerenciaPanel } from './alertas-gerencia'

const ALERTAS = [
  {
    id: 'no-show-ana',
    tipo: 'no_show',
    severidad: 'critica',
    responsableId: 'ana-id',
    responsable: 'Ana Álvarez',
    equipo: 'Equipo Norte',
    valor: 2,
    destino: 'reuniones',
  },
  {
    id: 'tarea-bruno',
    tipo: 'tarea_vencida',
    severidad: 'atencion',
    responsableId: 'bruno-id',
    responsable: 'Bruno Soto',
    equipo: 'Equipo Sur',
    valor: 3,
    destino: 'rendimiento',
  },
  {
    id: 'conversion-carla',
    tipo: 'bajo_meta_conversion',
    severidad: 'atencion',
    responsableId: 'carla-id',
    responsable: 'Carla Ruiz',
    equipo: 'Equipo Norte',
    valor: 12,
    actual: 12,
    objetivo: 20,
    brechaPp: 8,
    destino: 'ranking-vendedores',
  },
] satisfies AlertaGerencia[]

function montar(over: Partial<ComponentProps<typeof AlertasGerenciaPanel>> = {}) {
  const onReintentar = vi.fn()
  render(
    <AlertasGerenciaPanel
      alertas={ALERTAS}
      generadoEn="2026-08-06T17:42:00Z"
      cargando={false}
      errores={[]}
      onReintentar={onReintentar}
      {...over}
    />,
  )
  return { onReintentar }
}

describe('AlertasGerenciaPanel', () => {
  it('filtra por prioridad y expone la selección con aria-pressed', () => {
    montar()
    const todas = screen.getByRole('button', { name: 'Todas: 3' })
    const criticas = screen.getByRole('button', { name: 'Críticas: 1' })

    expect(todas).toHaveAttribute('aria-pressed', 'true')
    fireEvent.click(criticas)

    expect(todas).toHaveAttribute('aria-pressed', 'false')
    expect(criticas).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByText('1 alerta activa de 3')).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Alertas activas' })
    expect(within(tabla).getByText('Ana Álvarez')).toBeInTheDocument()
    expect(within(tabla).queryByText('Bruno Soto')).not.toBeInTheDocument()
  })

  it('combina el filtro por tipo con búsqueda normalizada por responsable o equipo', () => {
    montar()
    fireEvent.change(screen.getByRole('combobox', { name: 'Filtrar alertas por tipo' }), {
      target: { value: 'bajo_meta_conversion' },
    })
    fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar responsable o equipo' }), {
      target: { value: 'equipo norte' },
    })

    const tabla = screen.getByRole('table', { name: 'Alertas activas' })
    expect(within(tabla).getByText('Carla Ruiz')).toBeInTheDocument()
    expect(within(tabla).queryByText('Ana Álvarez')).not.toBeInTheDocument()
  })

  it('ofrece limpiar cuando los filtros no tienen coincidencias', () => {
    montar()
    fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar responsable o equipo' }), {
      target: { value: 'equipo inexistente' },
    })

    expect(screen.getByText('Sin coincidencias')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))

    expect(screen.getByRole('table', { name: 'Alertas activas' })).toBeInTheDocument()
    expect(screen.getByRole('searchbox', { name: 'Buscar responsable o equipo' })).toHaveValue('')
  })

  it('distingue carga inicial, error total y vacío sano', () => {
    const { rerender } = render(
      <AlertasGerenciaPanel alertas={[]} cargando errores={[]} onReintentar={() => {}} />,
    )
    expect(screen.getByRole('status', { name: 'Cargando alertas' })).toHaveAttribute('aria-busy', 'true')
    expect(screen.queryByText('Todo al día')).not.toBeInTheDocument()

    rerender(
      <AlertasGerenciaPanel alertas={[]} cargando={false} errores={['No se pudo consultar el servidor.']} onReintentar={() => {}} />,
    )
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo consultar el servidor.')
    expect(screen.queryByText('Todo al día')).not.toBeInTheDocument()

    rerender(
      <AlertasGerenciaPanel alertas={[]} cargando={false} errores={[]} onReintentar={() => {}} />,
    )
    expect(screen.getByText('Todo al día')).toBeInTheDocument()
    expect(screen.getByText(/No hay alertas activas/)).toBeInTheDocument()
  })

  it('conserva las alertas cuando el error es parcial y permite reintentar', () => {
    const { onReintentar } = montar({ errores: ['No se cargaron las reuniones.'] })

    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent('Información incompleta')
    expect(screen.getByRole('table', { name: 'Alertas activas' })).toBeInTheDocument()
    fireEvent.click(within(aviso).getByRole('button', { name: 'Reintentar' }))
    expect(onReintentar).toHaveBeenCalledTimes(1)
  })

  it('genera enlaces navegables al destino y nombra la severidad con texto', () => {
    montar()
    const tabla = screen.getByRole('table', { name: 'Alertas activas' })
    const enlace = within(tabla).getByRole('link', { name: 'Abrir Reuniones para Ana Álvarez' })

    expect(enlace).toHaveAttribute('href', '#/reuniones')
    expect(within(tabla).getByText('Crítica')).toBeInTheDocument()
    expect(within(tabla).getAllByRole('columnheader').map((celda) => celda.textContent)).toEqual([
      'Prioridad y señal',
      'Responsable',
      'Equipo',
      'Valor',
      'Destino',
    ])
  })

  it('actualiza desde la cabecera y comunica el horario de Lima', () => {
    const { onReintentar } = montar({ modoDemo: true })
    expect(screen.getByRole('heading', { name: 'Estado actual · Lima' })).toBeInTheDocument()
    expect(screen.getByText(/Actualizado 6 ago/)).toBeInTheDocument()
    expect(screen.getByText('Ejemplo')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Actualizar' }))
    expect(onReintentar).toHaveBeenCalledTimes(1)
  })
})
