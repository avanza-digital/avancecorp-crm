// La base del analista (F1, 02/10/2026): sus leads descartados para volver a intentarlo, en una lista plana
// y legible (nombre 16 px, detalle 14 px, filas altas). El SERVIDOR decide qué entra y en qué orden
// (rellamada de hoy → etapa máxima → menos días desde el descarte) y aplica las reglas; la pantalla solo
// presenta. Escritorio pinta una tabla; el celular, tarjetas con «Llamar» a la vista (useEsMovil monta solo
// una de las dos). «Llamar» depende del APARATO, como en Gestión Diaria: el celular abre el marcador
// (`tel:`) y la laptop copia el número. Registrar el intento, reactivar y la ficha con el historial llegan en F2.
import { useMemo, type JSX } from 'react'
import { toast } from 'sonner'
import { ArchiveRestore, Phone, RotateCcw } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useBaseGestion } from '@/data/crm-queries'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { useEsMovil, usePuedeMarcar } from '@/lib/media'
import { ETAPA_INFO } from '@/lib/tipos'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { enlaceTel } from '@/lib/telefono'
import {
  DIAS_DESCANSO_BASE,
  DIAS_MAX_RELLAMADA,
  MAX_INTENTOS_BASE,
  estadoRellamada,
  etiquetaDiasDescarte,
  etiquetaEtapaMaxima,
  etiquetaIntentos,
  etiquetaMomento,
  etiquetaMotivoDescarte,
  etiquetaOrigen,
  etiquetaRellamada,
  etiquetaUltimoResultado,
  filasDemoBaseGestion,
  type EtapaMaxima,
  type FilaBaseGestion,
} from '@/lib/base-gestion'

const COLOR_SIN_HISTORIAL = '#94a3b8'
const colorEtapa = (etapa: EtapaMaxima): string => (etapa === 'sin_datos' ? COLOR_SIN_HISTORIAL : ETAPA_INFO[etapa].color)
const BOTON_LLAMAR = cn(
  'inline-flex h-10 items-center justify-center gap-2 whitespace-nowrap rounded-lg bg-accent px-4 text-sm font-semibold text-accent-foreground transition-colors hover:bg-[var(--accent-press)] pointer-coarse:h-11',
  FOCO,
)

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

  if (!yo) return <PanelVacio icono={ArchiveRestore} titulo="Sin sesión" detalle="Vuelve a entrar para ver tu base para gestión." />
  if (real && consulta.isPending) return <PanelCargando filas={6} />
  // Sin datos que mostrar, el error ocupa el panel. Si ya había datos (el refresco al volver de una llamada
  // falló), se conservan y se avisa en línea: desmontar la lista tiraría el foco y la posición del analista.
  if (real && consulta.isError && consulta.data === undefined) {
    return <PanelError mensaje="No se pudo cargar tu base para gestión." onReintentar={() => void consulta.refetch()} reintentando={consulta.isFetching} />
  }
  const recargaFallida = real && consulta.isError

  const ahora = Date.now()
  const llamarHoy = filas.filter((f) => f.rellamada_hoy).length
  const agendadas = filas.filter((f) => f.proxima_llamada_en !== null && !f.rellamada_hoy).length

  return (
    <div className="mx-auto w-full max-w-[1640px] space-y-5">
      <section aria-label="Resumen de tu base">
        {esMovil ? (
          // En el celular, una franja de texto que se acomoda a cualquier ancho (a 320 px tres tarjetas no caben).
          <p className="flex flex-wrap items-baseline gap-x-4 gap-y-1 rounded-xl border border-border bg-card px-4 py-3 text-sm text-[var(--muted-foreground-strong)]">
            <span><strong className="text-xl font-extrabold tabular-nums text-primary">{filas.length}</strong> en tu base</span>
            <span><strong className={cn('text-xl font-extrabold tabular-nums', llamarHoy > 0 ? 'text-[var(--destructive-text)]' : 'text-primary')}>{llamarHoy}</strong> para llamar hoy</span>
            <span><strong className="text-xl font-extrabold tabular-nums text-primary">{agendadas}</strong> rellamadas agendadas</span>
          </p>
        ) : (
          <div className="grid grid-cols-3 gap-3">
            <Cifra titulo="En tu base" valor={filas.length} detalle="Descartados que puedes volver a intentar" />
            <Cifra titulo="Para llamar hoy" valor={llamarHoy} detalle="Rellamadas de hoy o ya vencidas" urgente={llamarHoy > 0} />
            <Cifra titulo="Rellamadas agendadas" valor={agendadas} detalle="Para los próximos días" />
          </div>
        )}
      </section>

      {recargaFallida && (
        <div className="flex flex-wrap items-center gap-3 rounded-xl border border-border bg-card px-4 py-3">
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
        <div className="rounded-xl border border-border bg-card">
          <PanelVacio
            icono={ArchiveRestore}
            titulo="No tienes leads descartados por gestionar"
            detalle={`Cuando descartes un lead, aparecerá aquí para que vuelvas a intentarlo. Los que están en descanso vuelven solos al terminar sus ${DIAS_DESCANSO_BASE} días.`}
          />
        </div>
      ) : esMovil ? (
        // Rol explícito: con el list-style:none del preflight, Safari + VoiceOver deja de anunciar un <ul> como lista.
        <div role="list" aria-label="Tu base para gestión" className="space-y-3">
          {filas.map((fila) => <TarjetaBase key={fila.lead_id} fila={fila} ahora={ahora} puedeMarcar={puedeMarcar} />)}
        </div>
      ) : (
        // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar la tabla con el teclado.
        <div className={cn('ac-scroll overflow-x-auto rounded-xl border border-border bg-card', FOCO)} tabIndex={0} role="region" aria-label="Tu base para gestión">
          <table className="w-full min-w-[1080px] border-separate border-spacing-0 text-sm">
            <caption className="sr-only">
              Tus leads descartados. Primero los que toca llamar hoy; después los que llegaron más lejos en el pipeline y los descartados más recientes.
            </caption>
            <thead className="bg-muted/70 text-[13px] text-[var(--muted-foreground-strong)]">
              <tr>
                <th scope="col" className="px-4 py-2.5 text-left font-semibold">Lead</th>
                <th scope="col" className="px-4 py-2.5 text-left font-semibold">Motivo del descarte</th>
                <th scope="col" className="px-4 py-2.5 text-left font-semibold">Etapa máxima</th>
                <th scope="col" className="px-4 py-2.5 text-left font-semibold">Descartado</th>
                <th scope="col" className="px-4 py-2.5 text-left font-semibold">Intentos</th>
                <th scope="col" className="px-4 py-2.5 text-left font-semibold">Último resultado</th>
                <th scope="col" className="px-4 py-2.5 text-left font-semibold">Próxima llamada</th>
                <th scope="col" className="px-4 py-2.5 text-right font-semibold"><span className="sr-only">Acciones</span></th>
              </tr>
            </thead>
            <tbody>
              {filas.map((fila) => <FilaBase key={fila.lead_id} fila={fila} ahora={ahora} puedeMarcar={puedeMarcar} />)}
            </tbody>
          </table>
        </div>
      )}

      <p className="text-sm text-[var(--muted-foreground-strong)]">
        Tras {MAX_INTENTOS_BASE} intentos sin cita ni rellamada, el lead descansa {DIAS_DESCANSO_BASE} días y vuelve solo a tu base.
        La rellamada se agenda como máximo a {DIAS_MAX_RELLAMADA} días.
      </p>
    </div>
  )
}

function Cifra({ titulo, valor, detalle, urgente = false }: { titulo: string; valor: number; detalle: string; urgente?: boolean }) {
  return (
    <div className={cn('rounded-xl border bg-card px-5 py-4', urgente ? 'border-destructive/40' : 'border-border')}>
      <p className="text-sm font-semibold text-[var(--muted-foreground-strong)]">{titulo}</p>
      <p className={cn('text-3xl font-extrabold tabular-nums', urgente ? 'text-[var(--destructive-text)]' : 'text-primary')}>{valor}</p>
      <p className="text-sm text-[var(--muted-foreground-strong)]">{detalle}</p>
    </div>
  )
}

/** Teléfono · distrito · origen: lo que el analista necesita a la vista para ubicar al lead. */
function contactoDe(fila: FilaBaseGestion): string {
  return [fila.telefono ? telefonoLegible(fila.telefono) : null, fila.distrito, etiquetaOrigen(fila.origen)]
    .filter((parte): parte is string => !!parte)
    .join(' · ')
}

function FilaBase({ fila, ahora, puedeMarcar }: { fila: FilaBaseGestion; ahora: number; puedeMarcar: boolean }) {
  const celda = 'border-t border-border px-4 py-3 align-middle text-foreground'
  return (
    <tr className={cn(fila.rellamada_hoy && 'bg-destructive/[0.04]')}>
      <th scope="row" className={cn(celda, 'text-left font-normal', fila.rellamada_hoy && 'shadow-[inset_4px_0_0_var(--destructive)]')}>
        <span className="block text-base font-semibold">
          {fila.nombre_completo}
          {fila.rellamada_hoy && <span className="sr-only"> — toca llamar hoy</span>}
        </span>
        <span className="block text-sm text-[var(--muted-foreground-strong)]">{contactoDe(fila)}</span>
      </th>
      <td className={celda}>{etiquetaMotivoDescarte(fila.motivo_descarte)}</td>
      <td className={celda}><EtapaMaximaChip etapa={fila.etapa_maxima} /></td>
      <td className={cn(celda, 'tabular-nums')}>{etiquetaDiasDescarte(fila.dias_desde_descarte)}</td>
      <td className={celda}><Intentos n={fila.intentos} /></td>
      <td className={celda}><UltimoResultado fila={fila} ahora={ahora} /></td>
      <td className={celda}><ProximaLlamada iso={fila.proxima_llamada_en} ahora={ahora} /></td>
      <td className={cn(celda, 'text-right')}><AccionLlamar fila={fila} puedeMarcar={puedeMarcar} /></td>
    </tr>
  )
}

function TarjetaBase({ fila, ahora, puedeMarcar }: { fila: FilaBaseGestion; ahora: number; puedeMarcar: boolean }) {
  const dato = 'text-sm text-foreground'
  const rotulo = 'text-[13px] font-semibold text-[var(--muted-foreground-strong)]'
  return (
    <div role="listitem" className={cn('rounded-xl border bg-card p-4', fila.rellamada_hoy ? 'border-destructive/40 shadow-[inset_4px_0_0_var(--destructive)]' : 'border-border')}>
      <p className="text-base font-semibold text-foreground">{fila.nombre_completo}</p>
      <p className="text-sm text-[var(--muted-foreground-strong)]">{contactoDe(fila)}</p>
      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2">
        <div><dt className={rotulo}>Próxima llamada</dt><dd className={dato}><ProximaLlamada iso={fila.proxima_llamada_en} ahora={ahora} /></dd></div>
        <div><dt className={rotulo}>Intentos</dt><dd className={dato}><Intentos n={fila.intentos} /></dd></div>
        <div><dt className={rotulo}>Motivo del descarte</dt><dd className={dato}>{etiquetaMotivoDescarte(fila.motivo_descarte)}</dd></div>
        <div><dt className={rotulo}>Etapa máxima</dt><dd className={dato}><EtapaMaximaChip etapa={fila.etapa_maxima} /></dd></div>
        <div><dt className={rotulo}>Descartado</dt><dd className={dato}>{etiquetaDiasDescarte(fila.dias_desde_descarte)}</dd></div>
        <div><dt className={rotulo}>Último resultado</dt><dd className={dato}><UltimoResultado fila={fila} ahora={ahora} /></dd></div>
      </dl>
      <div className="mt-4 [&>*]:w-full"><AccionLlamar fila={fila} puedeMarcar={puedeMarcar} /></div>
    </div>
  )
}

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
  // En la laptop un `tel:` no marca nada: se copia el número para marcarlo desde el celular.
  const marcable = tel.slice('tel:'.length)
  const legible = telefonoLegible(fila.telefono)
  const copiar = () => {
    const copia = navigator.clipboard?.writeText(marcable) ?? Promise.reject(new Error('sin portapapeles'))
    void copia.then(
      () => { toast.success(`Número copiado: ${legible} — márcalo desde tu celular`) },
      () => { toast.info(`Marca ${legible} desde tu celular`) },
    )
  }
  return (
    <button type="button" onClick={copiar} aria-label={`Llamar a ${fila.nombre_completo}: copia su número`} className={BOTON_LLAMAR}>
      <Phone className="size-4" aria-hidden />
      Llamar
    </button>
  )
}

function EtapaMaximaChip({ etapa }: { etapa: EtapaMaxima }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span aria-hidden className="size-2.5 shrink-0 rounded-full" style={{ background: colorEtapa(etapa) }} />
      {etiquetaEtapaMaxima(etapa)}
    </span>
  )
}

function UltimoResultado({ fila, ahora }: { fila: FilaBaseGestion; ahora: number }) {
  return (
    <>
      <span className="block">{etiquetaUltimoResultado(fila.ultimo_resultado)}</span>
      {fila.ultimo_intento_en && <span className="block text-[13px] text-[var(--muted-foreground-strong)]">{etiquetaMomento(fila.ultimo_intento_en, ahora)}</span>}
    </>
  )
}

function Intentos({ n }: { n: number }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span aria-hidden className="flex gap-1">
        {Array.from({ length: MAX_INTENTOS_BASE }, (_, i) => (
          <span key={i} className={cn('size-2.5 rounded-full', i < n ? 'bg-primary' : 'bg-[var(--border-strong)]')} />
        ))}
      </span>
      <span className="tabular-nums">{etiquetaIntentos(n)}</span>
    </span>
  )
}

function ProximaLlamada({ iso, ahora }: { iso: string | null; ahora: number }) {
  if (!iso) return <span className="text-[var(--muted-foreground-strong)]">Sin agendar</span>
  const estado = estadoRellamada(iso, ahora)
  const texto = etiquetaRellamada(iso, ahora)
  if (estado === 'futura') return <span className="font-semibold text-[var(--warning-text)]">{texto}</span>
  return (
    <span className="inline-flex rounded-md bg-destructive/10 px-2 py-1 font-semibold text-[var(--destructive-text)]">{texto}</span>
  )
}
