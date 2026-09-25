import { useEffect, useState, type ReactNode } from 'react'
import { Check, Copy, Landmark } from 'lucide-react'
import { toast } from 'sonner'
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
      <p className="text-[11px] font-extrabold uppercase tracking-wider text-muted-foreground">{etiqueta}</p>
      <p className={`text-sm font-bold text-foreground [overflow-wrap:anywhere] ${valueClassName}`}>{children}</p>
    </div>
  )
}

/** Identificador de lectura exacta: no lo parte y ofrece copia explícita. */
export function DatoClienteCopiable({
  etiqueta,
  valor,
  className = '',
  monoespaciado = false,
  enmascarado = false,
}: {
  etiqueta: string
  valor: string | null | undefined
  className?: string
  monoespaciado?: boolean
  enmascarado?: boolean
}) {
  const [copiado, setCopiado] = useState(false)
  const texto = enmascarado && valor?.trim()
    ? `••••${valor.trim().slice(-4)}`
    : valorCliente(valor ?? null)
  const valorCopiable = valor?.trim() ?? ''
  const sePuedeCopiar = valorCopiable !== ''

  useEffect(() => setCopiado(false), [valorCopiable])

  const copiar = async () => {
    if (!sePuedeCopiar) return
    try {
      await navigator.clipboard.writeText(valorCopiable)
      setCopiado(true)
    } catch {
      toast.error(`No se pudo copiar ${etiqueta.toLowerCase()}.`)
    }
  }

  return (
    <div className={`min-w-0 ${className}`}>
      <p className="text-[11px] font-extrabold uppercase tracking-wider text-muted-foreground">{etiqueta}</p>
      <div className="mt-0.5 flex min-h-10 min-w-0 items-center gap-1 rounded-lg border border-border/60 bg-card px-2">
        <span
          className={`min-w-0 flex-1 overflow-x-auto whitespace-nowrap text-[13px] font-bold text-foreground [scrollbar-width:none] [&::-webkit-scrollbar]:hidden ${
            monoespaciado ? 'font-mono tabular-nums tracking-tight' : ''
          }`}
          title={texto}
        >
          {texto}
        </span>
        {sePuedeCopiar && (
          <button
            type="button"
            onClick={() => void copiar()}
            aria-label={copiado ? `${etiqueta} copiado` : `Copiar ${etiqueta.toLowerCase()}`}
            className="grid size-10 shrink-0 place-items-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35"
          >
            {copiado ? <Check className="size-4 text-primary" aria-hidden /> : <Copy className="size-4" aria-hidden />}
          </button>
        )}
      </div>
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
              <DatoClienteCopiable
                etiqueta="N° de cuenta"
                valor={cuenta.numeroCuenta}
                className="col-span-2"
                monoespaciado
                enmascarado
              />
              <DatoClienteCopiable etiqueta="CCI" valor={cuenta.cci} className="col-span-2" monoespaciado enmascarado />
              {cuenta.origen && (
                <DatoCliente etiqueta="Origen">{{ perfil: 'Perfil migrado', contrato: 'CRM / contrato', portal: 'Ficha de cliente' }[cuenta.origen]}</DatoCliente>
              )}
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
