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
  corregir:vi.fn(),confirmar:vi.fn(),cancelar:vi.fn(),acceso:vi.fn(),subir:vi.fn(),bienvenida:vi.fn(),convertirAnterior:vi.fn(),documento:vi.fn()}))
vi.mock('@/data/documento-lead',()=>({useDocumentoLead:api.documento}))
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
let correoFicha:string|null
const preparada=(clave:string,datos:DatosInversion):SolicitudInversion=>({solicitud_id:clave,lead_id:LEAD,estado:'preparada',
  inversion_id:null,inversionista_id:PERSONA_F5,inversionista_origen_id:PERSONA_F5,identidad_fusionada:false,
  responsable_esperado_id:ACTOR_F5,responsable_actual_id:ACTOR_F5,requiere_revision_responsable:false,
  revision_datos:0,revision_responsable:0,hash_datos:'huella',necesita_portal:datos.empresa==='avance'&&!perfil,
  comprobante_bucket:datos.empresa==='avance'?null:'f4-comprobantes',comprobante_ruta:datos.evidencia?.ruta??null,resultado:null,datos})
beforeEach(()=>{
  vi.resetAllMocks();sessionStorage.clear();vigente=null;perfil=null;correoFicha=fichaF5.persona.correo
  api.documento.mockImplementation((l:Lead)=>({data:{lead_id:l.id,inversionista_id:null,identificador_id:null,
    tipo:l.documento?.tipo??'DNI',numero:l.documento?.numero??l.dni??null,puede_corregir:false},isPending:false,isError:false}))
  api.persona.mockImplementation(async(leadId:string)=>({inversionista_id:PERSONA_F5,lead_id:leadId,solicitud_id:vigente?.solicitud_id??null}))
  api.contexto.mockImplementation(async()=>({...fichaF5,solicitud_id:vigente?.solicitud_id??null,documento_tipo:'DNI',persona:{...fichaF5.persona,perfil_id:perfil,correo:correoFicha}}))
  api.cancelar.mockImplementation(async()=>{vigente={...vigente!,estado:'cancelada'};return vigente})
  api.preparar.mockImplementation(async i=>{vigente=preparada(i.clave,i.datos);if(i.datos.alta_portal)correoFicha=i.datos.alta_portal.correo;return vigente})
  api.consultar.mockImplementation(async()=>{if(!vigente)throw new CrmApiError('Solicitud no encontrada','P0002');return vigente})
  api.corregir.mockImplementation(async i=>{vigente={...vigente!,datos:i.correccion.datos,revision_datos:vigente!.revision_datos+1,necesita_portal:!perfil};if(i.correccion.datos.alta_portal)correoFicha=i.correccion.datos.alta_portal.correo;return vigente})
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

describe('Documento vinculado al convertir',()=>{
  it.each([['CE','001234567'],['PASAPORTE','AB12345678']] as const)('precarga y utiliza %s aunque el DNI legado esté vacío',async(tipo,numero)=>{
    api.documento.mockReturnValue({data:{lead_id:LEAD,tipo,numero,inversionista_id:PERSONA_F5,identificador_id:FUENTE_F5,puede_corregir:false}})
    const {user}=montar({dni:null})
    expect(screen.getByLabelText('Tipo de documento')).toHaveValue(tipo)
    expect(screen.getByLabelText('Documento')).toHaveValue(numero)
    expect(screen.getByLabelText('Documento')).toBeDisabled()
    await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    expect(api.persona).toHaveBeenCalledWith(LEAD,tipo,numero,lead.nombre_completo)
  })

  it('un error al consultar identidad no permite convertir con el DNI antiguo',()=>{
    api.documento.mockReturnValue({data:undefined,isError:true,refetch:vi.fn()})
    montar()
    expect(screen.getByText(/No se pudo consultar el documento vinculado/)).toBeInTheDocument()
    expect(screen.queryByRole('button',{name:'Continuar a Nueva inversión'})).not.toBeInTheDocument()
    expect(api.persona).not.toHaveBeenCalled()
  })
})
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
function llenarAcceso(datos: Partial<{nombres:string;apellidos:string;correo:string;telefono:string}> = {}) {
  for (const [etiqueta, valor] of Object.entries({Apellidos: datos.apellidos ?? 'PRUEBA', Nombres: datos.nombres ?? 'PERSONA',
    'Correo de acceso Avance': datos.correo ?? 'persona@example.invalid', 'Teléfono': datos.telefono ?? '999123456',
    'Domicilio legal': 'AVENIDA SINTETICA 123 LIMA'})) {
    fireEvent.change(screen.getByLabelText(etiqueta, {exact:true}), {target:{value:valor}})
  }
}
describe('Recuperar el primer acceso rechazado',()=>{
  it('normaliza espacios copiados antes de enviar los nombres legales',async()=>{
    const {user}=montar();await entrar(user,'Avance')
    llenarAcceso({nombres:'  PERSONA\t SEGUNDA  ',apellidos:'  PRUEBA\u00a0 APELLIDO  '})
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(vigente?.datos?.alta_portal).toMatchObject({nombres:'PERSONA SEGUNDA',apellidos:'PRUEBA APELLIDO',
      nombre_completo:'PERSONA SEGUNDA PRUEBA APELLIDO'})
    expect(api.acceso).not.toHaveBeenCalled();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it.each([
    [{nombres:'PERSONA\u0001'},'Nombres','caracteres no válidos'],
    [{nombres:'A'.repeat(130),apellidos:'B'.repeat(130)},'Nombres','240 caracteres'],
    [{correo:'persona\u0001@example.invalid'},'Correo de acceso Avance','correo de acceso válido'],
  ])('explica datos que el servidor rechazaría sin guardar un intento: %j',async(datos,campo,mensaje)=>{
    const {user}=montar();await entrar(user,'Avance');llenarAcceso(datos)
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(screen.getByLabelText(campo)).toHaveAttribute('aria-invalid','true')
    expect(screen.getByRole('alert')).toHaveTextContent(mensaje)
    expect(api.preparar).not.toHaveBeenCalled();expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)).toBeNull()
  })
  it('22023 permite corregir tras confirmar ausencia y conserva clave y token',async()=>{
    api.preparar.mockRejectedValueOnce(new CrmApiError('Completa el nombre legal y un correo válido para el acceso Avance','22023'))
    const {user}=montar();await entrar(user,'Avance');llenarAcceso()
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(await screen.findByRole('alert')).toHaveTextContent('Completa el nombre legal')
    expect(screen.getByLabelText('Nombres')).toHaveValue('PERSONA')
    expect(screen.getByLabelText('Domicilio legal')).toHaveValue('AVENIDA SINTETICA 123 LIMA')
    expect(screen.getByText(/La solicitud aún no está registrada/)).toBeInTheDocument()
    const primero=leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)!
    expect(api.consultar).toHaveBeenCalledWith(primero.clave)
    fireEvent.change(screen.getByLabelText('Correo de acceso Avance'),{target:{value:'corregido@example.invalid'}})
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    const segundo=api.preparar.mock.calls[1]![0]
    expect(segundo).toMatchObject({clave:primero.clave,token:primero.token,datos:{alta_portal:{correo:'corregido@example.invalid'}}})
    expect(api.preparar).toHaveBeenCalledTimes(2);expect(api.corregir).not.toHaveBeenCalled()
    expect(api.acceso).not.toHaveBeenCalled();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it('un intento antiguo inválido vuelve a campos editables sin reenviarlo automáticamente',async()=>{
    const guardado=nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,
      empresa:'avance',contrato:{moneda:'PEN'},cronograma:[],cuenta:{},alta_portal:{nombres:'PERSONA\tSEGUNDA',apellidos:'PRUEBA',
        nombre_completo:'PERSONA\tSEGUNDA PRUEBA',correo:'',telefono:'999123456',domicilio:'AVENIDA SINTETICA 123 LIMA'}})
    guardarIntentoInversion(guardado)
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    expect(await screen.findByLabelText('Nombres')).toHaveValue('PERSONA\tSEGUNDA')
    expect(api.preparar).not.toHaveBeenCalled()
    fireEvent.change(screen.getByLabelText('Correo de acceso Avance'),{target:{value:'corregido@example.invalid'}})
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(api.preparar).toHaveBeenCalledWith(expect.objectContaining({clave:guardado.clave,token:guardado.token}))
    expect(vigente?.datos?.alta_portal?.nombre_completo).toBe('PERSONA SEGUNDA PRUEBA')
  })
  it('una consulta incierta mantiene recuperación hasta comprobar que no existe',async()=>{
    api.preparar.mockRejectedValueOnce(new CrmApiError('Datos no válidos','22023'))
    api.consultar.mockRejectedValueOnce(new TypeError('Conexión interrumpida'))
    const {user}=montar();await entrar(user,'Avance');llenarAcceso()
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('heading',{name:'Recuperar solicitud'})
    expect(screen.queryByLabelText('Nombres')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Consultar y recuperar'}))
    expect(await screen.findByLabelText('Nombres')).toHaveValue('PERSONA')
    expect(api.preparar).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
  })
  it('recupera una escritura confirmada cuya respuesta se perdió sin preparar otra',async()=>{
    api.preparar.mockImplementationOnce(async i=>{vigente=preparada(i.clave,i.datos);correoFicha=i.datos.alta_portal.correo;throw new TypeError('Respuesta perdida')})
    const {user}=montar();await entrar(user,'Avance');llenarAcceso()
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await user.click(await screen.findByRole('button',{name:'Consultar y recuperar'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(api.preparar).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
  })
  it('si otro envío registra la misma clave durante la edición, recupera los datos del servidor',async()=>{
    api.preparar.mockRejectedValueOnce(new CrmApiError('Datos no válidos','22023'))
    const {user}=montar();await entrar(user,'Avance');llenarAcceso()
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByLabelText('Nombres')
    const primero=leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)!
    vigente=preparada(primero.clave,primero.datos);correoFicha=primero.datos.alta_portal!.correo
    api.preparar.mockRejectedValueOnce(new CrmApiError('Clave ya utilizada','P0409'))
    fireEvent.change(screen.getByLabelText('Correo de acceso Avance'),{target:{value:'nuevo@example.invalid'}})
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(screen.getByText('persona@example.invalid')).toBeInTheDocument()
    expect(screen.queryByText('nuevo@example.invalid')).not.toBeInTheDocument()
    expect(api.preparar.mock.calls[1]![0].clave).toBe(primero.clave)
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)?.datos).toEqual(vigente!.datos)
    expect(api.acceso).not.toHaveBeenCalled();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it('un conflicto de otra inversión conserva el error sin invitar a corregir datos',async()=>{
    api.preparar.mockRejectedValueOnce(new CrmApiError('Ya existe otra inversión en preparación','P0409'))
    const {user}=montar();await entrar(user,'Avance');llenarAcceso()
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(await screen.findByRole('alert')).toHaveTextContent('Ya existe otra inversión')
    expect(screen.queryByLabelText('Nombres')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Consultar y recuperar'}))
    expect(screen.queryByLabelText('Nombres')).not.toBeInTheDocument()
    expect(screen.queryByText(/La solicitud aún no está registrada/)).not.toBeInTheDocument()
    expect(api.preparar).toHaveBeenCalledOnce()
  })
  it.each([false,true])('retoma otra solicitud existente del lead sin reenviar el intento local (reapertura=%s)',async(reabrir)=>{
    const otraClave='77777777-7777-4777-8777-777777777777'
    api.preparar.mockImplementationOnce(async i=>{
      vigente=preparada(otraClave,i.datos);correoFicha=i.datos.alta_portal.correo
      throw new CrmApiError('Este lead ya tiene una solicitud: retómala antes de crear otra','P0409')
    })
    api.consultar.mockImplementation(async id=>{
      if(id!==vigente?.solicitud_id)throw new CrmApiError('Solicitud no encontrada','P0002')
      return vigente
    })
    const primera=montar();await entrar(primera.user,'Avance');llenarAcceso()
    await primera.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Retomar solicitud registrada'})
    let user=primera.user
    if(reabrir){
      primera.unmount();user=montar().user
      await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
      await screen.findByRole('button',{name:'Retomar solicitud registrada'})
    }
    expect(screen.queryByLabelText('Nombres')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Retomar solicitud registrada'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)?.clave).toBe(otraClave)
    expect(api.preparar).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
  })
  it('conserva el token del primer envío si la lectura falla con 22023 después de guardar',async()=>{
    api.preparar.mockImplementationOnce(async i=>{
      vigente=preparada(i.clave,i.datos);correoFicha=i.datos.alta_portal.correo
      throw new CrmApiError('Lectura rechazada después de preparar','22023')
    })
    const {user}=montar();await entrar(user,'Avance');llenarAcceso()
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)).toMatchObject(api.preparar.mock.calls[0]![0])
    expect(screen.queryByLabelText('Nombres')).not.toBeInTheDocument()
    expect(api.preparar).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
  })
  it('un permiso revocado durante la recuperación cierra el flujo sin habilitar edición',async()=>{
    api.preparar.mockRejectedValueOnce(new CrmApiError('Datos no válidos','22023'))
    api.consultar.mockRejectedValueOnce(new CrmApiError('Acceso revocado','42501'))
    const {user,onClose}=montar();await entrar(user,'Avance');llenarAcceso()
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await waitFor(()=>expect(onClose).toHaveBeenCalledOnce())
    expect(screen.queryByLabelText('Nombres')).not.toBeInTheDocument()
    expect(api.preparar).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
  })
})
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
  function prepararAccesoPendiente(correo='anterior@example.invalid') {
    vigente=preparada(FUENTE_F5,{inversionista_id:PERSONA_F5,lead_id:LEAD,empresa:'avance',
      contrato:{moneda:'PEN'},cronograma:[],cuenta:{},alta_portal:{correo,nombre_completo:'PERSONA PRUEBA',
      nombres:'PERSONA',apellidos:'PRUEBA',telefono:'999123456',domicilio:'AVENIDA SINTETICA 123 LIMA'}})
    correoFicha=correo
  }
  it('una ficha corregida exige revisar el correo actualizado antes de crear acceso',async()=>{
    prepararAccesoPendiente()
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    vigente={...vigente!,revision_datos:1,datos:{...vigente!.datos!,alta_portal:{...vigente!.datos!.alta_portal!,correo:'actualizado@example.invalid'}}}
    correoFicha='actualizado@example.invalid'
    await user.click(screen.getByRole('button',{name:'Completar acceso Avance'}))
    expect(await screen.findByRole('alert')).toHaveTextContent('Revisa el correo actualizado')
    expect(api.acceso).not.toHaveBeenCalled()
    expect(screen.getByText('actualizado@example.invalid')).toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Completar acceso Avance'}))
    await screen.findByRole('heading',{name:'Condiciones del contrato compartido'})
    expect(api.acceso).toHaveBeenCalledOnce()
  })
  it('Auth ya creado sin perfil permite recuperar aunque cambió el correo de contacto',async()=>{
    prepararAccesoPendiente()
    vigente={...vigente!,acceso_creado:true}
    correoFicha='contacto-nuevo@example.invalid'
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    expect(await screen.findByRole('button',{name:'Completar acceso Avance'})).toBeEnabled()
    expect(screen.getByText(/El acceso ya fue creado con este correo/)).toBeInTheDocument()
    expect(screen.queryByRole('button',{name:'Corregir datos de acceso'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button',{name:'Usar correo de la ficha'})).not.toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Completar acceso Avance'}))
    await screen.findByRole('heading',{name:'Condiciones del contrato compartido'})
    expect(api.acceso).toHaveBeenCalledOnce();expect(api.corregir).not.toHaveBeenCalled()
  })
  it.each(['Usar correo de la ficha','Conservar correo de la solicitud'])('solicitud antigua con correos distintos permite decidir: %s',async(boton)=>{
    prepararAccesoPendiente();correoFicha='ficha-nueva@example.invalid'
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    expect(await screen.findByRole('button',{name:'Completar acceso Avance'})).toBeDisabled()
    await user.click(screen.getByRole('button',{name:boton}))
    await waitFor(()=>expect(screen.getByRole('button',{name:'Completar acceso Avance'})).not.toBeDisabled())
    const esperado=boton==='Usar correo de la ficha'?'ficha-nueva@example.invalid':'anterior@example.invalid'
    expect(vigente!.datos!.alta_portal!.correo).toBe(esperado);expect(correoFicha).toBe(esperado)
    expect(api.corregir).toHaveBeenCalledOnce();expect(api.acceso).not.toHaveBeenCalled()
  })
  it('un borrador anterior muestra el correo actual de la ficha y permite usarlo',async()=>{
    prepararAccesoPendiente()
    const primera=montar();await primera.user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await primera.user.click(await screen.findByRole('button',{name:'Corregir datos de acceso'}))
    await primera.user.type(screen.getByLabelText('Nombres',{exact:true}),' EXTRA')
    primera.unmount()
    correoFicha='ficha-actual@example.invalid'
    vigente={...vigente!,revision_datos:1,datos:{...vigente!.datos!,alta_portal:{...vigente!.datos!.alta_portal!,correo:correoFicha}}}
    const segunda=montar();await segunda.user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    expect(await screen.findByLabelText('Correo de acceso Avance')).toHaveValue('anterior@example.invalid')
    expect(screen.getByText('ficha-actual@example.invalid')).toBeInTheDocument()
    await segunda.user.click(screen.getByRole('button',{name:'Usar correo de la ficha'}))
    expect(screen.getByLabelText('Correo de acceso Avance')).toHaveValue('ficha-actual@example.invalid')
    expect(screen.getByLabelText('Nombres',{exact:true})).toHaveValue('PERSONA EXTRA')
    await segunda.user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('button',{name:'Completar acceso Avance'})
    expect(vigente!.datos!.alta_portal!.correo).toBe(correoFicha)
  })
  it.each(['P0409','PT409','22023','P0429','55P03'])('rechazo definitivo %s conserva lo escrito y permite volver a corregir',async(codigo)=>{
    prepararAccesoPendiente()
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await user.click(await screen.findByRole('button',{name:'Corregir datos de acceso'}))
    await user.clear(screen.getByLabelText('Correo de acceso Avance'))
    await user.type(screen.getByLabelText('Correo de acceso Avance'),'corregido@example.invalid')
    api.corregir.mockRejectedValueOnce(new CrmApiError('Revisa el acceso pendiente',codigo))
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(await screen.findByRole('alert')).toHaveTextContent('Revisa el acceso pendiente')
    expect(screen.queryByRole('heading',{name:'Actualización pendiente'})).not.toBeInTheDocument()
    expect(screen.getByLabelText('Correo de acceso Avance')).toHaveValue('corregido@example.invalid')
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)?.correccion).toBeUndefined()
    expect(api.acceso).not.toHaveBeenCalled()
  })
  it('una respuesta incierta conserva la corrección pendiente para recuperarla',async()=>{
    prepararAccesoPendiente()
    const {user}=montar();await user.click(screen.getByRole('button',{name:'Continuar a Nueva inversión'}))
    await user.click(await screen.findByRole('button',{name:'Corregir datos de acceso'}))
    await user.clear(screen.getByLabelText('Correo de acceso Avance'))
    await user.type(screen.getByLabelText('Correo de acceso Avance'),'corregido@example.invalid')
    api.corregir.mockRejectedValueOnce(new Error('Conexión interrumpida'))
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    await screen.findByRole('heading',{name:'Actualización pendiente'})
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5,LEAD)?.correccion?.datos.alta_portal?.correo).toBe('corregido@example.invalid')
    expect(api.acceso).not.toHaveBeenCalled()
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
