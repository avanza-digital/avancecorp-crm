// Acciones de contacto — Sprint A (F1d), ajustado 2026-07-17. Un solo
// componente para las 3 superficies: header del lead-drawer (completo) y colas
// de hoy/vendedor y hoy/supervisor (compacto).
//   · Llamar: DEPENDE DEL APARATO. En el CELULAR es un enlace `tel:` que abre
//     el marcador, y el resultado se pregunta AL VOLVER — mismo mecanismo que
//     wa.me. En la LAPTOP no hay radio (un `tel:` ahí no marca nada), así que
//     se conserva COPIAR el número al portapapeles y abrir el diálogo de una:
//     en las colas no existe el composer del timeline, este es el único
//     registro de la llamada. La detección es por INTERACCIÓN (`usePuedeMarcar`:
//     hover:none + pointer:coarse), NUNCA por user-agent ni por ancho a secas.
//   · WhatsApp (wa.me) abre WhatsApp Web en otra pestaña; al volver ≥4 s después
//     un dialog pregunta el resultado y lo registra vía registrarActividad.
// Directorio (solo lectura) copia/abre pero NO registra (sin seguimiento).
// El contenedor corta la propagación: viven dentro de filas clicables (colas)
// y no deben abrir la ficha al contactar.
// F1.1.2 (30/09/2026, plan «Llamadas desde el celular»): la INTENCIÓN de
// contacto («me fui a llamar y volví») ya no es un ref de cada instancia sino la
// cola compartida de lib/intencion-contacto: sobrevive al remount y a la recarga
// de la PWA, y puede llegar de FUERA (el enlace que arma el celular al colgar).
import { useCallback, useEffect, useRef, useState, type JSX } from 'react'
import { toast } from 'sonner'
import {
  CalendarPlus,
  Mail,
  MessageCircle,
  MessageSquare,
  Phone,
  PhoneCall,
  PhoneMissed,
  type LucideIcon,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import {
  CAMPOS_REUNION_VACIOS,
  CamposReunion,
  camposTareaDeReunion,
  type EstadoCamposReunion,
} from '@/components/app/campos-reunion'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
import { useAuth } from '@/lib/auth-context'
import { puedeEscribir } from '@/lib/roles'
import { useCRMData } from '@/lib/store-context'
import type { CompletarTareaInput } from '@/lib/store'
import { useAhora } from '@/lib/ahora'
import { usePuedeMarcar } from '@/lib/media'
import { enlaceTel, numeroWhatsapp } from '@/lib/telefono'
import { sugerirSiguiente, type SugerenciaSiguiente } from '@/lib/motor-siguiente'
import { proximoSlotSugerido, tareaAEvento } from '@/lib/agenda-derivada'
import { TIPO_TAREA_DE_CANAL, tareaQueCierra, type Canal } from '@/lib/contacto-tarea'
import {
  armarIntencion,
  cerrarIntencion,
  estaLista,
  intencionDe,
  reclamarIntencion,
  useIntencionContacto,
} from '@/lib/intencion-contacto'
import { esPlanVivo } from '@/lib/plan-lead'
import { primerNombre } from '@/lib/format'
import { presentarCitas } from '@/lib/terminologia'
import {
  ETAPA_INFO,
  type EtapaActiva,
  type Tarea,
  type TipoActividadManual,
  type LeadContactable,
} from '@/lib/tipos'

// ── Constantes ────────────────────────────────────────────────────────────────

/** Link de acción rápida — mismo estilo que usaban drawer y colas. */
const CLASE_ACCION =
  'inline-flex h-7 items-center gap-1.5 rounded-lg border border-input bg-card px-2.5 text-[11px] font-semibold text-foreground transition-colors hover:bg-muted hover:border-border-strong [&_svg]:size-3.5'

// ── Componente (export) ───────────────────────────────────────────────────────

export function AccionesContacto({
  lead,
  compacto,
  soloIcono,
  conAgendar,
  destacada,
  grande,
  onGuardado,
  onRegistrarLlamada,
  onLlamar,
}: {
  lead: LeadContactable
  compacto?: boolean
  /** Oculta las etiquetas SIEMPRE (columnas angostas, p. ej. la cola en 2/5). */
  soloIcono?: boolean
  /**
   * Añade "Agendar": crea el siguiente toque por defecto SIN abrir la ficha.
   * Vive aquí y no en la fila a propósito — este contenedor ya tiene el escudo
   * de propagación, y un `<button>` pelado dentro de la fila haría que Enter
   * abriera la ficha en vez de agendar.
   */
  conAgendar?: boolean
  /** Targets táctiles de 44 px para la franja primaria «Ahora» (Ley de Fitts). */
  destacada?: boolean
  /**
   * 48 px y 18 px para «Mi día», donde «Llamar» es la ÚNICA acción primaria de
   * la pantalla y el piso tipográfico es 16 px (queja de los analistas del
   * 20/09/2026). Se apoya en `destacada`, que ya tiñe el primer hijo de azul.
   */
  grande?: boolean
  /**
   * Aviso de que la LLAMADA quedó registrada. Lo usa «Mi día» para pasar al
   * siguiente lead de la cola desde la acción primaria, igual que ya hacía al
   * registrar desde el panel: sin esto, el camino principal —Llamar— dejaba la
   * cola parada en el lead recién atendido (hallazgo de Codex, 20/09/2026).
   */
  onGuardado?: (() => void) | undefined
  /** «Mi día» resuelve su tarea de servidor y usa el mismo panel desde ambos accesos. */
  onRegistrarLlamada?: (() => void) | undefined
  /**
   * Aviso SÍNCRONO de que se pulsó «Llamar», antes de copiar o de salir al
   * marcador (27/09/2026): «Mi día» fija ahí a la persona, para que un refresco
   * mientras el analista está en la llamada no cambie la tarjeta ni pierda la
   * pregunta del resultado al volver. Síncrono a propósito: en iOS un `await`
   * antes de navegar a `tel:` corta la activación y el marcador no abre.
   */
  onLlamar?: (() => void) | undefined
}): JSX.Element {
  const { yo } = useAuth()
  const escribe = puedeEscribir(yo?.rol)
  // Escritorio y celular NO comparten camino de "Llamar" — ver la cabecera.
  const puedeMarcar = usePuedeMarcar()
  const [dialogo, setDialogo] = useState<Canal | null>(null)
  // La intención de ESTE lead en la cola compartida. `instancia` identifica a
  // quien la armó (responde primero al volver); `montadoEn` distingue lo que ya
  // estaba armado al nacer esta instancia (recarga, remount) de su propio tap;
  // `tomada` es la que esta instancia tiene abierta: se cierra al terminar o al irse.
  const actor = yo?.id ?? null
  const instancia = useRef(`ac-${Math.random().toString(36).slice(2, 10)}`)
  const montadoEn = useRef(Date.now())
  const tomada = useRef<string | null>(null)
  const intencion = useIntencionContacto(actor, lead.id)
  const vigente = useRef(true)
  useEffect(() => {
    vigente.current = true
    return () => {
      vigente.current = false
      // Con el diálogo abierto y la instancia yéndose, la pregunta se va con ella (como siempre).
      if (tomada.current) { cerrarIntencion(tomada.current); tomada.current = null }
    }
  }, [])
  // Fase 4e «sin topes»: antes de registrar un contacto el store tiene que
  // conocer el lead (sin foto inicial se relee por id bajo su RLS).
  const { asegurarLead } = useCRMData()
  // `id` es la intención reclamada (null en el camino del escritorio, que no sale
  // de la pestaña). Una salida sin formulario termina con ella (lead fuera del
  // ámbito, sin red: la pregunta se pierde, como siempre). Con formulario, sigue
  // ABIERTA hasta que se cierre —el diálogo propio aquí; la tarjeta de «Mi día»
  // con `cerrarIntencionesDe` al cerrar su sesión—: mientras, la siguiente
  // llamada espera en la cola en vez de abrirse encima (visto el 30/09).
  const abrirRegistro = useCallback((canal: Canal, id: string | null) => {
    const terminar = () => { if (id) cerrarIntencion(id) }
    void asegurarLead(lead.id).then((ok) => {
      if (!vigente.current) { terminar(); return }
      if (!ok) { toast.error('Este lead ya no está disponible en tu ámbito.'); terminar(); return }
      tomada.current = id
      if (canal === 'tel' && onRegistrarLlamada) onRegistrarLlamada()
      else setDialogo(canal)
    }).catch(() => { toast.error('No se pudo comprobar el lead. Revisa tu conexión y vuelve a intentarlo.'); terminar() })
  }, [asegurarLead, lead.id, onRegistrarLlamada])

  useEffect(() => {
    if (!escribe) return
    const tomar = (id: string) => {
      const i = intencionDe(actor, lead.id)
      if (!i || i.id !== id || i.abierta) return // ya la tomó otra instancia, o cambió
      // Volvió casi al instante (< 4 s): no llegó a llamar/escribir — no
      // preguntamos, y la intención se descarta (un solo disparo por contacto).
      if (!estaLista(i)) { cerrarIntencion(i.id); return }
      if (reclamarIntencion(i.id)) abrirRegistro(i.canal, i.id)
    }
    const alVolver = () => {
      if (document.visibilityState !== 'visible') return
      const i = intencionDe(actor, lead.id)
      if (!i || i.abierta) return
      // La instancia que armó la intención responde primero (focus y
      // visibilitychange llegan juntos: `reclamar` garantiza un solo disparo).
      // Otra instancia del mismo lead solo actúa si aquella ya no está.
      if (i.instancia === instancia.current) tomar(i.id)
      else setTimeout(() => { if (vigente.current) tomar(i.id) }, 0)
    }
    window.addEventListener('focus', alVolver)
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      window.removeEventListener('focus', alVolver)
      document.removeEventListener('visibilitychange', alVolver)
    }
  }, [escribe, actor, lead.id, abrirRegistro])

  // Intención que llegó de FUERA (el enlace del celular) o que ya estaba armada
  // antes de que esta instancia existiera (recarga, remount): se ofrece al
  // montar, si ya está lista. La que armó esta misma instancia con su tap solo
  // se ofrece al volver a la pestaña, como siempre — nunca por reloj.
  useEffect(() => {
    if (!escribe || !intencion || intencion.abierta) return
    if (intencion.origen !== 'enlace' && intencion.ts >= montadoEn.current) return
    if (!estaLista(intencion)) return
    if (reclamarIntencion(intencion.id)) abrirRegistro(intencion.canal, intencion.id)
  }, [escribe, intencion, abrirRegistro])

  const marcar = (canal: Canal) => () => {
    if (escribe && actor) armarIntencion({ actor, leadId: lead.id, canal, origen: 'pantalla', instancia: instancia.current })
  }
  const cerrarDialogo = () => {
    if (tomada.current) { cerrarIntencion(tomada.current); tomada.current = null }
    setDialogo(null)
  }

  // Llamar desde la laptop no marca: el analista usa su celular corporativo.
  // Copiamos el número (para que lo marque) y abrimos directo el registro del
  // resultado. Directorio no registra (solo copia).
  const llamar = async () => {
    const num = lead.telefono
    try {
      await navigator.clipboard.writeText(num)
      toast.success(`Número copiado: ${num} — márcalo desde tu celular`)
    } catch {
      // Portapapeles no disponible (contexto inseguro o permiso denegado).
      toast.info(`Marca ${num} desde tu celular`)
    }
    if (escribe) abrirRegistro('tel', null)
  }

  const wa = numeroWhatsapp(lead.telefono)
  const tel = enlaceTel(lead.telefono)
  const labelCls = soloIcono ? 'hidden' : compacto ? 'hidden md:inline' : undefined

  return (
    <div
      className={cn(
        'flex items-center gap-1.5',
        compacto ? 'shrink-0' : 'flex-wrap',
        destacada && [
          '[&_a]:!h-11 [&_a]:!px-3 [&_button]:!h-11 [&_button]:!px-3 sm:[&_a]:!h-9 sm:[&_button]:!h-9',
          '[&>*:first-child]:!border-accent [&>*:first-child]:!bg-accent [&>*:first-child]:!text-white',
        ],
        grande && [
          'gap-3 [&_a]:!h-12 [&_a]:!px-5 [&_a]:!text-lg [&_button]:!h-12 [&_button]:!px-5 [&_button]:!text-lg',
          'sm:[&_a]:!h-12 sm:[&_button]:!h-12 [&_svg]:!size-5',
        ],
      )}
      // Escudo de propagación: ni el click en los links ni las teclas dentro del
      // dialog (portal — burbujea por el árbol de React) deben abrir la fila.
      // Escape SÍ pasa: el Dialog lo escucha a nivel de document para cerrarse.
      // role=presentation: NO es un control — solo intercepta burbujeo (los
      // interactivos reales son los <a>/<button> internos).
      role="presentation"
      onClick={(e) => e.stopPropagation()}
      onKeyDown={(e) => {
        if (e.key !== 'Escape') e.stopPropagation()
      }}
    >
      {puedeMarcar && tel ? (
        // CELULAR. Enlace `tel:` y no un handler con location.href, a propósito:
        //  · Cero trabajo asíncrono antes de navegar. Si aquí se copiara además
        //    al portapapeles, el `await` cortaría la activación de usuario en
        //    iOS Safari y el marcador NO abriría.
        //  · SIN `target="_blank"`: el diálogo de resultado depende de que ESTA
        //    pestaña se oculte y vuelva (`alVolver`). Con _blank la actual nunca
        //    se oculta → el resultado no se pregunta nunca, y en Android queda
        //    una pestaña en blanco. Por eso NO se copia aquí el patrón de wa.me.
        // Directorio (sin permiso de escritura) marca igual, pero `marcar` no
        // arma nada → no se le pregunta el resultado ni escribe actividad.
        <a
          href={tel}
          className={CLASE_ACCION}
          aria-label={`Llamar a ${lead.nombre_completo}`}
          onClick={() => { marcar('tel')(); onLlamar?.() }}
        >
          <Phone /> <span className={labelCls}>Llamar</span>
        </a>
      ) : (
        <button
          type="button"
          className={CLASE_ACCION}
          aria-label={`Copiar el número de ${lead.nombre_completo} y registrar la llamada`}
          onClick={() => { onLlamar?.(); void llamar() }}
        >
          <Phone /> <span className={labelCls}>Llamar</span>
        </button>
      )}
      {wa && (
        <a
          href={`https://wa.me/${wa}`}
          target="_blank"
          rel="noreferrer"
          className={CLASE_ACCION}
          aria-label={`WhatsApp a ${lead.nombre_completo}`}
          onClick={marcar('wa')}
        >
          <MessageCircle /> <span className={labelCls}>WhatsApp</span>
        </a>
      )}
      {!compacto && lead.correo && (
        <a href={`mailto:${lead.correo}`} className={CLASE_ACCION} aria-label={`Correo a ${lead.nombre_completo}`}>
          <Mail /> Correo
        </a>
      )}
      {conAgendar && escribe && <BotonAgendar lead={lead} labelCls={labelCls} />}
      {/* Gestión Diaria F2: TODA llamada se cierra con el resultado tipificado
          (panel del mockup 5). WhatsApp conserva su diálogo de dos opciones. */}
      {dialogo === 'tel' && <DialogResultadoLlamada lead={lead} onClose={cerrarDialogo} onGuardado={onGuardado} />}
      {dialogo === 'wa' && <DialogResultado lead={lead} canal={dialogo} onClose={cerrarDialogo} />}
    </div>
  )
}

// ── Agendar el siguiente toque sin abrir la ficha ─────────────────────────────

/**
 * Un tap crea la tarea por defecto —llamada, "Llamar a <nombre>", próximo slot
 * hábil— para el lead de la fila. Hasta hoy había que abrir la ficha, bajar
 * hasta la agenda y llenar un formulario para dejar programado el paso obvio.
 *
 * Se agenda de una y se AVISA cuándo quedó; si el analista quería otra cosa,
 * cambia la fecha desde la ficha. Pedirle el formulario por adelantado para el
 * 90% de los casos idénticos es justo la fricción que esto quita.
 */
function BotonAgendar({ lead, labelCls }: { lead: LeadContactable; labelCls: string | undefined }): JSX.Element | null {
  const { crearTarea, tareasDe, asegurarLead } = useCRMData()
  const ahora = useAhora()
  // ANTI-DOBLE-CLIC: entre el clic y la tarea media un `await` de red
  // (asegurarLead) y el botón recién se oculta al re-render; dos clics rápidos
  // creaban dos tareas, porque cada una lleva su propio id. El ref corta el
  // segundo clic en el acto; el estado solo pinta el botón deshabilitado.
  const enCurso = useRef(false)
  const [enviando, setEnviando] = useState(false)
  // ANTI-DUPLICADO: si ya tiene plan VIVO no se le encima otro. Ojo con la
  // palabra: una tarea VENCIDA no es un plan (lib/plan-lead.ts). Mirar
  // `tareasDe().length` a secas escondía este botón justo en los leads que la
  // cola acababa de destapar por tener una tarea muerta.
  if (tareasDe(lead.id).some((t) => esPlanVivo(t, ahora))) return null

  const agendar = async () => {
    if (enCurso.current) return
    enCurso.current = true
    setEnviando(true)
    try {
      let conocido = false
      try {
        conocido = await asegurarLead(lead.id)
      } catch {
        toast.error('No se pudo comprobar el lead. Revisa tu conexión y vuelve a intentarlo.')
        return
      }
      if (!conocido) {
        toast.error('Este lead ya no está disponible en tu ámbito.')
        return
      }
      const vence = proximoSlotSugerido(ahora)
      const res = crearTarea({
        lead_id: lead.id,
        tipo: 'llamada',
        titulo: `Llamar a ${primerNombre(lead.nombre_completo)}`,
        vence_en: vence,
      })
      if (!res.ok) {
        toast.error(res.error ?? 'No se pudo agendar')
        return
      }
      const cuando = tareaAEvento(
        { ...PLANTILLA_TAREA, tipo: 'llamada', titulo: 'x', vence_en: vence },
        ahora,
      ).cuando
      toast.success(`Agendado: llamar a ${primerNombre(lead.nombre_completo)} — ${cuando}`)
    } finally {
      enCurso.current = false
      setEnviando(false)
    }
  }

  return (
    <button
      type="button"
      className={cn(CLASE_ACCION, 'disabled:opacity-60')}
      aria-label={`Agendar el siguiente paso con ${lead.nombre_completo}`}
      disabled={enviando}
      aria-busy={enviando || undefined}
      onClick={() => void agendar()}
    >
      <CalendarPlus /> <span className={labelCls}>Agendar</span>
    </button>
  )
}

// ── Dialog de resultado de la LLAMADA (resultado tipificado, F2) ──────────────
// `tareaQueCierra` sigue decidiendo qué tarea de llamada pendiente cierra este
// contacto; el panel la ofrece con su casilla, como antes.
function DialogResultadoLlamada({ lead, onClose, onGuardado }: {
  lead: LeadContactable
  onClose: () => void
  onGuardado?: (() => void) | undefined
}): JSX.Element {
  const { tareasDe } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  const [tarea] = useState(() => tareaQueCierra(tareasDe(lead.id), 'tel', yo?.id, ahora))
  return <RegistrarResultado lead={lead} tarea={tarea} onClose={onClose} onGuardado={onGuardado} />
}

// ── Dialog de resultado del contacto (WhatsApp) ───────────────────────────────

const OPCIONES: Record<Canal, ReadonlyArray<{ tipo: TipoActividadManual; label: string; icono: LucideIcon }>> = {
  tel: [
    { tipo: 'llamada_realizada', label: 'Sí, contestó', icono: PhoneCall },
    { tipo: 'llamada_no_contestada', label: 'No contestó', icono: PhoneMissed },
  ],
  wa: [
    { tipo: 'whatsapp_enviado', label: 'Mensaje enviado', icono: MessageCircle },
    { tipo: 'whatsapp_recibido', label: 'Ya respondió', icono: MessageSquare },
  ],
}

/**
 * Aviso HONESTO de lo que acaba de pasar. Un tap puede desencadenar tres cosas
 * (registrar, mover la etapa, cerrar la tarea y agendar la siguiente); si el
 * toast solo dice "Contacto registrado", el analista descubre el resto por
 * accidente y deja de confiar en el sistema. Se enumera lo que ocurrió DE
 * VERDAD, en el orden en que ocurrió.
 */
function avisoDe({
  demo,
  avance,
  cerroTarea,
  sugerida,
  ahora,
}: {
  demo?: boolean | undefined
  avance?: EtapaActiva | undefined
  cerroTarea?: Tarea | undefined
  sugerida: SugerenciaSiguiente | null
  ahora: number
}): string {
  const partes = ['Contacto registrado']
  if (cerroTarea) partes.push('tarea cerrada')
  if (avance) partes.push(`pasó a ${ETAPA_INFO[avance].label}`)
  if (sugerida) {
    const cuando = tareaAEvento(
      { ...PLANTILLA_TAREA, tipo: sugerida.tipo, titulo: sugerida.titulo, vence_en: sugerida.vence_en },
      ahora,
    ).cuando
    partes.push(`siguiente ${cuando}`)
  }
  return `${partes.join(' · ')}${demo ? ' (demo)' : ''}`
}

/** Esqueleto mínimo para pedirle a `tareaAEvento` la etiqueta "cuándo" de una
 *  tarea que todavía no existe (la sugerencia del motor). */
const PLANTILLA_TAREA: Tarea = {
  id: 'sugerencia',
  lead_id: null,
  tipo: 'llamada',
  titulo: '',
  vence_en: new Date(0).toISOString(),
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: new Date(0).toISOString(),
}

type EnvioContacto = {
  leadId: string
  tipo: TipoActividadManual
  detalle: string | undefined
  siguiente: Exclude<CompletarTareaInput['siguiente'], undefined>
  tarea: Tarea | null
  sugerida: SugerenciaSiguiente | null
}

function DialogResultado({
  lead,
  canal,
  onClose,
}: {
  lead: LeadContactable
  canal: Canal
  onClose: () => void
}): JSX.Element {
  const { registrarActividad, tareasDe, completarTarea } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  const [nota, setNota] = useState('')
  const [procesando, setProcesando] = useState(false)
  const [sinConfirmar, setSinConfirmar] = useState<EnvioContacto | null>(null)
  const enviando = useRef(false)
  const ahoraDelFormulario = useRef(ahora).current
  const [cierraTarea, setCierraTarea] = useState(true)
  const [agendaSiguiente, setAgendaSiguiente] = useState(true)
  const [camposReunion, setCamposReunion] =
    useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)

  const pendientes = tareasDe(lead.id)
  const conPlanVivo = pendientes.filter((t) => esPlanVivo(t, ahora))
  const [tarea] = useState(() => tareaQueCierra(pendientes, canal, yo?.id, ahora))
  // Solo el DUEÑO encadena la siguiente: nadie debe llenarle la agenda a otro.
  const soyDueno = lead.vendedor_id != null && lead.vendedor_id === yo?.id
  // ANTI-DUPLICADO: si el lead ya tiene un plan vivo que este contacto no
  // cierra, no se le agenda otro encima — ese lead ya tiene dueño de su
  // siguiente paso (misma regla que la cola con `tienePlan`).
  // Si el analista DESTILDA el cierre de la tarea, esa tarea sigue viva → no se
  // le puede encimar un segundo plan. La condición depende del checkbox, no
  // solo de que exista una candidata.
  const cerrara = tarea != null && cierraTarea
  const puedeAgendar = soyDueno && (cerrara || conPlanVivo.length === 0)

  const enviar = async (envio: EnvioContacto) => {
    if (enviando.current) return
    enviando.current = true
    setProcesando(true)
    try {
      const res = envio.tarea
        ? completarTarea({ tarea_id: envio.tarea.id, estado: 'completada', resultado_tipo: envio.tipo,
          resultado_detalle: envio.detalle ?? null, siguiente: envio.siguiente })
        : registrarActividad(envio.leadId, envio.tipo, envio.detalle, envio.siguiente)
      if (!res.ok) {
        toast.error(res.error ?? 'No se pudo registrar el contacto')
        return
      }
      if (!(await (res.persistido ?? Promise.resolve(true)))) {
        setSinConfirmar(envio)
        return
      }
      onClose()
      toast.success(avisoDe({ demo: yo?.demo, avance: res.avance,
        ...(envio.tarea ? { cerroTarea: envio.tarea } : {}), sugerida: envio.sugerida, ahora }))
    } catch {
      setSinConfirmar(envio)
    } finally {
      enviando.current = false
      setProcesando(false)
    }
  }

  const registrar = async (tipo: TipoActividadManual) => {
    if (enviando.current || sinConfirmar) return
    const detalle = nota.trim() || undefined
    // La SIGUIENTE la calcula el motor ya escrito (alternancia de canal y
    // cadencia D1/D3 dentro de la ventana legal). `noContactar` es su
    // kill-switch de la Ley 29571: hasta hoy no se le pasaba desde ningún
    // llamador, así que el interruptor legal estaba muerto.
    const sugerida = puedeAgendar && agendaSiguiente
      ? sugerirSiguiente({
          tareaTipo: tarea?.tipo ?? TIPO_TAREA_DE_CANAL[canal],
          estado: 'completada',
          resultado: tipo,
          leadNombre: lead.nombre_completo,
          noContactar: lead.no_contactar ?? null,
          ahora: ahoraDelFormulario,
        })
      : null
    const reunionSugerida = sugerida?.tipo === 'reunion'
      ? validarReunionOperativa(camposReunion)
      : null
    if (reunionSugerida && !reunionSugerida.ok) {
      toast.error(reunionSugerida.error)
      return
    }
    const payloadReunionSugerida = camposTareaDeReunion(
      reunionSugerida?.ok ? reunionSugerida : null,
    )

    // El cierre y el contacto libre comparten la confirmación del servidor.
    // Cada RPC incluye la siguiente tarea en la misma transacción.
    await enviar({ leadId: lead.id, tipo, detalle, tarea: tarea && cierraTarea ? tarea : null, sugerida,
      siguiente: sugerida ? {
        tipo: sugerida.tipo, titulo: sugerida.titulo, vence_en: sugerida.vence_en,
        ...payloadReunionSugerida,
      } : null,
    })
  }

  return (
    <Dialog open onClose={() => { if (!enviando.current) onClose() }} ariaLabel="Resultado del contacto" className="w-[420px]">
      <DialogHeader>
        <DialogTitle>¿Lograste comunicarte con {primerNombre(lead.nombre_completo)}?</DialogTitle>
        <DialogDescription>
          {canal === 'tel'
            ? 'Registra cómo salió la llamada — queda en el historial del lead.'
            : 'Registra cómo va la conversación — queda en el historial del lead.'}
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-3">
        <fieldset disabled={procesando || sinConfirmar !== null} className="min-w-0 space-y-3">
        <div className="grid grid-cols-2 gap-2">
          {OPCIONES[canal].map((o) => (
            <Button key={o.tipo} size="sm" variant="outline" disabled={procesando} onClick={() => void registrar(o.tipo)}>
              <o.icono /> {o.label}
            </Button>
          ))}
        </div>
        <Textarea
          aria-label="Nota del contacto"
          disabled={procesando}
          value={nota}
          onChange={(e) => setNota(e.target.value)}
          placeholder="Nota (opcional)…"
          className="min-h-[56px] text-xs"
        />
        {/* NADA EN SILENCIO. El cierre de una tarea es irreversible y agendar
            escribe en la agenda del analista: las dos cosas se nombran, vienen
            premarcadas (es lo que quiere el 95% de las veces) y se destildan
            con un tap. Sin esto, el analista no entiende qué le pasó a su día. */}
        {(tarea || puedeAgendar) && (
          <div className="space-y-1.5 rounded-xl border border-[var(--accent)]/40 bg-[var(--accent)]/5 p-2.5">
            {tarea && (
              <label className="flex cursor-pointer items-start gap-2 text-[11px] font-semibold text-foreground/85">
                <input
                  type="checkbox"
                  className="mt-0.5 size-3.5 shrink-0 cursor-pointer accent-[var(--accent)]"
                  checked={cierraTarea}
                  onChange={(e) => setCierraTarea(e.target.checked)}
                />
                <span>
                  Cerrar también «{presentarCitas(tarea.titulo)}»{' '}
                  <span className="font-normal text-muted-foreground">
                    ({tareaAEvento(tarea, ahora).cuando})
                  </span>
                </span>
              </label>
            )}
            {puedeAgendar && (
              <>
                <label className="flex cursor-pointer items-start gap-2 text-[11px] font-semibold text-foreground/85">
                  <input
                    type="checkbox"
                    className="mt-0.5 size-3.5 shrink-0 cursor-pointer accent-[var(--accent)]"
                    checked={agendaSiguiente}
                    onChange={(e) => setAgendaSiguiente(e.target.checked)}
                  />
                  <span>
                    Agendar el siguiente paso{' '}
                    <span className="font-normal text-muted-foreground">
                      (el canal y la fecha los propone el sistema al elegir el resultado)
                    </span>
                  </span>
                </label>
                {agendaSiguiente && (
                  <div className="ml-5 mt-2 space-y-1.5">
                    <p className="text-[10px] font-medium text-muted-foreground">
                      Si el siguiente paso propuesto es una cita, indica su modalidad.
                    </p>
                    <CamposReunion
                      valor={camposReunion}
                      onChange={setCamposReunion}
                    />
                  </div>
                )}
              </>
            )}
          </div>
        )}
        </fieldset>
        {sinConfirmar && <p role="alert" className="text-sm text-destructive">El guardado todavía no está confirmado. Reintenta la misma operación para comprobar su resultado.</p>}
      </DialogBody>
      <DialogFooter>
        <Button variant="ghost" size="sm" disabled={procesando} onClick={() => {
          onClose()
          if (sinConfirmar) toast.warning('Guardado pendiente de confirmar: verifícalo en «Guardados por confirmar»')
          else toast.info('Contacto sin registrar: no quedó en el historial')
        }}>
          {sinConfirmar ? 'Cerrar (pendiente de confirmar)' : 'Cerrar sin registrar'}
        </Button>
        {sinConfirmar && <Button size="sm" disabled={procesando} onClick={() => void enviar(sinConfirmar)}>
          {procesando ? 'Confirmando…' : 'Reintentar guardado'}
        </Button>}
      </DialogFooter>
    </Dialog>
  )
}
