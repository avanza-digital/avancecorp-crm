// Ficha del lead (drawer derecho) — F1b. Se monta UNA vez en App.tsx y se abre
// desde cualquier pantalla vía usePanelesActions().abrirLead(id). Write-gating doble:
// la UI oculta acciones (directorio = solo lectura total) y el store re-valida.
// Los errores de validación del store ({ok:false, error} SIN toast) se muestran
// inline en los forms o con toast.error en acciones sueltas.
import { Fragment, useEffect, useMemo, useRef, useState, type ChangeEvent, type CSSProperties, type ReactNode } from 'react'
import { toast } from 'sonner'
import {
  ArrowRightLeft,
  BadgeCheck,
  Ban,
  CalendarCheck,
  CalendarPlus,
  CalendarX2,
  MessageCircle,
  MessageSquare,
  MoreHorizontal,
  Pencil,
  PhoneCall,
  PhoneMissed,
  RotateCcw,
  Send,
  Sparkles,
  StickyNote,
  Users,
  X,
  XCircle,
  type LucideIcon,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { AccionesContacto } from '@/components/app/contacto'
import { enlaceTel, numeroWhatsapp } from '@/lib/telefono'
import { reconocerTelefono } from '@/lib/validacion'
import { CerrarTareaDialog } from '@/components/app/cerrar-tarea'
import {
  CAMPOS_REUNION_VACIOS,
  CamposReunion,
  camposTareaDeReunion,
  type EstadoCamposReunion,
} from '@/components/app/campos-reunion'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { SeccionesBancarias } from '@/components/app/secciones-bancarias'
import { useAuth } from '@/lib/auth-context'
import {
  SECCION_BANCARIA_VACIA,
  normNombrePersona,
  validarBancariosForm,
  validarDomicilioLegal,
  type SeccionBancariaForm,
} from '@/lib/cliente-form-logica'
import { can, puedeEscribir } from '@/lib/roles'
import { useCRMData, usePanelesActions, usePanelesState } from '@/lib/store-context'
import { MOTIVOS_CON_EVIDENCIA, VETO_CORTO, vetoNoResponde } from '@/lib/descarte-evidencia'
import { DialogCapitalPropuesta } from '@/components/app/capital-propuesta'
import {
  convertirLead,
  CrmApiError,
  esClienteDeMiCartera,
  type TipoDocumentoCliente,
} from '@/data/crm-api'
import { ContratoNuevo } from '@/components/app/contrato-nuevo'
import { useAhora } from '@/lib/ahora'
import { retrocesoPorAnularReunion } from '@/lib/avance-automatico'
import { agruparTimeline } from '@/lib/timeline-lead'
import { MONTO_ESTIMADO_MAX, type CampoLead } from '@/lib/validacion'
import { esMoneda, fmtFecha, money, primerNombre, SIMBOLO, type Moneda } from '@/lib/format'
import { INFO_COOPERATIVA, type Cooperativa } from '@/lib/cierres-externos'
import { estadoDelCierre, puedeAnularCierreAvance } from '@/lib/cierre-estado'
import { useCierresEstado, useConvertirLeadExterno } from '@/data/crm-queries'
import { AnularCierreAvanceDialog } from '@/components/app/anular-cierre-avance'
import { ChipAnulado } from '@/components/app/chip-anulado'
import {
  CATEGORIAS_INTERES,
  CAT_LABEL,
  ETAPAS,
  ETAPA_INFO,
  esTipoTarea,
  MOTIVOS_NO_REALIZADA,
  MOTIVOS_DESCARTE,
  origenLabel,
  TIPOS_ACTIVIDAD,
  TIPOS_TAREA,
  type Actividad,
  type CategoriaInteres,
  type Etapa,
  type EtapaActiva,
  type Lead,
  type MotivoDescarte,
  type MotivoNoRealizadaManual,
  type TipoActividad,
  type TipoActividadManual,
  type TipoTarea,
  type Tarea,
} from '@/lib/tipos'
import { fechaLima, proximoSlotSugerido, tareaAEvento } from '@/lib/agenda-derivada'

// ── Helpers ───────────────────────────────────────────────────────────────────

const TIPOS_MANUALES: TipoActividadManual[] = [
  'llamada_realizada',
  'llamada_no_contestada',
  'whatsapp_enviado',
  'whatsapp_recibido',
  'reunion_realizada',
  'nota',
]

const ICONO_ACTIVIDAD: Record<TipoActividad, LucideIcon> = {
  llamada_realizada: PhoneCall,
  llamada_no_contestada: PhoneMissed,
  whatsapp_enviado: MessageCircle,
  whatsapp_recibido: MessageSquare,
  reunion_realizada: CalendarCheck,
  nota: StickyNote,
  cambio_etapa: ArrowRightLeft,
  reasignacion: Users,
  conversion: BadgeCheck,
}

/** "hace X" legible; para fechas viejas cae a fmtFecha. Formato propio del timeline
 * (min/h/'ayer'), más fino que haceTexto() de lib/inteligencia — NO sustituir.
 * `ahora` viene del reloj vivo useAhora() para que refresque sin remontar. */
function haceRelativo(iso: string, ahora: number): string {
  const ms = ahora - new Date(iso).getTime()
  if (!Number.isFinite(ms) || ms < 0) return fmtFecha(iso)
  const min = Math.floor(ms / 60_000)
  if (min < 1) return 'ahora'
  if (min < 60) return `hace ${min} min`
  const h = Math.floor(min / 60)
  if (h < 24) return `hace ${h} h`
  const d = Math.floor(h / 24)
  if (d === 1) return 'ayer'
  if (d < 7) return `hace ${d} d`
  return fmtFecha(iso)
}

/**
 * Rótulo del capital según el desenlace del lead. Un lead CERRADO no tiene
 * capital "en juego": el convertido ya lo ganó y el descartado no lo concretó.
 * Rotular ambos como "en juego" infla lo que el asesor cree tener vivo —
 * justo la cifra con la que decide a quién llamar hoy.
 */
function rotuloCapital(etapa: Etapa): string {
  if (etapa === 'convertido') return 'ganado'
  if (etapa === 'descartado') return 'no concretado'
  return 'en juego'
}

// ── Drawer (export) ───────────────────────────────────────────────────────────

export function LeadDrawer() {
  const { leadAbiertoId } = usePanelesState()
  const { lead } = useCRMData()
  const { cerrarPaneles } = usePanelesActions()
  const l = leadAbiertoId ? lead(leadAbiertoId) : undefined
  return (
    <Sheet open={!!l} onClose={cerrarPaneles} ariaLabel={l ? `Ficha del lead ${l.nombre_completo}` : 'Ficha del lead'}>
      {l && <Ficha key={l.id} l={l} />}
    </Sheet>
  )
}

// ── Ficha (contenido del sheet) ───────────────────────────────────────────────

function Ficha({ l }: { l: Lead }) {
  const { cerrarPaneles } = usePanelesActions()
  const { yo } = useAuth()
  const rol = yo?.rol
  const escribe = puedeEscribir(rol)
  const puedeReasignar = escribe && can(rol, 'reasignar')
  // Vendedor/supervisor conservan la regla de cartera propia. Gerencia puede
  // cerrar cualquier lead que ya tenga analista: el cliente conserva a ese
  // analista como asesor y las edges/RPC revalidan la membresía global.
  const tieneAnalista = l.vendedor_id != null
  const seraMiCliente = l.vendedor_id === yo?.id
  const operaGlobal = escribe && can(rol, 'verTodo')
  const puedeConvertir =
    escribe && (yo?.puede_contratar ?? false) && (seraMiCliente || (operaGlobal && tieneAnalista))
  const esTerminal = l.etapa === 'convertido' || l.etapa === 'descartado'
  const [dialogo, setDialogo] = useState<'convertir' | 'descartar' | null>(null)
  // Señal header → Datos: el badge "Sin capital estimado" abre el modo edición
  // de la sección Datos sin duplicar su estado (contador incremental).
  const [pedirEditarDatos, setPedirEditarDatos] = useState(0)
  const info = ETAPA_INFO[l.etapa]

  return (
    <>
      <SheetHeader className="gap-2.5">
        <div className="flex items-start gap-3">
          <Avatar nombre={l.nombre_completo} genero={l.genero ?? null} className="size-10" />
          <div className="min-w-0 flex-1">
            <SheetTitle className="truncate">{l.nombre_completo}</SheetTitle>
            <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
              <Badge color={info.color} dot>{info.label}</Badge>
              {l.categoria_interes && (
                <Badge color="var(--chart-4)">Inversión · {CAT_LABEL[l.categoria_interes]}</Badge>
              )}
              <Badge color="var(--muted-foreground)">{origenLabel(l.origen)}</Badge>
              {/* Capital ausente = vacío accionable: el badge ámbar abre Editar. */}
              {l.monto_estimado == null &&
                (escribe && !esTerminal ? (
                  <button
                    type="button"
                    className="cursor-pointer"
                    onClick={() => setPedirEditarDatos((n) => n + 1)}
                  >
                    <Badge color="#d97706">Sin capital estimado → completar</Badge>
                  </button>
                ) : (
                  <Badge color="#d97706">Sin capital estimado</Badge>
                ))}
            </div>
          </div>
          {/* Capital en juego arriba, siempre a la vista (mismo patrón del hover-card). */}
          {l.monto_estimado != null && (
            <div className="shrink-0 text-right leading-tight">
              <p className="text-sm font-extrabold tabular-nums text-primary">
                {money(l.monto_estimado, l.moneda)}
              </p>
              <p className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">
                {rotuloCapital(l.etapa)}
              </p>
            </div>
          )}
          <button
            type="button"
            onClick={cerrarPaneles}
            aria-label="Cerrar ficha"
            className="grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <X className="size-4" />
          </button>
        </div>
        <AccionesContacto lead={l} />
      </SheetHeader>

      <SheetBody className="space-y-5">
        {esTerminal ? <BannerTerminal l={l} escribe={escribe} /> : <Stepper l={l} escribe={escribe} />}
        <ProximaAccion l={l} escribe={escribe} activa={!esTerminal} />
        {/* `activa` faltaba AQUÍ y solo aquí: la ficha de un convertido seguía
            ofreciendo "Editar" y "Faltan DNI… → Completar" sobre un lead que el
            store ya no deja escribir. */}
        <Datos
          l={l}
          escribe={escribe}
          activa={!esTerminal}
          puedeReasignar={puedeReasignar}
          pedirEditar={pedirEditarDatos}
        />
        <Timeline l={l} escribe={escribe} activa={!esTerminal} />
      </SheetBody>

      {escribe && !esTerminal && (
        <SheetFooter className="justify-between">
          <Button
            variant="outline"
            size="sm"
            className="border-destructive/40 text-destructive hover:border-destructive/60 hover:bg-destructive/10"
            onClick={() => setDialogo('descartar')}
          >
            <XCircle /> Descartar
          </Button>
          {puedeConvertir ? (
            <Button size="sm" onClick={() => setDialogo('convertir')}>
              <BadgeCheck /> Convertir a cliente{yo?.demo ? ' (demo)' : ''}
            </Button>
          ) : (
            <p className="max-w-[62%] text-right text-[11px] leading-tight text-muted-foreground">
              {!tieneAnalista
                ? 'Asigna primero el lead a un analista; una conversión necesita responsable comercial.'
                : yo?.puede_contratar && !operaGlobal
                ? `La conversión la cierra ${primerNombre(l.vendedor_nombre) || 'el vendedor del lead'}. Para hacerla tú, reasígnate el lead.`
                : 'El alta del cliente la registra el vendedor.'}
            </p>
          )}
        </SheetFooter>
      )}

      {dialogo === 'convertir' && <DialogConvertir l={l} onClose={() => setDialogo(null)} />}
      {dialogo === 'descartar' && <DialogDescartar l={l} onClose={() => setDialogo(null)} />}
    </>
  )
}

// ── Stepper de etapas activas ─────────────────────────────────────────────────

function Stepper({ l, escribe }: { l: Lead; escribe: boolean }) {
  const { cambiarEtapa } = useCRMData()
  const idx = ETAPAS.findIndex((e) => e.k === l.etapa)
  // Mismo diálogo que el kanban: la pregunta del capital no puede depender de
  // POR DÓNDE se movió el lead, o la mitad de las propuestas guardaría la
  // corazonada del primer contacto.
  const [pidiendoCapital, setPidiendoCapital] = useState(false)

  const mover = (k: EtapaActiva) => {
    if (k === l.etapa) return
    if (k === 'propuesta_enviada') {
      setPidiendoCapital(true)
      return
    }
    const res = cambiarEtapa(l.id, k)
    if (!res.ok && res.error) toast.error(res.error)
  }

  return (
    <div className="flex items-center gap-1" role="group" aria-label="Etapa del lead">
      {pidiendoCapital && (
        <DialogCapitalPropuesta lead={l} onClose={() => setPidiendoCapital(false)} />
      )}
      {ETAPAS.map((e, i) => {
        const actual = i === idx
        const pasada = i < idx
        const st: CSSProperties | undefined = actual
          ? { background: e.color, color: '#fff' }
          : pasada
            ? { background: `color-mix(in srgb, ${e.color} 14%, transparent)`, color: e.color }
            : undefined
        return (
          <Fragment key={e.k}>
            {i > 0 && <span aria-hidden className="h-px w-2 shrink-0 bg-border" />}
            <button
              type="button"
              disabled={!escribe}
              onClick={() => mover(e.k)}
              title={escribe && !actual ? `Mover a ${e.label}` : undefined}
              aria-current={actual ? 'step' : undefined}
              className={cn(
                'whitespace-nowrap rounded-full px-2 py-1 text-[10px] font-bold leading-none transition-transform',
                !actual && !pasada && 'bg-muted text-muted-foreground',
                escribe ? 'cursor-pointer hover:scale-[1.05]' : 'cursor-default',
              )}
              style={st}
            >
              {e.label}
            </button>
          </Fragment>
        )
      })}
    </div>
  )
}

// ── Banner de estado terminal ─────────────────────────────────────────────────

function BannerTerminal({ l, escribe }: { l: Lead; escribe: boolean }) {
  const { reabrir, cierresEstado } = useCRMData()
  const { yo } = useAuth()
  const demo = Boolean(yo?.demo)
  const convertido = l.etapa === 'convertido'
  const info = ETAPA_INFO[l.etapa]
  const motivo = MOTIVOS_DESCARTE.find((m) => m.k === l.motivo_descarte)?.label
  const [anulando, setAnulando] = useState(false)
  /** El botón que abrió el diálogo, para devolverle el foco al cerrarlo. */
  const refAnular = useRef<HTMLButtonElement>(null)

  // El estado del cierre. En real solo puede venir de la RPC: la tabla donde se
  // escribe la anulación es deny-by-default y no se lee desde la Data API. En
  // demo viene DERIVADO del store, con la misma forma — así esta ficha no tiene
  // dos caminos que envejezcan por separado.
  const consultaEstado = useCierresEstado(!demo && convertido, [l.id])
  const filasEstado = demo ? cierresEstado : (consultaEstado.data ?? [])
  const estado = filasEstado.find((f) => f.lead_id === l.id)
  const { anulado, motivo: motivoAnulacion } = estadoDelCierre(estado)
  const puedeAnular = puedeAnularCierreAvance({ rol: yo?.rol, etapa: l.etapa, estado })

  const onReabrir = () => {
    const res = reabrir(l.id)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    toast.success(`Lead reabierto${yo?.demo ? ' (demo)' : ''} — vuelve a Nuevo`)
  }

  const cerrarAnulacion = () => {
    setAnulando(false)
    // De vuelta al botón de donde salió: sin esto el foco cae al principio de la
    // ficha y hay que recorrerla entera para volver al sitio.
    requestAnimationFrame(() => refAnular.current?.focus())
  }

  return (
    <div
      className="flex items-center gap-2.5 rounded-xl border px-3 py-2.5"
      style={{
        borderColor: `color-mix(in srgb, ${info.color} 30%, transparent)`,
        background: `color-mix(in srgb, ${info.color} 7%, transparent)`,
      }}
    >
      {convertido ? (
        <BadgeCheck aria-hidden className="size-4 shrink-0" style={{ color: info.color }} />
      ) : (
        <XCircle aria-hidden className="size-4 shrink-0" style={{ color: info.color }} />
      )}
      <div className="min-w-0 flex-1">
        <p className="text-xs font-bold" style={{ color: info.color }}>
          {convertido ? `Convertido a cliente${yo?.demo ? ' (demo)' : ''}` : 'Lead descartado'}
        </p>
        <p className="text-[11px] text-muted-foreground">
          {convertido
            ? yo?.demo
              ? 'En producción, la conversión crea al cliente en el portal y cierra el lead como ganado.'
              : 'Cliente creado en el portal y lead cerrado como ganado.'
            : `Motivo: ${motivo ?? '—'}`}
        </p>
        {/* La anulación se ve AQUÍ, junto al «Convertido a cliente» que
            contradice, y con la razón escrita: quien mire esta ficha tiene que
            poder explicarse por qué el número del asesor bajó. */}
        {convertido && anulado && (
          <p className="mt-1.5 flex flex-wrap items-center gap-1.5 text-[11px] text-destructive-text">
            <ChipAnulado etiqueta="CIERRE ANULADO" />
            <span className="min-w-0">{motivoAnulacion ?? 'Sin motivo registrado'}</span>
          </p>
        )}
      </div>
      {!convertido && escribe && (
        <Button size="xs" variant="outline" onClick={onReabrir}>
          <RotateCcw /> Reabrir{yo?.demo ? ' (demo)' : ''}
        </Button>
      )}
      {/* ⚠️ «Anular el cierre», no «Anular» a secas: esta misma ficha ya tiene
          botones «Anular» que quitan una TAREA, y dos acciones con el mismo
          rótulo son indistinguibles en el rotor de un lector de pantalla —
          además de invitar a confundir quitar un recordatorio con quitarle el
          mérito a una persona. */}
      {puedeAnular && (
        <Button
          ref={refAnular}
          size="xs"
          variant="outline"
          aria-label={`Anular el cierre de ${l.nombre_completo}`}
          onClick={() => setAnulando(true)}
        >
          <Ban /> Anular el cierre
        </Button>
      )}
      {anulando && (
        <AnularCierreAvanceDialog lead={l} demo={demo} onCerrar={cerrarAnulacion} />
      )}
    </div>
  )
}

// ── Próxima acción (agenda del lead — el corazón del motor) ───────────────────
// Regla de oro del plan v2: ningún lead activo sin una acción futura agendada.
// Esta sección la hace visible en la ficha: lista las tareas PENDIENTES del
// lead y permite agendar la siguiente en un gesto (quick-add con defaults:
// tipo llamada, título prellenado, próximo día hábil 10:00 — ventana legal
// L–S 07:00–20:00 como sugerencia, no candado).

const TITULO_POR_TIPO: Record<TipoTarea, string> = {
  llamada: 'Llamar a',
  whatsapp: 'WhatsApp a',
  reunion: 'Reunión con',
  tarea: 'Tarea —',
}

function tituloSugerido(tipo: TipoTarea, nombre: string): string {
  const primero = nombre.trim().split(/\s+/)[0] ?? ''
  return `${TITULO_POR_TIPO[tipo]} ${primero}`.trim()
}

/** ¿El instante cae fuera de la ventana legal peruana (L–S 07:00–20:00)? */
function fueraDeVentanaLegal(fecha: string, hora: string): boolean {
  const d = new Date(`${fecha}T${hora}:00-05:00`)
  if (Number.isNaN(d.getTime())) return false
  const dow = new Date(d.getTime() - 5 * 3600 * 1000).getUTCDay() // reloj Lima
  const [h] = hora.split(':').map(Number)
  return dow === 0 || (h ?? 12) < 7 || (h ?? 12) >= 20
}

function ProximaAccion({ l, escribe, activa }: { l: Lead; escribe: boolean; activa: boolean }) {
  const { tareasDe, crearTarea, anularTarea, actividadesDe } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  const pendientes = tareasDe(l.id)
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  // Confirmación de anulado, INLINE y por fila (id de la tarea, no un boolean):
  // la lista puede tener varias y el "¿seguro?" tiene que quedar pegado a la
  // que se va a anular. Anular es irreversible en el servidor, así que no puede
  // ir a un tap; `window.confirm` está descartado (bloquea el hilo y en móvil
  // sale como diálogo del navegador, fuera del CRM).
  const [anulandoId, setAnulandoId] = useState<string | null>(null)
  // Los botones de la confirmación se DESMONTAN al pulsarlos (y con «Sí» se va
  // el `<li>` entero). Sin devolver el foco a mano, Radix lo rescata al tope
  // del drawer y hay que re-tabular stepper, banner y ficha completa para
  // volver a la lista. Mismo idioma de refs por id que usa `repartir.tsx`.
  const refInterruptores = useRef(new Map<string, HTMLButtonElement>())
  const refSeccion = useRef<HTMLElement>(null)
  // Con pendientes vivas, agendar OTRA es un gesto raro: el quick-add se pliega
  // tras este botón. Solo con 0 pendientes (aviso ámbar) queda abierto siempre.
  const [agendarOtra, setAgendarOtra] = useState(false)
  const [motivoAnulacionReunion, setMotivoAnulacionReunion] =
    useState<MotivoNoRealizadaManual | ''>('')

  const slot = proximoSlotSugerido(ahora)
  const [tipo, setTipo] = useState<TipoTarea>('llamada')
  const [titulo, setTitulo] = useState(() => tituloSugerido('llamada', l.nombre_completo))
  const [tituloEditado, setTituloEditado] = useState(false)
  const [fecha, setFecha] = useState(() => fechaLima(Date.parse(slot)))
  const [hora, setHora] = useState('10:00')
  const [camposReunion, setCamposReunion] =
    useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)

  if (!escribe && pendientes.length === 0) return null
  // Lead cerrado: sus pendientes ya fueron canceladas por el trigger; nada que agendar.
  if (!activa && pendientes.length === 0) return null

  const cambiarTipo = (v: string) => {
    if (!esTipoTarea(v)) return
    setTipo(v)
    // El título sugerido sigue al tipo mientras el vendedor no lo haya tocado.
    if (!tituloEditado) setTitulo(tituloSugerido(v, l.nombre_completo))
  }

  /**
   * ANULAR desde la ficha — el atajo para el caso que lo motivó: acabas de
   * agendar la reunión y la llamada de la semana pasada sobra. Sin esto había
   * que abrir el diálogo de cierre y elegir un resultado FALSO para sacarla.
   * `anularTarea` no escribe actividad de contacto (ver lib/store.tsx); lo único
   * que puede mover es la etapa, hacia atrás y solo al anular la última reunión
   * viva sin reagendar (pedido de Miguel, 2026-07-26).
   */
  const anular = (t: Tarea) => {
    let res
    if (t.tipo === 'reunion') {
      if (!motivoAnulacionReunion) {
        toast.error('Selecciona por qué se cancela la reunión')
        return
      }
      res = anularTarea(t.id, { motivo: motivoAnulacionReunion })
    } else {
      res = anularTarea(t.id)
    }
    setAnulandoId(null)
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo anular la tarea')
      // La fila sigue ahí (no se anuló nada): el foco vuelve a su interruptor.
      requestAnimationFrame(() => refInterruptores.current.get(t.id)?.focus())
      return
    }
    // La fila se fue. El foco aterriza en la sección, que sigue montada aunque
    // la lista quede vacía — desde ahí el siguiente Tab es el quick-add.
    requestAnimationFrame(() => refSeccion.current?.focus())
    const sufijo = yo?.demo ? ' (demo)' : ''
    // Mismo orden de prioridad que en cerrar-tarea.tsx: el retroceso de etapa
    // gana al "sin próxima acción" porque es el cambio que el asesor no pidió.
    if (res.retroceso) {
      toast.warning(
        `Tarea anulada — ${primerNombre(l.nombre_completo)} vuelve a «${ETAPA_INFO[res.retroceso].label}»${sufijo}`,
      )
      return
    }
    // `pendientes` es la lista PREVIA a la mutación optimista: si esta era la
    // única, el lead se queda sin plan y cae a la cola. Mismo criterio de
    // honestidad que `quedaSinPlan` en cerrar-tarea.tsx — a un lead cerrado o
    // a un "No Insista" no se le puede prometer esa consecuencia.
    if (pendientes.length === 1 && activa && !l.no_contactar) {
      toast.warning(
        `Tarea anulada — ${primerNombre(l.nombre_completo)} quedó SIN próxima acción${sufijo}`,
      )
    } else {
      toast.success(`Tarea anulada${sufijo}`)
    }
  }

  const agendar = () => {
    const reunion = tipo === 'reunion'
      ? validarReunionOperativa(camposReunion)
      : null
    if (reunion && !reunion.ok) {
      toast.error(reunion.error)
      return
    }
    const res = crearTarea({
      lead_id: l.id,
      tipo,
      titulo,
      vence_en: new Date(`${fecha}T${hora}:00-05:00`).toISOString(),
      ...camposTareaDeReunion(reunion?.ok ? reunion : null),
    })
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo agendar la tarea')
      return
    }
    // NADA EN SILENCIO: agendar una reunión con quien ya se trabajó sube el lead
    // a "Reunión agendada" por trigger (lib/avance-automatico). El store ya lo
    // devolvía en los otros dos escritores y aquí se tiraba: el asesor veía
    // moverse el stepper sin saber por qué. Mismo formato "hecho · hecho" que
    // `avisoDe` en contacto.tsx, y el mismo orden en que ocurren las cosas.
    const partes = ['Tarea agendada']
    if (res.avance) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
    partes.push('la verás en Hoy y en Agenda')
    toast.success(`${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}`)
    setTituloEditado(false)
    setTitulo(tituloSugerido(tipo, l.nombre_completo))
    setAgendarOtra(false) // vuelve a plegarse: ya hay próxima acción visible
  }

  const avisoVentana = fueraDeVentanaLegal(fecha, hora)

  return (
    <section
      ref={refSeccion}
      tabIndex={-1}
      aria-label="Próxima acción"
      // `focus-visible` (no `focus`): tras anular, el foco aterriza aquí y quien
      // navega con teclado necesita VER dónde quedó antes de pulsar Tab. Como
      // solo se dispara si la última interacción fue de teclado, el caso ratón
      // no se ensucia con un anillo que nadie pidió.
      className="rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
    >
      <div className="mb-1.5 flex items-center justify-between">
        <h3 className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
          <CalendarPlus className="size-3.5" aria-hidden /> Próxima acción
        </h3>
        {pendientes.length > 0 && (
          <Badge color="var(--accent)" className="text-[10px]">
            {pendientes.length} pendiente{pendientes.length === 1 ? '' : 's'}
          </Badge>
        )}
      </div>

      {/* Pendientes del lead: la promesa visible de que nadie lo suelta. */}
      {pendientes.length > 0 && (
        <ul className="mb-2 space-y-1">
          {pendientes.map((t) => {
            const ev = tareaAEvento(t, ahora)
            return (
              <li
                key={t.id}
                // El estado «armado» se marca con FORMA (anillo), no con
                // tinte de fondo. El `bg-[#d97706]/10` que había aquí hundía
                // `text-muted-foreground` de 4.49:1 a 4.28:1 —por debajo de AA—
                // y la fecha VENCIDA a 2.86:1: justo cuando armas el botón
                // destructivo dejabas de poder leer el dato que decide si
                // anulas o no. El fondo se queda quieto y el anillo dice lo
                // mismo sin tocar ningún contraste.
                className={cn(
                  'rounded-lg bg-muted/50 px-2.5 py-1.5 text-xs',
                  anulandoId === t.id && 'ring-1 ring-[#d97706]/60',
                )}
              >
                {/* ⚠️ ESTA LÍNEA NO SE MUEVE NUNCA. La confirmación de anular
                    NO reemplaza la fila: se añade DEBAJO. Cuando sí la
                    reemplazaba, el «Sí, anular» (destructivo, `h-6`, último
                    hijo del flex) nacía cubriendo por completo los 24 px del
                    icono que acababa de armarlo — mismo borde derecho, mismo
                    alto. Un doble clic, o el segundo tap de quien cree que la
                    ficha no respondió, caía sobre «Sí, anular» y anulaba la
                    tarea sin que la pregunta llegara a leerse. Y anular es
                    IRREVERSIBLE en el servidor: no hay «Deshacer» como en la
                    pestaña Descartados. */}
                <div className="flex items-center gap-2">
                  <span className="size-2 shrink-0 rounded-full" style={{ background: ev.color }} aria-hidden />
                  <span className="min-w-0 flex-1 truncate font-medium">{t.titulo}</span>
                  <span
                    className={cn(
                      'shrink-0 font-semibold tabular-nums',
                      // `--warning-text` y no el ámbar puro: `#d97706` daba
                      // 3.01:1 sobre el fondo de la fila y AA pide 4.5.
                      ev.vencida ? 'text-warning-text' : 'text-muted-foreground',
                    )}
                  >
                    {ev.cuando}
                  </span>
                  {escribe && activa && (
                    <>
                      {/* `pointer-coarse:size-8`: el criterio que el repo ya
                          documentó en agenda.tsx — 24 px siempre, 32 px con
                          puntero grueso (el dedo). El icono de cerrar lo lleva
                          también porque ahora son DOS objetivos de 24 px a 8 px
                          uno del otro en la misma fila, y uno arma un
                          destructivo: dejarlos disparejos sería peor. */}
                      <button
                        type="button"
                        aria-label={`Cerrar tarea — ${t.titulo}`}
                        title="Cerrar tarea (resultado + siguiente)"
                        className="grid size-6 shrink-0 cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground pointer-coarse:size-8"
                        onClick={() => setTareaACerrar(t)}
                      >
                        <CalendarCheck className="size-3.5" aria-hidden />
                      </button>
                      {/* Anular: para la tarea que se volvió innecesaria (ya
                          hay reunión agendada). Sin este botón el único camino
                          era cerrarla con un resultado FALSO.
                          Es un INTERRUPTOR (`aria-expanded`), no un disparador:
                          el segundo clic desarma en vez de confirmar, así que
                          un doble clic sobre él se cancela a sí mismo. */}
                      <button
                        type="button"
                        ref={(el) => {
                          if (el) refInterruptores.current.set(t.id, el)
                          else refInterruptores.current.delete(t.id)
                        }}
                        aria-label={`Anular tarea — ${t.titulo}`}
                        aria-expanded={anulandoId === t.id}
                        // `aria-expanded` solo dice "expandido"; con
                        // `aria-controls` el lector puede SALTAR al bloque que
                        // abrió (mismo par que el panel de filtros de agenda).
                        {...(anulandoId === t.id ? { 'aria-controls': `anular-${t.id}` } : {})}
                        title="Anular (ya no hace falta) — no queda como gestión"
                        className={cn(
                          'grid size-6 shrink-0 cursor-pointer place-items-center rounded-md transition-colors pointer-coarse:size-8',
                          anulandoId === t.id
                            ? 'bg-[#d97706]/20 text-warning-text'
                            : 'text-muted-foreground hover:bg-[#d97706]/15 hover:text-warning-text',
                        )}
                        onClick={() => {
                          const abrir = anulandoId !== t.id
                          setAnulandoId(abrir ? t.id : null)
                          if (abrir) setMotivoAnulacionReunion('')
                        }}
                      >
                        <CalendarX2 className="size-3.5" aria-hidden />
                      </button>
                    </>
                  )}
                </div>
                {/* Segunda línea: el destructivo vive a la IZQUIERDA y abajo,
                    lo más lejos posible del icono que lo armó (arriba a la
                    derecha). Va dentro de la misma guarda `escribe && activa`
                    que el interruptor, para que un lead que se cierre con la
                    confirmación abierta no deje un botón destructivo armado. */}
                {escribe && activa && anulandoId === t.id && (
                  <div
                    id={`anular-${t.id}`}
                    className="mt-1.5 flex items-center gap-2 border-t border-[#d97706]/30 pt-1.5"
                  >
                    <Button
                      size="xs"
                      variant="destructive"
                      className="pointer-coarse:h-8 pointer-coarse:px-3"
                      aria-label={`Sí, anular — ${t.titulo}`}
                      // La consecuencia se pinta DESPUÉS de los botones, así
                      // que quien navega con teclado llegaría al destructivo
                      // antes de oírla. `aria-describedby` la trae al foco.
                      aria-describedby={`anular-nota-${t.id}`}
                      onClick={() => anular(t)}
                      disabled={t.tipo === 'reunion' && !motivoAnulacionReunion}
                    >
                      Sí, anular
                    </Button>
                    <Button
                      size="xs"
                      variant="ghost"
                      className="pointer-coarse:h-8 pointer-coarse:px-3"
                      aria-label={`No anular — ${t.titulo}`}
                      onClick={() => {
                        setAnulandoId(null)
                        requestAnimationFrame(() => refInterruptores.current.get(t.id)?.focus())
                      }}
                    >
                      No
                    </Button>
                    {t.tipo === 'reunion' && (
                      <Select
                        aria-label={`Motivo de cancelación — ${t.titulo}`}
                        value={motivoAnulacionReunion}
                        onChange={(evento) => setMotivoAnulacionReunion(
                          evento.target.value as typeof motivoAnulacionReunion,
                        )}
                        className="h-7 w-44 text-[11px]"
                      >
                        <option value="">Selecciona el motivo</option>
                        {MOTIVOS_NO_REALIZADA.map((opcion) => (
                          <option key={opcion.k} value={opcion.k}>{opcion.label}</option>
                        ))}
                      </Select>
                    )}
                    {/* La nota cambia cuando anular ARRASTRA la etapa: esa es
                        la consecuencia grande, y callarla aquí obligaría a
                        descubrirla por el toast, ya consumada. Se calcula por
                        fila (cada tarea tiene su propia respuesta) y con la
                        lista PREVIA a la mutación, igual que el store. */}
                    {/* `aria-live` porque este texto PUEDE cambiar con la
                        confirmación ya armada: desde aquí mismo se puede
                        agendar otra reunión o mover el stepper, y entonces la
                        respuesta pasa de «vuelve a Contactado» a la genérica.
                        `aria-describedby` solo se lee AL ENFOCAR y nunca se
                        re-anuncia solo, así que sin esto el botón destructivo
                        se quedaría prometiendo lo que se leyó hace 20 s.
                        La coletilla «No se puede deshacer» va en las DOS ramas:
                        el ternario sustituía en vez de sumar, y quien opera
                        desde la ficha (el que va más rápido) acababa con menos
                        aviso que quien abre el diálogo. */}
                    <span
                      id={`anular-nota-${t.id}`}
                      aria-live="polite"
                      className="min-w-0 flex-1 text-[11px] font-semibold text-warning-text"
                    >
                      {(() => {
                        const atras = retrocesoPorAnularReunion(l, t, pendientes, actividadesDe(l.id))
                        if (atras) {
                          return `Era su única reunión: vuelve a «${ETAPA_INFO[atras].label}». La cancelación queda en el reporte. No se puede deshacer.`
                        }
                        return t.tipo === 'reunion'
                          ? 'Queda cancelada con motivo en el reporte y no cuenta como realizada. No se puede deshacer.'
                          : 'No queda como gestión ni en el historial. No se puede deshacer.'
                      })()}
                    </span>
                  </div>
                )}
              </li>
            )
          })}
        </ul>
      )}

      {escribe && activa && pendientes.length > 0 && !agendarOtra && (
        <Button size="xs" variant="ghost" onClick={() => setAgendarOtra(true)}>
          <CalendarPlus /> Agendar otra
        </Button>
      )}

      {escribe && activa && (pendientes.length === 0 || agendarOtra) && (
        <div className="rounded-xl border border-border/70 p-2.5">
          {pendientes.length === 0 && (
            <p className="mb-2 text-[11px] font-medium text-[#d97706]">
              Este lead no tiene próxima acción — agéndale una para que no se enfríe.
            </p>
          )}
          {/* Fecha en la columna ancha ("dd/mm/aaaa" + picker) y hora en la fija:
              cada campo con el ancho de lo que hay que LEER. */}
          <div className="space-y-2">
            <div className="grid grid-cols-[110px_1fr] gap-2">
              <Select
                aria-label="Tipo de tarea"
                value={tipo}
                onChange={(e) => cambiarTipo(e.target.value)}
              >
                {TIPOS_TAREA.map((t) => (
                  <option key={t.k} value={t.k}>{t.label}</option>
                ))}
              </Select>
              <Input
                aria-label="Título de la tarea"
                value={titulo}
                maxLength={200}
                onChange={(e) => {
                  setTitulo(e.target.value)
                  setTituloEditado(true)
                }}
              />
            </div>
            <div className="grid grid-cols-[1fr_96px] gap-2">
              <Input
                aria-label="Fecha"
                type="date"
                value={fecha}
                onChange={(e) => setFecha(e.target.value)}
              />
              <Input
                aria-label="Hora"
                type="time"
                value={hora}
                onChange={(e) => setHora(e.target.value)}
              />
            </div>
            {tipo === 'reunion' && (
              <CamposReunion
                valor={camposReunion}
                onChange={setCamposReunion}
              />
            )}
            <Button
              size="sm"
              className="w-full"
              onClick={agendar}
              disabled={
                !titulo.trim()
                || !fecha
                || !hora
                || (tipo === 'reunion' && (
                  !camposReunion.modalidad
                  || (camposReunion.modalidad === 'presencial' && !camposReunion.ubicacion.trim())
                  || (camposReunion.modalidad === 'virtual' && !camposReunion.enlace.trim())
                ))
              }
            >
              <CalendarPlus /> Agendar
            </Button>
          </div>
          {avisoVentana && (
            <p className="mt-1.5 text-[10px] font-medium text-muted-foreground">
              Fuera de la ventana L–S 07:00–20:00 (Ley 29571) — úsalo solo si el cliente lo pidió.
            </p>
          )}
        </div>
      )}

      <CerrarTareaDialog tarea={tareaACerrar} onCerrar={() => setTareaACerrar(null)} />
    </section>
  )
}

// ── Sección Datos ─────────────────────────────────────────────────────────────

function Fila({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[96px_1fr] items-baseline gap-2 py-1">
      <dt className="text-[11px] font-semibold text-muted-foreground">{label}</dt>
      <dd className="min-w-0 text-[13px] text-foreground">{children}</dd>
    </div>
  )
}

/**
 * El segundo número del lead en sus tres estados. Vive aparte de `Fila` porque
 * la lógica de «qué hay que enseñar» no es de presentación: decide entre un
 * canal de contacto usable, un dato que hay que corregir y una ausencia real.
 *
 * El texto crudo NO se ofrece como enlace a propósito. Si no se pudo entender
 * como teléfono, un `tel:` encima marcaría cualquier cosa; el vendedor lo lee,
 * deduce el número y lo corrige. Presentarlo como marcable sería mentir sobre
 * la confianza que merece.
 */
function SegundoNumero({ numero, crudo }: { numero: string | null; crudo: string | null }) {
  if (numero) {
    const tel = enlaceTel(numero)
    // ⚠️ `numeroWhatsapp` solo mira que haya dígitos suficientes: sobre un FIJO
    // devuelve un número perfectamente formado que NADIE va a contestar. Quien
    // decide si hay WhatsApp es el reconocedor, que sí distingue móvil de fijo.
    const wa = reconocerTelefono(numero)?.movil ? numeroWhatsapp(numero) : null
    return (
      <span className="inline-flex flex-wrap items-baseline gap-x-2 gap-y-1">
        {tel ? (
          <a href={tel} className="tabular-nums text-primary underline-offset-2 hover:underline">
            {numero}
          </a>
        ) : (
          <span className="tabular-nums">{numero}</span>
        )}
        {wa && (
          <a
            href={`https://wa.me/${wa}`}
            target="_blank"
            rel="noreferrer"
            className="text-[11px] font-semibold text-primary underline-offset-2 hover:underline"
          >
            WhatsApp
          </a>
        )}
      </span>
    )
  }
  if (crudo) {
    return (
      <span className="inline-flex flex-wrap items-baseline gap-x-2 gap-y-1">
        <span className="tabular-nums">«{crudo}»</span>
        <Badge color="var(--warning)">sin validar</Badge>
      </span>
    )
  }
  return (
    <span className="text-muted-foreground">— el origen no dio un segundo número</span>
  )
}

/** Lista es-PE: "a, b y c" (para la línea de datos faltantes). */
function listarFaltantes(xs: string[]): string {
  if (xs.length <= 1) return xs[0] ?? ''
  return `${xs.slice(0, -1).join(', ')} y ${xs[xs.length - 1]}`
}

function Datos({
  l,
  escribe,
  activa,
  puedeReasignar,
  pedirEditar = 0,
}: {
  l: Lead
  escribe: boolean
  /** false en leads terminales: se puede LEER la ficha, no reescribirla. */
  activa: boolean
  puedeReasignar: boolean
  pedirEditar?: number
}) {
  const { editarLead, reasignar, ambito } = useCRMData()
  const { yo } = useAuth()
  const sufijoDemo = yo?.demo ? ' (demo)' : ''
  const [editando, setEditando] = useState(false)
  // El error se guarda CON su campo (código estructurado del store, nunca
  // adivinando por regex sobre el texto) para marcar como inválido el input
  // culpable y no el primero que pase por ahí. `campo: null` = error general.
  const [error, setError] = useState<{ campo: CampoLead | null; mensaje: string } | null>(null)
  const [form, setForm] = useState({
    nombre: '',
    telefono: '',
    telefonoAlternativo: '',
    correo: '',
    monto: '',
    moneda: 'PEN' as Moneda,
    dni: '',
    distrito: '',
    categoria: null as CategoriaInteres | null,
    nota: '',
  })

  // SOLO vendedores del ámbito del rol (espejo del WITH CHECK de leads_update):
  // supervisor ve/asigna únicamente a los suyos; gerencia sigue viendo a todos.
  const vendedores = ambito.vendedores.filter((m) => m.rol_crm === 'vendedor' && m.activo)

  const empezar = () => {
    setForm({
      nombre: l.nombre_completo,
      telefono: l.telefono,
      telefonoAlternativo: l.telefono_alternativo ?? l.telefono_alternativo_crudo ?? '',
      correo: l.correo ?? '',
      monto: l.monto_estimado != null ? String(l.monto_estimado) : '',
      moneda: l.moneda,
      dni: l.dni ?? '',
      distrito: l.distrito ?? '',
      categoria: l.categoria_interes ?? null,
      nota: l.nota ?? '',
    })
    setError(null)
    setEditando(true)
  }

  const guardar = () => {
    const montoTxt = form.monto.trim()
    const monto = Number(montoTxt.replace(',', '.'))
    if (!montoTxt || !Number.isFinite(monto) || monto <= 0) {
      setError({ campo: 'monto_estimado', mensaje: 'El capital estimado es obligatorio y debe ser mayor que 0' })
      return
    }
    // El DNI NO se revalida aquí: `editarLead` ya corre validarCamposLead (los
    // 8 dígitos) y devuelve el error CON su `campo`. Una segunda copia de la
    // regla en la UI es exactamente lo que hace divergir los mensajes.
    const res = editarLead(l.id, {
      nombre_completo: form.nombre,
      telefono: form.telefono,
      // Corregir el segundo número desde la ficha es la ÚNICA vía que tiene hoy
      // el vendedor: aquí es donde llega el texto que el origen escribió mal y
      // que la fila muestra como «sin validar». Vaciarlo también es legítimo.
      telefono_alternativo: form.telefonoAlternativo.trim() || null,
      correo: form.correo.trim() || null,
      monto_estimado: monto,
      moneda: form.moneda,
      dni: form.dni.trim() || null,
      distrito: form.distrito.trim() || null,
      categoria_interes: form.categoria,
      nota: form.nota.trim() || null,
    })
    if (!res.ok) {
      setError({ campo: res.campo ?? null, mensaje: res.error ?? 'No se pudo guardar' })
      return
    }
    setEditando(false)
    setError(null)
    toast.success(`Cambios guardados${sufijoDemo}`)
  }

  /** ¿El error vivo apunta a este campo? (marca aria-invalid + describedby). */
  const invalido = (campo: CampoLead) => error?.campo === campo

  const onReasignar = (v: string) => {
    const res = reasignar(l.id, v || null)
    if (!res.ok) {
      // Los errores de permiso ya los toastea el store (doble defensa).
      if (res.error && !res.error.startsWith('Sin permiso')) toast.error(res.error)
      return
    }
    toast.success(v ? `Lead reasignado${sufijoDemo}` : `Lead parkeado sin vendedor${sufijoDemo}`)
  }

  const campo = (k: keyof typeof form) => (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    // Al corregir, el error se va: si no, el input sigue marcado aria-invalid
    // (y describiéndose con un mensaje ya resuelto) hasta el siguiente Guardar.
    setError(null)
    setForm((f) => ({ ...f, [k]: e.target.value }))
  }

  // El badge "Sin capital estimado → completar" del header pide abrir la edición.
  useEffect(() => {
    if (pedirEditar > 0 && escribe && activa) empezar()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pedirEditar])

  // Campos sin dato: en vez de un muro de filas con '—', una sola línea accionable.
  const faltantes = [
    l.monto_estimado == null && 'capital estimado',
    !l.correo && 'correo',
    !l.dni && 'DNI',
    !l.distrito && 'distrito',
    !l.categoria_interes && 'categoría',
    !l.nota && 'nota',
  ].filter((x): x is string => typeof x === 'string')

  return (
    <section aria-label="Datos del lead">
      <div className="flex items-center justify-between">
        <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Datos</h3>
        {escribe && activa && !editando && (
          <Button size="xs" variant="ghost" onClick={empezar}>
            <Pencil /> Editar
          </Button>
        )}
      </div>

      {editando ? (
        <div className="mt-2 space-y-3 rounded-xl border border-border bg-muted/40 p-3">
          <div className="space-y-1.5">
            <Label htmlFor="ld-nombre">Nombre completo</Label>
            <Input
              id="ld-nombre"
              value={form.nombre}
              onChange={campo('nombre')}
              aria-invalid={invalido('nombre_completo')}
              aria-describedby={invalido('nombre_completo') ? 'ld-datos-error' : undefined}
            />
          </div>
          <div className="grid grid-cols-2 gap-2.5">
            <div className="space-y-1.5">
              <Label htmlFor="ld-telefono">Teléfono</Label>
              <Input
                id="ld-telefono"
                value={form.telefono}
                onChange={campo('telefono')}
                placeholder="9########"
                aria-invalid={invalido('telefono')}
                aria-describedby={invalido('telefono') ? 'ld-datos-error' : undefined}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ld-telefono-alt">Teléfono alternativo</Label>
              <Input
                id="ld-telefono-alt"
                value={form.telefonoAlternativo}
                onChange={campo('telefonoAlternativo')}
                placeholder="Otro celular, un fijo o +código de país"
                aria-invalid={invalido('telefono_alternativo')}
                aria-describedby={invalido('telefono_alternativo') ? 'ld-datos-error' : undefined}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ld-monto">Capital estimado *</Label>
              <div className="flex gap-2">
                <Input id="ld-monto" className="min-w-0 flex-1 tabular-nums" type="number" min={0.01} max={MONTO_ESTIMADO_MAX} step="0.01" inputMode="decimal" required aria-required="true" aria-invalid={invalido('monto_estimado')} aria-describedby={invalido('monto_estimado') ? 'ld-datos-error' : undefined} value={form.monto} onChange={campo('monto')} placeholder="Ej. 5000" />
                <Select
                  aria-label="Moneda del capital estimado"
                  className="w-24 shrink-0"
                  value={form.moneda}
                  onChange={(e) => {
                    const moneda = e.target.value
                    if (esMoneda(moneda)) {
                      setForm((actual) => ({ ...actual, moneda }))
                    }
                  }}
                >
                  <option value="PEN">{SIMBOLO.PEN} PEN</option>
                  <option value="USD">{SIMBOLO.USD} USD</option>
                </Select>
              </div>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ld-correo">Correo</Label>
            <Input
              id="ld-correo"
              type="email"
              value={form.correo}
              onChange={campo('correo')}
              placeholder="opcional"
              aria-invalid={invalido('correo')}
              aria-describedby={invalido('correo') ? 'ld-datos-error' : undefined}
            />
          </div>
          {/* DNI y distrito viven AQUÍ y no solo en el alta: los pide la línea
              "Faltan …" de abajo, y sin ellos ese aviso era un callejón sin
              salida (el 100% de los leads importados llega sin DNI). El DNI
              además es lo que desbloquea la conversión a cliente del portal. */}
          <div className="grid grid-cols-2 gap-2.5">
            <div className="space-y-1.5">
              <Label htmlFor="ld-dni">DNI</Label>
              <Input
                id="ld-dni"
                className="tabular-nums"
                inputMode="numeric"
                value={form.dni}
                placeholder="8 dígitos"
                aria-invalid={invalido('dni')}
                aria-describedby={invalido('dni') ? 'ld-datos-error' : undefined}
                // Se filtra a dígitos al teclear: el DNI peruano no tiene letras
                // y así el error de formato casi nunca llega a hacer falta.
                // El tope va DESPUÉS del filtro y no con maxLength, que cuenta
                // caracteres crudos: pegar "12.345.678" se habría cortado a
                // "12.345.6" → 6 dígitos guardados en silencio.
                onChange={(e) => {
                  setError(null)
                  setForm((f) => ({ ...f, dni: e.target.value.replace(/\D/g, '').slice(0, 8) }))
                }}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ld-distrito">Distrito</Label>
              <Input id="ld-distrito" value={form.distrito} onChange={campo('distrito')} placeholder="Miraflores" />
            </div>
          </div>
          {/* Chips en vez de <select>: la categoría se DESELECCIONA (volver a
              "sin dato" es legítimo) y son 3 opciones — mismo patrón del alta. */}
          <div className="space-y-1.5">
            <Label id="ld-categoria-label">Categoría de interés</Label>
            <div role="group" aria-labelledby="ld-categoria-label" className="flex flex-wrap gap-2">
              {CATEGORIAS_INTERES.map((c) => {
                const activa = form.categoria === c.k
                return (
                  <button
                    key={c.k}
                    type="button"
                    aria-pressed={activa}
                    onClick={() => setForm((f) => ({ ...f, categoria: activa ? null : c.k }))}
                    className={cn(
                      'cursor-pointer rounded-full border px-3 py-1.5 text-[11px] font-bold leading-none transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30',
                      activa
                        ? 'border-accent bg-accent text-accent-foreground'
                        : 'border-input bg-background text-muted-foreground hover:border-border-strong hover:text-foreground',
                    )}
                  >
                    {c.label}
                  </button>
                )
              })}
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ld-nota">Nota</Label>
            <Textarea id="ld-nota" value={form.nota} onChange={campo('nota')} placeholder="opcional" className="min-h-[56px]" />
          </div>
          {error && <p id="ld-datos-error" role="alert" className="text-xs font-semibold text-destructive">{error.mensaje}</p>}
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="outline" onClick={() => setEditando(false)}>
              Cancelar
            </Button>
            <Button size="sm" onClick={guardar}>
              Guardar
            </Button>
          </div>
        </div>
      ) : (
        <>
          {/* Orden comercial: capital → categoría → vendedor → contacto → resto.
              Las filas sin dato NO se listan con '—': se colapsan abajo en una
              sola línea accionable ("Faltan …" + Completar). */}
          <dl className="mt-1.5">
            {l.monto_estimado != null && (
              <Fila label="Capital estimado">
                <span className="font-extrabold tabular-nums text-primary">{money(l.monto_estimado, l.moneda)}</span>
              </Fila>
            )}
            {l.categoria_interes && (
              <Fila label="Categoría">Inversión · {CAT_LABEL[l.categoria_interes]}</Fila>
            )}
            <Fila label="Vendedor">
              {puedeReasignar ? (
                <Select
                  aria-label="Reasignar vendedor"
                  value={l.vendedor_id ?? ''}
                  onChange={(e) => onReasignar(e.target.value)}
                  className="h-8 text-xs"
                >
                  <option value="">Sin asignar (parkeado)</option>
                  {vendedores.map((m) => (
                    <option key={m.perfil_id} value={m.perfil_id}>
                      {m.nombre_completo}
                    </option>
                  ))}
                </Select>
              ) : l.vendedor_nombre ? (
                <span className="inline-flex items-center gap-1.5">
                  <Avatar nombre={l.vendedor_nombre} className="size-5 text-[8px]" />
                  {l.vendedor_nombre}
                </span>
              ) : (
                <Badge color="var(--warning)">Sin asignar (parkeado)</Badge>
              )}
            </Fila>
            <Fila label="Teléfono">
              <span className="tabular-nums">{l.telefono}</span>
            </Fila>
            {/*
              La fila del segundo número se dibuja SIEMPRE, tenga o no dato.
              Antes solo aparecía cuando había número, y eso dejaba al vendedor
              sin saber si el CRM se había comido algo o si el origen nunca lo
              dio — la duda exacta que Miguel quería quitar (2026-08-26). Tres
              estados, y ninguno es un hueco:
                · número bueno  → marcable y con WhatsApp si es móvil
                · texto ilegible → tal como llegó, marcado «sin validar»
                · nada          → dicho con todas las letras
            */}
            <Fila label="Teléfono alternativo">
              <SegundoNumero
                numero={l.telefono_alternativo ?? null}
                crudo={l.telefono_alternativo_crudo ?? null}
              />
            </Fila>
            {l.correo && <Fila label="Correo">{l.correo}</Fila>}
            {l.dni && (
              <Fila label="DNI">
                <span className="tabular-nums">{l.dni}</span>
              </Fila>
            )}
            {l.distrito && <Fila label="Distrito">{l.distrito}</Fila>}
            <Fila label="Origen">{origenLabel(l.origen)}</Fila>
            <Fila label="Creado">{fmtFecha(l.creado_en)}</Fila>
            {l.nota && <Fila label="Nota">{l.nota}</Fila>}
          </dl>
          {/* En un lead CERRADO la línea entera desaparece: era un vacío
              accionable cuyo "Completar" abría un formulario que el store
              rechaza. Un lead terminal es un acta, no una tarea pendiente. */}
          {activa && faltantes.length > 0 && (
            <div className="mt-1 flex items-center justify-between gap-2 rounded-lg bg-muted/40 px-2.5 py-1.5">
              <p className="min-w-0 text-[11px] text-muted-foreground">
                {faltantes.length === 1 ? 'Falta' : 'Faltan'} {listarFaltantes(faltantes)}
              </p>
              {escribe && (
                <Button size="xs" variant="ghost" onClick={empezar}>
                  <Pencil /> Completar
                </Button>
              )}
            </div>
          )}
        </>
      )}
    </section>
  )
}

// ── Timeline + composer ───────────────────────────────────────────────────────

const CLASE_HITO =
  'relative z-[1] grid size-7 shrink-0 place-items-center rounded-full border border-border bg-card text-muted-foreground [&_svg]:size-3.5'

// Tope de entradas visibles por defecto: el resto queda tras "Ver anteriores".
// El historial de un lead trabajado meses crece sin cota; sin tope el scroll
// interno se vuelve interminable (problema reportado 2026-07-17).
const TOPE_TIMELINE = 8

/** Una actividad suelta del timeline (hito + título + detalle + autor/tiempo). */
function FilaActividad({ a, ahora }: { a: Actividad; ahora: number }) {
  const Icono = ICONO_ACTIVIDAD[a.tipo]
  const esConversion = a.tipo === 'conversion'
  return (
    <li className="flex gap-2.5">
      <span className={cn(CLASE_HITO, esConversion && 'border-primary/30 text-primary')}>
        <Icono aria-hidden />
      </span>
      <div className="min-w-0 flex-1 pt-0.5">
        <p className="text-xs font-bold text-foreground">{TIPOS_ACTIVIDAD[a.tipo]}</p>
        {a.detalle && <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">{a.detalle}</p>}
        <p className="mt-0.5 text-[11px] text-muted-foreground/80">
          {a.autor_nombre} · {haceRelativo(a.creado_en, ahora)}
        </p>
      </div>
    </li>
  )
}

/** Racha colapsada de cambios de etapa: resumen contraído + expandir a la lista. */
function GrupoEtapa({ items, ahora }: { items: Actividad[]; ahora: number }) {
  const [abierto, setAbierto] = useState(false)
  const reciente = items[0]
  if (!reciente) return null
  if (abierto) {
    return (
      <>
        {items.map((a) => (
          <FilaActividad key={a.id} a={a} ahora={ahora} />
        ))}
        <li className="flex gap-2.5">
          <span className="w-7 shrink-0" aria-hidden />
          <button
            type="button"
            onClick={() => setAbierto(false)}
            className="cursor-pointer text-[11px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
          >
            Agrupar {items.length} cambios de etapa
          </button>
        </li>
      </>
    )
  }
  return (
    <li className="flex gap-2.5">
      <span className={CLASE_HITO}>
        <ArrowRightLeft aria-hidden />
      </span>
      <button
        type="button"
        onClick={() => setAbierto(true)}
        className="min-w-0 flex-1 cursor-pointer pt-0.5 text-left"
        aria-label={`Ver los ${items.length} cambios de etapa`}
      >
        <p className="text-xs font-bold text-foreground">{items.length} cambios de etapa</p>
        {reciente.detalle && (
          <p className="mt-0.5 truncate text-xs leading-relaxed text-muted-foreground">
            Último: {reciente.detalle}
          </p>
        )}
        <p className="mt-0.5 text-[11px] text-muted-foreground/80">
          {reciente.autor_nombre} · {haceRelativo(reciente.creado_en, ahora)} · toca para ver todos
        </p>
      </button>
    </li>
  )
}

function Timeline({ l, escribe, activa }: { l: Lead; escribe: boolean; activa: boolean }) {
  const { actividadesDe, registrarActividad } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  const acts = actividadesDe(l.id)
  const items = useMemo(() => agruparTimeline(acts), [acts])
  const [verTodo, setVerTodo] = useState(false)
  const visibles = verTodo ? items : items.slice(0, TOPE_TIMELINE)
  const ocultos = items.length - visibles.length
  const [tipo, setTipo] = useState<TipoActividadManual>('llamada_realizada')
  const [detalle, setDetalle] = useState('')
  // La sección se abre mayormente para LEER el historial: el composer vive
  // plegado tras una fila con aspecto de input y se despliega a un click.
  const [componiendo, setComponiendo] = useState(false)

  const registrar = () => {
    const res = registrarActividad(l.id, tipo, detalle)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    setDetalle('')
    setComponiendo(false)
    // NADA EN SILENCIO: un contacto de conversación sube la etapa por su cuenta
    // (lib/avance-automatico). El resto del CRM ya lo canta (`avisoDe` de
    // contacto.tsx) y aquí se tiraba el dato: el asesor veía moverse el stepper
    // sin saber por qué. Mismo formato "hecho · hecho" y mismo orden.
    const partes = ['Actividad registrada']
    if (res.avance) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
    toast.success(`${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}`)
  }

  return (
    <section aria-label="Actividad del lead">
      <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Actividad</h3>

      {escribe && activa && !componiendo && (
        <button
          type="button"
          onClick={() => setComponiendo(true)}
          className="mt-2 flex w-full cursor-pointer items-center gap-2 rounded-xl border border-border bg-muted/40 px-3 py-2 text-left text-xs text-muted-foreground transition-colors hover:bg-muted/60 hover:text-foreground"
        >
          <Send className="size-3.5 shrink-0" aria-hidden /> Registrar actividad…
        </button>
      )}

      {escribe && activa && componiendo && (
        <div className="mt-2 space-y-2 rounded-xl border border-border bg-muted/40 p-3">
          <Select
            aria-label="Tipo de actividad"
            value={tipo}
            onChange={(e) => setTipo(e.target.value as TipoActividadManual)}
            className="h-8 text-xs"
          >
            {TIPOS_MANUALES.map((t) => (
              <option key={t} value={t}>
                {TIPOS_ACTIVIDAD[t]}
              </option>
            ))}
          </Select>
          <Textarea
            aria-label="Detalle de la actividad"
            value={detalle}
            onChange={(e) => setDetalle(e.target.value)}
            placeholder="Detalle (opcional)…"
            className="min-h-[56px] text-xs"
            autoFocus
          />
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="ghost" onClick={() => setComponiendo(false)}>
              Cancelar
            </Button>
            <Button size="sm" onClick={registrar}>
              <Send /> Registrar
            </Button>
          </div>
        </div>
      )}

      <ol className="relative mt-3 space-y-4 before:absolute before:inset-y-2 before:left-[13px] before:w-px before:bg-border">
        {visibles.map((it) =>
          it.clase === 'act' ? (
            <FilaActividad key={it.act.id} a={it.act} ahora={ahora} />
          ) : (
            <GrupoEtapa key={it.id} items={it.items} ahora={ahora} />
          ),
        )}
        {/* Tope: el resto del historial queda a un clic, para no crecer sin cota */}
        {ocultos > 0 && (
          <li className="flex gap-2.5">
            <span className="grid size-7 shrink-0 place-items-center text-muted-foreground [&_svg]:size-3.5">
              <MoreHorizontal aria-hidden />
            </span>
            <button
              type="button"
              onClick={() => setVerTodo(true)}
              className="cursor-pointer pt-1 text-left text-[11px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
            >
              Ver {ocultos} {ocultos === 1 ? 'entrada anterior' : 'entradas anteriores'}
            </button>
          </li>
        )}
        {verTodo && items.length > TOPE_TIMELINE && (
          <li className="flex gap-2.5">
            <span className="w-7 shrink-0" aria-hidden />
            <button
              type="button"
              onClick={() => setVerTodo(false)}
              className="cursor-pointer pt-1 text-left text-[11px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
            >
              Ver menos
            </button>
          </li>
        )}
        {/* La creación NO es una actividad: ítem estático al final con creado_en */}
        <li className="flex gap-2.5">
          <span className={CLASE_HITO}>
            <Sparkles aria-hidden />
          </span>
          <div className="min-w-0 flex-1 pt-0.5">
            <p className="text-xs font-bold text-foreground">Lead creado</p>
            <p className="mt-0.5 text-[11px] text-muted-foreground/80">
              {fmtFecha(l.creado_en)} · {haceRelativo(l.creado_en, ahora)}
            </p>
          </div>
        </li>
      </ol>
    </section>
  )
}

// ── Diálogos de cierre ────────────────────────────────────────────────────────

const RE_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
// Espejo del formato de documento del portal (documento-core). Solo para feedback
// inmediato; la frontera real (edge + CHECK de BD) revalida.
const RE_DOCUMENTO: Record<TipoDocumentoCliente, { re: RegExp; err: string }> = {
  DNI: { re: /^\d{8}$/, err: 'El DNI debe tener 8 dígitos' },
  CE: { re: /^\d{9,12}$/, err: 'El Carné de Extranjería debe tener entre 9 y 12 dígitos' },
  PASAPORTE: { re: /^[A-Z0-9]{6,12}$/, err: 'El pasaporte debe tener entre 6 y 12 caracteres' },
}

interface IdentidadSugerida {
  nombres: string
  apellidoPaterno: string
  apellidoMaterno: string
}

/**
 * El lead todavía conserva un único nombre libre. La conversión propone una
 * separación útil para no obligar a reescribirlo, pero NO la toma como verdad:
 * el vendedor confirma los tres campos antes de crear el cliente de pagos.
 */
function sugerirIdentidadDelLead(nombreCompleto: string): IdentidadSugerida {
  const partes = normNombrePersona(nombreCompleto).split(' ').filter(Boolean)
  if (partes.length < 2) {
    return { nombres: partes[0] ?? '', apellidoPaterno: '', apellidoMaterno: '' }
  }
  if (partes.length === 2) {
    return { nombres: partes[0]!, apellidoPaterno: partes[1]!, apellidoMaterno: '' }
  }
  return {
    nombres: partes.slice(0, -2).join(' '),
    apellidoPaterno: partes.at(-2)!,
    apellidoMaterno: partes.at(-1)!,
  }
}

/** Exportado SOLO para los tests del componente (se monta solo, con la API mockeada). */
export function DialogConvertir({ l, onClose }: { l: Lead; onClose: () => void }) {
  const { convertir, convertirExterno, recargar } = useCRMData()
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  // Cómo se llama HOY la pantalla donde se corrigen los datos del cliente: la
  // 'mi-cartera' unificada, rotulada "Mi cartera" para el vendedor y "Cartera"
  // para quien supervisa (mismo criterio que el sidebar). Los avisos de abajo
  // la nombran así para que el asesor encuentre el ítem tal cual en su menú.
  const rotuloCartera = can(yo?.rol, 'verEquipo') ? 'Cartera' : 'Mi cartera'

  const confirmarDemo = () => {
    const res = convertir(l.id)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    onClose()
    toast.success(`${l.nombre_completo} ahora es cliente (demo)`)
  }

  // ── Conversión REAL: crea la cuenta del cliente en el portal (edge) ──
  const [correo, setCorreo] = useState(l.correo ?? '')
  const [tipoDoc, setTipoDoc] = useState<TipoDocumentoCliente>('DNI')
  const [documento, setDocumento] = useState(l.dni ?? '')
  const [domicilio, setDomicilio] = useState('')
  const [nombres, setNombres] = useState(() => sugerirIdentidadDelLead(l.nombre_completo).nombres)
  const [apellidoPaterno, setApellidoPaterno] = useState(
    () => sugerirIdentidadDelLead(l.nombre_completo).apellidoPaterno,
  )
  const [apellidoMaterno, setApellidoMaterno] = useState(
    () => sugerirIdentidadDelLead(l.nombre_completo).apellidoMaterno,
  )
  // Bancarios (PEN = columnas base, USD = sufijo _usd) — el cliente convertido
  // los necesita IGUAL que el del alta directa: sin cuenta no hay dónde
  // depositarle los intereses (hallazgo de Miguel 2026-07-16).
  const [pen, setPen] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  const [usd, setUsd] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // El flujo arranca en «¿Dónde invirtió?» (destino): Avance sigue su camino de
  // siempre (cliente en el portal → contrato); una COOPERATIVA va al formulario
  // corto del cierre externo (sin portal, sin correo, sin contrato).
  const [paso, setPaso] = useState<'destino' | 'convertir' | 'coop' | 'contrato'>('destino')
  const [coop, setCoop] = useState<Cooperativa>('qorilazo')
  // ── Cierre en cooperativa: lo que llena el vendedor ──
  // Monto REAL invertido (no el estimado del lead: ése era una promesa, éste es
  // el cierre). Nombre precargado del lead, editable.
  // NO se pregunta la moneda: en cooperativas solo se invierte en SOLES (regla
  // de negocio, 2026-08-12) y el servidor rechaza cualquier otra.
  const [montoCoop, setMontoCoop] = useState('')
  const [nombreCoop, setNombreCoop] = useState(l.nombre_completo)
  // El n.º de operación del depósito es la PRUEBA del cierre: obligatorio, único
  // por cooperativa, y una vez enviado solo gerencia lo corrige.
  const [transaccionCoop, setTransaccionCoop] = useState('')
  const [referenciaCoop, setReferenciaCoop] = useState('')
  const [venceCoop, setVenceCoop] = useState('')
  const [notaCoop, setNotaCoop] = useState('')
  // Qué campo del formulario coop falló: enlaza el error (cx-error) al input
  // culpable con aria-invalid/aria-describedby — sin esto, quien navega campo
  // a campo oye el alert pero no sabe cuál corregir (hallazgo M2 a11y).
  const [campoErrorCoop, setCampoErrorCoop] = useState<
    'monto' | 'documento' | 'nombre' | 'transaccion' | 'vence' | null
  >(null)
  /** Las tarjetas del paso «¿Dónde invirtió?», para devolverles el foco al
   *  pulsar «Volver» desde el formulario de la cooperativa. */
  const refTarjetaCoop = useRef(new Map<Cooperativa, HTMLButtonElement>())
  const cierreExternoMut = useConvertirLeadExterno()
  const [perfilId, setPerfilId] = useState<string | null>(null)
  /** El documento YA era cliente: se enlazó y sus bancarios NO se tocaron → hay
   *  que decírselo al asesor ANTES de seguir (acaba de llenar unos que no van). */
  const [avisoYaExistia, setAvisoYaExistia] = useState(false)
  const [domicilioAccion, setDomicilioAccion] = useState<'completado' | 'conservado'>('conservado')
  /**
   * ¿El cliente enlazado quedó en MI cartera? (`null` = no se pudo comprobar).
   *
   * La edge NO cambia el `asesor_perfil_id` de un cliente que ya existía: el
   * lead se enlaza, pero el cliente sigue siendo del asesor que lo tenía. Sin
   * esto la ficha prometía a ciegas un contrato que `public.crear_contrato`
   * rechaza («Solo puedes crear contratos para clientes de tu cartera») después
   * de hacerle llenar el formulario entero.
   */
  const [clienteEnMiCartera, setClienteEnMiCartera] = useState<boolean | null>(null)
  const refAviso = useRef<HTMLDivElement>(null)

  // El drawer normalmente se desmonta al cerrar, pero si navegan directo a otro
  // lead sin desmontarlo, la identidad sugerida debe pertenecer al lead nuevo.
  useEffect(() => {
    const identidad = sugerirIdentidadDelLead(l.nombre_completo)
    setNombres(identidad.nombres)
    setApellidoPaterno(identidad.apellidoPaterno)
    setApellidoMaterno(identidad.apellidoMaterno)
  }, [l.id, l.nombre_completo])

  // Al enviar, el botón se deshabilita y el foco cae a <body>; que vuelva a
  // entrar al diálogo NO puede quedar en manos del rescate implícito de Radix
  // cuando lo que se pinta es una advertencia que hay que leer.
  useEffect(() => {
    if (avisoYaExistia) refAviso.current?.focus()
  }, [avisoYaExistia])

  // Cierre BLINDADO: Radix cierra con Esc/overlay incondicionalmente, y un
  // cierre con el envío en vuelo perdería el resultado de una operación que ya
  // está corriendo en el servidor — mismo patrón que clientes.tsx.
  const cerrarSeguro = () => {
    if (enviando) return
    onClose()
  }

  const confirmarReal = async () => {
    if (enviando) return // guard anti doble-submit
    setError(null)
    if (!l.vendedor_id) {
      setError('Asigna el lead a un analista antes de convertirlo')
      return
    }
    const correoLimpio = correo.trim().toLowerCase()
    if (!RE_CORREO.test(correoLimpio)) {
      setError('Ingresa un correo válido — es la cuenta de acceso del cliente')
      return
    }
    const nombresLimpios = normNombrePersona(nombres)
    const apellidoPaternoLimpio = normNombrePersona(apellidoPaterno)
    const apellidoMaternoLimpio = normNombrePersona(apellidoMaterno)
    if (!nombresLimpios || !apellidoPaternoLimpio || !apellidoMaternoLimpio) {
      setError('Completa los nombres y los dos apellidos del cliente antes de crear su cuenta.')
      return
    }
    const apellidos = `${apellidoPaternoLimpio} ${apellidoMaternoLimpio}`
    const docLimpio = documento.trim().toUpperCase()
    if (!docLimpio) {
      setError('El documento del cliente es obligatorio')
      return
    }
    if (!RE_DOCUMENTO[tipoDoc].re.test(docLimpio)) {
      setError(RE_DOCUMENTO[tipoDoc].err)
      return
    }
    const domicilioValidado = validarDomicilioLegal(domicilio)
    if (!domicilioValidado.ok) {
      setError(domicilioValidado.error)
      return
    }
    // Bancarios ANTES de tocar el servidor (regla "al menos una cuenta", igual
    // que el alta del portal): si no validan, NO se crea la cuenta ni sale el
    // correo de bienvenida — no se empieza algo que quedaría a medias. Este
    // chequeo es solo para dar el error SIN ida y vuelta: la frontera de verdad
    // es la edge, que revalida el mismo bloque (_shared/bancarios.mjs).
    const valBanc = validarBancariosForm(pen, usd)
    if (!valBanc.ok) {
      setError(valBanc.error)
      return
    }
    setEnviando(true)
    try {
      // UN SOLO PASO: la edge valida los bancarios, crea la cuenta CON sus
      // cuentas de depósito en el mismo INSERT, manda el correo y cierra el
      // lead. Hasta 2026-07-27 los bancarios iban en un UPDATE posterior desde
      // aquí, y si ese segundo paso fallaba quedaba un cliente real —con su
      // correo ya enviado— sin cuenta donde cobrar. Ese estado ya no existe.
      const r = await convertirLead({
        lead_id: l.id,
        correo: correoLimpio,
        tipo_documento: tipoDoc,
        documento: docLimpio,
        nombre_completo: `${apellidos} ${nombresLimpios}`,
        apellidos,
        nombres: nombresLimpios,
        telefono: l.telefono,
        domicilio: domicilioValidado.valor,
        bancarios: { pen, usd },
      })
      // El lead ya quedó convertido en el servidor: el pipeline debe reflejarlo.
      const recargaConfirmada = await recargar()
      if (!recargaConfirmada) {
        toast.warning('La conversión quedó confirmada, pero la cartera no pudo actualizarse. Recarga la pantalla antes de continuar.')
      }
      setPerfilId(r.perfil_id)
      setDomicilioAccion(r.domicilio_accion)
      // El asesor acaba de llenar datos legales y bancarios que, por el dedup,
      // pueden no reemplazar lo que el cliente ya tenía. Un toast de éxito ahí
      // le haría creer que modificó esas fuentes: se para el flujo y se explica.
      if (r.ya_existia) {
        // Antes de hablar, PREGUNTAR: el aviso cambia por completo según si el
        // cliente enlazado es de este asesor o de otro, y eso solo lo sabe el
        // servidor. `null` = no se pudo comprobar y se dice tal cual.
        setClienteEnMiCartera(await esClienteDeMiCartera(r.perfil_id))
        setAvisoYaExistia(true)
        return
      }
      toast.success(
        `${l.nombre_completo} ahora es cliente${r.email_enviado ? ' — correo de bienvenida enviado' : ''}`,
      )
      // Seguido: el paso de crear el contrato (sin salir del CRM).
      setPaso('contrato')
    } catch (e) {
      setError(e instanceof CrmApiError ? e.message : 'No se pudo convertir el lead')
    } finally {
      setEnviando(false)
    }
  }

  // (Ya no hay estado "cliente creado sin bancarios": la edge los escribe en el
  //  mismo INSERT del cliente, así que o se crea con su cuenta o no se crea.)

  // ── Cierre en COOPERATIVA (Qorilazo/Prodelco) ──────────────────────────────
  // No crea usuario ni manda correo: registra la foto del cierre y el lead pasa
  // a convertido — cuenta en la cuota y en la conversión igual que Avance. La
  // fecha es automática (hoy): sin retro-datar, el mes del cierre es el real.
  const confirmarCoop = async () => {
    if (enviando) return
    setError(null)
    setCampoErrorCoop(null)
    if (!l.vendedor_id) {
      setError('Asigna el lead a un analista antes de convertirlo')
      return
    }
    const monto = Number(montoCoop)
    if (!montoCoop.trim() || !Number.isFinite(monto) || monto <= 0) {
      setCampoErrorCoop('monto')
      setError('Ingresa el monto REAL invertido — es lo que suma a tu cuota')
      return
    }
    // Tolerancia y no igualdad exacta: `10000.03 * 100` da 1000003.0000000001
    // en coma flotante y este aviso saltaba sobre un monto válido.
    if (Math.abs(Math.round(monto * 100) - monto * 100) >= 1e-6) {
      setCampoErrorCoop('monto')
      setError('El monto admite como máximo 2 decimales')
      return
    }
    const docLimpio = documento.trim().toUpperCase()
    if (!docLimpio) {
      setCampoErrorCoop('documento')
      setError('El documento es obligatorio — es el ancla de identidad del cierre')
      return
    }
    if (!RE_DOCUMENTO[tipoDoc].re.test(docLimpio)) {
      setCampoErrorCoop('documento')
      setError(RE_DOCUMENTO[tipoDoc].err)
      return
    }
    const nombreLimpio = nombreCoop.trim()
    if (!nombreLimpio) {
      setCampoErrorCoop('nombre')
      setError('El nombre completo es obligatorio')
      return
    }
    const transaccionLimpia = transaccionCoop.trim()
    if (!transaccionLimpia) {
      setCampoErrorCoop('transaccion')
      setError('El N.° de operación del depósito es obligatorio — es la prueba del cierre')
      return
    }
    // Hoy EN LIMA (en-CA = YYYY-MM-DD): a las 7 pm de Lima el reloj UTC ya va
    // por mañana y compararía mal — el servidor valida con el reloj de Lima.
    const hoyLima = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' })
      .format(new Date())
    if (venceCoop && venceCoop <= hoyLima) {
      setCampoErrorCoop('vence')
      setError('El vencimiento de la inversión debe ser una fecha futura')
      return
    }

    if (esDemo) {
      const res = convertirExterno(l.id, {
        cooperativa: coop,
        monto,
        numeroTransaccion: transaccionLimpia,
      })
      if (!res.ok) {
        if (res.error) setError(res.error)
        return
      }
      onClose()
      toast.success(`${nombreLimpio} cerrado en ${INFO_COOPERATIVA[coop].nombre} (demo)`)
      return
    }

    setEnviando(true)
    try {
      await cierreExternoMut.mutateAsync({
        leadId: l.id,
        cooperativa: coop,
        monto,
        moneda: 'PEN',
        documentoTipo: tipoDoc,
        documento: docLimpio,
        nombre: nombreLimpio,
        numeroTransaccion: transaccionLimpia,
        referencia: referenciaCoop.trim() || null,
        venceEn: venceCoop || null,
        nota: notaCoop.trim() || null,
      })
      // El lead ya quedó convertido en el servidor: el pipeline debe reflejarlo
      // (mismo patrón que la conversión Avance vía edge).
      await recargar()
      onClose()
      toast.success(
        `${nombreLimpio} cerrado en ${INFO_COOPERATIVA[coop].nombre} — ya cuenta en tu cuota y conversión`,
      )
    } catch (e) {
      setError(e instanceof CrmApiError ? e.message : 'No se pudo registrar el cierre en la cooperativa')
    } finally {
      setEnviando(false)
    }
  }

  // ── Cliente ya existente: ni los bancarios ni la ATRIBUCIÓN se movieron ─────
  // El enlace salió bien, pero no es el éxito que el asesor cree, y dos de las
  // promesas que este diálogo hacía antes eran falsas:
  //
  //  1. «actualízalas en Cartera → Corregir»: la policy `perfiles_analista_update`
  //     exige `creado_en > now() - 5h`. Un cliente que YA existía es más viejo
  //     que eso por definición → esa corrección no la puede hacer el asesor.
  //  2. «Continuar al contrato»: `public.crear_contrato` exige que el cliente
  //     sea de tu cartera (`asesor_perfil_id = auth.uid()`, o sin asesor y
  //     registrado por ti). La edge NO reasigna al cliente existente, así que si
  //     era de otro asesor la RPC lo rechaza — después de llenar el formulario.
  //
  // Ahora se PREGUNTA al servidor (esClienteDeMiCartera, misma regla exacta que
  // el gate de la RPC) y se dice la verdad de cada caso, con el camino real.
  if (avisoYaExistia && perfilId) {
    const esMio = clienteEnMiCartera === true
    const noEsMio = clienteEnMiCartera === false
    return (
      <Dialog open onClose={onClose} ariaLabel="Convertir a cliente">
        <DialogHeader>
          <DialogTitle>{primerNombre(l.nombre_completo)} ya era cliente</DialogTitle>
        </DialogHeader>
        <DialogBody className="space-y-3">
          {/* Foco AL AVISO, no al botón que lo despacha: este diálogo existe
              para frenar al asesor, y autoenfocar "Continuar" lo dejaría a un
              Enter de saltárselo sin leerlo. tabIndex=-1 = destino de foco
              programático, nunca parada del tabulador. */}
          <div
            ref={refAviso}
            tabIndex={-1}
            role="alert"
            className="rounded-xl border border-warning/40 bg-warning/10 p-3 text-xs font-semibold text-warning-text outline-none"
          >
            Ese documento ya tenía cuenta en el portal: el lead quedó enlazado a ella y cerrado
            como ganado, y se conservaron las cuentas bancarias que el cliente ya tenía registradas.
            {' '}{domicilioAccion === 'completado'
              ? 'Su domicilio estaba vacío y se completó con el que ingresaste.'
              : 'También se conservó el domicilio legal que ya estaba registrado.'}
            {noEsMio ? ' El cliente NO pasó a tu cartera.' : ''}
          </div>
          <p className="text-xs leading-relaxed text-muted-foreground">
            Lo que escribiste en el formulario no reemplaza las cuentas bancarias
            {domicilioAccion === 'conservado' ? ' ni el domicilio existente' : ''} — sobreescribirlos a ciegas
            podría alterar su identidad legal o desviarle sus intereses. Si ya no son correctos,
            verifícalos antes del contrato o próximo pago: desde “{rotuloCartera} → Corregir” solo
            se pueden cambiar para un cliente que registraste tú hace menos de 5 horas; si no,
            pídeselo a Gerencia.
          </p>
          {noEsMio && (
            <p className="text-xs leading-relaxed text-muted-foreground">
              El cliente sigue a nombre del asesor que lo tenía, así que no lo verás en
              “{rotuloCartera}” ni podrás crearle el contrato desde aquí: el servidor lo
              rechazaría. Pídele a Gerencia que te lo reasigne en el portal y créale el contrato
              después.
            </p>
          )}
          {clienteEnMiCartera === null && (
            <p className="text-xs leading-relaxed text-muted-foreground">
              No pudimos comprobar si el cliente quedó en tu cartera. Puedes intentar el
              contrato: si el servidor lo rechaza es porque sigue a nombre de otro asesor, y
              entonces hay que pedirle a Gerencia que te lo reasigne.
            </p>
          )}
        </DialogBody>
        <DialogFooter>
          <Button variant={noEsMio ? 'default' : 'outline'} size="sm" onClick={onClose}>
            {noEsMio ? 'Entendido' : 'Cerrar'}
          </Button>
          {/* El botón solo aparece cuando el contrato es POSIBLE (o cuando no
              se pudo comprobar). Con el cliente en otra cartera se retira: era
              la puerta que llevaba a un formulario largo y a un rechazo. */}
          {!noEsMio && (
            <Button
              size="sm"
              onClick={() => {
                setAvisoYaExistia(false)
                setPaso('contrato')
              }}
            >
              {esMio ? 'Continuar al contrato' : 'Intentar el contrato'}
            </Button>
          )}
        </DialogFooter>
      </Dialog>
    )
  }

  // Paso 2: contrato del cliente recién creado (reusa la RPC del portal).
  if (paso === 'contrato' && perfilId) {
    return (
      <Dialog open onClose={onClose} ariaLabel="Crear contrato del cliente">
        <ContratoNuevo
          clienteId={perfilId}
          clienteNombre={l.nombre_completo}
          montoSugerido={l.monto_estimado ?? null}
          monedaSugerida={l.moneda}
          onCreado={onClose}
          onOmitir={onClose}
        />
      </Dialog>
    )
  }

  // ── Paso 0: ¿DÓNDE invirtió? ────────────────────────────────────────────────
  // Avance sigue intacto su camino de siempre; una cooperativa NO crea usuario
  // de portal ni manda correo — solo registra el cierre, que igual cuenta en la
  // cuota y en la conversión del asesor.
  if (paso === 'destino') {
    return (
      <Dialog open onClose={onClose} ariaLabel="Convertir lead">
        <DialogHeader>
          <DialogTitle>¿Dónde invirtió?</DialogTitle>
          <DialogDescription>
            {l.nombre_completo} pasará a {ETAPA_INFO.convertido.label}. Elige la empresa donde
            cerró su inversión:
          </DialogDescription>
        </DialogHeader>
        <DialogBody className="space-y-2">
          <button
            type="button"
            className="w-full rounded-xl border border-border bg-card p-3 text-left transition-colors hover:border-primary/60 hover:bg-primary/5"
            onClick={() => setPaso('convertir')}
          >
            <span className="block text-sm font-bold text-foreground">Avance Corp</span>
            <span className="block text-xs text-muted-foreground">
              Crea su cuenta del portal, le llega el correo de bienvenida y sigues al contrato.
            </span>
          </button>
          {(['qorilazo', 'prodelco'] as const).map((c) => (
            <button
              key={c}
              ref={(el) => {
                if (el) refTarjetaCoop.current.set(c, el)
                else refTarjetaCoop.current.delete(c)
              }}
              type="button"
              className="w-full rounded-xl border border-border bg-card p-3 text-left transition-colors hover:border-primary/60 hover:bg-primary/5"
              onClick={() => {
                setCoop(c)
                setPaso('coop')
              }}
            >
              <span className="flex items-center gap-2">
                <span className="text-sm font-bold text-foreground">{INFO_COOPERATIVA[c].nombre}</span>
                <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-bold tracking-wide', INFO_COOPERATIVA[c].chipClase)}>
                  {INFO_COOPERATIVA[c].corto}
                </span>
              </span>
              <span className="block text-xs text-muted-foreground">
                Solo se registra el cierre — sin portal ni correo. Cuenta igual en tu cuota y conversión.
              </span>
            </button>
          ))}
        </DialogBody>
        {/* ⚠️ LA `key` NO ES DECORATIVA. El paso «coop» tiene otro <Button> en
            esta misma posición, así que React reconcilia POR ÍNDICE y reutiliza
            el MISMO nodo del DOM: al pulsar «Volver» el foco no se movía y el
            botón que quedaba debajo del dedo pasaba a llamarse «Cancelar» y a
            ejecutar `onClose()`. Un segundo Enter —el de quien no oyó nada y
            cree que no respondió— cerraba el diálogo y se llevaba el monto, el
            documento y el N.° de operación ya escritos. Con `key` distintas el
            nodo se desmonta de verdad y el nombre accesible nunca cambia bajo
            el foco (WCAG 4.1.2). Mismo bug, misma cura que en cerrar-tarea.tsx. */}
        <DialogFooter>
          <Button key="cancelar-destino" variant="outline" size="sm" onClick={onClose}>
            Cancelar
          </Button>
        </DialogFooter>
      </Dialog>
    )
  }

  // ── Cierre en COOPERATIVA: el formulario corto ─────────────────────────────
  if (paso === 'coop') {
    const infoCoop = INFO_COOPERATIVA[coop]
    return (
      <Dialog open onClose={cerrarSeguro} ariaLabel={`Cerrar en ${infoCoop.nombre}`}>
        <DialogHeader>
          <DialogTitle>
            Cerrar en {infoCoop.nombre}
            {esDemo ? ' (demo)' : ''}
          </DialogTitle>
          <DialogDescription>
            Sin portal ni correo: queda el registro del cierre y {primerNombre(l.nombre_completo)}{' '}
            pasa a {ETAPA_INFO.convertido.label}. El monto suma a tu cuota del mes.
          </DialogDescription>
        </DialogHeader>
        <DialogBody className="space-y-3">
          {/* Sin selector de moneda: en cooperativas solo se invierte en soles,
              así que se dice en el rótulo en vez de ofrecer una decisión que no
              existe (y que el servidor rechazaría). */}
          <div className="space-y-1.5">
            <Label htmlFor="cx-monto">Monto REAL invertido (S/)</Label>
            <Input
              id="cx-monto"
              type="number"
              inputMode="decimal"
              min="0"
              step="0.01"
              value={montoCoop}
              onChange={(e) => setMontoCoop(e.target.value)}
              placeholder="10000.00"
              disabled={enviando}
              aria-invalid={campoErrorCoop === 'monto'}
              aria-describedby={campoErrorCoop === 'monto' ? 'cx-error' : undefined}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cx-nombre">Nombre completo</Label>
            <Input
              id="cx-nombre"
              value={nombreCoop}
              onChange={(e) => setNombreCoop(e.target.value)}
              disabled={enviando}
              aria-invalid={campoErrorCoop === 'nombre'}
              aria-describedby={campoErrorCoop === 'nombre' ? 'cx-error' : undefined}
            />
          </div>
          <div className="grid grid-cols-[132px_1fr] gap-2.5">
            <div className="space-y-1.5">
              <Label htmlFor="cx-tipodoc">Tipo doc.</Label>
              <Select
                id="cx-tipodoc"
                value={tipoDoc}
                onChange={(e) => setTipoDoc(e.target.value as TipoDocumentoCliente)}
                disabled={enviando}
              >
                <option value="DNI">DNI</option>
                <option value="CE">C. Extranjería</option>
                <option value="PASAPORTE">Pasaporte</option>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="cx-doc">N° de documento</Label>
              <Input
                id="cx-doc"
                value={documento}
                onChange={(e) => setDocumento(e.target.value)}
                placeholder="Documento que registró la cooperativa"
                disabled={enviando}
                aria-invalid={campoErrorCoop === 'documento'}
                aria-describedby={campoErrorCoop === 'documento' ? 'cx-error' : undefined}
              />
            </div>
          </div>
          {/* LA PRUEBA del cierre. Va solo y arriba de los opcionales a propósito:
              no es un dato administrativo más, es lo que hace que este cierre se
              pueda contrastar. Una vez enviado, solo gerencia lo corrige. */}
          <div className="space-y-1.5">
            <Label htmlFor="cx-transaccion">N.° de operación del depósito</Label>
            <Input
              id="cx-transaccion"
              value={transaccionCoop}
              onChange={(e) => setTransaccionCoop(e.target.value)}
              placeholder="Código de la transferencia o del voucher"
              disabled={enviando}
              aria-invalid={campoErrorCoop === 'transaccion'}
              // La ayuda NO se pierde cuando hay error: es justo cuando más
              // falta hace. `aria-describedby` admite lista y el error sigue
              // teniendo su único id.
              aria-describedby={
                campoErrorCoop === 'transaccion'
                  ? 'cx-error cx-transaccion-ayuda'
                  : 'cx-transaccion-ayuda'
              }
            />
            <p id="cx-transaccion-ayuda" className="text-[11px] text-muted-foreground">
              Es lo que permite verificar el cierre. Después solo gerencia puede corregirlo.
            </p>
          </div>
          <div className="grid grid-cols-2 gap-2.5">
            <div className="space-y-1.5">
              <Label htmlFor="cx-ref">Certificado de la coop (opcional)</Label>
              <Input
                id="cx-ref"
                value={referenciaCoop}
                onChange={(e) => setReferenciaCoop(e.target.value)}
                placeholder="N° de contrato/certificado"
                disabled={enviando}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="cx-vence">Vencimiento (opcional)</Label>
              <Input
                id="cx-vence"
                type="date"
                value={venceCoop}
                onChange={(e) => setVenceCoop(e.target.value)}
                disabled={enviando}
                aria-invalid={campoErrorCoop === 'vence'}
                aria-describedby={campoErrorCoop === 'vence' ? 'cx-error' : undefined}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cx-nota">Nota (opcional)</Label>
            <Textarea
              id="cx-nota"
              rows={2}
              value={notaCoop}
              onChange={(e) => setNotaCoop(e.target.value)}
              disabled={enviando}
            />
          </div>
          {error && <p id="cx-error" role="alert" className="text-xs font-semibold text-destructive">{error}</p>}
        </DialogBody>
        <DialogFooter>
          <Button
            key="volver-coop"
            variant="outline"
            size="sm"
            disabled={enviando}
            onClick={() => {
              setError(null)
              setCampoErrorCoop(null)
              setPaso('destino')
              // El foco vuelve a la tarjeta de donde salió. Sin esto, Radix lo
              // rescata al tope del diálogo y hay que re-tabularlo entero.
              requestAnimationFrame(() => refTarjetaCoop.current.get(coop)?.focus())
            }}
          >
            Volver
          </Button>
          <Button size="sm" onClick={confirmarCoop} disabled={enviando}>
            <BadgeCheck /> {enviando ? 'Registrando…' : `Cerrar en ${infoCoop.corto}`}
          </Button>
        </DialogFooter>
      </Dialog>
    )
  }

  return (
    <Dialog open onClose={cerrarSeguro} ariaLabel="Convertir a cliente">
      <DialogHeader>
        <DialogTitle>Convertir a cliente{esDemo ? ' (demo)' : ''}</DialogTitle>
        <DialogDescription>
          {l.nombre_completo} pasará a {ETAPA_INFO.convertido.label}.
        </DialogDescription>
      </DialogHeader>

      {esDemo ? (
        <>
          <DialogBody className="space-y-2 text-xs leading-relaxed text-muted-foreground">
            <p>
              En producción, la conversión crea al{' '}
              <b className="text-foreground">cliente en el portal</b> y cierra el lead como ganado.
            </p>
            <p>En este modo demo solo se simula el cambio de estado — nada queda guardado de verdad.</p>
          </DialogBody>
          <DialogFooter>
            <Button variant="outline" size="sm" onClick={onClose}>Cancelar</Button>
            <Button size="sm" onClick={confirmarDemo}>
              <BadgeCheck /> Convertir (demo)
            </Button>
          </DialogFooter>
        </>
      ) : (
        <>
          <DialogBody className="space-y-3">
            <p className="text-xs leading-relaxed text-muted-foreground">
              Se creará la <b className="text-foreground">cuenta del cliente en el portal</b> y se le
              enviará su correo de bienvenida con el acceso. Revisa y completa sus datos:
            </p>
            <section className="rounded-xl border border-primary/20 bg-primary/[0.035] p-3" aria-label="Identidad para pagos">
              <div className="flex items-start gap-2.5">
                <span className="mt-0.5 grid size-7 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary [&_svg]:size-3.5">
                  <ArrowRightLeft aria-hidden />
                </span>
                <div className="min-w-0">
                  <p className="text-xs font-bold text-foreground">Revisión de identidad para pagos</p>
                  <p className="mt-0.5 text-[11px] leading-relaxed text-muted-foreground">
                    Se cargó una sugerencia desde el lead. Confirma que cada parte esté en el campo correcto.
                  </p>
                </div>
              </div>
              <div className="mt-2 border-l-2 border-primary/25 pl-2.5">
                <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Registrado en el lead</p>
                <p className="mt-0.5 truncate text-xs font-semibold text-foreground" title={l.nombre_completo}>
                  {l.nombre_completo}
                </p>
              </div>
            </section>
            <div className="grid grid-cols-2 gap-2.5">
              <div className="col-span-2 space-y-1.5">
                <Label htmlFor="cv-nombres">Nombres</Label>
                <Input
                  id="cv-nombres"
                  value={nombres}
                  onChange={(e) => setNombres(e.target.value)}
                  placeholder="Ej. MARÍA JOSÉ"
                  autoComplete="given-name"
                  disabled={enviando}
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cv-apellido-paterno">Apellido paterno</Label>
                <Input
                  id="cv-apellido-paterno"
                  value={apellidoPaterno}
                  onChange={(e) => setApellidoPaterno(e.target.value)}
                  placeholder="Ej. PÉREZ"
                  autoComplete="family-name"
                  disabled={enviando}
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cv-apellido-materno">Apellido materno</Label>
                <Input
                  id="cv-apellido-materno"
                  value={apellidoMaterno}
                  onChange={(e) => setApellidoMaterno(e.target.value)}
                  placeholder="Ej. ROJAS"
                  disabled={enviando}
                />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="cv-correo">Correo del cliente</Label>
              <Input
                id="cv-correo"
                type="email"
                value={correo}
                onChange={(e) => setCorreo(e.target.value)}
                placeholder="cliente@correo.com"
                disabled={enviando}
              />
            </div>
            <div className="grid grid-cols-[132px_1fr] gap-2.5">
              <div className="space-y-1.5">
                <Label htmlFor="cv-tipodoc">Tipo doc.</Label>
                <Select
                  id="cv-tipodoc"
                  value={tipoDoc}
                  onChange={(e) => setTipoDoc(e.target.value as TipoDocumentoCliente)}
                  disabled={enviando}
                >
                  <option value="DNI">DNI</option>
                  <option value="CE">C. Extranjería</option>
                  <option value="PASAPORTE">Pasaporte</option>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cv-doc">N° de documento</Label>
                <Input
                  id="cv-doc"
                  value={documento}
                  onChange={(e) => setDocumento(e.target.value)}
                  placeholder="Documento del cliente"
                  disabled={enviando}
                />
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Su contraseña temporal será su documento; el cliente la cambia en su primer ingreso.
            </p>
            <div className="space-y-1.5">
              <Label htmlFor="cv-domicilio">Domicilio legal completo</Label>
              <Input
                id="cv-domicilio"
                value={domicilio}
                onChange={(e) => setDomicilio(e.target.value)}
                placeholder="Av./Jr./Calle, número, distrito, provincia y departamento"
                autoComplete="street-address"
                disabled={enviando}
              />
              <p className="text-[11px] text-muted-foreground">
                Se copiará literalmente en el contrato legal. Si ya era cliente, se conserva el
                domicilio registrado en el portal.
              </p>
            </div>
            {/* Bloque compartido con el alta directa (cliente-form): el cliente
                convertido necesita dónde cobrar sus intereses desde el día uno.
                Si el documento ya era cliente del portal, sus cuentas actuales
                se respetan (la edge las deja intactas en el camino del dedup) y
                lo que se escribió aquí se descarta: eso se avisa, nunca en
                silencio. */}
            <SeccionesBancarias
              idBase="cv"
              pen={pen}
              usd={usd}
              onPen={setPen}
              onUsd={setUsd}
              deshabilitado={enviando}
            />
            {error && <p role="alert" className="text-xs font-semibold text-destructive">{error}</p>}
          </DialogBody>
          <DialogFooter>
            <Button variant="outline" size="sm" onClick={onClose} disabled={enviando}>Cancelar</Button>
            <Button size="sm" onClick={confirmarReal} disabled={enviando}>
              <BadgeCheck /> {enviando ? 'Convirtiendo…' : 'Convertir a cliente'}
            </Button>
          </DialogFooter>
        </>
      )}
    </Dialog>
  )
}

function DialogDescartar({ l, onClose }: { l: Lead; onClose: () => void }) {
  const { descartar, actividadesDe } = useCRMData()
  const { yo } = useAuth()
  const [motivo, setMotivo] = useState<MotivoDescarte>('sin_interes')
  const [nota, setNota] = useState('')

  // «No responde» no es una opinión: es una AFIRMACIÓN DE HECHO sobre el
  // cliente. Sin intentos registrados es falsa, y encima ensucia la métrica con
  // la que se decide de dónde traer leads. El veto se calcula del timeline.
  const veto = vetoNoResponde(actividadesDe(l.id))

  const confirmar = () => {
    const res = descartar(l.id, motivo, nota)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    onClose()
    toast.info(`Lead descartado${yo?.demo ? ' (demo)' : ''}`)
  }

  return (
    <Dialog open onClose={onClose} ariaLabel="Descartar lead">
      <DialogHeader>
        <DialogTitle>Descartar lead</DialogTitle>
        <DialogDescription>
          {l.nombre_completo} saldrá del pipeline. El motivo es obligatorio y queda en el timeline.
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-3">
        <div className="space-y-1.5">
          <Label htmlFor="ld-motivo">Motivo</Label>
          <Select
            id="ld-motivo"
            value={motivo}
            aria-describedby={veto ? 'ld-motivo-veto' : undefined}
            onChange={(e) => setMotivo(e.target.value as MotivoDescarte)}
          >
            {MOTIVOS_DESCARTE.map((m) => {
              // Deshabilitado y CON LA RAZÓN A LA VISTA, no escondido: si
              // desapareciera, el asesor elegiría "Otro" y perderíamos el dato.
              const vetado = veto != null && MOTIVOS_CON_EVIDENCIA.has(m.k)
              return (
                <option key={m.k} value={m.k} disabled={vetado}>
                  {vetado ? `${m.label} — ${VETO_CORTO}` : m.label}
                </option>
              )
            })}
          </Select>
          {/* Se pinta SIEMPRE que haya veto, no solo cuando el motivo vetado
              está seleccionado: el `aria-describedby` del select ya lo promete,
              y si el <p> no existe la razón no llega ni al lector de pantalla
              ni a la vista — el asesor solo veía una opción deshabilitada. */}
          {veto && (
            <p id="ld-motivo-veto" className="text-[11px] font-medium text-[#b45309]">
              {veto}
            </p>
          )}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="ld-nota-descarte">Nota (opcional)</Label>
          <Textarea
            id="ld-nota-descarte"
            value={nota}
            onChange={(e) => setNota(e.target.value)}
            placeholder="Contexto del descarte…"
          />
        </div>
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" size="sm" onClick={onClose}>
          Cancelar
        </Button>
        <Button variant="destructive" size="sm" onClick={confirmar}>
          <XCircle /> Descartar
        </Button>
      </DialogFooter>
    </Dialog>
  )
}
