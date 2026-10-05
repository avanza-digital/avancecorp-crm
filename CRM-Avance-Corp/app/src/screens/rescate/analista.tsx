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
// Bases cargadas (F6, 04/10/2026): los contactos de una base que el supervisor le repartió entran aquí como cualquier lead
// de su base (mismas reglas). Con alguno, la hoja lleva la columna «Base» y el selector «Base: Todas · Feria 2025 (40)»
// junto al del Mes; sin ninguno (o antes de la B10, que trae `base_nombre`), nada cambia.
import { useId, useMemo, useRef, useState, type JSX } from 'react'
import { ArchiveRestore, FunnelX, RotateCcw, X } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useBaseGestion } from '@/data/crm-queries'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { useEsMovil, usePuedeMarcar } from '@/lib/media'
import { FichaBase } from '@/components/base-gestion/ficha-base'
import { HojaBase, type BloqueHoja } from '@/components/base-gestion/hoja-base'
import { BarraFiltros, Pastilla } from '@/components/base-gestion/filtros-base'
import {
  DIAS_DESCANSO_BASE,
  DIAS_MAX_RELLAMADA,
  FILTRO_TODOS,
  MAX_INTENTOS_BASE,
  SIN_FILTROS,
  conBaseCargada,
  depurarFiltros,
  etiquetaMesLead,
  filasDemoBaseGestion,
  filtrarBase,
  hayFiltros,
  mesesDeLaBase,
  opcionesFiltro,
  separarLlamarHoy,
  tieneRellamadaAgendada,
  type DimensionFiltro,
  type FiltrosBase,
} from '@/lib/base-gestion'

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
  const conBase = conBaseCargada(filas)
  const opciones = opcionesFiltro(filas, filtros)
  const visibles = filtrarBase(filas, filtros)
  const { hoy, resto } = separarLlamarHoy(visibles)
  // El orden de la pantalla: el bloque «Llamar hoy» y después el resto (el servidor ya los manda así).
  const orden = [...hoy, ...resto]
  const conBloques = hoy.length > 0
  const filtrando = hayFiltros(filtros)
  const soloMes = filtrando && hayFiltros({ ...filtros, mes: FILTRO_TODOS }) === false
  const soloBase = filtrando && filtros.base !== FILTRO_TODOS && hayFiltros({ ...filtros, base: FILTRO_TODOS }) === false
  const nombreBase = opciones.base.opciones.find((o) => o.clave === filtros.base)?.etiqueta ?? ''
  const agendadas = visibles.filter(tieneRellamadaAgendada).length
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
  const etiquetaTotal = !filtrando ? 'En tu base' : soloMes ? `De ${etiquetaMesLead(filtros.mes)}` : soloBase ? `De ${nombreBase}` : 'Coinciden'
  // Con rellamadas de hoy, dos bloques con título; sin ellas, la hoja de F1 (una sola lista, sin título).
  const bloques: BloqueHoja[] = conBloques
    ? [
        { id: idHoy, ...BLOQUE_HOY, n: hoy.length, filas: hoy, urgente: true, tituloRef: tituloHoy },
        ...(resto.length > 0 ? [{ id: idResto, ...BLOQUE_RESTO, n: resto.length, filas: resto }] : []),
      ]
    : [{ id: idResto, ...BLOQUE_RESTO, n: resto.length, filas: resto }]

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
            conBase={conBase}
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
      ) : (
        <HojaBase
          bloques={bloques}
          conBandas={conBloques}
          esMovil={esMovil}
          etiqueta="Tu base para gestión"
          caption={
            <>
              Tus leads descartados{filtros.mes === FILTRO_TODOS ? '' : ` de ${etiquetaMesLead(filtros.mes)}`}{filtrando && !soloMes ? ', con los filtros elegidos' : ''}.
              {conBloques
                ? ' Primero el bloque «Llamar hoy», con las rellamadas de hoy y las vencidas; después el resto: los que llegaron más lejos en el pipeline y los descartados más recientes.'
                : ' Primero los que llegaron más lejos en el pipeline y los descartados más recientes.'}
            </>
          }
          conMes={conMes}
          conBase={conBase}
          ahora={ahora}
          puedeMarcar={puedeMarcar}
          onAbrir={abrirFicha}
          regionRef={regionHoja}
          listaRef={listaTarjetas}
        />
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
