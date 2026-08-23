import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
import {
  AlarmClock,
  BellRing,
  CalendarPlus,
  CheckCircle2,
  CircleAlert,
  Gauge,
  PhoneOutgoing,
  RefreshCw,
  Search,
  SearchX,
  Split,
  Trash2,
  TrendingDown,
  UserRoundX,
  type LucideIcon,
} from 'lucide-react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { CrmApiError, eliminarRecordatorioDisponibilidad } from '@/data/crm-api'
import { crmQueryKeys } from '@/data/crm-queries'
import { esFocoHuerfano } from '@/lib/foco'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { usePanelesActions } from '@/lib/store-context'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import { PanelError, PanelVacio } from '@/components/common/estado-panel'
import { useAlertasCRM } from '@/lib/alertas-context'
import { hashDe } from '@/lib/router'
import { SEMAFORO } from '@/lib/semaforo'
import type { AlertaCRM, TipoAlerta } from '@/lib/alertas'
import type { Rol } from '@/lib/roles'

type FiltroPrioridad = 'todas' | AlertaCRM['severidad']
type FiltroTipo = 'todos' | TipoAlerta

const ETIQUETA_TIPO: Record<TipoAlerta, string> = {
  tarea_vencida: 'Tarea vencida',
  lead_sin_responder: 'Lead sin responder',
  sin_proxima_accion: 'Sin próxima acción',
  // El supervisor recibe la bandeja AGRUPADA («12 leads esperando reparto»),
  // así que el filtro nombra la decisión, no el registro.
  por_repartir: 'Por repartir',
  bajo_meta_conversion: 'Conversión bajo meta',
  caida_conversion: 'Caída de conversión',
  revisar_contacto: 'Revisar contacto',
}

const ICONO_TIPO: Record<TipoAlerta, LucideIcon> = {
  tarea_vencida: AlarmClock,
  lead_sin_responder: UserRoundX,
  sin_proxima_accion: CalendarPlus,
  por_repartir: Split,
  bajo_meta_conversion: Gauge,
  caida_conversion: TrendingDown,
  revisar_contacto: PhoneOutgoing,
}

const COPY_ROL: Record<'vendedor' | 'supervisor' | 'gerencia', {
  alcance: string
  titulo: string
  detalle: string
  vacio: string
}> = {
  vendedor: {
    alcance: 'Tu acción',
    titulo: 'Mis pendientes actuales',
    detalle: 'Solo aparecen casos tuyos que puedes resolver desde el CRM.',
    vacio: 'No tienes acciones atrasadas ni leads sin siguiente paso.',
  },
  supervisor: {
    alcance: 'Tu intervención',
    titulo: 'Excepciones del equipo',
    detalle: 'Solo aparecen atrasos que ya superaron la tolerancia o requieren reparto.',
    vacio: 'Tu equipo no tiene excepciones que requieran intervención.',
  },
  gerencia: {
    alcance: 'Tu decisión',
    titulo: 'Señales de gestión',
    detalle: 'Solo aparecen desviaciones estratégicas con muestra suficiente.',
    vacio: 'No hay desviaciones estratégicas que requieran una decisión.',
  },
}

function copyRol(rol: Rol | null) {
  return rol === 'vendedor' || rol === 'supervisor' || rol === 'gerencia'
    ? COPY_ROL[rol]
    : COPY_ROL.vendedor
}

function normalizar(texto: string): string {
  return texto
    .toLocaleLowerCase('es-PE')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
}

function textoActualizacion(generadoEn: string | null): string {
  if (!generadoEn || !Number.isFinite(Date.parse(generadoEn))) return 'Actualización no disponible'
  return `Actualizado ${new Intl.DateTimeFormat('es-PE', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Lima',
  }).format(Date.parse(generadoEn))}`
}

function colorSeveridad(severidad: AlertaCRM['severidad']): string {
  return severidad === 'critica' ? SEMAFORO.critico : SEMAFORO.atencion
}

function CargaAlertas(): JSX.Element {
  return (
    <div className="space-y-2" role="status" aria-label="Cargando pendientes" aria-busy="true">
      <span className="sr-only">Cargando pendientes</span>
      {Array.from({ length: 4 }, (_, indice) => (
        <Skeleton key={indice} className="h-24 rounded-xl motion-reduce:animate-none" />
      ))}
    </div>
  )
}

function FiltrosPrioridad({
  valor,
  onCambiar,
  total,
  criticas,
}: {
  valor: FiltroPrioridad
  onCambiar: (valor: FiltroPrioridad) => void
  total: number
  criticas: number
}): JSX.Element {
  const opciones: Array<{ id: FiltroPrioridad; label: string; cantidad: number }> = [
    { id: 'todas', label: 'Todas', cantidad: total },
    { id: 'critica', label: 'Críticas', cantidad: criticas },
    { id: 'atencion', label: 'Atención', cantidad: total - criticas },
  ]
  return (
    <div className="inline-flex rounded-xl border border-border bg-card p-1" role="group" aria-label="Filtrar por prioridad">
      {opciones.map((opcion) => (
        <button
          key={opcion.id}
          type="button"
          aria-pressed={valor === opcion.id}
          aria-label={`${opcion.label}: ${opcion.cantidad}`}
          onClick={() => onCambiar(opcion.id)}
          className={`min-h-8 rounded-lg px-3 text-xs font-bold tabular-nums outline-none transition-colors focus-visible:ring-[3px] focus-visible:ring-ring/35 motion-reduce:transition-none ${
            valor === opcion.id
              ? 'bg-primary text-primary-foreground'
              : 'text-muted-foreground hover:bg-muted hover:text-foreground'
          }`}
        >
          {opcion.label} <span aria-hidden>{opcion.cantidad}</span>
        </button>
      ))}
    </div>
  )
}

/** F3 «Recordar» (§5.4): la alerta de contacto no navega — VERIFICA bajo
 *  demanda abriendo el alta con el teléfono precargado (el circuito completo
 *  de F1/F2: veredicto fresco, y si está libre, el botón «Tomar» ahí mismo).
 *  «Quitar» elimina el recordatorio (§5.3: puede eliminarse sin afectar nada). */
function AccionesRevisarContacto({ alerta }: { alerta: AlertaCRM }): JSX.Element {
  const { abrirNuevoLead } = usePanelesActions()
  const queryClient = useQueryClient()
  const [quitando, setQuitando] = useState(false)
  const botonQuitarRef = useRef<HTMLButtonElement | null>(null)
  // Rescate del foco tras un fallo vía EFECTO, no en línea: en el finally el
  // botón AÚN está disabled (el re-render de setQuitando(false) no conmutó) y
  // focus() sobre un control disabled es un no-op — la misma lección de F2.
  const rescatarFocoQuitarRef = useRef(false)
  useEffect(() => {
    if (quitando || !rescatarFocoQuitarRef.current) return
    rescatarFocoQuitarRef.current = false
    if (esFocoHuerfano(botonQuitarRef.current)) botonQuitarRef.current?.focus()
  }, [quitando])
  const contacto = alerta.contacto
  if (!contacto) return <></>

  const quitar = async () => {
    if (quitando) return
    setQuitando(true)
    try {
      await eliminarRecordatorioDisponibilidad(contacto.recordatorioId)
      toast.success('Recordatorio quitado')
    } catch (error: unknown) {
      // «Ya no existe» = caducó solo o se quitó en otra pestaña: el refetch
      // de abajo lo hace desaparecer igual — no es un fallo que gritar.
      if (!(error instanceof CrmApiError && error.code === 'NO_ENCONTRADO')) {
        toast.error(error instanceof CrmApiError ? error.message : 'No se pudo quitar el recordatorio.')
      }
    } finally {
      await queryClient.invalidateQueries({ queryKey: crmQueryKeys.recordatoriosDisponibilidad() })
      setQuitando(false)
      // a11y M4 (F3.1, refutación de Codex al diseño anterior): el destino del
      // foco se decide por la REALIDAD del dato, no por la intención — la fila
      // pinta exactamente lo que hay en el cache de esta query. Si el
      // recordatorio ya no está, la fila se va y el foco aterriza en el
      // contador (o el encabezado, si era la última alerta); si sigue —fallo
      // real o refetch caído que conservó el dato viejo—, el botón sigue
      // siendo el lugar y se rescata solo un foco huérfano.
      const filas = queryClient.getQueryData<ReadonlyArray<{ id: string }>>(
        crmQueryKeys.recordatoriosDisponibilidad(),
      )
      const sigueVivo = Array.isArray(filas)
        && filas.some((fila) => fila.id === contacto.recordatorioId)
      if (!sigueVivo) {
        const destino = document.getElementById('alertas-contador')
          ?? document.getElementById('alertas-encabezado')
        destino?.focus()
      } else {
        rescatarFocoQuitarRef.current = true
      }
    }
  }

  return (
    <div className="ml-12 flex items-center gap-2 sm:ml-0">
      <Button
        variant="accent"
        size="sm"
        onClick={() => abrirNuevoLead(undefined, contacto.telefono)}
        aria-label={`Verificar disponibilidad de ${telefonoLegible(contacto.telefono)}`}
      >
        <PhoneOutgoing /> Verificar disponibilidad
      </Button>
      <Button
        ref={botonQuitarRef}
        variant="ghost"
        size="sm"
        onClick={() => { void quitar() }}
        disabled={quitando}
        aria-busy={quitando}
        aria-label={`Quitar recordatorio de ${telefonoLegible(contacto.telefono)}`}
      >
        <Trash2 /> Quitar
      </Button>
    </div>
  )
}

function FilaAlerta({ alerta, alcance }: { alerta: AlertaCRM; alcance: string }): JSX.Element {
  const Icono = ICONO_TIPO[alerta.tipo]
  const color = colorSeveridad(alerta.severidad)
  return (
    <li className="group relative grid gap-3 px-4 py-4 pl-5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center sm:px-5 sm:pl-6">
      <span
        className="absolute inset-y-3 left-0 w-1 rounded-r-full"
        style={{ backgroundColor: color }}
        aria-hidden
      />
      <div className="flex min-w-0 items-start gap-3">
        <span className="mt-0.5 grid size-9 shrink-0 place-items-center rounded-xl bg-muted text-primary transition-transform group-hover:scale-105 motion-reduce:transition-none">
          <Icono className="size-4" aria-hidden />
        </span>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <Badge color={color} variant="outline">
              {alerta.severidad === 'critica' ? 'Crítica' : 'Atención'}
            </Badge>
            <span className="text-[10px] font-bold uppercase tracking-[0.1em] text-muted-foreground">
              {alcance}
            </span>
          </div>
          <h2 className="mt-1.5 text-sm font-extrabold text-primary">{alerta.titulo}</h2>
          <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">{alerta.detalle}</p>
          {alerta.responsable && (
            <p className="mt-1 text-[11px] font-semibold text-foreground/70">
              Responsable: {alerta.responsable}
            </p>
          )}
        </div>
      </div>
      {alerta.contacto ? (
        <AccionesRevisarContacto alerta={alerta} />
      ) : (
        <a
          href={hashDe(alerta.destino.vista, alerta.destino.leadId)}
          aria-label={`${alerta.destino.etiqueta}: ${alerta.titulo}`}
          className="ml-12 inline-flex min-h-9 items-center justify-center rounded-lg border border-border bg-card px-3 text-xs font-bold text-primary outline-none transition-colors hover:border-border-strong hover:bg-muted focus-visible:ring-[3px] focus-visible:ring-ring/35 motion-reduce:transition-none sm:ml-0"
        >
          {alerta.destino.etiqueta}
        </a>
      )}
    </li>
  )
}

export function Alertas(): JSX.Element {
  const { alertas, rol, cargando, errores, generadoEn, reintentar } = useAlertasCRM()
  const copy = copyRol(rol)
  const [prioridad, setPrioridad] = useState<FiltroPrioridad>('todas')
  const [tipo, setTipo] = useState<FiltroTipo>('todos')
  const [busqueda, setBusqueda] = useState('')

  const tipos = useMemo(
    () => [...new Set(alertas.map((alerta) => alerta.tipo))]
      .sort((a, b) => ETIQUETA_TIPO[a].localeCompare(ETIQUETA_TIPO[b], 'es-PE')),
    [alertas],
  )
  const criticas = useMemo(
    () => alertas.filter((alerta) => alerta.severidad === 'critica').length,
    [alertas],
  )
  const filtradas = useMemo(() => {
    const texto = normalizar(busqueda.trim())
    return alertas.filter((alerta) => {
      if (prioridad !== 'todas' && alerta.severidad !== prioridad) return false
      if (tipo !== 'todos' && alerta.tipo !== tipo) return false
      if (!texto) return true
      return normalizar(`${alerta.titulo} ${alerta.detalle} ${alerta.responsable ?? ''}`).includes(texto)
    })
  }, [alertas, busqueda, prioridad, tipo])
  const hayFiltros = prioridad !== 'todas' || tipo !== 'todos' || busqueda.trim() !== ''
  const limpiar = () => {
    setPrioridad('todas')
    setTipo('todos')
    setBusqueda('')
  }

  return (
    <section className="mx-auto max-w-5xl space-y-4" aria-label="Pendientes actuales">
      <header className="overflow-hidden rounded-2xl border border-border bg-card shadow-[var(--shadow-card)]">
        <div className="h-1 bg-gradient-to-r from-primary via-accent to-primary" aria-hidden />
        <div className="flex flex-wrap items-center justify-between gap-4 px-5 py-4 sm:px-6">
          <div className="flex min-w-0 items-start gap-3">
            <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
              <BellRing className="size-5" aria-hidden />
            </span>
            <div className="min-w-0">
              <p className="text-[10px] font-extrabold uppercase tracking-[0.14em] text-accent">{copy.alcance}</p>
              {/* id + tabIndex -1: destino de RESERVA del foco tras Quitar la
                  última alerta (el contador desaparece con la lista, F3.1). */}
              <h1
                id="alertas-encabezado"
                tabIndex={-1}
                className="mt-0.5 text-lg font-extrabold tracking-tight text-primary outline-none"
              >
                {copy.titulo}
              </h1>
              <p className="mt-1 max-w-2xl text-xs leading-relaxed text-muted-foreground">{copy.detalle}</p>
              <p className="mt-1 text-[11px] tabular-nums text-muted-foreground">{textoActualizacion(generadoEn)}</p>
            </div>
          </div>
          <Button type="button" variant="outline" size="sm" onClick={reintentar} disabled={cargando}>
            <RefreshCw className={cargando ? 'animate-spin motion-reduce:animate-none' : undefined} aria-hidden />
            {cargando ? 'Actualizando…' : 'Actualizar'}
          </Button>
        </div>
      </header>

      {cargando && alertas.length === 0 ? (
        <CargaAlertas />
      ) : errores.length > 0 && alertas.length === 0 ? (
        <div className="rounded-2xl border border-border bg-card" role="alert">
          <PanelError mensaje={errores.join(' ')} onReintentar={reintentar} reintentando={cargando} />
        </div>
      ) : alertas.length === 0 ? (
        <div className="rounded-2xl border border-border bg-card">
          <PanelVacio icono={CheckCircle2} titulo="Nada pendiente" detalle={copy.vacio} />
        </div>
      ) : (
        <>
          {errores.length > 0 && (
            <div className="flex flex-wrap items-start justify-between gap-3 rounded-xl border border-warning/35 bg-warning/5 px-4 py-3" role="alert">
              <div className="flex min-w-0 items-start gap-2.5">
                <CircleAlert className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden />
                <div>
                  <p className="text-xs font-bold text-foreground">Información incompleta</p>
                  <p className="mt-0.5 text-[11px] text-muted-foreground">{errores.join(' ')}</p>
                </div>
              </div>
              <Button type="button" variant="outline" size="sm" onClick={reintentar}>Reintentar</Button>
            </div>
          )}

          <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <FiltrosPrioridad valor={prioridad} onCambiar={setPrioridad} total={alertas.length} criticas={criticas} />
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
              <Select
                aria-label="Filtrar por tipo"
                value={tipo}
                onChange={(evento) => setTipo(evento.target.value as FiltroTipo)}
                className="sm:w-52"
              >
                <option value="todos">Todos los tipos</option>
                {tipos.map((valor) => <option key={valor} value={valor}>{ETIQUETA_TIPO[valor]}</option>)}
              </Select>
              <div className="relative sm:w-72">
                <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
                <Input
                  type="search"
                  aria-label="Buscar pendiente"
                  placeholder="Buscar responsable o señal…"
                  className="pl-9"
                  value={busqueda}
                  onChange={(evento) => setBusqueda(evento.target.value)}
                />
              </div>
              {hayFiltros && <Button type="button" variant="ghost" size="sm" onClick={limpiar}>Limpiar</Button>}
            </div>
          </div>

          <p
            id="alertas-contador"
            tabIndex={-1}
            className="px-1 text-xs font-semibold tabular-nums text-muted-foreground outline-none"
            role="status"
            aria-live="polite"
          >
            {filtradas.length} {filtradas.length === 1 ? 'pendiente activo' : 'pendientes activos'}
            {hayFiltros ? ` de ${alertas.length}` : ''}
          </p>

          <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-[var(--shadow-card)]">
            {filtradas.length === 0 ? (
              <PanelVacio icono={SearchX} titulo="Sin coincidencias" detalle="No hay pendientes con estos filtros.">
                <Button type="button" variant="outline" size="sm" onClick={limpiar}>Limpiar filtros</Button>
              </PanelVacio>
            ) : (
              <ol className="divide-y divide-border/70" aria-label="Pendientes activos">
                {filtradas.map((alerta) => (
                  <FilaAlerta key={alerta.id} alerta={alerta} alcance={copy.alcance} />
                ))}
              </ol>
            )}
          </div>
        </>
      )}
    </section>
  )
}
