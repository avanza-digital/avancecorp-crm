// La base del analista (F1, 02/10/2026): sus leads descartados para volver a intentarlo. El SERVIDOR decide qué
// entra y en qué orden (rellamada de hoy → etapa máxima → menos días desde el descarte) y aplica las reglas; la
// pantalla solo presenta.
// Forma (Miguel, 02/10/2026): las cifras de arriba son PEQUEÑAS (el analista trabaja la lista, no mira cifras) y la
// lista de escritorio es una HOJA DE CÁLCULO: cuadrícula, un dato por celda, número de fila, encabezado y primeras
// columnas fijos al desplazar, y la fila «hoy» con formato condicional. El celular pinta tarjetas (useEsMovil monta
// solo una de las dos). «Llamar» depende del APARATO, como en Gestión Diaria: el celular abre el marcador (`tel:`)
// y la laptop copia el número; en la hoja, el propio teléfono es el botón. Registrar el intento, reactivar y la
// ficha con el historial llegan en F2.
// El MES del lead (Miguel, 02/10/2026: «mis leads de enero, de marzo, de agosto»): columna «Mes» tras el lead y un
// selector pequeño con el conteo de cada mes; el número de fila y las pastillas cuentan lo filtrado. Sin el mes del
// servidor (antes de la migración B5) no hay ni columna ni selector: nada de una columna llena de rayas.
// Organizar el trabajo (F3, 03/10/2026): arriba el bloque «Llamar hoy» (rellamadas de hoy o vencidas) y después «El
// resto», cada uno con su título y conteo; sin rellamadas de hoy no se pinta ningún bloque (la hoja queda como en F1:
// el estado de producción de hoy, sin intentos, no gasta una fila en decir «nada»). Filtros en el navegador por motivo,
// etapa máxima y último resultado, en la MISMA fila que el Mes; cada opción dice cuántos leads deja ver. El orden lo
// trae el servidor y no se toca: filtrar solo quita filas.
import { useId, useMemo, useRef, useState, type JSX, type ReactNode, type Ref } from 'react'
import { ArchiveRestore, FunnelX, Phone, RotateCcw, X } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useBaseGestion } from '@/data/crm-queries'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { useEsMovil, usePuedeMarcar } from '@/lib/media'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { enlaceTel } from '@/lib/telefono'
import { TelefonoLlamable } from '@/components/base-gestion/llamar-base'
import { copiarNumero } from '@/components/base-gestion/copiar-numero'
import { EtapaMaximaChip, Intentos, MesDelLead, ProximaLlamada } from '@/components/base-gestion/piezas-base'
import { FichaBase } from '@/components/base-gestion/ficha-base'
import {
  DIAS_DESCANSO_BASE,
  DIAS_MAX_RELLAMADA,
  FILTRO_TODOS,
  MAX_INTENTOS_BASE,
  SIN_FILTROS,
  depurarFiltros,
  etiquetaDiasDescarte,
  etiquetaMesLead,
  etiquetaMomento,
  etiquetaMotivoDescarte,
  etiquetaOrigen,
  etiquetaUltimoResultado,
  filasDemoBaseGestion,
  filtrarBase,
  hayFiltros,
  mesesDeLaBase,
  opcionesFiltro,
  separarLlamarHoy,
  tieneRellamadaAgendada,
  type DimensionFiltro,
  type FacetaFiltro,
  type FilaBaseGestion,
  type FiltrosBase,
  type OpcionesFiltro,
} from '@/lib/base-gestion'

const BOTON_LLAMAR = cn(
  'inline-flex h-10 items-center justify-center gap-2 whitespace-nowrap rounded-lg bg-accent px-4 text-sm font-semibold text-accent-foreground transition-colors hover:bg-[var(--accent-press)] pointer-coarse:h-11',
  FOCO,
)

// ── La hoja: celdas de cuadrícula, una línea por celda ──────────────────────────────────────────────────────
const ANCHO_NUMERO = 'w-12 min-w-12'
const ANCHO_LEAD = 'w-64 min-w-64'
const CELDA = 'whitespace-nowrap border-b border-r border-border px-3 py-2 text-left align-middle text-sm text-foreground'
const ENCABEZADO = 'sticky top-0 z-10 whitespace-nowrap border-b border-r border-[var(--border-strong)] bg-muted px-3 py-2 text-left text-[13px] font-semibold text-[var(--muted-foreground-strong)]'
// Las dos primeras columnas quedan fijas al desplazar en horizontal (como «inmovilizar paneles»): necesitan fondo propio.
const FIJA_NUMERO = 'sticky left-0'
const FIJA_LEAD = 'sticky left-12'
/** Columnas de la hoja sin la del Mes (la banda de cada bloque las abarca todas). */
const COLUMNAS_SIN_MES = 12

// ── Los bloques (F3) ─────────────────────────────────────────────────────────────────────────────────────────
const BLOQUE_HOY = { titulo: 'Llamar hoy', detalle: 'Rellamadas de hoy y las que se pasaron' }
const BLOQUE_RESTO = { titulo: 'El resto', detalle: 'Primero los que llegaron más lejos en el pipeline' }

export function BaseGestionAnalista(): JSX.Element {
  const { yo } = useAuth()
  const { leads } = useCRMData()
  const esMovil = useEsMovil()
  const puedeMarcar = usePuedeMarcar()
  // Demo sin red (fail-closed): el espejo sale del store; la sesión real pregunta al servidor.
  const real = yo?.demo !== true
  const consulta = useBaseGestion(real && yo !== null)
  const filas = useMemo(
    () => (real ? consulta.data ?? [] : filasDemoBaseGestion(leads, yo?.id ?? '')),
    [real, consulta.data, leads, yo?.id],
  )
  const meses = useMemo(() => mesesDeLaBase(filas), [filas])
  const [filtrosElegidos, setFiltros] = useState<FiltrosBase>(SIN_FILTROS)
  // F2: la ficha se abre por lead_id y lee la fila VIGENTE (un refresco actualiza intentos y próxima llamada).
  const [fichaId, setFichaId] = useState<string | null>(null)
  // Si el lead sale de la lista con la ficha abierta (reactivado, descansa, «no contactar»), el foco no cae en <body>:
  // va a su vecino o, si no hay, a la hoja (revisor-a11y, WCAG 2.4.3).
  const vecino = useRef<string | null>(null)
  const regionHoja = useRef<HTMLDivElement>(null)
  const listaTarjetas = useRef<HTMLDivElement>(null)
  const resumen = useRef<HTMLElement>(null)
  const tituloHoy = useRef<HTMLHeadingElement>(null)
  const primerFiltro = useRef<HTMLSelectElement>(null)
  const idHoy = useId()
  const idResto = useId()
  // Si el valor elegido de un filtro sale de la base al refrescar (el último lead de ese mes o motivo se fue), el filtro
  // vuelve a «Todos» y se OLVIDA: si un refresco posterior lo trae de vuelta, la hoja no se filtra sola.
  const filtros = depurarFiltros(filas, filtrosElegidos)
  if (filtros !== filtrosElegidos) setFiltros(filtros)

  if (!yo) return <PanelVacio icono={ArchiveRestore} titulo="Sin sesión" detalle="Vuelve a entrar para ver tu base para gestión." />
  if (real && consulta.isPending) return <PanelCargando filas={6} />
  // Sin datos que mostrar, el error ocupa el panel. Si ya había datos (el refresco al volver de una llamada
  // falló), se conservan y se avisa en línea: desmontar la lista tiraría el foco y la posición del analista.
  if (real && consulta.isError && consulta.data === undefined) {
    return <PanelError mensaje="No se pudo cargar tu base para gestión." onReintentar={() => void consulta.refetch()} reintentando={consulta.isFetching} />
  }
  const recargaFallida = real && consulta.isError

  const conMes = meses.length > 0
  const opciones = opcionesFiltro(filas, filtros)
  const visibles = filtrarBase(filas, filtros)
  const { hoy, resto } = separarLlamarHoy(visibles)
  // El orden de la pantalla: el bloque «Llamar hoy» y después el resto (el servidor ya los manda así).
  const orden = [...hoy, ...resto]
  const conBloques = hoy.length > 0
  const filtrando = hayFiltros(filtros)
  const soloMes = filtrando && hayFiltros({ ...filtros, mes: FILTRO_TODOS }) === false
  const agendadas = visibles.filter(tieneRellamadaAgendada).length
  const columnas = COLUMNAS_SIN_MES + (conMes ? 1 : 0)
  const ahora = Date.now()

  const abrirFicha = (leadId: string) => {
    const i = orden.findIndex((f) => f.lead_id === leadId)
    vecino.current = (orden[i + 1] ?? orden[i - 1])?.lead_id ?? null
    setFichaId(leadId)
  }
  const focoRespaldo = (): HTMLElement | null =>
    (vecino.current ? document.querySelector<HTMLElement>(`[data-foco-clave="base-ficha-${vecino.current}"]`) : null)
    ?? (esMovil ? listaTarjetas.current : regionHoja.current)
    // Si era el último, la hoja ya no existe: el resumen (siempre montado) dice cómo quedó la base.
    ?? resumen.current
  const cambiarFiltro = (dimension: DimensionFiltro, valor: string) => setFiltros((f) => ({ ...f, [dimension]: valor }))
  // El botón desaparece al quitar los filtros: el foco va al primer filtro (no cae en <body>).
  const quitarFiltros = () => { setFiltros(SIN_FILTROS); primerFiltro.current?.focus() }
  const alternarAgendadas = () => {
    setFiltros((f) => ({ ...f, agendadas: !f.agendadas }))
    // Al apagarlo, si con el resto de filtros no queda ninguna agendada, la pastilla deja de ser botón (en 0 no se
    // abre nada): el foco va al resumen que la contiene, no cae en <body>.
    if (filtros.agendadas && filtrarBase(filas, { ...filtros, agendadas: false }).filter(tieneRellamadaAgendada).length === 0) resumen.current?.focus()
  }
  const etiquetaTotal = !filtrando ? 'En tu base' : soloMes ? `De ${etiquetaMesLead(filtros.mes)}` : 'Coinciden'
  const filaHoja = (f: FilaBaseGestion, numero: number) => (
    <FilaHoja key={f.lead_id} numero={numero} fila={f} ahora={ahora} puedeMarcar={puedeMarcar} conMes={conMes} onAbrir={() => abrirFicha(f.lead_id)} />
  )
  const tarjeta = (f: FilaBaseGestion) => (
    <TarjetaBase key={f.lead_id} fila={f} ahora={ahora} puedeMarcar={puedeMarcar} conMes={conMes} onAbrir={() => abrirFicha(f.lead_id)} />
  )

  return (
    <div className="mx-auto w-full max-w-[1640px] space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
        <section ref={resumen} tabIndex={-1} aria-label="Resumen de tu base" className={cn('flex flex-wrap items-center gap-2 rounded-lg', FOCO)}>
          <Pastilla etiqueta={etiquetaTotal} valor={visibles.length} />
          {/* Todo número se abre: «para llamar hoy» lleva a su bloque y «agendadas» filtra la hoja a esas filas. */}
          <Pastilla
            etiqueta="Para llamar hoy"
            valor={hoy.length}
            urgente={hoy.length > 0}
            pista="ver el bloque"
            onAbrir={hoy.length > 0 ? () => tituloHoy.current?.focus() : undefined}
          />
          <Pastilla
            etiqueta="Rellamadas agendadas"
            valor={agendadas}
            presionada={filtros.agendadas}
            pista="ver solo esas"
            onAbrir={agendadas > 0 || filtros.agendadas ? alternarAgendadas : undefined}
          />
        </section>
        {filas.length > 0 && (
          <BarraFiltros
            conMes={conMes}
            opciones={opciones}
            filtros={filtros}
            onCambiar={cambiarFiltro}
            onQuitar={quitarFiltros}
            mostrados={visibles.length}
            total={filas.length}
            primerFiltro={primerFiltro}
          />
        )}
      </div>

      {recargaFallida && (
        <div className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-card px-4 py-2.5">
          <p role="status" className="text-sm text-[var(--muted-foreground-strong)]">No pudimos actualizar tu base. Se muestran los últimos datos.</p>
          <Button
            variant="outline"
            size="sm"
            aria-disabled={consulta.isFetching || undefined}
            onClick={() => { if (!consulta.isFetching) void consulta.refetch() }}
          >
            <RotateCcw aria-hidden /> Reintentar
          </Button>
        </div>
      )}

      {filas.length === 0 ? (
        <div className="rounded-lg border border-border bg-card">
          <PanelVacio
            icono={ArchiveRestore}
            titulo="No tienes leads descartados por gestionar"
            detalle={`Cuando descartes un lead, aparecerá aquí para que vuelvas a intentarlo. Los que están en descanso vuelven solos al terminar sus ${DIAS_DESCANSO_BASE} días.`}
          />
        </div>
      ) : visibles.length === 0 ? (
        <div className="rounded-lg border border-border bg-card">
          <PanelVacio icono={FunnelX} titulo="Ningún lead coincide" detalle="Ningún lead de tu base cumple todos los filtros elegidos.">
            <Button type="button" variant="outline" className="mt-1 h-10 pointer-coarse:h-11" onClick={quitarFiltros}>
              <X aria-hidden /> Quitar filtros
            </Button>
          </PanelVacio>
        </div>
      ) : esMovil ? (
        conBloques ? (
          <div ref={listaTarjetas} tabIndex={-1} role="region" aria-label="Tu base para gestión" className={cn('space-y-5 rounded-lg', FOCO)}>
            <BloqueTarjetas id={idHoy} {...BLOQUE_HOY} n={hoy.length} urgente tituloRef={tituloHoy}>{hoy.map(tarjeta)}</BloqueTarjetas>
            {resto.length > 0 && <BloqueTarjetas id={idResto} {...BLOQUE_RESTO} n={resto.length}>{resto.map(tarjeta)}</BloqueTarjetas>}
          </div>
        ) : (
          // Rol explícito: con el list-style:none del preflight, Safari + VoiceOver deja de anunciar un <ul> como lista.
          <div ref={listaTarjetas} tabIndex={-1} role="list" aria-label="Tu base para gestión" className={cn('space-y-3 rounded-lg', FOCO)}>
            {orden.map(tarjeta)}
          </div>
        )
      ) : (
        // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La hoja se desplaza con el teclado en los dos ejes.
        <div ref={regionHoja} className={cn('ac-scroll max-h-[calc(100dvh-14rem)] scroll-pl-[19rem] scroll-pt-11 overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)} tabIndex={0} role="region" aria-label="Tu base para gestión">
          <table className="min-w-full border-separate border-spacing-0">
            <caption className="sr-only">
              Tus leads descartados{filtros.mes === FILTRO_TODOS ? '' : ` de ${etiquetaMesLead(filtros.mes)}`}{filtrando && !soloMes ? ', con los filtros elegidos' : ''}.
              {conBloques
                ? ' Primero el bloque «Llamar hoy», con las rellamadas de hoy y las vencidas; después el resto: los que llegaron más lejos en el pipeline y los descartados más recientes.'
                : ' Primero los que llegaron más lejos en el pipeline y los descartados más recientes.'}
            </caption>
            <thead>
              <tr>
                <th scope="col" className={cn(ENCABEZADO, FIJA_NUMERO, ANCHO_NUMERO, 'z-20 text-center')}>#</th>
                <th scope="col" className={cn(ENCABEZADO, FIJA_LEAD, ANCHO_LEAD, 'z-20')}>Lead</th>
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
            {/* Una sola hoja (las columnas no se desalinean) con un grupo de filas por bloque; el número de fila sigue
                de un bloque al otro: el último número es el total que dice la pastilla. */}
            {conBloques && (
              <tbody aria-labelledby={idHoy}>
                <BandaBloque id={idHoy} {...BLOQUE_HOY} n={hoy.length} columnas={columnas} urgente tituloRef={tituloHoy} />
                {hoy.map((f, i) => filaHoja(f, i + 1))}
              </tbody>
            )}
            {resto.length > 0 && (
              <tbody aria-labelledby={conBloques ? idResto : undefined}>
                {conBloques && <BandaBloque id={idResto} {...BLOQUE_RESTO} n={resto.length} columnas={columnas} />}
                {resto.map((f, i) => filaHoja(f, hoy.length + i + 1))}
              </tbody>
            )}
          </table>
        </div>
      )}

      <p className="text-sm text-[var(--muted-foreground-strong)]">
        Tras {MAX_INTENTOS_BASE} intentos sin cita ni rellamada, el lead descansa {DIAS_DESCANSO_BASE} días y vuelve solo a tu base.
        La rellamada se agenda como máximo a {DIAS_MAX_RELLAMADA} días.
      </p>

      <FichaBase
        fila={fichaId ? (filas.find((f) => f.lead_id === fichaId) ?? null) : null}
        demo={!real}
        puedeMarcar={puedeMarcar}
        onCerrar={() => setFichaId(null)}
        focoRespaldo={focoRespaldo}
      />
    </div>
  )
}

/** Cifra del resumen, pequeña a propósito: el protagonismo es de la hoja. Con `onAbrir` es un botón (todo número se
 *  abre); con `presionada`, un interruptor de filtro. */
function Pastilla({ etiqueta, valor, urgente = false, presionada, pista, onAbrir }: {
  etiqueta: string
  valor: number
  urgente?: boolean
  presionada?: boolean
  /** Qué hace al pulsarla, solo para el lector («ver el bloque»): a la vista ya lo dice el puntero. */
  pista?: string
  onAbrir?: (() => void) | undefined
}) {
  const clase = cn(
    'inline-flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm',
    urgente ? 'border-destructive/40 bg-destructive/[0.06] text-[var(--destructive-text)]'
      : presionada ? 'border-accent bg-accent/10 text-foreground'
        : 'border-border bg-card text-[var(--muted-foreground-strong)]',
  )
  const contenido = (
    <>
      {/* El «:» oculto separa la etiqueta del número para el lector («De Agosto 2026: 2», no «20262»). */}
      <span>{etiqueta}<span className="sr-only">:</span></span>
      <strong className={cn('font-bold tabular-nums', urgente ? 'text-[var(--destructive-text)]' : 'text-foreground')}>{valor}</strong>
    </>
  )
  if (!onAbrir) return <p className={clase}>{contenido}</p>
  return (
    <button
      type="button"
      onClick={onAbrir}
      aria-pressed={presionada}
      className={cn(clase, 'cursor-pointer transition-colors pointer-coarse:min-h-11', urgente ? 'hover:bg-destructive/10' : 'hover:border-[var(--border-strong)]', FOCO)}
    >
      {contenido}
      {pista && <span className="sr-only">, {pista}</span>}
      {presionada && <X className="size-3.5 text-[var(--muted-foreground-strong)]" aria-hidden />}
    </button>
  )
}

/** Los filtros en UNA fila (Miguel: horizontal antes que vertical), junto al Mes. En el celular, de dos en dos. */
function BarraFiltros({ conMes, opciones, filtros, onCambiar, onQuitar, mostrados, total, primerFiltro }: {
  conMes: boolean
  opciones: OpcionesFiltro
  filtros: FiltrosBase
  onCambiar: (dimension: DimensionFiltro, valor: string) => void
  onQuitar: () => void
  mostrados: number
  total: number
  primerFiltro: Ref<HTMLSelectElement>
}) {
  const filtrando = hayFiltros(filtros)
  const filtro = (dimension: DimensionFiltro, etiqueta: string, primero: boolean) => (
    <FiltroSelect
      etiqueta={etiqueta}
      faceta={opciones[dimension]}
      valor={filtros[dimension]}
      onCambiar={(v) => onCambiar(dimension, v)}
      selectRef={primero ? primerFiltro : undefined}
    />
  )
  return (
    <div role="group" aria-label="Filtrar tu base" className="grid w-full grid-cols-2 items-end gap-x-3 gap-y-2 sm:flex sm:w-auto sm:flex-wrap">
      {conMes && filtro('mes', 'Mes', true)}
      {filtro('motivo', 'Motivo del descarte', !conMes)}
      {filtro('etapa', 'Etapa máxima', false)}
      {filtro('resultado', 'Último resultado', false)}
      <div className="col-span-2 flex min-h-9 items-center gap-3">
        {/* Siempre montado: el lector anuncia el cambio del conteo al filtrar (una región que nace con texto no se lee). */}
        <p role="status" className="text-sm font-semibold tabular-nums text-[var(--muted-foreground-strong)]">
          {filtrando ? `${mostrados} de ${total} ${total === 1 ? 'lead' : 'leads'}` : ''}
        </p>
        {filtrando && (
          <Button type="button" variant="outline" className="h-9 pointer-coarse:h-11" onClick={onQuitar}>
            <X aria-hidden /> Quitar filtros
          </Button>
        )}
      </div>
    </div>
  )
}

function FiltroSelect({ etiqueta, faceta, valor, onCambiar, selectRef }: {
  etiqueta: string
  faceta: FacetaFiltro
  valor: string
  onCambiar: (valor: string) => void
  selectRef?: Ref<HTMLSelectElement> | undefined
}) {
  const id = useId()
  const activo = valor !== FILTRO_TODOS
  return (
    <div className="flex min-w-0 flex-col gap-1 sm:min-w-40">
      <label htmlFor={id} className="text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]">{etiqueta}</label>
      <Select
        ref={selectRef}
        id={id}
        value={valor}
        onChange={(e) => onCambiar(e.target.value)}
        // El outline del foco lo devuelve la regla global de index.css (`[class*='focus-visible:outline-none']`); el anillo
        // con desplazamiento lo refuerza. El activo NO usa anillos: se marca con borde y fondo.
        className={cn('pointer-coarse:h-11 pointer-coarse:text-base focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2', activo && 'border-accent bg-accent/[0.06] font-semibold text-foreground')}
      >
        <option value={FILTRO_TODOS}>Todos ({faceta.total})</option>
        {faceta.opciones.map((o) => <option key={o.clave} value={o.clave}>{o.etiqueta} ({o.leads})</option>)}
      </Select>
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
  tituloRef?: Ref<HTMLHeadingElement>
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

function TituloBloque({ id, titulo, n, urgente, tituloRef }: { id: string; titulo: string; n: number; urgente: boolean; tituloRef?: Ref<HTMLHeadingElement> | undefined }) {
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
  tituloRef?: Ref<HTMLHeadingElement>
  children: ReactNode
}) {
  return (
    // Un <div>, no otra región: ya está dentro de la región «Tu base para gestión» (el nombre se anunciaría dos veces).
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

function FilaHoja({ numero, fila, ahora, puedeMarcar, conMes, onAbrir }: { numero: number; fila: FilaBaseGestion; ahora: number; puedeMarcar: boolean; conMes: boolean; onAbrir: () => void }) {
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
      {conMes && <td className={CELDA}><MesDelLead fila={fila} /></td>}
      <td className={CELDA}><TelefonoLlamable fila={fila} puedeMarcar={puedeMarcar} /></td>
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

function TarjetaBase({ fila, ahora, puedeMarcar, conMes, onAbrir }: { fila: FilaBaseGestion; ahora: number; puedeMarcar: boolean; conMes: boolean; onAbrir: () => void }) {
  const dato = 'text-sm text-foreground'
  const rotulo = 'text-[13px] font-semibold text-[var(--muted-foreground-strong)]'
  return (
    <div role="listitem" className={cn('rounded-xl border bg-card p-4', fila.rellamada_hoy ? 'border-destructive/40 shadow-[inset_4px_0_0_var(--destructive)]' : 'border-border')}>
      <p className="text-base font-semibold text-foreground">{fila.nombre_completo}</p>
      <p className="text-sm text-[var(--muted-foreground-strong)]">{contactoDe(fila)}</p>
      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2">
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
      <div className="mt-4 grid grid-cols-2 gap-2 [&>*]:w-full">
        <AccionLlamar fila={fila} puedeMarcar={puedeMarcar} />
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
