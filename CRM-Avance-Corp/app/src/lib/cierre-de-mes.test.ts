import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { CierreMesEstadoSchema, avisoDelCiclo } from './cierre-de-mes'

/**
 * Los cinco payloads son la salida VERBATIM de ejecutar
 * `crm.cierre_mes_estado_fn` en el banco local con las migraciones reales
 * (generador: `supabase/scripts/fixture-cierre-mes-estado.sql`, corrido el
 * 2026-08-15). `en_ventana` y `hoy` salen de la copia con costura de reloj,
 * cuya fidelidad a la función real se comprueba dentro del propio generador.
 *
 * `mes_nombre` llega en inglés («June») porque el calco local de
 * `private.etiqueta_mes_es` usa el locale C; el contrato solo exige texto no
 * vacío, así que prueba lo mismo que con el nombre en español.
 */

const QUIETO = {
  hoy: '2026-08-15',
  zona: 'America/Lima',
  version: 1,
  pendiente: null,
  generado_en: '2026-08-15T20:34:50.843856-05:00',
  mes_en_curso: {
    mes: '2026-08',
    cierra_el: '2026-09-10',
    mes_nombre: 'August',
  },
  ultimo_cerrado: null,
}

const ATASCADO = {
  hoy: '2026-08-15',
  zona: 'America/Lima',
  version: 1,
  pendiente: {
    mes: '2026-06',
    estado: 'atascado',
    cierra_el: '2026-07-10',
    mes_nombre: 'June',
    dias_para_cierre: 0,
  },
  generado_en: '2026-08-15T20:34:50.843856-05:00',
  mes_en_curso: {
    mes: '2026-08',
    cierra_el: '2026-09-10',
    mes_nombre: 'August',
  },
  ultimo_cerrado: null,
}

const EN_VENTANA = {
  hoy: '2026-07-05',
  zona: 'America/Lima',
  version: 1,
  pendiente: {
    mes: '2026-06',
    estado: 'en_ventana',
    cierra_el: '2026-07-10',
    mes_nombre: 'June',
    dias_para_cierre: 5,
  },
  generado_en: '2026-07-05T12:00:00-05:00',
  mes_en_curso: {
    mes: '2026-07',
    cierra_el: '2026-08-10',
    mes_nombre: 'July',
  },
  ultimo_cerrado: null,
}

const HOY = {
  hoy: '2026-07-10',
  zona: 'America/Lima',
  version: 1,
  pendiente: {
    mes: '2026-06',
    estado: 'hoy',
    cierra_el: '2026-07-10',
    mes_nombre: 'June',
    dias_para_cierre: 0,
  },
  generado_en: '2026-07-10T09:20:00-05:00',
  mes_en_curso: {
    mes: '2026-07',
    cierra_el: '2026-08-10',
    mes_nombre: 'July',
  },
  ultimo_cerrado: null,
}

const SELLADO = {
  hoy: '2026-08-15',
  zona: 'America/Lima',
  version: 1,
  pendiente: null,
  generado_en: '2026-08-15T20:34:50.843856-05:00',
  mes_en_curso: {
    mes: '2026-08',
    cierra_el: '2026-09-10',
    mes_nombre: 'August',
  },
  ultimo_cerrado: {
    mes: '2026-06',
    automatico: true,
    cerrado_en: '2026-08-15T20:34:50.843856-05:00',
    mes_nombre: 'June',
  },
}

describe('el contrato del estado del ciclo acepta los cinco payloads reales', () => {
  it('quieto: nada pendiente y nada sellado — el día del estreno en producción', () => {
    const estado = v.parse(CierreMesEstadoSchema, QUIETO)
    expect(estado.pendiente).toBeNull()
    expect(estado.ultimo_cerrado).toBeNull()
    expect(estado.mes_en_curso.cierra_el).toBe('2026-09-10')
  })

  it('atascado: la ventana pasó hace más de un día y nadie selló — LA ALARMA', () => {
    const estado = v.parse(CierreMesEstadoSchema, ATASCADO)
    expect(estado.pendiente?.estado).toBe('atascado')
    expect(estado.pendiente?.dias_para_cierre).toBe(0)
  })

  it('en_ventana: del 1 al 10 todavía se corrige — el aviso normal', () => {
    const estado = v.parse(CierreMesEstadoSchema, EN_VENTANA)
    expect(estado.pendiente?.estado).toBe('en_ventana')
    expect(estado.pendiente?.dias_para_cierre).toBe(5)
  })

  it('hoy: la ventana abrió a medianoche y el ciclo corre a las 09:20 — NO es alarma', () => {
    const estado = v.parse(CierreMesEstadoSchema, HOY)
    expect(estado.pendiente?.estado).toBe('hoy')
    expect(estado.pendiente?.dias_para_cierre).toBe(0)
  })

  it('sellado: nada pendiente y el último mes cerrado con autoría automática', () => {
    const estado = v.parse(CierreMesEstadoSchema, SELLADO)
    expect(estado.pendiente).toBeNull()
    expect(estado.ultimo_cerrado?.automatico).toBe(true)
    expect(estado.ultimo_cerrado?.mes).toBe('2026-06')
  })
})

describe('el contrato sigue fail-closed', () => {
  it('rechaza una clave que nadie declaró', () => {
    expect(() =>
      v.parse(CierreMesEstadoSchema, { ...QUIETO, algo_que_nadie_declaro: 1 }),
    ).toThrow()
  })

  it('rechaza una versión de payload que este front no entiende', () => {
    expect(() => v.parse(CierreMesEstadoSchema, { ...QUIETO, version: 2 })).toThrow()
  })

  it('rechaza un estado del pendiente fuera de los tres nombrados', () => {
    expect(() =>
      v.parse(CierreMesEstadoSchema, {
        ...ATASCADO,
        pendiente: { ...ATASCADO.pendiente, estado: 'manana' },
      }),
    ).toThrow()
  })
})

describe('avisoDelCiclo — el texto del banner desde el estado que nombra el servidor', () => {
  const parsear = (payload: unknown) => v.parse(CierreMesEstadoSchema, payload)

  it('sin mes pendiente no hay banner: la cadencia gobierna los avisos', () => {
    expect(avisoDelCiclo(parsear(QUIETO))).toBeNull()
    expect(avisoDelCiclo(parsear(SELLADO))).toBeNull()
  })

  it('en_ventana: aviso con la fecha del sello y los días que quedan', () => {
    const aviso = avisoDelCiclo(parsear(EN_VENTANA))
    expect(aviso?.tono).toBe('aviso')
    expect(aviso?.titulo).toBe('June se cierra el 10 jul. 2026')
    expect(aviso?.detalle).toContain('Quedan 5 días de ajuste')
  })

  it('con 1 día habla en singular', () => {
    const unDia = {
      ...EN_VENTANA,
      pendiente: { ...EN_VENTANA.pendiente, dias_para_cierre: 1 },
    }
    expect(avisoDelCiclo(parsear(unDia))?.detalle).toContain('Queda 1 día de ajuste')
  })

  it('hoy: aviso con la hora del ciclo — NO es alarma', () => {
    const aviso = avisoDelCiclo(parsear(HOY))
    expect(aviso?.tono).toBe('aviso')
    expect(aviso?.titulo).toBe('June se cierra hoy')
    expect(aviso?.detalle).toContain('09:20')
  })

  it('atascado: LA ALARMA, con la fecha en que debió sellarse', () => {
    const aviso = avisoDelCiclo(parsear(ATASCADO))
    expect(aviso?.tono).toBe('alarma')
    expect(aviso?.titulo).toBe('El cierre de June está atascado')
    expect(aviso?.detalle).toContain('Debió sellarse el 10 jul. 2026')
    // No afirma la causa: un mes reabierto a propósito o con el ciclo en pausa
    // también sigue abierto (agosto, 17/09/2026).
    expect(aviso?.detalle).toMatch(/se reabrió a propósito/)
    expect(aviso?.detalle).not.toMatch(/no lo consiguió/)
  })
})
