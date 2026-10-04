// El INFORME de una carga de archivo (F5, E2 de Miguel: «38 cargados · 2 ya estaban · 1 con No insistir · 3 sin teléfono
// válido»): una pastilla por veredicto —cada una filtra la lista de abajo (todo número se abre)— y la lista fila por fila
// con su motivo. «Descargar informe» baja un CSV con la fila del archivo, el resultado y el motivo: NUNCA datos de otros
// leads (quién lo tiene, su id); quien lo descarga cruza la fila con su propio archivo.
import { useId, useState } from 'react'
import { Download } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Pastilla } from '@/components/base-gestion/filtros-base'
import { Paginacion } from '@/components/common/paginacion'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { descargarCsv } from '@/lib/exportar-csv'
import { paginar } from '@/lib/paginacion'
import { cn } from '@/lib/utils'
import {
  ROTULO_VEREDICTO,
  VEREDICTOS,
  VEREDICTO_SIN_ENVIAR,
  contarVeredictos,
  etiquetaMotivoFila,
  etiquetaVeredictoFila,
  informeCsv,
  type ResultadoFila,
  type Veredicto,
} from '@/lib/bases-cargadas'
import { CELDA_COMPACTA, ENCABEZADO_COMPACTO } from './piezas-bases'

/** Las urgentes (no entraron por un problema del archivo) se leen en rojo; las demás, neutras. */
const URGENTE: ReadonlySet<Veredicto> = new Set(['invalida'])

export function InformeCarga({ resultados, nombreBase, archivoNombre }: {
  /** Todas las filas: las del servidor y las que la vista previa no envió. */
  resultados: readonly ResultadoFila[]
  nombreBase: string
  archivoNombre: string
}) {
  const idTitulo = useId()
  const [filtro, setFiltro] = useState<string | null>(null)
  const [pagina, setPagina] = useState(0)
  const conteo = contarVeredictos(resultados)
  // Si la carga se terminó a medias, lo que no llegó a enviarse también se cuenta (y se abre).
  const sinEnviar = resultados.filter((r) => r.veredicto === VEREDICTO_SIN_ENVIAR).length
  const alternar = (v: string) => { setFiltro((f) => (f === v ? null : v)); setPagina(0) }
  const ordenadas = [...resultados].sort((a, b) => a.fila - b.fila)
  const visibles = filtro ? ordenadas.filter((r) => r.veredicto === filtro) : ordenadas
  const paginado = paginar(visibles, pagina)
  const descargar = () => {
    const nombre = `informe-${nombreBase.replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-|-$/g, '').toLowerCase() || 'base'}.csv`
    if (!descargarCsv(nombre, informeCsv(resultados))) toast.error('No se pudo descargar el informe.')
  }
  return (
    <section aria-labelledby={idTitulo} className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h3 id={idTitulo} className="text-[15px] font-bold text-primary">Informe de «{nombreBase}»</h3>
          <p className="text-[13px] text-[var(--muted-foreground-strong)]">{resultados.length.toLocaleString('es-PE')} filas de {archivoNombre}. Toca una cifra para ver esas filas.</p>
        </div>
        <Button type="button" variant="outline" className="h-9 pointer-coarse:h-11" onClick={descargar}>
          <Download aria-hidden /> Descargar informe
        </Button>
      </div>
      <div role="group" aria-label="Resultado por tipo" className="flex flex-wrap gap-2">
        {VEREDICTOS.map((v) => (
          <Pastilla
            key={v}
            etiqueta={ROTULO_VEREDICTO[v]}
            valor={conteo[v]}
            urgente={URGENTE.has(v) && conteo[v] > 0}
            presionada={filtro === v}
            pista="ver solo esas filas"
            onAbrir={conteo[v] > 0 || filtro === v ? () => alternar(v) : undefined}
          />
        ))}
        {sinEnviar > 0 && (
          <Pastilla etiqueta="Sin enviar" valor={sinEnviar} urgente presionada={filtro === VEREDICTO_SIN_ENVIAR} pista="ver solo esas filas" onAbrir={() => alternar(VEREDICTO_SIN_ENVIAR)} />
        )}
      </div>
      {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- El informe no tiene controles: se desplaza con el teclado desde aquí. */}
      <div tabIndex={0} role="region" aria-label="Resultado de cada fila" className={cn('ac-scroll max-h-[22rem] overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)}>
        <table className="min-w-full border-separate border-spacing-0">
          <caption className="sr-only">Resultado de cada fila del archivo{filtro ? `: solo «${etiquetaVeredictoFila(filtro)}»` : ''}.</caption>
          <thead>
            <tr>
              <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'w-24 text-right')}>Fila</th>
              <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left')}>Resultado</th>
              <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left')}>Motivo</th>
            </tr>
          </thead>
          <tbody>
            {paginado.visibles.map((r) => (
              <tr key={r.fila}>
                <th scope="row" className={cn(CELDA_COMPACTA, 'text-right font-normal tabular-nums text-[var(--muted-foreground-strong)]')}>{r.fila}</th>
                <td className={cn(CELDA_COMPACTA, r.veredicto === 'invalida' || r.veredicto === VEREDICTO_SIN_ENVIAR ? 'font-semibold text-[var(--destructive-text)]' : r.veredicto === 'cargada' ? 'font-semibold text-primary' : '')}>
                  {etiquetaVeredictoFila(r.veredicto)}
                </td>
                <td className={cn(CELDA_COMPACTA, 'whitespace-normal')}>{etiquetaMotivoFila(r.veredicto, r.motivo)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Paginacion paginaActual={paginado.paginaActual} paginas={paginado.paginas} total={visibles.length} onCambio={setPagina} ariaLabel="Páginas del informe" />
    </section>
  )
}
