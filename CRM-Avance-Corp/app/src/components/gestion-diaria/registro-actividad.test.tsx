// El registro crudo como lo ve cada rol: filas con texto íntegro, pestañas que
// cambian el filtro, «Ver más» por cursor SIN borrar lo ya leído, reinicio del
// cursor al cambiar un filtro, estados vacío/error/carga, filtro por equipo y
// la exportación solo para quien la tiene permitida. El data layer se mockea:
// aquí se prueba la presentación y el contrato con el hook, no el servidor.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { RegistroItem, RegistroPagina } from '@/lib/gestion-diaria'
import { CrmApiError } from '@/data/crm-api'

const ESTADO = vi.hoisted(() => ({
  pagina: null as RegistroPagina | null, cargando: false, enVuelo: false, error: null as unknown,
  recargar: vi.fn(async () => {}), llamadas: [] as { filtros: unknown; cursor: unknown }[],
  abrirLead: vi.fn(), descargar: vi.fn(() => true),
  yo: { id: 'u-sup', rol: 'supervisor', demo: false, nombre_completo: 'SUP' },
}))
const EQUIPO = [
  { perfil_id: 'sup1', nombre_completo: 'SUPERVISOR UNO', rol_crm: 'supervisor', supervisor_id: null, activo: true },
  { perfil_id: 'sup2', nombre_completo: 'SUPERVISOR DOS', rol_crm: 'supervisor', supervisor_id: null, activo: true },
  { perfil_id: 'u1', nombre_completo: 'ANALISTA UNO', rol_crm: 'vendedor', supervisor_id: 'sup1', activo: true },
  { perfil_id: 'u2', nombre_completo: 'ANALISTA DOS', rol_crm: 'vendedor', supervisor_id: 'sup1', activo: true },
  { perfil_id: 'u3', nombre_completo: 'ANALISTA TRES', rol_crm: 'vendedor', supervisor_id: 'sup2', activo: true },
  { perfil_id: 'u4', nombre_completo: 'ANALISTA BAJA', rol_crm: 'vendedor', supervisor_id: 'sup1', activo: false },
]
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: ESTADO.yo }) }))
// El reloj de la app, FIJO: sin esto «de hoy» dependía del día real y la suite
// se ponía roja sola al pasar la medianoche de Lima.
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-09-19T18:02:00Z') }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead: async () => true, equipo: EQUIPO, ambito: { leads: [], vendedores: EQUIPO.filter((m) => m.rol_crm === 'vendedor'), esGlobal: true } }),
  usePanelesActions: () => ({ abrirLead: ESTADO.abrirLead }),
}))
vi.mock('@/data/gestion-diaria-queries', () => ({
  useRegistroActividadOperativo: (filtros: unknown, cursor: unknown) => {
    ESTADO.llamadas.push({ filtros, cursor })
    return { pagina: ESTADO.pagina, cargando: ESTADO.cargando, enVuelo: ESTADO.enVuelo, error: ESTADO.error, recargar: ESTADO.recargar }
  },
}))
vi.mock('@/lib/exportar-csv', async (original) => ({ ...(await original<typeof import('@/lib/exportar-csv')>()), descargarCsv: ESTADO.descargar }))
const { RegistroActividad } = await import('./registro-actividad')
const { analistasDelEquipo } = await import('@/lib/gestion-diaria')

const item = (n: number, extra: Partial<RegistroItem> = {}): RegistroItem => ({
  id: `a${n}`, lead_id: `l${n}`, lead_nombre: `LEAD ${n}`, lead_etapa: 'contactado', etapa_en_ese_momento: 'nuevo',
  tipo: 'llamada_realizada', detalle: `Detalle íntegro ${n}`, metadata: {}, creado_por: 'u1', autor_nombre: 'ANALISTA UNO',
  creado_en: `2026-09-19T15:${String(n % 60).padStart(2, '0')}:00.000Z`, ...extra,
})
const pagina = (items: RegistroItem[]): RegistroPagina => ({ version: 1, generado_en: '2026-09-19T18:02:00Z', desde: '2026-09-19', hasta: '2026-09-19', zona: 'America/Lima', limite: 26, items })
const ultima = () => ESTADO.llamadas[ESTADO.llamadas.length - 1]!
const montar = (props: Partial<Parameters<typeof RegistroActividad>[0]> = {}) =>
  render(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} {...props} />)

beforeEach(() => {
  ESTADO.pagina = pagina([item(1), item(2, { tipo: 'llamada_no_contestada', detalle: null, metadata: { resultado: 'numero_errado' } })])
  ESTADO.cargando = false; ESTADO.enVuelo = false; ESTADO.error = null; ESTADO.llamadas = []
  ESTADO.yo = { id: 'u-sup', rol: 'supervisor', demo: false, nombre_completo: 'SUP' }
  vi.clearAllMocks()
})

describe('RegistroActividad — filas', () => {
  it('pinta hora Lima, chip con texto, lead, etapas y el detalle íntegro dentro del panel de la pestaña', () => {
    // «se actualiza cada minuto» solo si el día listado es HOY en Lima
    // (`esHoy` mira el reloj real): el reloj se fija al día del fixture, si no
    // el test caducaba a la medianoche de Lima del 19/09 (visto el 20/09 00:04).
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date('2026-09-19T18:02:00Z'))
    try {
      montar()
    } finally {
      vi.useRealTimers()
    }
    const panel = screen.getByRole('tabpanel')
    const lista = within(panel).getByRole('list', { name: 'Registro de actividad' })
    const filas = within(lista).getAllByRole('listitem')
    expect(filas).toHaveLength(2)
    expect(within(filas[0]!).getByText('10:01')).toBeInTheDocument()
    expect(within(filas[0]!).getByText('Contestó')).toBeInTheDocument()
    expect(within(filas[0]!).getByText('Detalle íntegro 1')).toBeInTheDocument()
    expect(within(filas[0]!).getByText(/Nuevo entonces · Contactado ahora/)).toBeInTheDocument()
    expect(within(filas[0]!).getByText('· ANALISTA UNO')).toBeInTheDocument()
    expect(within(filas[1]!).getByText('No contestó')).toBeInTheDocument()
    expect(within(filas[1]!).getByText('numero errado')).toBeInTheDocument()
    expect(within(filas[1]!).getByText('Sin detalle escrito.')).toBeInTheDocument()
    expect(screen.getByText(/2 gestiones cargadas/)).toBeInTheDocument()
    expect(screen.getByText(/Corte 13:02 \(Lima\) · se actualiza cada minuto/)).toBeInTheDocument()
  })

  it('el nombre del lead abre su ficha', () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: /LEAD 2/ }))
    expect(ESTADO.abrirLead).toHaveBeenCalledWith('l2')
  })

  it('el analista no ve filtros de analista ni de equipo ni la columna de autor', () => {
    montar({ analistaIds: ['u1'], mostrarAnalista: false })
    expect(screen.queryByLabelText('Analista')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Equipo')).not.toBeInTheDocument()
    expect(screen.queryByText('· ANALISTA UNO')).not.toBeInTheDocument()
    expect(ultima().filtros).toMatchObject({ analistaIds: ['u1'], pestana: 'llamadas', dia: '2026-09-19' })
  })
})

describe('RegistroActividad — filtros y cursor', () => {
  it('abre Todo desde la fila fija sin sugerir que se consultan otros analistas', () => {
    montar({ analistaIds: ['u1'], pestanaInicial: 'todo' })
    expect(screen.getByRole('tab', { name: 'Todo' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.queryByLabelText('Analista')).not.toBeInTheDocument()
    expect(screen.getAllByText('· ANALISTA UNO')).toHaveLength(2)
    expect(ultima().filtros).toMatchObject({ analistaIds: ['u1'], pestana: 'todo' })
  })

  it.each(['actor', 'rol', 'dia', 'ambito'] as const)('cambiar %s descarta páginas y filtros previos', (cambio) => {
    ESTADO.pagina = pagina(Array.from({ length: 26 }, (_, i) => item(i + 1)))
    const vista = montar()
    fireEvent.change(screen.getByLabelText('Analista'), { target: { value: 'u1' } })
    fireEvent.click(screen.getByRole('button', { name: 'Ver más' }))
    expect(ultima().cursor).not.toBeNull()
    ESTADO.pagina = null; ESTADO.cargando = true
    if (cambio === 'actor') ESTADO.yo = { ...ESTADO.yo, id: 'otro' }
    if (cambio === 'rol') ESTADO.yo = { ...ESTADO.yo, rol: 'gerencia' }
    vista.rerender(<RegistroActividad dia={cambio === 'dia' ? '2026-09-18' : '2026-09-19'}
      analistaIds={cambio === 'ambito' ? ['u2'] : null} mostrarAnalista permitirExportar={false} />)
    expect(screen.queryByRole('listitem')).not.toBeInTheDocument()
    expect(ultima().cursor).toBeNull()
    expect(ultima().filtros).toMatchObject({ analistaIds: cambio === 'ambito' ? ['u2'] : null })
  })

  it('«Ver más» pide la siguiente página desde la última visible y NO borra lo ya leído mientras carga', () => {
    ESTADO.pagina = pagina(Array.from({ length: 26 }, (_, i) => item(i + 1)))
    const vista = montar()
    expect(screen.getAllByRole('listitem')).toHaveLength(25)
    expect(screen.getByText(/hay más/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver más' }))
    expect(ultima().cursor).toEqual({ antes_de: item(25).creado_en, antes_id: 'a25' })
    // Transición real del hook: la página nueva aún no llegó.
    ESTADO.pagina = null; ESTADO.cargando = true; ESTADO.enVuelo = true
    vista.rerender(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} />)
    expect(screen.getAllByRole('listitem')).toHaveLength(25)
    expect(screen.getByText(/foto fija mientras paginas/)).toBeInTheDocument()
    // Llega la segunda página: se acumula debajo.
    ESTADO.pagina = pagina([item(30)]); ESTADO.cargando = false; ESTADO.enVuelo = false
    vista.rerender(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} />)
    expect(screen.getAllByRole('listitem')).toHaveLength(26)
    expect(screen.queryByRole('button', { name: 'Ver más' })).not.toBeInTheDocument()
  })

  it('un error en la página N conserva las N-1 cargadas y ofrece reintentar en línea', () => {
    ESTADO.pagina = pagina(Array.from({ length: 26 }, (_, i) => item(i + 1)))
    const vista = montar()
    fireEvent.click(screen.getByRole('button', { name: 'Ver más' }))
    ESTADO.pagina = null; ESTADO.error = new Error('caído')
    vista.rerender(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} />)
    expect(screen.getAllByRole('listitem')).toHaveLength(25)
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo traer la siguiente página')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(ESTADO.recargar).toHaveBeenCalled()
  })

  it('cambiar la pestaña estando en la página 2 reinicia el cursor y la acumulación en el MISMO render', () => {
    ESTADO.pagina = pagina(Array.from({ length: 26 }, (_, i) => item(i + 1)))
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Ver más' }))
    expect(ultima().cursor).not.toBeNull()
    fireEvent.click(screen.getByRole('tab', { name: 'Notas' }))
    // Ninguna llamada al hook con filtros nuevos llevó el cursor viejo.
    const conNotas = ESTADO.llamadas.filter((l) => (l.filtros as { pestana: string }).pestana === 'notas')
    expect(conNotas.length).toBeGreaterThan(0)
    expect(conNotas.every((l) => l.cursor === null)).toBe(true)
    expect(screen.getAllByRole('listitem').length).toBeLessThanOrEqual(25)
  })

  it('etapa, equipo y analista viajan al hook; el equipo acota la lista de analistas activos de su subárbol', () => {
    montar({ permitirEquipo: true })
    fireEvent.change(screen.getByLabelText('Etapa actual del lead'), { target: { value: 'nuevo' } })
    expect(ultima().filtros).toMatchObject({ etapa: 'nuevo' })
    const analista = screen.getByLabelText('Analista')
    expect(within(analista).getAllByRole('option').map((o) => o.textContent)).toEqual(['Todos los analistas', 'ANALISTA DOS', 'ANALISTA TRES', 'ANALISTA UNO'])
    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup1' } })
    expect(ultima().filtros).toMatchObject({ analistaIds: ['u1', 'u2'] })
    expect(within(screen.getByLabelText('Analista')).getAllByRole('option').map((o) => o.textContent)).toEqual(['Todos los analistas', 'ANALISTA DOS', 'ANALISTA UNO'])
    fireEvent.change(screen.getByLabelText('Analista'), { target: { value: 'u2' } })
    expect(ultima().filtros).toMatchObject({ analistaIds: ['u2'] })
  })

  it('analistasDelEquipo recorre el subárbol y excluye a los dados de baja', () => {
    const equipo = [...EQUIPO, { perfil_id: 'sup3', nombre_completo: 'ANIDADO', rol_crm: 'supervisor', supervisor_id: 'sup1', activo: true },
      { perfil_id: 'u5', nombre_completo: 'ANALISTA ANIDADO', rol_crm: 'vendedor', supervisor_id: 'sup3', activo: true }] as never
    expect(analistasDelEquipo(equipo, 'sup1')).toEqual(['u1', 'u2', 'u5'])
    expect(analistasDelEquipo(equipo, 'sup2')).toEqual(['u3'])
  })
})

describe('RegistroActividad — estados y exportación', () => {
  it('revocar permiso en página N oculta y borra las páginas previas, sin exportarlas ni afirmar vacío', () => {
    ESTADO.pagina = pagina(Array.from({ length: 26 }, (_, i) => item(i + 1)))
    const vista = montar({ permitirExportar: true })
    fireEvent.click(screen.getByRole('button', { name: 'Ver más' }))
    ESTADO.pagina = null; ESTADO.error = new CrmApiError('Revocado', '42501')
    vista.rerender(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar />)
    expect(screen.getByRole('alert')).toHaveTextContent('Ya no tienes autorización')
    expect(screen.queryByRole('listitem')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Exportar CSV/ })).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
    // Si el acceso vuelve, no reaparecen datos de antes de la revocación.
    ESTADO.error = null; ESTADO.pagina = pagina([item(30)])
    vista.rerender(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar />)
    expect(screen.getAllByRole('listitem')).toHaveLength(1)
    expect(screen.queryByText('Detalle íntegro 1')).not.toBeInTheDocument()
  })

  it('vacío honesto, carga y error con reintento cuando no hay nada cargado', () => {
    ESTADO.pagina = pagina([])
    const vista = montar()
    expect(screen.getByText('No hay actividad con estos filtros')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Todo' }))
    expect(screen.getByText('Todavía no hay actividad hoy')).toBeInTheDocument()
    ESTADO.pagina = null; ESTADO.cargando = true
    vista.rerender(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} />)
    expect(document.querySelector('[aria-busy="true"]')).not.toBeNull()
    ESTADO.cargando = false; ESTADO.error = new Error('caído')
    vista.rerender(<RegistroActividad dia="2026-09-19" analistaIds={null} mostrarAnalista permitirExportar={false} />)
    expect(screen.getByText(/No se pudo cargar el registro/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(ESTADO.recargar).toHaveBeenCalled()
  })

  it('exportar solo aparece cuando está permitido, descarga las filas cargadas con el detalle íntegro y el aviso se limpia al cambiar de filtro', () => {
    const sinPermiso = montar()
    expect(screen.queryByRole('button', { name: /Exportar CSV/ })).not.toBeInTheDocument()
    sinPermiso.unmount()
    montar({ permitirExportar: true })
    fireEvent.click(screen.getByRole('button', { name: /Exportar CSV/ }))
    expect(ESTADO.descargar).toHaveBeenCalledTimes(1)
    const [nombre, contenido] = ESTADO.descargar.mock.calls[0] as unknown as [string, string]
    expect(nombre).toBe('registro-actividad-2026-09-19.csv')
    expect(contenido).toContain('"Detalle íntegro 1"')
    expect(contenido).toContain('"numero_errado"')
    expect(screen.getByText(/Exportadas 2 filas cargadas del 2026-09-19/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Todo' }))
    expect(screen.queryByText(/Exportadas 2 filas/)).not.toBeInTheDocument()
  })
})
