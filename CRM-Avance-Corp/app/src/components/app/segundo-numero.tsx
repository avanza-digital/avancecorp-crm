import { Badge } from '@/components/ui/badge'
import { enlaceTel, numeroWhatsapp } from '@/lib/telefono'
import { reconocerTelefono } from '@/lib/validacion'

/**
 * El segundo número del lead en sus tres estados. Vive aparte de `Fila` porque
 * la lógica de «qué hay que enseñar» no es de presentación: decide entre un
 * canal de contacto usable, un dato que hay que corregir y una ausencia real.
 *
 * El texto crudo NO se ofrece como enlace a propósito. Si no se pudo entender
 * como teléfono, un `tel:` encima marcaría cualquier cosa; el vendedor lo lee,
 * deduce el número y lo corrige. Presentarlo como marcable sería mentir sobre
 * la confianza que merece.
 */
export function SegundoNumero({ numero, crudo }: { numero: string | null; crudo: string | null }) {
  if (numero) {
    const tel = enlaceTel(numero)
    // ⚠️ `numeroWhatsapp` solo mira que haya dígitos suficientes: sobre un FIJO
    // devuelve un número perfectamente formado que NADIE va a contestar. Quien
    // decide si hay WhatsApp es el reconocedor, que sí distingue móvil de fijo.
    const wa = reconocerTelefono(numero)?.movil ? numeroWhatsapp(numero) : null
    return (
      <span className="inline-flex flex-wrap items-baseline gap-x-2 gap-y-1">
        {tel ? (
          <a href={tel} className="tabular-nums text-primary underline-offset-2 hover:underline">
            {numero}
          </a>
        ) : (
          <span className="tabular-nums">{numero}</span>
        )}
        {wa && (
          <a
            href={`https://wa.me/${wa}`}
            target="_blank"
            rel="noreferrer"
            className="text-[11px] font-semibold text-primary underline-offset-2 hover:underline"
          >
            WhatsApp
          </a>
        )}
      </span>
    )
  }
  if (crudo) {
    return (
      <span className="inline-flex flex-wrap items-baseline gap-x-2 gap-y-1">
        <span className="tabular-nums">«{crudo}»</span>
        <Badge color="var(--warning)">sin validar</Badge>
      </span>
    )
  }
  return (
    <span className="text-muted-foreground">— el origen no dio un segundo número</span>
  )
}
