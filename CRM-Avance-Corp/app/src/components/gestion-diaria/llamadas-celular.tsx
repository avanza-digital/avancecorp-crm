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
import type { OpcionesResolucion } from '@/data/coincidencia-llamada'
import { digitosParaBuscar } from '@/lib/coincidencia-telefono'
import {
  MOTIVOS_DESCARTE, accionPrincipal, comoSeResolvio, cuandoFue, estadoPendiente, estadoResuelta, lineaPendiente,
  llegoTarde, momentoDeLlamada, numeroLegible, retrasoPendiente,
  type FilaBandeja, type MotivoDescarte, type ResueltaHoy,
} from '@/lib/llamadas-celular'
import type { Lead } from '@/lib/tipos'
import { cn } from '@/lib/utils'

export interface LlamadasCelularProps {
  pendientes: readonly FilaBandeja[]
  resueltas: readonly ResueltaHoy[]
  ahora: number
  /** evento_id con una acción en curso: sus botones esperan. */
  ocupado?: string | null | undefined
  /** Para «Elegir el lead»: la misma búsqueda del receptor de F1. */
  busqueda: OpcionesResolucion
  onRegistrar: (fila: FilaBandeja) => void
  onElegirLead: (fila: FilaBandeja, lead: Lead) => void
  onDescartar: (fila: FilaBandeja, motivo: MotivoDescarte, detalle: string | null) => void
  onAbrirFicha: (leadId: string) => void
}

type Vista = 'pendientes' | 'hoy'
type Panel = { evento: string; modo: 'descartar' | 'elegir' } | null

const BOTON_VISTA = 'inline-flex h-9 items-center rounded-full border px-3 text-[13px] font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11'
const NOMBRE = 'rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const APOYO = 'text-xs text-[var(--muted-foreground-strong)]'

export function LlamadasCelular(props: LlamadasCelularProps): JSX.Element {
  const { pendientes, resueltas } = props
  const [vista, setVista] = useState<Vista>('pendientes')
  const [panel, setPanel] = useState<Panel>(null)
  const vistas: [Vista, string][] = [['pendientes', `Pendientes · ${pendientes.length}`], ['hoy', `Qué pasó hoy · ${resueltas.length}`]]
  return (
    <div className="px-[18px] py-4">
      <h3 className="text-[15px] font-extrabold text-primary">Llamadas del celular</h3>
      <div role="group" aria-label="Qué llamadas ver" className="mt-2 flex flex-wrap gap-2">
        {vistas.map(([valor, texto]) => (
          <button key={valor} type="button" aria-pressed={vista === valor} onClick={() => { setVista(valor); setPanel(null) }}
            className={cn(BOTON_VISTA, vista === valor ? 'border-accent bg-accent text-white' : 'border-border bg-card text-foreground hover:bg-muted')}>
            {texto}
          </button>
        ))}
      </div>
      {vista === 'pendientes' ? (
        <>
          <p className={cn(APOYO, 'mt-2')}>
            Llamadas que hiciste desde tu celular y todavía no tienen resultado. Cerrar la encuesta sin registrar no las quita de aquí.
          </p>
          {pendientes.length === 0 ? (
            <PanelVacio icono={PhoneCall} titulo="Nada pendiente" detalle="Todo lo que llamaste desde el celular tiene resultado." />
          ) : (
            // oxlint-disable-next-line jsx-a11y/no-redundant-roles -- Safari quita el rol de lista a un <ol> sin viñetas.
            <ol role="list" aria-label="Llamadas pendientes" className="mt-2">
              {pendientes.map((fila) => (
                <FilaPendiente key={fila.evento_id} fila={fila} {...props}
                  panel={panel?.evento === fila.evento_id ? panel.modo : null}
                  onPanel={(modo) => setPanel(modo ? { evento: fila.evento_id, modo } : null)} />
              ))}
            </ol>
          )}
        </>
      ) : (
        <>
          <p className={cn(APOYO, 'mt-2')}>Las llamadas de hoy desde tu celular que ya resolviste, y cómo.</p>
          {resueltas.length === 0 ? (
            <PanelVacio icono={PhoneCall} titulo="Todavía nada resuelto hoy" detalle="Lo que registres o descartes aparecerá aquí." />
          ) : (
            // oxlint-disable-next-line jsx-a11y/no-redundant-roles -- Safari quita el rol de lista a un <ol> sin viñetas.
            <ol role="list" aria-label="Llamadas resueltas hoy" className="mt-2">
              {resueltas.map((r) => <FilaResuelta key={r.evento_id} r={r} ahora={props.ahora} onAbrirFicha={props.onAbrirFicha} />)}
            </ol>
          )}
        </>
      )}
    </div>
  )
}

function Titulo({ leadId, nombre, numero, onAbrirFicha }: {
  leadId: string | null; nombre: string | null; numero: string | null; onAbrirFicha: (leadId: string) => void
}): JSX.Element {
  if (leadId && nombre) return <button type="button" onClick={() => onAbrirFicha(leadId)} className={NOMBRE}>{nombre}</button>
  return <span className="text-sm font-bold text-primary">{numeroLegible(numero)}</span>
}

function FilaPendiente({ fila, ahora, ocupado, busqueda, panel, onPanel, onRegistrar, onElegirLead, onDescartar, onAbrirFicha }:
  LlamadasCelularProps & { fila: FilaBandeja; panel: 'descartar' | 'elegir' | null; onPanel: (modo: 'descartar' | 'elegir' | null) => void }): JSX.Element {
  const retraso = retrasoPendiente(fila, ahora)
  const principal = accionPrincipal(fila)
  const enEspera = ocupado === fila.evento_id
  const volverA = useRef<HTMLButtonElement>(null)
  const cerrarPanel = () => { onPanel(null); requestAnimationFrame(() => volverA.current?.focus()) }
  return (
    <li className="border-b border-muted py-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <Titulo leadId={fila.lead_id} nombre={fila.lead_nombre} numero={fila.numero} onAbrirFicha={onAbrirFicha} />
            <Badge color={fila.atencion === 'requiere_resultado' ? 'var(--accent)' : 'var(--warning)'}>{estadoPendiente(fila.atencion)}</Badge>
            {retraso && <Badge color="var(--destructive)">{retraso}</Badge>}
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

function FilaResuelta({ r, ahora, onAbrirFicha }: { r: ResueltaHoy; ahora: number; onAbrirFicha: (leadId: string) => void }): JSX.Element {
  const registrada = r.atencion === 'registrado'
  return (
    <li className="flex flex-wrap items-center justify-between gap-2 border-b border-muted py-2.5">
      <div className="min-w-0 space-y-0.5">
        <Titulo leadId={r.lead_id} nombre={r.lead_nombre} numero={r.numero} onAbrirFicha={onAbrirFicha} />
        <p className={APOYO}>{comoSeResolvio(r)} · llamada {cuandoFue(momentoDeLlamada(r), ahora)}</p>
      </div>
      <Badge color={registrada && !r.deshecho ? 'var(--accent)' : 'var(--muted-foreground-strong)'}>{estadoResuelta(r)}</Badge>
    </li>
  )
}
