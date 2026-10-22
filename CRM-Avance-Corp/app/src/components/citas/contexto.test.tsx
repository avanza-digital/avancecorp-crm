import { describe, expect, it } from 'vitest'
import { renderHook } from '@testing-library/react'
import type { ReactNode } from 'react'
import { ContextoCitas, useDatosCitas, type DatosCitas } from './contexto'
import { controlCitasInicial } from '@/lib/control-citas'

// Los selectores de analista y supervisor beben del mismo roster que la tabla:
// un analista que sólo tiene capital en el mes también se puede elegir.
describe('useDatosCitas', () => {
  it('incorpora al equipo a los analistas que sólo aparecen en el capital del mes, sin pisar nombres con actividad', () => {
    const datos: DatosCitas = {
      citas: [], corte: '2026-09-13T15:00:00Z', depositos: [], depositosDisponibles: false, mesInicial: '2026-09', modoDemo: false, meses: ['2026-09'],
      gestion: {
        citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70,
        asignaciones: [{ id: 'ana', nombre: 'Ana Actividad', supervisor: 'Supervisor', supervisorId: 'sup',
          leadId: 'lead-1', nombreLead: 'Persona uno', telefono: '900000001', asignadoEn: '2026-09-01T14:00:00Z',
          manualPropio: false, registroManual: false, origen: 'Referido', moneda: 'PEN', monto: 2500 }],
        avance: { control: { version: 1, mes_inicio: '2026-09', configuracion: controlCitasInicial() }, poblacion: [], conversiones: [],
          capital: [
            { contrato_id: 'contrato-1', lead_id: null, perfil_id: 'cliente-1', analista_id: 'ana', analista_nombre: 'Ana (capital)', supervisor_id: 'otro', supervisor_nombre: 'Otro', moneda: 'PEN', monto: 1000, fecha: '2026-09-03T05:00:00Z' },
            { contrato_id: 'contrato-2', lead_id: null, perfil_id: 'cliente-2', analista_id: 'luis', analista_nombre: 'Luis Solo Capital', supervisor_id: 'sup2', supervisor_nombre: 'Supervisora Dos', moneda: 'PEN', monto: 4000, fecha: '2026-09-10T05:00:00Z' },
            { contrato_id: null, cierre_externo_id: 'coop-1', lead_id: null, perfil_id: null, analista_id: 'sofia', moneda: 'PEN', monto: 500, fecha: '2026-09-11T05:00:00Z' },
          ] },
      },
    }
    const envoltura = ({ children }: { children: ReactNode }) => <ContextoCitas.Provider value={datos}>{children}</ContextoCitas.Provider>
    const { result } = renderHook(() => useDatosCitas(), { wrapper: envoltura })
    expect(result.current.equipo.map(p => [p.id, p.nombre, p.supervisorId])).toEqual([
      ['ana', 'Ana Actividad', 'sup'], ['luis', 'Luis Solo Capital', 'sup2'], ['sofia', 'Sin analista', 'sin_supervisor'],
    ])
    expect(result.current.nombreAnalista('luis')).toBe('Luis Solo Capital')
  })
})

// D-53 (bloque 2.14): el roster lleva el estado de hoy de cada analista, venga de la lista que venga; una fuente sin la
// clave (p. ej. el modo demo) no borra el estado que trajo otra.
describe('useDatosCitas · estado del analista (D-53)', () => {
  const envoltura = (datos: DatosCitas) => ({ children }: { children: ReactNode }) => <ContextoCitas.Provider value={datos}>{children}</ContextoCitas.Provider>
  const base: DatosCitas = { citas: [], corte: '2026-09-13T15:00:00Z', depositos: [], depositosDisponibles: false, mesInicial: '2026-09', modoDemo: false, meses: ['2026-09'] }
  const cita = (analista: string, analistaNombre: string, analistaEstado?: 'activo' | 'de_baja' | 'suspendido') => ({
    id: `c-${analista}`, leadId: `l-${analista}`, nombre: 'Persona', telefono: '900000000', analista, analistaNombre, supervisor: 'Supervisora', supervisorId: 'sup',
    fecha: '2026-09-04', hora: '09:00', estado: 'realizada' as const, modalidad: 'Virtual', origen: 'Referido', moneda: 'PEN' as const, monto: 1000,
    resultado: 'Interesado', cerrado: false, seguimiento: false, nuevaFecha: null, nota: '', ...(analistaEstado ? { analistaEstado } : {}),
  })
  it('estadoAnalista: de las citas, de las asignaciones y del capital; «activo» si nadie lo trae', () => {
    const datos: DatosCitas = { ...base,
      citas: [cita('ana', 'Ana', 'de_baja'), cita('cata', 'Cata', 'activo'), cita('dani', 'Dani')],
      gestion: { citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70,
        asignaciones: [{ id: 'beto', nombre: 'Beto', supervisor: 'Supervisora', supervisorId: 'sup', estado: 'suspendido',
          leadId: 'l-beto', nombreLead: 'Persona', telefono: '900000001', asignadoEn: '2026-09-01T14:00:00Z', manualPropio: false, registroManual: false, origen: 'Referido', moneda: 'PEN', monto: 2500 }],
        avance: { control: { version: 1, mes_inicio: '2026-09', configuracion: controlCitasInicial() }, poblacion: [], conversiones: [],
          capital: [{ contrato_id: 'k-1', lead_id: null, perfil_id: 'cli-1', analista_id: 'luis', analista_nombre: 'Luis', analista_estado: 'de_baja', supervisor_id: 'sup', supervisor_nombre: 'Supervisora', moneda: 'PEN', monto: 1000, fecha: '2026-09-03T05:00:00Z' }] },
      },
    }
    const { result } = renderHook(() => useDatosCitas(), { wrapper: envoltura(datos) })
    expect(result.current.estadoAnalista('ana')).toBe('de_baja')
    expect(result.current.estadoAnalista('beto')).toBe('suspendido')
    expect(result.current.estadoAnalista('luis')).toBe('de_baja')
    expect(result.current.estadoAnalista('cata')).toBe('activo')
    expect(result.current.estadoAnalista('dani')).toBe('activo')
    expect(result.current.estadoAnalista('nadie')).toBe('activo')
    expect(result.current.equipo.find(p => p.id === 'ana')?.estado).toBe('de_baja')
  })
  it('una fuente posterior sin la clave no borra el estado que trajo otra', () => {
    const datos: DatosCitas = { ...base,
      citas: [cita('luis', 'Luis')],
      gestion: { citasPorLead: 1.25, entrevistasPorcentaje: 70, depositosPorcentaje: 70, asignaciones: [],
        avance: { control: { version: 1, mes_inicio: '2026-09', configuracion: controlCitasInicial() }, poblacion: [], conversiones: [],
          capital: [{ contrato_id: 'k-1', lead_id: null, perfil_id: 'cli-1', analista_id: 'luis', analista_nombre: 'Luis', analista_estado: 'suspendido', supervisor_id: 'sup', supervisor_nombre: 'Supervisora', moneda: 'PEN', monto: 1000, fecha: '2026-09-03T05:00:00Z' }] },
      },
    }
    const { result } = renderHook(() => useDatosCitas(), { wrapper: envoltura(datos) })
    expect(result.current.estadoAnalista('luis')).toBe('suspendido')
    expect(result.current.nombreAnalista('luis')).toBe('Luis')
  })
})
