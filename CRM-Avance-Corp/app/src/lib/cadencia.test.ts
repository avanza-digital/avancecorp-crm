// Contrato de la SALIDA de la cadencia.
//
// Esto es lo único del sistema que empuja hacia CERRAR un lead, así que los dos
// umbrales son la protección: cinco intentos y tres días. El caso que más
// importa no es el positivo, es el falso positivo — cinco taps de "No contestó"
// en una misma tarde no pueden proponer cerrar un lead asignado esta mañana.
import { describe, expect, it } from 'vitest'
import { DIAS_PARA_PROPONER_CIERRE, INTENTOS_PARA_PROPONER_CIERRE, plantonDe } from './cadencia'
import type { Actividad, TipoActividad } from './tipos'

const AHORA = Date.UTC(2026, 6, 25, 15)
const DIA = 86_400_000
const haceDias = (d: number) => new Date(AHORA - d * DIA).toISOString()

const act = (tipo: TipoActividad, dias: number): Actividad => ({
  id: `${tipo}-${dias}`,
  lead_id: 'l1',
  tipo,
  detalle: null,
  autor_nombre: 'ANALISTA UNO',
  creado_en: haceDias(dias),
})

/** N intentos repartidos uno por día, el más viejo hace `desdeDias`. */
const racha = (n: number, desdeDias: number): Actividad[] =>
  Array.from({ length: n }, (_, i) => act('llamada_no_contestada', desdeDias - i * (desdeDias / n)))

describe('plantonDe — cuándo el motor deja de proponer otro toque', () => {
  it('con la racha completa y días de por medio, propone cerrar', () => {
    const p = plantonDe(racha(INTENTOS_PARA_PROPONER_CIERRE, 9), AHORA)
    expect(p).toMatchObject({ intentos: INTENTOS_PARA_PROPONER_CIERRE })
    expect(p?.dias).toBeCloseTo(9, 0)
  })

  it('un intento por debajo del corte NO propone nada', () => {
    expect(plantonDe(racha(INTENTOS_PARA_PROPONER_CIERRE - 1, 9), AHORA)).toBeNull()
  })

  it('CINCO TAPS EN UNA TARDE no cierran a nadie — ese es el falso positivo caro', () => {
    // Cada tap desde la cola escribe una actividad. Sin el umbral temporal,
    // media hora de insistencia propondría descartar un lead de esta mañana.
    const mismaTarde = Array.from({ length: 6 }, (_, i) => act('llamada_no_contestada', 0.1 * i))
    expect(plantonDe(mismaTarde, AHORA)).toBeNull()
  })

  it(`justo por debajo de ${DIAS_PARA_PROPONER_CIERRE} días tampoco`, () => {
    expect(plantonDe(racha(6, DIAS_PARA_PROPONER_CIERRE - 0.5), AHORA)).toBeNull()
  })

  it('si el cliente RESPONDIÓ, el contador vuelve a cero', () => {
    // Seis intentos viejos y una respuesta ayer: la racha vigente es de cero.
    // "No responde" describe el tramo actual, no la vida entera del lead.
    const acts = [...racha(6, 20), act('whatsapp_recibido', 1)]
    expect(plantonDe(acts, AHORA)).toBeNull()
  })

  it('tras la respuesta, una racha NUEVA vuelve a contar', () => {
    const acts = [act('whatsapp_recibido', 30), ...racha(INTENTOS_PARA_PROPONER_CIERRE, 10)]
    expect(plantonDe(acts, AHORA)).not.toBeNull()
  })

  it('las CONVERSACIONES no son intentos: hablar no acerca al descarte', () => {
    const hablados = Array.from({ length: 8 }, (_, i) => act('llamada_realizada', 10 - i))
    expect(plantonDe(hablados, AHORA)).toBeNull()
  })

  it('las notas y lo que emite el sistema tampoco cuentan', () => {
    const ruido = [
      ...Array.from({ length: 4 }, (_, i) => act('nota', 10 - i)),
      ...Array.from({ length: 4 }, (_, i) => act('reasignacion', 9 - i)),
    ]
    expect(plantonDe(ruido, AHORA)).toBeNull()
  })

  it('un timeline vacío nunca propone cerrar', () => {
    expect(plantonDe([], AHORA)).toBeNull()
  })
})
