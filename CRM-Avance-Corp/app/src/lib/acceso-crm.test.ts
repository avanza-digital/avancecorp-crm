import { describe, expect, it } from 'vitest'
import { interpretarMiAcceso, interpretarMiAccesoParaUsuario } from './acceso-crm'

describe('interpretarMiAcceso', () => {
  it('acepta una membresía activa y conserva la capacidad del portal', () => {
    expect(interpretarMiAcceso({
      estado: 'miembro',
      perfil_id: 'user-1',
      rol_crm: 'vendedor',
      rol_portal: 'analista',
      nombre_completo: 'Ana Asesora',
    })).toEqual({
      tipo: 'acceso',
      perfilId: 'user-1',
      rol: 'vendedor',
      nombre: 'Ana Asesora',
      puedeContratar: true,
    })
  })

  it('acepta el fallback global solo como Directorio', () => {
    expect(interpretarMiAcceso({
      estado: 'global',
      perfil_id: 'user-2',
      rol_crm: 'directorio',
      rol_portal: 'superadmin',
      nombre_completo: null,
    })).toEqual({
      tipo: 'acceso',
      perfilId: 'user-2',
      rol: 'directorio',
      nombre: '',
      puedeContratar: true,
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
    { estado: 'miembro', perfil_id: 'user-1', rol_crm: 'directorio', rol_portal: 'admin', nombre_completo: 'X' },
    { estado: 'global', perfil_id: 'user-1', rol_crm: 'gerencia', rol_portal: 'admin', nombre_completo: 'X' },
    { estado: 'miembro', perfil_id: 'user-1', rol_crm: 'vendedor', rol_portal: null, nombre_completo: 'X' },
  ])('rechaza un contrato remoto malformado: %j', (respuesta) => {
    expect(() => interpretarMiAcceso(respuesta)).toThrow(TypeError)
  })

  it('falla cerrado si la sesión cambia durante la resolución', () => {
    expect(() => interpretarMiAccesoParaUsuario({
      estado: 'revocado',
      perfil_id: 'user-b',
    }, 'user-a')).toThrow('La identidad cambió')
  })
})
