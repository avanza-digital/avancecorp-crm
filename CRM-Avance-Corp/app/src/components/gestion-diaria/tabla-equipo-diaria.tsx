import { useId, useState } from 'react'
import { ArrowDown, ArrowUp, ChevronDown } from 'lucide-react'
import { TablaEnvoltura, Th, Td } from '@/components/common/tabla'
import { Button } from '@/components/ui/button'
import { COLOR_NIVEL, ETIQUETA_NIVEL, textoTasa } from '@/lib/gestion-diaria-analista'
import { MOTIVOS_EQUIPO, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
import type { PestanaRegistro } from '@/lib/gestion-diaria'
import { DetalleAnalista } from './detalle-analista'

const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
  { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'pendientes', titulo: 'Pendientes' },
  { orden: 'atencion', titulo: 'Atención' },
]

export function TablaEquipoDiaria({ filas, dia, filtros, ordenar, abrirRegistro }: {
  filas: readonly FilaEquipoPresentada[]
  dia: string
  filtros: FiltrosEquipo
  ordenar: (orden: OrdenEquipo) => void
  abrirRegistro: (id: string, pestana?: PestanaRegistro) => void
}) {
  const tablaId = useId()
  return (
    <div className="@container">
      <TablaEnvoltura ariaLabel="Actividad y pendientes por analista">
        <thead className="border-b border-border bg-muted/60 text-left text-[var(--muted-foreground-strong)]">
          <tr>{COLUMNAS.map((c) => (
            <Th key={c.orden} scope="col" className="px-5 py-2 text-base"
              aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}>
              <button type="button" onClick={() => ordenar(c.orden)}
                className={`flex min-h-11 cursor-pointer items-center gap-2 rounded-md font-semibold focus-visible:outline-2 focus-visible:outline-ring ${c.orden === 'llamadas' ? 'ml-auto' : ''}`}
                aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}>
                {c.titulo}
                {filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp className="size-4" aria-hidden /> : <ArrowDown className="size-4" aria-hidden />)}
              </button>
            </Th>
          ))}</tr>
        </thead>
        {filas.length === 0 && <tbody><tr><Td colSpan={5} className="py-8 text-center text-base">Ningún analista coincide con estos filtros.</Td></tr></tbody>}
        {filas.map((f) => <FilaDeEquipo key={f.analista_id} fila={f} id={`${tablaId}-${f.analista_id}`} dia={dia} abrirRegistro={abrirRegistro} />)}
      </TablaEnvoltura>
    </div>
  )
}

/** Los controles pertenecen a la persona; su evidencia se expande a todo el ancho. */
function FilaDeEquipo({ fila: f, id, dia, abrirRegistro }: {
  fila: FilaEquipoPresentada
  id: string
  dia: string
  abrirRegistro: (id: string, pestana?: PestanaRegistro) => void
}) {
  const [abierto, setAbierto] = useState(false)
  return (
    <tbody aria-labelledby={id} className="border-b border-border last:border-0">
      <tr className="align-top" data-analista={f.analista_id}>
        <Th scope="rowgroup" id={id} aria-label={f.nombre_completo} className="min-w-60 px-5 py-5 text-left text-base font-normal">
          <p className="text-lg font-semibold text-primary">{f.nombre_completo}</p>
          <p className="mt-1 text-[var(--muted-foreground-strong)]">
            {f.gestiones_hoy === 0 ? 'Sin actividad registrada hoy' : `${f.gestiones_hoy} ${f.gestiones_hoy === 1 ? 'gestión registrada' : 'gestiones registradas'} hoy`}
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-x-4">
            <Button variant="ghost" aria-expanded={abierto} aria-controls={`${id}-detalle`} aria-label={`Detalle de ${f.nombre_completo}`}
              onClick={() => setAbierto((v) => !v)} className="min-h-11 px-0 text-base text-primary hover:bg-transparent hover:underline focus-visible:outline-2 focus-visible:outline-solid focus-visible:outline-offset-2 focus-visible:outline-ring">
              Detalle<ChevronDown aria-hidden className={`size-4 transition-transform ${abierto ? 'rotate-180' : ''}`} />
            </Button>
            <Button variant="ghost" className="min-h-11 px-0 text-base text-accent hover:bg-transparent hover:underline focus-visible:outline-2 focus-visible:outline-solid focus-visible:outline-offset-2 focus-visible:outline-ring" onClick={() => abrirRegistro(f.analista_id)} aria-label={`Ver registro de ${f.nombre_completo}`}>Ver registro</Button>
          </div>
        </Th>
        <Td className="px-5 pt-5 text-right text-base tabular-nums">
          <p className="text-2xl font-extrabold leading-8 text-primary">{f.marcador.llamadas}</p>
          <p className="whitespace-nowrap text-[var(--muted-foreground-strong)]">{f.marcador.contestadas} contestadas</p>
        </Td>
        <Td className="min-w-48 px-5 pt-5 text-base tabular-nums">
          <p className="font-semibold leading-8 text-primary">{textoTasa(f.marcador)}</p>
          {f.marcador.nivel !== null
            ? <p className="mt-1 font-semibold" style={{ color: COLOR_NIVEL[f.marcador.nivel] }}>{ETIQUETA_NIVEL[f.marcador.nivel]}</p>
            : <p className="mt-1 text-[var(--muted-foreground-strong)]">Sin muestra suficiente</p>}
        </Td>
        <Td className="min-w-52 px-5 pt-5 text-base tabular-nums">
          <p className="font-semibold leading-8 text-primary">{f.tareas_pendientes} tareas pendientes</p>
          <p className={f.tareas_vencidas > 0 ? 'mt-1 font-semibold text-destructive-text' : 'mt-1 text-[var(--muted-foreground-strong)]'}>{f.tareas_vencidas} {f.tareas_vencidas === 1 ? 'vencida' : 'vencidas'}</p>
          <p className="mt-1 text-[var(--muted-foreground-strong)]">{f.primer_intento_vencido === null ? 'Primer intento: no evaluado' : `${f.primer_intento_vencido} primeros intentos fuera de plazo`}</p>
        </Td>
        <Td className="min-w-60 px-5 pt-5 text-base">
          {f.requiere_atencion
            ? <ul className="space-y-2">{f.motivos_atencion.map((m) => <li key={m} className={`border-l-2 py-1 pl-3 font-medium ${m === 'tarea_vencida' || m === 'primer_intento_vencido' ? 'border-destructive/40 text-destructive-text' : 'border-warning/40 text-[var(--warning-text)]'}`}>{MOTIVOS_EQUIPO[m]}</li>)}</ul>
            : <p className="text-[var(--muted-foreground-strong)]">Sin alertas de esta vista</p>}
        </Td>
      </tr>
      <tr hidden={!abierto}>
        <Td colSpan={5} headers={id} className="px-5 pt-0 pb-5 text-base">
          {/* Se limita al ancho VISIBLE de la tabla, descontando el padding de
              la celda. Así las horas se desplazan en su región con teclado,
              también cuando las columnas exigen scroll horizontal. */}
          <div id={`${id}-detalle`} role="region" aria-label={`Detalle de ${f.nombre_completo}`} className="w-[calc(100cqw_-_2.5rem)] max-w-full rounded-lg border border-border bg-muted/30 p-4">
            <DetalleAnalista fila={f} dia={dia} abrirLlamadas={() => abrirRegistro(f.analista_id, 'llamadas')} />
          </div>
        </Td>
      </tr>
    </tbody>
  )
}
