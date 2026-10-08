import { describe, expect, it } from 'vitest'
import {
  ACCIONES,
  administraSoloRolesCrm,
  CAPS,
  can,
  puedeAdministrarRolesCrm,
  puedeAdministrarUsuariosCrm,
  puedeCorregirDocumentoCliente,
  puedeEliminarContratos,
  puedeEliminarInversion,
  puedeEliminarInversiones,
  puedeEscribir,
  puedeOrganizarJerarquiaCrm,
  puedeVerDirectorioUsuariosCrm,
  ROL_LABEL,
  ROLES,
  type Rol,
} from './roles'

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
    expect(can('gerencia', 'editarMetas')).toBe(true)
    expect(can('gerencia', 'editarCapacidad')).toBe(true)
    expect(can('gerencia', 'reasignar')).toBe(true)
    expect(can('directorio', 'reasignar')).toBe(false)
    expect(can('directorio', 'editarConfiguracion')).toBe(false)
    expect(can('directorio', 'verReportes')).toBe(true)
  })

  it('dirige la bandeja de alertas solo a analista, supervisor y Gerencia', () => {
    expect(can('vendedor', 'verAlertas')).toBe(true)
    expect(can('supervisor', 'verAlertas')).toBe(true)
    expect(can('gerencia', 'verAlertas')).toBe(true)
    expect(can('directorio', 'verAlertas')).toBe(false)
    expect(can('coordinador', 'verAlertas')).toBe(false)
  })

  it('acota al coordinador al reparto de la cola (C1): sin ámbito, sin cartera', () => {
    // repartirCola ≠ repartirLeads: la primera es la COLA GLOBAL (coordinador),
    // la segunda es bajar de la bandeja al analista (supervisor).
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
    // Los roles operativos y de auditoría conservan la cartera unificada.
    for (const rol of ['vendedor', 'supervisor', 'gerencia', 'directorio'] as const) {
      expect(can(rol, 'verCartera')).toBe(true)
    }
  })

  it('deja al analista VER configuración (su calendario ICS) sin poder editarla', () => {
    // Regresión: "Mi calendario de Google" (suscripción ICS de la agenda propia)
    // vive en la pantalla de configuración. Con verConfiguracion:false el
    // analista —el único rol que trabaja desde el celular— no llegaba a ella.
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
    expect(puedeEscribir('gerencia')).toBe(true)
    expect(puedeEscribir('directorio')).toBe(false)
  })

  it('habilita Gerencia como operador total del CRM', () => {
    expect(CAPS.gerencia).toEqual({
      verTodo: true,
      verEquipo: true,
      filtrarPorVendedor: true,
      reasignar: true,
      repartirLeads: true,
      repartirCola: true,
      verPipeline: true,
      verLeads: true,
      verAgenda: true,
      verGestionEquipo: true,
      // El reparto diario por analista es un espacio operativo propio de
      // Supervisión, aunque Gerencia conserve otras puertas de reparto.
      verDerivacionesEquipo: false,
      verFacturacion: true,
      verCitasEquipo: true,
      verAlertas: true,
      // La ÚNICA excepción del operador total, y es deliberada (F2 lead
      // libre): la toma directa es del ANALISTA para sí mismo — espejo del
      // guard de crm.tomar_lead_libre, que rechaza a gerencia con 42501.
      // Su puerta para asignar sigue siendo el reparto.
      tomarLeadDirecto: false,
      verCartera: true,
      verConfiguracion: true,
      editarConfiguracion: true,
      verReportes: true,
      editarMetas: true,
      editarCapacidad: true,
      altaDirectaCliente: true,
      soloLecturaTotal: false,
    })
  })

  it('la toma directa es SOLO del analista (espejo del guard del servidor)', () => {
    expect(ROLES.filter((rol) => CAPS[rol].tomarLeadDirecto)).toEqual(['vendedor'])
  })

  it('Facturación es de Gerencia, Supervisión (su equipo) y Directorio (lectura); nadie más', () => {
    // Directorio desde el 08/10/2026 (Miguel: «sí, que la vea»): el servidor ya
    // le abría la empresa entera por ser lector global.
    expect(ROLES.filter((rol) => CAPS[rol].verFacturacion)).toEqual(['supervisor', 'gerencia', 'directorio'])
    expect(can('vendedor', 'verFacturacion')).toBe(false)
    expect(can('directorio', 'verFacturacion')).toBe(true)
    expect(can('coordinador', 'verFacturacion')).toBe(false)
    expect(can(null, 'verFacturacion')).toBe(false)
  })

  it('reserva Citas a Gerencia y Supervisión; el servidor reduce al equipo', () => {
    expect(ROLES.filter((rol) => CAPS[rol].verCitasEquipo)).toEqual(['supervisor', 'gerencia'])
    expect(can('supervisor', 'verCitasEquipo')).toBe(true)
    expect(can('gerencia', 'verCitasEquipo')).toBe(true)
    expect(can('vendedor', 'verCitasEquipo')).toBe(false)
    expect(can('directorio', 'verCitasEquipo')).toBe(false)
    expect(can('coordinador', 'verCitasEquipo')).toBe(false)
  })

  it('el alta directa de clientes (sin lead) es de Supervisión y Gerencia; el analista convierte leads', () => {
    expect(ROLES.filter((rol) => CAPS[rol].altaDirectaCliente)).toEqual(['supervisor', 'gerencia'])
    expect(can('vendedor', 'altaDirectaCliente')).toBe(false)
    expect(can(null, 'altaDirectaCliente')).toBe(false)
  })
})

describe('capacidades administrativas Portal ↔ CRM', () => {
  it('reserva la correccion del documento para Admin y Superadmin del Portal', () => {
    expect(puedeCorregirDocumentoCliente({ rol: 'gerencia', rol_portal: 'admin' })).toBe(true)
    expect(puedeCorregirDocumentoCliente({ rol: 'directorio', rol_portal: 'superadmin' })).toBe(true)
    expect(puedeCorregirDocumentoCliente({ rol: 'gerencia', rol_portal: 'directorio' })).toBe(false)
    expect(puedeCorregirDocumentoCliente({ rol: 'vendedor', rol_portal: 'analista' })).toBe(false)
    expect(puedeCorregirDocumentoCliente(null)).toBe(false)
  })

  it('reserva la eliminación contractual para Admin y Superadmin del Portal', () => {
    expect(puedeEliminarContratos({ rol: 'vendedor', rol_portal: 'analista' })).toBe(false)
    expect(puedeEliminarContratos({ rol: 'gerencia', rol_portal: 'directorio' })).toBe(false)
    expect(puedeEliminarContratos({ rol: 'directorio', rol_portal: 'admin' })).toBe(true)
    expect(puedeEliminarContratos({ rol: 'vendedor', rol_portal: 'superadmin' })).toBe(true)
    expect(puedeEliminarContratos(null)).toBe(false)
  })

  // «Eliminar inversión» (05/10/2026): espejo del gate de crm.eliminar_inversion_fn.
  // Avance la borra el contrato auditado (solo Admin/Superadmin del Portal); las
  // cooperativas, también Gerencia del CRM.
  it.each([
    ['admin del portal', { rol: 'directorio' as const, rol_portal: 'admin' }, true, true, true],
    ['superadmin del portal', { rol: 'vendedor' as const, rol_portal: 'superadmin' }, true, true, true],
    ['gerencia sin admin del portal', { rol: 'gerencia' as const, rol_portal: 'directorio' }, true, false, true],
    ['gerencia y admin del portal', { rol: 'gerencia' as const, rol_portal: 'admin' }, true, true, true],
    ['analista', { rol: 'vendedor' as const, rol_portal: 'analista' }, false, false, false],
    ['supervisor', { rol: 'supervisor' as const, rol_portal: 'comercial' }, false, false, false],
    ['directorio', { rol: 'directorio' as const, rol_portal: 'directorio' }, false, false, false],
    ['sin identidad', null, false, false, false],
  ])('eliminar inversiones · %s: general %s, Avance %s, cooperativa %s', (_, identidad, general, avance, cooperativa) => {
    expect(puedeEliminarInversiones(identidad)).toBe(general)
    expect(puedeEliminarInversion(identidad, { empresa: 'avance' })).toBe(avance)
    expect(puedeEliminarInversion(identidad, { empresa: 'qorilazo' })).toBe(cooperativa)
    expect(puedeEliminarInversion(identidad, { empresa: 'prodelco' })).toBe(cooperativa)
  })

  it('Gerencia administra personas y jerarquía, pero no roles', () => {
    const yo = { rol: 'gerencia' as const, rol_portal: 'directorio' }
    expect(puedeAdministrarUsuariosCrm(yo)).toBe(true)
    expect(puedeOrganizarJerarquiaCrm(yo)).toBe(true)
    expect(puedeAdministrarRolesCrm(yo)).toBe(false)
  })

  it('Superadmin administra roles, pero no personas ni jerarquía', () => {
    const yo = { rol: 'directorio' as const, rol_portal: 'superadmin' }
    expect(puedeAdministrarRolesCrm(yo)).toBe(true)
    expect(administraSoloRolesCrm(yo)).toBe(true)
    expect(puedeAdministrarUsuariosCrm(yo)).toBe(false)
    expect(puedeOrganizarJerarquiaCrm(yo)).toBe(false)
    expect(puedeVerDirectorioUsuariosCrm(yo)).toBe(true)
    expect(puedeEscribir(yo.rol)).toBe(false)
  })

  it('Gerencia + Superadmin suma autoridades y no se reduce a solo roles', () => {
    const yo = { rol: 'gerencia' as const, rol_portal: 'superadmin' }
    expect(puedeAdministrarRolesCrm(yo)).toBe(true)
    expect(administraSoloRolesCrm(yo)).toBe(false)
  })

  it('Directorio normal solo consulta y una identidad ausente queda cerrada', () => {
    expect(puedeVerDirectorioUsuariosCrm({ rol: 'directorio' })).toBe(true)
    expect(puedeAdministrarRolesCrm({ rol: 'directorio', rol_portal: 'admin' })).toBe(false)
    expect(puedeVerDirectorioUsuariosCrm(null)).toBe(false)
  })

  it('prioriza las capacidades vivas del servidor sobre inferencias de UX', () => {
    const identidad = {
      rol: 'gerencia' as const,
      rol_portal: 'superadmin',
      capacidades_config: {
        puede_listar_usuarios: true,
        puede_administrar_usuarios: false,
        puede_organizar_jerarquia: false,
        puede_administrar_roles: false,
      },
    }
    expect(puedeVerDirectorioUsuariosCrm(identidad)).toBe(true)
    expect(puedeAdministrarUsuariosCrm(identidad)).toBe(false)
    expect(puedeOrganizarJerarquiaCrm(identidad)).toBe(false)
    expect(puedeAdministrarRolesCrm(identidad)).toBe(false)
    expect(administraSoloRolesCrm(identidad)).toBe(false)
  })
})
