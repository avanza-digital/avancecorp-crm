import { useCallback, useEffect, useMemo, useRef, useState, type JSX } from 'react'
import { ArrowRight, ChevronDown, History, RefreshCw, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import {
  listarHistorialDecisionesTasaGerencia,
  type DecisionHistorialTasa,
  type FilaHistorialDecisionTasa,
  type FiltrosHistorialDecisionesTasa,
  type PaginaHistorialDecisionesTasa,
} from '@/data/crm-api'
import { cn } from '@/lib/utils'
import { fechaHora, fmtFecha, money, numero } from '@/lib/format'
import { etiquetaReglaTasa, tasaTxt } from '@/lib/rentabilidad'

type Periodo = FiltrosHistorialDecisionesTasa['periodoDias']
type FiltroDecision = FiltrosHistorialDecisionesTasa['decision']
interface EstadoHistorial { paginas: PaginaHistorialDecisionesTasa[]; paginaActual: number; cargando: boolean; cargandoSiguiente: boolean; error: string | null }

const CATEGORIA_TXT: Record<string, string> = { nuevo: 'Primera inversión', renovacion: 'Renovación', upgrade: 'Aumento de capital' }
const MODALIDAD_TXT: Record<string, string> = { mensual: 'Mensual', trimestral: 'Trimestral', semestral: 'Semestral', anual: 'Anual' }
const ESTADO_TXT: Record<string, string> = {
  aprobada: 'Autorización vigente', aprobada_con_tope: 'Espera respuesta del analista', aceptada_por_analista: 'Aceptada por el analista',
  declinada_por_analista: 'Declinada por el analista', consumida: 'Consumida en contrato', rechazada: 'Cerrada', vencida: 'Vencida sin usar',
}

function etiquetaDecision(decision: DecisionHistorialTasa): string {
  return decision === 'aprobada' ? 'Aprobada' : decision === 'aprobada_con_tope' ? 'Con tope' : 'Rechazada'
}
function colorDecision(decision: DecisionHistorialTasa): string {
  return decision === 'aprobada' ? 'bg-emerald-50 text-emerald-700 ring-emerald-200' : decision === 'aprobada_con_tope' ? 'bg-amber-50 text-amber-800 ring-amber-200' : 'bg-rose-50 text-rose-700 ring-rose-200'
}
function tasaFinal(fila: FilaHistorialDecisionTasa): number {
  return fila.decision === 'rechazada' ? fila.tasa_base : (fila.tasa_maxima_autorizada ?? fila.tasa_solicitada)
}

function TarjetaDecision({ fila, abierta, onAlternar }: { fila: FilaHistorialDecisionTasa; abierta: boolean; onAlternar: () => void }): JSX.Element {
  const final = tasaFinal(fila)
  const puntos = final - fila.tasa_base
  const idDetalle = `decision-tasa-${fila.id}`
  return (
    <article className="border-b border-border last:border-b-0">
      <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-3 px-4 py-3.5 lg:grid-cols-[112px_minmax(170px,1.2fr)_minmax(125px,.8fr)_minmax(225px,1fr)_145px_36px] lg:items-center lg:px-5">
        <div className="hidden lg:block"><p className="text-xs font-bold tabular-nums text-foreground">{fmtFecha(fila.resuelta_en)}</p><p className="mt-0.5 text-[10px] tabular-nums text-muted-foreground">{fechaHora(fila.resuelta_en).split(', ').at(-1)}</p></div>
        <div className="min-w-0"><p className="truncate text-xs font-extrabold text-foreground" title={fila.cliente_nombre}>{fila.cliente_nombre}</p><p className="mt-0.5 truncate text-[10px] text-muted-foreground">Solicita {fila.solicitante_nombre}</p><p className="mt-1 text-[10px] tabular-nums text-muted-foreground lg:hidden">{fechaHora(fila.resuelta_en)}</p></div>
        <div className="hidden lg:block"><p className="text-xs font-bold tabular-nums text-foreground">{money(fila.capital, fila.moneda)}</p><p className="mt-0.5 text-[10px] text-muted-foreground">{CATEGORIA_TXT[fila.categoria] ?? fila.categoria}</p></div>
        <div className="col-start-1 flex min-w-0 items-center gap-2 lg:col-auto">
          <div><span className="block text-[9px] text-muted-foreground">Base</span><strong className="text-sm tabular-nums">{tasaTxt(fila.tasa_base)}</strong></div><ArrowRight className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />
          <div><span className="block text-[9px] text-muted-foreground">Solicita</span><strong className="text-sm tabular-nums">{tasaTxt(fila.tasa_solicitada)}</strong></div><ArrowRight className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />
          <div><span className="block text-[9px] text-muted-foreground">{fila.decision === 'rechazada' ? 'Queda' : fila.decision === 'aprobada_con_tope' ? 'Tope' : 'Autoriza'}</span><strong className={cn('text-sm tabular-nums', fila.decision === 'rechazada' ? 'text-rose-700' : 'text-emerald-700')}>{tasaTxt(final)}</strong></div>
        </div>
        <div className="col-start-2 row-start-1 text-right lg:col-auto lg:row-auto lg:text-left"><span className={cn('inline-flex items-center gap-1.5 rounded-full px-2 py-1 text-[10px] font-extrabold ring-1 ring-inset', colorDecision(fila.decision))}><span className="size-1.5 rounded-full bg-current" aria-hidden />{etiquetaDecision(fila.decision)}</span><p className="mt-1 text-[9px] text-muted-foreground">{ESTADO_TXT[fila.estado_actual] ?? fila.estado_actual}</p></div>
        <Button type="button" variant="outline" size="sm" className="col-start-2 row-start-2 size-8 justify-self-end p-0 lg:col-auto lg:row-auto" aria-expanded={abierta} aria-controls={idDetalle} aria-label={`${abierta ? 'Ocultar' : 'Ver'} detalle de ${fila.cliente_nombre}`} onClick={onAlternar}><ChevronDown className={cn('size-4 transition-transform', abierta && 'rotate-180')} aria-hidden /></Button>
      </div>
      {abierta && (
        <div id={idDetalle} className="bg-muted/20 px-4 pb-4 lg:px-5">
          <div className="grid overflow-hidden rounded-xl border border-border bg-background md:grid-cols-3">
            <section className="border-b border-border p-4 md:border-b-0 md:border-r"><h4 className="text-xs font-bold">Operación</h4><dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 text-[11px]"><dt className="text-muted-foreground">Categoría</dt><dd className="text-right font-semibold">{CATEGORIA_TXT[fila.categoria] ?? fila.categoria}</dd><dt className="text-muted-foreground">Contrato origen</dt><dd className="text-right font-semibold">{fila.contrato_origen_numero ?? 'No aplica'}</dd><dt className="text-muted-foreground">Capital</dt><dd className="text-right font-semibold tabular-nums">{money(fila.capital, fila.moneda)}</dd><dt className="text-muted-foreground">Plazo</dt><dd className="text-right font-semibold">{fmtFecha(fila.fecha_inicio)} al {fmtFecha(fila.fecha_vencimiento)}</dd><dt className="text-muted-foreground">Modalidad</dt><dd className="text-right font-semibold">{MODALIDAD_TXT[fila.modalidad] ?? fila.modalidad} · interés {fila.tipo_interes}</dd></dl></section>
            <section className="border-b border-border p-4 md:border-b-0 md:border-r"><h4 className="text-xs font-bold">Decisión de Gerencia</h4><dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 text-[11px]"><dt className="text-muted-foreground">Política</dt><dd className="text-right font-semibold">{fila.politica_version ? `Versión ${fila.politica_version}` : 'Sin versión'}</dd><dt className="text-muted-foreground">Regla</dt><dd className="text-right font-semibold">{etiquetaReglaTasa(fila.regla_base)}</dd><dt className="text-muted-foreground">Tasa base</dt><dd className="text-right font-semibold tabular-nums">{tasaTxt(fila.tasa_base)}</dd><dt className="text-muted-foreground">Solicitada</dt><dd className="text-right font-semibold tabular-nums">{tasaTxt(fila.tasa_solicitada)}</dd><dt className="text-muted-foreground">Resultado</dt><dd className="text-right font-semibold tabular-nums">{tasaTxt(final)} ({puntos > 0 ? '+' : ''}{puntos.toLocaleString('es-PE', { maximumFractionDigits: 2 })} pts)</dd><dt className="text-muted-foreground">Decidió</dt><dd className="text-right font-semibold">{fila.resolutor_nombre} · {fechaHora(fila.resuelta_en)}</dd></dl></section>
            <section className="p-4"><h4 className="text-xs font-bold">Motivos y resultado</h4><div className="mt-3 space-y-2.5 text-[11px]"><blockquote className="border-l-2 border-primary/30 pl-2.5 text-muted-foreground"><strong className="block text-foreground">Motivo comercial</strong>{fila.motivo}</blockquote>{fila.motivo_resolucion && <blockquote className="border-l-2 border-primary/30 pl-2.5 text-muted-foreground"><strong className="block text-foreground">Motivo de Gerencia</strong>{fila.motivo_resolucion}</blockquote>}<p className="border-l-2 border-primary/30 pl-2.5 text-muted-foreground"><strong className="block text-foreground">Resultado posterior</strong>{ESTADO_TXT[fila.estado_actual] ?? fila.estado_actual}{fila.contrato_numero ? ` · contrato ${fila.contrato_numero}` : ''}{fila.respondida_por_analista_en ? ` · respuesta ${fechaHora(fila.respondida_por_analista_en)}` : ''}</p></div></section>
          </div>
        </div>
      )}
    </article>
  )
}

export function HistorialDecisionesTasaGerencia(): JSX.Element {
  const [periodoDias, setPeriodoDias] = useState<Periodo>(30)
  const [decision, setDecision] = useState<FiltroDecision>('todas')
  const [busqueda, setBusqueda] = useState('')
  const [busquedaAplicada, setBusquedaAplicada] = useState('')
  const [abiertaId, setAbiertaId] = useState<string | null>(null)
  const [estado, setEstado] = useState<EstadoHistorial>({ paginas: [], paginaActual: 0, cargando: true, cargandoSiguiente: false, error: null })
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => { const temporizador = window.setTimeout(() => setBusquedaAplicada(busqueda.trim()), 350); return () => window.clearTimeout(temporizador) }, [busqueda])
  const filtros = useMemo<FiltrosHistorialDecisionesTasa>(() => ({ periodoDias, decision, busqueda: busquedaAplicada || null }), [busquedaAplicada, decision, periodoDias])
  const recargar = useCallback(async () => {
    abortRef.current?.abort(); const control = new AbortController(); abortRef.current = control; setAbiertaId(null); setEstado((anterior) => ({ ...anterior, cargando: true, error: null }))
    try { const pagina = await listarHistorialDecisionesTasaGerencia(filtros, null, control.signal); if (!control.signal.aborted) setEstado({ paginas: [pagina], paginaActual: 0, cargando: false, cargandoSiguiente: false, error: null }) }
    catch (error) { if (!control.signal.aborted) setEstado((anterior) => ({ ...anterior, cargando: false, cargandoSiguiente: false, error: error instanceof Error ? error.message : 'No se pudo cargar el historial de decisiones.' })) }
  }, [filtros])
  useEffect(() => { void recargar(); return () => abortRef.current?.abort() }, [recargar])

  const irSiguiente = useCallback(async () => {
    if (estado.cargandoSiguiente) return
    if (estado.paginaActual < estado.paginas.length - 1) { setAbiertaId(null); setEstado((anterior) => ({ ...anterior, paginaActual: anterior.paginaActual + 1, error: null })); return }
    const actual = estado.paginas[estado.paginaActual]; if (!actual?.siguienteCursor) return
    abortRef.current?.abort(); const control = new AbortController(); abortRef.current = control; setEstado((anterior) => ({ ...anterior, cargandoSiguiente: true, error: null }))
    try { const siguiente = await listarHistorialDecisionesTasaGerencia(filtros, actual.siguienteCursor, control.signal); if (!control.signal.aborted) { setAbiertaId(null); setEstado((anterior) => ({ ...anterior, paginas: [...anterior.paginas, siguiente], paginaActual: anterior.paginas.length, cargandoSiguiente: false })) } }
    catch (error) { if (!control.signal.aborted) setEstado((anterior) => ({ ...anterior, cargandoSiguiente: false, error: error instanceof Error ? error.message : 'No se pudo cargar la página siguiente.' })) }
  }, [estado, filtros])

  const pagina = estado.paginas[estado.paginaActual]; const filas = pagina?.items ?? []; const total = pagina?.total ?? 0
  const puedeAnterior = estado.paginaActual > 0; const puedeSiguiente = estado.paginaActual < estado.paginas.length - 1 || Boolean(pagina?.siguienteCursor)
  return (
    <div>
      <div className="border-b border-border bg-muted/15 px-4 py-3 lg:px-5">
        <div className="grid gap-2 sm:grid-cols-[minmax(220px,1fr)_160px_170px_auto]">
          <label className="relative"><Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" aria-hidden /><Input value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder="Buscar cliente o analista…" aria-label="Buscar cliente o analista en decisiones de tasa" className="h-9 pl-8 text-xs" /></label>
          <select value={periodoDias} onChange={(e) => setPeriodoDias(Number(e.target.value) as Periodo)} aria-label="Período del historial de decisiones" className="h-9 rounded-lg border border-input bg-background px-3 text-xs outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"><option value={7}>Últimos 7 días</option><option value={30}>Últimos 30 días</option><option value={90}>Últimos 90 días</option><option value={0}>Todo el historial</option></select>
          <select value={decision} onChange={(e) => setDecision(e.target.value as FiltroDecision)} aria-label="Tipo de decisión de tasa" className="h-9 rounded-lg border border-input bg-background px-3 text-xs outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"><option value="todas">Todas las decisiones</option><option value="aprobada">Aprobadas</option><option value="aprobada_con_tope">Con tope</option><option value="rechazada">Rechazadas</option></select>
          <Button type="button" size="sm" variant="outline" className="h-9" onClick={() => void recargar()} disabled={estado.cargando}><RefreshCw className={cn('size-3.5', estado.cargando && 'animate-spin')} aria-hidden /> Actualizar</Button>
        </div>
        <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-[11px] text-muted-foreground"><p>Mis decisiones de Gerencia. Las solicitudes pendientes se resuelven desde Hoy.</p><span className="font-semibold tabular-nums text-foreground">{numero(total)} {total === 1 ? 'decisión' : 'decisiones'}</span></div>
      </div>
      <div className="hidden grid-cols-[112px_minmax(170px,1.2fr)_minmax(125px,.8fr)_minmax(225px,1fr)_145px_36px] gap-3 border-b border-border bg-muted/15 px-5 py-2.5 text-[9px] font-extrabold tracking-wide text-muted-foreground lg:grid" aria-hidden><span>FECHA</span><span>CLIENTE Y SOLICITANTE</span><span>OPERACIÓN</span><span>RECORRIDO DE TASA</span><span>DECISIÓN</span><span /></div>
      {estado.cargando && estado.paginas.length === 0 ? <PanelCargando filas={5} /> : estado.error && estado.paginas.length === 0 ? <PanelError mensaje={estado.error} onReintentar={() => void recargar()} reintentando={estado.cargando} /> : filas.length === 0 ? <PanelVacio icono={History} titulo="No hay decisiones con estos filtros" detalle="Cambia el período, la decisión o la búsqueda para consultar otros resultados." /> : <div>{filas.map((fila) => <TarjetaDecision key={fila.id} fila={fila} abierta={abiertaId === fila.id} onAlternar={() => setAbiertaId((actual) => actual === fila.id ? null : fila.id)} />)}</div>}
      {estado.error && estado.paginas.length > 0 && <div className="border-t border-border px-5 py-3 text-sm text-destructive" role="status">{estado.error}</div>}
      {filas.length > 0 && (puedeAnterior || puedeSiguiente) && <nav className="flex flex-wrap items-center justify-between gap-3 border-t border-border bg-muted/10 px-4 py-3 lg:px-5" aria-label="Paginación del historial de decisiones de tasa"><span className="text-xs tabular-nums text-muted-foreground">Página {estado.paginaActual + 1} · mostrando {numero(filas.length)} de {numero(total)}</span><div className="flex gap-2"><Button type="button" size="sm" variant="outline" disabled={!puedeAnterior || estado.cargandoSiguiente} onClick={() => { setAbiertaId(null); setEstado((anterior) => ({ ...anterior, paginaActual: Math.max(0, anterior.paginaActual - 1), error: null })) }}>Anterior</Button><Button type="button" size="sm" variant="outline" disabled={!puedeSiguiente || estado.cargandoSiguiente} onClick={() => void irSiguiente()}>{estado.cargandoSiguiente ? 'Cargando…' : 'Siguiente'}</Button></div></nav>}
    </div>
  )
}
