import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { controlCitasInicial } from '@/lib/control-citas'
import { ContextoCitas, type DatosCitas } from './contexto'
import { TableroCitas } from './propuesta'
import type { CitaEjemplo } from './modelo'
import type { GestionCitas } from './metas'

const cotizacion = vi.hoisted(() => ({ tc: { promedio: 3.75, fuente: 'Fuente de prueba' } as { promedio: number; fuente: string } | null, recargar: vi.fn() }))
vi.mock('@/lib/tipo-cambio', async importOriginal => ({ ...await importOriginal<typeof import('@/lib/tipo-cambio')>(),
  // Como el hook real: sin dólares que convertir no consulta y devuelve null.
  useTipoCambio: (habilitado: boolean) => ({ tc: habilitado ? cotizacion.tc : null, recargar: cotizacion.recargar }) }))

afterEach(cleanup)
beforeEach(() => {
  window.history.replaceState(null, '', '#/reuniones')
  cotizacion.tc = { promedio: 3.75, fuente: 'Fuente de prueba' }
})

const EQUIPO = { ana: ['Ana Torres', 'sup-1', 'Claudia Ríos'], luis: ['Luis Vega', 'sup-1', 'Claudia Ríos'], diego: ['Diego Salas', 'sup-2', 'Javier Vega'] } as const
function cita(id: string, analista: keyof typeof EQUIPO, cambios: Partial<CitaEjemplo>): CitaEjemplo {
  const [analistaNombre, supervisorId, supervisor] = EQUIPO[analista]
  return {
    id, leadId: `lead-${id}`, nombre: `Persona ${id}`, telefono: '900000000', analista, analistaNombre, supervisor, supervisorId,
    fecha: '2026-10-10', hora: '10:00', estado: 'programada', modalidad: 'Virtual', origen: 'Formulario', moneda: 'PEN', monto: 10_000,
    resultado: 'Sin resultado registrado', cerrado: false, seguimiento: false, nuevaFecha: null, nota: '', creadoEn: '2026-10-05T15:00:00Z',
    manualPropio: false, registroManual: false, ...cambios,
  }
}
const CITAS = [
  cita('a1', 'ana', { estado: 'realizada', asistioEn: '2026-10-06T16:00:00Z', creadoEn: '2026-10-02T15:00:00Z' }),
  cita('a2', 'ana', { estado: 'realizada', asistioEn: '2026-10-07T16:00:00Z', moneda: 'USD', monto: 2_000, creadoEn: '2026-10-03T15:00:00Z' }),
  cita('a3', 'ana', { estado: 'no_show', monto: 20_000, origen: 'Referido', creadoEn: '2026-10-04T15:00:00Z' }),
  cita('a4', 'ana', { monto: null, creadoEn: '2026-10-12T15:00:00Z' }),
  cita('l1', 'luis', { monto: 5_000, creadoEn: '2026-10-18T15:00:00Z' }),
  cita('d1', 'diego', { estado: 'realizada', asistioEn: '2026-10-09T16:00:00Z', monto: 50_000, creadoEn: '2026-10-08T15:00:00Z' }),
  cita('d2', 'diego', { estado: 'cancelada', monto: 30_000, origen: 'Referido', creadoEn: '2026-10-15T15:00:00Z' }),
]
const conversion = (lead: string, instante: string) => ({ lead_id: lead, perfil_id: `perfil-${lead}`, convertido_en: instante, fecha_comercial: instante.slice(0, 10),
  analista_id: null, analista_nombre: 'Sin analista', supervisor_id: null, supervisor_nombre: 'Sin supervisor', contrato_id: null })
const gestion = (conversiones = [conversion('lead-a1', '2026-10-08T15:00:00Z'), conversion('lead-d1', '2026-10-01T15:00:00Z')]): GestionCitas => ({
  citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones: [],
  avance: { control: { version: 1, mes_inicio: '2026-10', configuracion: { ...controlCitasInicial(), mes_inicio: '2026-10' } }, poblacion: [], conversiones, capital: [] },
})
const fuente: DatosCitas = { citas: CITAS, corte: '2026-10-19T17:00:00Z', depositos: [], depositosDisponibles: false, mesInicial: '2026-10', modoDemo: false, meses: [], gestion: gestion() }
async function abrirProyeccion(cambios: Partial<DatosCitas> = {}) {
  const usuario = userEvent.setup()
  const vista = render(<ContextoCitas value={{ ...fuente, ...cambios }}><TableroCitas /></ContextoCitas>)
  await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
  return { usuario, vista, hoja: screen.getByRole('table', { name: /Proyección de citas por analista/ }) }
}
const fila = (hoja: HTMLElement, nombre: string) => within(hoja).getByRole('row', { name: new RegExp(`^\\d+ ${nombre}`) })

describe('Pestaña Proyección de Citas', () => {
  it('pinta una fila por analista en su equipo; toda cifra es botón, salvo los ceros y los derivados', async () => {
    const { hoja } = await abrirProyeccion()
    expect(screen.getByRole('tab', { name: 'Proyección' })).toHaveAttribute('aria-selected', 'true')
    expect(within(hoja).getAllByRole('button', { name: /^(Equipo|Sin supervisor)/ }).map(b => b.textContent)).toEqual([
      'Equipo Claudia Ríos· 2 analistas · 5 citas', 'Equipo Javier Vega· 1 analista · 2 citas',
    ])
    expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(3)
    // Columnas: # · Citas · Monto · Ticket · % Entrev. · % Conv. · Proyectado · Referidos · Clientes · Leads
    const DERIVADAS = [3, 6]
    for (const tr of hoja.querySelectorAll<HTMLTableRowElement>('tr.pc-fila')) {
      const celdas = within(tr).getAllByRole('cell')
      expect(celdas).toHaveLength(10)
      celdas.slice(1).forEach((celda, i) => {
        const columna = i + 1
        const texto = celda.textContent!.trim()
        // La señal añade su estado para el lector («0% · Brecha alta»): cuenta la cifra.
        const sinValor = ['0', '—', '0%'].includes(texto.replace(/ · .*$/, ''))
        expect(within(celda).queryByRole('button') !== null, `${tr.textContent} · columna ${columna}`).toBe(!sinValor && !DERIVADAS.includes(columna))
      })
    }
    const ana = fila(hoja, 'Ana Torres')
    expect(within(ana).getByRole('button', { name: '4 citas de Ana Torres' })).toBeVisible()
    expect(within(ana).getByRole('button', { name: 'S/ 37,500 en citas de Ana Torres' })).toBeVisible()
    expect(within(ana).getByRole('button', { name: /^% Entrev\. de Ana Torres: 50%/ })).toBeVisible()
    expect(within(ana).getAllByRole('cell')[3]).toHaveTextContent('S/9,375')
    expect(within(ana).queryByRole('button', { name: /con clientes/ })).not.toBeInTheDocument()
    const total = within(hoja).getByRole('row', { name: /^Total · 3 analistas/ })
    expect(within(total).getByRole('button', { name: '7 citas de todos los analistas' })).toBeVisible()
    expect(within(total).getAllByRole('cell')[3]).toHaveTextContent('S/17,500')
  })

  it('cada cifra abre la lista exacta de sus citas, con su conteo', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '4 citas de Ana Torres' }))
    let lista = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
    expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('1–19 oct 2026 · 4 citas')
    expect(within(lista).getAllByRole('row')).toHaveLength(5)
    expect(within(lista).getByRole('row', { name: /Persona a2/ })).toHaveTextContent('US$ 2,000 ·S/ 7,500')
    expect(within(lista).getByRole('button', { name: 'Exportar CSV' })).toBeEnabled()
    await usuario.click(within(lista).getByRole('button', { name: 'Cerrar lista' }))
    await usuario.click(screen.getByRole('button', { name: 'Clientes: 1, ver la lista' }))
    lista = screen.getByRole('dialog', { name: 'Citas con clientes · Total' })
    expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('· 1 cita')
    expect(within(lista).getByRole('columnheader', { name: 'Analista' })).toBeVisible()
    expect(within(lista).getByRole('row', { name: /Persona d1/ })).toHaveTextContent('Diego Salas')
    await usuario.keyboard('{Escape}')
    await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: /^% Conv\. de Ana Torres: 50%/ }))
    lista = screen.getByRole('dialog', { name: 'Entrevistas que cerraron cliente · Ana Torres' })
    expect(within(lista).getAllByRole('row')).toHaveLength(2)
  })

  it('el embudo de Analista filtra con casillas, deja un chip con × y Limpiar lo devuelve todo', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    const embudo = within(hoja).getByRole('button', { name: 'Filtrar Analista' })
    await usuario.click(embudo)
    const menu = screen.getByRole('dialog', { name: 'Filtrar Analista' })
    expect(within(menu).getByRole('searchbox', { name: 'Buscar analista' })).toHaveFocus()
    expect(within(menu).getAllByRole('checkbox').map(c => c.getAttribute('aria-label'))).toEqual([
      'Seleccionar todo', 'Ana Torres · 4 citas', 'Diego Salas · 2 citas', 'Luis Vega · 1 cita'])
    await usuario.click(within(menu).getByRole('checkbox', { name: 'Luis Vega · 1 cita' }))
    await usuario.click(within(menu).getByRole('button', { name: 'Aplicar' }))
    expect(screen.queryByRole('dialog', { name: 'Filtrar Analista' })).not.toBeInTheDocument()
    expect(within(hoja).queryByRole('row', { name: /Luis Vega/ })).not.toBeInTheDocument()
    expect(within(hoja).getByRole('row', { name: /^Total · 2 analistas/ })).toBeVisible()
    expect(screen.getByRole('group', { name: 'Filtros de columna' })).toHaveTextContent('Analista Ana Torres, Diego Salas')
    // Esc cierra el menú y devuelve el foco al embudo.
    await usuario.click(embudo)
    expect(screen.getByRole('dialog', { name: 'Filtrar Analista' })).toBeVisible()
    await usuario.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: 'Filtrar Analista' })).not.toBeInTheDocument()
    expect(embudo).toHaveFocus()
    expect(embudo).toHaveAccessibleName('Filtrar Analista, con filtro')
    // Tab desde el último control del menú lo cierra y devuelve el foco al embudo.
    await usuario.click(embudo)
    within(screen.getByRole('dialog', { name: 'Filtrar Analista' })).getByRole('button', { name: 'Aplicar' }).focus()
    await usuario.tab()
    expect(screen.queryByRole('dialog', { name: 'Filtrar Analista' })).not.toBeInTheDocument()
    expect(embudo).toHaveFocus()
    // Al desaparecer el chip, el foco no cae en <body>: vuelve al embudo de su columna.
    await usuario.click(screen.getByRole('button', { name: 'Limpiar' }))
    expect(fila(hoja, 'Luis Vega')).toBeVisible()
    expect(screen.queryByRole('group', { name: 'Filtros de columna' })).not.toBeInTheDocument()
    expect(embudo).toHaveFocus()
    expect(embudo).toHaveAccessibleName('Filtrar Analista')
  })

  it('el embudo de Clientes lista personas y recorta solo sus citas; Solo dólares deja las citas en USD', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Clientes' }))
    let menu = screen.getByRole('dialog', { name: 'Filtrar Clientes' })
    expect(within(menu).getAllByRole('checkbox').map(c => c.getAttribute('aria-label'))).toEqual(['Seleccionar todo', 'Persona d1 · 1 cita'])
    await usuario.type(within(menu).getByRole('searchbox', { name: 'Buscar cliente' }), 'nadie')
    expect(within(menu).getAllByRole('checkbox')).toHaveLength(1)
    await usuario.clear(within(menu).getByRole('searchbox', { name: 'Buscar cliente' }))
    await usuario.click(within(menu).getByRole('checkbox', { name: 'Seleccionar todo' }))
    await usuario.click(within(menu).getByRole('button', { name: 'Aplicar' }))
    expect(within(fila(hoja, 'Diego Salas')).getByRole('button', { name: '1 cita de Diego Salas' })).toBeVisible()
    await usuario.click(screen.getByRole('button', { name: 'Quitar filtro de Clientes' }))
    expect(within(hoja).getByRole('button', { name: 'Filtrar Clientes' })).toHaveFocus()
    await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Monto S/' }))
    menu = screen.getByRole('dialog', { name: 'Filtrar Monto S/' })
    expect(within(menu).getByRole('checkbox', { name: 'Dólares · US$ 2,000 · 1 cita' })).toBeChecked()
    await usuario.click(within(menu).getByRole('checkbox', { name: 'Soles · S/ 115,000 · 6 citas' }))
    await usuario.click(within(menu).getByRole('button', { name: 'Aplicar' }))
    expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(1)
    expect(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: 'S/ 7,500 en citas de Ana Torres' })).toBeVisible()
    expect(screen.getByRole('group', { name: 'Filtros de columna' })).toHaveTextContent('Monto S/ Solo dólares')
  })

  it('ordena con la cabecera y con el embudo', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    const nombres = () => [...hoja.querySelectorAll('tr.pc-fila th')].map(th => th.textContent)
    expect(nombres()).toEqual(['ATAna Torres', 'LVLuis Vega', 'DSDiego Salas'])
    await usuario.click(within(hoja).getByRole('button', { name: 'Citas' }))
    expect(within(hoja).getByRole('columnheader', { name: /Citas/ })).toHaveAttribute('aria-sort', 'ascending')
    expect(nombres()).toEqual(['LVLuis Vega', 'ATAna Torres', 'DSDiego Salas'])
    await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Ticket S/' }))
    await usuario.click(screen.getByRole('button', { name: 'Ordenar de mayor a menor' }))
    expect(nombres()).toEqual(['ATAna Torres', 'LVLuis Vega', 'DSDiego Salas'])
    await usuario.click(within(hoja).getByRole('button', { name: /^Equipo Claudia Ríos/ }))
    expect(nombres()).toEqual(['DSDiego Salas'])
    expect(within(hoja).getByText('3')).toHaveClass('pc-n0')
  })

  it('sin tipo de cambio: el monto con dólares queda pendiente y se puede reintentar', async () => {
    cotizacion.tc = null
    const { usuario, hoja } = await abrirProyeccion()
    expect(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: 'Pendiente de TC en citas de Ana Torres' })).toBeVisible()
    expect(within(fila(hoja, 'Ana Torres')).getAllByRole('cell')[3]).toHaveTextContent('—')
    expect(screen.getByRole('button', { name: 'Monto: Pendiente de TC, ver la lista' })).toBeVisible()
    await usuario.click(screen.getByRole('button', { name: 'Reintentar TC' }))
    expect(cotizacion.recargar).toHaveBeenCalledTimes(1)
  })

  it('exporta en CSV la hoja y la lista lateral, y avisa si el navegador no puede', async () => {
    const blobs: Blob[] = []
    const original = { crear: URL.createObjectURL, revocar: URL.revokeObjectURL }
    URL.createObjectURL = vi.fn((blob: Blob) => { blobs.push(blob); return 'blob:proyeccion' })
    URL.revokeObjectURL = vi.fn()
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    const leer = (blob: Blob) => new Promise<string>((resolve, reject) => {
      const lector = new FileReader()
      lector.onload = () => resolve(String(lector.result))
      lector.onerror = reject
      lector.readAsText(blob)
    })
    try {
      const { usuario, hoja } = await abrirProyeccion()
      await usuario.click(screen.getByRole('button', { name: 'Exportar CSV' }))
      expect(click).toHaveBeenCalledOnce()
      const csvHoja = (await leer(blobs[0]!)).split('\r\n')
      expect(csvHoja).toHaveLength(5)
      expect(csvHoja[0]).toContain('"Ticket S/","% Entrev.","% Conv.","Proyectado S/","Referidos","Clientes","Leads"')
      expect(csvHoja[1]).toMatch(/^"1–19 oct 2026","Claudia Ríos","Ana Torres","4","37500","9375","50","50",/)
      expect(screen.getByText('Se descargó la proyección de 3 analistas.')).toBeVisible()
      await usuario.click(within(hoja).getByRole('button', { name: '4 citas de Ana Torres' }))
      const lista = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
      const csvLista = (await leer(blobs[1]!)).split('\r\n')
      expect(csvLista).toHaveLength(5)
      expect(csvLista.find(l => l.startsWith('"a2"'))).toBe('"a2","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
      expect(within(lista).getByText('Se descargó el CSV con 4 citas.')).toBeVisible()
      URL.createObjectURL = vi.fn(() => { throw new Error('sin memoria') })
      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
      expect(within(lista).getByText('No se pudo descargar el archivo. Vuelve a intentarlo.')).toBeVisible()
    } finally {
      URL.createObjectURL = original.crear
      URL.revokeObjectURL = original.revocar
    }
  })

  it('el rango nace del mes de arriba hasta hoy; los atajos y las fechas lo cambian y se valida', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–19 oct 2026')
    expect(screen.getByRole('button', { name: 'Mes' })).toHaveAttribute('aria-pressed', 'true')
    await usuario.click(screen.getByRole('button', { name: 'S3' }))
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('15–21 oct 2026')
    expect([...hoja.querySelectorAll('tr.pc-fila th')].map(th => th.textContent)).toEqual(['LVLuis Vega', 'DSDiego Salas'])
    expect(screen.getByLabelText('Desde')).toHaveValue('2026-10-15')
    // Un rango al revés no se aplica: se avisa y la hoja conserva el último válido.
    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-10-25' } })
    expect(screen.getByRole('alert')).toHaveTextContent('«Desde» debe ser anterior o igual a «Hasta».')
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('15–21 oct 2026')
    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-10-03' } })
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('3–21 oct 2026')
    expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(3)
    // El rango es de la pestaña: sobrevive al ir y volver, y no toca la semana de arriba.
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    expect(screen.getByLabelText('Semana')).toHaveValue('')
    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('3–21 oct 2026')
    await usuario.click(screen.getByRole('button', { name: 'Mes pasado' }))
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–30 set 2026')
    expect(screen.getByRole('table', { name: /Proyección de citas por analista/ }).querySelectorAll('tr.pc-fila')).toHaveLength(0)
  })

  it('un rango que cruza meses pide esos meses, espera sin cifras parciales y pinta lo fusionado', async () => {
    const pedir = vi.fn()
    const septiembre = cita('s1', 'diego', { creadoEn: '2026-09-28T15:00:00Z', fecha: '2026-09-29' })
    const base = { onMesesProyeccion: pedir, proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, cargando: false, error: null, onReintentar: vi.fn() } }
    const { usuario, vista } = await abrirProyeccion(base)
    expect(pedir).toHaveBeenLastCalledWith(['2026-10'])
    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-09-25' } })
    expect(pedir).toHaveBeenLastCalledWith(['2026-09', '2026-10'])
    expect(screen.getByText('Cargando las citas del rango…')).toBeVisible()
    expect(screen.queryByRole('table', { name: /Proyección de citas por analista/ })).not.toBeInTheDocument()
    const rehacer = (proyeccion: Partial<NonNullable<DatosCitas['proyeccion']>>) => vista.rerender(<ContextoCitas value={{ ...fuente, ...base, proyeccion: { ...base.proyeccion, ...proyeccion } }}><TableroCitas /></ContextoCitas>)
    rehacer({ meses: ['2026-09', '2026-10'], error: 'No se pudieron cargar las citas.' })
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las citas.')
    await usuario.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(base.proyeccion.onReintentar).toHaveBeenCalledTimes(1)
    rehacer({ meses: ['2026-09', '2026-10'], citas: [...CITAS, septiembre] })
    const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('25 set – 19 oct 2026')
    expect(within(fila(hoja, 'Diego Salas')).getByRole('button', { name: '3 citas de Diego Salas' })).toBeVisible()
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    expect(pedir).toHaveBeenLastCalledWith([])
  })

  it('ESTADO DE PRODUCCIÓN (mes sin citas): cabecera, ninguna fila, total en cero y ningún error', async () => {
    const { hoja } = await abrirProyeccion({ citas: [], gestion: gestion([]) })
    expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(0)
    expect(within(hoja).getAllByRole('columnheader').map(th => th.textContent)).toEqual([
      '#Número', 'Analista', 'Citas', 'Monto S/', 'Ticket S/', '% Entrev.', '% Conv.', 'Proyectado S/', 'Referidos', 'Clientes', 'Leads',
    ])
    expect(within(hoja).getByRole('row', { name: /^Total · 0 analistas/ })).toBeVisible()
    expect(within(hoja).queryAllByRole('button', { name: /de todos los analistas/ })).toEqual([])
    expect(screen.getByRole('group', { name: 'Totales de la proyección' })).toHaveTextContent(/^Citas:0Monto:S\/ 0Ticket:—Entrevistas:—Conversión:—Proyectado:—Referidos:0Clientes:0Leads:0Analistas:0TC:—$/)
    expect(screen.queryByRole('button', { name: /^Citas: / })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Exportar CSV' })).toBeDisabled()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(screen.queryByText('No hay citas con esta combinación')).not.toBeInTheDocument()
  })
})
