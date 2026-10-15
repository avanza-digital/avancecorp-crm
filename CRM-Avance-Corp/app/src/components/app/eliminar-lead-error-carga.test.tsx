// «Eliminar lead (error de carga)»: el diálogo solo evita el clic suelto (motivo de
// 10 a 500 caracteres y la palabra ELIMINAR). Quién puede y si ese lead se puede
// borrar lo decide el servidor; su mensaje se muestra tal cual y el diálogo no se cierra.
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CrmApiError } from '@/data/crm-api'
import { EliminarLeadErrorCarga } from './eliminar-lead-error-carga'

type Confirmar = (motivo: string) => Promise<void>
const LEAD = { nombre_completo: 'MARGARITA PRUEBA', origen: 'oficina' as const, creado_en: '2026-10-13T15:00:00.000Z' }
const AVISO = 'Úsalo solo si el lead se cargó por error. Se borrará el lead junto con sus tareas, sus actividades y su '
  + 'historial de asignación. Antes de borrarlo se guarda una copia de auditoría con tu motivo y tu nombre. Esta acción '
  + 'no se deshace. Si el lead ya tiene contrato o conversión, se registró hace más de 30 días o es de un mes cerrado, '
  + 'no se podrá eliminar y verás el motivo.'

function montar(onConfirmar: Confirmar = vi.fn<Confirmar>(async () => {})) {
  const onCerrar = vi.fn()
  render(<EliminarLeadErrorCarga lead={LEAD} onConfirmar={onConfirmar} onCerrar={onCerrar} />)
  return {
    user: userEvent.setup(), onConfirmar, onCerrar,
    dialogo: screen.getByRole('dialog', { name: 'Eliminar lead (error de carga)' }),
    motivo: screen.getByLabelText('Motivo de la eliminación'),
    palabra: screen.getByLabelText('Escribe ELIMINAR para confirmar'),
    eliminar: screen.getByRole('button', { name: 'Eliminar lead' }),
  }
}

describe('EliminarLeadErrorCarga', () => {
  it('identifica el lead y explica, en lenguaje sencillo, qué se borra y qué queda', () => {
    const { dialogo, motivo } = montar()
    expect(dialogo).toHaveTextContent('MARGARITA PRUEBA')
    expect(dialogo).toHaveTextContent('Walking')
    expect(dialogo).not.toHaveTextContent(/SLA/)
    // Quien llega por teclado o lector oye la consecuencia al entrar al motivo, antes de escribir.
    expect(motivo).toHaveAccessibleDescription(`${AVISO} 0 de 500 caracteres · mínimo 10`)
    expect(screen.getByLabelText('Escribe ELIMINAR para confirmar')).toHaveAccessibleDescription('Tal cual, en mayúsculas.')
  })

  it('el foco entra al motivo al abrir', async () => {
    const { motivo } = montar()
    await waitFor(() => expect(motivo).toHaveFocus())
  })

  it('9 caracteres o solo espacios no habilitan; 10 tras recortar, sí', async () => {
    const { user, motivo, palabra, eliminar } = montar()
    await user.type(palabra, 'ELIMINAR')
    await user.type(motivo, '123456789')
    expect(eliminar).toBeDisabled()
    await user.clear(motivo)
    await user.type(motivo, '            ')
    expect(eliminar).toBeDisabled()
    expect(motivo).toHaveAccessibleDescription(/ 0 de 500 caracteres · mínimo 10$/)
    await user.clear(motivo)
    await user.type(motivo, '  1234567890  ')
    expect(eliminar).toBeEnabled()
  })

  it('cuenta como Postgres (un emoji es un carácter): 501 no habilita, se marca y se anuncia; 500, sí', async () => {
    const { user, motivo, palabra, eliminar } = montar()
    const aviso = screen.getByRole('status')
    expect(aviso).toBeEmptyDOMElement()
    await user.type(palabra, 'ELIMINAR')
    await user.click(motivo)
    await user.paste('🙂'.repeat(501))
    expect(eliminar).toBeDisabled()
    expect(motivo).toHaveAttribute('aria-invalid', 'true')
    expect(motivo).toHaveAccessibleDescription(/ 501 de 500 caracteres · mínimo 10$/)
    expect(aviso).toHaveTextContent('El motivo pasa de 500 caracteres: acórtalo para poder eliminar.')
    await user.clear(motivo)
    await user.paste('🙂'.repeat(500))
    expect(eliminar).toBeEnabled()
    expect(motivo).not.toHaveAttribute('aria-invalid')
    expect(aviso).toBeEmptyDOMElement()
  })

  it('«eliminar» en minúsculas no confirma; ELIMINAR con espacios alrededor, sí', async () => {
    const { user, motivo, palabra, eliminar } = montar()
    await user.type(motivo, 'Se cargó dos veces')
    await user.type(palabra, 'eliminar')
    expect(eliminar).toBeDisabled()
    await user.clear(palabra)
    await user.type(palabra, ' ELIMINAR ')
    expect(eliminar).toBeEnabled()
  })

  it('envía el motivo recortado y cierra al confirmar el servidor', async () => {
    const { user, motivo, palabra, eliminar, onConfirmar, onCerrar } = montar()
    await user.type(motivo, '   Se cargó dos veces por error   ')
    await user.type(palabra, 'ELIMINAR')
    await user.click(eliminar)
    await waitFor(() => expect(onCerrar).toHaveBeenCalledOnce())
    expect(onConfirmar).toHaveBeenCalledExactlyOnceWith('Se cargó dos veces por error')
  })

  it('no envía dos veces ni se cierra mientras el servidor responde', async () => {
    let terminar: () => void = () => {}
    const onConfirmar = vi.fn<Confirmar>(() => new Promise<void>(resolve => { terminar = resolve }))
    const { user, motivo, palabra, eliminar, onCerrar } = montar(onConfirmar)
    await user.type(motivo, 'Se cargó dos veces')
    await user.type(palabra, 'ELIMINAR')
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

  it('muestra el rechazo del servidor tal cual, no se cierra y permite reintentar', async () => {
    const razones = 'No se puede eliminar este lead: tiene una conversión registrada; aparece en un mes cerrado (09/2026).'
    const onConfirmar = vi.fn<Confirmar>(async () => { throw new CrmApiError(razones, 'CONFLICTO') })
    const { user, motivo, palabra, eliminar, onCerrar } = montar(onConfirmar)
    await user.type(motivo, 'Se cargó dos veces')
    await user.type(palabra, 'ELIMINAR')
    await user.click(eliminar)
    expect(await screen.findByRole('alert')).toHaveTextContent(razones)
    expect(onCerrar).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Eliminar lead' })).toBeEnabled()
    expect(motivo).toHaveValue('Se cargó dos veces')
  })

  it('un fallo que no es del servidor no enseña texto crudo', async () => {
    const onConfirmar = vi.fn<Confirmar>(async () => { throw new TypeError('Failed to fetch') })
    const { user, motivo, palabra, eliminar } = montar(onConfirmar)
    await user.type(motivo, 'Se cargó dos veces')
    await user.type(palabra, 'ELIMINAR')
    await user.click(eliminar)
    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo eliminar el lead. Reintenta o consulta al administrador.')
  })

  it('Cancelar cierra sin enviar', async () => {
    const { user, onConfirmar, onCerrar } = montar()
    await user.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(onCerrar).toHaveBeenCalledOnce()
    expect(onConfirmar).not.toHaveBeenCalled()
  })
})
