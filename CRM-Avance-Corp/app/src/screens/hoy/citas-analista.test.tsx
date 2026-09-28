// «Tus citas» v2 (Hoy · analista): la partición pura (cifras, ventana de 7
// días, filas de cada filtro, selección inicial) y la ficha montada con un
// reloj FIJO —miércoles 2026-07-15 10:00 en Lima— para que hoy/mañana/semana
// no dependan de cuándo corre la suite.
import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { agendaDeTareas } from '@/lib/agenda-derivada'
import { money } from '@/lib/format'
import type { Lead, Tarea } from '@/lib/tipos'
import { CitasAnalista } from './citas-analista'
import {
  filasDelFiltro,
  filtroInicial,
  filtroVigente,
  particionarCitas,
  type FiltroCitas,
} from './citas-analista-particion'

/** Miércoles 2026-07-15, 10:00 en Lima (UTC-5). */
const MIERCOLES_10AM = Date.parse('2026-07-15T15:00:00Z')
/** Domingo 2026-07-19, 10:00 en Lima. */
const DOMINGO_10AM = Date.parse('2026-07-19T15:00:00Z')
const DIA_MS = 86_400_000

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'l-1',
    nombre_completo: 'ANA TORRES',
    telefono: '+51987654321',
    etapa: 'contactado',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: '2026-07-01T15:00:00Z',
    activo: true,
    ...over,
  }
}

function cita(over: Partial<Tarea> = {}): Tarea {
  return {
    id: 'c-1',
    lead_id: 'l-1',
    tipo: 'reunion',
    titulo: 'Cita con Ana',
    vence_en: '2026-07-15T20:00:00Z',
    estado: 'pendiente',
    reprogramaciones: 0,
    activo: true,
    creado_en: '2026-07-10T15:00:00Z',
    ...over,
  }
}

const LEADS = [lead(), lead({ id: 'l-2', nombre_completo: 'BRUNO DÍAZ', monto_estimado: 25_000 })]

/** Las seis citas de la partición canónica (reloj: miércoles 15 a las 10:00):
 * lunes vencida · miércoles 09:00 (vencida) · miércoles 15:00 · jueves ·
 * viernes · miércoles siguiente. Desordenadas a propósito. */
const SEIS = [
  cita({ id: 'c-mie-sig', lead_id: 'l-2', titulo: 'Cita lejana con Bruno', vence_en: '2026-07-22T15:00:00Z' }),
  cita({ id: 'c-vie', lead_id: 'l-2', titulo: 'Cita con Bruno', vence_en: '2026-07-17T15:00:00Z', modalidad_reunion: 'virtual', enlace_reunion: 'https://meet.google.com/abc-defg' }),
  cita({ id: 'c-mie-15', titulo: 'Cita con Ana', vence_en: '2026-07-15T20:00:00Z', modalidad_reunion: 'presencial', ubicacion_reunion: 'Of. San Isidro' }),
  cita({ id: 'c-jue', lead_id: null, perfil_id: 'cliente-1', vendedor_id: 'v-1', titulo: 'Cita con Rosa', vence_en: '2026-07-16T15:00:00Z' }),
  cita({ id: 'c-mie-9', titulo: 'Cita temprana con Ana', vence_en: '2026-07-15T14:00:00Z' }),
  cita({ id: 'c-lun', titulo: 'Cita pendiente con Ana', vence_en: '2026-07-13T15:00:00Z', modalidad_reunion: 'sin_clasificar' }),
]

const abrirLead = vi.fn()
const onCompletar = vi.fn()

function montar(
  tareas: Tarea[],
  over: { ahora?: number; disposicion?: 'columna' | 'libre'; leads?: Lead[] } = {},
): ReturnType<typeof render> {
  abrirLead.mockClear()
  onCompletar.mockClear()
  const ahora = over.ahora ?? MIERCOLES_10AM
  const leads = over.leads ?? LEADS
  const base = {
    // Como la pantalla: solo las reuniones son citas (una llamada no lo es).
    citas: agendaDeTareas(tareas.filter((t) => t.tipo === 'reunion'), ahora),
    tareaPorId: new Map(tareas.map((t) => [t.id, t] as const)),
    leadPorId: (id: string) => leads.find((l) => l.id === id),
    abrirLead,
    onCompletar,
    ahora,
  }
  return over.disposicion
    ? render(<CitasAnalista {...base} disposicion={over.disposicion} />)
    : render(<CitasAnalista {...base} />)
}

/** Texto literal como RegExp (el «S/ 10,000» de money lleva barra y coma). */
function literal(texto: string): RegExp {
  return new RegExp(texto.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&'))
}

function panel(): HTMLElement {
  const tarjeta = screen.getByRole('heading', { name: 'Tus citas' }).closest('[data-slot="card"]')
  if (!(tarjeta instanceof HTMLElement)) throw new Error('sin tarjeta «Tus citas»')
  return tarjeta
}

/** Los ids de las filas pintadas, en orden (una fila = un botón «Cerrar tarea»). */
function idsPintados(tareas: Tarea[]): string[] {
  const porTitulo = new Map(tareas.map((t) => [t.titulo, t.id] as const))
  return within(panel())
    .getAllByRole('button', { name: /^Cerrar tarea — / })
    .map((b) => porTitulo.get(b.getAttribute('aria-label')?.replace('Cerrar tarea — ', '') ?? '') ?? '?')
}

function rotulos(): string[] {
  return within(panel()).queryAllByRole('heading', { level: 4 }).map((h) => h.textContent ?? '')
}

function chip(nombre: RegExp | string): HTMLElement {
  return within(panel()).getByRole('button', { name: nombre })
}

function tira(): HTMLElement {
  return within(panel()).getByRole('group', { name: 'Próximos 7 días' })
}

describe('«Tus citas» — partición pura', () => {
  it('miércoles 10:00: Vencidas 2 · Hoy 1 · Mañana 1 · Semana 3 · Todas 6, con sus ids', () => {
    const p = particionarCitas(agendaDeTareas(SEIS, MIERCOLES_10AM), MIERCOLES_10AM)
    expect([p.nVencidas, p.nHoy, p.nManana, p.nSemana, p.nTodas]).toEqual([2, 1, 1, 3, 6])
    const ids = (f: FiltroCitas) => filasDelFiltro(p, f).map((ev) => ev.id)
    // La de las 09:00 de HOY ya venció: es vencida, no «hoy».
    expect(ids('vencidas')).toEqual(['c-lun', 'c-mie-9'])
    expect(ids('hoy')).toEqual(['c-mie-15'])
    expect(ids('manana')).toEqual(['c-jue'])
    // La semana NO mete vencidas ni el miércoles siguiente (hoy+7).
    expect(ids('semana')).toEqual(['c-mie-15', 'c-jue', 'c-vie'])
    expect(ids('todas')).toEqual(['c-lun', 'c-mie-9', 'c-mie-15', 'c-jue', 'c-vie', 'c-mie-sig'])
    expect(ids('dia:2026-07-17')).toEqual(['c-vie'])
    expect(ids('dia:2026-07-18')).toEqual([])
    expect(p.hoy).toBe('2026-07-15')
    expect(p.manana).toBe('2026-07-16')
  })

  it('la tira son 7 fechas seguidas desde hoy, con el nombre de cada una (miércoles y domingo)', () => {
    const desdeMiercoles = particionarCitas(agendaDeTareas(SEIS, MIERCOLES_10AM), MIERCOLES_10AM).tira
    expect(desdeMiercoles.map((d) => d.fecha)).toEqual([
      '2026-07-15', '2026-07-16', '2026-07-17', '2026-07-18', '2026-07-19', '2026-07-20', '2026-07-21',
    ])
    expect(desdeMiercoles.map((d) => `${d.dia} ${d.numero}`)).toEqual([
      'Mié 15', 'Jue 16', 'Vie 17', 'Sáb 18', 'Dom 19', 'Lun 20', 'Mar 21',
    ])
    expect(desdeMiercoles.map((d) => d.n)).toEqual([1, 1, 1, 0, 0, 0, 0])
    expect(desdeMiercoles.map((d) => d.esHoy)).toEqual([true, false, false, false, false, false, false])

    const desdeDomingo = particionarCitas(agendaDeTareas(SEIS, DOMINGO_10AM), DOMINGO_10AM).tira
    expect(desdeDomingo.map((d) => `${d.fecha} ${d.dia}`)).toEqual([
      '2026-07-19 Dom', '2026-07-20 Lun', '2026-07-21 Mar', '2026-07-22 Mié', '2026-07-23 Jue', '2026-07-24 Vie', '2026-07-25 Sáb',
    ])
    // Desde el domingo el miércoles 22 ya entra en la semana; el resto venció.
    expect(desdeDomingo.map((d) => d.n)).toEqual([0, 0, 0, 1, 0, 0, 0])
  })

  it('selección inicial: la semana si tiene citas; si no, todas; y un día fuera de la ventana vuelve a la semana', () => {
    const conSemana = particionarCitas(agendaDeTareas(SEIS, MIERCOLES_10AM), MIERCOLES_10AM)
    expect(filtroInicial(conSemana)).toBe('semana')
    const soloLejana = particionarCitas(agendaDeTareas([SEIS[0]!], MIERCOLES_10AM), MIERCOLES_10AM)
    expect(filtroInicial(soloLejana)).toBe('todas')
    const soloVencidas = particionarCitas(agendaDeTareas([SEIS[4]!, SEIS[5]!], MIERCOLES_10AM), MIERCOLES_10AM)
    expect(filtroInicial(soloVencidas)).toBe('todas')
    const nada = particionarCitas([], MIERCOLES_10AM)
    expect(filtroInicial(nada)).toBe('todas')
    expect(nada.nTodas).toBe(0)

    expect(filtroVigente('dia:2026-07-17', conSemana)).toBe('dia:2026-07-17')
    // Pasó la medianoche del martes 21: el viernes 17 ya no está en la ventana.
    const semanaSiguiente = particionarCitas(agendaDeTareas(SEIS, MIERCOLES_10AM + 7 * DIA_MS), MIERCOLES_10AM + 7 * DIA_MS)
    expect(filtroVigente('dia:2026-07-17', semanaSiguiente)).toBe('semana')
    expect(filtroVigente('hoy', semanaSiguiente)).toBe('hoy')
  })
})

describe('«Tus citas» — la ficha', () => {
  it('arranca en «Semana», agrupada por día, sin vencidas ni lo posterior a hoy+6; «Todas» lo incluye con las vencidas primero', () => {
    montar(SEIS)
    expect(chip('Semana 3')).toHaveAttribute('aria-pressed', 'true')
    expect(chip('Todas 6')).toHaveAttribute('aria-pressed', 'false')
    expect(rotulos()).toEqual(['Hoy · Mié 15', 'Mañana · Jue 16', 'Vie 17'])
    expect(idsPintados(SEIS)).toEqual(['c-mie-15', 'c-jue', 'c-vie'])

    fireEvent.click(chip('Todas 6'))
    expect(chip('Todas 6')).toHaveAttribute('aria-pressed', 'true')
    expect(chip('Semana 3')).toHaveAttribute('aria-pressed', 'false')
    expect(rotulos()).toEqual(['Vencidas', 'Hoy · Mié 15', 'Mañana · Jue 16', 'Vie 17', 'Mié 22 Jul'])
    expect(idsPintados(SEIS)).toEqual(['c-lun', 'c-mie-9', 'c-mie-15', 'c-jue', 'c-vie', 'c-mie-sig'])
  })

  it('el total de la cabecera es un botón que abre «Todas» (todo número se abre)', () => {
    montar(SEIS)
    const total = chip('6 agendadas · 2 vencidas')
    expect(total).toHaveAttribute('aria-pressed', 'false')
    fireEvent.click(total)
    expect(total).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toHaveLength(6)
  })

  it('«Hoy», «Mañana» y las vencidas filtran, y las vencidas solo salen con «Vencidas» o «Todas»', () => {
    montar(SEIS)
    fireEvent.click(chip('Hoy 1'))
    expect(chip('Hoy 1')).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toEqual(['c-mie-15'])
    expect(rotulos()).toEqual(['Hoy · Mié 15'])

    fireEvent.click(chip('Mañana 1'))
    expect(idsPintados(SEIS)).toEqual(['c-jue'])

    fireEvent.click(chip('⚠ 2 vencidas'))
    expect(chip('⚠ 2 vencidas')).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toEqual(['c-lun', 'c-mie-9'])
    expect(rotulos()).toEqual(['Vencidas'])
    expect(within(panel()).getAllByText('Vencida')).toHaveLength(2)

    fireEvent.click(chip('Semana 3'))
    expect(within(panel()).queryByText('Vencida')).not.toBeInTheDocument()
  })

  it('la tira cuenta las citas de cada día, marca hoy y filtra por día (segundo clic vuelve a la semana)', () => {
    montar(SEIS)
    const celdas = within(tira()).getAllByRole('button')
    expect(celdas.map((c) => c.getAttribute('aria-label'))).toEqual([
      'Miércoles 15, 1 cita',
      'Jueves 16, 1 cita',
      'Viernes 17, 1 cita',
      'Sábado 18, sin citas',
      'Domingo 19, sin citas',
      'Lunes 20, sin citas',
      'Martes 21, sin citas',
    ])
    expect(celdas.map((c) => c.getAttribute('aria-current'))).toEqual(['date', null, null, null, null, null, null])
    expect(celdas.map((c) => c.getAttribute('aria-pressed'))).toEqual(Array<string>(7).fill('false'))
    // Cifras visibles con el mismo criterio que el chip «Hoy» (no vencidas).
    expect(celdas.map((c) => c.textContent)).toEqual(['Mié151', 'Jue161', 'Vie171', 'Sáb180', 'Dom190', 'Lun200', 'Mar210'])

    const jueves = within(tira()).getByRole('button', { name: 'Jueves 16, 1 cita' })
    fireEvent.click(jueves)
    expect(jueves).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toEqual(['c-jue'])
    expect(rotulos()).toEqual(['Mañana · Jue 16'])
    expect(chip('Semana 3')).toHaveAttribute('aria-pressed', 'false')

    fireEvent.click(jueves)
    expect(jueves).toHaveAttribute('aria-pressed', 'false')
    expect(chip('Semana 3')).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toHaveLength(3)
  })

  it('un día explícito que sale de la ventana (pasó la medianoche) vuelve solo a «Semana»', () => {
    const vista = montar(SEIS)
    fireEvent.click(within(tira()).getByRole('button', { name: 'Jueves 16, 1 cita' }))
    expect(idsPintados(SEIS)).toEqual(['c-jue'])

    const ahora = MIERCOLES_10AM + 7 * DIA_MS
    vista.rerender(
      <CitasAnalista
        citas={agendaDeTareas(SEIS, ahora)}
        tareaPorId={new Map(SEIS.map((t) => [t.id, t] as const))}
        leadPorId={(id) => LEADS.find((l) => l.id === id)}
        abrirLead={abrirLead}
        onCompletar={onCompletar}
        ahora={ahora}
      />,
    )
    // Miércoles 22: solo la «lejana» sigue viva en la semana; el resto venció.
    expect(chip('Semana 1')).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toEqual(['c-mie-sig'])
  })

  it('nombre del lead resuelto; título de la tarea para clientes (con badge) y leads ausentes; nunca se inventa', () => {
    montar(SEIS, { leads: [LEADS[0]!] })
    fireEvent.click(chip('Todas 6'))
    const p = panel()
    expect(within(p).getAllByText('ANA TORRES')).toHaveLength(3)
    // Bruno no está en la cartera cargada: se ve el título de su cita, no un nombre inventado.
    expect(within(p).queryByText('BRUNO DÍAZ')).not.toBeInTheDocument()
    expect(within(p).getByText('Cita con Bruno')).toBeInTheDocument()
    expect(within(p).getByText('Cita lejana con Bruno')).toBeInTheDocument()
    // Cliente de cartera: título + badge «Cliente».
    expect(within(p).getByText('Cita con Rosa')).toBeInTheDocument()
    expect(within(p).getAllByText('Cliente')).toHaveLength(1)
  })

  it('la modalidad es un icono con nombre accesible (ninguno para sin_clasificar) y va en la descripción de la fila', () => {
    montar(SEIS)
    fireEvent.click(chip('Todas 6'))
    const p = panel()
    expect(within(p).getByRole('img', { name: 'Presencial' })).toHaveAttribute('title', 'Presencial')
    expect(within(p).getByRole('img', { name: 'Virtual' })).toBeInTheDocument()
    expect(within(p).getAllByRole('img')).toHaveLength(2)
    expect(within(p).queryByText(/^(Presencial|Virtual)$/)).not.toBeInTheDocument()
    const fila = within(p).getByRole('button', { name: 'Abrir ficha — Cita con Ana, 15:00' })
    expect(fila).toHaveAccessibleDescription(/15:00/)
    expect(fila).toHaveAccessibleDescription(/Hoy/)
    expect(fila).toHaveAccessibleDescription(/Presencial/)
    expect(fila).toHaveAccessibleDescription(/Of\. San Isidro/)
    expect(fila).toHaveAccessibleDescription(literal(money(10_000)))
  })

  it('lugar: la ubicación si es presencial; el host del enlace si es virtual; texto recortado si no es URL; ubicación de respaldo sin enlace', () => {
    const tareas = [
      cita({ id: 'p', titulo: 'Presencial con Ana', vence_en: '2026-07-16T15:00:00Z', modalidad_reunion: 'presencial', ubicacion_reunion: 'Of. San Isidro', enlace_reunion: 'https://ignorado.example' }),
      cita({ id: 'v', titulo: 'Virtual con Ana', vence_en: '2026-07-16T16:00:00Z', modalidad_reunion: 'virtual', enlace_reunion: 'https://meet.google.com/abc-defg' }),
      cita({ id: 'z', titulo: 'Zoom con Ana', vence_en: '2026-07-16T17:00:00Z', modalidad_reunion: 'virtual', enlace_reunion: 'Zoom' }),
      cita({ id: 'r', titulo: 'Respaldo con Ana', vence_en: '2026-07-16T18:00:00Z', modalidad_reunion: 'virtual', ubicacion_reunion: 'Miraflores' }),
      cita({ id: 's', titulo: 'Sin dato con Ana', vence_en: '2026-07-16T19:00:00Z' }),
    ]
    montar(tareas)
    const p = panel()
    expect(within(p).getByText('Of. San Isidro')).toBeInTheDocument()
    expect(within(p).queryByText(/ignorado/)).not.toBeInTheDocument()
    expect(within(p).getByText('meet.google.com')).toBeInTheDocument()
    expect(within(p).getByText('Zoom')).toBeInTheDocument()
    expect(within(p).getByText('Miraflores')).toBeInTheDocument()
    const sinDato = within(p).getByRole('button', { name: 'Abrir ficha — Sin dato con Ana, 14:00' })
    expect(sinDato).toHaveAccessibleDescription(/14:00/)
    expect(sinDato).toHaveAccessibleDescription(/Mañana/)
    expect(sinDato).toHaveAccessibleDescription(literal(money(10_000)))
    expect(sinDato).not.toHaveAccessibleDescription(/Presencial|Virtual|meet|Zoom|Miraflores/)
  })

  it('cada fila lleva su capital; dos citas del mismo lead lo repiten fila a fila y NADA lo suma (el pie no trae importes)', () => {
    montar(SEIS)
    fireEvent.click(chip('Todas 6'))
    const p = panel()
    // Bruno tiene dos citas → dos filas con S/ 25,000; Ana tres → tres con S/ 10,000.
    expect(within(p).getAllByText(money(25_000))).toHaveLength(2)
    expect(within(p).getAllByText(money(10_000))).toHaveLength(3)
    // Ningún total: ni 50,000 (Bruno ×2), ni 55,000, ni «en juego».
    expect(within(p).queryByText(/50,000|55,000|en juego/)).not.toBeInTheDocument()
  })

  it('el pie es «Semana: N citas» como botón que activa la semana, más la salida a Agenda', () => {
    montar(SEIS)
    fireEvent.click(chip('Hoy 1'))
    const pie = chip('Semana: 3 citas')
    expect(pie).toHaveAttribute('aria-pressed', 'false')
    fireEvent.click(pie)
    expect(pie).toHaveAttribute('aria-pressed', 'true')
    expect(chip('Semana 3')).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toHaveLength(3)
    expect(within(panel()).getByRole('link', { name: 'Ver en Agenda ›' })).toHaveAttribute('href', '#/agenda')
  })

  it('«Cerrar tarea» cierra sin abrir la ficha (ni con Enter); Enter/Espacio sobre la fila sí la abre; el cliente sin ficha no es botón', () => {
    montar(SEIS)
    const p = panel()
    const fila = within(p).getByRole('button', { name: 'Abrir ficha — Cita con Ana, 15:00' })
    const cerrar = within(p).getByRole('button', { name: 'Cerrar tarea — Cita con Ana' })
    fireEvent.keyDown(cerrar, { key: 'Enter' })
    expect(abrirLead).not.toHaveBeenCalled()
    fireEvent.click(cerrar)
    expect(onCompletar).toHaveBeenCalledWith('c-mie-15')
    expect(abrirLead).not.toHaveBeenCalled()

    fireEvent.keyDown(fila, { key: 'Enter' })
    fireEvent.keyDown(fila, { key: ' ' })
    fireEvent.click(fila)
    expect(abrirLead).toHaveBeenCalledTimes(3)
    expect(abrirLead).toHaveBeenCalledWith('l-1')

    // La cita con un cliente de cartera (perfil) no abre ficha de lead: sin role=button.
    expect(within(p).queryByRole('button', { name: /^Abrir ficha — Cita con Rosa/ })).not.toBeInTheDocument()
    expect(within(p).getByRole('button', { name: 'Cerrar tarea — Cita con Rosa' })).toBeInTheDocument()
  })

  it('colores por estado, sin el violeta de la reunión: ámbar (texto oscuro) vencida, azul hoy, navy el resto', () => {
    montar(SEIS)
    fireEvent.click(chip('Todas 6'))
    const p = panel()
    const hora = (titulo: string, hh: string) => {
      const fila = within(p).getByRole('button', { name: `Abrir ficha — ${titulo}, ${hh}` })
      return within(fila).getByText(hh)
    }
    expect(hora('Cita pendiente con Ana', '10:00')).toHaveClass('text-warning-text')
    expect(hora('Cita con Ana', '15:00')).toHaveClass('text-accent')
    expect(hora('Cita con Bruno', '10:00')).toHaveClass('text-primary')
    // El subrótulo de la vencida también va en el ámbar OSCURO (texto ≥ 4,5:1).
    const vencida = within(p).getByRole('button', { name: 'Abrir ficha — Cita pendiente con Ana, 10:00' })
    expect(within(vencida).getByText('Vencida')).toHaveClass('text-warning-text')
  })

  it('sin ninguna cita: vacío compacto y ningún filtro; con citas pero no en el día elegido: aviso y salida a la semana', () => {
    const { unmount } = montar([cita({ id: 't', tipo: 'llamada', titulo: 'Llamar a Ana' })])
    expect(within(panel()).getByText('Sin citas agendadas')).toBeInTheDocument()
    expect(within(panel()).getByText('Agenda la próxima cita desde la ficha del lead.')).toBeInTheDocument()
    expect(within(panel()).queryAllByRole('button')).toHaveLength(0)
    unmount()

    montar(SEIS)
    fireEvent.click(within(tira()).getByRole('button', { name: 'Sábado 18, sin citas' }))
    expect(within(panel()).getByText('Sin citas este día')).toBeInTheDocument()
    expect(within(panel()).queryAllByRole('button', { name: /^Cerrar tarea — / })).toHaveLength(0)
    fireEvent.click(within(panel()).getByRole('button', { name: 'Ver la semana' }))
    expect(chip('Semana 3')).toHaveAttribute('aria-pressed', 'true')
    expect(idsPintados(SEIS)).toHaveLength(3)
  })

  it('disposición: en columna la lista se desplaza dentro de la ficha sin tope; libre (legado) con tope de 60vh', () => {
    const { unmount } = montar(SEIS, { disposicion: 'columna' })
    const tarjeta = panel()
    expect(tarjeta).toHaveClass('@container', 'flex', 'flex-col', 'min-h-0')
    const lista = tarjeta.querySelector('.overflow-y-auto')
    expect(lista).toHaveClass('ac-scroll', 'min-h-0', 'flex-1')
    expect(lista).not.toHaveClass('max-h-[60vh]')
    unmount()

    montar(SEIS)
    expect(panel()).not.toHaveClass('min-h-0')
    expect(panel().querySelector('.overflow-y-auto')).toHaveClass('max-h-[60vh]')
  })
})
