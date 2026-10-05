// F5a «Bases cargadas» (04/10/2026): la tarjeta flotante del lead (Cartera, cola de Hoy…) con un contacto de base —
// origen y motivo `base_cargada`, capital vacío (E8)— rotula sin siglas y no inventa «S/ 0». Antes, el motivo se
// buscaba en el catálogo cerrado del select y la fila «Descarte» desaparecía.
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { Lead } from '@/lib/tipos'

vi.mock('@/lib/use-etapa-visible', () => ({
  useEtapaVisible: () => (lead: Lead) => ({ label: lead.etapa, color: '#64748b' }),
}))

const { LeadHoverCard } = await import('./lead-hover-card')

const BASE: Lead = {
  id: 'lead-1',
  nombre_completo: 'ROSA QUISPE',
  telefono: '+51987654321',
  etapa: 'descartado',
  origen: 'base_cargada',
  motivo_descarte: 'base_cargada',
  monto_estimado: null,
  moneda: 'PEN',
  creado_en: '2026-10-01T12:00:00.000Z',
  activo: true,
}

async function abrir(lead: Lead) {
  const usuario = userEvent.setup()
  render(<LeadHoverCard lead={lead}><button type="button">{lead.nombre_completo}</button></LeadHoverCard>)
  await usuario.hover(screen.getByRole('button', { name: lead.nombre_completo }))
  return screen.findByText('Teléfono')
}

describe('LeadHoverCard · contacto de base cargada', () => {
  it('rotula origen y descarte «Base cargada» y no pinta capital inventado', async () => {
    await abrir(BASE)

    expect(screen.getAllByText('Base cargada')).toHaveLength(2) // Origen y Descarte
    expect(screen.getByText('Descarte')).toBeInTheDocument()
    expect(screen.queryByText(/S\/ 0\b/)).not.toBeInTheDocument()
  })

  it('ESTADO DE PRODUCCIÓN: un lead con capital y motivo de siempre se ve igual que hoy', async () => {
    await abrir({ ...BASE, origen: 'landing', motivo_descarte: 'sin_fondos', monto_estimado: 15_000 })

    expect(screen.getByText('LANDING')).toBeInTheDocument()
    expect(screen.getByText('Sin fondos')).toBeInTheDocument()
    expect(screen.getByText('S/ 15,000')).toBeInTheDocument()
    expect(screen.queryByText('Base cargada')).not.toBeInTheDocument()
  })
})
