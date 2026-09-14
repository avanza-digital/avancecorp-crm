// Datos ficticios y fórmulas de la propuesta. Este módulo no lee ni escribe el CRM.
export const CORTE_DIA = 13
export const MES = '2026-09'
export const META_CITAS = 1.25
export const META_ASISTENCIA = 70
export const META_CONVERSION = 70
export type BaseConversion = 'personas' | 'entrevistas'
export type Estado = 'realizada' | 'no_show' | 'pendiente' | 'programada'
export const EQUIPO = [
  { id: 'ana', nombre: 'Ana Torres', supervisor: 'María León', iniciales: 'AT' },
  { id: 'carla', nombre: 'Carla Rojas', supervisor: 'María León', iniciales: 'CR' },
  { id: 'diego', nombre: 'Diego Salas', supervisor: 'Jorge Ruiz', iniciales: 'DS' },
  { id: 'paola', nombre: 'Paola Vega', supervisor: 'Jorge Ruiz', iniciales: 'PV' },
] as const
export const ESTADOS: Record<Estado, string> = {
  realizada: 'Asistió', no_show: 'No asistió', pendiente: 'Sin resultado', programada: 'Programada',
}
export interface Persona {
  id: string; nombre: string; analista: string; mes: string; origen: string; manual: boolean
  moneda: 'PEN' | 'USD'; conversion: number | null; importe: number | null
}
export interface Cita {
  id: string; lead: string; analista: string; dia: number; creada: number; estado: Estado
  anterior?: string
}
export interface Consulta {
  mes: string; semana: string; supervisor: string; analista: string; origen: string; registro: string; moneda: string
}
export const INICIAL: Consulta = { mes: MES, semana: '', supervisor: '', analista: '', origen: '', registro: '', moneda: 'PEN' }
export const TRAMOS = [
  { id: '1', nombre: 'Semana 1 · 1–7', desde: 1, hasta: 7 },
  { id: '2', nombre: 'Semana 2 · 8–14', desde: 8, hasta: 14 },
  { id: '3', nombre: 'Semana 3 · 15–21', desde: 15, hasta: 21 },
  { id: '4', nombre: 'Semana 4 · 22–fin', desde: 22, hasta: 30 },
] as const
const nombres = ['Valeria', 'Andrés', 'Lucía', 'Mateo', 'Camila', 'Gabriel', 'Daniela', 'Sebastián', 'Mariana', 'Nicolás', 'Adriana', 'Rodrigo', 'Isabel', 'Santiago', 'Renata', 'Joaquín']
const apellidos = ['Paredes', 'Mendoza', 'Castro', 'Gutiérrez', 'Vargas', 'Flores', 'Navarro', 'Aguilar', 'Romero', 'Herrera', 'Medina']

function ejemplo(analista: string, cantidad: number, unicas: number, repetidas: number, faltaron: number, reagendadas: number, recuperadas: number, depositaron: number, recuperadasCliente: number, pendientes: number, futuras: number, ticket: number) {
  const personas: Persona[] = Array.from({ length: cantidad }, (_, i) => ({
    id: `${analista}-${i + 1}`, nombre: `${nombres[i % nombres.length]} ${apellidos[Math.floor(i / nombres.length) % apellidos.length]}`,
    analista, mes: MES, origen: ['Facebook', 'Web', 'Referido'][i % 3]!, manual: i % 5 === 0,
    moneda: 'PEN', conversion: null, importe: null,
  }))
  const citas: Cita[] = []
  function agregar(indice: number, dia: number, estado: Estado, anterior?: string) {
    const cita: Cita = { id: `${analista}-cita-${citas.length + 1}`, lead: personas[indice]!.id, analista, dia, creada: Math.max(1, Math.min(CORTE_DIA, dia - 2)), estado, ...(anterior ? { anterior } : {}) }
    citas.push(cita)
    return cita
  }
  // Las recuperadas están entre quienes sí asistieron: no se inventa una etapa independiente.
  const originales = Array.from({ length: faltaron }, (_, i) => agregar(i < recuperadas ? i : unicas + i - recuperadas, 1 + i % 7, 'no_show'))
  for (let i = 0; i < unicas; i++) agregar(i, i < recuperadas ? 9 + i % 3 : 3 + i % 8, 'realizada', i < recuperadas ? originales[i]!.id : undefined)
  for (let i = 0; i < repetidas; i++) agregar(i, 12, 'realizada')
  for (let i = recuperadas; i < reagendadas; i++) agregar(unicas + i - recuperadas, 16 + i % 4, 'programada', originales[i]!.id)
  const siguiente = unicas + faltaron - recuperadas
  for (let i = 0; i < futuras - (reagendadas - recuperadas); i++) agregar(siguiente + i, 18 + i % 5, 'programada')
  for (let i = 0; i < pendientes; i++) agregar(siguiente + futuras + i, 4 + i % 7, 'pendiente')
  const clientes = [...Array.from({ length: recuperadasCliente }, (_, i) => i), ...Array.from({ length: depositaron - recuperadasCliente }, (_, i) => recuperadas + i)]
  clientes.forEach(i => { personas[i]!.conversion = CORTE_DIA; personas[i]!.importe = ticket })
  return { personas, citas }
}
const grupos = [
  ejemplo('ana', 160, 60, 10, 20, 12, 8, 42, 5, 5, 5, 10_000),
  ejemplo('carla', 120, 50, 10, 20, 10, 6, 30, 3, 5, 5, 15_000),
  ejemplo('diego', 100, 20, 4, 20, 8, 4, 6, 2, 8, 8, 12_000),
  ejemplo('paola', 40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
]
export const PERSONAS = grupos.flatMap(g => g.personas)
export const CITAS = grupos.flatMap(g => g.citas)
export function personasConsulta(f: Consulta) {
  return PERSONAS.filter(p => p.mes === f.mes && p.moneda === f.moneda
    && (!f.analista || p.analista === f.analista)
    && (!f.supervisor || EQUIPO.find(a => a.id === p.analista)?.supervisor === f.supervisor)
    && (!f.origen || p.origen === f.origen)
    && (!f.registro || p.manual === (f.registro === 'manual')))
}
export function citasDe(personas: Persona[]) {
  const ids = new Set(personas.map(p => p.id))
  return CITAS.filter(c => ids.has(c.lead))
}
export function enSemana(dia: number, semana: string) {
  const tramo = TRAMOS.find(t => t.id === semana)
  return !tramo || (dia >= tramo.desde && dia <= tramo.hasta)
}
export function metricas(personas: Persona[], base: BaseConversion) {
  const citas = citasDe(personas)
  const realizadas = citas.filter(c => c.estado === 'realizada')
  const entrevistadas = new Set(realizadas.map(c => c.lead))
  const resueltas = citas.filter(c => c.estado === 'realizada' || c.estado === 'no_show').length
  const clientes = personas.filter(p => p.conversion !== null && entrevistadas.has(p.id)
    && realizadas.some(c => c.lead === p.id && c.dia <= p.conversion!))
  const capital = clientes.reduce((n, p) => n + (p.importe ?? 0), 0)
  const baseClientes = base === 'personas' ? entrevistadas.size : realizadas.length
  const asistencia = resueltas ? realizadas.length / resueltas : null
  const conversion = baseClientes ? clientes.length / baseClientes : null
  const ticket = clientes.length ? capital / clientes.length : null
  const citasEsperadas = citas.length / CORTE_DIA * 30
  const entrevistasEsperadas = asistencia === null ? null : citasEsperadas * asistencia
  const personasEsperadas = entrevistasEsperadas === null || !realizadas.length ? null
    : Math.min(personas.length, entrevistasEsperadas * entrevistadas.size / realizadas.length)
  // Cambiar el denominador cambia su tasa, no inventa nuevas personas: se aplica la tasa a su misma unidad.
  const clientesEsperados = conversion === null || personasEsperadas === null || entrevistasEsperadas === null ? null
    : Math.max(clientes.length, Math.min(personasEsperadas, (base === 'personas' ? personasEsperadas : entrevistasEsperadas) * conversion))
  return {
    leads: personas.length, manuales: personas.filter(p => p.manual).length, citas: citas.length,
    promedio: personas.length ? citas.length / personas.length : null,
    cumplimiento: personas.length ? citas.length / (personas.length * META_CITAS) * 100 : null,
    entrevistas: realizadas.length, unicas: entrevistadas.size, resueltas, clientes: clientes.length,
    asistencia, conversion, ticket, capital, citasEsperadas, personasEsperadas, clientesEsperados,
    proyeccion: ticket === null || clientesEsperados === null ? null : clientesEsperados * ticket,
    sinCita: personas.filter(p => !citas.some(c => c.lead === p.id)).length,
    sinResultado: citas.filter(c => c.estado === 'pendiente').length,
    futuras: citas.filter(c => c.estado === 'programada').length,
  }
}
export type Metricas = ReturnType<typeof metricas>
export interface Recorrido { persona: Persona; falta: Cita; nueva: Cita | undefined; asistencia: Cita | undefined; cliente: boolean }
export function recorrido(personas: Persona[], semana: string): Recorrido[] {
  const citas = citasDe(personas)
  return personas.flatMap(persona => {
    const falta = citas.find(c => c.lead === persona.id && c.estado === 'no_show' && enSemana(c.dia, semana))
    if (!falta) return []
    const nueva = citas.find(c => c.anterior === falta.id && c.dia > falta.dia)
    const asistencia = nueva?.estado === 'realizada' ? nueva : undefined
    return [{ persona, falta, nueva, asistencia, cliente: Boolean(asistencia && persona.conversion !== null && persona.conversion >= asistencia.dia) }]
  })
}
export const numero = (n: number | null, decimales = 0) => n === null ? '—' : new Intl.NumberFormat('es-PE', { maximumFractionDigits: decimales }).format(n)
export const porcentaje = (n: number | null) => n === null ? '—' : `${numero(n * 100, 1)}%`
export const dinero = (n: number | null, moneda = 'PEN') => n === null ? 'Sin base' : new Intl.NumberFormat('es-PE', { style: 'currency', currency: moneda, maximumFractionDigits: 0 }).format(n)
export const fecha = (dia: number) => `${dia} sept.`
