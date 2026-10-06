import { useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { fechaLima, horaLima } from '@/lib/agenda-derivada'
import { isoDeCampos } from '@/lib/campos-siguiente'
import { CAMPOS_REUNION_VACIOS, CamposReunion, camposTareaDeReunion, type EstadoCamposReunion } from './campos-reunion'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { RESULTADOS } from '@/lib/resultado-llamada'
import { refrescarPostventa } from '@/data/postventa-queries'
import { RESULTADOS_REUNION, type ResultadoReunionOperativo, type Tarea, type TipoTarea } from '@/lib/tipos'
import { RecuperacionPostventa } from './postventa-envio'
import { useEnvioPostventa } from '@/data/use-envio-postventa'

type Accion = 'completada' | 'cancelada' | 'no_show' | 'confirmar' | 'reprogramar'
export function FormTareaPostventa({tarea, onCerrar, onOcupado}: {
  tarea: Tarea; onCerrar: () => void; onOcupado: (ocupado: boolean) => void
}) {
  const {yo} = useAuth()
  const {recargar} = useCRMData()
  const actor = yo?.id ?? ''
  const envio = useEnvioPostventa(actor, 'tarea', tarea.id)
  const [accion, setAccion] = useState<Accion>('completada')
  const [resultado, setResultado] = useState('')
  const [resultadoReunion, setResultadoReunion] = useState<ResultadoReunionOperativo | ''>('')
  const [detalle, setDetalle] = useState('')
  const [fecha, setFecha] = useState(() => fechaLima(Date.now() + 86400000))
  const [hora, setHora] = useState(() => horaLima(Date.now() + 86400000))
  const [siguiente, setSiguiente] = useState(false)
  const [titulo, setTitulo] = useState('Seguimiento de postventa')
  const [tipo, setTipo] = useState<TipoTarea>('llamada')
  const [camposReunion, setCamposReunion] = useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)
  const exigeSiguiente = accion === 'completada' && tarea.tipo === 'llamada' &&
    (resultado === 'agendo_reunion' || resultado === 'volver_a_llamar')
  const conSiguiente = ['completada', 'no_show'].includes(accion) && (siguiente || exigeSiguiente)
  async function guardar(recuperar = false) {
    if (!actor || !tarea.inversionista_id || !tarea.postventa_revision || yo?.demo) return
    const iso = isoDeCampos({tipo, titulo, fecha, hora})
    if (!recuperar && accion === 'completada' && tarea.tipo === 'llamada' && !resultado) {toast.error('Selecciona qué pasó en la llamada.'); return}
    if (!recuperar && accion === 'completada' && tarea.tipo === 'whatsapp' && !resultado) {toast.error('Selecciona el resultado del WhatsApp.'); return}
    if (!recuperar && accion === 'completada' && tarea.tipo === 'reunion' && !resultadoReunion) {toast.error('Selecciona el resultado comercial de la entrevista.'); return}
    if (!recuperar && (accion === 'reprogramar' || conSiguiente) && !iso) {toast.error('Elige una fecha y hora válidas.'); return}
    const reunion = conSiguiente && tipo === 'reunion' ? validarReunionOperativa(camposReunion) : null
    if (!recuperar && reunion && !reunion.ok) {toast.error(reunion.error); return}
    onOcupado(true)
    try {
      const confirmada = await envio.ejecutar(recuperar ? undefined : {
        p_tarea: tarea.id, p_revision: tarea.postventa_revision,
        p_accion: accion === 'reprogramar' || accion === 'confirmar' ? accion : 'cerrar',
        p_datos: accion === 'confirmar' ? {} : accion === 'reprogramar' ? {detalle, vence_en: iso} : {
          version: 2, detalle, estado: accion,
          ...(accion === 'completada' && (tarea.tipo === 'llamada' || tarea.tipo === 'whatsapp') ? {resultado} : {}),
          ...(accion === 'completada' && tarea.tipo === 'reunion' ? {resultado_reunion: resultadoReunion} : {}),
          ...(conSiguiente ? {siguiente: {tipo, titulo, vence_en: iso,
            ...camposTareaDeReunion(reunion?.ok ? reunion : null)}} : {}),
        },
      })
      if (confirmada) {
        await Promise.all([recargar(), refrescarPostventa(actor)])
        toast.success(recuperar ? 'Envío recuperado. La gestión y la agenda están actualizadas.' : accion === 'confirmar'
          ? 'Cita confirmada. Sigue pendiente hasta registrar si asistió.'
          : accion === 'completada' && tarea.tipo === 'reunion'
            ? 'Entrevista registrada. La agenda está actualizada.'
            : 'Gestión registrada. La agenda está actualizada.')
        onCerrar()
      }
    } finally {onOcupado(false)}
  }
  return <>
    <DialogHeader><DialogTitle>Gestionar tarea de postventa</DialogTitle><p className="text-sm text-muted-foreground">{tarea.titulo}</p></DialogHeader>
    <DialogBody className="space-y-4">
      {(envio.pendiente || envio.bloqueado) ? <RecuperacionPostventa envio={envio} onRecuperar={() => void guardar(true)} /> : <>
        <div className="space-y-2"><Label htmlFor="pv-accion">Resultado o siguiente acción</Label>
          <Select id="pv-accion" value={accion} onChange={e => setAccion(e.target.value as Accion)}>
            <option value="completada">{tarea.tipo === 'reunion' ? 'Se realizó: registrar entrevista' : 'Gestión realizada'}</option>
            <option value="cancelada">Cancelar tarea</option>
            {tarea.tipo === 'reunion' && <><option value="no_show">El cliente no asistió</option><option value="confirmar">Confirmó que asistirá (cita pendiente)</option></>}
            <option value="reprogramar">Cambiar fecha</option>
          </Select></div>
        {accion === 'confirmar' && <p className="text-xs text-muted-foreground">Esto confirma la cita prevista. Después deberás indicar si se realizó para registrar la entrevista.</p>}
        {accion === 'completada' && tarea.tipo === 'llamada' && <div className="space-y-2">
          <Label htmlFor="pv-resultado">¿Qué pasó en la llamada?</Label>
          <Select id="pv-resultado" value={resultado} onChange={e => {
            const valor = e.target.value
            setResultado(valor); setSiguiente(false)
            setTipo(valor === 'agendo_reunion' ? 'reunion' : 'llamada')
            setTitulo(valor === 'agendo_reunion' ? 'Cita de seguimiento' : 'Seguimiento de postventa')
            setCamposReunion(CAMPOS_REUNION_VACIOS)
          }}>
            <option value="">Selecciona un resultado</option>
            {RESULTADOS.map(opcion => <option key={opcion.clave} value={opcion.clave}>{opcion.etiqueta}</option>)}
          </Select>
        </div>}
        {accion === 'completada' && tarea.tipo === 'whatsapp' && <div className="space-y-2">
          <Label htmlFor="pv-resultado">¿Qué pasó en WhatsApp?</Label>
          <Select id="pv-resultado" value={resultado} onChange={e => setResultado(e.target.value)}>
            <option value="">Selecciona un resultado</option>
            <option value="enviado">Enviado</option><option value="respondio">Respondió</option>
          </Select>
        </div>}
        {accion === 'completada' && tarea.tipo === 'reunion' && <div className="space-y-2">
          <Label htmlFor="pv-resultado-reunion">Resultado comercial de la entrevista</Label>
          <Select id="pv-resultado-reunion" value={resultadoReunion} onChange={e => setResultadoReunion(e.target.value as ResultadoReunionOperativo | '')}>
            <option value="">Selecciona un resultado</option>
            {RESULTADOS_REUNION.map(opcion => <option key={opcion.k} value={opcion.k}>{opcion.label}</option>)}
          </Select>
          <p className="text-xs text-muted-foreground">Al marcarla como realizada, la cita quedará registrada como entrevista.</p>
        </div>}
        {accion !== 'confirmar' && <div className="space-y-2"><Label htmlFor="pv-detalle">Detalle de la gestión</Label>
          <Textarea id="pv-detalle" value={detalle} onChange={e => setDetalle(e.target.value)} minLength={3} maxLength={1900} /></div>}
        {['completada', 'no_show'].includes(accion) && <label className="flex min-h-10 items-center gap-2 text-sm">
          <input type="checkbox" checked={conSiguiente} disabled={exigeSiguiente} onChange={e => setSiguiente(e.target.checked)} />
          {exigeSiguiente ? 'Agenda la cita o llamada acordada' : 'Programar el siguiente contacto'}
        </label>}
        {conSiguiente && <div className="space-y-3">
          <Label htmlFor="pv-titulo">Próxima gestión</Label><Input id="pv-titulo" value={titulo} onChange={e => setTitulo(e.target.value)} maxLength={200} />
          <Label htmlFor="pv-tipo">Tipo de contacto</Label><Select id="pv-tipo" value={tipo} disabled={exigeSiguiente} onChange={e => setTipo(e.target.value as TipoTarea)}>
            <option value="llamada">Llamada</option><option value="whatsapp">WhatsApp</option><option value="reunion">Cita</option><option value="tarea">Otra tarea</option>
          </Select>
          {tipo === 'reunion' && <CamposReunion valor={camposReunion} onChange={setCamposReunion} />}
        </div>}
        {(accion === 'reprogramar' || conSiguiente) && <div className="grid grid-cols-2 gap-3">
          <div className="space-y-2"><Label htmlFor="pv-fecha">Fecha</Label><Input id="pv-fecha" type="date" value={fecha} onChange={e => setFecha(e.target.value)} /></div>
          <div className="space-y-2"><Label htmlFor="pv-hora">Hora de Lima</Label><Input id="pv-hora" type="time" value={hora} onChange={e => setHora(e.target.value)} /></div>
        </div>}
        {envio.error && <p role="alert" className="text-sm text-destructive">{envio.error}</p>}
      </>}
    </DialogBody>
    <DialogFooter><Button variant="outline" disabled={envio.ocupado} onClick={onCerrar}>Cerrar</Button>
      {!envio.pendiente && !envio.bloqueado && <Button disabled={envio.ocupado || (accion !== 'confirmar' && detalle.trim().length < 3)
        || (accion === 'completada' && ((tarea.tipo === 'llamada' || tarea.tipo === 'whatsapp') && !resultado || tarea.tipo === 'reunion' && !resultadoReunion))}
        onClick={() => void guardar()}>Guardar gestión</Button>}
    </DialogFooter>
  </>
}
