// Lo que hay detrás de una cifra de «Bases» (todo número se abre): una hoja lateral con la lista del servidor
// (`crm.seguimiento_base_detalle`): el contacto, su estado, cuándo se asignó y su último intento. De la base entera
// (hoja de bases, pastillas de la base) o de un analista (seguimiento). Estados honestos: cargando, error con
// reintento, «aún no disponible» (servidor sin B10: nunca un cero inventado) y vacío.
import { useRef, type JSX } from 'react'
import { ListX, X } from 'lucide-react'
import { Sheet, SheetBody, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { etiquetaMomento } from '@/lib/base-gestion'
import { etiquetaResultado } from '@/lib/resultado-llamada'
import { etiquetaEstadoContacto, ROTULO_CIFRA, TEXTO_FUERA_DE_EQUIPO, type CifraSeguimiento, type FilaDetalleSeguimiento } from '@/lib/bases-cargadas'
import { AvisoReintentar, CELDA_COMPACTA, ENCABEZADO_COMPACTO, ROTULO } from './piezas-bases'

export interface CifraBaseAbierta {
  baseId: string
  baseNombre: string
  /** null = la base entera. */
  analistaId: string | null
  analistaNombre: string | null
  cifra: CifraSeguimiento
  valor: number
}

const momento = (iso: string | null, ahora: number) => (iso ? etiquetaMomento(iso, ahora) : '—')

export function DetalleCifraBase({ abierta, filas, cargando, error, reintentando, onReintentar, ahora, esMovil, onCerrar }: {
  abierta: CifraBaseAbierta | null
  /** `undefined` mientras carga; `null` si el servidor aún no tiene la lectura. */
  filas: readonly FilaDetalleSeguimiento[] | null | undefined
  cargando: boolean
  error: boolean
  reintentando: boolean
  onReintentar: () => Promise<boolean>
  ahora: number
  esMovil: boolean
  onCerrar: () => void
}): JSX.Element {
  const cabecera = useRef<HTMLDivElement>(null)
  const titulo = abierta ? ROTULO_CIFRA[abierta.cifra] : ''
  const reintentar = async () => { if (await onReintentar()) requestAnimationFrame(() => cabecera.current?.focus()) }
  return (
    <Sheet open={abierta !== null} onClose={onCerrar} className="w-full max-w-full sm:w-[760px] sm:max-w-[94vw]">
      {abierta && (
        <>
          <SheetHeader>
            <div className="flex items-start justify-between gap-3">
              <div ref={cabecera} tabIndex={-1} className={cn('min-w-0 rounded', FOCO)}>
                <p className={ROTULO}>{abierta.baseNombre}{abierta.analistaNombre ? ` · ${abierta.analistaNombre}` : ''}</p>
                <SheetTitle className="text-lg">{titulo} <span className="tabular-nums text-primary">· {abierta.valor.toLocaleString('es-PE')}</span></SheetTitle>
                <SheetDescription className="text-[13px] text-[var(--muted-foreground-strong)]">
                  Los contactos detrás de esta cifra, con su estado y su último intento.
                </SheetDescription>
              </div>
              <button type="button" onClick={onCerrar} aria-label="Cerrar el detalle" className={cn('grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground pointer-coarse:size-11', FOCO)}>
                <X className="size-4" aria-hidden />
              </button>
            </div>
          </SheetHeader>
          {/* El cuerpo se desplaza con el teclado (la lista no tiene controles por los que pasar con Tab). */}
          {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Región desplazable sin controles dentro: necesita su parada de tabulador. */}
          <SheetBody tabIndex={0} role="region" aria-label={`${titulo} de ${abierta.baseNombre}`} className={cn('scroll-pt-10 px-0 py-0', FOCO, 'focus-visible:-outline-offset-2')}>
            {error && filas !== undefined && (
              <div className="m-4"><AvisoReintentar conDatos mensaje="No se pudo actualizar el detalle. Se muestran los últimos datos." reintentando={reintentando} onReintentar={() => void reintentar()} /></div>
            )}
            {cargando && filas === undefined ? (
              <div className="pt-4"><PanelCargando filas={5} /></div>
            ) : error && filas === undefined ? (
              <div className="m-4"><AvisoReintentar mensaje="No se pudo cargar el detalle." reintentando={reintentando} onReintentar={() => void reintentar()} /></div>
            ) : filas === null ? (
              <PanelVacio icono={ListX} titulo="El detalle aún no está disponible" detalle="Llega con la próxima actualización del servidor. La cifra sí es la vigente." />
            ) : !filas || filas.length === 0 ? (
              <PanelVacio icono={ListX} titulo="Ya no hay contactos detrás de esta cifra" detalle="Pudo cambiar desde que se cargó la hoja: vuelve a abrirla para ver la cifra al día." />
            ) : esMovil ? (
              <div role="list" aria-label={`${titulo} de ${abierta.baseNombre}`} className="space-y-2 p-4">
                {filas.map((f, i) => (
                  <div role="listitem" key={f.lead_id ?? `fuera-${i}`} className="rounded-xl border border-border bg-card p-3">
                    <p className={cn('text-base font-semibold', !f.nombre_completo && 'text-[var(--muted-foreground-strong)]')}>{f.nombre_completo ?? TEXTO_FUERA_DE_EQUIPO}</p>
                    <p className="text-sm">{etiquetaEstadoContacto(f.estado)}{f.ultimo_resultado ? ` · ${etiquetaResultado(f.ultimo_resultado)}` : ''}</p>
                    <p className="text-[13px] text-[var(--muted-foreground-strong)]">Asignado: {momento(f.asignado_en, ahora)} · Último intento: {momento(f.ultimo_intento_en, ahora)}</p>
                  </div>
                ))}
              </div>
            ) : (
              <table className="min-w-full border-separate border-spacing-0">
                <caption className="sr-only">{titulo} de {abierta.baseNombre}</caption>
                <thead>
                  <tr>
                    {['#', 'Contacto', 'Estado', 'Asignado', 'Último intento', 'Último resultado'].map((c, i) => (
                      <th key={c} scope="col" className={cn(ENCABEZADO_COMPACTO, 'text-left', i === 0 && 'w-10 text-center')}>{c}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {filas.map((f, i) => (
                    <tr key={f.lead_id ?? `fuera-${i}`} className="hover:bg-accent/5">
                      <td className={cn(CELDA_COMPACTA, 'text-center text-[13px] tabular-nums text-[var(--muted-foreground-strong)]')}>{i + 1}</td>
                      <th scope="row" className={cn(CELDA_COMPACTA, 'max-w-56 truncate text-left font-semibold', !f.nombre_completo && 'font-normal italic text-[var(--muted-foreground-strong)]')}>{f.nombre_completo ?? TEXTO_FUERA_DE_EQUIPO}</th>
                      <td className={CELDA_COMPACTA}>{etiquetaEstadoContacto(f.estado)}</td>
                      <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{momento(f.asignado_en, ahora)}</td>
                      <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{momento(f.ultimo_intento_en, ahora)}</td>
                      <td className={CELDA_COMPACTA}>{f.ultimo_resultado ? etiquetaResultado(f.ultimo_resultado) : <span className="text-[var(--muted-foreground-strong)]">Sin intentos</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </SheetBody>
        </>
      )}
    </Sheet>
  )
}
