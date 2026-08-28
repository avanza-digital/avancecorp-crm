// Agenda del equipo (Fase F) — panel sobre la RPC crm.metricas_agenda_fn,
// leído como la supervisión de distribución: totales del ámbito primero, una
// sección por supervisor cuando hay varios equipos (caso gerencia) y detalle
// por miembro solo cuando registra algo — los miembros todo-en-cero se
// colapsan en una línea expandible ("no registra nada" sigue siendo señal del
// manager, pero ya no un muro de ceros). Semáforo sin verde (regla de la
// casa): rojo solo para no-shows repetidos.
//
// Desde 2026-08-23 este panel es SOLO producción (toques y cierres): el
// rezago de cada miembro —vencidas, sin próxima acción— vive en «Tu equipo
// hoy», pegado a la persona. Antes salía en las dos tarjetas, una al lado de
// la otra, y el supervisor juzgaba al mismo vendedor dos veces.
import type { JSX } from 'react'
import { CalendarClock, ChevronRight } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { SegmentBar } from '@/components/common/stat-strip'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { SEMAFORO } from '@/lib/semaforo'
import { cn } from '@/lib/utils'
import {
  agruparPorEquipo,
  canceladasAjenas,
  canceladasPropias,
  canceladasSistema,
  resumenAgenda,
  separarPorActividad,
  type GrupoAgendaEquipo,
  type ResumenAgenda,
} from '@/lib/agenda-equipo-vista'
import type { MetricaAgendaVendedor, MetricasAgenda } from '@/lib/metricas-agenda'
import type { Miembro } from '@/lib/tipos'

/** Ratio de toques por día en es-PE (coma decimal): «1,7». */
const RATIO_DIA = new Intl.NumberFormat('es-PE', { maximumFractionDigits: 1 })

/** Sub-línea bajo el nombre: rol + carga y planificación que salieron de columnas. */
function subLineaDe(ven: MetricaAgendaVendedor): string | null {
  const partes: string[] = []
  if (ven.rol === 'supervisor') partes.push('supervisor')
  if (ven.pendientes > 0) {
    partes.push(`${ven.pendientes} ${ven.pendientes === 1 ? 'pendiente' : 'pendientes'}`)
  }
  if (ven.reprogramaciones > 0) {
    partes.push(`×${ven.reprogramaciones} ${ven.reprogramaciones === 1 ? 'movida' : 'movidas'}`)
  }
  if (ven.reuniones_realizadas > 0) {
    partes.push(`${ven.reuniones_realizadas} ${ven.reuniones_realizadas === 1 ? 'cita' : 'citas'}`)
  }
  return partes.length > 0 ? partes.join(' · ') : null
}

/**
 * Desglose crudo de cierres para la sub-línea (omite las partes en cero).
 *
 * Las canceladas van SEPARADAS desde 2026-07-26 y con nombres distintos a
 * propósito: «anuladas» es una decisión del asesor sobre su agenda (y pesa en
 * su %), «cerradas por el lead» es bookkeeping del sistema al convertirse o
 * descartarse el prospecto (y no pesa). Llamarlas igual era exactamente el
 * problema que Miguel señaló — un supervisor no puede juzgar un número que
 * mezcla "decidió no hacerlo" con "cerró la venta".
 */
function desgloseCierres(ven: MetricaAgendaVendedor): string {
  const partes: string[] = []
  if (ven.completadas > 0) {
    partes.push(`${ven.completadas} ${ven.completadas === 1 ? 'completada' : 'completadas'}`)
  }
  const anuladas = canceladasPropias(ven)
  if (anuladas > 0) partes.push(`${anuladas} ${anuladas === 1 ? 'anulada' : 'anuladas'}`)
  if (ven.no_asistio > 0) partes.push(`${ven.no_asistio} no asistió`)
  // Anuladas por su supervisor o por gerencia: desde 2026-07-27 tampoco pesan
  // en su %, así que van marcadas igual que las del sistema. Sin esta parte la
  // sub-línea MENTIRÍA por omisión — el «n anuladas» de arriba ya no es el
  // total, y un supervisor volvería a sumar más cierres de los que usa el %.
  const porSuperior = canceladasAjenas(ven)
  if (porSuperior > 0) {
    partes.push(
      `${porSuperior} ${porSuperior === 1 ? 'anulada' : 'anuladas'} por un superior (fuera del %)`,
    )
  }
  const porSistema = canceladasSistema(ven)
  // Fuera del cómputo y dicho con todas las letras: no es gestión de nadie.
  // El «(fuera del %)» no es decorativo — esta línea es la ÚNICA alternativa
  // textual al color de la barra, y va unida por el mismo `·` a las partes que
  // SÍ cuentan: sin la marca, un supervisor suma 4 cierres donde el % usa 3.
  if (porSistema > 0) {
    partes.push(
      `${porSistema} ${porSistema === 1 ? 'cerrada' : 'cerradas'} por el lead (fuera del %)`,
    )
  }
  return partes.join(' · ')
}

/** Cero honesto: «—» en muted y SIN peso — solo los valores reales van en extrabold. */
function Vacia(): JSX.Element {
  return <span className="text-muted-foreground">—</span>
}

/** Cifra de la franja de totales: número grande + etiqueta; color solo si es señal. */
function CifraResumen({
  etiqueta,
  valor,
  extra,
  color,
}: {
  etiqueta: string
  valor: number
  extra?: string | undefined
  color?: string | undefined
}): JSX.Element {
  return (
    <span className="flex items-baseline gap-1.5 text-xs">
      <strong
        className="text-sm font-extrabold tabular-nums text-foreground"
        style={color != null ? { color } : undefined}
      >
        {valor}
      </strong>
      <span className="font-semibold text-muted-foreground">{etiqueta}</span>
      {extra != null && (
        <span className="text-[10.5px] tabular-nums text-muted-foreground">{extra}</span>
      )}
    </span>
  )
}

/** Franja compacta de totales del ámbito (estilo "En juego hoy" del vendedor). */
function FranjaResumen({ resumen }: { resumen: ResumenAgenda }): JSX.Element {
  return (
    <div className="mx-5 mb-3 flex flex-wrap items-center gap-x-5 gap-y-1.5 rounded-lg bg-muted/50 px-3 py-2.5">
      <CifraResumen etiqueta="toques" valor={resumen.toques} />
      <CifraResumen
        etiqueta="completadas"
        valor={resumen.completadas}
        extra={resumen.pctCompletadas != null ? `· ${resumen.pctCompletadas}%` : undefined}
      />
      <CifraResumen
        etiqueta="no asistió"
        valor={resumen.noAsistio}
        color={resumen.noAsistio >= 2 ? SEMAFORO.critico : undefined}
      />
    </div>
  )
}

/** Mini-chip agregado de la cabecera de equipo (solo se pinta si es señal >0). */
function ChipEquipo({
  n,
  etiqueta,
  color,
}: {
  n: number | string
  etiqueta: string
  color?: string | undefined
}): JSX.Element {
  return (
    <span
      className="text-[10.5px] font-medium tabular-nums text-muted-foreground"
      style={color != null ? { color } : undefined}
    >
      <strong className={cn('font-extrabold', color == null && 'text-foreground')}>{n}</strong>{' '}
      {etiqueta}
    </span>
  )
}

/** Línea colapsada de miembros todo-en-cero; se expande a chips con los nombres. */
function SinActividadColapsada({
  miembros,
  texto,
  centrado = false,
}: {
  miembros: MetricaAgendaVendedor[]
  texto?: string | undefined
  centrado?: boolean
}): JSX.Element | null {
  if (miembros.length === 0) return null
  const n = miembros.length
  return (
    <details className={cn('group px-5 py-2', centrado && 'text-center')}>
      <summary
        className={cn(
          'flex cursor-pointer list-none items-center gap-1 text-xs text-muted-foreground transition-colors hover:text-foreground [&::-webkit-details-marker]:hidden',
          centrado && 'justify-center',
        )}
      >
        <ChevronRight
          className="size-3.5 shrink-0 transition-transform group-open:rotate-90"
          aria-hidden
        />
        {texto ?? `${n} sin actividad registrada esta semana`}
      </summary>
      <ul className={cn('mt-2 flex flex-wrap gap-1.5 pb-1 pl-5', centrado && 'justify-center pl-0')}>
        {miembros.map((ven) => (
          <li
            key={ven.vendedor_id}
            className="rounded-full bg-muted/60 px-2.5 py-1 text-[10.5px] font-medium text-muted-foreground"
          >
            {ven.nombre}
          </li>
        ))}
      </ul>
    </details>
  )
}

/**
 * Tabla compacta de miembros CON actividad (las filas-cero van colapsadas
 * aparte). 3 columnas para caber SIN scroll horizontal en el slot del
 * supervisor: el ratio manda en cada celda y el conteo crudo baja a sub-línea.
 */
function TablaMiembros({
  miembros,
  ariaLabel,
}: {
  miembros: MetricaAgendaVendedor[]
  ariaLabel: string
}): JSX.Element {
  return (
    <TablaEnvoltura ariaLabel={ariaLabel}>
      <TheadCrm>
        <Th>Miembro</Th>
        <Th className="text-right">Toques</Th>
        <Th>Cierres</Th>
      </TheadCrm>
      <tbody className="divide-y divide-border/60">
        {miembros.map((ven) => {
          const subLinea = subLineaDe(ven)
          // Denominador = SOLO lo que decidió esta persona sobre su propia
          // agenda. Espejo exacto de `resumenAgenda` y de pct_completadas en la
          // RPC; lo que anuló el sistema —y lo que anuló un superior— se pinta
          // en la sub-línea pero no entra aquí.
          const cierres = ven.completadas + canceladasPropias(ven) + ven.no_asistio
          const pct =
            cierres > 0
              ? Math.round(ven.pct_completadas ?? (ven.completadas / cierres) * 100)
              : null
          // Se calcula UNA vez porque ahora decide también qué pintar cuando no
          // hay porcentaje: un vendedor al que su jefe le anuló los dos únicos
          // cierres se queda sin denominador, y un «—» a secas es exactamente
          // igual al de quien no registró nada en toda la semana. El desglose
          // es lo único que distingue «no trabajó» de «se lo anularon».
          const desglose = desgloseCierres(ven)
          return (
            <tr key={ven.vendedor_id}>
              <Td className="py-2">
                <span className="flex items-center gap-2">
                  <Avatar nombre={ven.nombre} className="size-6 text-[9px]" />
                  <span className="min-w-0 leading-tight">
                    <span className="block truncate text-sm font-semibold">{ven.nombre}</span>
                    {subLinea != null && (
                      <span className="block truncate text-[10px] text-muted-foreground">
                        {subLinea}
                      </span>
                    )}
                  </span>
                </span>
              </Td>
              <Td className="whitespace-nowrap py-2 text-right align-top">
                {ven.toques > 0 ? (
                  <span className="block leading-tight">
                    <span className="block text-sm font-extrabold tabular-nums">
                      {RATIO_DIA.format(ven.toques_por_dia)}/día
                    </span>
                    <span className="block text-[10px] tabular-nums text-muted-foreground">
                      {ven.toques} {ven.toques === 1 ? 'toque' : 'toques'}
                    </span>
                  </span>
                ) : (
                  <Vacia />
                )}
              </Td>
              <Td className="py-2 align-top">
                {cierres > 0 ? (
                  <span className="block leading-tight">
                    <span className="flex items-center gap-2">
                      <span className="whitespace-nowrap text-sm font-extrabold tabular-nums">
                        {pct} %
                      </span>
                      <SegmentBar
                        legend={false}
                        className="w-16 shrink-0"
                        segments={[
                          { label: 'completadas', value: ven.completadas, color: SEMAFORO.ok },
                          // `propias` y no `asesor`: los tres segmentos tienen que
                          // sumar EXACTAMENTE `cierres`, que es el denominador del
                          // % de al lado. Con el total la barra pintaría una
                          // proporción que no corresponde al número que la
                          // acompaña.
                          { label: 'anuladas', value: canceladasPropias(ven), color: SEMAFORO.atencion },
                          { label: 'no asistió', value: ven.no_asistio, color: SEMAFORO.critico },
                        ]}
                      />
                    </span>
                    <span className="mt-0.5 block text-[10px] tabular-nums text-muted-foreground">
                      {desglose}
                    </span>
                  </span>
                ) : desglose !== '' ? (
                  // Sin cierres PROPIOS que porcentuar, pero sí algo que
                  // explicar: se pinta el desglose solo. Sin esto, «le anularon
                  // sus 2 tareas» y «no hizo nada» se ven idénticos.
                  <span className="block text-[10px] leading-tight tabular-nums text-muted-foreground">
                    {desglose}
                  </span>
                ) : (
                  <Vacia />
                )}
              </Td>
            </tr>
          )
        })}
      </tbody>
    </TablaEnvoltura>
  )
}

/** Cabecera de sección: supervisor + tamaño del equipo + agregados con señal. */
function CabeceraEquipo({ grupo }: { grupo: GrupoAgendaEquipo }): JSX.Element {
  const total = grupo.miembros.length + grupo.sinActividad.length
  const agregados = grupo.agregados
  return (
    <div className="flex flex-wrap items-center gap-x-2 gap-y-1 bg-muted/30 px-5 py-2.5">
      {grupo.supervisor != null && (
        <Avatar nombre={grupo.nombreEquipo} className="size-7 text-[10px]" />
      )}
      <span className={cn('text-sm font-bold', grupo.supervisor == null && 'text-muted-foreground')}>
        {grupo.nombreEquipo}
      </span>
      <span className="text-xs text-muted-foreground">
        · {total} {total === 1 ? 'miembro' : 'miembros'}
      </span>
      <span className="ml-auto flex flex-wrap items-center gap-x-3 gap-y-1">
        {agregados.toques > 0 && <ChipEquipo n={agregados.toques} etiqueta="toques" />}
        {agregados.pctCompletadas != null && (
          <ChipEquipo n={`${agregados.pctCompletadas}%`} etiqueta="completadas" />
        )}
        {agregados.noAsistio > 0 && (
          <ChipEquipo
            n={agregados.noAsistio}
            etiqueta="no asistió"
            color={agregados.noAsistio >= 2 ? SEMAFORO.critico : undefined}
          />
        )}
      </span>
    </div>
  )
}

/** Pie fijo del panel: define qué cuenta como toque. */
function PieToques(): JSX.Element {
  return (
    <p className="px-5 pb-4 pt-2 text-[10.5px] text-muted-foreground">
      Toques = llamadas, WhatsApp y citas registrados en el periodo — las notas no cuentan.
    </p>
  )
}

export function AgendaEquipoPanel({
  datos,
  cargando,
  error,
  modoDemo,
  onReintentar,
  equipo,
}: {
  datos?: MetricasAgenda | null | undefined
  cargando: boolean
  error: string | null
  modoDemo?: boolean | undefined
  onReintentar: () => void
  /** Miembros del store (perfil → supervisor). Con >1 supervisor en el payload activa las secciones por equipo. */
  equipo?: Miembro[] | undefined
}): JSX.Element {
  const vendedores = datos?.vendedores ?? []
  const resumen = resumenAgenda(vendedores)
  const { conActividad, sinActividad } = separarPorActividad(vendedores)
  const grupos = agruparPorEquipo(vendedores, equipo)

  return (
    <Card className="overflow-hidden">
      <SectionHead
        icon={CalendarClock}
        title="Agenda del equipo"
        right={
          datos != null ? (
            // F2 (semejanza): badge = severidad y nada más — el periodo es un
            // rótulo y va en texto plano.
            <span className="text-xs text-muted-foreground">
              últimos {datos.periodo.dias} días{modoDemo ? ' · ejemplo' : ''}
            </span>
          ) : undefined
        }
      />
      {error != null ? (
        <PanelError mensaje={error} onReintentar={onReintentar} reintentando={cargando} />
      ) : datos == null ? (
        <PanelCargando filas={4} />
      ) : vendedores.length === 0 ? (
        <PanelVacio
          icono={CalendarClock}
          titulo="Sin miembros en tu ámbito"
          detalle="Cuando tu equipo tenga vendedores activos, verás aquí su actividad de agenda."
        />
      ) : conActividad.length === 0 ? (
        // Vacío TOTAL: nadie registra nada. Copy accionable + la lista de
        // miembros colapsada — "quién no registra" es información del manager.
        <>
          <PanelVacio
            icono={CalendarClock}
            titulo="Aún nadie registra actividad esta semana"
            detalle="Los toques aparecen solos cuando el equipo llama, escribe o agenda desde el CRM — carga leads y ponlos a trabajar."
          >
            <SinActividadColapsada
              miembros={sinActividad}
              texto={`${sinActividad.length} ${sinActividad.length === 1 ? 'miembro' : 'miembros'} sin actividad`}
              centrado
            />
          </PanelVacio>
          <PieToques />
        </>
      ) : grupos != null ? (
        // Caso gerencia: supervisores primero, detalle por miembro por sección.
        <>
          <FranjaResumen resumen={resumen} />
          <div className="border-t border-border/60">
            {grupos.map((grupo) => (
              <section
                key={grupo.id}
                aria-label={
                  grupo.supervisor != null ? `Equipo de ${grupo.nombreEquipo}` : grupo.nombreEquipo
                }
                className="border-b border-border/60 last:border-b-0"
              >
                <CabeceraEquipo grupo={grupo} />
                {grupo.miembros.length > 0 && (
                  <div className="border-t border-border/60">
                    <TablaMiembros
                      miembros={grupo.miembros}
                      ariaLabel={`Actividad de agenda del equipo de ${grupo.nombreEquipo}`}
                    />
                  </div>
                )}
                <SinActividadColapsada miembros={grupo.sinActividad} />
              </section>
            ))}
          </div>
          <PieToques />
        </>
      ) : (
        // Caso supervisor (o sin secciones): resumen + tabla única.
        <>
          <FranjaResumen resumen={resumen} />
          <div className="border-t border-border/60">
            <TablaMiembros
              miembros={conActividad}
              ariaLabel="Actividad de agenda por miembro del equipo"
            />
          </div>
          <SinActividadColapsada miembros={sinActividad} />
          <PieToques />
        </>
      )}
    </Card>
  )
}
