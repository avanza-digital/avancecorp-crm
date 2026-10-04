// Seguimiento de una base POR ANALISTA (F5, `crm.seguimiento_base`, B10): asignados · sin tocar · sin tocar 3 días (en
// ROJO: E6, nada se mueve solo) · trabajados · en descanso · citas · reactivados · movidos por otra vía (E14) · último
// intento. Todo número se abre en su lista. «Recoger» (B9) devuelve a «sin repartir» lo que ese analista no tocó (sin
// intento desde que se lo asignaron y sin seguimiento activo), tras confirmar.
import { useRef, useState } from 'react'
import { toast } from 'sonner'
import { Undo2, Users } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { PanelCargando } from '@/components/common/estado-panel'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { etiquetaMomento } from '@/lib/base-gestion'
import { CrmApiError } from '@/data/crm-api'
import { useRecogerDeBase, useSeguimientoBase, type PuertasBases } from '@/data/bases-cargadas-queries'
import { CIFRAS_ANALISTA, DIAS_SIN_TOCAR, ROTULO_CIFRA, esUrgenteSinTocar, type CifraAnalista, type FilaSeguimientoBase, type FilaSeguimientoBases } from '@/lib/bases-cargadas'
import { AvisoReintentar, CELDA_COMPACTA, DisponiblePronto, ENCABEZADO_COMPACTO, NumeroAbrible } from './piezas-bases'

const nombreDe = (f: FilaSeguimientoBase) => f.analista_nombre ?? 'Analista sin nombre'

export function SeguimientoAnalistas({ puertas, base, esMovil, ahora, onAbrirCifra }: {
  puertas: PuertasBases
  base: FilaSeguimientoBases
  esMovil: boolean
  ahora: number
  onAbrirCifra: (fila: FilaSeguimientoBase, cifra: CifraAnalista) => void
}) {
  const seguimiento = useSeguimientoBase(puertas, base.base_id)
  const [recoger, setRecoger] = useState<FilaSeguimientoBase | null>(null)

  if (seguimiento.isPending) return <div className="rounded-lg border border-border bg-card pt-4"><PanelCargando filas={3} /></div>
  if (seguimiento.isError && seguimiento.data === undefined) {
    return <AvisoReintentar mensaje="No se pudo cargar el seguimiento por analista." reintentando={seguimiento.isFetching} onReintentar={() => void seguimiento.refetch()} />
  }
  if (seguimiento.data === null) {
    return <DisponiblePronto titulo="Seguimiento por analista: disponible pronto" detalle="Llega con la próxima actualización del servidor." />
  }
  const filas = seguimiento.data ?? []
  const cifra = (f: FilaSeguimientoBase, c: CifraAnalista) => (
    <NumeroAbrible valor={f[c]} contexto={`${nombreDe(f)}, ${ROTULO_CIFRA[c].toLowerCase()}`} urgente={c === 'sin_tocar_3_dias'} onAbrir={() => onAbrirCifra(f, c)} />
  )
  const botonRecoger = (f: FilaSeguimientoBase) => f.sin_tocar > 0 ? (
    <Button type="button" variant="outline" size="sm" className="pointer-coarse:h-11" aria-label={`Recoger lo que ${nombreDe(f)} no tocó`} onClick={() => setRecoger(f)}>
      <Undo2 aria-hidden /> Recoger
    </Button>
  ) : <span className="text-[13px] text-[var(--muted-foreground-strong)]">Nada por recoger</span>

  return (
    <div className="space-y-2">
      {seguimiento.isError && <AvisoReintentar mensaje="No se pudo actualizar el seguimiento. Se muestran los últimos datos." reintentando={seguimiento.isFetching} onReintentar={() => void seguimiento.refetch()} />}
      {filas.length === 0 ? (
        <div className="flex items-center gap-3 rounded-lg border border-border bg-card px-4 py-3">
          <Users className="size-4 shrink-0 text-[var(--muted-foreground-strong)]" aria-hidden />
          <p className="text-sm text-[var(--muted-foreground-strong)]">Aún no repartiste esta base. Cuando lo hagas, aquí verás cómo la trabaja cada analista.</p>
        </div>
      ) : esMovil ? (
        <div role="list" aria-label={`Seguimiento de ${base.nombre} por analista`} className="space-y-2">
          {filas.map((f) => (
            <div role="listitem" key={f.analista_id} className={cn('rounded-xl border bg-card p-3', esUrgenteSinTocar(f) ? 'border-destructive/40 shadow-[inset_4px_0_0_var(--destructive)]' : 'border-border')}>
              <p className="text-[15px] font-bold text-primary">{nombreDe(f)}</p>
              <dl className="mt-2 grid grid-cols-2 gap-x-2 gap-y-1">
                {CIFRAS_ANALISTA.map((c) => (
                  <div key={c} className="flex min-w-0 flex-row-reverse items-center justify-end gap-1">
                    <dt className="min-w-0 text-[13px] leading-tight text-[var(--muted-foreground-strong)]">{ROTULO_CIFRA[c]}</dt>
                    <dd className="min-w-10 shrink-0 text-center text-base">{cifra(f, c)}</dd>
                  </div>
                ))}
              </dl>
              <p className="mt-2 text-[13px] text-[var(--muted-foreground-strong)]">Último intento: {f.ultimo_intento_en ? etiquetaMomento(f.ultimo_intento_en, ahora) : 'ninguno'}</p>
              <div className="mt-2">{botonRecoger(f)}</div>
            </div>
          ))}
        </div>
      ) : (
        // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Con muchos analistas la hoja se desplaza con el teclado.
        <div tabIndex={0} role="region" aria-label={`Seguimiento de ${base.nombre} por analista`} className={cn('ac-scroll max-h-[24rem] scroll-pt-10 overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)}>
          <table className="min-w-full border-separate border-spacing-0">
            <caption className="sr-only">
              Cómo trabaja cada analista los contactos de {base.nombre}. En rojo, los que llevan {DIAS_SIN_TOCAR} días o más sin tocar. Cada número abre su lista.
            </caption>
            <thead>
              <tr>
                <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left')}>Analista</th>
                {CIFRAS_ANALISTA.map((c) => <th key={c} scope="col" className={cn(ENCABEZADO_COMPACTO, 'min-w-16 whitespace-normal text-right leading-tight', c === 'sin_tocar_3_dias' && 'text-[var(--destructive-text)]')}>{ROTULO_CIFRA[c]}</th>)}
                <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'whitespace-normal text-left leading-tight')}>Último intento</th>
                <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left')}><span className="sr-only">Acción</span></th>
              </tr>
            </thead>
            <tbody>
              {filas.map((f) => (
                <tr key={f.analista_id} className={esUrgenteSinTocar(f) ? 'bg-destructive/[0.04]' : 'hover:bg-accent/5'}>
                  <th scope="row" className={cn(CELDA_COMPACTA, 'text-left font-semibold text-primary', esUrgenteSinTocar(f) && 'shadow-[inset_3px_0_0_var(--destructive)]')}>{nombreDe(f)}</th>
                  {CIFRAS_ANALISTA.map((c) => <td key={c} className={cn(CELDA_COMPACTA, 'text-right')}>{cifra(f, c)}</td>)}
                  <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{f.ultimo_intento_en ? etiquetaMomento(f.ultimo_intento_en, ahora) : <span className="text-[var(--muted-foreground-strong)]">Ninguno</span>}</td>
                  <td className={CELDA_COMPACTA}>{botonRecoger(f)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <RecogerDialogo puertas={puertas} base={base} fila={recoger} onCerrar={() => setRecoger(null)} />
    </div>
  )
}

function RecogerDialogo({ puertas, base, fila, onCerrar }: { puertas: PuertasBases; base: FilaSeguimientoBases; fila: FilaSeguimientoBase | null; onCerrar: () => void }) {
  const mutacion = useRecogerDeBase(puertas)
  const [error, setError] = useState<string | null>(null)
  // Un id por diálogo abierto: el reintento tras un corte devuelve lo mismo (no recoge dos veces).
  const operacion = useRef<{ analista: string; id: string } | null>(null)
  const cerrar = () => { if (mutacion.isPending) return; setError(null); operacion.current = null; onCerrar() }
  const confirmar = async () => {
    if (!fila || mutacion.isPending) return
    if (operacion.current?.analista !== fila.analista_id) operacion.current = { analista: fila.analista_id, id: crypto.randomUUID() }
    setError(null)
    try {
      const r = await mutacion.mutateAsync({ operacionId: operacion.current.id, baseId: base.base_id, analistaId: fila.analista_id })
      toast.success(`Recogidos ${r.recogidos}: vuelven a «sin repartir».${r.omitidos > 0 ? ` ${r.omitidos} se quedan con ${nombreDe(fila)} (los trabajó o tienen seguimiento activo).` : ''}`)
      operacion.current = null
      onCerrar()
    } catch (causa: unknown) {
      setError(causa instanceof CrmApiError ? causa.message : 'No se pudo recoger. Vuelve a intentarlo.')
    }
  }
  return (
    <Dialog open={fila !== null} onClose={cerrar}>
      {fila && (
        <>
          <DialogHeader>
            <DialogTitle>¿Recoger lo que {nombreDe(fila)} no tocó?</DialogTitle>
            <DialogDescription id="recoger-consecuencia" className="text-sm">
              Vuelven a «sin repartir» los contactos de «{base.nombre}» que no intentó desde que se los asignaste (hoy, {fila.sin_tocar}). Los que ya trabajó o tienen seguimiento activo se quedan con {nombreDe(fila)}.
            </DialogDescription>
          </DialogHeader>
          <DialogBody>
            {error ? <p role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{error}</p> : <p className="text-sm text-[var(--muted-foreground-strong)]">Después podrás repartirlos a otro analista.</p>}
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={cerrar}>Cancelar</Button>
            <Button type="button" aria-disabled={mutacion.isPending || undefined} aria-describedby="recoger-consecuencia" onClick={() => void confirmar()}>
              <Undo2 aria-hidden /> {mutacion.isPending ? 'Recogiendo…' : 'Recoger'}
            </Button>
          </DialogFooter>
        </>
      )}
    </Dialog>
  )
}
