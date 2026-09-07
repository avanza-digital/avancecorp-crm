import { Fragment, useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, RefreshCw } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { GuardadosSlaPendientes } from './guardados-sla-pendientes'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, ETAPAS } from '@/lib/tipos'
import { slaOperacionKeys, useColaSlaPagina, useEstadosSlaV2, useModoSla } from '@/data/sla-operacion-queries'
import { ACCIONES_SLA, MOTIVOS_REVISION_SLA, SENALES_SLA, fechaSla, type CursorSla, type EstadoSlaV2, type FiltrosSla, type SenalSla } from '@/lib/sla-operacion'

export function SlaOperacionBoundary({ children, legado }: { children: ReactNode; legado?: ReactNode }) {
  const modo = useModoSla()
  const { yo } = useAuth()
  if (modo.legado) return legado ?? null
  if (modo.error) return <FalloSla onReintentar={() => void modo.refetch()} />
  if (!modo.activo) return <p role="status" className="rounded-xl border p-4 text-sm">Consultando el seguimiento comercial…</p>
  return <Fragment key={`${yo?.id}|${yo?.rol}|${modo.data?.control_revision}`}>{children}</Fragment>
}
function FalloSla({ onReintentar }: { onReintentar: () => void }) {
  return <div role="alert" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 p-4">
    <p className="text-sm">No se pudo cargar el seguimiento. Los pendientes todavía no están confirmados.</p>
    <Button variant="outline" size="sm" onClick={onReintentar}><RefreshCw aria-hidden /> Reintentar</Button>
  </div>
}
export function ColaSlaPanel() {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const [filtros, setFiltros] = useState<FiltrosSla>({ senal: 'todas', etapa: null, analista_id: null })
  const [limite, setLimite] = useState(10)
  const [abriendo, setAbriendo] = useState<string | null>(null)
  const [errorApertura, setErrorApertura] = useState(false)
  const [cursores, setCursores] = useState<(CursorSla | null)[]>([null])
  const cursor = cursores[cursores.length - 1] ?? null
  const consulta = useColaSlaPagina(filtros, cursor, limite, true)
  const pagina = consulta.error ? undefined : consulta.data
  const encabezado = useRef<HTMLHeadingElement>(null)
  const queryClient = useQueryClient()
  const prefijo = JSON.stringify(slaOperacionKeys.raiz()).slice(0, -1)
  // Cada gestión confirmada invalida esta raíz: el orden anterior ya no sirve.
  useEffect(() => queryClient.getQueryCache().subscribe((evento) => {
    if (evento.type === 'updated' && evento.action.type === 'invalidate'
      && JSON.stringify(evento.query.queryKey).startsWith(prefijo)) setCursores([null])
  }), [prefijo, queryClient])
  const esSupervisor = yo?.rol === 'supervisor' || yo?.rol === 'gerencia' || yo?.rol === 'directorio'
  const id = useId()
  function filtrar(cambio: Partial<FiltrosSla>) { setFiltros((actual) => ({ ...actual, ...cambio })); setCursores([null]) }
  function navegar(siguiente: boolean) {
    if (consulta.isFetching) return
    if (siguiente && pagina?.cursor_siguiente) setCursores((actual) => [...actual, pagina.cursor_siguiente])
    else if (!siguiente) setCursores((actual) => actual.length > 1 ? actual.slice(0, -1) : actual)
    encabezado.current?.focus()
  }
  const reiniciar = () => { setCursores([null]); if (cursor === null) void consulta.refetch() }
  async function abrirFicha(id: string) {
    if (abriendo) return
    setAbriendo(id)
    setErrorApertura(false)
    try {
      if (await abrirLead(id) === false) setErrorApertura(true)
    } catch {
      setErrorApertura(true)
    } finally {
      setAbriendo(null)
    }
  }
  return <Card><CardContent className="space-y-4 p-4 sm:p-5">
    <GuardadosSlaPendientes />
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h2 ref={encabezado} tabIndex={-1} className="text-base font-bold outline-none">Seguimiento comercial</h2>
        <p className="mt-1 text-xs text-muted-foreground">{esSupervisor ? 'Prioriza las gestiones y revisa los casos que necesitan una decisión.' : 'Tus próximas acciones, ordenadas por prioridad.'}</p></div>
      <Button variant="outline" size="sm" disabled={consulta.isFetching} onClick={reiniciar}><RefreshCw aria-hidden /> Actualizar</Button>
    </div>
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <label htmlFor={`${id}-senal`} className="space-y-1 text-xs font-semibold">Mostrar
        <Select id={`${id}-senal`} value={filtros.senal} onChange={(e) => filtrar({ senal: e.target.value as SenalSla })}>
          {SENALES_SLA.filter(([key]) => esSupervisor || key !== 'por_repartir').map(([key, label]) => <option key={key} value={key}>{label}{key !== 'todas' && pagina ? ` (${pagina.totales[key]})` : ''}</option>)}
        </Select>
      </label>
      <label htmlFor={`${id}-etapa`} className="space-y-1 text-xs font-semibold">Etapa
        <Select id={`${id}-etapa`} value={filtros.etapa ?? ''} onChange={(e) => filtrar({ etapa: e.target.value || null })}>
          <option value="">Todas las etapas</option>{ETAPAS.map((etapa) => <option key={etapa.k} value={etapa.k}>{etapa.label}</option>)}
        </Select>
      </label>
      {esSupervisor && <label htmlFor={`${id}-analista`} className="space-y-1 text-xs font-semibold">Analista
        <Select id={`${id}-analista`} value={filtros.analista_id ?? ''} onChange={(e) => filtrar({ analista_id: e.target.value || null })}>
          <option value="">Todos los analistas</option>{equipo.filter((miembro) => miembro.activo).map((miembro) => <option key={miembro.perfil_id} value={miembro.perfil_id}>{miembro.nombre_completo}</option>)}
        </Select>
      </label>}
      <label htmlFor={`${id}-limite`} className="space-y-1 text-xs font-semibold">Por página
        <Select id={`${id}-limite`} value={limite} onChange={(e) => { setLimite(Number(e.target.value)); setCursores([null]) }}>
          {[10, 25, 50].map((n) => <option key={n} value={n}>{n} oportunidades</option>)}
        </Select>
      </label>
    </div>
    {abriendo && <p role="status" className="text-xs text-muted-foreground">Abriendo ficha…</p>}
    {errorApertura && <p role="alert" className="text-sm text-destructive">No se pudo abrir la ficha. Actualiza la lista o vuelve a intentarlo.</p>}
    {consulta.error ? <div className="space-y-2"><FalloSla onReintentar={reiniciar} />{cursores.length > 1 && <Button variant="outline" size="sm" onClick={() => setCursores([null])}>Volver a la primera página</Button>}</div>
      : !pagina ? <p role="status" className="py-8 text-sm">Cargando oportunidades…</p>
      : pagina.modo !== 'activo' ? <p role="status">Las reglas operativas están desactivadas. Actualiza la pantalla para ver el modo vigente.</p>
      : <>
        <p role="status" aria-live="polite" className="text-xs text-muted-foreground">{pagina.rango.desde}–{pagina.rango.hasta} de {pagina.total_items} oportunidades · Página {cursores.length}{consulta.isFetching ? ' · Actualizando…' : ''}</p>
        {pagina.items.length === 0 ? <p className="rounded-lg bg-muted/40 p-6 text-sm">No hay oportunidades con estos filtros. Puedes elegir otra señal o etapa.</p>
          : <ul className="divide-y divide-border" aria-label="Oportunidades de esta página" aria-busy={consulta.isFetching}>
            {pagina.items.map((item) => <li key={item.lead_id}>
              <button type="button" disabled={abriendo !== null} onClick={() => void abrirFicha(item.lead_id)} className="flex w-full cursor-pointer items-start justify-between gap-3 rounded-lg px-2 py-3 text-left hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-wait disabled:opacity-60">
                <div className="min-w-0 space-y-1">
                  <p className="text-sm font-semibold">{item.lead.nombre_completo}</p>
                  <p className="text-xs text-muted-foreground">{ETAPA_INFO[item.lead.etapa as keyof typeof ETAPA_INFO]?.label ?? item.lead.etapa}{esSupervisor ? ` · ${item.lead.analista_nombre ?? 'Sin analista'}` : ''}</p>
                  <div className="flex flex-wrap gap-1.5">
                    <Badge color={item.severidad === 'critica' ? '#dc2626' : item.severidad === 'media' ? '#b45309' : '#2563eb'}>{ACCIONES_SLA[item.bucket] ?? 'Revisar oportunidad'}</Badge>
                    {item.senales.revisiones && item.bucket !== 'revision_comercial' && <Badge color="#b45309">Revisión comercial</Badge>}
                    {item.estado.compromiso.cobertura_activa && <Badge color="#2563eb">Cubierto por compromiso</Badge>}
                  </div>
                  {item.senales.revisiones && <p className="text-xs text-muted-foreground">{item.estado.etapa.motivos_revision.map((motivo) => MOTIVOS_REVISION_SLA[motivo] ?? 'Revisión requerida').join(' · ')}</p>}
                  <p className="text-xs text-muted-foreground sm:hidden">{fechaSla(item.referencia_en)}</p>
                </div>
                <span className="hidden shrink-0 items-center gap-1 text-right text-xs text-muted-foreground sm:flex">{fechaSla(item.referencia_en)}<ChevronRight className="size-4" aria-hidden /></span>
              </button>
            </li>)}
          </ul>}
        <nav aria-label="Paginación del seguimiento comercial" className="flex flex-wrap items-center justify-between gap-3 border-t pt-3">
          <Button variant="outline" size="sm" disabled={cursores.length === 1 || consulta.isFetching} onClick={() => navegar(false)}><ChevronLeft aria-hidden /> Anterior</Button>
          <span className="text-xs tabular-nums">Página {cursores.length}</span>
          <Button variant="outline" size="sm" disabled={!pagina.hay_mas || consulta.isFetching} onClick={() => navegar(true)}>Siguiente <ChevronRight aria-hidden /></Button>
        </nav>
        <p className="text-[11px] text-muted-foreground">Las señales pueden coincidir en una oportunidad. Totales de todo el ámbito filtrado, calculados {fechaSla(pagina.calculado_en)} (Lima).</p>
      </>}
  </CardContent></Card>
}
export function EstadoSlaFicha({ leadId }: { leadId: string }) {
  const { yo } = useAuth()
  const consulta = useEstadosSlaV2([leadId])
  if (yo?.demo) return null
  if (consulta.error) return <FalloSla onReintentar={() => void consulta.refetch()} />
  if (!consulta.data) return <p role="status" className="text-xs">Consultando plazos de seguimiento…</p>
  if (consulta.data.modo !== 'activo') return null
  const estado = consulta.data.filas.find((fila) => fila.lead_id === leadId)
  if (!estado) return <p role="alert" className="text-xs">El estado de seguimiento no está disponible para esta oportunidad.</p>
  if (estado.evaluacion === 'no_aplica') return null
  return <div className="space-y-3"><GuardadosSlaPendientes /><DetalleSla estado={estado} /></div>
}
export function DetalleSla({ estado }: { estado: EstadoSlaV2 }) {
  return <section aria-label="Plazos de seguimiento" className="space-y-3 rounded-xl border p-3">
    <h3 className="text-sm font-bold">Plazos de seguimiento</h3>
    {estado.evaluacion === 'parcial' && <p role="status" className="text-xs text-amber-800">Faltan datos para confirmar todos los plazos. Solicita revisión al supervisor.</p>}
    <dl className="grid gap-3 text-xs sm:grid-cols-2">
      <div><dt className="text-muted-foreground">Seguimiento</dt><dd className="mt-1 font-semibold">{estado.compromiso.cobertura_activa ? 'Cubierto por compromiso' : estado.seguimiento.accion_pendiente ? 'Pendiente' : estado.seguimiento.accion_pendiente === false ? 'Dentro del plazo' : 'Sin confirmar'}</dd><dd>{fechaSla(estado.seguimiento.limite_en)}</dd></div>
      <div><dt className="text-muted-foreground">Plazo operativo de etapa</dt><dd className="mt-1 font-semibold">{fechaSla(estado.etapa.limite_operativo_en)}</dd><dd>Tope: {fechaSla(estado.etapa.techo_en)}</dd></div>
    </dl>
    {estado.compromiso.tarea && <p className="text-xs">Compromiso: {fechaSla(estado.compromiso.tarea.vence_en)}.{estado.compromiso.cobertura_activa ? ` Cubre hasta ${fechaSla(estado.compromiso.hasta_en)}.` : ' No cubre el seguimiento actualmente.'} La tarea vence a su hora en Agenda.</p>}
    {(estado.etapa.prorrogas_usadas ?? 0) > 0 && <p className="text-xs">{estado.etapa.prorrogas_usadas} prórroga(s) confirmada(s) · Plazo prorrogado: {fechaSla(estado.etapa.limite_prorrogado_en)} · {estado.etapa.prorrogas_restantes ?? 0} disponibles.</p>}
    {estado.etapa.revision_requerida && <div className="rounded-lg bg-amber-50 p-2 text-xs text-amber-900"><p className="font-bold">Revisión comercial pendiente</p><p>{estado.etapa.motivos_revision.map((motivo) => MOTIVOS_REVISION_SLA[motivo] ?? 'Revisión requerida').join(' · ')}. Supervisor o Gerencia decide el siguiente paso.</p></div>}
  </section>
}
