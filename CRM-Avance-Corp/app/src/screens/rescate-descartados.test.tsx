// La pantalla se prueba contra la capa de datos simulada: importa que el
// supervisor vea una bandeja compacta, pueda escoger un bloque y que el CRM
// preserve la regla de no devolverlo al asesor que lo descartó.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { EpisodioRescateDescarte, MesRescateDescartes, Miembro } from '@/lib/tipos'

const abrirLead = vi.fn()
const toastSuccess = vi.fn()
const toastError = vi.fn()
const mesesMock = vi.fn<() => Promise<MesRescateDescartes[]>>()
const episodiosMock = vi.fn<(mes: string) => Promise<EpisodioRescateDescarte[]>>()
const rescatarMock = vi.fn<(episodios: string[], destinos: string[], evitarOrigen: boolean) => Promise<void>>()

let YO: { id: string; rol: string; demo: boolean } | null = null
let EQUIPO: Miembro[] = []

vi.mock('sonner', () => ({ toast: { success: toastSuccess, error: toastError } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ equipo: EQUIPO }),
  usePanelesActions: () => ({ abrirLead }),
}))
vi.mock('@/data/crm-api', () => ({
  mesesRescateDescartes: () => mesesMock(),
  descartesRescateDelMes: (mes: string) => episodiosMock(mes),
  rescatarDescartes: (episodios: string[], destinos: string[], evitarOrigen: boolean) => rescatarMock(episodios, destinos, evitarOrigen),
}))

const { RescateDescartados } = await import('./rescate-descartados')
const { RescateCarpeta } = await import('./rescate-carpeta')

function mesActualLima(): string {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit',
  }).formatToParts(new Date())
  const anio = partes.find((parte) => parte.type === 'year')?.value ?? '2026'
  const mes = partes.find((parte) => parte.type === 'month')?.value ?? '01'
  return `${anio}-${mes}-01`
}

function episodio(n: number, sobre: Partial<EpisodioRescateDescarte> = {}): EpisodioRescateDescarte {
  return {
    episodio_id: `episodio-${n}`,
    lead_id: `lead-${n}`,
    nombre_completo: `LEAD RESCATE ${n}`,
    distrito: 'Miraflores',
    origen: 'landing',
    categoria_interes: 'nuevo',
    monto_estimado: 12000,
    moneda: 'PEN',
    motivo_descarte: 'sin_interes',
    descartado_en: `2026-08-20T1${n % 10}:00:00Z`,
    asesor_id: 'asesor-origen',
    asesor_nombre: 'ASESOR ORIGEN',
    puede_rescatar: true,
    estado: 'pendiente',
    ...sobre,
  }
}

beforeEach(() => {
  window.history.replaceState(null, '', '/')
  YO = { id: 'supervisor-1', rol: 'supervisor', demo: false }
  EQUIPO = [
    { perfil_id: 'asesor-origen', nombre_completo: 'ASESOR ORIGEN', rol_crm: 'vendedor', supervisor_id: 'supervisor-1', activo: true },
    { perfil_id: 'asesor-destino', nombre_completo: 'ASESOR DESTINO', rol_crm: 'vendedor', supervisor_id: 'supervisor-1', activo: true },
  ]
  mesesMock.mockReset().mockResolvedValue([{ mes: mesActualLima(), total: 26, pendientes: 26 }])
  episodiosMock.mockReset().mockResolvedValue(Array.from({ length: 26 }, (_, i) => episodio(i + 1)))
  rescatarMock.mockReset().mockResolvedValue(undefined)
  abrirLead.mockReset()
  toastSuccess.mockReset()
  toastError.mockReset()
})

afterEach(() => {
  vi.restoreAllMocks()
  vi.clearAllMocks()
})

describe('Base para gestión', () => {
  it('abre una carpeta en otra pestaña y conserva el mosaico en la actual', async () => {
    const usuario = userEvent.setup()
    const pestana = { opener: window } as unknown as Window
    const abrirPestana = vi.spyOn(window, 'open').mockReturnValue(pestana)
    render(<RescateDescartados />)

    await usuario.click(await screen.findByRole('button', { name: 'Abrir carpeta Sin interés' }))

    expect(abrirPestana).toHaveBeenCalledOnce()
    const [destino, target] = abrirPestana.mock.calls[0] ?? []
    const url = new URL(String(destino))
    expect(target).toBe('_blank')
    expect(url.searchParams.get('rescate_carpeta')).toBe('sin_interes')
    expect(url.searchParams.get('rescate_mes')).toBe(mesActualLima())
    expect(url.hash).toBe('#/rescate-carpeta')
    expect(pestana.opener).toBeNull()
    expect(screen.getByText('Base para gestión')).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Sin interés' })).not.toBeInTheDocument()
  })

  it('abre cada bloque en una carpeta propia y pagina sus leads sin agrandar el mosaico', async () => {
    const usuario = userEvent.setup()
    window.history.replaceState(null, '', `/?rescate_carpeta=sin_interes&rescate_mes=${mesActualLima()}#/rescate-carpeta`)
    render(<RescateCarpeta />)

    expect(await screen.findByText('LEAD RESCATE 1')).toBeInTheDocument()
    expect(screen.queryByText('LEAD RESCATE 20')).not.toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Paginación de la carpeta' }))
      .toHaveTextContent('Página 1 de 2 · 26 registros')

    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
    expect(await screen.findByText('LEAD RESCATE 20')).toBeInTheDocument()
  })

  it('selecciona un bloque y lo reactiva con la protección de no devolverlo al origen', async () => {
    const usuario = userEvent.setup()
    episodiosMock.mockResolvedValue([episodio(1), episodio(2)])
    mesesMock.mockResolvedValue([{ mes: mesActualLima(), total: 2, pendientes: 2 }])
    window.history.replaceState(null, '', `/?rescate_carpeta=sin_interes&rescate_mes=${mesActualLima()}#/rescate-carpeta`)
    render(<RescateCarpeta />)

    await screen.findByText('LEAD RESCATE 1')
    await usuario.click(screen.getByRole('button', { name: 'Seleccionar esta página (2)' }))
    await usuario.click(screen.getByRole('button', { name: 'Reactivar y repartir' }))

    await usuario.selectOptions(screen.getByLabelText('Asesor destino'), 'asesor-destino')
    await usuario.click(screen.getByRole('button', { name: 'Reactivar 2 y repartir' }))

    await waitFor(() => expect(rescatarMock).toHaveBeenCalledWith(
      ['episodio-1', 'episodio-2'],
      ['asesor-destino'],
      true,
    ))
    expect(toastSuccess).toHaveBeenCalledWith('2 leads reactivados y repartidos')
  })
})
