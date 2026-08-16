import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ChipArrastre } from './chip-arrastre'

const DESCUENTO = {
  etiqueta: 'arrastra 1 conversión de anulaciones · julio 2026',
  detalle: 'julio 2026: Cierre anulado por gerencia (−1)',
}

describe('ChipArrastre — el porqué alcanzable sin ratón (observación #5)', () => {
  it('es un botón enfocable con el detalle desplegable y aria-expanded', () => {
    render(<ChipArrastre descuento={DESCUENTO} />)

    const boton = screen.getByRole('button', { name: DESCUENTO.etiqueta })
    expect(boton).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByText(DESCUENTO.detalle)).not.toBeInTheDocument()

    // Clic (= tap en táctil, = Enter/Espacio con teclado sobre un button nativo)
    fireEvent.click(boton)
    expect(boton).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByText(DESCUENTO.detalle)).toBeInTheDocument()

    fireEvent.click(boton)
    expect(boton).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByText(DESCUENTO.detalle)).not.toBeInTheDocument()
  })

  it('el ratón conserva su atajo (title) cerrado; abierto no se duplica', () => {
    render(<ChipArrastre descuento={DESCUENTO} />)
    const boton = screen.getByRole('button')
    expect(boton).toHaveAttribute('title', DESCUENTO.detalle)
    fireEvent.click(boton)
    expect(boton).not.toHaveAttribute('title')
  })
})
