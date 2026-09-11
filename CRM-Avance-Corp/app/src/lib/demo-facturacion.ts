// lib/demo-facturacion.ts — FIXTURE DE EJEMPLO de la pantalla Facturación.
//
// Existe para el MODO DEMO: el fixture general tiene tres contratos de un solo
// analista y de meses pasados, con lo que la malla saldría vacía y no se podría
// enseñar la pantalla. La fuente real es `crm.facturacion_diaria_fn`, que ya
// está en producción; esto NO se usa con una sesión real.
//
// La pantalla rotula estos datos como ejemplo, siempre y de forma visible
// (regla A3 de honestidad: una cifra inventada nunca se presenta como real).
//
// Devuelve EXACTAMENTE la misma forma que `crm.facturacion_diaria_fn`: filas ya
// agrupadas por día, tipo, moneda, analista y supervisor. Que el demo no pueda
// enseñar más detalle que producción es deliberado — es la trampa que el gate de
// realidad del proyecto persigue: una pantalla que en demo promete algo que
// arriba no existe.
import type { Moneda } from './format'
import type { FilaFacturacionDia } from './facturacion'
import { diasDelMes, diaSemana, TIPO_CAPITAL_NUEVO } from './facturacion'

interface PlantillaAnalista {
  readonly id: string
  readonly nombre: string
  /** Fuerza relativa: 1 es un analista promedio. */
  readonly nivel: number
}

interface PlantillaEquipo {
  readonly id: string
  readonly supervisor: string
  readonly analistas: readonly PlantillaAnalista[]
}

const EQUIPOS: readonly PlantillaEquipo[] = [
  {
    id: 'f-sup1',
    supervisor: 'Valeria Mendoza',
    analistas: [
      { id: 'f-a01', nombre: 'Katherine Ríos', nivel: 1.3 },
      { id: 'f-a02', nombre: 'Jorge Palomino', nivel: 0.95 },
      { id: 'f-a03', nombre: 'Milagros Ávila', nivel: 1.05 },
      { id: 'f-a04', nombre: 'Sergio Núñez', nivel: 0.62 },
      { id: 'f-a05', nombre: 'Ana Lucía Quispe', nivel: 0.86 },
    ],
  },
  {
    id: 'f-sup2',
    supervisor: 'Gustavo Paredes',
    analistas: [
      { id: 'f-a06', nombre: 'Renzo Carrasco', nivel: 1.18 },
      { id: 'f-a07', nombre: 'Pamela Ortiz', nivel: 1.02 },
      { id: 'f-a08', nombre: 'Iván Huamán', nivel: 0.55 },
      { id: 'f-a09', nombre: 'Claudia Bermúdez', nivel: 0.92 },
    ],
  },
  {
    id: 'f-sup3',
    supervisor: 'Ximena Arce',
    analistas: [
      { id: 'f-a10', nombre: 'Andrés Tapia', nivel: 0.8 },
      { id: 'f-a11', nombre: 'Lucero Vega', nivel: 1.34 },
      { id: 'f-a12', nombre: 'Marco Ruiz', nivel: 0.72 },
      { id: 'f-a13', nombre: 'Fiorella Chávez', nivel: 1.0 },
    ],
  },
]


/** Peso comercial de cada día de la semana (domingo no se vende). */
const FACTOR_DIA = [0, 1.12, 1.02, 0.98, 1.06, 1.18, 0.34] as const

/**
 * Generador determinista (mulberry32). El fixture NO usa Math.random: la misma
 * pantalla tiene que dar las mismas cifras entre recargas, o revisar el diseño
 * con Miguel sería imposible.
 */
function semilla(texto: string): () => number {
  let a = 0
  for (let i = 0; i < texto.length; i += 1) a = (a * 31 + texto.charCodeAt(i)) | 0
  return () => {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/**
 * Filas de ejemplo del mes, con la forma de la RPC. `hasta` (una fecha
 * 'YYYY-MM-DD') corta el mes en curso: los días que aún no han pasado salen
 * vacíos, como en la realidad.
 */
export function filasFacturacionDemo(mes: string, hasta: string): FilaFacturacionDia[] {
  const azar = semilla(`facturacion:${mes}`)
  // Se acumula por (día, moneda) y se emite UNA fila por combinación, que es lo
  // que devuelve el servidor. Emitir una fila por venta daría un total idéntico
  // pero una forma distinta, y la pantalla dejaría de probarse contra lo real.
  const cubos = new Map<string, { operaciones: number; capital: number }>()
  const filas: FilaFacturacionDia[] = []

  for (const equipo of EQUIPOS) {
    for (const analista of equipo.analistas) {
      for (const dia of diasDelMes(mes)) {
        if (dia > hasta) continue
        const factor = FACTOR_DIA[diaSemana(dia)] ?? 0
        const lambda = analista.nivel * factor * 1.06
        const tirada = azar()
        let cuantos = 0
        if (tirada < lambda * 0.62) cuantos = 1
        if (tirada < lambda * 0.24) cuantos = 2
        if (tirada < lambda * 0.06) cuantos = 3

        for (let k = 0; k < cuantos; k += 1) {
          const esUsd = azar() < 0.19
          const base = azar()
          const capital = esUsd
            ? Math.round((5000 + base * base * 58000) / 500) * 500
            : Math.round((18000 + base * base * 245000) / 500) * 500
          const moneda: Moneda = esUsd ? 'USD' : 'PEN'
          const clave = `${dia}|${moneda}`
          const cubo = cubos.get(clave) ?? { operaciones: 0, capital: 0 }
          cubos.set(clave, { operaciones: cubo.operaciones + 1, capital: cubo.capital + capital })
        }
      }

      for (const [clave, cubo] of cubos) {
        const [diaCubo = '', monedaCubo = 'PEN'] = clave.split('|')
        filas.push({
          dia: diaCubo,
          tipo: TIPO_CAPITAL_NUEVO,
          moneda: monedaCubo === 'USD' ? 'USD' : 'PEN',
          analistaId: analista.id,
          analistaNombre: analista.nombre,
          supervisorId: equipo.id,
          supervisorNombre: equipo.supervisor,
          operaciones: cubo.operaciones,
          capital: cubo.capital,
        })
      }
      cubos.clear()
    }
  }
  return filas
}
