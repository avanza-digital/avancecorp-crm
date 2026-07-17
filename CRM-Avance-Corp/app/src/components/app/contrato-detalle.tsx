// Detalle SOLO LECTURA del contrato — espejo del "Ver detalle" del portal
// (analista.js: abrirModalDetalle + renderDetalleMeta/renderDetalleTitulares, y
// las reglas finas del cronograma del admin: cuota/retorno/devolución
// etiquetados, pagadas vs pendientes, fecha y monto del pago real, totales).
// Siempre disponible: NO depende de la ventana de 5 h — la RLS ya limita a la
// cartera (contrato ajeno = 0 filas, fail-closed). Se monta DENTRO de <Dialog>
// (mismo patrón que ContratoNuevo: el caller pone el Dialog, aquí va el panel).
import { useMemo, type ReactNode } from 'react'
import { FileText, RotateCcw, WifiOff } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { fmtFecha, money } from '@/lib/format'
import { mensajeDeError } from '@/data/crm-api'
import { useContrato, useCronograma, useTitulares } from '@/data/crm-queries'
import { CATEGORIA_LABEL, MODALIDAD_LABEL } from '@/lib/contratos-catalogo'
import { etiquetaDocumento } from '@/lib/titulares'
import type { ContratoRow, Cuota, EstadoContrato, EstadoCuota, Titular } from '@/lib/clientes-tipos'

// Sin verde en el sistema ("positivo" = azul): activo/pagado en accent,
// vencido en destructive, renovado/trasladado en ámbar, retirado neutro.
// Paleta PROPIA del detalle (aquí 'vencido' es deuda): no es una copia del
// ESTADO_COLOR de la tabla (contratos-catalogo) y por eso se queda local.
const ESTADO_CONTRATO_COLOR: Record<EstadoContrato, string> = {
  activo: 'var(--accent)',
  vencido: 'var(--destructive)',
  renovado: 'var(--warning)',
  retirado: 'var(--muted-foreground)',
}
// 'trasladado' JAMÁS se pinta como deuda: es capital roleado a la renovación
// (misma regla que "CAPITAL RENOVADO" del portal, ciclo de vida 2026-07-13).
const ESTADO_CUOTA_UI: Record<EstadoCuota, { label: string; color: string }> = {
  pendiente: { label: 'pendiente', color: 'var(--muted-foreground)' },
  pagado: { label: 'pagado', color: 'var(--accent)' },
  vencido: { label: 'vencido', color: 'var(--destructive)' },
  trasladado: { label: 'CAPITAL RENOVADO', color: 'var(--warning)' },
}

/** Celda del grid de términos (espejo visual de renderDetalleMeta del portal). */
function Termino({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <p className="text-[10px] font-extrabold uppercase tracking-widest text-muted-foreground">{label}</p>
      <p className="text-sm font-bold text-foreground [overflow-wrap:anywhere]">{children}</p>
    </div>
  )
}

/**
 * Datos PRECARGADOS del detalle (modo DEMO): contrato + cronograma + co-titulares
 * ya en memoria. Si vienen, el detalle NO fetchea NADA — una sesión demo no tiene
 * Supabase y cualquier GET pegaría a producción (regla de oro). La ruta real (sin
 * este prop) lee de la caché de TanStack (useContrato/useCronograma/useTitulares).
 */
export interface ContratoDetalleDatos {
  contrato: ContratoRow
  cuotas: Cuota[]
  titulares: Titular[]
}

export interface ContratoDetalleProps {
  contratoId: string
  onCerrar: () => void
  datos?: ContratoDetalleDatos
}

export function ContratoDetalle({ contratoId, onCerrar, datos }: ContratoDetalleProps) {
  // DEMO: con datos precargados los hooks quedan DESHABILITADOS — cero red
  // (una sesión demo no tiene Supabase, ver ContratoDetalleDatos).
  const precargado = datos != null

  // Los términos salen de la MISMA clave contratos() que la tabla (useContrato
  // hace select por id sobre la caché): abrir el detalle desde la pantalla ya
  // no re-descarga la cartera completa (tope 2000) para encontrar UNA fila que
  // el caller tenía pintada — con la lista fresca (< 30 s) no hay fetch.
  // Cronograma y co-titulares cargan aparte: espejo del portal — un fallo de
  // co-titulares NO rompe el detalle; uno del cronograma solo rompe su sección.
  const qContrato = useContrato(contratoId, !precargado)
  const qCronograma = useCronograma(contratoId, !precargado)
  const qTitulares = useTitulares(contratoId, !precargado)

  const contrato = datos?.contrato ?? qContrato.data ?? null
  // El error solo gana SIN data: un refetch de fondo fallido de la lista (foco
  // de ventana + retry:false) no debe voltear un detalle ya pintado desde caché.
  const errorContrato = precargado
    ? null
    : qContrato.isError && qContrato.data == null
      ? mensajeDeError(qContrato.error, 'No se pudo cargar el contrato.')
      : qContrato.isSuccess && qContrato.data == null
        // Fuera de la cartera o inexistente: mismo mensaje, sin revelar existencia.
        ? 'No se encontró el contrato en tu cartera.'
        : null
  const cuotas = datos?.cuotas ?? qCronograma.data ?? null
  const errorCrono = !precargado && qCronograma.isError && qCronograma.data == null
    ? mensajeDeError(qCronograma.error, 'No se pudo cargar el cronograma.')
    : null
  // Espejo del portal (cargarTitulares): un fallo aquí no rompe la pantalla —
  // el bloque simplemente no se pinta (crm-api ya registró el error).
  const titulares = datos?.titulares ?? qTitulares.data ?? []

  // Reintento AMPLIO (mismo alcance que el intento++ anterior): el fallo suele
  // ser de red y afecta a las tres lecturas a la vez.
  const reintentar = () => {
    void qContrato.refetch()
    void qCronograma.refetch()
    void qTitulares.refetch()
  }

  // Totales con las mismas reglas del portal: las cuotas de interés excluyen el
  // retorno del capital; "Pagado" suma lo COBRADO real (monto_pagado) y
  // "Por pagar" excluye lo trasladado (ese capital vive en la renovación).
  const totales = useMemo(() => {
    if (!cuotas) return null
    const interes = cuotas.filter((c) => c.tipo !== 'retorno')
    return {
      cuotasInteres: interes.length,
      pagadasInteres: interes.filter((c) => c.estado === 'pagado').length,
      pagado: cuotas
        .filter((c) => c.estado === 'pagado')
        .reduce((a, c) => a + (c.monto_pagado ?? 0), 0),
      porPagar: cuotas
        .filter((c) => c.estado !== 'pagado' && c.estado !== 'trasladado')
        .reduce((a, c) => a + c.monto_programado, 0),
    }
  }, [cuotas])

  const tituloCronograma = contrato?.tipo_interes === 'compuesto'
    ? 'Cronograma de pagos (intereses al vencimiento + retorno del capital)'
    : `Cronograma de pagos (${totales?.cuotasInteres ?? 0} cuotas de interés + retorno del capital)`

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <FileText className="size-4 text-primary" aria-hidden />
          Contrato {contrato?.numero_contrato ?? '…'}
        </DialogTitle>
        <DialogDescription>
          Detalle de solo lectura — disponible siempre, con o sin ventana de corrección.
        </DialogDescription>
      </DialogHeader>
      <DialogBody className="max-h-[65vh] space-y-4 overflow-y-auto">
        {errorContrato ? (
          <div className="flex flex-col items-center justify-center gap-3 py-10 text-center">
            <span className="grid size-11 place-items-center rounded-2xl bg-destructive/10 text-destructive">
              <WifiOff className="size-5" aria-hidden />
            </span>
            <p className="text-sm font-semibold text-foreground">{errorContrato}</p>
            <Button variant="outline" size="sm" onClick={reintentar}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          </div>
        ) : !contrato ? (
          <div className="space-y-2" aria-busy>
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-40 w-full" />
          </div>
        ) : (
          <>
            {/* ── Términos del contrato (espejo de renderDetalleMeta) ─────────── */}
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <Termino label="Cliente">{contrato.cliente_nombre ?? '—'}</Termino>
              <Termino label="Capital">{money(contrato.capital, contrato.moneda)}</Termino>
              <Termino label="Tasa anual">{contrato.tasa_anual}%</Termino>
              <Termino label="Tipo de interés">
                {contrato.tipo_interes === 'compuesto' ? 'Compuesto' : 'Simple'}
              </Termino>
              {/* En compuesto la modalidad no aplica (capitaliza anual) — regla del portal. */}
              <Termino label="Modalidad">
                {contrato.tipo_interes === 'compuesto' ? '—' : MODALIDAD_LABEL[contrato.modalidad]}
              </Termino>
              <Termino label="Categoría">
                {contrato.categoria ? (
                  <Badge color="var(--warning)">{CATEGORIA_LABEL[contrato.categoria]}</Badge>
                ) : (
                  '—'
                )}
              </Termino>
              <Termino label="Inicio">{fmtFecha(contrato.fecha_inicio)}</Termino>
              <Termino label="Vencimiento">{fmtFecha(contrato.fecha_vencimiento)}</Termino>
              <Termino label="Estado">
                <Badge color={ESTADO_CONTRATO_COLOR[contrato.estado]} dot>
                  {contrato.estado}
                </Badge>
              </Termino>
            </div>

            {contrato.notas_internas && (
              <div className="rounded-xl border border-dashed border-border bg-muted/40 p-3">
                <p className="text-[10px] font-extrabold uppercase tracking-widest text-muted-foreground">
                  Notas internas
                </p>
                <p className="mt-0.5 whitespace-pre-wrap text-xs text-foreground [overflow-wrap:anywhere]">
                  {contrato.notas_internas}
                </p>
              </div>
            )}

            {/* ── Co-titulares (cuentas mancomunadas, solo lectura) ───────────── */}
            {titulares.length > 0 && (
              <div className="rounded-xl border border-border bg-muted/40 p-3">
                <p className="text-[10px] font-extrabold uppercase tracking-widest text-muted-foreground">
                  Co-titulares
                </p>
                <ul className="mt-1 space-y-1">
                  {titulares.map((t) => (
                    <li key={t.orden} className="text-sm font-semibold text-foreground [overflow-wrap:anywhere]">
                      {t.nombre_completo}{' '}
                      <span className="font-normal text-muted-foreground">
                        · {etiquetaDocumento(t.tipo_documento, t.documento)}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {/* ── Cronograma COMPLETO (reglas finas del portal) ───────────────── */}
            <div>
              <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
                {tituloCronograma}
              </p>
              {errorCrono ? (
                <div className="mt-2 space-y-2 rounded-xl border border-destructive/30 bg-destructive/5 p-3">
                  <p className="text-xs font-semibold text-destructive">{errorCrono}</p>
                  <Button variant="outline" size="xs" onClick={reintentar}>
                    <RotateCcw aria-hidden /> Reintentar
                  </Button>
                </div>
              ) : !cuotas ? (
                <Skeleton className="mt-2 h-28 w-full" aria-busy />
              ) : cuotas.length === 0 ? (
                // Copy del estado vacío del timeline del portal.
                <p className="mt-2 rounded-xl border border-dashed border-border p-4 text-center text-xs text-muted-foreground">
                  Aún no se ha generado el cronograma para este contrato.
                </p>
              ) : (
                <>
                  <div className="mt-2 overflow-x-auto rounded-xl border border-border">
                    <table className="w-full text-xs">
                      <thead>
                        <tr className="border-b border-border bg-muted/50 text-left text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
                          <th className="px-3 py-2">Cuota</th>
                          <th className="px-3 py-2">Fecha</th>
                          <th className="px-3 py-2">Monto</th>
                          <th className="px-3 py-2">Estado</th>
                          <th className="px-3 py-2">Pago real</th>
                        </tr>
                      </thead>
                      <tbody>
                        {cuotas.map((c) => {
                          // Hitos de cobro del contrato (fila resaltada, como el portal):
                          // retorno del capital y pago de intereses del compuesto.
                          const esHito = c.tipo === 'retorno' || c.tipo === 'devolucion'
                          const estadoUi = ESTADO_CUOTA_UI[c.estado]
                          const tienePago = c.fecha_pago_real != null || c.monto_pagado != null
                          return (
                            <tr
                              key={c.id}
                              className={`border-b border-border/60 last:border-0 ${esHito ? 'bg-warning/10' : ''}`}
                            >
                              <td className="px-3 py-2">
                                {c.tipo === 'retorno' ? (
                                  <Badge color="var(--warning)" className="text-[10px] tracking-wide">
                                    RETORNO DEL CAPITAL
                                  </Badge>
                                ) : c.tipo === 'devolucion' ? (
                                  <Badge color="var(--warning)" className="text-[10px] tracking-wide">
                                    PAGO DE INTERESES
                                  </Badge>
                                ) : (
                                  <span className="font-semibold text-foreground">Cuota #{c.numero_cuota}</span>
                                )}
                              </td>
                              <td className="px-3 py-2 tabular-nums text-muted-foreground">
                                {fmtFecha(c.fecha_programada)}
                              </td>
                              <td className="px-3 py-2 font-semibold tabular-nums text-foreground">
                                {money(c.monto_programado, contrato.moneda)}
                              </td>
                              <td className="px-3 py-2">
                                <Badge color={estadoUi.color}>{estadoUi.label}</Badge>
                              </td>
                              <td className="px-3 py-2 tabular-nums text-muted-foreground">
                                {tienePago
                                  ? `${fmtFecha(c.fecha_pago_real)}${
                                      c.monto_pagado != null ? ` · ${money(c.monto_pagado, contrato.moneda)}` : ''
                                    }`
                                  : '—'}
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                  {totales && (
                    <p className="mt-2 text-xs text-muted-foreground">
                      <b className="text-foreground">
                        {totales.pagadasInteres} de {totales.cuotasInteres}
                      </b>{' '}
                      cuotas de interés pagadas · Pagado{' '}
                      <b className="tabular-nums text-foreground">{money(totales.pagado, contrato.moneda)}</b>{' '}
                      · Por pagar{' '}
                      <b className="tabular-nums text-foreground">{money(totales.porPagar, contrato.moneda)}</b>
                    </p>
                  )}
                </>
              )}
            </div>
          </>
        )}
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" size="sm" onClick={onCerrar}>
          Cerrar
        </Button>
      </DialogFooter>
    </>
  )
}
