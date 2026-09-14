import { fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { ControlCitasEditor } from './control-citas-editor'
import { controlCitasInicial, type ConsultaControlCitas, type GuardarControlCitasInput } from '@/lib/control-citas'

const vacia: ConsultaControlCitas = { version_actual: 0, ultimo: null, historial: [] }
function guardada(input: GuardarControlCitasInput): ConsultaControlCitas {
  const ultimo = { version: input.versionEsperada + 1, configuracion: input.configuracion, guardado_en: '2026-09-11T20:00:00Z', guardado_por: '90000000-0000-4000-8000-000000000001', nota: input.nota, estado: 'borrador' as const }
  return { version_actual: ultimo.version, ultimo, historial: [ultimo] }
}
describe('Editor del Control de Citas', () => {
  it('solo aplica un borrador completo y guardado, después de revisarlo', async () => {
    const config = { ...controlCitasInicial(), mes_resultado: 'evento' as const,
      analista_resultado: 'evento' as const, base_depositos: 'entrevistas' as const, mes_inicio: '2026-09' }
    const consulta = { ...guardada({ versionEsperada: 0, configuracion: config, nota: '' }), aplicaciones: [] }
    const aplicar = vi.fn(async () => ({ ...consulta, aplicaciones: [{ version: 1, mes_inicio: '2026-09', aplicado_en: '2026-09-13T20:00:00Z', aplicado_por: '90000000-0000-4000-8000-000000000001' }] }))
    render(<ControlCitasEditor consulta={consulta} guardar={vi.fn()} aplicar={aplicar} />)
    await userEvent.click(screen.getByRole('button', { name: 'Aplicar al tablero' }))
    expect(aplicar).not.toHaveBeenCalled()
    expect(screen.getByRole('dialog')).toHaveTextContent('2026-09')
    await userEvent.click(screen.getByRole('button', { name: 'Confirmar aplicación' }))
    expect(aplicar).toHaveBeenCalledWith(1)
    expect(screen.getByRole('status')).toHaveTextContent('aplicada desde 2026-09')
  })
  it('mantiene Aplicar deshabilitado mientras falten reglas o haya cambios sin guardar', async () => {
    const consulta = { ...guardada({ versionEsperada: 0, configuracion: controlCitasInicial(), nota: '' }), aplicaciones: [] }
    render(<ControlCitasEditor consulta={consulta} guardar={vi.fn()} aplicar={vi.fn()} />)
    expect(screen.getByRole('button', { name: 'Aplicar al tablero' })).toBeDisabled()
  })
  it('guarda los valores y conserva como pendientes las reglas sin elegir', async () => {
    const guardar = vi.fn(async (input: GuardarControlCitasInput) => guardada(input))
    render(<ControlCitasEditor consulta={vacia} guardar={guardar} />)
    await userEvent.click(screen.getByRole('button', { name: 'Guardar borrador' }))
    expect(guardar).toHaveBeenCalledWith({ versionEsperada: 0, configuracion: controlCitasInicial(), nota: '' })
    expect(await screen.findByRole('status')).toHaveTextContent('Todavía no está aplicado')
    expect(screen.getByRole('button', { name: 'Guardar borrador' })).toHaveFocus()
  })
  it('no guarda datos inválidos y enfoca el campo con error', async () => {
    const guardar = vi.fn()
    render(<ControlCitasEditor consulta={vacia} guardar={guardar} />)
    const campo = screen.getByLabelText('Objetivo de depósitos (%)')
    await userEvent.clear(campo)
    await userEvent.type(campo, '120')
    await userEvent.click(screen.getByRole('button', { name: 'Guardar borrador' }))
    expect(guardar).not.toHaveBeenCalled()
    expect(campo).toHaveFocus()
    expect(campo).toHaveAttribute('aria-invalid', 'true')
  })
  it('conserva el borrador ante fallos y versiones nuevas de otra sesión', async () => {
    const guardar = vi.fn().mockRejectedValue(new Error('Conflicto de versión'))
    const vista = render(<ControlCitasEditor consulta={vacia} guardar={guardar} />)
    const campo = screen.getByLabelText('Citas por lead')
    await userEvent.clear(campo); await userEvent.type(campo, '1,50')
    await userEvent.click(screen.getByRole('button', { name: 'Guardar borrador' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Conflicto')
    expect(campo).toHaveValue('1,50')
    vista.rerender(<ControlCitasEditor consulta={guardada({ versionEsperada: 0, configuracion: controlCitasInicial(), nota: '' })} guardar={guardar} />)
    expect(campo).toHaveValue('1,50')
    expect(screen.getByRole('button', { name: 'Guardar borrador' })).toHaveAttribute('aria-disabled', 'true')
    await userEvent.click(screen.getByRole('button', { name: 'Cargar último borrador' }))
    expect(campo).toHaveValue('1,50')
    await userEvent.click(screen.getByRole('button', { name: 'Conservar mi edición' }))
    expect(campo).toHaveValue('1,50')
    await userEvent.click(screen.getByRole('button', { name: 'Cargar último borrador' }))
    await userEvent.click(screen.getByRole('button', { name: 'Descartar cambios y cargar' }))
    expect(campo).toHaveValue('1,25')
  })
  it('actualiza la base sin borrar las reglas elegidas', async () => {
    render(<ControlCitasEditor consulta={vacia} guardar={vi.fn()} />)
    await userEvent.click(screen.getByRole('checkbox'))
    expect(screen.getByLabelText('Ejemplo de la meta de citas')).toHaveTextContent('100')
    await userEvent.click(screen.getByText('Reglas de avance'))
    await userEvent.selectOptions(screen.getByLabelText('Cómo contar las entrevistas'), 'personas_unicas')
    expect(screen.getByLabelText('Cómo contar las entrevistas')).toHaveValue('personas_unicas')
    expect(screen.getByText('4 por definir')).toBeInTheDocument()
  })
  it('abre las reglas y enfoca un mes inválido aunque el navegador acepte texto', async () => {
    const guardar = vi.fn(async (input: GuardarControlCitasInput) => guardada(input))
    render(<ControlCitasEditor consulta={vacia} guardar={guardar} />)
    await userEvent.click(screen.getByText('Reglas de avance'))
    const mes = screen.getByLabelText('Mes de inicio previsto')
    mes.setAttribute('type', 'text')
    fireEvent.change(mes, { target: { value: '2026-99' } })
    await userEvent.click(screen.getByText('Reglas de avance'))
    await userEvent.click(screen.getByRole('button', { name: 'Guardar borrador' }))
    expect(mes).toBeVisible()
    expect(mes).toHaveFocus()
    expect(mes).toHaveAttribute('aria-invalid', 'true')
    expect(guardar).not.toHaveBeenCalled()
  })
})
