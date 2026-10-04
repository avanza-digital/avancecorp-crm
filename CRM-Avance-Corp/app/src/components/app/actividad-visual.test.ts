// El icono de una actividad concreta: los eventos que el servidor guarda como `nota`
// (reactivación desde la base, «No contactar») no se ven como una nota cualquiera.
import { describe, expect, it } from 'vitest'
import { ArchiveRestore, Ban, PhoneMissed, StickyNote } from 'lucide-react'
import { iconoActividad, ICONO_ACTIVIDAD } from './actividad-visual'

describe('iconoActividad', () => {
  it('la reactivación desde la base lleva su propio icono', () => {
    expect(iconoActividad({ tipo: 'nota', metadata: { evento: 'reactivacion_base', via: 'base_gestion' } })).toBe(ArchiveRestore)
  })

  it('«No contactar», al marcarlo y al levantarlo, lleva el icono de prohibido', () => {
    expect(iconoActividad({ tipo: 'nota', metadata: { evento: 'no_contactar', accion: 'marcar' } })).toBe(Ban)
    expect(iconoActividad({ tipo: 'nota', metadata: { evento: 'no_contactar', accion: 'levantar' } })).toBe(Ban)
  })

  it('sin evento conocido (o sin metadata) usa el icono de su tipo', () => {
    expect(iconoActividad({ tipo: 'nota' })).toBe(StickyNote)
    expect(iconoActividad({ tipo: 'nota', metadata: {} })).toBe(StickyNote)
    expect(iconoActividad({ tipo: 'llamada_no_contestada', metadata: { evento: 'intento_base', intento_n: 1 } })).toBe(PhoneMissed)
    expect(iconoActividad({ tipo: 'conversion', metadata: { evento: 'otro_nuevo' } })).toBe(ICONO_ACTIVIDAD.conversion)
  })
})
