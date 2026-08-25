// Gestión comercial postventa desde Mi cartera. Usa la MISMA crm.tareas que
// alimenta Hoy y Agenda, pero su sujeto es perfil_id (cliente), no lead_id.
import { useState } from 'react'
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
import { TIPOS_TAREA, esTipoTarea, type TipoTarea } from '@/lib/tipos'

const ACCION_POR_TIPO: Record<TipoTarea, string> = {
  llamada: 'Llamar a',
  whatsapp: 'Escribir a',
  reunion: 'Reunión con',
  tarea: 'Gestionar a',
}

function tituloSugerido(tipo: TipoTarea, nombre: string): string {
  const primero = nombre.trim().split(/\s+/)[0] || 'cliente'
  return `${ACCION_POR_TIPO[tipo]} ${primero}`
}

export function ClienteGestion({
  clienteId,
  clienteNombre,
  onCerrar,
}: {
  clienteId: string
  clienteNombre: string
  onCerrar: () => void
}) {
  const { crearTarea, tareasDeCliente } = useCRMData()
  const ahora = useAhora()
  const pendientes = tareasDeCliente?.(clienteId) ?? []
  const slot = proximoSlotSugerido(ahora)
  const [tipo, setTipo] = useState<TipoTarea>('llamada')
  const [titulo, setTitulo] = useState(() => tituloSugerido('llamada', clienteNombre))
  const [tituloEditado, setTituloEditado] = useState(false)
  const [fecha, setFecha] = useState(() => fechaLima(Date.parse(slot)))
  const [hora, setHora] = useState(() => horaLima(Date.parse(slot)))
  const [nota, setNota] = useState('')
  const [camposReunion, setCamposReunion] = useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)
  const [guardando, setGuardando] = useState(false)

  const cambiarTipo = (valor: string) => {
    if (!esTipoTarea(valor)) return
    setTipo(valor)
    if (!tituloEditado) setTitulo(tituloSugerido(valor, clienteNombre))
  }

  const guardar = async () => {
    if (guardando) return
    const venceEn = isoDeCampos({ tipo, titulo, fecha, hora })
    if (!titulo.trim()) {
      toast.error('Escribe qué gestión vas a realizar')
      return
    }
    if (!venceEn) {
      toast.error('Elige una fecha y hora válidas')
      return
    }
    const reunion = tipo === 'reunion' ? validarReunionOperativa(camposReunion) : null
    if (reunion && !reunion.ok) {
      toast.error(reunion.error)
      return
    }
    setGuardando(true)
    const resultado = crearTarea({
      perfil_id: clienteId,
      tipo,
      titulo: titulo.trim(),
      nota: nota.trim() || null,
      vence_en: venceEn,
      ...camposTareaDeReunion(reunion?.ok ? reunion : null),
    })
    if (!resultado.ok) {
      setGuardando(false)
      toast.error(resultado.error ?? 'No se pudo agendar la gestión')
      return
    }

    // `crearTarea` aplica primero el espejo optimista. El mensaje definitivo y
    // el cierre esperan el commit real: RLS o el trigger todavía pueden negar
    // un cliente que cambió de estado/asesor mientras el diálogo estaba abierto.
    if (!resultado.persistido) {
      setGuardando(false)
      toast.error('No se pudo confirmar la gestión con el servidor')
      return
    }
    const confirmado = await resultado.persistido
    if (!confirmado.ok) {
      setGuardando(false)
      return
    }
    toast.success('Gestión agendada · la verás en Hoy y en Agenda')
    onCerrar()
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <CalendarPlus className="size-4 text-primary" aria-hidden />
          Gestionar a {clienteNombre}
        </DialogTitle>
        <DialogDescription>
          Programa una llamada, WhatsApp, reunión u otra tarea comercial sobre este cliente.
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="max-h-[65vh] space-y-4 overflow-y-auto">
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
                  <span className="min-w-0 flex-1 truncate">{tarea.titulo}</span>
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
        <Button type="button" variant="ghost" onClick={onCerrar} disabled={guardando}>
          Cancelar
        </Button>
        <Button type="button" onClick={() => void guardar()} disabled={guardando}>
          <CalendarPlus aria-hidden /> {guardando ? 'Guardando…' : 'Agendar gestión'}
        </Button>
      </DialogFooter>
    </>
  )
}
