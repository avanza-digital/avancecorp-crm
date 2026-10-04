// Cómo se VE una gestión del lead: su icono y el «hace X» del timeline. Una sola
// definición para la ficha, el directorio y «Ahora» de Gestión Diaria (antes el
// mapa de iconos vivía copiado en la ficha y en el directorio).
import type { LucideIcon } from 'lucide-react'
import { ArchiveRestore, ArrowRightLeft, BadgeCheck, Ban, CalendarCheck, MessageCircle, MessageSquare, PhoneCall, PhoneMissed, StickyNote, Users } from 'lucide-react'
import { fmtFecha } from '@/lib/format'
import type { Actividad, TipoActividad } from '@/lib/tipos'

export const ICONO_ACTIVIDAD: Record<TipoActividad, LucideIcon> = {
  llamada_realizada: PhoneCall,
  llamada_no_contestada: PhoneMissed,
  whatsapp_enviado: MessageCircle,
  whatsapp_recibido: MessageSquare,
  reunion_realizada: CalendarCheck,
  nota: StickyNote,
  cambio_etapa: ArrowRightLeft,
  reasignacion: Users,
  conversion: BadgeCheck,
}

/** Icono de UNA actividad concreta: algunos eventos del servidor se guardan como `nota`
 *  (el CHECK de actividades no admite tipos nuevos; el evento va en `metadata.evento`) y
 *  no deben verse como una nota cualquiera. Valores escritos por el servidor:
 *  `reactivacion_base` (private.base_gestion_reactivar_core, migración 20261002231436) y
 *  `no_contactar` (crm.marcar_no_contactar / crm.levantar_no_contactar, con
 *  `accion` = marcar | levantar). Sin evento conocido, el icono de su tipo. */
export function iconoActividad(a: Pick<Actividad, 'tipo' | 'metadata'>): LucideIcon {
  const evento = a.metadata?.evento
  if (evento === 'reactivacion_base') return ArchiveRestore
  if (evento === 'no_contactar') return Ban
  return ICONO_ACTIVIDAD[a.tipo]
}

/** "hace X" legible; para fechas viejas cae a fmtFecha. Formato propio del timeline
 * (min/h/'ayer'), más fino que haceTexto() de lib/inteligencia — NO sustituir.
 * `ahora` viene del reloj vivo useAhora() para que refresque sin remontar. */
export function haceRelativo(iso: string, ahora: number): string {
  const ms = ahora - new Date(iso).getTime()
  if (!Number.isFinite(ms) || ms < 0) return fmtFecha(iso)
  const min = Math.floor(ms / 60_000)
  if (min < 1) return 'ahora'
  if (min < 60) return `hace ${min} min`
  const h = Math.floor(min / 60)
  if (h < 24) return `hace ${h} h`
  const d = Math.floor(h / 24)
  if (d === 1) return 'ayer'
  if (d < 7) return `hace ${d} d`
  return fmtFecha(iso)
}
