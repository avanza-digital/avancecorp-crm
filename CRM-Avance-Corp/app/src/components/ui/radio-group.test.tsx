// Contrato del RadioGroup: grupo con nombre (fieldset/legend), radios nativos,
// estado marcado visible en texto, obligatorio, descripción enlazada y
// deshabilitadas. Es la base del panel «¿Cómo terminó la llamada?».
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { RadioGroup } from './radio-group'

type Resultado = 'no_contesto' | 'volver_a_llamar' | 'numero_errado'
const OPCIONES = [
  { valor: 'no_contesto', etiqueta: 'No contestó', atajo: '1' },
  { valor: 'volver_a_llamar', etiqueta: 'Contestó · volver a llamar', detalle: 'Se crea la tarea al guardar', atajo: '2' },
  { valor: 'numero_errado', etiqueta: 'Número errado', deshabilitada: true },
] as const

function Pantalla({ inicial = null, descripcion, invalido, alCambiar }: { inicial?: Resultado | null; descripcion?: string; invalido?: boolean; alCambiar?: (v: Resultado) => void }) {
  const [valor, setValor] = useState<Resultado | null>(inicial)
  return (
    <RadioGroup leyenda="Resultado" obligatorio opciones={OPCIONES} valor={valor} onCambio={(v) => { setValor(v); alCambiar?.(v) }} descripcion={descripcion} invalido={invalido} />
  )
}

describe('RadioGroup — estructura accesible', () => {
  it('es un grupo con nombre y una radio por opción, ninguna marcada al inicio', () => {
    render(<Pantalla />)
    expect(screen.getByRole('group', { name: /Resultado/ })).toBeInTheDocument()
    const radios = screen.getAllByRole('radio')
    expect(radios).toHaveLength(3)
    for (const radio of radios) expect(radio).not.toBeChecked()
    expect(screen.getByRole('radio', { name: /No contestó/ })).toBeRequired()
  })

  it('marca «obligatorio» en la leyenda y pinta detalle y atajo', () => {
    render(<Pantalla />)
    expect(screen.getByText('· obligatorio')).toBeInTheDocument()
    expect(screen.getByText('Se crea la tarea al guardar')).toBeInTheDocument()
    expect(screen.getByText('2')).toHaveAttribute('aria-hidden', 'true')
  })

  it('la opción deshabilitada no se puede elegir', async () => {
    const usuario = userEvent.setup()
    const alCambiar = vi.fn()
    render(<Pantalla alCambiar={alCambiar} />)
    const errado = screen.getByRole('radio', { name: /Número errado/ })
    expect(errado).toBeDisabled()
    await usuario.click(errado)
    expect(alCambiar).not.toHaveBeenCalled()
  })
})

describe('RadioGroup — cambio de valor', () => {
  it('el clic en la etiqueta marca la opción y avisa una vez', async () => {
    const usuario = userEvent.setup()
    const alCambiar = vi.fn()
    render(<Pantalla alCambiar={alCambiar} />)
    await usuario.click(screen.getByText('Contestó · volver a llamar'))
    expect(alCambiar).toHaveBeenCalledTimes(1)
    expect(alCambiar).toHaveBeenCalledWith('volver_a_llamar')
    expect(screen.getByRole('radio', { name: /volver a llamar/ })).toBeChecked()
    expect(screen.getByRole('radio', { name: /No contestó/ })).not.toBeChecked()
  })

  it('con teclado, la flecha abajo pasa a la siguiente opción habilitada', async () => {
    const usuario = userEvent.setup()
    render(<Pantalla inicial="no_contesto" />)
    screen.getByRole('radio', { name: /No contestó/ }).focus()
    await usuario.keyboard('{ArrowDown}')
    expect(screen.getByRole('radio', { name: /volver a llamar/ })).toBeChecked()
  })
})

describe('RadioGroup — descripción y error', () => {
  it('la descripción queda enlazada al grupo y se pinta como error cuando es inválido', () => {
    render(<Pantalla descripcion="Elige un resultado para guardar." invalido />)
    const grupo = screen.getByRole('group', { name: /Resultado/ })
    const descripcion = screen.getByText('Elige un resultado para guardar.')
    expect(grupo).toHaveAttribute('aria-describedby', descripcion.id)
    expect(grupo).toHaveAttribute('aria-invalid', 'true')
    expect(descripcion).toHaveClass('text-destructive')
  })
})
