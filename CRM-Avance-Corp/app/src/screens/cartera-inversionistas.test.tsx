import {ContratoEliminacionError} from '@/lib/contrato-pdf-archivo'
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest'
import {act, cleanup, fireEvent, render, screen, waitFor, within} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {QueryClient, QueryClientProvider} from '@tanstack/react-query'
import {toast} from 'sonner'
import {CarteraInversionistas} from './cartera-inversionistas'
import {InversionNueva, type OperacionInversion} from '@/components/app/inversion-nueva'
import {InversionistaFicha} from '@/components/app/inversionista-ficha'
import {Sheet} from '@/components/ui/sheet'
import {CrmApiError} from '@/data/crm-api'
import {crmQueryKeys} from '@/data/crm-queries'
import {postventaKeys} from '@/data/postventa-queries'
import {ACTOR_F5, carteraF5, fichaF5, FUENTE_F5, inversionF5, PERSONA_F5, PERFIL_F5} from '@/test/fixtures/f5'
import {EMPRESA_NOMBRE, type InversionFuente, type ResumenEmpresa} from '@/lib/inversionistas'
import {inversionistasKeys} from '@/data/inversionistas-queries'
import {leerIntentoInversion, guardarIntentoInversion, nuevoIntentoInversion, type SolicitudInversion} from '@/lib/inversion-solicitud'

vi.mock('@/data/postventa-api', () => ({estadoPostventa: vi.fn().mockResolvedValue({version: 1, habilitada: false}), fichaPostventa: (...args: unknown[]) => api.postventa(...args)}))
const sesion = vi.hoisted(() => ({rolPortal: 'directorio', rol:'gerencia', demo: false, puedeContratar:false}))
vi.mock('@/lib/auth-context', () => ({useAuth: () => ({yo: {id: ACTOR_F5, rol: sesion.rol, rol_portal: sesion.rolPortal, demo: sesion.demo, puede_contratar:sesion.puedeContratar}})}))

const api = vi.hoisted(() => ({lista:vi.fn(), ficha:vi.fn(), bancos:vi.fn(), documento:vi.fn(), consultar:vi.fn(), preparar:vi.fn(),
  corregir:vi.fn(), responsable:vi.fn(), confirmar:vi.fn(), acceso:vi.fn(), subir:vi.fn(), postventa:vi.fn(), eliminar:vi.fn(),
  buscarCliente:vi.fn(), eliminarInversion:vi.fn()}))
vi.mock('@/data/crm-api', async (original) => ({...await original<typeof import('@/data/crm-api')>(), eliminarInversion:api.eliminarInversion}))
vi.mock('@/data/cliente-existente-api', () => ({buscarClienteExistente:api.buscarCliente, obtenerContextoClienteExistente:vi.fn(),
  cuentasClienteExistente:vi.fn(), datosLegalesClienteExistente:vi.fn(), contratosUpgradeClienteExistente:vi.fn()}))
vi.mock('@/lib/contrato-pdf-archivo', async (original) => ({...await original<typeof import('@/lib/contrato-pdf-archivo')>(), eliminarContratoConPdf:api.eliminar}))
vi.mock('@/data/inversionistas-api', () => ({listarInversionistas:api.lista, obtenerFichaInversionista:api.ficha,
  obtenerCuentasInversionista:api.bancos, descargarDocumentoInversionista:api.documento}))
vi.mock('@/data/inversion-solicitud-api', () => ({consultarSolicitudInversion:api.consultar, prepararSolicitudInversion:api.preparar,
  corregirSolicitudInversion:api.corregir, revisarResponsableInversion:api.responsable, confirmarSolicitudInversion:api.confirmar,
  completarAccesoInversion:api.acceso, subirComprobanteInversion:api.subir}))
vi.mock('@/lib/store-context', () => ({useCRMData:()=>({equipo:[]})}))
const revocado = vi.fn(), confirmada = vi.fn(), cerrar = vi.fn()
function montar(nueva=false, operacion?: OperacionInversion) {
  const qc=new QueryClient({defaultOptions:{queries:{retry:false}}})
  const vista=render(<QueryClientProvider client={qc}>{nueva
    ? <InversionNueva actor={ACTOR_F5} persona={PERSONA_F5} operacion={operacion} onCerrar={cerrar} onRevocado={revocado} onConfirmada={confirmada} />
    : <CarteraInversionistas actor={ACTOR_F5} permiteInversion />}</QueryClientProvider>)
  return {...vista,qc,user:userEvent.setup()}
}
const resultado = {ok:true as const,solicitud_id:FUENTE_F5,inversion_id:FUENTE_F5,inversionista_id:PERSONA_F5,empresa:'qorilazo' as const,fuente:{cierre_id:FUENTE_F5}}
const solicitud = (id=FUENTE_F5): SolicitudInversion => ({solicitud_id:id,estado:'preparada',inversion_id:null,
  inversionista_id:PERSONA_F5,inversionista_origen_id:PERSONA_F5,identidad_fusionada:false,responsable_esperado_id:ACTOR_F5,
  responsable_actual_id:ACTOR_F5,requiere_revision_responsable:false,revision_datos:0,revision_responsable:0,hash_datos:'hash',
  necesita_portal:false,comprobante_bucket:'f4-comprobantes',comprobante_ruta:`${PERSONA_F5}/${id}/comprobante.pdf`,resultado:null})
beforeEach(() => {
  vi.clearAllMocks(); sesion.rolPortal='directorio'; sesion.rol='gerencia'; sesion.demo=false; sesion.puedeContratar=false; sessionStorage.clear(); history.replaceState(null, '', '#/mi-cartera')
  api.postventa.mockResolvedValue({version:1,habilitada:true,retiros:[]})
  api.lista.mockResolvedValue(structuredClone(carteraF5)); api.ficha.mockResolvedValue(structuredClone(fichaF5)); api.bancos.mockResolvedValue([])
})
afterEach(() => {cleanup(); vi.restoreAllMocks()})
describe('F5: cartera y ficha con acceso vigente', () => {
  it.each([
    ['gerencia',true,true],['supervisor',true,true],['analista',true,false],
    ['directorio',true,false],['gerencia',false,false],
  ] as const)('alta directa: rol %s, capacidad %s muestra acceso %s', async (rol,capacidad,visible) => {
    sesion.rol=rol;sesion.rolPortal='comercial';sesion.puedeContratar=capacidad
    montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    const alta=screen.queryByRole('button',{name:'Nuevo cliente'})
    if(visible) expect(alta).toBeEnabled()
    else expect(alta).not.toBeInTheDocument()
    expect(screen.queryByRole('button',{name:'Gestión Avance'})).not.toBeInTheDocument()
  })

  it('recupera la jerarquía Ficha 360 y lee el vencimiento de toda la ficha, no solo de la página', async () => {
    const d=structuredClone(fichaF5)
    d.persona.telefono='+51999888777'
    d.continuidad={proximo_vencimiento:'2026-10-31'}
    d.inversiones[0]!.condiciones_coopac={plazo_meses:12,tasa_anual:12.5}
    api.ficha.mockResolvedValue(d)
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const continuidad=await screen.findByRole('region',{name:'Continuidad comercial del cliente'})
    expect(continuidad).toHaveTextContent('31 oct')
    expect(screen.getByRole('link',{name:'Abrir WhatsApp de ANA SINTÉTICA F5'})).toHaveAttribute('href','https://wa.me/51999888777')
    const seguimiento=screen.getByRole('heading',{name:'Seguimiento'})
    const inversiones=screen.getByRole('heading',{name:'Inversiones y contratos'})
    const informacion=screen.getByRole('heading',{name:'Información del cliente'})
    expect(seguimiento.compareDocumentPosition(inversiones)&Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(inversiones.compareDocumentPosition(informacion)&Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(screen.getByText('12.5% anual')).not.toBeVisible()
    await user.click(screen.getByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'}))
    expect(screen.getByText('12.5% anual')).toBeVisible()
    expect(screen.getByText('12 meses')).toBeInTheDocument()
    expect(screen.getByRole('button',{name:/Copiar correo/i})).toBeInTheDocument()
  })
  it('conserva los totales del núcleo aunque la página solo contenga una inversión', async () => {
    const d=structuredClone(fichaF5)
    d.inversiones_total=40
    d.totales=[{empresa:'avance',moneda:'USD',cantidad:12,capital_activo:17000,capital_registrado:22000},
      {empresa:'qorilazo',moneda:'PEN',cantidad:28,capital_activo:null,capital_registrado:90000}]
    api.ficha.mockResolvedValue(d)
    const {user,qc}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const r=await screen.findByRole('region',{name:'Continuidad comercial del cliente'})
    expect(r).toHaveTextContent('US$ 17,000')
    expect(r).toHaveTextContent('S/ 90,000')
    expect(r).toHaveTextContent('40 inversiones registradas')
    expect(r).toHaveTextContent('Capital activo · 12 inversiones')
    expect(r).toHaveTextContent('Capital registrado · 28 inversiones')
    expect(within(r).queryByText('S/ 1,200')).not.toBeInTheDocument()
    const abrir=screen.getByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})
    await user.click(abrir)
    await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    expect(abrir).toHaveAttribute('aria-expanded','true')
    expect(screen.getByText('DEPÓSITO SINTÉTICO')).toBeVisible()
    await user.click(abrir)
    expect(screen.getByText('DEPÓSITO SINTÉTICO')).not.toBeVisible()
  })
  it('un capital Avance sin saldo activo confirmado se identifica como registrado', async () => {
    const d=structuredClone(fichaF5)
    d.totales=[{empresa:'avance',moneda:'PEN',cantidad:1,capital_activo:null,capital_registrado:4000}]
    api.ficha.mockResolvedValue(d)
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const r=await screen.findByRole('region',{name:'Continuidad comercial del cliente'})
    expect(r).toHaveTextContent('Capital registrado')
    expect(r).not.toHaveTextContent('Capital vigente')
    expect(r).toHaveTextContent('S/ 4,000')
  })
  it('con un mes elegido usa capital registrado del núcleo aunque el capital activo sea distinto', async () => {
    api.lista.mockResolvedValue({...structuredClone(carteraF5),totales:[
      {empresa:'avance',moneda:'PEN',cantidad:2,capital_activo:null,capital_registrado:4000},
      {empresa:'qorilazo',moneda:'USD',cantidad:3,capital_activo:0,capital_registrado:1200},
    ]})
    montar()
    const avance=(await screen.findByText('Avance · PEN')).parentElement!
    expect(avance).toHaveTextContent('S/ 4,000')
    expect(avance).toHaveTextContent('Capital registrado · 2 inversiones')
    const coopac=screen.getByText('Qorilazo · USD').parentElement!
    expect(coopac).toHaveTextContent('US$ 1,200')
    expect(coopac).toHaveTextContent('Capital registrado · 3 inversiones')
  })
  it.each([12000, 0])('buscar por documento muestra el capital activo %s sin sumar contratos anteriores', async capitalActivo => {
    sesion.rol='vendedor'; sesion.rolPortal='comercial'
    const resumen: ResumenEmpresa[] = [{empresa:'avance',moneda:'USD',cantidad:2,capital_activo:capitalActivo,capital_registrado:17000}]
    api.lista.mockResolvedValue({...carteraF5,totales:resumen,filas:[{...carteraF5.filas[0],empresas:['avance'],resumen}]})
    const {user}=montar()
    expect(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).toHaveTextContent('US$ 17,000')
    await user.type(screen.getByLabelText('Buscar persona'),'93334444')
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0]).toMatchObject({texto:'93334444',mes:''}))
    const fila=await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    const importe=capitalActivo === 0 ? 'US$ 0' : 'US$ 12,000'
    expect(fila).toHaveTextContent(importe)
    expect(fila).not.toHaveTextContent('US$ 17,000')
    expect(fila).toHaveAccessibleDescription(/Capital.*Avance.*USD.*Activo/)
    const total=screen.getByLabelText('Capital de las inversiones filtradas')
    expect(total).toHaveTextContent(importe)
    expect(total).toHaveTextContent('Capital activo')
    expect(total).not.toHaveTextContent('US$ 17,000')
  })
  it('todos los meses usa capital activo y conserva el registrado cuando no hay saldo activo informado', async () => {
    const resumen: ResumenEmpresa[] = [
      {empresa:'avance',moneda:'USD',cantidad:2,capital_activo:12000,capital_registrado:17000},
      {empresa:'avance',moneda:'PEN',cantidad:1,capital_activo:null,capital_registrado:4000},
      {empresa:'qorilazo',moneda:'PEN',cantidad:1,capital_activo:null,capital_registrado:2500},
    ]
    api.lista.mockResolvedValue({...carteraF5,totales:resumen,filas:[{...carteraF5.filas[0],empresas:['avance','qorilazo'],resumen}]})
    const {user}=montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    await user.selectOptions(screen.getByLabelText('Mes de cierre comercial'),'')
    const fila=await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    expect(fila).toHaveTextContent('US$ 12,000')
    expect(fila).not.toHaveTextContent('US$ 17,000')
    expect(fila).toHaveTextContent('S/ 4,000')
    expect(fila).toHaveTextContent('S/ 2,500')
    expect(fila).toHaveAccessibleDescription(/Avance.*USD.*Activo.*Avance.*PEN.*Registrado.*Qorilazo.*PEN.*Registrado/)
    const total=screen.getByLabelText('Capital de las inversiones filtradas')
    expect(total).toHaveTextContent('US$ 12,000')
    expect(total).toHaveTextContent('S/ 4,000')
    expect(total).toHaveTextContent('S/ 2,500')
  })
  it.each(['renovado','retirado','vencido','anulado_comercialmente'])('consultar el estado histórico %s conserva su importe registrado', async estado => {
    const resumen: ResumenEmpresa[] = [{empresa:'avance',moneda:'USD',cantidad:1,capital_activo:0,capital_registrado:5000}]
    api.lista.mockResolvedValue({...carteraF5,totales:resumen,filas:[{...carteraF5.filas[0],empresas:['avance'],resumen}]})
    const {user}=montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    await user.selectOptions(screen.getByLabelText('Mes de cierre comercial'),'')
    await user.click(screen.getByRole('button',{name:'Más filtros'}))
    await user.selectOptions(screen.getByLabelText('Estado de inversión'),estado)
    const fila=await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    expect(fila).toHaveTextContent('US$ 5,000')
    expect(screen.getByLabelText('Capital de las inversiones filtradas')).toHaveTextContent('Capital registrado')
  })
  it('distingue inversiones sin número por posición dentro de su empresa y moneda', async () => {
    const d=structuredClone(fichaF5)
    d.inversiones[0]!.numero=null
    d.inversiones.push({...d.inversiones[0]!,fuente_id:PERFIL_F5,moneda:'USD'})
    d.inversiones_total=2
    api.ficha.mockResolvedValue(d)
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const pen=await screen.findByRole('button',{name:'Ver inversión registro 1 de Qorilazo PEN en esta página'})
    const usd=screen.getByRole('button',{name:'Ver inversión registro 1 de Qorilazo USD en esta página'})
    await user.click(usd)
    expect(usd).toHaveAttribute('aria-expanded','true')
    expect(pen).toHaveAttribute('aria-expanded','false')
  })
  it('la tarjeta compacta avisa de PDF pendiente y anulación antes de abrir detalles', async () => {
    const d=structuredClone(fichaF5)
    d.inversiones[0]!.pdf={estado:'reservado',reintentable:true}
    d.inversiones[0]!.estado='anulado_comercialmente'
    api.ficha.mockResolvedValue(d)
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    expect(await screen.findByRole('button',{name:'Recuperar PDF pendiente'})).toBeVisible()
    expect(screen.getByText('PDF pendiente')).toBeVisible()
    expect(screen.getByText('Anulación comercial. El capital registrado se conserva.')).toBeVisible()
    expect(screen.getByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})).toHaveAttribute('aria-expanded','false')
  })
  it('una caída F6 conserva el detalle y el foco, retira sus controles y permite recuperarlos', async () => {
    const d=structuredClone(fichaF5);d.capacidades.postventa=true
    api.ficha.mockResolvedValue(d)
    const {user,qc}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Agendar gestión'})
    const detalle=screen.getByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})
    await user.click(detalle)
    api.postventa.mockRejectedValue(new CrmApiError('Corte F6','RED'))
    await act(async()=>{await qc.invalidateQueries({queryKey:['crm','postventa',ACTOR_F5]})})
    await screen.findByText('Corte F6')
    expect(screen.queryByRole('button',{name:'Agendar gestión'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button',{name:'Cambiar responsable'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button',{name:'Marcar No contactar'})).not.toBeInTheDocument()
    expect(detalle).toHaveFocus()
    expect(detalle).toHaveAttribute('aria-expanded','true')
    api.postventa.mockResolvedValue({version:1,habilitada:true,retiros:[]})
    await user.click(screen.getByRole('button',{name:/Reintentar/}))
    await screen.findByRole('button',{name:'Agendar gestión'})
    expect(detalle).toHaveAttribute('aria-expanded','true')
  })
  it('cambiar la habilitación F6 mantiene la ficha y exige otra lectura al reactivar', async () => {
    const d=structuredClone(fichaF5);d.capacidades.postventa=true
    api.ficha.mockResolvedValue(d)
    const {user,qc}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Agendar gestión'})
    const detalle=screen.getByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})
    await user.click(detalle)
    api.ficha.mockResolvedValue({...d,capacidades:{...d.capacidades,postventa:false}})
    await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    await waitFor(()=>expect(screen.queryByRole('button',{name:'Agendar gestión'})).not.toBeInTheDocument())
    expect(detalle).toHaveFocus()
    expect(detalle).toHaveAttribute('aria-expanded','true')
    const lecturas=api.postventa.mock.calls.length
    api.ficha.mockResolvedValue(d)
    await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    await screen.findByRole('button',{name:'Agendar gestión'})
    expect(api.postventa.mock.calls.length).toBeGreaterThan(lecturas)
    expect(detalle).toHaveFocus()
    expect(detalle).toHaveAttribute('aria-expanded','true')
  })
  it.each([
    ['Agendar gestión','error'],
    ['Registrar solicitud de retiro','capacidad'],
  ])('recuperar F6 no vuelve a abrir %s después de perder %s', async (boton,corte) => {
    const d=structuredClone(fichaF5);d.capacidades.postventa=true
    const titulo=boton==='Agendar gestión' ? 'Gestionar a ANA SINTÉTICA F5' : 'Registrar solicitud de retiro'
    api.ficha.mockResolvedValue(d)
    const {user,qc}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Agendar gestión'})
    await user.click(screen.getByRole('button',{name:boton}))
    expect(await screen.findByRole('dialog',{name:titulo})).toBeVisible()
    if (corte==='error') {
      api.postventa.mockRejectedValue(new CrmApiError('Corte F6','RED'))
      await act(async()=>{await qc.invalidateQueries({queryKey:['crm','postventa',ACTOR_F5]})})
    } else {
      api.ficha.mockResolvedValue({...d,capacidades:{...d.capacidades,postventa:false}})
      await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    }
    await waitFor(()=>expect(screen.queryByRole('dialog',{name:titulo})).not.toBeInTheDocument())
    // Completar la restitución de foco del modal antes de seguir navegando.
    await act(async()=>{await new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve())))})
    await waitFor(()=>expect(screen.getByRole('dialog')).toHaveFocus())
    const detalle=screen.getByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})
    await user.click(detalle)
    api.postventa.mockResolvedValue({version:1,habilitada:true,retiros:[]})
    api.ficha.mockResolvedValue(d)
    await act(async()=>{await qc.invalidateQueries({queryKey:corte==='error'
      ? ['crm','postventa',ACTOR_F5] : inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    await screen.findByRole('button',{name:'Agendar gestión'})
    expect(screen.queryByRole('dialog',{name:titulo})).not.toBeInTheDocument()
    expect(detalle).toHaveFocus()
    await user.click(screen.getByRole('button',{name:boton}))
    expect(await screen.findByRole('dialog',{name:titulo})).toBeVisible()
  })
  it('un fallo transitorio conserva la ficha y el foco, deshabilita sus acciones y permite recuperar', async () => {
    const sinInversiones={...structuredClone(fichaF5),inversiones:[],inversiones_total:0,totales:[]}
    api.ficha.mockResolvedValue(sinInversiones)
    const {user,qc}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const informacion=await screen.findByRole('region',{name:'Información del cliente'})
    const contacto=screen.getByRole('link',{name:'Abrir WhatsApp de ANA SINTÉTICA F5'}); contacto.focus()
    api.ficha.mockRejectedValue(new CrmApiError('Sin conexión','RED'))
    await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    await screen.findByText(/Se conservan los últimos datos confirmados/)
    expect(screen.getByRole('region',{name:'Información del cliente'})).toBe(informacion)
    expect(contacto).toHaveFocus()
    expect(contacto).toHaveAttribute('aria-disabled','true')
    expect(screen.getByRole('button',{name:'Registrar primera inversión'})).toBeDisabled()
    expect(screen.getByText('Abrir WhatsApp').closest('a')).not.toHaveAttribute('href')
    api.ficha.mockResolvedValue(sinInversiones)
    await user.click(screen.getByRole('button',{name:'Reintentar actualización'}))
    await waitFor(()=>expect(screen.getByRole('button',{name:'Registrar primera inversión'})).toBeEnabled())
    expect(screen.getByRole('region',{name:'Información del cliente'})).toBe(informacion)
  })
  it('la lista confirmada mantiene sus filas durante un corte y una revocación sí las retira', async () => {
    const {qc}=montar()
    const fila=await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    api.lista.mockRejectedValue(new CrmApiError('Sin conexión','RED'))
    await act(async()=>{await qc.invalidateQueries({queryKey:[...inversionistasKeys.actor(ACTOR_F5),'lista']})})
    expect(screen.getByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).toBe(fila)
    expect(await screen.findByText(/Se muestran los últimos datos confirmados/)).toBeInTheDocument()
    api.lista.mockRejectedValue(new CrmApiError('No autorizado','42501'))
    await act(async()=>{await qc.invalidateQueries({queryKey:[...inversionistasKeys.actor(ACTOR_F5),'lista']})})
    await waitFor(()=>expect(screen.queryByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).not.toBeInTheDocument())
  })
  it('filtra en servidor, conserva consulta al cerrar y mantiene paginación visible',async () => {
    const {user}=montar()
    await user.type(screen.getByLabelText('Buscar persona'),'9333')
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0].texto).toBe('9333'))
    expect(screen.getByRole('navigation',{name:'Paginación de inversionistas'})).toBeInTheDocument()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByText('Información del cliente')
    expect(screen.queryByText('Cuentas para recibir pagos')).not.toBeInTheDocument()
    expect(api.bancos).not.toHaveBeenCalled()
    await user.click(screen.getAllByRole('button',{name:'Cerrar ficha'})[0]!)
    expect(screen.getByLabelText('Buscar persona')).toHaveValue('9333')
  })
  it('combina filtros en servidor, reinicia página y muestra los totales recibidos completos',async () => {
    api.lista.mockImplementation(f => Promise.resolve({...carteraF5,pagina:f.pagina,total:60,
      totales:[{empresa:'avance',moneda:'USD',cantidad:60,capital_activo:200,capital_registrado:90000}]}))
    const {user}=montar()
    await screen.findByText(/60 personas/)
    await user.click(screen.getByRole('button',{name:/Siguiente/i}))
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0].pagina).toBe(2))
    await user.selectOptions(screen.getByLabelText('Mes de cierre comercial'),'2026-08')
    await user.selectOptions(screen.getByLabelText('Empresa'),'avance')
    await user.click(screen.getByRole('button',{name:'Más filtros'}))
    await user.selectOptions(screen.getByLabelText('Moneda'),'USD')
    await user.selectOptions(screen.getByLabelText('Estado de inversión'),'vigente')
    await user.selectOptions(screen.getByLabelText('Responsable actual'),ACTOR_F5)
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0]).toMatchObject({pagina:1,mes:'2026-08',empresa:'avance',moneda:'USD',estado:'vigente',responsable:ACTOR_F5}))
    expect(await screen.findByText('US$ 90,000')).toBeVisible()
    expect(screen.getByText(/60 personas/)).toBeVisible()
    await user.click(screen.getByRole('button',{name:/Más filtros/}))
    expect(screen.getByRole('button',{name:'Más filtros (3)'})).toHaveAttribute('aria-expanded','false')
  })
  it('los clientes sin inversiones y el radar de 30 días limpian recortes incompatibles',async () => {
    const {user}=montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    await user.selectOptions(screen.getByLabelText('Empresa'),'qorilazo')
    await user.click(screen.getByRole('button',{name:'Más filtros'}))
    await user.selectOptions(screen.getByLabelText('Moneda'),'USD')
    await user.selectOptions(screen.getByLabelText('Estado de inversión'),'sin_inversiones')
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0]).toMatchObject({estado:'sin_inversiones',mes:'',empresa:'',moneda:'',porVencer:false}))
    expect(screen.getByLabelText('Mes de cierre comercial')).toBeDisabled()
    expect(screen.getByText('Clientes sin inversiones. Mes, empresa y moneda no se aplican.')).not.toHaveClass('hidden')
    await user.selectOptions(screen.getByLabelText('Estado de inversión'),'')
    await user.selectOptions(screen.getByLabelText('Mes de cierre comercial'),'2026-08')
    await user.click(screen.getByLabelText('Por vencer en 30 días'))
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0]).toMatchObject({mes:'',estado:'vigente',porVencer:true}))
    await user.click(screen.getByLabelText('Por vencer en 30 días'))
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0]).toMatchObject({mes:'2026-08',estado:'',porVencer:false}))
    await user.click(screen.getByLabelText('Por vencer en 30 días'))
    await user.selectOptions(screen.getByLabelText('Estado de inversión'),'vencido')
    expect(screen.getByLabelText('Por vencer en 30 días')).not.toBeChecked()
    await user.click(screen.getByRole('button',{name:'Limpiar filtros'}))
    await waitFor(()=>expect(api.lista.mock.calls.at(-1)?.[0]).toMatchObject({mes:'',estado:'',porVencer:false}))
  })
  it('Directorio explica que sus clientes sin inversiones pertenecen al ámbito Avance',async () => {
    api.lista.mockResolvedValue({...carteraF5,solo_avance:true,sin_inversiones_total:1,totales:[],
      filas:[{...carteraF5.filas[0],empresas:[],resumen:[],ultima_fecha_comercial:null}]})
    const {user}=montar()
    await screen.findByText(/1 sin inversiones Avance/)
    expect(within(screen.getByLabelText('Empresa')).queryByRole('option',{name:'Qorilazo'})).not.toBeInTheDocument()
    await user.click(screen.getByRole('button',{name:'Más filtros'}))
    await user.selectOptions(screen.getByLabelText('Estado de inversión'),'sin_inversiones')
    expect(screen.getByRole('option',{name:'Sin inversiones Avance'})).toBeInTheDocument()
    expect(screen.getByText('Clientes sin inversiones Avance. Mes, empresa y moneda no se aplican.')).not.toHaveClass('hidden')
  })
  it('la fila anuncia documento, capital, cierre, responsable y No contactar al lector de pantalla',async () => {
    api.lista.mockResolvedValue({...carteraF5,filas:[{...carteraF5.filas[0],no_contactar:true}]})
    montar()
    const fila=await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    expect(fila).toHaveAccessibleDescription(/DNI 93334444.*Capital registrado.*Qorilazo.*S\/ 1,200.*Último cierre:.*Responsable actual: ANALISTA F5.*No contactar/)
  })
  it('un rechazo persistente retira los datos sin encadenar reconsultas de revocación',async () => {
    api.lista.mockImplementation(()=>Promise.reject(new CrmApiError('No autorizado','42501')))
    const {user}=montar()
    await screen.findByText('No autorizado')
    await act(async()=>{await new Promise(resolve=>setTimeout(resolve,100))})
    expect(api.lista.mock.calls.length).toBeLessThanOrEqual(2)
    expect(screen.queryByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).not.toBeInTheDocument()
    api.lista.mockResolvedValue(carteraF5)
    await user.click(screen.getByRole('button',{name:/Reintentar/}))
    expect(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).toBeVisible()
  })
  it('un analista filtra su cartera sin selector de responsables ajenos',async () => {
    sesion.rol='vendedor'
    const {user}=montar()
    await user.click(screen.getByRole('button',{name:'Más filtros'}))
    expect(screen.queryByLabelText('Responsable actual')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Mes de cierre comercial')).toBeVisible()
  })
  it('cambiar mes cancela la consulta anterior y no presenta sus importes como actuales',async () => {
    let resolver!: (v:typeof carteraF5)=>void
    const {user}=montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    api.lista.mockImplementation(f => f.mes==='2026-08' ? new Promise(r=>{resolver=r}) : Promise.resolve({...carteraF5,total:0,filas:[],totales:[]}))
    await user.selectOptions(screen.getByLabelText('Mes de cierre comercial'),'2026-08')
    const signal=api.lista.mock.calls.at(-1)?.[1] as AbortSignal
    expect(screen.queryByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).not.toBeInTheDocument()
    await user.selectOptions(screen.getByLabelText('Mes de cierre comercial'),'2026-09')
    await screen.findByText('No hay personas que coincidan con estos filtros.')
    expect(signal.aborted).toBe(true)
    await act(async()=>resolver(carteraF5))
    expect(screen.queryByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})).not.toBeInTheDocument()
    expect(screen.queryByText('S/ 1,200')).not.toBeInTheDocument()
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
    d.capacidades.postventa=true
    api.ficha.mockResolvedValue(d)
    api.documento.mockImplementationOnce((_p,_f,_d,signal:AbortSignal)=>new Promise((_r,reject)=>{
      signal.addEventListener('abort',()=>reject(new DOMException('Cancelada','AbortError')),{once:true})
    })).mockResolvedValue(undefined)
    const {user}=montar();await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'}))
    await user.click(await screen.findByRole('button',{name:'Documento del ensayo'}))
    await user.click(screen.getByRole('button',{name:'Reinvertir desde esta inversión'}))
    await user.click(await screen.findByRole('button',{name:'Cerrar y continuar después'}))
    await waitFor(()=>expect(screen.getByRole('region',{name:'Inversiones y contratos'})).toHaveFocus())
    await user.click(await screen.findByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'}))
    await user.click(await screen.findByRole('button',{name:'Documento del ensayo'}))
    await waitFor(()=>expect(api.documento).toHaveBeenCalledTimes(2))
    expect(screen.queryByText('Comprobando acceso y descargando documento…')).not.toBeInTheDocument()
  })
  it('actualizar la ficha no desmonta ni vuelve a cargar las cuentas abiertas',async()=>{
    const d=structuredClone(fichaF5);d.capacidades.cuentas_perfil_ids=[PERFIL_F5]
    api.ficha.mockResolvedValue(d)
    const {user,qc}=montar();await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByLabelText(/Cuentas para recibir pagos\. Cuentas autorizadas/))
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
  it('QORILAZO no pregunta la moneda: solo admite soles',async () => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones:[],inversiones_total:0,totales:[]})
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Qorilazo'}))
    expect(screen.queryByLabelText('Moneda')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Capital en soles (PEN)')).toBeInTheDocument()
  })
  it('PRODELCO pregunta la moneda y la inversión en dólares viaja como USD',async () => {
    // Es el caso que justifica la apertura: una inversión ADICIONAL de Prodelco
    // en dólares. Antes del 17/09/2026 este formulario mandaba 'PEN' fijo.
    let vigente=solicitud()
    api.preparar.mockImplementation(async intento=> {vigente={...solicitud(intento.clave),revision_datos:1,datos:intento.datos}; return vigente})
    api.consultar.mockImplementation(async()=>vigente)
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Prodelco'}))
    const moneda=screen.getByLabelText('Moneda')
    expect(moneda).toHaveValue('PEN')
    await user.selectOptions(moneda,'USD')
    // El rótulo del capital dice en qué moneda va el número.
    expect(screen.getByLabelText('Capital en dólares (USD)')).toBeInTheDocument()
    await user.type(screen.getByLabelText('Capital en dólares (USD)'),'4321')
    await user.type(screen.getByLabelText('Número de operación del depósito'),'F5-USD-001')
    await user.clear(screen.getByLabelText('Fecha comercial (inicio)')); await user.type(screen.getByLabelText('Fecha comercial (inicio)'),'2026-09-01')
    await user.type(screen.getByLabelText('Plazo (meses)'),'12')
    await user.type(screen.getByLabelText('Rentabilidad anual (%)'),'9.5')
    await user.type(screen.getByLabelText('Referencia de la inversión'),'REFERENCIA USD')
    await user.upload(screen.getByLabelText(/Comprobante PDF/),new File(['pdf sintético'],'prueba.pdf',{type:'application/pdf'}))
    fireEvent.submit(screen.getByRole('button',{name:'Revisar inversión'}).closest('form')!)
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(api.preparar).toHaveBeenCalledWith(expect.objectContaining({
      datos:expect.objectContaining({empresa:'prodelco',moneda:'USD',monto:4321}),
    }))
  })
  it('prepara sin éxito anticipado, confirma con revisión devuelta y recupera un corte sin otra alta',async () => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones:[],inversiones_total:0,totales:[]})
    let vigente=solicitud()
    api.preparar.mockImplementation(async intento=> {vigente={...solicitud(intento.clave),revision_datos:3,datos:intento.datos}; return vigente})
    api.consultar.mockImplementation(async()=>vigente)
    api.confirmar.mockImplementation(async()=> {
      vigente={...vigente,estado:'confirmada',resultado:{...resultado,solicitud_id:vigente.solicitud_id}}
      api.ficha.mockResolvedValue(structuredClone(fichaF5))
      throw new CrmApiError('Respuesta perdida','RED')
    })
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Qorilazo'}))
    await user.type(screen.getByLabelText('Capital en soles (PEN)'),'2500')
    await user.type(screen.getByLabelText('Número de operación del depósito'),'F5-DEP-001')
    await user.clear(screen.getByLabelText('Fecha comercial (inicio)')); await user.type(screen.getByLabelText('Fecha comercial (inicio)'),'2026-09-01')
    await user.type(screen.getByLabelText('Plazo (meses)'),'12')
    expect(screen.getByLabelText('Vencimiento')).toHaveValue('2027-09-01')
    expect(screen.getByLabelText('Vencimiento')).toHaveAttribute('readonly')
    await user.type(screen.getByLabelText('Rentabilidad anual (%)'),'12')
    await user.type(screen.getByLabelText('Referencia de la inversión'),'REFERENCIA SINTÉTICA')
    await user.upload(screen.getByLabelText(/Comprobante PDF/),new File(['pdf sintético'],'prueba.pdf',{type:'application/pdf'}))
    expect((screen.getByLabelText(/Comprobante PDF/) as HTMLInputElement).files).toHaveLength(1)
    // JSDOM 29 no considera el FileList de userEvent al validar required.
    // Playwright cubre el submit nativo con un archivo real del navegador.
    fireEvent.submit(screen.getByRole('button',{name:'Revisar inversión'}).closest('form')!)
    await screen.findByRole('button',{name:'Confirmar inversión'})
    expect(confirmada).not.toHaveBeenCalled(); expect(api.confirmar).not.toHaveBeenCalled()
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5)?.datos).toMatchObject({plazo_meses:12,tasa_anual:12,vence_en:'2027-09-01'})
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


// «Eliminar inversión» (05/10/2026) reemplaza en la Cartera al borrado contractual
// viejo: admin/superadmin del portal o gerencia; en Avance solo el admin del portal.
// El servidor decide siempre; la pantalla solo no ofrece el botón a quien seguro no puede.
function contratoAvance() {
  const ficha=structuredClone(fichaF5)
  ficha.inversiones[0]!.empresa='avance'
  ficha.inversiones[0]!.numero='2026-01-999999'
  ficha.inversiones[0]!.perfil_id=PERFIL_F5
  ficha.inversiones[0]!.contrato={fecha_inicio:'2026-09-01',tasa_anual:15,modalidad:'mensual',tipo_interes:'simple',categoria:'nuevo'}
  api.ficha.mockResolvedValue(ficha)
  return ficha
}
async function confirmarEliminacion(user: ReturnType<typeof userEvent.setup>, dialogo: HTMLElement, motivo='Registro duplicado') {
  await user.type(within(dialogo).getByLabelText('Motivo de la eliminación'), motivo)
  await user.type(within(dialogo).getByLabelText('Escribe ELIMINAR para confirmar'), 'ELIMINAR')
  await user.click(within(dialogo).getByRole('button',{name:'Eliminar inversión'}))
}
const ELIMINAR_ALGO = /Eliminar (contrato|inversión)/

describe('Eliminación administrativa desde la ficha', () => {
  it.each(['admin','superadmin'])('%s elimina la inversión Avance con motivo, sin el «Eliminar contrato» viejo, y la cartera se actualiza',async(rol)=>{
    sesion.rolPortal=rol
    const ficha=contratoAvance()
    api.eliminarInversion.mockImplementation(async()=>{
      api.ficha.mockResolvedValue({...ficha,inversiones:[],inversiones_total:0})
      return {auditoriaId:PERFIL_F5,empresa:'avance',conversionAnulada:false,mesCerrado:false}
    })
    const exito=vi.spyOn(toast,'success')
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Eliminar inversión 2026-01-999999'}))
    expect(screen.queryByRole('button',{name:/Eliminar contrato/})).not.toBeInTheDocument()
    const dialogo=screen.getByRole('dialog',{name:'Eliminar inversión 2026-01-999999'})
    expect(within(dialogo).getByText(/Esta acción no se deshace/)).toBeVisible()
    expect(within(dialogo).getByRole('button',{name:'Eliminar inversión'})).toBeDisabled()
    await confirmarEliminacion(user,dialogo,'  Contrato cargado dos veces  ')
    await waitFor(()=>expect(api.eliminarInversion).toHaveBeenCalledExactlyOnceWith(FUENTE_F5,'Contrato cargado dos veces'))
    await waitFor(()=>expect(screen.queryByRole('dialog',{name:'Eliminar inversión 2026-01-999999'})).not.toBeInTheDocument())
    expect(await screen.findByText('Este cliente todavía no tiene una inversión registrada.')).toBeVisible()
    // La fila ya no existe: el foco vuelve a la ficha, nunca a <body>.
    await waitFor(()=>expect(screen.getByRole('dialog')).toHaveFocus())
    expect(exito).toHaveBeenCalledWith(`Inversión eliminada. Copia de auditoría: ${PERFIL_F5}.`)
    expect(api.eliminar).not.toHaveBeenCalled()
  })
  it.each(['analista','directorio','operaciones'])('gerencia con portal %s no recibe ningún borrado en Avance',async(rol)=>{
    sesion.rolPortal=rol;contratoAvance()
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Ver inversión 2026-01-999999'})
    expect(screen.queryByRole('button',{name:ELIMINAR_ALGO})).not.toBeInTheDocument()
  })
  it('cancelar no borra y devuelve el foco; un rechazo del servidor conserva la inversión y muestra su motivo',async()=>{
    sesion.rolPortal='admin';contratoAvance()
    api.eliminarInversion.mockRejectedValue(new CrmApiError('Este contrato ya se renovó: tiene historia propia y no se elimina','CONFLICTO'))
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const boton=await screen.findByRole('button',{name:'Eliminar inversión 2026-01-999999'})
    await user.click(boton)
    // Apilado sobre la ficha, el foco entra al motivo y no se queda en la ficha de abajo.
    await waitFor(()=>expect(screen.getByLabelText('Motivo de la eliminación')).toHaveFocus())
    await user.click(screen.getByRole('button',{name:'Cancelar'}))
    expect(api.eliminarInversion).not.toHaveBeenCalled()
    await waitFor(()=>expect(boton).toHaveFocus())
    await user.click(boton)
    const dialogo=screen.getByRole('dialog',{name:'Eliminar inversión 2026-01-999999'})
    await confirmarEliminacion(user,dialogo)
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('Este contrato ya se renovó: tiene historia propia y no se elimina')
    expect(api.eliminarInversion).toHaveBeenCalledExactlyOnceWith(FUENTE_F5,'Registro duplicado')
    // Detrás del modal (inerte para la tecnología asistiva) la inversión sigue en la ficha.
    expect(screen.getByRole('button',{name:'Ver inversión 2026-01-999999',hidden:true})).toBeInTheDocument()
  })
  it('en cooperativas el administrador recibe «Eliminar inversión», nunca el borrado contractual de Avance',async()=>{
    sesion.rolPortal='admin'
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    expect(await screen.findByRole('button',{name:'Eliminar inversión QORILAZO SINTÉTICO'})).toBeEnabled()
    expect(screen.queryByRole('button',{name:/Eliminar contrato/})).not.toBeInTheDocument()
  })
  it('una sesión demo no recibe ningún borrado',async()=>{
    sesion.rolPortal='admin';sesion.demo=true;contratoAvance()
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Ver inversión 2026-01-999999'})
    expect(screen.queryByRole('button',{name:ELIMINAR_ALGO})).not.toBeInTheDocument()
    expect(api.eliminar).not.toHaveBeenCalled()
    expect(api.eliminarInversion).not.toHaveBeenCalled()
  })
  it.each(['sin datos de contrato','ya enlazada a la cartera multiempresa'] as const)('una inversión Avance %s se ofrece igual: el servidor decide',async(estado)=>{
    sesion.rolPortal='superadmin'
    const ficha=contratoAvance()
    if(estado==='sin datos de contrato') ficha.inversiones[0]!.contrato=null
    else ficha.inversiones[0]!.inversion_id=FUENTE_F5
    api.ficha.mockResolvedValue(ficha)
    api.eliminarInversion.mockResolvedValue({auditoriaId:PERFIL_F5,empresa:'avance',conversionAnulada:false,mesCerrado:false})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Eliminar inversión 2026-01-999999'}))
    expect(screen.queryByRole('button',{name:/Eliminar contrato/})).not.toBeInTheDocument()
    await confirmarEliminacion(user,screen.getByRole('dialog',{name:'Eliminar inversión 2026-01-999999'}))
    await waitFor(()=>expect(api.eliminarInversion).toHaveBeenCalledExactlyOnceWith(FUENTE_F5,'Registro duplicado'))
  })
})

describe('Eliminar inversión: gerencia y la conversión de un lead', () => {
  function fichaMixta() {
    const ficha=structuredClone(fichaF5)
    ficha.inversiones.push({...structuredClone(inversionF5),fuente_id:PERFIL_F5,empresa:'avance',numero:'2026-01-000777',
      perfil_id:PERFIL_F5,es_inicial:false,contrato:{fecha_inicio:'2026-09-01',tasa_anual:15,modalidad:'mensual',tipo_interes:'simple',categoria:'nuevo'}})
    ficha.inversiones_total=2
    api.ficha.mockResolvedValue(ficha)
    return ficha
  }
  it('gerencia sin admin del portal: «Eliminar inversión» en la cooperativa, nunca en Avance',async()=>{
    fichaMixta()
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    expect(await screen.findByRole('button',{name:'Eliminar inversión QORILAZO SINTÉTICO'})).toBeEnabled()
    expect(screen.getByRole('button',{name:'Ver inversión 2026-01-000777'})).toBeInTheDocument()
    expect(screen.queryByRole('button',{name:'Eliminar inversión 2026-01-000777'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button',{name:/Eliminar contrato/})).not.toBeInTheDocument()
  })
  it.each([['vendedor','analista'],['supervisor','comercial'],['directorio','directorio']])('%s (portal %s) no ve «Eliminar inversión»',async(rol,rolPortal)=>{
    sesion.rol=rol;sesion.rolPortal=rolPortal;fichaMixta()
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})
    expect(screen.queryByRole('button',{name:ELIMINAR_ALGO})).not.toBeInTheDocument()
  })
  it.each([
    [false,false,''],
    [true,false,' La conversión del lead quedó anulada.'],
    [true,true,' La conversión del lead quedó anulada. El mes ya estaba cerrado: el ajuste pasa al mes vivo.'],
  ])('conversión anulada %s, mes cerrado %s: avisa y refresca lo mismo que el borrado contractual',async(conversionAnulada,mesCerrado,aviso)=>{
    const ficha=structuredClone(fichaF5)
    api.ficha.mockResolvedValue(ficha)
    api.eliminarInversion.mockImplementation(async()=>{
      api.ficha.mockResolvedValue({...ficha,inversiones:[],inversiones_total:0,totales:[]})
      return {auditoriaId:PERFIL_F5,empresa:'qorilazo',conversionAnulada,mesCerrado}
    })
    const exito=vi.spyOn(toast,'success')
    const {user,qc}=montar()
    const invalidar=vi.spyOn(qc,'invalidateQueries')
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Eliminar inversión QORILAZO SINTÉTICO'}))
    const dialogo=screen.getByRole('dialog',{name:'Eliminar inversión QORILAZO SINTÉTICO'})
    expect(within(dialogo).getByText('Si es la conversión de un lead, también se anula (solo gerencia).')).toBeVisible()
    await confirmarEliminacion(user,dialogo)
    await waitFor(()=>expect(exito).toHaveBeenCalledWith(`Inversión eliminada. Copia de auditoría: ${PERFIL_F5}.${aviso}`))
    expect(api.eliminarInversion).toHaveBeenCalledExactlyOnceWith(FUENTE_F5,'Registro duplicado')
    expect(invalidar.mock.calls.map(([filtro])=>filtro?.queryKey)).toEqual(expect.arrayContaining([
      inversionistasKeys.actor(ACTOR_F5), crmQueryKeys.contratos(), crmQueryKeys.metricas(), crmQueryKeys.leads(), postventaKeys.actor(ACTOR_F5),
    ]))
    expect(await screen.findByText('Este cliente todavía no tiene una inversión registrada.')).toBeVisible()
  })
  it('si la ficha queda desactualizada, el diálogo se cierra sin enviar y el botón se retira',async()=>{
    const {user,qc}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Eliminar inversión QORILAZO SINTÉTICO'}))
    expect(screen.getByRole('dialog',{name:'Eliminar inversión QORILAZO SINTÉTICO'})).toBeInTheDocument()
    api.ficha.mockRejectedValue(new CrmApiError('Corte de red','RED'))
    await act(async()=>{await qc.invalidateQueries({queryKey:inversionistasKeys.ficha(ACTOR_F5,PERSONA_F5)})})
    await waitFor(()=>expect(screen.queryByRole('dialog',{name:'Eliminar inversión QORILAZO SINTÉTICO'})).not.toBeInTheDocument())
    expect(screen.getByText('No pudimos actualizar la ficha. Se conservan los últimos datos confirmados.')).toBeInTheDocument()
    expect(screen.queryByRole('button',{name:ELIMINAR_ALGO})).not.toBeInTheDocument()
    expect(api.eliminarInversion).not.toHaveBeenCalled()
  })
})

describe('Ficha montada sin «Eliminar inversión»', () => {
  it('conserva el borrado contractual en Avance; con las dos acciones, solo queda «Eliminar inversión»',async()=>{
    contratoAvance()
    const onEliminar=vi.fn<(i: InversionFuente) => Promise<void>>()
      .mockRejectedValueOnce(new ContratoEliminacionError('El contrato forma parte del historial de inversiones'))
      .mockResolvedValueOnce(undefined)
    const qc=new QueryClient({defaultOptions:{queries:{retry:false}}})
    const user=userEvent.setup()
    const ficha=(extra: {onEliminarInversion?: (i: InversionFuente, motivo: string) => Promise<void>}) =>
      <QueryClientProvider client={qc}><Sheet open onClose={()=>{}} ariaLabel="Ficha del inversionista">
        <InversionistaFicha actor={ACTOR_F5} inversionistaId={PERSONA_F5} onCerrar={()=>{}} onRevocado={()=>{}} onEliminar={onEliminar} {...extra} />
      </Sheet></QueryClientProvider>
    const {rerender}=render(ficha({}))
    await user.click(await screen.findByRole('button',{name:'Eliminar contrato 2026-01-999999'}))
    expect(screen.queryByRole('button',{name:/Eliminar inversión/})).not.toBeInTheDocument()
    const dialogo=screen.getByRole('dialog',{name:'Eliminar contrato 2026-01-999999'})
    await user.type(within(dialogo).getByLabelText('Escribe 2026-01-999999 para confirmar'),'2026-01-999999')
    await user.click(within(dialogo).getByRole('button',{name:'Eliminar y conservar auditoría'}))
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('historial de inversiones')
    await user.click(within(dialogo).getByRole('button',{name:'Eliminar y conservar auditoría'}))
    await waitFor(()=>expect(screen.queryByRole('dialog',{name:'Eliminar contrato 2026-01-999999'})).not.toBeInTheDocument())
    expect(onEliminar).toHaveBeenCalledTimes(2)
    expect(onEliminar).toHaveBeenLastCalledWith(expect.objectContaining({fuente_id:FUENTE_F5}))
    rerender(ficha({onEliminarInversion:vi.fn(async()=>{})}))
    expect(await screen.findByRole('button',{name:'Eliminar inversión 2026-01-999999'})).toBeInTheDocument()
    expect(screen.queryByRole('button',{name:/Eliminar contrato/})).not.toBeInTheDocument()
  })
})

describe('Upgrade: continuidad del cliente que ya tiene una inversión', () => {
  // El analista leía «Registrar nueva inversión» como el único camino y creía
  // que el upgrade MODIFICABA el contrato vivo. El upgrade abre un contrato
  // NUEVO que solo hereda la tasa del que amplía, así que la operación vive
  // al costado, en la cabecera de la sección, no escondida en cada tarjeta.
  function avanceActivo(numero: string, fuente: string, capital = 4000) {
    return {...structuredClone(inversionF5), fuente_id: fuente, empresa: 'avance' as const, numero,
      capital, estado: 'activo', perfil_id: PERFIL_F5,
      contrato: {fecha_inicio: '2026-09-01', tasa_anual: 15, modalidad: 'mensual' as const,
        tipo_interes: 'simple' as const, categoria: 'nuevo'}}
  }
  function fichaCon(...inversiones: InversionFuente[]) {
    const totales=inversiones.reduce<ResumenEmpresa[]>((filas,i)=>{
      const fila=filas.find(f=>f.empresa===i.empresa&&f.moneda===i.moneda)
      if(fila) {fila.cantidad++;fila.capital_registrado+=i.capital}
      else filas.push({empresa:i.empresa,moneda:i.moneda,cantidad:1,capital_registrado:i.capital,capital_activo:null})
      return filas
    },[])
    const ficha = {...structuredClone(fichaF5), inversiones, inversiones_total: inversiones.length,totales}
    api.ficha.mockResolvedValue(ficha)
    return ficha
  }
  it('con un solo contrato activo entra directo al upgrade, sin preguntar cuál amplía', async () => {
    fichaCon(avanceActivo('2026-01-000111', FUENTE_F5))
    const {user} = montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const seccion = (await screen.findByRole('heading',{name:'Inversiones y contratos'})).closest('section')!
    const upgrade = within(seccion).getByRole('button',{name:'Registrar upgrade'})
    expect(within(seccion).getByRole('button',{name:'Registrar nueva inversión'})).toBeEnabled()
    expect(within(seccion).getByText(/hereda la tasa del contrato que amplía/)).toBeVisible()
    await user.click(upgrade)
    expect(screen.queryByRole('dialog',{name:/amplía este upgrade/})).not.toBeInTheDocument()
    await waitFor(() => expect(screen.queryByRole('dialog',{name:'Ficha del inversionista'})).not.toBeInTheDocument())
  })
  it('con dos contratos activos pregunta cuál se amplía antes de abrir el upgrade', async () => {
    fichaCon(avanceActivo('2026-01-000111', FUENTE_F5, 4000), avanceActivo('2026-01-000222', PERFIL_F5, 9000))
    const {user} = montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const seccion = (await screen.findByRole('heading',{name:'Inversiones y contratos'})).closest('section')!
    await user.click(within(seccion).getByRole('button',{name:'Registrar upgrade'}))
    const dialogo = await screen.findByRole('dialog',{name:/amplía este upgrade/})
    expect(within(dialogo).getByRole('button',{name:/2026-01-000111/})).toBeInTheDocument()
    expect(within(dialogo).getByRole('button',{name:/S\/ 9,000/})).toBeInTheDocument()
    await user.click(within(dialogo).getByRole('button',{name:/2026-01-000222/}))
    await waitFor(() => expect(screen.queryByRole('dialog',{name:/amplía este upgrade/})).not.toBeInTheDocument())
  })
  it('sin contratos Avance activos y sin permiso de postventa no ofrece el upgrade', async () => {
    fichaCon({...structuredClone(inversionF5)})
    const {user} = montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})
    expect(screen.queryByRole('button',{name:/Registrar upgrade/})).not.toBeInTheDocument()
  })
})

describe('Upgrade cooperativo separado de reinversión', () => {
  it('la ficha muestra el evento upgrade confirmado sin perder la inversión original',async()=>{
    const ficha={...structuredClone(fichaF5),inversiones_total:2,
      inversiones:[inversionF5,{...inversionF5,fuente_id:PERFIL_F5,capital:250,numero:'APORTE ADICIONAL'}],
      historial_total:1,historial:[{id:FUENTE_F5,origen:'postventa' as const,tipo:'upgrade',empresa:'qorilazo' as const,
        detalle:'Upgrade confirmado · aporte adicional',creado_en:'2026-10-06T12:00:00Z'}]}
    // La RPC real y su historial se ejercitan también en el banco SQL.
    const {parse}=await import('valibot')
    const {FichaInversionistaSchema}=await import('@/lib/inversionistas')
    api.ficha.mockResolvedValue(parse(FichaInversionistaSchema,ficha))
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    expect(await screen.findByText('Upgrade confirmado · aporte adicional')).toBeVisible()
    expect(screen.getByRole('button',{name:'Ver inversión APORTE ADICIONAL'})).toBeVisible()
    expect(screen.getByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})).toBeVisible()
  })

  it.each(['qorilazo','prodelco'] as const)('%s ofrece ambos botones y abre el aporte adicional', async empresa => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),capacidades:{...fichaF5.capacidades,postventa:true},
      inversiones:[{...inversionF5,empresa}],totales:fichaF5.totales.map(t=>({...t,empresa}))})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const region=await screen.findByRole('region',{name:'Inversiones y contratos'})
    expect(within(region).getByRole('button',{name:'Registrar nueva inversión'})).toBeEnabled()
    expect(within(region).getByRole('button',{name:'Reinvertir desde esta inversión'})).toBeEnabled()
    await user.click(within(region).getByRole('button',{name:'Registrar upgrade'}))
    expect(await screen.findByRole('heading',{name:/^Upgrade ·/})).toBeVisible()
    expect(screen.getByLabelText('Aporte adicional en soles (PEN)')).toHaveValue('')
    expect(screen.getByText(/únicamente el dinero adicional/)).toBeVisible()
    expect(api.preparar).not.toHaveBeenCalled()
  })

  it.each(['vencido','anulado_comercialmente','demo','sin_permiso'] as const)('no ofrece upgrade para %s',async caso=>{
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),
      capacidades:{...fichaF5.capacidades,postventa:caso!=='sin_permiso'},
      inversiones:[{...inversionF5,estado:caso==='demo'||caso==='sin_permiso'?'vigente':caso,es_demo:caso==='demo'}]})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('region',{name:'Inversiones y contratos'})
    expect(screen.queryByRole('button',{name:/Registrar upgrade/})).not.toBeInTheDocument()
    if(caso==='vencido')expect(screen.getByRole('button',{name:'Reinvertir desde esta inversión'})).toBeEnabled()
  })

  it('guarda el upgrade y al reabrir desde reinversión recupera su tipo y origen reales',async()=>{
    let vigente=solicitud()
    api.preparar.mockImplementation(async i=>{vigente={...solicitud(i.clave),datos:i.datos,upgrade_origen_id:i.upgrade_origen_id,upgrade_origen_referencia:'ORIGEN CONSERVADO'};return vigente})
    api.consultar.mockImplementation(async()=>vigente)
    const vista=montar(true,{tipo:'upgrade',fuente:inversionF5})
    await vista.user.type(await screen.findByLabelText('Aporte adicional en soles (PEN)'),'250')
    await vista.user.type(screen.getByLabelText('Número de operación del depósito'),'UPGRADE-NUEVO-DEPOSITO')
    await vista.user.type(screen.getByLabelText('Plazo (meses)'),'12')
    await vista.user.type(screen.getByLabelText('Rentabilidad anual (%)'),'12')
    await vista.user.type(screen.getByLabelText('Referencia de la inversión'),'UPGRADE SINTÉTICO')
    await vista.user.upload(screen.getByLabelText(/Comprobante PDF/),new File(['pdf sintético'],'aporte.pdf',{type:'application/pdf'}))
    fireEvent.submit(screen.getByRole('button',{name:'Revisar upgrade'}).closest('form')!)
    await screen.findByRole('button',{name:'Confirmar upgrade'})
    expect(api.preparar).toHaveBeenCalledWith(expect.objectContaining({upgrade_origen_id:FUENTE_F5,
      datos:expect.objectContaining({monto:250,empresa:'qorilazo'})}))
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5)?.reinversion_origen_id).toBeUndefined()
    vista.unmount()
    montar(true,{tipo:'reinversion',fuente:{...inversionF5,fuente_id:PERFIL_F5}})
    expect(await screen.findByRole('button',{name:'Confirmar upgrade'})).toBeEnabled()
    expect(screen.getByRole('heading',{name:'Revisar upgrade'})).toBeVisible()
    expect(screen.getByText(/ORIGEN CONSERVADO/)).toBeVisible()
    expect(screen.queryByText(/Reinversión vinculada/)).not.toBeInTheDocument()
    expect(api.preparar).toHaveBeenCalledTimes(1)
  })

  it('un intento de reinversión pendiente se conserva al abrir el botón upgrade',async()=>{
    const datos={inversionista_id:PERSONA_F5,empresa:'qorilazo' as const,monto:250,moneda:'PEN' as const}
    guardarIntentoInversion(nuevoIntentoInversion(ACTOR_F5,PERSONA_F5,FUENTE_F5,datos,FUENTE_F5))
    api.consultar.mockResolvedValue({...solicitud(),datos,reinversion_origen_id:FUENTE_F5})
    montar(true,{tipo:'upgrade',fuente:inversionF5})
    expect(await screen.findByRole('button',{name:'Confirmar reinversión'})).toBeEnabled()
    expect(screen.getByRole('heading',{name:'Revisar reinversión'})).toBeVisible()
    expect(screen.queryByText(/Upgrade · aporte adicional/)).not.toBeInTheDocument()
    expect(api.preparar).not.toHaveBeenCalled()
  })
})

describe('Nueva inversión reservada a la primera inversión en cada empresa', () => {
  it('Qorilazo vigente permite nueva inversión únicamente en Avance y Prodelco', async () => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),capacidades:{...fichaF5.capacidades,postventa:true}})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const region=await screen.findByRole('region',{name:'Inversiones y contratos'})
    expect(within(region).getByRole('button',{name:'Registrar upgrade'})).toBeEnabled()
    expect(within(region).getByRole('button',{name:'Reinvertir desde esta inversión'})).toBeEnabled()
    const nueva=within(region).getByRole('button',{name:'Registrar nueva inversión'})
    expect(nueva).toBeEnabled()
    await user.click(nueva)
    const dialogo=await screen.findByRole('dialog',{name:'Nueva inversión'})
    expect(within(dialogo).getByRole('button',{name:'Avance'})).toBeEnabled()
    expect(within(dialogo).getByRole('button',{name:'Prodelco'})).toBeEnabled()
    expect(within(dialogo).queryByRole('button',{name:'Qorilazo'})).not.toBeInTheDocument()
  })

  it.each(['avance','qorilazo','prodelco'] as const)('una inversión en %s permite solamente las otras empresas', async empresa => {
    const ficha={...structuredClone(fichaF5),inversiones:[{...inversionF5,empresa}],totales:fichaF5.totales.map(t=>({...t,empresa}))}
    api.ficha.mockResolvedValue(ficha)
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const nueva=await screen.findByRole('button',{name:'Registrar nueva inversión'})
    expect(nueva).toBeEnabled()
    expect(nueva).toHaveAccessibleDescription(/primera inversión en/)
    await user.click(nueva)
    const dialogo=await screen.findByRole('dialog',{name:'Nueva inversión'})
    for(const [id,nombre] of Object.entries(EMPRESA_NOMBRE)) {
      if(id===empresa) expect(within(dialogo).queryByRole('button',{name:nombre})).not.toBeInTheDocument()
      else expect(within(dialogo).getByRole('button',{name:nombre})).toBeEnabled()
    }
  })

  it('bloquea con explicación si el total de inversiones no coincide con los totales por empresa', async () => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones:[],inversiones_total:26})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    expect(await screen.findByRole('button',{name:'Registrar nueva inversión'})).toBeDisabled()
    expect(screen.getByRole('button',{name:'Registrar nueva inversión'})).toHaveAccessibleDescription(/Falta verificar/)
  })

  it('cuenta empresas de otras páginas aunque el capital activo sea cero', async () => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones_total:40,
      totales:[{empresa:'avance',moneda:'USD',cantidad:12,capital_registrado:22000,capital_activo:0},
        {...fichaF5.totales[0],cantidad:28}]})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Registrar nueva inversión'}))
    const dialogo=await screen.findByRole('dialog',{name:'Nueva inversión'})
    expect(within(dialogo).getByRole('button',{name:'Prodelco'})).toBeEnabled()
    expect(within(dialogo).queryByRole('button',{name:'Avance'})).not.toBeInTheDocument()
    expect(within(dialogo).queryByRole('button',{name:'Qorilazo'})).not.toBeInTheDocument()
  })

  it('con historial en las tres empresas bloquea con explicación y conserva la recuperación', async () => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones_total:3,
      totales:Object.keys(EMPRESA_NOMBRE).map(empresa=>({...fichaF5.totales[0],empresa,cantidad:1}))})
    const vista=montar()
    await vista.user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const nueva=await screen.findByRole('button',{name:'Registrar nueva inversión'})
    expect(nueva).toBeDisabled()
    expect(nueva).toHaveAccessibleDescription(/inversiones registradas en las tres empresas/)
    vista.unmount()
    montar(true)
    expect(await screen.findByLabelText('Retomar una solicitud por su referencia')).toBeEnabled()
    for(const nombre of Object.values(EMPRESA_NOMBRE)) expect(screen.queryByRole('button',{name:nombre})).not.toBeInTheDocument()
  })

  it.each(['otra_inversion','error_lectura','permiso_revocado'] as const)('antes de preparar verifica el historial y se detiene ante %s', async caso => {
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Prodelco'}))
    await user.type(screen.getByLabelText('Capital en soles (PEN)'),'2500')
    await user.type(screen.getByLabelText('Número de operación del depósito'),'VERIFICAR-EMPRESA')
    await user.type(screen.getByLabelText('Plazo (meses)'),'12')
    await user.type(screen.getByLabelText('Rentabilidad anual (%)'),'12')
    await user.type(screen.getByLabelText('Referencia de la inversión'),'PRIMERA PRODELCO')
    await user.upload(screen.getByLabelText(/Comprobante PDF/),new File(['pdf sintético'],'prueba.pdf',{type:'application/pdf'}))
    if(caso==='error_lectura') api.ficha.mockRejectedValue(new CrmApiError('Sin respuesta al verificar','RED'))
    else if(caso==='permiso_revocado') api.ficha.mockResolvedValue({...structuredClone(fichaF5),
      capacidades:{...fichaF5.capacidades,nueva_inversion:false,motivo_no_operable:'Solo lectura'}})
    else api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones_total:2,
      totales:[...fichaF5.totales,{...fichaF5.totales[0],empresa:'prodelco',cantidad:1}]})
    fireEvent.submit(screen.getByRole('button',{name:'Revisar inversión'}).closest('form')!)
    if(caso==='error_lectura') expect(await screen.findByText('Sin respuesta al verificar')).toBeVisible()
    else if(caso==='permiso_revocado') expect(await screen.findByText('Solo lectura')).toBeVisible()
    else {
      expect(await screen.findByRole('button',{name:'Avance'})).toBeEnabled()
      expect(screen.queryByRole('button',{name:'Prodelco'})).not.toBeInTheDocument()
      expect(screen.getByRole('alert')).toHaveTextContent('Esta empresa ya tiene una inversión registrada')
      await user.click(screen.getByRole('button',{name:'Avance'}))
      expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    }
    expect(api.preparar).not.toHaveBeenCalled()
    expect(api.confirmar).not.toHaveBeenCalled()
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5)).toBeNull()
  })

  it('Avance también relee el historial antes de preparar el acceso', async () => {
    const {user}=montar(true)
    await user.click(await screen.findByRole('button',{name:'Avance'}))
    await user.type(screen.getByLabelText('Apellidos'),'PRUEBA')
    await user.type(screen.getByLabelText('Nombres'),'ANA')
    await user.type(screen.getByLabelText('Domicilio legal'),'Av. Prueba 123, Miraflores, Lima')
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones_total:2,
      totales:[...fichaF5.totales,{empresa:'avance',moneda:'PEN',cantidad:1,capital_registrado:1000,capital_activo:1000}]})
    await user.click(screen.getByRole('button',{name:'Revisar acceso Avance'}))
    expect(await screen.findByRole('button',{name:'Prodelco'})).toBeEnabled()
    expect(screen.queryByRole('button',{name:'Avance'})).not.toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('Esta empresa ya tiene una inversión registrada')
    expect(api.preparar).not.toHaveBeenCalled()
    expect(api.acceso).not.toHaveBeenCalled()
    expect(leerIntentoInversion(ACTOR_F5,PERSONA_F5)).toBeNull()
  })

  it('un cliente sin inversiones puede registrar su primera inversión', async () => {
    api.ficha.mockResolvedValue({...structuredClone(fichaF5),inversiones:[],inversiones_total:0,totales:[]})
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    const primera=await screen.findByRole('button',{name:'Registrar primera inversión'})
    expect(primera).toBeEnabled()
    await user.click(primera)
    expect(await screen.findByRole('dialog',{name:'Nueva inversión'})).toBeInTheDocument()
    expect(screen.getByRole('button',{name:'Avance'})).toBeEnabled()
  })
})

describe('Venta cruzada desde la Cartera', () => {
  it('ofrece buscar a un cliente de otra cartera', async () => {
    const {user}=montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    api.buscarCliente.mockResolvedValue({estado:'no_encontrado',busqueda_id:FUENTE_F5,criterio:'documento'})
    await user.click(screen.getByRole('button',{name:'Cliente de otra cartera'}))
    expect(screen.getByRole('dialog',{name:'Cliente de otra cartera'})).toBeInTheDocument()
  })

  it('un documento se busca en todos los meses, y si no está en la cartera se ofrece buscarlo en otras', async () => {
    api.lista.mockImplementation(async (f:{texto:string}) => f.texto
      ? {...structuredClone(carteraF5),total:0,filas:[],totales:[],sin_inversiones_total:0} : structuredClone(carteraF5))
    const {user}=montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    expect(api.lista.mock.calls[0]![0].mes).toMatch(/^\d{4}-\d{2}$/)
    await user.type(screen.getByLabelText('Buscar persona'),'70000021')
    await waitFor(() => expect(api.lista.mock.calls.at(-1)![0]).toMatchObject({texto:'70000021',mes:''}))
    expect(screen.getByText('Buscas un documento, un teléfono o un número de contrato: se muestran todos los meses.')).toBeInTheDocument()
    api.buscarCliente.mockResolvedValue({estado:'no_encontrado',busqueda_id:FUENTE_F5,criterio:'documento'})
    await user.click(await screen.findByRole('button',{name:'Buscar en otras carteras'}))
    await waitFor(() => expect(api.buscarCliente).toHaveBeenCalledWith({tipo:'documento',tipoDocumento:'DNI',numero:'70000021'}))
  })

  it('un nombre sigue filtrando por el mes elegido', async () => {
    const {user}=montar()
    await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'})
    const mes=api.lista.mock.calls[0]![0].mes
    await user.type(screen.getByLabelText('Buscar persona'),'Ana')
    await waitFor(() => expect(api.lista.mock.calls.at(-1)![0]).toMatchObject({texto:'Ana',mes}))
  })
})
