/**
 * El payload de `crm.cumplimiento_metas_fn` DESPUÉS de la migración B.
 *
 * Por qué existe este fichero: hasta hoy ningún test ejercitaba el payload
 * post-B de punta a punta. El diseño decía que el front lo toleraba (claves
 * `v.optional`, picklist con los dos literales, `conversion_real` sin techo),
 * pero «lo dice el diseño» no es una prueba — y el modo de fallo de B es que
 * los TRES roles se quedan sin metas a la vez, porque `CumplimientoMetasSchema`
 * es un `v.strictObject` que falla tanto por clave de MÁS como por clave de
 * MENOS.
 *
 * El fixture NO está escrito a mano: es la salida literal de ejecutar la
 * función ya migrada contra un Postgres 16 local con el esquema de producción
 * (2026-08-13). Un literal inventado por el test probaría el test, no el
 * servidor.
 *
 * El caso sembrado es el que rompe los invariantes viejos a propósito:
 *   · Ana:  conversión 132,5 % — pasa de 100 porque el arrastre y los referidos
 *           suman ARRIBA y no abajo, y `convertidos` (7) es MAYOR que
 *           `resueltos` (4), que ahora son RECIBIDOS y no resueltos.
 *   · Beto: sin muestra — divisor 0 y conversión null (la rama que degrada).
 */
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  CumplimientoMetasSchema,
  cumplimientoDesdeRpc,
} from './objetivos'
import { derivarAlertasGerencia } from './alertas-gerencia'

/** Salida VERBATIM de `crm.cumplimiento_metas_fn('2026-08-01')` ya con la B. */
const PAYLOAD_POST_B = {
  periodo: '2026-08-01',
  version: 1,
  revision: 3,
  vendedores: [
    {
      nombre: 'Ana Torres',
      detalles: [
        {
          moneda: 'PEN',
          categoria: 'nuevo',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 250000.0,
          contratos_objetivo: 5,
          capital_cumplimiento_pct: 0.0,
          contratos_cumplimiento_pct: 0.0,
        },
        {
          moneda: 'USD',
          categoria: 'nuevo',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'PEN',
          categoria: 'renovacion',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'USD',
          categoria: 'renovacion',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'PEN',
          categoria: 'upgrade',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'USD',
          categoria: 'upgrade',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
      ],
      numerador: 5.3,
      resueltos: 4,
      convertidos: 7,
      vendedor_id: '11111111-1111-1111-1111-111111111111',
      supervisor_id: '33333333-3333-3333-3333-333333333333',
      conversion_real: 132.5,
      cierres_referidos: 2,
      supervisor_nombre: 'Maria Salazar',
      conversion_objetivo: 40.0,
      cierres_no_referidos: 5,
    },
    {
      nombre: 'Beto Ruiz',
      detalles: [
        {
          moneda: 'PEN',
          categoria: 'nuevo',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 250000.0,
          contratos_objetivo: 5,
          capital_cumplimiento_pct: 0.0,
          contratos_cumplimiento_pct: 0.0,
        },
        {
          moneda: 'USD',
          categoria: 'nuevo',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'PEN',
          categoria: 'renovacion',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'USD',
          categoria: 'renovacion',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'PEN',
          categoria: 'upgrade',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
        {
          moneda: 'USD',
          categoria: 'upgrade',
          capital_real: 0,
          contratos_real: 0,
          capital_objetivo: 0.0,
          contratos_objetivo: 0,
          capital_cumplimiento_pct: null,
          contratos_cumplimiento_pct: null,
        },
      ],
      numerador: 0,
      resueltos: 0,
      convertidos: 0,
      vendedor_id: '22222222-2222-2222-2222-222222222222',
      supervisor_id: '33333333-3333-3333-3333-333333333333',
      conversion_real: null,
      cierres_referidos: 0,
      supervisor_nombre: 'Maria Salazar',
      conversion_objetivo: 40.0,
      cierres_no_referidos: 0,
    },
  ],
  publicada_en: '2026-08-01T05:00:00-05:00',
  fuentes_reales: {
    conversion: 'leads_recibidos_ponderado',
    capital_y_contratos: 'contratos_confirmados',
  },
  ponderacion_referido: 0.15,
}

describe('payload de cumplimiento tras la migración B', () => {
  it('el bundle desplegado lo parsea: ni una clave de más ni una de menos', () => {
    // Si esto falla, los tres roles se quedan sin metas en producción.
    const parseado = v.parse(CumplimientoMetasSchema, PAYLOAD_POST_B)
    expect(parseado.fuentes_reales.conversion).toBe('leads_recibidos_ponderado')
    expect(parseado.ponderacion_referido).toBe(0.15)
  })

  it('sigue parseando el payload VIEJO: la vuelta atrás no exige redespliegue', () => {
    // Es lo que hace barata la reversión de B (el rollback devuelve este mundo).
    const viejo = {
      ...PAYLOAD_POST_B,
      fuentes_reales: { ...PAYLOAD_POST_B.fuentes_reales, conversion: 'leads_resueltos' },
      vendedores: PAYLOAD_POST_B.vendedores.map(({
        numerador: _n, cierres_no_referidos: _cnr, cierres_referidos: _cr, ...resto
      }) => resto),
    }
    delete (viejo as { ponderacion_referido?: number }).ponderacion_referido

    const parseado = v.parse(CumplimientoMetasSchema, viejo)
    expect(parseado.fuentes_reales.conversion).toBe('leads_resueltos')
    // Y el fallback mantiene los agregados de siempre: numerador = convertidos.
    expect(cumplimientoDesdeRpc(parseado).porVendedor['11111111-1111-1111-1111-111111111111']?.numerador)
      .toBe(7)
  })

  it('una conversión de 132,5 % sobrevive: un resultado no tiene techo', () => {
    const parseado = v.parse(CumplimientoMetasSchema, PAYLOAD_POST_B)
    const jerarquico = cumplimientoDesdeRpc(parseado, '33333333-3333-3333-3333-333333333333')
    const ana = jerarquico.porVendedor['11111111-1111-1111-1111-111111111111']

    expect(ana?.conversionReal).toBe(132.5)
    // El invariante viejo se rompe A PROPÓSITO: `resueltos` son RECIBIDOS.
    expect(ana!.convertidos).toBeGreaterThan(ana!.resueltos)
  })

  it('el agregado ya no lleva conversión: la del grupo la sirve el servidor (F3.3)', () => {
    const parseado = v.parse(CumplimientoMetasSchema, PAYLOAD_POST_B)
    const jerarquico = cumplimientoDesdeRpc(parseado, '33333333-3333-3333-3333-333333333333')

    // Mutante vigilado: si alguien reintroduce la división del agregado en el
    // navegador (numerador÷resueltos, o peor, convertidos crudos = 175 %),
    // este caso lo caza — el agregado no debe traer NINGUNA de esas claves.
    expect(jerarquico.supervisor).not.toBeNull()
    expect('conversionReal' in jerarquico.supervisor!).toBe(false)
    expect('numerador' in jerarquico.supervisor!).toBe(false)
    expect('resueltos' in jerarquico.supervisor!).toBe(false)
  })

  it('las alertas leen la MISMA conversión y no avisan de quien va sobrado', () => {
    // La consecuencia de negocio de B: las alertas dejan de tener fórmula
    // propia. Ana va al 132,5 % contra una meta del 40 % → nadie debe avisar.
    const parseado = v.parse(CumplimientoMetasSchema, PAYLOAD_POST_B)
    const jerarquico = cumplimientoDesdeRpc(parseado)

    const alertas = derivarAlertasGerencia({
      conversiones: undefined,
      metasVendedores: Object.fromEntries(
        Object.values(jerarquico.porVendedor).map((fila) => [fila.vendedorId, fila]),
      ),
      cumplimientosVendedores: jerarquico.porVendedor,
      diaDelMes: 20,
      diasDelMes: 31,
    })

    expect(alertas.filter((a) => a.tipo === 'bajo_meta_conversion')
      .map((a) => a.responsableId)).not.toContain('11111111-1111-1111-1111-111111111111')
  })
})
