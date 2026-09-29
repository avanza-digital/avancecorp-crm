import { FormTareaPostventa } from './postventa-tarea'
// Diálogo de cierre de tarea — el corazón del MOTOR (Fase B del plan v2).
//
// Flujo en un solo diálogo: resultado 1-tap (obligatorio en llamadas — patrón
// Outreach: sin disposición la llamada no cuenta) → el motor PROPONE la
// siguiente (cuándo + canal + qué, con alternancia) → [Cerrar y agendar] o
// "Saltar esta vez" a UN toque (jamás candado: el lead saltado cae al bucket
// amarillo "sin próxima acción", visible e inocultable).
//
// La escritura real es la RPC atómica crm.cerrar_tarea (cierre + log +
// siguiente en una transacción); aquí solo se arma el input y se traduce el
// resultado a toasts honestos.
import { useEffect, useMemo, useRef, useState } from 'react'
import { toast } from 'sonner'
import {
  CheckCircle2,
  PhoneCall,
  PhoneMissed,
  Send,
  MessageSquare,
  Users,
  UserX,
  CircleCheckBig,
  CalendarX2,
} from 'lucide-react'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import {
  CAMPOS_REUNION_VACIOS,
  CamposReunion,
  camposTareaDeReunion,
  type EstadoCamposReunion,
} from '@/components/app/campos-reunion'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { useCRMData } from '@/lib/store-context'
import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
import { useAhora } from '@/lib/ahora'
import { sugerirSiguiente } from '@/lib/motor-siguiente'
import { tareaAEvento } from '@/lib/agenda-derivada'
import { camposDeSugerencia, isoDeCampos, type CamposSiguiente } from '@/lib/campos-siguiente'
import { notaNoShow } from '@/lib/nota-no-show'
import { esAbierto } from '@/lib/inteligencia'
import { retrocesoPorAnularReunion } from '@/lib/avance-automatico'
import { plantonDe } from '@/lib/cadencia'
import { money, primerNombre } from '@/lib/format'
import type { Moneda } from '@/lib/format'
import {
  ETAPA_INFO,
  MOTIVOS_NO_REALIZADA,
  RESULTADOS_REUNION,
  TIPOS_CONVERSACION_K,
  TIPOS_TAREA,
  esTipoTarea,
  type Tarea,
  type MotivoNoRealizadaManual,
  type ResultadoReunionOperativo,
  type TipoActividadManual,
  type TipoTarea,
} from '@/lib/tipos'
import { cn } from '@/lib/utils'
import { presentarCitas } from '@/lib/terminologia'
import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
import { nombreClienteDeTitulo } from '@/lib/nombre-cliente-tarea'

/** Opciones de resultado por tipo de tarea (1 tap, sin formularios). */
interface OpcionCierre {
  k: string
  label: string
  icono: typeof PhoneCall
  estado: 'completada' | 'no_show'
  resultado: TipoActividadManual | null
}

function opcionesDe(tipo: TipoTarea): OpcionCierre[] {
  switch (tipo) {
    case 'llamada':
      return [
        {
          k: 'contesto',
          label: 'Contestó',
          icono: PhoneCall,
          estado: 'completada',
          resultado: 'llamada_realizada',
        },
        {
          k: 'no_contesto',
          label: 'No contestó',
          icono: PhoneMissed,
          estado: 'completada',
          resultado: 'llamada_no_contestada',
        },
      ]
    case 'whatsapp':
      return [
        {
          k: 'enviado',
          label: 'Enviado',
          icono: Send,
          estado: 'completada',
          resultado: 'whatsapp_enviado',
        },
        {
          k: 'respondio',
          label: 'Respondió',
          icono: MessageSquare,
          estado: 'completada',
          resultado: 'whatsapp_recibido',
        },
      ]
    case 'reunion':
      return [
        {
          k: 'realizada',
          label: 'Se realizó',
          icono: Users,
          estado: 'completada',
          resultado: 'reunion_realizada',
        },
        {
          k: 'no_show',
          label: 'No asistió',
          icono: UserX,
          estado: 'no_show',
          resultado: null,
        },
      ]
    case 'tarea':
      return [
        {
          k: 'hecha',
          label: 'Hecha',
          icono: CircleCheckBig,
          estado: 'completada',
          resultado: null,
        },
      ]
  }
}

export function CerrarTareaDialog({ tarea, onCerrar }: { tarea: Tarea | null; onCerrar: () => void }) {
  const [ocupado, setOcupado] = useState(false)
  const { lead, asegurarLead } = useCRMData()
  // Fase 4e «sin topes»: sin foto inicial, el lead de la llamada puede no ser
  // conocido aún (entrar a la Agenda sin abrir su ficha); se asegura por id al
  // abrir el diálogo para que el panel tipificado aparezca (Codex 20/09).
  const leadIdLlamada = tarea?.tipo === 'llamada' && tarea.lead_id && !tarea.inversionista_id ? tarea.lead_id : null
  const conocido = leadIdLlamada ? lead(leadIdLlamada) != null : true
  useEffect(() => {
    if (leadIdLlamada && !conocido) void asegurarLead(leadIdLlamada).catch(() => {})
  }, [leadIdLlamada, conocido, asegurarLead])
  // Gestión Diaria F2: una tarea de LLAMADA sobre un lead se cierra con el
  // resultado tipificado (panel del mockup 5), que además la cierra
  // (p_tarea_id). El diálogo conserva su cuarta salida («anular»); al pulsar
  // «Registrar resultado» el panel ocupa su lugar (un solo diálogo a la vez).
  // Las tareas de cliente (perfil) y el resto de tipos siguen su cierre de siempre.
  const [panelLlamada, setPanelLlamada] = useState<string | null>(null)
  const leadDeLlamada = tarea?.tipo === 'llamada' && tarea.lead_id && !tarea.inversionista_id ? lead(tarea.lead_id) : undefined
  // El panel se APILA sobre este diálogo (Radix apila modales y `escape-dialogo`
  // cierra por capas): así el origen del foco (el botón «Registrar resultado…»)
  // sigue montado y, al cerrar los dos, el foco vuelve a la fila de la agenda
  // desde la que se abrió (revisión a11y 20/09). Sustituirlo desmontaba el
  // origen y el foco caía al cuerpo del documento.
  return (
    <>
      <Dialog open={tarea != null} onClose={() => { if (!ocupado) onCerrar() }} ariaLabel="Cerrar tarea">
        {tarea && (tarea.inversionista_id
          ? <FormTareaPostventa key={tarea.id} tarea={tarea} onCerrar={onCerrar} onOcupado={setOcupado} />
          : <FormCierre key={tarea.id} tarea={tarea} onCerrar={onCerrar} onRegistrarLlamada={leadDeLlamada ? () => setPanelLlamada(tarea.id) : undefined} />)}
      </Dialog>
      {tarea && leadDeLlamada && panelLlamada === tarea.id && (
        <RegistrarResultado key={tarea.id} lead={leadDeLlamada} tarea={tarea} onClose={() => { setPanelLlamada(null); onCerrar() }} />
      )}
    </>
  )
}

function FormCierre({ tarea, onCerrar, onRegistrarLlamada }: { tarea: Tarea; onCerrar: () => void; onRegistrarLlamada?: (() => void) | undefined }) {
  // Tarea de LLAMADA de un lead: el resultado (siete opciones) vive en el panel
  // de Gestión Diaria; aquí quedan el contexto del lead y «anular».
  const llamadaTipificada = onRegistrarLlamada != null
  const { lead, completarTarea, anularTarea, descartar, tareasDe } = useCRMData()
  const ahora = useAhora()
  const l = tarea.lead_id ? lead(tarea.lead_id) : undefined
  // Historial POR LEAD (Fase 1 «sin topes»): el plantón y el retroceso ya no
  // se leen de la lista global del ámbito, que PostgREST recorta a 1 000 filas.
  const historial = useActividadesDeLead(tarea.lead_id ?? null)
  // Sin el historial servido no se afirma nada sobre el lead: ni plantón ni
  // etapa de retroceso (con señales vacías la función diría «Nuevo» sin base).
  const historialListo = !historial.cargando && historial.error == null
  const nombreSujeto =
    l?.nombre_completo ??
    (tarea.perfil_id
      ? nombreClienteDeTitulo(tarea.titulo)
      : '')
  const opciones = opcionesDe(tarea.tipo)

  const [eleccion, setEleccion] = useState<OpcionCierre | null>(
    // "Hecha" es la única opción de una tarea genérica: preseleccionada.
    opciones.length === 1 ? (opciones[0] ?? null) : null,
  )
  const [detalle, setDetalle] = useState('')
  const [resultadoReunion, setResultadoReunion] = useState<ResultadoReunionOperativo | null>(null)
  // CAPITAL DE LA ENTREVISTA. Precargado con lo que el lead ya trae: Enter
  // confirma tal cual y el paso cuesta un gesto, no un formulario (mismo patrón
  // que el diálogo de capital del kanban, que este cierre deja de necesitar).
  const [capitalMonto, setCapitalMonto] = useState(String(l?.monto_estimado ?? ''))
  const [capitalMoneda, setCapitalMoneda] = useState<Moneda>(l?.moneda ?? 'PEN')
  const [motivoAnulacion, setMotivoAnulacion] = useState<MotivoNoRealizadaManual | ''>('')
  const [detalleAnulacion, setDetalleAnulacion] = useState('')
  const [camposReunionSiguiente, setCamposReunionSiguiente] = useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)
  const [saltar, setSaltar] = useState(false)
  // `null` = el analista NO ha tocado la siguiente → manda la sugerencia del
  // motor. En cuanto edita un campo, esto pasa a ser la fuente y el motor deja
  // de pisarle lo escrito.
  const [editados, setEditados] = useState<CamposSiguiente | null>(null)
  // Instante en que se eligió el resultado. La sugerencia se calcula con ESTE
  // y no con el reloj vivo: alimenta un formulario editable, y una fecha que
  // cambia sola cada minuto es un formulario que se mueve mientras lo llenas.
  const [tsEleccion, setTsEleccion] = useState(() => Date.now())

  const sugerencia = useMemo(
    () =>
      eleccion
        ? sugerirSiguiente({
            tareaTipo: tarea.tipo,
            estado: eleccion.estado,
            resultado: eleccion.resultado,
            leadNombre: nombreSujeto,
            // Ley 29571 "No Insista": el kill-switch de motor-siguiente.ts
            // existía desde el plan v2 pero NINGÚN llamador le pasaba el flag
            // —`Lead` ni siquiera lo traía del servidor—, así que el motor
            // proponía insistir contra quien había pedido que no lo llamaran.
            noContactar: l?.no_contactar ?? null,
            ahora: tsEleccion,
          })
        : null,
    [eleccion, tarea.tipo, nombreSujeto, l?.no_contactar, tsEleccion],
  )

  /**
   * FUENTE ÚNICA de lo que muestra y manda el formulario de la siguiente.
   *
   * Antes había dos: un `useMemo` decidía si el panel se VE y una copia a
   * estado dentro del `onClick` decidía qué DICE. Una tarea genérica tiene UNA
   * sola opción y nace preseleccionada, así que ese `onClick` no ocurría nunca
   * → el panel salía visible y EN BLANCO, el lead se caía de la cadencia en
   * silencio, y si el analista escribía el título que faltaba, confirmar lanzaba
   * un `RangeError` que se llevaba el diálogo al error boundary.
   */
  const campos: CamposSiguiente | null = editados ?? (sugerencia ? camposDeSugerencia(sugerencia) : null)

  const editar = (parche: Partial<CamposSiguiente>) => {
    setEditados({
      ...(campos ?? { tipo: 'llamada', titulo: '', fecha: '', hora: '10:00' }),
      ...parche,
    })
  }

  /**
   * Elegir un resultado RESETEA todo lo que dependía del anterior. Sin esto:
   *  · el checkbox «cerrar por no responde» sobrevivía a corregir el resultado
   *    a «Contestó» → se descartaba por «No responde» un lead que acababa de
   *    contestar, con la llamada exitosa en su propio timeline desmintiéndolo;
   *  · `editados` conservaba canal y fecha del resultado anterior, y la
   *    alternancia del motor (llamada fallida → WhatsApp) quedaba anulada;
   *  · el instante se congela aquí para que el reloj vivo (useAhora, que
   *    tickea) no mueva la fecha propuesta bajo el cursor mientras el analista
   *    llena el formulario — en el borde de las 20:00 saltaba de día.
   */
  const elegir = (op: OpcionCierre) => {
    setEleccion(op)
    setEditados(null)
    setSaltar(false)
    setCerrarLead(false)
    setTsEleccion(Date.now())
    setResultadoReunion(null)
    setCapitalMonto(String(l?.monto_estimado ?? ''))
    setCapitalMoneda(l?.moneda ?? 'PEN')
    setCamposReunionSiguiente(CAMPOS_REUNION_VACIOS)
    // Elegir un resultado es afirmar algo del cliente: sale del modo anular.
    setAnulando(false)
  }

  // SALIDA DE LA CADENCIA: tras 5 intentos sin respuesta en ≥3 días, el motor
  // deja de proponer otro toque y ofrece cerrar. Se ofrece, no se hace: nada en
  // este CRM descarta solo, y menos por un contador.
  // Ofrecer «cerrar por no responde» mientras se registra que el cliente SÍ
  // respondió es una contradicción — y era además la grieta por la que el gate
  // del store (que evalúa el timeline del render ANTERIOR) dejaba pasar un
  // descarte con una conversación recién escrita desmintiéndolo.
  const esConversacion = eleccion?.resultado != null && TIPOS_CONVERSACION_K.has(eleccion.resultado)
  const planton = historialListo && tarea.lead_id && !esConversacion ? plantonDe(historial.items, ahora) : null
  const [cerrarLead, setCerrarLead] = useState(false)
  // Solo el cierre por plantón espera al servidor (ver `cerrarPorNoResponde`).
  // Mientras espera, el botón se bloquea: un segundo clic mandaría un cierre de
  // una tarea que el espejo local ya dio por cerrada → "Tarea no encontrada".
  const [procesando, setProcesando] = useState(false)
  // MODO ANULAR — "esta tarea ya no hace falta". No es un resultado más: no
  // afirma NADA sobre el cliente, así que no puede vivir en la grilla de
  // "¿Qué pasó?" (ahí, entre Contestó y No contestó, se elegiría por descarte).
  // Vive debajo, en tono menor, y toma el diálogo entero al activarse: mientras
  // está encendido no hay resultado, ni siguiente, ni plantón que valgan.
  const [anulando, setAnulando] = useState(false)
  // El disparador de anular se DESMONTA al activarse, y Radix solo rescata el
  // foco al contenedor del diálogo. Quien no ve pulsaría el enlace y no oiría
  // ni el panel nuevo ni el «no se puede deshacer» — justo lo que hay que leer
  // antes de una acción irreversible. Mismo patrón que ya usa la advertencia de
  // conversión en lead-drawer.tsx: el foco entra al panel, y «Volver» lo
  // devuelve al enlace exactamente de donde salió.
  const refPanelAnular = useRef<HTMLDivElement>(null)
  const refEnlaceAnular = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    if (anulando) refPanelAnular.current?.focus()
  }, [anulando])

  /**
   * El capital viaja SOLO cuando la cita de un lead se cierra como realizada:
   * ahí la cita es una entrevista y la etapa sube a «Entrevista realizada». La
   * puerta `crm.cerrar_reunion_v3` rechaza una cifra en cualquier otro caso —a
   * quien no vino nadie le propuso capital—.
   */
  const capitalDe = (op: OpcionCierre) =>
    tarea.tipo === 'reunion' && tarea.lead_id && op.estado === 'completada'
      && resultadoReunion !== 'no_interesado'
      ? { monto_estimado: Number(capitalMonto), moneda: capitalMoneda }
      : null

  /** ¿Hay capital que declarar? Con «No interesado» no hubo propuesta. */
  const pideCapital =
    tarea.tipo === 'reunion'
    && tarea.lead_id != null
    && eleccion?.estado === 'completada'
    && resultadoReunion !== 'no_interesado'

  /** Rastro que va al timeline — MISMO cálculo para las dos salidas del
   *  diálogo (cierre normal y cierre por plantón), o el no-show volvía a
   *  quedar mudo por una de las dos puertas. */
  const rastroDe = (op: OpcionCierre) => {
    const esPlanton = op.estado === 'no_show'
    return {
      resultado_tipo:
        op.resultado ?? (esPlanton || (tarea.tipo === 'tarea' && detalle.trim()) ? ('nota' as const) : null),
      resultado_detalle: esPlanton ? notaNoShow(tarea.vence_en, detalle) : detalle.trim() || null,
    }
  }

  const cerrarPorNoResponde = async () => {
    if (!eleccion || !tarea.lead_id) return
    const leadId = tarea.lead_id
    // ⚠️ ORDEN NO NEGOCIABLE EN EL SERVIDOR: PRIMERO la tarea, DESPUÉS el
    // descarte. Al pasar el lead a `descartado`, el trigger
    // `trg_leads_zz_sync_tareas` cancela todas sus tareas pendientes — y
    // entonces `crm.cerrar_tarea` ya no encontraría la suya (`for update` exige
    // `estado='pendiente'`) y reventaría con "Tarea no encontrada", perdiéndose
    // la actividad del último intento: la EVIDENCIA misma del descarte.
    // Encadenarlas en el espejo local NO basta — las dos viajan por red y
    // salían en el mismo tick, así que el orden de llegada era una lotería.
    // Por eso se espera a `res.persistido`: la promesa de la RPC ya aceptada
    // por el servidor (en demo resuelve al toque, sin esperar a nadie).
    setProcesando(true)
    const res = completarTarea({
      tarea_id: tarea.id,
      estado: eleccion.estado,
      capital: capitalDe(eleccion),
      ...rastroDe(eleccion),
      siguiente: null,
    })
    if (!res.ok) {
      setProcesando(false)
      toast.error(res.error ?? 'No se pudo cerrar la tarea')
      return
    }
    if (!(await (res.persistido ?? Promise.resolve(true)))) {
      // El servidor RECHAZÓ el cierre: el store ya revirtió el espejo y avisó.
      // No se descarta — el lead quedaría cerrado por «No responde» sin la
      // actividad que lo sostiene. La tarea sigue pendiente: se puede reintentar
      // desde este mismo diálogo, que se queda abierto a propósito.
      setProcesando(false)
      return
    }
    const cerrado = descartar(leadId, 'no_responde', detalle.trim() || undefined)
    if (!cerrado.ok) {
      // El cierre de la tarea YA persistió: no se miente diciendo que se
      // revirtió. Se avisa exactamente qué quedó hecho y qué no.
      toast.warning('Tarea cerrada, pero el lead no se pudo descartar')
      onCerrar()
      return
    }
    onCerrar()
    toast.info(`${l ? primerNombre(l.nombre_completo) : 'El lead'} se cerró por «No responde»`)
  }

  /**
   * ¿Sacar ESTA tarea de en medio deja al lead sin ninguna otra pendiente?
   *
   * Una sola pregunta para las DOS salidas del diálogo (cerrar y anular): el
   * aviso ámbar "quedó SIN próxima acción" solo se da cuando es VERDAD. Un lead
   * cerrado jamás aparece en ese bucket (lo filtra `esAbierto`) y a un "No
   * Insista" no se le puede empujar a agendar nada — prometer esa consecuencia
   * en esos dos casos sería mentir. Se evalúa en render, o sea ANTES de que la
   * mutación optimista saque la tarea de la lista.
   */
  const quedaSinPlan = l != null && esAbierto(l) && !l.no_contactar && !tareasDe(l.id).some((t) => t.id !== tarea.id)

  /**
   * ¿Anular ESTA tarea devuelve el lead a una etapa anterior?
   *
   * Se calcula en RENDER (no en el handler) porque el panel de confirmación
   * tiene que DECIRLO antes de que el analista pulse: bajar de etapa a espaldas
   * de quien anula es exactamente el susto que el resto del CRM evita cantando
   * cada avance. El handler vuelve a leer el retroceso REAL que devuelve el
   * store —esta copia es solo para el texto— y por eso las dos no pueden
   * divergir en la escritura, solo, como mucho, en el aviso previo.
   */
  const retrocesoPrevisto = historialListo && l != null ? retrocesoPorAnularReunion(l, tarea, tareasDe(l.id), historial.senales) : null

  /**
   * ANULAR — sale del diálogo SIN afirmar nada del cliente: ni actividad de
   * contacto en el timeline, ni siguiente encadenada (ver `anularTarea` en
   * lib/store.tsx). Es lo que faltaba para poder decir "ya agendé la reunión,
   * esta llamada sobra" sin tener que mentir con «Contestó»/«No contestó».
   *
   * Lo ÚNICO que mueve es la etapa, y solo hacia atrás y solo al anular la
   * última reunión viva: pedido de Miguel del 2026-07-26.
   */
  const anular = async () => {
    let res
    if (tarea.tipo === 'reunion') {
      if (!motivoAnulacion) {
        toast.error('Selecciona por qué se cancela la cita')
        return
      }
      if (motivoAnulacion === 'otro' && !detalleAnulacion.trim()) {
        toast.error('Describe brevemente por qué se cancela la cita')
        return
      }
      res = anularTarea(tarea.id, {
        motivo: motivoAnulacion,
        detalle: detalleAnulacion.trim() || null,
      })
    } else {
      res = anularTarea(tarea.id)
    }
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo anular la tarea')
      return
    }
    // En postventa no se cierra el diálogo con el mero espejo optimista: una
    // reunión de cliente necesita que cerrar_tarea confirme también el motivo
    // estructurado. Si RLS/RPC la rechaza, el store revierte y este mismo
    // diálogo queda disponible para reintentar sin haber anunciado éxito.
    setProcesando(true)
    const persistio = await (res.persistido ?? Promise.resolve(true))
    setProcesando(false)
    if (!persistio) return
    onCerrar()
    // Orden de los avisos: el retroceso de etapa manda sobre el "sin próxima
    // acción" porque es el cambio más grande y el que el analista no pidió
    // explícitamente. Los dos son ciertos a la vez a menudo (anular la última
    // reunión suele dejar al lead sin plan), pero dos toasts encima de otro se
    // pisan; gana el que más sorprende.
    if (res.retroceso && l) {
      toast.warning(`Tarea anulada — ${primerNombre(l.nombre_completo)} vuelve a «${ETAPA_INFO[res.retroceso].label}»`)
    } else if (quedaSinPlan && l) {
      toast.warning(`Tarea anulada — ${primerNombre(l.nombre_completo)} quedó SIN próxima acción`)
    } else {
      toast.success('Tarea anulada — fuera de tu agenda')
    }
  }

  const confirmar = async () => {
    if (procesando) return
    if (!eleccion) return
    if (tarea.tipo === 'reunion' && eleccion.estado === 'completada' && !resultadoReunion) {
      toast.error('Selecciona el resultado comercial de la cita')
      return
    }
    if (pideCapital) {
      const monto = Number(capitalMonto)
      if (!capitalMonto.trim() || !Number.isFinite(monto) || monto <= 0) {
        toast.error('Escribe el capital que le propusiste en la entrevista')
        return
      }
    }
    // El plantón sustituye el flujo normal: cierra la tarea y cierra el lead,
    // en ese orden (ver `cerrarPorNoResponde`). Es la ÚNICA salida asíncrona
    // del diálogo — espera a que el cierre haya llegado al servidor.
    if (planton && cerrarLead) {
      void cerrarPorNoResponde()
      return
    }
    const quiereSiguiente = !saltar && campos != null && campos.titulo.trim() !== ''
    // `isoDeCampos` devuelve null si la fecha o la hora quedaron vacías. Antes
    // se construía el Date aquí mismo y reventaba dentro del onClick: la tarea
    // NO se cerraba y nadie se enteraba. Ahora se avisa y no se pierde nada.
    const venceEn = quiereSiguiente && campos ? isoDeCampos(campos) : null
    if (quiereSiguiente && venceEn == null) {
      toast.error('Ponle fecha y hora a la siguiente acción (o salta esta vez)')
      return
    }
    const conSiguiente = quiereSiguiente && venceEn != null
    const reunionSiguiente =
      conSiguiente && campos?.tipo === 'reunion' ? validarReunionOperativa(camposReunionSiguiente) : null
    if (reunionSiguiente && !reunionSiguiente.ok) {
      toast.error(reunionSiguiente.error)
      return
    }
    const res = completarTarea({
      tarea_id: tarea.id,
      estado: eleccion.estado,
      // El PLANTÓN deja rastro: `no_show` mandaba `null` y el timeline se
      // quedaba mudo — el estado de la tarea es dato real, pero la ficha del
      // lead no lo lee. Va como 'nota' a propósito (ver lib/nota-no-show.ts):
      // no sube la etapa ni cuenta como contacto.
      // Una tarea genérica con nota deja rastro igual; sin nota, solo cierra.
      ...rastroDe(eleccion),
      capital: capitalDe(eleccion),
      resultado_reunion: tarea.tipo === 'reunion' ? resultadoReunion : null,
      motivo_no_realizada: tarea.tipo === 'reunion' && eleccion.estado === 'no_show' ? 'cliente_no_asistio' : null,
      siguiente:
        conSiguiente && campos && venceEn
          ? {
              tipo: campos.tipo,
              titulo: campos.titulo.trim(),
              vence_en: venceEn,
              ...camposTareaDeReunion(reunionSiguiente?.ok ? reunionSiguiente : null),
            }
          : null,
    })
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo cerrar la tarea')
      return
    }
    // Las gestiones de cliente esperan el COMMIT real. Además de evitar un
    // éxito falso ante RLS, esto mantiene juntos el cierre, la clasificación,
    // actividades_cliente y la siguiente acción que la RPC escribe de forma
    // atómica. Los leads conservan su interacción optimista histórica.
    setProcesando(true)
    const persistio = await (res.persistido ?? Promise.resolve(true))
    setProcesando(false)
    if (!persistio) return
    // El AVANCE de etapa se anuncia SIEMPRE que ocurra. `completarTarea` ya lo
    // devolvía (el resultado registrado y/o la reunión encadenada pueden mover
    // el lead) y este diálogo —la superficie donde más tareas se cierran— lo
    // tiraba: el stepper de la ficha se movía solo. Mismo formato y mismo orden
    // que `avisoDe` en contacto.tsx: lo que pasó, en el orden en que pasó.
    const partes = ['Tarea cerrada']
    if (res.avance) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
    if (conSiguiente && campos && venceEn) {
      const cuando = tareaAEvento(
        {
          ...tarea,
          id: 'x',
          tipo: campos.tipo,
          titulo: campos.titulo,
          vence_en: venceEn,
          estado: 'pendiente',
        },
        ahora,
      ).cuando
      partes.push(`siguiente agendada: ${cuando}`)
      toast.success(partes.join(' · '))
    } else if (quedaSinPlan && l) {
      // Ver `quedaSinPlan`: el aviso ámbar solo se da cuando es VERDAD.
      toast.warning(`${partes.join(' · ')} — ${primerNombre(l.nombre_completo)} quedó SIN próxima acción`)
    } else {
      toast.success(partes.join(' · '))
    }
    onCerrar()
  }

  // La guarda del botón es EXACTAMENTE la de `confirmar()` (`if (!eleccion)
  // return`). Antes era `opciones.length > 1 && !eleccion`, que en la tarea
  // genérica —una sola opción— daba false aunque `eleccion` fuese null: el
  // botón se pintaba habilitado y no hacía nada. Dos condiciones para lo mismo
  // siempre acaban divergiendo; esta es la única.
  const requiereEleccion = !eleccion

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <CheckCircle2 className="size-4 text-[var(--accent)]" aria-hidden /> Cerrar tarea
        </DialogTitle>
        <DialogDescription className="truncate">{presentarCitas(tarea.titulo)}</DialogDescription>
        {tarea.perfil_id && !l && (
          <Badge color="var(--primary)" className="mt-1 w-fit text-[10px]">
            Gestión de cliente · Mi cartera
          </Badge>
        )}
        {/* Contexto del lead: quién es, en qué etapa va y CUÁNTO está en juego —
            la decisión de proponer/saltar la siguiente no se toma a ciegas.
            (Tareas genéricas sin lead: la franja se omite.) */}
        {l && (
          <div className="mt-1 flex items-center gap-2 rounded-lg bg-muted/40 px-2.5 py-1.5">
            <Avatar nombre={l.nombre_completo} genero={l.genero ?? null} className="size-6 text-[9px]" />
            <span className="min-w-0 flex-1 truncate text-xs font-semibold text-foreground">{l.nombre_completo}</span>
            <Badge color={ETAPA_INFO[l.etapa].color} dot className="shrink-0 text-[10px]">
              {ETAPA_INFO[l.etapa].label}
            </Badge>
            {l.monto_estimado != null && (
              <span className="shrink-0 text-sm font-extrabold tabular-nums text-primary">
                {money(l.monto_estimado, l.moneda)}
              </span>
            )}
          </div>
        )}
      </DialogHeader>
      <DialogBody className="space-y-3.5">
        {/* Resultado 1-tap */}
        <div>
          <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">¿Qué pasó?</p>
          {llamadaTipificada && !anulando && (
            <button
              type="button"
              disabled={procesando}
              onClick={onRegistrarLlamada}
              className="flex w-full cursor-pointer items-center justify-center gap-2 rounded-xl border border-[var(--accent)] bg-[var(--accent)]/10 px-3 py-3 text-sm font-semibold text-foreground transition-colors hover:bg-[var(--accent)]/20 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
            >
              <PhoneCall className="size-4" aria-hidden /> Registrar resultado de la llamada
            </button>
          )}
          {llamadaTipificada && !anulando && (
            <p className="mt-1.5 text-[11px] text-muted-foreground">Siete resultados (contestó, volver a llamar, agendó cita, no le interesa, número errado…): la tarea se cierra al guardar.</p>
          )}
          {!llamadaTipificada && (
          <div className={cn('grid gap-2', opciones.length > 1 ? 'grid-cols-2' : 'grid-cols-1')}>
            {opciones.map((op) => (
              <button
                key={op.k}
                type="button"
                onClick={() => elegir(op)}
                // Con un cierre en vuelo, cambiar de resultado ya no cancela
                // nada (el payload viajó): se bloquea en vez de mentir.
                disabled={procesando}
                aria-pressed={eleccion?.k === op.k}
                className={cn(
                  'flex cursor-pointer items-center justify-center gap-2 rounded-xl border px-3 py-3 text-sm font-semibold transition-colors',
                  eleccion?.k === op.k
                    ? 'border-[var(--accent)] bg-[var(--accent)]/10 text-foreground'
                    : 'border-border/70 text-muted-foreground hover:bg-muted/60',
                )}
              >
                <op.icono className="size-4" aria-hidden /> {op.label}
              </button>
            ))}
          </div>
          )}
          {/* LA CUARTA SALIDA. Deliberadamente FUERA de la grilla y en tono
              menor: no es "qué pasó" (no pasó nada), es "esto ya no aplica".
              Meterla como tercer botón junto a Contestó/No contestó la
              convertiría en el clic fácil para vaciar la agenda. */}
          {!anulando && (
            <button
              type="button"
              ref={refEnlaceAnular}
              disabled={procesando}
              // `min-h-6` (24 px, SC 2.5.8) y 32 en puntero grueso: es un
              // botón SUELTO, no va dentro de una frase, así que no le vale la
              // excepción de objetivo en línea. A 11 px medía unos 16.
              className="mt-2 flex min-h-6 cursor-pointer items-center gap-1.5 py-1 text-[11px] font-semibold text-muted-foreground underline-offset-2 hover:text-foreground hover:underline disabled:cursor-not-allowed disabled:opacity-50 pointer-coarse:min-h-8"
              // NO se toca `eleccion` al entrar: el modo anular la IGNORA (los
              // paneles de abajo se apagan con `!anulando`), y así «Volver»
              // devuelve el diálogo EXACTAMENTE como estaba. Vaciarla costaba
              // dos bugs: en una tarea genérica —única opción, preseleccionada
              // al montar— `requiereEleccion` seguía en false y el botón
              // «Cerrar tarea» quedaba habilitado pero MUDO (`confirmar` sale
              // por `if (!eleccion) return`: ni escribe, ni avisa, ni cierra);
              // y en las demás obligaba a re-elegir, y `elegir` borra
              // `editados` — o sea, la siguiente acción ya escrita a mano.
              onClick={() => {
                setMotivoAnulacion('')
                setDetalleAnulacion('')
                setAnulando(true)
              }}
            >
              <CalendarX2 className="size-3.5" aria-hidden />
              Ya no hace falta — anular esta tarea
            </button>
          )}
        </div>

        {!anulando && tarea.tipo === 'reunion' && eleccion?.estado === 'completada' && (
          <div>
            <label
              className="mb-1.5 block text-[11px] font-bold uppercase tracking-wide text-muted-foreground"
              htmlFor="resultado-reunion"
            >
              Resultado comercial
            </label>
            <Select
              id="resultado-reunion"
              value={resultadoReunion ?? ''}
              onChange={(evento) =>
                setResultadoReunion((evento.target.value || null) as ResultadoReunionOperativo | null)
              }
            >
              <option value="">Selecciona un resultado</option>
              {RESULTADOS_REUNION.map((opcion) => (
                <option key={opcion.k} value={opcion.k}>
                  {opcion.label}
                </option>
              ))}
            </Select>
          </div>
        )}

        {/* CAPITAL DE LA ENTREVISTA — el otro dato del mismo acto.
            Pedido de Miguel (2026-09-18): que marcar «Se realizó» convierta la
            cita en entrevista solo. Y una entrevista sin capital no sirve: de esa
            cifra viven el capital en proceso y las metas del mes, y el estimado
            del primer contacto es una corazonada. Antes se preguntaba DESPUÉS,
            en un segundo diálogo del kanban al que había que llegar arrastrando
            la tarjeta; ahora se pregunta aquí, donde el analista acaba de
            hablar con la persona y la cifra está fresca. */}
        {!anulando && pideCapital && (
          <div>
            <label
              className="mb-1.5 block text-[11px] font-bold uppercase tracking-wide text-muted-foreground"
              htmlFor="capital-entrevista"
            >
              Capital propuesto
            </label>
            <div className="grid grid-cols-[1fr_96px] gap-2">
              <Input
                id="capital-entrevista"
                type="number"
                inputMode="decimal"
                min="0"
                step="0.01"
                value={capitalMonto}
                onChange={(evento) => setCapitalMonto(evento.target.value)}
              />
              {/* La moneda viaja PEGADA al monto: PEN y USD jamás se suman, así
                  que un número sin su moneda no significa nada. */}
              <Select
                aria-label="Moneda del capital propuesto"
                value={capitalMoneda}
                onChange={(evento) => setCapitalMoneda(evento.target.value === 'USD' ? 'USD' : 'PEN')}
              >
                <option value="PEN">PEN</option>
                <option value="USD">USD</option>
              </Select>
            </div>
            <p className="mt-1 text-[11px] text-muted-foreground">
              Al guardar, la cita cuenta como entrevista y
              {l ? ` ${primerNombre(l.nombre_completo)}` : ' el lead'} pasa a «
              {ETAPA_INFO.propuesta_enviada.label}».
            </p>
          </div>
        )}

        {/* Confirmación de anulado: dice EXACTAMENTE qué hace y qué no hace.
            Un cierre es irreversible en el servidor (`trg_tareas_before_update`
            rechaza tocar una tarea ya cerrada), así que no puede ir a un tap. */}
        {anulando && (
          // `tabIndex={-1}` = destino de foco PROGRAMÁTICO, no una parada del
          // tabulador: enfocar el contenedor hace que el lector lea el aviso
          // entero antes de que el usuario llegue a «Sí, anular».
          <div
            ref={refPanelAnular}
            tabIndex={-1}
            // `role="group"` + `aria-labelledby` en vez de confiar en que el
            // lector lea solo el subárbol de un div enfocado: eso NO lo define
            // la spec y cada lector hace una cosa (NVDA suele leerlo entero,
            // JAWS a menudo se queda en la primera línea). Con el grupo
            // nombrado la lectura es determinista. `role="alert"` —el
            // precedente del drawer— daría DOBLE lectura al combinarse con el
            // foco programático de aquí arriba.
            role="group"
            aria-labelledby="anular-titulo"
            className="rounded-xl border border-[#d97706]/40 bg-[#d97706]/10 p-2.5 outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          >
            <p id="anular-titulo" className="text-[11px] font-bold text-warning-text">
              Anular esta tarea
            </p>
            {/* `--warning-text` (#92400e) y no el ámbar de siempre: a 11 px el
                `#b45309/90` de los otros avisos da 3.84:1 y AA exige 4.5:1 — y
                este párrafo es justo el que dice que no se puede deshacer. */}
            <p id="anular-que-hace" className="mt-0.5 text-[11px] text-warning-text">
              {tarea.tipo === 'reunion' ? (
                <>
                  La cita quedará cancelada con su motivo y autor para el reporte de Gerencia. No se puede deshacer.
                </>
              ) : (
                <>
                  Sale de tu agenda. <strong>No</strong> cuenta como gestión y <strong>no</strong> escribe nada en el
                  historial
                  {l ? ` de ${primerNombre(l.nombre_completo)}` : ''} — úsala cuando la tarea dejó de tener sentido. No
                  se puede deshacer.
                </>
              )}
            </p>
            {/* El retroceso de etapa va PRIMERO y en negrita: es la única
                consecuencia de anular que toca el embudo, y la que el analista no
                pidió. Anunciarla antes del tap es el mismo trato que el resto
                del CRM le da a los avances automáticos (ahí se cantan DESPUÉS
                porque suben; este baja, así que se avisa ANTES). */}
            {!historialListo && l && (
              <p id="anular-historial" role="status" className="mt-1.5 text-[11px] font-semibold text-warning-text">
                {historial.cargando
                  ? 'Comprobando el historial del lead…'
                  : 'No se pudo leer el historial: al anular, la etapa podría bajar.'}
              </p>
            )}
            {retrocesoPrevisto && l && (
              <p id="anular-retroceso" className="mt-1.5 text-[11px] font-semibold text-warning-text">
                Era su única cita: {primerNombre(l.nombre_completo)} vuelve a la etapa «
                {ETAPA_INFO[retrocesoPrevisto].label}». Si la vas a mover de fecha, usa <strong>Reprogramar</strong> en
                vez de anular.
              </p>
            )}
            {quedaSinPlan && l && (
              <p id="anular-sin-plan" className="mt-1.5 text-[11px] font-semibold text-warning-text">
                Ojo: es su única pendiente. {primerNombre(l.nombre_completo)} quedará sin próxima acción.
              </p>
            )}
            {tarea.tipo === 'reunion' && (
              <div className="mt-3 grid gap-2">
                <Select
                  aria-label="Motivo de cancelación de la cita"
                  value={motivoAnulacion}
                  onChange={(evento) => setMotivoAnulacion(evento.target.value as typeof motivoAnulacion)}
                >
                  <option value="">Selecciona el motivo</option>
                  {MOTIVOS_NO_REALIZADA.map((opcion) => (
                    <option key={opcion.k} value={opcion.k}>
                      {opcion.label}
                    </option>
                  ))}
                </Select>
                <Textarea
                  aria-label="Detalle de cancelación de la cita"
                  placeholder={
                    motivoAnulacion === 'otro' ? 'Describe el motivo (obligatorio)' : 'Detalle adicional (opcional)'
                  }
                  rows={2}
                  value={detalleAnulacion}
                  onChange={(evento) => setDetalleAnulacion(evento.target.value)}
                />
              </div>
            )}
          </div>
        )}

        {/* La nota se esconde al anular, y no es cosmético: anular NO escribe
            actividad, así que dejar visible un campo que promete "va al
            timeline del lead" sería tragarse en silencio lo que el analista
            escribió. Si tiene algo que contar, cierra la tarea con resultado. */}
        {!anulando && !llamadaTipificada && (
          <Textarea
            aria-label="Nota del resultado (opcional)"
            placeholder={
              tarea.perfil_id
                ? 'Nota corta (opcional) — va al historial del cliente'
                : 'Nota corta (opcional) — va al timeline del lead'
            }
            rows={2}
            value={detalle}
            onChange={(e) => setDetalle(e.target.value)}
          />
        )}

        {/* SALIDA DE LA CADENCIA. Aparece por encima de la siguiente acción
            porque la sustituye: seguir proponiendo toques a quien no contesta
            desde hace días es lo que llena el embudo de zombis. */}
        {!anulando && eleccion && planton && l && (
          <div className="rounded-xl border border-[#d97706]/40 bg-[#d97706]/10 p-2.5">
            {/* `--warning-text` también aquí: el `#b45309/90` de abajo daba
                3.84:1 con AA exigiendo 4.5, y el opaco pasaba por 0.02. Se
                salda la deuda que este mismo archivo documentaba 40 líneas más
                abajo en vez de dejarla escrita al lado de su propio parche. */}
            <p className="text-[11px] font-bold text-warning-text">{primerNombre(l.nombre_completo)} no responde</p>
            <p className="mt-0.5 text-[11px] text-warning-text">
              {planton.intentos} intentos en {Math.floor(planton.dias)} días sin una sola respuesta. Seguir insistiendo
              le cuesta un toque cada dos días.
            </p>
            <label className="mt-2 flex cursor-pointer items-start gap-2 text-[11px] font-semibold text-foreground/85">
              <input
                type="checkbox"
                className="mt-0.5 size-3.5 shrink-0 cursor-pointer accent-[#b45309]"
                checked={cerrarLead}
                onChange={(e) => setCerrarLead(e.target.checked)}
              />
              <span>Cerrar el lead por «No responde» al confirmar</span>
            </label>
          </div>
        )}

        {/* La SIGUIENTE — la regla de oro, con saltar a un toque */}
        {!anulando && eleccion && campos && !saltar && !(planton && cerrarLead) && (
          <div className="rounded-xl border border-[var(--accent)]/40 bg-[var(--accent)]/5 p-2.5">
            <div className="mb-2 flex items-center justify-between">
              <p className="text-[11px] font-bold uppercase tracking-wide text-foreground/80">
                Siguiente acción propuesta
              </p>
              <button
                type="button"
                className="cursor-pointer text-[11px] font-semibold text-muted-foreground underline-offset-2 hover:underline"
                onClick={() => setSaltar(true)}
              >
                Saltar esta vez
              </button>
            </div>
            {/* Fila fecha/hora invertida: la fecha ("dd/mm/aaaa" + picker) toma
                la columna flexible y la hora ("10:00") la fija de 96px — el
                ancho sigue al valor de lectura de cada campo. */}
            <div className="space-y-2">
              <div className="grid grid-cols-[110px_1fr] gap-2">
                <Select
                  aria-label="Tipo de la siguiente"
                  value={campos.tipo}
                  onChange={(e) => {
                    if (esTipoTarea(e.target.value)) editar({ tipo: e.target.value })
                  }}
                >
                  {TIPOS_TAREA.map((t) => (
                    <option key={t.k} value={t.k}>
                      {t.label}
                    </option>
                  ))}
                </Select>
                <Input
                  aria-label="Título de la siguiente"
                  value={campos.titulo}
                  maxLength={200}
                  onChange={(e) => editar({ titulo: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-[1fr_96px] gap-2">
                <Input
                  aria-label="Fecha de la siguiente"
                  type="date"
                  value={campos.fecha}
                  onChange={(e) => editar({ fecha: e.target.value })}
                />
                <Input
                  aria-label="Hora de la siguiente"
                  type="time"
                  value={campos.hora}
                  onChange={(e) => editar({ hora: e.target.value })}
                />
              </div>
              {campos.tipo === 'reunion' && (
                <CamposReunion valor={camposReunionSiguiente} onChange={setCamposReunionSiguiente} />
              )}
            </div>
          </div>
        )}
        {!anulando && eleccion && saltar && (
          <div className="flex items-center justify-between rounded-xl border border-[#d97706]/40 bg-[#d97706]/10 px-3 py-2">
            <p className="text-[11px] font-semibold text-warning-text">
              {tarea.perfil_id
                ? 'Sin siguiente — el cliente quedará sin otra gestión agendada.'
                : 'Sin siguiente — el lead quedará en “sin próxima acción”.'}
            </p>
            <button
              type="button"
              className="cursor-pointer text-[11px] font-semibold text-foreground underline-offset-2 hover:underline"
              onClick={() => setSaltar(false)}
            >
              Deshacer
            </button>
          </div>
        )}
      </DialogBody>
      {/* ⚠️ LAS `key` NO SON DECORATIVAS. Las dos ramas tienen un <Button> en
          cada posición, así que React reconcilia POR ÍNDICE y reutiliza el
          MISMO nodo del DOM: al pulsar «Volver» el foco no se movía y el botón
          que quedaba debajo del dedo pasaba a llamarse «Cancelar» y a ejecutar
          `onCerrar()`. Un segundo Enter —el de quien no oyó nada y cree que no
          respondió— cerraba el diálogo y se llevaba la nota y la siguiente
          acción ya escritas. Con `key` distintas el nodo se desmonta de verdad
          y el nombre accesible nunca cambia bajo el foco (WCAG 4.1.2). */}
      <DialogFooter className="justify-between">
        {anulando ? (
          <>
            <Button
              key="volver"
              variant="ghost"
              size="sm"
              disabled={procesando}
              onClick={() => {
                setAnulando(false)
                // Devolver el foco al enlace de donde salió: si no, Radix lo
                // rescata al tope del diálogo y hay que re-tabularlo entero.
                requestAnimationFrame(() => refEnlaceAnular.current?.focus())
              }}
            >
              Volver
            </Button>
            {/* La consecuencia viaja CON el foco: quien salte directo al
                destructivo tiene que oírla igual. Mismo trato que su gemelo de
                la ficha (lead-drawer.tsx), que ya lo hacía. */}
            <Button
              key="si-anular"
              variant="destructive"
              size="sm"
              aria-describedby={[
                'anular-que-hace',
                !historialListo && l ? 'anular-historial' : null,
                retrocesoPrevisto && l ? 'anular-retroceso' : null,
                quedaSinPlan && l ? 'anular-sin-plan' : null,
              ]
                .filter((x): x is string => x !== null)
                .join(' ')}
              onClick={() => void anular()}
              disabled={procesando || (tarea.tipo === 'reunion' && !motivoAnulacion)}
            >
              <CalendarX2 aria-hidden /> {procesando ? 'Guardando…' : 'Sí, anular'}
            </Button>
          </>
        ) : (
          <>
            <Button key="cancelar" variant="ghost" size="sm" disabled={procesando} onClick={onCerrar}>
              Cancelar
            </Button>
            {!llamadaTipificada && (
              <Button
                key="cerrar"
                size="sm"
                onClick={() => void confirmar()}
                disabled={requiereEleccion || procesando}
              >
                <CheckCircle2 /> {procesando ? 'Guardando…' : 'Cerrar tarea'}
              </Button>
            )}
          </>
        )}
      </DialogFooter>
    </>
  )
}
