import { useMemo, useState, type JSX } from 'react'
import {
  BellRing,
  CheckCircle2,
  CircleAlert,
  RefreshCw,
  Search,
  SearchX,
  TriangleAlert,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import { PanelError, PanelVacio } from '@/components/common/estado-panel'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import type { AlertaGerencia } from '@/lib/alertas-gerencia'
import { SEMAFORO } from '@/lib/semaforo'

type FiltroPrioridad = 'todas' | 'critica' | 'atencion'
type FiltroTipo = 'todos' | AlertaGerencia['tipo']

export interface AlertasGerenciaPanelProps {
  alertas: AlertaGerencia[]
  generadoEn?: string | null
  cargando: boolean
  errores: string[]
  onReintentar: () => void
  modoDemo?: boolean
}

const ETIQUETAS_TIPO: Record<AlertaGerencia['tipo'], string> = {
  tarea_vencida: 'Tareas vencidas',
  sin_proxima_accion: 'Leads sin próxima acción',
  no_show: 'Inasistencias a reuniones',
  bajo_meta_conversion: 'Conversión bajo meta',
  caida_conversion: 'Caída de conversión',
}

const ETIQUETAS_DESTINO: Record<AlertaGerencia['destino'], string> = {
  conversiones: 'Conversiones',
  'ranking-vendedores': 'Ranking',
  reuniones: 'Reuniones',
  rendimiento: 'Equipo',
}

function etiquetaTipo(tipo: AlertaGerencia['tipo']): string {
  return ETIQUETAS_TIPO[tipo]
}

function etiquetaDestino(destino: AlertaGerencia['destino']): string {
  return ETIQUETAS_DESTINO[destino]
}

function normalizar(texto: string): string {
  return texto
    .toLocaleLowerCase('es-PE')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
}

function textoActualizacion(generadoEn: string | null | undefined): string {
  if (!generadoEn) return 'Hora de actualización no disponible'
  const instante = Date.parse(generadoEn)
  if (!Number.isFinite(instante)) return 'Hora de actualización no disponible'
  return `Actualizado ${new Intl.DateTimeFormat('es-PE', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Lima',
  }).format(instante)}`
}

function textoMetrica(valor: string | number | null | undefined): string | null {
  if (valor == null || valor === '') return null
  return typeof valor === 'number'
    ? new Intl.NumberFormat('es-PE', { maximumFractionDigits: 1 }).format(valor)
    : valor
}

function detalleMetrica(alerta: AlertaGerencia): string | null {
  const actual = textoMetrica(alerta.actual)
  const objetivo = textoMetrica(alerta.objetivo)
  const brecha = textoMetrica(alerta.brechaPp)
  const esPorcentaje = alerta.tipo === 'bajo_meta_conversion' || alerta.tipo === 'caida_conversion'
  const unidad = esPorcentaje ? '%' : ''
  if (actual != null && objetivo != null) {
    return `Actual ${actual}${unidad} · referencia ${objetivo}${unidad}${brecha == null ? '' : ` · brecha ${brecha} pp`}`
  }
  if (brecha != null) return `Brecha ${brecha} pp`
  if (actual != null) return `Actual ${actual}${unidad}`
  if (objetivo != null) return `Referencia ${objetivo}${unidad}`
  return null
}

function textoValor(alerta: AlertaGerencia): string {
  const valor = textoMetrica(alerta.valor) ?? '—'
  if (alerta.tipo === 'tarea_vencida') return `${valor} ${alerta.valor === 1 ? 'tarea' : 'tareas'}`
  if (alerta.tipo === 'sin_proxima_accion') return `${valor} ${alerta.valor === 1 ? 'lead' : 'leads'}`
  if (alerta.tipo === 'no_show') return `${valor} ${alerta.valor === 1 ? 'inasistencia' : 'inasistencias'}`
  return `${valor}%`
}

function configuracionSeveridad(severidad: AlertaGerencia['severidad']): {
  color: string
  etiqueta: string
  Icono: typeof CircleAlert
} {
  return severidad === 'critica'
    ? { color: SEMAFORO.critico, etiqueta: 'Crítica', Icono: CircleAlert }
    : { color: SEMAFORO.atencion, etiqueta: 'Atención', Icono: TriangleAlert }
}

function ResumenPrioridad({
  filtro,
  onCambiar,
  total,
  criticas,
  atencion,
}: {
  filtro: FiltroPrioridad
  onCambiar: (filtro: FiltroPrioridad) => void
  total: number
  criticas: number
  atencion: number
}): JSX.Element {
  const opciones: Array<{ id: FiltroPrioridad; etiqueta: string; cantidad: number; color: string }> = [
    { id: 'todas', etiqueta: 'Todas', cantidad: total, color: 'var(--gi-blue)' },
    { id: 'critica', etiqueta: 'Críticas', cantidad: criticas, color: SEMAFORO.critico },
    { id: 'atencion', etiqueta: 'Atención', cantidad: atencion, color: SEMAFORO.atencion },
  ]
  return (
    <div className="grid grid-cols-3 overflow-hidden rounded-xl border border-[var(--gi-line)] bg-white" role="group" aria-label="Filtrar alertas por prioridad">
      {opciones.map((opcion) => {
        const activa = filtro === opcion.id
        return (
          <button
            key={opcion.id}
            type="button"
            aria-pressed={activa}
            aria-label={`${opcion.etiqueta}: ${opcion.cantidad}`}
            onClick={() => onCambiar(opcion.id)}
            className={`relative min-w-0 cursor-pointer px-3 py-3 text-left transition-colors focus-visible:z-10 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/35 motion-reduce:transition-none ${activa ? 'bg-[var(--gi-soft)]' : 'hover:bg-[var(--gi-soft)]/70'} [&+&]:border-l [&+&]:border-[var(--gi-line)]`}
          >
            <span
              className="absolute inset-x-3 top-0 h-[3px] rounded-b-full"
              style={{ background: activa ? opcion.color : 'transparent' }}
              aria-hidden
            />
            <span className="block truncate text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--gi-muted)]">
              {opcion.etiqueta}
            </span>
            <strong className="mt-1 block text-xl leading-none tabular-nums text-[var(--gi-navy)]">
              {opcion.cantidad}
            </strong>
          </button>
        )
      })}
    </div>
  )
}

function CabeceraAlertas({
  generadoEn,
  cargando,
  modoDemo,
  onActualizar,
}: {
  generadoEn: string | null | undefined
  cargando: boolean
  modoDemo: boolean
  onActualizar: () => void
}): JSX.Element {
  return (
    <section className="gi-card flex flex-wrap items-center justify-between gap-3 px-4 py-3.5 sm:px-5" aria-labelledby="estado-alertas-gerencia">
      <div className="flex min-w-0 items-center gap-3">
        <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-[var(--gi-soft)] text-[var(--gi-blue)]">
          <BellRing className="size-4" aria-hidden />
        </span>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h2 id="estado-alertas-gerencia" className="gi-title">Estado actual · Lima</h2>
            {modoDemo && <Badge color="var(--gi-blue)" variant="outline">Ejemplo</Badge>}
          </div>
          <p className="gi-caption mt-0.5 tabular-nums">{textoActualizacion(generadoEn)}</p>
        </div>
      </div>
      <Button type="button" variant="outline" size="sm" disabled={cargando} onClick={onActualizar}>
        <RefreshCw className={cargando ? 'animate-spin motion-reduce:animate-none' : undefined} aria-hidden />
        {cargando ? 'Actualizando…' : 'Actualizar'}
      </Button>
    </section>
  )
}

function CargaInicial(): JSX.Element {
  return (
    <div className="space-y-3" role="status" aria-label="Cargando alertas" aria-busy="true">
      <span className="sr-only">Cargando alertas</span>
      <Skeleton className="h-20 rounded-xl motion-reduce:animate-none" />
      <div className="gi-card space-y-2 p-4">
        {Array.from({ length: 5 }, (_, indice) => (
          <Skeleton key={indice} className="h-14 rounded-lg motion-reduce:animate-none" />
        ))}
      </div>
    </div>
  )
}

function AvisoParcial({ errores, cargando, onReintentar }: {
  errores: string[]
  cargando: boolean
  onReintentar: () => void
}): JSX.Element {
  return (
    <div className="gi-card flex flex-wrap items-start justify-between gap-3 border-destructive/25 px-4 py-3" role="alert">
      <div className="flex min-w-0 items-start gap-2.5">
        <CircleAlert className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
        <div>
          <p className="text-sm font-bold text-[var(--gi-navy)]">Información incompleta</p>
          <ul className="mt-1 space-y-0.5 text-xs text-[var(--gi-muted)]">
            {errores.map((error) => <li key={error}>{error}</li>)}
          </ul>
        </div>
      </div>
      <Button type="button" variant="outline" size="sm" disabled={cargando} onClick={onReintentar}>
        <RefreshCw aria-hidden /> Reintentar
      </Button>
    </div>
  )
}

function CeldaAlerta({ alerta }: { alerta: AlertaGerencia }): JSX.Element {
  const severidad = configuracionSeveridad(alerta.severidad)
  const detalle = detalleMetrica(alerta)
  return (
    <div className="min-w-0">
      <div className="flex flex-wrap items-center gap-2">
        <Badge color={severidad.color} variant="outline">
          <severidad.Icono className="size-3" aria-hidden /> {severidad.etiqueta}
        </Badge>
        <span className="text-sm font-bold text-[var(--gi-navy)]">{etiquetaTipo(alerta.tipo)}</span>
      </div>
      {detalle != null && <p className="mt-1 text-[11px] tabular-nums text-[var(--gi-muted)]">{detalle}</p>}
    </div>
  )
}

function TablaAlertas({ alertas }: { alertas: AlertaGerencia[] }): JSX.Element {
  return (
    <div className="hidden md:block">
      <TablaEnvoltura ariaLabel="Alertas activas">
        <TheadCrm>
          <Th>Prioridad y señal</Th>
          <Th>Responsable</Th>
          <Th>Equipo</Th>
          <Th className="text-right">Valor</Th>
          <Th className="w-28"><span className="sr-only">Destino</span></Th>
        </TheadCrm>
        <tbody className="divide-y divide-[var(--gi-line)]">
          {alertas.map((alerta) => {
            const severidad = configuracionSeveridad(alerta.severidad)
            const responsable = alerta.responsable || 'Sin responsable'
            const equipo = alerta.equipo || 'Sin equipo'
            return (
              <tr key={alerta.id} className="transition-colors hover:bg-[var(--gi-soft)]/70 motion-reduce:transition-none">
                <Td className="relative py-3 pl-5">
                  <span className="absolute inset-y-2 left-0 w-1 rounded-r-full" style={{ background: severidad.color }} aria-hidden />
                  <CeldaAlerta alerta={alerta} />
                </Td>
                <Td className="py-3 text-sm font-semibold text-[var(--gi-ink)]">{responsable}</Td>
                <Td className="py-3 text-xs text-[var(--gi-muted)]">{equipo}</Td>
                <Td className="py-3 text-right text-sm font-bold tabular-nums text-[var(--gi-navy)]">{textoValor(alerta)}</Td>
                <Td className="py-3 text-right">
                  <a
                    href={`#/${alerta.destino}`}
                    aria-label={`Abrir ${etiquetaDestino(alerta.destino)} para ${responsable}`}
                    className="inline-flex min-h-8 items-center rounded-lg px-2.5 text-xs font-bold text-[var(--gi-blue)] outline-none transition-colors hover:bg-[var(--gi-soft)] focus-visible:ring-[3px] focus-visible:ring-ring/35 motion-reduce:transition-none"
                  >
                    Ver {etiquetaDestino(alerta.destino)}
                  </a>
                </Td>
              </tr>
            )
          })}
        </tbody>
      </TablaEnvoltura>
    </div>
  )
}

function ListaMovilAlertas({ alertas }: { alertas: AlertaGerencia[] }): JSX.Element {
  return (
    <ol className="divide-y divide-[var(--gi-line)] md:hidden" aria-label="Alertas activas en móvil">
      {alertas.map((alerta) => {
        const severidad = configuracionSeveridad(alerta.severidad)
        const responsable = alerta.responsable || 'Sin responsable'
        const equipo = alerta.equipo || 'Sin equipo'
        return (
          <li key={alerta.id} className="relative px-4 py-4 pl-5">
            <span className="absolute inset-y-3 left-0 w-1 rounded-r-full" style={{ background: severidad.color }} aria-hidden />
            <CeldaAlerta alerta={alerta} />
            <dl className="mt-3 grid grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-1 text-xs">
              <div className="min-w-0">
                <dt className="sr-only">Responsable y equipo</dt>
                <dd className="truncate font-semibold text-[var(--gi-ink)]">{responsable}</dd>
                <dd className="truncate text-[11px] text-[var(--gi-muted)]">{equipo}</dd>
              </div>
              <div className="text-right">
                <dt className="text-[10px] font-bold uppercase tracking-[0.08em] text-[var(--gi-muted)]">Valor</dt>
                <dd className="mt-0.5 font-bold tabular-nums text-[var(--gi-navy)]">{textoValor(alerta)}</dd>
              </div>
            </dl>
            <a
              href={`#/${alerta.destino}`}
              aria-label={`Abrir ${etiquetaDestino(alerta.destino)} para ${responsable}`}
              className="mt-3 inline-flex min-h-9 items-center rounded-lg border border-[var(--gi-line)] px-3 text-xs font-bold text-[var(--gi-blue)] outline-none transition-colors hover:bg-[var(--gi-soft)] focus-visible:ring-[3px] focus-visible:ring-ring/35 motion-reduce:transition-none"
            >
              Ver {etiquetaDestino(alerta.destino)}
            </a>
          </li>
        )
      })}
    </ol>
  )
}

export function AlertasGerenciaPanel({
  alertas,
  generadoEn = null,
  cargando,
  errores,
  onReintentar,
  modoDemo = false,
}: AlertasGerenciaPanelProps): JSX.Element {
  const [prioridad, setPrioridad] = useState<FiltroPrioridad>('todas')
  const [tipo, setTipo] = useState<FiltroTipo>('todos')
  const [busqueda, setBusqueda] = useState('')

  const tipos = useMemo(
    () => [...new Set(alertas.map((alerta) => alerta.tipo))]
      .sort((a, b) => etiquetaTipo(a).localeCompare(etiquetaTipo(b), 'es-PE')),
    [alertas],
  )
  const conteos = useMemo(() => ({
    criticas: alertas.filter((alerta) => alerta.severidad === 'critica').length,
    atencion: alertas.filter((alerta) => alerta.severidad === 'atencion').length,
  }), [alertas])
  const filtradas = useMemo(() => {
    const texto = normalizar(busqueda.trim())
    return alertas.filter((alerta) => {
      if (prioridad !== 'todas' && alerta.severidad !== prioridad) return false
      if (tipo !== 'todos' && alerta.tipo !== tipo) return false
      if (!texto) return true
      return normalizar(`${alerta.responsable ?? ''} ${alerta.equipo ?? ''}`).includes(texto)
    })
  }, [alertas, busqueda, prioridad, tipo])
  const hayFiltros = prioridad !== 'todas' || tipo !== 'todos' || busqueda.trim() !== ''
  const limpiarFiltros = () => {
    setPrioridad('todas')
    setTipo('todos')
    setBusqueda('')
  }

  return (
    <section className="space-y-4" aria-label="Centro de alertas de Gerencia">
      <CabeceraAlertas generadoEn={generadoEn} cargando={cargando} modoDemo={modoDemo} onActualizar={onReintentar} />

      {cargando && alertas.length === 0 ? (
        <CargaInicial />
      ) : errores.length > 0 && alertas.length === 0 ? (
        <div className="gi-card" role="alert">
          <PanelError
            mensaje={errores.join(' ') || 'No pudimos cargar las alertas.'}
            onReintentar={onReintentar}
            reintentando={cargando}
          />
        </div>
      ) : alertas.length === 0 ? (
        <div className="gi-card">
          <PanelVacio
            icono={CheckCircle2}
            titulo="Todo al día"
            detalle="No hay alertas activas en la operación al momento de esta actualización."
          />
        </div>
      ) : (
        <>
          {errores.length > 0 && (
            <AvisoParcial errores={errores} cargando={cargando} onReintentar={onReintentar} />
          )}

          <div className="grid gap-3 lg:grid-cols-[minmax(0,390px)_minmax(0,1fr)] lg:items-end">
            <ResumenPrioridad
              filtro={prioridad}
              onCambiar={setPrioridad}
              total={alertas.length}
              criticas={conteos.criticas}
              atencion={conteos.atencion}
            />
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center lg:justify-end">
              <div className="w-full sm:w-56">
                <Select aria-label="Filtrar alertas por tipo" value={tipo} onChange={(evento) => setTipo(evento.target.value as FiltroTipo)}>
                  <option value="todos">Todos los tipos</option>
                  {tipos.map((valor) => <option key={valor} value={valor}>{etiquetaTipo(valor)}</option>)}
                </Select>
              </div>
              <div className="relative w-full sm:max-w-xs">
                <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--gi-muted)]" aria-hidden />
                <Input
                  type="search"
                  aria-label="Buscar responsable o equipo"
                  placeholder="Responsable o equipo…"
                  className="pl-9"
                  value={busqueda}
                  onChange={(evento) => setBusqueda(evento.target.value)}
                />
              </div>
              {hayFiltros && (
                <Button type="button" variant="ghost" size="sm" onClick={limpiarFiltros}>Limpiar</Button>
              )}
            </div>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 px-1">
            <p className="text-xs font-semibold tabular-nums text-[var(--gi-muted)]" role="status" aria-live="polite" aria-atomic="true">
              {filtradas.length} {filtradas.length === 1 ? 'alerta activa' : 'alertas activas'}
              {hayFiltros ? ` de ${alertas.length}` : ''}
            </p>
            {cargando && alertas.length > 0 && (
              <span className="inline-flex items-center gap-1.5 text-[11px] font-semibold text-[var(--gi-muted)]" role="status">
                <RefreshCw className="size-3 animate-spin motion-reduce:animate-none" aria-hidden /> Actualizando datos
              </span>
            )}
          </div>

          <div className="gi-card overflow-hidden">
            {filtradas.length === 0 ? (
              <PanelVacio
                icono={SearchX}
                titulo="Sin coincidencias"
                detalle="No hay alertas que coincidan con estos filtros."
              >
                <Button type="button" variant="outline" size="sm" onClick={limpiarFiltros}>Limpiar filtros</Button>
              </PanelVacio>
            ) : (
              <>
                <TablaAlertas alertas={filtradas} />
                <ListaMovilAlertas alertas={filtradas} />
              </>
            )}
          </div>
        </>
      )}
    </section>
  )
}

export const AlertasGerencia = AlertasGerenciaPanel
