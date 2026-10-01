// Chip del potencial del lead: Frío (gris pizarra, copo), Tibio (naranja,
// termómetro) y Estrella (dorado, estrella). Ícono y texto SIEMPRE: el color
// nunca es la única señal. Mismas medidas que el `Badge` de la casa, en sólido.
//
// No es un semáforo: rojo y ámbar ya significan urgencia de tiempo en el CRM.
// El potencial dice cuánto promete el lead, no cuándo toca gestionarlo.
import { Snowflake, Star, ThermometerSun, type LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'
import { ETIQUETA_POTENCIAL, type NivelPotencial, type PotencialLead } from '@/lib/potencial'
import { usePotencialLead } from '@/data/potencial-queries'

const ICONOS: Record<NivelPotencial, LucideIcon> = {
  frio: Snowflake,
  tibio: ThermometerSun,
  estrella: Star,
}

/** El ícono de un nivel. `relleno` pinta la estrella llena (marca confirmada). */
export function IconoPotencial({ nivel, relleno = false, grosor = 2.5, className }: {
  nivel: NivelPotencial
  relleno?: boolean
  grosor?: number
  className?: string
}) {
  const Icono = ICONOS[nivel]
  return <Icono aria-hidden className={className} fill={relleno ? 'currentColor' : 'none'} strokeWidth={grosor} />
}

/**
 * La marca de un lead. Sin marca (o sin dato) no pinta nada: «sin marcar» es
 * el estado normal de la cartera y no merece un chip en cada fila.
 * `pequeno` = 10 px, para la tarjeta del Pipeline. `id` permite que una fila
 * que es un solo control (la de la tabla de Leads) lo use como descripción.
 */
export function ChipPotencial({ marca, pequeno = false, className, id }: {
  marca: PotencialLead | undefined
  pequeno?: boolean
  className?: string
  id?: string
}) {
  const nivel = marca?.nivel
  if (!nivel) return null
  const etiqueta = ETIQUETA_POTENCIAL[nivel]
  return (
    <span
      id={id}
      className={cn('pot-chip ac-pop', `pot-chip--${nivel}`, pequeno && 'pot-chip--pequeno', className)}
      title={`Potencial: ${etiqueta}`}
    >
      <IconoPotencial nivel={nivel} relleno={nivel === 'estrella'} className="pot-chip-ico" />
      {/* El espacio va FUERA del span oculto: dentro, el cálculo del nombre
          accesible lo recorta y se leería «Potencial:Estrella». */}
      <span className="sr-only">Potencial:</span>{' '}
      {etiqueta}
    </span>
  )
}

/** El chip de la ficha: pregunta por su propio lead (misma caché que las listas). */
export function ChipPotencialDeLead({ leadId }: { leadId: string }) {
  const { habilitada, item } = usePotencialLead(leadId)
  return habilitada ? <ChipPotencial marca={item} /> : null
}
