import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { configuracionFixture } from '@/lib/politica-gestion-diaria.fixture'
import type { ConfiguracionGestionDiaria } from '@/lib/politica-gestion-diaria'

const dobles = vi.hoisted(() => ({ datos: null as ConfiguracionGestionDiaria | null,
  publicar: vi.fn(), controlar: vi.fn(), refetch: vi.fn(), error: null as unknown }))
vi.mock('@/data/gestion-diaria-seguimiento-queries', () => ({ useConfiguracionGestionDiaria: () => ({
  datos: dobles.datos, habilitada: true, consulta: { error: dobles.error, isFetching: false, refetch: dobles.refetch },
  publicar: { isPending: false, mutateAsync: dobles.publicar }, controlar: { isPending: false, mutateAsync: dobles.controlar },
}) }))
const { ConfigGestionDiaria } = await import('./config-gestion-diaria')
beforeEach(() => { vi.clearAllMocks(); dobles.datos = configuracionFixture(); dobles.error = null })

describe('configuración de Gestión Diaria', () => {
  it('muestra reglas vigentes, explica el objetivo y publica desde medianoche Lima', async () => {
    render(<ConfigGestionDiaria />)
    expect(screen.getByRole('region', { name: 'Reglas vigentes' })).toHaveTextContent('11:30')
    fireEvent.change(screen.getByLabelText('Llamadas al primer corte para el ejemplo'), { target: { value: '20' } })
    expect(screen.getByText(/el crecimiento pide 50/)).toHaveTextContent('30 llamadas acumuladas')
    fireEvent.change(screen.getByLabelText('Motivo del cambio'), { target: { value: 'Ajuste para mañana' } })
    fireEvent.click(screen.getByRole('button', { name: 'Revisar y publicar v2' }))
    const dialogo = screen.getByRole('dialog')
    expect(dialogo).toHaveTextContent('2026-09-23')
    expect(dialogo).toHaveTextContent('muestra mínima 5')
    await act(async () => { fireEvent.click(within(dialogo).getByRole('button', { name: 'Confirmar' })) })
    expect(dobles.publicar).toHaveBeenCalledWith(expect.objectContaining({ version: 1,
      vigenteDesde: '2026-09-23T05:00:00.000Z', motivo: 'Ajuste para mañana' }))
  })
  it('directorio puede leer todas las reglas, pero no publicar ni controlar avisos', () => {
    dobles.datos!.puede_editar = false
    render(<ConfigGestionDiaria />)
    expect(screen.getByText(/Solo lectura: puedes auditar/)).toBeVisible()
    expect(screen.getByLabelText('Activar cortes desde la jornada elegida')).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Revisar y publicar v2' })).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Detener avisos' })).not.toBeInTheDocument()
  })
  it('una nueva versión no sobrescribe el borrador ni permite guardar sobre ella', () => {
    const vista = render(<ConfigGestionDiaria />)
    fireEvent.change(screen.getByLabelText('Mínimo del sábado'), { target: { value: '7' } })
    const siguiente = { ...dobles.datos!.vigente, version: 2, vigente_desde: '2026-09-24T05:00:00Z' }
    dobles.datos = { ...dobles.datos!, expected_version: 2, historial: [siguiente, dobles.datos!.vigente], revisiones_pendientes: [siguiente] }
    vista.rerender(<ConfigGestionDiaria />)
    expect(screen.getByLabelText('Mínimo del sábado')).toHaveValue(7)
    expect(screen.getByText('Se publicó otra versión mientras editabas. Revisa la nueva configuración antes de guardar.')).toBeVisible()
    expect(screen.getByRole('button', { name: 'Revisar y publicar v2' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'Cargar última versión' }))
    expect(screen.getByLabelText('Mínimo del sábado')).toHaveValue(3)
    expect(screen.getByLabelText('Jornada de inicio (Lima)')).toHaveValue('2026-09-24')
  })
  it('un cambio de otro gerente no invierte una confirmación de apagado en reanudación', () => {
    const vista = render(<ConfigGestionDiaria />)
    fireEvent.change(screen.getByLabelText('Motivo para detener'), { target: { value: 'Incidencia de prueba' } })
    fireEvent.click(screen.getByRole('button', { name: 'Detener avisos' }))
    dobles.datos = { ...dobles.datos!, control_avisos: { ...dobles.datos!.control_avisos, version: 2, habilitados: false } }
    vista.rerender(<ConfigGestionDiaria />)
    const dialogo = screen.getByRole('dialog')
    expect(dialogo).toHaveTextContent('Se detendrán nuevas apariciones')
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('Otro gerente cambió el canal')
    expect(within(dialogo).getByRole('button', { name: 'Confirmar' })).toBeDisabled()
    expect(dobles.controlar).not.toHaveBeenCalled()
  })
  it('un error del servidor conserva el formulario y la confirmación para revisión', async () => {
    dobles.publicar.mockRejectedValueOnce(new Error('Conflicto de red'))
    render(<ConfigGestionDiaria />)
    fireEvent.change(screen.getByLabelText('Motivo del cambio'), { target: { value: 'Motivo conservado' } })
    fireEvent.click(screen.getByRole('button', { name: 'Revisar y publicar v2' }))
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Confirmar' })) })
    expect(screen.getByRole('dialog')).toBeVisible()
    expect(screen.getByRole('alert')).toBeVisible()
    expect(screen.getByLabelText('Motivo del cambio')).toHaveValue('Motivo conservado')
  })
})
