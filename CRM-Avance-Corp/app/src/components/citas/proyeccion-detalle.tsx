// Lista lateral detrás de una cifra de la Proyección: las citas exactas que la
// componen, con su monto original y en soles, y su CSV. Donde la tabla no cabe
// entera (celular y tablet) cada cita es una tarjeta: nada se desliza de lado.
import { useState } from 'react'
import { Download, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { fmtFecha, money, numero } from '@/lib/format'
import { useMediaQuery } from '@/lib/media'
import { useDatosCitas } from './contexto'
import { fechaLocalCitas } from './fecha-comercial'
import { ESTADOS } from './modelo'
import { ROTULO_ORIGEN, csvCitasProyeccion, type CitaProyectada } from './proyeccion'
import { descargarCsv } from './proyeccion-descarga'

/**
 * El panel mide 980 px pero nunca más del 92 % de la ventana: llega a 980 desde los 1 066 px. Por debajo de
 * 1 080 px (con margen) la tabla no cabe entera y la lista usa tarjetas, aunque la hoja siga siendo tabla.
 */
const LISTA_EN_TARJETAS = '(max-width: 1079px)'

export interface ListaProyeccion { titulo: string; periodo: string; lista: CitaProyectada[]; conAnalista: boolean; archivo: string }
type AbrirFicha = ((leadId: string, tareaId: string) => void) | undefined

// Cada dato se pinta con la misma pieza en la fila y en la tarjeta: las dos vistas no pueden diferir.
const creada = (c: CitaProyectada) => c.cita.creadoEn ? fmtFecha(fechaLocalCitas(c.cita.creadoEn)) : '—'
const momento = (c: CitaProyectada) => `${fmtFecha(c.cita.fecha)} · ${c.cita.hora}`
const EstadoCita = ({ c }: { c: CitaProyectada }) => <span className="pc-estado" data-estado={c.cita.estado}>{ESTADOS[c.cita.estado].label}</span>
const OrigenCita = ({ c }: { c: CitaProyectada }) => <span className="pc-origen" data-origen={c.origen}>{ROTULO_ORIGEN[c.origen]}</span>

/** Cada parte va en su propio span: en la tabla, el importe original y su conversión solo se separan en dos líneas si no caben. */
function MontoCita({ c }: { c: CitaProyectada }) {
  if (c.cita.monto == null) return <span className="pc-cero">—</span>
  if (c.cita.moneda === 'PEN') return <span>{money(c.cita.monto, 'PEN')}</span>
  return <><span className="pc-m">{money(c.cita.monto, 'USD')} ·</span><span>{c.enSoles === null ? 'Pendiente de TC' : `S/ ${numero(c.enSoles)}`}</span></>
}

/** La persona abre su ficha de lead; una reunión con un cliente sin lead no tiene ficha que abrir. */
function PersonaCita({ c, onAbrir }: { c: CitaProyectada; onAbrir: AbrirFicha }) {
  const leadId = c.cita.leadId
  if (!onAbrir || leadId === null) return <span className="pc-persona">{c.cita.nombre}</span>
  return <button type="button" className="pc-persona" onClick={() => onAbrir(leadId, c.cita.id)}>{c.cita.nombre}</button>
}

/** Escritorio: una fila por cita. */
function TablaCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: AbrirFicha }) {
  return <table className="pc-lista">
    <caption className="sr-only">{detalle.titulo}</caption>
    <thead><tr><th scope="col">Creada</th><th scope="col">Cita</th><th scope="col">Persona</th>{detalle.conAnalista && <th scope="col">Analista</th>}<th scope="col">Estado</th><th scope="col" className="pc-num">Monto</th><th scope="col">Origen</th></tr></thead>
    <tbody>{detalle.lista.map(c => <tr key={c.cita.id}>
      <td>{creada(c)}</td>
      <td>{momento(c)}</td>
      <th scope="row"><PersonaCita c={c} onAbrir={onAbrir} /></th>
      {detalle.conAnalista && <td className="pc-lista-analista">{c.cita.analistaNombre}</td>}
      <td className="pc-lista-estado"><EstadoCita c={c} /></td>
      <td className="pc-num"><MontoCita c={c} /></td>
      <td><OrigenCita c={c} /></td>
    </tr>)}</tbody>
  </table>
}

/** Celular y tablet: una tarjeta por cita, con los mismos datos y en el mismo orden que la tabla. */
function TarjetasCitas({ detalle, onAbrir }: { detalle: ListaProyeccion; onAbrir: AbrirFicha }) {
  return <ul className="pc-citas" aria-label={detalle.titulo}>{detalle.lista.map(c => <li key={c.cita.id} className="pc-cita">
    <div className="pc-cita-cab"><PersonaCita c={c} onAbrir={onAbrir} /><OrigenCita c={c} /></div>
    <dl className="pc-cita-datos">
      <div><dt>Creada</dt><dd>{creada(c)}</dd></div>
      <div><dt>Cita</dt><dd>{momento(c)}</dd></div>
      {detalle.conAnalista && <div><dt>Analista</dt><dd>{c.cita.analistaNombre}</dd></div>}
      <div><dt>Estado</dt><dd><EstadoCita c={c} /></dd></div>
      <div><dt>Monto</dt><dd><MontoCita c={c} /></dd></div>
    </dl>
  </li>)}</ul>
}

export function DetalleProyeccion({ detalle, onCerrar, focoRespaldo }: { detalle: ListaProyeccion | null; onCerrar: () => void; focoRespaldo: () => HTMLElement | null }) {
  const { onAbrirLead } = useDatosCitas()
  const enTarjetas = useMediaQuery(LISTA_EN_TARJETAS)
  const [aviso, setAviso] = useState('')
  const n = detalle?.lista.length ?? 0
  const cerrar = () => { setAviso(''); onCerrar() }
  const abrirFicha = onAbrirLead && ((leadId: string, tareaId: string) => { cerrar(); requestAnimationFrame(() => requestAnimationFrame(() => onAbrirLead(leadId, tareaId))) })
  function exportar() {
    if (!detalle) return
    setAviso(descargarCsv(detalle.archivo, csvCitasProyeccion(detalle.lista)) ? `Se descargó el CSV con ${n} ${n === 1 ? 'cita' : 'citas'}.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
  }
  return <Sheet open={Boolean(detalle)} onClose={cerrar} focoRespaldo={focoRespaldo} className="citas-crm-dialogo pc-detalle w-[980px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div>
      <SheetTitle>{detalle?.titulo ?? 'Citas'}</SheetTitle>
      <p className="mt-1 text-sm text-muted-foreground-strong" data-testid="pc-detalle-conteo">{detalle?.periodo} · {numero(n)} {n === 1 ? 'cita' : 'citas'}</p>
    </div><Button variant="ghost" size="icon" aria-label="Cerrar lista" onClick={cerrar}><X aria-hidden /></Button></div></SheetHeader>
    {detalle && <>
      <SheetBody className="p-0">
        {enTarjetas ? <TarjetasCitas detalle={detalle} onAbrir={abrirFicha} /> : <TablaCitas detalle={detalle} onAbrir={abrirFicha} />}
      </SheetBody>
      <SheetFooter className="justify-end"><p role="status" className={aviso ? 'mr-auto text-xs text-muted-foreground-strong' : 'sr-only'}>{aviso}</p><Button variant="outline" onClick={exportar} disabled={!n}><Download aria-hidden />Exportar CSV</Button></SheetFooter>
    </>}
  </Sheet>
}
