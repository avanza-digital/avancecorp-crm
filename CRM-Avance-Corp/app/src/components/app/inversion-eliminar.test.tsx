// «Eliminar inversión»: el diálogo solo evita el clic suelto (motivo de 5 a 300
// caracteres y la palabra ELIMINAR). Quién puede y si se puede lo decide el
// servidor; su mensaje se muestra tal cual y el diálogo no se cierra.
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CrmApiError } from '@/data/crm-api'
import type { InversionFuente } from '@/lib/inversionistas'
import { inversionF5 } from '@/test/fixtures/f5'
import { InversionEliminar } from './inversion-eliminar'

type Confirmar = (inversion: InversionFuente, motivo: string) => Promise<void>

function montar(inversion: InversionFuente = inversionF5, onConfirmar: Confirmar = vi.fn<Confirmar>(async () => {})) {
  const onCerrar = vi.fn()
  render(<InversionEliminar inversion={inversion} onConfirmar={onConfirmar} onCerrar={onCerrar} />)
  const dialogo = screen.getByRole('dialog')
  return {
    user: userEvent.setup(), onConfirmar, onCerrar, dialogo,
    motivo: screen.getByLabelText('Motivo de la eliminación'),
    confirmacion: screen.getByLabelText('Escribe ELIMINAR para confirmar'),
    eliminar: screen.getByRole('button', { name: 'Eliminar inversión' }),
  }
}

describe('InversionEliminar', () => {
  it('muestra empresa, capital y referencia, y avisa de la conversión de un lead', () => {
    const { dialogo, motivo } = montar()
    expect(screen.getByRole('dialog', { name: 'Eliminar inversión QORILAZO SINTÉTICO' })).toBe(dialogo)
    expect(dialogo).toHaveTextContent('Qorilazo')
    expect(dialogo).toHaveTextContent('S/ 1,200')
    expect(dialogo).toHaveTextContent('QORILAZO SINTÉTICO')
    expect(dialogo).toHaveTextContent('La inversión saldrá del capital, de la cartera y de la conversión. Se guardará una copia de auditoría con tu motivo y tu nombre. Esta acción no se deshace.')
    expect(dialogo).toHaveTextContent('Si es la conversión de un lead, también se anula (solo gerencia).')
    // Quien llega por teclado o lector oye la consecuencia al entrar al motivo, antes de escribir.
    expect(motivo).toHaveAccessibleDescription('La inversión saldrá del capital, de la cartera y de la conversión. '
      + 'Se guardará una copia de auditoría con tu motivo y tu nombre. Esta acción no se deshace. '
      + 'Si es la conversión de un lead, también se anula (solo gerencia). 0 de 300 caracteres · mínimo 5')
    expect(screen.getByLabelText('Escribe ELIMINAR para confirmar')).toHaveAccessibleDescription('Tal cual, en mayúsculas.')
  })

  it('sin número se identifica por su empresa y sin cierre inicial no habla de conversión', () => {
    const { dialogo, motivo } = montar({ ...inversionF5, numero: null, es_inicial: false, empresa: 'prodelco', moneda: 'USD' })
    expect(screen.getByRole('dialog', { name: 'Eliminar inversión en Prodelco' })).toBe(dialogo)
    expect(dialogo).toHaveTextContent('Inversión registrada')
    expect(dialogo).toHaveTextContent('US$ 1,200')
    expect(dialogo).not.toHaveTextContent('Si es la conversión de un lead')
    expect(motivo).toHaveAccessibleDescription(/Esta acción no se deshace\. 0 de 300 caracteres · mínimo 5$/)
  })

  it('el foco entra al motivo al abrir', async () => {
    const { motivo } = montar()
    await waitFor(() => expect(motivo).toHaveFocus())
  })

  it('queda deshabilitado sin motivo o sin confirmación', async () => {
    const { user, motivo, confirmacion, eliminar, onConfirmar } = montar()
    expect(eliminar).toBeDisabled()
    await user.type(confirmacion, 'ELIMINAR')
    expect(eliminar).toBeDisabled()
    await user.clear(confirmacion)
    await user.type(motivo, 'Registro duplicado')
    expect(eliminar).toBeDisabled()
    await user.type(confirmacion, 'ELIMINAR')
    expect(eliminar).toBeEnabled()
    expect(onConfirmar).not.toHaveBeenCalled()
  })

  it('un motivo de 4 caracteres o de solo espacios no habilita; 5 tras recortar, sí', async () => {
    const { user, motivo, confirmacion, eliminar } = montar()
    await user.type(confirmacion, 'ELIMINAR')
    await user.type(motivo, 'abcd')
    expect(eliminar).toBeDisabled()
    await user.clear(motivo)
    await user.type(motivo, '         ')
    expect(eliminar).toBeDisabled()
    expect(motivo).toHaveAccessibleDescription(/ 0 de 300 caracteres · mínimo 5$/)
    await user.clear(motivo)
    await user.type(motivo, '  abcde  ')
    expect(eliminar).toBeEnabled()
  })

  it('301 caracteres no habilita, marca el campo y lo anuncia; 300, sí', async () => {
    const { user, motivo, confirmacion, eliminar } = montar()
    const aviso = screen.getByRole('status')
    expect(aviso).toBeEmptyDOMElement()
    await user.type(confirmacion, 'ELIMINAR')
    await user.click(motivo)
    await user.paste('x'.repeat(301))
    expect(eliminar).toBeDisabled()
    expect(motivo).toHaveAttribute('aria-invalid', 'true')
    expect(motivo).toHaveAccessibleDescription(/ 301 de 300 caracteres · mínimo 5$/)
    expect(aviso).toHaveTextContent('El motivo pasa de 300 caracteres: acórtalo para poder eliminar.')
    await user.type(motivo, '{Backspace}')
    expect(eliminar).toBeEnabled()
    expect(motivo).not.toHaveAttribute('aria-invalid')
    expect(aviso).toBeEmptyDOMElement()
  })

  it('«eliminar» en minúsculas no confirma; ELIMINAR con espacios alrededor, sí', async () => {
    const { user, motivo, confirmacion, eliminar } = montar()
    await user.type(motivo, 'Registro duplicado')
    await user.type(confirmacion, 'eliminar')
    expect(eliminar).toBeDisabled()
    await user.clear(confirmacion)
    await user.type(confirmacion, ' ELIMINAR ')
    expect(eliminar).toBeEnabled()
  })

  it('envía el motivo recortado y cierra al confirmar el servidor', async () => {
    const { user, motivo, confirmacion, eliminar, onConfirmar, onCerrar } = montar()
    await user.type(motivo, '   Se registró dos veces por error   ')
    await user.type(confirmacion, 'ELIMINAR')
    await user.click(eliminar)
    await waitFor(() => expect(onCerrar).toHaveBeenCalledOnce())
    expect(onConfirmar).toHaveBeenCalledExactlyOnceWith(inversionF5, 'Se registró dos veces por error')
  })

  it('no envía dos veces ni se cierra mientras el servidor responde', async () => {
    let terminar: () => void = () => {}
    const onConfirmar = vi.fn<Confirmar>(() => new Promise<void>(resolve => { terminar = resolve }))
    const { user, motivo, confirmacion, eliminar, onCerrar } = montar(inversionF5, onConfirmar)
    await user.type(motivo, 'Registro duplicado')
    await user.type(confirmacion, 'ELIMINAR')
    await user.click(eliminar)
    const enviando = screen.getByRole('button', { name: 'Eliminando…' })
    expect(enviando).toHaveAttribute('aria-disabled', 'true')
    expect(enviando).toHaveAttribute('aria-busy', 'true')
    await user.click(enviando)
    await user.keyboard('{Escape}')
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled()
    expect(motivo).toBeDisabled()
    expect(onConfirmar).toHaveBeenCalledOnce()
    expect(onCerrar).not.toHaveBeenCalled()
    terminar()
    await waitFor(() => expect(onCerrar).toHaveBeenCalledOnce())
  })

  it('muestra el mensaje del servidor, no se cierra y permite reintentar', async () => {
    const onConfirmar = vi.fn<Confirmar>(async () => {
      throw new CrmApiError('Esta inversión tiene una solicitud de retiro registrada: no se elimina', 'CONFLICTO')
    })
    const { user, motivo, confirmacion, eliminar, onCerrar } = montar(inversionF5, onConfirmar)
    await user.type(motivo, 'Registro duplicado')
    await user.type(confirmacion, 'ELIMINAR')
    await user.click(eliminar)
    expect(await screen.findByRole('alert')).toHaveTextContent('Esta inversión tiene una solicitud de retiro registrada: no se elimina')
    expect(onCerrar).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Eliminar inversión' })).toBeEnabled()
    expect(screen.getByLabelText('Motivo de la eliminación')).toHaveValue('Registro duplicado')
  })

  it('un fallo sin mensaje de negocio muestra el texto genérico, nunca el crudo', async () => {
    const onConfirmar = vi.fn<Confirmar>(async () => { throw new TypeError('Failed to fetch') })
    const { user, motivo, confirmacion, eliminar } = montar(inversionF5, onConfirmar)
    await user.type(motivo, 'Registro duplicado')
    await user.type(confirmacion, 'ELIMINAR')
    await user.click(eliminar)
    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent('No se pudo eliminar la inversión. Reintenta o consulta al administrador.')
    expect(alerta).not.toHaveTextContent('Failed to fetch')
  })

  it('cancelar cierra sin enviar', async () => {
    const { user, onConfirmar, onCerrar } = montar()
    await user.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(onCerrar).toHaveBeenCalledOnce()
    expect(onConfirmar).not.toHaveBeenCalled()
  })
})
