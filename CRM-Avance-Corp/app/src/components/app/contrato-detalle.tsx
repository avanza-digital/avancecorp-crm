// Detalle SOLO LECTURA del contrato — espejo del "Ver detalle" del portal
// (analista.js: abrirModalDetalle + renderDetalleMeta/renderDetalleTitulares, y
// las reglas finas del cronograma del admin: cuota/retorno/devolución
// etiquetados, pagadas vs pendientes, fecha y monto del pago real, totales).
// Siempre disponible: NO depende de la ventana de 5 h — la RLS ya limita a la
// cartera (contrato ajeno = 0 filas, fail-closed). Se monta DENTRO de <Dialog>
// (mismo patrón que ContratoNuevo: el caller pone el Dialog, aquí va el panel).
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { Download, ExternalLink, FileText, LoaderCircle, RotateCcw, Trash2, WifiOff } from 'lucide-react'
import { toast } from 'sonner'
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
import { CODIGO_PRODUCTO_HISTORICO } from '@/components/app/producto-contrato-selector'
import type { ContratoPdfDatos } from '@/lib/contrato-pdf'
import {
  abrirVentanaContratoPdf,
  archivarContratoPdfConfirmado,
  consultarEstadoContratoPdf,
  CONTRATO_DOCUMENTO_DESDE_TEXTO,
  ContratoPdfNoSelladoError,
  descargarArchivoContratoPdf,
  esContratoRegimenAnterior,
  etiquetaEstadoContratoPdf,
  obtenerContratoPdfArchivado,
  verArchivoContratoPdf,
  type EstadoContratoPdf,
} from '@/lib/contrato-pdf-archivo'
import { archivarContratoPdfDemoHabilitado } from '@/lib/contrato-pdf-demo-loader'

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
  /** Fotografía legal completa. Presente en demo y, luego, desde la RPC privada. */
  pdfDatos?: ContratoPdfDatos | undefined
}

export interface ContratoDetalleProps {
  contratoId: string
  onCerrar: () => void
  datos?: ContratoDetalleDatos
  puedeEliminar?: boolean
  onEliminar?: () => Promise<void> | void
}

interface EstadoPdfUi {
  contratoId: string
  secuencia: number
  estado: EstadoContratoPdf | null
  cargando: boolean
  error: boolean
}

export function ContratoDetalle({ contratoId, onCerrar, datos,
  puedeEliminar = false,
  onEliminar,
}: ContratoDetalleProps) {
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
        ? // Fuera de la cartera o inexistente: mismo mensaje, sin revelar existencia.
          'No se encontró el contrato en tu cartera.'
        : null
  const cuotas = datos?.cuotas ?? qCronograma.data ?? null
  const errorCrono = !precargado && qCronograma.isError && qCronograma.data == null
    ? mensajeDeError(qCronograma.error, 'No se pudo cargar el cronograma.')
    : null
  // Un fallo aquí NO rompe el detalle (espejo del portal, cargarTitulares), pero
  // tampoco puede silenciarse: `?? []` colapsaba "no se pudo cargar" con "no
  // tiene", y el bloque, condicionado a length > 0, desaparecía. Una caída de
  // red se leía entonces como "este contrato no es mancomunado" — una
  // afirmación FALSA sobre quién es titular legal del capital, justo el dato
  // que alguien abre el detalle para verificar. Tres estados distintos:
  // null = cargando · error = no se sabe · [] = de verdad no tiene.
  const titulares = datos?.titulares ?? qTitulares.data ?? null
  const pdfDatos = datos?.pdfDatos
  const contratoIdActualRef = useRef(contratoId)
  contratoIdActualRef.current = contratoId
  const secuenciaEstadoPdfRef = useRef(0)
  const secuenciaAccionPdfRef = useRef(0)
  const [accionPdfUi, setAccionPdfUi] = useState<{
    contratoId: string
    secuencia: number
    accion: 'ver' | 'descargar'
  } | null>(null)
  const [estadoPdfUi, setEstadoPdfUi] = useState<EstadoPdfUi>(() => ({
    contratoId,
    secuencia: 0,
    estado: pdfDatos ? 'pendiente' : null,
    cargando: !pdfDatos,
    error: false,
  }))
  const [confirmandoEliminar, setConfirmandoEliminar] = useState(false)
  const [eliminando, setEliminando] = useState(false)
  // Etiquetar el estado con su contrato evita pintar, incluso durante un frame,
  // el estado o spinner de A después de que el mismo diálogo ya recibió B.
  const estadoPdfEsActual = estadoPdfUi.contratoId === contratoId
    && estadoPdfUi.secuencia === secuenciaEstadoPdfRef.current
  const estadoPdf = estadoPdfEsActual
    ? estadoPdfUi.estado
    : pdfDatos ? 'pendiente' : null
  const cargandoEstadoPdf = estadoPdfEsActual ? estadoPdfUi.cargando : !pdfDatos
  const errorEstadoPdf = estadoPdfEsActual ? estadoPdfUi.error : false
  const accionPdf = accionPdfUi?.contratoId === contratoId
    && accionPdfUi.secuencia === secuenciaAccionPdfRef.current
    ? accionPdfUi.accion
    : null
  // El régimen documental se decide por la FECHA DE FIRMA del contrato. Importa
  // aquí porque «Ver contrato PDF» no muestra: si no hay documento, lo FABRICA.
  // En un contrato del formato anterior eso acuñaría un segundo contrato para
  // una operación ya firmada —así nacieron los 21 documentos del 18 y 19 de
  // agosto—, fechado meses atrás y con el domicilio de hoy, que es el de
  // notificaciones. El servidor ya lo niega; esto evita ofrecerlo.
  const regimenAnterior = esContratoRegimenAnterior(contrato?.fecha_inicio, contrato?.creado_en)
  // Los que YA se emitieron siguen siendo descargables: se quedan como están.
  const documentoEmitido = estadoPdf === 'sellado'
  const puedeOperarPdf = !regimenAnterior || documentoEmitido
  const errorTitulares = !precargado && qTitulares.isError && qTitulares.data == null
    ? mensajeDeError(qTitulares.error, 'No se pudieron cargar los co-titulares.')
    : null

  // Reintento AMPLIO (mismo alcance que el intento++ anterior): el fallo suele
  // ser de red y afecta a las tres lecturas a la vez.
  const reintentar = () => {
    void qContrato.refetch()
    void qCronograma.refetch()
    void qTitulares.refetch()
  }

  useEffect(() => {
    const secuencia = ++secuenciaEstadoPdfRef.current
    // Un cambio de contrato o de fotografía demo invalida cualquier acción que
    // todavía esté esperando bytes del contexto anterior.
    ++secuenciaAccionPdfRef.current
    if (pdfDatos) {
      setEstadoPdfUi({ contratoId, secuencia, estado: 'pendiente', cargando: false, error: false,
      })
      return
    }
    let vigente = true
    setEstadoPdfUi({ contratoId, secuencia, estado: null, cargando: true, error: false,
    })
    void consultarEstadoContratoPdf(contratoId)
      .then((estado) => {
        if (
          vigente
          && secuenciaEstadoPdfRef.current === secuencia
          && contratoIdActualRef.current === contratoId
        ) {
          setEstadoPdfUi({ contratoId, secuencia, estado: estado.estado, cargando: false, error: false,
          })
        }
      })
      .catch(() => {
        if (
          vigente
          && secuenciaEstadoPdfRef.current === secuencia
          && contratoIdActualRef.current === contratoId
        ) {
          setEstadoPdfUi({ contratoId, secuencia, estado: null, cargando: false, error: true,
          })
        }
      })
    return () => { vigente = false }
  }, [contratoId, pdfDatos])

  useEffect(() => {
    setConfirmandoEliminar(false)
    setEliminando(false)
  }, [contratoId])

  const confirmarEliminacion = async () => {
    if (!onEliminar || eliminando) return
    setEliminando(true)
    try {
      await onEliminar()
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudo eliminar el contrato y sus PDF.'))
      setEliminando(false)
    }
  }

  const ejecutarPdf = async (accion: 'ver' | 'descargar') => {
    if (!contrato || accionPdf) return
    const contratoIdAccion = contratoId
    const secuenciaAccion = ++secuenciaAccionPdfRef.current
    const accionSigueVigente = () =>
      contratoIdActualRef.current === contratoIdAccion
      && secuenciaAccionPdfRef.current === secuenciaAccion
    let ventanaPdf: Window | null = null
    try {
      // La pestaña debe reservarse dentro del gesto del usuario. Esperar a la
      // Edge, descargar y calcular SHA antes de window.open activa el bloqueador.
      if (accion === 'ver') ventanaPdf = abrirVentanaContratoPdf()
      setAccionPdfUi({ contratoId: contratoIdAccion, secuencia: secuenciaAccion, accion,
      })
      // El resultado de una consulta de estado iniciada antes del ensure ya no
      // puede sobrescribir el estado sellado que confirme esta acción.
      const secuenciaEstado = ++secuenciaEstadoPdfRef.current
      setEstadoPdfUi((anterior) => ({
        contratoId: contratoIdAccion,
        secuencia: secuenciaEstado,
        estado: anterior.contratoId === contratoIdAccion ? anterior.estado : null,
        cargando: false,
        error: false,
      }))
      // Demo: la primera generación gana en el archivo local inmutable. Real:
      // primero recupera el objeto archivado por Edge; si el alta quedó sin PDF,
      // permite repararlo desde la fotografía contractual privada del servidor.
      const archivo = pdfDatos
        ? await archivarContratoPdfDemoHabilitado(contratoId, pdfDatos)
        : ((await obtenerContratoPdfArchivado(contratoId)) ??
          // Recuperación post-commit: genera únicamente desde la fotografía
          // contractual privada e inmutable de la RPC, nunca desde perfiles.
          (await archivarContratoPdfConfirmado(contratoId)))
      if (!accionSigueVigente()) {
        ventanaPdf?.close()
        return
      }
      setEstadoPdfUi({
        contratoId: contratoIdAccion,
        secuencia: secuenciaEstado,
        estado: 'sellado',
        cargando: false,
        error: false,
      })
      if (accion === 'ver') verArchivoContratoPdf(archivo, ventanaPdf!)
      else descargarArchivoContratoPdf(archivo)
    } catch (error) {
      ventanaPdf?.close()
      if (!accionSigueVigente()) return
      if (error instanceof ContratoPdfNoSelladoError) {
        setEstadoPdfUi({
          contratoId: contratoIdAccion,
          secuencia: secuenciaEstadoPdfRef.current,
          estado: error.estado,
          cargando: false,
          error: false,
        })
      }
      console.error('[contrato-pdf] No se pudo recuperar el documento archivado', error)
      toast.error(
        error instanceof Error
          ? error.message
          : 'No se pudo recuperar el contrato PDF. Inténtalo nuevamente.',
      )
    } finally {
      setAccionPdfUi((actual) => (actual?.secuencia === secuenciaAccion ? null : actual))
    }
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
            <div className="rounded-lg border border-border bg-muted/35 px-3 py-2 text-xs text-muted-foreground">
              {regimenAnterior && !documentoEmitido ? (
                <>
                  Contrato firmado antes del{' '}
                  <b className="text-foreground">{CONTRATO_DOCUMENTO_DESDE_TEXTO}</b>: su contrato es el del
                  formato anterior. El sistema no emite documento para esta operación.
                </>
              ) : cargandoEstadoPdf ? (
                'Consultando el estado documental…'
              ) : errorEstadoPdf ? (
                'No se pudo consultar el estado documental. Puedes reintentar desde los botones de PDF.'
              ) : estadoPdf ? (
                <>
                  Estado documental: <b className="text-foreground">{etiquetaEstadoContratoPdf(estadoPdf)}</b>.
                </>
              ) : (
                'Estado documental no disponible.'
              )}
            </div>
            {/* El documento ES el contrato desde el 19/08: que uno del régimen
                nuevo se quede sin él no puede ser un detalle en gris. Solo se
                grita cuando ya se sabe (estado consultado y sin sellar), nunca
                mientras carga. */}
            {!regimenAnterior && !cargandoEstadoPdf && !errorEstadoPdf
              && estadoPdf != null && estadoPdf !== 'sellado' && (
              <div
                role="alert"
                className="rounded-lg border border-destructive/35 bg-destructive/5 px-3 py-2 text-xs text-destructive"
              >
                Este contrato aún no tiene su documento, y el documento es el contrato. Genéralo con «Ver
                contrato PDF» o «Descargar contrato PDF».
              </div>
            )}
            {confirmandoEliminar && (
              <div
                role="alert"
                className="rounded-lg border border-destructive/35 bg-destructive/5 px-3 py-2 text-xs text-destructive"
              >
                Esta acción es permanente: se eliminarán el contrato, su cronograma, sus documentos y todas las
                revisiones del PDF. Confirma una segunda vez.
              </div>
            )}
            {/* ── Términos del contrato (espejo de renderDetalleMeta) ─────────── */}
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <Termino label="Cliente">{contrato.cliente_nombre ?? '—'}</Termino>
              <Termino label="Producto">
                <span title={`Condición ${contrato.producto_condicion_id}`}>
                  {contrato.producto_codigo === CODIGO_PRODUCTO_HISTORICO
                    ? 'Snapshot histórico'
                    : `${contrato.producto_codigo} · ${contrato.producto_nombre}`}
                </span>
              </Termino>
              <Termino label="Versión de producto">
                v{contrato.producto_version} · {contrato.producto_version_estado}
              </Termino>
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
                {contrato.categoria ? <Badge color="var(--warning)">{CATEGORIA_LABEL[contrato.categoria]}</Badge> : '—'}
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

            {/* ── Co-titulares (cuentas mancomunadas, solo lectura) ─────────────
                El caso vacío ([]) sigue sin pintar nada: la mayoría de contratos
                no son mancomunados y un bloque "sin co-titulares" en todos sería
                ruido. Lo que NUNCA puede pasar por vacío es el FALLO: ahí se dice
                explícitamente que el dato no se pudo leer, con reintento. */}
            {errorTitulares ? (
              <div className="space-y-2 rounded-xl border border-destructive/30 bg-destructive/5 p-3">
                <p className="text-[10px] font-extrabold uppercase tracking-widest text-muted-foreground">
                  Co-titulares
                </p>
                <p className="text-xs font-semibold text-destructive">{errorTitulares}</p>
                <p className="text-[11px] text-muted-foreground">
                  No se sabe si este contrato tiene co-titulares — esto NO significa que no los tenga.
                </p>
                <Button variant="outline" size="xs" onClick={reintentar}>
                  <RotateCcw aria-hidden /> Reintentar
                </Button>
              </div>
            ) : titulares == null ? (
              <Skeleton className="h-14 w-full" aria-busy />
            ) : titulares.length > 0 ? (
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
            ) : null}

            {/* ── Cronograma COMPLETO (reglas finas del portal) ───────────────── */}
            <div>
              <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">{tituloCronograma}</p>
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
                      <b className="tabular-nums text-foreground">{money(totales.pagado, contrato.moneda)}</b> · Por pagar <b className="tabular-nums text-foreground">{money(totales.porPagar, contrato.moneda)}</b>
                    </p>
                  )}
                </>
              )}
            </div>
          </>
        )}
      </DialogBody>
      <DialogFooter>
        {contrato &&
          puedeEliminar &&
          onEliminar &&
          (confirmandoEliminar ? (
            <>
            <Button
              variant="outline"
              size="sm"
              disabled={eliminando} onClick={() => setConfirmandoEliminar(false)}>
                Cancelar eliminación
              </Button>
              <Button variant="destructive" size="sm" disabled={eliminando} onClick={() => void confirmarEliminacion()}>
                {eliminando ? <LoaderCircle className="animate-spin" aria-hidden /> : <Trash2 aria-hidden />}
                Sí, eliminar contrato y PDF
              </Button>
            </>
          ) : (
            <Button
              variant="destructive"
              size="sm"
              disabled={accionPdf != null}
              onClick={() => setConfirmandoEliminar(true)}
            >
              <Trash2 aria-hidden /> Eliminar contrato
            </Button>
          ))}
        {contrato && puedeOperarPdf && (
          <>
            <Button
              variant="outline"
              size="sm"
              disabled={eliminando || accionPdf != null || estadoPdf === 'integridad_bloqueada'}
              onClick={() => void ejecutarPdf('ver')}
            >
              {accionPdf === 'ver'
                ? (
                <LoaderCircle className="animate-spin" aria-hidden />
              ) : (
                <ExternalLink aria-hidden />
              )}
              Ver contrato PDF
            </Button>
            <Button
              size="sm"
              disabled={eliminando || accionPdf != null || estadoPdf === 'integridad_bloqueada'}
              onClick={() => void ejecutarPdf('descargar')}
            >
              {accionPdf === 'descargar'
                ? (
                <LoaderCircle className="animate-spin" aria-hidden />
              ) : (
                <Download aria-hidden />
              )}
              Descargar contrato PDF
            </Button>
          </>
        )}
        <Button variant="outline" size="sm" disabled={eliminando} onClick={onCerrar}>
          Cerrar
        </Button>
      </DialogFooter>
    </>
  )
}
