// El bloque «No contactar» de la vista del supervisor (F4, decisiones 1 y 4 de Miguel, 03/10): con el interruptor
// «Ver no contactar» encendido, AL FINAL de la hoja, los leads de la base marcados «No contactar» (Ley 29571), también
// los que descansan. Cada uno con su marca completa: cuándo, motivo y quién la puso; si la marca vino de otro lead de
// la misma persona, se dice (el servidor no la copia a este lead). Nadie los llama: el teléfono no se ofrece. El
// nombre abre la ficha, donde Supervisión o Gerencia pueden quitar la marca. Rojo: es lo que no se puede tocar.
import type { JSX, Ref } from 'react'
import { Ban } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  etiquetaAnalista,
  etiquetaMomento,
  etiquetaMotivoDescarte,
  type FilaBaseGestion,
} from '@/lib/base-gestion'
import { CELDA, ENCABEZADO } from './hoja-base'
import { EtapaMaximaChip } from './piezas-base'

const MARCA_DE_OTRO_LEAD = 'Viene de otro lead de la persona'

/** «Hasta el 02/11» si el lead está en descanso (los vetados en descanso también se listan). */
function descanso(fila: FilaBaseGestion, ahora: number): string | null {
  if (!fila.enfriado_hasta) return null
  const hasta = Date.parse(fila.enfriado_hasta)
  if (!Number.isFinite(hasta) || hasta <= ahora) return null
  const [, mes, dia] = fechaLima(hasta).split('-')
  return `Descansa hasta el ${dia}/${mes}`
}

/** La marca: cuándo, motivo y quién (o que vino de otro lead de la persona). */
function marcaDe(fila: FilaBaseGestion, ahora: number) {
  const propia = Boolean(fila.no_contactar_en || fila.no_contactar_motivo || fila.no_contactar_por)
  return {
    propia,
    cuando: fila.no_contactar_en ? etiquetaMomento(fila.no_contactar_en, ahora) : null,
    motivo: fila.no_contactar_motivo ?? (propia ? null : MARCA_DE_OTRO_LEAD),
    quien: fila.no_contactar_por ?? null,
  }
}

export function HojaVetados({ id, filas, numeroInicial, total, esMovil, ahora, cargando, tituloRef, onAbrir }: {
  id: string
  filas: readonly FilaBaseGestion[]
  /** # de la primera fila de esta página. */
  numeroInicial: number
  /** Cuántos vetados hay en total (con páginas, más que `filas`). */
  total: number
  esMovil: boolean
  ahora: number
  /** Encendido el interruptor, mientras llega la lista con los vetados. */
  cargando: boolean
  tituloRef?: Ref<HTMLHeadingElement> | undefined
  onAbrir: (leadId: string) => void
}): JSX.Element {
  const titulo = (
    <div className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
      <h2 id={id} ref={tituloRef} tabIndex={-1} className={cn('inline-flex items-center gap-2 rounded text-[15px] font-bold text-[var(--destructive-text)]', FOCO)}>
        <Ban className="size-4" aria-hidden />
        No contactar
        <span className="sr-only">:</span>
        <span className="rounded-full bg-destructive px-2 py-0.5 text-[13px] tabular-nums text-destructive-foreground">{cargando ? '…' : total}</span>
      </h2>
      <span className="text-[13px] text-[var(--muted-foreground-strong)]">Ley 29571 (No insista): nadie los llama. La marca se quita desde su ficha.</span>
    </div>
  )

  if (cargando) {
    return (
      <div className="space-y-2">
        {titulo}
        {/* El aviso para el lector lo da la pantalla (una región de estado que ya existía): aquí solo se ve. */}
        <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm text-[var(--muted-foreground-strong)]">Cargando los leads con «No contactar»…</p>
      </div>
    )
  }
  if (filas.length === 0) {
    return (
      <div className="space-y-2">
        {titulo}
        <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm text-[var(--muted-foreground-strong)]">Ningún lead de la base con «No contactar» coincide con lo que estás viendo.</p>
      </div>
    )
  }

  if (esMovil) {
    return (
      <div className="space-y-2">
        {titulo}
        <div role="list" aria-labelledby={id} className="space-y-3">
          {filas.map((f) => {
            const marca = marcaDe(f, ahora)
            const pausa = descanso(f, ahora)
            return (
              <div role="listitem" key={f.lead_id} className="rounded-xl border border-destructive/40 bg-card p-4 shadow-[inset_4px_0_0_var(--destructive)]">
                <div className="flex items-start justify-between gap-2">
                  <p className="text-base font-semibold">{f.nombre_completo}</p>
                  <Badge color="var(--destructive)" style={{ color: 'var(--destructive-text)' }}>No contactar</Badge>
                </div>
                <p className="text-sm text-[var(--muted-foreground-strong)]">{etiquetaAnalista(f)}{pausa ? ` · ${pausa}` : ''}</p>
                <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                  <div><dt className="text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Desde</dt><dd>{marca.cuando ?? 'Sin dato'}</dd></div>
                  <div><dt className="text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Marcó</dt><dd>{marca.quien ?? 'Sin dato'}</dd></div>
                  <div className="col-span-2"><dt className="text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Motivo</dt><dd>{marca.motivo ?? 'Sin motivo'}</dd></div>
                </dl>
                <button
                  type="button"
                  onClick={() => onAbrir(f.lead_id)}
                  data-foco-clave={`base-ficha-${f.lead_id}`}
                  aria-label={`Ver ficha de ${f.nombre_completo}`}
                  className={cn('mt-3 inline-flex h-10 w-full cursor-pointer items-center justify-center rounded-lg border border-border text-sm font-semibold hover:bg-muted pointer-coarse:h-11', FOCO)}
                >
                  Ver ficha
                </button>
              </div>
            )
          })}
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-2">
      {titulo}
      {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La hoja se desplaza con el teclado en horizontal. */}
      <div className={cn('ac-scroll overflow-auto rounded-lg border border-destructive/40 bg-card', FOCO)} tabIndex={0} role="region" aria-labelledby={id}>
        <table className="min-w-full border-separate border-spacing-0">
          <caption className="sr-only">Leads de la base marcados «No contactar»: cuándo, motivo y quién puso la marca.</caption>
          <thead>
            <tr>
              <th scope="col" className={cn(ENCABEZADO, 'w-12 min-w-12 text-center')}>#</th>
              <th scope="col" className={cn(ENCABEZADO, 'w-64 min-w-64')}>Lead</th>
              <th scope="col" className={ENCABEZADO}>Gestiona</th>
              <th scope="col" className={ENCABEZADO}>Marcado</th>
              <th scope="col" className={ENCABEZADO}>Motivo de la marca</th>
              <th scope="col" className={ENCABEZADO}>Marcó</th>
              <th scope="col" className={ENCABEZADO}>Descanso</th>
              <th scope="col" className={ENCABEZADO}>Etapa máxima</th>
              <th scope="col" className={cn(ENCABEZADO, 'border-r-0')}>Motivo del descarte</th>
            </tr>
          </thead>
          <tbody>
            {filas.map((f, i) => {
              const marca = marcaDe(f, ahora)
              return (
                <tr key={f.lead_id} className="bg-destructive/[0.03] hover:bg-destructive/[0.06]">
                  <td className={cn(CELDA, 'text-center text-[13px] font-bold tabular-nums text-[var(--destructive-text)]')}>{numeroInicial + i}</td>
                  <th scope="row" className={cn(CELDA, 'max-w-64 truncate text-base font-semibold')} title={f.nombre_completo}>
                    <button
                      type="button"
                      onClick={() => onAbrir(f.lead_id)}
                      data-foco-clave={`base-ficha-${f.lead_id}`}
                      className={cn('max-w-full cursor-pointer truncate rounded text-left underline decoration-[var(--border-strong)] decoration-dotted underline-offset-4 hover:decoration-solid', FOCO)}
                    >
                      {f.nombre_completo}
                    </button>
                  </th>
                  <td className={cn(CELDA, !f.vendedor_id && 'text-[var(--muted-foreground-strong)]')}>{etiquetaAnalista(f)}</td>
                  <td className={cn(CELDA, 'tabular-nums')}>{marca.cuando ?? <span className="text-[var(--muted-foreground-strong)]">Sin dato</span>}</td>
                  <td className={cn(CELDA, 'max-w-80 truncate', !marca.propia && 'text-[var(--muted-foreground-strong)]')} title={marca.motivo ?? undefined}>{marca.motivo ?? <span className="text-[var(--muted-foreground-strong)]">Sin motivo</span>}</td>
                  <td className={CELDA}>{marca.quien ?? <span className="text-[var(--muted-foreground-strong)]">Sin dato</span>}</td>
                  <td className={CELDA}>{descanso(f, ahora) ?? <span className="text-[var(--muted-foreground-strong)]">—</span>}</td>
                  <td className={CELDA}><EtapaMaximaChip etapa={f.etapa_maxima} /></td>
                  <td className={cn(CELDA, 'border-r-0')}>{etiquetaMotivoDescarte(f.motivo_descarte)}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
