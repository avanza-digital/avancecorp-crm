import { useState } from 'react'
import { CalendarClock } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { SectionHead } from '@/components/common/section-head'
import { Paginacion } from '@/components/common/paginacion'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { usePostventa, useVencimientosPostventa } from '@/data/postventa-queries'
import { mensajeDeError } from '@/data/crm-api'
import { EMPRESA_NOMBRE, type EmpresaInversion } from '@/lib/inversionistas'
import { fmtFecha, money } from '@/lib/format'

export function VencimientosPostventa({actor, empresa, onAbrir}: {
  actor: string; empresa: EmpresaInversion | ''; onAbrir: (id: string) => void
}) {
  const [abierto, setAbierto] = useState(false)
  const [pagina, setPagina] = useState(1)
  const estado = usePostventa(actor)
  const habilitada = estado.isFetchedAfterMount && estado.isSuccess && estado.data.habilitada
  const q = useVencimientosPostventa(actor, empresa, pagina, habilitada && abierto)
  if (estado.isError) return <PanelError mensaje={mensajeDeError(estado.error, 'No pudimos comprobar los vencimientos.')}
    onReintentar={() => void estado.refetch()} reintentando={estado.isFetching} />
  if (!habilitada) return null
  const datos = q.isFetchedAfterMount && q.isSuccess && q.data.habilitada ? q.data : null
  return <Card className="overflow-hidden">
    <SectionHead icon={CalendarClock} title="Vencimientos" right={<Button size="sm" variant="ghost" aria-expanded={abierto}
      aria-controls="pv-vencimientos" onClick={() => setAbierto(v => !v)}>{abierto ? 'Ocultar' : 'Ver vencimientos'}</Button>} />
    {abierto && <div id="pv-vencimientos">
      <p className="px-5 pb-3 text-sm text-muted-foreground">Inversiones vencidas o por vencer en los próximos 30 días, según sus registros de origen.</p>
      {q.isError ? <PanelError mensaje={mensajeDeError(q.error, 'No pudimos consultar los vencimientos.')} onReintentar={() => void q.refetch()} reintentando={q.isFetching} />
        : !datos ? <PanelCargando filas={3} /> : <>
          {datos.filas.length === 0 ? <p role="status" className="px-5 pb-4 text-sm">No hay vencimientos en esta página.</p>
            : <ul className="divide-y divide-border border-y border-border">{datos.filas.map(f => <li key={`${f.empresa}:${f.fuente_id}`}>
              <button type="button" onClick={() => onAbrir(f.inversionista_id)} className="grid min-h-20 w-full gap-1 px-5 py-3 text-left hover:bg-muted/50 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring sm:grid-cols-[2fr_1fr_1fr]"
                aria-label={`Ver vencimiento de ${f.nombre} en ${EMPRESA_NOMBRE[f.empresa]}`}>
                <span><span className="block text-sm font-semibold">{f.nombre}</span><span className="text-xs text-muted-foreground">{EMPRESA_NOMBRE[f.empresa]}{f.numero ? ` · ${f.numero}` : ''}</span></span>
                <span className="text-sm tabular-nums">{money(f.capital, f.moneda)}</span><span className="text-sm">{fmtFecha(f.vence_en)}</span>
              </button>
            </li>)}</ul>}
          <div className="px-5 py-3"><Paginacion paginaActual={pagina - 1} paginas={Math.max(1, Math.ceil(datos.total / 25))} total={datos.total}
            onCambio={n => setPagina(n + 1)} mostrarSiempre ariaLabel="Paginación de vencimientos" /></div>
        </>}
    </div>}
  </Card>
}
