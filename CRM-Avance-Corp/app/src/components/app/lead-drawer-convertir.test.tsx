// Formulario compartido desde el lead. SQL/Auth se prueban en el banco aislado.
import {beforeEach,describe,expect,it,vi} from 'vitest'
import {act,fireEvent,render,screen,waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {QueryClient,QueryClientProvider} from '@tanstack/react-query'
import {AuthContext,type AuthContextValue} from '@/lib/auth-context'
import {StoreDataContext} from '@/lib/store-context'
import type {StoreDataApi} from '@/lib/store'
import type {Lead} from '@/lib/tipos'
import {CrmApiError,type CrearContratoInput} from '@/data/crm-api'
import type {CuotaCronograma} from '@/lib/cronograma'
import {guardarIntentoInversion,leerIntentoInversion,nuevoIntentoInversion,type DatosInversion,type SolicitudInversion} from '@/lib/inversion-solicitud'
import {ACTOR_F5,PERSONA_F5,PERFIL_F5,FUENTE_F5,fichaF5} from '@/test/fixtures/f5'
import {DialogConvertir} from './lead-drawer'

const api=vi.hoisted(()=>({persona:vi.fn(),contexto:vi.fn(),ficha:vi.fn(),preparar:vi.fn(),consultar:vi.fn(),
  corregir:vi.fn(),confirmar:vi.fn(),cancelar:vi.fn(),acceso:vi.fn(),subir:vi.fn(),bienvenida:vi.fn(),convertirAnterior:vi.fn()}))
vi.mock('@/data/inversion-solicitud-api',async original=>({...await original<typeof import('@/data/inversion-solicitud-api')>(),
  prepararPersonaLeadInversion:api.persona,obtenerContextoConversionInversion:api.contexto,
  prepararSolicitudInversion:api.preparar,consultarSolicitudInversion:api.consultar,
  corregirSolicitudInversion:api.corregir,confirmarSolicitudInversion:api.confirmar,cancelarSolicitudInversion:api.cancelar,
  completarAccesoInversion:api.acceso,subirComprobanteInversion:api.subir,enviarBienvenidaInversion:api.bienvenida}))
vi.mock('@/data/inversionistas-api',async original=>({...await original<typeof import('@/data/inversionistas-api')>(),obtenerFichaInversionista:api.ficha}))
vi.mock('@/data/crm-api',async original=>({...await original<typeof import('@/data/crm-api')>(),convertirLead:api.convertirAnterior}))
// ContratoNuevo tiene su propia suite de campos/cuentas/tasas. Aquí debe
// proponer datos al flujo compartido, sin crear por su cuenta el contrato.
vi.mock('./contrato-nuevo',async()=>{
  const {DialogTitle}=await import('@/components/ui/dialog')
  return {ContratoNuevo:(p:{clienteId:string;leadOrigenId?:string;analistaInicial?:string;
    onRevisar:(i:CrearContratoInput,c:CuotaCronograma[])=>Promise<void>;onOmitir:()=>void})=><>
    <DialogTitle>Condiciones del contrato compartido</DialogTitle>
    <span data-testid="origen-tasa">{p.leadOrigenId}</span><span data-testid="analista">{p.analistaInicial}</span>
    <button onClick={()=>void p.onRevisar({cliente_id:p.clienteId,analista_cierre_id:p.analistaInicial,
      categoria:'nuevo',capital:5000,moneda:'PEN',tasa_anual:15,modalidad:'mensual',tipo_interes:'simple',
      fecha_inicio:'2026-09-01',fecha_vencimiento:'2027-09-01',cuenta_pago:{tipo:'nueva',banco:'BANCO PRUEBA',
      tipo_cuenta:'ahorros',numero_cuenta:'PRUEBA-001',cci:'99999999999999999991',titular_distinto:false}} as CrearContratoInput,[])}>
      Revisar contrato compartido</button>
    <button onClick={p.onOmitir}>Cancelar contrato</button>
  </>}
})
const LEAD='55555555-5555-4555-8555-555555555555'
const OTRO_LEAD='66666666-6666-4666-8666-666666666666'
const lead:Lead={id:LEAD,nombre_completo:'PERSONA PRUEBA CONVERSIÓN',telefono:'999888777',correo:'persona@pruebas.example',
  dni:'93334444',etapa:'propuesta_enviada',origen:'landing',monto_estimado:5000,moneda:'PEN',
  vendedor_id:ACTOR_F5,vendedor_nombre:'ANALISTA F5',creado_en:'2026-09-01T12:00:00Z',activo:true}
let vigente:SolicitudInversion|null
let perfil:string|null
const preparada=(clave:string,datos:DatosInversion):SolicitudInversion=>({solicitud_id:clave,lead_id:LEAD,estado:'preparada',
  inversion_id:null,inversionista_id:PERSONA_F5,inversionista_origen_id:PERSONA_F5,identidad_fusionada:false,
  responsable_esperado_id:ACTOR_F5,responsable_actual_id:ACTOR_F5,requiere_revision_responsable:false,
  revision_datos:0,revision_responsable:0,hash_datos:'huella',necesita_portal:datos.empresa==='avance'&&!perfil,
  comprobante_bucket:datos.empresa==='avance'?null:'f4-comprobantes',comprobante_ruta:datos.evidencia?.ruta??null,resultado:null,datos})
beforeEach(()=>{
  vi.resetAllMocks();sessionStorage.clear();vigente=null;perfil=null
  api.persona.mockImplementation(async(leadId:string)=>({inversionista_id:PERSONA_F5,lead_id:leadId,solicitud_id:vigente?.solicitud_id??null}))
  api.contexto.mockImplementation(async()=>({...fichaF5,solicitud_id:vigente?.solicitud_id??null,documento_tipo:'DNI',persona:{...fichaF5.persona,perfil_id:perfil}}))
  api.cancelar.mockImplementation(async()=>{vigente={...vigente!,estado:'cancelada'};return vigente})
  api.preparar.mockImplementation(async i=>{vigente=preparada(i.clave,i.datos);return vigente})
  api.consultar.mockImplementation(async()=>{if(!vigente)throw new CrmApiError('Solicitud no encontrada','P0002');return vigente})
  api.corregir.mockImplementation(async i=>{vigente={...vigente!,datos:i.correccion.datos,revision_datos:vigente!.revision_datos+1,necesita_portal:!perfil};return vigente})
  api.acceso.mockImplementation(async()=>{perfil=PERFIL_F5;vigente={...vigente!,necesita_portal:false};return {ok:true,solicitud_id:vigente.solicitud_id,perfil_id:perfil}})
  api.confirmar.mockImplementation(async()=>{
    const resultado={ok:true as const,solicitud_id:vigente!.solicitud_id,inversion_id:FUENTE_F5,inversionista_id:PERSONA_F5,
      empresa:vigente!.datos!.empresa,fuente:vigente!.datos!.empresa==='avance'?{id:FUENTE_F5}:{cierre_id:FUENTE_F5}}
    vigente={...vigente!,estado:'confirmada',inversion_id:FUENTE_F5,resultado};return resultado
  })
  api.subir.mockResolvedValue(undefined)
  api.bienvenida.mockResolvedValue({estado:'enviada'})
})
function montar(datos:Partial<Lead>={}){
  const qc=new QueryClient({defaultOptions:{queries:{retry:false}}}),onClose=vi.fn(),recargar=vi.fn().mockResolvedValue(true),convertir=vi.fn()
  const auth={yo:{id:ACTOR_F5,rol:'vendedor',nombre_completo:'ANALISTA F5',demo:false,puede_contratar:true}} as AuthContextValue
  const store={recargar,convertir,convertirExterno:convertir,equipo:[]} as unknown as StoreDataApi
  const vista=render(<QueryClientProvider client={qc}><AuthContext.Provider value={auth}><StoreDataContext.Provider value={store}>
    <DialogConvertir l={{...lead,...datos}} onClose={onClose}/>
  </StoreDataContext.Provider></AuthContext.Provider></QueryClientProvider>)
  return {...vista,user:userEvent.setup(),onClose,recargar,convertir,qc}
}
async function entrar(user:ReturnType<typeof userEvent.setup>,empresa:string){
  await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
  await user.click(await screen.findByRole('button',{name:empresa}))
}
async function llenarCoop(user:ReturnType<typeof userEvent.setup>,moneda='PEN'){
  if(moneda==='USD')await user.selectOptions(screen.getByLabelText('Moneda'),'USD')
  const capital=screen.getByLabelText(new RegExp('Capital.*'+moneda))
  await user.clear(capital);await user.type(capital,'5000')
  await user.type(screen.getByLabelText('Número de operación del depósito'),'CI-PRUEBA-001')
  await user.type(screen.getByLabelText(/Plazo.*meses/),'12')
  await user.type(screen.getByLabelText(/Rentabilidad anual/),'18')
  await user.type(screen.getByLabelText('Referencia de la inversión'),'CI-CERTIFICADO')
  await user.upload(screen.getByLabelText('Comprobante PDF, JPG o PNG (hasta 10 MB)'),new File(['comprobante'],'prueba.pdf',{type:'application/pdf'}))
  const formulario=screen.getByRole('button',{name:'Revisar inversión'}).closest('form')!
  const invalidos=[...formulario.querySelectorAll('input')]
    .filter(i=>i.type!=='file'&&!i.checkValidity()).map(i=>({id:i.id,error:i.validationMessage}))
  expect(invalidos).toEqual([])
  expect(formulario.querySelector<HTMLInputElement>('input[type=file]')!.files).toHaveLength(1)
  // JSDOM no integra FileList simulado en la validación nativa de required.
  // El navegador se verifica además con E2E; aquí se ejerce el onSubmit real.
  fireEvent.submit(formulario)
  await screen.findByRole('button',{name:'Confirmar inversión'})
}
describe('Convertir a cliente usa Nueva inversión',()=>{
  it('cancelar una solicitud permite elegir otra empresa sin convertir',async()=>{
    const {user,recargar}=montar();await entrar(user,'Prodelco');await llenarCoop(user)
    const id=vigente!.solicitud_id
    await user.click(screen.getByRole('button',{name:'Cancelar solicitud'}))
    await user.click(screen.getByRole('button',{name:'Confirmar cancelación'}))
    await screen.findByRole('heading',{name:'Solicitud cancelada'})
    expect(api.cancelar).toHaveBeenCalledWith(id,0);expect(api.confirmar).not.toHaveBeenCalled();expect(recargar).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button',{name:'Iniciar otra inversión'}))
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)).toBeNull()
    await user.click(screen.getByRole('button',{name:'Qorilazo'}))
    expect(screen.getByLabelText('Número de operación del depósito')).toHaveValue('')
    await llenarCoop(user);expect(vigente!.solicitud_id).not.toBe(id)
    expect(vigente!.datos?.empresa).toBe('qorilazo')
  })
  it('una lectura fallida conserva campos y comprobante hasta recuperar permisos',async()=>{
    const {user,qc}=montar();await entrar(user,'Prodelco')
    await user.type(screen.getByLabelText('Número de operación del depósito'),'NO-PERDER-001')
    const archivo=new File(['datos'],'comprobante.png',{type:'image/png'})
    await user.upload(screen.getByLabelText('Comprobante PDF, JPG o PNG (hasta 10 MB)'),archivo)
    api.contexto.mockRejectedValueOnce(new CrmApiError('Fallo temporal','55P03'))
    await act(async()=>{await qc.invalidateQueries({queryKey:['crm','inversionistas',ACTOR_F5]})})
    expect(await screen.findByRole('alert')).toHaveTextContent('Conservamos tus datos')
    const campo=screen.getByLabelText('Número de operación del depósito')
    expect(campo).toHaveValue('NO-PERDER-001');expect(campo).toBeDisabled()
    expect((screen.getByLabelText('Comprobante PDF, JPG o PNG (hasta 10 MB)') as HTMLInputElement).files?.[0]).toBe(archivo)
    await user.click(screen.getByRole('button',{name:'Verificar y continuar'}))
    await waitFor(()=>expect(campo).not.toBeDisabled());expect(campo).toHaveValue('NO-PERDER-001')
    expect(api.preparar).not.toHaveBeenCalled()
  })
  it('un lead convertido recupera su bienvenida sin borrador ni volver a preparar identidad',async()=>{
    vigente=preparada(FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,empresa:'avance'})
    await api.confirmar();api.confirmar.mockClear()
    montar({etapa:'convertido'})
    await screen.findByRole('heading',{name:'Inversión confirmada'})
    await waitFor(()=>expect(api.bienvenida).toHaveBeenCalledExactlyOnceWith(FUENTE_F5))
    expect(api.persona).not.toHaveBeenCalled();expect(api.preparar).not.toHaveBeenCalled();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it('precarga identidad; cancelar no prepara ni convierte',async()=>{
    const {user,onClose,convertir}=montar()
    expect(screen.getByLabelText('Nombre completo')).toHaveValue(lead.nombre_completo)
    expect(screen.getByLabelText('Documento')).toHaveValue(lead.dni)
    await user.click(screen.getByRole('button',{name:'Cancelar'}))
    expect(onClose).toHaveBeenCalledOnce();expect(api.persona).not.toHaveBeenCalled();expect(convertir).not.toHaveBeenCalled()
  })
  it.each([['DNI','123'],['CE','12345678'],['PASAPORTE','A']])('valida el documento %s antes de reconocer la persona',async(tipo,doc)=>{
    const {user}=montar({dni:''})
    await user.selectOptions(screen.getByLabelText('Tipo de documento'),tipo)
    await user.type(screen.getByLabelText('Documento'),doc)
    await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    expect(screen.getByRole('alert')).toBeInTheDocument();expect(api.persona).not.toHaveBeenCalled()
  })
  it('muestra el rechazo de ámbito/identidad sin abrir otra persona',async()=>{
    api.persona.mockRejectedValueOnce(new CrmApiError('La persona pertenece a otro equipo','42501'))
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    expect(await screen.findByRole('alert')).toHaveTextContent('otro equipo');expect(api.preparar).not.toHaveBeenCalled()
  })
  it.each([['Qorilazo','qorilazo','PEN'],['Prodelco','prodelco','PEN'],['Prodelco','prodelco','USD']])('registra %s en %s/%s con la revisión de Cartera',async(nombre,empresa,moneda)=>{
    const {user,recargar,convertir,qc}=montar();const invalidar=vi.spyOn(qc,'invalidateQueries')
    await entrar(user,nombre);await llenarCoop(user,moneda)
    expect(api.persona).toHaveBeenCalledWith(LEAD,'DNI',lead.dni,lead.nombre_completo)
    expect(api.ficha).not.toHaveBeenCalled();expect(api.preparar).toHaveBeenCalledOnce()
    expect(api.preparar.mock.calls[0]![0].datos).toMatchObject({lead_id:LEAD,inversionista_id:PERSONA_F5,empresa,moneda,monto:5000,plazo_meses:12,tasa_anual:18,referencia:'CI-CERTIFICADO'})
    expect(recargar).not.toHaveBeenCalled();expect(convertir).not.toHaveBeenCalled();expect(api.convertirAnterior).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button',{name:'Confirmar inversión'}))
    await screen.findByRole('heading',{name:'Inversión confirmada'})
    expect(api.subir).toHaveBeenCalledOnce();expect(api.confirmar).toHaveBeenCalledWith(vigente!.solicitud_id,0)
    expect(recargar).toHaveBeenCalledOnce();expect(convertir).not.toHaveBeenCalled()
    await waitFor(()=>expect(invalidar).toHaveBeenCalledWith({queryKey:['crm','metricas']}))
    expect(invalidar).toHaveBeenCalledWith({queryKey:['crm','inversionistas',ACTOR_F5]})
  })
  it('cerrar en revisión conserva la solicitud; reabrir retoma la misma',async()=>{
    const vista=montar();await entrar(vista.user,'Qorilazo');await llenarCoop(vista.user);const clave=vigente!.solicitud_id
    await vista.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
    expect(vista.onClose).toHaveBeenCalledOnce();expect(api.confirmar).not.toHaveBeenCalled();expect(vista.recargar).not.toHaveBeenCalled()
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)?.clave).toBe(clave)
    vista.unmount();const segunda=montar()
    await segunda.user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(api.consultar).toHaveBeenCalledWith(clave,expect.any(AbortSignal));expect(api.preparar).toHaveBeenCalledOnce()
  })
  it('recupera del servidor después de perder el borrador local',async()=>{
    vigente=preparada(FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,empresa:'qorilazo',monto:5000,moneda:'PEN'})
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(api.preparar).not.toHaveBeenCalled();expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)?.clave).toBe(FUENTE_F5)
  })
  it('si falla recuperar la solicitud conocida, exige consultar la misma antes de continuar',async()=>{
    vigente=preparada(FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,empresa:'qorilazo',monto:5000,moneda:'PEN'})
    api.consultar.mockRejectedValueOnce(new TypeError('Conexión interrumpida'))
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await user.click(await screen.findByRole('button',{name:'Consultar y recuperar'}))
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(api.consultar).toHaveBeenCalledTimes(2);expect(api.preparar).not.toHaveBeenCalled()
    expect(screen.queryByRole('button',{name:'Prodelco'})).not.toBeInTheDocument()
  })
  it('reintenta la misma clave tras fallo de confirmación sin preparar otra',async()=>{
    api.confirmar.mockRejectedValueOnce(new TypeError('Conexión interrumpida'))
    const {user,recargar}=montar();await entrar(user,'Qorilazo');await llenarCoop(user)
    await user.click(screen.getByRole('button',{name:'Confirmar inversión'}));await screen.findByRole('alert')
    expect(recargar).not.toHaveBeenCalled();const id=vigente!.solicitud_id
    await user.click(screen.getByRole('button',{name:'Confirmar inversión'}));await screen.findByRole('heading',{name:'Inversión confirmada'})
    expect(api.confirmar.mock.calls).toEqual([[id,0],[id,0]]);expect(api.preparar).toHaveBeenCalledOnce();expect(recargar).toHaveBeenCalledOnce()
  })
  it('el acceso Avance no convierte hasta confirmar el contrato compartido',async()=>{
    const {user,recargar,convertir}=montar();await entrar(user,'Avance')
    expect(screen.queryByLabelText('Nombre completo')).not.toBeInTheDocument()
    expect(screen.getAllByRole('textbox').slice(0, 2)).toEqual([screen.getByLabelText('Apellidos'), screen.getByLabelText('Nombres')])
    expect(screen.getByLabelText('Correo de acceso Avance')).toHaveValue(fichaF5.persona.correo)
    await user.type(screen.getByLabelText('Nombres'),'PERSONA');await user.type(screen.getByLabelText('Apellidos'),'PRUEBA CONVERSIÓN')
    await user.type(screen.getByLabelText('Domicilio legal'),'AVENIDA SINTETICA 123 LIMA')
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(vigente!.datos!.alta_portal).toMatchObject({nombres:'PERSONA',apellidos:'PRUEBA CONVERSIÓN',nombre_completo:'PERSONA PRUEBA CONVERSIÓN'})
    await user.click(await screen.findByRole('button',{name:'Completar acceso Avance'}))
    await screen.findByRole('heading',{name:'Condiciones del contrato compartido'})
    expect(screen.getByTestId('origen-tasa')).toHaveTextContent(LEAD);expect(screen.getByTestId('analista')).toHaveTextContent(ACTOR_F5)
    expect(api.confirmar).not.toHaveBeenCalled();expect(recargar).not.toHaveBeenCalled();expect(convertir).not.toHaveBeenCalled()
    expect(api.bienvenida).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button',{name:'Revisar contrato compartido'}))
    await user.click(await screen.findByRole('button',{name:'Confirmar inversión'}))
    await screen.findByRole('heading',{name:'Inversión confirmada'})
    expect(api.confirmar).toHaveBeenCalledWith(vigente!.solicitud_id,1);expect(recargar).toHaveBeenCalledOnce()
    await waitFor(()=>expect(api.bienvenida).toHaveBeenCalledExactlyOnceWith(vigente!.solicitud_id))
    expect(vigente!.datos!.contrato).not.toHaveProperty('analista_cierre_id');expect(vigente!.datos!.contrato).not.toHaveProperty('cliente_id')
    expect(api.convertirAnterior).not.toHaveBeenCalled()
  })
  it('guarda y recupera el acceso; señala domicilio inválido y permite corregir el correo antes de crear la cuenta',async()=>{
    const primera=montar();await entrar(primera.user,'Avance')
    expect(screen.getByRole('navigation',{name:'Progreso de primera inversión Avance'})).toHaveTextContent('Paso 1 de 3')
    await primera.user.type(screen.getByLabelText('Apellidos'),'PRUEBA')
    await primera.user.type(screen.getByLabelText('Nombres'),'PERSONA')
    await primera.user.clear(screen.getByLabelText('Correo de acceso Avance'))
    await primera.user.type(screen.getByLabelText('Correo de acceso Avance'),'persona-correcta@example.invalid')
    await primera.user.type(screen.getByLabelText('Domicilio legal'),'Av. Corta 1')
    expect(screen.getByRole('status')).toHaveTextContent('Borrador guardado')
    await primera.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
    expect(primera.onClose).toHaveBeenCalledOnce();expect(api.preparar).not.toHaveBeenCalled()
    primera.unmount()

    const segunda=montar();await entrar(segunda.user,'Avance')
    expect(screen.getByLabelText('Apellidos')).toHaveValue('PRUEBA')
    expect(screen.getByLabelText('Nombres')).toHaveValue('PERSONA')
    expect(screen.getByLabelText('Correo de acceso Avance')).toHaveValue('persona-correcta@example.invalid')
    expect(screen.getByLabelText('Domicilio legal')).toHaveValue('Av. Corta 1')
    await segunda.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(screen.getByLabelText('Domicilio legal')).toHaveAttribute('aria-invalid','true')
    expect(screen.getByRole('alert')).toHaveTextContent('entre 15 y 240 caracteres')
    expect(api.preparar).not.toHaveBeenCalled()
    await segunda.user.clear(screen.getByLabelText('Domicilio legal'))
    await segunda.user.type(screen.getByLabelText('Domicilio legal'),'AVENIDA SINTETICA 123 LIMA')
    await segunda.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(screen.getByText('persona-correcta@example.invalid')).toBeInTheDocument()
    expect(screen.getByText('AVENIDA SINTETICA 123 LIMA')).toBeInTheDocument()
    await segunda.user.click(screen.getByRole('button',{name:'Corregir datos de acceso'}))
    await segunda.user.clear(screen.getByLabelText('Correo de acceso Avance'))
    await segunda.user.type(screen.getByLabelText('Correo de acceso Avance'),'correo-final@example.invalid')
    await segunda.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(await screen.findByText('correo-final@example.invalid')).toBeInTheDocument()
    expect(vigente?.datos?.alta_portal?.correo).toBe('correo-final@example.invalid')
    expect(vigente?.datos).toMatchObject({contrato:{moneda:'PEN'},cronograma:[],cuenta:{}})
    expect(api.acceso).not.toHaveBeenCalled()
    await segunda.user.click(screen.getByRole('button',{name:'Completar acceso Avance'}))
    await screen.findByRole('heading',{name:'Condiciones del contrato compartido'})
    expect(api.acceso).toHaveBeenCalledOnce()
  })
  it('no muestra el borrador de otro lead aunque comparta analista y persona',async()=>{
    const primera=montar();await entrar(primera.user,'Avance')
    await primera.user.type(screen.getByLabelText('Apellidos'),'PRIMER LEAD')
    await primera.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
    primera.unmount()
    const segunda=montar({id:OTRO_LEAD,nombre_completo:'OTRO LEAD SINTÉTICO'})
    await entrar(segunda.user,'Avance')
    expect(screen.getByLabelText('Apellidos')).toHaveValue('')
    await segunda.user.type(screen.getByLabelText('Apellidos'),'SEGUNDO LEAD')
    await segunda.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
    segunda.unmount()
    const retomada=montar();await entrar(retomada.user,'Avance')
    expect(screen.getByLabelText('Apellidos')).toHaveValue('PRIMER LEAD')
    expect(api.preparar).not.toHaveBeenCalled()
  })
  it('avisa si el navegador impide guardar y exige confirmar antes de cerrar',async()=>{
    const vista=montar();await entrar(vista.user,'Avance')
    const original=sessionStorage
    vi.stubGlobal('sessionStorage',{
      getItem:original.getItem.bind(original),removeItem:original.removeItem.bind(original),
      setItem:()=>{throw new DOMException('Sin espacio','QuotaExceededError')},
    })
    try {
      await vista.user.type(screen.getByLabelText('Apellidos'),'PRUEBA')
      expect(screen.getAllByRole('alert').some(alerta=>alerta.textContent?.includes('No se están guardando'))).toBe(true)
      await vista.user.click(screen.getByRole('button',{name:'Cerrar y continuar después'}))
      expect(vista.onClose).not.toHaveBeenCalled()
      expect(screen.getByRole('button',{name:'Cerrar sin guardar'})).toBeInTheDocument()
      await vista.user.click(screen.getByRole('button',{name:'Cerrar sin guardar'}))
      expect(vista.onClose).toHaveBeenCalledOnce()
    } finally {vi.unstubAllGlobals()}
  })
  it('cancelar el contrato conserva la inversión sin confirmar',async()=>{
    perfil=PERFIL_F5;const {user,onClose,recargar}=montar();await entrar(user,'Avance')
    await user.click(screen.getByRole('button',{name:'Cancelar contrato'}))
    expect(onClose).toHaveBeenCalledOnce();expect(api.confirmar).not.toHaveBeenCalled();expect(recargar).not.toHaveBeenCalled()
  })
  it('la revocación borra la recuperación de ese lead',async()=>{
    vigente=preparada(FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,empresa:'qorilazo'})
    guardarIntentoInversion(nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,vigente.datos!))
    api.contexto.mockRejectedValueOnce(new CrmApiError('Acceso revocado','42501'))
    const {user,onClose}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await waitFor(()=>expect(onClose).toHaveBeenCalled())
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)).toBeNull();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it('bloquea doble envío de identidad mientras espera respuesta',async()=>{
    let resolver!:(v:{inversionista_id:string;lead_id:string;solicitud_id:null})=>void
    api.persona.mockImplementationOnce(()=>new Promise(r=>{resolver=r}))
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    fireEvent.submit(screen.getByRole('button',{name:'Verificando…'}).closest('form')!)
    expect(api.persona).toHaveBeenCalledOnce()
    resolver({inversionista_id:PERSONA_F5,lead_id:LEAD,solicitud_id:null})
    await screen.findByRole('button',{name:'Avance'})
  })
})
