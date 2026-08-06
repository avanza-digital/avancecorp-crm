import { useEffect, useMemo, useState, type JSX } from 'react'
import { toast } from 'sonner'
import { Target, UsersRound } from 'lucide-react'
import {
  agregarObjetivos,
  META_CONVERSION_PREDETERMINADA,
  type ObjetivoComercial,
  type ObjetivosPorRol,
  type ObjetivosPorVendedor,
} from '@/lib/objetivos'
import type { Miembro } from '@/lib/tipos'
import type { ResultadoMut } from '@/lib/store'
import { money } from '@/lib/format'

interface Borrador {
  capital: string
  conversion: string
}

function aNumero(texto: string): number {
  const numero = Number(texto.trim() || '0')
  return Number.isFinite(numero) ? numero : Number.NaN
}

function aBorrador(meta?: ObjetivoComercial): Borrador {
  return {
    capital: meta && meta.capitalObjetivo > 0 ? String(meta.capitalObjetivo) : '',
    conversion: meta && meta.conversionObjetivo > 0
      ? String(meta.conversionObjetivo)
      : String(META_CONVERSION_PREDETERMINADA),
  }
}

function aBorradores(
  objetivos: ObjetivosPorRol,
  vendedores: Miembro[],
): Record<string, Borrador> {
  return Object.fromEntries(
    vendedores.map((vendedor) => [
      vendedor.perfil_id,
      aBorrador(objetivos.porVendedor?.[vendedor.perfil_id]),
    ]),
  )
}

function desdeBorradores(
  vendedores: Miembro[],
  borradores: Record<string, Borrador>,
): ObjetivosPorVendedor {
  return Object.fromEntries(vendedores.map((vendedor) => {
    const borrador = borradores[vendedor.perfil_id] ?? aBorrador()
    return [vendedor.perfil_id, {
      vendedorId: vendedor.perfil_id,
      supervisorId: vendedor.supervisor_id ?? null,
      capitalObjetivo: aNumero(borrador.capital),
      ventasObjetivo: 0,
      conversionObjetivo: aNumero(borrador.conversion),
    }]
  }))
}

function ResumenMeta({ label, meta }: { label: string; meta: ObjetivoComercial }): JSX.Element {
  return (
    <div className="rounded-xl border border-border/80 bg-card px-3 py-2.5">
      <p className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-muted-foreground">{label}</p>
      <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs font-semibold text-primary">
        <span>{money(meta.capitalObjetivo, 'PEN')}</span>
        <span>{meta.conversionObjetivo.toLocaleString('es-PE', { maximumFractionDigits: 2 })}% conversión</span>
      </div>
    </div>
  )
}

export function MetasEditor({
  objetivos,
  equipo,
  demo,
  onGuardar,
}: {
  objetivos: ObjetivosPorRol
  equipo: Miembro[]
  demo: boolean
  onGuardar: (metas: ObjetivosPorVendedor) => ResultadoMut
}): JSX.Element {
  const vendedores = useMemo(
    () => equipo
      .filter((miembro) => miembro.activo && miembro.rol_crm === 'vendedor')
      .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')),
    [equipo],
  )
  const supervisores = useMemo(
    () => new Map(
      equipo
        .filter((miembro) => miembro.activo && miembro.rol_crm === 'supervisor')
        .map((miembro) => [miembro.perfil_id, miembro.nombre_completo]),
    ),
    [equipo],
  )
  const [borradores, setBorradores] = useState<Record<string, Borrador>>(
    () => aBorradores(objetivos, vendedores),
  )

  // El store aplica las metas de forma optimista y, si la RPC falla, vuelve a
  // cargar la fotografía autoritativa. El formulario debe acompañar ese
  // rollback: conservar aquí el borrador rechazado haría que la pantalla y el
  // resumen mostraran objetivos distintos y un segundo clic lo reenviaría.
  useEffect(() => {
    setBorradores(aBorradores(objetivos, vendedores))
  }, [objetivos, vendedores])

  const metas = useMemo(
    () => desdeBorradores(vendedores, borradores),
    [borradores, vendedores],
  )
  const grupos = useMemo(() => {
    const porSupervisor = new Map<string, Miembro[]>()
    for (const vendedor of vendedores) {
      const supervisorId = vendedor.supervisor_id ?? ''
      porSupervisor.set(supervisorId, [...(porSupervisor.get(supervisorId) ?? []), vendedor])
    }
    return [...porSupervisor.entries()].sort(([a], [b]) =>
      (supervisores.get(a) ?? 'Sin supervisor').localeCompare(
        supervisores.get(b) ?? 'Sin supervisor',
        'es',
      ))
  }, [supervisores, vendedores])
  const empresa = agregarObjetivos(Object.values(metas))
  const sinSupervisor = vendedores.some((vendedor) => !vendedor.supervisor_id)

  const editar = (vendedorId: string, campo: keyof Borrador, valor: string): void => {
    setBorradores((actual) => ({
      ...actual,
      [vendedorId]: { ...(actual[vendedorId] ?? aBorrador()), [campo]: valor },
    }))
  }

  const guardar = (): void => {
    if (sinSupervisor) {
      toast.error('Asigna un supervisor a cada vendedor antes de fijar las metas')
      return
    }
    const resultado = onGuardar(metas)
    if (resultado.ok) toast.success(`Metas individuales actualizadas${demo ? ' (demo)' : ''}`)
    else if (resultado.error) toast.error(resultado.error)
  }

  if (vendedores.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
        No hay vendedores activos para establecer metas.
      </div>
    )
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center gap-2 rounded-xl border border-accent/20 bg-accent/[0.05] px-4 py-3">
        <Target className="size-4 shrink-0 text-accent" aria-hidden />
        <p className="text-xs font-bold text-primary">Metas por vendedor · totales automáticos</p>
      </div>

      <ResumenMeta label="Meta total de la empresa" meta={empresa} />

      {sinSupervisor && (
        <p className="rounded-xl border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs font-semibold text-destructive">
          Hay vendedores sin supervisor. La jerarquía debe completarse antes de guardar.
        </p>
      )}

      {grupos.map(([supervisorId, miembros]) => {
        const subtotal = agregarObjetivos(
          miembros.flatMap((vendedor) => {
            const meta = metas[vendedor.perfil_id]
            return meta ? [meta] : []
          }),
        )
        const nombreSupervisor = supervisores.get(supervisorId) ?? 'Sin supervisor asignado'
        return (
          <section key={supervisorId || 'sin-supervisor'} className="overflow-hidden rounded-2xl border border-border bg-background/70">
            <div className="flex flex-col gap-3 border-b border-border bg-muted/35 px-4 py-3 lg:flex-row lg:items-center lg:justify-between">
              <div className="flex items-center gap-2">
                <UsersRound className="size-4 text-accent" aria-hidden />
                <div>
                  <p className="text-sm font-extrabold text-primary">{nombreSupervisor}</p>
                  <p className="text-[11px] text-muted-foreground">Suma automática de {miembros.length} vendedor{miembros.length === 1 ? '' : 'es'}</p>
                </div>
              </div>
              <ResumenMeta label="Meta del supervisor" meta={subtotal} />
            </div>

            <div className="divide-y divide-border/70">
              {miembros.map((vendedor) => {
                const borrador = borradores[vendedor.perfil_id] ?? aBorrador()
                return (
                  <div key={vendedor.perfil_id} className="grid gap-3 px-4 py-3 md:grid-cols-[minmax(180px,1fr)_repeat(2,minmax(140px,180px))] md:items-end">
                    <div>
                      <p className="text-xs font-bold text-primary">{vendedor.nombre_completo}</p>
                      <p className="mt-0.5 text-[10px] uppercase tracking-wide text-muted-foreground">Meta individual</p>
                    </div>
                    <label className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                      Monto en soles
                      <input
                        type="text"
                        inputMode="numeric"
                        aria-label={`Monto objetivo de ${vendedor.nombre_completo}`}
                        value={borrador.capital ? Number(borrador.capital).toLocaleString('es-PE') : ''}
                        onChange={(evento) => editar(vendedor.perfil_id, 'capital', evento.target.value.replace(/\D/g, ''))}
                        className="mt-1 h-9 w-full rounded-lg border border-border bg-background px-2 text-xs tabular-nums text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                      />
                    </label>
                    <label className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                      Conversión %
                      <input
                        type="number"
                        min={0}
                        max={100}
                        step={0.1}
                        inputMode="decimal"
                        aria-label={`Conversión objetivo de ${vendedor.nombre_completo}`}
                        value={borrador.conversion}
                        onChange={(evento) => editar(vendedor.perfil_id, 'conversion', evento.target.value)}
                        className="mt-1 h-9 w-full rounded-lg border border-border bg-background px-2 text-xs tabular-nums text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                      />
                    </label>
                  </div>
                )
              })}
            </div>
          </section>
        )
      })}

      <div className="flex justify-end">
        <button
          type="button"
          disabled={sinSupervisor}
          onClick={guardar}
          className="rounded-xl bg-primary px-5 py-2.5 text-xs font-extrabold text-primary-foreground shadow-sm transition-opacity disabled:cursor-not-allowed disabled:opacity-45"
        >
          Guardar metas individuales
        </button>
      </div>
    </div>
  )
}
