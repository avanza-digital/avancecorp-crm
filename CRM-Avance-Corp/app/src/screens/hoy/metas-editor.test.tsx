import { render, screen } from '@testing-library/react'
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

  it('presenta una sola meta total en soles sin categorías auxiliares', () => {
    render(<MetasEditor objetivos={METAS_DEMO} demo />)

    expect(screen.getByText(/datos de ejemplo/)).toBeInTheDocument()
    expect(screen.getByText('S/ 1,000,000')).toBeInTheDocument()
    expect(screen.getByText(/No se divide por nueva inversión, renovación, aumento de inversión/)).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
})
