import { describe, expect, it } from 'vitest'
import type { AlertaCRM } from './alertas'
import {
  aplicarReconocimientos,
  reconocimientoVigente,
  ultimoAsientoPorAlerta,
  type AsientoReconocimiento,
} from './reconocimientos-alertas'

// Reloj congelado del arnés: 2026-08-23T15:00Z.
const AHORA = Date.UTC(2026, 7, 23, 15)
const DIA_MS = 86_400_000

function asiento(over: Partial<AsientoReconocimiento> = {}): AsientoReconocimiento {
  return {
    id: '0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0001',
    alerta_id: 'grupo:por_repartir:s1',
    accion: 'reconocer',
    miembros: ['lead-1', 'lead-2'],
    severidad: 'atencion',
    hasta: null,
    creado_en: new Date(AHORA - DIA_MS).toISOString(),
    secuencia: 1,
    ...over,
  }
}

function alerta(over: Partial<AlertaCRM> = {}): AlertaCRM {
  return {
    id: 'grupo:por_repartir:s1',
    tipo: 'por_repartir',
    severidad: 'atencion',
    alcance: 'equipo',
    titulo: '2 leads esperando reparto',
    detalle: 'A, B.',
    responsableId: 's1',
    responsable: null,
    valor: 2,
    miembros: ['lead-1', 'lead-2'],
    destino: { vista: 'derivaciones', leadId: null, etiqueta: 'Repartir' },
    ...over,
  }
}

describe('ultimoAsientoPorAlerta', () => {
  it('manda la SECUENCIA, no creado_en: dos asientos con la misma fecha no empatan', () => {
    // El contrato de F4.1: clock_timestamp() puede empatar al microsegundo;
    // la identity es el orden total del libro.
    const mismoInstante = new Date(AHORA - DIA_MS).toISOString()
    const viejo = asiento({ secuencia: 3, accion: 'reconocer', creado_en: mismoInstante })
    const nuevo = asiento({ secuencia: 4, accion: 'posponer', hasta: new Date(AHORA + DIA_MS).toISOString(), creado_en: mismoInstante })
    // Orden de llegada adverso (el nuevo primero): el resultado no depende de él.
    expect(ultimoAsientoPorAlerta([nuevo, viejo]).ultimo.get('grupo:por_repartir:s1')).toBe(nuevo)
    expect(ultimoAsientoPorAlerta([viejo, nuevo]).ultimo.get('grupo:por_repartir:s1')).toBe(nuevo)
  })

  it('separa por alerta: el libro gobierna cada grupo por su cuenta', () => {
    const a = asiento({ alerta_id: 'grupo:por_repartir:s1', secuencia: 1 })
    const b = asiento({ alerta_id: 'grupo:tarea_vencida:s1', secuencia: 2 })
    const { ultimo, empatadas } = ultimoAsientoPorAlerta([a, b])
    expect(ultimo.get('grupo:por_repartir:s1')).toBe(a)
    expect(ultimo.get('grupo:tarea_vencida:s1')).toBe(b)
    expect(empatadas.size).toBe(0)
  })

  it('una secuencia GANADORA duplicada marca la alerta como empatada (libro corrupto)', () => {
    // La identity del servidor lo hace imposible por la vía normal; si
    // aparece (restauración, doble carga), no se adivina un ganador.
    const a = asiento({ id: '0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0001', secuencia: 5, accion: 'reconocer' })
    const b = asiento({
      id: '0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0002',
      secuencia: 5,
      accion: 'posponer',
      hasta: new Date(AHORA + DIA_MS).toISOString(),
    })
    // En ambos órdenes de llegada el veredicto es el mismo: empatada.
    expect(ultimoAsientoPorAlerta([a, b]).empatadas.has('grupo:por_repartir:s1')).toBe(true)
    expect(ultimoAsientoPorAlerta([b, a]).empatadas.has('grupo:por_repartir:s1')).toBe(true)
    // Una secuencia MAYOR posterior limpia el empate: vuelve a haber ganador.
    const gana = asiento({ id: '0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0003', secuencia: 6 })
    expect(ultimoAsientoPorAlerta([a, b, gana]).empatadas.size).toBe(0)
  })
})

describe('reconocimientoVigente', () => {
  it('un reconocimiento fresco sobre el mismo grupo VIGE y trae su vencimiento', () => {
    const vigente = reconocimientoVigente(alerta(), asiento(), AHORA)
    expect(vigente).toMatchObject({ accion: 'reconocer' })
    // Vence a los 7 días del creado_en (que fue hace 1): quedan 6.
    expect(vigente?.venceEn).toBe(AHORA - DIA_MS + 7 * DIA_MS)
  })

  it('CADUCA a los 7 días exactos del creado_en — el candado acotado del servidor', () => {
    const alFilo = asiento({ creado_en: new Date(AHORA - 7 * DIA_MS).toISOString() })
    expect(reconocimientoVigente(alerta(), alFilo, AHORA)).toBeNull()
    const unMsAntes = asiento({ creado_en: new Date(AHORA - 7 * DIA_MS + 1).toISOString() })
    expect(reconocimientoVigente(alerta(), unMsAntes, AHORA)).not.toBeNull()
  })

  it('posponer cede en su `hasta` aunque los 7 días no hayan corrido — igualdad exacta incluida', () => {
    const pospuesta = asiento({
      accion: 'posponer',
      hasta: new Date(AHORA - 1).toISOString(),
      creado_en: new Date(AHORA - DIA_MS).toISOString(),
    })
    expect(reconocimientoVigente(alerta(), pospuesta, AHORA)).toBeNull()
    // Con hasta == ahora también cede (mutante `<` en vez de `<=`, Codex #9).
    const alFilo = asiento({
      accion: 'posponer',
      hasta: new Date(AHORA).toISOString(),
      creado_en: new Date(AHORA - DIA_MS).toISOString(),
    })
    expect(reconocimientoVigente(alerta(), alFilo, AHORA)).toBeNull()
  })

  it('posponer vigente vence en el MÍNIMO entre su hasta y los 7 días', () => {
    const hasta = new Date(AHORA + 2 * DIA_MS).toISOString()
    const pospuesta = asiento({ accion: 'posponer', hasta })
    expect(reconocimientoVigente(alerta(), pospuesta, AHORA)?.venceEn).toBe(Date.parse(hasta))
  })

  it('REAPARECE si un miembro nuevo entra al grupo — la foto ya no lo cubre', () => {
    const conNuevo = alerta({ miembros: ['lead-1', 'lead-2', 'lead-3'] })
    expect(reconocimientoVigente(conNuevo, asiento(), AHORA)).toBeNull()
  })

  it('un miembro que SALIÓ no revive nada: mejorar no despierta alertas', () => {
    const mejorado = alerta({ miembros: ['lead-1'] })
    expect(reconocimientoVigente(mejorado, asiento(), AHORA)).not.toBeNull()
  })

  it('REAPARECE si la severidad subió sobre la reconocida, y no al revés', () => {
    const subio = alerta({ severidad: 'critica' })
    expect(reconocimientoVigente(subio, asiento({ severidad: 'atencion' }), AHORA)).toBeNull()
    const bajo = alerta({ severidad: 'atencion' })
    expect(reconocimientoVigente(bajo, asiento({ severidad: 'critica' }), AHORA)).not.toBeNull()
  })

  it('sin asiento, sin miembros en la alerta o con fechas ilegibles: la alerta suena', () => {
    expect(reconocimientoVigente(alerta(), undefined, AHORA)).toBeNull()
    // Una alerta SIN foto (no agrupada) jamás se atenúa.
    expect(reconocimientoVigente({ severidad: 'atencion' }, asiento(), AHORA)).toBeNull()
    // Un dato corrupto no se convierte en silencio.
    expect(reconocimientoVigente(alerta(), asiento({ creado_en: 'no-fecha' }), AHORA)).toBeNull()
    expect(
      reconocimientoVigente(alerta(), asiento({ accion: 'posponer', hasta: null }), AHORA),
    ).toBeNull()
  })
})

describe('aplicarReconocimientos', () => {
  it('reconocer ATENÚA sin borrar (va al final, con traza) y descuenta del conteo', () => {
    const roja = alerta({ id: 'grupo:tarea_vencida:s1', severidad: 'critica', miembros: ['lead-9'] })
    const reconocida = alerta()
    const { visibles, pendientes } = aplicarReconocimientos(
      [reconocida, roja],
      [asiento()],
      AHORA,
    )
    expect(pendientes).toBe(1)
    // La activa primero aunque llegó después; la reconocida al final, marcada.
    expect(visibles.map((fila) => fila.id)).toEqual(['grupo:tarea_vencida:s1', 'grupo:por_repartir:s1'])
    expect(visibles[1]?.reconocimiento?.accion).toBe('reconocer')
    expect(visibles[0]?.reconocimiento).toBeUndefined()
  })

  it('posponer OCULTA de lista y campana hasta su fecha — pero se CUENTA (nada se niega)', () => {
    const pospuesta = asiento({ accion: 'posponer', hasta: new Date(AHORA + DIA_MS).toISOString() })
    const { visibles, pendientes, pospuestas } = aplicarReconocimientos([alerta()], [pospuesta], AHORA)
    expect(visibles).toEqual([])
    expect(pendientes).toBe(0)
    expect(pospuestas).toBe(1)
  })

  it('con el libro vacío devuelve las alertas tal cual — la degradación honesta', () => {
    const alertas = [alerta(), alerta({ id: 'grupo:tarea_vencida:s1' })]
    const { visibles, pendientes, pospuestas } = aplicarReconocimientos(alertas, [], AHORA)
    expect(visibles).toEqual(alertas)
    expect(pendientes).toBe(2)
    expect(pospuestas).toBe(0)
  })

  it('una alerta con la secuencia ganadora EMPATADA suena entera: fail-loud, no adivinanza', () => {
    const a = asiento({ id: '0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0001', secuencia: 5, accion: 'posponer', hasta: new Date(AHORA + DIA_MS).toISOString() })
    const b = asiento({ id: '0b0b2f6a-3d55-49a4-9a10-1f2f6f6e0002', secuencia: 5, accion: 'reconocer' })
    const { visibles, pendientes, pospuestas } = aplicarReconocimientos([alerta()], [a, b], AHORA)
    expect(visibles).toEqual([alerta()])
    expect(pendientes).toBe(1)
    expect(pospuestas).toBe(0)
  })

  it('un posponer que SUPERSEDE a un reconocer manda aunque comparta fecha', () => {
    const mismoInstante = new Date(AHORA - DIA_MS).toISOString()
    const { visibles } = aplicarReconocimientos(
      [alerta()],
      [
        asiento({ secuencia: 2, accion: 'posponer', hasta: new Date(AHORA + DIA_MS).toISOString(), creado_en: mismoInstante }),
        asiento({ secuencia: 1, accion: 'reconocer', creado_en: mismoInstante }),
      ],
      AHORA,
    )
    expect(visibles).toEqual([])
  })
})
