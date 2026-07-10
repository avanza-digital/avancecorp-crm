import { describe, expect, it } from 'vitest'
import { CAPS, can, puedeEscribir, ROL_LABEL, type Accion, type Rol } from './roles'

const ACCIONES: Accion[] = [
  'verTodo',
  'verEquipo',
  'filtrarPorVendedor',
  'reasignar',
  'repartirLeads',
  'verConfiguracion',
  'editarConfiguracion',
  'verReportes',
  'soloLecturaTotal',
]

describe('capacidades por rol', () => {
  it('mantiene una matriz completa y etiquetada para cada rol', () => {
    const roles = Object.keys(CAPS) as Rol[]

    expect(roles).toEqual(['vendedor', 'supervisor', 'gerencia', 'directorio'])
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
