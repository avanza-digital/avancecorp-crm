import {ContratoEliminacionError} from '@/lib/contrato-pdf-archivo'
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest'
import {act, cleanup, fireEvent, render, screen, waitFor, within} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {QueryClient, QueryClientProvider} from '@tanstack/react-query'
import {CarteraInversionistas} from './cartera-inversionistas'
import {InversionNueva} from '@/components/app/inversion-nueva'
import {CrmApiError} from '@/data/crm-api'
import {ACTOR_F5, carteraF5, fichaF5, FUENTE_F5, PERSONA_F5, PERFIL_F5} from '@/test/fixtures/f5'
import {inversionistasKeys} from '@/data/inversionistas-queries'
import {leerIntentoInversion, guardarIntentoInversion, nuevoIntentoInversion, type SolicitudInversion} from '@/lib/inversion-solicitud'

vi.mock('@/data/postventa-api', () => ({estadoPostventa: vi.fn().mockResolvedValue({version: 1, habilitada: false}), fichaPostventa: (...args: unknown[]) => api.postventa(...args)}))
const sesion = vi.hoisted(() => ({rolPortal: 'directorio', rol:'gerencia', demo: false}))
vi.mock('@/lib/auth-context', () => ({useAuth: () => ({yo: {id: ACTOR_F5, rol: sesion.rol, rol_portal: sesion.rolPortal, demo: sesion.demo}})}))

const api = vi.hoisted(() => ({lista:vi.fn(), ficha:vi.fn(), bancos:vi.fn(), documento:vi.fn(), consultar:vi.fn(), preparar:vi.fn(),
  corregir:vi.fn(), responsable:vi.fn(), confirmar:vi.fn(), acceso:vi.fn(), subir:vi.fn(), postventa:vi.fn(), eliminar:vi.fn()}))
vi.mock('@/lib/contrato-pdf-archivo', async (original) => ({...await original<typeof import('@/lib/contrato-pdf-archivo')>(), eliminarContratoConPdf:api.eliminar}))
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
  vi.clearAllMocks(); sesion.rolPortal='directorio'; sesion.rol='gerencia'; sesion.demo=false; sessionStorage.clear(); history.replaceState(null, '', '#/mi-cartera')
  api.postventa.mockResolvedValue({version:1,habilitada:true,retiros:[]})
  api.lista.mockResolvedValue(structuredClone(carteraF5)); api.ficha.mockResolvedValue(structuredClone(fichaF5)); api.bancos.mockResolvedValue([])
})
afterEach(() => {cleanup(); vi.restoreAllMocks()})
describe('F5: cartera y ficha con acceso vigente', () => {
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
  it('el resumen comercial usa capital registrado del núcleo aunque el capital activo sea distinto', async () => {
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
    expect(screen.getByRole('button',{name:'Registrar nueva inversión'})).toBeDisabled()
    expect(screen.getByText('Abrir WhatsApp').closest('a')).not.toHaveAttribute('href')
    api.ficha.mockResolvedValue(structuredClone(fichaF5))
    await user.click(screen.getByRole('button',{name:'Reintentar actualización'}))
    await waitFor(()=>expect(screen.getByRole('button',{name:'Registrar nueva inversión'})).toBeEnabled())
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
    api.ficha.mockResolvedValue(d)
    api.documento.mockImplementationOnce((_p,_f,_d,signal:AbortSignal)=>new Promise((_r,reject)=>{
      signal.addEventListener('abort',()=>reject(new DOMException('Cancelada','AbortError')),{once:true})
    })).mockResolvedValue(undefined)
    const {user}=montar();await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'}))
    await user.click(await screen.findByRole('button',{name:'Documento del ensayo'}))
    await user.click(screen.getByRole('button',{name:'Registrar nueva inversión'}))
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
  it('prepara sin éxito anticipado, confirma con revisión devuelta y recupera un corte sin otra alta',async () => {
    let vigente=solicitud()
    api.preparar.mockImplementation(async intento=> {vigente={...solicitud(intento.clave),revision_datos:3,datos:intento.datos}; return vigente})
    api.consultar.mockImplementation(async()=>vigente)
    api.confirmar.mockImplementation(async()=> {vigente={...vigente,estado:'confirmada',resultado:{...resultado,solicitud_id:vigente.solicitud_id}}; throw new CrmApiError('Respuesta perdida','RED')})
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


describe('Eliminación administrativa de contratos desde la ficha', () => {
  function contratoAvance() {
    const ficha=structuredClone(fichaF5)
    ficha.inversiones[0]!.empresa='avance'
    ficha.inversiones[0]!.numero='2026-01-999999'
    ficha.inversiones[0]!.perfil_id=PERFIL_F5
    ficha.inversiones[0]!.contrato={fecha_inicio:'2026-09-01',tasa_anual:15,modalidad:'mensual',tipo_interes:'simple',categoria:'nuevo'}
    api.ficha.mockResolvedValue(ficha)
    return ficha
  }
  it.each(['admin','superadmin'])('%s confirma el número y actualiza cartera tras conservar auditoría',async(rol)=>{
    sesion.rolPortal=rol
    const ficha=contratoAvance()
    api.eliminar.mockImplementation(async()=>{
      api.ficha.mockResolvedValue({...ficha,inversiones:[],inversiones_total:0})
      return {contratoId:FUENTE_F5,auditoriaId:PERFIL_F5,archivosConservados:2}
    })
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Eliminar contrato 2026-01-999999'}))
    const dialogo=screen.getByRole('dialog',{name:'Eliminar contrato 2026-01-999999'})
    expect(within(dialogo).getByText(/incluidos los pagos registrados/)).toBeVisible()
    const confirmar=within(dialogo).getByRole('button',{name:'Eliminar y conservar auditoría'})
    expect(confirmar).toBeDisabled()
    await user.type(within(dialogo).getByLabelText('Escribe 2026-01-999999 para confirmar'),'incorrecto')
    expect(confirmar).toBeDisabled()
    await user.clear(within(dialogo).getByRole('textbox'))
    await user.type(within(dialogo).getByRole('textbox'),'2026-01-999999')
    expect(api.eliminar).not.toHaveBeenCalled()
    await user.click(confirmar)
    await waitFor(()=>expect(api.eliminar).toHaveBeenCalledExactlyOnceWith(FUENTE_F5))
    await waitFor(()=>expect(screen.queryByRole('dialog',{name:'Eliminar contrato 2026-01-999999'})).not.toBeInTheDocument())
    expect(await screen.findByText('Este cliente todavía no tiene una inversión registrada.')).toBeVisible()
  })
  it.each(['analista','directorio','operaciones'])('oculta eliminar para %s',async(rol)=>{
    sesion.rolPortal=rol;contratoAvance()
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Ver inversión 2026-01-999999'})
    expect(screen.queryByRole('button',{name:/Eliminar contrato/})).not.toBeInTheDocument()
  })
  it('cancelar no borra y un rechazo del servidor conserva el contrato y muestra el motivo',async()=>{
    sesion.rolPortal='admin';contratoAvance()
    api.eliminar.mockRejectedValue(new ContratoEliminacionError('El contrato forma parte del historial de inversiones'))
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await user.click(await screen.findByRole('button',{name:'Eliminar contrato 2026-01-999999'}))
    await user.click(screen.getByRole('button',{name:'Cancelar'}))
    expect(api.eliminar).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button',{name:'Eliminar contrato 2026-01-999999'}))
    const dialogo=screen.getByRole('dialog',{name:'Eliminar contrato 2026-01-999999'})
    await user.type(within(dialogo).getByRole('textbox'),'2026-01-999999')
    await user.click(within(dialogo).getByRole('button',{name:'Eliminar y conservar auditoría'}))
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('historial de inversiones')
    expect(api.eliminar).toHaveBeenCalledExactlyOnceWith(FUENTE_F5)
  })
  it('el administrador no recibe borrado Avance para cooperativas',async()=>{
    sesion.rolPortal='admin'
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Ver inversión QORILAZO SINTÉTICO'})
    expect(screen.queryByRole('button',{name:/Eliminar contrato/})).not.toBeInTheDocument()
  })
  it.each(['demo','sin contrato','historial'] as const)('protege una ficha en estado %s',async(estado)=>{
    sesion.rolPortal='admin'
    const ficha=contratoAvance()
    if(estado==='demo') sesion.demo=true
    if(estado==='sin contrato') ficha.inversiones[0]!.contrato=null
    if(estado==='historial') ficha.inversiones[0]!.inversion_id=FUENTE_F5
    api.ficha.mockResolvedValue(ficha)
    const {user}=montar()
    await user.click(await screen.findByRole('button',{name:'Abrir ficha de ANA SINTÉTICA F5'}))
    await screen.findByRole('button',{name:'Ver inversión 2026-01-999999'})
    const borrar=screen.queryByRole('button',{name:/Eliminar contrato/})
    if(estado==='historial') expect(borrar).toBeDisabled()
    else expect(borrar).not.toBeInTheDocument()
    expect(api.eliminar).not.toHaveBeenCalled()
  })
})
