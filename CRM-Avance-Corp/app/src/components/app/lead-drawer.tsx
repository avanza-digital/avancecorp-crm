// Ficha del lead (drawer derecho) — F1b. Se monta UNA vez en App.tsx y se abre
// desde cualquier pantalla vía usePanelesActions().abrirLead(id). Write-gating doble:
// la UI oculta acciones (directorio = solo lectura total) y el store re-valida.
// Los errores de validación del store ({ok:false, error} SIN toast) se muestran
// inline en los forms o con toast.error en acciones sueltas.
import { Fragment, useEffect, useMemo, useState, type ChangeEvent, type CSSProperties, type ReactNode } from 'react'
import { toast } from 'sonner'
import {
  ArrowRightLeft,
  BadgeCheck,
  CalendarCheck,
  CalendarPlus,
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
import { CerrarTareaDialog } from '@/components/app/cerrar-tarea'
import { SeccionesBancarias } from '@/components/app/secciones-bancarias'
import { useAuth } from '@/lib/auth-context'
import {
  SECCION_BANCARIA_VACIA,
  validarBancariosForm,
  type SeccionBancariaForm,
} from '@/lib/cliente-form-logica'
import { can, puedeEscribir } from '@/lib/roles'
import { useCRMData, usePanelesActions, usePanelesState } from '@/lib/store-context'
import {
  actualizarClientePortal,
  convertirLead,
  CrmApiError,
  type TipoDocumentoCliente,
} from '@/data/crm-api'
import { ContratoNuevo } from '@/components/app/contrato-nuevo'
import { useAhora } from '@/lib/ahora'
import { agruparTimeline } from '@/lib/timeline-lead'
import { MONTO_ESTIMADO_MAX } from '@/lib/validacion'
import { esMoneda, fmtFecha, money, primerNombre, SIMBOLO, type Moneda } from '@/lib/format'
import {
  CAT_LABEL,
  ETAPAS,
  ETAPA_INFO,
  esTipoTarea,
  MOTIVOS_DESCARTE,
  origenLabel,
  TIPOS_ACTIVIDAD,
  TIPOS_TAREA,
  type Actividad,
  type EtapaActiva,
  type Lead,
  type MotivoDescarte,
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
  // Convertir es de UNA pieza para el usuario, pero por dentro son dos permisos
  // distintos, y hay que pasar los DOS o no empezar: la edge crea el cliente (y
  // le manda el correo de bienvenida a una persona real), y recién después
  // `crear_contrato` decide. Esa RPC exige (a) rol de portal que dé de alta y
  // (b) que el cliente sea de TU cartera. Como la edge pone
  // `asesor = vendedor del lead ?? quien convierte`, el (b) solo se cumple si el
  // cliente va a quedar a tu nombre. Un supervisor sobre el lead de su vendedor
  // pasa (a) y falla (b) → cliente creado, correo enviado, lead cerrado y
  // contrato imposible. Por eso se exigen los dos aquí: para no empezar algo que
  // no se puede terminar (si quiere cerrarla él, primero se reasigna el lead).
  const tieneAnalista = l.vendedor_id != null
  const seraMiCliente = l.vendedor_id === yo?.id
  const puedeConvertir = escribe && (yo?.puede_contratar ?? false) && seraMiCliente
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
                (escribe ? (
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
                {l.etapa === 'convertido' ? 'ganado' : 'en juego'}
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
        <Datos l={l} escribe={escribe} puedeReasignar={puedeReasignar} pedirEditar={pedirEditarDatos} />
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
                : yo?.puede_contratar
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

  const mover = (k: EtapaActiva) => {
    if (k === l.etapa) return
    const res = cambiarEtapa(l.id, k)
    if (!res.ok && res.error) toast.error(res.error)
  }

  return (
    <div className="flex items-center gap-1" role="group" aria-label="Etapa del lead">
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
  const { reabrir } = useCRMData()
  const { yo } = useAuth()
  const convertido = l.etapa === 'convertido'
  const info = ETAPA_INFO[l.etapa]
  const motivo = MOTIVOS_DESCARTE.find((m) => m.k === l.motivo_descarte)?.label

  const onReabrir = () => {
    const res = reabrir(l.id)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    toast.success(`Lead reabierto${yo?.demo ? ' (demo)' : ''} — vuelve a Nuevo`)
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
      </div>
      {!convertido && escribe && (
        <Button size="xs" variant="outline" onClick={onReabrir}>
          <RotateCcw /> Reabrir{yo?.demo ? ' (demo)' : ''}
        </Button>
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
  const { tareasDe, crearTarea } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  const pendientes = tareasDe(l.id)
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  // Con pendientes vivas, agendar OTRA es un gesto raro: el quick-add se pliega
  // tras este botón. Solo con 0 pendientes (aviso ámbar) queda abierto siempre.
  const [agendarOtra, setAgendarOtra] = useState(false)

  const slot = proximoSlotSugerido(ahora)
  const [tipo, setTipo] = useState<TipoTarea>('llamada')
  const [titulo, setTitulo] = useState(() => tituloSugerido('llamada', l.nombre_completo))
  const [tituloEditado, setTituloEditado] = useState(false)
  const [fecha, setFecha] = useState(() => fechaLima(Date.parse(slot)))
  const [hora, setHora] = useState('10:00')

  if (!escribe && pendientes.length === 0) return null
  // Lead cerrado: sus pendientes ya fueron canceladas por el trigger; nada que agendar.
  if (!activa && pendientes.length === 0) return null

  const cambiarTipo = (v: string) => {
    if (!esTipoTarea(v)) return
    setTipo(v)
    // El título sugerido sigue al tipo mientras el vendedor no lo haya tocado.
    if (!tituloEditado) setTitulo(tituloSugerido(v, l.nombre_completo))
  }

  const agendar = () => {
    const res = crearTarea({
      lead_id: l.id,
      tipo,
      titulo,
      vence_en: new Date(`${fecha}T${hora}:00-05:00`).toISOString(),
    })
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo agendar la tarea')
      return
    }
    toast.success(`Tarea agendada${yo?.demo ? ' (demo)' : ''} — la verás en Hoy y en Agenda`)
    setTituloEditado(false)
    setTitulo(tituloSugerido(tipo, l.nombre_completo))
    setAgendarOtra(false) // vuelve a plegarse: ya hay próxima acción visible
  }

  const avisoVentana = fueraDeVentanaLegal(fecha, hora)

  return (
    <section aria-label="Próxima acción">
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
                className="flex items-center gap-2 rounded-lg bg-muted/50 px-2.5 py-1.5 text-xs"
              >
                <span className="size-2 shrink-0 rounded-full" style={{ background: ev.color }} aria-hidden />
                <span className="min-w-0 flex-1 truncate font-medium">{t.titulo}</span>
                <span
                  className={cn(
                    'shrink-0 font-semibold tabular-nums',
                    ev.vencida ? 'text-[#d97706]' : 'text-muted-foreground',
                  )}
                >
                  {ev.cuando}
                </span>
                {escribe && activa && (
                  <button
                    type="button"
                    aria-label={`Cerrar tarea — ${t.titulo}`}
                    title="Cerrar tarea (resultado + siguiente)"
                    className="grid size-6 shrink-0 cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground"
                    onClick={() => setTareaACerrar(t)}
                  >
                    <CalendarCheck className="size-3.5" aria-hidden />
                  </button>
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
            <Button
              size="sm"
              className="w-full"
              onClick={agendar}
              disabled={!titulo.trim() || !fecha || !hora}
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

/** Lista es-PE: "a, b y c" (para la línea de datos faltantes). */
function listarFaltantes(xs: string[]): string {
  if (xs.length <= 1) return xs[0] ?? ''
  return `${xs.slice(0, -1).join(', ')} y ${xs[xs.length - 1]}`
}

function Datos({
  l,
  escribe,
  puedeReasignar,
  pedirEditar = 0,
}: {
  l: Lead
  escribe: boolean
  puedeReasignar: boolean
  pedirEditar?: number
}) {
  const { editarLead, reasignar, ambito } = useCRMData()
  const { yo } = useAuth()
  const sufijoDemo = yo?.demo ? ' (demo)' : ''
  const [editando, setEditando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState({
    nombre: '',
    telefono: '',
    correo: '',
    monto: '',
    moneda: 'PEN' as Moneda,
    nota: '',
  })

  // SOLO vendedores del ámbito del rol (espejo del WITH CHECK de leads_update):
  // supervisor ve/asigna únicamente a los suyos; gerencia sigue viendo a todos.
  const vendedores = ambito.vendedores.filter((m) => m.rol_crm === 'vendedor' && m.activo)

  const empezar = () => {
    setForm({
      nombre: l.nombre_completo,
      telefono: l.telefono,
      correo: l.correo ?? '',
      monto: l.monto_estimado != null ? String(l.monto_estimado) : '',
      moneda: l.moneda,
      nota: l.nota ?? '',
    })
    setError(null)
    setEditando(true)
  }

  const guardar = () => {
    const montoTxt = form.monto.trim()
    const monto = Number(montoTxt.replace(',', '.'))
    if (!montoTxt || !Number.isFinite(monto) || monto <= 0) {
      setError('El capital estimado es obligatorio y debe ser mayor que 0')
      return
    }
    const res = editarLead(l.id, {
      nombre_completo: form.nombre,
      telefono: form.telefono,
      correo: form.correo.trim() || null,
      monto_estimado: monto,
      moneda: form.moneda,
      nota: form.nota.trim() || null,
    })
    if (!res.ok) {
      setError(res.error ?? 'No se pudo guardar')
      return
    }
    setEditando(false)
    setError(null)
    toast.success(`Cambios guardados${sufijoDemo}`)
  }

  const onReasignar = (v: string) => {
    const res = reasignar(l.id, v || null)
    if (!res.ok) {
      // Los errores de permiso ya los toastea el store (doble defensa).
      if (res.error && !res.error.startsWith('Sin permiso')) toast.error(res.error)
      return
    }
    toast.success(v ? `Lead reasignado${sufijoDemo}` : `Lead parkeado sin vendedor${sufijoDemo}`)
  }

  const campo = (k: keyof typeof form) => (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [k]: e.target.value }))

  // El badge "Sin capital estimado → completar" del header pide abrir la edición.
  useEffect(() => {
    if (pedirEditar > 0 && escribe) empezar()
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
        {escribe && !editando && (
          <Button size="xs" variant="ghost" onClick={empezar}>
            <Pencil /> Editar
          </Button>
        )}
      </div>

      {editando ? (
        <div className="mt-2 space-y-3 rounded-xl border border-border bg-muted/40 p-3">
          <div className="space-y-1.5">
            <Label htmlFor="ld-nombre">Nombre completo</Label>
            <Input id="ld-nombre" value={form.nombre} onChange={campo('nombre')} />
          </div>
          <div className="grid grid-cols-2 gap-2.5">
            <div className="space-y-1.5">
              <Label htmlFor="ld-telefono">Teléfono</Label>
              <Input id="ld-telefono" value={form.telefono} onChange={campo('telefono')} placeholder="9########" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ld-monto">Capital estimado *</Label>
              <div className="flex gap-2">
                <Input id="ld-monto" className="min-w-0 flex-1 tabular-nums" type="number" min={0.01} max={MONTO_ESTIMADO_MAX} step="0.01" inputMode="decimal" required aria-required="true" aria-invalid={!!error} aria-describedby={error ? 'ld-datos-error' : undefined} value={form.monto} onChange={campo('monto')} placeholder="Ej. 5000" />
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
            <Input id="ld-correo" type="email" value={form.correo} onChange={campo('correo')} placeholder="opcional" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ld-nota">Nota</Label>
            <Textarea id="ld-nota" value={form.nota} onChange={campo('nota')} placeholder="opcional" className="min-h-[56px]" />
          </div>
          {error && <p id="ld-datos-error" role="alert" className="text-xs font-semibold text-destructive">{error}</p>}
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
          {faltantes.length > 0 && (
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
    toast.success(`Actividad registrada${yo?.demo ? ' (demo)' : ''}`)
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

// Cola del aviso de conversión parcial (paso 2 fallido). Mensaje de negocio del
// mismo corte que el del alta directa (cliente-form): honesto y accionable.
const MSG_BANCARIOS_NO_GUARDADOS_CV =
  'los datos bancarios NO se guardaron — corrígelo en Clientes dentro de las 5 horas.'

/** Exportado SOLO para los tests del componente (se monta solo, con la API mockeada). */
export function DialogConvertir({ l, onClose }: { l: Lead; onClose: () => void }) {
  const { convertir, recargar } = useCRMData()
  const { yo } = useAuth()
  const esDemo = yo?.demo === true

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
  // Bancarios (PEN = columnas base, USD = sufijo _usd) — el cliente convertido
  // los necesita IGUAL que el del alta directa: sin cuenta no hay dónde
  // depositarle los intereses (hallazgo de Miguel 2026-07-16).
  const [pen, setPen] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  const [usd, setUsd] = useState<SeccionBancariaForm>(SECCION_BANCARIA_VACIA)
  const [enviando, setEnviando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // Dos pasos: (1) crear el cliente, (2) crear su contrato — "todo en un sitio".
  const [paso, setPaso] = useState<'convertir' | 'contrato'>('convertir')
  const [perfilId, setPerfilId] = useState<string | null>(null)
  /** Conversión con bancarios fallidos: cliente creado SIN cuentas → aviso terminal. */
  const [avisoParcial, setAvisoParcial] = useState<string | null>(null)

  // Cierre BLINDADO: Radix cierra con Esc/overlay incondicionalmente, y un
  // cierre con el envío en vuelo perdería el aviso de "creado sin bancarios"
  // (la cuenta ya existe y el correo ya salió) — mismo patrón que clientes.tsx.
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
    const docLimpio = documento.trim().toUpperCase()
    if (!docLimpio) {
      setError('El documento del cliente es obligatorio')
      return
    }
    if (!RE_DOCUMENTO[tipoDoc].re.test(docLimpio)) {
      setError(RE_DOCUMENTO[tipoDoc].err)
      return
    }
    // Bancarios ANTES de tocar el servidor (regla "al menos una cuenta", igual
    // que el alta del portal): si no validan, NO se crea la cuenta ni sale el
    // correo de bienvenida — no se empieza algo que quedaría a medias.
    const valBanc = validarBancariosForm(pen, usd)
    if (!valBanc.ok) {
      setError(valBanc.error)
      return
    }
    setEnviando(true)
    try {
      // Paso 1: la edge crea la cuenta + correo de bienvenida + cierra el lead.
      const r = await convertirLead({
        lead_id: l.id,
        correo: correoLimpio,
        tipo_documento: tipoDoc,
        documento: docLimpio,
        nombre_completo: l.nombre_completo,
        telefono: l.telefono,
      })
      // Paso 2: bancarios por UPDATE vía RLS (la edge no los acepta) — mismo
      // flujo de 2 pasos que el alta directa (cliente-form). Si el documento YA
      // era cliente del portal (dedup de la edge), NO se pisan sus cuentas: un
      // PATCH ciego sobreescribiría los bancarios con los que ya cobra — se
      // salta el paso y se sigue al contrato.
      let bancariosOk = true
      if (!r.ya_existia) {
        try {
          bancariosOk = await actualizarClientePortal(r.perfil_id, {
            ...valBanc.bancarios,
            actualizado_en: new Date().toISOString(),
          })
        } catch {
          bancariosOk = false
        }
      }
      // El lead YA quedó convertido en el servidor pase lo que pase con los
      // bancarios: el pipeline debe reflejarlo también en el camino parcial.
      await recargar()
      if (!bancariosOk) {
        // Aviso honesto y TERMINAL (sin re-submit: la cuenta existe y el correo
        // salió) y SIN encadenar al contrato — patrón exacto de cliente-form.
        setAvisoParcial(
          r.email_enviado
            ? `Cliente creado y correo enviado, pero ${MSG_BANCARIOS_NO_GUARDADOS_CV}`
            : `Cliente creado (el correo de bienvenida no se pudo enviar), pero ${MSG_BANCARIOS_NO_GUARDADOS_CV}`,
        )
        return
      }
      toast.success(
        r.ya_existia
          ? `${l.nombre_completo} enlazado a su cuenta de cliente`
          : `${l.nombre_completo} ahora es cliente${r.email_enviado ? ' — correo de bienvenida enviado' : ''}`,
      )
      // Seguido: el paso de crear el contrato (sin salir del CRM).
      setPerfilId(r.perfil_id)
      setPaso('contrato')
    } catch (e) {
      setError(e instanceof CrmApiError ? e.message : 'No se pudo convertir el lead')
    } finally {
      setEnviando(false)
    }
  }

  // ── Conversión parcial (bancarios fallidos): estado terminal, sin re-submit ──
  if (avisoParcial) {
    return (
      <Dialog open onClose={onClose} ariaLabel="Convertir a cliente">
        <DialogHeader>
          <DialogTitle>Convertir a cliente</DialogTitle>
        </DialogHeader>
        <DialogBody className="space-y-3">
          <div
            role="alert"
            className="rounded-xl border border-destructive/40 bg-destructive/10 p-3 text-xs font-semibold text-destructive"
          >
            {avisoParcial}
          </div>
          <p className="text-xs text-muted-foreground">
            El lead quedó convertido y la cuenta del cliente ya existe en el portal, pero NO se
            creó su contrato. Complétale los datos bancarios desde “Clientes → Corregir datos”
            antes de crear el contrato.
          </p>
        </DialogBody>
        <DialogFooter>
          <Button size="sm" onClick={onClose}>Entendido</Button>
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
              enviará su correo de bienvenida con el acceso. Confirma sus datos:
            </p>
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
            {/* Bloque compartido con el alta directa (cliente-form): el cliente
                convertido necesita dónde cobrar sus intereses desde el día uno.
                Si el documento ya era cliente del portal, sus cuentas actuales
                se respetan (el paso 2 se salta — dedup de la edge). */}
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
  const { descartar } = useCRMData()
  const { yo } = useAuth()
  const [motivo, setMotivo] = useState<MotivoDescarte>('sin_interes')
  const [nota, setNota] = useState('')

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
          <Select id="ld-motivo" value={motivo} onChange={(e) => setMotivo(e.target.value as MotivoDescarte)}>
            {MOTIVOS_DESCARTE.map((m) => (
              <option key={m.k} value={m.k}>
                {m.label}
              </option>
            ))}
          </Select>
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
