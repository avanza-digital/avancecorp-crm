// Modal de alta de lead (F1b) — se monta UNA vez en App.tsx y se abre con
// usePanelesActions().abrirNuevoLead(etapa?). Todo demo: crearLead() vive en el store
// (memoria + sessionStorage), jamás Supabase. Doble defensa de escritura: este
// componente ni se renderiza para roles de solo lectura (directorio) y el
// store re-valida cada mutación por su cuenta. El formulario vive DENTRO del
// Dialog (que desmonta al cerrar), así que se resetea solo al reabrirse.
import { useState, type FormEvent, type ReactNode } from 'react'
import { toast } from 'sonner'
import { UserRoundPlus } from 'lucide-react'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { useAuth } from '@/lib/auth-context'
import { can, puedeEscribir } from '@/lib/roles'
import { useCRMData, usePanelesActions, usePanelesState } from '@/lib/store-context'
import { normalizarTelefono } from '@/lib/validacion'
import {
  CATEGORIAS_INTERES,
  ETAPA_INFO,
  ORIGENES,
  esOrigen,
  type CategoriaInteres,
  type Origen,
} from '@/lib/tipos'
import { SIMBOLO, type Moneda } from '@/lib/format'
import { cn } from '@/lib/utils'

const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/** Clases de estado inválido para Input/Select (borde + ring destructive). */
const claseError =
  'border-destructive focus-visible:border-destructive focus-visible:ring-destructive/25'

/** Etiqueta + control + mensaje de error inline (bajo el campo). */
function Campo({
  label,
  htmlFor,
  requerido = false,
  error,
  children,
}: {
  label: string
  htmlFor?: string | undefined
  requerido?: boolean | undefined
  error?: string | undefined
  children: ReactNode
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor}>
        {label}
        {requerido && (
          <span aria-hidden className="text-destructive">
            {' '}
            *
          </span>
        )}
      </Label>
      {children}
      {error && (
        <p role="alert" className="text-[11px] font-medium text-destructive">
          {error}
        </p>
      )}
    </div>
  )
}

export function LeadNuevo() {
  const { nuevoLeadAbierto } = usePanelesState()
  const { cerrarPaneles } = usePanelesActions()
  const { yo } = useAuth()

  // Guard interno (además del gate externo): directorio jamás ve este modal.
  if (!puedeEscribir(yo?.rol)) return null

  return (
    <Dialog open={nuevoLeadAbierto} onClose={cerrarPaneles} ariaLabel="Nuevo lead">
      <FormularioNuevoLead />
    </Dialog>
  )
}

/** Estado y campos del alta. Montado solo mientras el Dialog está abierto. */
function FormularioNuevoLead() {
  const { etapaInicial } = usePanelesState()
  const { ambito, crearLead } = useCRMData()
  const { abrirLead, cerrarPaneles } = usePanelesActions()
  const { yo } = useAuth()

  const puedeElegirVendedor = can(yo?.rol, 'reasignar')
  // SOLO vendedores del ámbito del rol (espejo del WITH CHECK de leads_insert):
  // supervisor solo puede crear leads asignados dentro de SU equipo.
  const vendedores = ambito.vendedores.filter((m) => m.rol_crm === 'vendedor' && m.activo)
  const etapa = ETAPA_INFO[etapaInicial]

  const [nombre, setNombre] = useState('')
  const [telefono, setTelefono] = useState('')
  const [correo, setCorreo] = useState('')
  const [dni, setDni] = useState('')
  const [distrito, setDistrito] = useState('')
  // '' = placeholder "Selecciona…" aún sin elegir; la validación exige un Origen real.
  const [origen, setOrigen] = useState<Origen | ''>('')
  const [monto, setMonto] = useState('')
  const [moneda, setMoneda] = useState<Moneda>('PEN')
  const [categoria, setCategoria] = useState<CategoriaInteres | null>(null)
  const [vendedorId, setVendedorId] = useState('')
  const [nota, setNota] = useState('')
  const [errores, setErrores] = useState<Record<string, string>>({})
  const [errorGeneral, setErrorGeneral] = useState<string | null>(null)

  /** Al corregir un campo, su error inline (y el general) desaparecen. */
  const limpiarError = (campo: string) => {
    setErrorGeneral(null)
    setErrores((e) => {
      if (!(campo in e)) return e
      const { [campo]: _omitido, ...resto } = e
      return resto
    })
  }

  /** CampoLead del store → clave del estado local de errores del formulario. */
  const CAMPO_UI: Record<string, string> = {
    nombre_completo: 'nombre',
    telefono: 'telefono',
    dni: 'dni',
    correo: 'correo',
    origen: 'origen',
    monto_estimado: 'monto',
  }

  const enviar = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const err: Record<string, string> = {}
    if (!nombre.trim()) err.nombre = 'El nombre es obligatorio'
    if (!normalizarTelefono(telefono)) {
      err.telefono = 'Celular peruano inválido — ej.: 987 654 321 o +51 987 654 321'
    }
    if (correo.trim() && !CORREO_RE.test(correo.trim())) err.correo = 'Correo inválido'
    if (dni.trim() && !/^\d{8}$/.test(dni.trim())) {
      err.dni = 'El DNI debe tener exactamente 8 dígitos'
    }
    if (!origen) err.origen = 'Selecciona el origen'
    const montoNum = monto.trim() === '' ? null : Number(monto)
    if (montoNum !== null && (!Number.isFinite(montoNum) || montoNum < 0)) {
      err.monto = 'Usa un número mayor o igual a 0'
    }
    setErrores(err)
    setErrorGeneral(null)
    // esOrigen narra '' → fuera: si origen está vacío, err.origen ya forzó el return.
    if (Object.keys(err).length > 0 || !esOrigen(origen)) return

    const res = crearLead({
      nombre_completo: nombre.trim(),
      telefono, // el store normaliza a +519########
      correo: correo.trim() || null,
      dni: dni.trim() || null,
      distrito: distrito.trim() || null,
      origen,
      etapa: etapaInicial,
      monto_estimado: montoNum,
      moneda,
      categoria_interes: categoria,
      vendedor_id: puedeElegirVendedor ? vendedorId || null : (yo?.id ?? null),
      nota: nota.trim() || null,
    })
    if (res.ok && res.id) {
      toast.success(`Lead creado${yo?.demo ? ' (demo)' : ''} — ${nombre.trim()}`)
      abrirLead(res.id) // abrirLead ya cierra este modal
      return
    }
    // Errores del store → anclados a su campo por res.campo (código
    // estructurado; jamás adivinando por regex sobre el texto del mensaje).
    const msg = res.error ?? 'No se pudo crear el lead'
    const campoUi = res.campo ? (CAMPO_UI[res.campo] ?? null) : null
    if (campoUi) setErrores({ [campoUi]: msg })
    else setErrorGeneral(msg)
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle>Nuevo lead</DialogTitle>
        <DialogDescription className="flex flex-wrap items-center gap-1.5">
          Entrará al pipeline en
          <Badge color={etapa.color} dot>
            {etapa.label}
          </Badge>
        </DialogDescription>
      </DialogHeader>
      <form onSubmit={enviar} noValidate className="flex min-h-0 flex-1 flex-col">
        <DialogBody className="space-y-3.5">
          {errorGeneral && (
            <div
              role="alert"
              className="rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs font-medium text-destructive"
            >
              {errorGeneral}
            </div>
          )}
          <Campo label="Nombre completo" htmlFor="nl-nombre" requerido error={errores.nombre}>
            <Input
              id="nl-nombre"
              autoFocus
              autoComplete="off"
              placeholder="Nombres y apellidos"
              value={nombre}
              aria-invalid={!!errores.nombre}
              className={cn(errores.nombre && claseError)}
              onChange={(e) => {
                setNombre(e.target.value)
                limpiarError('nombre')
              }}
            />
          </Campo>
          <div className="grid grid-cols-2 gap-3">
            <Campo label="Teléfono" htmlFor="nl-telefono" requerido error={errores.telefono}>
              <Input
                id="nl-telefono"
                type="tel"
                inputMode="tel"
                autoComplete="off"
                placeholder="987 654 321"
                value={telefono}
                aria-invalid={!!errores.telefono}
                className={cn(errores.telefono && claseError)}
                onChange={(e) => {
                  setTelefono(e.target.value)
                  limpiarError('telefono')
                }}
              />
            </Campo>
            <Campo label="DNI" htmlFor="nl-dni" error={errores.dni}>
              <Input
                id="nl-dni"
                inputMode="numeric"
                maxLength={8}
                autoComplete="off"
                placeholder="8 dígitos (opcional)"
                value={dni}
                aria-invalid={!!errores.dni}
                className={cn(errores.dni && claseError)}
                onChange={(e) => {
                  setDni(e.target.value.replace(/\D/g, ''))
                  limpiarError('dni')
                }}
              />
            </Campo>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Campo label="Correo" htmlFor="nl-correo" error={errores.correo}>
              <Input
                id="nl-correo"
                type="email"
                autoComplete="off"
                placeholder="correo@ejemplo.com"
                value={correo}
                aria-invalid={!!errores.correo}
                className={cn(errores.correo && claseError)}
                onChange={(e) => {
                  setCorreo(e.target.value)
                  limpiarError('correo')
                }}
              />
            </Campo>
            <Campo label="Distrito" htmlFor="nl-distrito">
              <Input
                id="nl-distrito"
                autoComplete="off"
                placeholder="Miraflores"
                value={distrito}
                onChange={(e) => setDistrito(e.target.value)}
              />
            </Campo>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Campo label="Origen" htmlFor="nl-origen" requerido error={errores.origen}>
              <Select
                id="nl-origen"
                value={origen}
                aria-invalid={!!errores.origen}
                className={cn(errores.origen && claseError)}
                onChange={(e) => {
                  // Las <option> salen del catálogo ORIGENES; esOrigen hace el narrow a Origen.
                  if (esOrigen(e.target.value)) setOrigen(e.target.value)
                  limpiarError('origen')
                }}
              >
                <option value="" disabled>
                  Selecciona…
                </option>
                {ORIGENES.map((o) => (
                  <option key={o.k} value={o.k}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </Campo>
            <Campo label="Monto estimado" htmlFor="nl-monto" error={errores.monto}>
              <div className="flex gap-2">
                <div className="min-w-0 flex-1">
                  <Input
                    id="nl-monto"
                    type="number"
                    min={0}
                    step="any"
                    inputMode="decimal"
                    placeholder="0"
                    value={monto}
                    aria-invalid={!!errores.monto}
                    className={cn('tabular-nums', errores.monto && claseError)}
                    onChange={(e) => {
                      setMonto(e.target.value)
                      limpiarError('monto')
                    }}
                  />
                </div>
                <div className="w-24 shrink-0">
                  <Select
                    aria-label="Moneda"
                    value={moneda}
                    onChange={(e) => setMoneda(e.target.value as Moneda)}
                  >
                    <option value="PEN">{SIMBOLO.PEN} PEN</option>
                    <option value="USD">{SIMBOLO.USD} USD</option>
                  </Select>
                </div>
              </div>
            </Campo>
          </div>
          <Campo label="Vendedor asignado" htmlFor="nl-vendedor">
            {puedeElegirVendedor ? (
              <Select
                id="nl-vendedor"
                value={vendedorId}
                onChange={(e) => setVendedorId(e.target.value)}
              >
                <option value="">Sin asignar (parkeado)</option>
                {vendedores.map((v) => (
                  <option key={v.perfil_id} value={v.perfil_id}>
                    {v.nombre_completo}
                  </option>
                ))}
              </Select>
            ) : (
              <>
                <Input id="nl-vendedor" value={yo?.nombre_completo ?? ''} disabled readOnly />
                <p className="text-[11px] text-muted-foreground">
                  El lead se te asigna automáticamente.
                </p>
              </>
            )}
          </Campo>
          <div className="space-y-1.5">
            <Label id="nl-categoria-label">
              Categoría de interés{' '}
              <span className="font-normal text-muted-foreground">(opcional)</span>
            </Label>
            <div
              role="group"
              aria-labelledby="nl-categoria-label"
              className="flex flex-wrap gap-2"
            >
              {CATEGORIAS_INTERES.map((c) => {
                const activa = categoria === c.k
                return (
                  <button
                    key={c.k}
                    type="button"
                    aria-pressed={activa}
                    onClick={() => setCategoria(activa ? null : c.k)}
                    className={cn(
                      'cursor-pointer rounded-full border px-3 py-1.5 text-[11px] font-bold leading-none transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30',
                      activa
                        ? 'border-accent bg-accent text-accent-foreground'
                        : 'border-input bg-background text-muted-foreground hover:border-border-strong hover:text-foreground',
                    )}
                  >
                    {c.label}
                  </button>
                )
              })}
            </div>
          </div>
          <Campo label="Nota" htmlFor="nl-nota">
            <Textarea
              id="nl-nota"
              rows={3}
              placeholder="Contexto del lead, próximos pasos… (opcional)"
              value={nota}
              onChange={(e) => setNota(e.target.value)}
            />
          </Campo>
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="ghost" onClick={cerrarPaneles}>
            Cancelar
          </Button>
          <Button type="submit">
            <UserRoundPlus /> Crear lead
          </Button>
        </DialogFooter>
      </form>
    </>
  )
}
