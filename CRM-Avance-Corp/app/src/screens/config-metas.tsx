import { useEffect, useMemo, useState } from 'react'
import { ArrowRight, ChevronLeft, ChevronRight, Copy, RefreshCw, Save, Target, TriangleAlert } from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useConfiguracionMetas, usePublicarMetas } from '@/data/crm-config-queries'
import { obtenerConfiguracionMetas, publicacionDesdeConfiguracion } from '@/data/crm-config-api'
import { mensajeDeError } from '@/data/crm-api'
import type { ConfiguracionMetas } from '@/lib/metas-versionadas'
import { periodoLima } from '@/lib/objetivos'

function desplazarPeriodo(periodo: string, meses: number): string {
  const anio = Number(periodo.slice(0, 4))
  const mes = Number(periodo.slice(5, 7))
  const fecha = new Date(Date.UTC(anio, mes - 1 + meses, 1))
  return `${fecha.getUTCFullYear()}-${String(fecha.getUTCMonth() + 1).padStart(2, '0')}-01`
}

function nombrePeriodo(periodo: string): string {
  const anio = Number(periodo.slice(0, 4))
  const mes = Number(periodo.slice(5, 7))
  return new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'UTC' })
    .format(new Date(Date.UTC(anio, mes - 1, 1)))
}

function aNumero(valor: string): number {
  const numero = Number(valor)
  return Number.isFinite(numero) ? numero : 0
}

function fechaPublicacion(valor: string | null): string {
  if (!valor) return 'Sin publicación todavía'
  return new Intl.DateTimeFormat('es-PE', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'America/Lima',
  }).format(new Date(valor))
}

function clonar(config: ConfiguracionMetas): ConfiguracionMetas {
  return {
    ...config,
    vendedores: config.vendedores.map((vendedor) => ({
      ...vendedor,
      detalles: vendedor.detalles.map((detalle) => ({ ...detalle })),
    })),
  }
}

function metaTotal(vendedor: ConfiguracionMetas['vendedores'][number]): number {
  return vendedor.detalles
    .filter((detalle) => detalle.moneda === 'PEN')
    .reduce((total, detalle) => total + detalle.capital_objetivo, 0)
}

/**
 * La base conserva seis dimensiones por compatibilidad histórica. La experiencia
 * operativa usa una sola meta: la guardamos en el slot canónico nuevo/PEN y
 * dejamos las demás dimensiones y objetivos auxiliares en cero.
 */
function fijarMetaTotal(
  vendedor: ConfiguracionMetas['vendedores'][number],
  total: number,
) {
  vendedor.conversion_objetivo = 0
  vendedor.detalles = vendedor.detalles.map((detalle) => ({
    ...detalle,
    capital_objetivo: detalle.categoria === 'nuevo' && detalle.moneda === 'PEN' ? total : 0,
    contratos_objetivo: 0,
  }))
}

function validar(config: ConfiguracionMetas): string | null {
  for (const vendedor of config.vendedores) {
    const total = metaTotal(vendedor)
    if (!Number.isFinite(total) || total < 0 || total > 100_000_000) {
      return `La meta mensual de ${vendedor.nombre} debe estar entre S/ 0 y S/ 100,000,000.`
    }
  }
  return null
}

function MetaVendedor({
  vendedor,
  editable,
  onMetaTotal,
}: {
  vendedor: ConfiguracionMetas['vendedores'][number]
  editable: boolean
  onMetaTotal: (valor: number) => void
}) {
  const total = metaTotal(vendedor)
  return (
    <Card>
      <CardHeader className="border-b border-border/70 pb-4">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <CardTitle>{vendedor.nombre}</CardTitle>
            <p className="mt-1 text-xs text-muted-foreground">Supervisor: {vendedor.supervisor_nombre}</p>
          </div>
          <div className="rounded-xl border border-accent/25 bg-accent/[0.06] px-3 py-2 text-xs text-foreground sm:max-w-xs">
            Una sola meta mensual, sin dividirla entre Nuevo, Renovación o Upgrade.
          </div>
        </div>
      </CardHeader>
      <CardContent className="pt-5">
        <div className="max-w-md">
          <Label htmlFor={`meta-total-${vendedor.vendedor_id}`}>Meta mensual total</Label>
          <div className="relative mt-1.5">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm font-extrabold text-primary">S/</span>
            <Input
              id={`meta-total-${vendedor.vendedor_id}`}
              aria-label={`Meta mensual total de ${vendedor.nombre}`}
              type="number"
              inputMode="decimal"
              min={0}
              max={100_000_000}
              step="1000"
              value={total}
              disabled={!editable}
              onChange={(evento) => onMetaTotal(aNumero(evento.target.value))}
              className="h-12 pl-10 text-lg font-extrabold tabular-nums"
            />
          </div>
          <p className="mt-2 text-[11px] text-muted-foreground">Monto total esperado para el analista durante el mes seleccionado.</p>
        </div>
      </CardContent>
    </Card>
  )
}

/** Cada motivo es un arreglo distinto; decir «sin supervisor» a los tres manda
 * a Gerencia a buscar un problema que no es. */
const MOTIVO_SIN_SUPERVISOR: Record<
  ConfiguracionMetas['sin_supervisor'][number]['motivo'], string
> = {
  sin_supervisor: 'no tiene supervisor asignado',
  supervisor_inactivo: 'su supervisor está dado de baja',
  supervisor_no_es_supervisor: 'quien figura como su supervisor ya no tiene ese rol',
}

/**
 * A quién NO se le puede fijar meta y por qué. Un analista fuera del roster no
 * cabe en la meta del mes —`crm.metas_vendedor.supervisor_id` es obligatorio— y
 * callarlo dejaría a alguien sin objetivo y sin producción atribuida hasta que
 * alguien se diera cuenta a fin de mes.
 */
function AnalistasFueraDeMetas({
  analistas,
}: {
  analistas: ConfiguracionMetas['sin_supervisor']
}) {
  if (analistas.length === 0) return null
  const plural = analistas.length !== 1
  return (
    <Card className="border-warning/40 bg-warning/[0.06]">
      <CardContent className="flex flex-col gap-3 py-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-start gap-3">
          <TriangleAlert className="mt-0.5 size-5 shrink-0 text-warning" aria-hidden />
          <div>
            {/* Encabezado real: con 17 analistas la pantalla emite ~18 h3, y sin
                este el único bloque ausente de la navegación por encabezados
                sería justo el aviso que Gerencia no puede pasar por alto. */}
            <h3 id="analistas-sin-meta" className="text-sm font-extrabold text-foreground">
              {analistas.length} analista{plural ? 's' : ''} sin meta este mes
            </h3>
            <ul className="mt-1.5 space-y-1" aria-labelledby="analistas-sin-meta">
              {analistas.map((analista) => (
                // `text-foreground/70` y no `muted-foreground`: la tinta ámbar de
                // la card gana a `bg-card` en twMerge y deja el gris en 4.21:1.
                <li key={analista.vendedor_id} className="text-xs text-foreground/70">
                  <span className="font-semibold text-foreground">{analista.nombre}</span>
                  {` — ${MOTIVO_SIN_SUPERVISOR[analista.motivo]}.`}
                </li>
              ))}
            </ul>
            <p className="mt-2 text-xs text-foreground/70">
              Mientras siga así no {plural ? 'se les' : 'se le'} puede fijar meta y su
              producción no se atribuye en el cumplimiento del mes. La publicación del
              resto del equipo no se detiene.
            </p>
          </div>
        </div>
        <a
          href="#/config-usuarios"
          className="inline-flex h-9 shrink-0 items-center justify-center gap-2 rounded-md border border-border bg-card px-3 text-xs font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          Revisar jerarquía <ArrowRight className="size-4" aria-hidden />
        </a>
      </CardContent>
    </Card>
  )
}

export function ConfigMetas() {
  const [periodo, setPeriodo] = useState(() => periodoLima(Date.now()))
  const consulta = useConfiguracionMetas(periodo)
  const publicar = usePublicarMetas(periodo)
  const [borrador, setBorrador] = useState<ConfiguracionMetas | null>(null)
  const [copiando, setCopiando] = useState(false)

  useEffect(() => {
    if (consulta.data) setBorrador(clonar(consulta.data))
  }, [consulta.data])

  const metaEquipo = useMemo(() => {
    return (borrador?.vendedores ?? []).reduce((total, vendedor) => total + metaTotal(vendedor), 0)
  }, [borrador])

  const editable = Boolean(borrador?.puede_editar)
  const dirty = Boolean(consulta.data && borrador
    && JSON.stringify(consulta.data.vendedores.map((vendedor) => [vendedor.vendedor_id, metaTotal(vendedor)]))
      !== JSON.stringify(borrador.vendedores.map((vendedor) => [vendedor.vendedor_id, metaTotal(vendedor)])))

  const editarVendedor = (
    vendedorId: string,
    mutar: (vendedor: ConfiguracionMetas['vendedores'][number]) => void,
  ) => {
    setBorrador((actual) => {
      if (!actual) return actual
      const siguiente = clonar(actual)
      const vendedor = siguiente.vendedores.find((item) => item.vendedor_id === vendedorId)
      if (vendedor) mutar(vendedor)
      return siguiente
    })
  }

  const copiarAnterior = async () => {
    if (!borrador) return
    setCopiando(true)
    try {
      const anterior = await obtenerConfiguracionMetas(desplazarPeriodo(periodo, -1))
      const metasAnteriores = new Map(anterior.vendedores.map((vendedor) => [vendedor.vendedor_id, vendedor]))
      setBorrador((actual) => {
        if (!actual) return actual
        const siguiente = clonar(actual)
        for (const vendedor of siguiente.vendedores) {
          const previa = metasAnteriores.get(vendedor.vendedor_id)
          if (!previa) continue
          fijarMetaTotal(vendedor, metaTotal(previa))
        }
        return siguiente
      })
      toast.success(`Se copiaron las metas de ${nombrePeriodo(anterior.periodo)}.`)
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudieron copiar las metas del mes anterior.'))
    } finally {
      setCopiando(false)
    }
  }

  const guardar = async () => {
    if (!borrador) return
    const normalizado = clonar(borrador)
    for (const vendedor of normalizado.vendedores) fijarMetaTotal(vendedor, metaTotal(vendedor))
    const error = validar(normalizado)
    if (error) {
      toast.error(error)
      return
    }
    try {
      await publicar.mutateAsync({
        periodo,
        expectedRevision: borrador.revision,
        metas: publicacionDesdeConfiguracion(normalizado),
      })
      toast.success(`Metas de ${nombrePeriodo(periodo)} publicadas.`)
    } catch (fallo) {
      toast.error(mensajeDeError(fallo, 'No se pudieron publicar las metas.'))
    }
  }

  return (
    <ConfiguracionShell
      icono={Target}
      titulo="Metas mensuales"
      descripcion="Una sola meta mensual en soles por analista, sin categorías, cantidad de contratos ni porcentaje de conversión."
      soloLectura={borrador ? !borrador.puede_editar : true}
      estado={borrador ? {
        etiqueta: borrador.revision > 0 ? `Revisión ${borrador.revision}` : 'Sin publicar',
        detalle: borrador.publicada_en
          ? `Publicada por ${borrador.publicada_por_nombre ?? 'usuario no disponible'} · ${fechaPublicacion(borrador.publicada_en)}`
          : 'El período todavía no tiene una revisión publicada.',
      } : undefined}
      acciones={editable ? (
        <>
          <Button variant="outline" size="sm" onClick={copiarAnterior} disabled={copiando || publicar.isPending}>
            <Copy aria-hidden /> {copiando ? 'Copiando…' : 'Copiar mes anterior'}
          </Button>
          <Button size="sm" onClick={guardar} disabled={!dirty || publicar.isPending}>
            <Save aria-hidden /> {publicar.isPending ? 'Publicando…' : 'Publicar revisión'}
          </Button>
        </>
      ) : undefined}
    >
      <Card>
        <CardContent className="flex flex-col gap-4 py-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <Label htmlFor="periodo-metas">Período</Label>
            <div className="mt-1 flex items-center gap-2">
              <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label="Mes anterior"
                onClick={() => setPeriodo((actual) => desplazarPeriodo(actual, -1))}
              >
                <ChevronLeft aria-hidden />
              </Button>
              <Input
                id="periodo-metas"
                type="month"
                value={periodo.slice(0, 7)}
                onChange={(evento) => evento.target.value && setPeriodo(`${evento.target.value}-01`)}
                className="w-44 font-semibold capitalize"
              />
              <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label="Mes siguiente"
                onClick={() => setPeriodo((actual) => desplazarPeriodo(actual, 1))}
              >
                <ChevronRight aria-hidden />
              </Button>
            </div>
          </div>
          {borrador && (
            <div className="rounded-xl border border-accent/25 bg-accent/[0.06] px-4 py-3 text-right">
              <p className="text-[10px] font-extrabold uppercase tracking-[0.08em] text-muted-foreground">Meta total del equipo</p>
              <p className="mt-1 text-lg font-extrabold tabular-nums text-primary">
                S/ {metaEquipo.toLocaleString('es-PE', { maximumFractionDigits: 2 })}
              </p>
              <p className="mt-0.5 text-[10px] text-muted-foreground">{borrador.vendedores.length} analista{borrador.vendedores.length === 1 ? '' : 's'}</p>
            </div>
          )}
        </CardContent>
      </Card>

      {borrador && <AnalistasFueraDeMetas analistas={borrador.sin_supervisor} />}

      {consulta.isPending && (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground" role="status">Cargando las metas del período…</CardContent></Card>
      )}

      {consulta.isError && (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
            <p className="text-sm font-semibold text-destructive">{mensajeDeError(consulta.error, 'No se pudieron cargar las metas.')}</p>
            <Button variant="outline" size="sm" onClick={() => void consulta.refetch()}>
              <RefreshCw aria-hidden /> Reintentar
            </Button>
          </CardContent>
        </Card>
      )}

      {borrador && borrador.vendedores.length === 0 && (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">No hay vendedores activos en el roster de este período.</CardContent></Card>
      )}

      {borrador?.vendedores.map((vendedor) => (
        <MetaVendedor
          key={vendedor.vendedor_id}
          vendedor={vendedor}
          editable={editable && !publicar.isPending}
          onMetaTotal={(valor) => editarVendedor(vendedor.vendedor_id, (fila) => fijarMetaTotal(fila, valor))}
        />
      ))}

      {dirty && editable && (
        <p className="sticky bottom-4 rounded-xl border border-warning/30 bg-card px-4 py-3 text-center text-xs font-semibold text-warning shadow-[var(--shadow-pop)]" role="status">
          Hay cambios sin publicar. Se crearán como una revisión nueva; el historial anterior no se modifica.
        </p>
      )}
    </ConfiguracionShell>
  )
}
