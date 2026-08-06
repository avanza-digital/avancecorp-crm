import { describe, expect, it } from 'vitest'
import { ACCIONES, CAPS, can, puedeEscribir, ROL_LABEL, type Rol } from './roles'

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
    expect(can('gerencia', 'editarConfiguracion')).toBe(false)
    expect(can('gerencia', 'editarMetas')).toBe(true)
    expect(can('gerencia', 'editarCapacidad')).toBe(true)
    expect(can('gerencia', 'reasignar')).toBe(false)
    expect(can('directorio', 'reasignar')).toBe(false)
    expect(can('directorio', 'editarConfiguracion')).toBe(false)
    expect(can('directorio', 'verReportes')).toBe(true)
  })

  it('dirige la bandeja de alertas solo a vendedor, supervisor y Gerencia', () => {
    expect(can('vendedor', 'verAlertas')).toBe(true)
    expect(can('supervisor', 'verAlertas')).toBe(true)
    expect(can('gerencia', 'verAlertas')).toBe(true)
    expect(can('directorio', 'verAlertas')).toBe(false)
    expect(can('coordinador', 'verAlertas')).toBe(false)
  })

  it('acota al coordinador al reparto de la cola (C1): sin ámbito, sin cartera', () => {
    // repartirCola ≠ repartirLeads: la primera es la COLA GLOBAL (coordinador),
    // la segunda es bajar de la bandeja al vendedor (supervisor).
    expect(can('coordinador', 'repartirCola')).toBe(true)
    expect(can('gerencia', 'repartirCola')).toBe(false)
    expect(can('supervisor', 'repartirCola')).toBe(false)
    expect(can('vendedor', 'repartirCola')).toBe(false)
    expect(can('directorio', 'repartirCola')).toBe(false)
    // verTodo:false es el espejo exacto de la RLS (su ámbito de leads es ∅).
    expect(can('coordinador', 'verTodo')).toBe(false)
    expect(can('coordinador', 'verEquipo')).toBe(false)
    expect(can('coordinador', 'verCartera')).toBe(false)
    expect(can('coordinador', 'reasignar')).toBe(false)
    expect(can('coordinador', 'repartirLeads')).toBe(false)
    // Los roles operativos y de auditoría conservan la cartera unificada;
    // Gerencia entra solo a inteligencia comercial.
    for (const rol of ['vendedor', 'supervisor', 'directorio'] as const) {
      expect(can(rol, 'verCartera')).toBe(true)
    }
    expect(can('gerencia', 'verCartera')).toBe(false)
  })

  it('deja al vendedor VER configuración (su calendario ICS) sin poder editarla', () => {
    // Regresión: "Mi calendario de Google" (suscripción ICS de la agenda propia)
    // vive en la pantalla de configuración. Con verConfiguracion:false el
    // vendedor —el único rol que trabaja desde el celular— no llegaba a ella.
    expect(can('vendedor', 'verConfiguracion')).toBe(true)
    // Y NADA más: ver ≠ editar (metas del mes y demás escrituras son de gerencia).
    expect(can('vendedor', 'editarConfiguracion')).toBe(false)
    expect(can('vendedor', 'verTodo')).toBe(false)
    expect(can('vendedor', 'verEquipo')).toBe(false)
    expect(can('vendedor', 'reasignar')).toBe(false)
    // El directorio conserva su auditoría: ve la pantalla, no escribe nada — y
    // por eso la tarjeta ICS (gateada por puedeEscribir) no le aparece.
    expect(can('directorio', 'verConfiguracion')).toBe(true)
    expect(puedeEscribir('directorio')).toBe(false)
    // El coordinador sigue acotado a "Repartir": ni configuración ni agenda.
    expect(can('coordinador', 'verConfiguracion')).toBe(false)
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
    expect(puedeEscribir('gerencia')).toBe(false)
    expect(puedeEscribir('directorio')).toBe(false)
  })

  it('limita Gerencia a inteligencia, metas y capacidad', () => {
    expect(CAPS.gerencia).toEqual({
      verTodo: true,
      verEquipo: true,
      filtrarPorVendedor: true,
      reasignar: false,
      repartirLeads: false,
      repartirCola: false,
      verPipeline: false,
      verLeads: false,
      verAgenda: false,
      verGestionEquipo: false,
      verAlertas: true,
      verCartera: false,
      verConfiguracion: false,
      editarConfiguracion: false,
      verReportes: true,
      editarMetas: true,
      editarCapacidad: true,
      soloLecturaTotal: true,
    })
  })
})
