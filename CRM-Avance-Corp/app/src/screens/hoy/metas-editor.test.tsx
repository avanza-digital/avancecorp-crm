import { render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { METAS_DEMO } from '@/lib/demo'
import { MetasEditor } from './metas-editor'

describe('resumen de metas publicado', () => {
  it('es solo lectura y dirige a la única vía versionada de administración', () => {
    render(<MetasEditor objetivos={METAS_DEMO} demo={false} />)

    expect(screen.getByText('Metas publicadas · solo lectura')).toBeInTheDocument()
    expect(screen.getByText(/Revisión 1/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Administrar metas/ })).toHaveAttribute('href', '#/config-metas')
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('spinbutton')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /guardar/i })).not.toBeInTheDocument()
  })

  it('presenta las seis dimensiones sin sumar PEN y USD', () => {
    render(<MetasEditor objetivos={METAS_DEMO} demo />)

    expect(screen.getByText(/datos de ejemplo/)).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Metas publicadas por categoría y moneda' })
    const nuevo = within(tabla).getByRole('row', { name: /Nuevo/ })
    expect(within(nuevo).getByText('S/ 600,000')).toBeInTheDocument()
    expect(within(nuevo).getByText('US$ 100,000')).toBeInTheDocument()
    expect(within(tabla).getByRole('row', { name: /Renovación/ })).toBeInTheDocument()
    expect(within(tabla).getByRole('row', { name: /Upgrade/ })).toBeInTheDocument()
  })
})
