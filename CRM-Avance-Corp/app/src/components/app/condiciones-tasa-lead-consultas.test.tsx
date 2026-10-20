import { useState, type ReactNode } from 'react'
import { act, cleanup, fireEvent, render, renderHook, screen } from '@testing-library/react'
import { focusManager, onlineManager, QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { CrmApiError } from '@/data/crm-api'
import { crmQueryKeys, useSolicitudesTasa } from '@/data/crm-queries'
import { queryClient } from '@/lib/query-client'
import { ESTADOS_SOLICITUD_TASA_SEGUIMIENTO } from '@/lib/rentabilidad'
import type { Lead } from '@/lib/tipos'
import { SolicitudTasaLeadPlegable, type EstadoCondicionesLead } from './condiciones-tasa-lead'

const dobles = vi.hoisted(() => ({ listar: vi.fn(), observacion: true }))
vi.mock('@/data/crm-api', async (original) => ({
  ...await original<typeof import('@/data/crm-api')>(), listarSolicitudesTasa: dobles.listar,
}))
// Se conserva el hook de solicitudes real: sustituirlo por un estado fijo
// ocultaría el bucle entre los dos observadores que ocurrió en producción.
vi.mock('@/data/crm-queries', async (original) => ({
  ...await original<typeof import('@/data/crm-queries')>(),
  usePoliticaRentabilidad: () => ({ data: { observacion_sin_aprobacion: true, vigente: { modo: dobles.observacion ? 'observacion' : 'enforcement' } }, isPending: false, isError: false }),
  useResolucionTasa: () => ({ data: { observacion_sin_aprobacion: true, tasa_base: 15, tasa_minima_sin_autorizacion: 0.01, regla: 'primera_inversion', politica: { modo: dobles.observacion ? 'observacion' : 'enforcement', tope_tecnico: 25 } }, isPending: false, isError: false }),
}))

const lead = { id: 'lead-consultas', monto_estimado: 1000, moneda: 'PEN', dni: '00000000', etapa: 'contactado' } as Lead
const clave = crmQueryKeys.solicitudesTasa(ESTADOS_SOLICITUD_TASA_SEGUIMIENTO, { leadId: lead.id })
const clientes: QueryClient[] = []
function arnes() {
  const cliente = new QueryClient({ defaultOptions: queryClient.getDefaultOptions() })
  clientes.push(cliente)
  return { cliente, wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider> }
}
function Panel({ id = lead.id }: { id?: string }) {
  const [estado, setEstado] = useState<EstadoCondicionesLead | null>(null)
  return <>
    <SolicitudTasaLeadPlegable key={id} lead={{ ...lead, id }} demo={false} puedeEditar onCambio={setEstado} />
    <button type="button" disabled={!estado || !!estado.bloqueo}>Convertir a cliente</button>
  </>
}
async function avanzar(ms = 100) {
  await act(async () => { await vi.advanceTimersByTimeAsync(ms) })
  await act(async () => { await vi.advanceTimersByTimeAsync(0) })
}
function denegar(codigo = 'SIN_PERMISO') {
  dobles.listar.mockImplementation(async () => {
    await new Promise(resolve => setTimeout(resolve, 20))
    throw new CrmApiError('Lectura rechazada en la prueba', codigo)
  })
}
beforeEach(() => {
  vi.useFakeTimers()
  dobles.listar.mockReset()
  dobles.observacion = true
  focusManager.setFocused(true)
  onlineManager.setOnline(true)
  denegar()
})
afterEach(() => {
  cleanup()
  for (const cliente of clientes.splice(0)) cliente.clear()
  focusManager.setFocused(undefined)
  onlineManager.setOnline(true)
  vi.useRealTimers()
})

it.each([['SIN_PERMISO', true], ['SIN_PERMISO', false], ['42501', true], ['42501', false]] as const)('403 (%s) en observación=%s: una llamada, incluso plegado, reabierto y con foco/reconexión', async (codigo, observacion) => {
  dobles.observacion = observacion
  denegar(codigo)
  const { cliente, wrapper } = arnes()
  const vista = render(<Panel />, { wrapper })
  await avanzar()
  expect(cliente.getQueryState(clave)?.status).toBe('error')
  fireEvent.click(screen.getByRole('button', { name: 'Mostrar solicitud de tasa' }))
  fireEvent.click(screen.getByRole('button', { name: 'Ocultar solicitud de tasa' }))
  vista.rerender(<></>)
  vista.rerender(<Panel />)
  await avanzar(180_000)
  act(() => {
    focusManager.setFocused(false)
    focusManager.setFocused(true)
    onlineManager.setOnline(false)
    onlineManager.setOnline(true)
    void cliente.invalidateQueries({ queryKey: crmQueryKeys.rentabilidad() })
  })
  await avanzar()
  expect(dobles.listar).toHaveBeenCalledTimes(1)
  if (observacion) expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled()
  else expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
})

it('enforcement permite reintento explícito y recupera el formulario al responder correctamente', async () => {
  dobles.observacion = false
  const { wrapper } = arnes()
  render(<Panel />, { wrapper })
  await avanzar()
  fireEvent.click(screen.getByRole('button', { name: 'Mostrar solicitud de tasa' }))
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
  dobles.listar.mockResolvedValue([])
  fireEvent.click(screen.getByRole('button', { name: 'Reintentar condiciones' }))
  await avanzar()
  expect(dobles.listar).toHaveBeenCalledTimes(2)
  expect(screen.getByLabelText('Tasa anual (%)')).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled()
})

it('error transitorio en observación conserva el borrador durante la recuperación periódica', async () => {
  denegar('NETWORK_ERROR')
  const { wrapper } = arnes()
  render(<Panel />, { wrapper })
  await avanzar()
  fireEvent.click(screen.getByRole('button', { name: 'Mostrar solicitud de tasa' }))
  const tasa = screen.getByLabelText('Tasa anual (%)')
  fireEvent.change(tasa, { target: { value: '19' } })
  await avanzar(1000)
  expect(dobles.listar).toHaveBeenCalledTimes(1)
  // Todavía sin datos: el refetch pasa por pending, pero no desmonta el hijo.
  await avanzar(60_000)
  expect(screen.getByLabelText('Tasa anual (%)')).toBe(tasa)
  expect(tasa).toHaveValue('19')
  expect(dobles.listar).toHaveBeenCalledTimes(2)
  dobles.listar.mockResolvedValue([])
  await avanzar(60_000)
  expect(dobles.listar).toHaveBeenCalledTimes(3)
  expect(screen.getByLabelText('Tasa anual (%)')).toBe(tasa)
  expect(tasa).toHaveValue('19')
})

it('la primera lectura espera; cambiar de lead consulta una sola vez el nuevo contexto', async () => {
  dobles.listar.mockImplementation(async () => {
    await new Promise(resolve => setTimeout(resolve, 20))
    return []
  })
  const { wrapper } = arnes()
  const vista = render(<Panel />, { wrapper })
  expect(screen.queryByTestId('condiciones-tasa-lead')).not.toBeInTheDocument()
  await avanzar()
  expect(screen.getByTestId('condiciones-tasa-lead')).toBeInTheDocument()
  expect(dobles.listar).toHaveBeenCalledTimes(1)
  vista.rerender(<Panel id="otro-lead" />)
  expect(screen.queryByTestId('condiciones-tasa-lead')).not.toBeInTheDocument()
  await avanzar()
  expect(dobles.listar).toHaveBeenCalledTimes(2)
  expect(dobles.listar).toHaveBeenLastCalledWith(ESTADOS_SOLICITUD_TASA_SEGUIMIENTO, expect.any(AbortSignal), { leadId: 'otro-lead' })
})

it('un 403 posterior al éxito detiene polling y remontajes; refetch explícito restablece las actualizaciones', async () => {
  dobles.listar.mockResolvedValue([])
  const { cliente, wrapper } = arnes()
  const useConsulta = () => useSolicitudesTasa(ESTADOS_SOLICITUD_TASA_SEGUIMIENTO, true, 30_000, { leadId: lead.id })
  const primera = renderHook(useConsulta, { wrapper })
  await avanzar()
  denegar()
  await avanzar(30_000)
  await avanzar()
  expect(primera.result.current.isError).toBe(true)
  primera.unmount()
  const segunda = renderHook(useConsulta, { wrapper })
  expect(segunda.result.current.isError).toBe(true)
  await avanzar(120_000)
  await act(async () => { await cliente.invalidateQueries({ queryKey: clave }) })
  expect(dobles.listar).toHaveBeenCalledTimes(2)
  dobles.listar.mockResolvedValue([])
  act(() => { void segunda.result.current.refetch() })
  await avanzar()
  expect(segunda.result.current.isSuccess).toBe(true)
  await avanzar(30_000)
  expect(dobles.listar).toHaveBeenCalledTimes(4)
})

it('una sesión nueva con caché limpia vuelve a consultar tras un permiso denegado', async () => {
  const { cliente, wrapper } = arnes()
  const vista = render(<Panel />, { wrapper })
  await avanzar()
  vista.unmount()
  cliente.clear()
  dobles.listar.mockResolvedValue([])
  render(<Panel />, { wrapper })
  await avanzar()
  expect(dobles.listar).toHaveBeenCalledTimes(2)
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled()
})

it('un JWT vencido normalizado como SIN_PERMISO recupera por polling tras renovarse', async () => {
  dobles.listar.mockRejectedValue(new CrmApiError('Sesión vencida', 'SIN_PERMISO', 'prueba', 'PGRST301'))
  const { wrapper } = arnes()
  render(<Panel />, { wrapper })
  await avanzar()
  expect(dobles.listar).toHaveBeenCalledTimes(1)
  dobles.listar.mockResolvedValue([])
  await avanzar(60_000)
  expect(dobles.listar).toHaveBeenCalledTimes(2)
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled()
})

it('las bandejas sin lead conservan la recuperación al remontar tras un error transitorio', async () => {
  denegar('NETWORK_ERROR')
  const { wrapper } = arnes()
  const useBandeja = () => useSolicitudesTasa(['pendiente'], true)
  const primera = renderHook(useBandeja, { wrapper })
  await avanzar()
  primera.unmount()
  dobles.listar.mockResolvedValue([])
  const segunda = renderHook(useBandeja, { wrapper })
  expect(segunda.result.current.isSuccess).toBe(false)
  await avanzar()
  expect(dobles.listar).toHaveBeenCalledTimes(2)
  expect(segunda.result.current.isSuccess).toBe(true)
})
