import { ConfiguracionSlaOperativa } from '@/components/app/configuracion-sla-operativa'
import { useEffect, useMemo, useState } from 'react'
import { Clock, RefreshCw, Save, ShieldCheck } from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { useConfiguracionSla, useMetricasSla, usePublicarPoliticaSla } from '@/data/crm-config-queries'
import { CrmApiError, mensajeDeError } from '@/data/crm-api'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  ETAPAS_SLA,
  minutosLegibles,
  type ConfiguracionSla,
  type PublicacionSla,
} from '@/lib/sla-versionado'

const ETIQUETA_ETAPA = {
  nuevo: 'Lead nuevo',
  contactado: 'Contactado',
  reunion_agendada: 'Cita agendada',
  propuesta_enviada: 'Entrevista realizada',
} as const

function fechaCorta(valor: string): string {
  if (valor === '-infinity') return 'Desde el inicio del historial'
  const fecha = new Date(valor)
  if (!Number.isFinite(fecha.getTime())) return 'Vigencia histórica'
  return new Intl.DateTimeFormat('es-PE', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'America/Lima',
  }).format(fecha)
}

function inicioMes(fecha: string): string {
  return `${fecha.slice(0, 7)}-01`
}

function payload(config: ConfiguracionSla): PublicacionSla {
  return {
    zona_horaria: config.politica.zona_horaria,
    tipo_reloj: config.politica.tipo_reloj,
    primera_gestion_minutos: config.politica.primera_gestion_minutos,
    primer_contacto_minutos: config.politica.primer_contacto_minutos,
    etapas: config.politica.etapas.map((regla) => ({ ...regla })),
  }
}

function validar(config: PublicacionSla): string | null {
  if (!Number.isInteger(config.primera_gestion_minutos)
    || config.primera_gestion_minutos < 1
    || config.primera_gestion_minutos > 43_200) {
    return 'La primera gestión debe ser mayor a cero y no superar 30 días.'
  }
  if (!Number.isInteger(config.primer_contacto_minutos)
    || config.primer_contacto_minutos < config.primera_gestion_minutos
    || config.primer_contacto_minutos > 43_200) {
    return 'El primer contacto debe ser igual o posterior a la primera gestión y no superar 30 días.'
  }
  if (config.etapas.length !== ETAPAS_SLA.length) return 'Deben definirse las cuatro etapas.'
  for (const regla of config.etapas) {
    if (!Number.isInteger(regla.maximo_minutos)
      || regla.maximo_minutos < 1
      || regla.maximo_minutos > 43_200) {
      return `El plazo de ${ETIQUETA_ETAPA[regla.etapa]} está fuera del rango permitido.`
    }
  }
  return null
}

type UnidadDuracion = 'horas' | 'dias'

const MINUTOS_POR_UNIDAD: Record<UnidadDuracion, number> = {
  horas: 60,
  dias: 1_440,
}

function CampoDuracion({
  id,
  etiqueta,
  valor,
  unidadInicial,
  ayuda,
  disabled,
  onChange,
}: {
  id: string
  etiqueta: string
  valor: number
  unidadInicial: UnidadDuracion
  ayuda: string
  disabled: boolean
  onChange: (valor: number) => void
}) {
  const [unidad, setUnidad] = useState<UnidadDuracion>(unidadInicial)
  const factor = MINUTOS_POR_UNIDAD[unidad]
  const valorVisible = Number((valor / factor).toFixed(4))
  return (
    <div>
      <Label htmlFor={id}>{etiqueta}</Label>
      <div className="mt-1.5 grid grid-cols-[minmax(0,1fr)_7.5rem] items-center gap-2">
        <Input
          id={id}
          type="number"
          inputMode="decimal"
          min={0.5}
          max={43_200 / factor}
          step={0.5}
          value={valorVisible}
          disabled={disabled}
          onChange={(evento) => onChange(Math.round(Number(evento.target.value || 0) * factor))}
          className="h-11 text-base font-bold tabular-nums"
        />
        <Select
          aria-label={`Unidad de ${etiqueta}`}
          value={unidad}
          disabled={disabled}
          onChange={(evento) => setUnidad(evento.target.value as UnidadDuracion)}
          className="h-11 font-semibold"
        >
          <option value="horas">Horas</option>
          <option value="dias">Días</option>
        </Select>
      </div>
      <p className="mt-1.5 text-[11px] leading-relaxed text-muted-foreground">{ayuda}</p>
    </div>
  )
}

function Cumplimiento({
  titulo,
  grupos,
}: {
  titulo: string
  grupos: Array<{
    politica_id: string
    politica_version: number
    objetivo_minutos: number
    total: number
    evaluables: number
    cumplidos: number
    fuera_objetivo: number
    pendientes: number
  }>
}) {
  return (
    <div className="rounded-xl border border-border bg-background/70 p-3">
      <p className="text-xs font-extrabold text-primary">{titulo}</p>
      {grupos.length === 0 ? (
        <p className="mt-2 text-[11px] text-muted-foreground">Sin casos en el período.</p>
      ) : (
        <div className="mt-3 space-y-3">
          {grupos.map((grupo) => {
            const porcentaje = grupo.evaluables > 0
              ? Math.round((grupo.cumplidos / grupo.evaluables) * 100)
              : null
            return (
              <div key={grupo.politica_id}>
                <div className="flex items-center justify-between gap-3 text-[11px]">
                  <span className="font-semibold text-foreground">v{grupo.politica_version} · {minutosLegibles(grupo.objetivo_minutos)}</span>
                  <span className="font-extrabold tabular-nums text-primary">{porcentaje == null ? 'Sin evaluables' : `${porcentaje}%`}</span>
                </div>
                <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-muted">
                  <div className="h-full rounded-full bg-accent" style={{ width: `${porcentaje ?? 0}%` }} />
                </div>
                <p className="mt-1 text-[10px] text-muted-foreground">
                  {grupo.cumplidos} cumplidos · {grupo.fuera_objetivo} fuera · {grupo.pendientes} pendientes
                </p>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

export function ConfigSla() {
  const hoy = fechaLima(Date.now())
  const [desde, setDesde] = useState(() => inicioMes(hoy))
  const [hasta, setHasta] = useState(hoy)
  const consulta = useConfiguracionSla()
  const metricas = useMetricasSla(desde, hasta)
  const publicar = usePublicarPoliticaSla()
  const [borrador, setBorrador] = useState<PublicacionSla | null>(null)
  const [confirmando, setConfirmando] = useState(false)
  const [vigenciaLocal, setVigenciaLocal] = useState('')

  useEffect(() => {
    if (consulta.data) setBorrador(payload(consulta.data))
  }, [consulta.data])

  const dirty = Boolean(consulta.data && borrador
    && JSON.stringify(payload(consulta.data)) !== JSON.stringify(borrador))
  const editable = Boolean(consulta.data?.puede_editar)

  const actualizar = (patch: Partial<PublicacionSla>) => {
    setBorrador((actual) => actual ? { ...actual, ...patch } : actual)
  }

  const actualizarEtapa = (etapa: (typeof ETAPAS_SLA)[number], valor: number) => {
    setBorrador((actual) => actual ? {
      ...actual,
      etapas: actual.etapas.map((regla) => regla.etapa === etapa
        ? { ...regla, maximo_minutos: valor }
        : regla),
    } : actual)
  }

  const prepararPublicacion = () => {
    if (!borrador) return
    const error = validar(borrador)
    if (error) {
      toast.error(error)
      return
    }
    if (vigenciaLocal) {
      const fecha = new Date(vigenciaLocal)
      if (!Number.isFinite(fecha.getTime()) || fecha.getTime() < Date.now() - 30_000) {
        toast.error('La vigencia programada debe iniciar ahora o en el futuro.')
        return
      }
    }
    setConfirmando(true)
  }

  const confirmarPublicacion = async () => {
    if (!borrador || !consulta.data) return
    try {
      await publicar.mutateAsync({
        expectedVersion: consulta.data.expected_version,
        vigenteDesde: vigenciaLocal ? new Date(vigenciaLocal).toISOString() : null,
        config: borrador,
      })
      setConfirmando(false)
      setVigenciaLocal('')
      toast.success(`Política SLA v${consulta.data.expected_version + 1} publicada.`)
    } catch (error) {
      if (error instanceof CrmApiError && error.code === 'CONFLICTO_CONFIG') setConfirmando(false)
      toast.error(mensajeDeError(error, 'No se pudo publicar la política SLA.'))
    }
  }

  const gruposEtapa = useMemo(() => {
    const mapa = new Map(ETAPAS_SLA.map((etapa) => [etapa, [] as NonNullable<typeof metricas.data>['etapas']]))
    for (const grupo of metricas.data?.etapas ?? []) mapa.get(grupo.etapa)?.push(grupo)
    return mapa
  }, [metricas.data])

  return (
    <ConfiguracionShell
      icono={Clock}
      titulo="Tiempos de atención"
      descripcion="Define plazos claros en horas o días para atender cada lead. Los casos ya iniciados conservan los tiempos con los que comenzaron."
      soloLectura={consulta.data ? !consulta.data.puede_editar : true}
      estado={consulta.data ? {
        etiqueta: `Versión ${consulta.data.politica.version}`,
        detalle: `Vigente ${fechaCorta(consulta.data.politica.vigente_desde)} · publicada por ${consulta.data.politica.publicada_por_nombre ?? 'sistema'}`,
      } : undefined}
      acciones={editable ? (
        <Button size="sm" onClick={prepararPublicacion} disabled={!dirty || publicar.isPending}>
          <Save aria-hidden /> Publicar nueva versión
        </Button>
      ) : undefined}
    >
      <ConfiguracionSlaOperativa />

      {consulta.isPending && (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground" role="status">Cargando la política vigente…</CardContent></Card>
      )}
      {consulta.isError && (
        <Card><CardContent className="flex flex-col items-center gap-3 py-10 text-center">
          <p className="text-sm font-semibold text-destructive">{mensajeDeError(consulta.error, 'No se pudo cargar la política SLA.')}</p>
          <Button variant="outline" size="sm" onClick={() => void consulta.refetch()}><RefreshCw aria-hidden /> Reintentar</Button>
        </CardContent></Card>
      )}

      {borrador && consulta.data && (
        <Card>
          <CardHeader className="border-b border-border/70 pb-3">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <CardTitle>Plazos de atención</CardTitle>
                <p className="mt-1 text-xs text-muted-foreground">Los tiempos cuentan todos los días y horas, incluidos fines de semana. Máximo 30 días.</p>
              </div>
              {consulta.data.expected_version > consulta.data.politica.version && (
                <Badge color="var(--warning)" variant="outline">
                  Hay una versión futura v{consulta.data.expected_version}
                </Badge>
              )}
            </div>
          </CardHeader>
          <CardContent className="space-y-6 pt-5">
            <div className="grid gap-4 md:grid-cols-2">
              <CampoDuracion
                id="sla-primera-gestion"
                etiqueta="Primera gestión"
                valor={borrador.primera_gestion_minutos}
                unidadInicial="horas"
                ayuda="Tiempo para hacer la primera llamada o enviar el primer mensaje, aunque el cliente todavía no responda."
                disabled={!editable || publicar.isPending}
                onChange={(valor) => actualizar({ primera_gestion_minutos: valor })}
              />
              <CampoDuracion
                id="sla-primer-contacto"
                etiqueta="Primer contacto efectivo"
                valor={borrador.primer_contacto_minutos}
                unidadInicial="horas"
                ayuda="Tiempo para lograr una conversación o recibir una respuesta efectiva del cliente."
                disabled={!editable || publicar.isPending}
                onChange={(valor) => actualizar({ primer_contacto_minutos: valor })}
              />
            </div>
            <div>
              <p className="text-xs font-extrabold text-primary">Tiempo máximo en cada etapa</p>
              <p className="mt-1 text-[11px] text-muted-foreground">Al vencer este plazo, el lead aparecerá como retrasado.</p>
              <div className="mt-3 grid gap-4 md:grid-cols-2">
                {borrador.etapas.map((regla) => (
                  <CampoDuracion
                    key={regla.etapa}
                    id={`sla-${regla.etapa}`}
                    etiqueta={ETIQUETA_ETAPA[regla.etapa]}
                    valor={regla.maximo_minutos}
                    unidadInicial="dias"
                    ayuda="Tiempo máximo permitido en esta etapa."
                    disabled={!editable || publicar.isPending}
                    onChange={(valor) => actualizarEtapa(regla.etapa, valor)}
                  />
                ))}
              </div>
            </div>
            {editable && (
              <div className="rounded-xl border border-border bg-muted/25 p-3">
                <Label htmlFor="sla-vigencia">Programar vigencia (opcional)</Label>
                <Input
                  id="sla-vigencia"
                  type="datetime-local"
                  value={vigenciaLocal}
                  onChange={(evento) => setVigenciaLocal(evento.target.value)}
                  disabled={publicar.isPending}
                  className="mt-1 max-w-xs"
                />
                <p className="mt-1 text-[10px] text-muted-foreground">Vacío = entra en vigencia al publicar. Una fecha futura no altera casos ya iniciados.</p>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="border-b border-border/70 pb-3">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <CardTitle className="flex items-center gap-2"><ShieldCheck className="size-4 text-accent" aria-hidden /> Cumplimiento histórico</CardTitle>
              <p className="mt-1 text-xs text-muted-foreground">Agrupado por la versión realmente aplicada a cada caso.</p>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div><Label htmlFor="sla-desde">Desde</Label><Input id="sla-desde" type="date" value={desde} max={hasta && hasta < hoy ? hasta : hoy} onChange={(e) => setDesde(e.target.value)} className="mt-1" /></div>
              <div><Label htmlFor="sla-hasta">Hasta</Label><Input id="sla-hasta" type="date" value={hasta} min={desde} max={hoy} onChange={(e) => setHasta(e.target.value)} className="mt-1" /></div>
            </div>
          </div>
        </CardHeader>
        <CardContent className="pt-4">
          {metricas.isPending && <p className="py-8 text-center text-sm text-muted-foreground" role="status">Calculando cumplimiento…</p>}
          {metricas.isError && (
            <div className="flex flex-col items-center gap-3 py-8 text-center">
              <p className="text-sm font-semibold text-destructive">{mensajeDeError(metricas.error, 'No se pudieron cargar las métricas SLA.')}</p>
              <Button variant="outline" size="sm" onClick={() => void metricas.refetch()}><RefreshCw aria-hidden /> Reintentar</Button>
            </div>
          )}
          {metricas.data && (
            <div className="space-y-5">
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                <Cumplimiento titulo="Ciclo · primera gestión" grupos={metricas.data.ciclos.primera_gestion} />
                <Cumplimiento titulo="Ciclo · primer contacto" grupos={metricas.data.ciclos.primer_contacto} />
                <Cumplimiento titulo="Asignación · primera gestión" grupos={metricas.data.asignaciones.primera_gestion} />
                <Cumplimiento titulo="Asignación · primer contacto" grupos={metricas.data.asignaciones.primer_contacto} />
              </div>
              <div>
                <p className="mb-3 text-xs font-extrabold text-primary">Por etapa</p>
                <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                  {ETAPAS_SLA.map((etapa) => (
                    <Cumplimiento key={etapa} titulo={ETIQUETA_ETAPA[etapa]} grupos={gruposEtapa.get(etapa) ?? []} />
                  ))}
                </div>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={confirmando} onClose={() => !publicar.isPending && setConfirmando(false)} ariaLabel="Confirmar nueva política SLA">
        <DialogHeader>
          <DialogTitle>Publicar política SLA v{(consulta.data?.expected_version ?? 0) + 1}</DialogTitle>
          <DialogDescription>La versión actual y los plazos ya fotografiados permanecerán inmutables.</DialogDescription>
        </DialogHeader>
        <DialogBody className="space-y-3 text-sm">
          <p>La nueva política entrará en vigencia {vigenciaLocal ? fechaCorta(new Date(vigenciaLocal).toISOString()) : 'inmediatamente'}.</p>
          <p className="rounded-lg bg-warning/10 px-3 py-2 text-xs font-semibold text-warning">Esta publicación no se edita ni elimina; una corrección requiere otra versión.</p>
        </DialogBody>
        <DialogFooter>
          <Button variant="outline" onClick={() => setConfirmando(false)} disabled={publicar.isPending}>Cancelar</Button>
          <Button onClick={() => void confirmarPublicacion()} disabled={publicar.isPending}>{publicar.isPending ? 'Publicando…' : 'Confirmar publicación'}</Button>
        </DialogFooter>
      </Dialog>
    </ConfiguracionShell>
  )
}
