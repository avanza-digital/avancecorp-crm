import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { CalendarDays, LayoutDashboard, Phone, Wallet } from 'lucide-react'
import { NavegacionMovil } from './navegacion-movil'

const items = [
  { id: 'hoy', label: 'Hoy', icon: LayoutDashboard },
  { id: 'gestion-diaria', label: 'Gestión Diaria', icon: Phone },
  { id: 'agenda', label: 'Agenda', icon: CalendarDays },
  { id: 'mi-cartera', label: 'Mi cartera', icon: Wallet },
] as const

describe('Navegación móvil compartida', () => {
  it('Analista navega desde la barra y Más usando solo las entradas recibidas', () => {
    const navegar = vi.fn()
    render(<NavegacionMovil rol="vendedor" vista="hoy" grupos={[{ grupo: 'principal', label: 'Principal', items }]}
      nombre="Ana Analista" demo={false} onNavegar={navegar} onSalir={vi.fn()} esActiva={id => id === 'hoy'} />)
    const nav = screen.getByRole('navigation', { name: 'Navegación principal de Analista' })
    expect(within(nav).getAllByRole('button').map(b => b.textContent)).toEqual(['Mi día', 'Gestión Diaria', 'Agenda', 'Más'])
    fireEvent.click(within(nav).getByRole('button', { name: 'Agenda' }))
    expect(navegar).toHaveBeenCalledWith('agenda')
    fireEvent.click(within(nav).getByRole('button', { name: 'Más' }))
    const panel = screen.getByRole('dialog', { name: 'Más opciones' })
    expect(within(panel).getByText('Analista', { exact: true })).toBeVisible()
    expect(within(panel).getByRole('region', { name: 'Mi gestión' })).toBeVisible()
    expect(within(panel).getAllByRole('button').map(b => b.getAttribute('aria-label') ?? b.textContent))
      .toEqual(['Cerrar más opciones', 'Mi cartera', 'Cerrar sesión'])
    fireEvent.click(within(panel).getByRole('button', { name: 'Mi cartera' }))
    expect(navegar).toHaveBeenLastCalledWith('mi-cartera')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('si el catálogo autorizado omite los accesos principales no los vuelve a ofrecer', () => {
    render(<NavegacionMovil rol="vendedor" vista="mi-cartera" grupos={[{ grupo: 'principal', label: 'Principal', items: [items[3]] }]}
      nombre="Ana Analista" demo={false} onNavegar={vi.fn()} onSalir={vi.fn()} esActiva={id => id === 'mi-cartera'} />)
    const nav = screen.getByRole('navigation')
    expect(within(nav).getAllByRole('button')).toHaveLength(1)
    const mas = within(nav).getByRole('button', { name: 'Más' })
    expect(mas).toHaveAttribute('aria-current', 'true')
    fireEvent.click(mas)
    expect(screen.queryByRole('button', { name: 'Mi día' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Agenda' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Mi cartera' })).toHaveAttribute('aria-current', 'page')
  })
})
