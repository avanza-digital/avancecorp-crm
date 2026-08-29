import type { ReactNode } from 'react'
import { Landmark } from 'lucide-react'
import { fechaHora, type Moneda } from '@/lib/format'
import { valorCliente, type CuentaClienteVista } from '@/lib/cliente-cuentas-modelo'

export function DatoCliente({
  etiqueta,
  children,
  className = '',
  valueClassName = '',
}: {
  etiqueta: string
  children: ReactNode
  className?: string
  valueClassName?: string
}) {
  return (
    <div className={`min-w-0 ${className}`}>
      <p className="text-[10px] font-extrabold uppercase tracking-widest text-muted-foreground">{etiqueta}</p>
      <p className={`text-sm font-bold text-foreground [overflow-wrap:anywhere] ${valueClassName}`}>{children}</p>
    </div>
  )
}

export function CuentasClienteMoneda({
  moneda,
  cuentas,
  uso,
}: {
  moneda: Moneda
  cuentas: CuentaClienteVista[]
  uso: 'depositos' | 'pagos'
}) {
  const plural = cuentas.length > 1
  const titulo =
    uso === 'pagos'
      ? moneda === 'PEN'
        ? plural
          ? 'Cuentas para recibir pagos en soles'
          : 'Cuenta para recibir pagos en soles'
        : plural
          ? 'Cuentas para recibir pagos en dólares'
          : 'Cuenta para recibir pagos en dólares'
      : moneda === 'PEN'
        ? plural
          ? 'Cuentas para depósitos en soles'
          : 'Cuenta para depósitos en soles'
        : plural
          ? 'Cuentas para depósitos en dólares'
          : 'Cuenta para depósitos en dólares'

  return (
    <section className="rounded-xl border border-border bg-muted/30 p-3" aria-label={titulo}>
      <div className="flex items-center gap-2">
        <Landmark className="size-4 text-primary" aria-hidden />
        <h4 className="text-xs font-bold text-foreground">{titulo}</h4>
      </div>
      {cuentas.length > 0 ? (
        <div className="mt-3 space-y-3" role="list">
          {cuentas.map((cuenta, indice) => (
            <div
              key={cuenta.clave}
              role="listitem"
              aria-label={plural ? `Cuenta ${indice + 1} de ${cuentas.length}` : undefined}
              className="grid grid-cols-2 gap-3 border-t border-border/60 pt-3 first:border-t-0 first:pt-0 sm:grid-cols-4"
            >
              <DatoCliente etiqueta="Banco">{valorCliente(cuenta.banco)}</DatoCliente>
              <DatoCliente etiqueta="Tipo de cuenta">{valorCliente(cuenta.tipoCuenta)}</DatoCliente>
              <DatoCliente etiqueta="N° de cuenta">{valorCliente(cuenta.numeroCuenta)}</DatoCliente>
              <DatoCliente etiqueta="CCI">{valorCliente(cuenta.cci)}</DatoCliente>
              <DatoCliente etiqueta={uso === 'pagos' ? 'La cuenta está a nombre de' : 'Titular de la cuenta'}>
                {uso === 'pagos'
                  ? cuenta.titularDistinto
                    ? 'Otra persona'
                    : 'El cliente'
                  : cuenta.titularDistinto
                    ? 'Beneficiario'
                    : 'Cliente'}
              </DatoCliente>
              {cuenta.titularDistinto && (
                <>
                  <DatoCliente etiqueta={uso === 'pagos' ? 'Nombre del titular' : 'Beneficiario'}>
                    {valorCliente(cuenta.beneficiarioNombre)}
                  </DatoCliente>
                  <DatoCliente etiqueta={uso === 'pagos' ? 'Documento del titular' : 'Documento del beneficiario'}>
                    {valorCliente(cuenta.beneficiarioDni)}
                  </DatoCliente>
                </>
              )}
              {cuenta.registradaEn != null && (
                <DatoCliente etiqueta="Registrada el">{fechaHora(cuenta.registradaEn)}</DatoCliente>
              )}
            </div>
          ))}
        </div>
      ) : (
        <p className="mt-2 text-xs text-muted-foreground">No registró una cuenta en esta moneda.</p>
      )}
    </section>
  )
}
