/**
 * El payload de `crm.cumplimiento_metas_fn` DESPUÉS del CIERRE DE MES
 * (migraciones `20260815*`, en producción el 2026-08-15).
 *
 * 🔴 POR QUÉ EXISTE ESTE FICHERO. El servidor del cierre de mes se desplegó
 * primero y empezó a mandar dos claves nuevas —`cierre` arriba y `ajuste` en
 * cada vendedor—. `CumplimientoMetasSchema` es `v.strictObject`, o sea que falla
 * tanto por clave de MÁS como por clave de MENOS: rechazó el payload ENTERO y
 * los tres roles se quedaron sin cumplimiento a la vez, con un «Reintentar» que
 * no podía funcionar nunca. Ni los 1007 controles de RLS ni las 1.648 unitarias
 * lo vieron, porque todos montan payloads que ya encajan.
 *
 * La regla que lo habría evitado ya estaba escrita: **clave nueva en la
 * RESPUESTA de una RPC → el FRONT se despliega primero**.
 *
 * LOS FIXTURES NO ESTÁN ESCRITOS A MANO. Son la salida literal de ejecutar la
 * función ya migrada contra un Postgres 16 local con los calcos de producción
 * (`supabase/scripts/banco-local-cierre-mes.sql` + las siete `20260815*`),
 * sembrando un mes con actividad y sellándolo con `crm.cerrar_periodo`. La forma
 * del mes VIVO se contrastó además contra producción el 2026-08-15: idéntica.
 *
 * Los dos mundos importan y son distintos:
 *   · MES VIVO    — `cierre: {cerrado:false}` y `ajuste: {pendiente}`.
 *   · MES SELLADO — `cierre` con fecha y autoría, y `ajuste` con el desglose
 *                   `aplicado*`. Esta rama NO se estrenará hasta el 10/09/2026:
 *                   sin este fixture, el mismo apagón volvería ese día.
 */
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { CumplimientoMetasSchema, cumplimientoDesdeRpc } from './objetivos'

/** Salida VERBATIM de `crm.cumplimiento_metas_fn(<mes vivo>)`. */
const PAGO_MES_VIVO = {
  cierre: {
    cerrado: false
  },
  periodo: "2026-01-01",
  version: 1,
  revision: 1,
  vendedores: [
    {
      ajuste: {
        pendiente: 0
      },
      nombre: "VENDEDOR DE PRUEBA",
      detalles: [
        {
          moneda: "PEN",
          categoria: "nuevo",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 100000,
          contratos_objetivo: 5,
          capital_cumplimiento_pct: 0.0,
          contratos_cumplimiento_pct: 0.0
        },
        {
          moneda: "USD",
          categoria: "nuevo",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "renovacion",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "renovacion",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "upgrade",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "upgrade",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        }
      ],
      numerador: 0.0,
      resueltos: 0,
      convertidos: 0,
      vendedor_id: "33333333-3333-4333-8333-333333333333",
      supervisor_id: "22222222-2222-4222-8222-222222222222",
      conversion_real: null,
      cierres_referidos: 0,
      supervisor_nombre: "SUPERVISOR DE PRUEBA",
      conversion_objetivo: 15,
      cierres_no_referidos: 0
    },
    {
      ajuste: {
        pendiente: 0
      },
      nombre: "VENDEDOR SIN MUESTRA",
      detalles: [
        {
          moneda: "PEN",
          categoria: "nuevo",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 250000,
          contratos_objetivo: 8,
          capital_cumplimiento_pct: 0.0,
          contratos_cumplimiento_pct: 0.0
        },
        {
          moneda: "USD",
          categoria: "nuevo",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "renovacion",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "renovacion",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "upgrade",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "upgrade",
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        }
      ],
      numerador: 0,
      resueltos: 0,
      convertidos: 0,
      vendedor_id: "33333333-3333-4333-8333-333333333334",
      supervisor_id: "22222222-2222-4222-8222-222222222222",
      conversion_real: null,
      cierres_referidos: 0,
      supervisor_nombre: "SUPERVISOR DE PRUEBA",
      conversion_objetivo: 40,
      cierres_no_referidos: 0
    }
  ],
  publicada_en: "2026-08-15T15:16:23.584211-05:00",
  fuentes_reales: {
    conversion: "leads_recibidos_ponderado",
    capital_y_contratos: "contratos_confirmados"
  },
  ponderacion_referido: 0.15
} as const

/** Salida VERBATIM de `crm.cumplimiento_metas_fn(<mes sellado>)`. */
const PAGO_MES_SELLADO = {
  cierre: {
    cerrado: true,
    automatico: true,
    cerrado_en: "2026-08-15T15:16:23.584211-05:00"
  },
  periodo: "2025-12-01",
  version: 1,
  revision: 1,
  vendedores: [
    {
      ajuste: {
        aplicado: 0,
        pendiente: 0,
        aplicado_pen: 0,
        aplicado_usd: 0
      },
      nombre: "VENDEDOR DE PRUEBA",
      detalles: [
        {
          moneda: "PEN",
          categoria: "nuevo",
          capital_real: 40000,
          capital_ajuste: 0,
          contratos_real: 1,
          capital_objetivo: 100000,
          contratos_ajuste: 0,
          contratos_objetivo: 5,
          capital_cumplimiento_pct: 40.0,
          contratos_cumplimiento_pct: 20.0
        },
        {
          moneda: "USD",
          categoria: "nuevo",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "renovacion",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "renovacion",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "upgrade",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "upgrade",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        }
      ],
      numerador: 1.15,
      resueltos: 4,
      convertidos: 2,
      vendedor_id: "33333333-3333-4333-8333-333333333333",
      supervisor_id: "22222222-2222-4222-8222-222222222222",
      conversion_real: 28.75,
      cierres_referidos: 1,
      supervisor_nombre: "SUPERVISOR DE PRUEBA",
      conversion_objetivo: 15,
      cierres_no_referidos: 1
    },
    {
      ajuste: {
        aplicado: 0,
        pendiente: 0,
        aplicado_pen: 0,
        aplicado_usd: 0
      },
      nombre: "VENDEDOR SIN MUESTRA",
      detalles: [
        {
          moneda: "PEN",
          categoria: "nuevo",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 250000,
          contratos_ajuste: 0,
          contratos_objetivo: 8,
          capital_cumplimiento_pct: 0.0,
          contratos_cumplimiento_pct: 0.0
        },
        {
          moneda: "USD",
          categoria: "nuevo",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "renovacion",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "renovacion",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "PEN",
          categoria: "upgrade",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        },
        {
          moneda: "USD",
          categoria: "upgrade",
          capital_real: 0,
          capital_ajuste: 0,
          contratos_real: 0,
          capital_objetivo: 0,
          contratos_ajuste: 0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null
        }
      ],
      numerador: 0,
      resueltos: 0,
      convertidos: 0,
      vendedor_id: "33333333-3333-4333-8333-333333333334",
      supervisor_id: "22222222-2222-4222-8222-222222222222",
      conversion_real: null,
      cierres_referidos: 0,
      supervisor_nombre: "SUPERVISOR DE PRUEBA",
      conversion_objetivo: 40,
      cierres_no_referidos: 0
    }
  ],
  publicada_en: "2026-08-15T15:16:23.584211-05:00",
  fuentes_reales: {
    conversion: "leads_recibidos_ponderado",
    capital_y_contratos: "contratos_confirmados"
  },
  ponderacion_referido: 0.15
} as const


const VENDEDOR = '33333333-3333-4333-8333-333333333333'

describe('payload de cumplimiento tras el cierre de mes', () => {
  it('EL FALLO REAL: el mes vivo parsea con las dos claves nuevas', () => {
    // Este es exactamente el payload que producción devolvió el 2026-08-15 y que
    // el bundle desplegado rechazaba. Si esto se pone rojo, la pantalla de metas
    // está apagada para gerencia, supervisores y vendedores a la vez.
    const parseado = v.parse(CumplimientoMetasSchema, PAGO_MES_VIVO)

    expect(parseado.cierre?.cerrado).toBe(false)
    expect(parseado.vendedores).toHaveLength(2)
    expect(parseado.vendedores.every((fila) => fila.ajuste !== undefined)).toBe(true)
  })

  it('LA BOMBA DEL 10/09: la foto de un mes sellado también parsea', () => {
    // Esta rama no la ejerce ningún usuario hasta el primer cierre automático.
    // Leerla no basta: el fixture sale de sellar un mes de verdad.
    const parseado = v.parse(CumplimientoMetasSchema, PAGO_MES_SELLADO)

    expect(parseado.cierre?.cerrado).toBe(true)
    expect(parseado.cierre?.cerrado_en).toBeTruthy()
    expect(parseado.cierre?.automatico).toBe(true)
  })

  it('el desglose del descuento solo viaja en la foto, y el mes vivo no lo trae', () => {
    // Dos formas del MISMO campo. Si el esquema exigiera `aplicado` siempre, el
    // mes vivo se caería; si prohibiera los `aplicado*`, se caería la foto.
    const vivo = v.parse(CumplimientoMetasSchema, PAGO_MES_VIVO)
    const sellado = v.parse(CumplimientoMetasSchema, PAGO_MES_SELLADO)

    expect(vivo.vendedores[0]!.ajuste).toEqual({ pendiente: 0 })
    expect(sellado.vendedores[0]!.ajuste).toEqual({
      pendiente: 0, aplicado: 0, aplicado_pen: 0, aplicado_usd: 0,
    })
  })

  it('la VUELTA ATRÁS no exige redespliegue: sin las claves nuevas sigue parseando', () => {
    // La migración tiene su sección de vuelta atrás. Si se ejerciera, las dos
    // claves desaparecen — y un strictObject falla también por clave de MENOS.
    const { cierre: _c, ...raiz } = PAGO_MES_VIVO
    const viejo = {
      ...raiz,
      vendedores: PAGO_MES_VIVO.vendedores.map(({ ajuste: _a, ...resto }) => resto),
    }

    const parseado = v.parse(CumplimientoMetasSchema, viejo)
    expect(parseado.cierre).toBeUndefined()
    expect(parseado.vendedores[0]!.ajuste).toBeUndefined()
  })

  it('el fail-closed SIGUE puesto: una clave desconocida se rechaza igual', () => {
    // La reparación fue AÑADIR las claves que el servidor manda, no aflojar la
    // validación. Si alguien la relajara para «que no vuelva a pasar», este test
    // lo caza: el día que el servidor cambie el SIGNIFICADO de un campo, el front
    // debe seguir negándose a pintar cifras que no entiende.
    const intruso = { ...PAGO_MES_VIVO, algo_que_nadie_declaro: 1 }
    expect(v.safeParse(CumplimientoMetasSchema, intruso).success).toBe(false)
  })

  it('la pantalla sigue calculando lo de siempre con el payload nuevo', () => {
    // Que parsee no basta: el dato tiene que llegar entero a la pantalla.
    const parseado = v.parse(CumplimientoMetasSchema, PAGO_MES_SELLADO)
    const jerarquico = cumplimientoDesdeRpc(parseado, VENDEDOR)

    // numerador 1,15 sobre divisor 4 = 28,75 % (un cierre no referido + uno
    // referido al 15 %), contra una meta del 15 %.
    expect(jerarquico.porVendedor[VENDEDOR]?.conversionReal).toBe(28.75)
    expect(jerarquico.porVendedor[VENDEDOR]?.conversionObjetivo).toBe(15)
  })
})
