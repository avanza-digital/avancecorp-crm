import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import {
  AlertTriangle,
  ArrowRight,
  BookOpen,
  Check,
  ChevronLeft,
  Clock,
  HelpCircle,
  LoaderCircle,
  Minimize2,
  Search,
} from 'lucide-react'
import { consultarAyudaVendedor, mensajeDeError, obtenerInicioAyudaVendedor } from '@/data/crm-api'
import type { AccionAyudaVendedor, ResultadoConsultaAyudaVendedor } from '@/lib/ayuda-vendedor'
import type { Vista } from '@/lib/router'
import { Button } from '@/components/ui/button'

const ETIQUETA_VISTA: Record<Vista, string> = {
  hoy: 'Hoy',
  alertas: 'Pendientes',
  conversiones: 'Conversiones',
  'ranking-vendedores': 'Ranking',
  reuniones: 'Reuniones',
  metas: 'Metas',
  rendimiento: 'Equipo',
  'capital-cierres': 'Capital',
  pipeline: 'Pipeline',
  cartera: 'Leads',
  agenda: 'Agenda',
  'mi-cartera': 'Mi cartera',
  repartir: 'Repartir leads',
  derivaciones: 'Derivar leads',
  equipo: 'Equipo',
  config: 'Configuración',
  'config-usuarios': 'Usuarios y jerarquía',
  'config-productos': 'Productos',
  'config-metas': 'Metas',
  'config-sla': 'Tiempos de atención',
}

interface AyudaVendedorPanelProps {
  abierto: boolean
  onAbiertoChange: (abierto: boolean) => void
  vista: Vista
  onNavegar: (vista: Vista) => void
  onAbrirNuevoLead: () => void
}

export function AyudaVendedorPanel({
  abierto,
  onAbiertoChange,
  vista,
  onNavegar,
  onAbrirNuevoLead,
}: AyudaVendedorPanelProps) {
  // La ayuda del servidor todavía agrupa este flujo dentro del contexto
  // histórico de equipo. La interfaz lo presenta como módulo independiente.
  const contextoAyuda: Vista = vista === 'derivaciones' ? 'equipo' : vista
  const tituloId = useId()
  const inputRef = useRef<HTMLInputElement>(null)
  const resultadoRef = useRef<HTMLHeadingElement>(null)
  const secuenciaRef = useRef(0)
  const abortoConsultaRef = useRef<AbortController | null>(null)
  const [consulta, setConsulta] = useState('')
  const [buscando, setBuscando] = useState(false)
  const [preguntas, setPreguntas] = useState<readonly string[]>([])
  const [cargandoPreguntas, setCargandoPreguntas] = useState(false)
  const [errorPreguntas, setErrorPreguntas] = useState<string | null>(null)
  const [errorConsulta, setErrorConsulta] = useState<string | null>(null)
  const [revisionInicio, setRevisionInicio] = useState(0)
  const [resultado, setResultado] = useState<ResultadoConsultaAyudaVendedor | null>(null)
  const respuesta = resultado?.tipo === 'respuesta' ? resultado.respuesta : null
  const aclaracion = resultado?.tipo === 'aclaracion' ? resultado.aclaracion : null
  const sinResultado = resultado?.tipo === 'sin_resultado' ? resultado.consulta : null

  useEffect(() => {
    if (!abierto) return
    const controlador = new AbortController()
    setCargandoPreguntas(true)
    setErrorPreguntas(null)
    void obtenerInicioAyudaVendedor(contextoAyuda, controlador.signal)
      .then((inicio) => {
        if (controlador.signal.aborted) return
        setPreguntas(inicio.preguntas)
      })
      .catch((error: unknown) => {
        if (controlador.signal.aborted) return
        setPreguntas([])
        setErrorPreguntas(mensajeDeError(error, 'No se pudieron cargar las consultas frecuentes.'))
      })
      .finally(() => {
        if (!controlador.signal.aborted) setCargandoPreguntas(false)
      })
    return () => controlador.abort()
  }, [abierto, contextoAyuda, revisionInicio])

  useEffect(() => {
    if (!abierto || respuesta || aclaracion || buscando) return
    const cuadro = requestAnimationFrame(() => inputRef.current?.focus())
    return () => cancelAnimationFrame(cuadro)
  }, [abierto, aclaracion, buscando, respuesta])

  useEffect(() => {
    if (!abierto || (!respuesta && !aclaracion)) return
    resultadoRef.current?.focus({ preventScroll: true })
  }, [abierto, aclaracion, respuesta])

  useEffect(() => {
    if (!abierto) return
    const alTeclado = (evento: KeyboardEvent) => {
      if (evento.key === 'Escape') onAbiertoChange(false)
    }
    window.addEventListener('keydown', alTeclado)
    return () => window.removeEventListener('keydown', alTeclado)
  }, [abierto, onAbiertoChange])

  useEffect(
    () => () => {
      secuenciaRef.current += 1
      abortoConsultaRef.current?.abort()
    },
    [],
  )

  const consultar = async (texto: string) => {
    const limpio = texto.trim()
    if (!limpio) {
      inputRef.current?.focus()
      return
    }

    const secuencia = ++secuenciaRef.current
    abortoConsultaRef.current?.abort()
    const controlador = new AbortController()
    abortoConsultaRef.current = controlador
    setConsulta(limpio)
    setBuscando(true)
    setErrorConsulta(null)
    setResultado(null)
    try {
      const hallada = await consultarAyudaVendedor(limpio, contextoAyuda, controlador.signal)
      if (secuencia !== secuenciaRef.current) return
      setResultado(hallada)
    } catch (error: unknown) {
      if (controlador.signal.aborted || secuencia !== secuenciaRef.current) return
      setErrorConsulta(mensajeDeError(error, 'No se pudo consultar el manual. Intenta nuevamente.'))
    } finally {
      if (secuencia === secuenciaRef.current) {
        setBuscando(false)
        abortoConsultaRef.current = null
      }
    }
  }

  const alEnviar = (evento: FormEvent<HTMLFormElement>) => {
    evento.preventDefault()
    void consultar(consulta)
  }

  const volver = () => {
    secuenciaRef.current += 1
    abortoConsultaRef.current?.abort()
    abortoConsultaRef.current = null
    setBuscando(false)
    setResultado(null)
    setErrorConsulta(null)
    setConsulta('')
  }

  const ejecutarAccion = (accion: AccionAyudaVendedor) => {
    if (accion.tipo === 'nuevo_lead') {
      onAbrirNuevoLead()
      return
    }
    onNavegar(accion.vista)
  }

  if (!abierto) {
    const tituloPendiente = respuesta?.titulo ?? aclaracion?.titulo
    if (!tituloPendiente) return null
    return (
      <button
        type="button"
        onClick={() => onAbiertoChange(true)}
        className="fixed bottom-4 right-4 z-30 flex max-w-[calc(100vw-2rem)] cursor-pointer items-center gap-3 rounded-xl border border-primary/15 bg-primary px-3 py-2.5 text-left text-primary-foreground shadow-[var(--shadow-pop)] transition-transform hover:-translate-y-0.5 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50 motion-reduce:transform-none xl:bottom-6 xl:right-6"
        aria-label={`${respuesta ? 'Continuar guía' : 'Continuar consulta'}: ${tituloPendiente}`}
      >
        <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-white/12">
          <BookOpen className="size-4" aria-hidden />
        </span>
        <span className="min-w-0">
          <span className="block text-[10px] font-bold uppercase tracking-[0.14em] text-white/65">
            {respuesta ? 'Continuar guía' : 'Continuar consulta'}
          </span>
          <span className="block truncate text-xs font-semibold">{tituloPendiente}</span>
        </span>
        <ArrowRight className="size-4 shrink-0 text-white/70" aria-hidden />
      </button>
    )
  }

  return (
    <aside
      aria-labelledby={tituloId}
      className="fixed inset-x-3 bottom-3 z-40 flex h-[76svh] max-h-[720px] flex-col overflow-hidden rounded-2xl border border-border-strong bg-card shadow-[var(--shadow-pop)] min-[1120px]:static min-[1120px]:z-20 min-[1120px]:h-full min-[1120px]:max-h-none min-[1120px]:w-[400px] min-[1120px]:shrink-0 min-[1120px]:rounded-none min-[1120px]:border-y-0 min-[1120px]:border-r-0 min-[1120px]:shadow-none"
    >
      <header className="relative overflow-hidden bg-primary px-5 pb-4 pt-5 text-primary-foreground">
        <div
          className="pointer-events-none absolute -right-10 -top-16 size-40 rounded-full border-[28px] border-white/[0.04]"
          aria-hidden
        />
        <div className="relative flex items-start gap-3">
          <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-accent text-accent-foreground shadow-lg shadow-black/10">
            <BookOpen className="size-5" aria-hidden />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[10px] font-bold uppercase tracking-[0.18em] text-white/60">Centro de ayuda</p>
            <h2 id={tituloId} className="mt-0.5 text-lg font-bold tracking-tight">
              Manual del vendedor
            </h2>
            <p className="mt-1 text-xs leading-relaxed text-white/70">
              Lee la guía y continúa trabajando en la misma pantalla.
            </p>
          </div>
          <button
            type="button"
            onClick={() => onAbiertoChange(false)}
            className="grid size-9 shrink-0 cursor-pointer place-items-center rounded-lg text-white/70 transition-colors hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-white/35"
            aria-label="Minimizar ayuda"
            title="Minimizar"
          >
            <Minimize2 className="size-4" aria-hidden />
          </button>
        </div>
      </header>

      <div className="flex items-center gap-2 border-b border-border bg-secondary/55 px-5 py-2.5 text-[11px] text-muted-foreground-strong">
        <span className="relative flex size-2" aria-hidden>
          <span className="absolute inline-flex size-full animate-ping rounded-full bg-accent opacity-30 motion-reduce:animate-none" />
          <span className="relative inline-flex size-2 rounded-full bg-accent" />
        </span>
        Estás trabajando en <strong className="font-bold text-primary">{ETIQUETA_VISTA[vista]}</strong>
        <span className="ml-auto text-[10px] text-muted-foreground">sin salir del CRM</span>
      </div>

      <div className="ac-scroll flex-1 overflow-y-auto">
        {!respuesta && !aclaracion && !buscando && (
          <div className="p-5">
            <div className="mb-5 rounded-xl border border-accent/20 bg-accent/[0.07] p-3.5">
              <p className="flex items-center gap-2 text-xs font-extrabold text-primary">
                <span className="grid size-6 place-items-center rounded-md bg-accent text-accent-foreground">
                  <HelpCircle className="size-3.5" aria-hidden />
                </span>
                Pregunta como hablas en ventas
              </p>
              <p className="mt-2 text-[11px] leading-relaxed text-muted-foreground-strong">
                No necesitas saber el nombre del botón. Puedes escribir “ya hice la llamada”, “quiero sacar un
                pendiente” o “el número ya existe”.
              </p>
            </div>
            <form onSubmit={alEnviar}>
              <label htmlFor={`${tituloId}-consulta`} className="text-sm font-bold text-primary">
                ¿Qué necesitas resolver?
              </label>
              <div className="mt-3 flex items-center overflow-hidden rounded-xl border border-input bg-background transition-shadow focus-within:border-ring focus-within:ring-[3px] focus-within:ring-ring/20">
                <Search className="ml-3 size-4 shrink-0 text-muted-foreground" aria-hidden />
                <input
                  id={`${tituloId}-consulta`}
                  ref={inputRef}
                  value={consulta}
                  onChange={(evento) => {
                    setConsulta(evento.target.value)
                    setErrorConsulta(null)
                    if (resultado?.tipo === 'sin_resultado') setResultado(null)
                  }}
                  placeholder="Ej.: Ya llamé, ¿cómo lo marco?"
                  autoComplete="off"
                  maxLength={240}
                  className="h-11 min-w-0 flex-1 bg-transparent px-2 text-xs text-foreground outline-none placeholder:text-muted-foreground"
                />
                <button
                  type="submit"
                  className="mr-1 grid size-9 shrink-0 cursor-pointer place-items-center rounded-lg bg-accent text-accent-foreground transition-colors hover:bg-accent-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-45"
                  disabled={consulta.trim().length < 2}
                  aria-label="Buscar en el manual"
                >
                  <ArrowRight className="size-4" aria-hidden />
                </button>
              </div>
            </form>

            {sinResultado && (
              <div role="status" className="mt-4 rounded-xl border border-border bg-muted/45 p-3">
                <p className="flex items-center gap-2 text-xs font-bold text-primary">
                  <HelpCircle className="size-4 text-accent" aria-hidden />
                  Esa respuesta aún no está en el manual
                </p>
                <p className="mt-1 text-[11px] leading-relaxed text-muted-foreground">
                  Prueba con otra frase o elige una consulta frecuente. El manual prefiere no responder antes que
                  recomendar una acción equivocada.
                </p>
              </div>
            )}

            {errorConsulta && (
              <div role="alert" className="mt-4 rounded-xl border border-destructive/25 bg-destructive/5 p-3">
                <p className="flex items-center gap-2 text-xs font-bold text-destructive">
                  <AlertTriangle className="size-4" aria-hidden />
                  No pudimos consultar el manual
                </p>
                <p className="mt-1 text-[11px] leading-relaxed text-muted-foreground-strong">{errorConsulta}</p>
              </div>
            )}

            <div className="mt-6">
              <div className="flex items-center justify-between gap-3">
                <h3 className="text-xs font-bold uppercase tracking-[0.12em] text-muted-foreground-strong">
                  Consultas frecuentes
                </h3>
                <span className="text-[10px] text-muted-foreground">según tu pantalla</span>
              </div>
              <div className="mt-2 divide-y divide-border border-y border-border">
                {cargandoPreguntas && (
                  <div className="flex items-center gap-2 py-4 text-xs text-muted-foreground" role="status">
                    <LoaderCircle className="size-4 animate-spin motion-reduce:animate-none" aria-hidden />
                    Cargando consultas aprobadas…
                  </div>
                )}
                {!cargandoPreguntas && errorPreguntas && (
                  <div className="py-3">
                    <p className="text-[11px] leading-relaxed text-muted-foreground-strong">{errorPreguntas}</p>
                    <button
                      type="button"
                      onClick={() => setRevisionInicio((revision) => revision + 1)}
                      className="mt-2 cursor-pointer text-xs font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35"
                    >
                      Reintentar
                    </button>
                  </div>
                )}
                {!cargandoPreguntas &&
                  !errorPreguntas &&
                  preguntas.map((pregunta) => (
                    <button
                      key={pregunta}
                      type="button"
                      aria-label={pregunta}
                      onClick={() => void consultar(pregunta)}
                      className="group flex w-full cursor-pointer items-center gap-3 py-3 text-left focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/35"
                    >
                      <span className="grid size-7 shrink-0 place-items-center rounded-lg bg-secondary text-primary transition-colors group-hover:bg-accent group-hover:text-accent-foreground">
                        <HelpCircle className="size-3.5" aria-hidden />
                      </span>
                      <span className="min-w-0 flex-1 text-xs font-semibold leading-relaxed text-foreground">
                        {pregunta}
                      </span>
                      <ArrowRight
                        className="size-3.5 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:text-accent motion-reduce:transform-none"
                        aria-hidden
                      />
                    </button>
                  ))}
                {!cargandoPreguntas && !errorPreguntas && preguntas.length === 0 && (
                  <p className="py-4 text-[11px] leading-relaxed text-muted-foreground">
                    Todavía no hay consultas frecuentes publicadas para esta pantalla.
                  </p>
                )}
              </div>
            </div>
          </div>
        )}

        {buscando && (
          <div className="grid min-h-64 place-items-center px-6 text-center" role="status" aria-live="polite">
            <div>
              <span className="mx-auto grid size-12 place-items-center rounded-2xl bg-accent/10 text-accent">
                <LoaderCircle className="size-5 animate-spin motion-reduce:animate-none" aria-hidden />
              </span>
              <p className="mt-3 text-sm font-bold text-primary">Buscando en el manual…</p>
              <p className="mt-1 text-xs text-muted-foreground">Consultando el contenido aprobado para tu rol.</p>
            </div>
          </div>
        )}

        {aclaracion && !buscando && (
          <section className="p-5" aria-live="polite">
            <button
              type="button"
              onClick={volver}
              className="inline-flex cursor-pointer items-center gap-1 text-xs font-semibold text-muted-foreground transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35"
            >
              <ChevronLeft className="size-4" aria-hidden /> Otra consulta
            </button>

            <div className="mt-5 inline-flex items-center gap-1.5 rounded-full bg-accent/10 px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.12em] text-accent">
              <HelpCircle className="size-3" aria-hidden /> Necesito precisar
            </div>
            <h3
              ref={resultadoRef}
              tabIndex={-1}
              className="mt-3 text-xl font-extrabold leading-tight tracking-tight text-primary outline-none"
            >
              {aclaracion.titulo}
            </h3>
            <p className="mt-2 text-xs leading-relaxed text-muted-foreground-strong">{aclaracion.detalle}</p>

            <div className="mt-5 space-y-2" aria-label="Opciones para precisar la consulta">
              {aclaracion.opciones.map((opcion) => (
                <button
                  key={opcion.consulta}
                  type="button"
                  onClick={() => void consultar(opcion.consulta)}
                  className="group flex w-full cursor-pointer items-start gap-3 rounded-xl border border-border bg-background p-3.5 text-left transition-colors hover:border-accent/45 hover:bg-accent/[0.05] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35"
                >
                  <span className="mt-0.5 grid size-7 shrink-0 place-items-center rounded-lg bg-secondary text-primary transition-colors group-hover:bg-accent group-hover:text-accent-foreground">
                    <ArrowRight className="size-3.5" aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-xs font-extrabold text-foreground">{opcion.etiqueta}</span>
                    <span className="mt-1 block text-[11px] leading-relaxed text-muted-foreground">
                      {opcion.detalle}
                    </span>
                  </span>
                </button>
              ))}
            </div>

            <p className="mt-4 border-l-2 border-accent/50 pl-3 text-[10px] leading-relaxed text-muted-foreground">
              Esta confirmación evita indicarte que anules, corrijas o reprogrames el elemento equivocado.
            </p>
          </section>
        )}

        {respuesta && !buscando && (
          <article className="p-5" aria-live="polite">
            <button
              type="button"
              onClick={volver}
              className="inline-flex cursor-pointer items-center gap-1 text-xs font-semibold text-muted-foreground transition-colors hover:text-accent focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35"
            >
              <ChevronLeft className="size-4" aria-hidden /> Otra consulta
            </button>

            <div className="mt-4 flex items-center gap-2 text-[10px] font-bold uppercase tracking-[0.12em] text-muted-foreground">
              <span className="inline-flex items-center gap-1 rounded-full bg-secondary px-2 py-1 text-primary">
                <Clock className="size-3" aria-hidden /> {respuesta.duracion}
              </span>
              Guía paso a paso
            </div>
            <h3
              ref={resultadoRef}
              tabIndex={-1}
              className="mt-3 text-xl font-extrabold leading-tight tracking-tight text-primary outline-none"
            >
              {respuesta.titulo}
            </h3>
            <p className="mt-2 text-xs leading-relaxed text-muted-foreground-strong">{respuesta.resumen}</p>

            {respuesta.traduccion && (
              <div className="mt-5 rounded-xl border border-accent/20 bg-accent/[0.07] p-3.5">
                <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-muted-foreground">
                  Así lo encuentras en el CRM
                </p>
                <div className="mt-2 flex items-center gap-2 text-[11px] leading-tight">
                  <span className="min-w-0 flex-1 rounded-lg bg-card px-2.5 py-2 font-semibold text-muted-foreground-strong shadow-sm">
                    “{respuesta.traduccion.lenguajeVendedor}”
                  </span>
                  <ArrowRight className="size-3.5 shrink-0 text-accent" aria-hidden />
                  <span className="min-w-0 flex-1 rounded-lg bg-primary px-2.5 py-2 font-bold text-primary-foreground">
                    {respuesta.traduccion.lenguajeCrm}
                  </span>
                </div>
              </div>
            )}

            <ol className="mt-6" aria-label="Pasos de la guía">
              {respuesta.pasos.map((paso, indice) => (
                <li key={paso.titulo} className="relative grid grid-cols-[30px_1fr] gap-3 pb-5 last:pb-1">
                  {indice < respuesta.pasos.length - 1 && (
                    <span
                      className="absolute bottom-0 left-[14px] top-7 w-px bg-gradient-to-b from-accent/55 to-border"
                      aria-hidden
                    />
                  )}
                  <span className="relative z-10 grid size-[30px] place-items-center rounded-full border-2 border-accent bg-card text-[11px] font-extrabold text-accent">
                    {indice + 1}
                  </span>
                  <div className="pt-0.5">
                    <p className="text-xs font-extrabold text-foreground">{paso.titulo}</p>
                    <p className="mt-1 text-[11px] leading-relaxed text-muted-foreground-strong">{paso.detalle}</p>
                  </div>
                </li>
              ))}
            </ol>

            {respuesta.advertencia && (
              <div className="mt-5 border-l-2 border-warning bg-warning/10 px-3 py-2.5">
                <p className="flex items-center gap-1.5 text-[11px] font-extrabold text-warning-text">
                  <AlertTriangle className="size-3.5" aria-hidden /> Antes de continuar
                </p>
                <p className="mt-1 text-[11px] leading-relaxed text-warning-text">{respuesta.advertencia}</p>
              </div>
            )}

            <Button
              type="button"
              variant="accent"
              className="mt-5 w-full"
              onClick={() => ejecutarAccion(respuesta.accion)}
            >
              {respuesta.accion.etiqueta} <ArrowRight aria-hidden />
            </Button>

            <div className="mt-5 flex items-start gap-2 border-t border-border pt-4 text-[10px] leading-relaxed text-muted-foreground">
              <span className="mt-0.5 grid size-4 shrink-0 place-items-center rounded-full bg-accent text-accent-foreground">
                <Check className="size-2.5" strokeWidth={3} aria-hidden />
              </span>
              <span>{respuesta.fuente}</span>
            </div>
          </article>
        )}
      </div>

      <footer className="border-t border-border bg-muted/35 px-5 py-2 text-center text-[10px] text-muted-foreground">
        Contenido aprobado y respuesta resuelta por el servidor
      </footer>
    </aside>
  )
}
