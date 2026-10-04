// El teléfono de un lead de la base: marca en el celular (`tel:`) y copia en la laptop (ahí un `tel:` no marca
// nada). Lo comparten la hoja del analista y la ficha del lead (F2): un número que no sirve no se ofrece.
import { Copy, Phone } from 'lucide-react'
import { CLASE_ACCION } from '@/components/app/contacto'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { enlaceTel } from '@/lib/telefono'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import { copiarNumero } from './copiar-numero'

/** En la hoja, el teléfono ES el botón de llamar: marca en el celular, copia en la laptop. */
export function TelefonoLlamable({ fila, puedeMarcar }: { fila: FilaBaseGestion; puedeMarcar: boolean }) {
  const tel = enlaceTel(fila.telefono)
  if (!tel || !fila.telefono) return <span className="text-[var(--muted-foreground-strong)]">Sin teléfono</span>
  const legible = telefonoLegible(fila.telefono)
  const estilo = cn('inline-flex items-center gap-1.5 rounded px-1 font-semibold tabular-nums text-accent underline-offset-2 hover:underline', FOCO)
  if (puedeMarcar) {
    return (
      <a href={tel} aria-label={`Llamar a ${fila.nombre_completo}, ${legible}`} className={estilo}>
        <Phone className="size-3.5" aria-hidden />{legible}
      </a>
    )
  }
  return (
    <button type="button" onClick={() => copiarNumero(tel, legible)} aria-label={`Llamar a ${fila.nombre_completo}, ${legible}: copia su número`} title="Copiar el número" className={estilo}>
      <Phone className="size-3.5" aria-hidden />{legible}
    </button>
  )
}

const BOTON_CONTACTO = cn(CLASE_ACCION, 'cursor-pointer', FOCO)

/**
 * Los botones de contacto de la ficha, con el aspecto de los de la ficha del lead (`CLASE_ACCION`). NO es
 * `AccionesContacto`: ese registra la llamada por la puerta normal y mete el lead en el store, y un lead de la base
 * se registra con su propio formulario («¿Qué pasó con la llamada?»). Sin WhatsApp: la puerta de la base solo
 * registra llamadas. «Llamar» marca en el celular; en la laptop copia el número y avisa (`onLlamar`) para llevar
 * al analista a registrar el resultado.
 */
export function ContactoBase({ fila, puedeMarcar, onLlamar }: { fila: FilaBaseGestion; puedeMarcar: boolean; onLlamar?: () => void }) {
  const tel = enlaceTel(fila.telefono)
  if (!tel || !fila.telefono) return <p className="text-[13px] text-[var(--muted-foreground-strong)]">Sin teléfono para contactar</p>
  const legible = telefonoLegible(fila.telefono)
  return (
    <div role="group" aria-label="Contactar" className="flex flex-wrap items-center gap-1.5">
      {puedeMarcar ? (
        <a href={tel} className={BOTON_CONTACTO} aria-label={`Llamar a ${fila.nombre_completo}`}>
          <Phone aria-hidden /> <span>Llamar</span>
        </a>
      ) : (
        <button
          type="button"
          className={BOTON_CONTACTO}
          aria-label={`Llamar a ${fila.nombre_completo}: copia su número y pasa al resultado`}
          onClick={() => { copiarNumero(tel, legible); onLlamar?.() }}
        >
          <Phone aria-hidden /> <span>Llamar</span>
        </button>
      )}
      <button type="button" className={BOTON_CONTACTO} aria-label={`Copiar número de ${fila.nombre_completo}`} onClick={() => copiarNumero(tel, legible, 'copiar')}>
        <Copy aria-hidden /> <span>Copiar número</span>
      </button>
    </div>
  )
}
