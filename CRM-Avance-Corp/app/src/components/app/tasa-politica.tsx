// Rentabilidad R3 — la TASA la decide la política; la excepción la decide Gerencia.
//
// Este bloque reemplaza al input libre de «Tasa anual» en el formulario de contrato
// (alta y corrección). Pregunta al núcleo del servidor (crm.resolver_tasa_fn) qué
// tasa BASE corresponde —15% para una primera inversión, la heredada para
// renovación/upgrade— y bloquea el input en ese valor. Si el analista necesita
// más, pide una excepción con motivo (crm.solicitar_tasa_fn); Gerencia decide en
// su bandeja (aprobar, rechazar, aprobar hasta X%); si hubo tope, el analista lo
// acepta o lo declina aquí mismo. Con una autorización vigente el input se
// habilita entre la base y la tasa autorizada (D6: «hasta X%»). Nunca por debajo
// de la base (D4).
//
// El bloque NO calcula tasas: todo sale del servidor (regla de Miguel: un solo
// núcleo). El candado definitivo es el de R4 en la base de datos; mientras llega,
// el front ya no ofrece la tasa libre. En sesión DEMO no hay servidor: base fija.
import { useEffect, useMemo, useRef, useState, type JSX, type ReactNode } from 'react'
import { CheckCircle2, Clock, Lock, RotateCcw, ShieldCheck, Unlock } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { cn } from '@/lib/utils'
import { fmtFecha, money } from '@/lib/format'
import { parseMonto } from '@/lib/numero'
import type { CategoriaContrato, ModalidadContrato, TipoInteres } from '@/lib/cronograma'
import type { IntencionContrato, ReglaTasa, SolicitudTasa } from '@/data/crm-api'
import { DIAS_RECHAZO_VISIBLE, ESTADOS_SOLICITUD_TASA_SEGUIMIENTO, etiquetaReglaTasa } from '@/lib/rentabilidad'
import { useResolucionTasa, useResponderTopeTasa, useSolicitarTasa, useSolicitudesTasa } from '@/data/crm-queries'

const BASE_DEMO = 15
/** Mientras hay una solicitud pendiente se re-consulta cada medio minuto: la decisión de Gerencia llega sola al formulario. */
const REFRESCO_PENDIENTE_MS = 30_000

export type ModoTasaPolitica = 'cargando' | 'error' | 'base' | 'autorizada' | 'demo' | 'incompleta'

/** Lo que el formulario necesita para validar al guardar. */
export interface RangoTasaPolitica {
  modo: ModoTasaPolitica
  /** Tasa base según el núcleo (o la vigente del contrato en corrección). */
  base: number | null
  /** Mínimo y máximo aceptables para el input; iguales cuando la tasa está bloqueada. */
  minimo: number | null
  maximo: number | null
  regla: ReglaTasa | null
  /** Solicitud viva del actor para esta intención (pendiente / autorizada / con tope), si la hay. */
  solicitud: SolicitudTasa | null
  /** Motivo por el que todavía no se puede guardar el contrato, incluso a la base. */
  bloqueoContrato: string | null
}

export interface IntencionParcial {
  capital: number | null
  moneda: 'PEN' | 'USD'
  modalidad: ModalidadContrato
  tipo_interes: TipoInteres
  fecha_inicio: string
  fecha_vencimiento: string
  producto_condicion_id?: string | null
}

interface TasaPoliticaProps {
  clienteId: string
  leadId?: string
  categoria: CategoriaContrato | ''
  contratoOrigenId: string | null
  intencion: IntencionParcial
  tasa: string
  /** Tasa elegida en el lead: conservarla en la primera autorización válida del contrato. */
  tasaPreseleccionada?: number | undefined
  onTasaChange: (valor: string) => void
  onRangoChange?: (rango: RangoTasaPolitica) => void
  /** Sesión demo: sin servidor, base fija, sin solicitudes. */
  demo: boolean
  disabled?: boolean
  idInput?: string
  /** Campo contiguo a la tasa; la solicitud ocupa una fila completa debajo de ambos. */
  children?: ReactNode
  /**
   * Corrección de un contrato ya creado: la «base» es la tasa VIGENTE del contrato
   * (cambiarla exige autorización de Gerencia); el núcleo no se consulta. `contratoId` viaja con la solicitud para que
   * el núcleo acepte el origen de una renovación (que ya figura «renovado» por ese mismo contrato).
   */
  correccion?: { tasaActual: number; contratoId?: string }
}

function tasaTxt(n: number): string {
  return `${n.toLocaleString('es-PE', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}%`
}

/** La MISMA huella que calcula el servidor (private.huella_solicitud_tasa): todas las dimensiones, sin comodines. */
function mismaIntencion(s: SolicitudTasa, i: IntencionParcial): boolean {
  return (
    i.capital != null
    && Math.abs(s.capital - i.capital) < 0.005
    && s.moneda === i.moneda
    && s.fecha_inicio === i.fecha_inicio
    && s.fecha_vencimiento === i.fecha_vencimiento
    && s.modalidad === i.modalidad
    && s.tipo_interes === i.tipo_interes
    && (s.producto_condicion_id ?? null) === (i.producto_condicion_id ?? null)
  )
}

function sigueVigente(s: SolicitudTasa, ahora: number): boolean {
  return s.vigente && new Date(s.vence_en).getTime() > ahora
}

export function TasaPolitica({
  clienteId,
  leadId,
  categoria,
  contratoOrigenId,
  intencion,
  tasa,
  tasaPreseleccionada,
  onTasaChange,
  onRangoChange,
  demo,
  disabled = false,
  idInput = 'ct-tasa',
  children,
  correccion,
}: TasaPoliticaProps): JSX.Element {
  // En corrección la base es la tasa vigente del contrato: no hace falta el origen para bloquear.
  const listo = (!!clienteId || !!leadId) && !!categoria && (correccion != null || categoria === 'nuevo' || !!contratoOrigenId)
  const consultaNucleo = !demo && !correccion && listo
  const resolucion = useResolucionTasa(clienteId, categoria, contratoOrigenId, consultaNucleo, leadId)
  const [pidiendo, setPidiendo] = useState(false)
  const [tasaPedida, setTasaPedida] = useState('')
  const [motivo, setMotivo] = useState('')
  const [solicitudEnviada, setSolicitudEnviada] = useState<SolicitudTasa | null>(null)
  const enviandoSolicitud = useRef(false)
  const solicitar = useSolicitarTasa()
  const responder = useResponderTopeTasa()

  // Reloj propio: una autorización caduca por vence_en aunque el formulario lleve horas abierto (no se confía solo en la caché).
  const [ahora, setAhora] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setAhora(Date.now()), 60_000)
    return () => clearInterval(t)
  }, [])
  // Solo las MÍAS y de ESTE cliente, filtradas en el SERVIDOR (una bandeja de 200 del equipo no puede tapar mi
  // autorización); vivas y rechazadas (el analista tiene que enterarse del «no»). Se filtran a ESTA intención.
  const [hayPendiente, setHayPendiente] = useState(false)
  const solicitudes = useSolicitudesTasa(ESTADOS_SOLICITUD_TASA_SEGUIMIENTO, !demo && (!!clienteId || !!leadId), hayPendiente ? REFRESCO_PENDIENTE_MS : 60_000, leadId ? { leadId } : { soloMias: true, clienteId })
  // La respuesta del envío conserva el candado aunque falle la relectura de la bandeja.
  // En cuanto la consulta conoce ese id, vuelve a ser la fuente del estado (aprobación/rechazo).
  useEffect(() => {
    if (solicitudEnviada && solicitudes.data?.some((s) => s.id === solicitudEnviada.id)) setSolicitudEnviada(null)
  }, [solicitudEnviada, solicitudes.data])
  const { solicitud, otraViva, rechazada, pendiente } = useMemo(() => {
    const filas = solicitudes.data ?? []
    const conocidas = solicitudEnviada && !filas.some((s) => s.id === solicitudEnviada.id)
      ? [...filas, solicitudEnviada]
      : filas
    const mias = conocidas.filter(
      (s) => (leadId ? s.lead_id === leadId : s.es_mia && s.cliente_id === clienteId) && s.categoria === categoria && (s.contrato_origen_id ?? null) === (contratoOrigenId ?? null),
    )
    const candidatas = mias.filter((s) => sigueVigente(s, ahora))
    const coincidente = candidatas.find((s) => mismaIntencion(s, intencion)) ?? null
    // Una viva para OTRA intención (otro capital o plazo) no autoriza nada aquí: solo se avisa.
    const otra = coincidente ? null : candidatas[0] ?? null
    // El último rechazo para ESTA intención (pocos días): se dice qué decidió Gerencia y se puede volver a pedir.
    const rech = coincidente
      ? null
      : mias
        .filter((s) => s.estado_efectivo === 'rechazada' && s.resuelta_en != null && ahora - new Date(s.resuelta_en).getTime() < DIAS_RECHAZO_VISIBLE * 86_400_000 && mismaIntencion(s, intencion))
        .sort((a, b) => new Date(b.resuelta_en ?? 0).getTime() - new Date(a.resuelta_en ?? 0).getTime())[0] ?? null
    // Cambiar capital o plazo no permite saltarse una petición pendiente de esta operación.
    return { solicitud: coincidente, otraViva: otra, rechazada: rech, pendiente: candidatas.find((s) => s.estado_efectivo === 'pendiente') ?? null }
  }, [solicitudes.data, solicitudEnviada, clienteId, leadId, categoria, contratoOrigenId, intencion, ahora])
  useEffect(() => {
    setHayPendiente(pendiente != null)
  }, [pendiente])
  useEffect(() => {
    // Otra pestaña puede enviar la petición mientras este borrador está abierto.
    // Cuando aparece, el borrador oculto ya no debe impedir continuar tras la respuesta.
    if (solicitud || pendiente) setPidiendo(false)
  }, [solicitud, pendiente])

  const base: number | null = demo
    ? BASE_DEMO
    : correccion
      ? correccion.tasaActual
      : resolucion.data?.tasa_base ?? null
  const regla: ReglaTasa | null = demo ? 'primera_inversion' : correccion ? null : resolucion.data?.regla ?? null
  const autorizada = solicitud != null
    && (solicitud.estado_efectivo === 'aprobada' || solicitud.estado_efectivo === 'aceptada_por_analista')
    && solicitud.tasa_maxima_autorizada != null

  const modo: ModoTasaPolitica = demo
    ? 'demo'
    : !listo
      ? 'incompleta'
      : correccion
        ? autorizada ? 'autorizada' : 'base'
        : resolucion.isPending
          ? 'cargando'
          : resolucion.isError || base == null
            ? 'error'
            : autorizada
              ? 'autorizada'
              : 'base'
  const minimo = base
  const maximo = autorizada ? solicitud!.tasa_maxima_autorizada : base
  const bloqueoContrato = demo ? null
    : leadId && resolucion.data?.bloqueo_conversion ? resolucion.data.bloqueo_conversion
    : pendiente ? `La solicitud de tasa está pendiente de Gerencia. Espera su respuesta antes de ${leadId ? 'convertir el lead' : 'crear el contrato'}, incluso a la tasa base.`
      : solicitar.isPending ? 'Enviando la solicitud de tasa a Gerencia. Espera antes de continuar.'
        : solicitudes.isPending ? 'Consultando si hay solicitudes de tasa pendientes…'
          : solicitudes.isError ? 'No se pudieron verificar las solicitudes de tasa. Reintenta antes de continuar.'
            : pidiendo ? `Envía la solicitud de tasa o cancela su preparación antes de ${leadId ? 'convertir el lead' : 'crear el contrato'}.`
              : leadId && solicitud?.estado_efectivo === 'aprobada_con_tope' ? solicitud.es_mia
                ? 'Responde al tope de Gerencia antes de convertir el lead.'
                : `${solicitud.solicitante_nombre} debe aceptar o declinar el tope desde su bandeja de tasas antes de convertir el lead.`
              : null

  // El input SIGUE a la política: bloqueado en la base. `tasa` va en las dependencias a propósito: si otra parte
  // del formulario (p. ej. una condición de catálogo) escribe la tasa, la política la devuelve a su sitio.
  // Con autorización NO se pisa lo que teclea el analista: el rango se valida (aria-invalid) y al guardar.
  const preseleccionPendiente = useRef(tasaPreseleccionada)
  useEffect(() => {
    if (base == null) return
    if (preseleccionPendiente.current != null && (solicitudes.isPending || solicitudes.isError)) return
    if ((modo === 'base' || modo === 'demo') && parseMonto(tasa) !== base) onTasaChange(String(base))
    // onTasaChange es estable (setState).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [base, modo, tasa, solicitudes.isPending, solicitudes.isError])
  // Cuando APARECE una autorización en el ALTA, el input arranca en la tasa autorizada (el analista pidió más que la
  // base). En CORRECCIÓN no: se conserva la tasa persistida del contrato; subirla es una elección explícita (si no,
  // guardar solo unas notas cambiaría la rentabilidad).
  const autorizacionId = modo === 'autorizada' && !correccion ? solicitud?.id ?? null : null
  const ultimaAutorizacion = useRef<string | null>(null)
  useEffect(() => {
    if (solicitudes.isPending || solicitudes.isError) return
    if (autorizacionId && autorizacionId !== ultimaAutorizacion.current && maximo != null) {
      const elegida = preseleccionPendiente.current
      onTasaChange(String(elegida != null && minimo != null && elegida >= minimo && elegida <= maximo ? elegida : maximo))
    }
    ultimaAutorizacion.current = autorizacionId
    if (autorizacionId || modo === 'base') preseleccionPendiente.current = undefined
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autorizacionId, solicitudes.isPending, solicitudes.isError, modo])

  useEffect(() => {
    onRangoChange?.({ modo, base, minimo, maximo: maximo ?? null, regla, solicitud, bloqueoContrato })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [modo, base, minimo, maximo, regla, solicitud?.id, solicitud?.estado_efectivo, bloqueoContrato])

  // ── Pedir una excepción ──
  const intencionCompleta = intencion.capital != null && intencion.capital >= 100 && !!intencion.fecha_inicio && !!intencion.fecha_vencimiento
  const tope = resolucion.data?.politica.tope_tecnico ?? 50
  // Pedir requiere una intención que el servidor pueda resolver: nuevo, o renovación/upgrade con su origen (también en corrección).
  const puedePedir = !demo && !disabled && modo === 'base' && !solicitud && !pendiente && !resolucion.data?.bloqueo_conversion && !solicitudes.isPending && !solicitudes.isError && !!categoria && (categoria === 'nuevo' || !!contratoOrigenId)

  // Foco (a11y): al abrir el mini-formulario va a «Tasa solicitada»; al cancelar vuelve al botón que lo abrió
  // (el intercambio desmonta el nodo enfocado y Radix, dentro del diálogo, lo mandaría al contenedor). Tras
  // enviar o responder, el foco se posa en el bloque para que Tab continúe desde aquí y no desde el inicio.
  const raizRef = useRef<HTMLDivElement>(null)
  const abrirRef = useRef<HTMLButtonElement>(null)
  const pedidaRef = useRef<HTMLInputElement>(null)
  const volviendo = useRef(false)
  useEffect(() => {
    if (pidiendo) pedidaRef.current?.focus()
    else if (volviendo.current) { volviendo.current = false; abrirRef.current?.focus() }
  }, [pidiendo])
  const cerrarSolicitud = () => { volviendo.current = true; setPidiendo(false) }

  const enviarSolicitud = async () => {
    if (enviandoSolicitud.current || solicitar.isPending || !puedePedir || base == null || !categoria) return
    const pedida = parseMonto(tasaPedida)
    if (pedida == null || !Number.isFinite(pedida)) { toast.error('Escribe la tasa que necesitas.'); return }
    if (pedida <= base) { toast.error(`La excepción debe ser superior a la tasa base de ${tasaTxt(base)}.`); return }
    if (pedida > tope) { toast.error(`La tasa no puede superar el tope técnico de ${tasaTxt(tope)}.`); return }
    if (motivo.trim().length < 5 || motivo.trim().length > 500) { toast.error('Explica el motivo comercial (entre 5 y 500 caracteres).'); return }
    if (!intencionCompleta || intencion.capital == null) { toast.error('Completa capital y plazo antes de pedir la tasa.'); return }
    const cuerpo: IntencionContrato = {
      cliente_id: clienteId || null,
      ...(leadId ? { lead_id: leadId } : {}),
      categoria: categoria as CategoriaContrato,
      contrato_origen_id: contratoOrigenId,
      producto_condicion_id: intencion.producto_condicion_id ?? null,
      capital: intencion.capital,
      moneda: intencion.moneda,
      modalidad: intencion.modalidad,
      tipo_interes: intencion.tipo_interes,
      fecha_inicio: intencion.fecha_inicio,
      fecha_vencimiento: intencion.fecha_vencimiento,
      ...(correccion?.contratoId ? { contrato_id: correccion.contratoId } : {}),
    }
    enviandoSolicitud.current = true
    try {
      const enviada = await solicitar.mutateAsync({ intencion: cuerpo, tasaSolicitada: pedida, motivo: motivo.trim() })
      setSolicitudEnviada({ ...enviada, es_mia: true })
      toast.success(`Solicitud enviada a Gerencia: ${tasaTxt(pedida)}. Te avisamos aquí cuando decida.`)
      setPidiendo(false)
      setTasaPedida('')
      setMotivo('')
      raizRef.current?.focus()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo enviar la solicitud.')
    } finally {
      enviandoSolicitud.current = false
    }
  }

  const responderTope = async (acepta: boolean) => {
    if (!solicitud || !solicitud.es_mia) return
    try {
      await responder.mutateAsync({ solicitudId: solicitud.id, acepta, motivo: null })
      toast.success(acepta ? `Aceptaste ${tasaTxt(solicitud.tasa_maxima_autorizada ?? 0)}: puedes seguir con el contrato.` : 'Declinaste el tope. La tasa vuelve a la base.')
      raizRef.current?.focus()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo responder.')
    }
  }

  // El input solo se edita con autorización. La tasa fijada por la política es un DATO que hay que poder leer y
  // copiar: va readOnly (no disabled, que la apaga al 50 % y la saca del orden de tabulación). disabled queda para
  // cargando / incompleta / error / formulario enviando.
  const editable = !disabled && modo === 'autorizada'
  const soloLectura = !disabled && (modo === 'base' || modo === 'demo')
  const n = parseMonto(tasa)
  const fueraDeRango = editable && base != null && maximo != null && (n == null || n < base || n > maximo)

  // Una sola región viva, persistente y de una línea: los lectores anuncian los CAMBIOS (pendiente → aprobada),
  // no una caja que nace llena. Las cajas visibles no llevan role y los botones quedan fuera de la región.
  const resumenEstado = demo
    ? ''
    : solicitud
      ? solicitud.estado_efectivo === 'pendiente'
        ? `Solicitud de ${tasaTxt(solicitud.tasa_solicitada)} pendiente de Gerencia.`
        : solicitud.estado_efectivo === 'aprobada_con_tope' && solicitud.tasa_maxima_autorizada != null
          ? `Gerencia ofrece hasta ${tasaTxt(solicitud.tasa_maxima_autorizada)}: acéptalo para habilitar el campo de tasa.`
          : autorizada && base != null && maximo != null
            ? `Autorización vigente: tasa entre ${tasaTxt(base)} y ${tasaTxt(maximo)}.`
            : ''
      : rechazada
        ? `Gerencia rechazó tu solicitud de ${tasaTxt(rechazada.tasa_solicitada)}${rechazada.motivo_resolucion ? `: ${rechazada.motivo_resolucion}` : ''}. La tasa queda en la base.`
        : otraViva
          ? 'Tienes una solicitud viva para este cliente con otros datos: no aplica a este formulario.'
          : ''

  return (
    <>
    <div ref={raizRef} tabIndex={-1} className="min-w-0 space-y-1.5 outline-none" data-testid="tasa-politica">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Label htmlFor={idInput}>Tasa anual (%)</Label>
        {modo === 'autorizada' && maximo != null && (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold text-primary">
            <Unlock className="size-3" aria-hidden /> Autorizada hasta {tasaTxt(maximo)}
          </span>
        )}
        {modo === 'base' && (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold text-muted-foreground-strong">
            <Lock className="size-3" aria-hidden /> Fijada por la política
          </span>
        )}
      </div>
      <Input
        id={idInput}
        inputMode="decimal"
        value={tasa}
        onChange={(e) => onTasaChange(e.target.value)}
        disabled={!editable && !soloLectura}
        readOnly={soloLectura}
        aria-readonly={soloLectura || undefined}
        className={cn(soloLectura && 'bg-muted/40 font-bold tabular-nums')}
        aria-describedby={`${idInput}-ayuda`}
        aria-invalid={fueraDeRango || undefined}
      />
      <p id={`${idInput}-ayuda`} className={cn('text-xs', fueraDeRango ? 'font-semibold text-destructive' : 'text-muted-foreground')}>
        {modo === 'demo' && `Demo: la política fija ${tasaTxt(BASE_DEMO)}. En sesión real la decide el servidor.`}
        {modo === 'incompleta' && (categoria === 'upgrade' || categoria === 'renovacion'
          ? 'Selecciona el contrato origen para conocer la tasa que hereda.'
          : 'Selecciona la categoría para conocer la tasa base.')}
        {modo === 'cargando' && 'Consultando la política de rentabilidad…'}
        {modo === 'error' && (
          <>
            No se pudo obtener la tasa base.{' '}
            <button
              type="button"
              className="inline-flex min-h-6 items-center gap-1 rounded px-1 font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              onClick={() => void resolucion.refetch()}
            >
              <RotateCcw className="size-3" aria-hidden /> Reintentar
            </button>
          </>
        )}
        {modo === 'base' && base != null && (correccion
          ? `Tasa vigente del contrato: ${tasaTxt(base)}. Cambiarla requiere la autorización de Gerencia.`
          : `${etiquetaReglaTasa(regla ?? 'primera_inversion')}: ${tasaTxt(base)}.${resolucion.data?.contrato_origen ? ` Origen ${resolucion.data.contrato_origen.numero_contrato}.` : ''}`)}
        {modo === 'autorizada' && base != null && maximo != null && (fueraDeRango
          ? `La tasa debe estar entre ${tasaTxt(base)} y ${tasaTxt(maximo)} (autorizada por Gerencia).`
          : `Puedes usar cualquier tasa entre la base ${tasaTxt(base)} y el máximo autorizado ${tasaTxt(maximo)}.`)}
      </p>
      <p role="status" className="sr-only">{bloqueoContrato ?? resumenEstado}</p>
      {!demo && bloqueoContrato && (
        <p className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          {bloqueoContrato}
          {solicitudes.isError && (
            <Button type="button" size="sm" variant="outline" className="mt-2 min-h-10" onClick={() => void solicitudes.refetch()}>Reintentar solicitudes</Button>
          )}
        </p>
      )}

      {/* Estado de la solicitud viva para ESTA intención (caja visible; la región viva es la línea sr-only de arriba) */}
      {!demo && solicitud && (
        <div
          className={cn(
            'rounded-lg border px-3 py-2 text-xs',
            solicitud.estado_efectivo === 'pendiente' && 'border-amber-300 bg-amber-50 text-amber-900',
            solicitud.estado_efectivo === 'aprobada_con_tope' && 'border-sky-300 bg-sky-50 text-sky-900',
            (solicitud.estado_efectivo === 'aprobada' || solicitud.estado_efectivo === 'aceptada_por_analista') && 'border-primary/30 bg-primary/10 text-primary',
          )}
        >
          {solicitud.estado_efectivo === 'pendiente' && (
            <p className="flex items-start gap-1.5">
              <Clock className="mt-0.5 size-3.5 shrink-0" aria-hidden />
              <span>Solicitud de {tasaTxt(solicitud.tasa_solicitada)} pendiente de Gerencia. Vence el {fmtFecha(solicitud.vence_en)}.</span>
            </p>
          )}
          {solicitud.estado_efectivo === 'aprobada_con_tope' && solicitud.tasa_maxima_autorizada != null && (
            <div className="space-y-2">
              <p className="flex items-start gap-1.5">
                <ShieldCheck className="mt-0.5 size-3.5 shrink-0" aria-hidden />
                <span>
                  Gerencia ofrece hasta <strong>{tasaTxt(solicitud.tasa_maxima_autorizada)}</strong> (pediste {tasaTxt(solicitud.tasa_solicitada)}).{solicitud.motivo_resolucion ? ` «${solicitud.motivo_resolucion}».` : ''}{' '}
                  Acéptalo para cerrar con cualquier tasa hasta ese tope, o declínalo y la tasa se queda en la base.
                </span>
              </p>
              <div className="flex flex-wrap gap-2">
                <Button type="button" size="sm" className="min-h-10" disabled={disabled || responder.isPending || !solicitud.es_mia} onClick={() => void responderTope(true)}>
                  <CheckCircle2 className="size-4" aria-hidden /> Aceptar y continuar
                </Button>
                <Button type="button" size="sm" variant="outline" className="min-h-10" disabled={disabled || responder.isPending || !solicitud.es_mia} onClick={() => void responderTope(false)}>
                  No cerrar a ese tope
                </Button>
              </div>
            </div>
          )}
          {(solicitud.estado_efectivo === 'aprobada' || solicitud.estado_efectivo === 'aceptada_por_analista') && solicitud.tasa_maxima_autorizada != null && (
            <p className="flex items-start gap-1.5">
              <CheckCircle2 className="mt-0.5 size-3.5 shrink-0" aria-hidden />
              <span>
                Autorización vigente hasta {tasaTxt(solicitud.tasa_maxima_autorizada)} para {money(solicitud.capital, solicitud.moneda)} del {fmtFecha(solicitud.fecha_inicio)} al {fmtFecha(solicitud.fecha_vencimiento)}; vence el {fmtFecha(solicitud.vence_en)}.
              </span>
            </p>
          )}
        </div>
      )}

      {!demo && !solicitud && rechazada && (
        <p className="rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs font-semibold text-destructive">
          Gerencia rechazó tu solicitud de {tasaTxt(rechazada.tasa_solicitada)}{rechazada.resuelta_en ? ` el ${fmtFecha(rechazada.resuelta_en)}` : ''}{rechazada.motivo_resolucion ? `: «${rechazada.motivo_resolucion}»` : ''}. La tasa queda en la base{base != null ? ` (${tasaTxt(base)})` : ''}; puedes volver a pedir con otro motivo.
        </p>
      )}

      {!demo && !solicitud && otraViva && (
        <p className="rounded-lg border border-border bg-muted/30 px-3 py-2 text-xs text-muted-foreground-strong">
          Tienes una solicitud viva para este cliente con OTROS datos ({money(otraViva.capital, otraViva.moneda)}, {fmtFecha(otraViva.fecha_inicio)} <span aria-hidden>→</span><span className="sr-only">al</span> {fmtFecha(otraViva.fecha_vencimiento)}, {tasaTxt(otraViva.tasa_solicitada)}): con el capital o el plazo de este formulario no aplica.
        </p>
      )}

      {puedePedir && !pidiendo && (
        <Button ref={abrirRef} type="button" size="sm" variant="outline" className="min-h-10" onClick={() => setPidiendo(true)}>
          Solicitar tasa superior
        </Button>
      )}
    </div>
    {children}
    {/* Fuera de la media columna de la tasa: usa todo el ancho de la grilla del contrato. */}
    {pidiendo && (
          <div className="col-span-full min-w-0 space-y-2 rounded-lg border border-border bg-muted/30 p-3" role="group" aria-label="Solicitar tasa superior">
            <div className="grid min-w-0 grid-cols-[6rem_minmax(0,1fr)] gap-3 sm:grid-cols-[8rem_minmax(0,1fr)]">
              <div className="min-w-0 space-y-1">
                <Label className="flex min-h-8 items-end sm:min-h-0" htmlFor={`${idInput}-pedida`}>Tasa solicitada (%)</Label>
                <Input
                  ref={pedidaRef}
                  id={`${idInput}-pedida`}
                  inputMode="decimal"
                  value={tasaPedida}
                  disabled={solicitar.isPending}
                  onChange={(e) => setTasaPedida(e.target.value)}
                  placeholder={base != null ? String(base + 1) : ''}
                  // Este bloque vive DENTRO del <form> del contrato: Enter aquí haría el submit principal y crearía el
                  // contrato a la base en vez de pedir la excepción. Aquí Enter = «Enviar a Gerencia».
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault()
                      e.stopPropagation()
                      void enviarSolicitud()
                    }
                  }}
                />
              </div>
              <div className="min-w-0 space-y-1">
                <Label className="flex min-h-8 items-end sm:min-h-0" htmlFor={`${idInput}-motivo`}>Motivo comercial</Label>
                <Textarea id={`${idInput}-motivo`} rows={2} className="min-h-16 resize-y" maxLength={500} aria-describedby={`${idInput}-motivo-ayuda`} value={motivo} onChange={(e) => setMotivo(e.target.value)} disabled={solicitar.isPending} placeholder="Explica por qué solicitas esta tasa para el cliente" />
                <p id={`${idInput}-motivo-ayuda`} className="text-[11px] text-muted-foreground">Entre 5 y 500 caracteres · {motivo.length}/500</p>
              </div>
            </div>
            <div className="flex flex-wrap justify-end gap-2">
              <Button type="button" size="sm" variant="outline" className="min-h-10" onClick={cerrarSolicitud} disabled={solicitar.isPending}>Cancelar</Button>
              <Button type="button" size="sm" className="min-h-10" onClick={() => void enviarSolicitud()} disabled={solicitar.isPending || !puedePedir}>Enviar a Gerencia</Button>
            </div>
          </div>
      )}
    </>
  )
}
