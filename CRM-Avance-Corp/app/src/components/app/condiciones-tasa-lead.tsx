import { useEffect, useMemo, useState } from 'react'
import { Pencil, Percent } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { TasaPolitica, type RangoTasaPolitica } from './tasa-politica'
import { useSolicitudesTasa } from '@/data/crm-queries'
import type { CondicionesTasaLead, SolicitudTasa } from '@/data/crm-api'
import { ESTADOS_SOLICITUD_TASA_SEGUIMIENTO } from '@/lib/rentabilidad'
import { formatDateLocal, vencimientoDesdePlazo, type ModalidadContrato, type TipoInteres } from '@/lib/cronograma'
import { fmtFecha, money, type Moneda } from '@/lib/format'
import { parseMonto } from '@/lib/numero'
import type { Lead } from '@/lib/tipos'

export interface EstadoCondicionesLead {
  condiciones: CondicionesTasaLead
  bloqueo: string | null
}
interface Props {
  lead: Lead
  demo: boolean
  puedeEditar: boolean
  onCambio: (estado: EstadoCondicionesLead | null) => void
}

/** Una relectura fallida conserva el candado; nunca equivale a «no hay solicitudes». */
export function CondicionesTasaLeadPanel(props: Props) {
  const { demo, onCambio } = props
  const q = useSolicitudesTasa(ESTADOS_SOLICITUD_TASA_SEGUIMIENTO, !props.demo, false, { leadId: props.lead.id })
  useEffect(() => {
    if (!demo && (q.isPending || q.isError)) onCambio(null)
  }, [demo, onCambio, q.isPending, q.isError])
  if (!props.demo && q.isPending) return <p role="status" className="text-xs text-muted-foreground">Consultando las condiciones de inversión…</p>
  if (!props.demo && q.isError) return <div role="alert" className="space-y-2 rounded-xl border border-border p-3 text-xs">
    <p>No se pudieron verificar las condiciones de inversión.</p>
    <Button type="button" variant="outline" size="sm" onClick={() => void q.refetch()}>Reintentar condiciones</Button>
  </div>
  const ultima = [...(q.data ?? [])].sort((a, b) => b.solicitada_en.localeCompare(a.solicitada_en))[0]
  return <CondicionesEditables {...props} inicial={ultima} />
}

function CondicionesEditables({ lead, demo, puedeEditar, onCambio, inicial }: Props & { inicial?: SolicitudTasa | undefined }) {
  const inicio = inicial?.fecha_inicio ?? formatDateLocal(new Date())
  const [capital, setCapital] = useState(String(inicial?.capital ?? lead.monto_estimado ?? ''))
  const [moneda, setMoneda] = useState<Moneda>(inicial?.moneda ?? lead.moneda)
  const [fechaInicio, setFechaInicio] = useState(inicio)
  const [fechaFin, setFechaFin] = useState(inicial?.fecha_vencimiento ?? vencimientoDesdePlazo(inicio, 12))
  const [plazo, setPlazo] = useState('12')
  const [modalidad, setModalidad] = useState<ModalidadContrato>(inicial?.modalidad ?? 'mensual')
  const [interes, setInteres] = useState<TipoInteres>(inicial?.tipo_interes ?? 'simple')
  const [tasa, setTasa] = useState(String(inicial?.tasa_maxima_autorizada ?? inicial?.tasa_base ?? ''))
  const [rango, setRango] = useState<RangoTasaPolitica | null>(null)
  const [editando, setEditando] = useState(false)
  const [detalle, setDetalle] = useState(false)
  const monto = parseMonto(capital)
  const nTasa = parseMonto(tasa)
  const intencion = useMemo(() => ({
    capital: monto, moneda, modalidad, tipo_interes: interes, fecha_inicio: fechaInicio, fecha_vencimiento: fechaFin,
    producto_condicion_id: inicial?.producto_condicion_id ?? null,
  }), [monto, moneda, modalidad, interes, fechaInicio, fechaFin, inicial?.producto_condicion_id])
  const condicionesValidas = monto != null && monto >= 100 && monto <= 100_000_000 && !!fechaInicio && fechaFin > fechaInicio
  const bloqueo = editando ? 'Confirma las condiciones de inversión antes de convertir.'
    : !condicionesValidas ? 'Completa capital y plazo en las condiciones de inversión.'
      : !rango || ['cargando', 'error', 'incompleta'].includes(rango.modo) ? 'Verifica la política de tasa antes de convertir.'
        : rango.bloqueoContrato ?? (nTasa == null || rango.minimo == null || rango.maximo == null || nTasa < rango.minimo || nTasa > rango.maximo ? 'La tasa debe estar dentro del rango autorizado.' : null)
  useEffect(() => {
    onCambio({ condiciones: { ...intencion, capital: monto ?? 0, categoria: inicial?.categoria ?? 'nuevo', contrato_origen_id: inicial?.contrato_origen_id ?? null, tasa_anual: nTasa ?? 0 }, bloqueo })
  }, [intencion, monto, nTasa, inicial?.categoria, inicial?.contrato_origen_id, bloqueo, onCambio])
  const pendiente = rango?.solicitud?.estado_efectivo === 'pendiente'
  const estado = pendiente ? 'Pendiente de Gerencia' : rango?.modo === 'autorizada' ? 'Tasa aprobada'
    : rango?.minimo != null && rango.base != null && rango.minimo < rango.base ? 'Tasa acordada' : 'Tasa base'
  return <section aria-labelledby={`condiciones-${lead.id}`} className="space-y-3 rounded-xl border border-border bg-card p-3.5" data-testid="condiciones-tasa-lead">
    <div className="flex flex-wrap items-center justify-between gap-2">
      <h3 id={`condiciones-${lead.id}`} className="flex items-center gap-1.5 text-xs font-bold text-primary"><Percent className="size-4" aria-hidden /> Condiciones de inversión</h3>
      <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${pendiente ? 'bg-amber-50 text-amber-900' : 'bg-primary/10 text-primary'}`}>{estado}</span>
    </div>
    {!editando ? <div className="flex items-start justify-between gap-2 rounded-lg bg-muted/40 px-3 py-2.5">
      <div className="min-w-0">
        <p className="text-[13px] font-bold tabular-nums text-primary">{monto == null ? 'Capital por definir' : money(monto, moneda)}</p>
        <p className="mt-1 text-[10px] leading-relaxed text-muted-foreground-strong">Inicio previsto: {fmtFecha(fechaInicio)} · Vence: {fmtFecha(fechaFin)}<br />Pago {modalidad} · Interés {interes}</p>
      </div>
      {puedeEditar && <Button type="button" variant="ghost" size="xs" aria-label="Editar condiciones de inversión" disabled={pendiente || rango?.solicitud?.estado_efectivo === 'aprobada_con_tope'} onClick={() => setEditando(true)}><Pencil className="!size-3" aria-hidden /> Editar</Button>}
    </div> : <div className="space-y-3 rounded-lg border border-border bg-muted/20 p-3">
      <div className="grid grid-cols-[minmax(0,1fr)_80px] gap-2">
        <div className="space-y-1"><Label htmlFor="propuesta-capital">Capital propuesto</Label><Input id="propuesta-capital" inputMode="decimal" value={capital} onChange={(e) => setCapital(e.target.value)} /></div>
        <div className="space-y-1"><Label htmlFor="propuesta-moneda">Moneda</Label><Select id="propuesta-moneda" value={moneda} onChange={(e) => setMoneda(e.target.value as Moneda)}><option>PEN</option><option>USD</option></Select></div>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div className="min-w-0 space-y-1"><Label htmlFor="propuesta-plazo">Plazo (meses)</Label><Select id="propuesta-plazo" value={plazo} onChange={(e) => { setPlazo(e.target.value); setFechaFin(vencimientoDesdePlazo(fechaInicio, Number(e.target.value))) }}>{['3', '6', '12', '18', '24', '36'].map((v) => <option key={v}>{v}</option>)}</Select></div>
        <div className="min-w-0 space-y-1"><Label htmlFor="propuesta-inicio">Inicio previsto</Label><Input id="propuesta-inicio" type="date" className="min-w-0 text-xs" value={fechaInicio} onChange={(e) => { setFechaInicio(e.target.value); if (e.target.value) setFechaFin(vencimientoDesdePlazo(e.target.value, Number(plazo))) }} /></div>
        <div className="min-w-0 space-y-1"><Label htmlFor="propuesta-modalidad">Pago de intereses</Label><Select id="propuesta-modalidad" value={modalidad} onChange={(e) => setModalidad(e.target.value as ModalidadContrato)}>{(['mensual', 'trimestral', 'semestral', 'anual'] as const).map((v) => <option key={v}>{v}</option>)}</Select></div>
        <div className="min-w-0 space-y-1"><Label htmlFor="propuesta-interes">Tipo de interés</Label><Select id="propuesta-interes" value={interes} onChange={(e) => setInteres(e.target.value as TipoInteres)}><option value="simple">Simple</option><option value="compuesto">Compuesto</option></Select></div>
      </div>
      {rango?.modo === 'autorizada' && <p className="text-[11px] text-amber-900">Cambiar las condiciones requiere una nueva aprobación para usar una tasa superior.</p>}
      {!condicionesValidas && <p role="alert" className="text-xs text-destructive-text">Completa capital, plazo y fecha de inicio prevista.</p>}
      <div className="flex justify-end"><Button type="button" size="xs" disabled={!condicionesValidas} onClick={() => setEditando(false)}>Guardar condiciones</Button></div>
    </div>}
    <div className="grid gap-3">
      <TasaPolitica clienteId="" leadId={lead.id} categoria={inicial?.categoria ?? 'nuevo'} contratoOrigenId={inicial?.contrato_origen_id ?? null} intencion={intencion} tasa={tasa} onTasaChange={setTasa} onRangoChange={setRango} demo={demo} disabled={!puedeEditar || editando} idInput="lead-tasa" />
    </div>
    {!demo && !lead.dni && <p className="text-[11px] text-muted-foreground-strong">Completa el DNI en los datos del lead antes de solicitar una tasa especial.</p>}
    {rango?.modo === 'autorizada' && <p className="text-[11px] text-primary">La autorización se conservará para el contrato con estas mismas condiciones.</p>}
    {(rango?.solicitud ?? inicial) && <div className="border-t border-border pt-2">
      <button type="button" className="cursor-pointer rounded text-[11px] font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-expanded={detalle} onClick={() => setDetalle(!detalle)}>{detalle ? 'Ocultar detalle de la solicitud' : 'Ver detalle de la solicitud'}</button>
      {detalle && <p className="mt-2 whitespace-pre-wrap text-[11px] leading-relaxed">{(rango?.solicitud ?? inicial)?.motivo}</p>}
    </div>}
  </section>
}
