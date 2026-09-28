// Hoy · analista — la PARTICIÓN de «Tus citas»: cifras, ventana de 7 días,
// filas de cada filtro, selección inicial y rótulos. Pura e inyectable (`ahora`
// en ms) para probarla sin montar nada; el componente vive en citas-analista.tsx.
//
// Regla (decisión tras la refutación de Codex, 28/09/2026):
//  · Vencidas = `ev.vencida`, de cualquier fecha.
//  · Hoy / Mañana / Semana (hoy → hoy+6) / celdas de la tira = SOLO citas NO
//    vencidas de esa(s) fecha(s) en Lima: el chip «Hoy» y la celda de hoy dan
//    la misma cifra, y cada lista pinta EXACTAMENTE lo que su cifra cuenta.
//  · Todas = todas las pendientes (vencidas incluidas), el número del badge.
// Todo sale de `fechaLima(ahora)`; nada del reloj local del navegador.
import { DIAS, LIMA_OFFSET_MS, MESES, fechaLima, type EventoAgenda } from '@/lib/agenda-derivada'

const DIA_MS = 86_400_000
const DIAS_LARGOS = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'] as const

/** Qué lista se ve: una cifra de arriba o un día concreto de la tira. */
export type FiltroCitas = 'vencidas' | 'hoy' | 'manana' | 'semana' | 'todas' | `dia:${string}`

/** Un día de la tira «Próximos 7 días», con cuántas citas NO vencidas tiene. */
export interface DiaTira {
  /** 'YYYY-MM-DD' en Lima. */
  fecha: string
  /** 'Lun' … derivado de la fecha, no del reloj local. */
  dia: string
  diaLargo: string
  numero: number
  n: number
  esHoy: boolean
}

export interface ParticionCitas {
  hoy: string
  manana: string
  /** Los 7 días hoy → hoy+6, en Lima. */
  tira: DiaTira[]
  /** Vencidas de cualquier fecha, en el orden en que llegaron (vence_en asc). */
  vencidas: EventoAgenda[]
  /** No vencidas en orden cronológico (sus fechas con formato válido). */
  noVencidas: EventoAgenda[]
  /** No vencidas por fecha Lima, cronológicas dentro de cada día. */
  porDia: ReadonlyMap<string, EventoAgenda[]>
  nVencidas: number
  nHoy: number
  nManana: number
  nSemana: number
  nTodas: number
}

/** Fecha Lima, día de semana (0 = domingo), número de día y mes (0-11) de un instante. */
export function partesLima(ms: number): { fecha: string; diaSemana: number; numero: number; mes: number } {
  const d = new Date(ms - LIMA_OFFSET_MS)
  return { fecha: fechaLima(ms), diaSemana: d.getUTCDay(), numero: d.getUTCDate(), mes: d.getUTCMonth() }
}

/** Mediodía de Lima de una fecha 'YYYY-MM-DD' (para sacarle día de semana y mes). */
function mediodiaLima(fecha: string): number {
  return Date.parse(`${fecha}T12:00:00-05:00`)
}

/** `citas` llega ya ordenada por vence_en asc (agendaDeTareas), así que las
 * vencidas quedan primero y cada día conserva su orden sin volver a ordenar. */
export function particionarCitas(citas: EventoAgenda[], ahora: number): ParticionCitas {
  const hoy = fechaLima(ahora)
  const manana = fechaLima(ahora + DIA_MS)
  const vencidas: EventoAgenda[] = []
  const noVencidas: EventoAgenda[] = []
  const porDia = new Map<string, EventoAgenda[]>()
  for (const ev of citas) {
    if (ev.vencida) {
      vencidas.push(ev)
      continue
    }
    const ms = Date.parse(ev.vence_en)
    if (!Number.isFinite(ms)) continue
    noVencidas.push(ev)
    const fecha = fechaLima(ms)
    const lista = porDia.get(fecha)
    if (lista) lista.push(ev)
    else porDia.set(fecha, [ev])
  }
  const tira: DiaTira[] = Array.from({ length: 7 }, (_, i) => {
    const p = partesLima(ahora + i * DIA_MS)
    return {
      fecha: p.fecha,
      dia: DIAS[p.diaSemana] ?? '',
      diaLargo: DIAS_LARGOS[p.diaSemana] ?? '',
      numero: p.numero,
      n: porDia.get(p.fecha)?.length ?? 0,
      esHoy: i === 0,
    }
  })
  return {
    hoy,
    manana,
    tira,
    vencidas,
    noVencidas,
    porDia,
    nVencidas: vencidas.length,
    nHoy: porDia.get(hoy)?.length ?? 0,
    nManana: porDia.get(manana)?.length ?? 0,
    nSemana: tira.reduce((s, d) => s + d.n, 0),
    nTodas: vencidas.length + noVencidas.length,
  }
}

/** Exactamente las filas que la cifra del filtro cuenta. */
export function filasDelFiltro(p: ParticionCitas, filtro: FiltroCitas): EventoAgenda[] {
  switch (filtro) {
    case 'vencidas':
      return p.vencidas
    case 'hoy':
      return p.porDia.get(p.hoy) ?? []
    case 'manana':
      return p.porDia.get(p.manana) ?? []
    case 'semana':
      return p.tira.flatMap((d) => p.porDia.get(d.fecha) ?? [])
    case 'todas':
      return [...p.vencidas, ...p.noVencidas]
    default:
      return p.porDia.get(filtro.slice(4)) ?? []
  }
}

/** Selección inicial: la semana (llena la altura); si no tiene nada, todas. Se
 * calcula UNA vez al montar (inicializador de useState) y no se mueve sola. */
export function filtroInicial(p: ParticionCitas): FiltroCitas {
  return p.nSemana > 0 ? 'semana' : 'todas'
}

/** Un día explícito que ya salió de la ventana (pasó la medianoche) vuelve a la semana. */
export function filtroVigente(elegido: FiltroCitas, p: ParticionCitas): FiltroCitas {
  if (elegido.startsWith('dia:') && !p.tira.some((d) => d.fecha === elegido.slice(4))) return 'semana'
  return elegido
}

export interface GrupoCitas {
  clave: string
  rotulo: string
  filas: EventoAgenda[]
}

/** «Vencidas», «Hoy · Mié 15», «Mañana · Jue 16», «Vie 17», y con mes fuera de la semana («Mié 22 Jul»). */
export function rotuloGrupo(clave: string, p: ParticionCitas): string {
  if (clave === 'vencidas') return 'Vencidas'
  const { diaSemana, numero, mes } = partesLima(mediodiaLima(clave))
  const corto = `${DIAS[diaSemana] ?? ''} ${numero}`
  if (clave === p.hoy) return `Hoy · ${corto}`
  if (clave === p.manana) return `Mañana · ${corto}`
  if (p.tira.some((d) => d.fecha === clave)) return corto
  return `${corto} ${MESES[mes] ?? ''}`
}

/** Las filas ya vienen en orden (vencidas primero, luego cronológico): los
 * grupos salen de cortar donde cambia el día. */
export function agruparPorDia(filas: EventoAgenda[], p: ParticionCitas): GrupoCitas[] {
  const grupos: GrupoCitas[] = []
  for (const ev of filas) {
    const clave = ev.vencida ? 'vencidas' : fechaLima(Date.parse(ev.vence_en))
    const ultimo = grupos[grupos.length - 1]
    if (ultimo && ultimo.clave === clave) ultimo.filas.push(ev)
    else grupos.push({ clave, rotulo: rotuloGrupo(clave, p), filas: [ev] })
  }
  return grupos
}
