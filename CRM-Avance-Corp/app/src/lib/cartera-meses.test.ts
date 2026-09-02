// Tests del motor puro que parte Mi cartera en bloques por MES DE CIERRE
// COMERCIAL (el mismo con el que se paga la cuota, desde el 02/09/2026):
// la trampa de la zona horaria (Lima vs UTC), el cliente que cerró en varios
// meses, PEN y USD jamás sumados, los dos cubos (sin contrato / sin fecha) y el
// conteo de contratos registrados por otra persona.
import { describe, expect, it } from 'vitest'
import {
  agruparPorMes,
  mesDeCierre,
  mesLima,
  registradoEnOtroMes,
  registradoPorOtro,
  CLAVE_SIN_CONTRATOS,
  CLAVE_SIN_FECHA,
} from './cartera-meses'
import { fechaLima } from './agenda-derivada'
import { agruparCartera, resumirCliente } from './cartera-vista'
import type { ClienteBasico, ContratoRow } from './clientes-tipos'

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

/** Fecha de cierre por defecto: el día (Lima) en que se registró. Un `creado_en`
 *  ilegible se copia tal cual, para que el contrato caiga en el cubo «sin fecha»
 *  en vez de reventar el fixture. */
function cierrePorDefecto(creadoEn: string): string {
  const ms = Date.parse(creadoEn)
  return Number.isNaN(ms) ? creadoEn : fechaLima(ms)
}

function contrato(sobre: Partial<ContratoRow> = {}): ContratoRow {
  // El bloque va por FECHA DE CIERRE. Por defecto se cierra el mismo día en que
  // se registra (Lima), que es el caso corriente; un test que quiera separar las
  // dos fechas pasa `fecha_cierre_comercial` explícita y gana, porque `sobre` va
  // al final.
  const creadoEn = sobre.creado_en ?? '2026-08-10T15:00:00.000Z'
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
    fecha_inicio: '2026-08-01',
    fecha_vencimiento: '2027-08-01',
    fecha_cierre_comercial: cierrePorDefecto(creadoEn),
    notas_internas: null,
    creado_por: null,
    creado_en: creadoEn,
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

describe('mesLima — el mes se decide en Lima, no en UTC', () => {
  // LA TRAMPA. Lima es UTC-5: las 20:00 del 31 de julio en Lima son la 01:00
  // del 1 de agosto en UTC. Con `slice(0,7)` sobre el ISO crudo, este contrato
  // se iría solo al bloque de agosto e inflaría un mes que no le toca.
  it('un contrato del 31/07 a las 20:00 de Lima es de JULIO', () => {
    expect(mesLima('2026-08-01T01:00:00.000Z')).toBe('2026-07')
  })

  it('el mismo instante leído en crudo diría agosto (por eso existe esta función)', () => {
    expect('2026-08-01T01:00:00.000Z'.slice(0, 7)).toBe('2026-08')
  })

  it('un contrato del 1/08 a las 09:00 de Lima sí es de AGOSTO', () => {
    expect(mesLima('2026-08-01T14:00:00.000Z')).toBe('2026-08')
  })

  it('una fecha ilegible devuelve null en vez de lanzar', () => {
    // `new Date(NaN).toISOString()` LANZA: sin esta guarda, un solo contrato con
    // la fecha rota dejaba la pantalla entera en blanco.
    expect(mesLima('no es una fecha')).toBeNull()
    expect(mesLima(null)).toBeNull()
    expect(mesLima('')).toBeNull()
  })
})

describe('registradoPorOtro — el contrato que no cuadra con la cuota', () => {
  const g = (asesor: string | null, creador: string | null) =>
    resumirCliente(cliente({ asesor_perfil_id: asesor }), [contrato({ creado_por: creador })])

  it('lo registró otra persona distinta del analista', () => {
    expect(registradoPorOtro(contrato({ creado_por: 'carlos' }), g('miguel', 'carlos'))).toBe(true)
  })

  it('lo registró el propio analista', () => {
    expect(registradoPorOtro(contrato({ creado_por: 'miguel' }), g('miguel', 'miguel'))).toBe(false)
  })

  it('sin creador conocido NO se afirma que sea ajeno (contrato legado)', () => {
    expect(registradoPorOtro(contrato({ creado_por: null }), g('miguel', null))).toBe(false)
  })

  it('sin analista tampoco se afirma nada', () => {
    expect(registradoPorOtro(contrato({ creado_por: 'carlos' }), g(null, 'carlos'))).toBe(false)
  })

  it('sin analista, el dueño hereda de quien registró al CLIENTE (regla de la casa)', () => {
    const grupo = resumirCliente(
      cliente({ asesor_perfil_id: null, creado_por: 'miguel' }),
      [contrato({ creado_por: 'carlos' })],
    )
    expect(registradoPorOtro(contrato({ creado_por: 'carlos' }), grupo)).toBe(true)
  })
})

describe('agruparPorMes — la cartera partida por mes de cierre', () => {
  it('separa los contratos en su mes y ordena del más reciente al más viejo', () => {
    const grupos = agruparCartera(
      [cliente()],
      [
        contrato({ id: 'k-ago', creado_en: '2026-08-10T15:00:00.000Z' }),
        contrato({ id: 'k-jun', creado_en: '2026-06-03T15:00:00.000Z' }),
        contrato({ id: 'k-jul', creado_en: '2026-07-20T15:00:00.000Z' }),
      ],
    )
    const meses = agruparPorMes(grupos)
    expect(meses.map((m) => m.clave)).toEqual(['2026-08', '2026-07', '2026-06'])
    expect(meses.map((m) => m.etiqueta)).toEqual(['Agosto 2026', 'Julio 2026', 'Junio 2026'])
  })

  it('un cliente que cerró en dos meses sale en LOS DOS, con lo de cada uno', () => {
    const grupos = agruparCartera(
      [cliente()],
      [
        contrato({ id: 'k-ago', capital: 20000, creado_en: '2026-08-10T15:00:00.000Z' }),
        contrato({ id: 'k-jul', capital: 5000, creado_en: '2026-07-20T15:00:00.000Z' }),
      ],
    )
    const meses = agruparPorMes(grupos)
    const agosto = meses.find((m) => m.clave === '2026-08')!
    const julio = meses.find((m) => m.clave === '2026-07')!
    expect(agosto.grupos).toHaveLength(1)
    expect(julio.grupos).toHaveLength(1)
    // El resumen del cliente se RECALCULA por mes: si se reutilizara el global,
    // julio enseñaría los 25.000 de toda su vida en vez de sus 5.000.
    expect(agosto.grupos[0]!.capitalActivoPen).toBe(20000)
    expect(julio.grupos[0]!.capitalActivoPen).toBe(5000)
    expect(agosto.grupos[0]!.contratos.map((c) => c.id)).toEqual(['k-ago'])
  })

  it('PEN y USD nunca se suman en el total del mes', () => {
    const grupos = agruparCartera(
      [cliente()],
      [
        contrato({ id: 'k-pen', capital: 20000, moneda: 'PEN' }),
        contrato({ id: 'k-usd', capital: 7000, moneda: 'USD' }),
      ],
    )
    const [agosto] = agruparPorMes(grupos)
    expect(agosto!.capitalPen).toBe(20000)
    expect(agosto!.capitalUsd).toBe(7000)
    expect(agosto!.contratos).toBe(2)
  })

  // «Qué cerré en agosto» incluye lo que ya venció: se cerró igual. La columna
  // «Capital invertido» de la fila sigue midiendo lo VIVO, que es otra pregunta.
  it('el total del mes cuenta los contratos de CUALQUIER estado', () => {
    const grupos = agruparCartera(
      [cliente()],
      [
        contrato({ id: 'k-activo', capital: 10000, estado: 'activo' }),
        contrato({ id: 'k-vencido', capital: 30000, estado: 'vencido' }),
      ],
    )
    const [agosto] = agruparPorMes(grupos)
    expect(agosto!.contratos).toBe(2)
    expect(agosto!.capitalPen).toBe(40000)
    // …y la fila del cliente sigue contando solo lo activo.
    expect(agosto!.grupos[0]!.capitalActivoPen).toBe(10000)
  })

  it('los clientes sin contrato van a su propio cubo, al final, y no se pierden', () => {
    const grupos = agruparCartera(
      [cliente({ id: 'c-1' }), cliente({ id: 'c-2', nombre_completo: 'SIN NADA' })],
      [contrato({ cliente_id: 'c-1' })],
    )
    const meses = agruparPorMes(grupos)
    expect(meses.map((m) => m.clave)).toEqual(['2026-08', CLAVE_SIN_CONTRATOS])
    const cubo = meses.at(-1)!
    expect(cubo.etiqueta).toBe('Clientes sin contrato')
    expect(cubo.grupos.map((g) => g.cliente.id)).toEqual(['c-2'])
    expect(cubo.contratos).toBe(0)
  })

  it('un contrato con fecha ilegible cae en su cubo y no tumba el resto', () => {
    const grupos = agruparCartera(
      [cliente()],
      [
        contrato({ id: 'k-ok' }),
        contrato({ id: 'k-roto', creado_en: 'vaya usted a saber' }),
      ],
    )
    const meses = agruparPorMes(grupos)
    expect(meses.map((m) => m.clave)).toEqual(['2026-08', CLAVE_SIN_FECHA])
    expect(meses.at(-1)!.etiqueta).toBe('Sin fecha de cierre')
  })

  it('cuenta cuántos contratos del mes los registró otra persona', () => {
    const grupos = agruparCartera(
      [cliente({ asesor_perfil_id: 'miguel' })],
      [
        contrato({ id: 'k-mio', creado_por: 'miguel' }),
        contrato({ id: 'k-ajeno', creado_por: 'carlos' }),
        contrato({ id: 'k-legado', creado_por: null }),
      ],
    )
    const [agosto] = agruparPorMes(grupos)
    expect(agosto!.contratos).toBe(3)
    expect(agosto!.registradosPorOtro).toBe(1)
  })

  it('sin clientes devuelve una lista vacía, no un bloque fantasma', () => {
    expect(agruparPorMes([])).toEqual([])
  })

  // ESTADO DE PRODUCCIÓN (gate de realidad): el analista con más recorrido de la
  // base tiene 16 contratos repartidos en 4 meses y uno de ellos lo registró
  // gerencia. Es el caso que se va a mirar en la prueba visual.
  it('el caso real: 4 meses, un contrato ajeno y un cliente todavía sin contrato', () => {
    const clientes = [
      cliente({ id: 'c-1', nombre_completo: 'MIGUEL SANTIAGO', asesor_perfil_id: 'miguel' }),
      cliente({ id: 'c-2', nombre_completo: 'QUISPE TUNQUE', asesor_perfil_id: 'miguel' }),
      cliente({ id: 'c-3', nombre_completo: 'RECIÉN CAPTADO', asesor_perfil_id: 'miguel' }),
    ]
    const contratos = [
      contrato({ id: 'k1', cliente_id: 'c-1', capital: 20000, creado_por: 'carlos', creado_en: '2026-08-14T16:55:00.000Z' }),
      contrato({ id: 'k2', cliente_id: 'c-2', capital: 5000, creado_por: 'miguel', creado_en: '2026-08-08T16:00:00.000Z' }),
      contrato({ id: 'k3', cliente_id: 'c-2', capital: 9000, creado_por: 'miguel', creado_en: '2026-07-02T16:00:00.000Z' }),
      contrato({ id: 'k4', cliente_id: 'c-1', capital: 4000, creado_por: 'miguel', creado_en: '2026-06-11T16:00:00.000Z' }),
      contrato({ id: 'k5', cliente_id: 'c-1', capital: 3000, creado_por: 'miguel', creado_en: '2026-05-30T16:00:00.000Z' }),
    ]
    const meses = agruparPorMes(agruparCartera(clientes, contratos))
    expect(meses.map((m) => m.clave)).toEqual([
      '2026-08', '2026-07', '2026-06', '2026-05', CLAVE_SIN_CONTRATOS,
    ])
    const agosto = meses[0]!
    expect(agosto.contratos).toBe(2)
    expect(agosto.capitalPen).toBe(25000)
    expect(agosto.registradosPorOtro).toBe(1)
    expect(meses.at(-1)!.grupos.map((g) => g.cliente.id)).toEqual(['c-3'])
  })
})

describe('el mes que manda es el de CIERRE, no el de registro', () => {
  // El caso que lo destapó: contrato 2026-01-001348, cerrado el domingo 31 de
  // agosto y tecleado el lunes 1 de septiembre a las 11:00 de Lima. La cuota lo
  // paga en agosto; el bloque tiene que decir lo mismo.
  it('un cierre de agosto tecleado el 1 de septiembre cae en AGOSTO', () => {
    const k = contrato({
      id: '1348',
      fecha_inicio: '2026-08-31',
      fecha_cierre_comercial: '2026-08-31',
      creado_en: '2026-09-01T16:00:49.024Z', // 11:00 de Lima
    })
    const meses = agruparPorMes(agruparCartera([cliente()], [k]))
    expect(meses.map((m) => m.clave)).toEqual(['2026-08'])
    expect(mesLima(k.creado_en)).toBe('2026-09') // el registro sigue siendo septiembre
  })

  // LA TRAMPA: `fecha_cierre_comercial` es una fecha SECA. Pasada por el
  // conversor de instantes, '2026-08-01' se leería como medianoche UTC = 31 de
  // JULIO en Lima. Son 49 contratos reales cerrados en día 1.
  it('un cierre el DÍA 1 no se escapa al mes anterior', () => {
    expect(mesDeCierre('2026-08-01')).toBe('2026-08')
    expect(mesLima('2026-08-01')).toBe('2026-07') // lo que habría pasado sin helper propio
    const k = contrato({ fecha_cierre_comercial: '2026-08-01', creado_en: '2026-08-01T16:00:00.000Z' })
    expect(agruparPorMes(agruparCartera([cliente()], [k]))[0]!.clave)
      .toBe('2026-08')
  })

  it('manda el cierre aunque la fecha de INICIO sea de otro mes', () => {
    const k = contrato({ fecha_inicio: '2026-09-03', fecha_cierre_comercial: '2026-08-28' })
    expect(agruparPorMes(agruparCartera([cliente()], [k]))[0]!.clave)
      .toBe('2026-08')
  })

  it('un cierre ilegible cae en su cubo, no en un mes inventado', () => {
    expect(mesDeCierre('')).toBeNull()
    expect(mesDeCierre('2026-13-01')).toBeNull()
    expect(mesDeCierre(null)).toBeNull()
    const k = contrato({ fecha_cierre_comercial: 'sin-fecha' })
    expect(agruparPorMes(agruparCartera([cliente()], [k]))[0]!.clave)
      .toBe(CLAVE_SIN_FECHA)
  })

  // La fecha de registro no se tira: es la única que nadie puede mover, y la
  // cabecera la declara para que el mes siga siendo auditable.
  it('cuenta cuántos se teclearon fuera de su mes', () => {
    const dentro = contrato({ id: 'a', fecha_cierre_comercial: '2026-08-20', creado_en: '2026-08-20T16:00:00.000Z' })
    const fuera = contrato({ id: 'b', fecha_cierre_comercial: '2026-08-31', creado_en: '2026-09-01T16:00:49.024Z' })
    expect(registradoEnOtroMes(dentro)).toBe(false)
    expect(registradoEnOtroMes(fuera)).toBe(true)
    const agosto = agruparPorMes(agruparCartera([cliente()], [dentro, fuera]))[0]!
    expect(agosto.contratos).toBe(2)
    expect(agosto.registradosEnOtroMes).toBe(1)
  })
})
