import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { InversionNueva } from './inversion-nueva'
import { CrmApiError } from '@/data/crm-api'
import { guardarIntentoInversion, leerIntentoInversion, nuevoIntentoInversion, type DatosInversion, type SolicitudInversion } from '@/lib/inversion-solicitud'
import { ACTOR_F5, PERSONA_F5, FUENTE_F5, fichaF5 } from '@/test/fixtures/f5'

const LEAD = '55555555-5555-4555-8555-555555555555'
const MENSAJE = 'Antes de convertir, registra que asistió a su cita y que la entrevista se realizó, con su resultado. Revisa los pasos en la ficha del lead.'
const api = vi.hoisted(() => ({ contexto: vi.fn(), consultar: vi.fn(), confirmar: vi.fn(), acceso: vi.fn(), preparar: vi.fn() }))
vi.mock('@/data/inversion-solicitud-api', () => ({ obtenerContextoConversionInversion: api.contexto,
  consultarSolicitudInversion: api.consultar, confirmarSolicitudInversion: api.confirmar, completarAccesoInversion: api.acceso,
  prepararSolicitudInversion: api.preparar, corregirSolicitudInversion: vi.fn(), revisarResponsableInversion: vi.fn(),
  subirComprobanteInversion: vi.fn(), enviarBienvenidaInversion: vi.fn(), cancelarSolicitudInversion: vi.fn() }))
vi.mock('@/data/inversionistas-api', () => ({ obtenerFichaInversionista: vi.fn(), descargarDocumentoInversionista: vi.fn() }))

const cooperativa: DatosInversion = { inversionista_id: PERSONA_F5, lead_id: LEAD, empresa: 'qorilazo', monto: 2500,
  moneda: 'PEN', numero_transaccion: 'DEPOSITO-CONSERVADO', referencia: 'Referencia del borrador', fecha_comercial: '2026-10-01',
  vence_en: '2027-09-26', plazo_meses: 12, tasa_anual: 12,
  evidencia: { ruta: `${PERSONA_F5}/${FUENTE_F5}/comprobante.pdf` } }
const solicitud = (datos: DatosInversion): SolicitudInversion => ({ solicitud_id: FUENTE_F5, estado: 'preparada', inversion_id: null,
  inversionista_id: PERSONA_F5, inversionista_origen_id: PERSONA_F5, identidad_fusionada: false,
  responsable_esperado_id: ACTOR_F5, responsable_actual_id: ACTOR_F5, requiere_revision_responsable: false,
  revision_datos: 2, revision_responsable: 0, hash_datos: 'hash', necesita_portal: datos.empresa === 'avance',
  comprobante_bucket: 'f4-comprobantes', comprobante_ruta: datos.evidencia?.ruta ?? null, resultado: null, datos })
function montar(datos = cooperativa) {
  const intento = nuevoIntentoInversion(ACTOR_F5, PERSONA_F5, FUENTE_F5, datos)
  guardarIntentoInversion(intento)
  api.consultar.mockResolvedValue(solicitud(datos))
  api.contexto.mockResolvedValue({ solicitud_id: FUENTE_F5, documento_tipo: 'DNI',
    persona: { ...fichaF5.persona, perfil_id: datos.empresa === 'avance' ? null : fichaF5.persona.perfil_id,
      correo: datos.alta_portal?.correo ?? fichaF5.persona.correo },
    capacidades: { nueva_inversion: true, motivo_no_operable: null } })
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const onCerrar = vi.fn(), onRevocado = vi.fn(), onConfirmada = vi.fn()
  const view = render(<QueryClientProvider client={qc}><InversionNueva actor={ACTOR_F5} persona={PERSONA_F5}
    origenLead={{ id: LEAD, solicitudId: FUENTE_F5, monto: 2500, moneda: 'PEN', tipoDocumento: 'DNI' }}
    onCerrar={onCerrar} onRevocado={onRevocado} onConfirmada={onConfirmada} /></QueryClientProvider>)
  return { ...view, user: userEvent.setup(), onCerrar, onRevocado, onConfirmada, intento }
}
beforeEach(() => { vi.clearAllMocks(); sessionStorage.clear() })
afterEach(cleanup)

describe('El bloqueo de primera conversión conserva la solicitud', () => {
  it('muestra qué falta, conserva capital/comprobante/clave y confirma la misma solicitud al corregir los hechos', async () => {
    api.confirmar.mockRejectedValueOnce(new CrmApiError(MENSAJE, 'P0409')).mockResolvedValueOnce({ ok: true,
      solicitud_id: FUENTE_F5, inversion_id: FUENTE_F5, inversionista_id: PERSONA_F5, empresa: 'qorilazo', fuente: { cierre_id: FUENTE_F5 } })
    const { user, onRevocado, onConfirmada, intento } = montar()
    await user.click(await screen.findByRole('button', { name: 'Confirmar inversión' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(MENSAJE)
    expect(leerIntentoInversion(ACTOR_F5, PERSONA_F5, LEAD)).toEqual(intento)
    expect(screen.getByText('DEPOSITO-CONSERVADO')).toBeInTheDocument()
    expect(onRevocado).not.toHaveBeenCalled(); expect(onConfirmada).not.toHaveBeenCalled()
    expect(api.preparar).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Confirmar inversión' }))
    await waitFor(() => expect(onConfirmada).toHaveBeenCalledOnce())
    expect(api.confirmar.mock.calls).toEqual([[FUENTE_F5, 2], [FUENTE_F5, 2]])
  })

  it('un acceso rechazado conserva sus datos y permite cerrar para registrar la entrevista', async () => {
    const datos: DatosInversion = { inversionista_id: PERSONA_F5, lead_id: LEAD, empresa: 'avance',
      contrato: { moneda: 'PEN' }, cronograma: [], cuenta: {},
      alta_portal: { correo: 'recorrido@example.test', nombre_completo: 'PERSONA PRUEBA', apellidos: 'PRUEBA', nombres: 'PERSONA',
        domicilio: 'CALLE SINTETICA 123, LIMA', telefono: '999888777' } }
    api.acceso.mockRejectedValue(new CrmApiError(MENSAJE, 'ACCESO_PENDIENTE'))
    const { user, onCerrar, onRevocado, intento } = montar(datos)
    await user.click(await screen.findByRole('button', { name: 'Completar acceso Avance' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(MENSAJE)
    expect(leerIntentoInversion(ACTOR_F5, PERSONA_F5, LEAD)).toEqual(intento)
    expect(api.confirmar).not.toHaveBeenCalled(); expect(onRevocado).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Cerrar y continuar después' }))
    expect(onCerrar).toHaveBeenCalledOnce()
    expect(leerIntentoInversion(ACTOR_F5, PERSONA_F5, LEAD)?.datos).toEqual(datos)
  })
})
