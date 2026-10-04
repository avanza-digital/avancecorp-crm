// Lo que hay detrás de «Intentos de hoy» o «Reactivaciones del mes» de un analista (F4, «todo número se abre»): una
// hoja lateral con la lista del servidor (`crm.base_gestion_resumen_detalle`, B6b), del más reciente al más antiguo:
// el lead, cuándo, qué pasó y quién lo registró, y si sigue en la base. El lead que sigue en la base abre su ficha de
// la base; el que volvió a la cartera, su ficha normal (si el CRM lo tiene cargado). Estados honestos: cargando,
// error con reintento, «aún no disponible» (servidor sin la B6b: nunca un cero inventado) y vacío.
import type { JSX } from 'react'
import { ListX, RotateCcw, X } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { TITULO_CIFRA, etiquetaDetalleCifra, etiquetaMomento, type CifraDetalle, type FilaDetalleCifra } from '@/lib/base-gestion'

export interface CifraAbierta {
  vendedorId: string
  nombre: string
  cifra: CifraDetalle
  valor: number
}

export function DetalleCifra({ abierta, filas, cargando, error, reintentando, onReintentar, ahora, esMovil, onCerrar, abrible, onAbrirLead, focoRespaldo }: {
  abierta: CifraAbierta | null
  /** En el celular, una tarjeta por registro (la tabla no cabe). */
  esMovil: boolean
  /** `undefined` mientras carga; `null` si el servidor aún no tiene la lectura. */
  filas: readonly FilaDetalleCifra[] | null | undefined
  cargando: boolean
  error: boolean
  reintentando: boolean
  onReintentar: () => void
  ahora: number
  onCerrar: () => void
  /** ¿El lead se puede abrir (está en la base cargada o en el CRM)? */
  abrible: (fila: FilaDetalleCifra) => boolean
  onAbrirLead: (fila: FilaDetalleCifra) => void
  /** Si la cifra que lo abrió dejó de ser botón con el detalle abierto (pasó a 0 al refrescar), el foco vuelve aquí. */
  focoRespaldo?: () => HTMLElement | null
}): JSX.Element {
  const titulo = abierta ? TITULO_CIFRA[abierta.cifra] : ''
  return (
    <Sheet open={abierta !== null} onClose={onCerrar} className="w-full max-w-full sm:w-[760px] sm:max-w-[94vw]" {...(focoRespaldo ? { focoRespaldo } : {})}>
      {abierta && (
        <>
          <SheetHeader>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]">{abierta.nombre}</p>
                <SheetTitle className="text-lg">{titulo} <span className="tabular-nums text-primary">· {abierta.valor}</span></SheetTitle>
                <SheetDescription className="text-[13px] text-[var(--muted-foreground-strong)]">
                  {abierta.cifra === 'intentos_hoy'
                    ? 'Intentos registrados hoy sobre los leads de su base (cuentan para su analista aunque los registre Supervisión).'
                    : 'Leads de su base que volvieron a la cartera este mes.'}
                  {' '}Del más reciente al más antiguo.
                </SheetDescription>
              </div>
              <button
                type="button"
                onClick={onCerrar}
                aria-label="Cerrar el detalle"
                className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground pointer-coarse:size-11', FOCO)}
              >
                <X className="size-4" aria-hidden />
              </button>
            </div>
          </SheetHeader>
          {/* `scroll-pt-10`: el lead enfocado no queda bajo la cabecera fija de la tabla (WCAG 2.4.11). */}
          <SheetBody className="scroll-pt-10 px-0 py-0">
            {cargando && filas === undefined ? (
              <div className="pt-4"><PanelCargando filas={5} /></div>
            ) : error && filas === undefined ? (
              <div className="flex flex-col items-center gap-3 px-6 py-12 text-center">
                <p role="alert" className="text-base font-semibold text-foreground">No se pudo cargar el detalle.</p>
                <Button variant="outline" size="sm" className="pointer-coarse:h-11" aria-disabled={reintentando || undefined} onClick={() => { if (!reintentando) onReintentar() }}>
                  <RotateCcw aria-hidden /> Reintentar
                </Button>
              </div>
            ) : filas === null ? (
              <PanelVacio icono={ListX} titulo="El detalle aún no está disponible" detalle="El servidor todavía no tiene esta lectura. La cifra del panel sí es la vigente." />
            ) : !filas || filas.length === 0 ? (
              <PanelVacio icono={ListX} titulo="Ya no hay registros detrás de esta cifra" detalle="Pudo cambiar desde que se cargó el panel: vuelve a abrirlo para ver la cifra al día." />
            ) : esMovil ? (
              // Rol explícito: con el list-style:none del preflight, Safari + VoiceOver deja de anunciar un <ol> como lista.
              <div role="list" aria-label={`${titulo} de ${abierta.nombre}`} className="space-y-2 p-4">
                {filas.map((f, i) => (
                  <div role="listitem" key={`${f.lead_id}-${f.en}-${i}`} className="rounded-xl border border-border bg-card p-3">
                    <div className="flex items-start justify-between gap-2">
                      {abrible(f) ? (
                        <button type="button" onClick={() => onAbrirLead(f)} className={cn('cursor-pointer rounded text-left text-base font-semibold underline decoration-[var(--border-strong)] decoration-dotted underline-offset-4', FOCO)}>
                          {f.nombre_completo}
                        </button>
                      ) : <p className="text-base font-semibold">{f.nombre_completo}</p>}
                      {f.sigue_en_base
                        ? <Badge color="var(--primary)">En la base</Badge>
                        : <Badge color="var(--muted-foreground-strong)">Salió de la base</Badge>}
                    </div>
                    <p className="mt-1 text-sm">{etiquetaDetalleCifra(f.detalle) ?? 'Sin detalle'}</p>
                    <p className="text-[13px] text-[var(--muted-foreground-strong)]">{etiquetaMomento(f.en, ahora)} · {f.autor ?? 'Sin dato'}</p>
                  </div>
                ))}
              </div>
            ) : (
              <table className="min-w-full border-separate border-spacing-0">
                <caption className="sr-only">{titulo} de {abierta.nombre}</caption>
                <thead>
                  <tr>
                    {['#', 'Lead', 'Cuándo', abierta.cifra === 'intentos_hoy' ? 'Resultado' : 'Detalle', 'Registró', 'Estado'].map((c, i) => (
                      <th key={c} scope="col" className={cn('sticky top-0 z-10 whitespace-nowrap border-b border-[var(--border-strong)] bg-muted px-3 py-2 text-left text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]', i === 0 && 'w-10 text-center')}>{c}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {filas.map((f, i) => (
                    <tr key={`${f.lead_id}-${f.en}-${i}`} className="hover:bg-accent/5">
                      <td className="border-b border-border px-3 py-2 text-center text-[13px] tabular-nums text-[var(--muted-foreground-strong)]">{i + 1}</td>
                      <th scope="row" className="max-w-56 border-b border-border px-3 py-2 text-left text-sm font-semibold">
                        {abrible(f) ? (
                          <button
                            type="button"
                            onClick={() => onAbrirLead(f)}
                            className={cn('max-w-full cursor-pointer truncate rounded text-left underline decoration-[var(--border-strong)] decoration-dotted underline-offset-4 hover:decoration-solid', FOCO)}
                          >
                            {f.nombre_completo}
                          </button>
                        ) : <span className="block truncate">{f.nombre_completo}</span>}
                      </th>
                      <td className="whitespace-nowrap border-b border-border px-3 py-2 text-sm tabular-nums">{etiquetaMomento(f.en, ahora)}</td>
                      <td className="min-w-28 border-b border-border px-3 py-2 text-sm">{etiquetaDetalleCifra(f.detalle) ?? <span className="text-[var(--muted-foreground-strong)]">Sin detalle</span>}</td>
                      <td className="whitespace-nowrap border-b border-border px-3 py-2 text-sm">{f.autor ?? <span className="text-[var(--muted-foreground-strong)]">Sin dato</span>}</td>
                      <td className="whitespace-nowrap border-b border-border px-3 py-2">
                        {f.sigue_en_base
                          ? <Badge color="var(--primary)">En la base</Badge>
                          : <Badge color="var(--muted-foreground-strong)">Salió de la base</Badge>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </SheetBody>
        </>
      )}
    </Sheet>
  )
}
