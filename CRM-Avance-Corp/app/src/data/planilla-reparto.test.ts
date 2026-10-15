import { beforeEach, expect, it, vi } from 'vitest'
import { cargarPlanilla } from './planilla-reparto'
import { fechasPeriodo, periodoInicial } from '@/lib/planilla-reparto'
import { sumarDiasIso } from '@/lib/distribucion-lecturas'
import { agendaRepartoDiaria, leadsPorRepartir } from './crm-api'
vi.mock('./crm-api', () => ({ agendaRepartoDiaria: vi.fn(), leadsPorRepartir: vi.fn(async () => []), supervisoresParaReparto: vi.fn(async () => []) }))
const agenda = vi.mocked(agendaRepartoDiaria)
beforeEach(() => { agenda.mockReset(); agenda.mockImplementation(async ({ desde = '', dias = 1 } = {}) => ({ version: 1, fecha_desde: desde, reparto_libre: true, destinos: [], dias: Array.from({ length: dias }, (_, i) => ({ fecha: sumarDiasIso(desde, i), asignaciones: [], origenes: [] })) })) })
it('lee más de 14 días sin huecos ni solapes, y conserva cero explícito', async () => {
  const fechas = fechasPeriodo({ ...periodoInicial('rango', '2026-10-01'), hasta: '2026-10-15' })!
  const datos = await cargarPlanilla(fechas, new AbortController().signal)
  expect(datos.dias).toHaveLength(15)
  expect(agenda.mock.calls.map(([f]) => f)).toEqual([{ desde: '2026-10-01', dias: 14 }, { desde: '2026-10-15', dias: 1 }])
  expect(datos.repartoLibre).toBe(true)
})
it.each(['faltante', 'duplicado', 'sin_origenes', 'otra_fecha'])('rechaza un período %s; no inventa cero', async (caso) => {
  agenda.mockResolvedValueOnce({ version: 1, fecha_desde: '2026-10-14', reparto_libre: true, destinos: [], dias: caso === 'faltante' ? [] : caso === 'duplicado' ? [{ fecha: '2026-10-14', asignaciones: [], origenes: [] }, { fecha: '2026-10-14', asignaciones: [], origenes: [] }] : [{ fecha: caso === 'otra_fecha' ? '2026-10-13' : '2026-10-14', asignaciones: [], ...(caso !== 'sin_origenes' ? { origenes: [] } : {}) }] })
  await expect(cargarPlanilla(['2026-10-14'], new AbortController().signal)).rejects.toThrow('incompleta')
})
it('no agrega el hueco entre días sueltos ni ignora una revocación de permiso', async () => {
  agenda.mockResolvedValueOnce({ version: 1, fecha_desde: '2026-10-12', reparto_libre: false, destinos: [], dias: [{ fecha: '2026-10-12', asignaciones: [], origenes: [] }] })
  expect(await cargarPlanilla(['2026-10-12', '2026-10-15'], new AbortController().signal)).toMatchObject({ repartoLibre: false, dias: [{ fecha: '2026-10-12' }, { fecha: '2026-10-15' }] })
  expect(agenda.mock.calls.map(([f]) => f?.dias)).toEqual([1, 1])
})
it('no acepta una lectura cancelada aunque el transporte la resuelva', async () => {
  const controlador = new AbortController(); controlador.abort()
  await expect(cargarPlanilla(['2026-10-14'], controlador.signal)).rejects.toMatchObject({ name: 'AbortError' })
})
it('un fallo de cola cancela la ventana pendiente y no continúa con las siguientes', async () => {
  let terminar!: () => void
  let senal: AbortSignal | undefined
  agenda.mockImplementationOnce((_filtros, signal) => { senal = signal; return new Promise((resolver) => { terminar = () => resolver({ version: 1, fecha_desde: '2026-10-12', destinos: [], dias: [{ fecha: '2026-10-12', asignaciones: [], origenes: [] }] }) }) })
  vi.mocked(leadsPorRepartir).mockRejectedValueOnce(new Error('Cola incompleta'))
  await expect(cargarPlanilla(['2026-10-12', '2026-10-15'], new AbortController().signal)).rejects.toThrow('Cola incompleta')
  expect(senal?.aborted).toBe(true)
  terminar()
  await Promise.resolve()
  expect(agenda).toHaveBeenCalledTimes(1)
})
