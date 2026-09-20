// El chip de tiempo: lo que el analista lee en vez de la sigla «SLA».
// Casos que importan: el futuro y el pasado se dicen distinto, el grupo
// «sin conversación» NO miente (su referencia no es un vencimiento), y el tono
// «vencido» coincide con la severidad crítica del servidor — que es lo que
// permite retirar el chip «Crítica» sin perder información.
import { describe, expect, it } from 'vitest'
import { paginaDeFilas, pestanasDiarias, textoTiempoDeFila, type FilaDiaria } from './gestion-diaria-analista'

const AHORA = Date.parse('2026-09-20T15:00:00Z')

function fila(parcial: Partial<FilaDiaria> = {}): FilaDiaria {
  return {
    lead_id: 'l1',
    nombre_completo: 'ROSA QUISPE MAMANI',
    etapa: 'nuevo',
    grupo: 'primera_atencion',
    referencia_en: null,
    tarea_id: null,
    severidad: 'media',
    senal: null,
    ...parcial,
  }
}

describe('textoTiempoDeFila', () => {
  it('dice lo que QUEDA cuando el límite está en el futuro', () => {
    expect(textoTiempoDeFila(fila({ referencia_en: '2026-09-20T15:40:00Z' }), AHORA))
      .toEqual({ texto: 'Quedan 40 min', tono: 'pendiente' })
    expect(textoTiempoDeFila(fila({ referencia_en: '2026-09-20T16:20:00Z' }), AHORA))
      .toEqual({ texto: 'Quedan 1 h 20 min', tono: 'pendiente' })
    expect(textoTiempoDeFila(fila({ referencia_en: '2026-09-20T17:00:00Z' }), AHORA))
      .toEqual({ texto: 'Quedan 2 h', tono: 'pendiente' })
  })

  it('dice lo que SE PASÓ cuando el límite ya venció, y ese es el tono crítico', () => {
    expect(textoTiempoDeFila(fila({ grupo: 'tarea_vencida', referencia_en: '2026-09-20T14:15:00Z', severidad: 'critica' }), AHORA))
      .toEqual({ texto: 'Se pasó hace 45 min', tono: 'vencido' })
    expect(textoTiempoDeFila(fila({ grupo: 'tarea_vencida', referencia_en: '2026-09-18T15:00:00Z', severidad: 'critica' }), AHORA))
      .toEqual({ texto: 'Se pasó hace 2 días', tono: 'vencido' })
    // Un solo día se dice en singular.
    expect(textoTiempoDeFila(fila({ grupo: 'tarea_vencida', referencia_en: '2026-09-19T15:00:00Z' }), AHORA).texto)
      .toBe('Se pasó hace 1 día')
  })

  it('NO dice «se pasó» en «sin conversación»: su referencia no es un vencimiento', () => {
    const senal = { dias_sin_conversacion: 11 } as FilaDiaria['senal']
    expect(textoTiempoDeFila(fila({ grupo: 'sin_conversacion', referencia_en: '2026-09-09T15:00:00Z', senal }), AHORA))
      .toEqual({ texto: 'Sin conversación hace 11 días', tono: 'neutro' })
  })

  it('sin señal y sin referencia, lo dice en vez de inventar un tiempo', () => {
    expect(textoTiempoDeFila(fila({ grupo: 'sin_conversacion' }), AHORA).texto).toBe('Sin conversación reciente')
    expect(textoTiempoDeFila(fila(), AHORA)).toEqual({ texto: 'Sin hora confirmada', tono: 'neutro' })
    expect(textoTiempoDeFila(fila({ referencia_en: 'no-es-una-fecha' }), AHORA).tono).toBe('neutro')
  })

  it('nunca dice «Quedan 0 min»: por debajo del minuto sigue quedando 1', () => {
    expect(textoTiempoDeFila(fila({ referencia_en: '2026-09-20T15:00:20Z' }), AHORA).texto).toBe('Quedan 1 min')
  })
})

describe('pestanasDiarias', () => {
  it('devuelve los CUATRO grupos con su conteo, también los vacíos', () => {
    const pestanas = pestanasDiarias([fila(), fila({ lead_id: 'l2', grupo: 'tarea_vencida' })])
    expect(pestanas.map((p) => [p.clave, p.total])).toEqual([
      ['primera_atencion', 1], ['tarea_vencida', 1], ['tarea_hoy', 0], ['sin_conversacion', 0],
    ])
  })

  it('ninguna ayuda menciona la sigla SLA', () => {
    for (const p of pestanasDiarias([])) expect(p.ayuda).not.toMatch(/SLA/i)
  })
})

describe('paginaDeFilas', () => {
  const seis = Array.from({ length: 6 }, (_, i) => fila({ lead_id: `l${i}` }))

  it('pagina de cinco en cinco y dice el rango', () => {
    expect(paginaDeFilas(seis, 0, 5)).toMatchObject({ pagina: 0, paginas: 2, rango: '1–5 de 6' })
    expect(paginaDeFilas(seis, 1, 5)).toMatchObject({ pagina: 1, rango: '6–6 de 6' })
  })

  it('ACOTA la página: al encoger la lista no se queda en una vacía', () => {
    expect(paginaDeFilas(seis.slice(0, 3), 1, 5)).toMatchObject({ pagina: 0, rango: '1–3 de 3' })
    expect(paginaDeFilas(seis, 99, 5).pagina).toBe(1)
    expect(paginaDeFilas(seis, -3, 5).pagina).toBe(0)
  })

  it('sin filas no inventa un rango', () => {
    expect(paginaDeFilas([], 0, 5)).toMatchObject({ rango: '0 de 0', paginas: 1, total: 0 })
  })
})
