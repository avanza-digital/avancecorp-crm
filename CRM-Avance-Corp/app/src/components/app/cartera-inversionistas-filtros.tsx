import {useRef, useState} from 'react'
import {Search, SlidersHorizontal} from 'lucide-react'
import {Button} from '@/components/ui/button'
import {Input} from '@/components/ui/input'
import {Label} from '@/components/ui/label'
import {Select} from '@/components/ui/select'
import {EMPRESAS_INVERSION, EMPRESA_NOMBRE, type CarteraInversionistas, type FiltrosInversionistas} from '@/lib/inversionistas'
import {etiquetaDeMes} from '@/lib/cartera-meses'
import {fechaLima} from '@/lib/agenda-derivada'

export function FiltrosCarteraInversionistas({filtros, busqueda, catalogo, verResponsable, onBusqueda, onCambio, onLimpiar}: {
  filtros: FiltrosInversionistas; busqueda: string; catalogo: CarteraInversionistas | null; verResponsable: boolean
  onBusqueda: (texto: string) => void; onCambio: (cambio: Partial<FiltrosInversionistas>) => void; onLimpiar: () => void
}) {
  const [mas, setMas] = useState(false)
  const antesDeVencer = useRef<Pick<FiltrosInversionistas, 'mes' | 'estado'> | null>(null)
  const sinInversiones = filtros.estado === 'sin_inversiones'
  const sinInversionesTexto = catalogo?.solo_avance ? 'Sin inversiones Avance' : 'Sin inversiones'
  const mesActual = fechaLima(Date.now()).slice(0, 7)
  const meses = [...new Set([mesActual, ...catalogo?.opciones_meses ?? [], ...(filtros.mes && filtros.mes !== 'sin_fecha' ? [filtros.mes] : [])])].sort().reverse()
  const adicionales = [filtros.moneda, filtros.estado, filtros.responsable, filtros.contacto, filtros.porVencer].filter(Boolean).length
  return <div className="space-y-3 p-4">
    <div className="grid grid-cols-2 items-end gap-3 @4xl/cartera:grid-cols-[minmax(15rem,2fr)_1fr_1fr_auto]">
      <div className="col-span-2 min-w-0 space-y-1 @4xl/cartera:col-span-1"><Label htmlFor="f5-buscar">Buscar persona</Label><div className="relative">
        <Search aria-hidden className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" />
        <Input id="f5-buscar" type="search" placeholder="Nombre, documento, contacto o referencia" className="pl-9" maxLength={120}
          value={busqueda} onChange={e => onBusqueda(e.target.value)} /></div></div>
      <div className="min-w-0 space-y-1"><Label htmlFor="f5-mes">Mes de cierre<span className="sr-only @lg/cartera:not-sr-only"> comercial</span></Label>
        <Select id="f5-mes" value={filtros.mes} disabled={sinInversiones} onChange={e => onCambio({mes:e.target.value})}>
          <option value="">Todos</option>{meses.map(m => <option key={m} value={m}>{etiquetaDeMes(m).replace(/^\S+/, nombre => nombre.slice(0,3)+'.')}</option>)}
          <option value="sin_fecha">Sin fecha</option></Select></div>
      <div className="min-w-0 space-y-1"><Label htmlFor="f5-empresa">Empresa</Label>
        <Select id="f5-empresa" value={filtros.empresa} disabled={sinInversiones} onChange={e => onCambio({empresa:e.target.value as FiltrosInversionistas['empresa']})}>
          <option value="">{catalogo?.solo_avance ? 'Avance' : 'Todas'}</option>{!catalogo?.solo_avance && EMPRESAS_INVERSION.map(e => <option value={e} key={e}>{EMPRESA_NOMBRE[e]}</option>)}</Select></div>
      <Button variant={adicionales ? 'secondary' : 'outline'} className="col-span-2 min-h-10 @4xl/cartera:col-span-1" aria-expanded={mas} aria-controls="f5-mas-filtros" onClick={() => setMas(v => !v)}>
        <SlidersHorizontal aria-hidden className="size-4" />Más filtros{adicionales > 0 && ` (${adicionales})`}</Button>
    </div>
    {mas && <div id="f5-mas-filtros" className="grid gap-3 border-t border-border pt-3 @lg/cartera:grid-cols-2 @4xl/cartera:grid-cols-4">
      <div className="space-y-1"><Label htmlFor="f5-estado">Estado de inversión</Label>
        <Select id="f5-estado" value={filtros.estado} onChange={e => {
          const estado = e.target.value as FiltrosInversionistas['estado']
          onCambio(estado === 'sin_inversiones' ? {estado, mes:'', empresa:'', moneda:'', porVencer:false}
            : {estado, ...(filtros.porVencer && estado !== 'vigente' ? {porVencer:false} : {})})
        }}><option value="">Todos los estados</option><option value="vigente">Activas / vigentes</option>
          <option value="vencido">Vencidas</option><option value="renovado">Renovadas</option><option value="retirado">Retiradas</option>
          <option value="anulado_comercialmente">Anuladas comercialmente</option><option value="sin_inversiones">{sinInversionesTexto}</option></Select></div>
      <div className="space-y-1"><Label htmlFor="f5-moneda">Moneda</Label>
        <Select id="f5-moneda" value={filtros.moneda} disabled={sinInversiones} onChange={e => onCambio({moneda:e.target.value as FiltrosInversionistas['moneda']})}>
          <option value="">Soles y dólares</option><option value="PEN">Soles (PEN)</option><option value="USD">Dólares (USD)</option></Select></div>
      {verResponsable && <div className="space-y-1"><Label htmlFor="f5-responsable">Responsable actual</Label>
        <Select id="f5-responsable" value={filtros.responsable} onChange={e => onCambio({responsable:e.target.value})}>
          <option value="">Todos los visibles</option><option value="sin_responsable">Sin responsable</option>
          {(catalogo?.opciones_responsables ?? []).map(r => <option key={r.id} value={r.id}>{r.nombre || 'Responsable sin nombre'}</option>)}</Select></div>}
      <div className="space-y-1"><Label htmlFor="f5-contacto">Contacto</Label>
        <Select id="f5-contacto" value={filtros.contacto} onChange={e => onCambio({contacto:e.target.value as FiltrosInversionistas['contacto']})}>
          <option value="">Todos</option><option value="sin_restriccion">Sin marca «No contactar»</option><option value="no_contactar">No contactar</option></Select></div>
      <label className="flex min-h-10 items-center gap-2 text-sm @lg/cartera:col-span-2">
        <input type="checkbox" className="size-4 accent-accent" checked={filtros.porVencer} disabled={sinInversiones}
          onChange={e => {
            if (e.target.checked) {
              antesDeVencer.current = {mes:filtros.mes, estado:filtros.estado}
              onCambio({porVencer:true, mes:'', estado:'vigente'})
            } else {
              // Restaurar solo si el usuario no cambió estos filtros mientras tanto.
              const anteriores = filtros.mes === '' && filtros.estado === 'vigente' ? antesDeVencer.current : null
              onCambio({porVencer:false, ...anteriores})
              antesDeVencer.current = null
            }
          }} />Por vencer en 30 días</label>
    </div>}
    <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-xs text-muted-foreground">
      <p className={sinInversiones || filtros.porVencer ? '' : 'hidden @lg/cartera:block'}>{sinInversiones
        ? `Clientes sin inversiones${catalogo?.solo_avance ? ' Avance' : ''}. Mes, empresa y moneda no se aplican.`
        : filtros.porVencer ? 'Inversiones vigentes que vencen entre hoy y los próximos 30 días.'
        : 'El mes corresponde al cierre comercial. La ficha conserva el historial completo.'}</p>
      <Button size="sm" variant="ghost" onClick={onLimpiar}>Limpiar filtros</Button>
    </div>
  </div>
}
