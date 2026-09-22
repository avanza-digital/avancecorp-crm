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
import { textoVencimiento } from '@/lib/reconocimientos-alertas'
import { usePanelesActions } from '@/lib/store-context'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import { PanelError, PanelVacio } from '@/components/common/estado-panel'
import { usePeriodoGerencia } from '@/components/gerencia/use-periodo-gerencia'
import { useAlertasCRM } from '@/lib/alertas-context'
import { hashDe } from '@/lib/router'
import { SEMAFORO } from '@/lib/semaforo'
import type { AlertaCRM, TipoAlerta } from '@/lib/alertas'
import type { Rol } from '@/lib/roles'
import { presentarCitas } from '@/lib/terminologia'
import { AccionesReconocerAlerta } from '@/components/gestion-diaria/acciones-reconocer-alerta'
import { AccionesCorte } from '@/components/gestion-diaria/acciones-corte'

type FiltroPrioridad = 'todas' | AlertaCRM['severidad']
type FiltroTipo = 'todos' | TipoAlerta

const ETIQUETA_TIPO: Record<TipoAlerta, string> = {
  parado_2h: 'Sin llamadas recientes',
  corte_manana: 'Primer corte',
  corte_tarde: 'Segundo corte',
  seguimiento_comercial: 'Seguimiento',
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
  parado_2h: PhoneOutgoing,
  corte_manana: PhoneOutgoing,
  corte_tarde: PhoneOutgoing,
  seguimiento_comercial: AlarmClock,
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
    vacio: 'No hay avisos pendientes. Tus próximas actividades están en Agenda.',
  },
  supervisor: {
    alcance: 'Tu intervención',
    titulo: 'Excepciones del equipo',
    detalle: 'Revisa los pendientes del equipo y los casos que necesitan una decisión.',
    vacio: 'Tu equipo no tiene excepciones que requieran intervención.',
  },
  gerencia: {
    alcance: 'Tu decisión',
    titulo: 'Señales de gestión',
    detalle: 'Pendientes del equipo y resultados que necesitan revisión.',
    vacio: 'No se generaron avisos con los datos evaluables. Esto no confirma que todo esté dentro de la meta: puede faltar el corte de revisión, una meta, muestra suficiente o verificación.',
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
        toast.error(error instanceof CrmApiError ? presentarCitas(error.message) : 'No se pudo quitar el recordatorio.')
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
  const { setPeriodo, setOrigenFiltrado } = usePeriodoGerencia()
  const Icono = ICONO_TIPO[alerta.tipo]
  // Una fila reconocida se ATENÚA de verdad: tira y badge en gris neutro (el
  // rojo dormido no gasta presupuesto de color) y la traza dice el contrato
  // completo — reaparece si empeora, se reactiva en fecha cierta.
  const reconocimiento = alerta.reconocimiento
  const atendida = reconocimiento != null || (alerta.corte != null && alerta.corte.estado !== 'pendiente')
  const color = atendida ? SEMAFORO.neutro : colorSeveridad(alerta.severidad)
  return (
    <li className="group relative grid gap-3 px-4 py-4 pl-5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center sm:px-5 sm:pl-6">
      <span
        className="absolute inset-y-3 left-0 w-1 rounded-r-full"
        style={{ backgroundColor: color }}
        aria-hidden
      />
      {/* Se atenúa con COLOR (tira/badge/icono en gris), NUNCA con opacidad
          sobre el texto: opacity-75 tumbaba bajo 4.5:1 cuatro textos que ya
          iban justos (bloqueante del revisor a11y). El badge gris lleva el
          texto en --muted-foreground-strong: el neutro del semáforo es para
          tiras y puntos, no para texto de 11 px. */}
      <div className="flex min-w-0 items-start gap-3">
        <span className={`mt-0.5 grid size-9 shrink-0 place-items-center rounded-xl bg-muted text-primary transition-transform group-hover:scale-105 motion-reduce:transition-none${reconocimiento ? ' opacity-75' : ''}`}>
          <Icono className="size-4" aria-hidden />
        </span>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            {/* El outline pinta TEXTO y borde del `color`: el gris del badge
                reconocido es el strong (7.5:1), no el neutro del semáforo. */}
            <Badge
              color={atendida ? 'var(--muted-foreground-strong)' : color}
              variant="outline"
            >
              {alerta.corte?.estado === 'pospuesto' ? 'Pospuesta' : atendida
                ? 'Reconocida'
                : alerta.severidad === 'critica' ? 'Crítica' : 'Atención'}
            </Badge>
            <span className="text-[10px] font-bold uppercase tracking-[0.1em] text-muted-foreground">
              {alcance}
            </span>
          </div>
          <h2 className="mt-1.5 text-sm font-extrabold text-primary">{presentarCitas(alerta.titulo)}</h2>
          <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">
            {presentarCitas(alerta.detalle)}
          </p>
          {alerta.responsable && (
            <p className="mt-1 text-[11px] font-semibold text-foreground/70">
              Responsable: {alerta.responsable}
            </p>
          )}
          {reconocimiento && (
            <p className="mt-1 text-[11px] font-semibold text-muted-foreground-strong">
              La estás atendiendo · reaparece si empeora · se reactiva el {textoVencimiento(reconocimiento.venceEn)}
            </p>
          )}
        </div>
      </div>
      {alerta.contacto ? (
        <AccionesRevisarContacto alerta={alerta} />
      ) : (
        <div className="ml-12 flex flex-col items-start gap-2 sm:ml-0 sm:items-end">
          <a
            href={hashDe(alerta.destino.vista, alerta.destino.leadId)}
            onClick={() => {
              if (!alerta.destino.periodo) return
              setPeriodo(alerta.destino.periodo)
              setOrigenFiltrado(null)
            }}
            aria-label={`${alerta.destino.etiqueta}: ${presentarCitas(alerta.titulo)}`}
            className="inline-flex min-h-9 items-center justify-center rounded-lg border border-border bg-card px-3 text-xs font-bold text-primary outline-none transition-colors hover:border-border-strong hover:bg-muted focus-visible:ring-[3px] focus-visible:ring-ring/35 motion-reduce:transition-none"
          >
            {alerta.destino.etiqueta}
          </a>
          {alerta.corte && <AccionesCorte aviso={alerta.corte} />}
          {!alerta.corte && !reconocimiento && alerta.miembros != null && (
            <AccionesReconocerAlerta alerta={alerta} />
          )}
        </div>
      )}
    </li>
  )
}

export function Alertas(): JSX.Element {
  const { alertas, pospuestas, rol, cargando, errores, generadoEn, reintentar } = useAlertasCRM()
  const copy = copyRol(rol)
  const [prioridad, setPrioridad] = useState<FiltroPrioridad>('todas')
  const [tipo, setTipo] = useState<FiltroTipo>('todos')
  const [busqueda, setBusqueda] = useState('')

  // F4 (Codex #8): activas y reconocidas por SEPARADO. Los chips, los filtros
  // y el buscador operan solo sobre las activas — «Críticas 1» con «0
  // pendientes activos» era la pantalla contradiciéndose; las reconocidas
  // viven en su propia sección, siempre al final y sin filtrar.
  const activas = useMemo(
    () => alertas.filter((alerta) => alerta.reconocimiento == null && alerta.corte?.estado !== 'reconocido'),
    [alertas],
  )
  const reconocidas = useMemo(
    () => alertas.filter((alerta) => alerta.reconocimiento != null || alerta.corte?.estado === 'reconocido'),
    [alertas],
  )
  const tipos = useMemo(
    () => [...new Set(activas.map((alerta) => alerta.tipo))]
      .sort((a, b) => ETIQUETA_TIPO[a].localeCompare(ETIQUETA_TIPO[b], 'es-PE')),
    [activas],
  )
  const criticas = useMemo(
    () => activas.filter((alerta) => alerta.severidad === 'critica').length,
    [activas],
  )
  const filtradas = useMemo(() => {
    const texto = normalizar(busqueda.trim())
    return activas.filter((alerta) => {
      if (prioridad !== 'todas' && alerta.severidad !== prioridad) return false
      if (tipo !== 'todos' && alerta.tipo !== tipo) return false
      if (!texto) return true
      const copyVisible = presentarCitas(`${alerta.titulo} ${alerta.detalle}`)
      return normalizar(`${copyVisible} ${alerta.titulo} ${alerta.detalle} ${alerta.responsable ?? ''}`).includes(texto)
    })
  }, [activas, busqueda, prioridad, tipo])
  const hayFiltros = prioridad !== 'todas' || tipo !== 'todos' || busqueda.trim() !== ''
  // F4 (Codex #7): las pospuestas están OCULTAS pero no se niegan — el
  // contador y el vacío las dicen; sin esta línea, «Nada pendiente» afirmaría
  // algo falso mientras una excepción espera su fecha.
  const notaPospuestas = pospuestas > 0
    ? ` · ${pospuestas} ${pospuestas === 1 ? 'pospuesta' : 'pospuestas'} hasta su fecha`
    : ''
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

      {cargando && alertas.length === 0 && pospuestas === 0 ? (
        <CargaAlertas />
      ) : errores.length > 0 && alertas.length === 0 && pospuestas === 0 ? (
        <div className="rounded-2xl border border-border bg-card" role="alert">
          <PanelError mensaje={presentarCitas(errores.join(' '))} onReintentar={reintentar} reintentando={cargando} />
        </div>
      ) : alertas.length === 0 && pospuestas === 0 ? (
        <div className="rounded-2xl border border-border bg-card">
          <PanelVacio icono={CheckCircle2} titulo={rol === 'gerencia' ? 'Sin avisos generados' : 'Nada pendiente'} detalle={copy.vacio} />
        </div>
      ) : (
        <>
          {errores.length > 0 && (
            <div className="flex flex-wrap items-start justify-between gap-3 rounded-xl border border-warning/35 bg-warning/5 px-4 py-3" role="alert">
              <div className="flex min-w-0 items-start gap-2.5">
                <CircleAlert className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden />
                <div>
                  <p className="text-xs font-bold text-foreground">Información incompleta</p>
                  <p className="mt-0.5 text-[11px] text-muted-foreground">{presentarCitas(errores.join(' '))}</p>
                </div>
              </div>
              <Button type="button" variant="outline" size="sm" onClick={reintentar}>Reintentar</Button>
            </div>
          )}

          {activas.length > 0 && (
            <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
              <FiltrosPrioridad valor={prioridad} onCambiar={setPrioridad} total={activas.length} criticas={criticas} />
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
          )}

          <p
            id="alertas-contador"
            tabIndex={-1}
            className="px-1 text-xs font-semibold tabular-nums text-muted-foreground outline-none"
            role="status"
            aria-live="polite"
          >
            {filtradas.length} {filtradas.length === 1 ? 'pendiente activo' : 'pendientes activos'}
            {hayFiltros ? ` de ${activas.length}` : ''}
            {reconocidas.length > 0
              ? ` · ${reconocidas.length} ${reconocidas.length === 1 ? 'reconocida' : 'reconocidas'}`
              : ''}
            {notaPospuestas}
          </p>

          <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-[var(--shadow-card)]">
            {activas.length === 0 ? (
              <PanelVacio
                icono={CheckCircle2}
                titulo={rol === 'gerencia' ? 'Sin avisos activos' : 'Nada pendiente ahora'}
                detalle={`${copy.vacio}${notaPospuestas ? `${notaPospuestas}; reaparecerán solas.` : ''}`}
              />
            ) : filtradas.length === 0 ? (
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

          {reconocidas.length > 0 && (
            <section aria-label="Reconocidas" className="space-y-2">
              <h2 className="px-1 text-[11px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground-strong">
                Reconocidas — siguen vigilándose
              </h2>
              <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-[var(--shadow-card)]">
                <ol className="divide-y divide-border/70" aria-label="Alertas reconocidas">
                  {reconocidas.map((alerta) => (
                    <FilaAlerta key={alerta.id} alerta={alerta} alcance={copy.alcance} />
                  ))}
                </ol>
              </div>
            </section>
          )}
        </>
      )}
    </section>
  )
}
