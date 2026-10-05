import { useState, type ReactNode } from 'react'
import { Card } from '@/components/ui/card'
import { Tabs } from '@/components/ui/tabs'
import { numero } from '@/lib/format'
import { ListaLeadsRecibidosHoy } from './leads-recibidos-hoy'
import { useLeadsRecibidosHoy } from './use-leads-recibidos-hoy'
import './agenda-leads-hoy.css'

/** Recibidos en la jornada, no «sin leer»: abrir la pestaña o una ficha no
 * elimina el aviso. El día de Lima y la consulta del servidor fijan el total. */
export function AgendaLeadsHoy({ ahora, agenda }: { ahora: number; agenda: ReactNode }) {
  const [panel, setPanel] = useState<'agenda' | 'leads'>('agenda')
  const datos = useLeadsRecibidosHoy(ahora)
  const { total, dia } = datos
  return (
    <Card className="flex min-h-0 min-w-0 flex-1 flex-col">
      <Tabs etiqueta="Agenda y leads de hoy" valor={panel} onCambio={setPanel}
        pestanas={[
          { valor: 'agenda', etiqueta: 'Tu agenda de hoy' },
          { valor: 'leads', etiqueta: <span className="hoy-leads-etiqueta" data-aviso={total != null && total > 0}>
            <span>Leads de hoy</span>{' '}
            {total != null && <span key={`${dia}:${total}:${panel}`} className="hoy-leads-contador">{numero(total)}</span>}
          </span> },
        ]}
        variante="subrayado" className="hoy-agenda-leads flex min-h-0 flex-1 flex-col space-y-0"
        claseLista="mx-5 w-auto shrink-0 gap-5 pt-1 [&_button]:text-[15px]"
        clasePanel="flex min-h-0 flex-1 flex-col pt-3" panelEnfocable={false}>
        {panel === 'agenda' ? agenda : <ListaLeadsRecibidosHoy datos={datos} integrado />}
      </Tabs>
    </Card>
  )
}
