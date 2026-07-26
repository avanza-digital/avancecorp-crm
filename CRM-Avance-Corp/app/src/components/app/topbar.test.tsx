// Tests del buscador del topbar: que PROMETA solo lo que busca. Prometía «lead o
// cliente» y solo miraba leads, así que un cliente de la propia cartera salía
// como «Sin resultados» (el CRM negando a alguien que sí existe). Aquí se fija
// el contrato: textos de leads, vacío acotado y la pantalla REAL del cliente
// nombrada con el rótulo que ese rol ve en su menú.
// Contextos mockeados a mano (sin red): el topbar solo consume `yo`, el ámbito y
// las acciones de paneles.
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { Rol } from '@/lib/roles'
import type { Lead } from '@/lib/tipos'
import type { Vista } from '@/lib/router'

let YO: { id: string; nombre_completo: string; rol: Rol; demo: boolean } | null = null
let LEADS: Lead[] = []
const abrirLead = vi.fn()
const abrirNuevoLead = vi.fn()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ ambito: { leads: LEADS, vendedores: [], esGlobal: false } }),
  usePanelesActions: () => ({ abrirLead, abrirNuevoLead }),
}))

const { Topbar } = await import('./topbar')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'JUAN PEREZ ROJAS',
    telefono: '+51999888777',
    correo: null,
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 50_000,
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: 'u-v1',
    vendedor_nombre: 'Vendedor Real',
    asignado_supervisor_id: null,
    creado_en: '2026-07-01T00:00:00.000Z',
    activo: true,
    dni: null,
    distrito: null,
    nota: null,
    motivo_descarte: null,
    ...over,
  }
}

function montar({
  rol = 'vendedor' as Rol,
  vista = 'hoy' as Vista,
  leads = [lead()],
}: { rol?: Rol; vista?: Vista; leads?: Lead[] } = {}) {
  // demo:true = el gate FUNCIONES_LEADS_APROBADAS deja ver el buscador sin
  // depender de la bandera de config (que cambia con la aprobación de Miguel).
  YO = { id: 'u-v1', nombre_completo: 'Vendedor Real', rol, demo: true }
  LEADS = leads
  return render(<Topbar vista={vista} />)
}

const campoBusqueda = () =>
  screen.getByRole('combobox', { name: 'Buscar lead por nombre, teléfono o DNI' })

describe('Topbar — buscador', () => {
  it('promete SOLO leads: ni el placeholder ni el aria-label hablan de clientes', () => {
    montar()
    const campo = campoBusqueda()
    expect(campo).toHaveAttribute('placeholder', 'Buscar lead…')
    expect(campo.getAttribute('placeholder')).not.toMatch(/cliente/i)
    expect(campo.getAttribute('aria-label')).not.toMatch(/cliente/i)
  })

  it('encuentra un lead del ámbito por nombre y al elegirlo abre su ficha', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(campoBusqueda(), 'perez')
    await user.click(await screen.findByRole('button', { name: /JUAN PEREZ ROJAS/ }))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('sin coincidencias: acota el vacío a los leads y nombra la pantalla del cliente', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(campoBusqueda(), 'zzz')
    // "Sin resultados" a secas se leía como "esa persona no existe".
    expect(screen.getByText(/Sin resultados en tus leads para «zzz»/)).toBeInTheDocument()
    // Al vendedor su menú le rotula la cartera "Mi cartera": así se le nombra.
    expect(screen.getByText(/Búscalo en «Mi cartera», en el menú lateral/)).toBeInTheDocument()
  })

  it('quien supervisa lee el rótulo de SU menú («Cartera»)', async () => {
    const user = userEvent.setup()
    montar({ rol: 'supervisor' })
    await user.type(campoBusqueda(), 'zzz')
    expect(screen.getByText(/Búscalo en «Cartera», en el menú lateral/)).toBeInTheDocument()
  })

  it('a quien NO tiene cartera (coordinador) no se le manda a una pantalla que no ve', async () => {
    const user = userEvent.setup()
    montar({ rol: 'coordinador' })
    await user.type(campoBusqueda(), 'zzz')
    expect(screen.getByText(/Sin resultados en tus leads/)).toBeInTheDocument()
    expect(screen.queryByText(/menú lateral/)).not.toBeInTheDocument()
  })

  it('el título de la cartera usa el MISMO rótulo por rol que el resto del CRM', () => {
    const { unmount } = montar({ vista: 'mi-cartera' })
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Mi cartera')
    unmount()
    montar({ rol: 'gerencia', vista: 'mi-cartera' })
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Cartera')
  })
})
