// La sección «En cooperativas» de Mi cartera: los cierres del ámbito en COOPAC
// Qorilazo / Prodelco, con su distintivo, sus mini-totales y una mini-ficha.
//
// Por qué es una SECCIÓN aparte y no filas de la lista de clientes: estas
// personas NO tienen perfil de portal (no hay cliente que listar) y la lista
// principal pagina por keyset (F2) — meterle un UNION de dos fuentes a su
// cursor es riesgo real sin beneficio. Los mini-totales viajan del SERVIDOR
// (`totales`), nunca se suman de las filas: la lista llega con tope 200 y
// sumar una lista truncada mentiría (en demo sí se suman: la lista local es
// completa por construcción).
//
// Regla de layout: PEN y USD jamás se suman; y este dinero NO se mezcla con
// los totales Avance — no es capital administrado por Avance.
import { useEffect, useMemo, useRef, useState } from 'react'
import { Landmark } from 'lucide-react'
import { cn } from '@/lib/utils'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { toast } from 'sonner'
import { SectionHead } from '@/components/common/section-head'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { CrmApiError } from '@/data/crm-api'
import { useAnularCierreExterno, useCierresExternos } from '@/data/crm-queries'
import {
  capitalAvance,
  INFO_COOPERATIVA,
  type CierreExterno,
  type Cooperativa,
  type EmpresaVendedor,
} from '@/lib/cierres-externos'
import { periodoLima, type CumplimientoVendedor } from '@/lib/objetivos'
import { fmtFecha, money, type Moneda } from '@/lib/format'

/** Fila unificada de los dos mundos (real = foto completa; demo = lo local). */
interface FilaCoop {
  id: string
  nombre: string
  cooperativa: Cooperativa
  monto: number
  moneda: Moneda
  telefono: string | null
  numeroTransaccion: string
  creadoEn: string
  /** Anulado por gerencia: la fila se sigue viendo, marcada, pero no suma. */
  anuladoEn: string | null
  motivoAnulacion: string | null
  /** Solo en real: la foto completa para la mini-ficha. */
  detalle: CierreExterno | null
}

function ChipCoop({ cooperativa }: { cooperativa: Cooperativa }) {
  const info = INFO_COOPERATIVA[cooperativa]
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-[10px] font-bold tracking-wide',
        info.chipClase,
      )}
    >
      {info.corto}
    </span>
  )
}

/** Distintivo del cierre anulado. Se lee igual en la lista y en la mini-ficha:
 *  el asesor tiene que poder explicarse por qué su total bajó.
 *
 *  Es TEXTO y no solo un color o un tachado, y va en `destructive-text` (rojo
 *  oscuro): a 10px es el único portador NO cromático del estado, y el rojo puro
 *  sobre este fondo se queda en 4,1:1 — por debajo del mínimo legible. */
function ChipAnulado() {
  return (
    <span className="inline-flex shrink-0 items-center rounded-full border border-destructive/40 bg-destructive/10 px-2 py-0.5 text-[10px] font-bold tracking-wide text-destructive-text">
      ANULADO
    </span>
  )
}

function MiniFicha({ fila, onClose }: { fila: FilaCoop; onClose: () => void }) {
  const info = INFO_COOPERATIVA[fila.cooperativa]
  const d = fila.detalle
  const anulado = fila.anuladoEn != null
  const filas: Array<[string, string]> = [
    ['Invirtió en', info.nombre],
    ['Monto', money(fila.monto, fila.moneda)],
    ['N.° de operación', fila.numeroTransaccion],
    ['Fecha del cierre', fmtFecha(fila.creadoEn)],
  ]
  if (d) filas.push(['Documento', `${d.documento_tipo} ${d.documento}`])
  if (fila.telefono) filas.push(['Teléfono', fila.telefono])
  if (d?.referencia_externa) filas.push(['Certificado de la coop', d.referencia_externa])
  if (d?.vence_en) filas.push(['Vence', fmtFecha(d.vence_en)])
  if (d?.vendedor_nombre) filas.push(['Cerró', d.vendedor_nombre])
  if (anulado) filas.push(['Anulado el', fmtFecha(fila.anuladoEn!)])
  return (
    <Dialog open onClose={onClose} ariaLabel={`Detalle del cierre de ${fila.nombre}`}>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          {fila.nombre} <ChipCoop cooperativa={fila.cooperativa} />
          {anulado && <ChipAnulado />}
        </DialogTitle>
      </DialogHeader>
      <DialogBody className="space-y-2">
        {anulado && (
          <p className="rounded-lg border border-destructive/40 bg-destructive/10 p-2 text-xs font-semibold leading-relaxed text-destructive-text">
            Gerencia anuló este cierre: ya no cuenta en la cuota ni en la conversión.
            {fila.motivoAnulacion ? ` Motivo: ${fila.motivoAnulacion}` : ''}
          </p>
        )}
        <dl className="space-y-1.5">
          {filas.map(([k, v]) => (
            <div key={k} className="flex items-baseline justify-between gap-3">
              <dt className="text-xs text-muted-foreground">{k}</dt>
              <dd className="text-xs font-semibold text-foreground">{v}</dd>
            </div>
          ))}
        </dl>
        {d?.nota && (
          <p className="rounded-lg bg-muted/60 p-2 text-xs leading-relaxed text-muted-foreground">
            {d.nota}
          </p>
        )}
        <p className="text-[11px] leading-relaxed text-muted-foreground">
          Este inversionista no tiene cuenta en el portal: su inversión la administra la
          cooperativa. El cierre cuenta en la cuota y la conversión del asesor.
        </p>
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" size="sm" onClick={onClose}>Cerrar</Button>
      </DialogFooter>
    </Dialog>
  )
}

/**
 * Sección «En cooperativas» — se OCULTA si el ámbito no tiene ni un cierre
 * (la mayoría de asesores nunca la verá). Si la carga real falla, avisa con su
 * Reintentar: la degradación nunca es muda.
 */
export function SeccionEnCooperativas({ demo }: { demo: boolean }) {
  // Default defensivo: los harnesses de tests de pantalla montan stubs
  // parciales del store (`as unknown as StoreDataApi`).
  const { cierresExternos: cierresDemo = [] } = useCRMData()
  const consulta = useCierresExternos(!demo, periodoLima(Date.now()))
  const [abierta, setAbierta] = useState<FilaCoop | null>(null)

  const filas = useMemo<FilaCoop[]>(() => {
    if (demo) {
      return cierresDemo.map((c) => ({
        id: c.cierreId,
        nombre: c.nombre,
        cooperativa: c.cooperativa,
        monto: c.monto,
        moneda: c.moneda,
        telefono: c.telefono,
        numeroTransaccion: c.numeroTransaccion,
        creadoEn: c.creadoEn,
        anuladoEn: c.anuladoEn,
        motivoAnulacion: c.motivoAnulacion,
        detalle: null,
      }))
    }
    return (consulta.data?.cierres ?? []).map((c) => ({
      id: c.cierre_id,
      nombre: c.nombre_completo,
      cooperativa: c.cooperativa,
      monto: c.monto,
      moneda: c.moneda,
      telefono: c.telefono,
      numeroTransaccion: c.numero_transaccion,
      creadoEn: c.creado_en,
      anuladoEn: c.anulado_en,
      motivoAnulacion: c.motivo_anulacion,
      detalle: c,
    }))
  }, [demo, cierresDemo, consulta.data])

  // Mini-totales por moneda: del SERVIDOR en real (la lista puede venir
  // truncada), de la lista local en demo (completa por construcción).
  const totalesMoneda = useMemo(() => {
    const acumulado = new Map<Moneda, { capital: number; cierres: number }>()
    const sumar = (moneda: Moneda, capital: number, cierres: number) => {
      const previo = acumulado.get(moneda) ?? { capital: 0, cierres: 0 }
      acumulado.set(moneda, {
        capital: previo.capital + capital,
        cierres: previo.cierres + cierres,
      })
    }
    if (demo) {
      // Los anulados NO suman, igual que en el servidor: `totales` los excluye.
      for (const f of filas) if (!f.anuladoEn) sumar(f.moneda, f.monto, 1)
    } else {
      for (const t of consulta.data?.totales ?? []) sumar(t.moneda, t.capital, t.cierres)
    }
    return acumulado
  }, [demo, filas, consulta.data])

  const totalCierres = demo ? filas.length : (consulta.data?.cierres_total ?? 0)

  if (!demo && consulta.isError) {
    return (
      <section aria-label="En cooperativas" className="mt-6">
        {/* role=status: el aviso aparece asíncrono tras fallar la query y sin
            región viva la degradación sí sería muda para un lector (M3). */}
        <div role="status" className="flex items-center justify-between gap-3 rounded-xl border border-warning/40 bg-warning/10 p-3">
          <p className="text-xs font-semibold text-warning-text">
            No se pudieron cargar los cierres en cooperativas.
          </p>
          <Button variant="outline" size="sm" onClick={() => void consulta.refetch()}>
            Reintentar
          </Button>
        </div>
      </section>
    )
  }

  // Sin cierres (o aún cargando): la sección no existe para este asesor.
  if (totalCierres === 0) return null

  const resumen = (['PEN', 'USD'] as const)
    .filter((m) => totalesMoneda.has(m))
    .map((m) => money(totalesMoneda.get(m)!.capital, m))
    .join(' · ')

  return (
    <section aria-label="En cooperativas" className="mt-6 space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="flex items-center gap-2 text-sm font-bold text-foreground">
          <Landmark className="size-4 text-muted-foreground" aria-hidden />
          En cooperativas
          <span className="text-xs font-semibold text-muted-foreground">
            {totalCierres} {totalCierres === 1 ? 'cierre' : 'cierres'}
          </span>
        </h3>
        {/* Dinero de las COOPS, aparte de los totales Avance a propósito: no es
            capital administrado por Avance y mezclarlo mentiría en los tiles. */}
        <p className="text-xs font-semibold text-muted-foreground">{resumen}</p>
      </div>
      {!demo && totalCierres > filas.length && (
        <p className="text-[11px] text-muted-foreground">
          Mostrando los {filas.length} más recientes de {totalCierres}.
        </p>
      )}
      <ul className="divide-y divide-border overflow-hidden rounded-xl border border-border bg-card">
        {filas.map((f) => (
          <li key={f.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-2 text-sm font-semibold text-foreground">
                {/* El nombre tachado + el chip: el cierre anulado no desaparece
                    de la lista (sería un hueco inexplicable) pero tampoco puede
                    parecer vivo. */}
                <span className={cn('truncate', f.anuladoEn && 'text-muted-foreground line-through')}>
                  {f.nombre}
                </span>
                <ChipCoop cooperativa={f.cooperativa} />
                {f.anuladoEn && <ChipAnulado />}
              </p>
              <p className="text-xs text-muted-foreground">
                {fmtFecha(f.creadoEn)}
                {f.telefono ? ` · ${f.telefono}` : ''}
              </p>
            </div>
            <p
              className={cn(
                'text-sm font-bold',
                f.anuladoEn ? 'text-muted-foreground line-through' : 'text-foreground',
              )}
            >
              {money(f.monto, f.moneda)}
            </p>
            {/* aria-label por fila: N botones «Ver detalle» idénticos son
                indistinguibles en el rotor de un lector (hallazgo M1 a11y). */}
            <Button
              variant="outline"
              size="sm"
              aria-label={`Ver detalle — ${f.nombre}`}
              onClick={() => setAbierta(f)}
            >
              Ver detalle
            </Button>
          </li>
        ))}
      </ul>
      {abierta && <MiniFicha fila={abierta} onClose={() => setAbierta(null)} />}
    </section>
  )
}

// ─── Revisión del mes (supervisor y gerencia) ────────────────────────────────

/**
 * La lista de cierres en coops DEL MES con su N.° de operación a la vista.
 *
 * Por qué existe: la cooperativa no le manda nada al CRM, así que el número que
 * escribe el vendedor vale exactamente lo que valga la revisión que hay detrás.
 * Esta pantalla es esa revisión: pone los datos donde se pueden contrastar en un
 * minuto en vez de obligar a una excavación.
 *
 * Las filas vienen de `cierres_mes` (servidor), no de filtrar el histórico en el
 * cliente: esa lista llega con tope 200 por antigüedad y podría no alcanzar el
 * mes entero.
 */
function RevisionDelMes({
  filas,
  truncada,
  demo,
  esGerencia,
  onCerrar,
}: {
  filas: CierreExterno[]
  truncada: boolean
  demo: boolean
  esGerencia: boolean
  onCerrar: () => void
}) {
  const { anularCierreExterno, recargar } = useCRMData()
  const anularMut = useAnularCierreExterno()
  const [anulando, setAnulando] = useState<CierreExterno | null>(null)
  const [motivo, setMotivo] = useState('')
  const [error, setError] = useState<string | null>(null)
  /** Separado de `error`: un fallo del servidor NO deja inválido un motivo que
   *  estaba bien escrito, o el usuario lo reescribe sin necesidad. */
  const [motivoInvalido, setMotivoInvalido] = useState(false)
  const [enviando, setEnviando] = useState(false)
  /** Los botones «Anular» por fila, para devolverles el foco al volver. */
  const refBotonFila = useRef(new Map<string, HTMLButtonElement>())
  const refMotivo = useRef<HTMLTextAreaElement>(null)

  // Al abrir la confirmación el foco va al motivo: es el único campo que hay
  // que llenar, y sin esto el foco solo llega por rebote al tope del diálogo.
  useEffect(() => {
    if (anulando) refMotivo.current?.focus()
  }, [anulando])

  function cerrarConfirmacion() {
    const id = anulando?.cierre_id
    setAnulando(null)
    setMotivo('')
    setError(null)
    setMotivoInvalido(false)
    // De vuelta a la fila de donde salió: con 25 cierres, re-tabular la lista
    // entera después de cada intento es inaceptable.
    if (id) requestAnimationFrame(() => refBotonFila.current.get(id)?.focus())
  }

  async function confirmarAnulacion() {
    if (!anulando || enviando) return
    const limpio = motivo.trim()
    if (!limpio) {
      setMotivoInvalido(true)
      setError('Escribe el motivo de la anulación')
      return
    }
    setError(null)
    setMotivoInvalido(false)
    if (demo) {
      const res = anularCierreExterno(anulando.cierre_id, limpio)
      if (!res.ok) {
        setError(res.error ?? 'No se pudo anular el cierre')
        return
      }
      setAnulando(null)
      setMotivo('')
      toast.success('Cierre anulado (demo): ya no cuenta en cuota ni conversión')
      return
    }
    setEnviando(true)
    try {
      await anularMut.mutateAsync({ cierreId: anulando.cierre_id, motivo: limpio })
      // El cumplimiento de metas NO vive en TanStack (lo carga el store), así
      // que la invalidación de la mutación no lo alcanza. Sin este `recargar`,
      // el desglose restaba coops FRESCAS de un cumplimiento VIEJO y pintaba el
      // dinero recién anulado como si fuera capital de Avance.
      await recargar()
      setAnulando(null)
      setMotivo('')
      toast.success('Cierre anulado: ya no cuenta en cuota ni conversión')
    } catch (e) {
      setError(e instanceof CrmApiError ? e.message : 'No se pudo anular el cierre')
    } finally {
      setEnviando(false)
    }
  }

  // Paso de confirmación aparte: anular no se deshace, así que no puede ser un
  // clic suelto en una lista. Y el motivo se exige AQUÍ, no después.
  if (anulando) {
    return (
      <Dialog
        open
        onClose={enviando ? () => {} : cerrarConfirmacion}
        ariaLabel="Anular cierre en cooperativa"
      >
        <DialogHeader>
          <DialogTitle>Anular el cierre de {anulando.nombre_completo}</DialogTitle>
        </DialogHeader>
        <DialogBody className="space-y-3">
          <p className="rounded-xl border border-warning/40 bg-warning/10 p-3 text-xs font-semibold leading-relaxed text-warning-text">
            Este cierre dejará de contar en la cuota y en la conversión de{' '}
            {anulando.vendedor_nombre ?? 'su analista'}. No se puede deshacer.
          </p>
          <div className="space-y-1.5">
            <Label htmlFor="cx-motivo">Motivo de la anulación</Label>
            <Textarea
              id="cx-motivo"
              ref={refMotivo}
              rows={3}
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="Por ejemplo: el depósito no existe en el estado de cuenta"
              disabled={enviando}
              aria-invalid={motivoInvalido}
              aria-describedby={motivoInvalido ? 'cx-motivo-error' : undefined}
            />
          </div>
          {error && (
            <p id="cx-motivo-error" role="alert" className="text-xs font-semibold text-destructive-text">
              {error}
            </p>
          )}
        </DialogBody>
        {/* ⚠️ Las `key`: el diálogo de la LISTA tiene otro <Button> en cada una
            de estas posiciones y React reconcilia por índice, así que sin ellas
            «Volver» se convertiría en «Cerrar» bajo el foco y un segundo Enter
            cerraría la revisión entera (WCAG 4.1.2). Mismo bug que ya costó caro
            en cerrar-tarea.tsx. */}
        <DialogFooter>
          <Button
            key="volver-anular"
            variant="outline"
            size="sm"
            disabled={enviando}
            onClick={cerrarConfirmacion}
          >
            Volver
          </Button>
          {/* `aria-disabled` y no `disabled`: al deshabilitar de verdad, el foco
              se cae a <body> y Radix NO lo rescata (su MutationObserver solo mira
              nodos ELIMINADOS, y esto es un cambio de atributo). El guard de
              `confirmarAnulacion` ya es hermético, así que el botón puede seguir
              siendo enfocable sin riesgo de doble envío. */}
          <Button
            key="confirmar-anular"
            variant="destructive"
            size="sm"
            aria-disabled={enviando}
            aria-busy={enviando}
            className={enviando ? 'pointer-events-none opacity-50' : undefined}
            onClick={() => void confirmarAnulacion()}
          >
            {enviando ? 'Anulando…' : 'Anular cierre'}
          </Button>
        </DialogFooter>
      </Dialog>
    )
  }

  return (
    <Dialog open onClose={onCerrar} ariaLabel="Cierres en cooperativas de este mes">
      <DialogHeader>
        <DialogTitle>Cierres en cooperativas · este mes</DialogTitle>
        <DialogDescription>
          El N.° de operación es lo que permite contrastar cada cierre antes de pagarlo.
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-2">
        {truncada && (
          <p className="text-[11px] text-muted-foreground">
            Mostrando los {filas.length} más recientes del mes.
          </p>
        )}
        {filas.length === 0 ? (
          <p className="text-xs text-muted-foreground">
            Este mes todavía no hay cierres en cooperativas.
          </p>
        ) : (
          <ul className="divide-y divide-border overflow-hidden rounded-xl border border-border">
            {filas.map((c) => {
              const anulado = c.anulado_en != null
              return (
                <li key={c.cierre_id} className="space-y-1 p-3">
                  <p className="flex flex-wrap items-center gap-2 text-sm font-semibold">
                    <span className={cn('truncate', anulado && 'text-muted-foreground line-through')}>
                      {c.nombre_completo}
                    </span>
                    <ChipCoop cooperativa={c.cooperativa} />
                    {anulado && <ChipAnulado />}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {fmtFecha(c.creado_en)} · {c.vendedor_nombre ?? 'Analista sin nombre'}
                  </p>
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <p className="text-xs">
                      <span className="text-muted-foreground">N.° de operación: </span>
                      <span className="font-mono font-semibold text-foreground">
                        {c.numero_transaccion}
                      </span>
                    </p>
                    <p
                      className={cn(
                        'text-sm font-bold tabular-nums',
                        anulado ? 'text-muted-foreground line-through' : 'text-foreground',
                      )}
                    >
                      {money(c.monto, c.moneda)}
                    </p>
                  </div>
                  {anulado && c.motivo_anulacion && (
                    <p className="text-[11px] text-destructive-text">Anulado: {c.motivo_anulacion}</p>
                  )}
                  {esGerencia && !anulado && (
                    <Button
                      variant="outline"
                      size="sm"
                      ref={(el) => {
                        if (el) refBotonFila.current.set(c.cierre_id, el)
                        else refBotonFila.current.delete(c.cierre_id)
                      }}
                      // aria-label por fila: N botones «Anular» idénticos son
                      // indistinguibles en el rotor de un lector.
                      aria-label={`Anular el cierre de ${c.nombre_completo}`}
                      onClick={() => {
                        setAnulando(c)
                        setMotivo('')
                        setError(null)
                        setMotivoInvalido(false)
                      }}
                    >
                      Anular
                    </Button>
                  )}
                </li>
              )
            })}
          </ul>
        )}
      </DialogBody>
      <DialogFooter>
        <Button key="cerrar-revision" variant="outline" size="sm" onClick={onCerrar}>
          Cerrar
        </Button>
      </DialogFooter>
    </Dialog>
  )
}

// ─── Desglose «Por empresa» (supervisor y gerencia) ──────────────────────────

/** Un vendedor del desglose: capital por empresa y moneda. */
interface FilaPorEmpresa {
  vendedorId: string
  nombre: string
  /** Avance = capital TOTAL del cumplimiento − lo cerrado en coops (por moneda). */
  avance: Partial<Record<Moneda, number>>
  coops: EmpresaVendedor[]
}

/**
 * El bloque «Por empresa» de los reportes: por cada vendedor CON cierres en
 * cooperativas este mes, cuánto vino de Avance y cuánto de cada COOPAC (capital
 * por moneda, PEN/USD jamás sumados, y n.º de cierres). El total contra la
 * cuota sigue siendo UNO — esto solo enseña de dónde vino cada sol.
 *
 * Se OCULTA entero si el mes no tiene cierres en coops en el ámbito: sin
 * segunda fuente no hay desglose que explicar. La parte Avance se calcula
 * restando dos números servidos (cumplimiento − agregados coop), sin
 * divisiones en cliente.
 */
export function DesglosePorEmpresa({
  demo,
  porVendedor,
}: {
  demo: boolean
  /** `porVendedor` del cumplimiento de metas (store); null = aún sin foto. */
  porVendedor: Record<string, CumplimientoVendedor> | null
}) {
  const { cierresExternos: cierresDemo = [] } = useCRMData()
  const consulta = useCierresExternos(!demo, periodoLima(Date.now()))
  const { yo } = useAuth()
  const esGerencia = yo?.rol === 'gerencia'
  const [revisando, setRevisando] = useState(false)

  // Las filas del mes para la revisión. En real vienen del servidor
  // (`cierres_mes`); en demo se derivan del store, que ya es completo.
  const filasMes = useMemo<CierreExterno[]>(() => {
    if (!demo) return consulta.data?.cierres_mes ?? []
    const desde = periodoLima(Date.now())
    return cierresDemo
      .filter((c) => c.creadoEn.slice(0, 7) === desde.slice(0, 7))
      .map((c) => ({
        cierre_id: c.cierreId,
        lead_id: c.leadId,
        cooperativa: c.cooperativa,
        monto: c.monto,
        moneda: c.moneda,
        nombre_completo: c.nombre,
        documento_tipo: 'DNI' as const,
        documento: '',
        telefono: c.telefono,
        numero_transaccion: c.numeroTransaccion,
        referencia_externa: null,
        vence_en: null,
        nota: null,
        vendedor_id: c.vendedorId,
        vendedor_nombre: c.vendedorNombre,
        creado_en: c.creadoEn,
        anulado_en: c.anuladoEn,
        motivo_anulacion: c.motivoAnulacion,
      }))
  }, [demo, cierresDemo, consulta.data])

  const filasEmpresa = useMemo<EmpresaVendedor[]>(() => {
    if (!demo) return consulta.data?.por_empresa ?? []
    const mapa = new Map<string, EmpresaVendedor>()
    for (const c of cierresDemo) {
      // Espejo del servidor: `por_empresa` es una vista de DINERO y los cierres
      // anulados no son dinero.
      if (c.anuladoEn) continue
      const k = `${c.vendedorId}|${c.cooperativa}|${c.moneda}`
      const previo = mapa.get(k)
      if (previo) {
        previo.capital += c.monto
        previo.cierres += 1
      } else {
        mapa.set(k, {
          vendedor_id: c.vendedorId,
          vendedor_nombre: c.vendedorNombre,
          cooperativa: c.cooperativa,
          moneda: c.moneda,
          capital: c.monto,
          cierres: 1,
        })
      }
    }
    return [...mapa.values()]
  }, [demo, consulta.data, cierresDemo])

  const filas = useMemo<FilaPorEmpresa[]>(() => {
    const porId = new Map<string, FilaPorEmpresa>()
    for (const e of filasEmpresa) {
      let fila = porId.get(e.vendedor_id)
      if (!fila) {
        fila = {
          vendedorId: e.vendedor_id,
          nombre: e.vendedor_nombre
            ?? porVendedor?.[e.vendedor_id]?.nombre
            ?? 'Analista sin nombre',
          avance: {},
          coops: [],
        }
        porId.set(e.vendedor_id, fila)
      }
      fila.coops.push(e)
    }
    for (const fila of porId.values()) {
      const cumplimiento = porVendedor?.[fila.vendedorId]
      for (const moneda of ['PEN', 'USD'] as const) {
        const total = (cumplimiento?.detalles ?? [])
          .filter((d) => d.moneda === moneda)
          .reduce((suma, d) => suma + d.capitalReal, 0)
        const enCoops = fila.coops
          .filter((c) => c.moneda === moneda)
          .reduce((suma, c) => suma + c.capital, 0)
        const avance = capitalAvance(total, enCoops)
        // Solo se pinta la moneda que tiene algo que decir (Avance o coop).
        if (avance > 0 || enCoops > 0) fila.avance[moneda] = avance
      }
      fila.coops.sort((a, b) => a.cooperativa.localeCompare(b.cooperativa) || a.moneda.localeCompare(b.moneda))
    }
    return [...porId.values()].sort((a, b) => a.nombre.localeCompare(b.nombre))
  }, [filasEmpresa, porVendedor])

  if (!demo && consulta.isError) {
    return (
      <Card>
        <SectionHead icon={Landmark} title="Por empresa" />
        <CardContent role="status" className="flex items-center justify-between gap-3 pb-5 pt-0">
          <p className="text-xs font-semibold text-warning-text">
            No se pudo cargar el desglose por empresa.
          </p>
          <Button variant="outline" size="sm" onClick={() => void consulta.refetch()}>
            Reintentar
          </Button>
        </CardContent>
      </Card>
    )
  }

  if (filas.length === 0) return null

  return (
    <Card>
      <SectionHead
        icon={Landmark}
        title="Por empresa"
        right={
          <Button variant="outline" size="sm" onClick={() => setRevisando(true)}>
            Ver cierres del mes
          </Button>
        }
      />
      <CardContent className="pb-5 pt-0">
        <ul className="space-y-3">
        {filas.map((f) => (
          <li key={f.vendedorId} className="space-y-1">
            <p className="text-xs font-bold text-foreground">{f.nombre}</p>
            <div className="space-y-0.5 pl-3">
              <p className="flex flex-wrap items-baseline gap-x-2 text-xs text-muted-foreground">
                <span className="font-semibold text-foreground/80">Avance Corp</span>
                <span className="tabular-nums">
                  {(['PEN', 'USD'] as const)
                    .filter((m) => f.avance[m] != null)
                    .map((m) => money(f.avance[m]!, m))
                    .join(' · ') || '—'}
                </span>
              </p>
              {f.coops.map((c) => (
                <p
                  key={`${c.cooperativa}-${c.moneda}`}
                  className="flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground"
                >
                  <ChipCoop cooperativa={c.cooperativa} />
                  <span className="tabular-nums font-semibold text-foreground/80">
                    {money(c.capital, c.moneda)}
                  </span>
                  <span>{c.cierres} {c.cierres === 1 ? 'cierre' : 'cierres'}</span>
                </p>
              ))}
            </div>
          </li>
        ))}
        </ul>
        <p className="mt-3 text-[10.5px] text-muted-foreground">
          El total contra la cuota sigue siendo uno solo; aquí se ve de dónde vino cada sol.
          Solo aparecen analistas con cierres en cooperativas este mes.
        </p>
      </CardContent>
      {revisando && (
        <RevisionDelMes
          filas={filasMes}
          truncada={!demo && (consulta.data?.cierres_mes_total ?? 0) > filasMes.length}
          demo={demo}
          esGerencia={esGerencia}
          onCerrar={() => setRevisando(false)}
        />
      )}
    </Card>
  )
}
