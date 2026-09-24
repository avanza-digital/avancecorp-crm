import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { InversionNueva } from './inversion-nueva'
import { guardarIntentoInversion, leerIntentoInversion, nuevoIntentoInversion, type IntentoInversion, type SolicitudInversion } from '@/lib/inversion-solicitud'
import type { ContextoClienteExistente } from '@/data/cliente-existente-api'

const ACTOR = '55555555-5555-4555-8555-555555555555'
const PERSONA = '33333333-3333-4333-8333-333333333333'
const BUSQUEDA = '11111111-1111-4111-8111-111111111111'
const RESPONSABLE = '44444444-4444-4444-8444-444444444444'

const api = vi.hoisted(() => ({ contexto: vi.fn(), cuentas: vi.fn(), legales: vi.fn(), upgrade: vi.fn(), preparar: vi.fn(),
  consultar: vi.fn(), confirmar: vi.fn(), ficha: vi.fn() }))
vi.mock('@/data/cliente-existente-api', () => ({ obtenerContextoClienteExistente: api.contexto, cuentasClienteExistente: api.cuentas,
  datosLegalesClienteExistente: api.legales, contratosUpgradeClienteExistente: api.upgrade }))
vi.mock('@/data/inversion-solicitud-api', () => ({ prepararSolicitudInversion: api.preparar, consultarSolicitudInversion: api.consultar,
  confirmarSolicitudInversion: api.confirmar, corregirSolicitudInversion: vi.fn(), revisarResponsableInversion: vi.fn(),
  completarAccesoInversion: vi.fn(), subirComprobanteInversion: vi.fn(), obtenerContextoConversionInversion: vi.fn(),
  enviarBienvenidaInversion: vi.fn(), cancelarSolicitudInversion: vi.fn() }))
vi.mock('@/data/inversionistas-api', () => ({ obtenerFichaInversionista: api.ficha, descargarDocumentoInversionista: vi.fn() }))
// El formulario del contrato se prueba aparte; aquí importa QUÉ contratos recibe para un upgrade.
vi.mock('./contrato-nuevo', () => ({
  ContratoNuevo: (p: { contratosActivos?: unknown }) => <p data-testid="contrato-nuevo">{JSON.stringify(p.contratosActivos)}</p>,
}))

const contexto: ContextoClienteExistente = {
  solicitud_id: null, documento_tipo: 'DNI',
  persona: { inversionista_id: PERSONA, perfil_id: '66666666-6666-4666-8666-666666666666', tiene_acceso_avance: true,
    nombre: 'VC CLIENTE X', correo: null, telefono: null, responsable_id: RESPONSABLE, responsable_nombre: 'VC ANALISTA A' },
  capacidades: { nueva_inversion: true, motivo_codigo: null, motivo_no_operable: null },
}
const solicitud = (id: string, datos: IntentoInversion['datos']): SolicitudInversion => ({ solicitud_id: id, estado: 'preparada',
  inversion_id: null, inversionista_id: PERSONA, inversionista_origen_id: PERSONA, identidad_fusionada: false,
  responsable_esperado_id: RESPONSABLE, responsable_actual_id: RESPONSABLE, requiere_revision_responsable: false, revision_datos: 0,
  revision_responsable: 0, hash_datos: 'h', necesita_portal: false, comprobante_bucket: 'f4-comprobantes',
  comprobante_ruta: `${PERSONA}/${id}/comprobante.pdf`, resultado: null, datos, puerta: 'cliente_existente', analista_cierre_id: ACTOR })

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(<QueryClientProvider client={qc}><InversionNueva actor={ACTOR} persona={PERSONA} origenClienteExistente={{ busquedaId: BUSQUEDA }}
    onCerrar={vi.fn()} onRevocado={vi.fn()} onConfirmada={vi.fn()} /></QueryClientProvider>)
  return userEvent.setup()
}
beforeEach(() => {
  vi.clearAllMocks(); sessionStorage.clear()
  api.contexto.mockResolvedValue(structuredClone(contexto)); api.upgrade.mockResolvedValue([])
})
afterEach(() => {cleanup()})

describe('Nueva inversión de un cliente de otra cartera', () => {
  it('pide el motivo antes de elegir empresa y prepara por la puerta de la venta cruzada', async () => {
    api.preparar.mockImplementation(async (i: IntentoInversion) => solicitud(i.clave, i.datos))
    api.consultar.mockImplementation(async (id: string) => solicitud(id, leerIntentoInversion(ACTOR, PERSONA, { ventaCruzada: true })!.datos))
    const user = montar()
    await screen.findByText(/quedará a tu nombre y su responsable, VC ANALISTA A/)
    expect(api.contexto).toHaveBeenCalledWith({ busquedaId: BUSQUEDA }, expect.anything())
    const qorilazo = screen.getByRole('button', { name: 'Qorilazo' })
    const motivo = screen.getByLabelText('Motivo de la venta, sin datos personales')
    // Sin motivo, la empresa sigue enfocable, explica por qué no avanza y lleva al campo.
    expect(qorilazo).toHaveAttribute('aria-disabled', 'true')
    expect(qorilazo).toHaveAccessibleDescription('Escribe primero el motivo de la venta para elegir la empresa.')
    await user.click(qorilazo)
    expect(motivo).toHaveFocus()
    expect(screen.queryByLabelText('Capital en soles (PEN)')).not.toBeInTheDocument()
    await user.type(motivo, 'Corto')
    expect(qorilazo).toHaveAttribute('aria-disabled', 'true')
    expect(motivo).toHaveAccessibleDescription(/faltan 5/)
    await user.type(motivo, ': el cliente pidió invertir conmigo')
    expect(qorilazo).not.toHaveAttribute('aria-disabled')
    await user.click(qorilazo)
    await user.type(screen.getByLabelText('Capital en soles (PEN)'), '2500')
    await user.type(screen.getByLabelText('Número de operación del depósito'), 'VC-DEP-001')
    await user.clear(screen.getByLabelText('Fecha comercial (inicio)')); await user.type(screen.getByLabelText('Fecha comercial (inicio)'), '2026-09-01')
    await user.type(screen.getByLabelText('Plazo (meses)'), '12')
    await user.type(screen.getByLabelText('Rentabilidad anual (%)'), '12')
    await user.type(screen.getByLabelText('Referencia de la inversión'), 'REFERENCIA VC')
    await user.upload(screen.getByLabelText(/Comprobante PDF/), new File(['pdf sintético'], 'prueba.pdf', { type: 'application/pdf' }))
    fireEvent.submit(screen.getByRole('button', { name: 'Revisar inversión' }).closest('form')!)
    await screen.findByRole('button', { name: 'Confirmar inversión' })
    const intento = api.preparar.mock.calls[0]![0] as IntentoInversion
    expect(intento.venta_cruzada).toEqual({ busqueda_id: BUSQUEDA, motivo: 'Corto: el cliente pidió invertir conmigo' })
    expect(intento.datos).toMatchObject({ inversionista_id: PERSONA, empresa: 'qorilazo', monto: 2500 })
    expect(intento.datos).not.toHaveProperty('lead_id')
    // El intento vive aparte del de Cartera, y la llave pasa a ser la solicitud.
    expect(leerIntentoInversion(ACTOR, PERSONA, { ventaCruzada: true })?.clave).toBe(intento.clave)
    expect(leerIntentoInversion(ACTOR, PERSONA)).toBeNull()
    await waitFor(() => expect(api.contexto).toHaveBeenCalledWith({ solicitudId: intento.clave }, expect.anything()))
  })

  it('si hoy no se puede invertir, lo dice con el motivo del servidor y no ofrece empresas', async () => {
    api.contexto.mockResolvedValue({ ...structuredClone(contexto), capacidades: { nueva_inversion: false,
      motivo_codigo: 'responsable_inactivo', motivo_no_operable: 'El cliente no tiene un responsable activo: pide a Gerencia que se lo asigne.' } })
    montar()
    expect(await screen.findByText('El cliente no tiene un responsable activo: pide a Gerencia que se lo asigne.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Qorilazo' })).not.toBeInTheDocument()
    expect(api.preparar).not.toHaveBeenCalled()
  })

  it('una solicitud cancelada ya no es llave: se vuelve a la búsqueda y se puede iniciar otra', async () => {
    const clave = '77777777-7777-4777-8777-777777777777'
    const datos = { inversionista_id: PERSONA, empresa: 'qorilazo' as const, monto: 2500, moneda: 'PEN' as const }
    guardarIntentoInversion(nuevoIntentoInversion(ACTOR, PERSONA, clave, datos, undefined,
      { busqueda_id: BUSQUEDA, motivo: 'El cliente pidió invertir conmigo' }))
    api.consultar.mockResolvedValue({ ...solicitud(clave, datos), estado: 'cancelada' })
    montar()
    expect(await screen.findByText('Esta solicitud está cancelada. No se registró ninguna inversión.')).toBeInTheDocument()
    expect(api.contexto).toHaveBeenCalledWith({ busquedaId: BUSQUEDA }, expect.anything())
    expect(api.contexto).not.toHaveBeenCalledWith({ solicitudId: clave }, expect.anything())
    expect(api.upgrade).not.toHaveBeenCalledWith({ solicitudId: clave }, expect.anything())
    await waitFor(() => expect(screen.getByRole('button', { name: 'Iniciar otra inversión' })).toBeEnabled())
  })

  it('si los contratos para un upgrade no cargan, lo dice y reintenta: no ofrece un contrato «sin contratos»', async () => {
    api.upgrade.mockRejectedValueOnce(new Error('red caída'))
      .mockResolvedValueOnce([{ contrato_id: '88888888-8888-4888-8888-888888888888', numero_contrato: '2026-01-000123',
        capital: 1500, moneda: 'PEN', tasa_anual: 15, fecha_vencimiento: '2027-09-01' }])
    const user = montar()
    await screen.findByText(/quedará a tu nombre/)
    await user.type(screen.getByLabelText('Motivo de la venta, sin datos personales'), 'El cliente pidió invertir conmigo')
    await user.click(screen.getByRole('button', { name: 'Avance' }))
    expect(await screen.findByText('No pudimos cargar los contratos del cliente que un upgrade puede ampliar.')).toBeInTheDocument()
    expect(screen.queryByTestId('contrato-nuevo')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(await screen.findByTestId('contrato-nuevo')).toHaveTextContent('2026-01-000123')
  })
})
