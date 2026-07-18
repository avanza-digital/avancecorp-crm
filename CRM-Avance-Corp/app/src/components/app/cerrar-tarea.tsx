// Diálogo de cierre de tarea — el corazón del MOTOR (Fase B del plan v2).
//
// Flujo en un solo diálogo: resultado 1-tap (obligatorio en llamadas — patrón
// Outreach: sin disposición la llamada no cuenta) → el motor PROPONE la
// siguiente (cuándo + canal + qué, con alternancia) → [Cerrar y agendar] o
// "Saltar esta vez" a UN toque (jamás candado: el lead saltado cae al bucket
// amarillo "sin próxima acción", visible e inocultable).
//
// La escritura real es la RPC atómica crm.cerrar_tarea (cierre + log +
// siguiente en una transacción); aquí solo se arma el input y se traduce el
// resultado a toasts honestos.
import { useMemo, useState } from 'react'
import { toast } from 'sonner'
import { CheckCircle2, PhoneCall, PhoneMissed, Send, MessageSquare, Users, UserX, CircleCheckBig } from 'lucide-react'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { sugerirSiguiente } from '@/lib/motor-siguiente'
import { fechaLima, tareaAEvento } from '@/lib/agenda-derivada'
import { primerNombre } from '@/lib/format'
import {
  TIPOS_TAREA,
  esTipoTarea,
  type Tarea,
  type TipoActividadManual,
  type TipoTarea,
} from '@/lib/tipos'
import { cn } from '@/lib/utils'

/** Opciones de resultado por tipo de tarea (1 tap, sin formularios). */
interface OpcionCierre {
  k: string
  label: string
  icono: typeof PhoneCall
  estado: 'completada' | 'no_show'
  resultado: TipoActividadManual | null
}

function opcionesDe(tipo: TipoTarea): OpcionCierre[] {
  switch (tipo) {
    case 'llamada':
      return [
        { k: 'contesto', label: 'Contestó', icono: PhoneCall, estado: 'completada', resultado: 'llamada_realizada' },
        { k: 'no_contesto', label: 'No contestó', icono: PhoneMissed, estado: 'completada', resultado: 'llamada_no_contestada' },
      ]
    case 'whatsapp':
      return [
        { k: 'enviado', label: 'Enviado', icono: Send, estado: 'completada', resultado: 'whatsapp_enviado' },
        { k: 'respondio', label: 'Respondió', icono: MessageSquare, estado: 'completada', resultado: 'whatsapp_recibido' },
      ]
    case 'reunion':
      return [
        { k: 'realizada', label: 'Se realizó', icono: Users, estado: 'completada', resultado: 'reunion_realizada' },
        { k: 'no_show', label: 'No asistió', icono: UserX, estado: 'no_show', resultado: null },
      ]
    case 'tarea':
      return [
        { k: 'hecha', label: 'Hecha', icono: CircleCheckBig, estado: 'completada', resultado: null },
      ]
  }
}

export function CerrarTareaDialog({
  tarea,
  onCerrar,
}: {
  tarea: Tarea | null
  onCerrar: () => void
}) {
  return (
    <Dialog open={tarea != null} onClose={onCerrar} ariaLabel="Cerrar tarea">
      {tarea && <FormCierre key={tarea.id} tarea={tarea} onCerrar={onCerrar} />}
    </Dialog>
  )
}

function FormCierre({ tarea, onCerrar }: { tarea: Tarea; onCerrar: () => void }) {
  const { lead, completarTarea } = useCRMData()
  const ahora = useAhora()
  const l = tarea.lead_id ? lead(tarea.lead_id) : undefined
  const opciones = opcionesDe(tarea.tipo)

  const [eleccion, setEleccion] = useState<OpcionCierre | null>(
    // "Hecha" es la única opción de una tarea genérica: preseleccionada.
    opciones.length === 1 ? (opciones[0] ?? null) : null,
  )
  const [detalle, setDetalle] = useState('')
  const [saltar, setSaltar] = useState(false)
  const [sigEditada, setSigEditada] = useState(false)
  const [sigTipo, setSigTipo] = useState<TipoTarea>('llamada')
  const [sigTitulo, setSigTitulo] = useState('')
  const [sigFecha, setSigFecha] = useState('')
  const [sigHora, setSigHora] = useState('10:00')

  // La sugerencia del motor se recalcula al elegir el resultado; si el
  // vendedor ya editó la siguiente a mano, no se le pisa.
  const sugerencia = useMemo(
    () =>
      eleccion
        ? sugerirSiguiente({
            tareaTipo: tarea.tipo,
            estado: eleccion.estado,
            resultado: eleccion.resultado,
            leadNombre: l?.nombre_completo ?? '',
            ahora,
          })
        : null,
    [eleccion, tarea.tipo, l?.nombre_completo, ahora],
  )

  const elegir = (op: OpcionCierre) => {
    setEleccion(op)
    if (!sigEditada) {
      const s = sugerirSiguiente({
        tareaTipo: tarea.tipo,
        estado: op.estado,
        resultado: op.resultado,
        leadNombre: l?.nombre_completo ?? '',
        ahora,
      })
      if (s) {
        setSigTipo(s.tipo)
        setSigTitulo(s.titulo)
        const ms = Date.parse(s.vence_en)
        setSigFecha(fechaLima(ms))
        setSigHora(new Date(ms - 5 * 3600 * 1000).toISOString().slice(11, 16))
      }
    }
  }

  const confirmar = () => {
    if (!eleccion) return
    const conSiguiente = !saltar && sugerencia != null && sigTitulo.trim() !== ''
    const res = completarTarea({
      tarea_id: tarea.id,
      estado: eleccion.estado,
      // Una tarea genérica con nota deja rastro como 'nota'; sin nota, solo cierra.
      resultado_tipo: eleccion.resultado ?? (tarea.tipo === 'tarea' && detalle.trim() ? 'nota' : null),
      resultado_detalle: detalle.trim() || null,
      siguiente: conSiguiente
        ? {
            tipo: sigTipo,
            titulo: sigTitulo.trim(),
            vence_en: new Date(`${sigFecha}T${sigHora}:00-05:00`).toISOString(),
          }
        : null,
    })
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo cerrar la tarea')
      return
    }
    if (conSiguiente) {
      const cuando = tareaAEvento(
        { ...tarea, id: 'x', tipo: sigTipo, titulo: sigTitulo, vence_en: new Date(`${sigFecha}T${sigHora}:00-05:00`).toISOString(), estado: 'pendiente' },
        ahora,
      ).cuando
      toast.success(`Tarea cerrada — siguiente agendada: ${cuando}`)
    } else {
      toast.warning(
        l
          ? `Tarea cerrada — ${primerNombre(l.nombre_completo)} quedó SIN próxima acción`
          : 'Tarea cerrada',
      )
    }
    onCerrar()
  }

  const requiereEleccion = opciones.length > 1 && !eleccion

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <CheckCircle2 className="size-4 text-[var(--accent)]" aria-hidden /> Cerrar tarea
        </DialogTitle>
        <DialogDescription className="truncate">{tarea.titulo}</DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-3.5">
        {/* Resultado 1-tap */}
        <div>
          <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
            ¿Qué pasó?
          </p>
          <div className={cn('grid gap-2', opciones.length > 1 ? 'grid-cols-2' : 'grid-cols-1')}>
            {opciones.map((op) => (
              <button
                key={op.k}
                type="button"
                onClick={() => elegir(op)}
                aria-pressed={eleccion?.k === op.k}
                className={cn(
                  'flex cursor-pointer items-center justify-center gap-2 rounded-xl border px-3 py-3 text-sm font-semibold transition-colors',
                  eleccion?.k === op.k
                    ? 'border-[var(--accent)] bg-[var(--accent)]/10 text-foreground'
                    : 'border-border/70 text-muted-foreground hover:bg-muted/60',
                )}
              >
                <op.icono className="size-4" aria-hidden /> {op.label}
              </button>
            ))}
          </div>
        </div>

        <Textarea
          aria-label="Nota del resultado (opcional)"
          placeholder="Nota corta (opcional) — va al timeline del lead"
          rows={2}
          value={detalle}
          onChange={(e) => setDetalle(e.target.value)}
        />

        {/* La SIGUIENTE — la regla de oro, con saltar a un toque */}
        {eleccion && sugerencia && !saltar && (
          <div className="rounded-xl border border-[var(--accent)]/40 bg-[var(--accent)]/5 p-2.5">
            <div className="mb-2 flex items-center justify-between">
              <p className="text-[11px] font-bold uppercase tracking-wide text-foreground/80">
                Siguiente acción propuesta
              </p>
              <button
                type="button"
                className="cursor-pointer text-[11px] font-semibold text-muted-foreground underline-offset-2 hover:underline"
                onClick={() => setSaltar(true)}
              >
                Saltar esta vez
              </button>
            </div>
            <div className="grid grid-cols-[110px_1fr] gap-2">
              <Select
                aria-label="Tipo de la siguiente"
                value={sigTipo}
                onChange={(e) => {
                  if (esTipoTarea(e.target.value)) setSigTipo(e.target.value)
                  setSigEditada(true)
                }}
              >
                {TIPOS_TAREA.map((t) => (
                  <option key={t.k} value={t.k}>{t.label}</option>
                ))}
              </Select>
              <Input
                aria-label="Título de la siguiente"
                value={sigTitulo}
                maxLength={200}
                onChange={(e) => {
                  setSigTitulo(e.target.value)
                  setSigEditada(true)
                }}
              />
              <Input
                aria-label="Fecha de la siguiente"
                type="date"
                value={sigFecha}
                onChange={(e) => {
                  setSigFecha(e.target.value)
                  setSigEditada(true)
                }}
              />
              <Input
                aria-label="Hora de la siguiente"
                type="time"
                value={sigHora}
                onChange={(e) => {
                  setSigHora(e.target.value)
                  setSigEditada(true)
                }}
              />
            </div>
          </div>
        )}
        {eleccion && saltar && (
          <div className="flex items-center justify-between rounded-xl border border-[#d97706]/40 bg-[#d97706]/10 px-3 py-2">
            <p className="text-[11px] font-semibold text-[#b45309]">
              Sin siguiente — el lead quedará en “sin próxima acción”.
            </p>
            <button
              type="button"
              className="cursor-pointer text-[11px] font-semibold text-foreground underline-offset-2 hover:underline"
              onClick={() => setSaltar(false)}
            >
              Deshacer
            </button>
          </div>
        )}
      </DialogBody>
      <DialogFooter className="justify-between">
        <Button variant="ghost" size="sm" onClick={onCerrar}>Cancelar</Button>
        <Button size="sm" onClick={confirmar} disabled={requiereEleccion}>
          <CheckCircle2 /> Cerrar tarea
        </Button>
      </DialogFooter>
    </>
  )
}