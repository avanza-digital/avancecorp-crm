// Dentro de UNA base (F5): sus cifras arriba (pastillas pequeñas; todo número se abre), el REPARTO (por cantidades o
// por selección) y el SEGUIMIENTO por analista (con «Recoger»). En escritorio, reparto y seguimiento van lado a lado
// (horizontal antes que vertical); en pantallas más angostas, uno sobre otro.
import { useEffect, useRef, type Ref } from 'react'
import { ArrowLeft } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Pastilla } from '@/components/base-gestion/filtros-base'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { fmtFecha } from '@/lib/format'
import type { PuertasBases } from '@/data/bases-cargadas-queries'
import { CIFRAS_BASE, ROTULO_CIFRA, etiquetaOrigenBase, type CifraAnalista, type CifraBase, type FilaSeguimientoBase, type FilaSeguimientoBases } from '@/lib/bases-cargadas'
import type { Miembro } from '@/lib/tipos'
import { Avance } from './hoja-bases'
import { RepartoBase } from './reparto-base'
import { SeguimientoAnalistas } from './seguimiento-analistas'
import { ROTULO } from './piezas-bases'

export function DetalleBase({ puertas, base, analistas, esMovil, ahora, onVolver, onAbrirCifra, onAbrirCifraAnalista, volverRef }: {
  puertas: PuertasBases
  base: FilaSeguimientoBases
  analistas: readonly Miembro[]
  esMovil: boolean
  ahora: number
  onVolver: () => void
  onAbrirCifra: (cifra: CifraBase) => void
  onAbrirCifraAnalista: (fila: FilaSeguimientoBase, cifra: CifraAnalista) => void
  volverRef?: Ref<HTMLButtonElement> | undefined
}) {
  const titulo = useRef<HTMLHeadingElement>(null)
  // Adónde vuelve el foco si, tras repartir, el control pulsado desaparece (p. ej. ya no quedan por repartir).
  const tituloReparto = useRef<HTMLHeadingElement>(null)
  // Al abrir una base, el foco va a su título (quien usa lector sabe dónde está; nada cae en <body>).
  useEffect(() => { titulo.current?.focus() }, [base.base_id])
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-3">
        <div className="min-w-0 space-y-1">
          <Button ref={volverRef} type="button" variant="ghost" size="sm" className="-ml-2 pointer-coarse:h-11" onClick={onVolver}>
            <ArrowLeft aria-hidden /> Todas las bases
          </Button>
          <h2 ref={titulo} tabIndex={-1} className={cn('rounded text-[22px] font-bold leading-tight text-primary', FOCO)}>{base.nombre}</h2>
          <p className="text-sm text-[var(--muted-foreground-strong)]">
            {etiquetaOrigenBase(base.origen)} · Supervisor: {base.supervisor_nombre ?? '—'} · Creada el {fmtFecha(base.creado_en)}
          </p>
        </div>
        <section aria-label={`Cifras de ${base.nombre}`} className="flex flex-wrap items-center gap-2">
          {CIFRAS_BASE.map((c) => (
            <Pastilla key={c} etiqueta={ROTULO_CIFRA[c]} valor={base[c]} pista="ver la lista" onAbrir={base[c] > 0 ? () => onAbrirCifra(c) : undefined} />
          ))}
          <p className="inline-flex items-center gap-2 rounded-md border border-border bg-card px-3 py-1.5 text-sm text-[var(--muted-foreground-strong)]">
            Avance<span className="sr-only">:</span> <Avance avance={base.avance} />
          </p>
        </section>
      </div>

      <div className="grid gap-6 2xl:grid-cols-[minmax(0,34rem)_minmax(0,1fr)]">
        <section aria-labelledby={`reparto-${base.base_id}`} className="min-w-0 space-y-2">
          <h3 ref={tituloReparto} tabIndex={-1} id={`reparto-${base.base_id}`} className={cn(ROTULO, 'rounded', FOCO)}>Repartir · {base.sin_repartir.toLocaleString('es-PE')} sin repartir</h3>
          <RepartoBase puertas={puertas} base={base} analistas={analistas} tituloRef={tituloReparto} />
        </section>
        <section aria-labelledby={`seguimiento-${base.base_id}`} className="min-w-0 space-y-2">
          <h3 id={`seguimiento-${base.base_id}`} className={ROTULO}>Seguimiento por analista</h3>
          <SeguimientoAnalistas puertas={puertas} base={base} esMovil={esMovil} ahora={ahora} onAbrirCifra={onAbrirCifraAnalista} />
        </section>
      </div>
    </div>
  )
}
