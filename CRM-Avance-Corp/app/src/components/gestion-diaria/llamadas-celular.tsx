// Pestaña «Llamadas del celular» de la Gestión Diaria del analista (F4-b, F4-PLAN-CORTO.md §2 y el prototipo que le
// gustó a Miguel). Presentacional: recibe las llamadas y avisa qué eligió el analista; quién las trae (la demo o las
// puertas, cuando estén los tipos) y qué hace cada acción lo decide la pantalla.
// «Pendientes»: lo que el celular avisó y todavía no tiene resultado (cerrar la encuesta sin registrar no las quita).
// «Qué pasó hoy»: lo resuelto del día, con su resultado o su motivo y cómo se resolvió.
// La pestaña es la red de seguridad: el objetivo es que la encuesta se abra siempre al colgar (Jhosep, 03/10).
import { useEffect, useId, useRef, useState, type FormEvent, type JSX } from 'react'
import { PhoneCall } from 'lucide-react'
import { BusquedaManual } from '@/components/app/receptor-llamada'
import { PanelVacio } from '@/components/common/estado-panel'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import type { EstadoListaCelular } from '@/data/use-llamadas-celular'
import type { OpcionesResolucion } from '@/data/coincidencia-llamada'
import { digitosParaBuscar } from '@/lib/coincidencia-telefono'
import {
  MOTIVOS_DESCARTE, accionPrincipal, comoSeResolvio, cuandoFue, estadoPendiente, estadoResuelta, lineaPendiente,
  lineaResultadoGuardado, llegoTarde, momentoDeLlamada, numeroLegible, puedeRegistrarCorregido, puedeUnir, retrasoPendiente,
  type FilaBandeja, type MotivoDescarte, type ResueltaHoy, type ResultadoGuardado,
} from '@/lib/llamadas-celular'
import type { Lead } from '@/lib/tipos'
import { cn } from '@/lib/utils'

export interface LlamadasCelularProps {
  estadoPendientes?: EstadoListaCelular
  estadoResueltas?: EstadoListaCelular
  pendientes: readonly FilaBandeja[]
  resueltas: readonly ResueltaHoy[]
  ahora: number
  /** evento_id con una acción en curso: sus botones esperan. */
  ocupado?: string | null | undefined
  /** Para «Elegir el lead»: la misma búsqueda del receptor de F1. */
  busqueda: OpcionesResolucion
  onRegistrar: (fila: FilaBandeja) => void
  /** «Registrar el corregido» de una resuelta deshecha: la misma encuesta con el id de su llamada (hallazgo de P9). */
  onCorregir?: ((fila: ResueltaHoy) => void) | undefined
  onElegirLead: (fila: FilaBandeja, lead: Lead) => void
  onDescartar: (fila: FilaBandeja, motivo: MotivoDescarte, detalle: string | null) => void
  /** Unir a mano (F4.2.4, B7): los candidatos del lead y la unión. Sin las dos, el botón no aparece. */
  onBuscarResultados?: ((fila: FilaBandeja, signal?: AbortSignal) => Promise<ResultadoGuardado[]>) | undefined
  onUnir?: ((fila: FilaBandeja, resultado: ResultadoGuardado) => void) | undefined
  onAbrirFicha: (leadId: string) => void
}

type Vista = 'pendientes' | 'hoy'
type ModoPanel = 'descartar' | 'elegir' | 'unir'
type Panel = { evento: string; modo: ModoPanel } | null

const BOTON_VISTA = 'inline-flex h-9 items-center rounded-full border px-3 text-[13px] font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11'
const NOMBRE = 'rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const APOYO = 'text-xs text-[var(--muted-foreground-strong)]'

export function LlamadasCelular(props: LlamadasCelularProps): JSX.Element {
  const { pendientes, resueltas } = props
  const [vista, setVista] = useState<Vista>('pendientes')
  const [panel, setPanel] = useState<Panel>(null)
  const titulo = useRef<HTMLHeadingElement>(null)
  const estado = vista === 'pendientes' ? props.estadoPendientes : props.estadoResueltas
  const devolverFoco = () => { requestAnimationFrame(() => titulo.current?.focus()) }
  const { onUnir } = props
  const acciones = { ...props,
    onDescartar: (...args: Parameters<LlamadasCelularProps['onDescartar']>) => { props.onDescartar(...args); devolverFoco() },
    onElegirLead: (...args: Parameters<LlamadasCelularProps['onElegirLead']>) => { props.onElegirLead(...args); devolverFoco() },
    onUnir: onUnir === undefined ? undefined : (...args: Parameters<typeof onUnir>) => { onUnir(...args); devolverFoco() },
  }
  const vistas: [Vista, string][] = [['pendientes', `Pendientes · ${pendientes.length}`], ['hoy', `Qué pasó hoy · ${resueltas.length}`]]
  return (
    <div className="px-[18px] py-4">
      <h3 ref={titulo} tabIndex={-1} className="text-[15px] font-extrabold text-primary">Llamadas del celular</h3>
      <div role="group" aria-label="Qué llamadas ver" className="mt-2 flex flex-wrap gap-2">
        {vistas.map(([valor, texto]) => (
          <button key={valor} type="button" aria-pressed={vista === valor} onClick={() => { setVista(valor); setPanel(null) }}
            className={cn(BOTON_VISTA, vista === valor ? 'border-primary bg-primary text-white' : 'border-border bg-card text-foreground hover:bg-muted')}>
            {texto}
          </button>
        ))}
      </div>
      {estado?.error && <div role="alert" className="mt-3 text-sm">
        No se pudieron actualizar las llamadas. Comprueba la conexión y vuelve a intentarlo.
        <Button variant="outline" className="ml-2" onClick={estado.reintentar}>Reintentar</Button>
      </div>}
      {estado?.cargando && !estado.error ? <p role="status" className="mt-3 text-sm">Cargando llamadas…</p> : vista === 'pendientes' ? (
        <>
          <p className={cn(APOYO, 'mt-2')}>
            Llamadas que hiciste desde tu celular y todavía no tienen resultado. Cerrar la encuesta sin registrar no las quita de aquí.
          </p>
          {pendientes.length === 0 && !estado?.error ? (
            <PanelVacio icono={PhoneCall} titulo="Nada pendiente" detalle="Todo lo que llamaste desde el celular tiene resultado." />
          ) : (
            // oxlint-disable-next-line jsx-a11y/no-redundant-roles -- Safari quita el rol de lista a un <ol> sin viñetas.
            <ol role="list" aria-label="Llamadas pendientes" className="mt-2">
              {pendientes.map((fila) => (
                <FilaPendiente key={fila.evento_id} fila={fila} {...acciones}
                  panel={panel?.evento === fila.evento_id ? panel.modo : null}
                  onPanel={(modo) => setPanel(modo ? { evento: fila.evento_id, modo } : null)} />
              ))}
            </ol>
          )}
        </>
      ) : (
        <>
          <p className={cn(APOYO, 'mt-2')}>Las llamadas de hoy desde tu celular que ya resolviste, y cómo.</p>
          {resueltas.length === 0 && !estado?.error ? (
            <PanelVacio icono={PhoneCall} titulo="Todavía nada resuelto hoy" detalle="Lo que registres o descartes aparecerá aquí." />
          ) : (
            // oxlint-disable-next-line jsx-a11y/no-redundant-roles -- Safari quita el rol de lista a un <ol> sin viñetas.
            <ol role="list" aria-label="Llamadas resueltas hoy" className="mt-2">
              {resueltas.map((r) => (
                <FilaResuelta key={r.evento_id} r={r} ahora={props.ahora} ocupado={props.ocupado} onAbrirFicha={props.onAbrirFicha} onCorregir={props.onCorregir} />
              ))}
            </ol>
          )}
        </>
      )}
      {estado?.hayMas && <Button variant="outline" className="mt-3" disabled={estado.cargandoMas} onClick={estado.cargarMas}>
        {estado.cargandoMas ? 'Cargando más…' : 'Cargar más llamadas'}
      </Button>}
    </div>
  )
}

function Titulo({ leadId, nombre, numero, onAbrirFicha }: {
  leadId: string | null; nombre: string | null; numero: string | null; onAbrirFicha: (leadId: string) => void
}): JSX.Element {
  if (leadId && nombre) return <button type="button" onClick={() => onAbrirFicha(leadId)} className={NOMBRE}>{nombre}</button>
  return <span className="text-sm font-bold text-primary">{numeroLegible(numero)}</span>
}

function FilaPendiente({ fila, ahora, ocupado, busqueda, panel, onPanel, onRegistrar, onElegirLead, onDescartar, onBuscarResultados, onUnir, onAbrirFicha }:
  LlamadasCelularProps & { fila: FilaBandeja; panel: ModoPanel | null; onPanel: (modo: ModoPanel | null) => void }): JSX.Element {
  const retraso = retrasoPendiente(fila, ahora)
  const principal = accionPrincipal(fila)
  const unible = onUnir !== undefined && onBuscarResultados !== undefined && puedeUnir(fila)
  const enEspera = ocupado != null
  const volverA = useRef<HTMLButtonElement>(null)
  const volverAUnir = useRef<HTMLButtonElement>(null)
  // El botón se lee dentro del siguiente cuadro: la fila de acciones vuelve a montarse al cerrar el panel.
  const cerrarPanel = () => {
    const volver = panel === 'unir' ? volverAUnir : volverA
    onPanel(null)
    requestAnimationFrame(() => volver.current?.focus())
  }
  return (
    <li className="border-b border-muted py-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <Titulo leadId={fila.lead_id} nombre={fila.lead_nombre} numero={fila.numero} onAbrirFicha={onAbrirFicha} />
            <Badge color={fila.atencion === 'requiere_resultado' ? 'var(--primary)' : 'var(--warning-text)'}>{estadoPendiente(fila.atencion)}</Badge>
            {retraso && <Badge color="var(--destructive-text)">{retraso}</Badge>}
          </div>
          <p className={APOYO}>{lineaPendiente(fila, ahora)}</p>
          {llegoTarde(fila) && (
            <p className={APOYO}>El aviso llegó {cuandoFue(Date.parse(fila.recibido_en), ahora)}: el celular estuvo sin señal.</p>
          )}
        </div>
        {panel === null && (
          <div className="flex flex-wrap gap-2">
            {principal === 'registrar' ? (
              <Button size="sm" variant="accent" className="pointer-coarse:h-11" disabled={enEspera} onClick={() => onRegistrar(fila)}>
                Registrar resultado
              </Button>
            ) : (
              <Button ref={volverA} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" disabled={enEspera} onClick={() => onPanel('elegir')}>
                Elegir el lead
              </Button>
            )}
            {unible && (
              <Button ref={volverAUnir} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" disabled={enEspera} onClick={() => onPanel('unir')}>
                Unir a un resultado guardado
              </Button>
            )}
            <Button ref={principal === 'registrar' ? volverA : undefined} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11"
              disabled={enEspera} onClick={() => onPanel('descartar')}>
              Descartar
            </Button>
          </div>
        )}
      </div>
      {panel === 'descartar' && (
        <PanelDescarte onCancelar={cerrarPanel} onConfirmar={(motivo, detalle) => { onPanel(null); onDescartar(fila, motivo, detalle) }} />
      )}
      {panel === 'unir' && onBuscarResultados && onUnir && (
        <PanelUnir fila={fila} ahora={ahora} buscar={onBuscarResultados} onCancelar={cerrarPanel}
          onConfirmar={(r) => { onPanel(null); onUnir(fila, r) }} />
      )}
      {panel === 'elegir' && (
        <div role="group" aria-label="Elegir el lead de esta llamada" className="mt-2 space-y-2 rounded-xl border border-border bg-muted/40 p-3">
          <p className="text-[13px] font-extrabold text-primary">¿A cuál de tus leads llamaste?</p>
          <BusquedaManual inicial={digitosParaBuscar(fila.numero ?? '') ?? ''} manual={busqueda}
            onElegir={(lead) => { onPanel(null); onElegirLead(fila, lead) }} />
          <Button size="sm" variant="ghost" className="text-foreground pointer-coarse:h-11" onClick={cerrarPanel}>Cancelar</Button>
        </div>
      )}
    </li>
  )
}

function PanelDescarte({ onConfirmar, onCancelar }: {
  onConfirmar: (motivo: MotivoDescarte, detalle: string | null) => void
  onCancelar: () => void
}): JSX.Element {
  const id = useId()
  const grupo = useRef<HTMLDivElement>(null)
  const [otro, setOtro] = useState(false)
  const [texto, setTexto] = useState('')
  // Al abrirse, el foco va al primer motivo: quien pulsó «Descartar» sigue con el teclado donde estaba.
  useEffect(() => { grupo.current?.querySelector<HTMLButtonElement>('button')?.focus() }, [])
  const enviar = (e: FormEvent) => {
    e.preventDefault()
    if (texto.trim().length >= 3) onConfirmar('otro', texto.trim())
  }
  return (
    <div ref={grupo} role="group" aria-labelledby={`${id}-titulo`} className="mt-2 space-y-2 rounded-xl border border-border bg-muted/40 p-3">
      <p id={`${id}-titulo`} className="text-[13px] font-extrabold text-primary">¿Por qué la descartas?</p>
      <p className={APOYO}>No cuenta como gestión del lead.</p>
      <div className="flex flex-wrap gap-2">
        {MOTIVOS_DESCARTE.filter((m) => m.clave !== 'otro').map((m) => (
          <Button key={m.clave} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" onClick={() => onConfirmar(m.clave, null)}>
            {m.etiqueta}
          </Button>
        ))}
        <Button size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" aria-expanded={otro} onClick={() => setOtro(true)}>Otro motivo</Button>
        <Button size="sm" variant="ghost" className="text-foreground pointer-coarse:h-11" onClick={onCancelar}>Cancelar</Button>
      </div>
      {otro && (
        <form onSubmit={enviar} className="flex flex-wrap items-center gap-2">
          <label htmlFor={`${id}-otro`} className="sr-only">Escribe el motivo</label>
          <input id={`${id}-otro`} value={texto} onChange={(e) => setTexto(e.target.value)} maxLength={300} placeholder="Escribe el motivo"
            className="h-9 min-w-0 flex-1 rounded-lg border border-input bg-background px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:border-ring focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30 pointer-coarse:h-11" />
          <Button type="submit" size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" disabled={texto.trim().length < 3}>Descartar</Button>
        </form>
      )}
    </div>
  )
}

type EstadoUnir = { fase: 'cargando' } | { fase: 'error' } | { fase: 'lista'; resultados: ResultadoGuardado[] }

/**
 * «¿Es este su resultado?» (F4.2.4, B7): los resultados del lead guardados después de la llamada y sin unir, que trae la
 * pantalla; elegir uno los une sin crear otra gestión. Los candidatos se piden al abrir (no por fila) y la decisión final
 * es del servidor: si rechaza, la pantalla muestra su motivo.
 */
function PanelUnir({ fila, ahora, buscar, onConfirmar, onCancelar }: {
  fila: FilaBandeja; ahora: number
  buscar: (fila: FilaBandeja, signal?: AbortSignal) => Promise<ResultadoGuardado[]>
  onConfirmar: (resultado: ResultadoGuardado) => void
  onCancelar: () => void
}): JSX.Element {
  const id = useId()
  const grupo = useRef<HTMLDivElement>(null)
  const [estado, setEstado] = useState<EstadoUnir>({ fase: 'cargando' })
  const [intento, setIntento] = useState(0)
  useEffect(() => {
    const control = new AbortController()
    setEstado({ fase: 'cargando' })
    buscar(fila, control.signal)
      .then((resultados) => { if (!control.signal.aborted) setEstado({ fase: 'lista', resultados }) })
      .catch(() => { if (!control.signal.aborted) setEstado({ fase: 'error' }) })
    return () => control.abort()
  }, [buscar, fila, intento])
  // Al abrirse, el foco va al panel (la lista llega después): quien pulsó «Unir…» sigue con el teclado donde estaba.
  useEffect(() => { grupo.current?.focus() }, [])
  return (
    <div ref={grupo} tabIndex={-1} role="group" aria-labelledby={`${id}-titulo`}
      className="mt-2 space-y-2 rounded-xl border border-border bg-muted/40 p-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
      <p id={`${id}-titulo`} className="text-[13px] font-extrabold text-primary">¿Es este su resultado?</p>
      <p className={APOYO}>Resultados de este lead guardados después de la llamada y sin unir a otra. Unir no crea otra gestión.</p>
      {estado.fase === 'cargando' && <p role="status" className="text-sm">Buscando resultados guardados…</p>}
      {estado.fase === 'error' && (
        <div role="alert" className="text-sm">
          No se pudieron cargar los resultados del lead.
          <Button size="sm" variant="outline" className="ml-2 text-foreground pointer-coarse:h-11" onClick={() => setIntento((n) => n + 1)}>Reintentar</Button>
        </div>
      )}
      {estado.fase === 'lista' && (estado.resultados.length === 0 ? (
        <p className="text-sm">
          No hay resultados de este lead guardados después de esta llamada. Si lo guardaste hace un momento, espera y vuelve a
          intentar; si no, regístralo con «Registrar resultado».
        </p>
      ) : (
        <ul aria-label="Resultados guardados" className="space-y-2">
          {estado.resultados.map((r) => (
            <li key={r.id}>
              <Button size="sm" variant="outline" className="h-auto min-h-9 whitespace-normal text-left text-foreground pointer-coarse:min-h-11" onClick={() => onConfirmar(r)}>
                {lineaResultadoGuardado(r, ahora)}
              </Button>
            </li>
          ))}
        </ul>
      ))}
      <Button size="sm" variant="ghost" className="text-foreground pointer-coarse:h-11" onClick={onCancelar}>Cancelar</Button>
    </div>
  )
}

function FilaResuelta({ r, ahora, ocupado, onAbrirFicha, onCorregir }: {
  r: ResueltaHoy; ahora: number; ocupado?: string | null | undefined
  onAbrirFicha: (leadId: string) => void; onCorregir?: ((fila: ResueltaHoy) => void) | undefined
}): JSX.Element {
  const registrada = r.atencion === 'registrado'
  const corregible = onCorregir !== undefined && puedeRegistrarCorregido(r)
  return (
    <li className="flex flex-wrap items-center justify-between gap-2 border-b border-muted py-2.5">
      <div className="min-w-0 space-y-0.5">
        <Titulo leadId={r.lead_id} nombre={r.lead_nombre} numero={r.numero} onAbrirFicha={onAbrirFicha} />
        <p className={APOYO}>{comoSeResolvio(r)} · llamada {cuandoFue(momentoDeLlamada(r), ahora)}</p>
        {corregible && <p className={APOYO}>Deshiciste su resultado: registra el correcto para que esta llamada quede con él.</p>}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Badge color={registrada && !r.deshecho ? 'var(--primary)' : 'var(--muted-foreground-strong)'}>{estadoResuelta(r)}</Badge>
        {corregible && (
          <Button size="sm" variant="accent" className="pointer-coarse:h-11" disabled={ocupado != null} onClick={() => onCorregir(r)}>
            Registrar el corregido
          </Button>
        )}
      </div>
    </li>
  )
}
