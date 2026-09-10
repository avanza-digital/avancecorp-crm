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
import { refrescarPostventa } from '@/data/postventa-queries'
import type { Tarea, TipoTarea } from '@/lib/tipos'
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
  const [detalle, setDetalle] = useState('')
  const [fecha, setFecha] = useState(() => fechaLima(Date.now() + 86400000))
  const [hora, setHora] = useState(() => horaLima(Date.now() + 86400000))
  const [siguiente, setSiguiente] = useState(false)
  const [titulo, setTitulo] = useState('Seguimiento de postventa')
  const [tipo, setTipo] = useState<TipoTarea>('llamada')
  async function guardar(recuperar = false) {
    if (!actor || !tarea.inversionista_id || !tarea.postventa_revision || yo?.demo) return
    const iso = isoDeCampos({tipo, titulo, fecha, hora})
    if (!recuperar && (accion === 'reprogramar' || (siguiente && ['completada', 'no_show'].includes(accion))) && !iso) {toast.error('Elige una fecha y hora válidas.'); return}
    onOcupado(true)
    try {
      const confirmada = await envio.ejecutar(recuperar ? undefined : {
        p_tarea: tarea.id, p_revision: tarea.postventa_revision,
        p_accion: accion === 'reprogramar' || accion === 'confirmar' ? accion : 'cerrar',
        p_datos: accion === 'confirmar' ? {} : accion === 'reprogramar' ? {detalle, vence_en: iso} : {
          detalle, estado: accion, ...(siguiente && accion !== 'cancelada' ? {siguiente: {tipo, titulo, vence_en: iso}} : {}),
        },
      })
      if (confirmada) {
        await Promise.all([recargar(), refrescarPostventa(actor)])
        toast.success('Gestión registrada. La agenda está actualizada.')
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
            <option value="completada">Gestión realizada</option><option value="cancelada">Cancelar tarea</option>
            {tarea.tipo === 'reunion' && <><option value="no_show">El cliente no asistió</option><option value="confirmar">Confirmar asistencia</option></>}
            <option value="reprogramar">Cambiar fecha</option>
          </Select></div>
        {accion !== 'confirmar' && <div className="space-y-2"><Label htmlFor="pv-detalle">Detalle de la gestión</Label>
          <Textarea id="pv-detalle" value={detalle} onChange={e => setDetalle(e.target.value)} minLength={3} maxLength={2000} /></div>}
        {['completada', 'no_show'].includes(accion) && <label className="flex min-h-10 items-center gap-2 text-sm">
          <input type="checkbox" checked={siguiente} onChange={e => setSiguiente(e.target.checked)} />Programar el siguiente contacto
        </label>}
        {siguiente && ['completada', 'no_show'].includes(accion) && <div className="space-y-3">
          <Label htmlFor="pv-titulo">Próxima gestión</Label><Input id="pv-titulo" value={titulo} onChange={e => setTitulo(e.target.value)} maxLength={200} />
          <Label htmlFor="pv-tipo">Tipo de contacto</Label><Select id="pv-tipo" value={tipo} onChange={e => setTipo(e.target.value as TipoTarea)}>
            <option value="llamada">Llamada</option><option value="whatsapp">WhatsApp</option><option value="tarea">Otra tarea</option>
          </Select>
        </div>}
        {(accion === 'reprogramar' || (siguiente && ['completada', 'no_show'].includes(accion))) && <div className="grid grid-cols-2 gap-3">
          <div className="space-y-2"><Label htmlFor="pv-fecha">Fecha</Label><Input id="pv-fecha" type="date" value={fecha} onChange={e => setFecha(e.target.value)} /></div>
          <div className="space-y-2"><Label htmlFor="pv-hora">Hora de Lima</Label><Input id="pv-hora" type="time" value={hora} onChange={e => setHora(e.target.value)} /></div>
        </div>}
        {envio.error && <p role="alert" className="text-sm text-destructive">{envio.error}</p>}
      </>}
    </DialogBody>
    <DialogFooter><Button variant="outline" disabled={envio.ocupado} onClick={onCerrar}>Cerrar</Button>
      {!envio.pendiente && !envio.bloqueado && <Button disabled={envio.ocupado || (accion !== 'confirmar' && detalle.trim().length < 3)} onClick={() => void guardar()}>Guardar gestión</Button>}
    </DialogFooter>
  </>
}
