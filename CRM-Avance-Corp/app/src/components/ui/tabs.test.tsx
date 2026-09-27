// Contrato APG de la primitiva Tabs: roles, selección, teclado con vuelta y el
// panel enlazado al tab activo. Lo que se protege es que ninguna pantalla nueva
// vuelva a copiar el tablist a mano con un teclado a medias.
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Tabs } from './tabs'

type Valor = 'llamadas' | 'whatsapp' | 'todo'
const PESTANAS = [
  { valor: 'llamadas', etiqueta: 'Llamadas', extra: 9 },
  { valor: 'whatsapp', etiqueta: 'WhatsApp' },
  { valor: 'todo', etiqueta: 'Todo' },
] as const

function Pantalla({ alCambiar }: { alCambiar?: (v: Valor) => void }) {
  const [valor, setValor] = useState<Valor>('llamadas')
  return (
    <Tabs etiqueta="Tipo de registro" pestanas={PESTANAS} valor={valor} onCambio={(v) => { setValor(v); alCambiar?.(v) }}>
      <p>Panel de {valor}</p>
    </Tabs>
  )
}

describe('Tabs — roles y selección', () => {
  it('expone tablist con nombre, un tab por pestaña y el panel enlazado al tab activo', () => {
    render(<Pantalla />)
    expect(screen.getByRole('tablist', { name: 'Tipo de registro' })).toBeInTheDocument()
    expect(screen.getAllByRole('tab')).toHaveLength(3)
    const tabLlamadas = screen.getByRole('tab', { name: /Llamadas/ })
    expect(tabLlamadas).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('tab', { name: 'WhatsApp' })).toHaveAttribute('aria-selected', 'false')
    const panel = screen.getByRole('tabpanel')
    expect(panel).toHaveAttribute('aria-labelledby', tabLlamadas.id)
    expect(tabLlamadas).toHaveAttribute('aria-controls', panel.id)
    expect(panel).toHaveTextContent('Panel de llamadas')
  })

  it('pinta el extra (contador) dentro del tab', () => {
    render(<Pantalla />)
    expect(screen.getByRole('tab', { name: /Llamadas\s*9/ })).toBeInTheDocument()
  })

  it('el clic cambia la pestaña y avisa', async () => {
    const usuario = userEvent.setup()
    const alCambiar = vi.fn()
    render(<Pantalla alCambiar={alCambiar} />)
    await usuario.click(screen.getByRole('tab', { name: 'Todo' }))
    expect(alCambiar).toHaveBeenCalledWith('todo')
    expect(screen.getByRole('tab', { name: 'Todo' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('tabpanel')).toHaveTextContent('Panel de todo')
  })
})

describe('Tabs — teclado (roving tabindex con vuelta)', () => {
  it('solo el tab activo está en el orden de tabulación', () => {
    render(<Pantalla />)
    expect(screen.getByRole('tab', { name: /Llamadas/ })).toHaveAttribute('tabindex', '0')
    expect(screen.getByRole('tab', { name: 'WhatsApp' })).toHaveAttribute('tabindex', '-1')
    expect(screen.getByRole('tab', { name: 'Todo' })).toHaveAttribute('tabindex', '-1')
  })

  it('flecha derecha avanza y da la vuelta; flecha izquierda retrocede; Home y End saltan a los extremos', async () => {
    const usuario = userEvent.setup()
    render(<Pantalla />)
    const tab = (nombre: string) => screen.getByRole('tab', { name: new RegExp(nombre) })
    tab('Llamadas').focus()
    await usuario.keyboard('{ArrowRight}')
    expect(tab('WhatsApp')).toHaveAttribute('aria-selected', 'true')
    expect(tab('WhatsApp')).toHaveFocus()
    await usuario.keyboard('{ArrowRight}{ArrowRight}')
    expect(tab('Llamadas')).toHaveAttribute('aria-selected', 'true')
    await usuario.keyboard('{ArrowLeft}')
    expect(tab('Todo')).toHaveAttribute('aria-selected', 'true')
    await usuario.keyboard('{Home}')
    expect(tab('Llamadas')).toHaveAttribute('aria-selected', 'true')
    await usuario.keyboard('{End}')
    expect(tab('Todo')).toHaveAttribute('aria-selected', 'true')
    expect(tab('Todo')).toHaveFocus()
  })

  it('una tecla ajena no cambia nada', async () => {
    const usuario = userEvent.setup()
    render(<Pantalla />)
    screen.getByRole('tab', { name: /Llamadas/ }).focus()
    await usuario.keyboard('{ArrowDown}')
    expect(screen.getByRole('tab', { name: /Llamadas/ })).toHaveAttribute('aria-selected', 'true')
  })
})

describe('Tabs — variantes de aspecto (27/09/2026)', () => {
  it.each(['subrayado', 'pastilla'] as const)('%s conserva el patrón APG: tablist, tabs y panel enlazado', async (variante) => {
    const usuario = userEvent.setup()
    const alCambiar = vi.fn()
    function ConVariante() {
      const [valor, setValor] = useState<Valor>('llamadas')
      return (
        <Tabs etiqueta="Vista" variante={variante} clasePanel="panel-propio" pestanas={PESTANAS} valor={valor} onCambio={(v) => { setValor(v); alCambiar(v) }}>
          <p>Panel de {valor}</p>
        </Tabs>
      )
    }
    render(<ConVariante />)
    const activa = screen.getByRole('tab', { name: /Llamadas/ })
    expect(activa).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('tabpanel')).toHaveClass('panel-propio')
    activa.focus()
    await usuario.keyboard('{ArrowRight}')
    expect(alCambiar).toHaveBeenLastCalledWith('whatsapp')
    expect(screen.getByRole('tab', { name: 'WhatsApp' })).toHaveFocus()
  })

  it('pastilla rellena SOLO la activa, y el default sigue siendo el segmentado de siempre', () => {
    const { rerender } = render(<Tabs etiqueta="Filtro" variante="pastilla" pestanas={PESTANAS} valor="whatsapp" onCambio={() => {}} />)
    expect(screen.getByRole('tab', { name: 'WhatsApp' })).toHaveClass('bg-accent')
    expect(screen.getByRole('tab', { name: /Llamadas/ })).not.toHaveClass('bg-accent')
    rerender(<Tabs etiqueta="Filtro" pestanas={PESTANAS} valor="whatsapp" onCambio={() => {}} />)
    expect(screen.getByRole('tablist')).toHaveClass('bg-muted')
    expect(screen.getByRole('tab', { name: 'WhatsApp' })).toHaveClass('bg-white')
  })
})
