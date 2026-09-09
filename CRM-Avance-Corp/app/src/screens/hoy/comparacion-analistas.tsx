import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'
import type { ConversionMensual } from '@/lib/conversion-mensual'
import type { ConversionVendedoresAdaptada, DetalleConversionMensual } from '@/lib/conversion-vendedores'
import { numero, porcentajeConversionCanonica } from '@/lib/format'

const ESTADOS = {
  comparable: 'Comparable', solo_arrastre: 'Solo arrastre', solo_referidos: 'Solo recibió referidos',
  sin_muestra: 'Sin muestra', indisponible: 'No disponible',
}

export function ComparacionAnalistas({ datos, adaptada, cargando, error, mesEsperado, idsConDetalle, onAbrirDetalle }: {
  datos: ConversionMensual | null | undefined
  adaptada: ConversionVendedoresAdaptada<DetalleConversionMensual>
  cargando: boolean
  error: string | null
  mesEsperado?: string | undefined
  idsConDetalle: readonly string[]
  onAbrirDetalle: (id: string) => void
}) {
  const consulta = useConsultaGerencia()
  const [idsLocales, setIdsLocales] = useState<[string, string]>(['', ''])
  const [abiertaLocal, setAbiertaLocal] = useState(false)
  const ids = consulta?.consulta.comparacionIds ?? idsLocales
  const abierta = consulta?.consulta.comparacionAbierta ?? abiertaLocal
  const setAbierta = (valor: boolean) => {
    setAbiertaLocal(valor)
    if (valor) requestAnimationFrame(() => document.getElementById('comparacion-analistas')?.focus())
    consulta?.setConsulta((anterior) => ({ ...anterior, comparacionAbierta: valor }))
  }
  const seleccionar = (indice: number, id: string) => {
    const siguiente: [string, string] = indice === 0 ? [id, ids[1]] : [ids[0], id]
    setIdsLocales(siguiente)
    consulta?.setConsulta((anterior) => ({ ...anterior, comparacionIds: siguiente }))
  }
  const mismoMes = datos != null && (mesEsperado == null || datos.periodo.mes === mesEsperado)
  const disponible = !cargando && !error && mismoMes && adaptada.responsablesDisponibles
  const filas = ids.map((id) => adaptada.vendedores.find((fila) => fila.vendedorId === id) ?? null)
  const comparables = disponible && ids[0] !== ids[1] && filas.every((fila) => fila?.estadoConversion === 'comparable' && fila.detalle != null)
  const baseAutomatica = datos?.fuentes.divisor === 'crm.leads.creado_en'
  const medidas: { etiqueta: string; valor: (detalle: DetalleConversionMensual) => string }[] = [
    { etiqueta: 'Conversión', valor: (d) => porcentajeConversionCanonica(d.conversion_pct) },
    { etiqueta: baseAutomatica ? 'Base automática' : 'Base histórica', valor: (d) => numero(d.divisor) },
    { etiqueta: 'Aporte ponderado', valor: (d) => numero(d.numerador, 20) },
    { etiqueta: 'Cierres del mes', valor: (d) => numero(d.clientes) },
    { etiqueta: 'De ellos, de meses anteriores', valor: (d) => numero(d.cierres_de_arrastre) },
    { etiqueta: 'Operaciones de cartera', valor: (d) => numero(d.operacionesCartera) },
  ]
  return (
    <section className="gi-comparacion space-y-4" aria-label="Comparación de analistas">
      <Button id="comparacion-analistas-toggle" variant="outline" className="min-h-11" aria-expanded={abierta} aria-controls="comparacion-analistas" onClick={() => setAbierta(!abierta)}>
        {abierta ? 'Cerrar comparación' : 'Comparar dos analistas'}
      </Button>
      {abierta && <div id="comparacion-analistas" tabIndex={-1} className="space-y-4 rounded-2xl border border-[var(--gi-line)] bg-white p-4 sm:p-5">
        <h2 className="text-xl font-bold leading-7 tracking-[-.025em] text-[var(--gi-navy)]">Comparar dos analistas</h2>
        <p className="text-xs leading-[18px] text-[var(--muted-foreground-strong)]">Mes calendario · {datos?.periodo.mes_nombre ?? mesEsperado ?? 'mes por confirmar'} {datos?.periodo.anio ?? ''} · todos los orígenes. La comparación usa la misma fotografía mensual; no combina resultados del rango.</p>
        <div className="grid gap-3 sm:grid-cols-2">
          {(['Primer analista', 'Segundo analista'] as const).map((etiqueta, indice) => <label key={etiqueta} className="flex min-w-0 flex-col gap-2 text-xs font-semibold text-[var(--muted-foreground-strong)]">
            {etiqueta}
            <select aria-label={etiqueta} className="h-11 w-full min-w-0 rounded-[var(--gi-radius-8)] border border-[var(--gi-line)] bg-white px-3 text-sm font-normal text-[var(--gi-navy)] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40" disabled={!disponible} value={ids[indice]} onChange={(e) => seleccionar(indice, e.target.value)}>
              <option value="">Elegir analista</option>
              {ids[indice] && !filas[indice] && <option value={ids[indice]} disabled>Selección fuera de este alcance</option>}
              {adaptada.vendedores.map((fila) => <option key={fila.vendedorId} value={fila.vendedorId} disabled={fila.vendedorId === ids[1 - indice]}>{fila.nombre}{fila.estadoConversion === 'comparable' ? '' : ` · ${ESTADOS[fila.estadoConversion]}`}</option>)}
            </select>
          </label>)}
        </div>
        {!disponible ? <p role="status" className="rounded-lg bg-[var(--gi-soft)] p-3 text-sm">{cargando ? 'Consultando la fotografía mensual. La comparación espera a que termine la consulta.' : error ? 'No se pudo actualizar el mes. La selección se conserva, pero las cifras anteriores no se comparan.' : !mismoMes ? 'El mes disponible no corresponde a esta consulta.' : 'La comparación requiere una respuesta completa y verificable para todos los analistas del alcance.'}</p>
          : !comparables ? <p role="status" className="text-sm">{ids.some((id) => !id) ? 'Elige dos analistas para comparar sus resultados del mismo mes.' : 'Esta selección no es comparable. Revisa si falta el analista, su base o si sólo tiene referidos o arrastre. Las cifras no se sustituyen por cero.'}</p>
          : <>
            <table className="w-full table-fixed border-collapse text-xs leading-[18px]">
              <caption className="sr-only">Comparación mensual de {filas[0]?.nombre} y {filas[1]?.nombre}</caption>
              <thead className="bg-[var(--gi-soft)]"><tr><th scope="col" className="w-1/3 p-2 text-left">Lectura del mes</th>{filas.map((fila) => <th key={fila!.vendedorId} scope="col" className="w-1/3 break-words p-2 text-right">{fila!.nombre}</th>)}</tr></thead>
              <tbody>{medidas.map((medida) => <tr key={medida.etiqueta} className="border-b border-[var(--gi-line)]"><th scope="row" className="p-2 text-left font-normal text-[var(--muted-foreground-strong)]">{medida.etiqueta}</th>{filas.map((fila) => <td key={fila!.vendedorId} className="p-2 text-right [overflow-wrap:anywhere] tabular-nums text-[var(--gi-navy)]">{medida.valor(fila!.detalle!)}</td>)}</tr>)}</tbody>
            </table>
            <div className="flex flex-col gap-3 sm:flex-row">{filas.map((fila) => <Button key={fila!.vendedorId} variant="outline" className="min-h-11 rounded-[var(--gi-radius-8)] sm:min-w-57.5" disabled={!idsConDetalle.includes(fila!.vendedorId)} onClick={() => onAbrirDetalle(fila!.vendedorId)}>Ver detalle de {fila!.nombre.split(' ')[0]}</Button>)}</div>
            {filas.some((fila) => !idsConDetalle.includes(fila!.vendedorId)) && <p className="text-xs">El detalle individual requiere que el analista esté disponible también en los datos del rango consultado.</p>}
          </>}
        <p className="text-xs leading-[18px] text-[var(--muted-foreground-strong)]">La conversión no es el cumplimiento de una meta. La capacidad actual se consulta por separado en Rendimiento.</p>
        <details className="rounded-[var(--gi-radius-8)] bg-[var(--gi-soft)] p-3"><summary className="cursor-pointer py-1 text-sm font-semibold text-[var(--gi-blue)] focus-visible:ring-[3px] focus-visible:ring-accent/40">Cómo se calcula esta comparación</summary><p className="mt-2 text-xs leading-[18px] text-[var(--muted-foreground-strong)]">Cada porcentaje conserva el aporte ponderado y la base servidos. Los referidos y los cierres de meses anteriores tienen las ponderaciones de su mes. No se suman las dos filas ni se interpreta su promedio como conversión del equipo.</p></details>
      </div>}
    </section>
  )
}
