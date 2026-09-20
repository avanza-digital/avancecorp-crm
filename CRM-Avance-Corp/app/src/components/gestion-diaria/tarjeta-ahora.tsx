// «Ahora»: la respuesta a la pregunta de la pantalla, en una sola tarjeta.
//
// Aquí vive TODO el contexto que las filas de la cola dejaron de llevar —etapa,
// tiempo, última gestión— y la ÚNICA acción primaria de la pantalla: «Llamar».
// El resto (WhatsApp, registrar el resultado, abrir la ficha) va detrás de un
// solo botón, por la ley de Hick: una decisión visible, no dieciséis.
//
// Piso tipográfico 16 px y objetivos de 48: la queja de los analistas del
// 20/09/2026 fue «demasiada información, muchas letras pequeñas».
import type { JSX } from 'react'
import { ClipboardList, IdCard } from 'lucide-react'
import { AccionesContacto } from '@/components/app/contacto'
import { ChipTiempo } from '@/components/gestion-diaria/chip-tiempo'
import { Button } from '@/components/ui/button'
import { ETAPA_INFO, type Etapa, type Lead } from '@/lib/tipos'
import { cuandoLimaDe, type FilaDiaria } from '@/lib/gestion-diaria-analista'

/** Las dos últimas gestiones del lead, en el idioma del analista. */
function ultimasGestiones(fila: FilaDiaria): string[] {
  const s = fila.senal
  if (s === null) return []
  const lineas: string[] = []
  if (s.ultima_llamada_en !== null) {
    const resultado = (s.ultima_llamada_resultado ?? s.ultima_llamada_tipo ?? '').replaceAll('_', ' ')
    lineas.push(`${cuandoLimaDe(s.ultima_llamada_en)} · ${resultado === '' ? 'llamada' : resultado}`)
  }
  if (s.intentos_sin_respuesta > 0) {
    lineas.push(`${s.intentos_sin_respuesta} ${s.intentos_sin_respuesta === 1 ? 'intento' : 'intentos'} sin respuesta`)
  }
  if (lineas.length === 0 && s.ultima_conversacion_en !== null) {
    lineas.push(`Última conversación ${cuandoLimaDe(s.ultima_conversacion_en)}`)
  }
  return lineas
}

export function TarjetaAhora({ idBase, fila, lead, ahora, posicion, total, onRegistrar, onAbrirFicha }: {
  /** Base de `useId()` de la pantalla: dos instancias no pueden compartir id. */
  idBase: string
  fila: FilaDiaria | null
  lead: Lead | null
  ahora: number
  /** 1-based dentro del grupo visible; 0 cuando no hay nadie. */
  posicion: number
  total: number
  onRegistrar: () => void
  onAbrirFicha: () => void
}): JSX.Element {
  if (fila === null) {
    return (
      <section
        aria-labelledby={`${idBase}-ahora`}
        className="flex w-full shrink-0 flex-col gap-4 rounded-2xl border border-border bg-card p-6 lg:w-[22rem]"
      >
        <h3 id={`${idBase}-ahora`} className="text-xl font-semibold text-primary">Ahora</h3>
        <p role="status" className="text-base text-[var(--muted-foreground-strong)]">
          No queda nadie por llamar en este grupo. Revisa las otras pestañas de tu cola.
        </p>
      </section>
    )
  }
  const etapa = ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
  const gestiones = ultimasGestiones(fila)
  return (
    <section
      aria-labelledby={`${idBase}-ahora`}
      className="flex w-full shrink-0 flex-col justify-between gap-4 rounded-2xl border border-border bg-card p-6 lg:w-[22rem]"
    >
      <h3 id={`${idBase}-ahora`} className="text-xl font-semibold text-primary">Ahora</h3>

      {/* Elegir una fila sustituye TODO este panel y el foco se queda en la
          fila: sin esto el cambio sería mudo. No se pone `aria-live` en la
          sección entera porque el chip de tiempo se recalcula cada minuto y
          la región parlotearía sola. */}
      <span className="sr-only" role="status">Ahora: {fila.nombre_completo}</span>
      <p className="text-lg font-medium leading-7 text-foreground">{fila.nombre_completo}</p>
      <p className="text-base text-[var(--muted-foreground-strong)]">
        {etapa}{total > 0 && ` · ${posicion} de ${total} en este grupo`}
      </p>
      <ChipTiempo fila={fila} ahora={ahora} className="self-start" />

      {gestiones.length > 0 && (
        <>
          <div className="h-px bg-border" aria-hidden />
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ul role="list" aria-label="Últimas gestiones" className="space-y-2">
            {gestiones.map((g) => (
              <li key={g} className="text-base text-[var(--muted-foreground-strong)]">{g}</li>
            ))}
          </ul>
        </>
      )}

      <div className="space-y-3">
        {lead !== null ? (
          // Se reutiliza `AccionesContacto` y NO se reimplementa: lleva el
          // `asegurarLead` de la Fase 4e, la espera de 4 s que distingue una
          // llamada real de un click sin salir, y el escudo de propagación.
          <AccionesContacto lead={lead} destacada grande />
        ) : (
          <p className="text-base text-[var(--muted-foreground-strong)]">Abre la ficha para llamar.</p>
        )}
        <div className="flex flex-wrap gap-3">
          <Button variant="outline" className="h-12 text-base font-normal" onClick={onRegistrar}
            aria-label={`Registrar resultado de ${fila.nombre_completo}`}>
            <ClipboardList aria-hidden /> Registrar resultado
          </Button>
          <Button variant="outline" className="h-12 text-base font-normal" onClick={onAbrirFicha}
            aria-label={`Abrir la ficha de ${fila.nombre_completo}`}>
            <IdCard aria-hidden /> Ver ficha
          </Button>
        </div>
      </div>
    </section>
  )
}
