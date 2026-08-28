// Detalle SOLO LECTURA del cliente desde Mi cartera. Reusa la misma consulta
// completa que "Corregir", pero NO queda atada a la ventana de 5 horas: esa
// ventana solo limita escrituras. La RLS de public.perfiles sigue siendo la
// autoridad y devuelve cero filas fuera de la cartera del analista.
import { useEffect, useState, type ReactNode } from 'react'
import { History, Landmark, RotateCcw, UserRound, WifiOff } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { mensajeDeError } from '@/data/crm-api'
import { useActividadesCliente, useClienteDetalle, useCuentasBancariasCliente } from '@/data/crm-queries'
import { TIPOS_DOCUMENTO } from '@/lib/documento'
import { fechaHora, type Moneda } from '@/lib/format'
import type { ClienteDetalle as ClienteDetalleDatos, CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'
import { presentarCitas } from '@/lib/terminologia'

function Dato({ etiqueta, children }: { etiqueta: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <p className="text-[10px] font-extrabold uppercase tracking-widest text-muted-foreground">{etiqueta}</p>
      <p className="text-sm font-bold text-foreground [overflow-wrap:anywhere]">{children}</p>
    </div>
  )
}

function valor(valor: string | null): string {
  return valor?.trim() || '—'
}

/**
 * Vista unificada de una cuenta de depósito, venga del ledger
 * `crm.cuentas_bancarias` (vía RPC) o de las columnas embebidas del perfil
 * (solo demo/precarga). Un solo shape → un solo render.
 */
interface CuentaVista {
  clave: string
  banco: string | null
  tipoCuenta: string | null
  numeroCuenta: string | null
  cci: string | null
  titularDistinto: boolean
  beneficiarioNombre: string | null
  beneficiarioDni: string | null
  /** null = casilla vigente del perfil (no tiene fecha de registro propia). */
  registradaEn: string | null
}

function cuentaDesdeRpc(cuenta: CuentaBancariaSeleccionable): CuentaVista {
  return {
    clave: cuenta.cuenta_id ?? `perfil-${cuenta.moneda}`,
    banco: cuenta.banco,
    tipoCuenta: cuenta.tipo_cuenta,
    numeroCuenta: cuenta.numero_cuenta,
    cci: cuenta.cci,
    titularDistinto: cuenta.titular_distinto,
    beneficiarioNombre: cuenta.beneficiario_nombre,
    beneficiarioDni: cuenta.beneficiario_dni,
    registradaEn: cuenta.creada_en,
  }
}

/**
 * Demo/precarga: el fixture trae solo las 2 casillas embebidas del perfil
 * (modelo viejo). Se adaptan a la vista común; sin red no hay ledger que mirar.
 */
function cuentasEmbebidas(detalle: ClienteDetalleDatos, moneda: Moneda): CuentaVista[] {
  const c =
    moneda === 'USD'
      ? {
          banco: detalle.banco_usd,
          tipoCuenta: detalle.tipo_cuenta_usd,
          numeroCuenta: detalle.numero_cuenta_usd,
          cci: detalle.cci_usd,
          titularDistinto: detalle.titular_distinto_usd,
          beneficiarioNombre: detalle.beneficiario_nombre_usd,
          beneficiarioDni: detalle.beneficiario_dni_usd,
        }
      : {
          banco: detalle.banco,
          tipoCuenta: detalle.tipo_cuenta,
          numeroCuenta: detalle.numero_cuenta,
          cci: detalle.cci,
          titularDistinto: detalle.titular_distinto,
          beneficiarioNombre: detalle.beneficiario_nombre,
          beneficiarioDni: detalle.beneficiario_dni,
        }
  const tieneCuenta = [c.banco, c.tipoCuenta, c.numeroCuenta, c.cci].some((dato) => dato?.trim())
  return tieneCuenta ? [{ clave: `perfil-${moneda}`, ...c, registradaEn: null }] : []
}

function CuentasMoneda({ moneda, cuentas }: { moneda: Moneda; cuentas: CuentaVista[] }) {
  const titulo =
    moneda === 'PEN'
      ? cuentas.length > 1
        ? 'Cuentas para depósitos en soles'
        : 'Cuenta para depósitos en soles'
      : cuentas.length > 1
        ? 'Cuentas para depósitos en dólares'
        : 'Cuenta para depósitos en dólares'

  return (
    <section className="rounded-xl border border-border bg-muted/30 p-3" aria-label={titulo}>
      <div className="flex items-center gap-2">
        <Landmark className="size-4 text-primary" aria-hidden />
        {/* h4: subsección de "Datos bancarios" (h3) — el outline del diálogo lo refleja. */}
        <h4 className="text-xs font-bold text-foreground">{titulo}</h4>
      </div>
      {cuentas.length > 0 ? (
        // div role="list" (patrón de mi-cartera): semántica de lista explícita
        // que el preflight de Tailwind no puede degradar en VoiceOver.
        <div className="mt-3 space-y-3" role="list">
          {cuentas.map((cuenta, indice) => (
            <div
              key={cuenta.clave}
              role="listitem"
              aria-label={cuentas.length > 1 ? `Cuenta ${indice + 1} de ${cuentas.length}` : undefined}
              className="grid grid-cols-2 gap-3 border-t border-border/60 pt-3 first:border-t-0 first:pt-0 sm:grid-cols-4"
            >
              <Dato etiqueta="Banco">{valor(cuenta.banco)}</Dato>
              <Dato etiqueta="Tipo de cuenta">{valor(cuenta.tipoCuenta)}</Dato>
              <Dato etiqueta="N° de cuenta">{valor(cuenta.numeroCuenta)}</Dato>
              <Dato etiqueta="CCI">{valor(cuenta.cci)}</Dato>
              <Dato etiqueta="Titular de la cuenta">{cuenta.titularDistinto ? 'Beneficiario' : 'Cliente'}</Dato>
              {cuenta.titularDistinto && (
                <>
                  <Dato etiqueta="Beneficiario">{valor(cuenta.beneficiarioNombre)}</Dato>
                  <Dato etiqueta="Documento del beneficiario">{valor(cuenta.beneficiarioDni)}</Dato>
                </>
              )}
              {cuenta.registradaEn != null && <Dato etiqueta="Registrada el">{fechaHora(cuenta.registradaEn)}</Dato>}
            </div>
          ))}
        </div>
      ) : (
        <p className="mt-2 text-xs text-muted-foreground">No registró una cuenta en esta moneda.</p>
      )}
    </section>
  )
}

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
} as const

/**
 * Ficha completa del perfil del cliente: identidad, contacto y TODAS sus
 * cuentas de depósito vigentes (ledger crm.cuentas_bancarias + casilla del
 * perfil). Está hecha para consulta comercial; nunca ofrece edición.
 */
export function ClienteDetalle({ clienteId, onCerrar, datos }: ClienteDetalleProps) {
  const precargado = datos !== undefined
  const qDetalle = useClienteDetalle(clienteId, !precargado)
  // Las cuentas salen de la MISMA RPC del flujo de contrato (ledger
  // crm.cuentas_bancarias + casilla vigente del perfil, deduplicados por el
  // servidor): es la única fuente que incluye las cuentas registradas AL CREAR
  // un contrato — leer solo las columnas embebidas de perfiles las escondía.
  const qPen = useCuentasBancariasCliente(clienteId, 'PEN', !precargado)
  const qUsd = useCuentasBancariasCliente(clienteId, 'USD', !precargado)
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
    pen: CuentaVista[]
    usd: CuentaVista[]
  } | null>(null)

  useEffect(() => {
    if (precargado) return
    if (!qPen.isSuccess || qPen.isFetching || !qPen.isFetchedAfterMount) return
    if (!qUsd.isSuccess || qUsd.isFetching || !qUsd.isFetchedAfterMount) return
    setCuentasConfirmadas({
      clienteId,
      pen: qPen.data.map(cuentaDesdeRpc),
      usd: qUsd.data.map(cuentaDesdeRpc),
    })
  }, [
    clienteId,
    precargado,
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
    datos !== undefined
      ? cuentasEmbebidas(datos, 'PEN')
      : cuentasConfirmadas?.clienteId === clienteId
        ? cuentasConfirmadas.pen
        : null
  const cuentasUsd =
    datos !== undefined
      ? cuentasEmbebidas(datos, 'USD')
      : cuentasConfirmadas?.clienteId === clienteId
        ? cuentasConfirmadas.usd
        : null
  // El fallo de las cuentas degrada SOLO su sección (identidad y contacto
  // siguen visibles): vienen de consultas distintas y un fallo operativo del
  // lado bancario (red, RPC, permisos si el gating de fila cambiara) no debe
  // secuestrar una ficha cuya identidad ya está confirmada.
  const cuentasError =
    !precargado && (qPen.isError || qUsd.isError)
      ? mensajeDeError(qPen.error ?? qUsd.error, 'No se pudieron cargar las cuentas bancarias.')
      : null
  // Con el reintento EN VUELO se muestra la carga, no el alert: así el usuario
  // ve que algo pasa y, si vuelve a fallar, el alert se re-monta y el lector de
  // pantalla lo re-anuncia (un role="alert" que no cambia no se vuelve a leer).
  const cuentasReintentando = !precargado && (qPen.isError || qUsd.isError) && (qPen.isFetching || qUsd.isFetching)
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
                <Dato etiqueta="Domicilio legal">{valor(detalle.domicilio)}</Dato>
                <Dato etiqueta="Registrado el">{fechaHora(detalle.creado_en)}</Dato>
              </div>
            </section>

            <section>
              <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Datos bancarios</h3>
              {cuentasError && !cuentasReintentando ? (
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
                  <CuentasMoneda moneda="PEN" cuentas={cuentasPen} />
                  <CuentasMoneda moneda="USD" cuentas={cuentasUsd} />
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
