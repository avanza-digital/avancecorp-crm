import { useEffect, useId, useMemo, useRef, useState, type RefObject } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { LoaderCircle, Lock, RefreshCw } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Dialog, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { RadioGroup } from '@/components/ui/radio-group'
import { Textarea } from '@/components/ui/textarea'
import { ContratoNuevo } from './contrato-nuevo'
import { CrmApiError, mensajeDeError, type CrearContratoInput, type InversionReemplazadaResultado } from '@/data/crm-api'
import { MODALIDAD_LABEL } from '@/lib/contratos-catalogo'
import type { CuotaCronograma } from '@/lib/cronograma'
import { esTipoDocumento } from '@/lib/documento'
import { esFocoHuerfano } from '@/lib/foco'
import { fmtFecha, money } from '@/lib/format'
import { parseMonto } from '@/lib/numero'
import { cn } from '@/lib/utils'
import {
  MOTIVO_ELIMINACION_MAX, MOTIVO_ELIMINACION_MIN, diferenciasDeCarga, inversionReemplazable, largoMotivoEliminacion,
  mesLargo, motivoEliminacionValido, type FichaInversionista, type InversionFuente, type VistaPreviaReemplazo,
} from '@/lib/inversionistas'

/** Lo que la pantalla le presta a la ficha para reemplazar (el servidor decide todo). */
export interface ControlesReemplazo {
  puede: (inversion: InversionFuente) => boolean
  vistaPrevia: (inversion: InversionFuente, opciones: { fechaInicio: string } | { conservarId: string }) => Promise<VistaPreviaReemplazo>
  reemplazar: (inversion: InversionFuente, motivo: string, input: CrearContratoInput, cronograma: CuotaCronograma[]) => Promise<InversionReemplazadaResultado>
  conservar: (inversion: InversionFuente, conservarId: string, motivo: string) => Promise<InversionReemplazadaResultado>
  alTerminar: (inversion: InversionFuente, resultado: InversionReemplazadaResultado) => void
}

type Modo = 'nueva' | 'existente'

/** Una fecha que vale la pena consultar: completa y no a medio teclear (Chrome emite «0002-10-05» mientras se escribe el año). */
const fechaConsultable = (f: string) => /^\d{4}-\d{2}-\d{2}$/.test(f) && f >= '2000-01-01'

/** La original, para el formulario de alta: mismos datos, categoría «nuevo»; cliente y analista los fija el servidor. */
function borradorDesde(i: InversionFuente): CrearContratoInput {
  const c = i.contrato!
  return {
    cliente_id: i.perfil_id ?? '',
    capital: i.capital,
    moneda: i.moneda,
    tasa_anual: c.tasa_anual,
    modalidad: c.modalidad,
    tipo_interes: c.tipo_interes,
    categoria: 'nuevo',
    fecha_inicio: c.fecha_inicio,
    fecha_vencimiento: i.vence_en ?? c.fecha_inicio,
    numero_contrato: i.numero,
    titulares: i.cotitulares.flatMap(t => esTipoDocumento(t.tipo_documento)
      ? [{ tipo_documento: t.tipo_documento, documento: t.documento, nombre_completo: t.nombre }] : []),
    // Sin cuenta elegida: el formulario pide elegirla entre las del cliente.
    cuenta_pago: { tipo: 'existente', cuenta_id: '' },
  }
}

interface Cambio { etiqueta: string; antes?: string; ahora: string }

/** Lo que cambió respecto de la original (solo lo que el formulario cuenta mientras se edita). */
interface CambiosFormulario { capital: string; moneda: 'PEN' | 'USD'; tasa: string; fechaInicio: string; prefijo: string; numero: string }

export function InversionReemplazar({ inversion, ficha, controles, onCerrar, focoAlTerminar }: {
  inversion: InversionFuente
  ficha: FichaInversionista
  controles: ControlesReemplazo
  onCerrar: () => void
  /** Adónde va el foco tras reemplazar: la fila de la original desaparece al refrescar la ficha. */
  focoAlTerminar?: RefObject<HTMLElement | null> | undefined
}) {
  const id = useId()
  const original = inversion
  const [modo, setModo] = useState<Modo>('nueva')
  const [motivo, setMotivo] = useState('')
  const [enviando, setEnviando] = useState(false)
  const enCurso = useRef(false)
  const [error, setError] = useState('')
  const [formulario, setFormulario] = useState<CambiosFormulario | null>(null)
  const [conservarId, setConservarId] = useState<string | null>(null)
  // Lo que el formulario de alta dice de sí mismo (cuenta elegida, cronograma válido, datos legales) y, si no está
  // listo, por qué: se dice junto al botón, que vive lejos de los campos.
  const [formularioListo, setFormularioListo] = useState(false)
  const [razonFormulario, setRazonFormulario] = useState<string | null>(null)
  // Terminado: se cierra en el render siguiente, ya con el foco apuntando a las inversiones.
  const [terminado, setTerminado] = useState(false)
  const cerrar = useRef(onCerrar)
  cerrar.current = onCerrar
  useEffect(() => { if (terminado) cerrar.current() }, [terminado])
  const borrador = useMemo(() => borradorDesde(original), [original])
  const largo = largoMotivoEliminacion(motivo)
  const motivoValido = motivoEliminacionValido(motivo)
  const excedido = largo > MOTIVO_ELIMINACION_MAX
  const referencia = original.numero || 'la inversión'
  const titulo = `Reemplazar inversión ${original.numero ?? ''}`.trim()

  // La fecha de inicio que manda el mes: la del formulario (con un respiro al teclear) o la de la que se conserva.
  const fechaFormulario = formulario?.fechaInicio ?? original.contrato?.fecha_inicio ?? ''
  const [fechaPrevia, setFechaPrevia] = useState(fechaFormulario)
  useEffect(() => {
    const t = setTimeout(() => setFechaPrevia(fechaFormulario), 350)
    return () => clearTimeout(t)
  }, [fechaFormulario])
  // En «quedarme con la otra», antes de elegir, la previa va con la fecha de la original: el mes se muestra al elegir,
  // pero el aviso de cuotas pagadas (que es de la original) sale desde el principio.
  const fechaOriginal = original.contrato?.fecha_inicio ?? ''
  const consultaPrevia = modo === 'nueva'
    ? (fechaConsultable(fechaPrevia) ? { fechaInicio: fechaPrevia } : null)
    : (conservarId ? { conservarId } : fechaConsultable(fechaOriginal) ? { fechaInicio: fechaOriginal } : null)
  const mostrarMes = modo === 'nueva' || conservarId !== null
  const previa = useQuery({
    queryKey: ['reemplazo-inversion-previa', original.fuente_id, consultaPrevia],
    queryFn: () => controles.vistaPrevia(original, consultaPrevia!),
    enabled: consultaPrevia !== null,
    retry: false,
    staleTime: 15_000,
    // Mientras recalcula queda la respuesta anterior: el aviso de cuotas pagadas (que es de la original) y su bloqueo no
    // parpadean, y la región viva no se re-anuncia a medias.
    placeholderData: keepPreviousData,
  })
  // Confirmar exige un mes calculado PARA LO QUE SE ENVÍA: ni la respuesta anterior que queda mientras recalcula, ni
  // la fecha todavía en su respiro, ni un error.
  const previaAlDia = previa.isSuccess && !previa.isPlaceholderData && (modo === 'nueva'
    ? consultaPrevia !== null && fechaPrevia === fechaFormulario
    : conservarId !== null && consultaPrevia !== null && 'conservarId' in consultaPrevia && consultaPrevia.conservarId === conservarId)
  const previaVigente = useRef({ alDia: false, fechaInicio: null as string | null })
  previaVigente.current = { alDia: previaAlDia, fechaInicio: previaAlDia ? previa.data?.fecha_inicio ?? null : null }
  // Las cuotas pagadas son de la original, no de la fecha: una vez vistas, quedan aunque falle un recálculo.
  const [cuotasVistas, setCuotasVistas] = useState(false)
  // Reintentar el cálculo: el botón sigue montado mientras reintenta (si se desmontara, el foco caería al diálogo).
  const [reintentando, setReintentando] = useState(false)
  const motivoRef = useRef<HTMLTextAreaElement>(null)
  useEffect(() => { if (previa.data?.cuotas_pagadas === true) setCuotasVistas(true) }, [previa.data])

  const candidatas = useMemo(() => ficha.inversiones.filter(i => i.fuente_id !== original.fuente_id
    && i.perfil_id === original.perfil_id && inversionReemplazable(i)), [ficha.inversiones, original])
  const elegida = candidatas.find(i => i.fuente_id === conservarId) ?? null

  const cambios = useMemo((): Cambio[] => {
    if (modo === 'existente') return elegida
      ? [{ etiqueta: 'Se conserva', ahora: elegida.numero || 'Inversión registrada' }, { etiqueta: 'Se elimina', ahora: referencia }] : []
    if (!formulario) return []
    const lista: Cambio[] = []
    const capital = parseMonto(formulario.capital)
    if (capital !== null && (capital !== original.capital || formulario.moneda !== original.moneda)) {
      lista.push({ etiqueta: 'Capital', antes: money(original.capital, original.moneda), ahora: money(capital, formulario.moneda) })
    }
    const tasa = parseMonto(formulario.tasa)
    if (tasa !== null && tasa !== original.contrato?.tasa_anual) {
      lista.push({ etiqueta: 'Tasa anual', antes: `${original.contrato?.tasa_anual}%`, ahora: `${tasa}%` })
    }
    if (formulario.fechaInicio && formulario.fechaInicio !== original.contrato?.fecha_inicio) {
      lista.push({ etiqueta: 'Inicio', antes: fmtFecha(original.contrato?.fecha_inicio), ahora: fmtFecha(formulario.fechaInicio) })
    }
    const numero = `${formulario.prefijo}${formulario.numero}`
    if (formulario.numero && numero !== original.numero) lista.push({ etiqueta: 'N° de contrato', antes: original.numero ?? '—', ahora: numero })
    return lista
  }, [modo, formulario, elegida, original, referencia])

  function cambiarModo(m: Modo) {
    if (enCurso.current) return
    setModo(m)
    setError('')
  }

  async function reintentarCalculo(boton: HTMLButtonElement) {
    if (reintentando) return
    setReintentando(true)
    const r = await previa.refetch()
    setReintentando(false)
    // Con éxito el botón se va: el foco pasa al motivo (lo siguiente), no al contenedor. Si vuelve a fallar, se queda aquí.
    // Solo si el foco sigue en el botón (o huérfano): si mientras tanto la persona se fue a otro campo, no se lo roba.
    if (r.isSuccess && !r.isPlaceholderData && esFocoHuerfano(boton)) motivoRef.current?.focus({ preventScroll: true })
  }

  async function reemplazar(input: CrearContratoInput, cronograma: CuotaCronograma[]) {
    if (!motivoValido) {
      throw new CrmApiError(`Escribe el motivo del reemplazo (de ${MOTIVO_ELIMINACION_MIN} a ${MOTIVO_ELIMINACION_MAX} caracteres).`, 'INVERSION_MOTIVO_INVALIDO')
    }
    // Lo mismo que bloquea el botón, otra vez aquí (un Enter o un clic en el mismo instante en que cambia la fecha).
    if (!previaVigente.current.alDia || previaVigente.current.fechaInicio !== input.fecha_inicio) {
      throw new CrmApiError('El mes de la venta todavía se está calculando con la fecha nueva. Revísalo en «Antes de confirmar» y vuelve a confirmar.', 'INVERSION_PREVIA_DESACTUALIZADA')
    }
    const r = await controles.reemplazar(original, motivo.trim(), input, cronograma)
    controles.alTerminar(original, r)
    setTerminado(true)
  }

  async function conservar() {
    if (enCurso.current || !elegida || !motivoValido) return
    if (!previaVigente.current.alDia) {
      setError('El mes de la venta todavía se está calculando. Revísalo en «Antes de confirmar» y vuelve a confirmar.')
      return
    }
    enCurso.current = true
    setEnviando(true)
    setError('')
    try {
      const r = await controles.conservar(original, elegida.fuente_id, motivo.trim())
      controles.alTerminar(original, r)
      setTerminado(true)
    } catch (e) {
      setError(mensajeDeError(e, 'No se pudo reemplazar la inversión. Reintenta o consulta al administrador.'))
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }

  const p = previa.data
  const cuotasPagadas = cuotasVistas || p?.cuotas_pagadas === true
  const sinCandidatas = modo === 'existente' && candidatas.length === 0
  // Lo primero que falta para confirmar, en palabras (nunca una instrucción que no se cumple). Las cuotas pagadas ya
  // tienen su aviso; mientras recalcula el mes basta el indicador de la región.
  // Sin elegida, ya lo dicen la región («Elige la inversión que se conserva.») y el propio botón.
  const pista = cuotasPagadas || sinCandidatas || (modo === 'existente' && !elegida) ? null
    : modo === 'nueva' && !formularioListo ? razonFormulario ?? 'Completa los datos de la correcta.'
    : (previa.isError || reintentando) && !previaAlDia ? 'Sin el mes calculado no se puede confirmar: reintenta el cálculo.'
    : !motivoValido ? (excedido ? `Acorta el motivo a ${MOTIVO_ELIMINACION_MAX} caracteres.`
      : modo === 'nueva' ? 'Con el motivo escrito se activa «Reemplazar inversión».' : 'Con el motivo escrito se activa el botón de confirmar.')
    : null
  const puedeConfirmar = !cuotasPagadas && motivoValido && previaAlDia && (modo === 'nueva' ? formularioListo : elegida !== null)
  const c = original.contrato
  const pagoIntereses = c ? (c.tipo_interes === 'compuesto' ? 'Al vencimiento · interés compuesto'
    : `${MODALIDAD_LABEL[c.modalidad] ?? c.modalidad} · interés simple`) : '—'
  const idFormulario = `${id}-formulario`
  const enviandoClase = enviando ? 'pointer-events-none opacity-50' : undefined
  return <Dialog open onClose={() => { if (!enCurso.current) onCerrar() }} ariaLabel={titulo}
    focoAlCerrar={terminado ? focoAlTerminar : undefined}
    className="w-[1160px] max-w-[95vw] max-h-[92svh]">
    <DialogHeader className="flex-row flex-wrap items-center justify-between gap-3">
      <div className="min-w-0">
        <DialogTitle className="text-base">{titulo}</DialogTitle>
        <p id={`${id}-consecuencia`} className="mt-0.5 text-sm text-muted-foreground">La venta se conserva. La original se elimina y queda una copia «reemplazada por».</p>
      </div>
      <div role="group" aria-label="Cómo se reemplaza" className="inline-flex gap-1 rounded-xl bg-muted p-1">
        {([['nueva', 'Con los datos correctos'], ['existente', 'Quedarme con la otra']] as const).map(([m, etiqueta]) =>
          <button key={m} type="button" aria-pressed={modo === m} aria-controls={`${id}-medio`} disabled={enviando}
            className={cn('min-h-10 rounded-lg px-3.5 text-sm font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring',
              // Presionado: pastilla con borde de acento, no solo otro fondo.
              modo === m ? 'bg-card text-primary shadow-[var(--shadow-card)] ring-2 ring-accent' : 'text-[var(--muted-foreground-strong)] hover:text-foreground')}
            onClick={() => cambiarModo(m)}>{etiqueta}</button>)}
      </div>
    </DialogHeader>

    {/* Un solo desplazamiento en celular; en escritorio, cada columna el suyo. */}
    <div className="ac-scroll flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto px-5 py-4 lg:flex-row lg:overflow-hidden">
      {/* La original: solo lectura. */}
      <section aria-labelledby={`${id}-original`} className="lg:w-[270px] lg:shrink-0 lg:overflow-y-auto">
        <h3 id={`${id}-original`} className="mb-2 text-xs font-extrabold uppercase tracking-wide text-[var(--muted-foreground-strong)]">La original</h3>
        <div className="rounded-xl border border-border bg-muted/40 p-3.5 text-sm">
        {/* Nombre y analista a lo ancho (son largos); con candado: no cambian en un reemplazo. */}
        <dl className="space-y-2 border-b border-border pb-2.5">
          <div className="space-y-0.5">
            <dt className="text-muted-foreground">Cliente</dt>
            <dd className="flex items-start gap-1.5 text-base font-bold [overflow-wrap:anywhere]"><Lock aria-hidden className="mt-1 size-3.5 shrink-0 text-muted-foreground" />{ficha.persona.nombre}</dd>
          </div>
          <div className="space-y-0.5">
            <dt className="text-muted-foreground">Analista de la venta</dt>
            <dd className="flex items-start gap-1.5 font-semibold [overflow-wrap:anywhere]"><Lock aria-hidden className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />{original.analista_venta_nombre ?? original.analista_origen_nombre ?? 'Sin información'}</dd>
          </div>
        </dl>
        <dl className="mt-2.5 grid grid-cols-[auto_1fr] gap-x-3 gap-y-2">
          <dt className="text-muted-foreground">Capital</dt><dd className="text-right font-semibold tabular-nums">{money(original.capital, original.moneda)}</dd>
          <dt className="text-muted-foreground">Tasa anual</dt><dd className="text-right font-semibold">{c?.tasa_anual}%</dd>
          <dt className="text-muted-foreground">Inicio</dt><dd className="text-right font-semibold tabular-nums">{fmtFecha(c?.fecha_inicio)}</dd>
          <dt className="text-muted-foreground">Vencimiento</dt><dd className="text-right font-semibold tabular-nums">{fmtFecha(original.vence_en)}</dd>
          <dt className="text-muted-foreground">Pago de intereses</dt><dd className="text-right font-semibold">{pagoIntereses}</dd>
          <dt className="text-muted-foreground">Fecha comercial</dt><dd className="text-right font-semibold tabular-nums">{fmtFecha(original.fecha_comercial)}</dd>
          {original.cotitulares.length > 0 && <><dt className="text-muted-foreground">Cotitulares</dt><dd className="text-right font-semibold">{original.cotitulares.length}</dd></>}
        </dl>
        </div>
        <p className="mt-2 text-sm text-muted-foreground">El cliente y el analista no cambian en un reemplazo.</p>
      </section>

      {/* La correcta (el formulario de alta de siempre, precargado) o la que se conserva. El formulario NO se desmonta al
          cambiar de modo: lo editado, el resumen y el mes anunciado siguen coincidiendo al volver. */}
      <div id={`${id}-medio`} className="flex min-w-0 flex-col rounded-xl border border-border lg:min-h-0 lg:flex-1 lg:overflow-hidden">
        <section aria-labelledby={`${id}-correcta`} hidden={modo !== 'nueva'} className="ac-scroll flex flex-col lg:min-h-0 lg:flex-1 lg:overflow-y-auto">
          <ContratoNuevo
            clienteId={original.perfil_id ?? ''} clienteNombre={ficha.persona.nombre}
            categoriaFija="nuevo" borrador={borrador}
            incrustado={{ titulo: 'La correcta', idTitulo: `${id}-correcta`, idFormulario,
              onListoCambio: (listo, razon) => { setFormularioListo(listo); setRazonFormulario(razon) } }}
            onEnviandoCambio={v => { enCurso.current = v; setEnviando(v) }}
            onBorradorLocal={d => setFormulario({ capital: d.capital, moneda: d.moneda, tasa: d.tasa, fechaInicio: d.fechaInicio, prefijo: d.prefijo, numero: d.numero })}
            onRevisar={reemplazar}
            onCreado={() => {}} onOmitir={onCerrar} />
        </section>
        {modo === 'existente' && <section aria-labelledby={`${id}-conservar`} className="ac-scroll flex flex-col lg:min-h-0 lg:flex-1 lg:overflow-y-auto">
          <div className="border-b border-border px-5 py-3">
            <h3 id={`${id}-conservar`} className="flex items-center gap-2 text-[15px] font-bold tracking-tight">
              <RefreshCw aria-hidden className="size-4 text-primary" />La que se conserva</h3>
          </div>
          <div className="p-4">
            {candidatas.length === 0
              ? <p className="rounded-xl border border-dashed border-border px-3 py-6 text-center text-sm text-muted-foreground">
                  Este cliente no tiene otra inversión de Avance para conservar. Usa «Con los datos correctos».</p>
              : <RadioGroup grande leyenda="Inversiones de Avance de este cliente" valor={conservarId} onCambio={valor => { setConservarId(valor); setError('') }}
                  opciones={candidatas.map(i => {
                    const difiere = diferenciasDeCarga(original, i)
                    return {
                      valor: i.fuente_id,
                      deshabilitada: enviando,
                      etiqueta: <span className="flex flex-wrap items-center gap-2"><span className="tabular-nums">{i.numero || 'Inversión registrada'}</span>
                        {difiere.length === 0 ? <Badge dot color="var(--accent-press)" className="text-sm">Igual a la original</Badge>
                          : <Badge color="var(--muted-foreground-strong)" className="text-sm">Distinta: {difiere.join(', ')}</Badge>}</span>,
                      detalle: <span className="tabular-nums">{money(i.capital, i.moneda)} · {i.contrato?.tasa_anual}% · inicio {fmtFecha(i.contrato?.fecha_inicio)} · cargada el {fmtFecha(i.creado_en)}</span>,
                    }
                  })} />}
            {elegida && diferenciasDeCarga(original, elegida).length > 0 && <p className="mt-3 text-sm font-semibold text-warning-text">
              Solo se conserva una carga doble: la otra tiene que ser igual a la original (capital, moneda, tasa, fechas, pago de intereses y cotitulares).</p>}
          </div>
        </section>}
      </div>

      {/* Antes de confirmar: el mes (lo calcula el servidor), los cambios, el motivo y, al final, las acciones. */}
      <section aria-labelledby={`${id}-confirmar`} className="ac-scroll lg:w-[300px] lg:shrink-0 lg:overflow-y-auto">
        <h3 id={`${id}-confirmar`} className="mb-2 text-xs font-extrabold uppercase tracking-wide text-[var(--muted-foreground-strong)]">Antes de confirmar</h3>
        <div role="status" aria-live="polite" aria-busy={previa.isFetching || undefined}
          className={`rounded-xl border p-3.5 ${p?.cambia_mes ? 'border-warning/40 bg-warning/5' : 'border-accent/25 bg-accent/5'}`}>
          <p className="flex items-center justify-between gap-2 text-sm font-bold text-[var(--muted-foreground-strong)]">La venta queda en
            {previa.isFetching && !previa.isPending && <LoaderCircle aria-hidden className="size-3.5 animate-spin" />}</p>
          {consultaPrevia === null || !mostrarMes ? <p className="mt-1 text-sm text-[var(--muted-foreground-strong)]">{modo === 'nueva' ? 'Indica la fecha de inicio.'
            : sinCandidatas ? 'No hay otra inversión de este cliente para conservar.' : 'Elige la inversión que se conserva.'}</p>
            : previa.isPending || reintentando ? <p className="mt-1 flex items-center gap-2 text-sm text-[var(--muted-foreground-strong)]"><LoaderCircle aria-hidden className="size-4 animate-spin" />Calculando el mes…</p>
            : previa.isError ? <p className="mt-1 text-sm text-destructive-text">{mensajeDeError(previa.error, 'No se pudo calcular el mes.')}</p>
            : p && <>
              <p className="mt-1 text-xl font-extrabold tracking-tight text-primary">{mesLargo(p.mes_resultante)}</p>
              <p className={`mt-1 text-sm font-bold ${p.cambia_mes ? 'text-warning-text' : 'text-accent'}`}>
                {p.cambia_mes ? `Se muda desde ${mesLargo(p.mes_actual).toLowerCase()} (ese mes tiene que estar abierto)` : 'Igual que ahora'}</p>
              {p.fecha_corregida && <p className="mt-1 text-sm text-[var(--muted-foreground-strong)]">Gerencia corrigió la fecha de esta venta: se conserva.</p>}
            </>}
        </div>
        {/* Fuera de la región viva: un control no se anuncia como estado. */}
        {mostrarMes && (previa.isError || reintentando) && <Button type="button" variant="outline" size="lg"
          className={cn('mt-2 px-4', reintentando && 'pointer-events-none opacity-50')}
          aria-disabled={reintentando || undefined} aria-busy={reintentando || undefined} onClick={e => void reintentarCalculo(e.currentTarget)}>
          {reintentando ? <LoaderCircle className="animate-spin" aria-hidden /> : <RefreshCw aria-hidden />}
          {reintentando ? 'Calculando…' : 'Reintentar el cálculo'}</Button>}
        {cuotasPagadas && <p role="alert" className="mt-3 rounded-lg border border-destructive/25 bg-destructive/5 px-3 py-2 text-sm font-semibold text-destructive-text">
          Este contrato ya tiene cuotas pagadas: el reemplazo perdería esos pagos. No se puede reemplazar.</p>}
        {/* role explícito: Safari + VoiceOver le quita la semántica de lista a un ul con estilos. */}
        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
        {cambios.length > 0 && <ul role="list" className="mt-3 text-sm" aria-label="Cambios">
          {cambios.map(cambio => <li key={cambio.etiqueta} className="flex justify-between gap-3 border-t border-dashed border-border py-2">
            <span className="text-muted-foreground">{cambio.etiqueta}</span>
            <span className="text-right font-bold tabular-nums">{cambio.antes !== undefined && <><span className="sr-only">antes </span><span className="mr-1.5 font-medium text-muted-foreground line-through">{cambio.antes}</span><span className="sr-only">, ahora </span></>}{cambio.ahora}</span>
          </li>)}
        </ul>}
        <div className="mt-4 space-y-2">
          <Label htmlFor={`${id}-motivo`}>Motivo del reemplazo</Label>
          <Textarea ref={motivoRef} id={`${id}-motivo`} rows={3} value={motivo} disabled={enviando} aria-required="true"
            placeholder="Por ejemplo: el capital se registró mal" aria-invalid={excedido || undefined}
            aria-describedby={[`${id}-consecuencia`, `${id}-contador`, pista ? `${id}-pista` : null].filter(Boolean).join(' ')}
            onChange={e => setMotivo(e.target.value)} />
          <p id={`${id}-contador`} className={excedido ? 'text-sm font-semibold text-destructive-text' : 'text-sm text-muted-foreground'}>
            {largo} de {MOTIVO_ELIMINACION_MAX} caracteres · mínimo {MOTIVO_ELIMINACION_MIN}</p>
          {/* Montada desde el inicio: se anuncia al pasarse del tope, cuando el botón queda inactivo. */}
          <p role="status" className="sr-only">{excedido ? `El motivo pasa de ${MOTIVO_ELIMINACION_MAX} caracteres: acórtalo para poder reemplazar.` : ''}</p>
          {pista && <p id={`${id}-pista`} className="text-sm text-muted-foreground">{pista}</p>}
        </div>
        {error && <p role="alert" className="mt-3 rounded-lg border border-destructive/25 bg-destructive/5 px-3 py-2 text-sm font-semibold text-destructive-text">{error}</p>}
        {/* Las acciones van DESPUÉS del motivo (orden de foco y de lectura). Mientras envía, `aria-disabled` y no
            `disabled`: deshabilitar de verdad tira el foco a <body>. `enCurso` impide el segundo envío. */}
        <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-border pt-3">
          <Button type="button" variant="ghost" size="lg" className="px-4" disabled={enviando} onClick={onCerrar}>Cancelar</Button>
          {modo === 'nueva'
            ? <Button type="submit" form={idFormulario} size="lg" className={cn('px-4', enviandoClase)}
                disabled={!puedeConfirmar} aria-disabled={enviando || undefined} aria-busy={enviando || undefined}
                onClick={e => { if (enCurso.current) e.preventDefault() }}>
                {enviando ? <LoaderCircle className="animate-spin" aria-hidden /> : <RefreshCw aria-hidden />}
                {enviando ? 'Reemplazando…' : 'Reemplazar inversión'}
              </Button>
            : <Button type="button" size="lg" className={cn('px-4', enviandoClase)}
                disabled={!puedeConfirmar} aria-disabled={enviando || undefined} aria-busy={enviando || undefined}
                onClick={() => void conservar()}>
                {enviando ? <LoaderCircle className="animate-spin" aria-hidden /> : <RefreshCw aria-hidden />}
                {enviando ? 'Reemplazando…' : elegida ? `Quedarme con ${elegida.numero || 'esa inversión'}`
                  : sinCandidatas ? 'Sin inversión para conservar' : 'Elige la que se conserva'}
              </Button>}
        </div>
      </section>
    </div>
  </Dialog>
}
