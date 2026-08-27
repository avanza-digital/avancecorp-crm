import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { identidadesEquipoConversion } from './conversion-equipo'
import { totalConversionPublicable } from './conversion-mensual'
import { adaptarConversionMensual } from './conversion-vendedores'
import { derivarConversionMensual } from './demo-conversion-mensual'
import { porcentajeConversionCanonica } from './format'
import {
  MetricasVendedoresSchema,
  mapearMetricasVendedores,
} from './metricas-vendedores'
import type { Miembro } from './tipos'

const AHORA = Date.parse('2026-08-15T17:00:00-05:00')

describe('contrato offline de paridad — HOY/Ranking/Metas/Gestión/Directorio', () => {
  it('la misma foto canónica conserva valor, precisión y cierres en las cinco superficies', () => {
    // Foto GLOBAL realizable con un solo equipo/vendedor: total, fila y equipo
    // representan el mismo conjunto. Esto prueba el cableado frontend; la
    // paridad viva sigue requiriendo readback C0.1 con actor/snapshot reales.
    const vendedor: Miembro = {
      perfil_id: 'v-1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor',
      supervisor_id: 's-1', activo: true,
    }
    const supervisor: Miembro = {
      perfil_id: 's-1', nombre_completo: 'SUPERVISORA UNO', rol_crm: 'supervisor',
      supervisor_id: null, activo: true,
    }
    const noReferidos = Array.from({ length: 8 }, (_, indice) => ({
      leadId: `nr-${indice + 1}`,
      analistaId: vendedor.perfil_id,
      asignadoHaceMeses: 0 as const,
      origen: 'landing' as const,
      ...(indice < 2
        ? { resultado: 'convertido' as const, resultadoHaceMeses: 0 as const }
        : {}),
    }))
    const mensual = derivarConversionMensual(
      AHORA,
      { alcance: 'global' },
      [...noReferidos, {
        leadId: 'ref-1',
        analistaId: vendedor.perfil_id,
        asignadoHaceMeses: 0,
        origen: 'referido',
        resultado: 'convertido',
        resultadoHaceMeses: 0,
      }],
      [{ analistaId: vendedor.perfil_id, supervisorId: supervisor.perfil_id }],
    )
    const responsable = mensual.responsables[0]!
    const cierres = responsable.cierres_no_referidos + responsable.cierres_referidos
    const operaciones = responsable.cartera.conversiones_clientes

    const payloadGestion = v.parse(MetricasVendedoresSchema, {
      version: 1,
      generado_en: mensual.generado_en,
      ventana_convertidos_dias: 45,
      ventana_metrica: 'mes_calendario',
      mes_metrica: `${mensual.periodo.mes}-01`,
      peso_referido: mensual.ponderacion.referido,
      cobertura_conversion: mensual.cobertura,
      nucleo_total: {
        nucleo_convertidos: mensual.total.cierres_no_referidos
          + mensual.total.cierres_referidos,
        operaciones_cartera: mensual.total.cartera.conversiones_clientes,
        nucleo_divisor: mensual.total.divisor,
        nucleo_numerador: mensual.total.numerador,
        nucleo_conversion_pct: mensual.total.conversion_pct,
      },
      vendedores: [{
        vendedor_id: vendedor.perfil_id,
        rol_crm: 'vendedor',
        activo: true,
        activos: 0,
        capital_pen: 0,
        capital_usd: 0,
        convertidos: cierres,
        conversion_pct: Math.round(responsable.conversion_pct ?? 0),
        nucleo_convertidos: cierres,
        operaciones_cartera: operaciones,
        nucleo_divisor: responsable.divisor,
        nucleo_numerador: responsable.numerador,
        nucleo_conversion_pct: responsable.conversion_pct,
        sin_tocar: 0,
        dias_sin_actividad_max: 0,
      }],
      equipos: [{
        supervisor_id: supervisor.perfil_id,
        vendedores: 1,
        activos: 0,
        capital_pen: 0,
        capital_usd: 0,
        convertidos: cierres,
        conversion_pct: Math.round(mensual.total.conversion_pct ?? 0),
        nucleo_convertidos: cierres,
        operaciones_cartera: operaciones,
        nucleo_divisor: mensual.total.divisor,
        nucleo_numerador: mensual.total.numerador,
        nucleo_conversion_pct: mensual.total.conversion_pct,
        parkeados: 0,
      }],
    })
    const gestion = mapearMetricasVendedores(
      payloadGestion,
      [vendedor],
      [supervisor, vendedor],
    )
    const ranking = adaptarConversionMensual(
      mensual,
      identidadesEquipoConversion([vendedor], [supervisor, vendedor]),
    )

    const lecturas = {
      hoy: totalConversionPublicable(mensual)?.conversion_pct ?? null,
      ranking: ranking.vendedores[0]?.detalle?.conversion_pct ?? null,
      metas: totalConversionPublicable(mensual)?.conversion_pct ?? null,
      gestion: gestion.filas[0]?.conversion ?? null,
      directorio: gestion.totalConversion.conversion,
    }
    expect(lecturas).toEqual({
      hoy: 26.88,
      ranking: 26.88,
      metas: 26.88,
      gestion: 26.88,
      directorio: 26.88,
    })
    expect(Object.values(lecturas).map(porcentajeConversionCanonica))
      .toEqual(Array(5).fill('26.88%'))
    expect(gestion.filas[0]).toMatchObject({
      cierresConversion: cierres,
      operacionesCartera: operaciones,
      conversionDisponible: true,
    })
    expect(gestion.equipos[0]).toMatchObject({
      cierresConversion: cierres,
      operacionesCartera: operaciones,
      conversionDisponible: true,
    })
    expect(gestion.totalConversion).toMatchObject({
      cierresConversion: cierres,
      operacionesCartera: operaciones,
      conversionDisponible: true,
      conversion: 26.88,
    })

    const mensualEnRevision = {
      ...mensual,
      cobertura: { ...mensual.cobertura, cierres_sin_episodio: 1 },
    }
    const payloadEnRevision = v.parse(MetricasVendedoresSchema, {
      ...payloadGestion,
      cobertura_conversion: mensualEnRevision.cobertura,
    })
    const gestionEnRevision = mapearMetricasVendedores(
      payloadEnRevision,
      [vendedor],
      [supervisor, vendedor],
    )
    const rankingEnRevision = adaptarConversionMensual(
      mensualEnRevision,
      identidadesEquipoConversion([vendedor], [supervisor, vendedor]),
    )
    const totalVisible = totalConversionPublicable(mensualEnRevision)?.conversion_pct ?? null

    expect({
      hoy: totalVisible,
      ranking: rankingEnRevision.vendedores[0]?.detalle?.conversion_pct ?? null,
      metas: totalVisible,
      gestion: gestionEnRevision.filas[0]?.conversion ?? null,
      directorio: gestionEnRevision.totalConversion.conversion,
    }).toEqual({
      hoy: null,
      ranking: null,
      metas: null,
      gestion: null,
      directorio: null,
    })
  })
})
