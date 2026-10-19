// Lista lateral detrás de una cifra de la Proyección: las citas exactas que la
// componen, con su monto original y en soles, y su CSV.
import { useState } from 'react'
import { Download, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { fmtFecha, money, numero } from '@/lib/format'
import { useDatosCitas } from './contexto'
import { fechaLocalCitas } from './fecha-comercial'
import { ESTADOS } from './modelo'
import { ROTULO_ORIGEN, csvCitasProyeccion, type CitaProyectada } from './proyeccion'
import { descargarCsv } from './proyeccion-descarga'

export interface ListaProyeccion { titulo: string; periodo: string; lista: CitaProyectada[]; conAnalista: boolean; archivo: string }

function MontoCita({ c }: { c: CitaProyectada }) {
  if (c.cita.monto == null) return <span className="pc-cero">—</span>
  if (c.cita.moneda === 'PEN') return <>{money(c.cita.monto, 'PEN')}</>
  return <><span className="pc-m">{money(c.cita.monto, 'USD')} ·</span>{c.enSoles === null ? 'Pendiente de TC' : `S/ ${numero(c.enSoles)}`}</>
}

export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle: ListaProyeccion | null; onCerrar: () => void; focoRespaldo: () => HTMLElement | null }) {
  const { onAbrirLead } = useDatosCitas()
  const [aviso, setAviso] = useState('')
  const n = detalle?.lista.length ?? 0
  const cerrar = () => { setAviso(''); onCerrar() }
  function exportar() {
    if (!detalle) return
    setAviso(descargarCsv(detalle.archivo, csvCitasProyeccion(detalle.lista)) ? `Se descargó el CSV con ${n} ${n === 1 ? 'cita' : 'citas'}.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
  }
  return <Sheet open={Boolean(detalle)} onClose={cerrar} focoRespaldo={focoRespaldo} className="citas-crm-dialogo pc-detalle w-[760px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div>
      <SheetTitle>{detalle?.titulo ?? 'Citas'}</SheetTitle>
      <p className="mt-1 text-sm text-muted-foreground-strong" data-testid="pc-detalle-conteo">{detalle?.periodo} · {numero(n)} {n === 1 ? 'cita' : 'citas'}</p>
    </div><Button variant="ghost" size="icon" aria-label="Cerrar lista" onClick={cerrar}><X aria-hidden /></Button></div></SheetHeader>
    {detalle && <>
      <SheetBody className="p-0">
        <table className="pc-lista">
          <caption className="sr-only">{detalle.titulo}</caption>
          <thead><tr><th scope="col">Creada</th><th scope="col">Cita</th><th scope="col">Persona</th>{detalle.conAnalista && <th scope="col">Analista</th>}<th scope="col">Estado</th><th scope="col" className="pc-num">Monto</th><th scope="col">Origen</th></tr></thead>
          <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
            <td>{c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'}</td>
            <td>{fmtFecha(c.cita.fecha)} · {c.cita.hora}</td>
            <th scope="row">{onAbrirLead ? <button type="button" className="pc-persona" onClick={() => { cerrar(); requestAnimationFrame(() => requestAnimationFrame(() => onAbrirLead(c.cita.leadId, c.cita.id))) }}>{c.cita.nombre}</button> : <span className="pc-persona">{c.cita.nombre}</span>}</th>
            {detalle.conAnalista && <td>{c.cita.analistaNombre}</td>}
            <td><span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span></td>
            <td className="pc-num"><MontoCita c={c} /></td>
            <td><span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span></td>
          </tr>)}</tbody>
        </table>
      </SheetBody>
      <SheetFooter className="justify-end"><p role="status" className={aviso ? 'mr-auto text-xs text-muted-foreground-strong' : 'sr-only'}>{aviso}</p><Button variant="outline" onClick={exportar} disabled={!n}><Download aria-hidden />Exportar CSV</Button></SheetFooter>
    </>}
  </Sheet>
}
