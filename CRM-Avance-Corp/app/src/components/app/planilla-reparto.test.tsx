import { StrictMode } from 'react'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, expect, it, vi } from 'vitest'
import { PlanillaReparto } from './planilla-reparto'
import { cargarPlanilla, type DatosPlanilla } from '@/data/planilla-reparto'
import { repartirLead } from '@/data/crm-api'
import { hoyLimaIso, sumarDiasIso } from '@/lib/distribucion-lecturas'
vi.mock('@/data/planilla-reparto', () => ({ cargarPlanilla: vi.fn() }))
vi.mock('@/data/crm-api', () => ({ repartirLead: vi.fn() }))
const cargar = vi.mocked(cargarPlanilla)
const repartir = vi.mocked(repartirLead)
const cambio = vi.fn()
const ocupado = vi.fn()
const hoy = hoyLimaIso()
const ayer = sumarDiasIso(hoy, -1)
let datos: DatosPlanilla
beforeEach(() => {
  vi.clearAllMocks()
  datos = {
    repartoLibre: true,
    supervisores: ['Ana', 'Beto', 'Carla'].map((nombre) => ({ perfil_id: nombre, nombre, activo: true, bandeja_pendiente: 0 })),
    cola: [
      { id: 'viejo', nombre_completo: 'Lead anterior', origen: 'formulario_3', creado_en: `${ayer}T12:00:00Z`, moneda: 'PEN', monto_estimado: 0 },
      { id: 'nuevo', nombre_completo: 'Lead nuevo', origen: 'formulario_3', creado_en: `${hoy}T12:00:00Z`, moneda: 'PEN', monto_estimado: 0 },
    ], dias: [],
  }
  cargar.mockImplementation(async (fechas) => ({ ...datos, dias: fechas.map((fecha) => ({ fecha, asignaciones: [], origenes: fecha === ayer ? [{ origen: 'formulario_3', turno: 'formulario', derivados: 8, fuera_turno: 0, entregas: [{ supervisor_id: 'Ana', supervisor_nombre: 'Ana', supervisor_alias: null, derivados: 8, coincide_turno: true }] }] : [] })) }))
  repartir.mockImplementation(async (id) => { datos.cola = datos.cola.filter((lead) => lead.id !== id) })
})
const montar = () => render(<StrictMode><PlanillaReparto onCambio={cambio} onOcupado={ocupado} /></StrictMode>)
const campo = () => screen.getByRole('spinbutton', { name: 'Enviar Formulario 3 a Ana' })

it('muestra tres supervisores y respeta los dos calendarios y la proyección histórica', async () => {
  montar()
  await screen.findByRole('table', { name: 'Planilla de reparto' })
  const usuario = userEvent.setup()
  expect(screen.getByRole('spinbutton', { name: 'Enviar Formulario 3 a Carla' })).toBeEnabled()
  await usuario.selectOptions(screen.getByLabelText('Fecha de ingreso al CRM: período'), 'dia')
  fireEvent.change(screen.getByLabelText('Fecha de ingreso al CRM: inicio'), { target: { value: hoy } })
  expect(screen.getByLabelText('Resumen de la planilla')).toHaveTextContent('Pendientes disponibles1')
  await usuario.selectOptions(screen.getByLabelText('Fecha de reparto: período'), 'dia')
  fireEvent.change(screen.getByLabelText('Fecha de reparto: inicio'), { target: { value: ayer } })
  await waitFor(() => expect(screen.getByLabelText('Resumen de la planilla')).toHaveTextContent('Entregas en el período8'))
  await usuario.type(campo(), '1')
  expect(screen.getByRole('columnheader', { name: 'Histórico consultado' })).toBeInTheDocument()
  const fila = screen.getByRole('row', { name: /^Ana / })
  expect(within(fila).getAllByRole('cell').at(-1)).toHaveTextContent('8')
  await usuario.click(screen.getByRole('button', { name: 'Revisar reparto' }))
  expect(await screen.findByRole('dialog')).toHaveTextContent('Lead nuevo')
  expect(screen.getByRole('dialog')).not.toHaveTextContent('Lead anterior')
  expect(repartir).not.toHaveBeenCalled()
})

it('relee la cola antes de revisar y rechaza un exceso por cambios externos', async () => {
  montar(); await screen.findByRole('table', { name: 'Planilla de reparto' })
  fireEvent.change(campo(), { target: { value: '2' } })
  datos.cola = []
  await userEvent.click(screen.getByRole('button', { name: 'Revisar reparto' }))
  expect(await screen.findByRole('alert')).toHaveTextContent('superan los pendientes')
  expect(campo()).toHaveValue(2)
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  expect(repartir).not.toHaveBeenCalled()
})

it('confirma solo éxitos, detiene el lote incierto y no repite con doble clic', async () => {
  montar(); await screen.findByRole('table', { name: 'Planilla de reparto' })
  fireEvent.change(campo(), { target: { value: '2' } })
  await userEvent.click(screen.getByRole('button', { name: 'Revisar reparto' }))
  await screen.findByRole('dialog')
  let resolver!: () => void
  repartir.mockImplementationOnce(() => new Promise<void>((r) => { resolver = r }))
  repartir.mockRejectedValueOnce(new Error('Respuesta incierta'))
  fireEvent.click(screen.getByRole('button', { name: 'Confirmar reparto' }))
  fireEvent.click(screen.getByRole('button', { name: 'Repartiendo…' }))
  expect(repartir).toHaveBeenCalledTimes(1)
  expect(screen.getByRole('button', { name: 'Repartiendo…' })).toBeDisabled()
  await act(async () => { datos.cola = datos.cola.slice(1); resolver() })
  await waitFor(() => expect(screen.getByText(/1 entregas confirmadas · 0 sin intentar · 1 sin confirmar/)).toBeInTheDocument())
  expect(repartir.mock.calls).toEqual([['viejo', 'Ana'], ['nuevo', 'Ana']])
  expect(cambio).toHaveBeenCalledTimes(1)
  expect(screen.getByText(/Puede haberse registrado/)).toBeInTheDocument()
  await waitFor(() => expect(campo()).toHaveValue(null))
})

it('bloquea antes de confirmar si el servidor revoca reparto libre', async () => {
  montar(); await screen.findByRole('table', { name: 'Planilla de reparto' })
  fireEvent.change(campo(), { target: { value: '1' } }); datos.repartoLibre = false
  await userEvent.click(screen.getByRole('button', { name: 'Revisar reparto' }))
  expect(await screen.findByRole('alert')).toHaveTextContent('no está habilitado')
  expect(repartir).not.toHaveBeenCalled()
})

it('cambiar filtros limpia cantidades para que no se envíen destinos ocultos', async () => {
  montar(); await screen.findByRole('table', { name: 'Planilla de reparto' })
  fireEvent.change(campo(), { target: { value: '1' } })
  await userEvent.click(screen.getByText('Todos los supervisores', { selector: 'summary' }))
  await userEvent.click(screen.getByRole('checkbox', { name: 'Beto' }))
  expect(screen.queryByRole('spinbutton', { name: 'Enviar Formulario 3 a Ana' })).not.toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Revisar reparto' })).toBeDisabled()
  expect(screen.getByRole('status')).toHaveTextContent('Se limpiaron las cantidades')
})

it('una respuesta vieja no sobrescribe el período nuevo', async () => {
  montar(); await screen.findByRole('table', { name: 'Planilla de reparto' })
  let resolver!: (datos: DatosPlanilla) => void
  cargar.mockImplementationOnce(() => new Promise((r) => { resolver = r }))
  await userEvent.click(screen.getByRole('button', { name: 'Actualizar' }))
  await userEvent.selectOptions(screen.getByLabelText('Fecha de reparto: período'), 'dia')
  await screen.findByRole('table', { name: 'Planilla de reparto' })
  await act(async () => resolver({ ...datos, cola: [], repartoLibre: false }))
  expect(screen.getByLabelText('Resumen de la planilla')).toHaveTextContent('Pendientes disponibles2')
  expect(campo()).toBeEnabled()
})
