// Editor "Fijar metas del mes" — la única puerta de la UI hacia crm.objetivos.
// Solo lo monta la pantalla de gerencia (el gate duro vive en la RPC del
// servidor y el store lo espeja con can('editarConfiguracion')). Patrón de la
// casa: detalle bajo demanda — un botón chico abre el formulario en línea.
import { useState, type JSX } from 'react'
import { toast } from 'sonner'
import {
  ROLES_OBJETIVO,
  type ObjetivosPorRol,
  type RolObjetivo,
} from '@/lib/objetivos'
import type { ResultadoMut } from '@/lib/store'

const LABEL_ROL: Record<RolObjetivo, string> = {
  vendedor: 'Cada vendedor',
  supervisor: 'Cada supervisor',
  gerencia: 'Empresa',
}

interface Borrador {
  capital: string
  ventas: string
  conversion: string
}

function aBorradores(objetivos: ObjetivosPorRol): Record<RolObjetivo, Borrador> {
  const borradores = {} as Record<RolObjetivo, Borrador>
  for (const rol of ROLES_OBJETIVO) {
    borradores[rol] = {
      capital: objetivos[rol].capitalObjetivo > 0 ? String(objetivos[rol].capitalObjetivo) : '',
      ventas: objetivos[rol].ventasObjetivo > 0 ? String(objetivos[rol].ventasObjetivo) : '',
      conversion: objetivos[rol].conversionObjetivo > 0 ? String(objetivos[rol].conversionObjetivo) : '',
    }
  }
  return borradores
}

function aNumero(texto: string): number {
  const n = Number(texto.trim() || '0')
  return Number.isFinite(n) ? n : Number.NaN
}

export function MetasEditor({
  objetivos,
  demo,
  onGuardar,
}: {
  objetivos: ObjetivosPorRol
  demo: boolean
  onGuardar: (metas: ObjetivosPorRol) => ResultadoMut
}): JSX.Element {
  const [abierto, setAbierto] = useState(false)
  const [borradores, setBorradores] = useState<Record<RolObjetivo, Borrador>>(
    () => aBorradores(objetivos),
  )

  const editar = (rol: RolObjetivo, campo: keyof Borrador, valor: string): void => {
    setBorradores((prev) => ({ ...prev, [rol]: { ...prev[rol], [campo]: valor } }))
  }

  const guardar = (): void => {
    const metas = {} as ObjetivosPorRol
    for (const rol of ROLES_OBJETIVO) {
      metas[rol] = {
        capitalObjetivo: aNumero(borradores[rol].capital),
        ventasObjetivo: aNumero(borradores[rol].ventas),
        conversionObjetivo: aNumero(borradores[rol].conversion),
      }
    }
    const res = onGuardar(metas)
    if (res.ok) {
      toast.success(`Metas del mes actualizadas${demo ? ' (demo)' : ''}`)
      setAbierto(false)
    } else if (res.error) {
      toast.error(res.error)
    }
  }

  if (!abierto) {
    return (
      <div className="flex justify-end">
        <button
          type="button"
          onClick={() => {
            setBorradores(aBorradores(objetivos))
            setAbierto(true)
          }}
          className="rounded-full border border-border px-3 py-1 text-[11px] font-bold text-muted-foreground transition-colors hover:bg-muted/60 hover:text-primary focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          Fijar metas del mes
        </button>
      </div>
    )
  }

  return (
    <div className="w-full space-y-3 rounded-2xl border border-border bg-background/70 p-3">
      <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
        Metas de este mes (capital en soles)
      </p>
      {ROLES_OBJETIVO.map((rol) => (
        <div key={rol} className="grid grid-cols-[minmax(88px,1fr)_repeat(3,minmax(0,96px))] items-center gap-2">
          <span className="text-xs font-semibold text-primary">{LABEL_ROL[rol]}</span>
          <input
            type="number"
            min={0}
            step={1000}
            inputMode="numeric"
            placeholder="Capital"
            aria-label={`Capital objetivo — ${LABEL_ROL[rol]} (soles)`}
            value={borradores[rol].capital}
            onChange={(e) => editar(rol, 'capital', e.target.value)}
            className="h-8 rounded-lg border border-border bg-background px-2 text-xs tabular-nums focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          />
          <input
            type="number"
            min={0}
            step={1}
            inputMode="numeric"
            placeholder="Cierres"
            aria-label={`Cierres objetivo — ${LABEL_ROL[rol]}`}
            value={borradores[rol].ventas}
            onChange={(e) => editar(rol, 'ventas', e.target.value)}
            className="h-8 rounded-lg border border-border bg-background px-2 text-xs tabular-nums focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          />
          <input
            type="number"
            min={0}
            max={100}
            step={1}
            inputMode="numeric"
            placeholder="Conv. %"
            aria-label={`Conversión objetivo — ${LABEL_ROL[rol]} (porcentaje)`}
            value={borradores[rol].conversion}
            onChange={(e) => editar(rol, 'conversion', e.target.value)}
            className="h-8 rounded-lg border border-border bg-background px-2 text-xs tabular-nums focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          />
        </div>
      ))}
      <div className="flex items-center justify-end gap-2 pt-1">
        <button
          type="button"
          onClick={() => setAbierto(false)}
          className="rounded-xl border border-border px-3 py-1.5 text-xs font-bold text-muted-foreground transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          Cancelar
        </button>
        <button
          type="button"
          onClick={guardar}
          className="rounded-xl bg-primary px-4 py-1.5 text-xs font-bold text-primary-foreground shadow-sm transition-colors hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          Guardar metas
        </button>
      </div>
    </div>
  )
}
