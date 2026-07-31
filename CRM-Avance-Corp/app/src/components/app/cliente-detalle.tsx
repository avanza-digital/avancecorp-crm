// Detalle SOLO LECTURA del cliente desde Mi cartera. Reusa la misma consulta
// completa que "Corregir", pero NO queda atada a la ventana de 5 horas: esa
// ventana solo limita escrituras. La RLS de public.perfiles sigue siendo la
// autoridad y devuelve cero filas fuera de la cartera del analista.
import { useEffect, useState, type ReactNode } from 'react'
import { Landmark, RotateCcw, UserRound, WifiOff } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { mensajeDeError } from '@/data/crm-api'
import { useClienteDetalle } from '@/data/crm-queries'
import { TIPOS_DOCUMENTO } from '@/lib/documento'
import { fechaHora } from '@/lib/format'
import type { ClienteDetalle as ClienteDetalleDatos } from '@/lib/clientes-tipos'

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

function CuentaBancaria({
  moneda,
  banco,
  tipoCuenta,
  numeroCuenta,
  cci,
  titularDistinto,
  beneficiarioNombre,
  beneficiarioDni,
}: {
  moneda: 'PEN' | 'USD'
  banco: string | null
  tipoCuenta: string | null
  numeroCuenta: string | null
  cci: string | null
  titularDistinto: boolean
  beneficiarioNombre: string | null
  beneficiarioDni: string | null
}) {
  const tieneCuenta = [banco, tipoCuenta, numeroCuenta, cci].some((dato) => dato?.trim())
  const titulo = moneda === 'PEN' ? 'Cuenta para depósitos en soles' : 'Cuenta para depósitos en dólares'

  return (
    <section className="rounded-xl border border-border bg-muted/30 p-3" aria-label={titulo}>
      <div className="flex items-center gap-2">
        <Landmark className="size-4 text-primary" aria-hidden />
        <h3 className="text-xs font-bold text-foreground">{titulo}</h3>
      </div>
      {tieneCuenta ? (
        <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Dato etiqueta="Banco">{valor(banco)}</Dato>
          <Dato etiqueta="Tipo de cuenta">{valor(tipoCuenta)}</Dato>
          <Dato etiqueta="N° de cuenta">{valor(numeroCuenta)}</Dato>
          <Dato etiqueta="CCI">{valor(cci)}</Dato>
          <Dato etiqueta="Titular de la cuenta">{titularDistinto ? 'Beneficiario' : 'Cliente'}</Dato>
          {titularDistinto && (
            <>
              <Dato etiqueta="Beneficiario">{valor(beneficiarioNombre)}</Dato>
              <Dato etiqueta="Documento del beneficiario">{valor(beneficiarioDni)}</Dato>
            </>
          )}
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

/**
 * Ficha completa del perfil del cliente: identidad, contacto y sus dos cuentas
 * de depósito. Está hecha para consulta comercial; nunca ofrece edición.
 */
export function ClienteDetalle({ clienteId, onCerrar, datos }: ClienteDetalleProps) {
  const precargado = datos !== undefined
  const qDetalle = useClienteDetalle(clienteId, !precargado)

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

  const detalle = datos !== undefined
    ? datos
    : confirmado?.clienteId === clienteId
      ? confirmado.datos
      : null
  const error = !precargado && qDetalle.isError
    ? mensajeDeError(qDetalle.error, 'No se pudo cargar el detalle del cliente.')
    : null

  const reintentar = () => {
    // No dejar que una copia confirmada antes de un error reaparezca mientras
    // el nuevo intento está en vuelo.
    setConfirmado(null)
    void qDetalle.refetch()
  }

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
                <Dato etiqueta="Nombres">{valor(detalle.nombres)}</Dato>
                <Dato etiqueta="Apellidos">{valor(detalle.apellidos)}</Dato>
                <Dato etiqueta={TIPOS_DOCUMENTO[detalle.tipo_documento].etiqueta}>{valor(detalle.dni)}</Dato>
                <Dato etiqueta="Correo">{valor(detalle.correo)}</Dato>
                <Dato etiqueta="Teléfono">{valor(detalle.telefono)}</Dato>
                <Dato etiqueta="Registrado el">{fechaHora(detalle.creado_en)}</Dato>
              </div>
            </section>

            <section>
              <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Datos bancarios</h3>
              <div className="mt-2 space-y-3">
                <CuentaBancaria
                  moneda="PEN"
                  banco={detalle.banco}
                  tipoCuenta={detalle.tipo_cuenta}
                  numeroCuenta={detalle.numero_cuenta}
                  cci={detalle.cci}
                  titularDistinto={detalle.titular_distinto}
                  beneficiarioNombre={detalle.beneficiario_nombre}
                  beneficiarioDni={detalle.beneficiario_dni}
                />
                <CuentaBancaria
                  moneda="USD"
                  banco={detalle.banco_usd}
                  tipoCuenta={detalle.tipo_cuenta_usd}
                  numeroCuenta={detalle.numero_cuenta_usd}
                  cci={detalle.cci_usd}
                  titularDistinto={detalle.titular_distinto_usd}
                  beneficiarioNombre={detalle.beneficiario_nombre_usd}
                  beneficiarioDni={detalle.beneficiario_dni_usd}
                />
              </div>
            </section>
          </>
        )}
      </DialogBody>

      <DialogFooter>
        <Button type="button" variant="outline" onClick={onCerrar}>Cerrar</Button>
      </DialogFooter>
    </>
  )
}
