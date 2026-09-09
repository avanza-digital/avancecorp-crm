export type EstadoCita = 'vencida' | 'programada' | 'realizada' | 'no_show' | 'reprogramada' | 'cancelada' | 'sistema'
export interface PersonaCitas { id: string; nombre: string; supervisor: string; supervisorId: string }
export interface CitaEjemplo {
  id: string; leadId: string; nombre: string; telefono: string; analista: string; analistaNombre: string;
  supervisor: string; supervisorId: string; fecha: string; hora: string; estado: EstadoCita;
  modalidad: string; origen: string; moneda: 'PEN' | 'USD'; monto: number; resultado: string;
  cerrado: boolean; seguimiento: boolean; nuevaFecha: string | null; nota: string;
  citaAnteriorId?: string; reprogramadaEn?: string; asistioEn?: string;
}
export interface FiltrosCitas {
  q: string; equipo: string; analista: string; mes: string; semana: string; leadId?: string;
  estados: EstadoCita[]; modalidad: string; origen: string; resultado: string; seguimiento: string;
  moneda: string; min: string; max: string; sort: string;
}
export function mesLima(ahora = new Date()) { return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit' }).format(ahora).slice(0, 7) }
export function defaults(mes = mesLima()): FiltrosCitas { return { q: '', equipo: '', analista: '', mes, semana: '', estados: [], modalidad: '', origen: '', resultado: '', seguimiento: '', moneda: '', min: '', max: '', sort: 'prioridad' } }
export function rango(f: FiltrosCitas): [string, string] {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(f.mes) || !['', '1', '2', '3', '4'].includes(f.semana)) return ['', '']
  const [anio, mes] = f.mes.split('-').map(Number)
  const ultimo = new Date(Date.UTC(anio!, mes!, 0)).getUTCDate()
  const semana = Number(f.semana)
  const desde = semana ? (semana - 1) * 7 + 1 : 1
  const hasta = semana && semana < 4 ? semana * 7 : ultimo
  return [`${f.mes}-${String(desde).padStart(2, '0')}`, `${f.mes}-${String(hasta).padStart(2, '0')}`]
}
export const ESTADOS = {
  vencida: { label: 'Vencida sin resultado', short: 'Sin resultado', icon: 'circle-alert', next: 'Registrar resultado' },
  programada: { label: 'Programada', short: 'Programadas', icon: 'clock3', next: 'Preparar cita' },
  realizada: { label: 'Realizada', short: 'Realizadas', icon: 'circle-check', next: 'Continuar seguimiento' },
  no_show: { label: 'No asistió', short: 'No asistieron', icon: 'circle-x', next: 'Recuperar contacto' },
  reprogramada: { label: 'Reprogramada', short: 'Reprogramadas', icon: 'calendar-clock', next: 'Revisar nueva fecha' },
  cancelada: { label: 'Cancelada por asesor', short: 'Canceladas por asesor', icon: 'circle-x', next: 'Revisar motivo' },
  sistema: { label: 'Cancelada por sistema', short: 'Canceladas por sistema', icon: 'circle-x', next: 'Revisar contexto' },
}
export const normalizar = (s: unknown) => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
export function fechaValida(s: string) {
  const t = Date.parse(`${s}T12:00:00-05:00`)
  return /^\d{4}-\d{2}-\d{2}$/.test(s) && Number.isFinite(t) && new Date(t).toISOString().startsWith(s)
}
export function errorFiltros(f: FiltrosCitas) {
  if (!rango(f)[0]) return 'Selecciona un mes y una semana válidos.'
  const [desde, hasta] = rango(f)
  if ((desde && !fechaValida(desde)) || (hasta && !fechaValida(hasta))) return 'Introduce fechas válidas con un año de cuatro dígitos.'
  if (desde && hasta && desde > hasta) return 'La fecha inicial debe ser anterior o igual a la fecha final.'
  if (f.moneda && [f.min, f.max].some((v) => v !== '' && (!Number.isFinite(Number(v)) || Number(v) < 0))) return 'Introduce montos válidos, iguales o mayores que cero.'
  if (f.moneda && f.min !== '' && f.max !== '' && Number(f.min) > Number(f.max)) return 'El monto mínimo debe ser menor o igual al máximo.'
  return ''
}
export function filtrar<T extends CitaEjemplo>(f: FiltrosCitas, citas: T[]) {
  if (errorFiltros(f)) return []
  const [desde, hasta] = rango(f)
  const palabras = normalizar(f.q).split(/\s+/).filter(Boolean)
  const numeros = f.q.replace(/\D/g, '')
  return citas.filter((c) => {
    const texto = normalizar(`${c.nombre} ${c.telefono} ${c.id}`)
    const busqueda = palabras.every((p) => texto.includes(p)) || (numeros.length > 2 && /^[\d\s+()-]+$/.test(f.q) && c.telefono.replace(/\D/g, '').includes(numeros))
    return (!f.leadId || c.leadId === f.leadId) && busqueda && (!desde || c.fecha >= desde) && (!hasta || c.fecha <= hasta)
      && (!f.equipo || c.supervisorId === f.equipo) && (!f.analista || c.analista === f.analista)
      && (!f.estados.length || f.estados.includes(c.estado)) && (!f.modalidad || c.modalidad === f.modalidad)
      && (!f.origen || c.origen === f.origen) && (!f.resultado || c.resultado === f.resultado)
      && (!f.seguimiento || (f.seguimiento === 'pendiente' ? c.seguimiento : f.seguimiento === 'cerrado' ? c.cerrado : !c.cerrado))
      && (!f.moneda || c.moneda === f.moneda)
      && (!f.moneda || f.min === '' || c.monto >= Number(f.min))
      && (!f.moneda || f.max === '' || c.monto <= Number(f.max))
  })
}
export function ordenar<T extends CitaEjemplo>(citas: T[], orden: string) {
  const prioridad = ['vencida','programada','no_show','realizada','reprogramada','cancelada','sistema']
  const tiempo = (a: T,b: T) => `${a.fecha} ${a.hora}`.localeCompare(`${b.fecha} ${b.hora}`) || a.id.localeCompare(b.id)
  return [...citas].sort((a,b) => orden === 'nombre' ? a.nombre.localeCompare(b.nombre, 'es')
    : orden === 'reciente' ? -tiempo(a,b)
    : orden === 'fecha' ? tiempo(a,b)
    : prioridad.indexOf(a.estado) - prioridad.indexOf(b.estado) || tiempo(a,b))
}
export function agruparAnalistas(citas: CitaEjemplo[]) {
  return equipoCitas(citas).map((persona) => {
    const filas = citas.filter((c) => c.analista === persona.id)
    return {...persona, total: filas.length, realizadas: filas.filter(c => c.estado === 'realizada').length,
      vencidas: filas.filter(c => c.estado === 'vencida').length, programadas: filas.filter(c => c.estado === 'programada').length,
      noShow: filas.filter(c => c.estado === 'no_show').length,
      otras: filas.filter(c => ['reprogramada','cancelada','sistema'].includes(c.estado)).length}
  }).filter(p => p.total > 0).sort((a,b) => b.vencidas-a.vencidas || b.realizadas-a.realizadas || a.nombre.localeCompare(b.nombre, 'es'))
}
export function csv(citas: CitaEjemplo[]) {
  const celda = (v: unknown) => `"${String(v).replace(/^[\s=+@-]/, (m) => `'${m}`).replaceAll('"', '""')}"`
  const cabecera = ['Código de cita','Prospecto','Fecha prevista Lima','Hora Lima','Analista','Supervisor','Estado','Modalidad','Origen','Resultado registrado','Monto estimado','Moneda']
  const filas = citas.map(c => [c.id,c.nombre,c.fecha,c.hora,c.analistaNombre,c.supervisor,ESTADOS[c.estado].label,c.modalidad,c.origen,c.resultado,c.monto,c.moneda])
  return '\uFEFF' + [cabecera,...filas].map(f => f.map(celda).join(',')).join('\r\n')
}

export function equipoCitas(citas: CitaEjemplo[]): PersonaCitas[] {
  return [...new Map(citas.map(c => [c.analista, { id: c.analista, nombre: c.analistaNombre, supervisor: c.supervisor, supervisorId: c.supervisorId }])).values()]
    .sort((a,b) => a.nombre.localeCompare(b.nombre, 'es'))
}
