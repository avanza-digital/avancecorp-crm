// Detalle SOLO LECTURA del cliente desde Mi cartera. La frontera autorizada es
// `crm.cliente_detalle_fn`: devuelve cero filas fuera del ámbito y separa banca
// embebida del permiso para consultar el ledger. La ventana de 5 h solo limita
// escrituras y no participa en esta lectura.
import { useEffect, useState } from 'react'
import { History, RotateCcw, UserRound, WifiOff } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { SegundoNumero } from '@/components/app/segundo-numero'
import {
  CuentasClienteMoneda,
  DatoCliente as Dato,
} from '@/components/app/cliente-cuentas-vista'
import {
  cuentaClienteDesdeRpc,
  cuentasClienteEmbebidas,
  valorCliente as valor,
  type CuentaClienteVista,
} from '@/lib/cliente-cuentas-modelo'
import { mensajeDeError } from '@/data/crm-api'
import {
  useActividadesCliente,
  useClienteDetalle,
  useCuentasBancariasCliente,
  useSegundoNumeroCliente,
} from '@/data/crm-queries'
import { TIPOS_DOCUMENTO } from '@/lib/documento'
import { fechaHora } from '@/lib/format'
import type { ClienteDetalle as ClienteDetalleDatos } from '@/lib/clientes-tipos'
import { presentarCitas } from '@/lib/terminologia'

export interface ClienteDetalleProps {
  clienteId: string
  onCerrar: () => void
  /** Fixture completo para la sesión demo. Deshabilita la consulta remota. */
  datos?: ClienteDetalleDatos
}

const ACTIVIDAD_LABEL = {
  llamada_realizada: 'Llamada contestada',
  llamada_no_contestada: 'Llamada no contestada',
  whatsapp_enviado: 'WhatsApp enviado',
  whatsapp_recibido: 'WhatsApp respondido',
  reunion_realizada: 'Cita realizada',
  nota: 'Nota comercial',
  reasignacion: 'Asignación actualizada',
} as const

/**
 * Ficha comercial del cliente. Identidad y contacto siguen el ámbito CRM; las
 * cuentas solo se solicitan cuando `cliente_detalle_fn` confirma la capacidad
 * bancaria. Está hecha para consulta; nunca ofrece edición.
 */
export function ClienteDetalle({ clienteId, onCerrar, datos }: ClienteDetalleProps) {
  const precargado = datos !== undefined
  const qDetalle = useClienteDetalle(clienteId, !precargado)
  // El 2.º número vive en el LEAD que originó a este cliente, no en su perfil:
  // `public.perfiles` la comparte el portal y duplicar el dato es como acaban
  // divergiendo. Fail-closed en demo, igual que el resto de consultas de aquí.
  const qSegundo = useSegundoNumeroCliente(clienteId, !precargado)
  // Las cuentas salen del ledger crm.cuentas_bancarias. La RPC de detalle
  // también devuelve el último registro activo por moneda desde ese ledger;
  // las columnas bancarias de public.perfiles no son fuente de lectura.
  // La confirmación debe ser posterior al mount: una copia cacheada de una
  // sesión/capacidad anterior no puede disparar una consulta bancaria.
  const ledgerRemotoHabilitado =
    !precargado &&
    qDetalle.isSuccess &&
    !qDetalle.isFetching &&
    qDetalle.isFetchedAfterMount &&
    qDetalle.data.cuentas_bancarias_visibles
  const qPen = useCuentasBancariasCliente(clienteId, 'PEN', ledgerRemotoHabilitado)
  const qUsd = useCuentasBancariasCliente(clienteId, 'USD', ledgerRemotoHabilitado)
  const qActividades = useActividadesCliente(clienteId, !precargado)

  // El detalle contiene cuentas bancarias: en una sesión REAL nunca se pinta la
  // copia que React Query pudiera conservar de una apertura anterior. Solo se
  // acepta una respuesta terminada DESPUÉS de montar esta ficha. Si ese refresh
  // falla, se descarta incluso la última respuesta confirmada en este montaje y
  // la UI queda cerrada al dato hasta que Reintentar obtenga una copia fresca.
  // En DEMO `datos` es la fuente completa y la query está deshabilitada.
  const [confirmado, setConfirmado] = useState<{
    clienteId: string
    datos: ClienteDetalleDatos
  } | null>(null)

  useEffect(() => {
    if (precargado || !qDetalle.isSuccess || qDetalle.isFetching || !qDetalle.isFetchedAfterMount) return
    setConfirmado({ clienteId, datos: qDetalle.data })
  }, [clienteId, precargado, qDetalle.isSuccess, qDetalle.isFetching, qDetalle.isFetchedAfterMount, qDetalle.data])

  useEffect(() => {
    if (!precargado && qDetalle.isError) setConfirmado(null)
  }, [precargado, qDetalle.isError])

  // Misma disciplina que la ficha para las CUENTAS: solo se pintan copias
  // confirmadas DESPUÉS de montar (nunca una caché de otra apertura) y un
  // fallo las oculta hasta que Reintentar traiga una fotografía fresca.
  // Limitación aceptada (auditoría Codex 2026-08-11): PEN y USD son dos RPC
  // independientes, no una fotografía transaccional — una corrección concurrente
  // entre ambas respuestas puede mezclar monedas de dos versiones. Ventana de
  // milisegundos y ambas copias post-montaje; unificar exigiría una RPC conjunta.
  const [cuentasConfirmadas, setCuentasConfirmadas] = useState<{
    clienteId: string
    pen: CuentaClienteVista[]
    usd: CuentaClienteVista[]
  } | null>(null)

  useEffect(() => {
    if (precargado || !ledgerRemotoHabilitado) return
    if (!qPen.isSuccess || qPen.isFetching || !qPen.isFetchedAfterMount) return
    if (!qUsd.isSuccess || qUsd.isFetching || !qUsd.isFetchedAfterMount) return
    setCuentasConfirmadas({
      clienteId,
      pen: qPen.data.map(cuentaClienteDesdeRpc),
      usd: qUsd.data.map(cuentaClienteDesdeRpc),
    })
  }, [
    clienteId,
    precargado,
    ledgerRemotoHabilitado,
    qPen.isSuccess,
    qPen.isFetching,
    qPen.isFetchedAfterMount,
    qPen.data,
    qUsd.isSuccess,
    qUsd.isFetching,
    qUsd.isFetchedAfterMount,
    qUsd.data,
  ])

  useEffect(() => {
    if (!precargado && (qPen.isError || qUsd.isError)) setCuentasConfirmadas(null)
  }, [precargado, qPen.isError, qUsd.isError])

  const detalle = datos !== undefined ? datos : confirmado?.clienteId === clienteId ? confirmado.datos : null
  const error =
    !precargado && qDetalle.isError ? mensajeDeError(qDetalle.error, 'No se pudo cargar el detalle del cliente.') : null

  const reintentar = () => {
    // No dejar que una copia confirmada antes de un error reaparezca mientras
    // el nuevo intento está en vuelo.
    setConfirmado(null)
    void qDetalle.refetch()
  }

  const cuentasPen =
    detalle?.banca_visible !== true
      ? null
      : datos !== undefined || detalle.cuentas_bancarias_visibles !== true
        ? cuentasClienteEmbebidas(detalle, 'PEN')
        : cuentasConfirmadas?.clienteId === clienteId
          ? cuentasConfirmadas.pen
          : null
  const cuentasUsd =
    detalle?.banca_visible !== true
      ? null
      : datos !== undefined || detalle.cuentas_bancarias_visibles !== true
        ? cuentasClienteEmbebidas(detalle, 'USD')
        : cuentasConfirmadas?.clienteId === clienteId
          ? cuentasConfirmadas.usd
          : null
  // El fallo de las cuentas degrada SOLO su sección (identidad y contacto
  // siguen visibles): vienen de consultas distintas y un fallo operativo del
  // lado bancario (red, RPC, permisos si el gating de fila cambiara) no debe
  // secuestrar una ficha cuya identidad ya está confirmada.
  const cuentasError =
    ledgerRemotoHabilitado && (qPen.isError || qUsd.isError)
      ? mensajeDeError(qPen.error ?? qUsd.error, 'No se pudieron cargar las cuentas bancarias.')
      : null
  // Con el reintento EN VUELO se muestra la carga, no el alert: así el usuario
  // ve que algo pasa y, si vuelve a fallar, el alert se re-monta y el lector de
  // pantalla lo re-anuncia (un role="alert" que no cambia no se vuelve a leer).
  const cuentasReintentando =
    ledgerRemotoHabilitado &&
    (qPen.isError || qUsd.isError) &&
    (qPen.isFetching || qUsd.isFetching)
  const reintentarCuentas = () => {
    setCuentasConfirmadas(null)
    void qPen.refetch()
    void qUsd.refetch()
  }

  // Clientes migrados ANTES de separar nombres/apellidos: solo tienen
  // nombre_completo (mismo criterio esLegacySinSeparar del form de corregir).
  // Sin esto, la ficha mostraba «—» en Nombres y Apellidos con el nombre a la vista.
  const sinSeparar =
    detalle != null && !detalle.nombres?.trim() && !detalle.apellidos?.trim() && detalle.nombre_completo.trim() !== ''

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          <UserRound className="size-4 text-primary" aria-hidden />
          {detalle?.nombre_completo || 'Detalle del cliente'}
        </DialogTitle>
        <DialogDescription>
          Consulta de solo lectura — disponible aun cuando la ventana de corrección haya vencido.
        </DialogDescription>
      </DialogHeader>

      <DialogBody className="max-h-[65vh] space-y-4 overflow-y-auto">
        {error ? (
          <div className="flex flex-col items-center justify-center gap-3 py-10 text-center" role="alert">
            <span className="grid size-11 place-items-center rounded-2xl bg-destructive/10 text-destructive">
              <WifiOff className="size-5" aria-hidden />
            </span>
            <p className="text-sm font-semibold text-foreground">{error}</p>
            <Button variant="outline" size="sm" onClick={reintentar}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          </div>
        ) : !detalle ? (
          <div className="space-y-2" aria-busy>
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-40 w-full" />
          </div>
        ) : (
          <>
            <section>
              <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Datos personales</h3>
              <div className="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-3">
                {sinSeparar ? (
                  <Dato etiqueta="Nombres y apellidos">{valor(detalle.nombre_completo)}</Dato>
                ) : (
                  <>
                    <Dato etiqueta="Nombres">{valor(detalle.nombres)}</Dato>
                    <Dato etiqueta="Apellidos">{valor(detalle.apellidos)}</Dato>
                  </>
                )}
                <Dato etiqueta={TIPOS_DOCUMENTO[detalle.tipo_documento].etiqueta}>{valor(detalle.dni)}</Dato>
                <Dato etiqueta="Correo">{valor(detalle.correo)}</Dato>
                <Dato etiqueta="Teléfono">{valor(detalle.telefono)}</Dato>
                {/*
                  Solo se dibuja cuando HAY lead que mirar. Sin lead no se puede
                  decir «el origen no dio un segundo número» —no lo sabemos— y
                  afirmarlo sería inventar. Los cierres en cooperativa caen aquí:
                  no crean cliente de Avance, así que no tienen lead enlazado.
                */}
                {qSegundo.data && (
                  <Dato etiqueta="Teléfono alternativo">
                    <SegundoNumero
                      numero={qSegundo.data.telefono_alternativo}
                      crudo={qSegundo.data.telefono_alternativo_crudo}
                    />
                  </Dato>
                )}
                <Dato etiqueta="Domicilio legal">{valor(detalle.domicilio)}</Dato>
                <Dato etiqueta="Registrado el">{fechaHora(detalle.creado_en)}</Dato>
              </div>
            </section>

            <section>
              <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Datos bancarios</h3>
              {!detalle.banca_visible ? (
                <div className="mt-2 rounded-xl border border-border bg-muted/30 px-4 py-3">
                  <p className="text-xs font-semibold text-foreground">Información bancaria restringida</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    Tu acceso permite consultar la ficha comercial, pero no números de cuenta, CCI ni beneficiarios.
                  </p>
                </div>
              ) : cuentasError && !cuentasReintentando ? (
                <div
                  className="mt-2 flex flex-col items-center justify-center gap-3 rounded-xl border border-border bg-muted/30 p-4 text-center"
                  role="alert"
                >
                  <p className="text-sm font-semibold text-foreground">{cuentasError}</p>
                  <Button type="button" variant="outline" size="sm" onClick={reintentarCuentas}>
                    <RotateCcw aria-hidden /> Reintentar
                  </Button>
                </div>
              ) : cuentasPen == null || cuentasUsd == null || cuentasReintentando ? (
                <div className="mt-2 space-y-3" aria-busy>
                  <span className="sr-only">Cargando cuentas bancarias</span>
                  <Skeleton className="h-24 w-full" />
                  <Skeleton className="h-24 w-full" />
                </div>
              ) : (
                <div className="mt-2 space-y-3">
                  <CuentasClienteMoneda moneda="PEN" cuentas={cuentasPen} uso="depositos" />
                  <CuentasClienteMoneda moneda="USD" cuentas={cuentasUsd} uso="depositos" />
                </div>
              )}
            </section>

            <section aria-labelledby="cliente-historial-comercial">
              <h3
                id="cliente-historial-comercial"
                className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wide text-muted-foreground"
              >
                <History className="size-4 text-primary" aria-hidden /> Historial comercial
              </h3>
              {precargado ? (
                <p className="mt-2 text-xs text-muted-foreground">
                  El historial postventa se muestra en la cuenta real.
                </p>
              ) : qActividades.isPending ? (
                <div className="mt-2 space-y-2" aria-busy>
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                </div>
              ) : qActividades.isError ? (
                <div
                  className="mt-2 flex items-center justify-between gap-3 rounded-xl border border-border bg-muted/30 p-3"
                  role="alert"
                >
                  <p className="text-xs font-semibold text-foreground">No se pudo cargar el historial comercial.</p>
                  <Button type="button" variant="outline" size="sm" onClick={() => void qActividades.refetch()}>
                    <RotateCcw aria-hidden /> Reintentar
                  </Button>
                </div>
              ) : qActividades.data.length === 0 ? (
                <p className="mt-2 rounded-xl border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">
                  Aún no hay gestiones cerradas. Las llamadas, WhatsApp y citas completadas aparecerán aquí.
                </p>
              ) : (
                <ol className="mt-2 space-y-2">
                  {qActividades.data.map((actividad) => (
                    <li key={actividad.id} className="rounded-xl border border-border bg-muted/20 px-3 py-2.5">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <p className="text-xs font-bold text-foreground">{ACTIVIDAD_LABEL[actividad.tipo]}</p>
                        <time className="text-[11px] tabular-nums text-muted-foreground" dateTime={actividad.creado_en}>
                          {fechaHora(actividad.creado_en)}
                        </time>
                      </div>
                      {actividad.detalle && (
                        <p className="mt-1 whitespace-pre-wrap text-xs text-muted-foreground">
                          {presentarCitas(actividad.detalle)}
                        </p>
                      )}
                    </li>
                  ))}
                </ol>
              )}
            </section>
          </>
        )}
      </DialogBody>

      <DialogFooter>
        <Button type="button" variant="outline" onClick={onCerrar}>
          Cerrar
        </Button>
      </DialogFooter>
    </>
  )
}
