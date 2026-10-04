// La HOJA de la base para gestión (extraída de la vista del analista en F4, 03/10/2026, para que la vista del
// supervisor pinte la misma). Forma (Miguel, 02/10/2026): en escritorio una HOJA DE CÁLCULO —cuadrícula, un dato por
// celda, número de fila, encabezado y primeras columnas fijos al desplazar, la fila «hoy» con formato condicional—;
// en el celular, tarjetas (quien la monta decide con `esMovil`: se monta solo una de las dos).
// Los bloques (F3): con `conBandas`, cada bloque («Llamar hoy», «El resto») lleva su título dentro de la hoja y su
// grupo de filas; sin bandas, una sola lista. El número de fila sigue de un bloque al otro (y de una página a otra
// con `numeroInicial`). La vista del supervisor (F4) añade la columna «Gestiona», fija como tercera, y la consulta
// sin llamar: el teléfono se lee pero no marca ni copia (`llamable = false`).
import type { ReactNode, Ref } from 'react'
import { Phone } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { enlaceTel } from '@/lib/telefono'
import {
  etiquetaAnalista,
  etiquetaDiasDescarte,
  etiquetaMomento,
  etiquetaMotivoDescarte,
  etiquetaOrigen,
  etiquetaUltimoResultado,
  type FilaBaseGestion,
} from '@/lib/base-gestion'
import { TelefonoLlamable } from './llamar-base'
import { copiarNumero } from './copiar-numero'
import { EtapaMaximaChip, Intentos, MesDelLead, ProximaLlamada } from './piezas-base'

const BOTON_LLAMAR = cn(
  'inline-flex h-10 items-center justify-center gap-2 whitespace-nowrap rounded-lg bg-accent px-4 text-sm font-semibold text-accent-foreground transition-colors hover:bg-[var(--accent-press)] pointer-coarse:h-11',
  FOCO,
)

// ── La hoja: celdas de cuadrícula, una línea por celda ──────────────────────────────────────────────────────
const ANCHO_NUMERO = 'w-12 min-w-12'
const ANCHO_LEAD = 'w-64 min-w-64'
const ANCHO_GESTIONA = 'w-48 min-w-48'
export const CELDA = 'whitespace-nowrap border-b border-r border-border px-3 py-2 text-left align-middle text-sm text-foreground'
export const ENCABEZADO = 'sticky top-0 z-10 whitespace-nowrap border-b border-r border-[var(--border-strong)] bg-muted px-3 py-2 text-left text-[13px] font-semibold text-[var(--muted-foreground-strong)]'
// Las primeras columnas quedan fijas al desplazar en horizontal (como «inmovilizar paneles»): necesitan fondo propio.
const FIJA_NUMERO = 'sticky left-0'
const FIJA_LEAD = 'sticky left-12'
/** Tercera fija: tras el # (3rem) y el lead (16rem). */
const FIJA_GESTIONA = 'sticky left-[19rem]'
/** Columnas de la hoja sin la del Mes ni la de «Gestiona» (la banda de cada bloque las abarca todas). */
const COLUMNAS_BASE = 12

/** Un bloque de la hoja: su título (h2), su detalle, cuántos leads tiene EN TOTAL y las filas que se pintan. */
export interface BloqueHoja {
  id: string
  titulo: string
  detalle: string
  /** El conteo del título: el del bloque entero (con páginas, puede ser mayor que `filas.length`). */
  n: number
  filas: readonly FilaBaseGestion[]
  urgente?: boolean
  tituloRef?: Ref<HTMLHeadingElement> | undefined
}

export function HojaBase({
  bloques, conBandas, esMovil, etiqueta, caption, conMes, conGestiona = false, llamable = true, numeroInicial = 1,
  ahora, puedeMarcar, onAbrir, regionRef, listaRef,
}: {
  /** En orden; sin filas no se pasan (no se pinta un bloque vacío). */
  bloques: readonly BloqueHoja[]
  /** Con título por bloque; si no, una sola lista con las filas de todos. */
  conBandas: boolean
  esMovil: boolean
  /** Nombre de la región (escritorio) o de la lista (celular): «Tu base para gestión». */
  etiqueta: string
  /** Descripción de la tabla para el lector (sr-only). */
  caption: ReactNode
  conMes: boolean
  /** F4: columna «Gestiona», fija como tercera. */
  conGestiona?: boolean
  /** El teléfono marca (celular) o copia (laptop); `false` = solo se lee (la vista del supervisor consulta). */
  llamable?: boolean
  /** Número de la primera fila (páginas: el # es continuo). */
  numeroInicial?: number
  ahora: number
  puedeMarcar: boolean
  onAbrir: (leadId: string) => void
  regionRef?: Ref<HTMLDivElement> | undefined
  listaRef?: Ref<HTMLDivElement> | undefined
}) {
  const columnas = COLUMNAS_BASE + (conMes ? 1 : 0) + (conGestiona ? 1 : 0)
  // El número de fila sigue de un bloque al otro: el último número es el total que dice la pastilla.
  const inicios: number[] = []
  let siguiente = numeroInicial
  for (const b of bloques) { inicios.push(siguiente); siguiente += b.filas.length }
  const filaHoja = (f: FilaBaseGestion, numero: number) => (
    <FilaHoja key={f.lead_id} numero={numero} fila={f} ahora={ahora} puedeMarcar={puedeMarcar} conMes={conMes} conGestiona={conGestiona} llamable={llamable} onAbrir={() => onAbrir(f.lead_id)} />
  )
  const tarjeta = (f: FilaBaseGestion) => (
    <TarjetaBase key={f.lead_id} fila={f} ahora={ahora} puedeMarcar={puedeMarcar} conMes={conMes} conGestiona={conGestiona} llamable={llamable} onAbrir={() => onAbrir(f.lead_id)} />
  )

  if (esMovil) {
    return conBandas ? (
      <div ref={listaRef} tabIndex={-1} role="region" aria-label={etiqueta} className={cn('space-y-5 rounded-lg', FOCO)}>
        {bloques.map((b) => (
          <BloqueTarjetas key={b.id} id={b.id} titulo={b.titulo} detalle={b.detalle} n={b.n} urgente={b.urgente ?? false} tituloRef={b.tituloRef}>
            {b.filas.map(tarjeta)}
          </BloqueTarjetas>
        ))}
      </div>
    ) : (
      // Rol explícito: con el list-style:none del preflight, Safari + VoiceOver deja de anunciar un <ul> como lista.
      <div ref={listaRef} tabIndex={-1} role="list" aria-label={etiqueta} className={cn('space-y-3 rounded-lg', FOCO)}>
        {bloques.flatMap((b) => b.filas).map(tarjeta)}
      </div>
    )
  }

  return (
    // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La hoja se desplaza con el teclado en los dos ejes.
    <div ref={regionRef} className={cn('ac-scroll max-h-[calc(100dvh-14rem)] scroll-pt-11 overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', conGestiona ? 'scroll-pl-[31rem]' : 'scroll-pl-[19rem]', FOCO)} tabIndex={0} role="region" aria-label={etiqueta}>
      <table className="min-w-full border-separate border-spacing-0">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr>
            <th scope="col" className={cn(ENCABEZADO, FIJA_NUMERO, ANCHO_NUMERO, 'z-20 text-center')}>#</th>
            <th scope="col" className={cn(ENCABEZADO, FIJA_LEAD, ANCHO_LEAD, 'z-20')}>Lead</th>
            {conGestiona && <th scope="col" className={cn(ENCABEZADO, FIJA_GESTIONA, ANCHO_GESTIONA, 'z-20')}>Gestiona</th>}
            {conMes && <th scope="col" className={ENCABEZADO}>Mes</th>}
            <th scope="col" className={ENCABEZADO}>Teléfono</th>
            <th scope="col" className={ENCABEZADO}>Próxima llamada</th>
            <th scope="col" className={ENCABEZADO}>Intentos</th>
            <th scope="col" className={ENCABEZADO}>Último resultado</th>
            <th scope="col" className={ENCABEZADO}>Último intento</th>
            <th scope="col" className={ENCABEZADO}>Etapa máxima</th>
            <th scope="col" className={ENCABEZADO}>Motivo del descarte</th>
            <th scope="col" className={ENCABEZADO}>Descartado</th>
            <th scope="col" className={ENCABEZADO}>Distrito</th>
            <th scope="col" className={cn(ENCABEZADO, 'border-r-0')}>Origen</th>
          </tr>
        </thead>
        {/* Una sola hoja (las columnas no se desalinean) con un grupo de filas por bloque. */}
        {conBandas ? bloques.map((b, i) => (
          <tbody key={b.id} aria-labelledby={b.id}>
            <BandaBloque id={b.id} titulo={b.titulo} detalle={b.detalle} n={b.n} columnas={columnas} urgente={b.urgente ?? false} tituloRef={b.tituloRef} />
            {b.filas.map((f, j) => filaHoja(f, (inicios[i] ?? numeroInicial) + j))}
          </tbody>
        )) : (
          <tbody>
            {bloques.flatMap((b) => b.filas).map((f, j) => filaHoja(f, numeroInicial + j))}
          </tbody>
        )}
      </table>
    </div>
  )
}

/** Título de un bloque dentro de la hoja: una fila que abarca todas las columnas, con el texto fijo a la izquierda al
 *  desplazar en horizontal. Es un encabezado de verdad (h2) y nombra su grupo de filas. */
function BandaBloque({ id, titulo, detalle, n, columnas, urgente = false, tituloRef }: {
  id: string
  titulo: string
  detalle: string
  n: number
  columnas: number
  urgente?: boolean
  tituloRef?: Ref<HTMLHeadingElement> | undefined
}) {
  return (
    <tr>
      <td colSpan={columnas} className={cn('border-b border-[var(--border-strong)] p-0', urgente ? 'bg-[color-mix(in_srgb,var(--destructive)_10%,var(--card))]' : 'bg-muted')}>
        <div className="sticky left-0 inline-flex items-center gap-3 px-3 py-2">
          <TituloBloque id={id} titulo={titulo} n={n} urgente={urgente} tituloRef={tituloRef} />
          <span className="text-[13px] text-[var(--muted-foreground-strong)]">{detalle}</span>
        </div>
      </td>
    </tr>
  )
}

export function TituloBloque({ id, titulo, n, urgente, tituloRef }: { id: string; titulo: string; n: number; urgente: boolean; tituloRef?: Ref<HTMLHeadingElement> | undefined }) {
  return (
    <h2 id={id} ref={tituloRef} tabIndex={-1} className={cn('inline-flex items-center gap-2 rounded text-[15px] font-bold', urgente ? 'text-[var(--destructive-text)]' : 'text-foreground', FOCO)}>
      {titulo}
      <span className="sr-only">:</span>
      <span className={cn('rounded-full px-2 py-0.5 text-[13px] tabular-nums', urgente ? 'bg-destructive text-destructive-foreground' : 'bg-primary/10 text-primary')}>{n}</span>
    </h2>
  )
}

/** Un bloque en el celular: su título y su lista de tarjetas. */
function BloqueTarjetas({ id, titulo, detalle, n, urgente = false, tituloRef, children }: {
  id: string
  titulo: string
  detalle: string
  n: number
  urgente?: boolean
  tituloRef?: Ref<HTMLHeadingElement> | undefined
  children: ReactNode
}) {
  return (
    // Un <div>, no otra región: ya está dentro de la región de la base (el nombre se anunciaría dos veces).
    // El h2 y la lista con nombre bastan para ubicarse.
    <div className="space-y-2">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
        <TituloBloque id={id} titulo={titulo} n={n} urgente={urgente} tituloRef={tituloRef} />
        <span className="text-[13px] text-[var(--muted-foreground-strong)]">{detalle}</span>
      </div>
      <div role="list" aria-labelledby={id} className="space-y-3">{children}</div>
    </div>
  )
}

/** El teléfono que solo se lee (la vista del supervisor consulta: no marca ni copia). */
function TelefonoLeido({ fila }: { fila: FilaBaseGestion }) {
  if (!enlaceTel(fila.telefono) || !fila.telefono) return <span className="text-[var(--muted-foreground-strong)]">Sin teléfono</span>
  return <span className="tabular-nums">{telefonoLegible(fila.telefono)}</span>
}

function FilaHoja({ numero, fila, ahora, puedeMarcar, conMes, conGestiona, llamable, onAbrir }: {
  numero: number
  fila: FilaBaseGestion
  ahora: number
  puedeMarcar: boolean
  conMes: boolean
  conGestiona: boolean
  llamable: boolean
  onAbrir: () => void
}) {
  const hoy = fila.rellamada_hoy
  // Las celdas fijas llevan fondo opaco (tapan lo que pasa por debajo al desplazar); la fila «hoy» lo tiñe igual.
  const fondoFijo = hoy ? 'bg-[color-mix(in_srgb,var(--destructive)_6%,var(--card))]' : 'bg-card group-hover:bg-[color-mix(in_srgb,var(--accent)_5%,var(--card))]'
  return (
    <tr className={cn('group', hoy ? 'bg-destructive/[0.06]' : 'hover:bg-accent/5')}>
      <td className={cn(CELDA, FIJA_NUMERO, ANCHO_NUMERO, 'z-[1] text-center text-[13px] tabular-nums', hoy ? 'bg-[color-mix(in_srgb,var(--destructive)_15%,var(--card))] font-bold text-[var(--destructive-text)]' : 'bg-muted text-[var(--muted-foreground-strong)]')}>
        {numero}
      </td>
      <th scope="row" className={cn(CELDA, FIJA_LEAD, ANCHO_LEAD, 'z-[1] max-w-64 truncate text-base font-semibold', fondoFijo)} title={fila.nombre_completo}>
        {/* El nombre abre la ficha (F2); la clave estable devuelve el foco aquí aunque la fila se repinte. */}
        <button type="button" onClick={onAbrir} data-foco-clave={`base-ficha-${fila.lead_id}`} className={cn('max-w-full cursor-pointer truncate rounded text-left underline decoration-[var(--border-strong)] decoration-dotted underline-offset-4 hover:decoration-solid hover:decoration-current', FOCO)}>
          {fila.nombre_completo}
          {hoy && <span className="sr-only"> — toca llamar hoy</span>}
        </button>
      </th>
      {conGestiona && (
        <td className={cn(CELDA, FIJA_GESTIONA, ANCHO_GESTIONA, 'z-[1] max-w-48 truncate', fondoFijo, !fila.vendedor_id && 'text-[var(--muted-foreground-strong)]')} title={etiquetaAnalista(fila)}>
          {etiquetaAnalista(fila)}
        </td>
      )}
      {conMes && <td className={CELDA}><MesDelLead fila={fila} /></td>}
      <td className={CELDA}>{llamable ? <TelefonoLlamable fila={fila} puedeMarcar={puedeMarcar} /> : <TelefonoLeido fila={fila} />}</td>
      <td className={CELDA}><ProximaLlamada iso={fila.proxima_llamada_en} ahora={ahora} /></td>
      <td className={CELDA}><Intentos n={fila.intentos} /></td>
      <td className={CELDA}>{etiquetaUltimoResultado(fila.ultimo_resultado)}</td>
      <td className={cn(CELDA, 'tabular-nums text-[var(--muted-foreground-strong)]')}>{fila.ultimo_intento_en ? etiquetaMomento(fila.ultimo_intento_en, ahora) : '—'}</td>
      <td className={CELDA}><EtapaMaximaChip etapa={fila.etapa_maxima} /></td>
      <td className={CELDA}>{etiquetaMotivoDescarte(fila.motivo_descarte)}</td>
      <td className={cn(CELDA, 'tabular-nums')}>{etiquetaDiasDescarte(fila.dias_desde_descarte)}</td>
      <td className={CELDA}>{fila.distrito ?? '—'}</td>
      <td className={cn(CELDA, 'border-r-0')}>{etiquetaOrigen(fila.origen)}</td>
    </tr>
  )
}

/** Teléfono · distrito · origen: lo que el analista necesita a la vista para ubicar al lead (tarjeta del celular). */
function contactoDe(fila: FilaBaseGestion): string {
  return [fila.telefono ? telefonoLegible(fila.telefono) : null, fila.distrito, etiquetaOrigen(fila.origen)]
    .filter((parte): parte is string => !!parte)
    .join(' · ')
}

function TarjetaBase({ fila, ahora, puedeMarcar, conMes, conGestiona, llamable, onAbrir }: {
  fila: FilaBaseGestion
  ahora: number
  puedeMarcar: boolean
  conMes: boolean
  conGestiona: boolean
  llamable: boolean
  onAbrir: () => void
}) {
  const dato = 'text-sm text-foreground'
  const rotulo = 'text-[13px] font-semibold text-[var(--muted-foreground-strong)]'
  return (
    <div role="listitem" className={cn('rounded-xl border bg-card p-4', fila.rellamada_hoy ? 'border-destructive/40 shadow-[inset_4px_0_0_var(--destructive)]' : 'border-border')}>
      <p className="text-base font-semibold text-foreground">{fila.nombre_completo}</p>
      <p className="text-sm text-[var(--muted-foreground-strong)]">{contactoDe(fila)}</p>
      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2">
        {conGestiona && <div className="col-span-2"><dt className={rotulo}>Gestiona</dt><dd className={dato}>{etiquetaAnalista(fila)}</dd></div>}
        {conMes && <div><dt className={rotulo}>Mes</dt><dd className={dato}><MesDelLead fila={fila} /></dd></div>}
        <div><dt className={rotulo}>Próxima llamada</dt><dd className={dato}><ProximaLlamada iso={fila.proxima_llamada_en} ahora={ahora} /></dd></div>
        <div><dt className={rotulo}>Intentos</dt><dd className={dato}><Intentos n={fila.intentos} /></dd></div>
        <div><dt className={rotulo}>Motivo del descarte</dt><dd className={dato}>{etiquetaMotivoDescarte(fila.motivo_descarte)}</dd></div>
        <div><dt className={rotulo}>Etapa máxima</dt><dd className={dato}><EtapaMaximaChip etapa={fila.etapa_maxima} /></dd></div>
        <div><dt className={rotulo}>Descartado</dt><dd className={dato}>{etiquetaDiasDescarte(fila.dias_desde_descarte)}</dd></div>
        <div>
          <dt className={rotulo}>Último resultado</dt>
          <dd className={dato}>
            <span className="block">{etiquetaUltimoResultado(fila.ultimo_resultado)}</span>
            {fila.ultimo_intento_en && <span className="block text-[13px] text-[var(--muted-foreground-strong)]">{etiquetaMomento(fila.ultimo_intento_en, ahora)}</span>}
          </dd>
        </div>
      </dl>
      <div className={cn('mt-4 grid gap-2 [&>*]:w-full', llamable ? 'grid-cols-2' : 'grid-cols-1')}>
        {llamable && <AccionLlamar fila={fila} puedeMarcar={puedeMarcar} />}
        <Button type="button" variant="outline" className="h-10 pointer-coarse:h-11" onClick={onAbrir} data-foco-clave={`base-ficha-${fila.lead_id}`} aria-label={`Ver ficha de ${fila.nombre_completo}`}>
          Ver ficha
        </Button>
      </div>
    </div>
  )
}

/** Botón grande de la tarjeta del celular. */
function AccionLlamar({ fila, puedeMarcar }: { fila: FilaBaseGestion; puedeMarcar: boolean }) {
  // Fuente única (lib/telefono): un número que no sirve no se ofrece, ni como enlace ni para copiar.
  const tel = enlaceTel(fila.telefono)
  if (!tel || !fila.telefono) return <span className="text-sm text-[var(--muted-foreground-strong)]">Sin teléfono</span>
  if (puedeMarcar) {
    return (
      <a href={tel} aria-label={`Llamar a ${fila.nombre_completo}`} className={BOTON_LLAMAR}>
        <Phone className="size-4" aria-hidden />
        Llamar
      </a>
    )
  }
  const legible = telefonoLegible(fila.telefono)
  return (
    <button type="button" onClick={() => copiarNumero(tel, legible)} aria-label={`Llamar a ${fila.nombre_completo}: copia su número`} className={BOTON_LLAMAR}>
      <Phone className="size-4" aria-hidden />
      Llamar
    </button>
  )
}
