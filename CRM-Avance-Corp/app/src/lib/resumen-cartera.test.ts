// Espejo demo de crm.resumen_cartera_fn: mismas reglas que el servidor
// (ventana de convertidos 45 d, USD estricto, parkeados aparte, PEN y USD
// jamás sumados) y el shape EXACTO del payload version:1.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  ResumenCarteraSchema,
  VENTANA_CONVERTIDOS_DIAS,
  VENTANA_CONVERTIDOS_MS,
  resumenCarteraDesdeAmbito,
} from './resumen-cartera'
import type { Actividad, Lead } from './tipos'

const AHORA = Date.parse('2026-08-09T15:00:00Z')
const DIA = 86_400_000

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: `l-${Math.random().toString(36).slice(2, 8)}`,
    nombre_completo: 'ANA TORRES',
    telefono: '+51987654321',
    etapa: 'contactado',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: '2026-07-01T15:00:00Z',
    activo: true,
    ...over,
  }
}

function actividad(over: Partial<Actividad> = {}): Actividad {
  return {
    id: `a-${Math.random().toString(36).slice(2, 8)}`,
    lead_id: 'l-1',
    tipo: 'llamada_realizada',
    detalle: null,
    autor_nombre: 'ANA',
    creado_en: '2026-08-01T15:00:00Z',
    ...over,
  }
}

const iso = (ms: number): string => new Date(ms).toISOString()

describe('resumenCarteraDesdeAmbito — ámbito y ventana', () => {
  it('el payload que produce cumple el MISMO contrato Valibot que valida al RPC', () => {
    const resumen = resumenCarteraDesdeAmbito(
      [lead(), lead({ etapa: 'convertido', convertido_en: iso(AHORA - VENTANA_CONVERTIDOS_MS / 2) })],
      [actividad()],
      AHORA,
    )
    expect(v.safeParse(ResumenCarteraSchema, resumen).success).toBe(true)
    expect(resumen.ventana_convertidos_dias).toBe(VENTANA_CONVERTIDOS_DIAS)
  })

  it('un convertido dentro de la ventana cuenta; con más de 45 días desaparece del ámbito', () => {
    const reciente = lead({ id: 'c-nuevo', etapa: 'convertido', convertido_en: iso(AHORA - DIA * 44) })
    const viejo = lead({ id: 'c-viejo', etapa: 'convertido', convertido_en: iso(AHORA - DIA * 46) })
    const resumen = resumenCarteraDesdeAmbito([reciente, viejo], [], AHORA)
    expect(resumen.totales.convertidos).toBe(1)
    expect(resumen.totales.vivos).toBe(1)
    expect(resumen.embudo.find((p) => p.etapa === 'convertido')?.n).toBe(1)
  })

  it('un convertido SIN sello cae a la cadena de cierres-del-mes (solo pasa en demo)', () => {
    // creado_en del fixture: 2026-07-01, a 39 días de AHORA → dentro de la ventana.
    const resumen = resumenCarteraDesdeAmbito(
      [lead({ etapa: 'convertido', convertido_en: null })],
      [],
      AHORA,
    )
    expect(resumen.totales.convertidos).toBe(1)
  })

  it('un convertido sin sello y con TODA su historia fuera de la ventana desaparece', () => {
    const resumen = resumenCarteraDesdeAmbito(
      [lead({
        etapa: 'convertido',
        convertido_en: null,
        creado_en: iso(AHORA - DIA * 90),
        actualizado_en: iso(AHORA - DIA * 60),
      })],
      [],
      AHORA,
    )
    expect(resumen.totales.vivos).toBe(0)
  })

  it('los soft-borrados (activo=false) no cuentan aunque el ámbito del directorio los liste', () => {
    const resumen = resumenCarteraDesdeAmbito([lead({ activo: false })], [], AHORA)
    expect(resumen.totales.vivos).toBe(0)
    expect(resumen.totales.abiertos).toBe(0)
  })
})

describe('resumenCarteraDesdeAmbito — capital por moneda', () => {
  it('separa asignado/parkeado/ganado y JAMÁS suma PEN con USD', () => {
    const resumen = resumenCarteraDesdeAmbito(
      [
        lead({ monto_estimado: 1000, moneda: 'PEN' }),
        lead({ monto_estimado: 500, moneda: 'USD' }),
        lead({ monto_estimado: 300, vendedor_id: null }), // parkeado PEN
        lead({
          etapa: 'convertido',
          monto_estimado: 700,
          moneda: 'USD',
          convertido_en: iso(AHORA - DIA),
        }),
      ],
      [],
      AHORA,
    )
    expect(resumen.capital.asignado).toEqual({ pen: 1000, usd: 500 })
    expect(resumen.capital.parkeado).toEqual({ pen: 300, usd: 0 })
    expect(resumen.capital.ganado).toEqual({ pen: 0, usd: 700 })
    expect(resumen.totales.asignados_pen).toBe(1)
    expect(resumen.totales.asignados_usd).toBe(1)
  })
})

describe('resumenCarteraDesdeAmbito — conversión y descartes', () => {
  it('la base de conversión son los vivos CON analista; los parkeados no cuentan', () => {
    const resumen = resumenCarteraDesdeAmbito(
      [
        lead(),
        lead({ etapa: 'convertido', convertido_en: iso(AHORA - DIA) }),
        lead({ vendedor_id: null }), // parkeado: fuera de la base
        lead({ etapa: 'descartado', motivo_descarte: 'no_responde' }),
      ],
      [],
      AHORA,
    )
    expect(resumen.conversion).toEqual({ convertidos: 1, base: 3, pct: 33 })
  })

  it('descartes por motivo ordenados por n desc y motivo asc; sin_motivo aparte', () => {
    const resumen = resumenCarteraDesdeAmbito(
      [
        lead({ etapa: 'descartado', motivo_descarte: 'no_responde' }),
        lead({ etapa: 'descartado', motivo_descarte: 'no_responde' }),
        lead({ etapa: 'descartado', motivo_descarte: 'sin_fondos' }),
        lead({ etapa: 'descartado', motivo_descarte: 'competencia' }),
        lead({ etapa: 'descartado', motivo_descarte: null }),
      ],
      [],
      AHORA,
    )
    expect(resumen.descartes.total).toBe(5)
    expect(resumen.descartes.sin_motivo).toBe(1)
    expect(resumen.descartes.por_motivo).toEqual([
      { motivo: 'no_responde', n: 2 },
      { motivo: 'competencia', n: 1 },
      { motivo: 'sin_fondos', n: 1 },
    ])
  })
})

describe('resumenCarteraDesdeAmbito — sin tocar', () => {
  it('cuenta abiertos con dueño sin NINGÚN contacto; nota y reasignación no apagan el contador', () => {
    const tocado = lead({ id: 'l-tocado' })
    const soloNota = lead({ id: 'l-nota' })
    const parkeado = lead({ id: 'l-parkeado', vendedor_id: null })
    const resumen = resumenCarteraDesdeAmbito(
      [tocado, soloNota, parkeado],
      [
        actividad({ lead_id: 'l-tocado', tipo: 'whatsapp_enviado' }),
        actividad({ lead_id: 'l-nota', tipo: 'nota' }),
        actividad({ lead_id: 'l-parkeado', tipo: 'reasignacion' }),
      ],
      AHORA,
    )
    // Solo l-nota: abierto, con dueño y sin contacto real (la nota no cuenta).
    // El parkeado no entra aunque nadie lo haya tocado: no tiene dueño.
    expect(resumen.sin_tocar).toBe(1)
  })

  it('el embudo llega SIEMPRE con las 6 etapas en orden canónico, con ceros incluidos', () => {
    const resumen = resumenCarteraDesdeAmbito([lead({ etapa: 'nuevo' })], [], AHORA)
    expect(resumen.embudo.map((p) => p.etapa)).toEqual([
      'nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada', 'convertido', 'descartado',
    ])
    expect(resumen.embudo[0]).toEqual({ etapa: 'nuevo', n: 1 })
  })
})
