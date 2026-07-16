// Acciones de contacto reales (tel:/wa.me/mailto:) con registro del resultado
// — Sprint A (F1d). Un solo componente para las 3 superficies: header del
// lead-drawer (completo) y colas de hoy/vendedor y hoy/supervisor (compacto).
// Si el rol escribe, el click marca un contacto pendiente (useRef local con
// timestamp) y al volver a la pestaña ≥4 s después pregunta el resultado con
// un dialog compacto que registra la actividad vía registrarActividad del
// store. Directorio (solo lectura) ve links planos sin seguimiento.
// El contenedor corta la propagación: estos links viven dentro de filas
// clicables (colas) y no deben abrir la ficha al llamar/escribir.
import { useEffect, useRef, useState, type JSX } from 'react'
import { toast } from 'sonner'
import {
  Mail,
  MessageCircle,
  MessageSquare,
  Phone,
  PhoneCall,
  PhoneMissed,
  type LucideIcon,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { useAuth } from '@/lib/auth-context'
import { puedeEscribir } from '@/lib/roles'
import { useCRMData } from '@/lib/store-context'
import { primerNombre } from '@/lib/format'
import type { Lead, TipoActividadManual } from '@/lib/tipos'

// ── Constantes ────────────────────────────────────────────────────────────────

/** Link de acción rápida — mismo estilo que usaban drawer y colas. */
const CLASE_ACCION =
  'inline-flex h-7 items-center gap-1.5 rounded-lg border border-input bg-card px-2.5 text-[11px] font-semibold text-foreground transition-colors hover:bg-muted hover:border-border-strong [&_svg]:size-3.5'

type Canal = 'tel' | 'wa'

/** Tiempo mínimo fuera de la pestaña para considerar que hubo un intento real. */
const ESPERA_MS = 4_000

// ── Componente (export) ───────────────────────────────────────────────────────

export function AccionesContacto({ lead, compacto }: { lead: Lead; compacto?: boolean }): JSX.Element {
  const { yo } = useAuth()
  const escribe = puedeEscribir(yo?.rol)
  // Contacto pendiente de ESTA instancia (canal + cuándo se hizo click).
  const pendiente = useRef<{ canal: Canal; ts: number } | null>(null)
  const [dialogo, setDialogo] = useState<Canal | null>(null)

  useEffect(() => {
    if (!escribe) return
    const alVolver = () => {
      const p = pendiente.current
      if (!p || document.visibilityState !== 'visible') return
      pendiente.current = null // un solo disparo por contacto (focus y visibilitychange llegan juntos)
      // Volvió casi al instante (< 4 s): no llegó a llamar/escribir — no preguntamos.
      if (Date.now() - p.ts < ESPERA_MS) return
      setDialogo(p.canal)
    }
    window.addEventListener('focus', alVolver)
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      window.removeEventListener('focus', alVolver)
      document.removeEventListener('visibilitychange', alVolver)
    }
  }, [escribe])

  const marcar = (canal: Canal) => () => {
    if (escribe) pendiente.current = { canal, ts: Date.now() }
  }

  const wa = lead.telefono.replace('+', '')
  const labelCls = compacto ? 'hidden md:inline' : undefined

  return (
    <div
      className={cn('flex items-center gap-1.5', compacto ? 'shrink-0' : 'flex-wrap')}
      // Escudo de propagación: ni el click en los links ni las teclas dentro del
      // dialog (portal — burbujea por el árbol de React) deben abrir la fila.
      // Escape SÍ pasa: el Dialog lo escucha a nivel de document para cerrarse.
      // role=presentation: NO es un control — solo intercepta burbujeo (los
      // interactivos reales son los <a>/<button> internos).
      role="presentation"
      onClick={(e) => e.stopPropagation()}
      onKeyDown={(e) => {
        if (e.key !== 'Escape') e.stopPropagation()
      }}
    >
      <a
        href={`tel:${lead.telefono}`}
        className={CLASE_ACCION}
        aria-label={`Llamar a ${lead.nombre_completo}`}
        onClick={marcar('tel')}
      >
        <Phone /> <span className={labelCls}>Llamar</span>
      </a>
      <a
        href={`https://wa.me/${wa}`}
        target="_blank"
        rel="noreferrer"
        className={CLASE_ACCION}
        aria-label={`WhatsApp a ${lead.nombre_completo}`}
        onClick={marcar('wa')}
      >
        <MessageCircle /> <span className={labelCls}>WhatsApp</span>
      </a>
      {!compacto && lead.correo && (
        <a href={`mailto:${lead.correo}`} className={CLASE_ACCION} aria-label={`Correo a ${lead.nombre_completo}`}>
          <Mail /> Correo
        </a>
      )}
      {dialogo && <DialogResultado lead={lead} canal={dialogo} onClose={() => setDialogo(null)} />}
    </div>
  )
}

// ── Dialog de resultado del contacto ──────────────────────────────────────────

const OPCIONES: Record<Canal, ReadonlyArray<{ tipo: TipoActividadManual; label: string; icono: LucideIcon }>> = {
  tel: [
    { tipo: 'llamada_realizada', label: 'Sí, contestó', icono: PhoneCall },
    { tipo: 'llamada_no_contestada', label: 'No contestó', icono: PhoneMissed },
  ],
  wa: [
    { tipo: 'whatsapp_enviado', label: 'Mensaje enviado', icono: MessageCircle },
    { tipo: 'whatsapp_recibido', label: 'Ya respondió', icono: MessageSquare },
  ],
}

function DialogResultado({
  lead,
  canal,
  onClose,
}: {
  lead: Lead
  canal: Canal
  onClose: () => void
}): JSX.Element {
  const { registrarActividad } = useCRMData()
  const { yo } = useAuth()
  const [nota, setNota] = useState('')

  const registrar = (tipo: TipoActividadManual) => {
    const res = registrarActividad(lead.id, tipo, nota)
    if (!res.ok) {
      // P. ej. lead cerrado mientras tanto — reintentar no cambia nada: cerramos.
      if (res.error) toast.error(res.error)
      onClose()
      return
    }
    onClose()
    toast.success(`Contacto registrado${yo?.demo ? ' (demo)' : ''}`)
  }

  return (
    <Dialog open onClose={onClose} ariaLabel="Resultado del contacto" className="w-[420px]">
      <DialogHeader>
        <DialogTitle>¿Lograste comunicarte con {primerNombre(lead.nombre_completo)}?</DialogTitle>
        <DialogDescription>
          {canal === 'tel'
            ? 'Registra cómo salió la llamada — queda en el historial del lead.'
            : 'Registra cómo va la conversación — queda en el historial del lead.'}
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-2 gap-2">
          {OPCIONES[canal].map((o) => (
            <Button key={o.tipo} size="sm" variant="outline" onClick={() => registrar(o.tipo)}>
              <o.icono /> {o.label}
            </Button>
          ))}
        </div>
        <Textarea
          aria-label="Nota del contacto"
          value={nota}
          onChange={(e) => setNota(e.target.value)}
          placeholder="Nota (opcional)…"
          className="min-h-[56px] text-xs"
        />
      </DialogBody>
      <DialogFooter>
        <Button variant="ghost" size="sm" onClick={onClose}>
          Omitir
        </Button>
      </DialogFooter>
    </Dialog>
  )
}
