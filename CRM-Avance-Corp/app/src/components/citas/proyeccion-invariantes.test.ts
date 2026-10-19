// Invariantes de la Proyección de Citas (auditoría de consistencia, 19/10/2026).
// Regla del dueño: «no puede haber data distinta». Lo que debe cumplirse SIEMPRE,
// sean cuales sean los datos, y que la Proyección y Resultados
// (`calcularAvanceCitas`) cuenten lo mismo cuando dicen lo mismo.
import { describe, expect, it } from 'vitest'
import { controlCitasInicial } from '@/lib/control-citas'
import { fusionarConsultasCitas, type ConsultaCitasRpc } from '@/data/citas-gerencia'
import { calcularAvanceCitas } from './avance'
import { fechaLocalCitas } from './fecha-comercial'
import type { GestionCitas } from './metas'
import { defaults, type CitaEjemplo } from './modelo'
import { calcularProyeccion, type FuenteProyeccion, type HojaProyeccion, type MetricasProyeccion } from './proyeccion'
import { sumarDias, type RangoProyeccion, type TiempoProyeccion } from './proyeccion-rango'

const HOY = '2026-10-19T17:00:00Z' // lunes 19/10/2026, 12:00 de Lima
const TC = 3.4391
const OCTUBRE: RangoProyeccion = { desde: '2026-10-01', hasta: '2026-10-31' }
const SEPTIEMBRE: RangoProyeccion = { desde: '2026-09-01', hasta: '2026-09-30' }
type Conversion = NonNullable<GestionCitas['avance']>['conversiones'][number]
type Persona = NonNullable<GestionCitas['avance']>['poblacion'][number]

const ANALISTAS = [['ana', 'sup-1'], ['luis', 'sup-1'], ['diego', 'sup-2'], ['mateo', 'sup-2']] as const
function cita(n: number, cambios: Partial<CitaEjemplo> & { creadoEn: string }): CitaEjemplo {
  const [analista, supervisorId] = ANALISTAS[n % ANALISTAS.length]!
  return {
    id: `c${n}`, leadId: `lead-${n}`, nombre: `Persona ${n}`, telefono: '900000000', analista, analistaNombre: analista,
    supervisor: supervisorId, supervisorId, fecha: cambios.creadoEn.slice(0, 10), hora: '10:00', estado: 'programada',
    modalidad: 'Virtual', origen: 'Formulario', moneda: 'PEN', monto: 10_000, resultado: 'Sin clasificar', cerrado: false,
    seguimiento: false, nuevaFecha: null, nota: '', ...cambios,
  }
}
const venta = (c: CitaEjemplo, convertidoEn: string, fechaComercial: string | null): Conversion => ({
  lead_id: c.leadId, perfil_id: `perfil-${c.leadId}`, convertido_en: convertidoEn, fecha_comercial: fechaComercial,
  analista_id: c.analista, analista_nombre: c.analistaNombre, supervisor_id: c.supervisorId, supervisor_nombre: c.supervisor, contrato_id: null,
})

/** Lote determinista y variado: 45 días, monedas, orígenes, estados, sin monto, ya clientes, previstas en otro mes y ventas de todo tipo. */
function lote(): { citas: CitaEjemplo[]; conversiones: Conversion[] } {
  const estados = ['realizada', 'no_show', 'programada', 'vencida', 'cancelada', 'sistema', 'reprogramada'] as const
  const citas: CitaEjemplo[] = []
  for (let d = 0; d < 45; d += 1) {
    const dia = sumarDias('2026-09-20', d)
    for (let k = 0; k < 3; k += 1) {
      const i = d * 3 + k
      const estado = estados[i % estados.length]!
      citas.push(cita(i + 1, {
        creadoEn: `${dia}T${String(5 + k * 7).padStart(2, '0')}:30:00Z`, // 05:30Z = 00:30 de Lima (borde de día)
        fecha: sumarDias(dia, (i * 7) % 41), // prevista 0–40 días después: parte cae en el mes siguiente
        estado,
        ...(estado === 'realizada' ? { asistioEn: `${sumarDias(dia, 1)}T16:00:00Z` } : {}),
        moneda: i % 5 === 0 ? 'USD' : 'PEN',
        monto: i % 11 === 0 ? null : 1_000 * (1 + (i % 13)),
        origen: i % 4 === 0 ? 'Referido' : i % 4 === 1 ? 'referido' : 'Formulario',
        esCliente: i % 9 === 0,
        // La misma persona con dos citas (y de otro analista).
        ...(i % 6 === 1 ? { leadId: `lead-${i - 1}` } : {}),
      }))
    }
  }
  // Ventas: posterior a la entrevista (vincula), anterior a su día (no) y sin fecha comercial (no).
  const conversiones = citas.filter(c => c.estado === 'realizada').flatMap((c, i) => {
    const dia = fechaLocalCitas(c.asistioEn!)
    if (i % 4 === 3) return []
    return [venta(c, `${sumarDias(dia, 3)}T15:00:00Z`, i % 4 === 0 ? sumarDias(dia, 3) : i % 4 === 1 ? sumarDias(dia, -1) : null)]
  })
  return { citas, conversiones }
}

/** Las citas del lote creadas en septiembre, con la prevista y la asistencia el mismo día de Lima que la creación. */
const citasDeSeptiembre = () => lote().citas.filter(c => fechaLocalCitas(c.creadoEn!).startsWith('2026-09')).map(c => {
  const dia = fechaLocalCitas(c.creadoEn!)
  return { ...c, fecha: dia, hora: '18:00', ...(c.asistioEn ? { asistioEn: `${dia}T23:00:00Z` } : {}) }
})
/** Ventas de septiembre, todas registradas DESPUÉS de su entrevista: la fecha comercial va después, el mismo día, antes del día de la entrevista o falta. */
const ventasDeSeptiembre = (citas: readonly CitaEjemplo[], vendedor: (c: CitaEjemplo, i: number) => CitaEjemplo = c => c) => {
  const tope = (f: string) => f > SEPTIEMBRE.hasta ? SEPTIEMBRE.hasta : f
  return citas.filter(c => c.estado === 'realizada').map((c, i) => venta(vendedor(c, i), `${tope(sumarDias(c.fecha, 2))}T23:30:00Z`,
    [tope(sumarDias(c.fecha, 2)), c.fecha, sumarDias(c.fecha, -1), null][i % 4]!))
}

const fuente = (rango: RangoProyeccion, cambios: Partial<FuenteProyeccion> = {}): FuenteProyeccion =>
  ({ ...lote(), filtros: { equipo: '' }, rango, corte: HOY, tipoCambio: TC, ...cambios })
const filasYTotal = (h: HojaProyeccion): MetricasProyeccion[] => [...h.filas, h.total]
const ids = (lista: readonly { cita: CitaEjemplo }[]) => lista.map(c => c.cita.id).sort()
const RANGOS: RangoProyeccion[] = [
  { desde: '2026-10-01', hasta: '2026-10-07' }, { desde: '2026-10-01', hasta: '2026-10-19' }, OCTUBRE,
  { desde: '2026-09-25', hasta: '2026-10-19' }, { desde: '2026-10-19', hasta: '2026-10-19' },
]
const TIEMPOS: TiempoProyeccion[] = ['mes', 'semanas', 'dias']

describe('Invariantes de la Proyección (siempre ciertas)', () => {
  it.each(RANGOS)('Referidos + Clientes + Leads = Citas, por fila y en el total, sin una cita en dos orígenes ($desde → $hasta)', rango => {
    for (const tiempo of TIEMPOS) {
      for (const m of filasYTotal(calcularProyeccion(fuente(rango, { tiempo })))) {
        expect(m.referidos.length + m.clientes.length + m.leads.length).toBe(m.citas.length)
        expect(new Set([...m.referidos, ...m.clientes, ...m.leads].map(c => c.cita.id)).size).toBe(m.citas.length)
      }
    }
  })

  it.each(RANGOS)('el total es la suma de las filas: citas, resueltas, entrevistas, PEN, USD y proyectado ($desde → $hasta)', rango => {
    const hoja = calcularProyeccion(fuente(rango))
    const suma = (f: (m: MetricasProyeccion) => number) => hoja.filas.reduce((s, m) => s + f(m), 0)
    expect(hoja.filas.length).toBeGreaterThan(0)
    expect(suma(m => m.citas.length)).toBe(hoja.total.citas.length)
    expect(suma(m => m.resueltas.length)).toBe(hoja.total.resueltas.length)
    expect(suma(m => m.entrevistas.length)).toBe(hoja.total.entrevistas.length)
    expect(suma(m => m.montoPen)).toBeCloseTo(hoja.total.montoPen, 6)
    expect(suma(m => m.montoUsd)).toBeCloseTo(hoja.total.montoUsd, 6)
    const conBase = hoja.filas.filter(f => f.proyectado !== null)
    expect(hoja.total.proyectado).toEqual(conBase.length ? expect.closeTo(conBase.reduce((s, f) => s + f.proyectado!, 0), 6) : null)
  })

  it.each(RANGOS)('Semanas y Días: la suma de los tramos es Citas y cada tramo es la consulta de su propio rango ($desde → $hasta)', rango => {
    for (const tiempo of ['semanas', 'dias'] as const) {
      const hoja = calcularProyeccion(fuente(rango, { tiempo }))
      expect(hoja.tramos.length).toBeGreaterThan(0)
      for (const m of filasYTotal(hoja)) expect(m.porTramo.reduce((s, l) => s + l.length, 0)).toBe(m.citas.length)
      // Elegir el rango de un tramo da las mismas citas que su columna (y, con un mismo TC, el mismo dinero).
      const partes = hoja.tramos.map(t => calcularProyeccion(fuente({ desde: t.desde, hasta: t.hasta })).total)
      partes.forEach((parte, i) => expect(ids(parte.citas)).toEqual(ids(hoja.total.porTramo[i]!)))
      expect(partes.reduce((s, m) => s + m.entrevistas.length, 0)).toBe(hoja.total.entrevistas.length)
      expect(partes.reduce((s, m) => s + (m.monto ?? 0), 0)).toBeCloseTo(hoja.total.monto ?? 0, 4)
    }
  })

  it('la suma por supervisor es el total sin filtro', () => {
    const todo = calcularProyeccion(fuente(OCTUBRE))
    const porEquipo = ['sup-1', 'sup-2'].map(equipo => calcularProyeccion(fuente(OCTUBRE, { filtros: { equipo } })).total)
    expect(porEquipo.reduce((s, m) => s + m.citas.length, 0)).toBe(todo.total.citas.length)
    expect(porEquipo.reduce((s, m) => s + m.montoPen, 0)).toBeCloseTo(todo.total.montoPen, 6)
  })

  it.each(RANGOS)('aritmética de columnas: Monto = PEN + USD×TC; Ticket cita × Citas = Monto; % Entrev. = realizadas ÷ resueltas; Proyectado = citas esperadas × tasas × ticket ($desde → $hasta)', rango => {
    for (const m of filasYTotal(calcularProyeccion(fuente(rango)))) {
      if (!m.citas.length) continue
      expect(m.monto).toBeCloseTo(m.montoPen + m.montoUsd * TC, 6)
      expect(m.ticket! * m.citas.length).toBeCloseTo(m.monto!, 6)
      expect(m.entrevistas.every(c => c.cita.estado === 'realizada')).toBe(true)
      expect(m.resueltas.every(c => c.cita.estado === 'realizada' || c.cita.estado === 'no_show')).toBe(true)
      expect(m.pctEntrevistas).toEqual(m.resueltas.length ? expect.closeTo(m.entrevistas.length / m.resueltas.length * 100, 9) : null)
      expect(m.convertidas.every(c => m.entrevistas.includes(c))).toBe(true)
      expect(m.personasClientes).toBeLessThanOrEqual(m.personasEntrevistadas)
      if (m.pctConversion !== null) expect(m.pctConversion).toBeCloseTo(m.personasClientes / m.personasEntrevistadas * 100, 9)
    }
    for (const f of calcularProyeccion(fuente(rango)).filas) {
      if (f.proyectado === null) continue
      expect(f.proyectado).toBeCloseTo(f.citasEsperadas! * (f.pctEntrevistas! / 100) * (f.pctConversion! / 100) * f.ticket!, 6)
    }
  })

  it('la cohorte es por fecha de CREACIÓN (día de Lima), nunca por fecha prevista', () => {
    const { citas } = lote()
    const hoja = calcularProyeccion(fuente(OCTUBRE))
    const esperadas = citas.filter(c => fechaLocalCitas(c.creadoEn!) >= OCTUBRE.desde && fechaLocalCitas(c.creadoEn!) <= OCTUBRE.hasta)
    expect(ids(hoja.total.citas)).toEqual(ids(esperadas.map(c => ({ cita: c }))))
    // En la cohorte hay citas previstas en noviembre; fuera de ella, citas previstas en octubre.
    expect(hoja.total.citas.some(c => c.cita.fecha > OCTUBRE.hasta)).toBe(true)
    expect(citas.some(c => c.fecha.startsWith('2026-10') && !esperadas.includes(c))).toBe(true)
  })

  it('USD sin tipo de cambio: «pendiente de TC», nunca un monto parcial en soles', () => {
    const hoja = calcularProyeccion(fuente(OCTUBRE, { tipoCambio: null }))
    expect(hoja.total.montoUsd).toBeGreaterThan(0)
    expect(hoja.total).toMatchObject({ pendienteTc: true, monto: null, ticket: null })
  })
})

// Misma palabra, misma cifra: con citas creadas, previstas y resueltas en el MISMO
// mes, la Proyección (mes entero) y Resultados cuentan las mismas citas y
// entrevistas, con la misma tasa de entrevistas y las mismas personas vinculadas a cliente.
describe('Proyección ↔ Resultados (avance mensual)', () => {
  function escenario(ventasFuera: Conversion[] = []) {
    const citas = citasDeSeptiembre()
    // La regla vieja (convertido_en ≥ asistencia) contaba todas estas ventas.
    const conversiones = [...ventasDeSeptiembre(citas), ...ventasFuera]
    const leads = [...new Set(citas.map(c => c.leadId))]
    const gestion: GestionCitas = {
      citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones: [],
      avance: {
        control: { version: 1, mes_inicio: '2026-09', configuracion: { ...controlCitasInicial(), base_avance: 'actividad_real',
          conteo_entrevistas: 'citas_realizadas', base_depositos: 'personas_entrevistadas', mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: '2026-09' } },
        poblacion: leads.map(lead_id => ({ lead_id, nombre: lead_id, telefono: '900000000', origen: 'formulario', moneda: 'PEN' as const,
          monto_estimado: 1000, registro_manual: false, creado_por: null, analista_origen_id: null, analista_origen_nombre: 'Sin analista',
          supervisor_origen_id: null, supervisor_origen_nombre: 'Sin supervisor', primera_asignacion_en: null })),
        conversiones, capital: [],
      },
    }
    const resultados = calcularAvanceCitas(gestion, citas, defaults('2026-09'), HOY, TC)
    // Igual que la pantalla: las conversiones y la población del lector del avance.
    const proyeccion = calcularProyeccion({ citas, filtros: { equipo: '' }, rango: SEPTIEMBRE, corte: HOY, tipoCambio: TC,
      conversiones: gestion.avance!.conversiones, poblacion: gestion.avance!.poblacion })
    return { citas, conversiones, resultados, proyeccion }
  }

  it('Citas, entrevistas, resueltas y % Entrev. (base «actividad real»): iguales en el total y por analista', () => {
    const { citas, resultados, proyeccion } = escenario()
    expect(citas.length).toBeGreaterThan(20)
    const t = proyeccion.total, r = resultados.total
    expect([t.citas.length, t.entrevistas.length, t.resueltas.length]).toEqual([r.citas, r.entrevistas, r.resueltas])
    expect(t.citas.length).toBeGreaterThan(t.resueltas.length) // hay citas sin resultado: no entran en la base
    expect(t.pctEntrevistas! / 100).toBeCloseTo(r.tasaEntrevistas!, 12)
    expect(proyeccion.filas.length).toBe(resultados.filas.length)
    for (const f of proyeccion.filas) {
      const rf = resultados.filas.find(x => x.id === f.id)!
      expect([f.id, f.citas.length, f.entrevistas.length, f.resueltas.length]).toEqual([rf.id, rf.citas, rf.entrevistas, rf.resueltas])
      expect(f.pctEntrevistas! / 100).toBeCloseTo(rf.tasaEntrevistas!, 12)
    }
  })

  it('% Conv.: las mismas personas vinculadas a cliente, en el total y por analista', () => {
    const { citas, conversiones, resultados, proyeccion } = escenario()
    const t = proyeccion.total, r = resultados.total
    // El escenario tiene ventas que la regla vieja (convertido_en ≥ asistencia) contaba y Resultados no.
    const asistencia = new Map(citas.filter(c => c.asistioEn).map(c => [c.leadId, Date.parse(c.asistioEn!)]))
    const vieja = conversiones.filter(c => asistencia.has(c.lead_id) && Date.parse(c.convertido_en) >= asistencia.get(c.lead_id)!)
    expect(vieja.length).toBeGreaterThan(r.clientes)
    expect(r.clientes).toBeGreaterThan(0)
    expect([t.personasEntrevistadas, t.personasClientes]).toEqual([r.unicas, r.clientes])
    expect(new Set(t.convertidas.map(c => c.cita.leadId))).toEqual(new Set(r.vinculados.map(c => c.lead_id)))
    expect(t.pctConversion! / 100).toBeCloseTo(r.conversion!, 12)
    for (const f of proyeccion.filas) {
      const rf = resultados.filas.find(x => x.id === f.id)!
      expect([f.id, f.personasEntrevistadas, f.personasClientes]).toEqual([rf.id, rf.unicas, rf.clientes])
    }
  })

  it('diferencia a propósito: una venta del mes siguiente cuenta en la Proyección (sigue su cohorte hasta el corte) y no en Resultados del mes', () => {
    const base = escenario()
    const sinVenta = base.proyeccion.total.entrevistas.find(e => !base.proyeccion.total.convertidas.includes(e))!
    const tardia = venta(sinVenta.cita, '2026-10-05T15:00:00Z', '2026-10-05')
    const { resultados, proyeccion } = escenario([tardia])
    expect(proyeccion.total.personasClientes).toBe(base.proyeccion.total.personasClientes + 1)
    expect(resultados.total.clientes).toBe(base.resultados.total.clientes)
  })
})

// Atribución de la venta (hallazgo P1 de Codex, 19/10/2026). Como Resultados: en
// la FILA, una entrevista cierra cliente solo con una venta de ESE analista; en el
// TOTAL, con la de cualquier dueño del ámbito (supervisor elegido y embudo de
// Analista), porque dos analistas que entrevistan a la misma persona colaboran.
// Cada caso se compara con `calcularAvanceCitas` real, por fila y en el total.
describe('Atribución de la venta: la fila y el total, como Resultados', () => {
  const EQUIPO: Record<string, string> = Object.fromEntries(ANALISTAS)
  const DIA = '2026-09-10'
  const PERSONA = 'persona:00000000-0000-4000-8000-0000000000f1'
  const entrevista = (id: string, analista: string, lead: string): CitaEjemplo => ({
    ...cita(0, { creadoEn: `${DIA}T14:00:00Z` }), id, leadId: lead, nombre: lead, analista, analistaNombre: analista,
    supervisor: EQUIPO[analista]!, supervisorId: EQUIPO[analista]!, hora: '10:00', estado: 'realizada', asistioEn: `${DIA}T15:30:00Z`,
  })
  /** Venta del 12/09 registrada por `analista` (con su supervisor). */
  const vendida = (lead: string, analista: string): Conversion => venta(entrevista('x', analista, lead), '2026-09-12T15:00:00Z', '2026-09-12')
  const persona = (lead_id: string, origen: string | null = null, identidad?: string): Persona => ({
    lead_id, nombre: lead_id, telefono: '900000000', origen: 'formulario', moneda: 'PEN', monto_estimado: 1000, registro_manual: false, creado_por: null,
    analista_origen_id: origen, analista_origen_nombre: origen ?? 'Sin analista', supervisor_origen_id: origen && EQUIPO[origen]!,
    supervisor_origen_nombre: origen ? EQUIPO[origen]! : 'Sin supervisor', primera_asignacion_en: null, ...(identidad ? { identidad_persona: identidad } : {}),
  })
  interface Caso { citas: CitaEjemplo[]; conversiones: Conversion[]; poblacion: Persona[] }
  interface Consulta { regla?: 'evento' | 'asignacion'; equipo?: string; analista?: string }
  const tasa = (x: number | null) => x === null ? null : Math.round(x * 1e9) / 1e9
  const tabla = (filas: readonly { id: string; pctConversion: number | null }[], total: number | null): Record<string, number | null> =>
    Object.fromEntries([...filas.map(f => [f.id, f.pctConversion] as const), ['total', total] as const])

  /** Corre Resultados y la Proyección sobre los MISMOS datos y exige las mismas cifras de conversión; devuelve el % Conv. por fila y total. */
  function comparar(caso: Caso, { regla = 'evento', equipo = '', analista = '' }: Consulta = {}) {
    const gestion: GestionCitas = {
      citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones: [],
      avance: { control: { version: 1, mes_inicio: '2026-09', configuracion: { ...controlCitasInicial(), analista_resultado: regla, mes_inicio: '2026-09' } },
        poblacion: caso.poblacion, conversiones: caso.conversiones, capital: [] },
    }
    const resultados = calcularAvanceCitas(gestion, caso.citas, { ...defaults('2026-09'), equipo, analista }, HOY, TC)
    // Igual que la pantalla: conversiones, población y regla del lector del avance.
    const proyeccion = calcularProyeccion({ citas: caso.citas, filtros: { equipo }, rango: SEPTIEMBRE, corte: HOY, tipoCambio: TC,
      conversiones: caso.conversiones, poblacion: caso.poblacion, analistaResultado: regla }, analista ? { analistas: [analista] } : {})
    const consulta = `${regla} · equipo «${equipo}» · analista «${analista}»`
    expect(proyeccion.filas.map(f => f.id).sort(), consulta).toEqual(resultados.filas.map(f => f.id).sort())
    for (const f of proyeccion.filas) {
      const rf = resultados.filas.find(x => x.id === f.id)!
      expect([f.personasEntrevistadas, f.personasClientes, tasa(f.pctConversion === null ? null : f.pctConversion / 100)], `${consulta} · ${f.id}`)
        .toEqual([rf.unicas, rf.clientes, tasa(rf.conversion)])
    }
    const t = proyeccion.total, r = resultados.total
    expect([t.personasEntrevistadas, t.personasClientes, tasa(t.pctConversion === null ? null : t.pctConversion / 100)], `${consulta} · total`)
      .toEqual([r.unicas, r.clientes, tasa(r.conversion)])
    return tabla(proyeccion.filas, t.pctConversion)
  }

  it('venta de otro analista: Ana y Luis entrevistan a la misma persona y vende Luis → 0 % Ana, 100 % Luis; el total del ámbito la reconoce', () => {
    const caso: Caso = { citas: [entrevista('a', 'ana', 'lead-p'), entrevista('l', 'luis', 'lead-p')], conversiones: [vendida('lead-p', 'luis')], poblacion: [persona('lead-p')] }
    expect(comparar(caso)).toEqual({ ana: 0, luis: 100, total: 100 })
    // Supervisor elegido: los dos son del equipo 1; el del otro equipo no ve a nadie.
    expect(comparar(caso, { equipo: 'sup-1' })).toEqual({ ana: 0, luis: 100, total: 100 })
    expect(comparar(caso, { equipo: 'sup-2' })).toEqual({ total: null })
    // Embudo de Analista solo con Ana: la venta de Luis queda fuera del ámbito, también en el total.
    expect(comparar(caso, { analista: 'ana' })).toEqual({ ana: 0, total: 0 })
    expect(comparar(caso, { analista: 'luis' })).toEqual({ luis: 100, total: 100 })
  })

  it('colaboración entre dos equipos: el total sin filtro la reconoce; con el supervisor de Ana elegido, la venta de Diego no cuenta', () => {
    const caso: Caso = { citas: [entrevista('a', 'ana', 'lead-q'), entrevista('d', 'diego', 'lead-q')], conversiones: [vendida('lead-q', 'diego')], poblacion: [persona('lead-q')] }
    expect(comparar(caso)).toEqual({ ana: 0, diego: 100, total: 100 })
    expect(comparar(caso, { equipo: 'sup-1' })).toEqual({ ana: 0, total: 0 })
    expect(comparar(caso, { equipo: 'sup-2' })).toEqual({ diego: 100, total: 100 })
    // Si vende Ana, es al revés.
    const deAna = { ...caso, conversiones: [vendida('lead-q', 'ana')] }
    expect(comparar(deAna, { equipo: 'sup-1' })).toEqual({ ana: 100, total: 100 })
    expect(comparar(deAna, { equipo: 'sup-2' })).toEqual({ diego: 0, total: 0 })
  })

  it('regla «asignacion»: la venta es del analista de origen del lead, no del que la registró', () => {
    // Una persona con dos leads: el de Ana (origen Ana) y el de Luis (origen Luis). La venta
    // entra por el lead de Luis, pero la registró Ana.
    const caso: Caso = {
      citas: [entrevista('a', 'ana', 'lead-1'), entrevista('l', 'luis', 'lead-2')], conversiones: [vendida('lead-2', 'ana')],
      poblacion: [persona('lead-1', 'ana', PERSONA), persona('lead-2', 'luis', PERSONA)],
    }
    expect(comparar(caso, { regla: 'evento' })).toEqual({ ana: 100, luis: 0, total: 100 })
    expect(comparar(caso, { regla: 'asignacion' })).toEqual({ ana: 0, luis: 100, total: 100 })
    expect(comparar(caso, { regla: 'evento', analista: 'ana' })).toEqual({ ana: 100, total: 100 })
    expect(comparar(caso, { regla: 'asignacion', analista: 'ana' })).toEqual({ ana: 0, total: 0 })
  })

  it('lote de septiembre con ventas de otro analista (del mismo equipo y del otro): iguales por fila y en el total, con y sin filtros', () => {
    const citas = citasDeSeptiembre()
    // La mitad de las ventas la registra el analista siguiente: Ana→Luis y Diego→Mateo (mismo equipo); Luis→Diego y Mateo→Ana (otro equipo).
    const siguiente = (c: CitaEjemplo): CitaEjemplo => {
      const [analista, supervisorId] = ANALISTAS[(ANALISTAS.findIndex(([a]) => a === c.analista) + 1) % ANALISTAS.length]!
      return { ...c, analista, analistaNombre: analista, supervisorId, supervisor: supervisorId }
    }
    const conversiones = ventasDeSeptiembre(citas, (c, i) => i % 2 ? c : siguiente(c))
    const caso: Caso = { citas, conversiones, poblacion: [...new Set(citas.map(c => c.leadId))].map(lead => persona(lead)) }
    // El lote tiene ventas cuya persona entrevistó otro analista y que el dueño de la venta no entrevistó.
    const entrevistadores = (lead: string) => citas.filter(c => c.leadId === lead && c.estado === 'realizada').map(c => c.analista)
    expect(conversiones.some(v => v.fecha_comercial && !entrevistadores(v.lead_id).includes(v.analista_id!))).toBe(true)
    const todos = comparar(caso)
    expect(Object.values(todos).some(v => (v ?? 0) > 0)).toBe(true)
    for (const consulta of [{ equipo: 'sup-1' }, { equipo: 'sup-2' }, ...ANALISTAS.map(([analista]) => ({ analista }))]) comparar(caso, consulta)
  })
})

// Fusión de meses: una cita que llega en dos meses (el lector entrega el historial
// de los leads de su cohorte) cuenta UNA vez, por id de cita.
describe('Fusión de meses del rango', () => {
  const crudo = (id: string, lead: string, creado: string, vence: string) => ({
    id, lead_id: lead, nombre: 'X', telefono: '1', analista_id: '00000000-0000-4000-8000-000000000001', analista_nombre: 'A',
    supervisor_id: null, supervisor_nombre: 'S', vence_en: vence, estado: 'pendiente' as const, estado_comercial: 'programada' as const,
    cancelada_por: null, modalidad: 'virtual', origen: 'formulario', moneda: 'PEN' as const, monto_estimado: 1000, resultado: 'sin_clasificar',
    nota: '', reagendada_de: null, creado_en: creado, asistencia_registrada_en: null, cierre_posterior: false, es_cliente: false,
  })
  const mes = (desde: string, hasta: string, citas: ReturnType<typeof crudo>[]) => ({
    version: 1, periodo: { desde, hasta }, generado_en: HOY, citas, citas_clientes: 0, disponibilidad_depositos: 'sin_registro', depositos: [],
  }) as unknown as ConsultaCitasRpc

  it('una cita creada el 30/09 con fecha en noviembre, presente en septiembre y octubre, cuenta una vez', () => {
    const L1 = '00000000-0000-4000-8000-0000000000a1', L2 = '00000000-0000-4000-8000-0000000000a2'
    const C1 = '00000000-0000-4000-8000-0000000000c1', C2 = '00000000-0000-4000-8000-0000000000c2', C3 = '00000000-0000-4000-8000-0000000000c3'
    const c1 = crudo(C1, L1, '2026-09-30T20:00:00Z', '2026-11-05T15:00:00Z')
    const c2 = crudo(C2, L1, '2026-10-02T20:00:00Z', '2026-10-03T15:00:00Z') // mismo lead, otra cita: NO se colapsa
    const c3 = crudo(C3, L2, '2026-10-05T20:00:00Z', '2026-10-06T15:00:00Z')
    const fusion = fusionarConsultasCitas([mes('2026-09-01', '2026-09-30', [c1]), mes('2026-10-01', '2026-10-31', [c1, c2, c3])])
    expect(fusion.citas.map(c => c.id).sort()).toEqual([C1, C2, C3])
    const hoja = calcularProyeccion({ citas: fusion.citas, filtros: { equipo: '' }, rango: { desde: '2026-09-25', hasta: '2026-10-19' }, corte: HOY,
      tipoCambio: TC, conversiones: null, tiempo: 'semanas' })
    expect(hoja.total.citas.length).toBe(3)
    // S4 25–30 set · S1 1–7 oct · S2 · S3: la cita fusionada cae una sola vez, en la semana de su creación.
    expect(hoja.total.porTramo.map(l => l.length)).toEqual([1, 2, 0, 0])
  })
})
