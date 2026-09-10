import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest'
import {act, cleanup, fireEvent, render, screen, waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {QueryClient, QueryClientProvider} from '@tanstack/react-query'
import {CarteraInversionistas} from './cartera-inversionistas'
import {InversionNueva} from '@/components/app/inversion-nueva'
import {CrmApiError} from '@/data/crm-api'
import {ACTOR_F5, carteraF5, fichaF5, FUENTE_F5, PERSONA_F5, PERFIL_F5} from '@/test/fixtures/f5'
import {inversionistasKeys} from '@/data/inversionistas-queries'
import {leerIntentoInversion, guardarIntentoInversion, nuevoIntentoInversion, type SolicitudInversion} from '@/lib/inversion-solicitud'

vi.mock('@/data/postventa-api', () => ({estadoPostventa: vi.fn().mockResolvedValue({version: 1, habilitada: false})}))

const api = vi.hoisted(() => ({lista:vi.fn(), ficha:vi.fn(), bancos:vi.fn(), documento:vi.fn(), consultar:vi.fn(), preparar:vi.fn(),
  corregir:vi.fn(), responsable:vi.fn(), confirmar:vi.fn(), acceso:vi.fn(), subir:vi.fn()}))
vi.mock('@/data/inversionistas-api', () => ({listarInversionistas:api.lista, obtenerFichaInversionista:api.ficha,
  obtenerCuentasInversionista:api.bancos, descargarDocumentoInversionista:api.documento}))
vi.mock('@/data/inversion-solicitud-api', () => ({consultarSolicitudInversion:api.consultar, prepararSolicitudInversion:api.preparar,
  corregirSolicitudInversion:api.corregir, revisarResponsableInversion:api.responsable, confirmarSolicitudInversion:api.confirmar,
  completarAccesoInversion:api.acceso, subirComprobanteInversion:api.subir}))
vi.mock('@/lib/store-context', () => ({useCRMData:()=>({equipo:[]})}))
const revocado = vi.fn(), confirmada = vi.fn(), cerrar = vi.fn()
function montar(nueva=false) {
  const qc=new QueryClient({defaultOptions:{queries:{retry:false}}})
  const vista=render(<QueryClientProvider client={qc}>{nueva
    ? <InversionNueva actor={ACTOR_F5} persona={PERSONA_F5} onCerrar={cerrar} onRevocado={revocado} onConfirmada={confirmada} />
    : <CarteraInversionistas actor={ACTOR_F5} permiteInversion gestionAvance={<p>Gestión existente</p>} />}</QueryClientProvider>)
  return {...vista,qc,user:userEvent.setup()}
}
const resultado = {ok:true as const,solicitud_id:FUENTE_F5,inversion_id:FUENTE_F5,inversionista_id:PERSONA_F5,empresa:'qorilazo' as const,fuente:{cierre_id:FUENTE_F5}}
const solicitud = (id=FUENTE_F5): SolicitudInversion => ({solicitud_id:id,estado:'preparada',inversion_id:null,
  inversionista_id:PERSONA_F5,inversionista_origen_id:PERSONA_F5,identidad_fusionada:false,responsable_esperado_id:ACTOR_F5,
  responsable_actual_id:ACTOR_F5,requiere_revision_responsable:false,revision_datos:0,revision_responsable:0,hash_datos:'hash',
  necesita_portal:false,comprobante_bucket:'f4-comprobantes',comprobante_ruta:`${PERSONA_F5}/${id}/comprobante.pdf`,resultado:null})
beforeEach(() => {
  vi.clearAllMocks(); sessionStorage.clear(); history.replaceState(null, '', '#/mi-cartera')
  api.lista.mockResolvedValue(structuredClone(carteraF5)); api.ficha.mockResolvedValue(structuredClone(fichaF5)); api.bancos.mockResolvedValue([])
})
afterEach(() => {cleanup(); vi.restoreAllMocks()})
describe('F5: cartera y ficha con acceso vigente', () => {
  it('filtra en servidor, conserva consulta al cerrar y mantiene paginación visible',async () => {
    const {user}=montar()
    await user.type(screen.getByLabelText('Buscar persona'),'9333')
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0].texto).toBe('9333'))
    expect(screen.getByRole('navigation',{name:'Paginación de inversionistas'})).toBeInTheDocument()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByText('Identidad y responsable')
    expect(screen.queryByText('Cuentas de pago Avance')).not.toBeInTheDocument()
    expect(api.bancos).not.toHaveBeenCalled()
    await user.click(screen.getAllByRole('button',{name:'Cerrar ficha'})[0]!)
    expect(screen.getByLabelText('Buscar persona')).toHaveValue('9333')
  })
  it('la ficha no pinta PII de la lista mientras espera su propia respuesta',async () => {
    let resolver!: (v:typeof fichaF5)=>void
    api.ficha.mockReturnValue(new Promise(r=>{resolver=r}))
    const {user}=montar(); await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    expect(screen.queryByText('ana.f5@pruebas.example')).not.toBeInTheDocument()
    await act(async()=>resolver(fichaF5))
    expect(await screen.findByText('ana.f5@pruebas.example')).toBeInTheDocument()
  })
  it('revocación borra datos bancarios, intención y ficha aunque llegue tarde otra consulta',async () => {
    const intento=nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,{inversionista_id:PERSONA_F5,empresa:'qorilazo'})
    guardarIntentoInversion(intento)
    guardarIntentoInversion(nuevoIntentoInversion(ACTOR_F5,FUENTE_F5,FUENTE_F5,{inversionista_id:FUENTE_F5,empresa:'prodelco'}))
    const {user,qc}=montar(); await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByText('ana.f5@pruebas.example')
    api.ficha.mockRejectedValue(new CrmApiError('Revocado','42501'))
    api.lista.mockResolvedValue({...carteraF5,total:0,filas:[],totales:[]})
    await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    await waitFor(()=>expect(screen.queryByText('ana.f5@pruebas.example')).not.toBeInTheDocument())
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5)).toBeNull()
    expect(leerIntentoInversion(ACTOR_F5,FUENTE_F5)).not.toBeNull()
    expect(screen.getByText(/Referencia de la solicitud pendiente:/)).toHaveTextContent(FUENTE_F5)
    expect(qc.getQueriesData({queryKey:[...inversionistasKeys.actor(ACTOR_F5),'persona']})).toEqual([])
  })
  it('cancelar una descarga al abrir una inversión no bloquea la siguiente descarga',async()=>{
    const d=structuredClone(fichaF5);d.inversiones[0]!.documentos=[{id:FUENTE_F5,nombre:'Documento del ensayo',tipo:'comprobante'}]
    api.ficha.mockResolvedValue(d)
    api.documento.mockImplementationOnce((_p,_f,_d,signal:AbortSignal)=>new Promise((_r,reject)=>{
      signal.addEventListener('abort',()=>reject(new DOMException('Cancelada','AbortError')),{once:true})
    })).mockResolvedValue(undefined)
    const {user}=montar();await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Documento del ensayo'}))
    await user.click(screen.getByRole('button',{name:'Nueva inversión'}))
    await user.click(await screen.findByRole('button',{name:'Cerrar y continuar después'}))
    await user.click(await screen.findByRole('button',{name:'Documento del ensayo'}))
    await waitFor(()=>expect(api.documento).toHaveBeenCalledTimes(2))
    expect(screen.queryByText('Comprobando acceso y descargando documento…')).not.toBeInTheDocument()
  })
  it('actualizar la ficha no desmonta ni vuelve a cargar las cuentas abiertas',async()=>{
    const d=structuredClone(fichaF5);d.capacidades.cuentas_perfil_ids=[PERFIL_F5]
    api.ficha.mockResolvedValue(d)
    const {user,qc}=montar();await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByLabelText(/Cuentas de pago Avance\. Cuentas autorizadas/))
    await waitFor(()=>expect(api.bancos).toHaveBeenCalledTimes(2))
    await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    expect(api.bancos).toHaveBeenCalledTimes(2)
  })
  it('un error no se convierte en total cero ni conserva el capital como vigente',async () => {
    api.lista.mockRejectedValue(new CrmApiError('Sin respuesta','RED'))
    montar(); await screen.findByText('Sin respuesta')
    expect(screen.queryByText(/0 personas/)).not.toBeInTheDocument()
    expect(screen.queryByText('Capital registrado')).not.toBeInTheDocument()
  })
})
describe('F5: revisión y recuperación económica', () => {
  it('un borrador ilegible permite recuperar por referencia antes de cualquier nueva alta',async()=>{
    sessionStorage.setItem(`crm:f5:solicitud:${ACTOR_F5}:${PERSONA_F5}`,'{ilegible')
    const datos={inversionista_id:PERSONA_F5,empresa:'qorilazo' as const,monto:1000,moneda:'PEN' as const}
    api.consultar.mockResolvedValue({...solicitud(),datos})
    const {user}=montar(true)
    await user.type(await screen.findByLabelText('Retomar una solicitud por su referencia'),FUENTE_F5)
    await user.click(screen.getByRole('button',{name:'Consultar solicitud'}))
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5)?.clave).toBe(FUENTE_F5)
    expect(api.preparar).not.toHaveBeenCalled();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it('una corrección con respuesta perdida conserva su UUID y contenido al recargar',async () => {
    const datos={inversionista_id:PERSONA_F5,empresa:'qorilazo' as const,monto:1000,moneda:'PEN' as const}
    const intento={...nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,datos),
      correccion:{clave:crypto.randomUUID(),revision:4,datos:{...datos,monto:2000},motivo:'Corregir el importe revisado'}}
    guardarIntentoInversion(intento)
    api.consultar.mockResolvedValue({...solicitud(),revision_datos:5,datos:intento.correccion.datos})
    api.corregir.mockResolvedValue({...solicitud(),revision_datos:5,datos:intento.correccion.datos})
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Recuperar actualización pendiente'}))
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(api.corregir).toHaveBeenCalledWith(intento)
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5)?.correccion).toBeUndefined()
    expect(api.preparar).not.toHaveBeenCalled();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it('una ficha nula por reasignación también revoca el formulario de inversión',async () => {
    api.ficha.mockResolvedValue(null)
    montar(true)
    await waitFor(()=>expect(revocado).toHaveBeenCalled())
    expect(api.preparar).not.toHaveBeenCalled();expect(api.confirmar).not.toHaveBeenCalled()
  })
  it('prepara sin éxito anticipado, confirma con revisión devuelta y recupera un corte sin otra alta',async () => {
    let vigente=solicitud()
    api.preparar.mockImplementation(async intento=> {vigente={...solicitud(intento.clave),revision_datos:3,datos:intento.datos}; return vigente})
    api.consultar.mockImplementation(async()=>vigente)
    api.confirmar.mockImplementation(async()=> {vigente={...vigente,estado:'confirmada',resultado:{...resultado,solicitud_id:vigente.solicitud_id}}; throw new CrmApiError('Respuesta perdida','RED')})
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Qorilazo'}))
    await user.type(screen.getByLabelText('Capital en soles (PEN)'),'2500')
    await user.type(screen.getByLabelText('Número de operación del depósito'),'F5-DEP-001')
    await user.clear(screen.getByLabelText('Fecha comercial')); await user.type(screen.getByLabelText('Fecha comercial'),'2026-09-01')
    await user.type(screen.getByLabelText('Vencimiento'),'2027-09-01')
    await user.type(screen.getByLabelText('Referencia de la inversión'),'REFERENCIA SINTÉTICA')
    await user.upload(screen.getByLabelText(/Comprobante PDF/),new File(['pdf sintético'],'prueba.pdf',{type:'application/pdf'}))
    expect((screen.getByLabelText(/Comprobante PDF/) as HTMLInputElement).files).toHaveLength(1)
    // JSDOM 29 no considera el FileList de userEvent al validar required.
    // Playwright cubre el submit nativo con un archivo real del navegador.
    fireEvent.submit(screen.getByRole('button',{name:'Revisar inversión'}).closest('form')!)
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(confirmada).not.toHaveBeenCalled(); expect(api.confirmar).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button',{name:'Confirmar inversión'}))
    expect(api.confirmar).toHaveBeenCalledWith(vigente.solicitud_id,3)
    await screen.findByText('Respuesta perdida')
    expect(screen.queryByText('Inversión confirmada')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Actualizar revisión'}))
    await screen.findByText('Inversión confirmada')
    expect(api.preparar).toHaveBeenCalledTimes(1); expect(api.confirmar).toHaveBeenCalledTimes(1)
    expect(confirmada).toHaveBeenCalledTimes(1)
  })
  it('una recarga consulta el UUID guardado y espera revisión vigente antes de confirmar',async () => {
    const datos={inversionista_id:PERSONA_F5,empresa:'qorilazo' as const,monto:1000,moneda:'PEN' as const,fecha_comercial:'2026-09-01',vence_en:'2027-09-01',numero_transaccion:'F5-REANUDAR',referencia:'ENSAYO'}
    guardarIntentoInversion(nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,datos))
    api.consultar.mockResolvedValue({...solicitud(),revision_datos:8,datos})
    api.confirmar.mockResolvedValue(resultado)
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Confirmar inversión'}))
    expect(api.consultar).toHaveBeenCalledWith(FUENTE_F5,expect.any(AbortSignal))
    expect(api.confirmar).toHaveBeenCalledWith(FUENTE_F5,8)
    expect(api.preparar).not.toHaveBeenCalled()
  })
})
