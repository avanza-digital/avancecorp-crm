// Agenda del equipo (Fase F) — panel del SUPERVISOR sobre la RPC
// crm.metricas_agenda_fn: quién registra actividad (toques), cómo cierra sus
// reuniones y cuánta carga viva arrastra (vencidas / leads sin acción). Los
// miembros con TODO en cero se muestran igual: para el manager, "no registra
// nada" es exactamente la señal que necesita ver. Semáforo sin verde (regla
// de la casa): ámbar para rezago, rojo solo para no-shows repetidos.
import type { JSX } from 'react'
import { CalendarClock } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { SEMAFORO } from '@/lib/semaforo'
import type { MetricasAgenda } from '@/lib/metricas-agenda'

/** Ámbar si hay rezago (>0); color normal si está limpio. */
function colorRezago(n: number): string | undefined {
  return n > 0 ? SEMAFORO.atencion : undefined
}

export function AgendaEquipoPanel({
  datos,
  cargando,
  error,
  modoDemo,
  onReintentar,
}: {
  datos?: MetricasAgenda | null | undefined
  cargando: boolean
  error: string | null
  modoDemo?: boolean | undefined
  onReintentar: () => void
}): JSX.Element {
  return (
    <Card className="overflow-hidden">
      <SectionHead
        icon={CalendarClock}
        title="Agenda del equipo"
        right={
          datos != null ? (
            <Badge>
              últimos {datos.periodo.dias} días{modoDemo ? ' · ejemplo' : ''}
            </Badge>
          ) : undefined
        }
      />
      {error != null ? (
        <PanelError mensaje={error} onReintentar={onReintentar} reintentando={cargando} />
      ) : datos == null ? (
        <PanelCargando filas={4} />
      ) : datos.vendedores.length === 0 ? (
        <PanelVacio
          icono={CalendarClock}
          titulo="Sin miembros en tu ámbito"
          detalle="Cuando tu equipo tenga vendedores activos, verás aquí su actividad de agenda."
        />
      ) : (
        <>
          <div className="border-t border-border/60">
            <TablaEnvoltura ariaLabel="Actividad de agenda por miembro del equipo">
              <TheadCrm>
                <Th>Miembro</Th>
                <Th className="text-right">Toques</Th>
                <Th className="text-right">Completadas</Th>
                <Th className="text-right">No asistió</Th>
                <Th className="text-right">Reprog.</Th>
                <Th className="text-right">Vencidas</Th>
                <Th className="text-right">Sin acción</Th>
                <Th className="text-right">Pendientes</Th>
              </TheadCrm>
              <tbody className="divide-y divide-border/60">
                {datos.vendedores.map((ven) => (
                  <tr key={ven.vendedor_id}>
                    <Td>
                      <span className="flex items-center gap-2">
                        <Avatar nombre={ven.nombre} className="size-6 text-[9px]" />
                        <span className="min-w-0 leading-tight">
                          <span className="block truncate text-sm font-semibold">{ven.nombre}</span>
                          {ven.rol === 'supervisor' && (
                            <span className="block text-[10px] text-muted-foreground">supervisor</span>
                          )}
                        </span>
                      </span>
                    </Td>
                    <Td className="whitespace-nowrap text-right">
                      <span className="text-sm font-extrabold tabular-nums">{ven.toques}</span>{' '}
                      <span className="text-[10px] tabular-nums text-muted-foreground">
                        /día {ven.toques_por_dia}
                      </span>
                    </Td>
                    <Td className="whitespace-nowrap text-right tabular-nums">
                      {ven.completadas}
                      {ven.pct_completadas != null && (
                        <span className="text-[10.5px] text-muted-foreground">
                          {' '}· {Math.round(ven.pct_completadas)}%
                        </span>
                      )}
                    </Td>
                    <Td
                      className="text-right font-semibold tabular-nums"
                      style={ven.no_asistio >= 2 ? { color: SEMAFORO.critico } : undefined}
                    >
                      {ven.no_asistio}
                    </Td>
                    <Td className="text-right tabular-nums">{ven.reprogramaciones}</Td>
                    <Td
                      className="text-right font-semibold tabular-nums"
                      style={{ color: colorRezago(ven.vencidas) }}
                    >
                      {ven.vencidas}
                    </Td>
                    <Td
                      className="text-right font-semibold tabular-nums"
                      style={{ color: colorRezago(ven.leads_sin_accion) }}
                    >
                      {ven.leads_sin_accion}
                    </Td>
                    <Td className="text-right tabular-nums">{ven.pendientes}</Td>
                  </tr>
                ))}
              </tbody>
            </TablaEnvoltura>
          </div>
          <p className="px-5 pb-4 pt-2 text-[10.5px] text-muted-foreground">
            Toques = llamadas, WhatsApp y reuniones registrados en el periodo — las notas no cuentan.
          </p>
        </>
      )}
    </Card>
  )
}
