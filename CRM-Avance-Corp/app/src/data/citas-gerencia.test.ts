import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
const mocks = vi.hoisted(() => ({ rpc:vi.fn(), schema:vi.fn(), abortSignal:vi.fn() }))
vi.mock('@/lib/supabase',() => ({sb:{schema:mocks.schema}}))
import { adaptarCitas, adaptarDepositos, cargarCitasGerencia, ConsultaCitasSchema, type ConsultaCitasRpc } from './citas-gerencia'
import { defaults, filtrar } from '@/components/citas/modelo'
import { depositosDeInasistencias } from '@/components/citas/depositos'
import { metaCitas } from '@/components/citas/metas'

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`
const fila = (cambios: Partial<ConsultaCitasRpc['citas'][number]> = {}): ConsultaCitasRpc['citas'][number] => ({
  id:id(1),lead_id:id(10),nombre:'Prospecto de prueba',telefono:'+51900000001',analista_id:id(20),analista_nombre:'Analista de prueba',supervisor_id:id(30),supervisor_nombre:'Supervisor de prueba',
  vence_en:'2026-09-01T23:00:00Z',estado:'no_show',cancelada_por:null,modalidad:'virtual',origen:'referido',moneda:'USD',monto_estimado:5000,resultado:'sin_clasificar',nota:'',reagendada_de:null,creado_en:'2026-08-31T16:00:00Z',asistencia_registrada_en:null,cierre_posterior:false,...cambios,
})
const respuesta = (): Extract<ConsultaCitasRpc,{version:1}> => ({version:1,periodo:{desde:'2026-09-01',hasta:'2026-09-30'},generado_en:'2026-09-08T18:00:00Z',citas:[fila()],disponibilidad_depositos:'sin_registro',depositos:[],citas_clientes:0})
const respuestaConversion = (): Extract<ConsultaCitasRpc,{version:2}> => {
  const {depositos:_depositos,...base}=respuesta()
  return {...base,version:2,disponibilidad_depositos:'conversion_cliente',
    citas:[fila(),fila({id:id(2),estado:'completada',reagendada_de:id(1),creado_en:'2026-09-02T16:00:00Z',vence_en:'2026-09-03T16:00:00Z',asistencia_registrada_en:'2026-09-03T17:00:00Z'})],
    conversiones:[{lead_id:id(10),perfil_id:id(40),convertido_en:'2026-09-04T15:00:00Z'}]}
}
beforeEach(() => {
  vi.clearAllMocks()
  mocks.schema.mockReturnValue({rpc:mocks.rpc})
  mocks.rpc.mockImplementation(() => ({then:(resolver: (r: unknown) => unknown) => Promise.resolve({data:respuesta(),error:null}).then(resolver),abortSignal:mocks.abortSignal}))
})

describe('frontera de la consulta detallada de Citas',() => {
  it('consulta el mes completo, incluye futuras citas y propaga cancelación',async () => {
    const control = new AbortController()
    const r = await cargarCitasGerencia('2026-09',control.signal)
    expect(r.citas).toHaveLength(1)
    expect(mocks.schema).toHaveBeenCalledWith('crm')
    expect(mocks.rpc).toHaveBeenCalledWith('citas_gerencia_consulta_fn',{p_desde:'2026-09-01',p_hasta:'2026-09-30'})
    expect(mocks.abortSignal).toHaveBeenCalledWith(control.signal)
  })
  it('rechaza meses inválidos antes de llamar al servidor',async () => {
    await expect(cargarCitasGerencia('2026-13')).rejects.toThrow('mes válido')
    expect(mocks.rpc).not.toHaveBeenCalled()
  })
  it.each(['periodo','duplicada','deposito','incompleta'] as const)('rechaza una respuesta %s sin convertirla en vacío',async defecto => {
    const datos = respuesta()
    if (defecto==='periodo') datos.periodo.desde='2026-08-01'
    if (defecto==='duplicada') datos.citas.push(datos.citas[0]!)
    if (defecto==='deposito') datos.depositos.push({monto:5000})
    if (defecto==='incompleta') Reflect.deleteProperty(datos,'citas')
    mocks.rpc.mockResolvedValue({data:datos,error:null})
    await expect(cargarCitasGerencia('2026-09')).rejects.toThrow('respuesta de citas')
  })
  it('explica una migración ausente sin exponer detalles del servidor',async () => {
    mocks.rpc.mockResolvedValue({data:null,error:{code:'PGRST202',message:'internal database details'}})
    await expect(cargarCitasGerencia('2026-09')).rejects.toThrow('aún no está habilitada')
  })
  it('convierte fecha y nueva fecha en Lima, usa corte del servidor y mantiene ausencia de evidencia',() => {
    const datos = respuesta()
    datos.citas.push(fila({id:id(2),estado:'completada',reagendada_de:id(1),creado_en:'2026-09-02T00:00:00Z',vence_en:'2026-09-08T02:00:00Z',cierre_posterior:true}))
    const citas = adaptarCitas(datos)
    expect(citas[0]!.nuevaFecha).toBe('2026-09-07')
    expect(citas[1]!.hora).toBe('21:00')
    expect(citas[1]!.asistioEn).toBeUndefined()
    const flujo = depositosDeInasistencias(citas,[],datos.generado_en,citas)
    expect(flujo.reprogramadas).toHaveLength(1)
    expect(flujo.recuperadas).toHaveLength(0)
    expect(flujo.convertidos).toBe(0)
    expect(datos.disponibilidad_depositos).toBe('sin_registro')
  })
  it('cuenta asistencia registrada y seguimiento fuera de semana sin sumar otra persona',() => {
    const datos = respuesta()
    datos.citas.push(fila({id:id(2),estado:'completada',reagendada_de:id(1),creado_en:'2026-09-02T00:00:00Z',vence_en:'2026-09-08T15:00:00Z',asistencia_registrada_en:'2026-09-08T16:00:00Z'}))
    const citas = adaptarCitas(datos)
    const cohorte = filtrar({...defaults('2026-09'),semana:'1'},citas)
    expect(cohorte).toHaveLength(1)
    expect(depositosDeInasistencias(cohorte,[],datos.generado_en,citas).recuperadas).toHaveLength(1)
  })
  it('no promedia promedios ni suma leads compartidos al calcular la meta',() => {
    const datos = respuesta()
    datos.citas.push(fila({id:id(2),analista_id:id(21),analista_nombre:'Otra analista'}),fila({id:id(3)}))
    expect(metaCitas(adaptarCitas(datos))).toMatchObject({citas:3,leads:1,promedio:3,cumplimiento:100,leadsConMeta:1})
  })
  it('acepta un mes vacío y rechaza importes no finitos',() => {
    expect(v.safeParse(ConsultaCitasSchema,{...respuesta(),citas:[]}).success).toBe(true)
    expect(v.safeParse(ConsultaCitasSchema,{...respuesta(),citas:[fila({monto_estimado:Infinity})]}).success).toBe(false)
  })
  it('acepta el formato ISO de PostgreSQL y conserva el cierre histórico sin inferir depósito',() => {
    const datos={...respuesta(),citas:[fila({estado:'completada',vence_en:'2026-08-15T16:00:00+00:00',cierre_posterior:true})]}
    expect(v.safeParse(ConsultaCitasSchema,datos).success).toBe(true)
    expect(adaptarCitas(datos)[0]).toMatchObject({fecha:'2026-08-15',hora:'11:00',cerrado:true,seguimiento:false})
    expect(datos.disponibilidad_depositos).toBe('sin_registro')
  })
  it('acepta 10000 filas y rechaza 10001 en la frontera',() => {
    const citas=Array.from({length:10000},(_,n)=>fila({id:id(n+1)}))
    expect(v.safeParse(ConsultaCitasSchema,{...respuesta(),citas}).success).toBe(true)
    expect(v.safeParse(ConsultaCitasSchema,{...respuesta(),citas:[...citas,fila({id:id(10001)})]}).success).toBe(false)
  })
  it('la conversión a cliente completa el flujo una vez y no inventa un importe',async () => {
    mocks.rpc.mockResolvedValue({data:respuestaConversion(),error:null})
    const datos=await cargarCitasGerencia('2026-09')
    const citas=adaptarCitas(datos), depositos=adaptarDepositos(datos)
    const flujo=depositosDeInasistencias(citas,depositos,datos.generado_en,citas)
    expect(depositos[0]).toMatchObject({fuente:'conversion_cliente',monto:null,moneda:null,depositadoEn:'2026-09-04T15:00:00Z'})
    expect(flujo).toMatchObject({base:1,convertidos:1,porcentaje:100,montos:{PEN:0,USD:0}})
  })
  it.each(['duplicada','otra_persona','futura','sin_cliente'] as const)('rechaza conversión %s sin dibujar un cero',async defecto => {
    const datos=respuestaConversion()
    if(defecto==='duplicada') datos.conversiones.push(datos.conversiones[0]!)
    if(defecto==='otra_persona') datos.conversiones[0]!.lead_id=id(99)
    if(defecto==='futura') datos.conversiones[0]!.convertido_en='2026-10-01T15:00:00Z'
    if(defecto==='sin_cliente') Reflect.deleteProperty(datos.conversiones[0]!,'perfil_id')
    mocks.rpc.mockResolvedValue({data:datos,error:null})
    await expect(cargarCitasGerencia('2026-09')).rejects.toThrow('respuesta')
  })
  it('convertirse antes de asistir no completa la última etapa de esta recuperación',() => {
    const datos=respuestaConversion()
    datos.conversiones[0]!.convertido_en='2026-09-02T15:00:00Z'
    const citas=adaptarCitas(datos)
    expect(depositosDeInasistencias(citas,adaptarDepositos(datos),datos.generado_en,citas).convertidos).toBe(0)
    datos.conversiones[0]!.convertido_en='2026-09-04T15:00:00Z'
    const sinAsistencia=citas.map(c=>{ const {asistioEn:_asistencia,...resto}=c; return resto })
    expect(depositosDeInasistencias(sinAsistencia,adaptarDepositos(datos),datos.generado_en,sinAsistencia).convertidos).toBe(0)
  })
})
