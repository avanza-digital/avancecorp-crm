import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within, waitFor } from '@testing-library/react'
import { useState } from 'react'
import { diaEquipoPrueba, filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import { idH4, jornadaH4 } from '@/lib/gestion-diaria-h4.fixture'
import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import type { AvisosGestionDiaria } from '@/lib/gestion-diaria-avisos-context'
import { CrmApiError } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({ consulta: {} as DiaEquipoHook, consultar: vi.fn(), recargar: vi.fn(), registro: vi.fn(), yo: { id: 's1', rol: 'supervisor', demo: false }, avisos: null as AvisosGestionDiaria | null, ahora: Date.parse('2026-09-21T15:00:00Z') }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => dobles.ahora }))
vi.mock('@/data/gestion-diaria-equipo-queries', () => ({ useDiaEquipo: (dia: string) => { dobles.consultar(dia); return dobles.consulta } }))
vi.mock('@/lib/gestion-diaria-avisos-context', () => ({ useGestionDiariaAvisos: () => dobles.avisos }))
vi.mock('@/components/gestion-diaria/ultimas-gestiones-supervisor', () => ({ UltimasGestionesSupervisor: () => <p>Últimas gestiones</p> }))
vi.mock('@/components/gestion-diaria/pendientes-supervisor', () => ({ PendientesSupervisor: () => <p>Pendientes independientes</p> }))
vi.mock('@/components/gestion-diaria/avisos-equipo', () => ({ AvisosEquipo: () => <p>Avisos del equipo</p> }))
vi.mock('@/components/gestion-diaria/registro-actividad', () => ({ RegistroActividad: (props: unknown) => {
  dobles.registro(props)
  const [pagina, setPagina] = useState(1)
  return <div><p>Registro cargado</p><button onClick={() => setPagina((p) => p + 1)}>Página {pagina}</button></div>
} }))
const { GestionDiariaSupervisor } = await import('./supervisor')
const seleccionar = () => fireEvent.click(screen.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' }))
const abrirRegistro = () => { seleccionar(); fireEvent.click(screen.getByRole('tab', { name: 'Registro' })) }
beforeEach(() => {
  vi.clearAllMocks()
  dobles.avisos = null
  dobles.yo = { id: 's1', rol: 'supervisor', demo: false }
  dobles.ahora = Date.parse('2026-09-21T15:00:00Z')
  vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1400)
  dobles.consulta = { dia: diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO',
    tareas_pendientes: 270, tareas_vencidas: 270, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] })]),
  cargando: false, enVuelo: false, error: null, recargar: dobles.recargar }
})

describe('Supervisor horizontal', () => {
  it('elige otra fecha, limpia el detalle anterior y consulta el registro del día elegido', () => {
    render(<GestionDiariaSupervisor />)
    const fecha = screen.getByLabelText('Fecha de gestión')
    expect(fecha).toHaveValue('2026-09-21')
    expect(fecha).toHaveAttribute('min', '2025-09-21')
    expect(fecha).toHaveAttribute('max', '2026-09-21')
    // aria-disabled y no disabled: el botón puede conservar el foco (revisión Codex, 27/09).
    expect(screen.getByRole('button', { name: 'Hoy' })).toHaveAttribute('aria-disabled', 'true')
    abrirRegistro()
    fireEvent.click(screen.getByRole('button', { name: 'Página 1' }))
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'ana' } })
    fecha.focus()
    fireEvent.change(fecha, { target: { value: '2026-09-10' } })
    expect(fecha).toHaveFocus()
    expect(dobles.consultar).toHaveBeenLastCalledWith('2026-09-10')
    expect(screen.getByRole('searchbox')).toHaveValue('ana')
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Mi equipo por fecha' })).toBeVisible()
    expect(screen.getByText(/El equipo y los pendientes reflejan su estado actual/)).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Cortes y avisos' })).not.toBeInTheDocument()
    abrirRegistro()
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-10', analistaIds: ['a1'] }))
    expect(screen.getByRole('button', { name: 'Página 1' })).toBeVisible()
    fireEvent.change(fecha, { target: { value: '2026-08-31' } })
    fireEvent.click(screen.getByRole('button', { name: 'Registro del equipo' }))
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-08-31', analistaIds: null }))
    fireEvent.click(screen.getByRole('button', { name: 'Hoy' }))
    expect(fecha).toHaveValue('2026-09-21')
    expect(dobles.consultar).toHaveBeenLastCalledWith('2026-09-21')
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Cortes y avisos' })).toBeVisible()
  })
  it('usa hoy en Lima e impide consultar fechas vacías, futuras o fuera de los 365 días', () => {
    dobles.ahora = Date.parse('2026-09-22T03:00:00Z')
    render(<GestionDiariaSupervisor />)
    const fecha = screen.getByLabelText('Fecha de gestión')
    for (const valor of ['', '2026-09-22', '2025-09-20']) {
      fireEvent.change(fecha, { target: { value: valor } })
      fireEvent.blur(fecha)
      expect(fecha).toHaveValue('2026-09-21')
      expect(dobles.consultar).toHaveBeenLastCalledWith('2026-09-21')
    }
    fireEvent.change(fecha, { target: { value: '2025-09-21' } })
    expect(dobles.consultar).toHaveBeenLastCalledWith('2025-09-21')
  })
  it('permite cambiar fecha con el equipo vacío y en error sin presentarlo como actividad cero', () => {
    dobles.consulta.dia = diaEquipoPrueba([])
    const vista = render(<GestionDiariaSupervisor />)
    fireEvent.change(screen.getByLabelText('Fecha de gestión'), { target: { value: '2026-09-10' } })
    expect(screen.getByText('No tienes analistas activos asignados')).toBeVisible()
    dobles.consulta.error = new Error('Sin red')
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByRole('alert')).toHaveTextContent('no significa que el equipo no tenga actividad')
    fireEvent.click(screen.getByRole('button', { name: 'Hoy' }))
    expect(dobles.consultar).toHaveBeenLastCalledWith('2026-09-21')
  })
  it('desde un corte histórico abre las llamadas de esa fecha y devuelve el foco al panel', async () => {
    dobles.consulta.dia = jornadaH4('2026-09-18', 's1').equipo
    render(<GestionDiariaSupervisor />)
    fireEvent.change(screen.getByLabelText('Fecha de gestión'), { target: { value: '2026-09-18' } })
    fireEvent.click(screen.getByRole('button', { name: 'Cortes del día' }))
    const dialogo = screen.getByRole('dialog', { name: 'Cortes del día seleccionado' })
    const primerCorte = within(dialogo).getByText('Primer corte · 11:30')
    fireEvent.click(primerCorte)
    fireEvent.click(within(primerCorte.closest('details')!).getByRole('button', { name: 'Ver llamadas de ANA H4' }))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Detalle de ANA H4' })).toHaveFocus())
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-18', analistaIds: [idH4(2)], pestanaInicial: 'llamadas' }))
  })
  it('seis columnas (Citas en lugar de Pendientes), ceros, cifras completas y panel con quien más atención necesita', () => {
    render(<GestionDiariaSupervisor />)
    const tabla = screen.getByRole('table')
    expect(within(tabla).getAllByRole('columnheader').map((c) => c.textContent)).toEqual(['Analista', 'Llamadas', 'Contacto', 'Citas', 'Vencidas', 'Atención'])
    // Diseño 27/09: Pendientes sale de la tabla (sigue en la franja y el panel); las 270 vencidas quedan.
    expect(within(tabla).getAllByText('270')).toHaveLength(1)
    expect(within(tabla).getByText('270 vencidas')).toBeInTheDocument()
    expect(within(tabla).getByText(/Tareas vencidas/)).toBeInTheDocument()
    expect(within(tabla).getAllByText('Sin llamadas útiles')).toHaveLength(2)
    expect(within(tabla).getByRole('rowheader', { name: /ANA PÉREZ/ })).toHaveAttribute('scope', 'row')
    // Selección automática: el panel abre con BRUNO (270 vencidas) SIN mover el foco
    // y sin montar el registro (se consulta al visitarlo).
    expect(screen.getByRole('region', { name: 'Detalle de BRUNO' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Seleccionar a BRUNO' })).toHaveAttribute('aria-current', 'true')
    expect(document.body).toHaveFocus()
    expect(dobles.registro).not.toHaveBeenCalled()
  })
  it('los filtros no cambian indicadores y la ordenación comunica su dirección', () => {
    render(<GestionDiariaSupervisor />)
    const resumen = screen.getByRole('group', { name: 'Resumen del equipo' }).textContent
    fireEvent.click(screen.getByRole('button', { name: /^Necesitan atención/ }))
    expect(screen.queryByText('ANA PÉREZ')).not.toBeInTheDocument()
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'ana' } })
    expect(screen.getByText('Ningún analista coincide con estos filtros.')).toBeVisible()
    expect(screen.getByRole('group', { name: 'Resumen del equipo' })).toHaveTextContent(resumen!)
    fireEvent.click(screen.getByRole('button', { name: 'Ordenar por vencidas' }))
    expect(screen.getByRole('button', { name: 'Ordenar por vencidas' }).closest('th')).toHaveAttribute('aria-sort', 'descending')
  })
  it('cada número del resumen abre su lista en la tabla; solo una píldora a la vez (Miguel, 27/09)', () => {
    render(<GestionDiariaSupervisor />)
    const resumen = screen.getByRole('group', { name: 'Resumen del equipo' })
    const pildora = (nombre: RegExp) => within(resumen).getByRole('button', { name: nombre })
    expect(pildora(/^Todos 2$/)).toHaveAttribute('aria-pressed', 'true')
    fireEvent.click(pildora(/^Necesitan atención 1$/))
    expect(pildora(/^Necesitan atención/)).toHaveAttribute('aria-pressed', 'true')
    expect(pildora(/^Todos/)).toHaveAttribute('aria-pressed', 'false')
    expect(screen.getAllByRole('button', { name: /^Seleccionar a / }).map((b) => b.textContent)).toEqual(['BRUNO'])
    fireEvent.click(pildora(/^Sin registro 2$/))
    expect(pildora(/^Necesitan atención/)).toHaveAttribute('aria-pressed', 'false')
    expect(screen.getAllByRole('button', { name: /^Seleccionar a / })).toHaveLength(2)
    fireEvent.click(pildora(/^Con registro 0$/))
    expect(screen.getByText('Ningún analista coincide con estos filtros.')).toBeVisible()
    fireEvent.click(pildora(/^Con pendientes 1$/))
    expect(screen.getAllByRole('button', { name: /^Seleccionar a / }).map((b) => b.textContent)).toEqual(['BRUNO'])
  })
  it('seleccionar conserva foco, volver a pulsar no cierra y sólo la fila activa ofrece ir al detalle', () => {
    render(<GestionDiariaSupervisor />)
    const boton = screen.getByRole('button', { name: 'Seleccionar a ANA PÉREZ' })
    boton.focus(); seleccionar()
    expect(boton).toHaveFocus()
    expect(boton).toHaveAttribute('aria-current', 'true')
    expect(screen.getAllByRole('button', { name: /Ir al detalle/ })).toHaveLength(1)
    seleccionar()
    expect(screen.getByRole('region', { name: 'Detalle de ANA PÉREZ' })).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /Ir al detalle/ }))
    expect(screen.getByRole('heading', { name: 'Detalle de ANA PÉREZ' })).toHaveFocus()
  })
  it('Registro monta al visitarlo, conserva páginas entre pestañas, filtros y ampliar/restaurar', () => {
    render(<GestionDiariaSupervisor />)
    abrirRegistro()
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-21', analistaIds: ['a1'], mostrarAnalista: false, permitirEquipo: false, permitirExportar: false, pestanaInicial: 'todo' }))
    fireEvent.click(screen.getByRole('button', { name: 'Página 1' }))
    const pagina = screen.getByRole('button', { name: 'Página 2' })
    fireEvent.click(screen.getByRole('tab', { name: 'Resumen' }))
    expect(pagina).not.toBeVisible()
    fireEvent.click(screen.getByRole('tab', { name: 'Registro' }))
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'bruno' } })
    expect(screen.getByText('La selección está fuera de los filtros.')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Ampliar panel' }))
    expect(screen.getByRole('dialog', { name: 'Detalle de ANA PÉREZ' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    screen.getByRole('button', { name: 'Restaurar panel' }).focus()
    fireEvent.click(screen.getByRole('button', { name: 'Restaurar panel' }))
    expect(screen.getByRole('button', { name: 'Ampliar panel' })).toHaveFocus()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle' }))
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it('la apertura deliberada de llamadas reinicia páginas y selecciona sólo esa persona', () => {
    render(<GestionDiariaSupervisor />)
    abrirRegistro()
    fireEvent.click(screen.getByRole('button', { name: 'Página 1' }))
    fireEvent.click(screen.getByRole('tab', { name: 'Resumen' }))
    fireEvent.click(screen.getByRole('button', { name: 'Ver llamadas del día de ANA PÉREZ' }))
    expect(screen.getByRole('button', { name: 'Página 1' })).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Actividad de hoy' })).toHaveFocus()
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: ['a1'], pestanaInicial: 'llamadas' }))
  })
  it('un fallo del resumen no desmonta el registro ni roba foco al recuperarse', () => {
    const vista = render(<GestionDiariaSupervisor />)
    abrirRegistro()
    const pagina = screen.getByRole('button', { name: 'Página 1' })
    fireEvent.click(pagina); pagina.focus()
    dobles.consulta.error = new Error('Sin red')
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByRole('button', { name: 'Página 2' })).toBe(pagina)
    expect(pagina).toHaveFocus()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(pagina).toHaveFocus()
  })
  it.each(['revocacion', 'fuera'])('una pérdida confirmada del ámbito %s cierra las listas', (caso) => {
    const vista = render(<GestionDiariaSupervisor />)
    abrirRegistro(); screen.getByRole('button', { name: 'Página 1' }).focus()
    if (caso === 'revocacion') dobles.consulta.error = new CrmApiError('Revocado', '42501')
    else dobles.consulta.dia = diaEquipoPrueba([])
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Se cerró el detalle')
    expect(screen.getByRole('heading', { level: 2 })).toHaveFocus()
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it.each(['actor', 'demo', 'dia', 'rol'])('cambio de %s borra el contexto antes de pintar', (cambio) => {
    const vista = render(<GestionDiariaSupervisor />)
    abrirRegistro()
    if (cambio === 'actor') dobles.yo.id = 's2'
    if (cambio === 'demo') dobles.yo.demo = true
    if (cambio === 'dia') dobles.ahora += 86400000
    if (cambio === 'rol') dobles.yo.rol = 'gerencia'
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
  it('modo equipo abre Todo con selectores autorizados y sin pestañas de persona', () => {
    render(<GestionDiariaSupervisor />)
    fireEvent.click(screen.getByRole('button', { name: 'Registro del equipo' }))
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: null, mostrarAnalista: true, permitirEquipo: false, permitirExportar: false, pestanaInicial: 'todo' }))
    expect(screen.queryByRole('tab', { name: 'Resumen' })).not.toBeInTheDocument()
  })
  it('distingue error de red, permiso, carga y equipo vacío', () => {
    dobles.consulta.error = new Error('red')
    const vista = render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('alert')).toHaveTextContent('no significa que el equipo no tenga actividad')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(dobles.recargar).toHaveBeenCalledOnce()
    dobles.consulta.error = new CrmApiError('Revocado', '42501')
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
    dobles.consulta = { ...dobles.consulta, error: null, dia: null, cargando: true }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByText('Consultando el equipo completo…')).toBeVisible()
    dobles.consulta = { ...dobles.consulta, dia: diaEquipoPrueba([]), cargando: false }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByText('No tienes analistas activos asignados')).toBeVisible()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })
})


describe('Pedido de registro desde avisos', () => {
  const preparar = () => {
    dobles.avisos = { datos: null, cargando: false, error: null, ocupada: false, recargar: vi.fn(), actuar: vi.fn(),
      registroPedido: null, abrirRegistro: vi.fn(), consumirRegistro: vi.fn(() => { dobles.avisos!.registroPedido = null }) }
  }
  it('vuelve a hoy antes de abrir un aviso mientras se consulta otra fecha', () => {
    preparar()
    const vista = render(<GestionDiariaSupervisor />)
    fireEvent.change(screen.getByLabelText('Fecha de gestión'), { target: { value: '2026-09-10' } })
    dobles.avisos = { ...dobles.avisos!, registroPedido: { actor: 's1', dia: '2026-09-21', analista: 'a1', secuencia: 1 } }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByLabelText('Fecha de gestión')).toHaveValue('2026-09-21')
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-21', analistaIds: ['a1'], pestanaInicial: 'llamadas' }))
    expect(dobles.avisos!.consumirRegistro).toHaveBeenCalledOnce()
  })
  it('espera la consulta de hoy antes de abrir su aviso y rechaza pedidos de otra jornada', () => {
    preparar()
    const vista = render(<GestionDiariaSupervisor />)
    fireEvent.change(screen.getByLabelText('Fecha de gestión'), { target: { value: '2026-09-10' } })
    dobles.avisos = { ...dobles.avisos!, registroPedido: { actor: 's1', dia: '2026-09-10', analista: 'a1', secuencia: 1 } }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
    expect(dobles.avisos!.consumirRegistro).toHaveBeenCalledOnce()
    vi.mocked(dobles.avisos!.consumirRegistro).mockClear()
    dobles.consulta = { ...dobles.consulta, dia: null, cargando: true }
    dobles.avisos = { ...dobles.avisos!, registroPedido: { actor: 's1', dia: '2026-09-21', analista: 'a1', secuencia: 2 } }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.getByLabelText('Fecha de gestión')).toHaveValue('2026-09-21')
    expect(dobles.avisos!.consumirRegistro).not.toHaveBeenCalled()
    dobles.consulta = { ...dobles.consulta, dia: diaEquipoPrueba(), cargando: false }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ dia: '2026-09-21', analistaIds: ['a1'] }))
    expect(dobles.avisos!.consumirRegistro).toHaveBeenCalledOnce()
  })
  it('transfiere foco desde el diálogo de avisos al registro solicitado', async () => {
    preparar()
    const vista = render(<GestionDiariaSupervisor />)
    const origen = screen.getByRole('button', { name: 'Cortes y avisos' })
    origen.focus(); fireEvent.click(origen)
    expect(screen.getByRole('dialog')).toBeVisible()
    dobles.avisos = { ...dobles.avisos!, registroPedido: { actor: 's1', dia: '2026-09-21', analista: 'a1', secuencia: 1 } }
    vista.rerender(<GestionDiariaSupervisor />)
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Detalle de ANA PÉREZ' })).toHaveFocus())
    expect(dobles.registro).toHaveBeenLastCalledWith(expect.objectContaining({ analistaIds: ['a1'], pestanaInicial: 'llamadas' }))
    expect(dobles.avisos!.consumirRegistro).toHaveBeenCalledOnce()
  })
  it('consume el pedido revocado y no lo abre si se recupera el equipo', () => {
    preparar()
    dobles.avisos = { ...dobles.avisos!, registroPedido: { actor: 's1', dia: '2026-09-21', analista: 'a1', secuencia: 1 } }
    dobles.consulta.error = new CrmApiError('Revocado', '42501')
    const vista = render(<GestionDiariaSupervisor />)
    expect(dobles.avisos!.consumirRegistro).toHaveBeenCalledOnce()
    dobles.consulta.error = null
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByText('Registro cargado')).not.toBeInTheDocument()
  })
})

describe('Selección automática del panel (plan v2 tras la revisión de Codex, 27/09/2026)', () => {
  let alMedir: (() => void) | null = null
  beforeEach(() => {
    alMedir = null
    // jsdom no mide: se simula el observador para poder estrechar la pantalla.
    vi.stubGlobal('ResizeObserver', class { constructor(cb: () => void) { alMedir = cb } observe() {} disconnect() {} })
  })
  afterEach(() => { vi.unstubAllGlobals() })

  it('si nadie necesita atención, no elige a nadie y el panel lo dice', () => {
    dobles.consulta = { ...dobles.consulta, dia: diaEquipoPrueba([filaEquipoPrueba(), filaEquipoPrueba({ analista_id: 'b', nombre_completo: 'BRUNO' })]) }
    render(<GestionDiariaSupervisor />)
    expect(screen.getByText('Nadie necesita atención ahora. Elige un analista para ver su día.')).toBeVisible()
    expect(screen.queryByRole('button', { name: /Ir al detalle/ })).not.toBeInTheDocument()
  })
  it('cerrar el panel apaga la apertura automática aunque llegue otra foto', () => {
    const vista = render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('region', { name: 'Detalle de BRUNO' })).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle' }))
    dobles.consulta = { ...dobles.consulta, dia: { ...dobles.consulta.dia!, generado_en: '2026-09-21T15:01:00Z' } }
    vista.rerender(<GestionDiariaSupervisor />)
    expect(screen.queryByRole('region', { name: 'Detalle de BRUNO' })).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Detalle del analista' })).toBeVisible()
  })
  it('una automática que se queda sin sitio se CIERRA sin abrir ninguna ventana', () => {
    render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('region', { name: 'Detalle de BRUNO' })).toBeVisible()
    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1000)
    act(() => { alMedir?.() })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Detalle de BRUNO' })).not.toBeInTheDocument()
  })
  it('con la pantalla estrecha desde el inicio no elige a nadie ni abre ventana', () => {
    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1000)
    render(<GestionDiariaSupervisor />)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Seleccionar a BRUNO' })).not.toHaveAttribute('aria-current')
  })
  it('una selección del USUARIO sí sigue la mecánica de siempre: con poco sitio se abre encima', () => {
    render(<GestionDiariaSupervisor />)
    seleccionar()
    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1000)
    act(() => { alMedir?.() })
    expect(screen.getByRole('dialog', { name: 'Detalle de ANA PÉREZ' })).toBeVisible()
  })
  it('en otra fecha no se abre sola', () => {
    render(<GestionDiariaSupervisor />)
    fireEvent.change(screen.getByLabelText('Fecha de gestión'), { target: { value: '2026-09-10' } })
    expect(screen.queryByRole('region', { name: 'Detalle de BRUNO' })).not.toBeInTheDocument()
  })
  it('el título del panel se oye «Detalle de …» con su espacio', () => {
    render(<GestionDiariaSupervisor />)
    expect(screen.getByRole('heading', { level: 3, name: 'Detalle de BRUNO' })).toBeInTheDocument()
  })
  it('la automática elige al MÁS GRAVE aunque la tabla esté ordenada de otra forma (Codex, 27/09)', () => {
    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1000)
    dobles.consulta = { ...dobles.consulta, dia: diaEquipoPrueba([
      filaEquipoPrueba({ analista_id: 'x', nombre_completo: 'AVISO LEVE', requiere_atencion: true, motivos_atencion: ['sin_llamar_2h'] }),
      filaEquipoPrueba({ analista_id: 'y', nombre_completo: 'MUCHAS VENCIDAS', tareas_pendientes: 9, tareas_vencidas: 9, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] }),
    ]) }
    render(<GestionDiariaSupervisor />)
    fireEvent.click(screen.getByRole('button', { name: 'Ordenar por analista' }))
    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(1400)
    act(() => { alMedir?.() })
    expect(screen.getByRole('region', { name: 'Detalle de MUCHAS VENCIDAS' })).toBeVisible()
  })
})
