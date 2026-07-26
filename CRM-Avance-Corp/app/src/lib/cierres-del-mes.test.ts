// Cierres del mes vigente — la definición única contra la que se miden las
// metas mensuales de vendedor, supervisor y gerencia.
import { describe, expect, it } from 'vitest'
import { cerradoEnPeriodo, cierresDelMes } from './cierres-del-mes'
import type { Lead } from './tipos'

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5).
const AHORA = Date.parse('2026-07-15T15:00:00Z')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'l-1',
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

describe('cerradoEnPeriodo', () => {
  it('manda convertido_en: el sello del servidor gana a cualquier otra fecha', () => {
    expect(
      cerradoEnPeriodo(
        lead({
          etapa: 'convertido',
          creado_en: '2026-05-01T15:00:00Z',
          convertido_en: '2026-07-09T15:00:00Z',
          // Una edición POSTERIOR reescribió actualizado_en: no debe mover nada.
          actualizado_en: '2026-08-20T15:00:00Z',
        }),
        '2026-07-01',
      ),
    ).toBe(true)
  })

  it('EL BUG: editar un convertido reescribe actualizado_en y le robaba el cierre a su mes', () => {
    // Mismo lead, ganado el 9 de julio y con el teléfono corregido en agosto.
    const corregidoEnAgosto = lead({
      etapa: 'convertido',
      convertido_en: '2026-07-09T15:00:00Z',
      actualizado_en: '2026-08-03T15:00:00Z',
    })
    // El cierre se queda en JULIO…
    expect(cerradoEnPeriodo(corregidoEnAgosto, '2026-07-01')).toBe(true)
    // …y NO se le regala a agosto (que era el cierre falso de antes).
    expect(cerradoEnPeriodo(corregidoEnAgosto, '2026-08-01')).toBe(false)
  })

  it('sin convertido_en usa actualizado_en (descartados y modo demo)', () => {
    expect(
      cerradoEnPeriodo(lead({ etapa: 'descartado', creado_en: '2026-05-01T15:00:00Z', actualizado_en: '2026-07-09T15:00:00Z' }), '2026-07-01'),
    ).toBe(true)
  })

  it('sin convertido_en ni actualizado_en (demo) degrada al mes de creación', () => {
    expect(cerradoEnPeriodo(lead({ creado_en: '2026-07-02T15:00:00Z' }), '2026-07-01')).toBe(true)
    expect(cerradoEnPeriodo(lead({ creado_en: '2026-06-30T15:00:00Z' }), '2026-07-01')).toBe(false)
  })

  it('el mes es el de LIMA, no el del navegador: el 31 a las 22:00 sigue siendo julio', () => {
    // 2026-08-01T03:00Z = 2026-07-31 22:00 en Lima.
    expect(cerradoEnPeriodo(lead({ actualizado_en: '2026-08-01T03:00:00Z' }), '2026-07-01')).toBe(true)
    expect(cerradoEnPeriodo(lead({ actualizado_en: '2026-08-01T03:00:00Z' }), '2026-08-01')).toBe(false)
  })

  it('una fecha ilegible no se cuela al periodo', () => {
    expect(cerradoEnPeriodo(lead({ actualizado_en: 'no-es-fecha' }), '2026-07-01')).toBe(false)
    expect(cerradoEnPeriodo(lead({ convertido_en: 'no-es-fecha' }), '2026-07-01')).toBe(false)
  })
})

describe('cierresDelMes con el sello propio de conversión', () => {
  it('un convertido editado el mes siguiente sigue contando en SU mes', () => {
    const ganadoEnJulio = lead({
      id: 'a',
      etapa: 'convertido',
      convertido_en: '2026-07-09T15:00:00Z',
      actualizado_en: '2026-08-03T15:00:00Z', // el asesor le completó el DNI
    })
    expect(cierresDelMes([ganadoEnJulio], AHORA).convertidos).toBe(1)
    // Y en agosto (AHORA + 1 mes) ya no vuelve a contar: un cierre, un mes.
    expect(cierresDelMes([ganadoEnJulio], Date.parse('2026-08-15T15:00:00Z')).convertidos).toBe(0)
  })
})

describe('cierresDelMes', () => {
  it('el numerador es del MES, no del histórico de vida', () => {
    const r = cierresDelMes(
      [
        lead({ id: 'a', etapa: 'convertido', actualizado_en: '2026-05-20T15:00:00Z' }),
        lead({ id: 'b', etapa: 'convertido', actualizado_en: '2026-06-20T15:00:00Z' }),
        lead({ id: 'c', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
      ],
      AHORA,
    )
    expect(r.convertidos).toBe(1)
    expect(r.convertidosVida).toBe(3)
  })

  it('la conversión del mes se calcula sobre lo RESUELTO en el mes', () => {
    const r = cierresDelMes(
      [
        lead({ id: 'a', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
        lead({ id: 'b', etapa: 'descartado', actualizado_en: '2026-07-10T15:00:00Z' }),
        // Resuelto el mes pasado: fuera del cálculo.
        lead({ id: 'c', etapa: 'descartado', actualizado_en: '2026-06-10T15:00:00Z' }),
        // Abierto: todavía no votó, no puede castigar el denominador.
        lead({ id: 'd', etapa: 'propuesta_enviada' }),
      ],
      AHORA,
    )
    expect(r.resueltos).toBe(2)
    expect(r.conversion).toBe(50)
  })

  it('sin nada resuelto este mes la conversión es null (sin dato, NO 0 %)', () => {
    const r = cierresDelMes([lead({ etapa: 'contactado' })], AHORA)
    expect(r.resueltos).toBe(0)
    expect(r.conversion).toBeNull()
    expect(r.conversion).not.toBe(0)
  })

  it('los leads borrados en suave (activo=false) no cuentan en ninguna cifra', () => {
    const r = cierresDelMes(
      [lead({ etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z', activo: false })],
      AHORA,
    )
    expect(r).toEqual({ convertidos: 0, resueltos: 0, conversion: null, convertidosVida: 0 })
  })

  it('un descartado sin dueño también consume embudo (no se filtra por vendedor)', () => {
    const r = cierresDelMes(
      [
        lead({ id: 'a', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
        lead({ id: 'b', etapa: 'descartado', actualizado_en: '2026-07-09T15:00:00Z', vendedor_id: null }),
      ],
      AHORA,
    )
    expect(r.resueltos).toBe(2)
    expect(r.conversion).toBe(50)
  })
})
