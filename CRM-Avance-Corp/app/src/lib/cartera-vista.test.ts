// Tests del motor puro de la pantalla Cartera (fusión Clientes+Contratos):
// la unión 1:N con semántica LEFT JOIN, el capital EN JUEGO por moneda (PEN y
// USD JAMÁS sumados), el filtro por estado ('activo'), el orden por ingreso y
// los números del StatStrip (con corte de vencimiento en TZ Lima).
import { describe, expect, it } from 'vitest'
import { agruparCartera, esPorVencer, idsPorVencer, resumenCartera } from './cartera-vista'
import type { ClienteBasico, ContratoRow } from './clientes-tipos'

/** Cliente mínimo — cada test pisa solo lo que le importa. */
function cliente(sobre: Partial<ClienteBasico> = {}): ClienteBasico {
  return {
    id: 'c-1',
    nombres: null,
    apellidos: null,
    nombre_completo: 'CLIENTE DE PRUEBA',
    tipo_documento: 'DNI',
    dni: null,
    correo: null,
    telefono: null,
    asesor_perfil_id: null,
    creado_por: null,
    activo: true,
    creado_en: '2026-01-01T00:00:00.000Z',
    ...sobre,
  }
}

/** Contrato mínimo, activo por defecto. */
function contrato(sobre: Partial<ContratoRow> = {}): ContratoRow {
  return {
    id: 'k-1',
    numero_contrato: '2026-01-000001',
    cliente_id: 'c-1',
    cliente_nombre: 'CLIENTE DE PRUEBA',
    capital: 10000,
    moneda: 'PEN',
    tasa_anual: 12,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    categoria: 'nuevo',
    estado: 'activo',
    fecha_inicio: '2026-01-01',
    fecha_vencimiento: '2027-01-01',
    fecha_cierre_comercial: '2026-01-01',
    notas_internas: null,
    creado_por: null,
    creado_en: '2026-01-01T00:00:00.000Z',
    producto_condicion_id: '10000000-0000-4000-8000-000000000001',
    producto_id: '20000000-0000-4000-8000-000000000001',
    producto_codigo: 'RENTA-BASE',
    producto_version_id: '30000000-0000-4000-8000-000000000001',
    producto_version: 1,
    producto_nombre: 'Plan base',
    producto_version_estado: 'publicada',
    ...sobre,
  }
}

describe('agruparCartera — unión cliente ▸ contratos (1:N, LEFT JOIN)', () => {
  it('agrupa los N contratos de un cliente en un solo grupo', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'c-1' })],
      [
        contrato({ id: 'k1', cliente_id: 'c-1' }),
        contrato({ id: 'k2', cliente_id: 'c-1' }),
        contrato({ id: 'k3', cliente_id: 'c-1' }),
      ],
    )
    expect(grupos).toHaveLength(1)
    expect(grupos[0]?.contratos.map((c) => c.id)).toEqual(['k1', 'k2', 'k3'])
    expect(grupos[0]?.contratosActivos).toBe(3)
  })

  it('LEFT JOIN: un cliente SIN contratos aparece igual, con capital 0 y sin capital', () => {
    const grupos = agruparCartera([cliente({ id: 'solo' })], [])
    expect(grupos).toHaveLength(1)
    expect(grupos[0]?.contratos).toEqual([])
    expect(grupos[0]?.capitalActivoPen).toBe(0)
    expect(grupos[0]?.capitalActivoUsd).toBe(0)
    expect(grupos[0]?.contratosActivos).toBe(0)
    expect(grupos[0]?.tieneCapital).toBe(false)
    expect(grupos[0]?.proximoVencimiento).toBeNull()
  })

  it('un contrato huérfano (cliente_id sin cliente cargado) se descarta sin lanzar', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'c-1' })],
      [contrato({ id: 'ok', cliente_id: 'c-1' }), contrato({ id: 'fantasma', cliente_id: 'no-existe' })],
    )
    expect(grupos).toHaveLength(1)
    expect(grupos[0]?.contratos.map((c) => c.id)).toEqual(['ok'])
  })
})

describe('capital en juego — PEN y USD JAMÁS se suman, solo cuenta ACTIVO', () => {
  it('PEN y USD activos quedan en acumuladores separados (nunca 15000)', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'c-1' })],
      [
        contrato({ id: 'pen', cliente_id: 'c-1', moneda: 'PEN', capital: 10000 }),
        contrato({ id: 'usd', cliente_id: 'c-1', moneda: 'USD', capital: 5000 }),
      ],
    )
    expect(grupos[0]?.capitalActivoPen).toBe(10000)
    expect(grupos[0]?.capitalActivoUsd).toBe(5000)
    expect(grupos[0]?.contratosActivos).toBe(2)
  })

  it('vencido / renovado / retirado NO suman ni cuentan como activo', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'c-1' })],
      [
        contrato({ id: 'a', cliente_id: 'c-1', estado: 'activo', capital: 10000 }),
        contrato({ id: 'v', cliente_id: 'c-1', estado: 'vencido', capital: 99999 }),
        contrato({ id: 'r', cliente_id: 'c-1', estado: 'renovado', capital: 88888 }),
        contrato({ id: 't', cliente_id: 'c-1', estado: 'retirado', capital: 77777 }),
      ],
    )
    expect(grupos[0]?.capitalActivoPen).toBe(10000)
    expect(grupos[0]?.contratosActivos).toBe(1)
    expect(grupos[0]?.contratos).toHaveLength(4) // el grupo SÍ conserva todos para pintar
  })

  it('numeric-como-string de PostgREST se coacciona sin romper la suma', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'c-1' })],
      [contrato({ id: 'k', cliente_id: 'c-1', capital: '10000.50' as unknown as number })],
    )
    expect(grupos[0]?.capitalActivoPen).toBe(10000.5)
  })

  it('proximoVencimiento = la fecha más próxima entre los activos', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'c-1' })],
      [
        contrato({ id: 'lejos', cliente_id: 'c-1', fecha_vencimiento: '2027-12-31' }),
        contrato({ id: 'cerca', cliente_id: 'c-1', fecha_vencimiento: '2026-09-15' }),
        contrato({ id: 'vencido-cercano', cliente_id: 'c-1', estado: 'vencido', fecha_vencimiento: '2026-02-01' }),
      ],
    )
    expect(grupos[0]?.proximoVencimiento).toBe('2026-09-15') // el vencido no cuenta
  })
})

describe('agruparCartera — orden por ingreso (capital activo desc)', () => {
  it('el cliente con más capital activo PEN va primero; sin capital, al final', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'chico' }), cliente({ id: 'grande' }), cliente({ id: 'vacio' })],
      [
        contrato({ id: 'a', cliente_id: 'chico', capital: 5000 }),
        contrato({ id: 'b', cliente_id: 'grande', capital: 80000 }),
        // 'vacio' sin contratos
      ],
    )
    expect(grupos.map((g) => g.cliente.id)).toEqual(['grande', 'chico', 'vacio'])
  })

  it('empate en capital: desempata por cliente más reciente', () => {
    const grupos = agruparCartera(
      [
        cliente({ id: 'viejo', creado_en: '2026-01-01T00:00:00.000Z' }),
        cliente({ id: 'nuevo', creado_en: '2026-07-01T00:00:00.000Z' }),
      ],
      [], // ambos en capital 0
    )
    expect(grupos.map((g) => g.cliente.id)).toEqual(['nuevo', 'viejo'])
  })
})

describe('resumenCartera — números del StatStrip (corte de vencimiento en TZ Lima)', () => {
  const HOY = new Date(2026, 6, 20) // 20 de julio de 2026, medianoche local (Lima)

  const grupos = agruparCartera(
    [cliente({ id: 'a' }), cliente({ id: 'b' }), cliente({ id: 'c' })],
    [
      contrato({ id: 'k1', cliente_id: 'a', moneda: 'PEN', capital: 10000, fecha_vencimiento: '2026-08-04' }), // hoy+15 → cuenta
      contrato({ id: 'k2', cliente_id: 'a', moneda: 'USD', capital: 5000, fecha_vencimiento: '2026-09-03' }), // hoy+45 → NO
      contrato({ id: 'k3', cliente_id: 'b', moneda: 'PEN', capital: 20000, fecha_vencimiento: '2026-07-20' }), // hoy → cuenta
      contrato({ id: 'k4', cliente_id: 'b', estado: 'vencido', capital: 9999, fecha_vencimiento: '2026-08-01' }), // vencido → NO
      // 'c' sin contratos
    ],
  )

  it('separa capital por moneda y cuenta clientes con capital (N de M)', () => {
    const r = resumenCartera(grupos, HOY)
    expect(r.capitalActivoPen).toBe(30000) // 10000 + 20000
    expect(r.capitalActivoUsd).toBe(5000)
    expect(r.totalClientes).toBe(3)
    expect(r.clientesConCapital).toBe(2) // a y b tienen activos; c no
  })

  it('por vencer ≤30 d: cuenta hoy y hoy+15, NO hoy+45 ni los vencidos', () => {
    const r = resumenCartera(grupos, HOY)
    expect(r.porVencer30).toBe(2) // k1 (hoy+15) + k3 (hoy)
  })

  it('un vencimiento de AYER (ya pasado) no cuenta como "por vencer"', () => {
    const soloAyer = agruparCartera(
      [cliente({ id: 'a' })],
      [contrato({ id: 'k', cliente_id: 'a', fecha_vencimiento: '2026-07-19' })], // hoy-1
    )
    expect(resumenCartera(soloAyer, HOY).porVencer30).toBe(0)
  })

  it('una fecha de vencimiento malformada no rompe ni cuenta como "por vencer"', () => {
    const malformada = agruparCartera(
      [cliente({ id: 'a' })],
      [contrato({ id: 'k', cliente_id: 'a', fecha_vencimiento: 'sin-fecha' })],
    )
    expect(() => resumenCartera(malformada, HOY)).not.toThrow()
    expect(resumenCartera(malformada, HOY).porVencer30).toBe(0)
  })

  it('borde exacto: un vencimiento a hoy+30 SÍ cuenta como "por vencer"', () => {
    const g = agruparCartera(
      [cliente({ id: 'a' })],
      [contrato({ id: 'k30', cliente_id: 'a', fecha_vencimiento: '2026-08-19' })], // hoy+30
    )
    expect(resumenCartera(g, HOY).porVencer30).toBe(1)
  })

  it('borde exacto: un vencimiento a hoy+31 NO cuenta (≤30 es el límite)', () => {
    const g = agruparCartera(
      [cliente({ id: 'a' })],
      [contrato({ id: 'k31', cliente_id: 'a', fecha_vencimiento: '2026-08-20' })], // hoy+31
    )
    expect(resumenCartera(g, HOY).porVencer30).toBe(0)
  })
})

// —— Dinero vs ALARMA. Un cliente dado de baja en el portal (perfiles.activo =
// false) sale de los TOTALES de capital —el analista no puede trabajar esa
// cartera— pero NO de la alarma de vencimiento: su contrato activo sigue
// venciendo, la renovación es el ingreso más rentable del negocio y este chip
// es el único radar de renovación del CRM. Estos tests fijan esa separación
// (la pasada del 2026-07-25 la había roto: porVencer30 decía 0).
describe('resumenCartera — cliente dado de baja: fuera del dinero, DENTRO de la alarma', () => {
  const HOY = new Date(2026, 6, 20) // 20 de julio de 2026, medianoche en Lima

  it('un contrato por vencer de un cliente de baja SÍ cuenta en la alarma (y se desglosa)', () => {
    const g = agruparCartera(
      [cliente({ id: 'baja', activo: false })],
      [contrato({ id: 'k', cliente_id: 'baja', capital: 40000, fecha_vencimiento: '2026-08-04' })], // hoy+15
    )
    const r = resumenCartera(g, HOY)
    expect(r.porVencer30).toBe(1) // ← el bug lo dejaba en 0
    expect(r.porVencer30DeBaja).toBe(1)
    // …y su dinero sigue fuera de los totales (PEN y USD, cada uno en su cifra).
    expect(r.capitalActivoPen).toBe(0)
    expect(r.capitalActivoUsd).toBe(0)
    expect(r.clientesConCapital).toBe(0)
    expect(r.totalClientes).toBe(0) // el conteo es de clientes EN GESTIÓN
  })

  it('mezcla: la alarma suma los dos, el capital solo el del cliente en gestión', () => {
    const g = agruparCartera(
      [cliente({ id: 'viva' }), cliente({ id: 'baja', activo: false })],
      [
        contrato({ id: 'kv', cliente_id: 'viva', capital: 10000, fecha_vencimiento: '2026-08-04' }), // hoy+15
        contrato({ id: 'kb', cliente_id: 'baja', capital: 40000, fecha_vencimiento: '2026-07-25' }), // hoy+5
      ],
    )
    const r = resumenCartera(g, HOY)
    expect(r.porVencer30).toBe(2)
    expect(r.porVencer30DeBaja).toBe(1)
    expect(r.capitalActivoPen).toBe(10000) // jamás 50000
    expect(r.clientesConCapital).toBe(1)
    expect(r.totalClientes).toBe(1)
  })

  it('un cliente de baja SIN nada por vencer no aporta a la alarma', () => {
    const g = agruparCartera(
      [cliente({ id: 'baja', activo: false })],
      [
        contrato({ id: 'lejos', cliente_id: 'baja', fecha_vencimiento: '2027-01-01' }), // fuera de ventana
        contrato({ id: 'ya-vencido', cliente_id: 'baja', estado: 'vencido', fecha_vencimiento: '2026-08-01' }),
      ],
    )
    const r = resumenCartera(g, HOY)
    expect(r.porVencer30).toBe(0)
    expect(r.porVencer30DeBaja).toBe(0)
  })

  it('el USD de un cliente de baja tampoco entra al capital, y su alarma sí', () => {
    const g = agruparCartera(
      [cliente({ id: 'baja', activo: false })],
      [contrato({ id: 'k', cliente_id: 'baja', moneda: 'USD', capital: 9000, fecha_vencimiento: '2026-08-19' })], // hoy+30
    )
    const r = resumenCartera(g, HOY)
    expect(r.capitalActivoUsd).toBe(0)
    expect(r.capitalActivoPen).toBe(0)
    expect(r.porVencer30).toBe(1)
  })
})

describe('esPorVencer / idsPorVencer — el radar de renovación', () => {
  const HOY = new Date(2026, 6, 20)

  it('usa el día de Lima aunque el navegador tenga otro día local', () => {
    const instante = new Date('2026-09-05T02:00:00Z') // todavía 4 de septiembre en Lima
    // Simula getters del navegador en otra zona: el resultado no debe depender de ellos.
    instante.getFullYear = () => 2026
    instante.getMonth = () => 8
    instante.getDate = () => 5
    expect(esPorVencer(contrato({ fecha_vencimiento: '2026-09-04' }), instante)).toBe(true)
    expect(esPorVencer(contrato({ fecha_vencimiento: '2026-10-05' }), instante)).toBe(false)
  })

  it('activo dentro de la ventana sí; vencido/renovado/retirado no', () => {
    expect(esPorVencer(contrato({ fecha_vencimiento: '2026-08-04' }), HOY)).toBe(true)
    expect(esPorVencer(contrato({ estado: 'vencido', fecha_vencimiento: '2026-08-04' }), HOY)).toBe(false)
    expect(esPorVencer(contrato({ estado: 'renovado', fecha_vencimiento: '2026-08-04' }), HOY)).toBe(false)
    expect(esPorVencer(contrato({ estado: 'retirado', fecha_vencimiento: '2026-08-04' }), HOY)).toBe(false)
  })

  it('una fecha pasada o malformada nunca es "por vencer" (NaN no dispara alarmas)', () => {
    expect(esPorVencer(contrato({ fecha_vencimiento: '2026-07-19' }), HOY)).toBe(false) // ayer
    expect(esPorVencer(contrato({ fecha_vencimiento: 'sin-fecha' }), HOY)).toBe(false)
    expect(esPorVencer(contrato({ fecha_vencimiento: '' }), HOY)).toBe(false)
  })

  it('los ids incluyen los contratos de clientes dados de baja (la fila es alcanzable)', () => {
    const g = agruparCartera(
      [cliente({ id: 'viva' }), cliente({ id: 'baja', activo: false })],
      [
        contrato({ id: 'kv', cliente_id: 'viva', fecha_vencimiento: '2026-08-04' }), // hoy+15
        contrato({ id: 'kb', cliente_id: 'baja', fecha_vencimiento: '2026-07-25' }), // hoy+5
        contrato({ id: 'klejos', cliente_id: 'viva', fecha_vencimiento: '2027-01-01' }),
      ],
    )
    expect([...idsPorVencer(g, HOY)].sort()).toEqual(['kb', 'kv'])
  })
})
