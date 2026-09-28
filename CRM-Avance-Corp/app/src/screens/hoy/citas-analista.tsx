// Hoy · analista — «Tus citas» v2 (Miguel, 28/09/2026: «que esa ficha de citas
// sea más versátil, aprende a usar bien los espacios, hay demasiado negativo»).
//
// TODAS las citas pendientes del analista (tareas `reunion` de sus leads y de
// los clientes de su cartera), partidas en CIFRAS QUE FILTRAN (vencidas · hoy ·
// mañana · semana · todas), una tira de los próximos 7 días con el conteo de
// cada uno, y una lista de filas de UNA línea que se desplaza DENTRO de la
// ficha: sin tope de 8 ni «+N más». El pie no lleva importes (un total que no
// se puede abrir no sirve): el capital vive en cada fila, que sí se abre.
//
// PARTICIÓN (todo en Lima, con `fechaLima`; decisión tras la refutación de
// Codex, 28/09/2026):
//  · Vencidas = `ev.vencida`, de cualquier fecha (chip ámbar, transversal).
//  · Hoy / Mañana / Semana (hoy → hoy+6) / celdas de la tira = SOLO citas NO
//    vencidas de esa(s) fecha(s): el chip «Hoy» y la celda de hoy dan la misma
//    cifra, y cada lista pinta EXACTAMENTE las filas que su cifra cuenta.
//  · Todas = todas las pendientes (vencidas incluidas): el mismo número que el
//    badge de cabecera, que por eso es un botón (todo número se abre).
//
// El reloj (`ahora`) llega por prop desde la pantalla (su `useAhora`): la tira,
// los rótulos y la selección se derivan de él, nunca del reloj del navegador.
import {
  useId,
  useMemo,
  useState,
  type CSSProperties,
  type JSX,
  type KeyboardEvent as ReactKeyboardEvent,
} from 'react'
import { Building2, CalendarClock, ChevronRight, CircleCheckBig, Video, type LucideIcon } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { SectionHead } from '@/components/common/section-head'
import { VacioCompacto } from '@/components/common/vacio-compacto'
import { DIAS, type EventoAgenda } from '@/lib/agenda-derivada'
import { derivarReunionOperativa, type ReunionOperativaDerivada } from '@/lib/reunion-operativa'
import { money } from '@/lib/format'
import { abrirInversionista } from '@/lib/router'
import { cn } from '@/lib/utils'
import type { Lead, Tarea } from '@/lib/tipos'
import {
  agruparPorDia,
  filasDelFiltro,
  filtroInicial,
  filtroVigente,
  partesLima,
  particionarCitas,
  type FiltroCitas,
  type ParticionCitas,
} from './citas-analista-particion'

// ── Lugar / enlace ───────────────────────────────────────────────────────────

/** Host del enlace («meet.google.com»); si no es una URL, el texto recortado. */
function hostDe(enlace: string): string {
  try {
    return new URL(enlace).host
  } catch {
    const texto = enlace.trim()
    return texto.length > 40 ? `${texto.slice(0, 40)}…` : texto
  }
}

/** Presencial → la ubicación; virtual (o sin clasificar) → el host del enlace,
 * y sin enlace la ubicación de respaldo que `derivarReunionOperativa` conserva. */
function lugarDe(reunion: ReunionOperativaDerivada): string | null {
  if (reunion.modalidad !== 'presencial' && reunion.enlace) return hostDe(reunion.enlace)
  return reunion.destino
}

const ICONO_MODALIDAD: Record<'presencial' | 'virtual', { icono: LucideIcon; label: string }> = {
  presencial: { icono: Building2, label: 'Presencial' },
  virtual: { icono: Video, label: 'Virtual' },
}

// ── Fila ─────────────────────────────────────────────────────────────────────

/** Una cita en UNA línea de 48 px: hora (ancla) · barra de estado · nombre ·
 * modalidad como icono · lugar o enlace · capital · cerrar · ficha. Mismo
 * ritmo que `FilaAgenda` (role=button, teclado, hover, foco visible), sin los
 * badges de tipo y modalidad, que le robaban el ancho al nombre. */
function FilaCita({
  ev,
  lead,
  tarea,
  particion: p,
  abrirLead,
  onCompletar,
}: {
  ev: EventoAgenda
  lead: Lead | undefined
  tarea: Tarea | undefined
  particion: ParticionCitas
  abrirLead: (id: string) => void
  onCompletar: (id: string) => void
}): JSX.Element {
  // `useId` porque la misma cita puede pintarse también en la agenda del día.
  const metaId = useId()
  const ms = Date.parse(ev.vence_en)
  const partes = Number.isFinite(ms) ? partesLima(ms) : null
  const fecha = partes?.fecha ?? ''
  // La hora ya viene resuelta en Lima dentro de `cuando` ('Día · HH:MM').
  const hora = ev.cuando.split(' · ')[1] ?? ''
  const estado = ev.vencida ? 'vencida' : fecha === p.hoy ? 'hoy' : 'futura'
  const subrotulo =
    estado === 'vencida'
      ? 'Vencida'
      : estado === 'hoy'
        ? 'Hoy'
        : fecha === p.manana
          ? 'Mañana'
          : (DIAS[partes?.diaSemana ?? -1] ?? '')
  // Color LOCAL, no `ev.color` (las reuniones traen violeta, fuera de la
  // paleta): ámbar vencida, azul hoy, navy el resto. El texto ámbar va en
  // `--warning-text` (#d97706 sobre blanco da 3,2:1 y no sirve para texto).
  const barra = estado === 'vencida' ? 'var(--warning)' : estado === 'hoy' ? 'var(--accent)' : 'var(--primary)'
  const textoHora = estado === 'vencida' ? 'text-warning-text' : estado === 'hoy' ? 'text-accent' : 'text-primary'

  // Nombre: el lead resuelto, su nombre; cliente (perfil/inversionista) o lead
  // ausente de la cartera cargada, el título de la tarea. Nunca se inventa.
  const nombre = lead?.nombre_completo ?? ev.titulo
  const esCliente = Boolean(ev.perfil_id) || Boolean(ev.inversionista_id)
  const capital = lead?.monto_estimado != null ? money(lead.monto_estimado, lead.moneda) : null
  const reunion = derivarReunionOperativa({
    modalidad: tarea?.modalidad_reunion,
    ubicacion: tarea?.ubicacion_reunion,
    enlace: tarea?.enlace_reunion,
  })
  const modalidad = reunion.modalidad ? ICONO_MODALIDAD[reunion.modalidad] : null
  const IconoModalidad = modalidad?.icono
  const lugar = lugarDe(reunion)

  const abreFicha = ev.lead_id !== '' || Boolean(ev.inversionista_id)
  const abrir = () => {
    if (ev.inversionista_id) abrirInversionista(ev.inversionista_id)
    else if (ev.lead_id) abrirLead(ev.lead_id)
  }
  // Con role="button" el nombre lo fija el aria-label (título + hora) y el
  // resto —día, modalidad, lugar, capital— viaja como DESCRIPCIÓN.
  const descripcion = [
    `${metaId}-h`,
    modalidad ? `${metaId}-m` : null,
    lugar ? `${metaId}-l` : null,
    capital ? `${metaId}-c` : null,
  ]
    .filter((id): id is string => id != null)
    .join(' ')
  const interaccion = abreFicha
    ? {
        role: 'button' as const,
        tabIndex: 0,
        'aria-label': `Abrir ficha — ${ev.titulo}, ${hora}`,
        'aria-describedby': descripcion,
        onClick: abrir,
        onKeyDown: (e: ReactKeyboardEvent<HTMLDivElement>) => {
          // Solo teclas sobre la FILA: un Enter en «Cerrar tarea» burbujea
          // hasta aquí y el preventDefault le robaría su click nativo.
          if (e.target !== e.currentTarget) return
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            abrir()
          }
        },
      }
    : {}

  return (
    <div
      {...interaccion}
      className={cn(
        'group flex min-h-12 items-center gap-2 rounded-lg px-2.5 py-1.5 transition-colors',
        abreFicha
          ? 'cursor-pointer hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40'
          : 'cursor-default',
      )}
    >
      <div id={`${metaId}-h`} className="w-11 shrink-0 text-center leading-none">
        <p className={`text-base font-extrabold tabular-nums ${textoHora}`}>{hora}</p>
        <p
          className={`mt-1 text-[10px] font-semibold ${estado === 'vencida' ? 'text-warning-text' : 'text-[var(--muted-foreground-strong)]'}`}
        >
          {subrotulo}
        </p>
      </div>
      <span className="w-1 self-stretch rounded" style={{ background: barra, minHeight: 36 }} aria-hidden />
      <p className="flex min-w-0 flex-1 basis-2/5 items-center gap-1.5 text-sm font-semibold" title={nombre}>
        <span className="truncate">{nombre}</span>
        {esCliente && (
          <Badge color="var(--primary)" className="shrink-0 text-[10px]">
            Cliente
          </Badge>
        )}
      </p>
      {modalidad && IconoModalidad && (
        <span
          id={`${metaId}-m`}
          role="img"
          aria-label={modalidad.label}
          title={modalidad.label}
          className="ac-chip grid size-[22px] shrink-0 place-items-center rounded-md [&_svg]:size-3.5"
          style={{ '--c': 'var(--accent)' } as CSSProperties}
        >
          <IconoModalidad aria-hidden />
        </span>
      )}
      {/* El lugar solo cuando la ficha tiene ancho (container query): en una
          columna estrecha ese espacio es del nombre. */}
      {lugar && (
        <span
          id={`${metaId}-l`}
          className="hidden min-w-0 flex-1 basis-[30%] truncate text-[11px] text-[var(--muted-foreground-strong)] @[420px]:block"
          title={lugar}
        >
          {lugar}
        </span>
      )}
      {capital && (
        <span
          id={`${metaId}-c`}
          className="ml-auto shrink-0 text-[11px] font-semibold tabular-nums text-[var(--muted-foreground-strong)]"
        >
          {capital}
        </span>
      )}
      <button
        type="button"
        aria-label={`Cerrar tarea — ${ev.titulo}`}
        title="Cerrar tarea (registra el resultado y agenda la siguiente)"
        className="grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--accent)]/15 hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        onClick={(e) => {
          e.stopPropagation()
          onCompletar(ev.id)
        }}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <CircleCheckBig className="size-4" aria-hidden />
      </button>
      {abreFicha && (
        <ChevronRight
          className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
          aria-hidden
        />
      )}
    </div>
  )
}

// ── Controles ────────────────────────────────────────────────────────────────

const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'

/** Cifra que filtra: botón real con estado presionado. Activo = navy; el de
 * vencidas, ámbar suave con texto en `--warning-text` (≥ 4,5:1). */
function Chip({
  activo,
  ambar = false,
  onClick,
  children,
}: {
  activo: boolean
  ambar?: boolean
  onClick: () => void
  children: string
}): JSX.Element {
  return (
    <button
      type="button"
      aria-pressed={activo}
      onClick={onClick}
      className={cn(
        'inline-flex min-h-7 cursor-pointer items-center rounded-full border px-2.5 text-[11px] font-bold leading-none transition-colors',
        FOCO,
        activo
          ? 'border-primary bg-primary text-primary-foreground'
          : ambar
            ? 'border-warning/30 bg-warning/10 text-warning-text hover:bg-warning/15'
            : 'border-border bg-card text-[var(--muted-foreground-strong)] hover:bg-muted',
      )}
    >
      {children}
    </button>
  )
}

function textoCitas(n: number): string {
  return n === 1 ? '1 cita' : `${n} citas`
}

// ── Ficha ────────────────────────────────────────────────────────────────────

export function CitasAnalista({
  citas,
  tareaPorId,
  leadPorId,
  abrirLead,
  onCompletar,
  ahora,
  disposicion = 'libre',
  className,
}: {
  /** Ya filtradas a `reunion` y ordenadas por vence_en (vencidas primero). */
  citas: EventoAgenda[]
  tareaPorId: ReadonlyMap<string, Tarea>
  leadPorId: (id: string) => Lead | undefined
  abrirLead: (id: string) => void
  onCompletar: (id: string) => void
  /** El reloj vivo de la pantalla (useAhora): de él salen hoy, la tira y los rótulos. */
  ahora: number
  /** `columna`: la ficha llena la altura de su columna y la lista se desplaza
   *  dentro (modo activo, dos columnas). `libre`: altura natural, lista con
   *  tope de 60vh (legado/demo, a todo el ancho). */
  disposicion?: 'columna' | 'libre'
  className?: string
}): JSX.Element {
  const particion = useMemo(() => particionarCitas(citas, ahora), [citas, ahora])
  const [elegido, setElegido] = useState<FiltroCitas>(() => filtroInicial(particion))
  const filtro = filtroVigente(elegido, particion)
  const filas = filasDelFiltro(particion, filtro)
  const grupos = agruparPorDia(filas, particion)
  const { nVencidas, nHoy, nManana, nSemana, nTodas, tira } = particion

  // Vacío del filtro (hay citas, pero no en esta vista): una línea y una salida
  // que sí tiene filas.
  const salida: { filtro: FiltroCitas; label: string } =
    nSemana > 0 && filtro !== 'semana' ? { filtro: 'semana', label: 'Ver la semana' } : { filtro: 'todas', label: 'Ver todas' }
  const mensajeVacio =
    filtro === 'vencidas' ? 'Sin citas vencidas' : filtro === 'semana' ? 'Sin citas esta semana' : 'Sin citas este día'

  return (
    <Card
      className={cn(
        '@container flex flex-col',
        disposicion === 'columna' && 'min-h-0',
        // Sin citas la tarjeta no se estira a la altura de la agenda: mejor el
        // fondo de la página que una tarjeta blanca vacía de medio metro.
        disposicion === 'columna' && citas.length === 0 && 'lg:self-start',
        className,
      )}
    >
      <SectionHead
        className="shrink-0"
        icon={CalendarClock}
        title="Tus citas"
        right={
          nTodas > 0 ? (
            // El total ES el filtro «Todas» (todo número se abre): botón, no badge.
            <button
              type="button"
              aria-pressed={filtro === 'todas'}
              title="Ver todas las citas"
              onClick={() => setElegido('todas')}
              className={cn(
                'inline-flex min-h-6 cursor-pointer items-center rounded-full px-2 text-[11px] font-bold leading-none transition-colors',
                FOCO,
                filtro === 'todas' ? 'bg-primary text-primary-foreground' : 'ac-chip',
              )}
              style={{ '--c': nVencidas > 0 ? 'var(--warning-text)' : 'var(--accent)' } as CSSProperties}
            >
              {`${nTodas} ${nTodas === 1 ? 'agendada' : 'agendadas'}`}
              {nVencidas > 0 ? ` · ${nVencidas} vencida${nVencidas === 1 ? '' : 's'}` : ''}
            </button>
          ) : undefined
        }
      />
      <CardContent className="flex min-h-0 flex-1 flex-col gap-2 pt-0">
        {nTodas === 0 ? (
          <VacioCompacto
            icono={CalendarClock}
            titulo="Sin citas agendadas"
            detalle="Agenda la próxima cita desde la ficha del lead."
          />
        ) : (
          <>
            <div className="flex shrink-0 flex-wrap gap-1.5" role="group" aria-label="Filtrar citas">
              {nVencidas > 0 && (
                <Chip activo={filtro === 'vencidas'} ambar onClick={() => setElegido('vencidas')}>
                  {`⚠ ${nVencidas} ${nVencidas === 1 ? 'vencida' : 'vencidas'}`}
                </Chip>
              )}
              <Chip activo={filtro === 'hoy'} onClick={() => setElegido('hoy')}>{`Hoy ${nHoy}`}</Chip>
              <Chip activo={filtro === 'manana'} onClick={() => setElegido('manana')}>{`Mañana ${nManana}`}</Chip>
              <Chip activo={filtro === 'semana'} onClick={() => setElegido('semana')}>{`Semana ${nSemana}`}</Chip>
              <Chip activo={filtro === 'todas'} onClick={() => setElegido('todas')}>{`Todas ${nTodas}`}</Chip>
            </div>
            {/* Tira «Próximos 7 días»: cuántas citas hay cada día; hoy con anillo,
                el día elegido en navy. Clic = ese día; otro clic = la semana. */}
            <div
              className="grid shrink-0 grid-cols-7 gap-1 rounded-xl bg-muted p-1.5"
              role="group"
              aria-label="Próximos 7 días"
            >
              {tira.map((d) => {
                const seleccionado = filtro === `dia:${d.fecha}`
                return (
                  <button
                    key={d.fecha}
                    type="button"
                    aria-pressed={seleccionado}
                    aria-current={d.esHoy ? 'date' : undefined}
                    aria-label={`${d.diaLargo} ${d.numero}, ${d.n === 0 ? 'sin citas' : textoCitas(d.n)}`}
                    onClick={() => setElegido(seleccionado ? 'semana' : `dia:${d.fecha}`)}
                    className={cn(
                      'flex min-h-[54px] cursor-pointer flex-col items-center justify-center rounded-lg px-0.5 py-1 leading-none transition-colors',
                      'focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-ring',
                      seleccionado ? 'bg-primary text-primary-foreground' : 'hover:bg-card',
                      d.esHoy && !seleccionado && 'ring-2 ring-inset ring-primary',
                    )}
                  >
                    <span
                      className={cn(
                        'text-[10px] font-semibold uppercase tracking-[0.06em]',
                        seleccionado ? 'text-primary-foreground/80' : 'text-[var(--muted-foreground-strong)]',
                      )}
                    >
                      {d.dia}
                    </span>
                    <span
                      className={cn(
                        'mt-1 text-[15px] font-extrabold',
                        !seleccionado && d.n === 0 && 'text-[var(--muted-foreground-strong)]',
                      )}
                    >
                      {d.numero}
                    </span>
                    <span
                      className={cn(
                        'mt-1 text-[10px] font-bold tabular-nums',
                        seleccionado
                          ? 'text-primary-foreground'
                          : d.n > 0
                            ? 'text-accent'
                            : 'text-[var(--muted-foreground-strong)]',
                      )}
                    >
                      {d.n}
                    </span>
                  </button>
                )
              })}
            </div>
            <div
              className={cn(
                'ac-scroll flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto',
                disposicion === 'libre' && 'max-h-[60vh]',
              )}
            >
              {grupos.length === 0 ? (
                <div className="flex items-center gap-3 rounded-lg bg-muted/40 px-3 py-2.5">
                  <p className="text-sm font-semibold">{mensajeVacio}</p>
                  <button
                    type="button"
                    onClick={() => setElegido(salida.filtro)}
                    className={`ml-auto shrink-0 cursor-pointer rounded text-[11px] font-bold text-accent hover:underline ${FOCO}`}
                  >
                    {salida.label}
                  </button>
                </div>
              ) : (
                grupos.map((grupo) => (
                  <div key={grupo.clave} className="flex flex-col gap-0.5">
                    <h4 className="px-2.5 pt-1.5 text-[10px] font-extrabold uppercase tracking-[0.1em] text-[var(--muted-foreground-strong)]">
                      {grupo.rotulo}
                    </h4>
                    {grupo.filas.map((ev) => (
                      <FilaCita
                        key={ev.id}
                        ev={ev}
                        lead={ev.lead_id ? leadPorId(ev.lead_id) : undefined}
                        tarea={tareaPorId.get(ev.id)}
                        particion={particion}
                        abrirLead={abrirLead}
                        onCompletar={onCompletar}
                      />
                    ))}
                  </div>
                ))
              )}
            </div>
            <div className="flex shrink-0 items-center gap-2 border-t border-border pt-2.5 text-[11px] text-[var(--muted-foreground-strong)]">
              {/* Sin importes: un total que no se puede abrir no sirve. La cifra
                  de la semana sí se abre (activa el filtro). */}
              <button
                type="button"
                aria-pressed={filtro === 'semana'}
                onClick={() => setElegido('semana')}
                className={`cursor-pointer rounded font-semibold text-foreground/80 hover:underline ${FOCO}`}
              >
                {`Semana: ${textoCitas(nSemana)}`}
              </button>
              <a
                href="#/agenda"
                className="ml-auto inline-flex min-h-6 items-center rounded font-bold text-accent hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              >
                Ver en Agenda ›
              </a>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}
