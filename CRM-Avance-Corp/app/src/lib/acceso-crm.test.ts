import { describe, expect, it } from 'vitest'
import { interpretarMiAcceso, interpretarMiAccesoParaUsuario } from './acceso-crm'

const SIN_ADMIN = {
  puede_listar_usuarios: false,
  puede_administrar_usuarios: false,
  puede_organizar_jerarquia: false,
  puede_administrar_roles: false,
} as const

describe('interpretarMiAcceso', () => {
  it('acepta una membresía activa y conserva la capacidad del portal', () => {
    expect(interpretarMiAcceso({
      estado: 'miembro',
      perfil_id: 'user-1',
      rol_crm: 'vendedor',
      rol_portal: 'analista',
      nombre_completo: 'Ana Analista',
      ...SIN_ADMIN,
    })).toEqual({
      tipo: 'acceso',
      perfilId: 'user-1',
      rol: 'vendedor',
      rolPortal: 'analista',
      capacidadesConfig: {
        puedeListarUsuarios: false,
        puedeAdministrarUsuarios: false,
        puedeOrganizarJerarquia: false,
        puedeAdministrarRoles: false,
      },
      nombre: 'Ana Analista',
      puedeContratar: true,
    })
  })

  it('autoriza a Gerencia a contratar desde el CRM sin volverla admin del portal', () => {
    expect(interpretarMiAcceso({
      estado: 'miembro',
      perfil_id: 'gerencia-1',
      rol_crm: 'gerencia',
      rol_portal: 'comercial',
      nombre_completo: 'Gerencia',
      puede_listar_usuarios: true,
      puede_administrar_usuarios: true,
      puede_organizar_jerarquia: true,
      puede_administrar_roles: false,
    })).toMatchObject({ tipo: 'acceso', rol: 'gerencia', puedeContratar: true })
  })

  it('acepta el fallback global solo como Directorio', () => {
    expect(interpretarMiAcceso({
      estado: 'global',
      perfil_id: 'user-2',
      rol_crm: 'directorio',
      rol_portal: 'directorio',
      nombre_completo: null,
      puede_listar_usuarios: true,
      puede_administrar_usuarios: false,
      puede_organizar_jerarquia: false,
      puede_administrar_roles: false,
    })).toEqual({
      tipo: 'acceso',
      perfilId: 'user-2',
      rol: 'directorio',
      rolPortal: 'directorio',
      capacidadesConfig: {
        puedeListarUsuarios: true,
        puedeAdministrarUsuarios: false,
        puedeOrganizarJerarquia: false,
        puedeAdministrarRoles: false,
      },
      nombre: '',
      puedeContratar: false,
    })
  })

  it('acepta Superadmin sin Gerencia como autoridad exclusiva de roles', () => {
    expect(interpretarMiAcceso({
      estado: 'administrador_roles',
      perfil_id: 'superadmin-1',
      rol_portal: 'superadmin',
      nombre_completo: 'SUPERADMIN',
      puede_listar_usuarios: true,
      puede_administrar_usuarios: false,
      puede_organizar_jerarquia: false,
      puede_administrar_roles: true,
    })).toEqual({
      tipo: 'acceso',
      perfilId: 'superadmin-1',
      rol: 'directorio',
      rolPortal: 'superadmin',
      capacidadesConfig: {
        puedeListarUsuarios: true,
        puedeAdministrarUsuarios: false,
        puedeOrganizarJerarquia: false,
        puedeAdministrarRoles: true,
      },
      nombre: 'SUPERADMIN',
      puedeContratar: false,
    })
  })

  it.each(['revocado', 'no_enrolado'])('cierra el acceso para estado %s', (estado) => {
    expect(interpretarMiAcceso({ estado, perfil_id: 'user-off' })).toEqual({
      tipo: 'sin_acceso',
      perfilId: 'user-off',
    })
  })

  it.each([
    null,
    {},
    { estado: 'revocado' },
    { estado: 'otro', perfil_id: 'user-1' },
    { estado: 'miembro', perfil_id: 'user-1', rol_crm: 'directorio', rol_portal: 'admin', nombre_completo: 'X', ...SIN_ADMIN },
    { estado: 'miembro', perfil_id: 'user-1', rol_crm: 'gerencia', rol_portal: 'directorio', nombre_completo: 'X', ...SIN_ADMIN },
    { estado: 'global', perfil_id: 'user-1', rol_crm: 'gerencia', rol_portal: 'admin', nombre_completo: 'X' },
    { estado: 'global', perfil_id: 'user-1', rol_crm: 'directorio', rol_portal: 'superadmin', nombre_completo: 'X', ...SIN_ADMIN },
    { estado: 'miembro', perfil_id: 'user-1', rol_crm: 'vendedor', rol_portal: null, nombre_completo: 'X' },
    { estado: 'miembro', perfil_id: 'user-1', rol_crm: 'vendedor', rol_portal: 'superadmin', nombre_completo: 'X', ...SIN_ADMIN },
    { estado: 'administrador_roles', perfil_id: 'user-1', rol_crm: 'directorio', rol_portal: 'superadmin', nombre_completo: 'X', ...SIN_ADMIN },
    { estado: 'administrador_roles', perfil_id: 'user-1', rol_portal: 'superadmin', nombre_completo: 'X', ...SIN_ADMIN },
  ])('rechaza un contrato remoto malformado: %j', (respuesta) => {
    expect(() => interpretarMiAcceso(respuesta)).toThrow(TypeError)
  })

  it('acepta una membresía explícita de Directorio', () => {
    expect(interpretarMiAcceso({
      estado: 'miembro',
      perfil_id: 'directorio-1',
      rol_crm: 'directorio',
      rol_portal: 'directorio',
      nombre_completo: 'Auditor',
      ...SIN_ADMIN,
      puede_listar_usuarios: true,
    })).toMatchObject({
      tipo: 'acceso',
      rol: 'directorio',
      capacidadesConfig: {
        puedeListarUsuarios: true,
        puedeAdministrarUsuarios: false,
        puedeOrganizarJerarquia: false,
        puedeAdministrarRoles: false,
      },
    })
  })

  it('suma Gerencia y Superadmin solo cuando ambas autoridades están activas', () => {
    expect(interpretarMiAcceso({
      estado: 'miembro',
      perfil_id: 'gerencia-superadmin',
      rol_crm: 'gerencia',
      rol_portal: 'superadmin',
      nombre_completo: 'GERENCIA SUPERADMIN',
      puede_listar_usuarios: true,
      puede_administrar_usuarios: true,
      puede_organizar_jerarquia: true,
      puede_administrar_roles: true,
    })).toMatchObject({
      tipo: 'acceso',
      rol: 'gerencia',
      rolPortal: 'superadmin',
      puedeContratar: true,
    })
  })

  it('falla cerrado si la sesión cambia durante la resolución', () => {
    expect(() => interpretarMiAccesoParaUsuario({
      estado: 'revocado',
      perfil_id: 'user-b',
    }, 'user-a')).toThrow('La identidad cambió')
  })
})
