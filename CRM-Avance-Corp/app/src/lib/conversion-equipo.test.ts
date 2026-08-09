import { describe, expect, it } from 'vitest'
import { identidadesEquipoConversion } from './conversion-equipo'
import type { Miembro } from './tipos'

// `conversionesEquipo` (el agregador que recorría leads+actividades+tareas en
// cliente) se eliminó en F1b tanda 2 junto con sus tests: no tenía callers y
// su terreno lo sirven metricas_conversiones_fn / metricas_vendedores_fn.

const EQUIPO = [
  { perfil_id: 's1', nombre_completo: 'SUPERVISORA UNO', rol_crm: 'supervisor', activo: true },
  { perfil_id: 'v1', nombre_completo: 'ANA TORRES', rol_crm: 'vendedor', supervisor_id: 's1', activo: true },
  { perfil_id: 'v2', nombre_completo: 'BRUNO DIAZ', rol_crm: 'vendedor', supervisor_id: 's1', activo: true },
] satisfies Miembro[]

describe('identidades del equipo para conversiones', () => {
  it('puede obtener solo identidades sin depender de leads operativos', () => {
    expect(identidadesEquipoConversion(
      EQUIPO.filter((miembro) => miembro.rol_crm === 'vendedor'),
      EQUIPO,
    )).toEqual([
      expect.objectContaining({ vendedorId: 'v1', nombre: 'ANA TORRES', supervisorNombre: 'SUPERVISORA UNO', leads: 0 }),
      expect.objectContaining({ vendedorId: 'v2', nombre: 'BRUNO DIAZ', supervisorNombre: 'SUPERVISORA UNO', leads: 0 }),
    ])
  })
})
