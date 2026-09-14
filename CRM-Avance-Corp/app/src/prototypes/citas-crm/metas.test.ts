import { describe, expect, it } from 'vitest'
import { CITAS_CRM } from './datos'
import { metaCitas, baseCitasFiltrada, type LeadBaseCitas } from './metas'
import { defaults } from '@/components/citas/modelo'

const lead = (n: number, cambios: Partial<LeadBaseCitas> = {}): LeadBaseCitas => ({
  leadId:`lead-${n}`,id:'ana',nombre:'Ana',supervisor:'Supervisor',supervisorId:'sup',
  nombreLead:`Persona ${n}`,telefono:'900000001',asignadoEn:'2026-09-01T15:00:00Z',
  manualPropio:false,origen:'Referido',moneda:'PEN',monto:5000,...cambios,
})
const citas = (cantidad: number) => Array.from({length:cantidad},(_,n)=>({
  ...CITAS_CRM[0]!,id:`cita-${n}`,leadId:`lead-${n % 4}`,manualPropio:false,
}))

describe('meta interna de 1,25 citas sobre leads asignados', () => {
  it('100 citas entre 80 asignados alcanza 100%, aunque sólo cuatro tengan citas', () => {
    const base = Array.from({length:100},(_,n)=>lead(n,{manualPropio:n>=80}))
    expect(metaCitas(citas(100),base)).toMatchObject({citas:100,leads:80,promedio:1.25,cumplimiento:100})
    expect(metaCitas(citas(125),base).cumplimiento).toBe(125)
  })
  it('conserva leads sin citas y distingue cero de base no disponible', () => {
    expect(metaCitas([], [lead(1)])).toMatchObject({citas:0,leads:1,promedio:0,cumplimiento:0})
    expect(metaCitas([], [])).toMatchObject({citas:0,leads:0,promedio:null,cumplimiento:null})
    expect(metaCitas(citas(10))).toMatchObject({citas:null,leads:null,promedio:null,cumplimiento:null})
  })
  it('recalcula el total con personas únicas y no promedia promedios', () => {
    const base=[lead(1),lead(1,{id:'otro'}),lead(2)]
    expect(metaCitas(citas(4),base)).toMatchObject({leads:2,promedio:2,cumplimiento:160})
    expect(metaCitas(citas(3),[lead(1),lead(2),lead(3)]).cumplimiento).toBe(80)
  })
  it('no decide el aporte de manuales si falta la regla; soporta ambas elecciones', () => {
    const actividad=[...citas(1),{...citas(1)[0]!,id:'manual',manualPropio:true}]
    expect(metaCitas(actividad,[lead(1)]).cumplimiento).toBeNull()
    expect(metaCitas(actividad,[lead(1)],1.25,'excluir').cumplimiento).toBe(80)
    expect(metaCitas(actividad,[lead(1)],1.25,'incluir').cumplimiento).toBe(160)
    const sinEvidencia={...citas(1)[0]!}; Reflect.deleteProperty(sinEvidencia,'manualPropio')
    expect(metaCitas([sinEvidencia],[lead(1)]).cumplimiento).toBeNull()
  })
  it('lee la meta recibida del servidor y calcula antes de redondear', () => {
    expect(metaCitas(citas(4),[lead(1),lead(2),lead(3)],1.5).cumplimiento).toBeCloseTo(88.8888889)
    expect(metaCitas(citas(4),[lead(1)],0).cumplimiento).toBeNull()
  })
  it('la semana y el estado no eliminan asignados sin citas; persona y responsable sí filtran', () => {
    const base=[lead(1),lead(2,{id:'otro',moneda:'USD'})]
    const filtros={...defaults('2026-09'),semana:'4',estados:['realizada' as const]}
    expect(baseCitasFiltrada(base,filtros)).toHaveLength(2)
    expect(baseCitasFiltrada(base,{...filtros,analista:'ana'})).toEqual([base[0]])
    expect(baseCitasFiltrada(base,{...filtros,q:'Persona 2'})).toEqual([base[1]])
    expect(baseCitasFiltrada(base,{...filtros,moneda:'PEN',min:'5001'})).toEqual([])
  })
})
