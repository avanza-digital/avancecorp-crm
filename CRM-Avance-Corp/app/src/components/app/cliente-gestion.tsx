import { useAuth } from '@/lib/auth-context'
import { personaDePerfil } from '@/data/postventa-api'
import { refrescarPostventa } from '@/data/postventa-queries'
import { mensajeDeError } from '@/data/crm-api'
import { RecuperacionPostventa } from './postventa-envio'
import { useEnvioPostventa } from '@/data/use-envio-postventa'
// Gestión comercial postventa desde Mi cartera. Usa la MISMA crm.tareas que
// alimenta Hoy y Agenda, pero su sujeto es perfil_id (cliente), no lead_id.
import { useEffect, useState } from 'react'
import { CalendarPlus, Clock3 } from 'lucide-react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import {
  CAMPOS_REUNION_VACIOS,
  CamposReunion,
  camposTareaDeReunion,
  type EstadoCamposReunion,
} from '@/components/app/campos-reunion'
import { useAhora } from '@/lib/ahora'
import { fechaLima, horaLima, proximoSlotSugerido, tareaAEvento } from '@/lib/agenda-derivada'
import { isoDeCampos } from '@/lib/campos-siguiente'
import { useCRMData } from '@/lib/store-context'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { presentarCitas } from '@/lib/terminologia'
import { TIPOS_TAREA, esTipoTarea, type TipoTarea } from '@/lib/tipos'

const ACCION_POR_TIPO: Record<TipoTarea, string> = {
  llamada: 'Llamar a',
  whatsapp: 'Escribir a',
  reunion: 'Cita con',
  tarea: 'Gestionar a',
}

function tituloSugerido(tipo: TipoTarea, nombre: string): string {
  const primero = nombre.trim().split(/\s+/)[0] || 'cliente'
  return `${ACCION_POR_TIPO[tipo]} ${primero}`
}

interface PropsGestion {
  clienteId?: string | undefined
  inversionistaId?: string | undefined
  clienteNombre: string
  onCerrar: () => void
  onEnviandoCambio?: ((enviando: boolean) => void) | undefined
}
export function ClienteGestion(props: PropsGestion) {
  const {yo} = useAuth()
  return <ResolverGestion key={`${yo?.id}:${props.inversionistaId ?? props.clienteId}`} {...props} />
}
function ResolverGestion(props: PropsGestion) {
  const {yo} = useAuth()
  const [resuelta, setResuelta] = useState<{persona: string | null; error: string | null} | null>(null)
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    if (yo?.demo || props.inversionistaId || !props.clienteId) return
    const abort = new AbortController()
    void personaDePerfil(props.clienteId, abort.signal).then(r => {
      if (!abort.signal.aborted) setResuelta(r.habilitada && !r.inversionista_id
        ? {persona: null, error: 'La identidad del cliente requiere revisión antes de agendar.'}
        : {persona: r.inversionista_id, error: null})
    }).catch(e => {if (!abort.signal.aborted) setResuelta({persona: null, error: mensajeDeError(e, 'No pudimos comprobar la identidad.')})})
    return () => abort.abort()
  }, [props.clienteId, props.inversionistaId, yo?.demo, yo?.id, revision])
  if (!yo?.demo && !props.inversionistaId && (!resuelta || resuelta.error)) return <>
    <DialogHeader><DialogTitle>Gestionar a {props.clienteNombre}</DialogTitle></DialogHeader>
    <DialogBody>{resuelta?.error ? <><p role="alert">{resuelta.error}</p><Button onClick={() => setRevision(n => n + 1)}>Reintentar</Button></> : <p role="status">Comprobando la ficha…</p>}</DialogBody>
  </>
  const persona = props.inversionistaId ?? resuelta?.persona ?? undefined
  return <FormGestion key={persona ?? props.clienteId} {...props} inversionistaId={persona} actor={yo?.id ?? ''} />
}
function FormGestion({clienteId, inversionistaId, clienteNombre, onCerrar, onEnviandoCambio, actor}: PropsGestion & {actor: string}) {
  const { crearTarea, tareasDeCliente, tareas, recargar } = useCRMData()
  const envio = useEnvioPostventa(actor, 'agendar', inversionistaId ?? clienteId ?? '')
  const ahora = useAhora()
  const pendientes = inversionistaId
    ? (tareas ?? []).filter(t => (t.inversionista_canonico_id ?? t.inversionista_id) === inversionistaId && t.estado === 'pendiente')
    : clienteId ? tareasDeCliente?.(clienteId) ?? [] : []
  const slot = proximoSlotSugerido(ahora)
  const [tipo, setTipo] = useState<TipoTarea>('llamada')
  const [titulo, setTitulo] = useState(() => tituloSugerido('llamada', clienteNombre))
  const [tituloEditado, setTituloEditado] = useState(false)
  const [fecha, setFecha] = useState(() => fechaLima(Date.parse(slot)))
  const [hora, setHora] = useState(() => horaLima(Date.parse(slot)))
  const [nota, setNota] = useState('')
  const [camposReunion, setCamposReunion] = useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)
  const [enviando, setEnviando] = useState(false)

  const cambiarTipo = (valor: string) => {
    if (!esTipoTarea(valor)) return
    setTipo(valor)
    if (!tituloEditado) setTitulo(tituloSugerido(valor, clienteNombre))
  }

  const guardar = async (recuperar = false) => {
    const venceEn = isoDeCampos({ tipo, titulo, fecha, hora })
    if (!recuperar && !titulo.trim()) {
      toast.error('Escribe qué gestión vas a realizar')
      return
    }
    if (!recuperar && !venceEn) {
      toast.error('Elige una fecha y hora válidas')
      return
    }
    const reunion = tipo === 'reunion' ? validarReunionOperativa(camposReunion) : null
    if (!recuperar && reunion && !reunion.ok) {
      toast.error(reunion.error)
      return
    }
    setEnviando(true)
    onEnviandoCambio?.(true)
    let confirmada = false
    try {
      if (inversionistaId) {
        confirmada = await envio.ejecutar(recuperar ? undefined : {p_inversionista: inversionistaId, p_datos: {
          tipo, titulo: titulo.trim(), nota: nota.trim() || null, vence_en: venceEn,
          ...camposTareaDeReunion(reunion?.ok ? reunion : null),
        }})
        if (confirmada) await Promise.all([recargar(), refrescarPostventa(actor)])
      } else {
      if (!clienteId || !venceEn) throw new Error('La ficha o la fecha no son válidas.')
      const resultado = crearTarea({
        perfil_id: clienteId,
        tipo,
        titulo: titulo.trim(),
        nota: nota.trim() || null,
        vence_en: venceEn,
        ...camposTareaDeReunion(reunion?.ok ? reunion : null),
      })
      if (!resultado.ok) {
        toast.error(resultado.error ?? 'No se pudo agendar la gestión')
        return
      }
      // La fila optimista sirve para que la agenda responda rápido, pero el
      // diálogo solo promete éxito cuando el trigger/RLS confirmó la tarea. Es
      // especialmente importante para clientes: el servidor resuelve el dueño
      // real de cartera y rechaza perfiles inactivos o fuera del ámbito.
      confirmada = await (resultado.persistido ?? Promise.resolve(true))
      }
    } catch {
      toast.error('No se pudo agendar la gestión')
    } finally {
      setEnviando(false)
      onEnviandoCambio?.(false)
    }
    if (confirmada) {
      toast.success('Gestión agendada · la verás en Hoy y en Agenda')
      onCerrar()
    }
  }

  if (inversionistaId && (envio.pendiente || envio.bloqueado)) return <>
    <DialogHeader><DialogTitle>Gestionar a {clienteNombre}</DialogTitle></DialogHeader>
    <DialogBody><RecuperacionPostventa envio={envio} onRecuperar={() => void guardar(true)} /></DialogBody>
  </>

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <CalendarPlus className="size-4 text-primary" aria-hidden />
          Gestionar a {clienteNombre}
        </DialogTitle>
        <DialogDescription>
          Programa una llamada, WhatsApp, cita u otra tarea comercial sobre este cliente.
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="max-h-[65vh] space-y-4 overflow-y-auto">
        {inversionistaId && envio.error && <p role="alert" className="text-sm text-destructive">{envio.error}</p>}
        {pendientes.length > 0 && (
          <section
            className="rounded-xl border border-border bg-muted/30 p-3"
            aria-label="Gestiones pendientes del cliente"
          >
            <div className="flex items-center justify-between gap-2">
              <p className="text-xs font-bold text-foreground">Ya tiene próximas acciones</p>
              <Badge color="var(--accent)">
                {pendientes.length} pendiente
                {pendientes.length === 1 ? '' : 's'}
              </Badge>
            </div>
            <ul className="mt-2 space-y-1.5">
              {pendientes.slice(0, 3).map((tarea) => (
                <li key={tarea.id} className="flex items-center gap-2 text-xs text-muted-foreground">
                  <Clock3 className="size-3.5 shrink-0" aria-hidden />
                  <span className="min-w-0 flex-1 truncate">{presentarCitas(tarea.titulo)}</span>
                  <span className="shrink-0 tabular-nums">{tareaAEvento(tarea, ahora).cuando}</span>
                </li>
              ))}
            </ul>
          </section>
        )}

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="gestion-cliente-tipo">Canal</Label>
            <Select id="gestion-cliente-tipo" value={tipo} onChange={(e) => cambiarTipo(e.target.value)}>
              {TIPOS_TAREA.map((opcion) => (
                <option key={opcion.k} value={opcion.k}>
                  {opcion.label}
                </option>
              ))}
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="gestion-cliente-titulo">Gestión</Label>
            <Input
              id="gestion-cliente-titulo"
              value={titulo}
              maxLength={200}
              onChange={(e) => {
                setTituloEditado(true)
                setTitulo(e.target.value)
              }}
            />
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="gestion-cliente-fecha">Fecha</Label>
            <Input id="gestion-cliente-fecha" type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="gestion-cliente-hora">Hora</Label>
            <Input id="gestion-cliente-hora" type="time" value={hora} onChange={(e) => setHora(e.target.value)} />
          </div>
        </div>

        {tipo === 'reunion' && <CamposReunion valor={camposReunion} onChange={setCamposReunion} />}

        <div className="space-y-1.5">
          <Label htmlFor="gestion-cliente-nota">Nota (opcional)</Label>
          <Textarea
            id="gestion-cliente-nota"
            value={nota}
            maxLength={2000}
            placeholder="Contexto para preparar la gestión"
            onChange={(e) => setNota(e.target.value)}
          />
        </div>
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="ghost" disabled={enviando} onClick={onCerrar}>
          Cancelar
        </Button>
        <Button type="button" disabled={enviando} onClick={() => void guardar()}>
          <CalendarPlus aria-hidden /> {enviando ? 'Agendando…' : 'Agendar gestión'}
        </Button>
      </DialogFooter>
    </>
  )
}
