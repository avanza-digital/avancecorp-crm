import { describe, expect, it } from 'vitest'
import { CAPS, can, puedeEscribir, ROL_LABEL, type Accion, type Rol } from './roles'

const ACCIONES: Accion[] = [
  'verTodo',
  'verEquipo',
  'filtrarPorVendedor',
  'reasignar',
  'repartirLeads',
  'repartirCola',
  'verCartera',
  'verConfiguracion',
  'editarConfiguracion',
  'verReportes',
  'soloLecturaTotal',
]

describe('capacidades por rol', () => {
  it('mantiene una matriz completa y etiquetada para cada rol', () => {
    const roles = Object.keys(CAPS) as Rol[]

    expect(roles).toEqual(['vendedor', 'supervisor', 'gerencia', 'directorio', 'coordinador'])
    for (const rol of roles) {
      expect(Object.keys(CAPS[rol]).sort()).toEqual([...ACCIONES].sort())
      expect(ROL_LABEL[rol]).toBeTruthy()
    }
  })

  it('reserva las mutaciones globales para los roles operativos autorizados', () => {
    expect(can('vendedor', 'reasignar')).toBe(false)
    expect(can('supervisor', 'reasignar')).toBe(true)
    expect(can('gerencia', 'editarConfiguracion')).toBe(true)
    expect(can('directorio', 'reasignar')).toBe(false)
    expect(can('directorio', 'editarConfiguracion')).toBe(false)
    expect(can('directorio', 'verReportes')).toBe(true)
  })

  it('acota al coordinador al reparto de la cola (C1): sin ámbito, sin cartera', () => {
    // repartirCola ≠ repartirLeads: la primera es la COLA GLOBAL (coordinador),
    // la segunda es bajar de la bandeja al vendedor (supervisor).
    expect(can('coordinador', 'repartirCola')).toBe(true)
    expect(can('gerencia', 'repartirCola')).toBe(true)
    expect(can('supervisor', 'repartirCola')).toBe(false)
    expect(can('vendedor', 'repartirCola')).toBe(false)
    expect(can('directorio', 'repartirCola')).toBe(false)
    // verTodo:false es el espejo exacto de la RLS (su ámbito de leads es ∅).
    expect(can('coordinador', 'verTodo')).toBe(false)
    expect(can('coordinador', 'verEquipo')).toBe(false)
    expect(can('coordinador', 'verCartera')).toBe(false)
    expect(can('coordinador', 'reasignar')).toBe(false)
    expect(can('coordinador', 'repartirLeads')).toBe(false)
    // El resto de roles SÍ conserva la cartera unificada.
    for (const rol of ['vendedor', 'supervisor', 'gerencia', 'directorio'] as const) {
      expect(can(rol, 'verCartera')).toBe(true)
    }
  })

  it('degrada identidades ausentes o desconocidas a solo lectura total', () => {
    expect(can(null, 'soloLecturaTotal')).toBe(true)
    expect(can(undefined, 'verReportes')).toBe(false)
    expect(can('rol-inexistente' as Rol, 'reasignar')).toBe(false)
    expect(puedeEscribir(null)).toBe(false)
    expect(puedeEscribir('rol-inexistente' as Rol)).toBe(false)
  })

  it('solo permite escritura general a roles que no son de auditoría', () => {
    expect(puedeEscribir('vendedor')).toBe(true)
    expect(puedeEscribir('supervisor')).toBe(true)
    expect(puedeEscribir('gerencia')).toBe(true)
    expect(puedeEscribir('directorio')).toBe(false)
  })
})
