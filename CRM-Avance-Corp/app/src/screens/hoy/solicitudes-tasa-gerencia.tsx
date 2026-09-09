// Rentabilidad R3 — la BANDEJA de Gerencia: solicitudes de tasa superior a la base.
//
// Cada tarjeta es un contrato en intención de un analista que pide más que la tasa
// que dice la política. Gerencia decide en UN clic: Aprobar (la tasa pedida), Rechazar,
// o Aprobar hasta X% (D6: un tope entre la base y lo pedido; el analista acepta o no).
// Quien pidió nunca resuelve la suya (D3): el servidor lo impide y aquí ni se ofrece.
// Prioridad (D1): las de clientes que ya invirtieron van primero (lo ordena el servidor).
// Todo sale de crm.solicitudes_tasa_fn y las decisiones van por crm.resolver_solicitud_tasa_fn.
import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
import { CheckCircle2, Inbox, RotateCcw, XCircle } from 'lucide-react'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import { SectionHead } from '@/components/common/section-head'
import { PanelVacio } from '@/components/common/estado-panel'
import { useAuth } from '@/lib/auth-context'
import { cn } from '@/lib/utils'
import { fmtFecha, money, numero } from '@/lib/format'
import { parseMonto } from '@/lib/numero'
import type { SolicitudTasa } from '@/data/crm-api'
import { etiquetaReglaTasa } from '@/lib/rentabilidad'
import { useResolverSolicitudTasa, useSolicitudesTasa } from '@/data/crm-queries'

const CATEGORIA_TXT: Record<string, string> = { nuevo: 'Nuevo', renovacion: 'Renovación', upgrade: 'Upgrade' }
/** La bandeja se refresca sola: una solicitud nueva aparece sin recargar. */
const REFRESCO_MS = 45_000

function tasaTxt(n: number): string {
  return `${n.toLocaleString('es-PE', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}%`
}

function TarjetaSolicitud({ s, onDecidir, ocupada }: {
  s: SolicitudTasa
  onDecidir: (decision: 'aprobar' | 'rechazar' | 'aprobar_hasta', tope: number | null, motivo: string | null) => Promise<void>
  ocupada: boolean
}): JSX.Element {
  const [tope, setTope] = useState('')
  const [motivo, setMotivo] = useState('')
  const [modoTope, setModoTope] = useState(false)
  const [topeInvalido, setTopeInvalido] = useState(false)
  const topeNum = parseMonto(tope)
  const topeValido = topeNum != null && topeNum > s.tasa_base && topeNum <= s.tasa_solicitada
  const puntos = s.tasa_solicitada - s.tasa_base
  // El nombre del cliente da nombre a la tarjeta y describe sus botones: «Rechazar» × N tarjetas dejan de ser iguales en el rotor.
  const idCliente = `sol-${s.id}-cliente`
  // Foco (a11y): abrir «Aprobar hasta…» lleva al campo del tope; cancelar devuelve el foco al botón que lo abrió
  // (el intercambio de filas desmonta el nodo enfocado y el foco caería a <body>).
  const abrirRef = useRef<HTMLButtonElement>(null)
  const topeRef = useRef<HTMLInputElement>(null)
  const volviendo = useRef(false)
  useEffect(() => {
    if (modoTope) topeRef.current?.focus()
    else if (volviendo.current) { volviendo.current = false; abrirRef.current?.focus() }
  }, [modoTope])
  const cerrarTope = () => { volviendo.current = true; setTopeInvalido(false); setModoTope(false) }
  // El botón no se deshabilita (un botón inactivo no explica por qué): con un tope fuera de rango, el campo se marca
  // inválido y la ayuda dice el rango.
  const aprobarHasta = () => {
    if (!topeValido || topeNum == null) { setTopeInvalido(true); topeRef.current?.focus(); return }
    setTopeInvalido(false)
    void onDecidir('aprobar_hasta', topeNum, motivo.trim() || null)
  }
  return (
    <li className={cn('rounded-xl border bg-card p-3 shadow-[var(--shadow-card)]', s.prioridad_bandeja ? 'border-primary/40' : 'border-border')} aria-labelledby={idCliente}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p id={idCliente} className="truncate text-sm font-extrabold text-foreground" title={s.cliente_nombre}>{s.cliente_nombre}</p>
          {s.lead_id && <span className="text-[10px] font-semibold text-primary">Solicitud desde lead</span>}
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {CATEGORIA_TXT[s.categoria] ?? s.categoria}{s.contrato_origen_numero ? ` de ${s.contrato_origen_numero}` : ''} · {money(s.capital, s.moneda)} · {fmtFecha(s.fecha_inicio)} <span aria-hidden>→</span><span className="sr-only">al</span> {fmtFecha(s.fecha_vencimiento)}
          </p>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            Pide <strong className="text-foreground">{s.solicitante_nombre}</strong> · {fmtFecha(s.solicitada_en)} · vence {fmtFecha(s.vence_en)}
            {s.prioridad_bandeja && <span className="ml-1 rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-bold text-primary">cliente con {numero(s.contratos_previos)} {s.contratos_previos === 1 ? 'contrato' : 'contratos'}</span>}
          </p>
        </div>
        <div className="shrink-0 text-right">
          <p className="text-[11px] text-muted-foreground">base {tasaTxt(s.tasa_base)}</p>
          <p className="text-lg font-extrabold tabular-nums text-primary"><span className="sr-only">pedida </span>{tasaTxt(s.tasa_solicitada)}</p>
          <p className="text-[11px] tabular-nums text-muted-foreground">+{puntos.toLocaleString('es-PE', { maximumFractionDigits: 2 })} <abbr title="puntos" className="no-underline">pts</abbr></p>
        </div>
      </div>
      <p className="mt-2 rounded-lg bg-muted/40 px-2.5 py-1.5 text-xs text-foreground/90"><span className="font-bold">Motivo:</span> {s.motivo}</p>
      <p className="mt-1 text-[11px] text-muted-foreground">{etiquetaReglaTasa(s.regla_base)}.</p>
      {modoTope ? (
        <div className="mt-3 space-y-2 rounded-lg border border-border bg-muted/30 p-3" role="group" aria-label="Aprobar hasta un tope">
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-[9rem_1fr]">
            <div className="space-y-1">
              <Label htmlFor={`tope-${s.id}`}>Hasta (%)</Label>
              <Input
                ref={topeRef}
                id={`tope-${s.id}`}
                inputMode="decimal"
                value={tope}
                onChange={(e) => { setTope(e.target.value); if (topeInvalido) setTopeInvalido(false) }}
                placeholder={String(s.tasa_base + 1)}
                aria-describedby={`tope-${s.id}-ayuda`}
                aria-invalid={topeInvalido || undefined}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor={`motivo-${s.id}`}>Motivo (opcional)</Label>
              <Input id={`motivo-${s.id}`} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Mercado a ese nivel, no más" />
            </div>
          </div>
          <p id={`tope-${s.id}-ayuda`} className={cn('text-[11px]', topeInvalido ? 'font-semibold text-destructive' : 'text-muted-foreground-strong')}>
            {topeInvalido
              ? `Escribe un tope mayor que la base (${tasaTxt(s.tasa_base)}) y no mayor que lo pedido (${tasaTxt(s.tasa_solicitada)}).`
              : `Entre la base (${tasaTxt(s.tasa_base)}) y lo pedido (${tasaTxt(s.tasa_solicitada)}). El analista podrá cerrar con cualquier tasa hasta ese tope.`}
          </p>
          <div className="flex flex-wrap justify-end gap-2">
            <Button type="button" size="sm" variant="outline" className="min-h-10" onClick={cerrarTope} disabled={ocupada}>Cancelar</Button>
            <Button type="button" size="sm" className="min-h-10" disabled={ocupada} onClick={aprobarHasta} aria-describedby={idCliente}>
              Aprobar hasta {topeValido ? tasaTxt(topeNum) : '…'}
            </Button>
          </div>
        </div>
      ) : (
        <div className="mt-3 flex flex-wrap justify-end gap-2 border-t border-border/60 pt-2.5">
          <Button type="button" size="sm" variant="outline" className="min-h-10" disabled={ocupada} onClick={() => void onDecidir('rechazar', null, null)} aria-describedby={idCliente}>
            <XCircle className="size-4" aria-hidden /> Rechazar
          </Button>
          <Button ref={abrirRef} type="button" size="sm" variant="outline" className="min-h-10" disabled={ocupada} onClick={() => setModoTope(true)} aria-describedby={idCliente}>
            Aprobar hasta…
          </Button>
          <Button type="button" size="sm" className="min-h-10" disabled={ocupada} onClick={() => void onDecidir('aprobar', null, null)} aria-describedby={idCliente}>
            <CheckCircle2 className="size-4" aria-hidden /> Aprobar {tasaTxt(s.tasa_solicitada)}
          </Button>
        </div>
      )}
    </li>
  )
}

export function SolicitudesTasaGerenciaPanel(): JSX.Element {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const sesionReal = !!yo && !esDemo
  const consulta = useSolicitudesTasa(['pendiente'], sesionReal, sesionReal ? REFRESCO_MS : false)
  const decidir = useResolverSolicitudTasa()
  const [ocupadaId, setOcupadaId] = useState<string | null>(null)
  // Tras decidir, la tarjeta desaparece con el botón enfocado dentro: el foco se posa en el cuerpo de la bandeja
  // (tabIndex -1, como el resumen de errores del formulario de contrato) para que Tab siga desde aquí.
  const cuerpoRef = useRef<HTMLDivElement>(null)

  // Solo las que este actor PUEDE resolver (el servidor ya excluye las propias: D3) y siguen vigentes.
  const pendientes = useMemo(() => (consulta.data ?? []).filter((s) => s.puede_resolver), [consulta.data])
  const propias = useMemo(() => (consulta.data ?? []).filter((s) => s.es_mia && s.vigente).length, [consulta.data])

  const onDecidir = async (s: SolicitudTasa, decision: 'aprobar' | 'rechazar' | 'aprobar_hasta', tope: number | null, motivo: string | null) => {
    setOcupadaId(s.id)
    try {
      const r = await decidir.mutateAsync({ solicitudId: s.id, decision, tasaMaxima: tope, motivo })
      toast.success(
        r.estado === 'aprobada' ? `Aprobada: ${s.cliente_nombre} al ${tasaTxt(r.tasa_maxima_autorizada ?? s.tasa_solicitada)}.`
          : r.estado === 'aprobada_con_tope' ? `Aprobada hasta ${tasaTxt(r.tasa_maxima_autorizada ?? 0)}: ${s.solicitante_nombre} decide si cierra.`
            : `Rechazada: ${s.cliente_nombre} sigue en la base (${tasaTxt(s.tasa_base)}).`,
      )
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo registrar la decisión.')
    } finally {
      setOcupadaId(null)
      cuerpoRef.current?.focus()
    }
  }

  const cargando = sesionReal && consulta.isPending && consulta.data === undefined
  const error = sesionReal && consulta.isError
  return (
    <Card className="min-w-0" data-testid="solicitudes-tasa-gerencia">
      <SectionHead
        icon={Inbox}
        title="Solicitudes de tasa"
        right={pendientes.length > 0 ? (
          <span className="rounded-full bg-primary px-2 py-0.5 text-xs font-bold tabular-nums text-primary-foreground">
            {numero(pendientes.length)} <span className="sr-only">pendientes</span>
          </span>
        ) : undefined}
      />
      <CardContent className="min-w-0 pt-1">
        <div ref={cuerpoRef} tabIndex={-1} className="outline-none">
          <p role="status" className="sr-only">
            {cargando && 'Cargando solicitudes de tasa…'}
            {error && 'No se pudieron cargar las solicitudes de tasa.'}
            {!cargando && !error && (esDemo ? 'En demo no hay solicitudes de tasa.' : pendientes.length === 0 ? 'Sin solicitudes de tasa por resolver.' : `${numero(pendientes.length)} ${pendientes.length === 1 ? 'solicitud pendiente' : 'solicitudes pendientes'} de decisión.`)}
          </p>
          {cargando && <Skeleton className="h-[140px] w-full" aria-busy />}
          {error && (
            <div className="flex h-[140px] flex-col items-center justify-center gap-3 text-center">
              <p className="text-xs text-muted-foreground">No se pudieron cargar las solicitudes. Revisa tu conexión y vuelve a intentarlo.</p>
              <Button type="button" size="sm" variant="outline" onClick={() => void consulta.refetch()}>
                <RotateCcw className="size-4" aria-hidden /> Reintentar
              </Button>
            </div>
          )}
          {!cargando && !error && pendientes.length === 0 && (
            <PanelVacio
              icono={Inbox}
              titulo={esDemo ? 'La bandeja solo existe en sesión real' : 'Nada por decidir'}
              detalle={esDemo
                ? 'En demo no hay política de rentabilidad que aplicar.'
                : 'Cuando un analista pida una tasa superior a la base, aparece aquí para aprobarla, rechazarla o ponerle tope.'}
            />
          )}
          {!cargando && !error && pendientes.length > 0 && (
            <>
              {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
              <ol role="list" className="flex flex-col gap-2" aria-label="Solicitudes de tasa pendientes">
                {pendientes.map((s) => (
                  <TarjetaSolicitud key={s.id} s={s} ocupada={ocupadaId === s.id || decidir.isPending} onDecidir={(d, t, m) => onDecidir(s, d, t, m)} />
                ))}
              </ol>
              <p className="mt-3 text-[11px] text-muted-foreground">
                Aprobar autoriza la tasa pedida; «Aprobar hasta» fija un tope y el analista decide si cierra. Nunca por debajo de la base. Una autorización sirve para un solo contrato y vence a los días que marca la política.
              </p>
            </>
          )}
          {propias > 0 && (
            <p className="mt-2 text-[11px] text-muted-foreground">Tienes {numero(propias)} {propias === 1 ? 'solicitud propia' : 'solicitudes propias'} en curso: las resuelve otra persona de Gerencia.</p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
