// Rentabilidad R3 — el AVISO al analista: qué decidió Gerencia sobre sus solicitudes de tasa.
//
// Se muestra en la jornada del analista y del supervisor solo cuando hay algo que
// atender: una autorización vigente (puede crear el contrato con esa tasa), un tope
// que aceptar o declinar (D6), o una solicitud pendiente. Las decisiones se toman en el
// propio formulario de contrato; aquí se puede responder al tope sin abrirlo.
import { useMemo, useRef, useState, type JSX } from 'react'
import { BadgePercent, CheckCircle2, Clock, ShieldCheck, XCircle } from 'lucide-react'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { SectionHead } from '@/components/common/section-head'
import { useAuth } from '@/lib/auth-context'
import { fmtFecha, money, numero } from '@/lib/format'
import type { SolicitudTasa } from '@/data/crm-api'
import { DIAS_RECHAZO_VISIBLE, ESTADOS_SOLICITUD_TASA_SEGUIMIENTO } from '@/lib/rentabilidad'
import { useResponderTopeTasa, useSolicitudesTasa } from '@/data/crm-queries'

const CATEGORIA_TXT: Record<string, string> = { nuevo: 'nuevo', renovacion: 'renovación', upgrade: 'upgrade' }
function tasaTxt(n: number): string {
  return `${n.toLocaleString('es-PE', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}%`
}

export function TasasAutorizadasAnalistaPanel(): JSX.Element | null {
  const { yo } = useAuth()
  const sesionReal = !!yo && yo.demo !== true
  // Solo las MÍAS (filtro de servidor, antes del límite): vivas, más los rechazos de los últimos días.
  const consulta = useSolicitudesTasa(ESTADOS_SOLICITUD_TASA_SEGUIMIENTO, sesionReal, sesionReal ? 60_000 : false, { soloMias: true })
  const responder = useResponderTopeTasa()
  const mias = useMemo(() => {
    const corte = Date.now() - DIAS_RECHAZO_VISIBLE * 86_400_000
    return (consulta.data ?? []).filter((s) => s.es_mia && (s.vigente
      || (s.estado_efectivo === 'rechazada' && s.resuelta_en != null && new Date(s.resuelta_en).getTime() >= corte)))
  }, [consulta.data])
  // Tras responder, los botones de la tarjeta desaparecen con el foco dentro: se posa en el cuerpo del panel. Si era la
  // última, el panel NO se desmonta (quedaría el foco en <body>): se queda diciendo que no hay nada en curso.
  const cuerpoRef = useRef<HTMLDivElement>(null)
  const [huboAccion, setHuboAccion] = useState(false)
  if (!sesionReal || (mias.length === 0 && !huboAccion)) return null

  const responderTope = async (s: SolicitudTasa, acepta: boolean) => {
    setHuboAccion(true)
    try {
      await responder.mutateAsync({ solicitudId: s.id, acepta, motivo: null })
      toast.success(acepta ? `Aceptaste ${tasaTxt(s.tasa_maxima_autorizada ?? 0)} para ${s.cliente_nombre}: ${s.lead_id ? 'continúa desde la ficha del lead' : 'crea el contrato con esa tasa'}.` : `Declinaste el tope para ${s.cliente_nombre}.`)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo responder.')
    } finally {
      cuerpoRef.current?.focus()
    }
  }

  return (
    <Card className="min-w-0" data-testid="tasas-autorizadas-analista">
      <SectionHead icon={BadgePercent} title="Tus solicitudes de tasa" right={<span className="text-xs font-bold tabular-nums text-muted-foreground">{numero(mias.length)}<span className="sr-only"> en curso</span></span>} />
      <CardContent className="min-w-0 pt-1">
        <div ref={cuerpoRef} tabIndex={-1} className="outline-none">
          <p role="status" className="sr-only">{mias.length === 0 ? 'Sin solicitudes de tasa en curso.' : `${numero(mias.length)} ${mias.length === 1 ? 'solicitud de tasa en curso' : 'solicitudes de tasa en curso'}.`}</p>
          {mias.length === 0 && <p className="py-2 text-xs text-muted-foreground">Sin solicitudes de tasa en curso.</p>}
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ul role="list" className="flex flex-col gap-2" aria-label="Solicitudes de tasa en curso">
            {mias.map((s) => (
              <li key={s.id} className="rounded-xl border border-border bg-card p-3" aria-labelledby={`aut-${s.id}-cliente`}>
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p id={`aut-${s.id}-cliente`} className="truncate text-sm font-bold text-foreground" title={s.cliente_nombre}>{s.cliente_nombre}</p>
                    {s.lead_id && <span className="text-[10px] font-semibold text-primary">Solicitud desde lead</span>}
                    <p className="text-[11px] text-muted-foreground">
                      Contrato {CATEGORIA_TXT[s.categoria] ?? s.categoria} · {money(s.capital, s.moneda)} · pediste {tasaTxt(s.tasa_solicitada)} (base {tasaTxt(s.tasa_base)}) · vence {fmtFecha(s.vence_en)}
                    </p>
                  </div>
                  {s.estado_efectivo === 'pendiente' && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-bold text-amber-900"><Clock className="size-3" aria-hidden /> Pendiente de Gerencia</span>
                  )}
                  {(s.estado_efectivo === 'aprobada' || s.estado_efectivo === 'aceptada_por_analista') && s.tasa_maxima_autorizada != null && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-[11px] font-bold text-primary"><CheckCircle2 className="size-3" aria-hidden /> Autorizada hasta {tasaTxt(s.tasa_maxima_autorizada)}</span>
                  )}
                  {s.estado_efectivo === 'aprobada_con_tope' && s.tasa_maxima_autorizada != null && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-sky-50 px-2 py-0.5 text-[11px] font-bold text-sky-900"><ShieldCheck className="size-3" aria-hidden /> Gerencia ofrece hasta {tasaTxt(s.tasa_maxima_autorizada)}</span>
                  )}
                  {s.estado_efectivo === 'rechazada' && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-destructive/10 px-2 py-0.5 text-[11px] font-bold text-destructive-text"><XCircle className="size-3" aria-hidden /> Rechazada por Gerencia</span>
                  )}
                </div>
                {s.estado_efectivo === 'rechazada' && (
                  <p className="mt-2 text-[11px] text-muted-foreground">
                    {s.resuelta_en ? `El ${fmtFecha(s.resuelta_en)}` : 'Gerencia'}{s.motivo_resolucion ? `: «${s.motivo_resolucion}»` : ' sin motivo'}. La tasa queda en la base {tasaTxt(s.tasa_base)}; puedes volver a pedir con otro motivo desde el formulario.
                  </p>
                )}
                {s.estado_efectivo === 'aprobada_con_tope' && (
                  <div className="mt-2 flex flex-wrap justify-end gap-2">
                    <Button type="button" size="sm" variant="outline" className="min-h-10" disabled={responder.isPending} onClick={() => void responderTope(s, false)} aria-describedby={`aut-${s.id}-cliente`}>No cerrar a ese tope</Button>
                    <Button type="button" size="sm" className="min-h-10" disabled={responder.isPending} onClick={() => void responderTope(s, true)} aria-describedby={`aut-${s.id}-cliente`}>Aceptar y continuar</Button>
                  </div>
                )}
                {(s.estado_efectivo === 'aprobada' || s.estado_efectivo === 'aceptada_por_analista') && (
                  <p className="mt-2 text-[11px] text-muted-foreground">Crea el contrato desde la ficha del cliente con los mismos datos (capital y plazo): el formulario ya trae la tasa autorizada.</p>
                )}
              </li>
            ))}
          </ul>
        </div>
      </CardContent>
    </Card>
  )
}
