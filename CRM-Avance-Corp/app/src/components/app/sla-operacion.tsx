import { Fragment, useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, RefreshCw, ArrowUpRight, ListFilter, X } from 'lucide-react'
import './sla-operacion.css'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
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
  const senales = SENALES_SLA.filter(([key]) => esSupervisor || key !== 'por_repartir')
  const hayFiltros = filtros.senal !== 'todas' || filtros.etapa !== null || filtros.analista_id !== null
  const limpiar = () => { setFiltros({ senal: 'todas', etapa: null, analista_id: null }); setCursores([null]); setErrorApertura(false) }
  return <section className="sla-bandeja" aria-label="Seguimiento comercial">
    <GuardadosSlaPendientes />
    <header className="sla-cabecera">
      <div>
        <h2 ref={encabezado} tabIndex={-1} className="sla-titulo">Seguimiento comercial</h2>
        <p>{yo?.rol === 'gerencia' ? 'Las oportunidades de todo el equipo que necesitan atención.' : esSupervisor ? 'Los pendientes de tu equipo y los casos que necesitan tu decisión.' : 'Tus oportunidades pendientes, ordenadas para la próxima gestión.'}</p>
      </div>
      <Button variant="outline" size="sm" disabled={consulta.isFetching} onClick={reiniciar}><RefreshCw aria-hidden className={consulta.isFetching ? 'motion-safe:animate-spin' : ''} /> Actualizar</Button>
    </header>

    <div className="sla-prioridades" role="group" aria-label="Prioridades de seguimiento">
      {senales.filter(([key]) => key !== 'todas').map(([key, label]) => <button key={key} type="button"
        aria-label={`${label} ${pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : 'sin confirmar'}`}
        aria-pressed={filtros.senal === key} onClick={() => filtrar({ senal: key })}>
        <span>{label}</span><strong>{pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : '—'}</strong>
      </button>)}
    </div>

    <div className="sla-herramientas">
      <div className="sla-todas"><button type="button" aria-pressed={filtros.senal === 'todas'} onClick={() => filtrar({ senal: 'todas' })}><ListFilter aria-hidden /> Todas las acciones</button></div>
      <label htmlFor={`${id}-senal`} className="sla-mostrar">Mostrar
        <Select id={`${id}-senal`} value={filtros.senal} onChange={(e) => filtrar({ senal: e.target.value as SenalSla })}>
          {senales.map(([key, label]) => <option key={key} value={key}>{label}{key !== 'todas' && pagina ? ` (${pagina.totales[key]})` : ''}</option>)}
        </Select>
      </label>
      <label htmlFor={`${id}-etapa`}>Etapa
        <Select id={`${id}-etapa`} value={filtros.etapa ?? ''} onChange={(e) => filtrar({ etapa: e.target.value || null })}>
          <option value="">Todas las etapas</option>{ETAPAS.map((etapa) => <option key={etapa.k} value={etapa.k}>{etapa.label}</option>)}
        </Select>
      </label>
      {esSupervisor && <label htmlFor={`${id}-analista`}>Analista
        <Select id={`${id}-analista`} value={filtros.analista_id ?? ''} onChange={(e) => filtrar({ analista_id: e.target.value || null })}>
          <option value="">Todos los analistas</option>{equipo.filter((miembro) => miembro.activo && miembro.rol_crm === 'vendedor').map((miembro) => <option key={miembro.perfil_id} value={miembro.perfil_id}>{miembro.nombre_completo}</option>)}
        </Select>
      </label>}
      {hayFiltros && <Button variant="ghost" size="sm" onClick={limpiar}><X aria-hidden /> Limpiar filtros</Button>}
    </div>

    {abriendo && <p role="status" className="sla-aviso">Abriendo ficha…</p>}
    {errorApertura && <p role="alert" className="sla-aviso text-destructive">No se pudo abrir la ficha. Actualiza la lista o vuelve a intentarlo.</p>}
    {consulta.error ? <div className="sla-estado"><FalloSla onReintentar={reiniciar} />{cursores.length > 1 && <Button variant="outline" size="sm" onClick={() => setCursores([null])}>Volver a la primera página</Button>}</div>
      : !pagina ? <p role="status" className="sla-estado">Cargando oportunidades…</p>
      : pagina.modo !== 'activo' ? <p role="status" className="sla-estado">Las reglas operativas están desactivadas. Actualiza la pantalla para ver el modo vigente.</p>
      : <>
        <div className="sla-resultados">
          <p role="status" aria-live="polite">{pagina.rango.desde}–{pagina.rango.hasta} de {pagina.total_items} oportunidades · Página {cursores.length}{consulta.isFetching ? ' · Actualizando…' : ''}</p>
          <label htmlFor={`${id}-limite`}>Por página
            <Select id={`${id}-limite`} value={limite} onChange={(e) => { setLimite(Number(e.target.value)); setCursores([null]) }}>
              {[10, 25, 50].map((n) => <option key={n} value={n}>{n} oportunidades</option>)}
            </Select>
          </label>
        </div>
        {pagina.items.length === 0 ? <div className="sla-vacio"><ListFilter aria-hidden /><p>No hay oportunidades con estos filtros.</p><span>Puedes elegir otra señal o etapa para seguir revisando.</span>{hayFiltros && <Button variant="outline" size="sm" onClick={limpiar}>Ver todas las acciones</Button>}</div>
          : <>
            <div className="sla-columnas" aria-hidden="true"><span>Oportunidad{esSupervisor ? ' y analista' : ''}</span><span>Acción pendiente</span><span>Fecha de referencia</span><span>Ficha</span></div>
            <ul className="sla-lista" aria-label="Oportunidades de esta página" aria-busy={consulta.isFetching || abriendo !== null}>
              {pagina.items.map((item) => <li key={item.lead_id}>
                <button type="button" disabled={abriendo !== null} onClick={() => void abrirFicha(item.lead_id)} className="sla-fila">
                  <span className="sla-oportunidad">
                    <strong>{item.lead.nombre_completo}</strong>
                    <span className="sla-meta"><span>{ETAPA_INFO[item.lead.etapa as keyof typeof ETAPA_INFO]?.label ?? item.lead.etapa}</span>{esSupervisor && <span>{item.lead.analista_nombre ?? 'Sin analista'}</span>}</span>
                  </span>
                  <span className="sla-accion">
                    <span className={`sla-etiqueta sla-etiqueta-${item.severidad}`}>{ACCIONES_SLA[item.bucket] ?? 'Revisar oportunidad'}</span>
                    {item.senales.revisiones && item.bucket !== 'revision_comercial' && <span className="sla-revision">Revisión comercial</span>}
                    {item.senales.revisiones && <span className="sla-motivo">{item.estado.etapa.motivos_revision.map((motivo) => MOTIVOS_REVISION_SLA[motivo] ?? 'Revisión requerida').join(' · ')}</span>}
                    {item.estado.compromiso.cobertura_activa && <span className="sla-cobertura">Seguimiento en espera por actividad programada</span>}
                  </span>
                  <span className="sla-fecha"><span>Referencia</span>{fechaSla(item.referencia_en)}</span>
                  <span className="sla-abrir"><span>Abrir ficha</span><ArrowUpRight aria-hidden /></span>
                </button>
              </li>)}
            </ul>
          </>}
        <nav aria-label="Paginación del seguimiento comercial" className="sla-paginacion">
          <Button variant="outline" size="sm" disabled={cursores.length === 1 || consulta.isFetching} onClick={() => navegar(false)}><ChevronLeft aria-hidden /> Anterior</Button>
          <span>Página {cursores.length}</span>
          <Button variant="outline" size="sm" disabled={!pagina.hay_mas || consulta.isFetching} onClick={() => navegar(true)}>Siguiente <ChevronRight aria-hidden /></Button>
        </nav>
        <footer className="sla-nota"><p>Una oportunidad puede tener varios pendientes. Los conteos corresponden a {esSupervisor ? 'la etapa y al analista elegidos' : 'la etapa elegida y a tu cartera'}.</p><p>Actualizado {fechaSla(pagina.calculado_en)} (Lima).</p></footer>
      </>}
  </section>
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
  const { compromiso, seguimiento, etapa } = estado
  const enEspera = compromiso.cobertura_activa === true
  const pendiente = seguimiento.accion_pendiente === true
  // Solo explicamos decisiones del núcleo; las fechas no se recalculan aquí.
  let explicacionActividad = 'Esta actividad no permite aplazar el seguimiento del cliente.'
  if (compromiso.cobertura_activa === null || compromiso.validez === 'datos_incompletos') {
    explicacionActividad = 'Faltan datos para confirmar si esta actividad permite esperar antes de volver a gestionar al cliente.'
  } else if (enEspera) {
    explicacionActividad = 'Durante esta espera, el seguimiento no se marca como pendiente por falta de gestión. Las revisiones de la etapa se atienden por separado.'
  } else if (compromiso.validez === 'reprogramaciones_agotadas') {
    explicacionActividad = 'Esta actividad ya se reprogramó tres veces o más y no permite seguir aplazando el seguimiento.'
  } else if (compromiso.validez === 'deshabilitado') {
    explicacionActividad = 'En esta etapa, programar una actividad no aplaza el seguimiento del cliente.'
  } else if (compromiso.validez === 'valido' && compromiso.hasta_en) {
    explicacionActividad = `El tiempo de espera por esta actividad terminó el ${fechaSla(compromiso.hasta_en, 'completa')}`
  }
  return <section aria-label="Seguimiento y plazos" className="space-y-3 rounded-xl border p-3">
    <div><h3 className="text-sm font-bold">Seguimiento y plazos</h3><p className="text-xs text-muted-foreground">Fechas y horas de Lima.</p></div>
    {estado.evaluacion === 'parcial' && <p role="status" className="text-xs text-amber-800">Faltan datos para confirmar algunos plazos. El supervisor debe revisar la información de la ficha.</p>}
    {etapa.revision_requerida && <div className="space-y-1 rounded-lg bg-amber-50 p-3 text-xs text-amber-900">
      <p className="font-bold">Este caso necesita una decisión</p>
      {etapa.motivos_revision.length > 0 && <ul className="list-disc space-y-1 pl-4">{etapa.motivos_revision.map((motivo) => <li key={motivo}>{MOTIVOS_REVISION_SLA[motivo] ?? 'Hace falta revisar la gestión de esta etapa'}</li>)}</ul>}
      <p>El supervisor o Gerencia debe revisar el caso y definir cómo continuar.</p>
    </div>}
    <div className="grid gap-4 text-xs sm:grid-cols-2">
      <div className="space-y-1">
        <h4 className="font-bold">Seguimiento de la oportunidad</h4>
        <p className="font-semibold">{enEspera ? 'En espera por una actividad programada' : pendiente ? 'Seguimiento vencido' : seguimiento.accion_pendiente === false ? 'Seguimiento dentro de plazo' : 'Seguimiento por confirmar'}</p>
        <dl><dt className="text-muted-foreground">{enEspera ? 'Plazo habitual para registrar otra gestión' : pendiente ? 'Debía registrar otra gestión antes de' : 'Fecha límite para la próxima gestión'}</dt>
          <dd>{fechaSla(seguimiento.limite_en, 'completa')}</dd></dl>
        {pendiente && !enEspera && <p>El responsable debe retomar el contacto y registrar la gestión en la ficha.</p>}
      </div>
      <div className="space-y-1">
        <h4 className="font-bold">Permanencia en esta etapa</h4>
        <dl className="space-y-2">
          <div><dt className="text-muted-foreground">Fecha límite actual</dt><dd className="font-semibold">{fechaSla(etapa.limite_operativo_en, 'completa')}</dd></div>
          <div><dt className="text-muted-foreground">Límite máximo permitido</dt><dd>{fechaSla(etapa.techo_en, 'completa')}</dd></div>
        </dl>
        <p>Rige la fecha límite actual. Cualquier ampliación debe respetar el máximo permitido.</p>
      </div>
    </div>
    {compromiso.tarea && <div className="space-y-1 border-t pt-3 text-xs">
      <h4 className="font-bold">Actividad pendiente en Agenda</h4>
      <dl><dt className="text-muted-foreground">Fecha programada</dt><dd className="font-semibold">{fechaSla(compromiso.tarea.vence_en, 'completa')}</dd></dl>
      {enEspera && <dl><dt className="text-muted-foreground">Espera del seguimiento por esta actividad hasta</dt><dd>{fechaSla(compromiso.hasta_en, 'completa')}</dd></dl>}
      <p>{explicacionActividad}</p>
      <p>La actividad conserva su fecha y hora de Agenda, aunque el seguimiento esté en espera.</p>
    </div>}
    {(etapa.prorrogas_usadas ?? 0) > 0 && <div className="space-y-1 border-t pt-3 text-xs">
      <p>Ampliaciones aplicadas: {etapa.prorrogas_usadas} · Disponibles: {etapa.prorrogas_restantes ?? 'Por confirmar'}</p>
      <dl><dt className="text-muted-foreground">Fecha con las ampliaciones aplicadas</dt><dd>{fechaSla(etapa.limite_prorrogado_en, 'completa')}</dd></dl>
    </div>}
  </section>
}
