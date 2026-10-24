import { afterEach, expect, it } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import * as v from 'valibot'
import detalle from '../../../test-fixtures/capital-pendientes/detalle-pendiente.json'
import { CoberturaCapitalSchema } from '@/lib/capital-valorado'
import { CoberturaCapitalAviso } from './cobertura-capital'

afterEach(cleanup)

it('separa las ventas ya valoradas por incorporar del USD que aún espera TC', () => {
  const cobertura = v.parse(CoberturaCapitalSchema, detalle.cobertura)
  // capital_estado_corte incluye los pendientes dentro de por_incorporar.
  cobertura.por_incorporar = { cantidad: 3, pen: 6000, usd: 20000 }
  render(<CoberturaCapitalAviso cobertura={cobertura} />)
  expect(screen.getByText('2 operaciones ya valoradas se incorporarán en la próxima actualización.')).toBeVisible()
  expect(screen.getByText(/US\$ 20,000 pendiente de tipo de cambio\. No incluido/)).toBeVisible()
})

it('un PEN sin fecha acreditada conserva su motivo y no se anuncia como falta de TC', () => {
  const cobertura = v.parse(CoberturaCapitalSchema, detalle.cobertura)
  cobertura.pendientes = { cantidad: 2, pen: 5000, usd: 20000 }
  cobertura.por_incorporar = { ...cobertura.pendientes }
  cobertura.ventas_pendientes.push({ ...cobertura.ventas_pendientes[0]!,
    fuente_id: 'f3000000-0000-4000-8000-000000000203', moneda: 'PEN', monto: 5000,
    fecha_comercial: null, motivo: 'fecha_comercial_sin_acreditar' })
  render(<CoberturaCapitalAviso cobertura={cobertura} />)
  fireEvent.click(screen.getByText(/2 ventas pendientes de valoración/))
  expect(screen.getByText(/S\/ 5,000 pendiente de acreditar fecha comercial/)).toBeVisible()
  expect(screen.getByText(/US\$ 20,000 pendiente de tipo de cambio\. No incluido/)).toBeVisible()
  expect(screen.queryByText(/operaciones ya valoradas/)).not.toBeInTheDocument()
})
