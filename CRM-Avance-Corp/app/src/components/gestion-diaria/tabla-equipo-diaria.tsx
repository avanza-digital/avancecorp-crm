import { useId } from 'react'
import { ArrowDown, ArrowUp } from 'lucide-react'
import { TablaEnvoltura, Th, Td } from '@/components/common/tabla'
import { Button } from '@/components/ui/button'
import { COLOR_NIVEL, ETIQUETA_NIVEL, horaLimaDe, textoTasa } from '@/lib/gestion-diaria-analista'
import { MOTIVOS_EQUIPO, tiempoSinLlamar, type FilaEquipoDiario, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'

const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
  { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'pendientes', titulo: 'Pendientes' },
  { orden: 'atencion', titulo: 'Atención' },
]

export function TablaEquipoDiaria({ filas, filtros, ordenar, abrirRegistro }: {
  filas: readonly FilaEquipoDiario[]
  filtros: FiltrosEquipo
  ordenar: (orden: OrdenEquipo) => void
  abrirRegistro: (id: string) => void
}) {
  const tablaId = useId()
  return (
    <TablaEnvoltura ariaLabel="Actividad y pendientes por analista">
      <thead className="border-b bg-muted/40 text-left text-primary">
        <tr>{COLUMNAS.map((c) => (
          <Th key={c.orden} scope="col" className="py-3 text-base"
            aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}>
            <button type="button" onClick={() => ordenar(c.orden)}
              className="flex min-h-11 cursor-pointer items-center gap-2 rounded-md font-semibold focus-visible:outline-2 focus-visible:outline-ring"
              aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}>
              {c.titulo}
              {filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp className="size-4" aria-hidden /> : <ArrowDown className="size-4" aria-hidden />)}
            </button>
          </Th>
        ))}</tr>
      </thead>
      {filas.length === 0 && <tbody><tr><Td colSpan={5} className="py-8 text-center text-base">Ningún analista coincide con estos filtros.</Td></tr></tbody>}
        {filas.map((f) => (
          <tbody key={f.analista_id} aria-labelledby={`${tablaId}-${f.analista_id}`} className="border-b last:border-0">
            <tr className="align-top" data-analista={f.analista_id}>
              <Th scope="rowgroup" id={`${tablaId}-${f.analista_id}`} className="min-w-60 pt-5 text-left text-base font-normal">
                <p className="font-semibold text-primary">{f.nombre_completo}</p>
                <p className="mt-1 text-[var(--muted-foreground-strong)]">
                  {f.gestiones_hoy === 0 ? 'Sin actividad registrada hoy' : `${f.gestiones_hoy} ${f.gestiones_hoy === 1 ? 'gestión registrada' : 'gestiones registradas'} hoy`}
                </p>
              </Th>
              <Td className="pt-5 text-right text-base tabular-nums">
                <p className="text-xl font-semibold">{f.marcador.llamadas}</p>
                <p className="whitespace-nowrap text-[var(--muted-foreground-strong)]">{f.marcador.contestadas} contestadas</p>
              </Td>
              <Td className="min-w-48 pt-5 text-base tabular-nums">
                <p>{textoTasa(f.marcador)}</p>
                {f.marcador.nivel !== null
                  ? <p className="mt-1 font-semibold" style={{ color: COLOR_NIVEL[f.marcador.nivel] }}>{ETIQUETA_NIVEL[f.marcador.nivel]}</p>
                  : <p className="mt-1 text-[var(--muted-foreground-strong)]">Sin muestra suficiente</p>}
              </Td>
              <Td className="min-w-44 pt-5 text-right text-base tabular-nums">
                <p>{f.tareas_pendientes} tareas pendientes</p>
                <p className={f.tareas_vencidas > 0 ? 'mt-1 font-semibold text-destructive-text' : 'mt-1 text-[var(--muted-foreground-strong)]'}>{f.tareas_vencidas} {f.tareas_vencidas === 1 ? 'vencida' : 'vencidas'}</p>
                <p className="mt-1">{f.primer_intento_vencido === null ? 'Primer intento: no evaluado' : `${f.primer_intento_vencido} primeros intentos fuera de plazo`}</p>
              </Td>
              <Td className="min-w-60 pt-5 text-base">
                {f.requiere_atencion
                  ? <ul className="space-y-1">{f.motivos_atencion.map((m) => <li key={m} className={m === 'tarea_vencida' || m === 'primer_intento_vencido' ? 'text-destructive-text' : 'text-[var(--warning-text)]'}>{MOTIVOS_EQUIPO[m]}</li>)}</ul>
                  : <p className="text-[var(--muted-foreground-strong)]">Sin alertas de esta vista</p>}
              </Td>
            </tr>
            <tr>
              <Td colSpan={5} headers={`${tablaId}-${f.analista_id}`} className="pb-4 text-base">
                <div className="flex flex-wrap items-start gap-x-6 gap-y-2">
                  <details className="min-w-0 flex-1">
                    <summary className="w-fit cursor-pointer rounded-md py-3 font-medium text-primary focus-visible:outline-2 focus-visible:outline-ring">Detalle de {f.nombre_completo}</summary>
                    <dl className="grid gap-x-8 gap-y-3 py-3 sm:grid-cols-2 lg:grid-cols-4">
                      {[
                        ['Llamadas útiles', f.marcador.utiles], ['Leads distintos', f.marcador.leads_tocados],
                        ['Llamadas por lead', f.llamadas_por_lead ?? '—'], ['Citas pendientes para hoy', f.citas_hoy],
                        ['Primera llamada', horaLimaDe(f.marcador.primera_llamada_en)], ['Última llamada', horaLimaDe(f.marcador.ultima_llamada_en)],
                        ['Tiempo sin llamar', tiempoSinLlamar(f.minutos_sin_llamar)], ['Última gestión', horaLimaDe(f.ultima_gestion_en)],
                      ].map(([titulo, valor]) => <div key={titulo}><dt className="text-[var(--muted-foreground-strong)]">{titulo}</dt><dd className="mt-1 font-semibold tabular-nums">{valor}</dd></div>)}
                    </dl>
                  </details>
                  <Button variant="outline" className="min-h-11 text-base" onClick={() => abrirRegistro(f.analista_id)} aria-label={`Ver registro de ${f.nombre_completo}`}>Ver registro</Button>
                </div>
              </Td>
            </tr>
          </tbody>
        ))}
    </TablaEnvoltura>
  )
}
