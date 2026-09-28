// El resumen del analista en el panel del supervisor (diseño de Gestión Diaria,
// 27/09/2026): el aviso de lo vencido, 4 cuadros, las llamadas por hora y una
// línea con lo que el diseño no dibuja pero hoy existe. Explica la foto del
// servidor; no reconstruye cifras desde el store.
//
// El diseño pone «WhatsApp» en el cuarto cuadro; la foto no trae ese conteo por
// analista, así que va «Pendientes» (decisión del plan, 27/09). Gerencia sigue
// con `DetalleAnalista` hasta su propio plan (revisión Codex del plan).
import type { JSX, ReactNode } from 'react'
import { AlertCircle, ChevronRight } from 'lucide-react'
import { COLOR_NIVEL, ETIQUETA_NIVEL, horaLimaDe } from '@/lib/gestion-diaria-analista'
import {
  MOTIVOS_EQUIPO, horarioConfirmado, presentarAtencion, presentarContacto, tiempoSinLlamar,
  type FilaEquipoPresentada,
} from '@/lib/gestion-diaria-equipo'
import { haceRelativo } from '@/components/app/actividad-visual'
import { BarrasPorHora } from './barras-por-hora'
import { cn } from '@/lib/utils'

const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
const ENLACE = cn('mt-1.5 inline-flex min-h-6 cursor-pointer items-center gap-0.5 rounded-md text-xs font-semibold text-[var(--accent-press)] hover:underline pointer-coarse:min-h-11', FOCO)

function Cuadro({ etiqueta, children }: { etiqueta: string; children: ReactNode }): JSX.Element {
  return (
    <div className="min-w-0 rounded-xl bg-muted/70 px-3.5 py-3">
      <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</dt>
      <dd className="mt-1 min-w-0">{children}</dd>
    </div>
  )
}

const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`

const FECHA_RESUMEN = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })

export function ResumenAnalista({ fila: f, dia, minimo, esHoy, ahora, abrirLlamadas, abrirPendientes, abrirCitas }: {
  fila: FilaEquipoPresentada
  /** El día consultado (AAAA-MM-DD): se dice, también dentro de la ventana. */
  dia: string
  minimo: number
  /** Solo hoy tiene sentido «hace 25 min». */
  esHoy: boolean
  ahora: number
  abrirLlamadas: () => void
  /** Sin él (gerencia, hasta tener permiso sobre pendientes) las vencidas se dicen sin enlace. */
  abrirPendientes?: ((soloVencidas: boolean) => void) | undefined
  /** G4b: la lista exacta de las citas agendadas ese día. */
  abrirCitas?: (() => void) | undefined
}): JSX.Element {
  const atencion = presentarAtencion(f)
  const contacto = presentarContacto(f.marcador, minimo)
  // Con número, las vencidas van en su aviso; sin número confirmado, se dicen en la lista.
  const otros = f.tareas_vencidas > 0 ? atencion.lista.filter((m) => m !== MOTIVOS_EQUIPO.tarea_vencida) : atencion.lista
  const contestadasPorHora = f.marcador.por_hora.reduce((total, h) => total + h.contestadas, 0)
  const ultima = f.marcador.ultima_llamada_en
  return (
    <div className="space-y-4">
      <p className="text-xs text-[var(--muted-foreground-strong)]">
        {plural(f.gestiones_hoy, 'gestión', 'gestiones')} · {FECHA_RESUMEN.format(new Date(`${dia}T12:00:00-05:00`))} · Lima
      </p>
      {f.tareas_vencidas > 0 && (abrirPendientes ? (
        <button type="button" onClick={() => abrirPendientes(true)}
          className={cn('flex w-full cursor-pointer items-center gap-2.5 rounded-xl bg-destructive/10 px-4 py-3 text-left text-sm font-bold text-[var(--destructive-text)] transition-colors hover:bg-destructive/15', FOCO)}>
          <AlertCircle aria-hidden className="size-[18px] shrink-0" />
          <span className="flex-1">{plural(f.tareas_vencidas, 'tarea vencida', 'tareas vencidas')}</span>
          <ChevronRight aria-hidden className="size-4 shrink-0" />
        </button>
      ) : (
        <p className="flex w-full items-center gap-2.5 rounded-xl bg-destructive/10 px-4 py-3 text-sm font-bold text-[var(--destructive-text)]">
          <AlertCircle aria-hidden className="size-[18px] shrink-0" />{plural(f.tareas_vencidas, 'tarea vencida', 'tareas vencidas')}
        </p>
      ))}
      {otros.length > 0 && (
        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
        <ul role="list" aria-label="Otros motivos de atención" className="space-y-1 rounded-xl bg-warning/10 px-4 py-2.5 text-[13px] font-semibold text-[var(--warning-text)]">
          {otros.map((m) => <li key={m}>{m}</li>)}
        </ul>
      )}

      <dl className="grid grid-cols-2 gap-2.5">
        <Cuadro etiqueta="Llamadas">
          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.marcador.llamadas}</span>
          <span className="block text-xs text-[var(--muted-foreground-strong)]">{plural(f.marcador.contestadas, 'contestó', 'contestaron')}</span>
          <button type="button" onClick={abrirLlamadas} aria-label={`Ver llamadas del día de ${f.nombre_completo}`} className={ENLACE}>
            Ver llamadas<ChevronRight aria-hidden className="size-3.5" />
          </button>
        </Cuadro>
        <Cuadro etiqueta="Contacto">
          <span aria-hidden="true" className={cn('block font-extrabold leading-tight tabular-nums',
            contacto.estado === 'evaluado' ? 'text-[28px] text-primary' : 'text-base text-[var(--muted-foreground-strong)]')}>{contacto.valor}</span>
          <span aria-hidden="true" className="block text-xs text-[var(--muted-foreground-strong)]">
            {contacto.estado === 'evaluado'
              ? <>{contacto.detalle} · <span className="font-semibold" style={{ color: COLOR_NIVEL[contacto.nivel!] }}>{ETIQUETA_NIVEL[contacto.nivel!]}</span></>
              : contacto.estado === 'sin_muestra' ? `Sin muestra suficiente · ${contacto.detalle}` : contacto.detalle}
          </span>
          <span className="sr-only">{contacto.accesible}</span>
        </Cuadro>
        <Cuadro etiqueta="Citas agendadas">
          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.marcador.citas_agendadas}</span>
          <span className="block text-xs text-[var(--muted-foreground-strong)]">desde «Agendó cita»</span>
          {abrirCitas && <button type="button" onClick={abrirCitas} aria-label={`Ver citas agendadas de ${f.nombre_completo}`} className={ENLACE}>
            Ver citas<ChevronRight aria-hidden className="size-3.5" />
          </button>}
        </Cuadro>
        <Cuadro etiqueta="Pendientes">
          <span className="block text-[28px] font-extrabold leading-tight tabular-nums text-primary">{f.tareas_pendientes}</span>
          <span className={cn('block text-xs', f.tareas_vencidas > 0 ? 'font-semibold text-[var(--destructive-text)]' : 'text-[var(--muted-foreground-strong)]')}>
            {plural(f.tareas_vencidas, 'vencida', 'vencidas')}
          </span>
          {abrirPendientes && <button type="button" onClick={() => abrirPendientes(false)} aria-label={`Ver pendientes de ${f.nombre_completo}`} className={ENLACE}>
            Ver pendientes<ChevronRight aria-hidden className="size-3.5" />
          </button>}
        </Cuadro>
      </dl>

      {/* El desglose por hora se confirma ANTES de dibujarlo: con un desglose
          parcial no se pintan ceros como sustituto. */}
      {!horarioConfirmado(f.marcador) ? (
        <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">
          No se pudo confirmar el desglose por hora. Consulta las llamadas en el registro; no se muestran ceros como sustituto.
        </p>
      ) : f.marcador.llamadas === 0 ? (
        <div className="space-y-1">
          <h4 className="text-[15px] font-extrabold text-primary">Llamadas por hora</h4>
          <p className="text-[13px] text-[var(--muted-foreground-strong)]">No hay llamadas registradas ese día. Esto no indica ausencia ni descarta otras gestiones.</p>
        </div>
      ) : (
        <div className="space-y-1.5">
          <BarrasPorHora porHora={f.marcador.por_hora} titulo="Llamadas por hora" alto={96}
            apoyo={ultima !== null ? `Última llamada ${horaLimaDe(ultima)}${esHoy ? ` · ${haceRelativo(ultima, ahora)}` : ''}` : undefined} />
          {contestadasPorHora !== f.marcador.contestadas && (
            <p className="text-xs text-[var(--muted-foreground-strong)]">Las barras incluyen respuestas de «Número errado» o «No es la persona», que el contacto útil excluye.</p>
          )}
        </div>
      )}

      {/* Lo que hoy da el detalle y el diseño no dibuja: se conserva, compacto. */}
      <div role="group" aria-label="Más datos del día" className="border-t border-border pt-3">
      <dl className="grid grid-cols-1 gap-y-1.5 text-[12.5px]">
        {([
          ['Leads distintos', f.marcador.leads_tocados], ['Llamadas por lead', f.llamadas_por_lead ?? '—'],
          ['Primera llamada', horaLimaDe(f.marcador.primera_llamada_en)], ['Tiempo sin llamar', tiempoSinLlamar(f.minutos_sin_llamar)],
          ['Última gestión', horaLimaDe(f.ultima_gestion_en)], ['Citas pendientes del día', f.citas_hoy],
        ] as const).map(([titulo, valor]) => (
          <div key={titulo} className="flex min-w-0 items-baseline justify-between gap-2">
            <dt className="text-[var(--muted-foreground-strong)]">{titulo}</dt>
            {/* «—» se oye «Sin dato», no como silencio (revisión a11y, 27/09). */}
            <dd className="font-semibold tabular-nums text-foreground">{valor === '—' ? <><span aria-hidden="true">—</span><span className="sr-only">Sin dato</span></> : valor}</dd>
          </div>
        ))}
      </dl>
      </div>
    </div>
  )
}
