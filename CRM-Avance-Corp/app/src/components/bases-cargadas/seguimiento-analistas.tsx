// Seguimiento de una base POR ANALISTA (F5, `crm.seguimiento_base`, B10): asignados · sin tocar · sin tocar 3 días (en
// ROJO: E6, nada se mueve solo) · trabajados · en descanso · citas · reactivados · último intento, y en «Salieron» las
// pastillas de los movidos por otra vía (E14), retirados y «No contactar» (solo las que tienen algo). Todo número se abre en
// su lista, salvo los de un analista de OTRO equipo (el servidor no lo identifica: sin filtro posible, se leen y no se abren). «Recoger» (B9) devuelve a «sin repartir» lo que ese analista no tocó (sin
// intento desde que se lo asignaron y sin seguimiento activo), tras confirmar. Al cerrar el diálogo el foco vuelve al botón
// que lo abrió; si se recogió (el botón puede volverse «Nada por recoger»), a la hoja del seguimiento: nunca a <body>.
import { useEffect, useId, useRef, useState, type MouseEvent, type RefObject } from 'react'
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
import {
  CIFRAS_ANALISTA,
  CIFRAS_SALIDA,
  DIAS_SIN_TOCAR,
  ROTULO_CIFRA,
  TEXTO_ANALISTA_OTRO_EQUIPO,
  esCifraSalida,
  esUrgenteSinTocar,
  type CifraAnalista,
  type FilaSeguimientoBase,
  type FilaSeguimientoBases,
  type RespuestaRecoger,
} from '@/lib/bases-cargadas'
import { AvisoReintentar, CELDA_COMPACTA, DisponiblePronto, ENCABEZADO_COMPACTO, NumeroAbrible, PastillasSalida } from './piezas-bases'

const nombreDe = (f: FilaSeguimientoBase) => (f.analista_id === null ? TEXTO_ANALISTA_OTRO_EQUIPO : f.analista_nombre ?? 'Analista sin nombre')
/** Las cifras en columna; las de los que salieron van como pastillas en «Salieron». */
const CIFRAS_COLUMNA = CIFRAS_ANALISTA.filter((c) => !esCifraSalida(c))
const SIN_ABRIR_OTRO_EQUIPO = 'No se abre: el analista es de otro equipo y no puedes ver sus contactos'

export function SeguimientoAnalistas({ puertas, base, esMovil, ahora, onAbrirCifra, tituloRef }: {
  puertas: PuertasBases
  base: FilaSeguimientoBases
  esMovil: boolean
  ahora: number
  onAbrirCifra: (fila: FilaSeguimientoBase, cifra: CifraAnalista) => void
  /** El título de la sección (enfocable): el último respaldo del foco tras recoger. */
  tituloRef?: RefObject<HTMLElement | null>
}) {
  const seguimiento = useSeguimientoBase(puertas, base.base_id)
  const [recoger, setRecoger] = useState<FilaSeguimientoBase | null>(null)
  const hoja = useRef<HTMLDivElement>(null)
  const vacio = useRef<HTMLDivElement>(null)
  // Adónde vuelve el foco al cerrar «Recoger» sin recoger: el botón que lo abrió.
  const focoTrasRecoger = useRef<HTMLElement | null>(null)
  const abrirRecoger = (f: FilaSeguimientoBase, e: MouseEvent<HTMLButtonElement>) => { focoTrasRecoger.current = e.currentTarget; setRecoger(f) }
  // Tras recoger, el botón puede volverse «Nada por recoger» y la hoja, vaciarse: el foco va a lo que haya cuando el diálogo
  // termine de cerrarse (la hoja, el aviso de vacío o el título de la sección), nunca a <body>.
  const [recogido, setRecogido] = useState(0)
  useEffect(() => {
    if (recogido === 0) return
    let segundo = 0
    const primero = requestAnimationFrame(() => {
      segundo = requestAnimationFrame(() => (hoja.current ?? vacio.current ?? tituloRef?.current)?.focus())
    })
    return () => { cancelAnimationFrame(primero); cancelAnimationFrame(segundo) }
  }, [recogido, tituloRef])

  if (seguimiento.isPending) return <div className="rounded-lg border border-border bg-card pt-4"><PanelCargando filas={3} /></div>
  if (seguimiento.isError && seguimiento.data === undefined) {
    return <AvisoReintentar mensaje="No se pudo cargar el seguimiento por analista." reintentando={seguimiento.isFetching} onReintentar={() => void seguimiento.refetch()} />
  }
  if (seguimiento.data === null) {
    return <DisponiblePronto titulo="Seguimiento por analista: disponible pronto" detalle="Llega con la próxima actualización del servidor." />
  }
  const filas = seguimiento.data ?? []
  const cifra = (f: FilaSeguimientoBase, c: CifraAnalista) => (
    <NumeroAbrible
      valor={f[c]}
      contexto={`${nombreDe(f)}, ${ROTULO_CIFRA[c].toLowerCase()}`}
      urgente={c === 'sin_tocar_3_dias'}
      onAbrir={f.analista_id === null ? undefined : () => onAbrirCifra(f, c)}
      motivoSinAbrir={SIN_ABRIR_OTRO_EQUIPO}
    />
  )
  const salieron = (f: FilaSeguimientoBase) => (
    <PastillasSalida
      cifras={CIFRAS_SALIDA.map((c) => ({ clave: c, rotulo: ROTULO_CIFRA[c], valor: f[c] }))}
      contexto={nombreDe(f)}
      onAbrir={f.analista_id === null ? undefined : (c) => onAbrirCifra(f, c as CifraAnalista)}
      motivoSinAbrir={SIN_ABRIR_OTRO_EQUIPO}
    />
  )
  // Un analista de otro equipo no se puede recoger (no es tuyo): se dice, sin botón.
  // El porqué se dice UNA vez por fila con texto (el `title` de las cifras es solo apoyo para el ratón).
  const botonRecoger = (f: FilaSeguimientoBase) => f.analista_id === null
    ? (
      <span className="text-[13px] text-[var(--muted-foreground-strong)]">
        De otro equipo<span className="sr-only">: sus cifras no se abren porque no puedes ver sus contactos</span>
      </span>
    )
    : f.sin_tocar > 0 ? (
    <Button type="button" variant="outline" size="sm" className="pointer-coarse:h-11" aria-label={`Recoger lo que ${nombreDe(f)} no tocó`} onClick={(e) => abrirRecoger(f, e)}>
      <Undo2 aria-hidden /> Recoger
    </Button>
  ) : <span className="text-[13px] text-[var(--muted-foreground-strong)]">Nada por recoger</span>

  return (
    <div className="space-y-2">
      {seguimiento.isError && <AvisoReintentar conDatos mensaje="No se pudo actualizar el seguimiento. Se muestran los últimos datos." reintentando={seguimiento.isFetching} onReintentar={() => void seguimiento.refetch()} />}
      {filas.length === 0 ? (
        <div ref={vacio} tabIndex={-1} className={cn('flex items-center gap-3 rounded-lg border border-border bg-card px-4 py-3', FOCO)}>
          <Users className="size-4 shrink-0 text-[var(--muted-foreground-strong)]" aria-hidden />
          <p className="text-sm text-[var(--muted-foreground-strong)]">Aún no repartiste esta base. Cuando lo hagas, aquí verás cómo la trabaja cada analista.</p>
        </div>
      ) : esMovil ? (
        <div ref={hoja} tabIndex={-1} role="list" aria-label={`Seguimiento de ${base.nombre} por analista`} className={cn('space-y-2 rounded-lg', FOCO)}>
          {filas.map((f, i) => (
            <div role="listitem" key={f.analista_id ?? `otro-equipo-${i}`} className={cn('rounded-xl border bg-card p-3', esUrgenteSinTocar(f) ? 'border-destructive/40 shadow-[inset_4px_0_0_var(--destructive)]' : 'border-border')}>
              <p className={cn('text-[15px] font-bold', f.analista_id === null ? 'italic text-[var(--muted-foreground-strong)]' : 'text-primary')}>{nombreDe(f)}</p>
              <dl className="mt-2 grid grid-cols-2 gap-x-2 gap-y-1">
                {CIFRAS_COLUMNA.map((c) => (
                  <div key={c} className="flex min-w-0 flex-row-reverse items-center justify-end gap-1">
                    <dt className="min-w-0 text-[13px] leading-tight text-[var(--muted-foreground-strong)]">{ROTULO_CIFRA[c]}</dt>
                    <dd className="min-w-10 shrink-0 text-center text-base">{cifra(f, c)}</dd>
                  </div>
                ))}
              </dl>
              <p className="mt-2 text-[13px]"><span className="text-[var(--muted-foreground-strong)]">Salieron: </span>{salieron(f)}</p>

              <p className="mt-2 text-[13px] text-[var(--muted-foreground-strong)]">Último intento: {f.ultimo_intento_en ? etiquetaMomento(f.ultimo_intento_en, ahora) : 'ninguno'}</p>
              {/* En táctil no hay `title`: el porqué de la fila de otro equipo va visible. */}
              {f.analista_id === null
                ? <p className="mt-2 text-[13px] text-[var(--muted-foreground-strong)]">De otro equipo · sus cifras no se abren<span className="sr-only"> porque no puedes ver sus contactos</span></p>
                : <div className="mt-2">{botonRecoger(f)}</div>}
            </div>
          ))}
        </div>
      ) : (
        // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Con muchos analistas la hoja se desplaza con el teclado.
        <div ref={hoja} tabIndex={0} role="region" aria-label={`Seguimiento de ${base.nombre} por analista`} className={cn('ac-scroll max-h-[24rem] scroll-pt-10 overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)}>
          <table className="min-w-full border-separate border-spacing-0">
            <caption className="sr-only">
              Cómo trabaja cada analista los contactos de {base.nombre}. En rojo, los que llevan {DIAS_SIN_TOCAR} días o más sin tocar. Cada número abre su lista, salvo los de un analista de otro equipo.
            </caption>
            <thead>
              <tr>
                <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left')}>Analista</th>
                {CIFRAS_COLUMNA.map((c) => <th key={c} scope="col" className={cn(ENCABEZADO_COMPACTO, 'min-w-16 whitespace-normal text-right leading-tight', c === 'sin_tocar_3_dias' && 'text-[var(--destructive-text)]')}>{ROTULO_CIFRA[c]}</th>)}
                <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left')}>Salieron</th>
                <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'whitespace-normal text-left leading-tight')}>Último intento</th>
                <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left')}><span className="sr-only">Acción</span></th>
              </tr>
            </thead>
            <tbody>
              {filas.map((f, i) => (
                <tr key={f.analista_id ?? `otro-equipo-${i}`} className={esUrgenteSinTocar(f) ? 'bg-destructive/[0.04]' : 'hover:bg-accent/5'}>
                  <th scope="row" className={cn(CELDA_COMPACTA, 'text-left font-semibold', f.analista_id === null ? 'italic text-[var(--muted-foreground-strong)]' : 'text-primary', esUrgenteSinTocar(f) && 'shadow-[inset_3px_0_0_var(--destructive)]')}>{nombreDe(f)}</th>
                  {CIFRAS_COLUMNA.map((c) => <td key={c} className={cn(CELDA_COMPACTA, 'text-right')}>{cifra(f, c)}</td>)}
                  <td className={CELDA_COMPACTA}>{salieron(f)}</td>
                  <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{f.ultimo_intento_en ? etiquetaMomento(f.ultimo_intento_en, ahora) : <span className="text-[var(--muted-foreground-strong)]">Ninguno</span>}</td>
                  <td className={CELDA_COMPACTA}>{botonRecoger(f)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <RecogerDialogo
        puertas={puertas}
        base={base}
        fila={recoger}
        focoAlCerrar={focoTrasRecoger}
        // El diálogo no lleva el foco a ningún lado (el efecto de arriba lo hace cuando la hoja ya se repintó).
        onRecogido={() => { focoTrasRecoger.current = null; setRecogido((n) => n + 1) }}
        onCerrar={() => setRecoger(null)}
      />
    </div>
  )
}

/** «Recogidos 12: vuelven a «sin repartir». 28 se quedan con ANA… · Quedan 3 por recoger: vuelve a pulsar «Recoger».» */
function avisoRecogido(r: RespuestaRecoger, nombre: string): string {
  return `Recogidos ${r.recogidos}: vuelven a «sin repartir».`
    + (r.omitidos > 0 ? ` ${r.omitidos} se quedan con ${nombre} (los trabajó o tienen seguimiento activo).` : '')
    + (r.pendientes > 0 ? ` Quedan ${r.pendientes} por recoger (van de a 500): vuelve a pulsar «Recoger».` : '')
}

function RecogerDialogo({ puertas, base, fila, focoAlCerrar, onRecogido, onCerrar }: {
  puertas: PuertasBases
  base: FilaSeguimientoBases
  fila: FilaSeguimientoBase | null
  focoAlCerrar: RefObject<HTMLElement | null>
  onRecogido: () => void
  onCerrar: () => void
}) {
  const idConsecuencia = useId()
  const mutacion = useRecogerDeBase(puertas)
  const [error, setError] = useState<string | null>(null)
  // Un id por diálogo abierto: el reintento tras un corte devuelve lo mismo (no recoge dos veces).
  const operacion = useRef<{ analista: string; id: string } | null>(null)
  const cerrar = () => { if (mutacion.isPending) return; setError(null); operacion.current = null; onCerrar() }
  const confirmar = async () => {
    // Solo se recoge de un analista identificado (uno de otro equipo no tiene botón).
    const analista = fila?.analista_id
    if (!fila || !analista || mutacion.isPending) return
    if (operacion.current?.analista !== analista) operacion.current = { analista, id: crypto.randomUUID() }
    const id = operacion.current.id
    setError(null)
    try {
      const r = await mutacion.mutateAsync({ operacionId: id, baseId: base.base_id, analistaId: analista })
      toast.success(avisoRecogido(r, nombreDe(fila)))
      operacion.current = null
      onRecogido()
      onCerrar()
    } catch (causa: unknown) {
      setError(causa instanceof CrmApiError ? causa.message : 'No se pudo recoger. Vuelve a intentarlo.')
    }
  }
  return (
    <Dialog open={fila !== null} onClose={cerrar} focoAlCerrar={focoAlCerrar}>
      {fila && (
        <>
          <DialogHeader>
            <DialogTitle>¿Recoger lo que {nombreDe(fila)} no tocó?</DialogTitle>
            <DialogDescription id={idConsecuencia} className="text-sm">
              Vuelven a «sin repartir» los contactos de «{base.nombre}» que no intentó desde que se los asignaste (hoy, {fila.sin_tocar}). Los que ya trabajó o tienen seguimiento activo se quedan con {nombreDe(fila)}.
            </DialogDescription>
          </DialogHeader>
          <DialogBody>
            {error ? <p role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{error}</p> : <p className="text-sm text-[var(--muted-foreground-strong)]">Después podrás repartirlos a otro analista.</p>}
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={cerrar}>Cancelar</Button>
            <Button type="button" aria-disabled={mutacion.isPending || undefined} aria-describedby={idConsecuencia} onClick={() => void confirmar()}>
              <Undo2 aria-hidden /> {mutacion.isPending ? 'Recogiendo…' : 'Recoger'}
            </Button>
          </DialogFooter>
        </>
      )}
    </Dialog>
  )
}
