import { describe, expect, it } from 'vitest'
import { conversionesEquipo, identidadesEquipoConversion } from './conversion-equipo'
import type { Actividad, Lead, Miembro, Tarea } from './tipos'

const EQUIPO = [
  { perfil_id: 's1', nombre_completo: 'SUPERVISORA UNO', rol_crm: 'supervisor', activo: true },
  { perfil_id: 'v1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', supervisor_id: 's1', activo: true },
  { perfil_id: 'v2', nombre_completo: 'BRUNO DIAZ', rol_crm: 'vendedor', supervisor_id: 's1', activo: true },
] satisfies Miembro[]

function lead(id: string, cambios: Partial<Lead> = {}): Lead {
  return {
    id,
    nombre_completo: id,
    telefono: '999999999',
    etapa: 'nuevo',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v1',
    creado_en: '2026-08-05T15:00:00Z',
    activo: true,
    ...cambios,
  }
}

describe('conversiones del equipo con datos existentes', () => {
  it('puede obtener solo identidades sin depender de leads operativos', () => {
    expect(identidadesEquipoConversion(
      EQUIPO.filter((miembro) => miembro.rol_crm === 'vendedor'),
      EQUIPO,
    )).toEqual([
      expect.objectContaining({ vendedorId: 'v1', nombre: 'ANA TORRES', supervisorNombre: 'SUPERVISORA UNO', leads: 0 }),
      expect.objectContaining({ vendedorId: 'v2', nombre: 'BRUNO DIAZ', supervisorNombre: 'SUPERVISORA UNO', leads: 0 }),
    ])
  })

  it('solo cuenta como cliente al lead con inversión formalizada', () => {
    const resultado = conversionesEquipo({
      vendedores: EQUIPO.filter((miembro) => miembro.rol_crm === 'vendedor'),
      equipo: EQUIPO,
      leads: [
        lead('invertido', { etapa: 'convertido', contrato_id: 'contrato-1' }),
        lead('solo-perfil', { etapa: 'convertido' }),
        lead('contactado', { etapa: 'contactado' }),
        lead('fuera', { etapa: 'convertido', contrato_id: 'contrato-2', creado_en: '2026-07-01T15:00:00Z' }),
      ],
      actividades: [] as Actividad[],
      tareas: [] as Tarea[],
      desde: '2026-08-01',
      hasta: '2026-08-05',
    })

    expect(resultado[0]).toMatchObject({
      vendedorId: 'v1',
      leads: 3,
      contactados: 3,
      clientes: 1,
      reunionesRealizadas: 0,
      conversionPct: 33.3,
    })
    expect(resultado[1]).toMatchObject({ vendedorId: 'v2', leads: 0, conversionPct: null })
  })

  it('mantiene visibles los leads aún no asignados', () => {
    const resultado = conversionesEquipo({
      vendedores: EQUIPO.filter((miembro) => miembro.rol_crm === 'vendedor'),
      equipo: EQUIPO,
      leads: [lead('sin-dueno', { vendedor_id: null })],
      actividades: [],
      tareas: [],
      desde: '2026-08-01',
      hasta: '2026-08-05',
    })
    expect(resultado.find((fila) => fila.vendedorId === null)).toMatchObject({
      nombre: 'Sin vendedor asignado',
      leads: 1,
    })
  })
})
