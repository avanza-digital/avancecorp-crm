// «Reemplazar inversión» de una COOPERATIVA (Fase 4, 18/10/2026). Misma estructura y lenguaje que el de Avance
// (inversion-reemplazar.tsx): «La original» fija a la izquierda, «La correcta» al medio y «Antes de confirmar» a la
// derecha. Decisiones de Miguel: en una cooperativa el reemplazo cambia SOLO la cooperativa (Prodelco ↔ Qorilazo), la
// fecha comercial (el mes de la venta) y el comprobante; monto, moneda, plazo, tasa, n° de operación y nota se copian de
// la original (para eso está «Corregir»). Sin «Quedarme con la otra». Quién puede, si se puede y en qué mes queda la
// venta lo decide el servidor; la pantalla lo dice ANTES de confirmar.
import { useEffect, useId, useRef, useState, type ReactNode, type RefObject } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { Landmark, Lock } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { RadioGroup } from '@/components/ui/radio-group'
import {
  AccionesReemplazo, AvisoReemplazo, BotonReemplazo, CampoMotivo, DialogoReemplazo, ListaCambios, RegionMes, SeccionOriginal,
  type CambioReemplazo,
} from './inversion-reemplazar-partes'
import {
  CrmApiError, mensajeDeError, type CambiosReemplazoCooperativa, type InversionCooperativaReemplazadaResultado,
} from '@/data/crm-api'
import { fechaLima } from '@/lib/agenda-derivada'
import { COOPERATIVAS, admiteMoneda, type Cooperativa } from '@/lib/cierres-externos'
import { esFocoHuerfano } from '@/lib/foco'
import { fmtFecha, money } from '@/lib/format'
import {
  EMPRESA_NOMBRE, MOTIVO_ELIMINACION_MAX, largoMotivoEliminacion, mesLargo, motivoEliminacionValido,
  type EmpresaInversion, type FichaInversionista, type InversionFuente, type VistaPreviaReemplazoCooperativa,
} from '@/lib/inversionistas'
import { cn } from '@/lib/utils'

/** Lo que la pantalla le presta a la ficha para reemplazar una inversión de cooperativa (el servidor decide todo). */
export interface ControlesReemplazoCooperativa {
  puede: (inversion: InversionFuente) => boolean
  vistaPrevia: (inversion: InversionFuente, fechaComercial: string) => Promise<VistaPreviaReemplazoCooperativa>
  /** Sube el comprobante NUEVO a f4-comprobantes; se llama ANTES de confirmar. */
  subirComprobante: (ruta: string, archivo: File) => Promise<void>
  reemplazar: (inversion: InversionFuente, motivo: string, cambios: CambiosReemplazoCooperativa) => Promise<InversionCooperativaReemplazadaResultado>
  alTerminar: (inversion: InversionFuente, resultado: InversionCooperativaReemplazadaResultado) => void
}

type ModoComprobante = 'conservar' | 'nuevo'

/** Una fecha que vale la pena consultar: completa y no a medio teclear (Chrome emite «0002-10-05» mientras se escribe el año). */
const fechaConsultable = (f: string) => /^\d{4}-\d{2}-\d{2}$/.test(f) && f >= '2000-01-01'
const esCooperativa = (e: EmpresaInversion): e is Cooperativa => e !== 'avance'
/** Espejo de lo que admiten el bucket y la puerta: PDF, JPG o PNG de hasta 10 MB. */
const TIPOS_COMPROBANTE = ['application/pdf', 'image/jpeg', 'image/png']
const TOPE_COMPROBANTE = 10 * 1024 * 1024
const extensionDe = (tipo: string) => tipo === 'application/pdf' ? 'pdf' : tipo === 'image/png' ? 'png' : 'jpg'
const MONEDA_LARGA = { PEN: 'soles', USD: 'dólares' } as const

/** Un par dt/dd de «La original». */
function DatoOriginal({ etiqueta, children, cifra = false }: { etiqueta: string; children: ReactNode; cifra?: boolean }) {
  return <><dt className="text-muted-foreground">{etiqueta}</dt>
    <dd className={cn('text-right font-semibold [overflow-wrap:anywhere]', cifra && 'tabular-nums')}>{children}</dd></>
}

export function InversionReemplazarCooperativa({ inversion, ficha, controles, onCerrar, focoAlTerminar }: {
  inversion: InversionFuente
  ficha: FichaInversionista
  controles: ControlesReemplazoCooperativa
  onCerrar: () => void
  /** Adónde va el foco tras reemplazar: la fila de la original desaparece al refrescar la ficha. */
  focoAlTerminar?: RefObject<HTMLElement | null> | undefined
}) {
  const id = useId()
  const original = inversion
  const coopOriginal: Cooperativa = esCooperativa(original.empresa) ? original.empresa : COOPERATIVAS[0]
  const [cooperativa, setCooperativa] = useState<Cooperativa>(coopOriginal)
  const [fecha, setFecha] = useState(original.fecha_comercial ?? '')
  const [modoComprobante, setModoComprobante] = useState<ModoComprobante>('conservar')
  // El comprobante nuevo con SU ruta, decidida al elegirlo: un reintento sube al mismo sitio (la subida es idempotente
  // con los mismos bytes) y no deja copias sueltas en el bucket.
  const [comprobante, setComprobante] = useState<{ archivo: File; ruta: string } | null>(null)
  const [errorArchivo, setErrorArchivo] = useState('')
  const subido = useRef<string | null>(null)
  const [motivo, setMotivo] = useState('')
  const [enviando, setEnviando] = useState(false)
  const enCurso = useRef(false)
  const [error, setError] = useState('')
  // Terminado: se cierra en el render siguiente, ya con el foco apuntando a las inversiones.
  const [terminado, setTerminado] = useState(false)
  const cerrar = useRef(onCerrar)
  cerrar.current = onCerrar
  useEffect(() => { if (terminado) cerrar.current() }, [terminado])
  const [hoy] = useState(() => fechaLima(Date.now()))
  const motivoRef = useRef<HTMLTextAreaElement>(null)
  const motivoValido = motivoEliminacionValido(motivo)
  const excedido = largoMotivoEliminacion(motivo) > MOTIVO_ELIMINACION_MAX
  const titulo = `Reemplazar inversión en ${EMPRESA_NOMBRE[coopOriginal]}${original.numero ? ` ${original.numero}` : ''}`

  // La fecha que manda el mes, con un respiro al teclear; la previa se pide desde el principio para avisar ANTES de
  // llenar nada si la original no se puede reemplazar.
  const [fechaPrevia, setFechaPrevia] = useState(fecha)
  useEffect(() => {
    const t = setTimeout(() => setFechaPrevia(fecha), 350)
    return () => clearTimeout(t)
  }, [fecha])
  const consulta = fechaConsultable(fechaPrevia) ? fechaPrevia : null
  const previa = useQuery({
    queryKey: ['reemplazo-cooperativa-previa', original.fuente_id, consulta],
    queryFn: () => controles.vistaPrevia(original, consulta!),
    enabled: consulta !== null,
    retry: false,
    staleTime: 15_000,
    // Mientras recalcula queda la respuesta anterior: los avisos no parpadean ni se re-anuncian a medias.
    placeholderData: keepPreviousData,
  })
  // Confirmar exige un mes calculado PARA LO QUE SE ENVÍA: ni la respuesta anterior, ni la fecha en su respiro, ni un error.
  const previaAlDia = previa.isSuccess && !previa.isPlaceholderData && consulta !== null && fechaPrevia === fecha
  const previaVigente = useRef({ alDia: false, fecha: null as string | null })
  previaVigente.current = { alDia: previaAlDia, fecha: previaAlDia ? previa.data?.fecha_comercial_resultante ?? null : null }
  // Lo que impide reemplazar la original con CUALQUIER fecha (venta anulada, aporte adicional, movimientos): una vez
  // visto, queda aunque falle un recálculo con otra fecha.
  const [bloqueoOriginal, setBloqueoOriginal] = useState<string | null>(null)
  useEffect(() => {
    const d = previa.data
    if (!d) return
    const motivoBloqueo = d.no_reemplazable ?? (d.anulada ? 'La venta de esta inversión ya fue anulada: se elimina, no se reemplaza.'
      : !d.es_inicial ? 'Solo se reemplaza la inversión inicial de la cooperativa; un aporte adicional se corrige o se elimina.' : null)
    if (motivoBloqueo) setBloqueoOriginal(motivoBloqueo)
  }, [previa.data])
  // Reintentar el cálculo: el botón sigue montado mientras reintenta (si se desmontara, el foco caería al diálogo).
  const [reintentando, setReintentando] = useState(false)

  async function reintentarCalculo(boton: HTMLButtonElement) {
    if (reintentando) return
    setReintentando(true)
    const r = await previa.refetch()
    setReintentando(false)
    // Con éxito, el foco pasa al motivo (lo siguiente); si vuelve a fallar, se queda. Nunca se roba de otro campo.
    if (r.isSuccess && !r.isPlaceholderData && esFocoHuerfano(boton)) motivoRef.current?.focus({ preventScroll: true })
  }

  function elegirModoComprobante(modo: ModoComprobante) {
    setModoComprobante(modo)
    // Al volver a «conservar» se olvida el archivo: si luego eligen otro, el campo vacío no esconde uno anterior.
    if (modo === 'conservar') { setComprobante(null); setErrorArchivo('') }
    setError('')
  }

  function elegirArchivo(archivo: File | null) {
    setError('')
    if (!archivo) { setComprobante(null); setErrorArchivo(''); return }
    if (!TIPOS_COMPROBANTE.includes(archivo.type) || archivo.size < 1 || archivo.size > TOPE_COMPROBANTE) {
      setComprobante(null)
      setErrorArchivo('Usa un PDF, JPG o PNG de hasta 10 MB.')
      return
    }
    setErrorArchivo('')
    // La carpeta de ESTA persona y la de ESTE reemplazo: lo que el bucket y la puerta exigen.
    setComprobante({ archivo, ruta: `${original.inversionista_id.toLowerCase()}/reemplazo-${original.fuente_id.toLowerCase()}/${crypto.randomUUID()}.${extensionDe(archivo.type)}` })
  }

  const p = previa.data
  const fechaValida = fechaConsultable(fecha)
  const futura = fechaValida && fecha > hoy
  // La fecha de la original según el servidor (una fila antigua puede no tenerla: entonces fijarla ya es un cambio).
  const fechaActual = p ? p.fecha_comercial_actual : original.fecha_comercial
  const cambiaCooperativa = cooperativa !== coopOriginal
  const cambiaFecha = fechaValida && fecha !== fechaActual
  const comprobanteNuevo = modoComprobante === 'nuevo' ? comprobante : null
  const cambios: CambioReemplazo[] = [
    ...(cambiaCooperativa ? [{ etiqueta: 'Cooperativa', antes: EMPRESA_NOMBRE[coopOriginal], ahora: EMPRESA_NOMBRE[cooperativa] }] : []),
    ...(cambiaFecha ? [{ etiqueta: 'Fecha comercial', antes: fmtFecha(fechaActual), ahora: fmtFecha(fecha) }] : []),
    ...(comprobanteNuevo ? [{ etiqueta: 'Comprobante', ahora: 'Nuevo' }] : []),
  ]
  // Lo que depende de la fecha: con la respuesta anterior mientras recalcula (el botón sigue bloqueado hasta tener la suya).
  const bloqueoFecha = futura || p?.fecha_futura ? 'La fecha comercial no puede ser futura.'
    : p?.mes_sellado ? 'El mes de esta venta ya está cerrado: no se reemplaza. Un mes cerrado no se reescribe.'
    : p?.plazo_vencido ? `Venció el plazo de carga de ${mesLargo(p.mes_resultante).toLowerCase()}: con esta fecha la venta quedaría fuera de plazo. No se puede reemplazar así.`
    : null
  const bloqueado = bloqueoOriginal !== null || bloqueoFecha !== null
  // El aviso de la fecha se ve (y describe al campo) solo si no lo tapa un bloqueo de la original.
  const avisoFechaVisible = bloqueoOriginal === null && bloqueoFecha !== null
  const idAvisoFecha = `${id}-aviso-fecha`
  // La moneda que alguna cooperativa no admite: se explica en el grupo, a contraste completo (no en la opción apagada).
  const noAdmiten = COOPERATIVAS.filter(c => !admiteMoneda(c, original.moneda))
  const faltaArchivo = modoComprobante === 'nuevo' && comprobante === null
  // Lo primero que falta para confirmar, en palabras (nunca una instrucción que no se cumple). Un bloqueo ya tiene su aviso.
  const pista = bloqueado ? null
    : !fechaValida ? 'Indica la fecha comercial de la venta.'
    : faltaArchivo ? 'Elige el archivo del comprobante nuevo o conserva el de la original.'
    : cambios.length === 0 ? 'Cambia la cooperativa, la fecha comercial o el comprobante: si todo queda igual, no hay nada que reemplazar.'
    : (previa.isError || reintentando) && !previaAlDia ? 'Sin el mes calculado no se puede confirmar: reintenta el cálculo.'
    : !motivoValido ? (excedido ? `Acorta el motivo a ${MOTIVO_ELIMINACION_MAX} caracteres.` : 'Con el motivo escrito se activa «Reemplazar inversión».')
    : null
  const puedeConfirmar = !bloqueado && fechaValida && !faltaArchivo && cambios.length > 0 && motivoValido && previaAlDia

  async function confirmar() {
    if (enCurso.current || !puedeConfirmar) return
    // Lo mismo que bloquea el botón, otra vez aquí (un clic en el mismo instante en que cambia la fecha).
    if (!previaVigente.current.alDia || previaVigente.current.fecha !== fecha) {
      setError('El mes de la venta todavía se está calculando con la fecha nueva. Revísalo en «Antes de confirmar» y vuelve a confirmar.')
      return
    }
    enCurso.current = true
    setEnviando(true)
    setError('')
    try {
      // El comprobante nuevo va ANTES: si no sube, no se llama a la puerta (nada cambió).
      if (comprobanteNuevo && subido.current !== comprobanteNuevo.ruta) {
        try {
          await controles.subirComprobante(comprobanteNuevo.ruta, comprobanteNuevo.archivo)
        } catch (e) {
          const detalle = e instanceof CrmApiError && e.code === '22023' ? e.message : 'No se pudo subir el comprobante nuevo.'
          setError(`${detalle} No se hizo ningún cambio: vuelve a intentarlo.`)
          return
        }
        subido.current = comprobanteNuevo.ruta
      }
      // Solo viaja lo que cambia: lo que no viaja, el servidor lo toma de la original.
      const r = await controles.reemplazar(original, motivo.trim(), {
        ...(cambiaCooperativa ? { cooperativa } : {}),
        ...(cambiaFecha ? { fechaComercial: fecha } : {}),
        ...(comprobanteNuevo ? { comprobanteRuta: comprobanteNuevo.ruta } : {}),
      })
      controles.alTerminar(original, r)
      setTerminado(true)
    } catch (e) {
      setError(mensajeDeError(e, 'No se pudo reemplazar la inversión. Reintenta o consulta al administrador.'))
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }

  const condiciones = original.condiciones_coopac
  return <DialogoReemplazo id={id} titulo={titulo} onClose={() => { if (!enCurso.current) onCerrar() }}
    focoAlCerrar={terminado ? focoAlTerminar : undefined}
    original={<SeccionOriginal id={id} cliente={ficha.persona.nombre}
      analista={original.analista_venta_nombre ?? original.analista_origen_nombre ?? 'Sin información'}
      nota="El cliente y el analista no cambian en un reemplazo.">
      <DatoOriginal etiqueta="Cooperativa">{EMPRESA_NOMBRE[coopOriginal]}</DatoOriginal>
      <DatoOriginal etiqueta="Monto" cifra>{money(original.capital, original.moneda)}</DatoOriginal>
      <DatoOriginal etiqueta="Fecha comercial" cifra>{fmtFecha(original.fecha_comercial)}</DatoOriginal>
      <DatoOriginal etiqueta="Vencimiento" cifra>{fmtFecha(original.vence_en)}</DatoOriginal>
      {condiciones && <>
        <DatoOriginal etiqueta="Plazo">{condiciones.plazo_meses} meses</DatoOriginal>
        <DatoOriginal etiqueta="Rentabilidad anual">{condiciones.tasa_anual}%</DatoOriginal>
      </>}
      <DatoOriginal etiqueta="N° de operación" cifra>{original.numero_transaccion || '—'}</DatoOriginal>
      {original.numero && <DatoOriginal etiqueta="Referencia">{original.numero}</DatoOriginal>}
    </SeccionOriginal>}
    medio={<section aria-labelledby={`${id}-correcta`} className="ac-scroll flex flex-col lg:min-h-0 lg:flex-1 lg:overflow-y-auto">
      <div className="border-b border-border px-5 py-3">
        <h3 id={`${id}-correcta`} className="flex items-center gap-2 text-[15px] font-bold tracking-tight">
          <Landmark aria-hidden className="size-4 text-primary" />La correcta</h3>
      </div>
      <div className="space-y-5 p-4">
        {/* La de la original va primero: es la marcada y la que recibe el foco al abrir (el primer control). Espejo del
            catálogo del servidor: no se ofrece una cooperativa que no admite la moneda de la inversión. */}
        <RadioGroup grande leyenda="Cooperativa" valor={cooperativa} onCambio={c => { setCooperativa(c); setError('') }}
          descripcion={noAdmiten.length > 0
            ? `${noAdmiten.map(c => EMPRESA_NOMBRE[c]).join(' y ')} no admite inversiones en ${MONEDA_LARGA[original.moneda]}.` : undefined}
          opciones={[coopOriginal, ...COOPERATIVAS.filter(c => c !== coopOriginal)].map(c => ({
            valor: c, etiqueta: EMPRESA_NOMBRE[c], deshabilitada: enviando || !admiteMoneda(c, original.moneda),
            detalle: c === coopOriginal ? 'La de la original' : undefined,
          }))} />
        <div className="space-y-1.5">
          <Label htmlFor={`${id}-fecha`} className="text-base">Fecha comercial</Label>
          <Input id={`${id}-fecha`} type="date" required value={fecha} max={hoy} disabled={enviando}
            className="h-11 text-base sm:max-w-60" aria-invalid={(futura && avisoFechaVisible) || undefined}
            aria-describedby={[`${id}-fecha-ayuda`, futura && avisoFechaVisible ? idAvisoFecha : null].filter(Boolean).join(' ')}
            onChange={e => { setFecha(e.target.value); setError('') }} />
          <p id={`${id}-fecha-ayuda`} className="text-sm text-muted-foreground">
            Decide el mes de la venta.{condiciones ? ' El vencimiento se recalcula con el mismo plazo.' : ''}</p>
        </div>
        <RadioGroup grande leyenda="Comprobante de depósito" valor={modoComprobante} onCambio={elegirModoComprobante}
          opciones={[
            { valor: 'conservar', etiqueta: 'Conservar el de la original', deshabilitada: enviando,
              detalle: p && !p.comprobante ? 'La original no tiene comprobante cargado' : undefined },
            { valor: 'nuevo', etiqueta: 'Subir otro comprobante', deshabilitada: enviando },
          ]} />
        {modoComprobante === 'nuevo' && <div className="space-y-1.5">
          <Label htmlFor={`${id}-comprobante`} className="text-base">Comprobante nuevo (PDF, JPG o PNG, hasta 10 MB)</Label>
          <Input id={`${id}-comprobante`} type="file" accept="application/pdf,image/jpeg,image/png" disabled={enviando}
            aria-invalid={errorArchivo ? true : undefined} aria-describedby={errorArchivo ? `${id}-comprobante-error` : undefined}
            onChange={e => elegirArchivo(e.target.files?.[0] ?? null)} />
          {errorArchivo
            ? <p id={`${id}-comprobante-error`} role="alert" className="text-sm font-semibold text-destructive-text">{errorArchivo}</p>
            : comprobante && <p className="text-sm text-muted-foreground [overflow-wrap:anywhere]">Archivo elegido: {comprobante.archivo.name}</p>}
        </div>}
        <p className="flex items-start gap-2 rounded-xl border border-dashed border-border bg-muted/30 p-3 text-sm text-[var(--muted-foreground-strong)]">
          <Lock aria-hidden className="mt-0.5 size-4 shrink-0" />
          El monto, la moneda, el plazo, la tasa, el n° de operación y la nota se copian de la original. Para cambiarlos usa «Corregir».</p>
      </div>
    </section>}
    confirmar={<>
      <RegionMes previa={previa} reintentando={reintentando} onReintentar={b => void reintentarCalculo(b)}
        vacio={consulta === null ? 'Indica la fecha comercial.' : null} reintento={previa.isError || reintentando} />
      {bloqueoOriginal ? <AvisoReemplazo>{bloqueoOriginal}</AvisoReemplazo>
        : avisoFechaVisible && <AvisoReemplazo id={idAvisoFecha}>{bloqueoFecha}</AvisoReemplazo>}
      <ListaCambios cambios={cambios} />
      <CampoMotivo ref={motivoRef} id={id} valor={motivo} onCambio={setMotivo} deshabilitado={enviando}
        placeholder="Por ejemplo: se registró en la cooperativa equivocada" pista={pista} />
      {error && <AvisoReemplazo>{error}</AvisoReemplazo>}
      <AccionesReemplazo enviando={enviando} onCancelar={onCerrar}>
        <BotonReemplazo type="button" enviando={enviando} habilitado={puedeConfirmar} etiqueta="Reemplazar inversión"
          onClick={() => void confirmar()} />
      </AccionesReemplazo>
    </>} />
}
