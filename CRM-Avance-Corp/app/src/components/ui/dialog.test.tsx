import { useState } from 'react'
import { describe, expect, it } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Dialog, DialogTitle } from './dialog'
import { Sheet, SheetTitle } from './sheet'

function Pantalla({ anidado = false, origenNoEnfocable = false, modalFicha = false }: { anidado?: boolean; origenNoEnfocable?: boolean; modalFicha?: boolean }) {
  const [abierto, setAbierto] = useState(false)
  const [fichaAbierta, setFichaAbierta] = useState(true)
  const [resuelto, setResuelto] = useState(false)
  const contenido = <>
    {origenNoEnfocable
      ? <button disabled={resuelto} onClick={() => setAbierto(true)}>Revisar solicitud</button>
      : !resuelto && <button onClick={() => setAbierto(true)}>Revisar solicitud</button>}
    <button>Otra acción de la ficha</button>
    <Dialog open={abierto} onClose={() => setAbierto(false)}>
      <DialogTitle>Revisión</DialogTitle>
      <button onClick={() => {
        // La consulta actualizada retira el botón antes de cerrar el modal.
        setTimeout(() => { setResuelto(true); setTimeout(() => setAbierto(false), 20) }, 20)
      }}>Resolver</button>
    </Dialog>
  </>
  return anidado
    ? <Sheet open={fichaAbierta} onClose={() => setFichaAbierta(false)} modal={modalFicha}><SheetTitle>Ficha</SheetTitle>{contenido}</Sheet>
    : contenido
}

describe('foco de Dialog controlado sin Trigger', () => {
  it.each([false, true])('reabrir una revisión y pulsar Escape conserva la ficha inferior (modal=%s)', async (modalFicha) => {
    const usuario = userEvent.setup()
    render(<Pantalla anidado modalFicha={modalFicha} />)
    const origen = screen.getByRole('button', { name: 'Revisar solicitud' })
    for (let apertura = 0; apertura < 3; apertura++) {
      await usuario.click(origen)
      expect(screen.getByRole('dialog', { name: 'Revisión' })).toBeInTheDocument()
      await usuario.keyboard('{Escape}')
      await waitFor(() => expect(origen).toHaveFocus())
      expect(screen.getByRole('dialog', { name: 'Ficha' })).toBeInTheDocument()
      expect(screen.queryByRole('dialog', { name: 'Revisión' })).not.toBeInTheDocument()
    }
    await usuario.keyboard('{Escape}')
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Ficha' })).not.toBeInTheDocument())
  })

  it('Escape vuelve al botón exacto que abrió el diálogo por teclado', async () => {
    const usuario = userEvent.setup()
    render(<Pantalla />)
    const origen = screen.getByRole('button', { name: 'Revisar solicitud' })
    origen.focus()
    await usuario.keyboard('{Enter}')
    expect(screen.getByRole('dialog', { name: 'Revisión' })).toBeInTheDocument()
    await usuario.keyboard('{Escape}')
    await waitFor(() => expect(origen).toHaveFocus())
  })

  it.each([false, true])('una resolución vuelve a la ficha si su botón desaparece o queda deshabilitado (%s)', async (origenNoEnfocable) => {
    const usuario = userEvent.setup()
    render(<Pantalla anidado origenNoEnfocable={origenNoEnfocable} />)
    await usuario.click(screen.getByRole('button', { name: 'Revisar solicitud' }))
    await usuario.click(screen.getByRole('button', { name: 'Resolver' }))
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Revisión' })).not.toBeInTheDocument())
    const ficha = screen.getByRole('dialog', { name: 'Ficha' })
    await waitFor(() => expect(ficha).toHaveFocus())
    await usuario.tab()
    expect(screen.getByRole('button', { name: 'Otra acción de la ficha' })).toHaveFocus()
  })
})
