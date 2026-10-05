import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as v from 'valibot'
const mocks = vi.hoisted(() => ({ rpc:vi.fn(), schema:vi.fn(), abortSignal:vi.fn() }))
vi.mock('@/lib/supabase',() => ({sb:{schema:mocks.schema}}))
import { adaptarCitas, adaptarDepositos, adaptarGestion, cargarCitasGerencia, ConsultaCitasSchema, type ConsultaCitasRpc } from './citas-gerencia'
import { csv, defaults, filtrar } from '@/components/citas/modelo'
import { depositosDeInasistencias } from '@/components/citas/depositos'
import { baseCitasFiltrada, metaCitas } from '@/components/citas/metas'
import { GestionMensualCitasSchema } from '@/lib/gestion-citas'
import { controlCitasInicial } from '@/lib/control-citas'

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
  it('valida gestión mensual y capital por perfil aunque el lead no enlace un contrato', async () => {
    const datos = respuestaConversion()
    datos.citas = datos.citas.map(c => ({ ...c, manual_propio: false, registro_manual: false }))
    datos.gestion = { version: 2, citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70,
      actividad_manuales: 'incluir', asignaciones: [],
      control: { version: 0, mes_inicio: null, configuracion: controlCitasInicial() },
      poblacion: [{ lead_id: id(10), nombre: 'Persona', telefono: '900000001', origen: 'referido', moneda: 'PEN', monto_estimado: 5000,
        registro_manual: false, creado_por: id(20), analista_origen_id: id(20), analista_origen_nombre: 'Analista',
        supervisor_origen_id: id(30), supervisor_origen_nombre: 'Supervisor', primera_asignacion_en: '2026-09-01T05:00:00Z' }],
      conversiones: [{ lead_id: id(10), perfil_id: id(40), convertido_en: '2026-09-04T15:00:00Z', analista_id: id(20), analista_nombre: 'Analista',
        supervisor_id: id(30), supervisor_nombre: 'Supervisor', contrato_id: null }],
      capital: [{ contrato_id: id(70), lead_id: id(10), perfil_id: id(40), analista_id: id(20), moneda: 'USD', monto: 1000, fecha: '2026-09-04T05:00:00Z' }],
    }
    mocks.rpc.mockResolvedValue({ data: datos, error: null })
    expect(adaptarGestion(await cargarCitasGerencia('2026-09'))?.avance?.capital[0]?.moneda).toBe('USD')
    // Todo el capital del mes: un upgrade de un cliente sin lead y un cierre en
    // cooperativa sin perfil también pasan la frontera.
    const completo = structuredClone(datos)
    ;(completo.gestion as typeof datos.gestion).capital.push(
      { contrato_id: id(71), cierre_externo_id: null, tipo: 'contrato_upgrade', lead_id: null, perfil_id: id(41), identidad_persona: `perfil:${id(41)}`,
        analista_id: id(21), analista_nombre: 'Otra analista', supervisor_id: id(30), supervisor_nombre: 'Supervisor', moneda: 'PEN', monto: 20000, fecha: '2026-09-02T05:00:00Z' },
      { contrato_id: null, cierre_externo_id: id(72), tipo: 'cooperativa', lead_id: id(10), perfil_id: null, identidad_persona: `lead:${id(10)}`,
        analista_id: id(20), moneda: 'PEN', monto: 5000, fecha: '2026-09-03T05:00:00Z' })
    mocks.rpc.mockResolvedValue({ data: completo, error: null })
    expect(adaptarGestion(await cargarCitasGerencia('2026-09'))?.avance?.capital).toHaveLength(3)
    for (const defecto of ['capital_duplicado', 'capital_sin_clave', 'capital_doble_clave', 'capital_tipo_desconocido', 'cliente_ajeno', 'otro_mes', 'meta_distinta', 'poblacion_incompleta']) {
      const rota = structuredClone(datos)
      const g = rota.gestion as typeof datos.gestion
      if (defecto === 'capital_duplicado') g.capital.push(g.capital[0]!)
      if (defecto === 'capital_sin_clave') g.capital.push({ ...g.capital[0]!, contrato_id: null, cierre_externo_id: null })
      if (defecto === 'capital_doble_clave') g.capital.push({ ...g.capital[0]!, contrato_id: id(73), cierre_externo_id: id(74) })
      if (defecto === 'capital_tipo_desconocido') g.capital.push({ ...g.capital[0]!, contrato_id: id(75), tipo: 'desglose_renovado' as 'cooperativa' })
      if (defecto === 'cliente_ajeno') g.capital[0]!.perfil_id = id(99)
      if (defecto === 'otro_mes') g.capital[0]!.fecha = '2026-08-31T05:00:00Z'
      if (defecto === 'meta_distinta') g.citas_por_lead = 3
      if (defecto === 'poblacion_incompleta') g.poblacion = []
      mocks.rpc.mockResolvedValue({ data: rota, error: null })
      // Un tipo fuera del contrato lo rechaza el esquema; el resto, la frontera de gestión.
      await expect(cargarCitasGerencia('2026-09')).rejects.toThrow(defecto === 'capital_tipo_desconocido' ? 'incompleta' : 'fuentes de gestión')
    }
  })
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
  it('no reconstruye una meta a partir de citas sin la base asignada',() => {
    const datos = respuesta()
    datos.citas.push(fila({id:id(2),analista_id:id(21),analista_nombre:'Otra analista'}),fila({id:id(3)}))
    expect(metaCitas(adaptarCitas(datos))).toMatchObject({citas:null,leads:null,promedio:null,cumplimiento:null})
  })
  it('conecta la base del servidor incluyendo asignados sin cita y su meta interna',async () => {
    const datos=respuestaConversion()
    datos.citas=datos.citas.map(c=>({...c,manual_propio:false}))
    datos.gestion={version:1,citas_por_lead:1.25,entrevistas_porcentaje:70,depositos_porcentaje:70,
      asignaciones:[10,11].map(n=>({lead_id:id(n),analista_id:id(20),analista_nombre:'Analista de prueba',
        supervisor_id:id(30),supervisor_nombre:'Supervisor de prueba',asignado_en:'2026-09-01T05:00:00Z',
        manual_propio:false,nombre:'Persona de prueba',telefono:'900000001',origen:'referido',moneda:'PEN',monto_estimado:5000}))}
    mocks.rpc.mockResolvedValue({data:datos,error:null})
    const lectura=await cargarCitasGerencia('2026-09')
    const g=adaptarGestion(lectura)!
    expect(g).toMatchObject({citasPorLead:1.25,entrevistasPorcentaje:70,depositosPorcentaje:70})
    expect(g.asignaciones).toHaveLength(2)
    expect(metaCitas(adaptarCitas(lectura),g.asignaciones,g.citasPorLead)).toMatchObject({citas:2,leads:2,cumplimiento:80})
    for (const defecto of ['duplicada','fuera_mes','sin_origen_manual'] as const) {
      const rota=structuredClone(datos)
      if(defecto==='duplicada') rota.gestion!.asignaciones.push(rota.gestion!.asignaciones[0]!)
      if(defecto==='fuera_mes') rota.gestion!.asignaciones[0]!.asignado_en='2026-09-01T04:59:00Z'
      if(defecto==='sin_origen_manual') Reflect.deleteProperty(rota.citas[0]!,'manual_propio')
      mocks.rpc.mockResolvedValue({data:rota,error:null})
      await expect(cargarCitasGerencia('2026-09')).rejects.toThrow('base de leads asignados')
    }
  })
  it('acepta un mes vacío y rechaza importes no finitos',() => {
    expect(v.safeParse(ConsultaCitasSchema,{...respuesta(),citas:[]}).success).toBe(true)
    expect(v.safeParse(ConsultaCitasSchema,{...respuesta(),citas:[fila({monto_estimado:Infinity})]}).success).toBe(false)
  })
  it('usa el estado canónico del servidor y conserva compatibilidad con el contrato anterior',() => {
    const datos={...respuesta(),citas:[fila({estado:'pendiente',estado_comercial:'programada'})]}
    expect(adaptarCitas(datos)[0]!.estado).toBe('programada')
    Reflect.deleteProperty(datos.citas[0]!,'estado_comercial')
    expect(adaptarCitas(datos)[0]!.estado).toBe('vencida')
    expect(v.safeParse(ConsultaCitasSchema,{...datos,citas:[{...datos.citas[0],estado_comercial:'inventado'}]}).success).toBe(false)
    // Ausente permite un servidor anterior; null es una respuesta canónica
    // incompleta y debe fallar, igual que cualquier estado desconocido.
    expect(v.safeParse(ConsultaCitasSchema,{...datos,citas:[{...datos.citas[0],estado_comercial:null}]}).success).toBe(false)
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

// F5a «Bases cargadas»: el contrato de Citas se valida ENTERO (hasta 10 000 filas). Un lead de base sin capital
// (null, E8) en una cita, una asignación o la población del mes no puede apagar el módulo: se lee, se muestra
// «Sin capital», un filtro de monto lo excluye y el CSV deja la celda vacía.
describe('F5a · capital vacío del lead en Citas', () => {
  it('cita y asignación con capital null pasan la frontera y llegan como null, no como 0', async () => {
    const datos = respuestaConversion()
    datos.citas = datos.citas.map(c => ({ ...c, manual_propio: false, origen: 'base_cargada', monto_estimado: null }))
    datos.gestion = { version: 1, citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70,
      asignaciones: [{ lead_id: id(10), analista_id: id(20), analista_nombre: 'Analista de prueba', supervisor_id: id(30),
        supervisor_nombre: 'Supervisor de prueba', asignado_en: '2026-09-01T05:00:00Z', manual_propio: false,
        nombre: 'Persona de prueba', telefono: '900000001', origen: 'base_cargada', moneda: 'PEN', monto_estimado: null }] }
    mocks.rpc.mockResolvedValue({ data: datos, error: null })
    const lectura = await cargarCitasGerencia('2026-09')
    const citas = adaptarCitas(lectura)
    expect(citas.every(c => c.monto === null && c.origen === 'Base cargada')).toBe(true)
    expect(adaptarGestion(lectura)?.asignaciones[0]).toMatchObject({ monto: null, origen: 'Base cargada' })
  })

  it('la población del avance mensual acepta el capital null', () => {
    const r = v.safeParse(GestionMensualCitasSchema, {
      control: { version: 0, mes_inicio: null, configuracion: controlCitasInicial() },
      poblacion: [{ lead_id: id(10), nombre: 'Persona', telefono: '900000001', origen: 'base_cargada', moneda: 'PEN', monto_estimado: null,
        registro_manual: false, creado_por: null, analista_origen_id: id(20), analista_origen_nombre: 'Analista',
        supervisor_origen_id: id(30), supervisor_origen_nombre: 'Supervisor', primera_asignacion_en: '2026-09-01T05:00:00Z' }],
      conversiones: [], capital: [],
    })
    expect(r.success).toBe(true)
  })

  it('un filtro de monto excluye al lead sin capital y el CSV deja vacía su celda', () => {
    const conCapital = adaptarCitas({ ...respuesta(), citas: [fila({ moneda: 'PEN', monto_estimado: 5000 })] })[0]!
    const sinCapital = { ...conCapital, id: 'sin', monto: null }
    const f = { ...defaults('2026-09'), moneda: 'PEN', min: '0' }
    expect(filtrar(f, [conCapital, sinCapital]).map(c => c.id)).toEqual([conCapital.id])
    expect(filtrar({ ...defaults('2026-09'), moneda: 'PEN' }, [conCapital, sinCapital])).toHaveLength(2)
    const base = adaptarGestion({ ...respuesta(), gestion: { version: 1, citas_por_lead: 1, entrevistas_porcentaje: 70, depositos_porcentaje: 70,
      asignaciones: [{ lead_id: id(10), analista_id: id(20), analista_nombre: 'A', supervisor_id: null, supervisor_nombre: 'S',
        asignado_en: '2026-09-01T05:00:00Z', manual_propio: false, nombre: 'P', telefono: '900000001', origen: 'landing', moneda: 'PEN', monto_estimado: null }] } })!
    expect(baseCitasFiltrada(base.asignaciones, f)).toEqual([])
    const ultimaFila = csv([sinCapital]).split('\r\n').at(-1)!
    expect(ultimaFila.endsWith('"","PEN"')).toBe(true)
  })

  it('ESTADO DE PRODUCCIÓN: con capital numérico todo sigue igual (filtro y CSV)', () => {
    const cita = adaptarCitas({ ...respuesta(), citas: [fila({ moneda: 'PEN', monto_estimado: 5000 })] })[0]!
    expect(cita.monto).toBe(5000)
    expect(filtrar({ ...defaults('2026-09'), moneda: 'PEN', min: '1000', max: '6000' }, [cita])).toHaveLength(1)
    expect(csv([cita]).split('\r\n').at(-1)!.endsWith('"5000","PEN"')).toBe(true)
  })
})
