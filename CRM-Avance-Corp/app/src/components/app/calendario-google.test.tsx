// Tests de la tarjeta "Mi calendario de Google": estados demo / primera vez /
// conectado, generación y rotación del enlace. API inyectada (sin red).
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CalendarioGoogle, type CalendarioGoogleApi } from './calendario-google'

const BASE = 'https://abc.supabase.co'

function apiFalsa(sobre: Partial<CalendarioGoogleApi> = {}): CalendarioGoogleApi {
  return {
    obtener: vi.fn().mockResolvedValue(null),
    crear: vi.fn().mockResolvedValue('tok-nuevo'),
    rotar: vi.fn().mockResolvedValue('tok-rotado'),
    ...sobre,
  }
}

describe('CalendarioGoogle', () => {
  it('en demo solo se anuncia: sin llamadas a la API', () => {
    const api = apiFalsa()
    render(<CalendarioGoogle perfilId="p1" demo api={api} supabaseUrl={BASE} />)
    expect(screen.getByText(/cuenta real del CRM/i)).toBeInTheDocument()
    expect(api.obtener).not.toHaveBeenCalled()
  })

  it('sin token → botón de generar; al tocarlo aparece el enlace y los pasos', async () => {
    const api = apiFalsa()
    render(<CalendarioGoogle perfilId="p1" demo={false} api={api} supabaseUrl={BASE} />)
    const boton = await screen.findByRole('button', { name: /generar mi enlace/i })
    await userEvent.click(boton)
    const campo = await screen.findByRole('textbox', { name: /enlace secreto/i })
    expect(campo).toHaveValue(`${BASE}/functions/v1/crm-agenda-ics?t=tok-nuevo`)
    expect(api.crear).toHaveBeenCalledWith('p1')
    expect(screen.getByText(/Desde una URL/i)).toBeInTheDocument()
  })

  it('con token existente lo muestra directo y "Renovar" lo reemplaza', async () => {
    const api = apiFalsa({ obtener: vi.fn().mockResolvedValue('tok-viejo') })
    render(<CalendarioGoogle perfilId="p1" demo={false} api={api} supabaseUrl={BASE} />)
    const campo = await screen.findByRole('textbox', { name: /enlace secreto/i })
    expect(campo).toHaveValue(`${BASE}/functions/v1/crm-agenda-ics?t=tok-viejo`)

    await userEvent.click(screen.getByRole('button', { name: /renovar enlace/i }))
    await waitFor(() =>
      expect(screen.getByRole('textbox', { name: /enlace secreto/i })).toHaveValue(
        `${BASE}/functions/v1/crm-agenda-ics?t=tok-rotado`,
      ),
    )
    expect(api.rotar).toHaveBeenCalledWith('p1')
  })

  it('si la API falla, el error se anuncia (role=alert) y no rompe la tarjeta', async () => {
    const api = apiFalsa({ obtener: vi.fn().mockRejectedValue(new Error('boom')) })
    render(<CalendarioGoogle perfilId="p1" demo={false} api={api} supabaseUrl={BASE} />)
    expect(await screen.findByRole('alert')).toBeInTheDocument()
  })
})
