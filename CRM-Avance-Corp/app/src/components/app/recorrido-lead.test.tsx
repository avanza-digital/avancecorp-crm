import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { Lead, Tarea } from '@/lib/tipos'
import type { RecorridoLead } from '@/lib/recorrido-lead'
import type { EstadoConsultaRecorrido } from '@/data/recorrido-queries'
import { recorridoFixture, recorridoId as id } from '@/test/fixtures/recorrido'
import { RecorridoBreve, RecorridoEnMiDia, RecorridoFicha } from './recorrido-lead'

const consulta = { estado: 'listo' as EstadoConsultaRecorrido, porLead: new Map<string, RecorridoLead>(), refetch: vi.fn() }
let yo = { id: 'analista', rol: 'vendedor', demo: false }
const obtenerTareaParaRevision = vi.fn()
vi.mock('@/data/recorrido-queries', () => ({ useRecorridoLeads: () => consulta }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ obtenerTareaParaRevision }) }))
vi.mock('sonner', () => ({ toast: { error: vi.fn() } }))
vi.mock('./cerrar-tarea', () => ({
  AtenderOficinaDialog: ({ onCerrar }: { onCerrar: () => void }) => <div role="dialog" aria-label="Visita en oficina"><label>Nota de oficina<input /></label><button onClick={onCerrar}>Cerrar oficina</button></div>,
  CerrarTareaDialog: ({ tarea }: { tarea: Tarea | null }) => tarea && <div role="dialog" aria-label="Cierre habitual">{tarea.id}</div>,
}))
const lead = { id: id(1), nombre_completo: 'PERSONA DE PRUEBA', vendedor_id: 'analista', etapa: 'nuevo', no_contactar: false } as Lead
function montar(sobre: Partial<Lead> = {}, puedeOperar = true) {
  const onAgendar = vi.fn(), onAgenda = vi.fn(), onHistorial = vi.fn()
  const props = { lead: { ...lead, ...sobre }, puedeOperar, onAgendar, onAgenda, onHistorial }
  return { ...render(<RecorridoFicha {...props} />), props }
}
beforeEach(() => {
  vi.clearAllMocks()
  yo = { id: 'analista', rol: 'vendedor', demo: false }
  consulta.estado = 'listo'; consulta.porLead = new Map([[id(1), recorridoFixture()]])
})

describe('guía por hechos', () => {
  it('no confunde la etapa de entrevista con pruebas de asistencia y entrevista', () => {
    montar({ etapa: 'propuesta_enviada' })
    expect(screen.getAllByText('Pendiente')).toHaveLength(2)
    expect(screen.getByText(/Cambiar de etapa no registra/)).toBeVisible()
    expect(screen.getByText(/bloqueo todavía no se aplica/)).toBeVisible()
    expect(screen.queryByText(/Completa los dos requisitos/)).not.toBeInTheDocument()
  })
  it('muestra exigencia solo cuando el servidor la declara para ese lead', () => {
    consulta.porLead.set(id(1), recorridoFixture(id(1), { exigible: true }))
    montar()
    expect(screen.getByText(/Completa los dos requisitos/)).toBeVisible()
    expect(screen.queryByText(/Seguimiento informativo/)).not.toBeInTheDocument()
  })
  it('no agrega llamadas o contacto como impedimentos al completar los dos hechos', () => {
    const r = recorridoFixture(id(1), { habilita_conversion: true, estado: 'completo', pendiente: 'listo' })
    r.pasos.asistencia = true; r.pasos.entrevista = true
    consulta.porLead.set(id(1), r)
    montar()
    expect(screen.getAllByText('Registrada')).toHaveLength(2)
    expect(screen.queryByRole('button', { name: 'Llegó sin cita' })).not.toBeInTheDocument()
    expect(screen.queryByText(/contacto pendiente/i)).not.toBeInTheDocument()
  })
  it('permite agendar y revisar historial por teclado con controles reales', async () => {
    consulta.porLead.set(id(1), recorridoFixture(id(1), { estado: 'ambiguo', pendiente: 'revisar_historial' }))
    const { props } = montar()
    const usuario = userEvent.setup()
    await usuario.tab(); await usuario.tab(); await usuario.keyboard('{Enter}')
    expect(props.onAgendar).toHaveBeenCalledTimes(1)
    await usuario.tab(); await usuario.keyboard(' ')
    expect(props.onHistorial).toHaveBeenCalledTimes(1)
  })
  it('una cita futura ofrece verla y no un cierre anticipado o una visita duplicada', async () => {
    consulta.porLead.set(id(1), recorridoFixture(id(1), { tarea_pendiente_id: id(2), pendiente: 'esperar_cita', cita_pendiente_en: '2026-10-19T15:00:00Z' }))
    const { props } = montar()
    await userEvent.click(screen.getByRole('button', { name: 'Ver cita' }))
    expect(props.onAgenda).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('button', { name: /Registrar resultado/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Llegó sin cita' })).not.toBeInTheDocument()
  })
  it('recupera la cita autorizada y abre el cierre existente', async () => {
    consulta.porLead.set(id(1), recorridoFixture(id(1), { tarea_pendiente_id: id(2), pendiente: 'cerrar_entrevista' }))
    obtenerTareaParaRevision.mockResolvedValueOnce({ id: id(2), lead_id: id(1), tipo: 'reunion', estado: 'pendiente' })
    montar()
    await userEvent.click(screen.getByRole('button', { name: 'Registrar resultado de la cita' }))
    expect(obtenerTareaParaRevision).toHaveBeenCalledWith(id(1), id(2))
    expect(await screen.findByRole('dialog', { name: 'Cierre habitual' })).toHaveTextContent(id(2))
  })
  it('no abre una cita cambiada de lead o ya cerrada', async () => {
    consulta.porLead.set(id(1), recorridoFixture(id(1), { tarea_pendiente_id: id(2), pendiente: 'cerrar_entrevista' }))
    obtenerTareaParaRevision.mockResolvedValueOnce({ id: id(2), lead_id: id(3), tipo: 'reunion', estado: 'pendiente' })
    montar()
    await userEvent.click(screen.getByRole('button', { name: 'Registrar resultado de la cita' }))
    await waitFor(() => expect(consulta.refetch).toHaveBeenCalled())
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('una respuesta tardía al cambiar de actor no abre un cierre', async () => {
    consulta.porLead.set(id(1), recorridoFixture(id(1), { tarea_pendiente_id: id(2), pendiente: 'cerrar_entrevista' }))
    let resolver!: (t: unknown) => void
    obtenerTareaParaRevision.mockImplementationOnce(() => new Promise((r) => { resolver = r }))
    const { rerender, props } = montar()
    await userEvent.click(screen.getByRole('button', { name: 'Registrar resultado de la cita' }))
    yo = { ...yo, id: 'otro-actor' }; rerender(<RecorridoFicha {...props} />)
    await act(async () => resolver({ id: id(2), lead_id: id(1), tipo: 'reunion', estado: 'pendiente' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('un fallo de lectura conserva el formulario de oficina y su nota', async () => {
    const { rerender, props } = montar()
    const usuario = userEvent.setup()
    await usuario.click(screen.getByRole('button', { name: 'Llegó sin cita' }))
    await usuario.type(screen.getByLabelText('Nota de oficina'), 'Visita en curso')
    consulta.estado = 'error'; consulta.porLead = new Map()
    rerender(<RecorridoFicha {...props} />)
    expect(screen.getByLabelText('Nota de oficina')).toHaveValue('Visita en curso')
    expect(screen.getByText(/Puedes continuar registrando tu gestión/)).toBeVisible()
    await usuario.click(screen.getByRole('button', { name: 'Volver a comprobar' }))
    expect(consulta.refetch).toHaveBeenCalledTimes(1)
  })
  it.each(['sin permiso', 'sin analista', 'no contactar', 'coordinador', 'directorio', 'demo'])('no ofrece escritura: %s', (caso) => {
    if (caso === 'coordinador' || caso === 'directorio') yo = { ...yo, rol: caso }
    if (caso === 'demo') yo = { ...yo, demo: true }
    montar({ ...(caso === 'sin analista' ? { vendedor_id: null } : {}), no_contactar: caso === 'no contactar' }, caso !== 'sin permiso')
    expect(screen.queryByRole('button', { name: 'Llegó sin cita' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Agendar cita' })).not.toBeInTheDocument()
  })
  it('sin backend instalado no agrega requisitos falsos', () => {
    consulta.estado = 'inactivo'; consulta.porLead = new Map()
    const { container } = montar()
    expect(container).toBeEmptyDOMElement()
  })
  it('Mi día lleva a la ficha y el resumen de listas no anida controles', async () => {
    const abrir = vi.fn()
    const { unmount } = render(<RecorridoEnMiDia leadId={id(1)} onAbrirFicha={abrir} />)
    await userEvent.click(screen.getByRole('button', { name: 'Ver pasos en la ficha' }))
    expect(abrir).toHaveBeenCalledTimes(1)
    unmount()
    render(<button type="button"><RecorridoBreve item={recorridoFixture()} estado="listo" /></button>)
    expect(screen.getAllByRole('button')).toHaveLength(1)
  })
})


it('conserva el mismo estado accesible desde la consulta hasta su resultado', () => {
  consulta.estado = 'cargando'; consulta.porLead = new Map()
  const { rerender, props } = montar()
  const estado = screen.getByRole('status')
  expect(estado).toHaveTextContent('Comprobando asistencia y entrevista')
  consulta.estado = 'listo'; consulta.porLead.set(id(1), recorridoFixture())
  rerender(<RecorridoFicha {...props} />)
  expect(screen.getByRole('status')).toBe(estado)
  expect(estado).toHaveTextContent('Agendar una cita')
  expect(screen.getByRole('list', { name: 'Requisitos del ciclo actual' })).toHaveAttribute('role', 'list')
})
