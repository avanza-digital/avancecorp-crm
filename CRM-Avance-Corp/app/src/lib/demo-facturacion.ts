// lib/demo-facturacion.ts — FIXTURE DE EJEMPLO de la pantalla Facturación.
//
// Existe porque la fuente real (una RPC diaria de capital cerrado por analista)
// todavía no está construida, y porque el fixture general del modo demo tiene
// tres contratos de un solo analista y meses pasados: con eso la malla sale
// vacía y no se puede juzgar el diseño.
//
// La pantalla rotula estos datos como ejemplo, siempre y de forma visible
// (regla A3 de honestidad: una cifra inventada nunca se presenta como real).
// Cuando exista la RPC, este módulo desaparece o queda solo para las pruebas.
import type { ContratoFacturado } from './facturacion'
import { diasDelMes, diaSemana } from './facturacion'

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

const CLIENTES = [
  'Rosa Ccahuana Lipa', 'Julio Barrantes Vera', 'Elena Portocarrero',
  'Hugo Mendieta Ríos', 'Carmen Zapata Loli', 'Óscar Valdivia Núñez',
  'Teresa Ampuero Salas', 'Luis Felipe Cárdenas', 'Norma Huerta Sáenz',
  'Alberto Ramos Pinto', 'Sofía Delgado Arana', 'Wilfredo Ticona Mamani',
  'Beatriz Salcedo Mur', 'Enrique Bustamante', 'Gladys Quintanilla',
  'Raúl Espinoza Yáñez', 'Mercedes Trujillo Paz', 'Iván Berrocal Paz',
  'Pilar Gonzales Ávila', 'Fernando Ríos Cabrera',
] as const

const PRODUCTOS = [
  'Renta Fija 6 meses', 'Renta Fija 12 meses',
  'Renta Fija 18 meses', 'Renta Fija 24 meses',
] as const

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

function tomar<T>(lista: readonly T[], azar: number, respaldo: T): T {
  return lista[Math.floor(azar * lista.length)] ?? respaldo
}

/**
 * Contratos de ejemplo del mes. `hasta` (una fecha 'YYYY-MM-DD') corta el mes en
 * curso: los días que aún no han pasado salen vacíos, como en la realidad.
 */
export function contratosFacturacionDemo(mes: string, hasta: string): ContratoFacturado[] {
  const azar = semilla(`facturacion:${mes}`)
  const contratos: ContratoFacturado[] = []
  let correlativo = 1000 + (Number(mes.slice(5, 7)) || 1) * 40

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
          correlativo += 1
          contratos.push({
            id: `f-c${correlativo}`,
            numero: String(correlativo).padStart(6, '0'),
            cliente: tomar(CLIENTES, azar(), 'Cliente de ejemplo'),
            producto: tomar(PRODUCTOS, azar(), 'Renta Fija 12 meses'),
            tasaAnual: 11.5 + Math.round(azar() * 13) * 0.5,
            moneda: esUsd ? 'USD' : 'PEN',
            capital,
            dia,
            analistaId: analista.id,
            analistaNombre: analista.nombre,
            supervisorId: equipo.id,
            supervisorNombre: equipo.supervisor,
          })
        }
      }
    }
  }
  return contratos
}
