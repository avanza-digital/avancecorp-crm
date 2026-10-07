import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { CrmApiError } from '@/data/crm-api'
import type { AsignacionCelular, CelularSalud } from '@/lib/celulares'

const dobles = vi.hoisted(() => ({
  fuente: {} as Record<string, unknown>,
  catalogo: {} as Record<string, unknown>,
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
}))

vi.mock('sonner', () => ({ toast: { success: dobles.toastSuccess, error: dobles.toastError } }))
vi.mock('@/data/use-celulares', () => ({ useCelulares: () => dobles.fuente }))
vi.mock('@/data/crm-config-queries', () => ({ useCatalogoUsuariosAdministrables: () => dobles.catalogo }))

const { ConfigCelulares } = await import('./config-celulares')

const HEX = '0123456789abcdef'.repeat(4)
const persona = (perfil_id: string, nombre_completo: string, rol_crm: string | null, activo_crm: boolean | null) =>
  ({ perfil_id, nombre_completo, rol_crm, activo_crm, activo_portal: true }) as unknown as Record<string, unknown>

function celular(n: number, analista_id: string, nombre: string, extra: Partial<CelularSalud> = {}): CelularSalud {
  return {
    asignacion_id: `a${n}`, etiqueta: `C${n}`, analista_id, analista_nombre: nombre, vigente_desde: '2026-10-07T13:00:00Z',
    estado_latido: 'al_dia', horas_sin_latido: 0, reloj_desfasado: false, version_macro: 'llamadas-v3', eventos_en_cola: 0, ...extra,
  }
}
const cerrada: AsignacionCelular = {
  asignacion_id: 'a0', etiqueta: 'C1', analista_id: 'u1', analista_nombre: 'ANA TORRES',
  vigente_desde: '2026-09-29T13:00:00Z', vigente_hasta: '2026-10-07T13:00:00Z', motivo_cierre: 'rotacion',
}

function fuenteCon(extra: Record<string, unknown> = {}) {
  return {
    vigentes: [
      celular(1, 'u1', 'ANA TORRES'),
      celular(2, 'u2', 'BRUNO DÍAZ', { estado_latido: 'sin_latido', horas_sin_latido: 9, eventos_en_cola: 3 }),
      celular(5, 'u5', 'LUCÍA PAREDES', { estado_latido: 'sin_latido', horas_sin_latido: 31, eventos_en_cola: 12 }),
    ],
    asignaciones: [cerrada],
    estado: { cargando: false, error: false, reintentar: vi.fn() },
    ocupado: false,
    demo: false,
    habilitado: true,
    asignar: vi.fn(),
    rotar: vi.fn(),
    cerrar: vi.fn(),
    ...extra,
  }
}

beforeEach(() => {
  dobles.fuente = fuenteCon()
  dobles.catalogo = {
    data: [persona('u1', 'ANA TORRES', 'vendedor', true), persona('u2', 'BRUNO DÍAZ', 'vendedor', true),
      persona('u3', 'MARÍA SALAZAR', 'supervisor', true), persona('u5', 'LUCÍA PAREDES', null, null)],
    isPending: false,
  }
  dobles.toastSuccess.mockReset()
  dobles.toastError.mockReset()
  sessionStorage.clear()
  localStorage.clear()
})

describe('la tabla de vigentes', () => {
  it('dice la salud de cada celular y quita Rotar al analista de baja', () => {
    render(<ConfigCelulares />)
    expect(screen.getByText('3 vigentes')).toBeInTheDocument()
    expect(screen.getByText('1 sin latido · 1 con analista de baja')).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Celulares vigentes y su salud' })
    expect(within(tabla).getByText('Al día')).toBeInTheDocument()
    expect(within(tabla).getByText('Sin latido · 9 h')).toBeInTheDocument()
    expect(within(tabla).getByText('Analista de baja')).toBeInTheDocument()
    expect(within(tabla).getByText('Sin rotación: ciérralo y asígnalo a otro analista.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Rotar la clave de C5' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Rotar la clave de C1' })).toBeEnabled()
    const historial = screen.getByRole('table', { name: 'Historial de cierres de celulares' })
    expect(within(historial).getByText('Rotación de clave')).toBeInTheDocument()
  })
  it('con el interruptor de producción cerrado explica y no consulta ni ofrece acciones', () => {
    dobles.fuente = fuenteCon({ habilitado: false, vigentes: [], asignaciones: [] })
    render(<ConfigCelulares />)
    expect(screen.getByText('Todavía no está activa')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Asignar celular' })).not.toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
  it('sin celulares ofrece asignar el primero; con error ofrece reintentar', () => {
    dobles.fuente = fuenteCon({ vigentes: [], asignaciones: [] })
    const { unmount } = render(<ConfigCelulares />)
    expect(screen.getByText('Ningún celular asignado')).toBeInTheDocument()
    unmount()
    const reintentar = vi.fn()
    dobles.fuente = fuenteCon({ estado: { cargando: false, error: true, reintentar } })
    render(<ConfigCelulares />)
    expect(screen.getByText('No se pudo consultar la salud de los celulares.')).toBeInTheDocument()
  })
})

describe('asignar', () => {
  it('valida la etiqueta y la persona antes de llamar al servidor', async () => {
    const user = userEvent.setup()
    render(<ConfigCelulares />)
    await user.click(screen.getByRole('button', { name: 'Asignar celular' }))
    const dialogo = screen.getByRole('dialog', { name: 'Asignar un celular' })
    await user.type(within(dialogo).getByLabelText('Etiqueta del celular'), 'c0')
    await user.click(within(dialogo).getByRole('button', { name: 'Asignar y ver la clave' }))
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('La etiqueta es una C seguida de 1 a 3 dígitos')
    await user.clear(within(dialogo).getByLabelText('Etiqueta del celular'))
    await user.type(within(dialogo).getByLabelText('Etiqueta del celular'), 'c7')
    await user.click(within(dialogo).getByRole('button', { name: 'Asignar y ver la clave' }))
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('Elige a la persona que usará el celular.')
    expect(dobles.fuente.asignar).not.toHaveBeenCalled()
  })
  it('la clave se ve una sola vez: se copia, Esc no cierra, y al cerrar desaparece del DOM sin tocar el almacenamiento', async () => {
    const user = userEvent.setup()
    const asignar = vi.fn().mockResolvedValue({ asignacion_id: 'a7', etiqueta: 'C7', analista_id: 'u1', credencial: HEX })
    dobles.fuente = fuenteCon({ asignar })
    render(<ConfigCelulares />)
    await user.click(screen.getByRole('button', { name: 'Asignar celular' }))
    const dialogo = screen.getByRole('dialog', { name: 'Asignar un celular' })
    await user.type(within(dialogo).getByLabelText('Etiqueta del celular'), 'c7')
    await user.selectOptions(within(dialogo).getByLabelText('Analista que lo usará'), 'u1')
    await user.click(within(dialogo).getByRole('button', { name: 'Asignar y ver la clave' }))
    expect(asignar).toHaveBeenCalledWith('C7', 'u1')
    const clave = await screen.findByRole('dialog', { name: /Clave de C7/ })
    expect(within(clave).getByLabelText('Clave del celular C7')).toHaveValue(HEX)
    await user.click(within(clave).getByRole('button', { name: 'Copiar la clave' }))
    // user-event instala su propio portapapeles: lo que copió el botón se lee de ahí.
    expect(await navigator.clipboard.readText()).toBe(HEX)
    expect(within(clave).getByRole('button', { name: 'Copiar la clave' })).toHaveTextContent('Copiada')
    await user.keyboard('{Escape}')
    expect(screen.getByRole('dialog', { name: /Clave de C7/ })).toBeInTheDocument()
    await user.click(within(clave).getByRole('button', { name: 'Ya la copié al celular' }))
    await waitFor(() => expect(screen.queryByRole('dialog', { name: /Clave de C7/ })).not.toBeInTheDocument())
    expect(document.body.innerHTML).not.toContain(HEX)
    expect(sessionStorage.length).toBe(0)
    expect(localStorage.length).toBe(0)
    expect(dobles.toastSuccess).toHaveBeenCalledWith(expect.stringContaining('C7'))
    expect(dobles.toastSuccess.mock.calls.flat().join(' ')).not.toContain(HEX)
  })
  it('una etiqueta repetida muestra el texto del servidor y ofrece rotar', async () => {
    const user = userEvent.setup()
    const asignar = vi.fn().mockRejectedValue(new CrmApiError('C1 ya está asignado: ciérralo o rota su credencial', '23505'))
    dobles.fuente = fuenteCon({ asignar })
    render(<ConfigCelulares />)
    await user.click(screen.getByRole('button', { name: 'Asignar celular' }))
    const dialogo = screen.getByRole('dialog', { name: 'Asignar un celular' })
    await user.type(within(dialogo).getByLabelText('Etiqueta del celular'), 'c1')
    await user.selectOptions(within(dialogo).getByLabelText('Analista que lo usará'), 'u2')
    await user.click(within(dialogo).getByRole('button', { name: 'Asignar y ver la clave' }))
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('C1 ya está asignado: ciérralo o rota su credencial')
    await user.click(within(dialogo).getByRole('button', { name: 'Rotar la clave de C1' }))
    expect(await screen.findByRole('dialog', { name: 'Rotar la clave de C1' })).toBeInTheDocument()
  })
})

describe('rotar y cerrar', () => {
  it('rotar entrega la clave nueva', async () => {
    const user = userEvent.setup()
    const rotar = vi.fn().mockResolvedValue({ asignacion_id: 'a9', etiqueta: 'C1', analista_id: 'u1', credencial: HEX, anterior_id: 'a1' })
    dobles.fuente = fuenteCon({ rotar })
    render(<ConfigCelulares />)
    await user.click(screen.getByRole('button', { name: 'Rotar la clave de C1' }))
    const dialogo = screen.getByRole('dialog', { name: 'Rotar la clave de C1' })
    await user.click(within(dialogo).getByRole('button', { name: 'Rotar y ver la nueva clave' }))
    expect(rotar).toHaveBeenCalledWith('C1')
    expect(await screen.findByRole('dialog', { name: /Clave de C1/ })).toBeInTheDocument()
  })
  it('cerrar exige el motivo, avisa de la cola atascada y confirma con un toast sin clave', async () => {
    const user = userEvent.setup()
    const cerrar = vi.fn().mockResolvedValue(undefined)
    dobles.fuente = fuenteCon({ cerrar })
    render(<ConfigCelulares />)
    await user.click(screen.getByRole('button', { name: 'Cerrar C2' }))
    const dialogo = screen.getByRole('dialog', { name: 'Cerrar C2' })
    expect(within(dialogo).getByText(/3 avisos sin enviar/)).toBeInTheDocument()
    await user.click(within(dialogo).getByRole('button', { name: 'Cerrar asignación' }))
    expect(cerrar).not.toHaveBeenCalled()
    expect(within(dialogo).getByText('Elige el motivo del cierre.')).toBeInTheDocument()
    await user.click(within(dialogo).getByLabelText(/Extravío del celular/))
    await user.click(within(dialogo).getByRole('button', { name: 'Cerrar asignación' }))
    expect(cerrar).toHaveBeenCalledWith('a2', 'extravio')
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Cerrar C2' })).not.toBeInTheDocument())
    expect(dobles.toastSuccess).toHaveBeenCalledWith(expect.stringContaining('C2 cerrado'))
  })
  it('con una acción en curso los botones se bloquean (doble clic = una llamada)', () => {
    dobles.fuente = fuenteCon({ ocupado: true })
    render(<ConfigCelulares />)
    expect(screen.getByRole('button', { name: 'Asignar celular' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Rotar la clave de C1' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cerrar C1' })).toBeDisabled()
  })
})
