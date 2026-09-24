import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { VentaCruzada } from './venta-cruzada'
import type { BusquedaCliente } from '@/data/cliente-existente-api'

const api = vi.hoisted(() => ({ buscar: vi.fn(), abrir: vi.fn() }))
vi.mock('@/data/cliente-existente-api', () => ({ buscarClienteExistente: api.buscar }))
vi.mock('@/lib/router', async (original) => ({ ...await original<typeof import('@/lib/router')>(), abrirInversionista: api.abrir }))
// Un diálogo REAL encima de la búsqueda: así se prueba adónde vuelve el foco.
vi.mock('./inversion-nueva', async () => {
  const { Dialog, DialogTitle } = await import('@/components/ui/dialog')
  return {
    InversionNueva: (p: { persona: string; origenClienteExistente: { busquedaId: string }
      onCerrar: () => void; onRevocado: () => void; onConfirmada: () => void }) =>
      <Dialog open onClose={p.onCerrar} ariaLabel="Nueva inversión"><DialogTitle>Nueva inversión</DialogTitle>
        <p data-testid="inversion-nueva">{p.persona}|{p.origenClienteExistente.busquedaId}</p>
        <button type="button" onClick={p.onCerrar}>Cerrar la inversión</button>
        <button type="button" onClick={p.onRevocado}>Simular acceso vencido</button>
        <button type="button" onClick={p.onConfirmada}>Simular confirmación</button>
      </Dialog>,
  }
})

const ACTOR = '55555555-5555-4555-8555-555555555555'
const PERSONA = '33333333-3333-4333-8333-333333333333'
const BUSQUEDA = '11111111-1111-4111-8111-111111111111'
const cliente = {
  inversionista_id: PERSONA, nombre: 'VC CLIENTE X', documento_tipo: 'DNI' as const, documento_enmascarado: '•••••021',
  responsable_nombre: 'VC ANALISTA A', empresas: ['avance', 'qorilazo'], es_mi_cartera: false,
}
const acciones = { ver_ficha: false, nueva_inversion: true, requiere_documento: false, motivo_codigo: null, motivo_no_operable: null }
const porDocumento: BusquedaCliente = { estado: 'encontrado', busqueda_id: BUSQUEDA, criterio: 'documento', cliente, acciones }
const cerrar = vi.fn()

function montar(props: Partial<Parameters<typeof VentaCruzada>[0]> = {}) {
  render(<VentaCruzada actor={ACTOR} puedeRegistrar onCerrar={cerrar} {...props} />)
  return userEvent.setup()
}
beforeEach(() => {vi.clearAllMocks()})
afterEach(() => {cleanup()})

describe('venta cruzada: buscar al cliente de otra cartera', () => {
  it('por documento: muestra quién es, su responsable y abre la nueva inversión con la búsqueda como llave', async () => {
    api.buscar.mockResolvedValue(porDocumento)
    const user = montar()
    await user.type(screen.getByLabelText('Número'), '70000021')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(api.buscar).toHaveBeenCalledWith({ tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' })
    const tarjeta = await screen.findByRole('region', { name: 'Esta persona ya es cliente' })
    expect(tarjeta).toHaveTextContent('VC CLIENTE X')
    expect(tarjeta).toHaveTextContent('VC ANALISTA A')
    expect(tarjeta).toHaveTextContent('Avance')
    await user.click(screen.getByRole('button', { name: 'Nueva inversión' }))
    expect(screen.getByTestId('inversion-nueva')).toHaveTextContent(`${PERSONA}|${BUSQUEDA}`)
  })

  it('quien no registra ventas (Gerencia) ve al cliente pero no la nueva inversión', async () => {
    api.buscar.mockResolvedValue(porDocumento)
    const user = montar({ puedeRegistrar: false })
    await user.type(screen.getByLabelText('Número'), '70000021')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    await screen.findByRole('region', { name: 'Esta persona ya es cliente' })
    expect(screen.queryByRole('button', { name: 'Nueva inversión' })).not.toBeInTheDocument()
  })

  it('por teléfono solo da iniciales y pide el documento para registrar', async () => {
    api.buscar.mockResolvedValue({ ...porDocumento, criterio: 'telefono',
      cliente: { ...cliente, inversionista_id: null, nombre: 'VC C. X.' },
      acciones: { ...acciones, nueva_inversion: false, requiere_documento: true } })
    const user = montar()
    await user.click(screen.getByRole('button', { name: 'Teléfono' }))
    await user.type(screen.getByLabelText('Teléfono'), '987 000 021')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(api.buscar).toHaveBeenCalledWith({ tipo: 'telefono', telefono: '987 000 021' })
    expect(await screen.findByText('VC C. X.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nueva inversión' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Buscar por documento' }))
    await waitFor(() => expect(screen.getByLabelText('Número')).toHaveFocus())
    expect(screen.getByLabelText('Tipo de documento')).toHaveValue('DNI')
  })

  it('un motivo reservado no nombra a la persona', async () => {
    api.buscar.mockResolvedValue({ estado: 'no_operable', busqueda_id: BUSQUEDA, criterio: 'documento',
      cliente: { es_mi_cartera: false },
      acciones: { ...acciones, nueva_inversion: false, motivo_codigo: 'no_admite', motivo_no_operable: 'La persona no admite nuevas inversiones por ahora.' } })
    const user = montar()
    await user.type(screen.getByLabelText('Número'), '70000025')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(await screen.findByText('La persona no admite nuevas inversiones por ahora.')).toBeInTheDocument()
    expect(screen.queryByText('VC CLIENTE X')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nueva inversión' })).not.toBeInTheDocument()
  })

  it('el cliente de la propia cartera se abre en su ficha', async () => {
    api.buscar.mockResolvedValue({ ...porDocumento, cliente: { ...cliente, es_mi_cartera: true },
      acciones: { ...acciones, ver_ficha: true, nueva_inversion: false } })
    const user = montar()
    await user.type(screen.getByLabelText('Número'), '70000021')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    await screen.findByRole('region', { name: 'Este cliente es de tu cartera' })
    await user.click(screen.getByRole('button', { name: 'Ver cliente' }))
    expect(api.abrir).toHaveBeenCalledWith(PERSONA)
    expect(cerrar).toHaveBeenCalled()
  })

  it('con un resultado ya obtenido (el lead descartado) no vuelve a buscar y propone su DNI', async () => {
    const user = montar({ resultadoInicial: { ...porDocumento, criterio: 'lead',
      cliente: { ...cliente, inversionista_id: null }, acciones: { ...acciones, nueva_inversion: false, requiere_documento: true } },
      documentoSugerido: { tipo: 'DNI', numero: '70000021' } })
    expect(screen.getByRole('region', { name: 'Esta persona ya es cliente' })).toHaveTextContent('VC CLIENTE X')
    expect(api.buscar).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Buscar por documento' }))
    expect(screen.getByLabelText('Número')).toHaveValue('70000021')
  })

  it.each([
    ['no_encontrado', 'No encontramos a un cliente con ese dato'],
    ['ambiguo', 'Ese teléfono lo comparten varios clientes'],
    ['limite', 'Hiciste muchas búsquedas en la última hora'],
    ['invalido', 'no tiene un formato válido'],
  ] as const)('el veredicto %s se explica', async (estado, texto) => {
    api.buscar.mockResolvedValue({ estado, busqueda_id: BUSQUEDA, criterio: 'documento' })
    const user = montar()
    await user.type(screen.getByLabelText('Número'), '70000099')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(await screen.findByText(new RegExp(texto))).toBeInTheDocument()
  })

  it('sin número no busca', async () => {
    const user = montar()
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Escribe el número de documento.')
    expect(api.buscar).not.toHaveBeenCalled()
  })

  it('abre buscando lo que ya escribió quien vende, una sola vez', async () => {
    api.buscar.mockResolvedValue(porDocumento)
    montar({ inicial: { tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' } })
    await screen.findByRole('region', { name: 'Esta persona ya es cliente' })
    expect(api.buscar).toHaveBeenCalledTimes(1)
  })

  it('la nueva inversión se abre ENCIMA: al cerrarla sin confirmar, el foco vuelve a su botón', async () => {
    api.buscar.mockResolvedValue(porDocumento)
    const user = montar({ inicial: { tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' } })
    await user.click(await screen.findByRole('button', { name: 'Nueva inversión' }))
    expect(screen.getByTestId('inversion-nueva')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Cerrar la inversión' }))
    expect(screen.queryByTestId('inversion-nueva')).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: 'Nueva inversión' })).toHaveFocus())
    expect(cerrar).not.toHaveBeenCalled()
  })

  it('confirmada la inversión, cerrarla cierra también la búsqueda', async () => {
    api.buscar.mockResolvedValue(porDocumento)
    const onConfirmada = vi.fn()
    const user = montar({ inicial: { tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' }, onConfirmada })
    await user.click(await screen.findByRole('button', { name: 'Nueva inversión' }))
    await user.click(screen.getByRole('button', { name: 'Simular confirmación' }))
    expect(onConfirmada).toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Cerrar la inversión' }))
    expect(cerrar).toHaveBeenCalled()
  })

  it('si la búsqueda vence mientras registra, vuelve a la búsqueda y dice por qué', async () => {
    api.buscar.mockResolvedValue(porDocumento)
    const user = montar({ inicial: { tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' } })
    await user.click(await screen.findByRole('button', { name: 'Nueva inversión' }))
    await user.click(screen.getByRole('button', { name: 'Simular acceso vencido' }))
    expect(screen.getByRole('alert')).toHaveTextContent('La búsqueda venció o cambió tu acceso. Vuelve a buscarlo por su documento.')
    expect(screen.queryByRole('region', { name: 'Esta persona ya es cliente' })).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByLabelText('Número')).toHaveFocus())
    expect(cerrar).not.toHaveBeenCalled()
  })

  it('el error de un campo vacío queda asociado al campo', async () => {
    const user = montar()
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(screen.getByLabelText('Número')).toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByLabelText('Número')).toHaveAccessibleDescription('Escribe el número de documento.')
    await user.click(screen.getByRole('button', { name: 'Teléfono' }))
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(screen.getByLabelText('Teléfono')).toHaveFocus()
    expect(screen.getByLabelText('Teléfono')).toHaveAttribute('aria-invalid', 'true')
  })

  it('una segunda búsqueda retira el veredicto anterior mientras espera (así el mismo veredicto se vuelve a anunciar)', async () => {
    let resolver!: (v: BusquedaCliente) => void
    api.buscar.mockResolvedValueOnce({ estado: 'no_encontrado', busqueda_id: BUSQUEDA, criterio: 'documento' })
      .mockReturnValueOnce(new Promise<BusquedaCliente>((r) => {resolver = r}))
    const user = montar()
    await user.type(screen.getByLabelText('Número'), '70000099')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(await screen.findByText(/No encontramos a un cliente/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(screen.queryByText(/No encontramos a un cliente/)).not.toBeInTheDocument()
    resolver({ estado: 'no_encontrado', busqueda_id: BUSQUEDA, criterio: 'documento' })
    expect(await screen.findByText(/No encontramos a un cliente/)).toBeInTheDocument()
  })
})
