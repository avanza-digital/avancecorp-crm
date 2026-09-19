// Simulación local: comparte los campos financieros y nunca llama a las
// puertas de Auth, conversión o inversión del servidor.
import {useRef,useState} from 'react'
import {Button} from '@/components/ui/button'
import {Dialog,DialogBody,DialogFooter,DialogHeader,DialogTitle} from '@/components/ui/dialog'
import {useAuth} from '@/lib/auth-context'
import {useCRMData} from '@/lib/store-context'
import type {Lead} from '@/lib/tipos'
import {EMPRESAS_INVERSION,EMPRESA_NOMBRE,type EmpresaInversion} from '@/lib/inversionistas'
import {datosAvanceRevisados,type DatosInversion} from '@/lib/inversion-solicitud'
import {prepararPayloadContrato,type CondicionesTasaLead} from '@/data/crm-api'
import {ContratoNuevo} from './contrato-nuevo'
import {InversionCooperativa,ResumenRevision} from './inversion-nueva'

export function InversionDesdeLeadDemo({l,onClose,condicionesTasa}: {
  l:Lead;onClose:()=>void;condicionesTasa?:CondicionesTasaLead|undefined
}) {
  const {yo}=useAuth()
  const {convertir,convertirExterno}=useCRMData()
  const [empresa,setEmpresa]=useState<EmpresaInversion|null>(null)
  const [datos,setDatos]=useState<DatosInversion|null>(null)
  const [confirmada,setConfirmada]=useState(false)
  const [error,setError]=useState<string|null>(null)
  const [persona]=useState(()=>crypto.randomUUID())
  const enviada=useRef(false)
  if (!yo?.demo) return null
  const base:DatosInversion={inversionista_id:persona,empresa:empresa??'avance'}
  return <Dialog open onClose={onClose} ariaLabel="Nueva inversión (demo)" className="w-[760px]">
    {!empresa ? <><DialogHeader><DialogTitle>Nueva inversión (demo)</DialogTitle></DialogHeader>
      <DialogBody className="space-y-4"><p className="text-sm">{l.nombre_completo} · Elige la empresa en la que invertirá.</p>
        <div className="grid gap-3 sm:grid-cols-3">{EMPRESAS_INVERSION.map(e=><Button key={e} variant="outline" onClick={()=>setEmpresa(e)}>{EMPRESA_NOMBRE[e]}</Button>)}</div>
      </DialogBody></> : confirmada ? <><DialogHeader><DialogTitle>Inversión confirmada (demo)</DialogTitle></DialogHeader>
      <DialogBody><p role="status">El lead quedó convertido en la simulación.</p></DialogBody></>
      : datos ? <><DialogHeader><DialogTitle>Revisar inversión (demo)</DialogTitle></DialogHeader>
        <DialogBody className="space-y-4"><ResumenRevision datos={datos}/>
          <p className="text-sm">Analista: {l.vendedor_nombre??'Analista del lead'}</p>
          {error&&<p role="alert" className="text-sm text-destructive-text">{error}</p>}
          <Button onClick={()=>{
            if(enviada.current)return
            enviada.current=true
            const r=datos.empresa==='avance'?convertir(l.id):convertirExterno(l.id,{
              cooperativa:datos.empresa,monto:datos.monto!,moneda:datos.moneda!,numeroTransaccion:datos.numero_transaccion!,
              plazoMeses:datos.plazo_meses!,tasaAnual:datos.tasa_anual!,venceEn:datos.vence_en!,
            })
            if(!r.ok){enviada.current=false;setError(r.error??'No se pudo confirmar la simulación.');return}
            setConfirmada(true)
          }}>Confirmar inversión (demo)</Button>
        </DialogBody></>
      : empresa==='avance' ? <ContratoNuevo clienteId={persona} clienteNombre={l.nombre_completo} categoriaFija="nuevo"
          condicionesIniciales={condicionesTasa} montoSugerido={l.monto_estimado} monedaSugerida={l.moneda}
          analistas={l.vendedor_id?[{perfil_id:l.vendedor_id,nombre_completo:l.vendedor_nombre??'Analista del lead'}]:[]}
          analistaInicial={l.vendedor_id??null} onCreado={()=>{}} onOmitir={onClose}
          onRevisar={async(input,cuotas)=>{setDatos(datosAvanceRevisados(base,prepararPayloadContrato(input),cuotas,input.cuenta_pago))}}/>
        : <><DialogHeader><DialogTitle>Nueva inversión · {EMPRESA_NOMBRE[empresa]} (demo)</DialogTitle></DialogHeader>
          <DialogBody><InversionCooperativa datos={base} ocupado={false} correccion={false} motivo="" onMotivo={()=>{}}
            onGuardar={async d=>{setDatos(d)}}/></DialogBody></>}
    <DialogFooter><Button variant="outline" onClick={onClose}>{confirmada?'Cerrar':'Cancelar'}</Button></DialogFooter>
  </Dialog>
}
