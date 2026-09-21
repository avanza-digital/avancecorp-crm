// El menú «···» promete el patrón `menu` del APG en cuanto se anuncia con
// `role="menu"`: teclado completo y foco que vuelve al disparador. Hasta el
// 20/09/2026 solo cumplía Escape, y «Mi día» metió ahí una acción principal
// («Registrar resultado»), así que la promesa pasó a ser exigible.
import { describe, expect, it } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import { DropdownItem, DropdownMenu } from './dropdown-menu'

function Menu(): React.JSX.Element {
  return (
    <DropdownMenu trigger={<button type="button">Acciones</button>}>
      <DropdownItem>Primera</DropdownItem>
      <DropdownItem>Segunda</DropdownItem>
    </DropdownMenu>
  )
}

describe('DropdownMenu', () => {
  it('al abrir, el foco entra en la primera opción', () => {
    render(<Menu />)
    fireEvent.click(screen.getByRole('button', { name: 'Acciones' }))
    expect(screen.getByRole('menuitem', { name: 'Primera' })).toHaveFocus()
  })

  it('las flechas recorren las opciones y dan la vuelta', () => {
    render(<Menu />)
    fireEvent.click(screen.getByRole('button', { name: 'Acciones' }))
    fireEvent.keyDown(document, { key: 'ArrowDown' })
    expect(screen.getByRole('menuitem', { name: 'Segunda' })).toHaveFocus()
    fireEvent.keyDown(document, { key: 'ArrowDown' })
    expect(screen.getByRole('menuitem', { name: 'Primera' })).toHaveFocus()
    fireEvent.keyDown(document, { key: 'End' })
    expect(screen.getByRole('menuitem', { name: 'Segunda' })).toHaveFocus()
  })

  it('Escape cierra y DEVUELVE el foco al disparador, no al body', () => {
    render(<Menu />)
    const disparador = screen.getByRole('button', { name: 'Acciones' })
    fireEvent.click(disparador)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
    expect(disparador).toHaveFocus()
    expect(disparador).toHaveAttribute('aria-expanded', 'false')
  })

  it('Tab sale del menú, así que el menú se cierra', () => {
    render(<Menu />)
    fireEvent.click(screen.getByRole('button', { name: 'Acciones' }))
    fireEvent.keyDown(document, { key: 'Tab' })
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
  })

  it('elegir una opción cierra y devuelve el foco', () => {
    render(<Menu />)
    const disparador = screen.getByRole('button', { name: 'Acciones' })
    fireEvent.click(disparador)
    fireEvent.click(screen.getByRole('menuitem', { name: 'Segunda' }))
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
    expect(disparador).toHaveFocus()
  })
})
