// Volver a la ventana o recargar la página no puede devolver al analista al
// modal de identidad. Aquí el lector del documento es el REAL (solo se simula el
// transporte): el fallo vivía en cómo su clave y su resultado decidían qué
// diálogo se pinta.
import {useEffect,useState} from 'react'
import {beforeEach,describe,expect,it,vi} from 'vitest'
import {act,render,screen,waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {QueryClient,QueryClientProvider,focusManager} from '@tanstack/react-query'
import {AuthContext,type AuthContextValue} from '@/lib/auth-context'
import {StoreDataContext} from '@/lib/store-context'
import type {StoreDataApi} from '@/lib/store'
import type {Lead} from '@/lib/tipos'
import {guardarConversionAbierta,guardarIntentoInversion,leerConversionAbierta,leerIntentoInversion,nuevoIntentoInversion} from '@/lib/inversion-solicitud'
import {useDocumentoLead,type DocumentoLead} from '@/data/documento-lead'
import {ACTOR_F5,PERSONA_F5,FUENTE_F5} from '@/test/fixtures/f5'
import {InversionDesdeLead} from './inversion-desde-lead'

const api=vi.hoisted(()=>({persona:vi.fn(),contexto:vi.fn(),documento:vi.fn(),montajes:{n:0,desmontajes:0}}))
// `documento` puede devolver el dato, una promesa que nunca responde (carga) o una rechazada (caída).
vi.mock('@/lib/supabase',()=>({sb:{schema:()=>({rpc:(_nombre:string,args:{p_lead_id:string})=>{
  const respuesta=Promise.resolve().then(()=>api.documento(args.p_lead_id)).then(data=>({data,error:null}))
  return Object.assign(respuesta,{abortSignal:()=>respuesta})
}})}}))
vi.mock('@/data/inversion-solicitud-api',async original=>({...await original<typeof import('@/data/inversion-solicitud-api')>(),
  prepararPersonaLeadInversion:api.persona,obtenerContextoConversionInversion:api.contexto}))
// El wizard tiene su propia suite. Aquí solo importa si SOBREVIVE montado, con
// lo que el analista ya escribió, y para qué persona y solicitud se abre.
vi.mock('./inversion-nueva',()=>({InversionNueva:(p:{persona:string;origenLead:{solicitudId:string|null};
  onCerrar:()=>void;onConfirmada:()=>void;onRevocado:()=>void})=>{
  const [capital,setCapital]=useState('')
  useEffect(()=>{api.montajes.n++;return()=>{api.montajes.desmontajes++}},[])
  return <div role="dialog" aria-label="Nueva inversión">
    <span data-testid="persona">{p.persona}</span><span data-testid="solicitud">{p.origenLead.solicitudId??'sin solicitud'}</span>
    <label>Capital del contrato<input value={capital} onChange={e=>setCapital(e.target.value)}/></label>
    <button onClick={p.onCerrar}>Cerrar y continuar después</button>
    <button onClick={p.onConfirmada}>Confirmar inversión</button>
    <button onClick={p.onRevocado}>Perder el acceso</button>
  </div>
}}))

const LEAD='55555555-5555-4555-8555-555555555555'
const OTRO_ACTOR='77777777-7777-4777-8777-777777777777'
const lead:Lead={id:LEAD,nombre_completo:'PERSONA PRUEBA FOCO',telefono:'999888777',correo:'persona@pruebas.example',
  dni:null,etapa:'propuesta_enviada',origen:'landing',monto_estimado:5000,moneda:'PEN',
  vendedor_id:ACTOR_F5,vendedor_nombre:'ANALISTA F5',creado_en:'2026-09-01T12:00:00Z',
  actualizado_en:'2026-10-01T15:00:00Z',activo:true}
const sinVincular:DocumentoLead={lead_id:LEAD,inversionista_id:null,identificador_id:null,tipo:'DNI',numero:null,puede_corregir:false}
const vinculado:DocumentoLead={...sinVincular,inversionista_id:PERSONA_F5,identificador_id:FUENTE_F5,numero:'93334444'}

beforeEach(()=>{
  vi.resetAllMocks();sessionStorage.clear();api.montajes.n=0;api.montajes.desmontajes=0
  api.documento.mockReturnValue(sinVincular)
  // Preparar la identidad ESCRIBE en el lead (inversionista_id): desde aquí el
  // servidor responde con el documento vinculado y otra fecha de actualización.
  api.persona.mockImplementation(async(leadId:string)=>{
    api.documento.mockReturnValue(vinculado)
    return {inversionista_id:PERSONA_F5,lead_id:leadId,solicitud_id:null}
  })
})
/** La sección Datos de la ficha lee el MISMO documento, con la misma clave. */
function OtraLectura({l}:{l:Lead}){
  const documento=useDocumentoLead(l)
  return <span data-testid="otra-lectura">{documento.data?.numero??'sin documento'}</span>
}
function montar({actor=ACTOR_F5,sembrar,conFicha=false}:{actor?:string;sembrar?:(qc:QueryClient)=>void;conFicha?:boolean}={}){
  const qc=new QueryClient({defaultOptions:{queries:{retry:false}}}),onClose=vi.fn(),recargar=vi.fn().mockResolvedValue(true)
  sembrar?.(qc)
  const auth={yo:{id:actor,rol:'vendedor',nombre_completo:'ANALISTA F5',demo:false,puede_contratar:true}} as AuthContextValue
  const store={recargar} as unknown as StoreDataApi
  const arbol=(l:Lead)=><QueryClientProvider client={qc}><AuthContext.Provider value={auth}><StoreDataContext.Provider value={store}>
    {conFicha&&<OtraLectura l={l}/>}<InversionDesdeLead l={l} onClose={onClose}/>
  </StoreDataContext.Provider></AuthContext.Provider></QueryClientProvider>
  const vista=render(arbol(lead))
  return {user:userEvent.setup(),onClose,recargar,unmount:vista.unmount,conLead:(l:Lead)=>vista.rerender(arbol(l))}
}
async function llegarAlWizard(user:ReturnType<typeof userEvent.setup>){
  await user.type(await screen.findByLabelText('Documento'),'93334444')
  await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
  await user.type(await screen.findByLabelText('Capital del contrato'),'25000')
}
const sigueElWizard=async()=>{
  // Deja terminar cualquier relectura antes de mirar: el fallo aparecía DESPUÉS de cargar.
  await waitFor(()=>expect(screen.queryByText('Documento del lead')).not.toBeInTheDocument())
  expect(screen.queryByText('Registrar la inversión del lead')).not.toBeInTheDocument()
  expect(screen.getByLabelText('Capital del contrato')).toHaveValue('25000')
  expect(api.montajes).toEqual({n:1,desmontajes:0})
}

describe('Volver a la ventana con el wizard abierto',()=>{
  it('la resincronización de la cartera (lead con otra fecha de actualización) conserva el wizard',async()=>{
    const {user,conLead}=montar()
    await llegarAlWizard(user)
    // Es lo que hace el store al recuperar el foco: mismo lead, fila más reciente.
    conLead({...lead,actualizado_en:'2026-10-01T15:00:42Z'})
    await sigueElWizard()
  })

  it('recuperar el foco no vuelve a leer el documento ni toca el wizard',async()=>{
    const {user}=montar()
    await llegarAlWizard(user)
    const lecturas=api.documento.mock.calls.length
    await act(async()=>{focusManager.setFocused(false);focusManager.setFocused(true)})
    await sigueElWizard()
    expect(api.documento).toHaveBeenCalledTimes(lecturas)
    focusManager.setFocused(undefined)
  })

  it('la ficha sigue releyendo su documento por su cuenta sin tocar el wizard',async()=>{
    const {user,conLead}=montar({conFicha:true})
    await llegarAlWizard(user)
    expect(screen.getByTestId('otra-lectura')).toHaveTextContent('sin documento')
    conLead({...lead,actualizado_en:'2026-10-01T15:00:42Z'})
    await waitFor(()=>expect(screen.getByTestId('otra-lectura')).toHaveTextContent('93334444'))
    await sigueElWizard()
  })

  it('lo escrito en la identidad tampoco se pierde si la cartera se resincroniza antes de continuar',async()=>{
    const {user,conLead}=montar()
    await user.type(await screen.findByLabelText('Documento'),'93334444')
    conLead({...lead,actualizado_en:'2026-10-01T15:00:42Z'})
    await waitFor(()=>expect(screen.queryByText('Documento del lead')).not.toBeInTheDocument())
    expect(screen.getByLabelText('Documento')).toHaveValue('93334444')
  })
})

describe('El documento que precarga la identidad',()=>{
  /** La ficha ya leyó este documento: su copia está en caché cuando se abre la conversión. */
  const enCache=(documento:DocumentoLead)=>(qc:QueryClient)=>
    qc.setQueryData(['crm','leads','documento',ACTOR_F5,LEAD,lead.actualizado_en],documento)
  /** El servidor tarda: la prueba decide cuándo responde. */
  function servidorLento(){
    let responder!:(documento:DocumentoLead)=>void
    api.documento.mockReturnValue(new Promise(r=>{responder=r}))
    // React Query avisa a sus observadores en la siguiente vuelta: se espera dentro del act.
    return (documento:DocumentoLead)=>act(async()=>{responder(documento);await new Promise(r=>setTimeout(r,20))})
  }

  it('abre con la copia de la ficha sin esperar y, si el servidor trae otro documento, se queda con el del servidor',async()=>{
    const responder=servidorLento()
    montar({sembrar:enCache({...sinVincular,numero:'11111111'})})
    expect(screen.getByLabelText('Documento')).toHaveValue('11111111')
    expect(screen.queryByText('Documento del lead')).not.toBeInTheDocument()
    await responder({...sinVincular,tipo:'CE',numero:'001234567'})
    expect(screen.getByLabelText('Documento')).toHaveValue('001234567')
    expect(screen.getByLabelText('Tipo de documento')).toHaveValue('CE')
  })

  it('si el servidor confirma la misma copia, lo ya escrito no se pierde',async()=>{
    const responder=servidorLento()
    const {user}=montar({sembrar:enCache(sinVincular)})
    await user.type(screen.getByLabelText('Documento'),'93334444')
    await responder(sinVincular)
    expect(screen.getByLabelText('Documento')).toHaveValue('93334444')
  })

  it('la identidad no se puede enviar hasta que el servidor confirma el documento',async()=>{
    // Una respuesta con otro documento remonta el formulario: un envío en curso se perdería.
    const responder=servidorLento()
    const {user}=montar({sembrar:enCache({...sinVincular,numero:'93334444'})})
    const continuar=screen.getByRole('button',{name:'Continuar a Nueva inversión'})
    expect(continuar).toBeDisabled()
    expect(continuar).toHaveAccessibleDescription('Comprobando el documento con el servidor…')
    await user.type(screen.getByLabelText('Nombre completo'),'{Enter}')
    expect(api.persona).not.toHaveBeenCalled()
    await responder({...sinVincular,numero:'93334444'})
    expect(continuar).toBeEnabled()
    await user.click(continuar)
    expect(api.persona).toHaveBeenCalledOnce()
  })

  it('un wizard retomado no se remonta aunque el servidor responda tarde con otro documento',async()=>{
    guardarConversionAbierta(ACTOR_F5,LEAD,PERSONA_F5)
    const responder=servidorLento()
    const {user}=montar({sembrar:enCache(sinVincular)})
    await user.type(await screen.findByLabelText('Capital del contrato'),'25000')
    // Llega ya vinculado (otro número): sin fijar al tener persona, eso cambiaba la `key`.
    await responder(vinculado)
    await sigueElWizard()
    expect(api.persona).not.toHaveBeenCalled()
  })

  it('cancelar la identidad devuelve el foco al botón que la abrió',async()=>{
    function Pantalla(){
      const [abierto,setAbierto]=useState(false)
      return <><button onClick={()=>setAbierto(true)}>Convertir a cliente</button>
        {abierto&&<InversionDesdeLead l={lead} onClose={()=>setAbierto(false)}/>}</>
    }
    const qc=new QueryClient({defaultOptions:{queries:{retry:false}}});enCache(sinVincular)(qc)
    const auth={yo:{id:ACTOR_F5,rol:'vendedor',nombre_completo:'ANALISTA F5',demo:false,puede_contratar:true}} as AuthContextValue
    render(<QueryClientProvider client={qc}><AuthContext.Provider value={auth}>
      <StoreDataContext.Provider value={{recargar:vi.fn()} as unknown as StoreDataApi}><Pantalla/></StoreDataContext.Provider>
    </AuthContext.Provider></QueryClientProvider>)
    const user=userEvent.setup(),boton=screen.getByRole('button',{name:'Convertir a cliente'})
    await user.click(boton)
    // Con la copia de la ficha el formulario es el PRIMER diálogo: conserva su origen.
    await user.click(await screen.findByRole('button',{name:'Cancelar'}))
    await waitFor(()=>expect(boton).toHaveFocus())
  })
})

describe('Recargar la página con el wizard abierto',()=>{
  it('lo retoma para la misma persona sin volver a pedir la identidad',async()=>{
    const primera=montar()
    await llegarAlWizard(primera.user)
    // Recargar no avisa a nadie: el diálogo desaparece sin pasar por su cierre.
    primera.unmount()
    montar()
    expect(await screen.findByTestId('persona')).toHaveTextContent(PERSONA_F5)
    // La solicitud la trae el intento guardado, que es quien sigue sus cambios.
    expect(screen.getByTestId('solicitud')).toHaveTextContent('sin solicitud')
    expect(screen.queryByText('Registrar la inversión del lead')).not.toBeInTheDocument()
    expect(api.persona).toHaveBeenCalledOnce()
  })

  it('cerrarlo a propósito sí vuelve a pedir la identidad la próxima vez',async()=>{
    const primera=montar()
    await llegarAlWizard(primera.user)
    await primera.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
    expect(primera.onClose).toHaveBeenCalledOnce()
    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
    primera.unmount()
    montar()
    expect(await screen.findByText('Registrar la inversión del lead')).toBeInTheDocument()
  })

  it('cerrar mientras todavía carga el documento también deja de retomarlo',async()=>{
    guardarConversionAbierta(ACTOR_F5,LEAD,PERSONA_F5)
    api.documento.mockReturnValue(new Promise(()=>undefined))
    const {user,onClose}=montar()
    await user.click(screen.getByRole('button',{name:'Volver a la ficha'}))
    expect(onClose).toHaveBeenCalledOnce()
    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
  })

  it('cerrar el aviso de que el documento no cargó también deja de retomarlo',async()=>{
    guardarConversionAbierta(ACTOR_F5,LEAD,PERSONA_F5)
    api.documento.mockRejectedValue(new TypeError('Conexión interrumpida'))
    const {user,onClose}=montar()
    expect(await screen.findByText(/No se pudo consultar el documento vinculado/)).toBeInTheDocument()
    expect(screen.queryByTestId('persona')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Volver a la ficha'}))
    expect(onClose).toHaveBeenCalledOnce()
    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
  })

  it('confirmar la inversión deja de retomarlo y recarga la cartera',async()=>{
    const {user,recargar,onClose}=montar()
    await llegarAlWizard(user)
    await user.click(screen.getByRole('button',{name:'Confirmar inversión'}))
    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
    expect(recargar).toHaveBeenCalledOnce();expect(onClose).not.toHaveBeenCalled()
  })

  it('perder el acceso lo cierra y borra también la solicitud guardada en la pestaña',async()=>{
    const {user,onClose}=montar()
    await llegarAlWizard(user)
    guardarIntentoInversion(nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,empresa:'avance'}))
    await user.click(screen.getByRole('button',{name:'Perder el acceso'}))
    expect(onClose).toHaveBeenCalledOnce()
    expect(leerConversionAbierta(ACTOR_F5,LEAD)).toBeNull()
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)).toBeNull()
  })

  it('otra cuenta en la misma pestaña no hereda el wizard',async()=>{
    const primera=montar()
    await llegarAlWizard(primera.user)
    primera.unmount()
    montar({actor:OTRO_ACTOR})
    expect(await screen.findByText('Registrar la inversión del lead')).toBeInTheDocument()
    expect(screen.queryByTestId('persona')).not.toBeInTheDocument()
  })
})
