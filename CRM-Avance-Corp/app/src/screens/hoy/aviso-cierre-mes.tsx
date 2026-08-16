import type { JSX } from 'react'
import { CalendarClock, TriangleAlert } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { useCierreMesEstado } from '@/data/crm-queries'
import { avisoDelCiclo } from '@/lib/cierre-de-mes'

/**
 * El aviso del ciclo del CIERRE DE MES, para quien puede actuar (gerencia):
 * del 1 al 10 recuerda cuántos días quedan de ajuste, el día 10 avisa que el
 * sello pasa a las 09:20, y pasado el día sin sellar suena la ALARMA — sin
 * ella, un cron roto es invisible hasta el reclamo de una comisión.
 *
 * Si la consulta cae no hay banner: es advisory (fail-open) y el candado real
 * vive en el servidor. El texto lo decide `avisoDelCiclo` desde el estado que
 * NOMBRA el servidor; aquí solo se pinta.
 */
export function AvisoCierreMesPanel(): JSX.Element | null {
  const estado = useCierreMesEstado(true)
  const aviso = estado.data ? avisoDelCiclo(estado.data) : null
  if (!aviso) return null
  const alarma = aviso.tono === 'alarma'
  const Icono = alarma ? TriangleAlert : CalendarClock
  return (
    <Card
      // El anuncio de un alert lo dispara la INSERCIÓN del nodo: si el estado
      // cambia de 'hoy' a 'atascado' con la pestaña abierta (refetch al
      // reenfocar), mutar el atributo sobre el mismo div no anuncia nada. El
      // key remonta la Card al cambiar el tono y la alarma sí suena.
      key={aviso.tono}
      role={alarma ? 'alert' : undefined}
      className={alarma
        ? 'border-destructive/40 bg-destructive/[0.06]'
        : 'border-primary/25 bg-primary/[0.05]'}
    >
      <CardContent className="flex items-start gap-3 py-4">
        <Icono
          className={`mt-0.5 size-5 shrink-0 ${alarma ? 'text-destructive' : 'text-primary'}`}
          aria-hidden
        />
        <div>
          {/* Solo la PRIMERA letra: `capitalize` pondría Mayúscula En Cada Palabra. */}
          <h2 className="text-sm font-extrabold text-foreground first-letter:uppercase">{aviso.titulo}</h2>
          <p className="mt-1 text-xs text-foreground/70">{aviso.detalle}</p>
        </div>
      </CardContent>
    </Card>
  )
}
