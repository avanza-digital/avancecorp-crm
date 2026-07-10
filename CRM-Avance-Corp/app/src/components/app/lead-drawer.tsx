// Ficha del lead (drawer derecho) — F1b. Se monta UNA vez en App.tsx y se abre
// desde cualquier pantalla vía usePanelesActions().abrirLead(id). Write-gating doble:
// la UI oculta acciones (directorio = solo lectura total) y el store re-valida.
// Los errores de validación del store ({ok:false, error} SIN toast) se muestran
// inline en los forms o con toast.error en acciones sueltas.
import { Fragment, useState, type ChangeEvent, type CSSProperties, type ReactNode } from 'react'
import { toast } from 'sonner'
import {
  ArrowRightLeft,
  BadgeCheck,
  CalendarCheck,
  MessageCircle,
  MessageSquare,
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
import { useAuth } from '@/lib/auth-context'
import { can, puedeEscribir } from '@/lib/roles'
import { useCRMData, usePanelesActions, usePanelesState } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { fmtFecha, money, SIMBOLO } from '@/lib/format'
import {
  CAT_LABEL,
  ETAPAS,
  ETAPA_INFO,
  MOTIVOS_DESCARTE,
  origenLabel,
  TIPOS_ACTIVIDAD,
  type EtapaActiva,
  type Lead,
  type MotivoDescarte,
  type TipoActividad,
  type TipoActividadManual,
} from '@/lib/tipos'

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
  const esTerminal = l.etapa === 'convertido' || l.etapa === 'descartado'
  const [dialogo, setDialogo] = useState<'convertir' | 'descartar' | null>(null)
  const info = ETAPA_INFO[l.etapa]

  return (
    <>
      <SheetHeader className="gap-2.5">
        <div className="flex items-start gap-3">
          <Avatar nombre={l.nombre_completo} color={info.color} className="size-10 text-[13px]" />
          <div className="min-w-0 flex-1">
            <SheetTitle className="truncate">{l.nombre_completo}</SheetTitle>
            <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
              <Badge color={info.color} dot>{info.label}</Badge>
              {l.categoria_interes && (
                <Badge color="var(--chart-4)">Inversión · {CAT_LABEL[l.categoria_interes]}</Badge>
              )}
              <Badge color="var(--muted-foreground)">{origenLabel(l.origen)}</Badge>
            </div>
          </div>
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
        <Datos l={l} escribe={escribe} puedeReasignar={puedeReasignar} />
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
          <Button size="sm" onClick={() => setDialogo('convertir')}>
            <BadgeCheck /> Convertir a cliente (demo)
          </Button>
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
  const convertido = l.etapa === 'convertido'
  const info = ETAPA_INFO[l.etapa]
  const motivo = MOTIVOS_DESCARTE.find((m) => m.k === l.motivo_descarte)?.label

  const onReabrir = () => {
    const res = reabrir(l.id)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    toast.success('Lead reabierto (demo) — vuelve a Nuevo')
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
          {convertido ? 'Convertido a cliente (demo)' : 'Lead descartado'}
        </p>
        <p className="text-[11px] text-muted-foreground">
          {convertido
            ? 'En el sistema definitivo, la conversión crea al cliente y su contrato en el portal.'
            : `Motivo: ${motivo ?? '—'}`}
        </p>
      </div>
      {!convertido && escribe && (
        <Button size="xs" variant="outline" onClick={onReabrir}>
          <RotateCcw /> Reabrir (demo)
        </Button>
      )}
    </div>
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

function Datos({ l, escribe, puedeReasignar }: { l: Lead; escribe: boolean; puedeReasignar: boolean }) {
  const { editarLead, reasignar, ambito } = useCRMData()
  const [editando, setEditando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState({ nombre: '', telefono: '', correo: '', monto: '', nota: '' })

  // SOLO vendedores del ámbito del rol (espejo del WITH CHECK de leads_update):
  // supervisor ve/asigna únicamente a los suyos; gerencia sigue viendo a todos.
  const vendedores = ambito.vendedores.filter((m) => m.rol_crm === 'vendedor' && m.activo)

  const empezar = () => {
    setForm({
      nombre: l.nombre_completo,
      telefono: l.telefono,
      correo: l.correo ?? '',
      monto: l.monto_estimado != null ? String(l.monto_estimado) : '',
      nota: l.nota ?? '',
    })
    setError(null)
    setEditando(true)
  }

  const guardar = () => {
    const montoTxt = form.monto.trim()
    let monto: number | null = null
    if (montoTxt) {
      monto = Number(montoTxt.replace(',', '.'))
      if (!Number.isFinite(monto) || monto < 0) {
        setError('Monto inválido — usa solo números (sin símbolo de moneda)')
        return
      }
    }
    const res = editarLead(l.id, {
      nombre_completo: form.nombre,
      telefono: form.telefono,
      correo: form.correo.trim() || null,
      monto_estimado: monto,
      nota: form.nota.trim() || null,
    })
    if (!res.ok) {
      setError(res.error ?? 'No se pudo guardar')
      return
    }
    setEditando(false)
    setError(null)
    toast.success('Cambios guardados (demo)')
  }

  const onReasignar = (v: string) => {
    const res = reasignar(l.id, v || null)
    if (!res.ok) {
      // Los errores de permiso ya los toastea el store (doble defensa).
      if (res.error && !res.error.startsWith('Sin permiso')) toast.error(res.error)
      return
    }
    toast.success(v ? 'Lead reasignado (demo)' : 'Lead parkeado sin vendedor (demo)')
  }

  const campo = (k: keyof typeof form) => (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [k]: e.target.value }))

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
              <Label htmlFor="ld-monto">Monto estimado ({SIMBOLO[l.moneda]})</Label>
              <Input id="ld-monto" inputMode="decimal" value={form.monto} onChange={campo('monto')} placeholder="—" />
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
          {error && <p className="text-xs font-semibold text-destructive">{error}</p>}
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
        <dl className="mt-1.5">
          <Fila label="Teléfono">
            <span className="tabular-nums">{l.telefono}</span>
          </Fila>
          <Fila label="Correo">{l.correo || '—'}</Fila>
          <Fila label="DNI">
            <span className="tabular-nums">{l.dni || '—'}</span>
          </Fila>
          <Fila label="Distrito">{l.distrito || '—'}</Fila>
          <Fila label="Monto">
            {l.monto_estimado != null ? (
              <span className="font-extrabold tabular-nums text-primary">{money(l.monto_estimado, l.moneda)}</span>
            ) : (
              '—'
            )}
          </Fila>
          <Fila label="Categoría">
            {l.categoria_interes ? `Inversión · ${CAT_LABEL[l.categoria_interes]}` : '—'}
          </Fila>
          <Fila label="Origen">{origenLabel(l.origen)}</Fila>
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
          <Fila label="Creado">{fmtFecha(l.creado_en)}</Fila>
          <Fila label="Nota">{l.nota || '—'}</Fila>
        </dl>
      )}
    </section>
  )
}

// ── Timeline + composer ───────────────────────────────────────────────────────

const CLASE_HITO =
  'relative z-[1] grid size-7 shrink-0 place-items-center rounded-full border border-border bg-card text-muted-foreground [&_svg]:size-3.5'

function Timeline({ l, escribe, activa }: { l: Lead; escribe: boolean; activa: boolean }) {
  const { actividadesDe, registrarActividad } = useCRMData()
  const ahora = useAhora()
  const acts = actividadesDe(l.id)
  const [tipo, setTipo] = useState<TipoActividadManual>('llamada_realizada')
  const [detalle, setDetalle] = useState('')

  const registrar = () => {
    const res = registrarActividad(l.id, tipo, detalle)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    setDetalle('')
    toast.success('Actividad registrada (demo)')
  }

  return (
    <section aria-label="Actividad del lead">
      <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Actividad</h3>

      {escribe && activa && (
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
          />
          <div className="flex justify-end">
            <Button size="sm" onClick={registrar}>
              <Send /> Registrar
            </Button>
          </div>
        </div>
      )}

      <ol className="relative mt-3 space-y-4 before:absolute before:inset-y-2 before:left-[13px] before:w-px before:bg-border">
        {acts.map((a) => {
          const Icono = ICONO_ACTIVIDAD[a.tipo]
          const esConversion = a.tipo === 'conversion'
          return (
            <li key={a.id} className="flex gap-2.5">
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
        })}
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

function DialogConvertir({ l, onClose }: { l: Lead; onClose: () => void }) {
  const { convertir } = useCRMData()

  const confirmar = () => {
    const res = convertir(l.id)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    onClose()
    toast.success(`${l.nombre_completo} ahora es cliente (demo)`)
  }

  return (
    <Dialog open onClose={onClose} ariaLabel="Convertir a cliente">
      <DialogHeader>
        <DialogTitle>Convertir a cliente (demo)</DialogTitle>
        <DialogDescription>
          {l.nombre_completo} pasará a {ETAPA_INFO.convertido.label}.
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-2 text-xs leading-relaxed text-muted-foreground">
        <p>
          En el sistema definitivo, la conversión crea al{' '}
          <b className="text-foreground">cliente y su contrato en el portal</b> y cierra el
          lead como ganado.
        </p>
        <p>En este modo demo solo se simula el cambio de estado — nada queda guardado de verdad.</p>
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" size="sm" onClick={onClose}>
          Cancelar
        </Button>
        <Button size="sm" onClick={confirmar}>
          <BadgeCheck /> Convertir (demo)
        </Button>
      </DialogFooter>
    </Dialog>
  )
}

function DialogDescartar({ l, onClose }: { l: Lead; onClose: () => void }) {
  const { descartar } = useCRMData()
  const [motivo, setMotivo] = useState<MotivoDescarte>('sin_interes')
  const [nota, setNota] = useState('')

  const confirmar = () => {
    const res = descartar(l.id, motivo, nota)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    onClose()
    toast.info('Lead descartado (demo)')
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
