// Tests de la máquina de estados del BotonGuardar: guardando bloquea el doble
// envío, el éxito se anuncia y vuelve solo al reposo, y el error reintenta
// desde el mismo botón.
import { describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { BotonGuardar } from './boton-guardar'

describe('BotonGuardar', () => {
  it('muestra «Guardando…» y se deshabilita mientras la promesa viaja', async () => {
    let resolver!: () => void
    const onGuardar = vi.fn(
      () => new Promise<void>((res) => { resolver = res }),
    )
    const user = userEvent.setup()
    render(<BotonGuardar onGuardar={onGuardar} />)

    await user.click(screen.getByRole('button', { name: /guardar cambios/i }))

    // No hay disabled real (expulsaría el foco del teclado): el doble envío
    // lo bloquea el guard interno y el estado se expone por aria-disabled.
    const boton = screen.getByRole('button', { name: /guardando/i })
    expect(boton).toHaveAttribute('aria-disabled', 'true')
    expect(boton).toHaveAttribute('aria-busy', 'true')
    await user.click(boton)
    expect(onGuardar).toHaveBeenCalledTimes(1)

    await act(async () => resolver())
    expect(screen.getByRole('button', { name: /guardado/i })).toBeInTheDocument()
    // El resultado también viaja por texto para el lector de pantalla,
    // no solo por el color del botón.
    expect(screen.getByText('Cambios guardados')).toBeInTheDocument()
  })

  it('tras el éxito vuelve solo al reposo, listo para el próximo guardado', async () => {
    // fireEvent y no userEvent: userEvent se cuelga bajo fake timers.
    vi.useFakeTimers()
    try {
      render(<BotonGuardar onGuardar={() => Promise.resolve()} />)

      const boton = screen.getByRole('button', { name: /guardar cambios/i })
      boton.focus()
      fireEvent.click(boton)
      await act(async () => {}) // deja resolver la promesa del guardado
      expect(screen.getByRole('button', { name: /guardado/i })).toBeInTheDocument()

      act(() => vi.advanceTimersByTime(1800))
      expect(screen.getByRole('button', { name: /guardar cambios/i })).toBeEnabled()
      // El foco del teclado sobrevive al ciclo completo: nunca hubo disabled real.
      expect(document.activeElement).toBe(boton)
    } finally {
      vi.useRealTimers()
    }
  })

  it('el error explica, sacude y reintenta desde el mismo botón', async () => {
    const onGuardar = vi
      .fn<() => Promise<void>>()
      .mockRejectedValueOnce(new Error('red caída'))
      .mockResolvedValueOnce(undefined)
    const user = userEvent.setup()
    render(<BotonGuardar onGuardar={onGuardar} etiqueta="Guardar corrección" />)

    await user.click(screen.getByRole('button', { name: /guardar corrección/i }))
    const botonError = await screen.findByRole('button', { name: /no se pudo guardar/i })
    expect(botonError).toBeEnabled()
    expect(botonError.className).toContain('ac-shake')
    expect(screen.getByText('Error al guardar, reintenta')).toBeInTheDocument()

    await user.click(botonError)
    expect(await screen.findByRole('button', { name: /guardado/i })).toBeInTheDocument()
    expect(onGuardar).toHaveBeenCalledTimes(2)
  })

  it('respeta el disabled externo del formulario', () => {
    render(<BotonGuardar onGuardar={() => Promise.resolve()} disabled />)
    expect(screen.getByRole('button', { name: /guardar cambios/i })).toBeDisabled()
  })
})
