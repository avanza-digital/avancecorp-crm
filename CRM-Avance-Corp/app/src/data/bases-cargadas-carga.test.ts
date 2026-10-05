// La carga en lotes (F5): crea la base y envía los lotes EN ORDEN, cada uno con su id de operación fijo; «otra carga en
// curso» (55P03) se reintenta sola con espera creciente y un tope; la red cortada PAUSA y «Reintentar» sigue desde el
// mismo lote con el MISMO id (el servidor devuelve la misma respuesta: nunca carga dos veces).
import { describe, expect, it, vi } from 'vitest'
import { ErrorBases } from './bases-cargadas-api'
import { AVANCE_INICIAL, MAX_REINTENTOS_OCUPADO, confirmarLoteIncierto, ejecutarCarga, esperaReintento, type PlanCarga, type PuertasCarga } from './bases-cargadas-carga'
import { esFalloIncierto, esRechazoDefinitivo } from './bases-cargadas-api'

vi.mock('@/lib/supabase', () => ({ sb: null }))

const PLAN: PlanCarga = {
  crear: { operacionId: 'op-crear', nombre: 'Feria', archivoNombre: 'feria.csv', supervisorId: null },
  lotes: [
    { operacionId: 'op-1', filas: [{ fila: 2, nombre: 'A', telefono: '+51987000001' }, { fila: 3, nombre: 'B', telefono: '+51987000002' }] },
    { operacionId: 'op-2', filas: [{ fila: 4, nombre: 'C', telefono: '+51987000003' }] },
  ],
}
const respuestaLote = (filas: { fila: number }[]) => ({
  ok: true as const, base_id: 'base-1', lote: { cargadas: filas.length, ya_existian: 0, no_contactar: 0, invalidas: 0, repetidas: 0 },
  base: { filas_recibidas: 0, cargadas: 0 }, filas: filas.map((f) => ({ fila: f.fila, veredicto: 'cargada', motivo: null, lead_id: null })),
})

function puertas(sobre: Partial<PuertasCarga> = {}): PuertasCarga & { crearBase: ReturnType<typeof vi.fn>; cargarBaseLote: ReturnType<typeof vi.fn>; esperar: ReturnType<typeof vi.fn> } {
  return {
    crearBase: vi.fn(async () => ({ ok: true as const, base_id: 'base-1', supervisor_id: 'sup' })),
    cargarBaseLote: vi.fn(async ({ filas }: { filas: { fila: number }[] }) => respuestaLote(filas)),
    esperar: vi.fn(async () => undefined),
    alAvanzar: vi.fn(),
    ...sobre,
  } as never
}

describe('ejecutarCarga', () => {
  it('crea la base y envía los lotes en orden con sus ids fijos; junta los veredictos de cada fila', async () => {
    const p = puertas()
    const fin = await ejecutarCarga(PLAN, AVANCE_INICIAL, p)
    expect(fin.tipo).toBe('completa')
    expect(p.crearBase).toHaveBeenCalledWith(PLAN.crear)
    expect(p.cargarBaseLote.mock.calls.map(([e]) => [e.operacionId, e.baseId, e.filas.length])).toEqual([['op-1', 'base-1', 2], ['op-2', 'base-1', 1]])
    expect(fin.avance).toMatchObject({ baseId: 'base-1', lotesHechos: 2, filasHechas: 3 })
    expect(fin.avance.resultados.map((r) => r.fila)).toEqual([2, 3, 4])
    expect(p.alAvanzar).toHaveBeenCalledWith(expect.objectContaining({ lotesHechos: 1, filasHechas: 2 }))
  })

  it('«otra carga en curso» (OCUPADO): reintenta sola, con espera creciente, el MISMO lote con el MISMO id', async () => {
    let n = 0
    const p = puertas({
      cargarBaseLote: vi.fn(async (e: { operacionId: string; filas: { fila: number }[] }) => {
        n += 1
        if (e.operacionId === 'op-1' && n <= 2) throw new ErrorBases('Hay otra carga en curso de esta base; reintenta', 'OCUPADO')
        return respuestaLote(e.filas)
      }) as never,
    })
    const fin = await ejecutarCarga(PLAN, AVANCE_INICIAL, p)
    expect(fin.tipo).toBe('completa')
    expect(p.cargarBaseLote.mock.calls.map(([e]) => e.operacionId)).toEqual(['op-1', 'op-1', 'op-1', 'op-2'])
    expect(p.esperar.mock.calls.map(([ms]) => ms)).toEqual([esperaReintento(1), esperaReintento(2)])
    expect(p.alAvanzar).toHaveBeenCalledWith(expect.objectContaining({ reintento: 2, lotesHechos: 0 }))
  })

  it(`tras ${MAX_REINTENTOS_OCUPADO} reintentos se pausa (no insiste para siempre)`, async () => {
    const p = puertas({ cargarBaseLote: vi.fn(async () => { throw new ErrorBases('ocupada', 'OCUPADO') }) as never })
    const fin = await ejecutarCarga(PLAN, AVANCE_INICIAL, p)
    expect(fin).toMatchObject({ tipo: 'pausada', error: { code: 'OCUPADO' }, avance: { lotesHechos: 0, baseId: 'base-1' } })
    expect(p.cargarBaseLote).toHaveBeenCalledTimes(MAX_REINTENTOS_OCUPADO + 1)
  })

  it('la red se corta en el 2.º lote: se pausa ahí; «Reintentar» sigue desde ese lote con su MISMO id y no recrea la base', async () => {
    let cortar = true
    const p = puertas({
      cargarBaseLote: vi.fn(async (e: { operacionId: string; filas: { fila: number }[] }) => {
        if (e.operacionId === 'op-2' && cortar) { cortar = false; throw new ErrorBases('Se cortó la conexión', 'RED') }
        return respuestaLote(e.filas)
      }) as never,
    })
    const pausa = await ejecutarCarga(PLAN, AVANCE_INICIAL, p)
    expect(pausa).toMatchObject({ tipo: 'pausada', error: { code: 'RED' }, avance: { lotesHechos: 1, filasHechas: 2 } })
    expect(p.esperar).not.toHaveBeenCalled()
    const fin = await ejecutarCarga(PLAN, pausa.avance, p)
    expect(fin.tipo).toBe('completa')
    expect(p.crearBase).toHaveBeenCalledTimes(1)
    expect(p.cargarBaseLote.mock.calls.map(([e]) => e.operacionId)).toEqual(['op-1', 'op-2', 'op-2'])
    expect(fin.avance.resultados.map((r) => r.fila)).toEqual([2, 3, 4])
  })

  it('si falla CREAR, no se envía ningún lote; un error que no es de la casa se vuelve un fallo legible', async () => {
    const p = puertas({ crearBase: vi.fn(async () => { throw new ErrorBases('Ya hay una base viva con ese nombre', 'NOMBRE_REPETIDO') }) as never })
    expect(await ejecutarCarga(PLAN, AVANCE_INICIAL, p)).toMatchObject({ tipo: 'pausada', error: { code: 'NOMBRE_REPETIDO' }, avance: { baseId: null } })
    expect(p.cargarBaseLote).not.toHaveBeenCalled()
    const raro = puertas({ crearBase: vi.fn(async () => { throw new TypeError('x') }) as never })
    expect(await ejecutarCarga(PLAN, AVANCE_INICIAL, raro)).toMatchObject({ tipo: 'pausada', error: { code: 'DESCONOCIDO' } })
  })

  it('confirmarLoteIncierto: repite el lote del corte con su MISMO id; si responde, sus filas cuentan; si no, queda sin confirmar', async () => {
    const desde = { baseId: 'base-1', lotesHechos: 1, filasHechas: 2, resultados: [], reintento: 0, incierto: true }
    const p = puertas()
    const r = await confirmarLoteIncierto(PLAN, desde, p)
    expect(p.cargarBaseLote).toHaveBeenCalledWith({ operacionId: 'op-2', baseId: 'base-1', filas: PLAN.lotes[1]?.filas })
    expect(r).toMatchObject({ confirmado: true, avance: { lotesHechos: 2, filasHechas: 3 } })
    const sinRespuesta = puertas({ cargarBaseLote: vi.fn(async () => { throw new ErrorBases('red', 'RED') }) as never })
    expect(await confirmarLoteIncierto(PLAN, desde, sinRespuesta)).toMatchObject({ confirmado: false, avance: { lotesHechos: 1 } })
    const rechazo = puertas({ cargarBaseLote: vi.fn(async () => { throw new ErrorBases('regla', 'REGLA_SERVIDOR') }) as never })
    expect(await confirmarLoteIncierto(PLAN, desde, rechazo)).toMatchObject({ confirmado: true, avance: { lotesHechos: 1 } })
  })

  it('qué es incierto (repetir con el mismo id) y qué es un rechazo definitivo (corregir el pedido)', () => {
    expect(esFalloIncierto(new ErrorBases('x', 'RED'))).toBe(true)
    expect(esFalloIncierto(new ErrorBases('x', 'BASES_CONTRACT'))).toBe(true)
    expect(esFalloIncierto(new TypeError('x'))).toBe(true)
    expect(esFalloIncierto(new ErrorBases('x', 'OCUPADO'))).toBe(false)
    expect(esFalloIncierto(new ErrorBases('x', 'REGLA_SERVIDOR'))).toBe(false)
    expect(esRechazoDefinitivo(new ErrorBases('x', 'NOMBRE_REPETIDO'))).toBe(true)
    expect(esRechazoDefinitivo(new ErrorBases('x', 'RED'))).toBe(false)
  })

  it('Codex r2: RED y después «otra operación en curso» (55P03) NO resuelven el lote: sigue incierto hasta el recibo de ESE id', async () => {
    let fase: 'red' | 'ocupado' | 'recibo' = 'red'
    const p = puertas({
      cargarBaseLote: vi.fn(async (e: { operacionId: string; filas: { fila: number }[] }) => {
        if (fase === 'red') { fase = 'ocupado'; throw new ErrorBases('red', 'RED') }
        if (fase === 'ocupado') throw new ErrorBases('Hay otra carga en curso de esta base; reintenta', 'OCUPADO')
        return respuestaLote(e.filas)
      }) as never,
    })
    const solo = { ...PLAN, lotes: PLAN.lotes.slice(0, 1) }
    const corte = await ejecutarCarga(solo, AVANCE_INICIAL, p)
    expect(corte).toMatchObject({ tipo: 'pausada', error: { code: 'RED' }, avance: { lotesHechos: 0, incierto: true } })
    // «Reintentar»: el mismo id choca con la original, que sigue corriendo → 55P03 hasta el tope. Sigue incierto.
    const ocupado = await ejecutarCarga(solo, corte.avance, p)
    expect(ocupado).toMatchObject({ tipo: 'pausada', error: { code: 'OCUPADO' }, avance: { lotesHechos: 0, incierto: true } })
    // «Terminar aquí» mientras sigue ocupada: no se puede confirmar → «sin confirmar» (nunca «sin enviar»).
    expect(await confirmarLoteIncierto(solo, ocupado.avance, p)).toMatchObject({ confirmado: false, avance: { incierto: true, lotesHechos: 0 } })
    // La original terminó: el mismo id devuelve su recibo y el lote cuenta con sus filas.
    fase = 'recibo'
    const r = await confirmarLoteIncierto(solo, ocupado.avance, p)
    expect(r).toMatchObject({ confirmado: true, avance: { incierto: false, lotesHechos: 1, filasHechas: 2 } })
    expect(r.avance.resultados.map((x) => x.veredicto)).toEqual(['cargada', 'cargada'])
    expect(new Set(p.cargarBaseLote.mock.calls.map(([e]) => (e as { operacionId: string }).operacionId))).toEqual(new Set(['op-1']))
  })

  it('un rechazo definitivo del mismo id SÍ resuelve (no se guardó): queda «sin enviar»; sin incertidumbre no se repite nada', async () => {
    const desde = { baseId: 'base-1', lotesHechos: 0, filasHechas: 0, resultados: [], reintento: 0, incierto: true }
    const rechazo = puertas({ cargarBaseLote: vi.fn(async () => { throw new ErrorBases('Una base recibe hasta 5000 filas', 'REGLA_SERVIDOR') }) as never })
    expect(await confirmarLoteIncierto(PLAN, desde, rechazo)).toMatchObject({ confirmado: true, avance: { incierto: false, lotesHechos: 0 } })
    const nada = puertas()
    expect(await confirmarLoteIncierto(PLAN, { ...desde, incierto: false }, nada)).toMatchObject({ confirmado: true })
    expect(nada.cargarBaseLote).not.toHaveBeenCalled()
  })
})
