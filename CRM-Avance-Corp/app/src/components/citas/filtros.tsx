import { useDatosCitas } from './contexto'
import { useState } from 'react'
import { Search, SlidersHorizontal, RotateCcw, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { fmtFecha } from '@/lib/format'
import { ESTADOS, errorFiltros, type EstadoCita } from './modelo'

import { rangoConsulta as rango, type ConsultaCitas as FiltrosCitas } from './datos'

const ESTADOS_DISPONIBLES = Object.keys(ESTADOS) as EstadoCita[]
const SEGUIMIENTOS = [['', 'Cualquier seguimiento'], ['pendiente', 'Con seguimiento pendiente'], ['cerrado', 'Con cierre posterior'], ['sin_cierre', 'Sin cierre posterior']] as const

interface PropsFiltros {
  filtros: FiltrosCitas
  onCambiar: (cambios: Partial<FiltrosCitas>) => void
  onRestablecer: () => void
}

export function Filtros({ filtros: f, onCambiar, onRestablecer }: PropsFiltros) {
  const { citas: CITAS, equipo: EQUIPO, mesInicial, meses, gestion } = useDatosCitas()
  const compacta = Boolean(gestion?.avance)
  const SUPERVISORES = [...new Map(EQUIPO.map(p => [p.supervisorId, p.supervisor])).entries()]
  if (f.equipo && !SUPERVISORES.some(([id]) => id === f.equipo)) SUPERVISORES.push([f.equipo, f.equipo === 'sin_supervisor' ? 'Sin supervisor' : 'Equipo seleccionado'])
  const ORIGENES = [...new Set([...CITAS, ...(gestion?.asignaciones ?? [])].map(c => c.origen))]
  const RESULTADOS = [...new Set(CITAS.map(c => c.resultado))]
  const [avanzados, setAvanzados] = useState(false)
  const error = errorFiltros(f)
  const errorMonto = error
  const [desde, hasta] = rango(f)
  const etiquetas: { id: string; texto: string; quitar: Partial<FiltrosCitas> }[] = []
  if (f.dia) etiquetas.push({ id: 'dia', texto: `Día: ${fmtFecha(f.dia)}`, quitar: { dia: '' } })
  if (f.leadId) etiquetas.push({ id: 'leadId', texto: `Lead: ${CITAS.find(cita => cita.leadId === f.leadId)?.nombre ?? f.leadId}`, quitar: { leadId: '' } })
  if (f.q) etiquetas.push({ id: 'q', texto: `Búsqueda: ${f.q}`, quitar: { q: '' } })
  if (f.equipo) etiquetas.push({ id: 'equipo', texto: `Supervisor: ${SUPERVISORES.find(([id]) => id === f.equipo)?.[1] ?? f.equipo}`, quitar: { equipo: '' } })
  if (f.analista) etiquetas.push({ id: 'analista', texto: `Analista: ${EQUIPO.find(p => p.id === f.analista)?.nombre}`, quitar: { analista: '' } })
  for (const estado of f.estados) etiquetas.push({ id: estado, texto: ESTADOS[estado].label, quitar: { estados: f.estados.filter(e => e !== estado) } })
  for (const [clave, nombre] of [['modalidad', 'Modalidad'], ['origen', 'Origen'], ['resultado', 'Resultado'], ['moneda', 'Moneda'], ['min', 'Monto desde'], ['max', 'Monto hasta']] as const) {
    if (f[clave]) etiquetas.push({ id: clave, texto: `${nombre}: ${f[clave]}`, quitar: { [clave]: '' } })
  }
  if (f.seguimiento) etiquetas.push({ id: 'seguimiento', texto: SEGUIMIENTOS.find(([id]) => id === f.seguimiento)?.[1] ?? '', quitar: { seguimiento: '' } })
  if (f.semana) etiquetas.push({ id: 'semana', texto: `Semana ${f.semana}`, quitar: { semana: '' } })
  if (f.registro) etiquetas.push({ id: 'registro', texto: f.registro === 'manual' ? 'Registro manual' : 'Leads recibidos', quitar: { registro: '' } })
  if (f.mes && f.mes !== mesInicial) etiquetas.push({ id: 'mes', texto: `Mes: ${f.mes}`, quitar: { mes: mesInicial } })
  const cantidadAvanzados = f.estados.length + ['modalidad', 'origen', 'resultado', 'seguimiento', 'moneda', 'min', 'max', 'registro', ...(compacta ? ['q'] : [])].filter(k => f[k as keyof FiltrosCitas]).length
  const buscar = <label className="space-y-1 text-xs font-semibold">Buscar una cita<div className="relative"><Search aria-hidden className="pointer-events-none absolute top-2.5 left-3 size-4 text-muted-foreground" /><Input type="search" className="pl-9" placeholder="Prospecto, teléfono o código" value={f.q} onChange={e => onCambiar({ q: e.target.value })} /></div></label>
  return <section className={`citas-filtros${compacta ? ' cm-filtros' : ''}`} aria-label="Consulta de citas">
    <h2 className="sr-only">Tu consulta</h2>
    <form noValidate onSubmit={evento => evento.preventDefault()}>
      <div className="citas-filtros-fila">
        {!compacta && buscar}
        <label className="space-y-1 text-xs font-semibold">Supervisor<Select aria-label="Supervisor" value={f.equipo} onChange={e => onCambiar({ equipo: e.target.value })}><option value="">Todos</option>{SUPERVISORES.map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}</Select></label>
        <label className="space-y-1 text-xs font-semibold">Analista<Select aria-label="Analista" value={f.analista} onChange={e => onCambiar({ analista: e.target.value })}><option value="">Todos</option>{EQUIPO.map(persona => <option key={persona.id} value={persona.id} disabled={Boolean(f.equipo && persona.supervisorId !== f.equipo)}>{persona.nombre}</option>)}</Select></label>
        <label className="space-y-1 text-xs font-semibold">Mes{meses.length ? <Select aria-label="Mes" value={f.mes} onChange={e => onCambiar({ mes: e.target.value })}>{meses.map(mes => <option key={mes} value={mes}>{mes}</option>)}</Select> : <Input type="month" aria-label="Mes" min="2000-01" value={f.mes} onChange={e => onCambiar({ mes: e.target.value })} />}</label>
        <label className="space-y-1 text-xs font-semibold">Semana<Select aria-label="Semana" value={f.semana || ''} onChange={e => onCambiar({ semana: e.target.value })}><option value="">Todo el mes</option><option value="1">Semana 1 · 1–7</option><option value="2">Semana 2 · 8–14</option><option value="3">Semana 3 · 15–21</option><option value="4">Semana 4 · 22–fin</option></Select></label>
        <Button variant="outline" aria-expanded={avanzados} aria-controls="citas-filtros-adicionales" onClick={() => setAvanzados(!avanzados)}><SlidersHorizontal aria-hidden />Más filtros{cantidadAvanzados > 0 && <span>{cantidadAvanzados}</span>}</Button>
        <Button variant="ghost" size="icon" aria-label="Restablecer consulta" title="Restablecer consulta" onClick={onRestablecer}><RotateCcw aria-hidden /></Button>
      </div>
      <div id="citas-filtros-adicionales" hidden={!avanzados}>
        <div className="space-y-5 border-t border-border bg-muted/20 p-4 sm:p-5">
          <fieldset><legend className="mb-3 text-xs font-semibold">Estado de la cita <span className="ml-2 font-normal text-muted-foreground-strong">Puedes elegir varios</span></legend><div className="flex flex-wrap gap-x-5 gap-y-3">{ESTADOS_DISPONIBLES.map(estado => <label key={estado} className="flex cursor-pointer items-center gap-2 text-sm"><input type="checkbox" className="size-4 accent-accent" checked={f.estados.includes(estado)} onChange={e => onCambiar({ estados: e.target.checked ? [...f.estados, estado] : f.estados.filter(id => id !== estado) })} />{ESTADOS[estado].label}</label>)}</div></fieldset>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {compacta && buscar}
            {compacta && <label className="space-y-1 text-xs font-semibold">Tipo de registro<Select value={f.registro ?? ''} onChange={e => onCambiar({ registro: e.target.value as '' | 'manual' | 'recibido' })}><option value="">Todos los leads</option><option value="recibido">Recibidos</option><option value="manual">Registrados manualmente</option></Select></label>}
            <p className="text-xs text-muted-foreground-strong sm:col-span-2 xl:col-span-3">Cuatro semanas comerciales: 1–7, 8–14, 15–21 y 22 hasta el último día del mes.</p>
            <label className="space-y-1 text-xs font-semibold">Modalidad<Select value={f.modalidad} onChange={e => onCambiar({ modalidad: e.target.value })}><option value="">Todas las modalidades</option>{['Presencial', 'Virtual', 'Sin clasificar'].map(valor => <option key={valor}>{valor}</option>)}</Select></label>
            <label className="space-y-1 text-xs font-semibold">Origen del prospecto<Select value={f.origen} onChange={e => onCambiar({ origen: e.target.value })}><option value="">Todos los orígenes</option>{ORIGENES.map(valor => <option key={valor}>{valor}</option>)}</Select></label>
            <label className="space-y-1 text-xs font-semibold">Resultado registrado<Select value={f.resultado} onChange={e => onCambiar({ resultado: e.target.value })}><option value="">Todos los resultados</option>{RESULTADOS.map(valor => <option key={valor}>{valor}</option>)}</Select></label>
            <label className="space-y-1 text-xs font-semibold">Seguimiento comercial<Select value={f.seguimiento} onChange={e => onCambiar({ seguimiento: e.target.value })}>{SEGUIMIENTOS.map(([id, etiqueta]) => <option key={id} value={id}>{etiqueta}</option>)}</Select></label>
            <label className="space-y-1 text-xs font-semibold">Moneda del monto estimado<Select value={f.moneda} onChange={e => onCambiar({ moneda: e.target.value })}><option value="">Soles y dólares</option><option value="PEN">Soles (PEN)</option><option value="USD">Dólares (USD)</option></Select></label>
            <div className="grid grid-cols-2 gap-3">{[['min', 'Monto desde'], ['max', 'Monto hasta']].map(([clave, etiqueta]) => <label key={clave} className="space-y-1 text-xs font-semibold">{etiqueta}<Input type="number" min="0" step="any" placeholder="Sin límite" disabled={!f.moneda} value={f[clave as 'min' | 'max']} aria-invalid={Boolean(errorMonto)} aria-describedby={errorMonto ? 'citas-error citas-monto-ayuda' : 'citas-monto-ayuda'} onChange={e => onCambiar({ [clave!]: e.target.value })} /></label>)}</div>
          </div>
          <p className="text-xs text-muted-foreground-strong" id="citas-monto-ayuda">Elige una moneda para filtrar el monto. Al cambiar de moneda se limpian los límites anteriores.</p>
        </div>
      </div>
      {error && <p id="citas-error" role="alert" className="border-t border-destructive/20 bg-destructive/5 px-5 py-3 text-sm text-destructive-text">{error}</p>}
    </form>
    <div className={etiquetas.length ? 'border-t border-border p-2' : 'sr-only'}><p className="sr-only">{`${fmtFecha(desde)} – ${fmtFecha(hasta)} · fecha prevista`}</p>{etiquetas.length > 0 && <div className="flex flex-wrap gap-2" aria-label="Filtros aplicados">{etiquetas.map(etiqueta => <Button key={etiqueta.id} variant="secondary" size="sm" className="h-auto max-w-full whitespace-normal py-1.5 text-left" aria-label={`Quitar ${etiqueta.texto}`} onClick={() => onCambiar(etiqueta.quitar)}>{etiqueta.texto}<X aria-hidden className="shrink-0" /></Button>)}</div>}</div>
  </section>
}
