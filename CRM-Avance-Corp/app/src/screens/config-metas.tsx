import { useEffect, useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, Copy, RefreshCw, Save, Target } from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useConfiguracionMetas, usePublicarMetas } from '@/data/crm-config-queries'
import { obtenerConfiguracionMetas, publicacionDesdeConfiguracion } from '@/data/crm-config-api'
import { mensajeDeError } from '@/data/crm-api'
import type { ConfiguracionMetas, DetalleMeta } from '@/lib/metas-versionadas'
import { periodoLima } from '@/lib/objetivos'
import { MONEDAS_PRODUCTO } from '@/lib/productos-inversion'

const ETIQUETA_CATEGORIA = {
  nuevo: 'Nuevo',
  renovacion: 'Renovación',
  upgrade: 'Upgrade',
} as const

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

function validar(config: ConfiguracionMetas): string | null {
  for (const vendedor of config.vendedores) {
    if (!Number.isFinite(vendedor.conversion_objetivo)
      || vendedor.conversion_objetivo < 0
      || vendedor.conversion_objetivo > 100) {
      return `La conversión de ${vendedor.nombre} debe estar entre 0 y 100.`
    }
    for (const detalle of vendedor.detalles) {
      if (!Number.isFinite(detalle.capital_objetivo)
        || detalle.capital_objetivo < 0
        || detalle.capital_objetivo > 100_000_000) {
        return `El capital de ${vendedor.nombre} está fuera del rango permitido.`
      }
      if (!Number.isInteger(detalle.contratos_objetivo)
        || detalle.contratos_objetivo < 0
        || detalle.contratos_objetivo > 1_000) {
        return `Los contratos de ${vendedor.nombre} deben ser enteros entre 0 y 1,000.`
      }
    }
  }
  return null
}

function MetaVendedor({
  vendedor,
  editable,
  onConversion,
  onDetalle,
}: {
  vendedor: ConfiguracionMetas['vendedores'][number]
  editable: boolean
  onConversion: (valor: number) => void
  onDetalle: (indice: number, patch: Partial<DetalleMeta>) => void
}) {
  return (
    <Card>
      <CardHeader className="border-b border-border/70 pb-3">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <CardTitle>{vendedor.nombre}</CardTitle>
            <p className="mt-1 text-xs text-muted-foreground">Supervisor: {vendedor.supervisor_nombre}</p>
          </div>
          <div className="w-full sm:w-44">
            <Label htmlFor={`conversion-${vendedor.vendedor_id}`}>Conversión objetivo</Label>
            <div className="relative mt-1">
              <Input
                id={`conversion-${vendedor.vendedor_id}`}
                aria-label={`Conversión objetivo de ${vendedor.nombre}`}
                type="number"
                inputMode="decimal"
                min={0}
                max={100}
                step="0.1"
                value={vendedor.conversion_objetivo}
                disabled={!editable}
                onChange={(evento) => onConversion(aNumero(evento.target.value))}
                className="pr-8 tabular-nums"
              />
              <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">%</span>
            </div>
          </div>
        </div>
      </CardHeader>
      <CardContent className="pt-4">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[680px] border-separate border-spacing-0 text-left text-xs">
            <thead>
              <tr className="text-[10px] font-extrabold uppercase tracking-[0.08em] text-muted-foreground">
                <th className="border-b border-border px-2 py-2">Categoría</th>
                <th className="border-b border-border px-2 py-2">Moneda</th>
                <th className="border-b border-border px-2 py-2">Capital objetivo</th>
                <th className="border-b border-border px-2 py-2">Contratos objetivo</th>
              </tr>
            </thead>
            <tbody>
              {vendedor.detalles.map((detalle, indice) => (
                <tr key={`${detalle.categoria}-${detalle.moneda}`}>
                  <td className="border-b border-border/60 px-2 py-2 font-semibold text-primary">
                    {ETIQUETA_CATEGORIA[detalle.categoria]}
                  </td>
                  <td className="border-b border-border/60 px-2 py-2">
                    <Badge variant="outline" color={detalle.moneda === 'PEN' ? 'var(--accent)' : 'var(--info)'}>
                      {detalle.moneda}
                    </Badge>
                  </td>
                  <td className="border-b border-border/60 px-2 py-2">
                    <Input
                      aria-label={`Capital ${detalle.categoria} ${detalle.moneda} de ${vendedor.nombre}`}
                      type="number"
                      inputMode="decimal"
                      min={0}
                      max={100_000_000}
                      step="0.01"
                      value={detalle.capital_objetivo}
                      disabled={!editable}
                      onChange={(evento) => onDetalle(indice, { capital_objetivo: aNumero(evento.target.value) })}
                      className="h-8 tabular-nums"
                    />
                  </td>
                  <td className="border-b border-border/60 px-2 py-2">
                    <Input
                      aria-label={`Contratos ${detalle.categoria} ${detalle.moneda} de ${vendedor.nombre}`}
                      type="number"
                      inputMode="numeric"
                      min={0}
                      max={1_000}
                      step={1}
                      value={detalle.contratos_objetivo}
                      disabled={!editable}
                      onChange={(evento) => onDetalle(indice, { contratos_objetivo: aNumero(evento.target.value) })}
                      className="h-8 tabular-nums"
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
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

  const resumen = useMemo(() => {
    const base = Object.fromEntries(MONEDAS_PRODUCTO.map((moneda) => [moneda, { capital: 0, contratos: 0 }])) as Record<'PEN' | 'USD', { capital: number; contratos: number }>
    for (const vendedor of borrador?.vendedores ?? []) {
      for (const detalle of vendedor.detalles) {
        base[detalle.moneda].capital += detalle.capital_objetivo
        base[detalle.moneda].contratos += detalle.contratos_objetivo
      }
    }
    return base
  }, [borrador])

  const editable = Boolean(borrador?.puede_editar)
  const dirty = Boolean(consulta.data && borrador
    && JSON.stringify(publicacionDesdeConfiguracion(consulta.data)) !== JSON.stringify(publicacionDesdeConfiguracion(borrador)))

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
          vendedor.conversion_objetivo = previa.conversion_objetivo
          vendedor.detalles = previa.detalles.map((detalle) => ({ ...detalle }))
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
    const error = validar(borrador)
    if (error) {
      toast.error(error)
      return
    }
    try {
      await publicar.mutateAsync({
        periodo,
        expectedRevision: borrador.revision,
        metas: publicacionDesdeConfiguracion(borrador),
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
      descripcion="Objetivos de capital y contratos por vendedor, categoría y moneda. PEN y USD se gobiernan y comparan por separado."
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
            <div className="grid grid-cols-2 gap-2 text-xs">
              {MONEDAS_PRODUCTO.map((moneda) => (
                <div key={moneda} className="rounded-xl border border-border bg-muted/30 px-3 py-2">
                  <p className="font-extrabold text-primary">{moneda} {resumen[moneda].capital.toLocaleString('es-PE', { maximumFractionDigits: 2 })}</p>
                  <p className="mt-0.5 text-[10px] text-muted-foreground">{resumen[moneda].contratos} contratos objetivo</p>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

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
          onConversion={(valor) => editarVendedor(vendedor.vendedor_id, (fila) => { fila.conversion_objetivo = valor })}
          onDetalle={(indice, patch) => editarVendedor(vendedor.vendedor_id, (fila) => {
            const actual = fila.detalles[indice]
            if (!actual) return
            fila.detalles[indice] = {
              categoria: actual.categoria,
              moneda: actual.moneda,
              capital_objetivo: patch.capital_objetivo ?? actual.capital_objetivo,
              contratos_objetivo: patch.contratos_objetivo ?? actual.contratos_objetivo,
            }
          })}
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
