import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { controlCitasInicial } from '@/lib/control-citas'
import { ContextoCitas, type DatosCitas } from './contexto'
import { TableroCitas } from './propuesta'
import type { CitaEjemplo } from './modelo'
import type { GestionCitas } from './metas'
import type { ReunionClienteProyeccion } from './proyeccion'

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
// Cada venta lleva su dueño: como en Resultados, una venta sin analista no cierra ninguna entrevista.
const conversion = (lead: string, instante: string, analista: keyof typeof EQUIPO) => ({ lead_id: lead, perfil_id: `perfil-${lead}`, convertido_en: instante, fecha_comercial: instante.slice(0, 10),
  analista_id: analista, analista_nombre: EQUIPO[analista][0], supervisor_id: EQUIPO[analista][1], supervisor_nombre: EQUIPO[analista][2], contrato_id: null })
// La población del avance, como la manda el servidor: una persona por lead. % Entrev. y % Conv. son los de Resultados,
// que solo mide a las personas de la población.
const POBLACION = [...new Set(CITAS.map(c => c.leadId))].map(lead_id => ({ lead_id, nombre: lead_id, telefono: '900000000', origen: 'formulario',
  moneda: 'PEN' as const, monto_estimado: 1000, registro_manual: false, creado_por: null, analista_origen_id: null, analista_origen_nombre: 'Sin analista',
  supervisor_origen_id: null, supervisor_origen_nombre: 'Sin supervisor', primera_asignacion_en: null }))
const gestion = (conversiones = [conversion('lead-a1', '2026-10-08T15:00:00Z', 'ana'), conversion('lead-d1', '2026-10-01T15:00:00Z', 'diego')]): GestionCitas => ({
  citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones: [],
  avance: { control: { version: 1, mes_inicio: '2026-10', configuracion: { ...controlCitasInicial(), mes_inicio: '2026-10' } }, poblacion: POBLACION, conversiones, capital: [] },
})
const fuente: DatosCitas = { citas: CITAS, corte: '2026-10-19T17:00:00Z', depositos: [], depositosDisponibles: false, mesInicial: '2026-10', modoDemo: false, meses: [], gestion: gestion() }
async function abrirProyeccion(cambios: Partial<DatosCitas> = {}) {
  const usuario = userEvent.setup()
  const vista = render(<ContextoCitas value={{ ...fuente, ...cambios }}><TableroCitas /></ContextoCitas>)
  await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
  return { usuario, vista, hoja: screen.getByRole('table', { name: /Proyección de citas por analista/ }) }
}
const fila = (hoja: HTMLElement, nombre: string) => within(hoja).getByRole('row', { name: new RegExp(`^\\d+ ${nombre}`) })
const filaTotal = (hoja: HTMLElement) => within(hoja).getByRole('row', { name: /^Total · / })
const nombres = (hoja: HTMLElement) => [...hoja.querySelectorAll('tr.pc-fila th')].map(th => th.textContent)
const tiempo = (nombre: 'Mes' | 'Semanas' | 'Días') => within(screen.getByRole('group', { name: 'Columnas de tiempo' })).getByRole('button', { name: nombre })
const atajo = (nombre: string) => within(screen.getByRole('group', { name: 'Atajos de periodo' })).getByRole('button', { name: nombre })
/** Cabeceras de las columnas de tiempo tal como se ven (título y detalle). */
const cabecerasTiempo = (hoja: HTMLElement) => [...hoja.querySelectorAll('thead th.pc-tiempo .pc-tiempo-cab')].map(e => `${e.firstChild?.textContent} ${e.querySelector('small')?.textContent}`)
/** Intercepta las descargas: nombre del archivo y filas del CSV (sin la cabecera), en orden. */
function capturarDescargas() {
  const archivos: { nombre: string; blob: Blob }[] = []
  const original = { crear: URL.createObjectURL, revocar: URL.revokeObjectURL }
  let ultimo: Blob | null = null
  URL.createObjectURL = vi.fn((blob: Blob) => { ultimo = blob; return 'blob:proyeccion' })
  URL.revokeObjectURL = vi.fn()
  const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) { archivos.push({ nombre: this.download, blob: ultimo! }) })
  const filas = async (i: number) => (await archivos[i]!.blob.text()).split('\r\n').slice(1)
  return { archivos, filas, restaurar: () => { URL.createObjectURL = original.crear; URL.revokeObjectURL = original.revocar; click.mockRestore() } }
}
const codigos = (filas: string[]) => filas.map(f => f.slice(1, f.indexOf('"', 1)))

describe('Pestaña Proyección de Citas', () => {
  it('pinta una hoja plana, una fila por analista y # continuo; toda cifra es botón (también Ticket cita y Proyectado citas), salvo ceros y «—»', async () => {
    const { hoja } = await abrirProyeccion()
    expect(screen.getByRole('tab', { name: 'Proyección' })).toHaveAttribute('aria-selected', 'true')
    // Sin bandas por equipo ni pastillas de totales: la fila Σ da los totales.
    expect(within(hoja).queryByRole('button', { name: /^(Equipo|Sin supervisor)/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('group', { name: 'Totales de la proyección' })).not.toBeInTheDocument()
    expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(3)
    expect([...hoja.querySelectorAll('tr.pc-fila td.pc-n0')].map(td => td.textContent)).toEqual(['1', '2', '3'])
    // Columnas: # · Citas · Monto · Ticket · % Entrev. · % Conv. · Proyectado · Referidos · Clientes · Leads
    for (const tr of hoja.querySelectorAll<HTMLTableRowElement>('tr.pc-fila')) {
      const celdas = within(tr).getAllByRole('cell')
      expect(celdas).toHaveLength(10)
      celdas.slice(1).forEach((celda, i) => {
        const columna = i + 1
        const texto = celda.textContent!.trim()
        // La señal añade su estado para el lector («0% · Brecha alta»): cuenta la cifra.
        const sinValor = ['0', '—', '0%'].includes(texto.replace(/ · .*$/, ''))
        expect(within(celda).queryByRole('button') !== null, `${tr.textContent} · columna ${columna}`).toBe(!sinValor)
      })
    }
    const ana = fila(hoja, 'Ana Torres')
    expect(within(ana).getByRole('button', { name: '4 citas de Ana Torres' })).toBeVisible()
    expect(within(ana).getByRole('button', { name: 'S/ 37,500 en citas de Ana Torres' })).toBeVisible()
    // Codex (19/10): «todo número se abre»; Ticket cita y Proyectado citas abren su base, las citas con lead.
    expect(within(ana).getByRole('button', { name: /^S\/ 9,375 de ticket cita de Ana Torres$/ })).toBeVisible()
    expect(within(ana).getByRole('button', { name: /proyectado en citas de Ana Torres$/ })).toBeVisible()
    // % Entrev. como Resultados: 2 realizadas ÷ 3 resueltas (la programada a4 no es base).
    expect(within(ana).getByRole('button', { name: /^% Entrev\. de Ana Torres: 66\.7%/ })).toBeVisible()
    expect(within(fila(hoja, 'Luis Vega')).getAllByRole('cell')[4]).toHaveTextContent('— · Sin base para evaluar')
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
    await usuario.click(within(filaTotal(hoja)).getByRole('button', { name: '1 cita con cliente de todos los analistas' }))
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

  it('ordena con la cabecera y con el embudo, en un orden global que mezcla equipos', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    expect(nombres(hoja)).toEqual(['ATAna Torres', 'DSDiego Salas', 'LVLuis Vega'])
    await usuario.click(within(hoja).getByRole('button', { name: 'Citas' }))
    expect(within(hoja).getByRole('columnheader', { name: /Citas/ })).toHaveAttribute('aria-sort', 'ascending')
    expect(nombres(hoja)).toEqual(['LVLuis Vega', 'DSDiego Salas', 'ATAna Torres'])
    await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Ticket cita S/' }))
    await usuario.click(screen.getByRole('button', { name: 'Ordenar de mayor a menor' }))
    expect(nombres(hoja)).toEqual(['DSDiego Salas', 'ATAna Torres', 'LVLuis Vega'])
    expect([...hoja.querySelectorAll('tr.pc-fila td.pc-n0')].map(td => td.textContent)).toEqual(['1', '2', '3'])
  })

  it('sin tipo de cambio: el monto con dólares queda pendiente y se puede reintentar', async () => {
    cotizacion.tc = null
    const { usuario, hoja } = await abrirProyeccion()
    expect(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: 'Pendiente de TC en citas de Ana Torres' })).toBeVisible()
    expect(within(fila(hoja, 'Ana Torres')).getAllByRole('cell')[3]).toHaveTextContent('—')
    expect(within(filaTotal(hoja)).getByRole('button', { name: 'Pendiente de TC en citas de todos los analistas' })).toBeVisible()
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
      await usuario.click(screen.getByRole('button', { name: 'Exportar' }))
      await usuario.click(screen.getByRole('menuitem', { name: 'Hoja por analista' }))
      expect(click).toHaveBeenCalledOnce()
      const csvHoja = (await leer(blobs[0]!)).split('\r\n')
      expect(csvHoja).toHaveLength(5)
      expect(csvHoja[0]).toContain('"Ticket cita S/","% Entrev.","% Conv.","Proyectado citas S/","Referidos","Clientes","Leads"')
      expect(csvHoja[1]).toMatch(/^"1–19 oct 2026","Claudia Ríos","Ana Torres","4","37500","9375","66.7","50",/)
      expect(screen.getByText('Se descargó la proyección de 3 analistas.')).toBeVisible()
      await usuario.click(within(hoja).getByRole('button', { name: '4 citas de Ana Torres' }))
      const lista = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
      const csvLista = (await leer(blobs[1]!)).split('\r\n')
      expect(csvLista).toHaveLength(5)
      expect(csvLista.find(l => l.startsWith('"a2"'))).toBe('"a2","2026-10-03","2026-10-10","10:00","Persona a2","Ana Torres","Claudia Ríos","Realizada","USD","2000","7500","Lead"')
      expect(within(lista).getByText('Se descargó el CSV con 4 citas.')).toBeVisible()
      URL.createObjectURL = vi.fn(() => { throw new Error('sin memoria') })
      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
      expect(within(lista).getByText('No se pudo descargar el archivo. Vuelve a intentarlo.')).toBeVisible()
    } finally {
      URL.createObjectURL = original.crear
      URL.revokeObjectURL = original.revocar
    }
  })

  it('Exportar abre un menú con «Hoja por analista» y «Citas del periodo»: flechas para moverse y Esc lo cierra devolviendo el foco', async () => {
    const descargas = capturarDescargas()
    try {
      const { usuario } = await abrirProyeccion()
      const exportar = screen.getByRole('button', { name: 'Exportar' })
      expect(exportar).toHaveAttribute('aria-haspopup', 'menu')
      await usuario.click(exportar)
      const menu = screen.getByRole('menu')
      expect(within(menu).getAllByRole('menuitem').map(item => item.textContent)).toEqual(['Hoja por analista', 'Citas del periodo'])
      expect(within(menu).getByRole('menuitem', { name: 'Hoja por analista' })).toHaveFocus()
      await usuario.keyboard('{ArrowDown}')
      expect(within(menu).getByRole('menuitem', { name: 'Citas del periodo' })).toHaveFocus()
      await usuario.keyboard('{Escape}')
      expect(screen.queryByRole('menu')).not.toBeInTheDocument()
      expect(exportar).toHaveFocus()
      expect(descargas.archivos).toHaveLength(0)
      // Con teclado: Enter elige; el menú se cierra, el foco vuelve a Exportar y el aviso lo cuenta.
      await usuario.keyboard('{Enter}')
      await usuario.keyboard('{ArrowDown}')
      await usuario.keyboard('{Enter}')
      expect(screen.queryByRole('menu')).not.toBeInTheDocument()
      expect(exportar).toHaveFocus()
      expect(descargas.archivos.map(a => a.nombre)).toEqual(['proyeccion-citas-del-periodo-2026-10-01_2026-10-19.csv'])
      expect(screen.getByText('Se descargaron las 7 citas del periodo.')).toBeVisible()
      // (Blob.text() descarta el BOM que el CSV lleva para Excel.)
      const [cabecera] = (await descargas.archivos[0]!.blob.text()).split('\r\n')
      expect(cabecera).toBe('"Código de cita","Creada","Fecha","Hora","Persona","Analista","Supervisor","Estado","Moneda","Monto","Monto S/","Origen"')
      await usuario.click(exportar)
      await usuario.click(screen.getByRole('menuitem', { name: 'Hoja por analista' }))
      expect(descargas.archivos[1]!.nombre).toBe('proyeccion-por-analista-2026-10-01_2026-10-19.csv')
      expect(await descargas.filas(1)).toHaveLength(4)
    } finally { descargas.restaurar() }
  })

  it('el rango nace del mes de arriba hasta hoy; los atajos y las fechas lo cambian y se valida', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–19 oct 2026')
    expect(atajo('Mes')).toHaveAttribute('aria-pressed', 'true')
    await usuario.click(atajo('S3'))
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('15–21 oct 2026')
    expect(nombres(hoja)).toEqual(['DSDiego Salas', 'LVLuis Vega'])
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
    await usuario.click(atajo('Mes pasado'))
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–30 set 2026')
    expect(screen.getByRole('table', { name: /Proyección de citas por analista/ }).querySelectorAll('tr.pc-fila')).toHaveLength(0)
  })

  it('un rango que cruza meses pide esos meses, espera sin cifras parciales y pinta lo fusionado', async () => {
    const pedir = vi.fn()
    const septiembre = cita('s1', 'diego', { creadoEn: '2026-09-28T15:00:00Z', fecha: '2026-09-29' })
    const base = { onMesesProyeccion: pedir, proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: { desde: '2026-10-01', hasta: '2026-10-19' }, reunionesClientes: [], cargando: false, error: null, onReintentar: vi.fn() } }
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
    rehacer({ meses: ['2026-09', '2026-10'], rango: { desde: '2026-09-25', hasta: '2026-10-19' }, citas: [...CITAS, septiembre] })
    const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('25 set – 19 oct 2026')
    expect(within(fila(hoja, 'Diego Salas')).getByRole('button', { name: '3 citas de Diego Salas' })).toBeVisible()
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    expect(pedir).toHaveBeenLastCalledWith([])
  })

  it('con el mes de arriba cargando o en error, la Proyección se pinta con los meses de su propio rango', async () => {
    // Codex (19/10): el mes de arriba puede quedar fuera del rango; su carga o su
    // error no deben tapar una hoja cuyos meses ya llegaron.
    const propia = { onMesesProyeccion: vi.fn(), proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: { desde: '2026-10-01', hasta: '2026-10-19' }, reunionesClientes: [], cargando: false, error: null, onReintentar: vi.fn() } }
    const { hoja, vista } = await abrirProyeccion({ ...propia, cargando: true })
    expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(3)
    expect(screen.getByRole('tabpanel')).not.toHaveTextContent('Cargando las citas de tu consulta…')
    vista.rerender(<ContextoCitas value={{ ...fuente, ...propia, cargando: false, error: 'No se pudieron cargar las citas.' }}><TableroCitas /></ContextoCitas>)
    expect(screen.getByRole('table', { name: /Proyección de citas por analista/ }).querySelectorAll('tr.pc-fila')).toHaveLength(3)
    expect(within(screen.getByRole('tabpanel')).queryByRole('alert')).not.toBeInTheDocument()
    // Sin cargador propio (demo), la compuerta del mes de arriba sigue mandando.
    vista.rerender(<ContextoCitas value={{ ...fuente, cargando: true }}><TableroCitas /></ContextoCitas>)
    expect(within(screen.getByRole('tabpanel')).getByRole('status')).toHaveTextContent('Cargando las citas de tu consulta…')
  })

  it('ESTADO DE PRODUCCIÓN (mes sin citas): cabecera, ninguna fila, total en cero y ningún error', async () => {
    const { hoja } = await abrirProyeccion({ citas: [], gestion: gestion([]) })
    expect(hoja.querySelectorAll('tr.pc-fila')).toHaveLength(0)
    expect(within(hoja).getAllByRole('columnheader').map(th => th.textContent)).toEqual([
      '#Número', 'Analista', 'Citas', 'Monto S/', 'Ticket cita S/', '% Entrev.', '% Conv.', 'Proyectado citas S/', 'Referidos', 'Clientes', 'Leads',
    ])
    expect(within(hoja).getByRole('row', { name: /^Total · 0 analistas/ })).toBeVisible()
    expect(within(hoja).queryAllByRole('button', { name: /de todos los analistas/ })).toEqual([])
    expect(within(filaTotal(hoja)).getAllByRole('cell').map(td => td.textContent)).toEqual(['Σ', '0', '—', '—', '— · Sin base para evaluar', '— · Sin base para evaluar', '—', '0', '0', '0'])
    expect(screen.queryByRole('group', { name: 'Totales de la proyección' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Exportar' })).toBeDisabled()
    // Sin citas, las columnas de tiempo también se pintan, en cero y sin botones.
    await userEvent.setup().click(tiempo('Semanas'))
    expect(cabecerasTiempo(hoja)).toEqual(['S1 1–7', 'S2 8–14', 'S3 15–19'])
    expect(within(filaTotal(hoja)).getAllByRole('cell').slice(1, 4).map(td => td.textContent)).toEqual(['0', '0', '0'])
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(screen.queryByText('No hay citas con esta combinación')).not.toBeInTheDocument()
  })
  it('en Proyección no se pintan los filtros de arriba: el Supervisor vive en su barra y el analista o un error de arriba no aplican', async () => {
    const usuario = userEvent.setup()
    render(<ContextoCitas value={fuente}><TableroCitas /></ContextoCitas>)
    // Arriba: Luis como analista y un monto imposible (error de filtros).
    fireEvent.change(screen.getByLabelText('Analista'), { target: { value: 'luis' } })
    await usuario.click(screen.getByRole('button', { name: /^Más filtros/ }))
    fireEvent.change(screen.getByLabelText(/^Moneda del monto estimado/), { target: { value: 'PEN' } })
    fireEvent.change(screen.getByLabelText('Monto desde'), { target: { value: '10' } })
    fireEvent.change(screen.getByLabelText('Monto hasta'), { target: { value: '5' } })
    expect(screen.getAllByText('El monto mínimo debe ser menor o igual al máximo.')[0]).toBeVisible()
    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
    expect(screen.queryByRole('region', { name: 'Consulta de citas' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Exportar citas/ })).not.toBeInTheDocument()
    expect(document.querySelector('.citas-corte')!.textContent).toMatch(/^Seguimiento al /)
    const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
    expect(nombres(hoja)).toEqual(['ATAna Torres', 'DSDiego Salas', 'LVLuis Vega'])
    expect(screen.queryByText('Revisa los filtros de la consulta')).not.toBeInTheDocument()
    // Barra única: Supervisor · rango · atajos · columnas de tiempo · Exportar.
    const barra = screen.getByRole('group', { name: 'Consulta de la proyección' })
    expect([...barra.querySelectorAll('label, strong, [role=group], .pc-acciones')].map(e => e.getAttribute('aria-label') ?? e.textContent!.slice(0, 10)))
      .toEqual(['Supervisor', '1–19 oct 2', 'Desde', 'Hasta', 'Atajos de periodo', 'Columnas de tiempo', 'Exportar'])
    const supervisor = within(barra).getByLabelText('Supervisor')
    expect([...supervisor.querySelectorAll('option')].map(o => o.textContent)).toEqual(['Todos', 'Claudia Ríos', 'Javier Vega'])
    await usuario.selectOptions(supervisor, 'sup-2')
    expect(nombres(hoja)).toEqual(['DSDiego Salas'])
    // Es el mismo supervisor de las otras pestañas; Luis no es de ese equipo y sale del filtro de analista.
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    expect(screen.getByLabelText('Supervisor')).toHaveValue('sup-2')
    expect(screen.getByLabelText('Analista')).toHaveValue('')
  })

  it('Semanas: columnas S1–S3 justo antes de Citas; cada número abre su lista y los tramos suman la columna Citas', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    expect(tiempo('Mes')).toHaveAttribute('aria-pressed', 'true')
    expect(hoja.querySelectorAll('th.pc-tiempo')).toHaveLength(0)
    await usuario.click(tiempo('Semanas'))
    expect(tiempo('Semanas')).toHaveAttribute('aria-pressed', 'true')
    expect(cabecerasTiempo(hoja)).toEqual(['S1 1–7', 'S2 8–14', 'S3 15–19'])
    expect(within(hoja).getByRole('columnheader', { name: 'S2 8–14 oct' })).toBeVisible()
    const cabeceras = [...hoja.querySelectorAll('thead th')]
    expect(cabeceras[1]).toHaveTextContent('Analista')
    expect(cabeceras[5]).toHaveClass('pc-tcierre')
    expect(cabeceras[5]).toHaveTextContent('Citas')
    // Sin embudo ni orden en las columnas de tiempo.
    expect(within(hoja).queryByRole('button', { name: /^Filtrar S\d/ })).not.toBeInTheDocument()
    const ana = fila(hoja, 'Ana Torres')
    expect(within(ana).getAllByRole('cell').slice(1, 5).map(td => td.textContent)).toEqual(['3', '1', '0', '4'])
    expect(within(ana).queryByRole('button', { name: /S3 15–19 oct/ })).not.toBeInTheDocument()
    for (const tr of [...hoja.querySelectorAll<HTMLTableRowElement>('tbody tr, tfoot tr')]) {
      const [, s1, s2, s3, citas] = within(tr).getAllByRole('cell').map(td => Number(td.textContent))
      expect(s1! + s2! + s3!, tr.textContent!).toBe(citas)
    }
    await usuario.click(within(ana).getByRole('button', { name: '1 cita de Ana Torres, S2 8–14 oct' }))
    let lista = screen.getByRole('dialog', { name: 'Citas · S2 8–14 oct · Ana Torres' })
    expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('8–14 oct 2026 · 1 cita')
    expect(within(lista).getByRole('row', { name: /Persona a4/ })).toBeVisible()
    await usuario.keyboard('{Escape}')
    await usuario.click(within(filaTotal(hoja)).getByRole('button', { name: '2 citas de todos los analistas, S3 15–19 oct' }))
    lista = screen.getByRole('dialog', { name: 'Citas · S3 15–19 oct · Total' })
    expect(within(lista).getByRole('columnheader', { name: 'Analista' })).toBeVisible()
    expect(within(lista).getAllByRole('row')).toHaveLength(3)
    await usuario.keyboard('{Escape}')
    // Un rango que cruza meses lleva el mes en el detalle de cada semana.
    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-09-25' } })
    expect(cabecerasTiempo(hoja)).toEqual(['S4 25–30 set', 'S1 1–7 oct', 'S2 8–14 oct', 'S3 15–19 oct'])
  })

  it('Días: una columna por día con domingo, hoy y futuros marcados; con más de 31 días cae a Semanas', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    await usuario.click(tiempo('Días'))
    expect(hoja).toHaveAttribute('data-tiempo', 'dias')
    const dias = cabecerasTiempo(hoja)
    expect(dias).toHaveLength(19)
    expect(dias.slice(0, 3)).toEqual(['1 oct jue', '2 vie', '3 sáb'])
    expect([...hoja.querySelectorAll('thead th.pc-domingo')].map(th => th.querySelector('.sr-only')!.textContent)).toEqual(['dom 4 oct', 'dom 11 oct', 'dom 18 oct'])
    expect([...hoja.querySelectorAll('thead th.pc-hoy')].map(th => th.querySelector('.sr-only')!.textContent)).toEqual(['lun 19 oct'])
    await usuario.click(within(fila(hoja, 'Luis Vega')).getByRole('button', { name: '1 cita de Luis Vega, 18 oct' }))
    const lista = screen.getByRole('dialog', { name: 'Citas · 18 oct · Luis Vega' })
    expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('18 oct 2026 · 1 cita')
    expect(within(lista).getByRole('row', { name: /Persona l1/ })).toBeVisible()
    await usuario.keyboard('{Escape}')
    // Días que aún no llegan: atenuados (3 filas × 6 días).
    fireEvent.change(screen.getByLabelText('Hasta'), { target: { value: '2026-10-25' } })
    expect(hoja.querySelectorAll('tbody td.pc-futuro')).toHaveLength(18)
    // Más de 31 días: «Días» se deshabilita y la hoja se pinta por semanas.
    fireEvent.change(screen.getByLabelText('Desde'), { target: { value: '2026-09-01' } })
    expect(tiempo('Días')).toBeDisabled()
    expect(tiempo('Semanas')).toHaveAttribute('aria-pressed', 'true')
    expect(hoja).toHaveAttribute('data-tiempo', 'semanas')
    expect(cabecerasTiempo(hoja)[0]).toBe('S1 1–7 set')
    // Al volver a 31 días o menos, vuelve lo elegido.
    await usuario.click(atajo('Mes'))
    expect(tiempo('Días')).toHaveAttribute('aria-pressed', 'true')
    expect(cabecerasTiempo(hoja)).toHaveLength(19)
  })

  it('Actualizar recarga los meses del rango cuando la Proyección tiene cargador propio', async () => {
    const recargarMes = vi.fn()
    const propia = { onMesesProyeccion: vi.fn(), proyeccion: { meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: { desde: '2026-10-01', hasta: '2026-10-19' }, reunionesClientes: [], cargando: false, error: null, onReintentar: vi.fn() } }
    const { usuario } = await abrirProyeccion({ ...propia, onReintentar: recargarMes })
    await usuario.click(screen.getByRole('button', { name: 'Actualizar' }))
    expect(propia.proyeccion.onReintentar).toHaveBeenCalledTimes(1)
    expect(recargarMes).not.toHaveBeenCalled()
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    await usuario.click(screen.getByRole('button', { name: 'Actualizar' }))
    expect(recargarMes).toHaveBeenCalledTimes(1)
  })

  it('un enlace de Proyección abre la pestaña con su rango, columnas y supervisor; los cambios lo reescriben y otra pestaña lo quita', async () => {
    const usuario = userEvent.setup()
    // El enlace solo admite supervisores reales (uuid) o «sin_supervisor».
    const sinSupervisor = cita('x1', 'luis', { supervisorId: 'sin_supervisor', supervisor: 'Sin supervisor', creadoEn: '2026-10-06T15:00:00Z' })
    window.history.replaceState(null, '', '#/reuniones/proyeccion/2026-10-03/2026-10-19/semanas')
    render(<ContextoCitas value={{ ...fuente, citas: [...CITAS, sinSupervisor] }}><TableroCitas /></ContextoCitas>)
    expect(screen.getByRole('tab', { name: 'Proyección' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('3–19 oct 2026')
    expect(tiempo('Semanas')).toHaveAttribute('aria-pressed', 'true')
    const hoja = screen.getByRole('table', { name: /Proyección de citas por analista/ })
    expect(cabecerasTiempo(hoja)).toEqual(['S1 3–7', 'S2 8–14', 'S3 15–19'])
    await usuario.selectOptions(screen.getByLabelText('Supervisor'), 'sin_supervisor')
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-03/2026-10-19/semanas/equipo/sin_supervisor')
    expect(nombres(hoja)).toEqual(['LVLuis Vega'])
    await usuario.click(tiempo('Días'))
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-03/2026-10-19/dias/equipo/sin_supervisor')
    await usuario.click(atajo('S1'))
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-07/dias/equipo/sin_supervisor')
    await usuario.click(tiempo('Mes'))
    await usuario.selectOptions(screen.getByLabelText('Supervisor'), '')
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-07')
    // Reescribir el enlace no reinicia la pestaña (el oyente reconoce su propia firma).
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–7 oct 2026')
    // Un enlace nuevo desde fuera manda; si su rango pasa de 6 meses, cae al mes de «Hasta».
    act(() => { window.history.replaceState(null, '', '#/reuniones/proyeccion/2026-09-28/2026-10-04/dias'); window.dispatchEvent(new HashChangeEvent('hashchange')) })
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('28 set – 4 oct 2026')
    expect(tiempo('Días')).toHaveAttribute('aria-pressed', 'true')
    act(() => { window.history.replaceState(null, '', '#/reuniones/proyeccion/2026-01-01/2026-10-19'); window.dispatchEvent(new HashChangeEvent('hashchange')) })
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('1–19 oct 2026')
    expect(tiempo('Mes')).toHaveAttribute('aria-pressed', 'true')
    // Otra pestaña: el enlace de Proyección ya no la describe.
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    expect(window.location.hash).toBe('#/reuniones')
    expect(screen.getByRole('tab', { name: 'Agenda' })).toHaveAttribute('aria-selected', 'true')
  })

  it('al entrar desde un enlace de Agenda o sin enlace, la URL pasa a describir la Proyección y sigue sus cambios', async () => {
    // Codex (19/10): con «#/reuniones/mes/…» la URL seguía describiendo la Agenda y al recargar se volvía allí.
    const usuario = userEvent.setup()
    window.history.replaceState(null, '', '#/reuniones/mes/2026-10/equipo/sin_supervisor')
    const vista = render(<ContextoCitas value={fuente}><TableroCitas /></ContextoCitas>)
    expect(screen.getByRole('tab', { name: 'Agenda' })).toHaveAttribute('aria-selected', 'true')
    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-19/equipo/sin_supervisor')
    await usuario.selectOptions(screen.getByLabelText('Supervisor'), '')
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-19')
    await usuario.click(atajo('S3'))
    await usuario.click(tiempo('Días'))
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-15/2026-10-21/dias')
    // Reescribir la URL no reinicia la pestaña.
    expect(screen.getByTestId('pc-rotulo-rango')).toHaveTextContent('15–21 oct 2026')
    vista.unmount()
    // Sin enlace: entrar en la pestaña también la escribe.
    window.history.replaceState(null, '', '#/reuniones')
    render(<ContextoCitas value={fuente}><TableroCitas /></ContextoCitas>)
    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
    expect(window.location.hash).toBe('#/reuniones/proyeccion/2026-10-01/2026-10-19')
  })
})

// Fase 0b: reuniones con clientes sin lead, del lector propio de la Proyección.
describe('Proyección con reuniones con clientes sin lead', () => {
  const OCTUBRE_19 = { desde: '2026-10-01', hasta: '2026-10-19' }
  const reunion = (id: string, cambios: Partial<ReunionClienteProyeccion>): ReunionClienteProyeccion => ({
    id, leadId: null, moneda: null, monto: null, persona: `persona:${id}`, nombre: `CLIENTE ${id.toUpperCase()}`, analista: 'ana', analistaNombre: 'Ana Torres',
    supervisor: 'Claudia Ríos', supervisorId: 'sup-1', fecha: '2026-10-10', hora: '10:00', estado: 'programada', creadoEn: '2026-10-08T15:00:00Z', ...cambios,
  })
  const REUNIONES = [
    reunion('r1', { estado: 'realizada', asistioEn: '2026-10-10T16:00:00Z', nombre: 'CLIENTE UNO' }),
    reunion('r2', { estado: 'no_show', persona: 'oculta:r2', nombre: 'Cliente fuera de tu cartera', creadoEn: '2026-10-11T15:00:00Z' }),
  ]
  const cargador = (cambios: Partial<NonNullable<DatosCitas['proyeccion']>> = {}) => ({ onMesesProyeccion: vi.fn(), onAbrirLead: vi.fn(), proyeccion: {
    meses: ['2026-10'], citas: CITAS, gestion: gestion(), corte: fuente.corte, rango: OCTUBRE_19, reunionesClientes: REUNIONES,
    cargando: false, error: null, onReintentar: vi.fn(), ...cambios } })

  it('cuentan en Citas y Clientes; Monto, Ticket cita, % Entrev., % Conv. y Proyectado quedan los de las citas con lead', async () => {
    const { hoja: sinReuniones, vista } = await abrirProyeccion(cargador({ reunionesClientes: [] }))
    // La señal añade su estado para el lector («60% · Por mejorar»): cuenta la cifra.
    const cifras = (tr: HTMLElement) => within(tr).getAllByRole('cell').slice(1).map(td => td.textContent!.replace(/ · .*$/, ''))
    let ana = fila(sinReuniones, 'Ana Torres')
    expect(cifras(ana)).toEqual(['4', 'S/37,500', 'S/9,375', '66.7%', '50%', 'S/12,500', '1', '0', '3'])
    vista.unmount()
    const { hoja } = await abrirProyeccion(cargador())
    ana = fila(hoja, 'Ana Torres')
    // 4 citas con lead + 2 reuniones = 6 · % Entrev., el de Resultados: 2 ÷ 3, sin las reuniones (20/10/2026) · lo demás, igual.
    expect(cifras(ana)).toEqual(['6', 'S/37,500', 'S/9,375', '66.7%', '50%', 'S/12,500', '1', '2', '3'])
    expect(within(ana).getByRole('button', { name: '6 citas de Ana Torres' })).toBeVisible()
    expect(within(filaTotal(hoja)).getByRole('button', { name: '3 citas con clientes de todos los analistas' })).toBeVisible()
  })

  it('el embudo de Clientes lista estas personas (la redactada con su texto) y la lista lateral las muestra sin ficha, con su CSV', async () => {
    const blobs: Blob[] = []
    const original = { crear: URL.createObjectURL, revocar: URL.revokeObjectURL }
    URL.createObjectURL = vi.fn((blob: Blob) => { blobs.push(blob); return 'blob:proyeccion' })
    URL.revokeObjectURL = vi.fn()
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    try {
      const { usuario, hoja } = await abrirProyeccion(cargador())
      await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Clientes' }))
      const menu = screen.getByRole('dialog', { name: 'Filtrar Clientes' })
      expect(within(menu).getAllByRole('checkbox').map(c => c.getAttribute('aria-label'))).toEqual(
        ['Seleccionar todo', 'Cliente fuera de tu cartera · 1 cita', 'CLIENTE UNO · 1 cita', 'Persona d1 · 1 cita'])
      await usuario.click(within(menu).getByRole('checkbox', { name: 'Persona d1 · 1 cita' }))
      await usuario.click(within(menu).getByRole('checkbox', { name: 'Cliente fuera de tu cartera · 1 cita' }))
      await usuario.click(within(menu).getByRole('button', { name: 'Aplicar' }))
      expect(screen.getByRole('group', { name: 'Filtros de columna' })).toHaveTextContent('Clientes CLIENTE UNO')
      expect(within(filaTotal(hoja)).getByRole('button', { name: '1 cita con cliente de todos los analistas' })).toBeVisible()
      await usuario.click(screen.getByRole('button', { name: 'Quitar filtro de Clientes' }))
      await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '2 citas con clientes de Ana Torres' }))
      const lista = screen.getByRole('dialog', { name: 'Citas con clientes · Ana Torres' })
      expect(within(lista).getAllByRole('row')).toHaveLength(3)
      // Sin lead no hay ficha que abrir: la persona es texto, no botón.
      expect(within(lista).queryByRole('button', { name: 'CLIENTE UNO' })).not.toBeInTheDocument()
      expect(within(lista).getByRole('row', { name: /CLIENTE UNO/ })).toHaveTextContent('Realizada—Cliente')
      expect(within(lista).getByRole('row', { name: /Cliente fuera de tu cartera/ })).toHaveTextContent('No asistió—Cliente')
      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
      const texto = await blobs[0]!.text()
      expect(texto.split('\r\n')[1]).toBe('"r1","2026-10-08","2026-10-10","10:00","CLIENTE UNO","Ana Torres","Claudia Ríos","Realizada","","","","Cliente"')
      await usuario.click(within(lista).getByRole('button', { name: 'Cerrar lista' }))
      // Las citas con lead siguen abriendo su ficha.
      await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '6 citas de Ana Torres' }))
      expect(within(screen.getByRole('dialog', { name: 'Citas · Ana Torres' })).getByRole('button', { name: 'Persona a1' })).toBeVisible()
      expect(within(screen.getByRole('dialog', { name: 'Citas · Ana Torres' })).queryByRole('button', { name: 'CLIENTE UNO' })).not.toBeInTheDocument()
    } finally {
      URL.createObjectURL = original.crear
      URL.revokeObjectURL = original.revocar
      click.mockRestore()
    }
  })

  it('«Citas del periodo» trae exactamente las citas que suma la columna Citas del total, reuniones con clientes incluidas, también tras un embudo', async () => {
    const descargas = capturarDescargas()
    try {
      const { usuario, hoja } = await abrirProyeccion(cargador())
      const total = filaTotal(hoja)
      expect(within(total).getByRole('button', { name: '9 citas de todos los analistas' })).toBeVisible()
      const exportarPeriodo = async () => {
        await usuario.click(screen.getByRole('button', { name: 'Exportar' }))
        await usuario.click(screen.getByRole('menuitem', { name: 'Citas del periodo' }))
        return descargas.filas(descargas.archivos.length - 1)
      }
      const periodo = await exportarPeriodo()
      expect(descargas.archivos[0]!.nombre).toBe('proyeccion-citas-del-periodo-2026-10-01_2026-10-19.csv')
      expect(codigos(periodo).sort()).toEqual(['a1', 'a2', 'a3', 'a4', 'd1', 'd2', 'l1', 'r1', 'r2'])
      expect(periodo.find(f => f.startsWith('"r2"'))).toBe('"r2","2026-10-11","2026-10-10","10:00","Cliente fuera de tu cartera","Ana Torres","Claudia Ríos","No asistió","","","","Cliente"')
      // Las mismas filas, en el mismo orden, que el CSV de la lista detrás de esa cifra.
      await usuario.click(within(total).getByRole('button', { name: '9 citas de todos los analistas' }))
      const lista = screen.getByRole('dialog', { name: 'Citas · Total' })
      await usuario.click(within(lista).getByRole('button', { name: 'Exportar CSV' }))
      expect(await descargas.filas(1)).toEqual(periodo)
      await usuario.click(within(lista).getByRole('button', { name: 'Cerrar lista' }))
      // Un Mín de Citas oculta filas: el total y el CSV del periodo dejan fuera las mismas citas.
      await usuario.click(within(hoja).getByRole('button', { name: 'Filtrar Citas' }))
      await usuario.type(within(screen.getByRole('dialog', { name: 'Filtrar Citas' })).getByRole('spinbutton', { name: 'Mín' }), '3')
      await usuario.click(within(screen.getByRole('dialog', { name: 'Filtrar Citas' })).getByRole('button', { name: 'Aplicar' }))
      expect(within(total).getByRole('button', { name: '6 citas de todos los analistas' })).toBeVisible()
      expect(codigos(await exportarPeriodo()).sort()).toEqual(['a1', 'a2', 'a3', 'a4', 'r1', 'r2'])
      expect(screen.getByText('Se descargaron las 6 citas del periodo.')).toBeVisible()
    } finally { descargas.restaurar() }
  })

  it('pide el rango a la pantalla y, mientras sus reuniones no lleguen o si fallan, no pinta cifras parciales', async () => {
    const pedirRango = vi.fn()
    const datos = { ...cargador({ rango: null }), onRangoProyeccion: pedirRango }
    const usuario = userEvent.setup()
    const vista = render(<ContextoCitas value={{ ...fuente, ...datos }}><TableroCitas /></ContextoCitas>)
    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
    expect(pedirRango).toHaveBeenLastCalledWith(OCTUBRE_19)
    // Las reuniones aún son de otro rango (o de ninguno): espera.
    expect(screen.getByText('Cargando las citas del rango…')).toBeVisible()
    expect(screen.queryByRole('table', { name: /Proyección de citas por analista/ })).not.toBeInTheDocument()
    const rehacer = (cambios: Partial<NonNullable<DatosCitas['proyeccion']>>) =>
      vista.rerender(<ContextoCitas value={{ ...fuente, ...datos, proyeccion: { ...datos.proyeccion, ...cambios } }}><TableroCitas /></ContextoCitas>)
    rehacer({ rango: OCTUBRE_19, cargando: true })
    expect(screen.getByText('Cargando las citas del rango…')).toBeVisible()
    rehacer({ rango: OCTUBRE_19, error: 'El rango es demasiado grande. Acorta las fechas.' })
    expect(screen.getByRole('alert')).toHaveTextContent(/^El rango es demasiado grande\. Acorta las fechas\.Reintentar$/)
    expect(screen.queryByRole('table', { name: /Proyección de citas por analista/ })).not.toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(datos.proyeccion.onReintentar).toHaveBeenCalledTimes(1)
    rehacer({ rango: OCTUBRE_19 })
    expect(within(fila(screen.getByRole('table', { name: /Proyección de citas por analista/ }), 'Ana Torres')).getByRole('button', { name: '6 citas de Ana Torres' })).toBeVisible()
    await usuario.click(atajo('S3'))
    expect(pedirRango).toHaveBeenLastCalledWith({ desde: '2026-10-15', hasta: '2026-10-21' })
    expect(screen.getByText('Cargando las citas del rango…')).toBeVisible()
    await usuario.click(screen.getByRole('tab', { name: 'Agenda' }))
    expect(pedirRango).toHaveBeenLastCalledWith(null)
  })
})

// Fase 3: en el celular (< 768 px) la hoja se vuelve tarjetas, con el mismo estado (orden, embudos y listas).
describe('Proyección en el celular: tarjetas', () => {
  /** Ancho simulado de la ventana: cada `max-width` se resuelve contra él. */
  let ancho = 390
  beforeEach(() => {
    ancho = 390
    vi.stubGlobal('matchMedia', (consulta: string) => {
      const maximo = /max-width: (\d+)px/.exec(consulta)
      return { matches: maximo ? ancho <= Number(maximo[1]) : consulta.includes('prefers-reduced-motion'), media: consulta,
        addEventListener: () => {}, removeEventListener: () => {} }
    })
  })
  afterEach(() => { vi.unstubAllGlobals() })

  async function abrirTarjetas() {
    const usuario = userEvent.setup()
    render(<ContextoCitas value={fuente}><TableroCitas /></ContextoCitas>)
    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
    return { usuario, lista: screen.getByRole('list', { name: 'Proyección de citas por analista · 1–19 oct 2026' }) }
  }
  const tarjetas = (lista: HTMLElement) => within(lista).getAllByRole('listitem')
  const nombresTarjetas = (lista: HTMLElement) => tarjetas(lista).map(t => t.querySelector('.pc-tarjeta-nombre')!.textContent)
  const tarjeta = (lista: HTMLElement, nombre: string) => tarjetas(lista).find(t => t.querySelector('.pc-tarjeta-nombre')!.textContent === nombre)!
  const filtros = () => screen.getByRole('button', { name: /^Filtros/ })
  /** La lista lateral en el celular: una tarjeta por cita. */
  const citasDe = (detalle: HTMLElement) => within(within(detalle).getByRole('list')).getAllByRole('listitem')
  const citaDe = (detalle: HTMLElement, persona: string) => citasDe(detalle).find(li => li.querySelector('.pc-persona')!.textContent === persona)!

  it('una tarjeta por analista en el orden de la hoja, con el Total primero; cada cifra es botón (salvo ceros y «—») y abre la misma lista', async () => {
    const { usuario, lista } = await abrirTarjetas()
    expect(screen.queryByRole('table', { name: /Proyección de citas por analista/ })).not.toBeInTheDocument()
    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Ana Torres', 'Diego Salas', 'Luis Vega'])
    const ana = tarjeta(lista, 'Ana Torres')
    expect(ana.querySelector('.pc-tarjeta-sup')).toHaveTextContent('Claudia Ríos')
    expect(within(ana).getAllByRole('term').map(dt => dt.textContent)).toEqual(
      ['Citas', 'Monto', 'Ticket cita', '% Entrev.', '% Conv.', 'Proyectado citas', 'Referidos', 'Clientes', 'Leads'])
    for (const t of tarjetas(lista)) {
      for (const par of t.querySelectorAll<HTMLElement>('dl > div')) {
        const texto = within(par).getByRole('definition').textContent!.trim().replace(/ · .*$/, '')
        const sinValor = ['0', '—', '0%'].includes(texto)
        expect(within(par).queryByRole('button') !== null, `${t.textContent} · ${par.dataset.col}`).toBe(!sinValor)
      }
    }
    // El semáforo de % Entrev. y % Conv. se conserva.
    expect(within(ana).getByRole('button', { name: /^% Entrev\. de Ana Torres: 66\.7%/ })).toHaveAttribute('data-senal')
    expect(ana.querySelector('[data-col="ticket"] dd')).toHaveTextContent('S/9,375')
    await usuario.click(within(ana).getByRole('button', { name: '4 citas de Ana Torres' }))
    let detalle = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
    expect(within(detalle).getByTestId('pc-detalle-conteo')).toHaveTextContent('1–19 oct 2026 · 4 citas')
    // La lista lateral también es de tarjetas: una por cita, sin tabla que deslizar de lado.
    expect(within(detalle).queryByRole('table')).not.toBeInTheDocument()
    expect(citasDe(detalle)).toHaveLength(4)
    await usuario.click(within(detalle).getByRole('button', { name: 'Cerrar lista' }))
    const total = tarjeta(lista, 'Total · 3 analistas')
    await usuario.click(within(total).getByRole('button', { name: '1 cita con cliente de todos los analistas' }))
    detalle = screen.getByRole('dialog', { name: 'Citas con clientes · Total' })
    expect(citaDe(detalle, 'Persona d1')).toHaveTextContent('Diego Salas')
    await usuario.keyboard('{Escape}')
    await usuario.click(within(ana).getByRole('button', { name: /^% Conv\. de Ana Torres: 50%/ }))
    expect(citasDe(screen.getByRole('dialog', { name: 'Entrevistas que cerraron cliente · Ana Torres' }))).toHaveLength(1)
  })

  it('la lista lateral pinta una tarjeta por cita con los mismos datos de la tabla y la persona abre su ficha', async () => {
    const onAbrirLead = vi.fn()
    const usuario = userEvent.setup()
    render(<ContextoCitas value={{ ...fuente, onAbrirLead }}><TableroCitas /></ContextoCitas>)
    await usuario.click(screen.getByRole('tab', { name: 'Proyección' }))
    const lista = screen.getByRole('list', { name: 'Proyección de citas por analista · 1–19 oct 2026' })
    await usuario.click(within(tarjeta(lista, 'Total · 3 analistas')).getByRole('button', { name: '7 citas de todos los analistas' }))
    const detalle = screen.getByRole('dialog', { name: 'Citas · Total' })
    expect(within(detalle).getByRole('list', { name: 'Citas · Total' })).toBeVisible()
    // El mismo orden que la tabla: por fecha y hora de la cita (aquí todas a la misma hora, así que por código), no el de llegada.
    expect(citasDe(detalle).map(li => li.querySelector('.pc-persona')!.textContent)).toEqual(
      ['Persona a1', 'Persona a2', 'Persona a3', 'Persona a4', 'Persona d1', 'Persona d2', 'Persona l1'])
    // Los mismos datos que la fila de la tabla, en el mismo orden; con varios analistas, también el analista.
    const a2 = citaDe(detalle, 'Persona a2')
    expect(within(a2).getAllByRole('term').map(dt => dt.textContent)).toEqual(['Creada', 'Cita', 'Analista', 'Estado', 'Monto'])
    expect(within(a2).getAllByRole('definition').map(dd => dd.textContent)).toEqual(['03 oct. 2026', '10 oct. 2026 · 10:00', 'Ana Torres', 'Realizada', 'US$ 2,000 ·S/ 7,500'])
    expect(a2.querySelector('.pc-origen')).toHaveTextContent('Lead')
    expect(citaDe(detalle, 'Persona a3').querySelector('.pc-origen')).toHaveTextContent('Referido')
    expect(within(citaDe(detalle, 'Persona a4')).getAllByRole('definition').at(-1)).toHaveTextContent('—')
    await usuario.click(within(a2).getByRole('button', { name: 'Persona a2' }))
    await vi.waitFor(() => expect(onAbrirLead).toHaveBeenCalledWith('lead-a2', 'a2'))
    expect(screen.queryByRole('dialog', { name: 'Citas · Total' })).not.toBeInTheDocument()
    // La lista de un solo analista no repite su nombre en cada tarjeta.
    await usuario.click(within(tarjeta(lista, 'Ana Torres')).getByRole('button', { name: '4 citas de Ana Torres' }))
    expect(within(citaDe(screen.getByRole('dialog', { name: 'Citas · Ana Torres' }), 'Persona a1')).getAllByRole('term').map(dt => dt.textContent)).toEqual(['Creada', 'Cita', 'Estado', 'Monto'])
  })

  it('en una tablet la hoja sigue siendo tabla, pero su lista lateral usa tarjetas hasta 1 079 px porque la tabla no cabe en el panel', async () => {
    for (const [px, enTarjetas] of [[900, true], [1079, true], [1080, false], [1440, false]] as const) {
      cleanup()
      ancho = px
      const { usuario, hoja } = await abrirProyeccion()
      await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: '4 citas de Ana Torres' }))
      const detalle = screen.getByRole('dialog', { name: 'Citas · Ana Torres' })
      if (enTarjetas) {
        expect(within(detalle).queryByRole('table'), `${px} px`).not.toBeInTheDocument()
        expect(citasDe(detalle), `${px} px`).toHaveLength(4)
      } else {
        expect(within(detalle).getAllByRole('row'), `${px} px`).toHaveLength(5)
      }
    }
  })

  it('«Ordenar por» y «Filtros» usan el mismo orden y los mismos embudos de la hoja', async () => {
    const { usuario, lista } = await abrirTarjetas()
    const ordenar = screen.getByRole('combobox', { name: 'Ordenar por' })
    expect(ordenar).toHaveValue('citas')
    const sentido = screen.getByRole('button', { name: 'Orden de mayor a menor' })
    await usuario.selectOptions(ordenar, 'ticket')
    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Diego Salas', 'Ana Torres', 'Luis Vega'])
    await usuario.click(sentido)
    expect(sentido).toHaveAccessibleName('Orden de menor a mayor')
    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Luis Vega', 'Ana Torres', 'Diego Salas'])
    await usuario.selectOptions(ordenar, 'analista')
    expect(sentido).toHaveAccessibleName('Orden de A a Z')
    expect(nombresTarjetas(lista)).toEqual(['Total · 3 analistas', 'Ana Torres', 'Diego Salas', 'Luis Vega'])

    // Filtros: las mismas columnas que tienen embudo en la hoja; cada una abre su embudo.
    await usuario.click(filtros())
    expect(screen.getAllByRole('menuitem').map(item => item.textContent)).toEqual(
      ['Analista', 'Citas', 'Monto', 'Ticket cita', '% Entrev.', '% Conv.', 'Proyectado citas', 'Referidos', 'Clientes', 'Leads'])
    await usuario.click(screen.getByRole('menuitem', { name: 'Analista' }))
    let embudo = screen.getByRole('dialog', { name: 'Filtrar Analista' })
    expect(within(embudo).getByRole('searchbox', { name: 'Buscar analista' })).toHaveFocus()
    await usuario.click(within(embudo).getByRole('checkbox', { name: 'Luis Vega · 1 cita' }))
    await usuario.click(within(embudo).getByRole('button', { name: 'Aplicar' }))
    expect(nombresTarjetas(lista)).toEqual(['Total · 2 analistas', 'Ana Torres', 'Diego Salas'])
    expect(screen.getByRole('group', { name: 'Filtros de columna' })).toHaveTextContent('Analista Ana Torres, Diego Salas')
    // El embudo se ancla a «Filtros»: al cerrarse, el foco vuelve ahí, que ya cuenta el filtro.
    expect(filtros()).toHaveFocus()
    expect(filtros()).toHaveAccessibleName('Filtros, 1 con filtro')
    await usuario.click(filtros())
    expect(screen.getByRole('menuitem', { name: 'Analista, con filtro' })).toBeVisible()
    await usuario.keyboard('{Escape}')
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
    expect(filtros()).toHaveFocus()
    // Sin cabeceras, quitar el chip devuelve el foco a «Filtros», no a <body>.
    await usuario.click(screen.getByRole('button', { name: 'Quitar filtro de Analista' }))
    expect(nombresTarjetas(lista)).toHaveLength(4)
    expect(filtros()).toHaveFocus()
    expect(filtros()).toHaveAccessibleName('Filtros')

    await usuario.click(filtros())
    await usuario.click(screen.getByRole('menuitem', { name: 'Clientes' }))
    embudo = screen.getByRole('dialog', { name: 'Filtrar Clientes' })
    expect(within(embudo).getAllByRole('checkbox').map(c => c.getAttribute('aria-label'))).toEqual(['Seleccionar todo', 'Persona d1 · 1 cita'])
    await usuario.keyboard('{Escape}')
    expect(filtros()).toHaveFocus()
    await usuario.click(filtros())
    await usuario.click(screen.getByRole('menuitem', { name: 'Monto' }))
    embudo = screen.getByRole('dialog', { name: 'Filtrar Monto S/' })
    await usuario.click(within(embudo).getByRole('checkbox', { name: 'Soles · S/ 115,000 · 6 citas' }))
    await usuario.click(within(embudo).getByRole('button', { name: 'Aplicar' }))
    expect(nombresTarjetas(lista)).toEqual(['Total · 1 analista', 'Ana Torres'])
    expect(within(tarjeta(lista, 'Ana Torres')).getByRole('button', { name: 'S/ 7,500 en citas de Ana Torres' })).toBeVisible()
  })

  it('Semanas y Días: los tramos van en una fila de la tarjeta, cada número abre su lista; Exportar sigue en la barra', async () => {
    const { usuario, lista } = await abrirTarjetas()
    expect(lista.querySelectorAll('.pc-tarjeta-tramos')).toHaveLength(0)
    await usuario.click(tiempo('Semanas'))
    const ana = tarjeta(lista, 'Ana Torres')
    const semanas = within(ana).getByRole('group', { name: 'Citas por semana de Ana Torres' })
    expect([...semanas.querySelectorAll('.sr-only')].map(e => e.textContent)).toEqual(['S1 1–7 oct', 'S2 8–14 oct', 'S3 15–19 oct'])
    expect([...semanas.querySelectorAll('.pc-n')].map(e => e.textContent)).toEqual(['3', '1', '0'])
    expect(within(tarjeta(lista, 'Total · 3 analistas')).getByRole('group', { name: 'Citas por semana de todos los analistas' })).toBeVisible()
    await usuario.click(within(semanas).getByRole('button', { name: '1 cita de Ana Torres, S2 8–14 oct' }))
    const detalle = screen.getByRole('dialog', { name: 'Citas · S2 8–14 oct · Ana Torres' })
    expect(citaDe(detalle, 'Persona a4')).toBeVisible()
    await usuario.keyboard('{Escape}')
    await usuario.click(tiempo('Días'))
    const dias = within(tarjeta(lista, 'Luis Vega')).getByRole('group', { name: 'Citas por día de Luis Vega' })
    expect(dias.querySelectorAll('.pc-tiempo')).toHaveLength(19)
    expect(dias.querySelector('.pc-hoy .sr-only')).toHaveTextContent('lun 19 oct')
    expect(within(dias).getByRole('button', { name: '1 cita de Luis Vega, 18 oct' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Exportar' })).toBeEnabled()
  })
})

describe('Proyección: Ticket cita y Proyectado citas abren su base', () => {
  it('abren la lista de las citas con lead de la fila (sin las reuniones con clientes sin lead)', async () => {
    const { usuario, hoja } = await abrirProyeccion()
    await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: /de ticket cita de Ana Torres$/ }))
    let lista = screen.getByRole('dialog', { name: 'Citas con lead · Ana Torres' })
    expect(within(lista).getByTestId('pc-detalle-conteo')).toHaveTextContent('· 4 citas')
    await usuario.keyboard('{Escape}')
    await usuario.click(within(fila(hoja, 'Ana Torres')).getByRole('button', { name: /proyectado en citas de Ana Torres$/ }))
    lista = screen.getByRole('dialog', { name: 'Citas con lead · Ana Torres' })
    expect(within(lista).getAllByRole('row')).toHaveLength(5)
  })
})
