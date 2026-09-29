import { Fragment, useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { GuardadosSlaPendientes } from './guardados-sla-pendientes'
import { useQueryClient } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, RefreshCw, ArrowUpRight, ListFilter, X } from 'lucide-react'
import './sla-operacion.css'
import { CrmApiError } from '@/data/crm-api'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, ETAPAS } from '@/lib/tipos'
import { slaOperacionKeys, useColaDiaPagina, useEstadosSlaV2, useModoSla } from '@/data/sla-operacion-queries'
import { ACCIONES_CLIENTE_SLA, ACCIONES_SLA, MOTIVOS_REVISION_SLA, SENALES_SLA, fechaSla, idFichaCliente, puedeRegistrarGestionSla, textoAvisoSla, type AvisoSla, type CursorSla, type EstadoSlaV2, type FiltrosSla, type ItemColaDiaCliente, type SenalSla } from '@/lib/sla-operacion'
import { hashDe } from '@/lib/router'

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
// «Seguimiento comercial» lee la cola v3 desde el 29/09/2026 (F3): los leads de
// siempre y, además, las tareas de CLIENTES del día (vencidas o de hoy) del
// ámbito del actor. Una fila de cliente abre su ficha de «Mi cartera» si tiene
// una; si es solo del portal, no ofrece nada que no exista.
export function ColaSlaPanel() {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  // La página solo vale con la MISMA revisión de reglas que el modo vigente: la
  // clave de la consulta no la lleva y, tras publicar reglas, la caché podría
  // servir una página calculada con las anteriores (Codex, 29/09/2026).
  const modoVigente = useModoSla()
  const { abrirLead } = usePanelesActions()
  const [filtros, setFiltros] = useState<FiltrosSla>({ senal: 'pendientes', etapa: null, analista_id: null })
  const [limite, setLimite] = useState(10)
  const [abriendo, setAbriendo] = useState<string | null>(null)
  const [errorApertura, setErrorApertura] = useState(false)
  const [cursores, setCursores] = useState<(CursorSla | null)[]>([null])
  const cursor = cursores[cursores.length - 1] ?? null
  const consulta = useColaDiaPagina(filtros, cursor, limite, true)
  const pagina = consulta.error || consulta.data === undefined || consulta.data.control_revision !== modoVigente.data?.control_revision
    ? undefined : consulta.data
  const encabezado = useRef<HTMLHeadingElement>(null)
  const queryClient = useQueryClient()
  const prefijo = JSON.stringify(slaOperacionKeys.raiz()).slice(0, -1)
  // Cada gestión confirmada invalida esta raíz: el orden anterior ya no sirve.
  useEffect(() => queryClient.getQueryCache().subscribe((evento) => {
    if (evento.type === 'updated' && evento.action.type === 'invalidate'
      && JSON.stringify(evento.query.queryKey).startsWith(prefijo)) setCursores([null])
  }), [prefijo, queryClient])
  // Una frontera temporal o un cambio de cartera invalida la posición anterior.
  useEffect(() => {
    if (cursor && consulta.error instanceof CrmApiError && consulta.error.code === '22023') setCursores([null])
  }, [cursor, consulta.error])
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
  const senales = SENALES_SLA.filter(([key]) => esSupervisor || (key !== 'por_repartir' && key !== 'revisiones'))
    .map(([key, label]) => [key, pagina?.modelo_avisos === 3 && key === 'primera_atencion' ? 'Primera gestión pendiente' : label] as const)
  const hayFiltros = filtros.senal !== 'pendientes' || filtros.etapa !== null || filtros.analista_id !== null
  const limpiar = () => { setFiltros({ senal: 'pendientes', etapa: null, analista_id: null }); setCursores([null]); setErrorApertura(false) }
  return <section className="sla-bandeja" aria-label="Seguimiento comercial">
    <header className="sla-cabecera">
      <div>
        <h2 ref={encabezado} tabIndex={-1} className="sla-titulo">Seguimiento comercial</h2>
        <p>{yo?.rol === 'gerencia' ? 'Las oportunidades de todo el equipo que necesitan atención.' : esSupervisor ? 'Los pendientes de tu equipo y los casos que necesitan tu decisión.' : 'Tus oportunidades pendientes, ordenadas para la próxima gestión.'}</p>
      </div>
      <Button variant="outline" size="sm" disabled={consulta.isFetching} onClick={reiniciar}><RefreshCw aria-hidden className={consulta.isFetching ? 'motion-safe:animate-spin' : ''} /> Actualizar</Button>
    </header>

    <div className="sla-prioridades" role="group" aria-label="Prioridades de seguimiento">
      {senales.filter(([key]) => key !== 'todas' && key !== 'pendientes').map(([key, label]) => <button key={key} type="button"
        aria-label={`${label} ${pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : 'sin confirmar'}`}
        aria-pressed={filtros.senal === key} onClick={() => filtrar({ senal: key })}>
        <span>{label}</span><strong>{pagina ? pagina.totales[key as Exclude<SenalSla, 'todas'>].toLocaleString('es-PE') : '—'}</strong>
      </button>)}
    </div>

    <div className="sla-herramientas">
      <div className="sla-todas"><button type="button" aria-pressed={filtros.senal === 'pendientes'} onClick={() => filtrar({ senal: 'pendientes' })}>Para atender ahora</button><button type="button" aria-pressed={filtros.senal === 'todas'} onClick={() => filtrar({ senal: 'todas' })}><ListFilter aria-hidden /> Todas las acciones</button></div>
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
          {/* La región viva dice solo lo que CAMBIA la lista; «Actualizando…» entra y
              sale en cada relectura y haría releer la frase entera dos veces por minuto. */}
          <p><span role="status" aria-live="polite">{pagina.rango.desde}–{pagina.rango.hasta} de {pagina.total_items} oportunidades · Página {cursores.length}{clientesEnPagina(pagina.items)}</span>{consulta.isFetching && <span aria-hidden="true"> · Actualizando…</span>}</p>
          <label htmlFor={`${id}-limite`}>Por página
            <Select id={`${id}-limite`} value={limite} onChange={(e) => { setLimite(Number(e.target.value)); setCursores([null]) }}>
              {[10, 25, 50].map((n) => <option key={n} value={n}>{n} oportunidades</option>)}
            </Select>
          </label>
        </div>
        {pagina.items.length === 0 ? <div className="sla-vacio"><ListFilter aria-hidden /><p>No hay oportunidades con estos filtros.</p><span>{filtros.senal === 'pendientes' ? 'Las próximas actividades siguen en Agenda.' : 'Puedes elegir otra señal o etapa.'}</span>{hayFiltros && <Button variant="outline" size="sm" onClick={limpiar}>Ver todas las acciones</Button>}</div>
          : <>
            <div className="sla-columnas" aria-hidden="true"><span>Oportunidad{esSupervisor ? ' y analista' : ''}</span><span>Acción pendiente</span><span>Fecha de referencia</span><span>Ficha</span></div>
            <ul className="sla-lista" aria-label="Oportunidades de esta página" aria-busy={consulta.isFetching || abriendo !== null}>
              {pagina.items.map((item) => item.lead_id === null
                ? <FilaClienteSla key={item.clave} item={item} idFicha={idFichaCliente(item)} deshabilitada={abriendo !== null} />
                : <li key={item.clave}>
                <button type="button" disabled={abriendo !== null} onClick={() => void abrirFicha(item.lead_id)} className="sla-fila">
                  <span className="sla-oportunidad">
                    <strong>{item.lead.nombre_completo}</strong>
                    <span className="sla-meta"><span>{ETAPA_INFO[item.lead.etapa as keyof typeof ETAPA_INFO]?.label ?? item.lead.etapa}</span>{esSupervisor && <span>{item.lead.analista_nombre ?? 'Sin analista'}</span>}</span>
                  </span>
                  <span className="sla-accion">
                    <span className={`sla-etiqueta sla-etiqueta-${item.severidad}`}>{pagina.modelo_avisos === 3 && item.bucket === 'primera_atencion' ? 'Realizar la primera gestión' : ACCIONES_SLA[item.bucket] ?? 'Revisar oportunidad'}</span>
                    {esSupervisor && item.senales.revisiones && item.bucket !== 'revision_comercial' && <span className="sla-revision">Revisión comercial</span>}
                    {esSupervisor && item.senales.revisiones && <span className="sla-motivo">{item.estado.etapa.motivos_revision.map((motivo) => MOTIVOS_REVISION_SLA[motivo] ?? 'Revisión requerida').join(' · ')}</span>}
                  </span>
                  <span className="sla-fecha"><span>Referencia</span>{fechaSla(item.referencia_en)} <span>(Lima)</span></span>
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

/**
 * Cuántas filas de ESTA página son tareas de clientes. No se usa
 * `totales.clientes`: el servidor cuenta ahí todas las del ámbito, sin la señal
 * elegida, y con «Para atender ahora» no cuadraría con lo que se ve (Codex).
 */
function clientesEnPagina(items: readonly { lead_id: string | null }[]): string {
  const n = items.filter((i) => i.lead_id === null).length
  return n === 0 ? '' : n === 1 ? ' · 1 gestión con un cliente en esta página' : ` · ${n.toLocaleString('es-PE')} gestiones con clientes en esta página`
}

/**
 * Una tarea de CLIENTE en «Seguimiento comercial». Misma rejilla que la de un
 * lead, sin lo que un cliente no tiene: etapa, analista (la v3 no lo manda) y
 * avisos de SLA. Con ficha es un ENLACE a su ficha de «Mi cartera» (cambia de
 * vista, a diferencia del panel de un lead; Ctrl/Cmd+clic la abre aparte sin
 * perder esta lista). Sin ficha (cliente solo del portal) es una fila de
 * lectura, y lo dice en la línea que siempre se ve (revisión a11y, 29/09/2026).
 */
function FilaClienteSla({ item, idFicha, deshabilitada }: { item: ItemColaDiaCliente; idFicha: string | null; deshabilitada: boolean }) {
  const contenido = <>
    <span className="sla-oportunidad">
      <strong>{item.sujeto.nombre}</strong>
      <span className="sla-meta">
        <span>{idFicha !== null ? 'Cliente de la cartera' : 'Cliente del portal'}</span>
        {idFicha === null && <span>Sin ficha en la cartera</span>}
      </span>
    </span>
    <span className="sla-accion">
      <span className={`sla-etiqueta sla-etiqueta-${item.severidad}`}>{ACCIONES_CLIENTE_SLA[item.bucket]}</span>
    </span>
    <span className="sla-fecha"><span>Referencia</span>{fechaSla(item.referencia_en)} <span>(Lima)</span></span>
  </>
  return <li>
    {idFicha !== null
      ? <a href={hashDe('mi-cartera', null, idFicha)} className="sla-fila" aria-disabled={deshabilitada || undefined}
          onClick={(e) => { if (deshabilitada) e.preventDefault() }}>
          {contenido}
          <span className="sla-abrir"><span>Ver en Mi cartera</span><ArrowUpRight aria-hidden /></span>
        </a>
      : <div className="sla-fila sla-fila-lectura">{contenido}</div>}
  </li>
}

export function EstadoSlaFicha({ leadId, onActuar }: { leadId: string; onActuar?: ((aviso: AvisoSla) => void | Promise<void>) | undefined }) {
  const { yo } = useAuth()
  const puedeRegistrarGestion = puedeRegistrarGestionSla(yo?.rol)
  const consulta = useEstadosSlaV2([leadId])
  if (yo?.demo) return null
  if (consulta.error) return <FalloSla onReintentar={() => void consulta.refetch()} />
  if (!consulta.data) return <p role="status" className="text-xs">Consultando plazos de seguimiento…</p>
  if (consulta.data.modo !== 'activo') return null
  const estado = consulta.data.filas.find((fila) => fila.lead_id === leadId)
  if (!estado) return <p role="alert" className="text-xs">El estado de seguimiento no está disponible para esta oportunidad.</p>
  if (estado.evaluacion === 'no_aplica') return null
  // El aviso vive TAMBIÉN aquí, no solo en el montaje global de App.tsx: la
  // ficha es un Sheet MODAL y, mientras está abierta, marca como aria-hidden e
  // inerte todo lo que hay detrás — el aviso global queda fuera del alcance del
  // lector de pantalla y del puntero. Dos copias, nunca alcanzables a la vez.
  return <div className="space-y-3"><GuardadosSlaPendientes /><DetalleSla estado={estado} supervision={!puedeRegistrarGestion} onActuar={onActuar} /></div>
}
export function DetalleSla({ estado, supervision = false, onActuar }: {
  estado: EstadoSlaV2; supervision?: boolean; onActuar?: ((aviso: AvisoSla) => void | Promise<void>) | undefined
}) {
  const { compromiso, seguimiento, etapa } = estado
  const modelo = estado.operacion?.modelo
  const avisos = modelo === 3 ? estado.avisos_mostrados ?? [] : estado.avisos
  const programada = modelo === 3 ? estado.operacion?.proxima_accion : compromiso.tarea
  const [abriendo, setAbriendo] = useState<string | null>(null)
  async function actuar(aviso: AvisoSla) {
    if (abriendo || !onActuar) return
    setAbriendo(aviso.id)
    try { await onActuar(aviso) } finally { setAbriendo(null) }
  }
  return <section aria-label="Pendientes y plazos" className="space-y-2">
    {avisos.length > 0 && <ul aria-label="Acciones pendientes" className="space-y-2">
      {avisos.map((aviso) => {
        const texto = textoAvisoSla(aviso, supervision, modelo)
        return <li key={aviso.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-warning-text/30 bg-warning-text/5 px-3 py-2">
          <div className="min-w-0 flex-1 text-xs">
            <p className="font-semibold text-foreground">{texto.titulo}</p>
            {aviso.bucket === 'tarea_vencida' && <p className="mt-0.5 text-muted-foreground">Programada: {fechaSla(aviso.referencia_en)} · Lima</p>}
            {aviso.bucket === 'revision_comercial' && <p className="mt-0.5 text-muted-foreground">{etapa.motivos_revision.map((motivo) => MOTIVOS_REVISION_SLA[motivo] ?? 'Revisión requerida').join(' · ')}</p>}
          </div>
          {onActuar && texto.boton && <Button variant="outline" size="sm" disabled={abriendo !== null} onClick={() => void actuar(aviso)}>{abriendo === aviso.id ? 'Abriendo…' : texto.boton}<ArrowUpRight aria-hidden /></Button>}
        </li>
      })}
    </ul>}
    <details className="rounded-lg border px-3 py-2 text-xs">
      <summary className="cursor-pointer font-medium text-muted-foreground focus-visible:outline-2 focus-visible:outline-ring">Ver plazos</summary>
      <div className="mt-3 space-y-2">
        <p className="text-muted-foreground">Fechas y horas de Lima.</p>
        <dl className="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-x-3 gap-y-2">
          {programada && <><dt className="text-muted-foreground">Actividad programada</dt><dd>{fechaSla(programada.vence_en)}</dd></>}
          {modelo !== 3 && <><dt className="text-muted-foreground">{compromiso.cobertura_activa === true ? 'Retomar seguimiento desde' : 'Próxima gestión: límite'}</dt>
          <dd>{fechaSla(compromiso.cobertura_activa === true ? compromiso.hasta_en : seguimiento.limite_en)}</dd></>}
          <dt className="text-muted-foreground">Plazo actual de etapa</dt><dd>{fechaSla(etapa.limite_operativo_en)}</dd>
          {supervision && <><dt className="text-muted-foreground">Tope para ampliaciones</dt><dd>{fechaSla(etapa.techo_en)}</dd></>}
        </dl>
      </div>
    </details>
  </section>
}
