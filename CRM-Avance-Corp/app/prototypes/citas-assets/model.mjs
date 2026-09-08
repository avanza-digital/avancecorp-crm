// Escenario ficticio y fijo: no depende del reloj del dispositivo ni consulta el CRM.
export const CORTE = '2026-09-07T13:00:00-05:00'
export const ESTADOS = {
  vencida: { label: 'Vencida sin resultado', short: 'Sin resultado', icon: 'circle-alert', next: 'Registrar resultado' },
  programada: { label: 'Programada', short: 'Programadas', icon: 'clock3', next: 'Preparar cita' },
  realizada: { label: 'Realizada', short: 'Realizadas', icon: 'circle-check', next: 'Continuar seguimiento' },
  no_show: { label: 'No asistió', short: 'No asistieron', icon: 'circle-x', next: 'Recuperar contacto' },
  reprogramada: { label: 'Reprogramada', short: 'Reprogramadas', icon: 'calendar-clock', next: 'Revisar nueva fecha' },
  cancelada: { label: 'Cancelada por asesor', short: 'Canceladas por asesor', icon: 'circle-x', next: 'Revisar motivo' },
  sistema: { label: 'Cancelada por sistema', short: 'Canceladas por sistema', icon: 'circle-x', next: 'Revisar contexto' },
}
export const EQUIPO = [
  { id: 'ana', nombre: 'Ana Torres', supervisor: 'Claudia Ríos' },
  { id: 'diego', nombre: 'Diego Salas', supervisor: 'Javier Vega' },
  { id: 'lucia', nombre: 'Lucía Mendoza', supervisor: 'Claudia Ríos' },
  { id: 'mateo', nombre: 'Mateo Paredes', supervisor: 'Javier Vega' },
  { id: 'valeria', nombre: 'Valeria León', supervisor: 'Claudia Ríos' },
  { id: 'bruno', nombre: 'Bruno Castro', supervisor: 'Javier Vega' },
]
const nombres = ['Mariana Fuentes','Ricardo Benavides','Elena Cáceres','Andrés Villanueva','Patricia Montes','Roberto Arce','Daniela Méndez','Luis Alvarado','Gabriela Santos','Eduardo Navarro','Carolina Ponce','Jorge Valdez','Sofía Cabrera','Fernando Arias','Isabel Córdova','Alonso Medina','Camila Rojas','Héctor Linares','Valentina Flores','Sergio Palacios','Natalia Suárez','Oscar Romero','Adriana Guerra','Renato Espinoza','Teresa Beltrán','Mauricio Paz','Victoria Núñez','Arturo Molina','Mónica Silva','Pablo Cárdenas','Andrea Peralta','Esteban Duarte','Jimena Rivas','Emilio Aguirre','Lorena Velásquez','Gonzalo Salcedo','Cecilia Durán','Raúl Bustamante','Clara Delgado','Iván Reyes']
const origenes = ['Formulario web', 'Referido', 'Meta Ads', 'WhatsApp', 'Base comercial']
const resultados = ['Interesado', 'Seguimiento', 'Propuesta enviada', 'Inicia registro']
const pad = (n) => String(n).padStart(2, '0')
export const CITAS = nombres.map((nombre, i) => {
  const estado = i < 6 ? 'vencida' : i < 16 ? 'programada' : i < 28 ? 'realizada' : i < 32 ? 'no_show' : i < 35 ? 'reprogramada' : i < 38 ? 'cancelada' : 'sistema'
  const dia = estado === 'vencida' ? 4 + (i % 4) : estado === 'programada' ? 7 + Math.floor((i - 6) / 2) : 1 + (i % 6)
  const hora = estado === 'programada' ? 14 + (i % 3) : 9 + (i % 4)
  const persona = EQUIPO[i % EQUIPO.length]
  const cerrado = estado === 'realizada' && i % 3 === 0
  return {
    id: `C-2609-${String(i + 1).padStart(3, '0')}`, nombre, telefono: `000 000 ${101 + i}`,
    analista: persona.id, supervisor: persona.supervisor,
    fecha: `2026-09-${pad(dia)}`, hora: `${pad(hora)}:${i % 2 ? '30' : '00'}`,
    estado, modalidad: i === 39 ? 'Sin clasificar' : i % 3 === 1 ? 'Virtual' : 'Presencial',
    origen: origenes[i % origenes.length], moneda: i % 4 === 1 ? 'USD' : 'PEN',
    monto: [50000, 15000, 80000, 120000, 35000, 25000, 65000][i % 7],
    resultado: estado === 'realizada' ? resultados[i % 4] : 'Sin resultado registrado',
    cerrado, seguimiento: estado === 'realizada' && !cerrado,
    nuevaFecha: estado === 'reprogramada' ? `2026-09-${pad(11 + i % 3)}` : null,
    nota: estado === 'cancelada' ? 'El prospecto pidió retomar la conversación el próximo mes.'
      : estado === 'sistema' ? 'Cita cancelada al cambiar el responsable del prospecto.'
      : estado === 'no_show' ? 'No se registró asistencia. Queda pendiente recuperar el contacto.'
      : 'Interés en conocer las alternativas de inversión. Revisar plazo y disponibilidad de capital durante el siguiente contacto.',
  }
})
export function defaults() { return { q: '', equipo: '', analista: '', periodo: 'mes', desde: '2026-09-01', hasta: '2026-09-30', estados: [], modalidad: '', origen: '', resultado: '', seguimiento: '', moneda: '', min: '', max: '', sort: 'prioridad' } }
export function rango(f) {
  if (f.periodo === 'hoy') return ['2026-09-07','2026-09-07']
  if (f.periodo === 'semana') return ['2026-09-07','2026-09-13']
  if (f.periodo === 'pasada') return ['2026-08-31','2026-09-06']
  if (f.periodo === 'todos') return ['', '']
  return f.periodo === 'custom' ? [f.desde, f.hasta] : ['2026-09-01','2026-09-30']
}
export const normalizar = (s) => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
export function fechaValida(s) {
  const t = Date.parse(`${s}T12:00:00-05:00`)
  return /^\d{4}-\d{2}-\d{2}$/.test(s) && Number.isFinite(t) && new Date(t).toISOString().startsWith(s)
}
export function errorFiltros(f) {
  if (f.periodo === 'custom' && (!f.desde || !f.hasta)) return 'Completa las dos fechas para consultar el rango.'
  const [desde, hasta] = rango(f)
  if ((desde && !fechaValida(desde)) || (hasta && !fechaValida(hasta))) return 'Introduce fechas válidas con un año de cuatro dígitos.'
  if (desde && hasta && desde > hasta) return 'La fecha inicial debe ser anterior o igual a la fecha final.'
  if (f.moneda && [f.min, f.max].some((v) => v !== '' && (!Number.isFinite(Number(v)) || Number(v) < 0))) return 'Introduce montos válidos, iguales o mayores que cero.'
  if (f.moneda && f.min !== '' && f.max !== '' && Number(f.min) > Number(f.max)) return 'El monto mínimo debe ser menor o igual al máximo.'
  return ''
}
export function filtrar(f, citas = CITAS) {
  if (errorFiltros(f)) return []
  const [desde, hasta] = rango(f)
  const palabras = normalizar(f.q).split(/\s+/).filter(Boolean)
  const numeros = f.q.replace(/\D/g, '')
  return citas.filter((c) => {
    const texto = normalizar(`${c.nombre} ${c.telefono} ${c.id}`)
    const busqueda = palabras.every((p) => texto.includes(p)) || (numeros.length > 2 && /^[\d\s+()-]+$/.test(f.q) && c.telefono.replace(/\D/g, '').includes(numeros))
    return busqueda && (!desde || c.fecha >= desde) && (!hasta || c.fecha <= hasta)
      && (!f.equipo || c.supervisor === f.equipo) && (!f.analista || c.analista === f.analista)
      && (!f.estados.length || f.estados.includes(c.estado)) && (!f.modalidad || c.modalidad === f.modalidad)
      && (!f.origen || c.origen === f.origen) && (!f.resultado || c.resultado === f.resultado)
      && (!f.seguimiento || (f.seguimiento === 'pendiente' ? c.seguimiento : f.seguimiento === 'cerrado' ? c.cerrado : !c.cerrado))
      && (!f.moneda || c.moneda === f.moneda)
      && (!f.moneda || f.min === '' || c.monto >= Number(f.min))
      && (!f.moneda || f.max === '' || c.monto <= Number(f.max))
  })
}
export function ordenar(citas, orden) {
  const prioridad = ['vencida','programada','no_show','realizada','reprogramada','cancelada','sistema']
  const tiempo = (a,b) => `${a.fecha} ${a.hora}`.localeCompare(`${b.fecha} ${b.hora}`) || a.id.localeCompare(b.id)
  return [...citas].sort((a,b) => orden === 'nombre' ? a.nombre.localeCompare(b.nombre, 'es')
    : orden === 'reciente' ? -tiempo(a,b)
    : orden === 'fecha' ? tiempo(a,b)
    : prioridad.indexOf(a.estado) - prioridad.indexOf(b.estado) || tiempo(a,b))
}
export function agruparAnalistas(citas) {
  return EQUIPO.map((persona) => {
    const filas = citas.filter((c) => c.analista === persona.id)
    return {...persona, total: filas.length, realizadas: filas.filter(c => c.estado === 'realizada').length,
      vencidas: filas.filter(c => c.estado === 'vencida').length, programadas: filas.filter(c => c.estado === 'programada').length,
      noShow: filas.filter(c => c.estado === 'no_show').length,
      otras: filas.filter(c => ['reprogramada','cancelada','sistema'].includes(c.estado)).length}
  }).filter(p => p.total > 0).sort((a,b) => b.vencidas-a.vencidas || b.realizadas-a.realizadas || a.nombre.localeCompare(b.nombre, 'es'))
}
export function csv(citas) {
  const celda = (v) => `"${String(v).replace(/^[\s=+@-]/, (m) => `'${m}`).replaceAll('"', '""')}"`
  const cabecera = ['Código demo','Prospecto ficticio','Fecha prevista Lima','Hora Lima','Analista','Supervisor','Estado','Modalidad','Origen','Resultado registrado','Monto estimado','Moneda']
  const filas = citas.map(c => [c.id,c.nombre,c.fecha,c.hora,EQUIPO.find(p=>p.id===c.analista)?.nombre ?? '',c.supervisor,ESTADOS[c.estado].label,c.modalidad,c.origen,c.resultado,c.monto,c.moneda])
  return '\uFEFF' + [cabecera,...filas].map(f => f.map(celda).join(',')).join('\r\n')
}
