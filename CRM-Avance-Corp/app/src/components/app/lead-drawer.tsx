import { SolicitudTasaLeadPlegable, type EstadoCondicionesLead } from './condiciones-tasa-lead'
import { InversionDesdeLead } from './inversion-desde-lead'
import { InversionDesdeLeadDemo } from './inversion-desde-lead-demo'
import { VentaCruzada } from './venta-cruzada'
import { buscarClienteExistente, type BusquedaCliente } from '@/data/cliente-existente-api'
import type { CondicionesTasaLead } from '@/data/crm-api'
import { fechaSla, puedeRegistrarGestionSla, type AvisoSla } from '@/lib/sla-operacion'
import { useEstadosSlaV2 } from '@/data/sla-operacion-queries'
import { EstadoSlaFicha } from '@/components/app/sla-operacion'
import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
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
  MoreHorizontal,
  Pencil,
  RotateCcw,
  Send,
  Sparkles,
  X,
  XCircle,
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
import { SegundoNumero } from '@/components/app/segundo-numero'
import { CerrarTareaDialog } from '@/components/app/cerrar-tarea'
import {
  CAMPOS_REUNION_VACIOS,
  CamposReunion,
  camposTareaDeReunion,
  type EstadoCamposReunion,
} from '@/components/app/campos-reunion'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { useAuth } from '@/lib/auth-context'
import { can, puedeEscribir } from '@/lib/roles'
import { useCRMData, usePanelesActions, usePanelesState } from '@/lib/store-context'
import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
import { haceRelativo, ICONO_ACTIVIDAD } from './actividad-visual'
import { MOTIVOS_CON_EVIDENCIA, VETO_CORTO, vetoNoResponde } from '@/lib/descarte-evidencia'
import { DialogCapitalPropuesta } from '@/components/app/capital-propuesta'
import { useAhora } from '@/lib/ahora'
import { retrocesoPorAnularReunion } from '@/lib/avance-automatico'
import { agruparTimeline } from '@/lib/timeline-lead'
import { MONTO_ESTIMADO_MAX, type CampoLead } from '@/lib/validacion'
import { esMoneda, fmtFecha, money, primerNombre, SIMBOLO, type Moneda } from '@/lib/format'
import { estadoDelCierre, puedeAnularCierreAvance } from '@/lib/cierre-estado'
import { useCierresEstado } from '@/data/crm-queries'
import { ConversionCreditoLead } from './conversion-credito-lead'
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
  textoCargadoPor,
  TIPOS_ACTIVIDAD,
  TIPOS_TAREA,
  type Actividad,
  type CategoriaInteres,
  type Etapa,
  type EtapaActiva,
  type Lead,
  type MotivoDescarte,
  type MotivoNoRealizadaManual,
  type TipoActividadManual,
  type TipoTarea,
  type Tarea,
} from '@/lib/tipos'
import { ChipProcedencia } from '@/components/app/procedencia-chip'
import { ChipReasignado } from '@/components/app/reasignado-chip'
import { fechaLima, proximoSlotSugerido, tareaAEvento } from '@/lib/agenda-derivada'
import { tituloProximaAccion } from '@/lib/campos-siguiente'
import { presentarCitas } from '@/lib/terminologia'

// ── Helpers ───────────────────────────────────────────────────────────────────

const TIPOS_MANUALES: TipoActividadManual[] = [
  'llamada_realizada',
  'llamada_no_contestada',
  'whatsapp_enviado',
  'whatsapp_recibido',
  'reunion_realizada',
  'nota',
]

/**
 * Rótulo del capital según el desenlace del lead. Un lead CERRADO no tiene
 * capital "en juego": el convertido ya lo ganó y el descartado no lo concretó.
 * Rotular ambos como "en juego" infla lo que el analista cree tener vivo —
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
  const { obtenerTareaParaRevision, ambito } = useCRMData()
  const rol = yo?.rol
  const escribe = puedeEscribir(rol)
  const puedeRegistrarGestion = puedeRegistrarGestionSla(rol)
  const puedeReasignar = escribe && can(rol, 'reasignar')
  // Analista/supervisor conservan la regla de cartera propia. Gerencia puede
  // cerrar cualquier lead que ya tenga analista: el cliente conserva a ese
  // analista como responsable del cliente y las edges/RPC revalidan la membresía global.
  const tieneAnalista = l.vendedor_id != null
  const seraMiCliente = l.vendedor_id === yo?.id
  const operaGlobal = escribe && can(rol, 'verTodo')
  // Supervisor: mismo criterio que ya usa el selector de reasignar (ambito.vendedores) —
  // el lead está en su equipo aunque él mismo no sea el analista asignado.
  const enMiEquipo = tieneAnalista && ambito.vendedores.some((m) => m.perfil_id === l.vendedor_id)
  const operaEquipo = escribe && can(rol, 'verEquipo') && enMiEquipo
  const puedeConvertir =
    escribe && (yo?.puede_contratar ?? false) && (seraMiCliente || (operaGlobal && tieneAnalista) || operaEquipo)
  const esTerminal = l.etapa === 'convertido' || l.etapa === 'descartado'
  const [dialogo, setDialogo] = useState<'convertir' | 'descartar' | null>(null)
  // Reabrir el descarte de alguien que ya es cliente no reabre nada: se muestra quién es y se
  // ofrece su venta cruzada. Vive aquí y no en el banner: el reabrir optimista pasa el lead a
  // «Nuevo» (y desmonta el banner) antes de que el servidor responda.
  const [clienteDelLead, setClienteDelLead] = useState<BusquedaCliente | null>(null)
  const [condicionesLead, setCondicionesLead] = useState<EstadoCondicionesLead | null>(null)
  const bloqueoTasa = condicionesLead?.bloqueo ?? (condicionesLead ? null : 'Verifica las condiciones de inversión antes de convertir.')
  // Señal header → Datos: el badge "Sin capital estimado" abre el modo edición
  // de la sección Datos sin duplicar su estado (contador incremental).
  const [pedirEditarDatos, setPedirEditarDatos] = useState(0)
  const [componiendoGestion, setComponiendoGestion] = useState(false)
  const [tareaAviso, setTareaAviso] = useState<Tarea | null>(null)
  const refEtapa = useRef<HTMLDivElement>(null)
  const refDatos = useRef<HTMLDivElement>(null)
  const refActividad = useRef<HTMLDivElement>(null)
  async function actuarSobreAviso(aviso: AvisoSla) {
    if (aviso.bucket === 'tarea_vencida') {
      try {
        const tarea = aviso.tarea_id ? await obtenerTareaParaRevision(l.id, aviso.tarea_id) : null
        if (tarea) setTareaAviso(tarea)
        else toast.error('La actividad ya no está pendiente o disponible. Actualiza la ficha.')
      } catch {
        toast.error('No se pudo abrir la actividad. Vuelve a intentarlo.')
      }
    } else if (aviso.bucket === 'primera_atencion' || aviso.bucket === 'seguimiento') {
      if (!puedeRegistrarGestion) return
      setComponiendoGestion(true)
      refActividad.current?.scrollIntoView({ block: 'nearest' })
    } else {
      const destino = aviso.bucket === 'revision_comercial' ? refEtapa : refDatos
      destino.current?.focus()
      destino.current?.scrollIntoView({ block: 'nearest' })
    }
  }
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
              <ChipProcedencia lead={l} conNombre />
              <ChipReasignado lead={l} />
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
        <div ref={refEtapa} tabIndex={-1} className="rounded-lg focus-visible:outline-2 focus-visible:outline-ring">{esTerminal ? <BannerTerminal l={l} escribe={escribe} onClienteDelLead={setClienteDelLead} /> : <Stepper l={l} escribe={escribe} />}</div>
        {!esTerminal && tieneAnalista && <SolicitudTasaLeadPlegable lead={l} demo={Boolean(yo?.demo)} puedeEditar={puedeConvertir} onCambio={setCondicionesLead} />}
        {!esTerminal && <EstadoSlaFicha leadId={l.id} onActuar={escribe ? actuarSobreAviso : undefined} />}
        <ProximaAccion l={l} escribe={escribe} activa={!esTerminal} />
        {/* `activa` faltaba AQUÍ y solo aquí: la ficha de un convertido seguía
            ofreciendo "Editar" y "Faltan DNI… → Completar" sobre un lead que el
            store ya no deja escribir. */}
        <div ref={refDatos} tabIndex={-1} className="rounded-lg focus-visible:outline-2 focus-visible:outline-ring"><Datos
          l={l}
          escribe={escribe}
          activa={!esTerminal}
          puedeReasignar={puedeReasignar}
          pedirEditar={pedirEditarDatos}
        /></div>
        <div ref={refActividad}><Timeline l={l} escribe={escribe} activa={!esTerminal} puedeRegistrarGestion={puedeRegistrarGestion} componiendo={componiendoGestion} setComponiendo={setComponiendoGestion} /></div>
      </SheetBody>

      {escribe && !esTerminal && (
        <SheetFooter className="flex-wrap justify-between">
          <Button
            variant="outline"
            size="sm"
            className="border-destructive/40 text-destructive hover:border-destructive/60 hover:bg-destructive/10"
            onClick={() => setDialogo('descartar')}
          >
            <XCircle /> Descartar
          </Button>
          {puedeConvertir ? (
            <Button size="sm" aria-describedby={bloqueoTasa ? `lead-${l.id}-bloqueo-tasa` : undefined} onClick={() => setDialogo('convertir')}>
              <BadgeCheck /> Convertir a cliente{yo?.demo ? ' (demo)' : ''}
            </Button>
          ) : (
            <p className="max-w-[62%] text-right text-[11px] leading-tight text-muted-foreground">
              {!tieneAnalista
                ? 'Asigna primero el lead a un analista; una conversión necesita responsable comercial.'
                : rol === 'supervisor' && yo?.puede_contratar
                ? `La conversión la cierra el equipo de ${primerNombre(l.vendedor_nombre) || 'otro supervisor'}, fuera de tu equipo.`
                : yo?.puede_contratar && !operaGlobal
                ? `La conversión la cierra ${primerNombre(l.vendedor_nombre) || 'el analista del lead'}. Para hacerla tú, reasígnate el lead.`
                : 'El alta del cliente la registra el analista.'}
            </p>
          )}
          {puedeConvertir && bloqueoTasa && <div className="w-full space-y-1 text-[11px] text-muted-foreground-strong">
            <p id={`lead-${l.id}-bloqueo-tasa`}>{bloqueoTasa}</p>
          </div>}
        </SheetFooter>
      )}

      <CerrarTareaDialog tarea={tareaAviso} onCerrar={() => setTareaAviso(null)} />
      {l.etapa === 'convertido' && puedeConvertir && !yo?.demo && <SheetFooter>
        <Button size="sm" variant="outline" onClick={() => setDialogo('convertir')}>Ver inversión y bienvenida</Button>
      </SheetFooter>}
      {dialogo === 'convertir' && <DialogConvertir l={l} condicionesTasa={condicionesLead?.condiciones} bloqueoTasa={bloqueoTasa} onClose={() => setDialogo(null)} />}
      {dialogo === 'descartar' && <DialogDescartar l={l} onClose={() => setDialogo(null)} />}
      {clienteDelLead && yo && (
        <VentaCruzada
          actor={yo.id}
          resultadoInicial={clienteDelLead}
          documentoSugerido={l.dni ? { tipo: 'DNI', numero: l.dni } : undefined}
          puedeRegistrar={!yo.demo && (yo.rol === 'vendedor' || yo.rol === 'supervisor')}
          // El botón «Reabrir» ya no existe cuando llega la respuesta: el foco vuelve a la etapa.
          focoAlCerrar={refEtapa}
          onCerrar={() => setClienteDelLead(null)}
        />
      )}
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
    <div className="flex flex-wrap items-center gap-x-1 gap-y-2" role="group" aria-label="Etapa del lead">
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

function BannerTerminal({ l, escribe, onClienteDelLead }: {
  l: Lead; escribe: boolean
  /** «Ya es cliente»: la ficha muestra la tarjeta (el banner puede estar desmontado). */
  onClienteDelLead: (busqueda: BusquedaCliente) => void
}) {
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
    const exito = `Lead reabierto${yo?.demo ? ' (demo)' : ''} — vuelve a Nuevo`
    if (!res.persistido) {
      toast.success(exito)
      return
    }
    // El aviso espera al servidor: un «reabierto» que luego se deshace confunde.
    void res.persistido.then(async (r) => {
      if (r.ok) {
        toast.success(exito)
        return
      }
      if (r.codigo === 'P0409' && r.error?.includes('ya es cliente')) {
        try {
          const b = await buscarClienteExistente({ tipo: 'lead', leadId: l.id })
          if (b.estado === 'encontrado' || b.estado === 'no_operable') {
            onClienteDelLead(b)
            return
          }
        } catch {
          /* Sin la tarjeta queda el mensaje del servidor. */
        }
      }
      toast.error(r.error ?? 'No se pudo reabrir el lead')
    })
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
              ? 'La conversión confirma la inversión y cierra el lead como ganado (demo).'
              : 'Lead cerrado como ganado. El crédito mensual se verifica por separado.'
            : `Motivo: ${motivo ?? '—'}`}
        </p>
        {/* La anulación se ve AQUÍ, junto al «Convertido a cliente» que
            contradice, y con la razón escrita: quien mire esta ficha tiene que
            poder explicarse por qué el número del analista bajó. */}
        {convertido && !demo && <ConversionCreditoLead leadId={l.id} />}
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

/** ¿El instante cae fuera de la ventana legal peruana (L–S 07:00–20:00)? */
function fueraDeVentanaLegal(fecha: string, hora: string): boolean {
  const d = new Date(`${fecha}T${hora}:00-05:00`)
  if (Number.isNaN(d.getTime())) return false
  const dow = new Date(d.getTime() - 5 * 3600 * 1000).getUTCDay() // reloj Lima
  const [h] = hora.split(':').map(Number)
  return dow === 0 || (h ?? 12) < 7 || (h ?? 12) >= 20
}

export function ProximaAccion({ l, escribe, activa }: { l: Lead; escribe: boolean; activa: boolean }) {
  const { tareasDe, crearTarea, anularTarea, obtenerTareaParaRevision } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  // Señales «alguna vez» del historial POR LEAD (Fase 1 «sin topes»): el aviso
  // de retroceso al anular una cita ya no se calcula sobre la lista global.
  const historial = useActividadesDeLead(l.id)
  const consultaSla = useEstadosSlaV2([l.id])
  const operacion = !consultaSla.error && consultaSla.data?.modo === 'activo'
    ? consultaSla.data.filas.find((fila) => fila.lead_id === l.id)?.operacion : undefined
  const proxima = operacion?.proxima_accion
  const agendaSinConfirmar = !yo?.demo && (!consultaSla.data || Boolean(consultaSla.error))
  // El núcleo escoge la primera tarea. Agenda conserva las restantes y sus flujos.
  const locales = tareasDe(l.id)
  const pendientes = proxima
    ? [...locales.filter((t) => t.id === proxima.id), ...locales.filter((t) => t.id !== proxima.id)] : locales
  const fueraDelLote = proxima && !locales.some((t) => t.id === proxima.id)
  const [abriendoProxima, setAbriendoProxima] = useState(false)
  const [tareaACerrar, setTareaACerrar] = useState<Tarea | null>(null)
  // Confirmación de anulado, INLINE y por fila (id de la tarea, no un boolean):
  // la lista puede tener varias y el "¿seguro?" tiene que quedar pegado a la
  // que se va a anular. Anular es irreversible en el servidor, así que no puede
  // ir a un tap; `window.confirm` está descartado (bloquea el hilo y en móvil
  // sale como diálogo del navegador, fuera del CRM).
  const [anulandoId, setAnulandoId] = useState<string | null>(null)
  const [guardandoAnulacion, setGuardandoAnulacion] = useState(false)
  const [anulacionSinConfirmar, setAnulacionSinConfirmar] = useState<{
    tarea: Tarea; motivo: MotivoNoRealizadaManual | ''
  } | null>(null)
  const envioAnulacion = useRef(false)
  // Los botones de la confirmación se DESMONTAN al pulsarlos (y con «Sí» se va
  // el `<li>` entero). Sin devolver el foco a mano, Radix lo rescata al tope
  // del drawer y hay que re-tabular stepper, banner y ficha completa para
  // volver a la lista. Mismo idioma de refs por id que usa `repartir.tsx`.
  const refInterruptores = useRef(new Map<string, HTMLButtonElement>())
  const refSeccion = useRef<HTMLElement>(null)
  // Con pendientes vivas, agendar OTRA es un gesto raro: el quick-add se pliega
  // tras este botón. Solo con 0 pendientes (aviso ámbar) queda abierto siempre.
  const [agendarOtra, setAgendarOtra] = useState(false)
  const [guardandoTarea, setGuardandoTarea] = useState(false)
  const [errorTarea, setErrorTarea] = useState<string | null>(null)
  const envioTarea = useRef(false)
  const [motivoAnulacionReunion, setMotivoAnulacionReunion] =
    useState<MotivoNoRealizadaManual | ''>('')

  const slot = proximoSlotSugerido(ahora)
  const [tipo, setTipo] = useState<TipoTarea>('llamada')
  const [titulo, setTitulo] = useState(() => tituloProximaAccion('llamada', l.nombre_completo))
  const [tituloEditado, setTituloEditado] = useState(false)
  const [fecha, setFecha] = useState(() => fechaLima(Date.parse(slot)))
  const [hora, setHora] = useState('10:00')
  const [camposReunion, setCamposReunion] =
    useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)

  if (!escribe && pendientes.length === 0 && !fueraDelLote) return null
  // Lead cerrado: sus pendientes ya fueron canceladas por el trigger; nada que agendar.
  if (!activa && pendientes.length === 0 && !fueraDelLote) return null

  async function revisarProxima() {
    if (!proxima || abriendoProxima) return
    setAbriendoProxima(true)
    try {
      // Recupera el registro completo por ID y autoridad actual, incluido el tipo
      // real de reunión/llamada. El título libre no determina el flujo de cierre.
      const tarea = await obtenerTareaParaRevision(l.id, proxima.id)
      if (tarea) setTareaACerrar(tarea)
      else { toast.error('La actividad cambió. Actualiza la ficha.'); void consultaSla.refetch() }
    } catch { toast.error('No se pudo abrir la actividad. Vuelve a intentarlo.') }
    finally { setAbriendoProxima(false) }
  }

  const cambiarTipo = (v: string) => {
    if (!esTipoTarea(v)) return
    setTipo(v)
    // El título sugerido sigue al tipo mientras el analista no lo haya tocado.
    if (!tituloEditado) setTitulo(tituloProximaAccion(v, l.nombre_completo))
  }

  /**
   * ANULAR desde la ficha — el atajo para el caso que lo motivó: acabas de
   * agendar la reunión y la llamada de la semana pasada sobra. Sin esto había
   * que abrir el diálogo de cierre y elegir un resultado FALSO para sacarla.
   * `anularTarea` no escribe actividad de contacto (ver lib/store.tsx); lo único
   * que puede mover es la etapa, hacia atrás y solo al anular la última reunión
   * viva sin reagendar (pedido de Miguel, 2026-07-26).
   */
  const anular = async (t: Tarea, motivo = motivoAnulacionReunion) => {
    if (envioAnulacion.current) return
    let res
    if (t.tipo === 'reunion') {
      if (!motivo) {
        toast.error('Selecciona por qué se cancela la cita')
        return
      }
      res = anularTarea(t.id, { motivo })
    } else {
      res = anularTarea(t.id)
    }
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo anular la tarea')
      // La fila sigue ahí (no se anuló nada): el foco vuelve a su interruptor.
      requestAnimationFrame(() => refInterruptores.current.get(t.id)?.focus())
      return
    }
    envioAnulacion.current = true
    setGuardandoAnulacion(true)
    try {
      if (!(await (res.persistido ?? Promise.resolve(true)))) {
        setAnulacionSinConfirmar({ tarea: t, motivo })
        return
      }
    } catch {
      setAnulacionSinConfirmar({ tarea: t, motivo })
      return
    } finally {
      envioAnulacion.current = false
      setGuardandoAnulacion(false)
    }
    setAnulacionSinConfirmar(null)
    setAnulandoId(null)
    // La fila se fue. El foco aterriza en la sección, que sigue montada aunque
    // la lista quede vacía — desde ahí el siguiente Tab es el quick-add.
    requestAnimationFrame(() => refSeccion.current?.focus())
    const sufijo = yo?.demo ? ' (demo)' : ''
    // Mismo orden de prioridad que en cerrar-tarea.tsx: el retroceso de etapa
    // gana al "sin próxima acción" porque es el cambio que el analista no pidió.
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
    if (pendientes.length === 1 && !fueraDelLote && activa && !l.no_contactar) {
      toast.warning(
        `Tarea anulada — ${primerNombre(l.nombre_completo)} quedó SIN próxima acción${sufijo}`,
      )
    } else {
      toast.success(`Tarea anulada${sufijo}`)
    }
  }

  const agendar = async () => {
    if (envioTarea.current) return
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
    envioTarea.current = true
    setGuardandoTarea(true)
    setAgendarOtra(true)
    setErrorTarea(null)
    try {
      if (!(await (res.persistido ?? Promise.resolve(true)))) {
        setErrorTarea('No se confirmó la tarea. Revisa la agenda antes de volver a agendarla.')
        return
      }
    } catch {
      setErrorTarea('No se confirmó la tarea. Revisa la agenda antes de volver a agendarla.')
      return
    } finally {
      envioTarea.current = false
      setGuardandoTarea(false)
    }
    // NADA EN SILENCIO: agendar una reunión con quien ya se trabajó sube el lead
    // a "Reunión agendada" por trigger (lib/avance-automatico). El store ya lo
    // devolvía en los otros dos escritores y aquí se tiraba: el analista veía
    // moverse el stepper sin saber por qué. Mismo formato "hecho · hecho" que
    // `avisoDe` en contacto.tsx, y el mismo orden en que ocurren las cosas.
    const partes = ['Tarea agendada']
    if (res.avance) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
    partes.push('la verás en Hoy y en Agenda')
    toast.success(`${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}`)
    setTituloEditado(false)
    setTitulo(tituloProximaAccion(tipo, l.nombre_completo))
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
        {(pendientes.length > 0 || fueraDelLote) && (
          <Badge color="var(--accent)" className="text-[10px]">
            {operacion ? 'En Agenda' : `${pendientes.length} pendiente${pendientes.length === 1 ? '' : 's'}`}
          </Badge>
        )}
      </div>

      {agendaSinConfirmar && pendientes.length === 0 && <p role="status" className="mb-2 text-xs text-muted-foreground">La próxima actividad todavía no está confirmada.</p>}
      {fueraDelLote && proxima && <div className="mb-2 grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-2 gap-y-1 rounded-lg bg-muted/50 px-2.5 py-1.5 text-xs">
        <span className="col-span-2 min-w-0 font-medium wrap-break-word">{proxima.titulo}</span>
        <span className="min-w-0 text-muted-foreground tabular-nums">{fechaSla(proxima.vence_en)} · Lima</span>
        {escribe && activa && <Button variant="outline" size="sm" disabled={abriendoProxima} onClick={() => void revisarProxima()}>
          {abriendoProxima ? 'Abriendo…' : 'Revisar actividad'}
        </Button>}
      </div>}
      {/* Pendientes del lead: la promesa visible de que nadie lo suelta. */}
      {pendientes.length > 0 && (
        <ul className="mb-2 space-y-1">
          {pendientes.map((t) => {
            const ev = tareaAEvento(proxima?.id === t.id ? { ...t, titulo: proxima.titulo, vence_en: proxima.vence_en } : t, ahora)
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
                  <span className="min-w-0 flex-1 truncate font-medium">{ev.titulo}</span>
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
                        aria-label={`Cerrar tarea — ${ev.titulo}`}
                        title="Cerrar tarea (resultado + siguiente)"
                        className="grid size-6 shrink-0 cursor-pointer place-items-center rounded-md text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground pointer-coarse:size-8"
                        disabled={abriendoProxima}
                        onClick={() => proxima?.id === t.id ? void revisarProxima() : setTareaACerrar(t)}
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
                        aria-label={`Anular tarea — ${ev.titulo}`}
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
                      aria-label={`Sí, anular — ${ev.titulo}`}
                      // La consecuencia se pinta DESPUÉS de los botones, así
                      // que quien navega con teclado llegaría al destructivo
                      // antes de oírla. `aria-describedby` la trae al foco.
                      aria-describedby={`anular-nota-${t.id}`}
                      onClick={() => void anular(t)}
                      disabled={guardandoAnulacion || anulacionSinConfirmar !== null || (t.tipo === 'reunion' && !motivoAnulacionReunion)}
                    >
                      Sí, anular
                    </Button>
                    <Button
                      size="xs"
                      variant="ghost"
                      className="pointer-coarse:h-8 pointer-coarse:px-3"
                      aria-label={`No anular — ${ev.titulo}`}
                      disabled={guardandoAnulacion || anulacionSinConfirmar !== null}
                      onClick={() => {
                        setAnulandoId(null)
                        requestAnimationFrame(() => refInterruptores.current.get(t.id)?.focus())
                      }}
                    >
                      No
                    </Button>
                    {t.tipo === 'reunion' && (
                      <Select
                        aria-label={`Motivo de cancelación — ${ev.titulo}`}
                        value={motivoAnulacionReunion}
                        disabled={guardandoAnulacion || anulacionSinConfirmar !== null}
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
                        // Sin el historial servido no se afirma ninguna etapa:
                        // con señales vacías la función diría «Nuevo» sin base.
                        if (historial.cargando) return 'Comprobando el historial del lead…'
                        if (historial.error != null) return 'No se pudo leer el historial: al anular, la etapa podría bajar. No se puede deshacer.'
                        const atras = retrocesoPorAnularReunion(l, t, pendientes, historial.senales)
                        if (atras) {
                          return `Era su única cita: vuelve a «${ETAPA_INFO[atras].label}». La cancelación queda en el reporte. No se puede deshacer.`
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

      {guardandoAnulacion && <p role="status" className="mb-2 text-xs">Confirmando anulación…</p>}
      {anulacionSinConfirmar && <div className="mb-2 space-y-2 rounded-lg border p-2">
        <p role="alert" className="text-xs text-destructive">La anulación de «{presentarCitas(anulacionSinConfirmar.tarea.titulo)}» todavía no está confirmada.</p>
        <Button size="xs" disabled={guardandoAnulacion} onClick={() => void anular(anulacionSinConfirmar.tarea, anulacionSinConfirmar.motivo)}>Reintentar anulación</Button>
      </div>}

      {escribe && activa && (pendientes.length > 0 || fueraDelLote) && !agendarOtra && (
        <Button size="xs" variant="ghost" onClick={() => setAgendarOtra(true)}>
          <CalendarPlus /> Agendar otra
        </Button>
      )}

      {escribe && activa && ((pendientes.length === 0 && !fueraDelLote && !agendaSinConfirmar) || agendarOtra) && (
        <fieldset disabled={guardandoTarea} className="min-w-0 rounded-xl border border-border/70 p-2.5">
          {pendientes.length === 0 && !fueraDelLote && (
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
              onClick={() => void agendar()}
              disabled={
                guardandoTarea || !titulo.trim()
                || !fecha
                || !hora
                || (tipo === 'reunion' && (
                  !camposReunion.modalidad
                  || (camposReunion.modalidad === 'presencial' && !camposReunion.ubicacion.trim())
                ))
              }
            >
              <CalendarPlus /> {guardandoTarea ? 'Confirmando…' : 'Agendar'}
            </Button>
          </div>
          {avisoVentana && (
            <p className="mt-1.5 text-[10px] font-medium text-muted-foreground">
              Fuera de la ventana L–S 07:00–20:00 (Ley 29571) — úsalo solo si el cliente lo pidió.
            </p>
          )}
          {errorTarea && <p role="alert" className="mt-2 text-xs text-destructive">{errorTarea}</p>}
        </fieldset>
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

  // SOLO analistas del ámbito del rol (espejo del WITH CHECK de leads_update):
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
      // el analista: aquí es donde llega el texto que el origen escribió mal y
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
    toast.success(v ? `Lead reasignado${sufijoDemo}` : `Lead parkeado sin analista${sufijoDemo}`)
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
          <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
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
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="ld-monto">Capital estimado *</Label>
              <div className="flex gap-2">
                <Input id="ld-monto" className="min-w-0 flex-1 tabular-nums" type="number" min={0.01} max={MONTO_ESTIMADO_MAX} step="0.01" inputMode="decimal" required aria-required="true" aria-invalid={invalido('monto_estimado')} aria-describedby={invalido('monto_estimado') ? 'ld-datos-error' : undefined} value={form.monto} onChange={campo('monto')} placeholder="Ej. 5000" />
                {/* Select envuelve el <select> en un div w-full. El ancho debe
                    fijarse en ESTE flex-item; aplicarlo al nodo interior deja
                    que el wrapper reclame toda la fila y aplaste el monto. */}
                <div className="w-24 shrink-0">
                  <Select
                    aria-label="Moneda del capital estimado"
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
          <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
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
          {/* Orden comercial: capital → categoría → analista → contacto → resto.
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
            <Fila label="Responsable comercial">
              {puedeReasignar ? (
                <Select
                  aria-label="Reasignar responsable comercial"
                  value={l.vendedor_id ?? ''}
                  onChange={(e) => onReasignar(e.target.value)}
                  className="h-8 text-xs"
                >
                  <option value="">Sin asignar (parkeado)</option>
                  {/* Conserva al responsable actual si es supervisor o ya no
                      está en el selector de analistas activos. No ofrece
                      otros supervisores como destinos de reasignación. */}
                  {l.vendedor_id && !vendedores.some((m) => m.perfil_id === l.vendedor_id) && (
                    <option value={l.vendedor_id}>{l.vendedor_nombre ?? 'Responsable actual'}</option>
                  )}
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
              Antes solo aparecía cuando había número, y eso dejaba al analista
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
            {textoCargadoPor(l) && <Fila label="Cargado por">{textoCargadoPor(l)}</Fila>}
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
        {a.detalle && (
          <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">{presentarCitas(a.detalle)}</p>
        )}
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
            Último: {presentarCitas(reciente.detalle)}
          </p>
        )}
        <p className="mt-0.5 text-[11px] text-muted-foreground/80">
          {reciente.autor_nombre} · {haceRelativo(reciente.creado_en, ahora)} · toca para ver todos
        </p>
      </button>
    </li>
  )
}

// Exportado para probar sus estados (cargando / error / vacío / cargar más)
// sin montar el drawer entero, como ProximaAccion.
export function Timeline({ l, escribe, activa, puedeRegistrarGestion, componiendo, setComponiendo }: { l: Lead; escribe: boolean; activa: boolean; puedeRegistrarGestion: boolean; componiendo: boolean; setComponiendo: (valor: boolean) => void }) {
  const { registrarActividad } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  // Historial POR LEAD (Fase 1 «sin topes», 19/09/2026): lo sirve
  // `crm.actividades_de_lead_fn` paginado por cursor. Antes se filtraba de la
  // lista global del ámbito, que PostgREST recorta a 1 000 filas: un supervisor
  // veía ~4 días de gestiones de su equipo y gerencia ~2 — y la ficha pintaba
  // «Lead creado» a secas, como si nadie hubiera trabajado el lead.
  const historial = useActividadesDeLead(l.id)
  const acts = historial.items
  const items = useMemo(() => agruparTimeline(acts), [acts])
  const [verTodo, setVerTodo] = useState(false)
  const visibles = verTodo ? items : items.slice(0, TOPE_TIMELINE)
  const ocultos = items.length - visibles.length
  // «Cargar más» pide otra página al servidor; a diferencia de «Ver N
  // anteriores» (pliegue LOCAL sobre lo ya cargado, con cuenta exacta) no
  // promete una cifra. Se sigue mostrando, deshabilitado, cuando ya no queda
  // historial: así el foco del teclado no se pierde al desaparecer el botón.
  const [pidioMas, setPidioMas] = useState(false)
  const muestraCargarMas = (verTodo || items.length <= TOPE_TIMELINE) && (historial.hayMas || pidioMas)
  // El botón no se DESHABILITA (un botón enfocado que se deshabilita pierde el
  // foco, y Radix no lo rescata): queda inerte con aria-disabled y la guarda.
  const cargarMasInerte = !historial.hayMas || historial.cargandoMas
  // Destino programático del foco al reintentar: el botón «Reintentar» se
  // desmonta al pulsarlo y, sin esto, Radix mandaría el foco al tope del drawer
  // (revisión a11y 19/09). No es parada del tabulador (tabIndex -1).
  const refSeccion = useRef<HTMLElement>(null)
  const [tipo, setTipo] = useState<TipoActividadManual>('llamada_realizada')
  const [detalle, setDetalle] = useState('')
  // La sección se abre mayormente para LEER el historial. El composer solo se
  // muestra cuando una acción operativa (por ejemplo, un aviso SLA) lo solicita.
  const [guardandoActividad, setGuardandoActividad] = useState(false)
  const [errorActividad, setErrorActividad] = useState<string | null>(null)
  // Gestión Diaria F2: una LLAMADA se registra con su resultado tipificado; el
  // composer abre el panel (con la nota ya escrita) en vez de mandar el tipo pelado.
  const [panelLlamada, setPanelLlamada] = useState(false)

  // Defensa terminal: aunque otra ruta futura intente activar el estado, una
  // identidad de supervisión no conserva ni revive el composer al cambiar rol.
  useEffect(() => {
    if (puedeRegistrarGestion) return
    setPanelLlamada(false)
    setComponiendo(false)
  }, [puedeRegistrarGestion, setComponiendo])

  const registrar = async () => {
    if (!puedeRegistrarGestion || guardandoActividad) return
    setErrorActividad(null)
    if (tipo === 'llamada_realizada' || tipo === 'llamada_no_contestada') {
      setPanelLlamada(true)
      return
    }
    const res = registrarActividad(l.id, tipo, detalle)
    if (!res.ok) {
      if (res.error) toast.error(res.error)
      return
    }
    if (res.persistido) {
      setGuardandoActividad(true)
      try {
        const confirmado = await res.persistido
        if (!confirmado) {
          setErrorActividad('No se confirmó el guardado. Conservamos tu actividad para reintentar.')
          return
        }
      } catch {
        setErrorActividad('No se confirmó el guardado. Conservamos tu actividad para reintentar.')
        return
      } finally { setGuardandoActividad(false) }
    }
    setDetalle('')
    setComponiendo(false)
    // NADA EN SILENCIO: un contacto de conversación sube la etapa por su cuenta
    // (lib/avance-automatico). El resto del CRM ya lo canta (`avisoDe` de
    // contacto.tsx) y aquí se tiraba el dato: el analista veía moverse el stepper
    // sin saber por qué. Mismo formato "hecho · hecho" y mismo orden.
    const partes = ['Actividad registrada']
    if (res.avance) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
    toast.success(`${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}`)
  }

  return (
    <section
      ref={refSeccion}
      tabIndex={-1}
      aria-label="Actividad del lead"
      className="rounded-lg outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Actividad</h3>
      {/* UNA sola región viva, siempre montada y fuera del <ol> (un <li> no
          admite role=status y una región que nace con texto no se anuncia). */}
      <p role="status" className="sr-only">
        {historial.cargando
          ? 'Cargando el historial…'
          : historial.cargandoMas
            ? 'Cargando más gestiones'
            : pidioMas
              ? `${acts.length} ${acts.length === 1 ? 'gestión cargada' : 'gestiones cargadas'}`
              : ''}
      </p>

      {puedeRegistrarGestion && panelLlamada && (
        <RegistrarResultado lead={l} notaInicial={detalle} onClose={() => {
          setPanelLlamada(false); setDetalle(''); setComponiendo(false)
          // El botón «Registrar» del composer se desmonta con el panel: el foco
          // vuelve a la sección Actividad, no al contenedor general de la ficha.
          requestAnimationFrame(() => refSeccion.current?.focus())
        }} />
      )}
      {escribe && activa && puedeRegistrarGestion && componiendo && (
        <div className="mt-2 space-y-2 rounded-xl border border-border bg-muted/40 p-3">
          <Select
            disabled={guardandoActividad}
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
            disabled={guardandoActividad}
            aria-label="Detalle de la actividad"
            value={detalle}
            onChange={(e) => setDetalle(e.target.value)}
            placeholder="Detalle (opcional)…"
            className="min-h-[56px] text-xs"
            autoFocus
          />
          {errorActividad && <p role="alert" className="text-xs text-destructive">{errorActividad}</p>}
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="ghost" disabled={guardandoActividad} onClick={() => setComponiendo(false)}>
              Cancelar
            </Button>
            <Button size="sm" disabled={guardandoActividad} onClick={() => void registrar()}>
              <Send /> {guardandoActividad ? 'Guardando…' : 'Registrar'}
            </Button>
          </div>
        </div>
      )}

      <div
        role="region"
        aria-label="Historial de actividades"
        className="ac-scroll mt-2 max-h-80 overflow-y-auto overscroll-contain rounded-lg pr-2 outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
      >
        <ol
          className="relative space-y-4 before:absolute before:inset-y-2 before:left-[13px] before:w-px before:bg-border"
          aria-busy={historial.cargando || historial.cargandoMas}
        >
        {/* Estados HONESTOS del historial servido: cargando, fallo y vacío se
            distinguen entre sí y de «Lead creado» (que hoy era la única señal). */}
        {historial.cargando && [0, 1].map((n) => (
          <li key={`esq-${n}`} className="flex gap-2.5" aria-hidden>
            <span className={CLASE_HITO} />
            <div className="min-w-0 flex-1 pt-1">
              <div className="h-3 w-40 animate-pulse rounded bg-muted motion-reduce:animate-none" />
              <div className="mt-1.5 h-2.5 w-24 animate-pulse rounded bg-muted motion-reduce:animate-none" />
            </div>
          </li>
        ))}
        {historial.error != null && !historial.cargando && (
          <li className="flex gap-2.5">
            <span className="w-7 shrink-0" aria-hidden />
            <div className="min-w-0 flex-1 pt-0.5">
              <p role="alert" className="text-xs text-destructive">
                {acts.length === 0
                  ? 'No se pudo cargar el historial de este lead.'
                  : 'No se pudo cargar el resto del historial.'}
              </p>
              <Button
                size="xs"
                variant="ghost"
                className="mt-1"
                onClick={() => {
                  refSeccion.current?.focus({ preventScroll: true })
                  historial.reintentar()
                }}
              >
                Reintentar
              </Button>
            </div>
          </li>
        )}
        {!historial.cargando && historial.error == null && acts.length === 0 && (
          <li className="flex gap-2.5">
            <span className="w-7 shrink-0" aria-hidden />
            <p className="pt-0.5 text-xs text-muted-foreground">Sin gestiones todavía.</p>
          </li>
        )}
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
        {muestraCargarMas && (
          <li className="flex gap-2.5">
            <span className="grid size-7 shrink-0 place-items-center text-muted-foreground [&_svg]:size-3.5">
              <MoreHorizontal aria-hidden />
            </span>
            <div className="min-w-0 flex-1">
              <button
                type="button"
                aria-disabled={cargarMasInerte || undefined}
                onClick={() => {
                  if (cargarMasInerte) return
                  setPidioMas(true)
                  // Pedir más implica desplegar: si no, la página nueva podría
                  // quedar plegada tras «Ver N anteriores» y este botón
                  // desmontarse con el foco dentro.
                  setVerTodo(true)
                  historial.cargarMas()
                }}
                className="min-h-6 cursor-pointer pt-1 text-left text-[11px] font-semibold text-muted-foreground transition-colors hover:text-foreground pointer-coarse:min-h-8 aria-disabled:cursor-default aria-disabled:hover:text-muted-foreground"
              >
                {historial.cargandoMas
                  ? 'Cargando más gestiones…'
                  : historial.error != null
                    ? 'No se pudo cargar más'
                    : historial.hayMas
                      ? 'Cargar más gestiones'
                      : 'Historial completo'}
              </button>
            </div>
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
      </div>
    </section>
  )
}

// ── Diálogos de cierre ────────────────────────────────────────────────────────

/** El botón sólo aporta el origen; la inversión usa el flujo compartido. */
export function DialogConvertir({l,onClose,condicionesTasa}: {
  l:Lead;onClose:()=>void;condicionesTasa?:CondicionesTasaLead|undefined;bloqueoTasa?:string|null
}) {
  const {yo}=useAuth()
  return yo?.demo
    ? <InversionDesdeLeadDemo l={l} onClose={onClose} condicionesTasa={condicionesTasa}/>
    : <InversionDesdeLead l={l} onClose={onClose} condicionesTasa={condicionesTasa}/>
}

function DialogDescartar({ l, onClose }: { l: Lead; onClose: () => void }) {
  const { descartar } = useCRMData()
  const { yo } = useAuth()
  const [motivo, setMotivo] = useState<MotivoDescarte>('sin_interes')
  const [nota, setNota] = useState('')

  // «No responde» no es una opinión: es una AFIRMACIÓN DE HECHO sobre el
  // cliente. Sin intentos registrados es falsa, y encima ensucia la métrica con
  // la que se decide de dónde traer leads. El veto se calcula del historial POR
  // LEAD (Fase 1 «sin topes»); mientras no haya llegado, o si falló, no se
  // afirma nada: la opción queda vetada con la razón a la vista.
  const historial = useActividadesDeLead(l.id)
  const veto = historial.cargando
    ? '«No responde» espera al historial del lead, que todavía se está cargando.'
    : historial.error != null
      ? '«No responde» necesita el historial del lead y no se pudo cargar. Cierra, reintenta en la ficha y vuelve.'
      : vetoNoResponde(historial.items)

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
              // desapareciera, el analista elegiría "Otro" y perderíamos el dato.
              const vetado = veto != null && MOTIVOS_CON_EVIDENCIA.has(m.k)
              // El sufijo dice la razón REAL: mientras carga o si falló, no es
              // «faltan intentos» (revisión a11y 19/09).
              const sufijo = historial.cargando
                ? 'cargando historial'
                : historial.error != null
                  ? 'historial no disponible'
                  : VETO_CORTO
              return (
                <option key={m.k} value={m.k} disabled={vetado}>
                  {vetado ? `${m.label} — ${sufijo}` : m.label}
                </option>
              )
            })}
          </Select>
          {/* Se pinta SIEMPRE que haya veto, no solo cuando el motivo vetado
              está seleccionado: el `aria-describedby` del select ya lo promete,
              y si el <p> no existe la razón no llega ni al lector de pantalla
              ni a la vista — el analista solo veía una opción deshabilitada.
              aria-live: cuando el historial termina de cargar, la razón cambia
              (o desaparece) y el lector debe enterarse sin re-tabular. */}
          {veto && (
            <p id="ld-motivo-veto" aria-live="polite" className="text-[11px] font-medium text-warning-text">
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
