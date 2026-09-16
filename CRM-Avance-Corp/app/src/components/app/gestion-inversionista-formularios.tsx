import { useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { useEnvioPostventa } from '@/data/use-envio-postventa'
import { corregirDocumentoInversionista, type GestionInversionista, type GestionInversion } from '@/data/gestion-inversionista'
import { mensajeDeError } from '@/data/crm-api'
import { RecuperacionPostventa } from './postventa-envio'
import { useVentana } from '@/lib/ventana'

interface Base {actor:string; persona:string; permitido:boolean; onCerrar:()=>void; onGuardado:()=>void; onEnviando:(enviando:boolean)=>void}
export function CorregirContactoNeutral({actor,persona,datos,permitido,onCerrar,onGuardado,onEnviando}:Base & {datos:GestionInversionista['contacto']}) {
  const [base] = useState(datos)
  const [nombre,setNombre] = useState(base.nombre_completo)
  const [telefono,setTelefono] = useState(base.telefono ?? '')
  const [domicilio,setDomicilio] = useState(base.domicilio ?? '')
  const envio = useEnvioPostventa(actor,'corregir_contacto',persona)
  const ventana = useVentana(base.creado_en)
  const ocupado = useRef(false)
  const guardar = async (recuperar = false) => {
    if (ocupado.current || (!recuperar && !permitido)) return
    ocupado.current=true; onEnviando(true)
    try {
      if (await envio.ejecutar(recuperar ? undefined : {p_inversionista:persona,p_revision:base.revision,
        p_datos:{nombre_completo:nombre.trim(),telefono:telefono.trim() || null,domicilio:domicilio.trim() || null}})) onGuardado()
    } finally {ocupado.current=false; onEnviando(false)}
  }
  return <>
    <DialogHeader><DialogTitle>Corregir datos del cliente</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <p className="text-xs text-muted-foreground">{base.sin_limite ? 'Corrección administrativa.' : `Ventana de cinco horas: ${ventana.texto}.`} Los datos de las inversiones anteriores se conservan.</p>
      {envio.pendiente ? <RecuperacionPostventa envio={envio} onRecuperar={() => void guardar(true)} /> : <>
        <div className="space-y-1"><Label htmlFor="neutral-nombre">Nombres y apellidos</Label><Input id="neutral-nombre" value={nombre} maxLength={200} onChange={e=>setNombre(e.target.value)} disabled={envio.ocupado} /></div>
        <div className="space-y-1"><Label htmlFor="neutral-telefono">Teléfono</Label><Input id="neutral-telefono" type="tel" value={telefono} maxLength={32} onChange={e=>setTelefono(e.target.value)} disabled={envio.ocupado} /></div>
        <div className="space-y-1"><Label htmlFor="neutral-domicilio">Domicilio</Label><Textarea id="neutral-domicilio" value={domicilio} maxLength={500} onChange={e=>setDomicilio(e.target.value)} disabled={envio.ocupado} /></div>
        {!permitido && <p role="status" className="text-xs text-muted-foreground">La corrección requiere el responsable autorizado y una ventana vigente, o una autorización administrativa.</p>}
        {envio.error && <p role="alert" className="text-sm text-destructive">{envio.error}</p>}
      </>}
    </DialogBody>
    <DialogFooter><Button variant="outline" onClick={onCerrar} disabled={envio.ocupado}>Cancelar corrección</Button>
      {!envio.pendiente && <Button onClick={()=>void guardar()} disabled={!permitido || envio.ocupado || envio.bloqueado || nombre.trim().length<2 || (!base.sin_limite && !ventana.vigente)}>{envio.ocupado ? 'Guardando…' : 'Guardar corrección'}</Button>}
    </DialogFooter>
  </>
}

export function CorregirInversionCoopac({actor,persona,inversion,permitido,onCerrar,onGuardado,onEnviando}:Base & {inversion:GestionInversion & {coopac:NonNullable<GestionInversion['coopac']>}}) {
  const [base] = useState(inversion.coopac)
  const [monto,setMonto] = useState(String(base.monto))
  const [operacion,setOperacion] = useState(base.numero_transaccion)
  const [referencia,setReferencia] = useState(base.referencia ?? '')
  const [nota,setNota] = useState(base.nota ?? '')
  const [plazo,setPlazo] = useState(base.plazo_meses === null ? '' : String(base.plazo_meses))
  const [tasa,setTasa] = useState(base.tasa_anual === null ? '' : String(base.tasa_anual))
  const [vence,setVence] = useState(base.vence_en ?? '')
  const envio=useEnvioPostventa(actor,'corregir_coopac',inversion.fuente_id)
  const ocupado=useRef(false)
  const guardar=async(recuperar=false)=>{
    if(ocupado.current || (!recuperar && !permitido)) return
    ocupado.current=true;onEnviando(true)
    try {if(await envio.ejecutar(recuperar ? undefined : {p_inversionista:persona,p_fuente:inversion.fuente_id,p_revision:base.revision,
      p_datos:{monto:Number(monto),numero_transaccion:operacion.trim(),referencia:referencia.trim() || null,nota:nota.trim() || null,
        plazo_meses:plazo ? Number(plazo) : null,tasa_anual:tasa ? Number(tasa) : null,vence_en:vence || null}}))onGuardado()
    }finally{ocupado.current=false;onEnviando(false)}
  }
  return <>
    <DialogHeader><DialogTitle>Corregir inversión en cooperativa</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <p className="text-xs text-muted-foreground">Corrección de Gerencia. La empresa, la moneda, el cliente y el autor original se conservan.</p>
      {envio.pendiente ? <RecuperacionPostventa envio={envio} onRecuperar={()=>void guardar(true)} /> : <>
        <div className="space-y-1"><Label htmlFor="coopac-monto">Capital en soles</Label><Input id="coopac-monto" type="number" min="0.01" step="0.01" value={monto} onChange={e=>setMonto(e.target.value)} disabled={envio.ocupado} /></div>
        <div className="space-y-1"><Label htmlFor="coopac-operacion">Número de operación</Label><Input id="coopac-operacion" value={operacion} maxLength={64} onChange={e=>setOperacion(e.target.value)} disabled={envio.ocupado} /></div>
        <div className="space-y-1"><Label htmlFor="coopac-referencia">Certificado o referencia</Label><Input id="coopac-referencia" value={referencia} maxLength={64} onChange={e=>setReferencia(e.target.value)} disabled={envio.ocupado} /></div>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1"><Label htmlFor="coopac-plazo">Plazo en meses</Label><Input id="coopac-plazo" type="number" min="1" max="1200" step="1" value={plazo} onChange={e=>setPlazo(e.target.value)} disabled={envio.ocupado} /></div>
          <div className="space-y-1"><Label htmlFor="coopac-tasa">Rentabilidad anual (%)</Label><Input id="coopac-tasa" type="number" min="0.01" step="0.01" value={tasa} onChange={e=>setTasa(e.target.value)} disabled={envio.ocupado} /></div>
        </div>
        {base.plazo_meses===null && !plazo && !tasa ? <div className="space-y-1"><Label htmlFor="coopac-vence">Vencimiento histórico</Label><Input id="coopac-vence" type="date" value={vence} onChange={e=>setVence(e.target.value)} disabled={envio.ocupado} /></div>
          : <p className="text-xs text-muted-foreground">El vencimiento se ajustará al plazo desde la fecha comercial original.</p>}
        <div className="space-y-1"><Label htmlFor="coopac-nota">Notas de la operación</Label><Textarea id="coopac-nota" value={nota} maxLength={2000} onChange={e=>setNota(e.target.value)} disabled={envio.ocupado} /></div>
        {envio.error && <p role="alert" className="text-sm text-destructive">{envio.error}</p>}
      </>}
    </DialogBody>
    <DialogFooter><Button variant="outline" disabled={envio.ocupado} onClick={onCerrar}>Volver a la inversión</Button>
      {!envio.pendiente && <Button onClick={()=>void guardar()} disabled={!permitido || envio.ocupado || envio.bloqueado || !(Number(monto)>0) || !operacion.trim() || Boolean(plazo)!==Boolean(tasa)}>{envio.ocupado?'Guardando…':'Guardar corrección'}</Button>}
    </DialogFooter>
  </>
}

export function CorregirDocumentoNeutral({persona,datos,permitido,onCerrar,onGuardado,onEnviando}:Omit<Base,'actor'> & {datos:GestionInversionista['documento']}) {
  const [base]=useState(datos)
  const [tipo,setTipo]=useState(base.tipo ?? 'DNI')
  const [numero,setNumero]=useState(base.numero ?? '')
  const [motivo,setMotivo]=useState('')
  const [error,setError]=useState('')
  const [enviando,setEnviando]=useState(false)
  const ocupado=useRef(false)
  async function guardar(){
    if(ocupado.current || !permitido)return
    ocupado.current=true;setEnviando(true);onEnviando(true);setError('')
    try{await corregirDocumentoInversionista(persona,base,tipo,numero,motivo);onGuardado()}
    catch(e){setError(mensajeDeError(e,'No se pudo confirmar la corrección del documento.'))}
    finally{ocupado.current=false;setEnviando(false);onEnviando(false)}
  }
  return <>
    <DialogHeader><DialogTitle>Corregir documento del cliente</DialogTitle></DialogHeader>
    <DialogBody className="space-y-4">
      <p className="text-xs text-muted-foreground">Corrección administrativa con motivo y registro de auditoría.</p>
      <div className="space-y-1"><Label htmlFor="neutral-tipo">Tipo de documento</Label><Select id="neutral-tipo" value={tipo} onChange={e=>setTipo(e.target.value)} disabled={enviando}>
        <option>DNI</option><option>CE</option><option>PASAPORTE</option></Select></div>
      <div className="space-y-1"><Label htmlFor="neutral-documento">Número de documento</Label><Input id="neutral-documento" value={numero} maxLength={12} onChange={e=>setNumero(e.target.value)} disabled={enviando} /></div>
      <div className="space-y-1"><Label htmlFor="neutral-motivo">Motivo de la corrección</Label><Textarea id="neutral-motivo" value={motivo} maxLength={500} onChange={e=>setMotivo(e.target.value)} disabled={enviando} /></div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </DialogBody>
    <DialogFooter><Button variant="outline" disabled={enviando} onClick={onCerrar}>Cancelar</Button><Button disabled={enviando || !permitido || !numero.trim() || motivo.trim().length<3} onClick={()=>void guardar()}>{enviando?'Guardando…':'Corregir documento'}</Button></DialogFooter>
  </>
}
