import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { useState } from 'react'
import { beforeEach, expect, it, vi } from 'vitest'
import type { SolicitudTasa } from '@/data/crm-api'
import type { Lead } from '@/lib/tipos'
import { CondicionesTasaLeadPanel, type EstadoCondicionesLead } from './condiciones-tasa-lead'

const dobles = vi.hoisted(() => ({ filas: [] as SolicitudTasa[], error: false, pending: false, inferior: false, enviar: vi.fn(), responder: vi.fn() }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))
vi.mock('@/data/crm-queries', () => ({
  useSolicitudesTasa: () => ({ data: dobles.filas, isPending: dobles.pending, isError: dobles.error, refetch: vi.fn() }),
  useResolucionTasa: () => ({ data: { tasa_base: 15, ...(dobles.inferior ? { tasa_minima_sin_autorizacion: 0.01 } : {}), regla: 'primera_inversion', politica: { tope_tecnico: 50 } }, isPending: false, isError: false }),
  useSolicitarTasa: () => ({ mutateAsync: dobles.enviar, isPending: false }),
  useResponderTopeTasa: () => ({ mutateAsync: dobles.responder, isPending: false }),
}))
const lead = { id: 'lead-1', nombre_completo: 'PRUEBA LOCAL', monto_estimado: 20000, moneda: 'PEN' } as Lead
function solicitud(estado: SolicitudTasa['estado'] = 'pendiente'): SolicitudTasa {
  return {
    id: 'sol-1', lead_id: lead.id, cliente_id: null, estado, estado_efectivo: estado, vigente: true, categoria: 'nuevo',
    cliente_nombre: lead.nombre_completo, contrato_origen_id: null, contrato_origen_numero: null, producto_condicion_id: null,
    capital: 20000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple', fecha_inicio: '2026-10-01', fecha_vencimiento: '2027-10-01',
    tasa_base: 15, regla_base: 'primera_inversion', tasa_solicitada: 18, tasa_maxima_autorizada: estado === 'aprobada' ? 18 : estado === 'aprobada_con_tope' ? 17 : null,
    motivo: 'Solicitud de prueba', motivo_resolucion: null, motivo_analista: null, prioridad_bandeja: false, contratos_previos: 0,
    solicitada_por: 'analista', solicitante_nombre: 'ANALISTA', solicitada_en: new Date().toISOString(), vence_en: new Date(Date.now() + 86400000).toISOString(),
    resuelta_por: null, resolutor_nombre: null, resuelta_en: null, respondida_por_analista_en: null, contrato_id: null,
    es_mia: true, puede_resolver: false, puede_responder: estado === 'aprobada_con_tope',
  }
}
function Arnes({ editar = true }: { editar?: boolean }) {
  const [estado, setEstado] = useState<EstadoCondicionesLead | null>(null)
  return <>
    <CondicionesTasaLeadPanel lead={lead} demo={false} puedeEditar={editar} onCambio={setEstado} />
    <button type="button" disabled={!estado || !!estado.bloqueo}>Convertir a cliente</button>
    <output data-testid="condiciones">{JSON.stringify(estado?.condiciones)}</output>
  </>
}
beforeEach(() => { dobles.inferior = false; dobles.filas = []; dobles.error = false; dobles.pending = false; dobles.enviar.mockReset(); dobles.responder.mockReset() })
it('envía la solicitud sobre el lead sin crear ni inventar un cliente y bloquea al prepararla', async () => {
  dobles.enviar.mockImplementation(async ({ intencion }) => ({ ...solicitud(), ...intencion }))
  render(<Arnes />)
  await waitFor(() => expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled())
  fireEvent.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
  fireEvent.change(screen.getByLabelText('Tasa solicitada (%)'), { target: { value: '18' } })
  fireEvent.change(screen.getByLabelText('Motivo comercial'), { target: { value: 'Negociación con referido' } })
  fireEvent.click(screen.getByRole('button', { name: /Enviar a Gerencia/ }))
  await waitFor(() => expect(dobles.enviar).toHaveBeenCalledWith(expect.objectContaining({ intencion: expect.objectContaining({ lead_id: lead.id, cliente_id: null, capital: 20000 }), tasaSolicitada: 18 })))
  await waitFor(() => expect(screen.queryByRole('group', { name: 'Solicitar tasa superior' })).not.toBeInTheDocument())
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
})
it('al reabrir recupera monto y fechas exactas de una solicitud pendiente', () => {
  dobles.filas = [solicitud()]
  render(<Arnes />)
  expect(screen.getByTestId('condiciones')).toHaveTextContent('2026-10-01')
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
  expect(screen.getByRole('button', { name: 'Editar condiciones de inversión' })).toBeDisabled()
})
it('una aprobación precarga tasa y condiciones para el contrato; cambiar capital deja de autorizarla', async () => {
  dobles.filas = [solicitud('aprobada')]
  render(<Arnes />)
  await waitFor(() => expect(screen.getByTestId('condiciones')).toHaveTextContent('"tasa_anual":18'))
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled()
  fireEvent.click(screen.getByRole('button', { name: 'Editar condiciones de inversión' }))
  fireEvent.change(screen.getByLabelText('Capital propuesto'), { target: { value: '30000' } })
  fireEvent.click(screen.getByRole('button', { name: 'Guardar condiciones' }))
  await waitFor(() => expect(screen.getByTestId('condiciones')).toHaveTextContent('"tasa_anual":15'))
  expect(screen.getByTestId('condiciones')).toHaveTextContent('"capital":30000')
  expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
})
it('un tope requiere respuesta, y un lector no puede aceptarlo por el analista', () => {
  dobles.filas = [solicitud('aprobada_con_tope')]
  render(<Arnes editar={false} />)
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
  expect(screen.getByRole('button', { name: 'Aceptar y continuar' })).toBeDisabled()
})
it('una relectura fallida retira la confirmación previa y bloquea la conversión', async () => {
  const vista = render(<Arnes />)
  await waitFor(() => expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled())
  dobles.error = true
  vista.rerender(<Arnes />)
  expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
  expect(screen.getByRole('button', { name: 'Reintentar condiciones' })).toBeInTheDocument()
})

it('traslada la tasa menor en las condiciones sin crear una solicitud', async () => {
  dobles.inferior = true
  render(<Arnes />)
  const input = screen.getByLabelText('Tasa anual (%)')
  for (const [texto, numero] of [['12', 12], ['13,5', 13.5], ['14.99', 14.99], ['15', 15]] as const) {
    fireEvent.change(input, { target: { value: texto } })
    await waitFor(() => expect(screen.getByTestId('condiciones')).toHaveTextContent(`"tasa_anual":${numero}`))
    expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeEnabled()
  }
  expect(screen.getByText('Tasa acordada')).toBeInTheDocument()
  expect(dobles.enviar).not.toHaveBeenCalled()
  for (const texto of ['', '0', '-1', '16', '13.555']) {
    fireEvent.change(input, { target: { value: texto } })
    expect(screen.getByRole('button', { name: 'Convertir a cliente' })).toBeDisabled()
  }
})
