import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest'
import {act,cleanup,fireEvent,render,screen,waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {QueryClient,QueryClientProvider} from '@tanstack/react-query'
import {GestionInversionistaDialogo} from './gestion-inversionista-dialogo'
import {leerEnvioPostventa} from '@/lib/postventa-envios'
import {ACTOR_F5 as actor,PERSONA_F5 as persona,FUENTE_F5 as fuente} from '@/test/fixtures/f5'
import type {GestionInversionista} from '@/data/gestion-inversionista'
const mock=vi.hoisted(()=>({rpc:vi.fn(),sesion:vi.fn()}))
vi.mock('@/lib/supabase',()=>({sb:{schema:()=>({rpc:(...args:unknown[])=>{
  const promesa=Promise.resolve(mock.rpc(...args));return Object.assign(promesa,{abortSignal:()=>promesa})
}}),auth:{getSession:mock.sesion}}}))
vi.mock('@/lib/auth-context',()=>({useAuth:()=>({yo:{id:actor,rol:'gerencia',rol_portal:'comercial'}})}))
vi.mock('@/lib/store-context',()=>({useCRMData:()=>({equipo:[]})}))
let base:GestionInversionista
let leer:()=>Promise<unknown>,escribir:()=>Promise<unknown>
const cerrar=vi.fn(),revocado=vi.fn()
const respuesta=(data:unknown)=>({data,error:null})
beforeEach(()=>{
  vi.clearAllMocks();sessionStorage.clear()
  base={version:1,inversionista_id:persona,perfiles:[],
    contacto:{nombre_completo:'ANA SINTÉTICA',telefono:'999888777',domicilio:null,revision:'rev1',creado_en:new Date().toISOString(),sin_limite:false,puede_corregir:true},
    documento:{id:null,tipo:'DNI',numero:'93334444',puede_corregir:false},inversion:null}
  leer=()=>Promise.resolve(respuesta(base));escribir=()=>Promise.resolve(respuesta({ok:true,inversionista_id:persona}))
  mock.sesion.mockResolvedValue({data:{session:{user:{id:actor}}},error:null})
  mock.rpc.mockImplementation((nombre:string)=>{
    if(nombre==='inversionista_gestion_fn')return leer()
    if(nombre==='inversionista_corregir_contacto_fn')return escribir()
    if(nombre==='postventa_operacion_estado_fn')return respuesta({registrada:true})
    throw new Error('RPC no esperada: '+nombre)
  })
})
afterEach(()=>cleanup())
function montar(fuenteId:string|null=null){
  const qc=new QueryClient({defaultOptions:{queries:{retry:false},mutations:{retry:false}}})
  return {...render(<QueryClientProvider client={qc}><GestionInversionistaDialogo actor={actor} persona={persona} fuente={fuenteId} onCerrar={cerrar} onRevocado={revocado}/></QueryClientProvider>),qc,user:userEvent.setup()}
}
describe('Gestión desde ficha neutral',()=>{
  it('precarga, guarda una vez, bloquea Escape durante el envío y retorna a la ficha',async()=>{
    let resolver!:(x:unknown)=>void
    escribir=()=>new Promise(r=>{resolver=r})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Corregir datos de contacto'}))
    const nombre=screen.getByLabelText('Nombres y apellidos')
    expect(nombre).toHaveValue('ANA SINTÉTICA');await user.clear(nombre);await user.type(nombre,'ANA CORREGIDA')
    const guardar=screen.getByRole('button',{name:'Guardar corrección'})
    fireEvent.click(guardar);fireEvent.click(guardar)
    await waitFor(()=>expect(mock.rpc.mock.calls.filter(c=>c[0]==='inversionista_corregir_contacto_fn')).toHaveLength(1))
    await user.keyboard('{Escape}');expect(cerrar).not.toHaveBeenCalled()
    expect(mock.rpc).toHaveBeenCalledWith('inversionista_corregir_contacto_fn',expect.objectContaining({p_inversionista:persona,p_revision:'rev1',p_datos:{nombre_completo:'ANA CORREGIDA',telefono:'999888777',domicilio:null}}))
    await act(async()=>resolver(respuesta({ok:true,inversionista_id:persona})))
    await waitFor(()=>expect(cerrar).toHaveBeenCalledTimes(1))
  })
  it('un error de red al refrescar conserva el borrador y bloquea guardar hasta revalidar',async()=>{
    const {user,qc}=montar();await user.click(await screen.findByRole('button',{name:'Corregir datos de contacto'}))
    await user.type(screen.getByLabelText('Domicilio'),'Dirección conservada')
    leer=()=>Promise.reject(new Error('Sin conexión'))
    await act(async()=>{await qc.invalidateQueries()})
    expect(screen.getByLabelText('Domicilio')).toHaveValue('Dirección conservada')
    await waitFor(()=>expect(screen.getByRole('button',{name:'Guardar corrección'})).toBeDisabled())
    leer=()=>Promise.resolve(respuesta(base));await user.click(screen.getByRole('button',{name:'Reintentar'}))
    await waitFor(()=>expect(screen.getByRole('button',{name:'Guardar corrección'})).toBeEnabled())
  })
  it('recupera una respuesta perdida por recibo sin duplicar la corrección',async()=>{
    escribir=()=>Promise.reject(new Error('Respuesta perdida'))
    const {user}=montar();await user.click(await screen.findByRole('button',{name:'Corregir datos de contacto'}));await user.click(screen.getByRole('button',{name:'Guardar corrección'}))
    await user.click(await screen.findByRole('button',{name:'Verificar envío guardado'}))
    await waitFor(()=>expect(cerrar).toHaveBeenCalledTimes(1))
    expect(mock.rpc.mock.calls.filter(c=>c[0]==='inversionista_corregir_contacto_fn')).toHaveLength(1)
    expect(leerEnvioPostventa(actor,'corregir_contacto',persona)).toBeNull()
  })
  it('rechazo explícito mantiene campos editables y libera el intento no registrado',async()=>{
    escribir=()=>Promise.resolve({data:null,error:{code:'22023',message:'Revisa el teléfono'}})
    const {user}=montar();await user.click(await screen.findByRole('button',{name:'Corregir datos de contacto'}));await user.click(screen.getByRole('button',{name:'Guardar corrección'}))
    expect(await screen.findByRole('alert')).toHaveTextContent('Revisa el teléfono')
    expect(screen.getByLabelText('Nombres y apellidos')).toHaveValue('ANA SINTÉTICA')
    expect(screen.getByRole('button',{name:'Guardar corrección'})).toBeEnabled()
    expect(leerEnvioPostventa(actor,'corregir_contacto',persona)).toBeNull()
  })
  it('cierra los datos visibles al revocarse el ámbito y no usa una respuesta de otra persona',async()=>{
    const {qc}=montar();await screen.findByText('ANA SINTÉTICA')
    leer=()=>Promise.resolve({data:null,error:{code:'42501',message:'Fuera de ámbito'}})
    await act(async()=>{await qc.invalidateQueries()})
    await waitFor(()=>expect(revocado).toHaveBeenCalledTimes(1));expect(screen.queryByText('ANA SINTÉTICA')).not.toBeInTheDocument()
  })
  it('no presenta datos de otra identidad aunque el servidor conteste 200',async()=>{
    base.inversionista_id=fuente;montar()
    expect(await screen.findByText('La identidad o la inversión cambió. Vuelve a abrir la ficha.')).toBeInTheDocument()
    expect(screen.queryByText('ANA SINTÉTICA')).not.toBeInTheDocument()
  })
  it('una fecha vencida bloquea al analista y conserva la excepción del servidor',async()=>{
    base.contacto.creado_en='2020-01-01T00:00:00Z';base.contacto.puede_corregir=false
    const {user}=montar();await user.click(await screen.findByRole('button',{name:'Corregir datos de contacto'}))
    expect(screen.getByRole('button',{name:'Guardar corrección'})).toBeDisabled()
  })
})
