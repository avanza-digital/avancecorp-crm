// El receptor del enlace del celular (F1.2.3 y F1.3.3): lee el número del hash
// una sola vez, lo quita de la URL, espera al store, y con un solo lead arma la
// intención y abre la ficha si nadie la toma; en los demás casos avisa y deja
// elegir o buscar a mano. La coincidencia tiene sus tests; aquí se prueba QUÉ
// hace con cada resultado.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { Lead } from '@/lib/tipos'
import * as config from '@/lib/config'
import { armarIntencion, cerrarIntencion, intencionDe, limpiarIntencionesContacto, reclamarIntencion, suscribirIntenciones } from '@/lib/intencion-contacto'

const dobles = vi.hoisted(() => ({
  yo: { id: 'v1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' },
  cargando: false,
  leads: [] as Lead[],
  conocerLeads: vi.fn(),
  abrirLead: vi.fn(async () => true),
  resolver: vi.fn(),
  buscarManual: vi.fn(),
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn() },
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ ambito: { leads: dobles.leads }, conocerLeads: dobles.conocerLeads }),
  usePanelesActions: () => ({ abrirLead: dobles.abrirLead }),
  useStoreEstado: () => ({ cargando: dobles.cargando, error: false, reintentar: () => {} }),
}))
vi.mock('@/data/coincidencia-llamada', () => ({
  resolverNumeroLlamada: (...args: unknown[]) => dobles.resolver(...args),
  buscarLeadsManual: (...args: unknown[]) => dobles.buscarManual(...args),
}))
vi.mock('sonner', () => ({ toast: dobles.toast }))
const { ReceptorLlamada } = await import('./receptor-llamada')

/** Números sintéticos: no son de nadie. */
const lead = (id: string, nombre: string, telefono: string, extra: Partial<Lead> = {}): Lead =>
  ({ id, nombre_completo: nombre, telefono, telefono_alternativo: null, etapa: 'nuevo', activo: true, vendedor_id: 'v1', ...extra }) as unknown as Lead
const L1 = lead('lead-1', 'MARÍA PÉREZ', '+51999888777')
const L2 = lead('lead-2', 'JUAN QUISPE', '+51999888777')
const SIN = { estado: 'sin_coincidencia', numero: '+51999888777', reconocido: true, terminales: [] }

const esperar = (ms = 10) => new Promise((r) => setTimeout(r, ms))

beforeEach(() => {
  limpiarIntencionesContacto()
  window.history.replaceState(null, '', '/')
  dobles.yo = { id: 'v1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }
  dobles.cargando = false
  dobles.leads = []
  dobles.resolver.mockResolvedValue(SIN)
  dobles.buscarManual.mockResolvedValue([])
  dobles.abrirLead.mockResolvedValue(true)
})

describe('ReceptorLlamada', () => {
  it('con un solo lead: quita el número del hash, arma la intención (origen enlace) y abre la ficha si nadie la toma', async () => {
    window.location.hash = '#/gestion-diaria/llamada/%2B51999888777'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    render(<ReceptorLlamada />)
    expect(window.location.hash).toBe('#/gestion-diaria')
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-1'), { timeout: 2_000 })
    expect(dobles.resolver).toHaveBeenCalledWith('+51999888777', expect.objectContaining({ demo: false }))
    expect(dobles.conocerLeads).toHaveBeenCalledWith([L1])
    expect(intencionDe('v1', 'lead-1')).toMatchObject({ origen: 'enlace', numero: '+51999888777', canal: 'tel', abierta: false })
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    expect(dobles.toast.info).not.toHaveBeenCalled()
  })

  it('si una AccionesContacto del lead toma la intención en el mismo tick, no abre la ficha', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    // Lo que hace la instancia de «Ahora» al ver aparecer una intención del enlace.
    const dejar = suscribirIntenciones(() => {
      const i = intencionDe('v1', 'lead-1')
      if (i && !i.abierta) reclamarIntencion(i.id)
    })
    render(<ReceptorLlamada />)
    await waitFor(() => expect(intencionDe('v1', 'lead-1')).toMatchObject({ abierta: true }))
    // Más que la espera de reclamo: la ficha no se abre porque la intención ya está tomada.
    await act(async () => { await esperar(800) })
    expect(dobles.abrirLead).not.toHaveBeenCalled()
    dejar()
  })

  it('la tarjeta tiene tiempo de tomar la intención: la ficha no se abre en el acto', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    render(<ReceptorLlamada />)
    await waitFor(() => expect(intencionDe('v1', 'lead-1')).toMatchObject({ origen: 'enlace', abierta: false }))
    await act(async () => { await esperar(100) })
    expect(dobles.abrirLead).not.toHaveBeenCalled()
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-1'), { timeout: 2_000 })
  })

  it('con una encuesta abierta, la segunda llamada espera y se atiende sola al cerrarse la primera', async () => {
    // La encuesta de otro lead está abierta (intención tomada).
    const abierta = armarIntencion({ actor: 'v1', leadId: 'lead-9', canal: 'tel', origen: 'pantalla' })
    reclamarIntencion(abierta.id)
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L2, terminales: [] })
    render(<ReceptorLlamada />)
    await waitFor(() => expect(dobles.resolver).toHaveBeenCalledTimes(1))
    await act(async () => { await esperar(800) })
    expect(dobles.abrirLead).not.toHaveBeenCalled()
    expect(intencionDe('v1', 'lead-2')).toBeNull() // espera detrás de la abierta
    act(() => { cerrarIntencion(abierta.id) })
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-2'), { timeout: 2_000 })
  })

  it('si el lead ya no es visible al abrir su ficha, la intención se cierra y la cola no se atasca', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    dobles.abrirLead.mockResolvedValue(false)
    render(<ReceptorLlamada />)
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-1'), { timeout: 2_000 })
    await waitFor(() => expect(intencionDe('v1', 'lead-1')).toBeNull())
  })

  it('número reciclado: el lead vivo es el candidato y se avisa quién más lo tuvo', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    const L9 = lead('lead-9', 'ELENA VARGAS', '+51999888777', { etapa: 'descartado' })
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [L9] })
    render(<ReceptorLlamada />)
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-1'), { timeout: 2_000 })
    expect(dobles.toast.info).toHaveBeenCalledWith('Ojo: este número también figura en ELENA VARGAS (descartado).')
  })

  it('espera a que el store termine de cargar antes de buscar (tras el login)', async () => {
    window.location.hash = '#/gestion-diaria/llamada/999888777'
    dobles.cargando = true
    const { rerender } = render(<ReceptorLlamada />)
    expect(window.location.hash).toBe('#/gestion-diaria')
    await act(async () => { await esperar() })
    expect(dobles.resolver).not.toHaveBeenCalled()
    dobles.cargando = false
    rerender(<ReceptorLlamada />)
    await waitFor(() => expect(dobles.resolver).toHaveBeenCalledTimes(1))
    // La respuesta del resolver llega en otra vuelta: se espera el texto, no se lee en el mismo tick (en CI perdía la carrera).
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Ningún lead de tu cartera tiene el número 999 888 777.'))
  })

  it('ambiguo: lista los candidatos y elegir uno arma la intención y abre su ficha', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.resolver.mockResolvedValue({ estado: 'ambiguo', numero: '+51999888777', leads: [L1, L2] })
    render(<ReceptorLlamada />)
    expect(await screen.findByText('2 leads tienen el número 999 888 777. ¿A quién llamaste?')).toBeInTheDocument()
    const lista = screen.getByRole('list', { name: 'Leads con este número' })
    expect(lista.querySelectorAll('li')).toHaveLength(2)
    fireEvent.click(screen.getByRole('button', { name: /JUAN QUISPE/ }))
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-2'), { timeout: 2_000 })
    expect(intencionDe('v1', 'lead-2')).toMatchObject({ origen: 'enlace', numero: '+51999888777' })
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  // F4-b: el id de la llamada viaja con la intención; el hash se limpia entero.
  it('con el id de la llamada en el enlace: lo quita del hash con el número y lo lleva en la intención', async () => {
    vi.spyOn(config, 'llamadasCelularHabilitadas').mockReturnValue(true)
    window.location.hash = '#/gestion-diaria/llamada/%2B51999888777/C1-1790980958'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    render(<ReceptorLlamada />)
    expect(window.location.hash).toBe('#/gestion-diaria')
    await waitFor(() => expect(intencionDe('v1', 'lead-1')).toMatchObject({ origen: 'enlace', origenLlamada: 'C1-1790980958' }))
  })

  it('sin activar la integración conserva F1 y abre el resultado manual aunque el enlace traiga un id', async () => {
    window.location.hash = '#/gestion-diaria/llamada/%2B51999888777/C1-1790980958'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    render(<ReceptorLlamada />)
    await waitFor(() => expect(intencionDe('v1', 'lead-1')).toMatchObject({ origen: 'enlace', numero: '+51999888777' }))
    expect(intencionDe('v1', 'lead-1')?.origenLlamada).toBeUndefined()
    expect(window.location.hash).toBe('#/gestion-diaria')
  })

  it('sin id en el enlace (la macro de hoy) la intención no inventa uno', async () => {
    window.location.hash = '#/gestion-diaria/llamada/%2B51999888777'
    dobles.resolver.mockResolvedValue({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    render(<ReceptorLlamada />)
    await waitFor(() => expect(intencionDe('v1', 'lead-1')).toMatchObject({ origen: 'enlace' }))
    expect(intencionDe('v1', 'lead-1')?.origenLlamada).toBeUndefined()
  })

  it('ambiguo con id: el lead elegido a mano también lleva el id de la llamada', async () => {
    vi.spyOn(config, 'llamadasCelularHabilitadas').mockReturnValue(true)
    window.location.hash = '#/hoy/llamada/999888777/C3-1790980958'
    dobles.resolver.mockResolvedValue({ estado: 'ambiguo', numero: '+51999888777', leads: [L1, L2] })
    render(<ReceptorLlamada />)
    fireEvent.click(await screen.findByRole('button', { name: /JUAN QUISPE/ }))
    await waitFor(() => expect(intencionDe('v1', 'lead-2')).toMatchObject({ origen: 'enlace', origenLlamada: 'C3-1790980958' }))
  })

  it('sin coincidencia: avisa, precarga la búsqueda manual con los dígitos y deja elegir un resultado', async () => {
    window.location.hash = '#/hoy/llamada/%2B51999888777'
    const L11 = lead('lead-11', 'CARLOS RUIZ', '+51999888777', { etapa: 'convertido' })
    dobles.resolver.mockResolvedValue({ ...SIN, terminales: [L11] })
    render(<ReceptorLlamada />)
    expect(await screen.findByText('Ningún lead de tu cartera tiene el número 999 888 777.')).toBeInTheDocument()
    expect(screen.getByText('Figura en CARLOS RUIZ (convertido).')).toBeInTheDocument()
    const campo = screen.getByRole('searchbox', { name: 'Buscar lead por nombre, teléfono o DNI' })
    expect(campo).toHaveValue('999888777')
    fireEvent.change(campo, { target: { value: 'maría' } })
    dobles.buscarManual.mockResolvedValue([L1])
    fireEvent.click(screen.getByRole('button', { name: 'Buscar' }))
    const resultados = await screen.findByRole('list', { name: 'Resultados de la búsqueda' })
    expect(dobles.buscarManual).toHaveBeenCalledWith('maría', expect.objectContaining({ demo: false }))
    fireEvent.click(resultados.querySelector('button')!)
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-1'), { timeout: 2_000 })
    expect(intencionDe('v1', 'lead-1')).toMatchObject({ origen: 'enlace', numero: '+51999888777' })
  })

  it('la búsqueda manual sin resultados lo dice, y un texto bajo el mínimo no busca', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    render(<ReceptorLlamada />)
    const campo = await screen.findByRole('searchbox', { name: 'Buscar lead por nombre, teléfono o DNI' })
    fireEvent.change(campo, { target: { value: 'x' } })
    expect(screen.getByRole('button', { name: 'Buscar' })).toBeDisabled()
    fireEvent.change(campo, { target: { value: 'nadie' } })
    fireEvent.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(await screen.findByText('Sin resultados en tus leads para «nadie».')).toBeInTheDocument()
  })

  it('número que no se reconoce: lo dice y ofrece buscar a mano', async () => {
    window.location.hash = '#/hoy/llamada/123'
    dobles.resolver.mockResolvedValue({ estado: 'invalido', numero: '+123' })
    render(<ReceptorLlamada />)
    expect(await screen.findByText('El celular no entregó un número reconocible («+123»). Busca el lead a mano.')).toBeInTheDocument()
    expect(screen.getByRole('searchbox', { name: 'Buscar lead por nombre, teléfono o DNI' })).toHaveValue('')
  })

  it('error: lo dice y «Reintentar» vuelve a buscar', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.resolver
      .mockResolvedValueOnce({ estado: 'error', numero: '+51999888777', mensaje: 'No se pudo buscar el número en tus leads. Revisa tu conexión.' })
      .mockResolvedValueOnce({ estado: 'unico', numero: '+51999888777', lead: L1, terminales: [] })
    render(<ReceptorLlamada />)
    expect(await screen.findByText('No se pudo buscar el número en tus leads. Revisa tu conexión.')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    await waitFor(() => expect(dobles.abrirLead).toHaveBeenCalledWith('lead-1'), { timeout: 2_000 })
    expect(dobles.resolver).toHaveBeenCalledTimes(2)
  })

  it('«Cerrar» quita el aviso', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    render(<ReceptorLlamada />)
    await screen.findByText('Ningún lead de tu cartera tiene el número 999 888 777.')
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar el aviso de la llamada' }))
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('solo lectura (directorio): quita el número del hash, avisa y no busca', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.yo = { ...dobles.yo, rol: 'directorio' }
    render(<ReceptorLlamada />)
    expect(window.location.hash).toBe('#/hoy')
    await act(async () => { await esperar() })
    expect(dobles.toast.info).toHaveBeenCalledWith('Tu cuenta no registra llamadas.')
    expect(dobles.resolver).not.toHaveBeenCalled()
  })

  it('sin número en el hash no pinta nada ni busca', async () => {
    window.location.hash = '#/gestion-diaria'
    render(<ReceptorLlamada />)
    await act(async () => { await esperar() })
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    expect(dobles.resolver).not.toHaveBeenCalled()
  })

  it('en la demo busca en el ámbito local (sin servidor)', async () => {
    window.location.hash = '#/hoy/llamada/999888777'
    dobles.yo = { ...dobles.yo, demo: true }
    dobles.leads = [L1]
    render(<ReceptorLlamada />)
    await waitFor(() => expect(dobles.resolver).toHaveBeenCalledWith('999888777', expect.objectContaining({ demo: true, leadsLocales: [L1] })))
  })

  it('en la demo espera a que lleguen los leads antes de buscar (visto en C1 tras el login)', async () => {
    window.location.hash = '#/gestion-diaria/llamada/999888777'
    dobles.yo = { ...dobles.yo, demo: true }
    dobles.leads = []
    const { rerender } = render(<ReceptorLlamada />)
    await act(async () => { await esperar() })
    expect(dobles.resolver).not.toHaveBeenCalled()
    dobles.leads = [L1]
    rerender(<ReceptorLlamada />)
    await waitFor(() => expect(dobles.resolver).toHaveBeenCalledWith('999888777', expect.objectContaining({ demo: true, leadsLocales: [L1] })))
    expect(dobles.resolver).toHaveBeenCalledTimes(1)
  })

  it('una demo sin leads no se queda colgada: a los 3 s busca con lo que haya', async () => {
    vi.useFakeTimers()
    try {
      window.location.hash = '#/gestion-diaria/llamada/999888777'
      dobles.yo = { ...dobles.yo, demo: true }
      dobles.leads = []
      render(<ReceptorLlamada />)
      expect(dobles.resolver).not.toHaveBeenCalled()
      await act(async () => { vi.advanceTimersByTime(3_000) })
      expect(dobles.resolver).toHaveBeenCalledWith('999888777', expect.objectContaining({ demo: true, leadsLocales: [] }))
    } finally {
      vi.useRealTimers()
    }
  })
})
