// «Cargar base» (F5, E1 de Miguel: «las dos cosas»): una hoja lateral ancha con dos caminos que terminan en el mismo
// reparto: subir un archivo (.xlsx/.csv) o armarla con descartados del CRM. Mientras una carga corre, la hoja no se cierra
// (cerrarla a medias dejaría la base incompleta sin informe).
import { useCallback, useState, type JSX } from 'react'
import { toast } from 'sonner'
import { X } from 'lucide-react'
import { Sheet, SheetBody, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Tabs } from '@/components/ui/tabs'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import type { PuertasBases } from '@/data/bases-cargadas-queries'
import type { Miembro } from '@/lib/tipos'
import { CargaArchivo } from './carga-archivo'
import { ArmarDesdeCrm } from './armar-desde-crm'

type Camino = 'archivo' | 'crm'
const CAMINOS = [
  { valor: 'archivo', etiqueta: 'Subir archivo' },
  { valor: 'crm', etiqueta: 'Armar desde el CRM' },
] as const satisfies readonly { valor: Camino; etiqueta: string }[]

export function CargarBase({ abierta, puertas, esGerencia, supervisores, onCerrar, onVerBase }: {
  abierta: boolean
  puertas: PuertasBases
  esGerencia: boolean
  supervisores: readonly Miembro[]
  onCerrar: () => void
  onVerBase: (baseId: string) => void
}): JSX.Element {
  const [camino, setCamino] = useState<Camino>('archivo')
  const [enCurso, setEnCurso] = useState(false)
  const alEnCurso = useCallback((v: boolean) => setEnCurso(v), [])
  const cerrar = () => {
    if (enCurso) { toast.info('Espera a que termine la carga: si cierras ahora, la base queda a medias.'); return }
    onCerrar()
  }
  const verBase = (baseId: string) => { onCerrar(); onVerBase(baseId) }
  return (
    <Sheet open={abierta} onClose={cerrar} className="w-full max-w-full sm:w-[1080px] sm:max-w-[96vw]">
      {abierta && (
        <>
          <SheetHeader>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <SheetTitle className="text-lg">Cargar base</SheetTitle>
                <SheetDescription className="text-[13px] text-[var(--muted-foreground-strong)]">
                  Sube un archivo con contactos que no están en el CRM o arma una base con descartados que ya están. Las dos terminan en el mismo reparto.
                </SheetDescription>
              </div>
              <button
                type="button"
                onClick={cerrar}
                aria-label="Cerrar «Cargar base»"
                aria-disabled={enCurso || undefined}
                className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground pointer-coarse:size-11', FOCO)}
              >
                <X className="size-4" aria-hidden />
              </button>
            </div>
          </SheetHeader>
          <SheetBody>
            <Tabs etiqueta="Cómo cargar la base" pestanas={CAMINOS} valor={camino} onCambio={(c) => { if (!enCurso) setCamino(c) }} variante="pastilla" panelEnfocable={false}>
              {camino === 'archivo'
                ? <CargaArchivo puertas={puertas} esGerencia={esGerencia} supervisores={supervisores} onVerBase={verBase} onEnCurso={alEnCurso} />
                : <ArmarDesdeCrm puertas={puertas} esGerencia={esGerencia} supervisores={supervisores} onVerBase={verBase} />}
            </Tabs>
          </SheetBody>
        </>
      )}
    </Sheet>
  )
}
