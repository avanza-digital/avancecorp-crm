import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { CrmApiError } from '@/data/crm-api'
import type { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
import { objetivosCero, cumplimientoDesdeRpc, CumplimientoMetasV2Schema, type CumplimientoMetasJerarquico } from '@/lib/objetivos'
import * as v from 'valibot'
import valorado from '@/lib/__fixtures__/capital-valorado/activo.json'
import { totalEnSoles } from '@/lib/capital-unificado'
import { diaEquipoPrueba, filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import { resumenCarteraDesdeAmbito } from '@/lib/resumen-cartera'
import type { CitaEjemplo } from '@/components/citas/modelo'
import { HoySupervisorJornada } from './supervisor-jornada'
import type { useResultadosHoy } from './use-resultados-hoy'

const AHORA = Date.parse('2026-10-18T16:00:00-05:00')
let actor = { id: 's1', rol: 'supervisor', demo: false }
let ahora = AHORA
const refrescar = vi.fn(async () => {})
const base = filaEquipoPrueba()
const crearDia = () => ({ dia: { ...diaEquipoPrueba([{ ...base, nombre_completo: 'Ana Pérez',
  marcador: { ...base.marcador, llamadas: 10, utiles: 8, contestadas: 4, tasa_contacto_pct: 50, nivel: 'bien' as const },
  gestiones_hoy: 10, tareas_pendientes: 5, tareas_vencidas: 3, primer_intento_vencido: 2,
  requiere_atencion: true, motivos_atencion: ['tarea_vencida' as const],
}]), dia: '2026-10-18' }, error: null as Error | null, cargando: false, recargar: refrescar })
let diario = crearDia()
const crearMensual = () => ({
  ahora: AHORA, sesionReal: true, equipo: [],
  cumplimientoMensual: null as CumplimientoMetasJerarquico | null, cumplimientoMensualError: false,
  objetivosMensuales: objetivosCero('2026-10-01'), objetivosMensualesError: false,
  fotoMensualStoreCargando: false,
  capitalConfirmado: totalEnSoles(null, null, null), metaCapital: totalEnSoles(0, 0, null), metaConversion: null,
  conversionMensual: null, conversionConfirmada: null, lecturaConversion: { mostrar: false, aviso: null },
  hayErrorMensual: false, filasMeta: [{ nota: null }],
  reintentarMensual: refrescar, recargarMensual: refrescar, tc: null,
  resumen: resumenCarteraDesdeAmbito([], [], AHORA),
  resumenOp: { recargar: refrescar, cargando: false, error: null as Error | null }, totalPorRepartir: 0,
})
let mensual = crearMensual()
const crearCierres = (): ReturnType<typeof useResultadosHoy> => ({
  resultados: { operaciones: 3, pen: 45000, usd: 10000,
    analistas: [{ id: 'a1', nombre: 'Ana Pérez', operaciones: 3, pen: 45000, usd: 10000 }] },
  error: false, cargando: false, aviso: null, recargar: refrescar,
})
let cierres = crearCierres()
const crearCitas = () => ({ datos: {}, citas: [{ fecha: '2026-10-18', estado: 'realizada' }, { fecha: '2026-10-18', estado: 'no_show' }] as CitaEjemplo[],
  consulta: { error: null as Error | null, isPending: false, refetch: refrescar } })
let citas = crearCitas()
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: actor }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => ahora }))
vi.mock('./datos-supervisor', () => ({ useDatosSupervisor: () => mensual }))
vi.mock('./use-resultados-hoy', () => ({ useResultadosHoy: () => cierres }))
vi.mock('./use-datos-citas-gerencia', () => ({ useDatosCitasGerencia: () => citas }))
vi.mock('@/data/gestion-diaria-equipo-queries', () => ({ useDiaEquipo: () => diario }))
vi.mock('./tasas-autorizadas-analista', () => ({ TasasAutorizadasAnalistaPanel: () => null }))
const consultarTareas = vi.fn()
const refrescarTareas = vi.fn(async () => {})
const crearPendientes = (): ReturnType<typeof usePendientesSupervisor> => ({ items: [], pagina: null,
  congelada: false, consultadoDesde: null, cargando: false, enVuelo: false, error: null,
  sinPermiso: false, hayMas: false, cargarMas: vi.fn(), recargar: refrescarTareas })
let pendientes = crearPendientes()
vi.mock('@/data/gestion-diaria-pendientes-queries', () => ({ usePendientesSupervisor: (...args: unknown[]) => { consultarTareas(...args); return pendientes } }))
vi.mock('@/components/gestion-diaria/panel-analista-supervisor', async () => {
  const { DialogTitle } = await import('@/components/ui/dialog')
  return { PanelAnalistaSupervisor: ({ fila }: { fila?: { nombre_completo: string } }) => <DialogTitle>Detalle de {fila?.nombre_completo ?? 'equipo'}</DialogTitle> }
})

beforeEach(() => {
  actor = { id: 's1', rol: 'supervisor', demo: false }; diario = crearDia(); mensual = crearMensual()
  cierres = crearCierres()
  citas = crearCitas(); ahora = AHORA; refrescar.mockClear()
  pendientes = crearPendientes(); consultarTareas.mockClear(); refrescarTareas.mockClear()
})

describe('portada comercial del supervisor', () => {
  it('muestra el aviso solo con saldo confirmado y lo retira al terminar el reparto', () => {
    const { rerender } = render(<HoySupervisorJornada />)
    expect(screen.queryByRole('region', { name: 'Leads por repartir' })).not.toBeInTheDocument()
    mensual.resumen.totales.parkeados = 4; rerender(<HoySupervisorJornada />)
    const aviso = screen.getByRole('region', { name: 'Leads por repartir' })
    expect(aviso).toHaveTextContent('4 leads por repartir')
    expect(aviso).toHaveTextContent('Por asignar')
    expect(screen.getByRole('status', { name: 'Aviso de reparto' })).toHaveTextContent('4 leads pendientes de repartir')
    expect(within(aviso).getByRole('link', { name: 'Repartir leads' })).toHaveAttribute('href', '#/derivaciones')
    mensual.resumen.totales.parkeados = 1; rerender(<HoySupervisorJornada />)
    expect(aviso).toHaveTextContent('1 lead por repartir')
    mensual.resumen.totales.parkeados = 0; rerender(<HoySupervisorJornada />)
    expect(screen.queryByRole('region', { name: 'Leads por repartir' })).not.toBeInTheDocument()
    expect(document.querySelector('.sj-aviso-reparto')).toBeNull()
    expect(screen.getByRole('status', { name: 'Aviso de reparto' })).toBeEmptyDOMElement()
  })
  it('sin metas publicadas conserva actividad y citas, y no presenta ventas como cero', () => {
    render(<HoySupervisorJornada />)
    const resultado = screen.getByRole('region', { name: /Resultado del equipo en/ })
    expect(resultado).toHaveTextContent('Sin meta fijada')
    expect(resultado).not.toHaveTextContent('S/ 0')
    expect(screen.getByRole('region', { name: 'Llamadas de hoy' })).toHaveTextContent('4 contestadas / 8 útiles')
    const llamadas = screen.getByRole('region', { name: 'Llamadas de hoy' })
    expect(within(llamadas).getAllByRole('link')).toHaveLength(3)
    for (const enlace of within(llamadas).getAllByRole('link')) expect(enlace).toHaveAttribute('href', '#/gestion-diaria')
    expect(screen.queryByText(/hora de lima/i)).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Citas de hoy' })).toHaveTextContent('realizadas de 2 previstas')
    expect(screen.queryByText('Cómo leer las cifras')).not.toBeInTheDocument()
    expect(screen.queryByText('Si faltan datos')).not.toBeInTheDocument()
  })
  it('al fallar un refresco retira las cifras antiguas y cierra el detalle; permite reintentar', () => {
    const { rerender } = render(<HoySupervisorJornada />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver día de Ana Pérez' }))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    diario.error = new Error('Sin permiso'); citas.consulta.error = new Error('Sin permiso')
    rerender(<HoySupervisorJornada />)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Ver día de Ana Pérez' })).not.toBeInTheDocument()
    const contacto = screen.getByRole('region', { name: 'Llamadas de hoy' })
    expect(contacto).not.toHaveTextContent('4 contestadas')
    expect(screen.getByRole('region', { name: 'Citas de hoy' })).not.toHaveTextContent('realizadas de 2 previstas')
    fireEvent.click(within(contacto).getByRole('button', { name: 'Reintentar' }))
    expect(refrescar).toHaveBeenCalledOnce()
  })
  it('oculta el capital viejo si falla el cumplimiento aunque siga en la caché', () => {
    mensual.capitalConfirmado = totalEnSoles(150000, 0, 3.5)
    mensual.cumplimientoMensualError = true; mensual.hayErrorMensual = true
    render(<HoySupervisorJornada />)
    expect(screen.queryByText('S/ 150,000')).not.toBeInTheDocument()
    expect(screen.getByText('Resultado mensual no disponible.')).toBeInTheDocument()
  })
  it('la búsqueda tolera acentos y el cambio de actor desmonta filtros y selección', () => {
    const { rerender } = render(<HoySupervisorJornada />)
    fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar analista' }), { target: { value: 'perez' } })
    expect(screen.getByRole('button', { name: 'Ver día de Ana Pérez' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver día de Ana Pérez' }))
    actor = { ...actor, id: 's2' }; diario.dia.equipo = []; diario.dia.resumen.analistas = 0
    rerender(<HoySupervisorJornada />)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.getByRole('searchbox')).toHaveValue('')
    expect(screen.queryByText('Ana Pérez')).not.toBeInTheDocument()
  })
  it('enlaza las citas con su fecha; no concede esta vista a otros roles', () => {
    const { rerender } = render(<HoySupervisorJornada />)
    expect(screen.getByRole('link', { name: /Ver citas del equipo/ })).toHaveAttribute('href', '#/reuniones/dia/2026-10-18')
    expect(screen.getByRole('link', { name: /pendientes? de resultado/ })).toHaveAttribute('href', '#/reuniones/dia/2026-10-18')
    // «Citas de hoy» cuenta citas PREVISTAS hoy; la Proyección cuenta citas CREADAS: el título no enlaza allí (misma palabra, otra cifra).
    expect(screen.queryByRole('link', { name: 'Citas de hoy' })).not.toBeInTheDocument()
    actor = { ...actor, rol: 'vendedor' }; rerender(<HoySupervisorJornada />)
    expect(screen.queryByRole('heading', { name: 'Dirección de la jornada' })).not.toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('supervisores autorizados')
  })
  it('Actualizar consulta todas las fuentes y vuelve a habilitarse al terminar', async () => {
    const fuentes = Array.from({ length: 5 }, () => vi.fn(async () => {}))
    diario.recargar = fuentes[0]!
    mensual.recargarMensual = fuentes[1]!
    mensual.resumenOp.recargar = fuentes[2]!
    citas.consulta.refetch = fuentes[3]!
    cierres.recargar = fuentes[4]!
    render(<HoySupervisorJornada />)
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Actualizar' })).toBeEnabled())
    for (const fuente of fuentes) expect(fuente).toHaveBeenCalledOnce()
  })
  it('al cambiar el día de Lima cierra el detalle y cambia el destino de Citas', () => {
    const { rerender } = render(<HoySupervisorJornada />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver pendientes' }))
    ahora = Date.parse('2026-10-19T00:00:01-05:00')
    rerender(<HoySupervisorJornada />)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Ver citas del equipo/ })).toHaveAttribute('href', '#/reuniones/dia/2026-10-19')
  })
  it('abre las tareas exactas por analista, conserva los filtros y devuelve el foco', async () => {
    render(<HoySupervisorJornada />)
    const buscar = screen.getByRole('searchbox', { name: 'Buscar analista' })
    fireEvent.change(buscar, { target: { value: 'perez' } })
    const boton = screen.getByRole('button', { name: 'Ver pendientes' })
    fireEvent.click(boton)
    const dialogo = screen.getByRole('dialog')
    expect(within(dialogo).getByRole('row', { name: 'Total del equipo 5 3' })).toBeInTheDocument()
    fireEvent.click(within(dialogo).getByRole('button', { name: 'Ver tareas de Ana Pérez' }))
    expect(within(dialogo).getByRole('button', { name: 'Todas 5' })).toHaveAttribute('aria-pressed', 'true')
    expect(consultarTareas).toHaveBeenLastCalledWith('2026-10-18', base.analista_id, false, true, 0)
    expect(within(dialogo).getByRole('heading', { name: 'Tareas de Ana Pérez' })).toHaveFocus()
    fireEvent.click(within(dialogo).getByRole('button', { name: 'Volver al equipo' }))
    expect(within(dialogo).getByRole('heading', { name: 'Pendientes del equipo' })).toHaveFocus()
    fireEvent.click(within(dialogo).getByRole('button', { name: 'Cerrar tareas' }))
    await waitFor(() => expect(boton).toHaveFocus())
    expect(buscar).toHaveValue('perez')
    fireEvent.click(screen.getByRole('button', { name: 'Ver 3 tareas atrasadas de Ana Pérez' }))
    expect(within(screen.getByRole('dialog')).getByRole('button', { name: 'Vencidas 3' })).toHaveAttribute('aria-pressed', 'true')
  })
  it('el lector real de tareas recibe Actualizar y revalida el equipo al perder permiso', async () => {
    const { rerender } = render(<HoySupervisorJornada />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver 3 tareas atrasadas de Ana Pérez' }))
    expect(consultarTareas).toHaveBeenLastCalledWith('2026-10-18', base.analista_id, true, true, 0)
    // El diálogo mantiene el contexto mientras se actualizan las fuentes de la portada.
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar', hidden: true }))
    await waitFor(() => expect(refrescarTareas).toHaveBeenCalledOnce())
    refrescar.mockClear()
    pendientes = { ...pendientes, error: new CrmApiError('Sin permiso', '42501'), sinPermiso: true }
    rerender(<HoySupervisorJornada />)
    expect(screen.getByRole('alert')).toHaveTextContent('Ya no tienes acceso a estas tareas.')
    expect(refrescar).toHaveBeenCalledOnce()
  })
  it('retira tareas antiguas ante error o pérdida del analista y ofrece reintento', async () => {
    const { rerender } = render(<HoySupervisorJornada />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver 3 tareas atrasadas de Ana Pérez' }))
    diario.error = new Error('No disponible'); rerender(<HoySupervisorJornada />)
    const dialogo = screen.getByRole('dialog')
    expect(within(dialogo).queryByRole('group', { name: 'Filtro de tareas' })).not.toBeInTheDocument()
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('Pendientes del equipo no disponible')
    fireEvent.click(within(dialogo).getByRole('button', { name: 'Reintentar' }))
    expect(refrescar).toHaveBeenCalledOnce()
    fireEvent.click(within(dialogo).getByRole('button', { name: 'Cerrar tareas' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Con quién trabajar ahora' })).toHaveFocus())
    diario = crearDia(); diario.dia.equipo = []; rerender(<HoySupervisorJornada />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver pendientes' }))
    expect(screen.getByRole('dialog')).toHaveTextContent('No hay tareas pendientes en el equipo.')
  })
  it('identifica ventas propias del supervisor, sin inventar meta, y anuncia la carga mensual', () => {
    const rpc = v.parse(CumplimientoMetasV2Schema, valorado)
    actor.id = rpc.vendedores[0]!.supervisor_id!
    rpc.capital_valoracion!.personas.push({ ...rpc.capital_valoracion!.personas[0]!, vendedor_id: actor.id,
      nombre: 'Supervisor de prueba', rol_crm: 'supervisor', en_ranking: false, supervisor_id: null })
    mensual.cumplimientoMensual = cumplimientoDesdeRpc(rpc, actor.id)
    const { rerender } = render(<HoySupervisorJornada />)
    fireEvent.click(screen.getByRole('tab', { name: 'Resultado del mes' }))
    const fila = screen.getByRole('row', { name: /Supervisor de prueba/ })
    expect(fila).toHaveTextContent('Supervisor · ventas propias')
    expect(fila).toHaveTextContent('Sin meta individual')
    expect(fila).not.toHaveTextContent('Sin meta fijada')
    mensual.fotoMensualStoreCargando = true; rerender(<HoySupervisorJornada />)
    expect(screen.getByText('Consultando capital y metas del mes…')).toHaveAttribute('role', 'status')
  })
  it('una meta en carga o con error no se anuncia como una meta inexistente', () => {
    mensual.fotoMensualStoreCargando = true
    const { rerender } = render(<HoySupervisorJornada />)
    expect(screen.getAllByText('Meta por confirmar')).toHaveLength(2)
    expect(screen.queryByText('Sin meta fijada')).not.toBeInTheDocument()
    mensual.fotoMensualStoreCargando = false; mensual.objetivosMensualesError = true
    rerender(<HoySupervisorJornada />)
    expect(screen.getAllByText('Meta no disponible')).toHaveLength(2)
    expect(screen.queryByText('Sin meta de conversión')).not.toBeInTheDocument()
  })
  it('un error en el reparto retira el aviso antiguo sin ocultar los resultados del día', () => {
    mensual.resumen.totales.parkeados = 222
    mensual.resumenOp.error = new Error('Sin acceso')
    render(<HoySupervisorJornada />)
    expect(screen.queryByText('222 leads por repartir')).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Ver derivaciones' })).toBeInTheDocument()
    expect(screen.getByText('Leads por repartir no disponible.')).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Facturación de hoy' })).toHaveTextContent('S/ 45,000')
  })
  it('abre Facturación desde la tarjeta y retira cifras si falla la fuente sin bloquear el acceso', () => {
    const { rerender } = render(<HoySupervisorJornada />)
    const tarjeta = screen.getByRole('region', { name: 'Facturación de hoy' })
    expect(within(tarjeta).getByRole('link', { name: /3.*operaciones cerradas/ })).toHaveAttribute('href', '#/facturacion')
    expect(within(tarjeta).getAllByRole('link')).toHaveLength(3)
    for (const enlace of within(tarjeta).getAllByRole('link')) expect(enlace).toHaveAttribute('href', '#/facturacion')
    expect(tarjeta).toHaveTextContent('S/ 45,000')
    expect(tarjeta).toHaveTextContent('US$ 10,000')
    expect(screen.queryByRole('region', { name: 'Resultados de hoy' })).not.toBeInTheDocument()
    expect(screen.queryByText('Acompañar el cierre')).not.toBeInTheDocument()
    expect(screen.queryByText('Potencial estimado de cartera')).not.toBeInTheDocument()
    cierres = { ...cierres, resultados: null, error: true }
    rerender(<HoySupervisorJornada />)
    expect(tarjeta).not.toHaveTextContent('S/ 45,000')
    expect(within(tarjeta).getByRole('alert')).toHaveTextContent('Facturación de hoy no disponible')
    expect(within(tarjeta).getByRole('link', { name: /Ver Facturación de hoy/ })).toHaveAttribute('href', '#/facturacion')
    fireEvent.click(within(tarjeta).getByRole('button', { name: 'Reintentar' }))
    expect(refrescar).toHaveBeenCalledOnce()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('un día confirmado sin cierres conserva cero; la carga usa ausencia de dato', () => {
    cierres = { ...cierres, resultados: { operaciones: 0, pen: 0, usd: 0, analistas: [] } }
    const { rerender } = render(<HoySupervisorJornada />)
    const tarjeta = screen.getByRole('region', { name: 'Facturación de hoy' })
    expect(within(tarjeta).getByRole('link', { name: /0.*operaciones cerradas/ })).toHaveAttribute('href', '#/facturacion')
    expect(tarjeta).toHaveTextContent('Sin cierres registrados hoy')
    cierres = { ...cierres, resultados: null, cargando: true }
    rerender(<HoySupervisorJornada />)
    expect(tarjeta).not.toHaveTextContent('S/ 0')
    expect(tarjeta).toHaveTextContent('Consultando facturación de hoy')
    expect(within(tarjeta).getByRole('link', { name: /Ver Facturación de hoy/ })).toHaveAttribute('href', '#/facturacion')
  })
})
