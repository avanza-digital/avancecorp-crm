import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ArchiveRestore, ArrowLeft, ArrowRight, CalendarDays, ChevronRight,
  CircleAlert, ExternalLink, Filter, Folder, Layers3, RefreshCw, Search,
} from 'lucide-react'
import { toast } from 'sonner'
import {
  descartesRescateDelMes,
  mesesRescateDescartes,
  rescatarDescartes,
} from '@/data/crm-api'
import { useAuth } from '@/lib/auth-context'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import {
  MOTIVOS_DESCARTE,
  origenLabel,
  type EpisodioRescateDescarte,
  type MesRescateDescartes,
  type Miembro,
  type MotivoDescarte,
} from '@/lib/tipos'
import { fechaHora, moneyK } from '@/lib/format'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import {
  Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import { Select } from '@/components/ui/select'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { paginar } from '@/lib/paginacion'

const POR_PAGINA_CARPETA = 25
export const MAX_REPARTO_RESCATE = 100
const PARAM_CARPETA = 'rescate_carpeta'
const PARAM_MES = 'rescate_mes'

const TONO_MOTIVO: Record<MotivoDescarte, string> = {
  no_responde: '#2563eb',
  sin_interes: '#7c3aed',
  sin_fondos: '#c77b14',
  competencia: '#0f8c82',
  datos_invalidos: '#c1445f',
  pide_credito: '#b45309',
  otro: '#64748b',
}

type Filtro = 'todos' | 'recuperables' | MotivoDescarte
type FiltroCarpeta = 'todos' | 'recuperables' | 'rescatados' | 'historico'
type OrdenCarpeta = 'recientes' | 'antiguos' | 'asesor' | 'origen'
type ModoReparto = 'uno' | 'equilibrado'

function parametrosCarpetaDesdeUrl(): { carpeta: MotivoDescarte | null; mes: string | null } {
  const parametros = new URLSearchParams(window.location.search)
  const carpetaCruda = parametros.get(PARAM_CARPETA)
  const mesCrudo = parametros.get(PARAM_MES)
  const carpeta = MOTIVOS_DESCARTE.some((motivo) => motivo.k === carpetaCruda)
    ? carpetaCruda as MotivoDescarte
    : null
  const mes = /^\d{4}-\d{2}-01$/.test(mesCrudo ?? '') ? mesCrudo : null
  return { carpeta, mes }
}

function mesActualLima(): string {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit',
  }).formatToParts(new Date())
  const anio = partes.find((p) => p.type === 'year')?.value ?? '2026'
  const mes = partes.find((p) => p.type === 'month')?.value ?? '01'
  return [anio, mes, '01'].join('-')
}

function mesLimaDeFecha(valor: string): string {
  const fecha = new Date(valor)
  if (Number.isNaN(fecha.getTime())) return mesActualLima()
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit',
  }).formatToParts(fecha)
  const anio = partes.find((parte) => parte.type === 'year')?.value ?? '2026'
  const mes = partes.find((parte) => parte.type === 'month')?.value ?? '01'
  return `${anio}-${mes}-01`
}

function moverMes(mes: string, variacion: number): string {
  const [anio, numeroMes] = mes.split('-').map(Number)
  const fecha = new Date(Date.UTC(anio ?? 2026, (numeroMes ?? 1) - 1 + variacion, 1))
  return fecha.toISOString().slice(0, 10)
}

function etiquetaMes(mes: string): string {
  const [anio, numeroMes] = mes.split('-').map(Number)
  const fecha = new Date(Date.UTC(anio ?? 2026, (numeroMes ?? 1) - 1, 1))
  return fecha.toLocaleDateString('es-PE', { month: 'long', year: 'numeric', timeZone: 'UTC' })
}

function etiquetaMotivo(motivo: MotivoDescarte): string {
  return MOTIVOS_DESCARTE.find((item) => item.k === motivo)?.label ?? motivo
}

function construirMeses(meses: MesRescateDescartes[]): MesRescateDescartes[] {
  const porMes = new Map(meses.map((item) => [item.mes, item]))
  const actual = mesActualLima()
  const masAntiguo = meses.at(-1)?.mes ?? moverMes(actual, -3)
  const resultado: MesRescateDescartes[] = []
  for (let cursor = actual; cursor >= masAntiguo; cursor = moverMes(cursor, -1)) {
    resultado.push(porMes.get(cursor) ?? { mes: cursor, total: 0, pendientes: 0 })
  }
  return resultado
}

function EstadoEpisodio({ episodio }: { episodio: EpisodioRescateDescarte }) {
  if (episodio.puede_rescatar) return <Badge color="#0f8c82" dot>Pendiente de revisión</Badge>
  if (episodio.estado === 'rescatado') return <Badge color="#2563eb" dot>Ya reactivado</Badge>
  return <Badge color="#64748b">Solo historial</Badge>
}

function FilaEpisodio({
  episodio, seleccionado, onSeleccionar, onAbrir,
}: {
  episodio: EpisodioRescateDescarte
  seleccionado: boolean
  onSeleccionar: () => void
  onAbrir: () => void
}) {
  return (
    <tr className={cn('border-b border-border/70 last:border-0', seleccionado && 'bg-accent/5', !episodio.puede_rescatar && 'bg-muted/25')}>
      <td className="w-11 px-4 py-3 text-center">
        <input
          type="checkbox"
          checked={seleccionado}
          disabled={!episodio.puede_rescatar}
          onChange={onSeleccionar}
          aria-label={'Seleccionar ' + episodio.nombre_completo}
          className="size-4 accent-[var(--accent)]"
        />
      </td>
      <td className="min-w-[220px] px-3 py-3">
        <p className="font-semibold text-foreground">{episodio.nombre_completo}</p>
        <p className="mt-0.5 text-[11px] text-muted-foreground">{episodio.distrito || 'Distrito no registrado'}</p>
      </td>
      <td className="whitespace-nowrap px-3 py-3 text-[12px] text-muted-foreground">{episodio.asesor_nombre}</td>
      <td className="whitespace-nowrap px-3 py-3 text-[12px] text-muted-foreground">{origenLabel(episodio.origen)}</td>
      <td className="whitespace-nowrap px-3 py-3 text-right text-[12px] font-semibold text-foreground">{moneyK(episodio.monto_estimado, episodio.moneda)}</td>
      <td className="whitespace-nowrap px-3 py-3 text-[11px] text-muted-foreground">{fechaHora(episodio.descartado_en)}</td>
      <td className="whitespace-nowrap px-3 py-3"><EstadoEpisodio episodio={episodio} /></td>
      <td className="px-4 py-3 text-right">
        <button type="button" onClick={onAbrir} className="text-[11px] font-bold text-accent hover:underline">Ver ficha</button>
      </td>
    </tr>
  )
}

function DialogReparto({
  abierto, episodios, asesores, ocupado, onCerrar, onConfirmar,
}: {
  abierto: boolean
  episodios: EpisodioRescateDescarte[]
  asesores: Miembro[]
  ocupado: boolean
  onCerrar: () => void
  onConfirmar: (destinos: string[], evitarOrigen: boolean) => void
}) {
  const [modo, setModo] = useState<ModoReparto>('uno')
  const [destinoUnico, setDestinoUnico] = useState('')
  const [destinos, setDestinos] = useState<string[]>([])
  const [evitarOrigen, setEvitarOrigen] = useState(true)

  useEffect(() => {
    if (!abierto) return
    setModo('uno')
    setDestinoUnico('')
    setDestinos([])
    setEvitarOrigen(true)
  }, [abierto])

  const alternarDestino = (id: string) => {
    setDestinos((actual) => actual.includes(id)
      ? actual.filter((item) => item !== id)
      : [...actual, id])
  }

  const activos = modo === 'uno' ? (destinoUnico ? [destinoUnico] : []) : destinos
  const n = episodios.length

  return (
    <Dialog open={abierto} onClose={ocupado ? () => {} : onCerrar} ariaLabel="Reactivar y repartir descartes" className="w-[680px]">
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <ArchiveRestore className="size-4 text-accent" aria-hidden />
          Reactivar y repartir
        </DialogTitle>
        <DialogDescription>
          {n} {n === 1 ? 'lead conservará' : 'leads conservarán'} el descarte original y empezarán una gestión nueva en etapa Nuevo.
          {' '}Máximo {MAX_REPARTO_RESCATE} por operación.
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-4">
        <div className="rounded-xl border border-accent/20 bg-accent/5 p-3 text-xs text-muted-foreground">
          <span className="font-bold text-accent">{n} seleccionados</span>
          {' · '}
          el historial del mes y el asesor que descartó cada caso no se modifican.
        </div>
        <fieldset className="space-y-2">
          <legend className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Cómo repartir</legend>
          <label className={cn('flex cursor-pointer gap-3 rounded-lg border p-3', modo === 'uno' ? 'border-accent/40 bg-accent/5' : 'border-border')}>
            <input type="radio" name="modo-rescate" checked={modo === 'uno'} onChange={() => setModo('uno')} />
            <span>
              <span className="block text-sm font-semibold">Enviar a una persona</span>
              <span className="text-xs text-muted-foreground">Todo el bloque llega al asesor seleccionado.</span>
            </span>
          </label>
          <label className={cn('flex cursor-pointer gap-3 rounded-lg border p-3', modo === 'equilibrado' ? 'border-accent/40 bg-accent/5' : 'border-border')}>
            <input type="radio" name="modo-rescate" checked={modo === 'equilibrado'} onChange={() => setModo('equilibrado')} />
            <span>
              <span className="block text-sm font-semibold">Repartir equilibradamente</span>
              <span className="text-xs text-muted-foreground">El CRM alterna los leads entre los asesores elegidos.</span>
            </span>
          </label>
        </fieldset>
        {modo === 'uno' ? (
          <div>
            <label htmlFor="destino-rescate" className="mb-1.5 block text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Asesor destino</label>
            <Select id="destino-rescate" value={destinoUnico} onChange={(event) => setDestinoUnico(event.target.value)}>
              <option value="">Seleccionar asesor…</option>
              {asesores.map((asesor) => <option key={asesor.perfil_id} value={asesor.perfil_id}>{asesor.nombre_completo}</option>)}
            </Select>
          </div>
        ) : (
          <fieldset>
            <legend className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Asesores destino</legend>
            <div className="grid gap-2 sm:grid-cols-2">
              {asesores.map((asesor) => {
                const activo = destinos.includes(asesor.perfil_id)
                return (
                  <label key={asesor.perfil_id} className={cn('flex cursor-pointer items-center gap-2 rounded-lg border p-2.5 text-sm', activo ? 'border-accent/40 bg-accent/5' : 'border-border')}>
                    <input type="checkbox" checked={activo} onChange={() => alternarDestino(asesor.perfil_id)} />
                    <span className="font-semibold">{asesor.nombre_completo}</span>
                  </label>
                )
              })}
            </div>
          </fieldset>
        )}
        <label className="flex cursor-pointer items-start gap-2 text-xs text-muted-foreground">
          <input type="checkbox" checked={evitarOrigen} onChange={(event) => setEvitarOrigen(event.target.checked)} className="mt-0.5 accent-[var(--accent)]" />
          <span><span className="font-semibold text-foreground">No devolver al asesor que lo descartó.</span> Si no hay otra persona disponible para un caso, el CRM detendrá todo el reparto.</span>
        </label>
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" onClick={onCerrar} disabled={ocupado}>Cancelar</Button>
        <Button disabled={ocupado || activos.length === 0} onClick={() => onConfirmar(activos, evitarOrigen)}>
          <ArchiveRestore aria-hidden />
          {ocupado ? 'Reactivando…' : 'Reactivar ' + n + ' y repartir'}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}

export function RescateDescartados({ modoCarpeta = false }: { modoCarpeta?: boolean }) {
  const { yo } = useAuth()
  const { equipo, leads } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const parametrosRuta = useRef(modoCarpeta
    ? parametrosCarpetaDesdeUrl()
    : { carpeta: null, mes: null })
  const [mesesCrudos, setMesesCrudos] = useState<MesRescateDescartes[]>([])
  const [mesActivo, setMesActivo] = useState<string | null>(parametrosRuta.current.mes)
  const [inicioFranja, setInicioFranja] = useState(0)
  const [episodios, setEpisodios] = useState<EpisodioRescateDescarte[]>([])
  const [cargandoMeses, setCargandoMeses] = useState(true)
  const [cargandoEpisodios, setCargandoEpisodios] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [filtro, setFiltro] = useState<Filtro>('todos')
  const [carpetaActiva, setCarpetaActiva] = useState<MotivoDescarte | null>(parametrosRuta.current.carpeta)
  const [filtroCarpeta, setFiltroCarpeta] = useState<FiltroCarpeta>('todos')
  const [busquedaCarpeta, setBusquedaCarpeta] = useState('')
  const [ordenCarpeta, setOrdenCarpeta] = useState<OrdenCarpeta>('recientes')
  const [paginaCarpeta, setPaginaCarpeta] = useState(0)
  const [seleccionados, setSeleccionados] = useState<Set<string>>(() => new Set())
  const [dialogoAbierto, setDialogoAbierto] = useState(false)
  const [repartiendo, setRepartiendo] = useState(false)
  const abortMeses = useRef<AbortController | null>(null)
  const abortEpisodios = useRef<AbortController | null>(null)

  const episodiosDemo = useMemo<EpisodioRescateDescarte[]>(() => {
    if (!yo?.demo) return []
    const visibles = new Set(
      yo.rol === 'gerencia'
        ? equipo.filter((miembro) => miembro.rol_crm === 'vendedor').map((miembro) => miembro.perfil_id)
        : equipo.filter((miembro) => miembro.supervisor_id === yo.id).map((miembro) => miembro.perfil_id),
    )
    return leads
      .filter((lead) => lead.etapa === 'descartado' && lead.vendedor_id && visibles.has(lead.vendedor_id))
      .map((lead) => {
        const asesorId = lead.vendedor_id as string
        const asesor = equipo.find((miembro) => miembro.perfil_id === asesorId)
        const recuperable = lead.motivo_descarte !== 'datos_invalidos' && lead.no_contactar !== true
        return {
          episodio_id: `demo-rescate-${lead.id}`,
          lead_id: lead.id,
          nombre_completo: lead.nombre_completo,
          distrito: lead.distrito ?? null,
          origen: lead.origen,
          categoria_interes: lead.categoria_interes ?? null,
          monto_estimado: lead.monto_estimado,
          moneda: lead.moneda,
          motivo_descarte: lead.motivo_descarte ?? 'otro',
          descartado_en: lead.creado_en,
          asesor_id: asesorId,
          asesor_nombre: asesor?.nombre_completo ?? lead.vendedor_nombre ?? 'Asesor no disponible',
          puede_rescatar: recuperable,
          estado: recuperable ? 'pendiente' as const : 'historial' as const,
        }
      })
  }, [equipo, leads, yo])

  const meses = useMemo(() => construirMeses(mesesCrudos), [mesesCrudos])
  const mesMeta = useMemo(() => meses.find((item) => item.mes === mesActivo) ?? null, [mesActivo, meses])

  const cargarMeses = useCallback(async () => {
    abortMeses.current?.abort()
    const control = new AbortController()
    abortMeses.current = control
    setCargandoMeses(true)
    setError(null)
    try {
      const respuesta = yo?.demo
        ? Array.from(
            episodiosDemo.reduce((acumulado, episodio) => {
              const mes = mesLimaDeFecha(episodio.descartado_en)
              const actual = acumulado.get(mes) ?? { mes, total: 0, pendientes: 0 }
              actual.total += 1
              if (episodio.puede_rescatar) actual.pendientes += 1
              acumulado.set(mes, actual)
              return acumulado
            }, new Map<string, MesRescateDescartes>()).values(),
          ).sort((a, b) => b.mes.localeCompare(a.mes))
        : await mesesRescateDescartes(control.signal)
      if (control.signal.aborted) return
      setMesesCrudos(respuesta)
      setMesActivo((actual) => actual ?? respuesta[0]?.mes ?? mesActualLima())
    } catch (causa) {
      if (!control.signal.aborted) setError(causa instanceof Error ? causa.message : 'No se pudo cargar el historial de descartes.')
    } finally {
      if (!control.signal.aborted) setCargandoMeses(false)
    }
  }, [episodiosDemo, yo?.demo])

  const cargarEpisodios = useCallback(async (mes: string) => {
    abortEpisodios.current?.abort()
    const control = new AbortController()
    abortEpisodios.current = control
    setCargandoEpisodios(true)
    setError(null)
    try {
      const respuesta = yo?.demo
        ? episodiosDemo.filter((episodio) => mesLimaDeFecha(episodio.descartado_en) === mes)
        : await descartesRescateDelMes(mes, control.signal)
      if (!control.signal.aborted) setEpisodios(respuesta)
    } catch (causa) {
      if (!control.signal.aborted) setError(causa instanceof Error ? causa.message : 'No se pudo cargar este mes de descartes.')
    } finally {
      if (!control.signal.aborted) setCargandoEpisodios(false)
    }
  }, [episodiosDemo, yo?.demo])

  useEffect(() => {
    void cargarMeses()
    return () => abortMeses.current?.abort()
  }, [cargarMeses])

  useEffect(() => {
    if (!mesActivo) return
    setSeleccionados(new Set())
    setCarpetaActiva((actual) => (
      actual && parametrosRuta.current.mes === mesActivo ? actual : null
    ))
    setPaginaCarpeta(0)
    void cargarEpisodios(mesActivo)
  }, [cargarEpisodios, mesActivo])

  const cambiarMes = (mes: string) => {
    const indice = meses.findIndex((item) => item.mes === mes)
    const maximo = Math.max(0, meses.length - 4)
    if (indice >= 0) setInicioFranja(Math.min(Math.max(0, indice - 1), maximo))
    setMesActivo(mes)
  }

  const filtrados = useMemo(() => episodios.filter((episodio) => {
    if (filtro === 'todos') return true
    if (filtro === 'recuperables') return episodio.puede_rescatar
    return episodio.motivo_descarte === filtro
  }), [episodios, filtro])
  const grupos = useMemo(() => MOTIVOS_DESCARTE
    .map((motivo) => ({
      motivo: motivo.k,
      total: filtrados.filter((episodio) => episodio.motivo_descarte === motivo.k),
    }))
    .filter((grupo) => grupo.total.length > 0), [filtrados])
  const episodiosCarpeta = useMemo(() => carpetaActiva
    ? filtrados.filter((episodio) => episodio.motivo_descarte === carpetaActiva)
    : [], [carpetaActiva, filtrados])
  const episodiosCarpetaFiltrados = useMemo(() => {
    const busqueda = busquedaCarpeta.trim().toLocaleLowerCase('es-PE')
    const resultados = episodiosCarpeta.filter((episodio) => {
      if (filtroCarpeta === 'recuperables' && !episodio.puede_rescatar) return false
      if (filtroCarpeta === 'rescatados' && episodio.estado !== 'rescatado') return false
      if (filtroCarpeta === 'historico' && (episodio.puede_rescatar || episodio.estado === 'rescatado')) return false
      if (!busqueda) return true
      return [episodio.nombre_completo, episodio.asesor_nombre, episodio.distrito, origenLabel(episodio.origen)]
        .filter(Boolean)
        .join(' ')
        .toLocaleLowerCase('es-PE')
        .includes(busqueda)
    })
    return resultados.sort((a, b) => {
      if (ordenCarpeta === 'recientes') return b.descartado_en.localeCompare(a.descartado_en)
      if (ordenCarpeta === 'antiguos') return a.descartado_en.localeCompare(b.descartado_en)
      if (ordenCarpeta === 'asesor') return a.asesor_nombre.localeCompare(b.asesor_nombre, 'es-PE')
      return origenLabel(a.origen).localeCompare(origenLabel(b.origen), 'es-PE')
    })
  }, [busquedaCarpeta, episodiosCarpeta, filtroCarpeta, ordenCarpeta])
  const paginacionCarpeta = paginar(episodiosCarpetaFiltrados, paginaCarpeta, POR_PAGINA_CARPETA)
  const seleccionadosVisibles = useMemo(
    () => episodios.filter((episodio) => seleccionados.has(episodio.episodio_id)),
    [episodios, seleccionados],
  )
  const asesoresDestino = useMemo(() => equipo.filter((miembro) => (
    miembro.activo
    && miembro.rol_crm === 'vendedor'
    && (yo?.rol === 'gerencia' || miembro.supervisor_id === yo?.id)
  )), [equipo, yo?.id, yo?.rol])
  const franja = meses.slice(inicioFranja, inicioFranja + 4).reverse()
  const puedeIrAntiguos = inicioFranja + 4 < meses.length
  const puedeIrRecientes = inicioFranja > 0

  const cambiarFiltro = (siguiente: Filtro) => {
    setFiltro(siguiente)
    setCarpetaActiva(null)
    setPaginaCarpeta(0)
  }
  const abrirCarpeta = (motivo: MotivoDescarte) => {
    if (!mesActivo) return
    const url = new URL(window.location.href)
    url.searchParams.set(PARAM_CARPETA, motivo)
    url.searchParams.set(PARAM_MES, mesActivo)
    url.hash = '#/rescate-carpeta'
    const pestana = window.open(url.toString(), '_blank')
    if (!pestana) {
      toast.error('El navegador bloqueó la nueva pestaña. Permite ventanas emergentes para este CRM.')
      return
    }
    pestana.opener = null
  }
  const cerrarCarpeta = () => {
    const url = new URL(window.location.href)
    url.searchParams.delete(PARAM_CARPETA)
    url.searchParams.delete(PARAM_MES)
    url.hash = '#/rescate'
    window.location.assign(url.toString())
  }
  const alternarEpisodio = (episodio: EpisodioRescateDescarte) => {
    if (!episodio.puede_rescatar) return
    if (!seleccionados.has(episodio.episodio_id) && seleccionados.size >= MAX_REPARTO_RESCATE) {
      toast.error(`Puedes repartir como máximo ${MAX_REPARTO_RESCATE} leads por operación.`)
      return
    }
    setSeleccionados((actual) => {
      const nuevo = new Set(actual)
      if (nuevo.has(episodio.episodio_id)) nuevo.delete(episodio.episodio_id)
      else if (nuevo.size < MAX_REPARTO_RESCATE) nuevo.add(episodio.episodio_id)
      return nuevo
    })
  }
  const agregarSeleccion = (candidatos: EpisodioRescateDescarte[]) => {
    const nuevo = new Set(seleccionados)
    let omitidos = 0
    for (const episodio of candidatos) {
      if (!episodio.puede_rescatar || nuevo.has(episodio.episodio_id)) continue
      if (nuevo.size >= MAX_REPARTO_RESCATE) {
        omitidos += 1
        continue
      }
      nuevo.add(episodio.episodio_id)
    }
    setSeleccionados(nuevo)
    if (omitidos > 0) {
      toast.error(
        `Se seleccionaron ${MAX_REPARTO_RESCATE}. Reparte ese bloque antes de elegir los restantes.`,
      )
    }
  }
  const seleccionarCarpeta = () => agregarSeleccion(episodiosCarpetaFiltrados)
  const seleccionarPaginaCarpeta = () => agregarSeleccion(paginacionCarpeta.visibles)
  const confirmarRescate = async (destinos: string[], evitarOrigen: boolean) => {
    if (seleccionadosVisibles.length === 0) return
    setRepartiendo(true)
    try {
      if (yo?.demo) {
        const ids = new Set(seleccionadosVisibles.map((episodio) => episodio.episodio_id))
        const total = ids.size
        setEpisodios((actuales) => actuales.map((episodio) => ids.has(episodio.episodio_id)
          ? { ...episodio, puede_rescatar: false, estado: 'rescatado' }
          : episodio))
        setMesesCrudos((actuales) => actuales.map((mes) => mes.mes === mesActivo
          ? { ...mes, pendientes: Math.max(0, mes.pendientes - total) }
          : mes))
        setSeleccionados(new Set())
        setDialogoAbierto(false)
        toast.success(`${total}${total === 1 ? ' lead reactivado y repartido' : ' leads reactivados y repartidos'} (demo)`)
        return
      }
      await rescatarDescartes(
        seleccionadosVisibles.map((episodio) => episodio.episodio_id),
        destinos,
        evitarOrigen,
      )
      const total = seleccionadosVisibles.length
      setSeleccionados(new Set())
      setDialogoAbierto(false)
      toast.success(total + (total === 1 ? ' lead reactivado y repartido' : ' leads reactivados y repartidos'))
      await Promise.all([
        cargarMeses(),
        mesActivo ? cargarEpisodios(mesActivo) : Promise.resolve(),
      ])
    } catch (causa) {
      toast.error(causa instanceof Error ? causa.message : 'No se pudo completar el reparto.')
    } finally {
      setRepartiendo(false)
    }
  }
  const reintentar = () => {
    void cargarMeses()
    if (mesActivo) void cargarEpisodios(mesActivo)
  }

  if (cargandoMeses && mesesCrudos.length === 0) {
    return <Card className="mx-auto max-w-[1240px]"><PanelCargando filas={8} /></Card>
  }
  if (error && mesesCrudos.length === 0) {
    return <Card className="mx-auto max-w-[1240px]"><PanelError mensaje={error} onReintentar={reintentar} reintentando={cargandoMeses} /></Card>
  }

  if (modoCarpeta && !carpetaActiva) {
    return (
      <Card className="mx-auto max-w-[720px]">
        <PanelVacio
          icono={Folder}
          titulo="Esta carpeta no es válida"
          detalle="Vuelve a Base para gestión y abre una carpeta desde el mosaico."
        />
        <div className="flex justify-center border-t border-border p-4">
          <Button onClick={cerrarCarpeta}>Ir a Base para gestión</Button>
        </div>
      </Card>
    )
  }

  if (carpetaActiva) {
    const etiqueta = etiquetaMotivo(carpetaActiva)
    const tono = TONO_MOTIVO[carpetaActiva]
    const recuperables = episodiosCarpeta.filter((episodio) => episodio.puede_rescatar).length
    const rescatados = episodiosCarpeta.filter((episodio) => episodio.estado === 'rescatado').length
    const soloHistorial = episodiosCarpeta.length - recuperables - rescatados
    const recuperablesFiltrados = episodiosCarpetaFiltrados.filter((episodio) => episodio.puede_rescatar).length
    const recuperablesPagina = paginacionCarpeta.visibles.filter((episodio) => episodio.puede_rescatar).length
    return (
      <div className="mx-auto max-w-[1240px] space-y-4">
        <button type="button" onClick={cerrarCarpeta} className="inline-flex items-center gap-1.5 text-xs font-bold text-muted-foreground hover:text-accent">
          <ArrowLeft className="size-3.5" aria-hidden /> Ir a Base para gestión
        </button>

        <section className="relative mt-2 pt-4">
          <div
            aria-hidden
            className="absolute left-4 top-0 h-7 w-48 rounded-t-xl rounded-br-lg border border-b-0"
            style={{ backgroundColor: tono + '1f', borderColor: tono + '55' }}
          />
          <header className="relative overflow-hidden rounded-2xl rounded-tl-md border border-border bg-card shadow-[var(--shadow-card)]">
            <div className="flex flex-col gap-4 px-5 py-5 sm:flex-row sm:items-center sm:justify-between sm:px-6" style={{ backgroundColor: tono + '0d' }}>
              <div className="flex min-w-0 items-center gap-3">
                <Folder className="size-8 shrink-0" style={{ color: tono }} aria-hidden />
                <div className="min-w-0">
                  <p className="text-[10px] font-bold uppercase tracking-[0.13em] text-muted-foreground">Carpeta de descartes · {mesActivo ? etiquetaMes(mesActivo) : '—'}</p>
                  <h1 className="mt-1 truncate text-2xl font-extrabold tracking-[-0.035em] text-primary">{etiqueta}</h1>
                  <p className="mt-1 text-sm text-muted-foreground">{episodiosCarpeta.length} leads guardados · {recuperables} recuperables para una nueva gestión</p>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                <div className="min-w-[92px] rounded-xl border border-border bg-card/85 px-3 py-2">
                  <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Registros</p>
                  <p className="mt-0.5 text-lg font-extrabold tabular-nums">{episodiosCarpeta.length}</p>
                </div>
                <div className="min-w-[104px] rounded-xl border px-3 py-2" style={{ borderColor: tono + '55', backgroundColor: tono + '12' }}>
                  <p className="text-[10px] font-bold uppercase tracking-wide" style={{ color: tono }}>Recuperables</p>
                  <p className="mt-0.5 text-lg font-extrabold tabular-nums" style={{ color: tono }}>{recuperables}</p>
                </div>
                <div className="min-w-[92px] rounded-xl border border-border bg-card/85 px-3 py-2">
                  <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Repartidos</p>
                  <p className="mt-0.5 text-lg font-extrabold tabular-nums">{rescatados}</p>
                </div>
                {soloHistorial > 0 && <div className="min-w-[92px] rounded-xl border border-border bg-card/85 px-3 py-2">
                  <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Historial</p>
                  <p className="mt-0.5 text-lg font-extrabold tabular-nums">{soloHistorial}</p>
                </div>}
              </div>
            </div>
          </header>
        </section>

        <Card className="overflow-hidden">
          <div className="flex flex-col gap-3 border-b border-border px-5 py-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between">
            <div className="flex min-w-0 flex-1 flex-col gap-2 sm:flex-row sm:items-center">
              <div className="relative min-w-0 flex-1 sm:max-w-[300px]">
                <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
                <input
                  value={busquedaCarpeta}
                  onChange={(event) => { setBusquedaCarpeta(event.target.value); setPaginaCarpeta(0) }}
                  aria-label="Buscar en la carpeta"
                  placeholder="Buscar lead, asesor, distrito u origen"
                  className="h-9 w-full rounded-lg border border-border bg-card pl-9 pr-3 text-xs outline-none placeholder:text-muted-foreground focus:border-accent focus:ring-2 focus:ring-accent/15"
                />
              </div>
              <div className="flex flex-wrap gap-1.5">
                {([['todos', 'Todos'], ['recuperables', 'Para repartir'], ['rescatados', 'Ya repartidos'], ['historico', 'Solo historial']] as const).map(([valor, titulo]) => (
                  <button
                    key={valor}
                    type="button"
                    onClick={() => { setFiltroCarpeta(valor); setPaginaCarpeta(0) }}
                    className={cn('rounded-full border px-2.5 py-1 text-[11px] font-bold', filtroCarpeta === valor ? 'border-accent/30 bg-accent/10 text-accent' : 'border-border text-muted-foreground hover:text-foreground')}
                  >
                    {titulo}
                  </button>
                ))}
              </div>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs font-semibold tabular-nums text-muted-foreground">{episodiosCarpetaFiltrados.length} resultados</span>
              <Select
                aria-label="Ordenar resultados de la carpeta"
                value={ordenCarpeta}
                onChange={(event) => { setOrdenCarpeta(event.target.value as OrdenCarpeta); setPaginaCarpeta(0) }}
                className="h-9 w-[178px] text-xs"
              >
                <option value="recientes">Más recientes</option>
                <option value="antiguos">Más antiguos</option>
                <option value="asesor">Asesor que descartó</option>
                <option value="origen">Origen del lead</option>
              </Select>
            </div>
          </div>

          <div className="flex flex-col gap-2 border-b border-border bg-muted/15 px-5 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-6">
            <p className="text-xs text-muted-foreground">Elige el bloque y luego reparte. Máximo {MAX_REPARTO_RESCATE} por operación; el historial no cambia.</p>
            <div className="flex flex-wrap gap-2">
              {recuperablesPagina > 0 && <Button size="sm" variant="outline" onClick={seleccionarPaginaCarpeta}>Seleccionar esta página ({recuperablesPagina})</Button>}
              {recuperablesFiltrados > recuperablesPagina && <Button size="sm" variant="outline" onClick={seleccionarCarpeta}>Seleccionar hasta {Math.min(MAX_REPARTO_RESCATE, recuperablesFiltrados)} del filtro</Button>}
            </div>
          </div>

          {seleccionados.size > 0 && (
            <div className="flex flex-col gap-2 border-b border-primary/15 bg-primary px-5 py-3 text-primary-foreground sm:flex-row sm:items-center sm:px-6">
              <span className="text-lg font-extrabold tabular-nums text-accent">{seleccionados.size}</span>
              <span className="flex-1 text-xs font-semibold">de {MAX_REPARTO_RESCATE} leads máximos para revisar y repartir</span>
              <button type="button" className="text-left text-xs font-bold text-primary-foreground/75 hover:text-primary-foreground" onClick={() => setSeleccionados(new Set())}>Limpiar</button>
              <Button size="sm" className="bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => setDialogoAbierto(true)}>
                Reactivar y repartir <ChevronRight aria-hidden />
              </Button>
            </div>
          )}

          {episodiosCarpetaFiltrados.length === 0 ? (
            <PanelVacio icono={Search} titulo="No hay coincidencias en esta carpeta" detalle="Cambia el filtro o ajusta la búsqueda para encontrar otro lead." />
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full min-w-[940px] text-left">
                  <thead className="border-b border-border bg-muted/25 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                    <tr>
                      <th className="w-11 px-4 py-3 text-center"><span className="sr-only">Seleccionar</span></th>
                      <th className="px-3 py-3">Lead</th>
                      <th className="px-3 py-3">Descartó</th>
                      <th className="px-3 py-3">Origen</th>
                      <th className="px-3 py-3 text-right">Capital</th>
                      <th className="px-3 py-3">Fecha</th>
                      <th className="px-3 py-3">Estado</th>
                      <th className="px-4 py-3 text-right">Detalle</th>
                    </tr>
                  </thead>
                  <tbody>
                    {paginacionCarpeta.visibles.map((episodio) => (
                      <FilaEpisodio
                        key={episodio.episodio_id}
                        episodio={episodio}
                        seleccionado={seleccionados.has(episodio.episodio_id)}
                        onSeleccionar={() => alternarEpisodio(episodio)}
                        onAbrir={() => abrirLead(episodio.lead_id)}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="border-t border-border px-4 py-3 sm:px-5">
                <Paginacion
                  paginaActual={paginacionCarpeta.paginaActual}
                  paginas={paginacionCarpeta.paginas}
                  total={episodiosCarpetaFiltrados.length}
                  onCambio={setPaginaCarpeta}
                  ariaLabel="Paginación de la carpeta"
                />
              </div>
            </>
          )}
        </Card>

        <DialogReparto
          abierto={dialogoAbierto}
          episodios={seleccionadosVisibles}
          asesores={asesoresDestino}
          ocupado={repartiendo}
          onCerrar={() => setDialogoAbierto(false)}
          onConfirmar={(destinos, evitarOrigen) => { void confirmarRescate(destinos, evitarOrigen) }}
        />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-[1240px] space-y-4">
      <header className="flex flex-col gap-4 rounded-2xl border border-border bg-card px-5 py-5 shadow-[var(--shadow-card)] sm:px-6 lg:flex-row lg:items-end lg:justify-between">
        <div className="max-w-2xl">
          <div className="mb-2 flex items-center gap-2 text-[11px] font-bold uppercase tracking-[0.13em] text-accent">
            <ArchiveRestore className="size-3.5" aria-hidden />
            Supervisión de cartera
          </div>
          <h1 className="text-[26px] font-extrabold tracking-[-0.035em] text-primary">Base para gestión</h1>
          <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">
            Revisa los descartes de tu equipo, identifica oportunidades recuperables y reparte bloques sin borrar su historial.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div className="rounded-xl border border-border bg-muted/35 px-3 py-2.5">
            <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">En el mes</p>
            <p className="mt-0.5 text-lg font-extrabold tabular-nums">{mesMeta?.total ?? 0}</p>
          </div>
          <div className="rounded-xl border border-accent/20 bg-accent/5 px-3 py-2.5">
            <p className="text-[10px] font-bold uppercase tracking-wide text-accent">Por revisar</p>
            <p className="mt-0.5 text-lg font-extrabold tabular-nums text-accent">{mesMeta?.pendientes ?? 0}</p>
          </div>
        </div>
      </header>

      <Card className="overflow-hidden">
        <div className="flex flex-col gap-3 border-b border-border px-5 py-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-muted-foreground">Historial de gestión</p>
            <p className="mt-0.5 text-sm font-bold">Mostrando descartes de: {mesActivo ? etiquetaMes(mesActivo) : '—'}</p>
            <p className="mt-1 text-xs text-muted-foreground">El mes corresponde al día en que el asesor descartó el lead.</p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button size="icon" variant="outline" aria-label="Ver cuatro meses más recientes" disabled={!puedeIrRecientes} onClick={() => {
              const siguiente = Math.max(0, inicioFranja - 4)
              setInicioFranja(siguiente)
              setMesActivo(meses[siguiente]?.mes ?? mesActivo)
            }}>
              <ArrowLeft aria-hidden />
            </Button>
            <Button size="icon" variant="outline" aria-label="Ver cuatro meses anteriores" disabled={!puedeIrAntiguos} onClick={() => {
              const siguiente = Math.min(Math.max(0, meses.length - 4), inicioFranja + 4)
              setInicioFranja(siguiente)
              setMesActivo(meses[siguiente]?.mes ?? mesActivo)
            }}>
              <ArrowRight aria-hidden />
            </Button>
            <Select aria-label="Ir a un mes del historial" value={mesActivo ?? ''} onChange={(event) => cambiarMes(event.target.value)} className="w-[175px]">
              {meses.map((mes) => <option key={mes.mes} value={mes.mes}>{etiquetaMes(mes.mes)}</option>)}
            </Select>
          </div>
        </div>
        <div className="grid gap-2 overflow-x-auto p-4 sm:grid-cols-2 lg:grid-cols-4">
          {franja.map((mes) => {
            const activo = mes.mes === mesActivo
            return (
              <button
                key={mes.mes}
                type="button"
                aria-pressed={activo}
                onClick={() => cambiarMes(mes.mes)}
                className={cn(
                  'group relative min-w-[190px] rounded-xl border p-3 text-left transition-colors',
                  activo ? 'border-accent/45 bg-accent/5 shadow-sm' : 'border-border bg-card hover:border-accent/30',
                )}
              >
                <span className={cn('absolute left-3 top-0 h-0.5 w-12 rounded-full', activo ? 'bg-accent' : 'bg-border')} />
                <div className="flex items-start justify-between gap-3">
                  <span className={cn('grid size-8 place-items-center rounded-full text-[10px] font-extrabold uppercase', activo ? 'bg-accent text-accent-foreground' : 'bg-muted text-muted-foreground')}>
                    {etiquetaMes(mes.mes).slice(0, 3)}
                  </span>
                  <span className={cn('text-xl font-extrabold tabular-nums', activo ? 'text-accent' : 'text-foreground')}>{mes.total}</span>
                </div>
                <p className="mt-3 text-[11px] font-bold capitalize">{etiquetaMes(mes.mes)}</p>
                <p className="mt-0.5 text-[11px] text-muted-foreground">{mes.pendientes} por revisar</p>
              </button>
            )
          })}
        </div>
      </Card>

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_260px]">
        <Card className="min-w-0 overflow-hidden">
          <div className="flex flex-col gap-3 border-b border-border px-5 py-4 sm:px-6">
            <div className="flex flex-wrap items-center gap-2">
              <Filter className="size-4 text-muted-foreground" aria-hidden />
              <div className="flex flex-wrap gap-1.5">
                <button type="button" onClick={() => cambiarFiltro('todos')} className={cn('rounded-full border px-2.5 py-1 text-[11px] font-bold', filtro === 'todos' ? 'border-accent/30 bg-accent/10 text-accent' : 'border-border text-muted-foreground hover:text-foreground')}>Todos</button>
                <button type="button" onClick={() => cambiarFiltro('recuperables')} className={cn('rounded-full border px-2.5 py-1 text-[11px] font-bold', filtro === 'recuperables' ? 'border-accent/30 bg-accent/10 text-accent' : 'border-border text-muted-foreground hover:text-foreground')}>Recuperables</button>
                {MOTIVOS_DESCARTE.map((motivo) => (
                  <button key={motivo.k} type="button" onClick={() => cambiarFiltro(motivo.k)} className={cn('rounded-full border px-2.5 py-1 text-[11px] font-bold', filtro === motivo.k ? 'border-accent/30 bg-accent/10 text-accent' : 'border-border text-muted-foreground hover:text-foreground')}>
                    {motivo.label}
                  </button>
                ))}
              </div>
            </div>
            {seleccionados.size > 0 && (
              <div className="flex flex-col gap-2 rounded-xl border border-primary/15 bg-primary px-3 py-2.5 text-primary-foreground sm:flex-row sm:items-center">
                <span className="text-lg font-extrabold tabular-nums text-accent">{seleccionados.size}</span>
                <span className="flex-1 text-xs font-semibold">de {MAX_REPARTO_RESCATE} leads máximos para revisar y repartir</span>
                <button type="button" className="text-left text-xs font-bold text-primary-foreground/75 hover:text-primary-foreground" onClick={() => setSeleccionados(new Set())}>Limpiar</button>
                <Button size="sm" className="bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => setDialogoAbierto(true)}>
                  Reactivar y repartir <ChevronRight aria-hidden />
                </Button>
              </div>
            )}
          </div>
          {cargandoEpisodios ? (
            <PanelCargando filas={6} />
          ) : error ? (
            <PanelError mensaje={error} onReintentar={reintentar} reintentando={cargandoEpisodios} />
          ) : episodios.length === 0 ? (
            <PanelVacio icono={CalendarDays} titulo="No hubo descartes este mes" detalle="Selecciona otro mes en el historial para revisar los descartes de tu equipo." />
          ) : (
            <div className="grid gap-3 p-4 sm:grid-cols-2 sm:p-5 xl:grid-cols-3">
              {grupos.map((grupo) => {
                const recuperables = grupo.total.filter((episodio) => episodio.puede_rescatar).length
                const etiqueta = etiquetaMotivo(grupo.motivo)
                return (
                  <section key={grupo.motivo} className="relative mt-2 self-start pt-3">
                    <div
                      aria-hidden
                      className="absolute left-3 top-0 h-5 w-36 rounded-t-lg rounded-br-md border border-b-0"
                      style={{
                        backgroundColor: TONO_MOTIVO[grupo.motivo] + '1f',
                        borderColor: TONO_MOTIVO[grupo.motivo] + '55',
                      }}
                    />
                    <div className="relative overflow-hidden rounded-xl rounded-tl-sm border border-border bg-card shadow-sm">
                      <header
                        className="flex min-h-[82px] flex-col items-stretch gap-3 px-3 py-3"
                        style={{ backgroundColor: TONO_MOTIVO[grupo.motivo] + '0d' }}
                      >
                        <button
                          type="button"
                          onClick={() => abrirCarpeta(grupo.motivo)}
                          aria-label={'Abrir carpeta ' + etiqueta}
                          className="flex min-w-0 items-center gap-2.5 text-left"
                        >
                          <Folder className="size-5 shrink-0" style={{ color: TONO_MOTIVO[grupo.motivo] }} aria-hidden />
                          <span className="min-w-0">
                            <span className="block truncate text-[13px] font-bold">{etiqueta}</span>
                            <span className="block text-[11px] text-muted-foreground">{grupo.total.length} en el filtro · {recuperables} recuperables</span>
                          </span>
                        </button>
                        <button type="button" onClick={() => abrirCarpeta(grupo.motivo)} className="inline-flex items-center justify-between rounded-lg border border-border bg-card px-2.5 py-1.5 text-[11px] font-bold text-accent shadow-sm hover:bg-accent/5">
                          Abrir en otra pestaña <ExternalLink className="size-3.5" aria-hidden />
                        </button>
                      </header>
                    </div>
                  </section>
                )
              })}
            </div>
          )}
        </Card>

        <aside className="space-y-4">
          <Card className="p-4">
            <div className="flex items-center gap-2 text-accent">
              <Layers3 className="size-4" aria-hidden />
              <h2 className="text-sm font-bold text-foreground">Lectura rápida</h2>
            </div>
            <div className="mt-3 space-y-3 text-xs leading-relaxed text-muted-foreground">
              <p><span className="font-bold text-foreground">Pendiente de revisión</span> sigue descartado y puede volver a la cartera.</p>
              <p><span className="font-bold text-foreground">Ya reactivado</span> queda como evidencia del mes, sin duplicar el trabajo.</p>
              <p><span className="font-bold text-foreground">Datos inválidos</span> se conserva en historial pero no se reparte hasta corregirlo.</p>
            </div>
          </Card>
          <Card className="border-warning/25 bg-warning/5 p-4">
            <div className="flex gap-2">
              <CircleAlert className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden />
              <div>
                <h2 className="text-sm font-bold">Trazabilidad intacta</h2>
                <p className="mt-1 text-xs leading-relaxed text-muted-foreground">Al reactivar, el descarte conserva su fecha, motivo y asesor origen. El nuevo reparto inicia otro ciclo de gestión.</p>
              </div>
            </div>
          </Card>
          <Button variant="outline" className="w-full" onClick={reintentar} disabled={cargandoMeses || cargandoEpisodios}>
            <RefreshCw aria-hidden /> Actualizar historial
          </Button>
        </aside>
      </div>

      <DialogReparto
        abierto={dialogoAbierto}
        episodios={seleccionadosVisibles}
        asesores={asesoresDestino}
        ocupado={repartiendo}
        onCerrar={() => setDialogoAbierto(false)}
        onConfirmar={(destinos, evitarOrigen) => { void confirmarRescate(destinos, evitarOrigen) }}
      />
    </div>
  )
}
