// DEMO_YO (auth.tsx) mantiene LITERALES los ids de EQUIPO_DEMO a propósito:
// importar demo.ts en auth metería el chunk de fixtures en el bundle de
// producción. Este test es el contrato que impide que diverjan en silencio
// (si un id demo cambia, el ámbito jerárquico del store se rompería sin error
// de compilación — hallazgo Media de la auditoría 2026-07-10).
import { describe, expect, it } from 'vitest'
import { DEMO_YO } from './auth-demo'
import { EQUIPO_DEMO } from './demo'

describe('sincronía DEMO_YO ↔ EQUIPO_DEMO', () => {
  it.each(['vendedor', 'supervisor', 'gerencia'] as const)(
    'la identidad demo de %s existe en EQUIPO_DEMO con el mismo nombre y rol',
    (rol) => {
      const identidad = DEMO_YO[rol]
      const miembro = EQUIPO_DEMO.find((m) => m.perfil_id === identidad.id)
      expect(miembro, `EQUIPO_DEMO no tiene un miembro con id ${identidad.id}`).toBeDefined()
      expect(miembro?.nombre_completo).toBe(identidad.nombre_completo)
      expect(miembro?.rol_crm).toBe(rol)
      expect(miembro?.activo).toBe(true)
    },
  )

  it('directorio queda FUERA del organigrama (id sintético, como en producción)', () => {
    const idsEquipo = new Set(EQUIPO_DEMO.map((m) => m.perfil_id))
    expect(idsEquipo.has(DEMO_YO.directorio.id)).toBe(false)
  })

  it('coordinador también queda FUERA del organigrama (C1: off-roster)', () => {
    // Reparte la cola global sin cartera ni jerarquía: no es fila del roster.
    // Si alguien lo añadiera a EQUIPO_DEMO, el ámbito del store lo trataría
    // como vendedor y contradiría Miembro.rol_crm (Exclude<...>).
    const idsEquipo = new Set(EQUIPO_DEMO.map((m) => m.perfil_id))
    expect(idsEquipo.has(DEMO_YO.coordinador.id)).toBe(false)
  })
})
