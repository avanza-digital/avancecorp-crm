import { useState } from 'react'
import { CalendarPlus, ClipboardList } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { PanelError } from '@/components/common/estado-panel'
import { FichaComercialSeccion } from './ficha-comercial'
import { ClienteGestion } from './cliente-gestion'
import { RecuperacionPostventa } from './postventa-envio'
import { useEnvioPostventa } from '@/data/use-envio-postventa'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { mensajeDeError } from '@/data/crm-api'
import { asignarResponsablePostventa } from '@/data/postventa-api'
import { refrescarPostventa, useFichaPostventa } from '@/data/postventa-queries'
import { EMPRESA_NOMBRE, type FichaInversionista, type InversionFuente } from '@/lib/inversionistas'
import { RETIRO_ETIQUETA, type EstadoRetiro, type RetiroPostventa } from '@/lib/postventa'
import { fechaHora, money } from '@/lib/format'

type AccionPersona = {tipo: 'agendar'} | {tipo: 'asignar'} | {tipo: 'veto'} | {tipo: 'solicitar_retiro'; fuente: InversionFuente} | {tipo: 'revisar_retiro'; retiro: RetiroPostventa}
export function PostventaPersona({actor, ficha, retiroElegido, onRetiroCerrado, deshabilitado = false}: {
  actor: string; ficha: FichaInversionista; retiroElegido: InversionFuente | null;
  onRetiroCerrado: () => void
  deshabilitado?: boolean
}) {
  const {yo} = useAuth()
  const q = useFichaPostventa(actor, ficha.persona.inversionista_id)
  const [accion, setAccion] = useState<AccionPersona | null>(null)
  const [ocupado, setOcupado] = useState(false)
  // La cola de supervisor es visible en F5 sin habilitar F6. Un rechazo de
  // esta sección no borra borradores F4; la propia ficha F5 revalida su ámbito.
  if (q.error) return <PanelError mensaje={mensajeDeError(q.error, 'No pudimos consultar las gestiones.')}
    onReintentar={() => void q.refetch()} reintentando={q.isFetching} />
  if (!q.isFetchedAfterMount || !q.isSuccess || !q.data.habilitada || yo?.demo) return null
  const actual: AccionPersona | null = retiroElegido ? {tipo: 'solicitar_retiro', fuente: retiroElegido} : accion
  const cerrar = () => {setAccion(null); onRetiroCerrado()}
  return <>
    <FichaComercialSeccion icono={CalendarPlus} titulo="Gestión de postventa">
      <div className="flex flex-wrap gap-2">
        <Button size="sm" disabled={deshabilitado || ficha.persona.no_contactar || !ficha.persona.responsable_id} onClick={() => setAccion({tipo: 'agendar'})}>Agendar gestión</Button>
        {yo?.rol === 'gerencia' && <Button size="sm" variant="outline" disabled={deshabilitado} onClick={() => setAccion({tipo: 'asignar'})}>{ficha.persona.responsable_id ? 'Cambiar responsable' : 'Asignar responsable'}</Button>}
        {(!ficha.persona.no_contactar || yo?.rol === 'gerencia') && <Button size="sm" variant="outline" disabled={deshabilitado} onClick={() => setAccion({tipo: 'veto'})}>{ficha.persona.no_contactar ? 'Levantar No contactar' : 'Marcar No contactar'}</Button>}
      </div>
      {!ficha.persona.responsable_id && <p className="text-xs text-muted-foreground">Gerencia debe asignar un responsable antes de programar el contacto.</p>}
    </FichaComercialSeccion>
    {q.data.retiros.length > 0 && <FichaComercialSeccion icono={ClipboardList} titulo="Solicitudes de retiro">
      <ul className="space-y-3">{q.data.retiros.map(r => <li key={r.id} className="space-y-1 rounded-lg border border-border p-3 text-sm">
        <p className="font-semibold">{EMPRESA_NOMBRE[r.empresa]} · {RETIRO_ETIQUETA[r.estado]}</p><p>{r.motivo}</p>
        {r.resolucion && <p>{r.resolucion}</p>}<p className="text-xs text-muted-foreground">{fechaHora(r.actualizado_en)}</p>
        {['solicitada', 'en_revision'].includes(r.estado) && <Button size="sm" variant="outline" disabled={deshabilitado} onClick={() => setAccion({tipo: 'revisar_retiro', retiro: r})}>
          {yo?.rol === 'gerencia' ? 'Revisar solicitud' : 'Cancelar solicitud'}
        </Button>}
      </li>)}</ul>
    </FichaComercialSeccion>}
    <Dialog open={actual !== null} onClose={() => {if (!ocupado) cerrar()}} ariaLabel="Gestión de postventa">
      {actual?.tipo === 'agendar' ? <ClienteGestion inversionistaId={ficha.persona.inversionista_id} clienteNombre={ficha.persona.nombre}
        onCerrar={cerrar} onEnviandoCambio={setOcupado} />
        : actual?.tipo === 'asignar' ? <AsignarResponsable ficha={ficha} actor={actor} onCerrar={cerrar} onOcupado={setOcupado} />
          : actual && <TramitePostventa key={actual.tipo === 'revisar_retiro' ? actual.retiro.id : actual.tipo === 'solicitar_retiro' ? actual.fuente.fuente_id : actual.tipo}
            actor={actor} ficha={ficha} accion={actual} gerencia={yo?.rol === 'gerencia'} onCerrar={cerrar} onOcupado={setOcupado} />}
    </Dialog>
  </>
}
function AsignarResponsable({ficha, actor, onCerrar, onOcupado}: {ficha: FichaInversionista; actor: string; onCerrar: () => void; onOcupado: (b: boolean) => void}) {
  const {equipo, recargar} = useCRMData()
  const [responsable, setResponsable] = useState(ficha.persona.responsable_id ?? '')
  const [motivo, setMotivo] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [ocupado, setOcupado] = useState(false)
  async function guardar() {
    setOcupado(true); onOcupado(true); setError(null)
    try {
      await asignarResponsablePostventa(ficha.persona.inversionista_id, responsable, motivo)
      await Promise.all([recargar(), refrescarPostventa(actor)]); toast.success('Responsable actualizado.'); onCerrar()
    } catch (e) {setError(mensajeDeError(e, 'No pudimos actualizar el responsable.'))}
    finally {setOcupado(false); onOcupado(false)}
  }
  return <><DialogHeader><DialogTitle>Asignar responsable de relación</DialogTitle></DialogHeader>
    <DialogBody className="space-y-3"><Label htmlFor="pv-responsable">Responsable</Label>
      <Select id="pv-responsable" value={responsable} onChange={e => setResponsable(e.target.value)} disabled={ocupado}>
        <option value="">Selecciona un responsable</option>
        {equipo.filter(m => m.activo && ['vendedor', 'supervisor', 'gerencia'].includes(m.rol_crm)).map(m => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
      </Select><Label htmlFor="pv-motivo-responsable">Motivo, sin números de documento</Label>
      <Textarea id="pv-motivo-responsable" value={motivo} onChange={e => setMotivo(e.target.value)} minLength={3} maxLength={500} disabled={ocupado} />
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </DialogBody><DialogFooter><Button variant="outline" onClick={onCerrar} disabled={ocupado}>Cerrar</Button>
      <Button disabled={ocupado || !responsable || motivo.trim().length < 3} onClick={() => void guardar()}>Guardar responsable</Button></DialogFooter></>
}
function TramitePostventa({actor, ficha, accion, gerencia, onCerrar, onOcupado}: {
  actor: string; ficha: FichaInversionista; accion: Exclude<AccionPersona, {tipo: 'agendar' | 'asignar'}>;
  gerencia: boolean; onCerrar: () => void; onOcupado: (b: boolean) => void
}) {
  const {recargar} = useCRMData()
  const sujeto = accion.tipo === 'revisar_retiro' ? accion.retiro.id : accion.tipo === 'solicitar_retiro' ? accion.fuente.fuente_id : ficha.persona.inversionista_id
  const envio = useEnvioPostventa(actor, accion.tipo, sujeto)
  const [detalle, setDetalle] = useState('')
  const [estado, setEstado] = useState<EstadoRetiro>(accion.tipo === 'revisar_retiro' && gerencia
    ? accion.retiro.estado === 'solicitada' ? 'en_revision' : 'revisada' : 'cancelada')
  const titulo = accion.tipo === 'veto' ? ficha.persona.no_contactar ? 'Levantar No contactar' : 'Marcar No contactar'
    : accion.tipo === 'solicitar_retiro' ? 'Registrar solicitud de retiro' : 'Revisar solicitud de retiro'
  async function guardar(recuperar = false) {
    onOcupado(true)
    try {
      const parametros = accion.tipo === 'veto' ? {p_inversionista: ficha.persona.inversionista_id, p_vetar: !ficha.persona.no_contactar, p_motivo: detalle}
        : accion.tipo === 'solicitar_retiro' ? {p_inversionista: ficha.persona.inversionista_id, p_fuente: accion.fuente.fuente_id, p_motivo: detalle}
          : {p_retiro: accion.retiro.id, p_revision: accion.retiro.revision, p_estado: estado, p_detalle: detalle}
      if (await envio.ejecutar(recuperar ? undefined : parametros)) {
        await Promise.all([recargar(), refrescarPostventa(actor)]); toast.success('Gestión registrada.'); onCerrar()
      }
    } finally {onOcupado(false)}
  }
  return <><DialogHeader><DialogTitle>{titulo}</DialogTitle></DialogHeader><DialogBody className="space-y-3">
    {(envio.pendiente || envio.bloqueado) ? <RecuperacionPostventa envio={envio} onRecuperar={() => void guardar(true)} /> : <>
      {accion.tipo === 'solicitar_retiro' && <><p className="font-medium">{EMPRESA_NOMBRE[accion.fuente.empresa]} · {money(accion.fuente.capital, accion.fuente.moneda)}</p>
        <p className="text-sm text-muted-foreground">Registra la solicitud recibida del cliente para que Gerencia revise su seguimiento.</p></>}
      {accion.tipo === 'revisar_retiro' && <><p className="text-sm">{accion.retiro.motivo}</p><Label htmlFor="pv-retiro-estado">Estado de la revisión</Label>
        <Select id="pv-retiro-estado" value={estado} onChange={e => setEstado(e.target.value as EstadoRetiro)}>
          {gerencia && (accion.retiro.estado === 'solicitada' ? <option value="en_revision">Iniciar revisión</option> : <><option value="revisada">Revisión terminada</option><option value="rechazada">Solicitud rechazada</option></>)}
          <option value="cancelada">Cancelar solicitud</option>
        </Select></>}
      <Label htmlFor="pv-tramite-detalle">{accion.tipo === 'veto' ? 'Motivo, sin números de documento' : 'Detalle'}</Label>
      <Textarea id="pv-tramite-detalle" value={detalle} onChange={e => setDetalle(e.target.value)} minLength={3} maxLength={accion.tipo === 'veto' ? 500 : 1900} />
      {envio.error && <p role="alert" className="text-sm text-destructive">{envio.error}</p>}
    </>}
  </DialogBody><DialogFooter><Button variant="outline" onClick={onCerrar} disabled={envio.ocupado}>Cerrar</Button>
    {!envio.pendiente && !envio.bloqueado && <Button disabled={envio.ocupado || detalle.trim().length < 3} onClick={() => void guardar()}>Guardar gestión</Button>}
  </DialogFooter></>
}
