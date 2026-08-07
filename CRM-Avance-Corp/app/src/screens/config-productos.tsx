import { useMemo, useState, type FormEvent } from 'react'
import {
  Archive,
  CalendarDays,
  CirclePlus,
  Edit3,
  Layers3,
  Package,
  RefreshCw,
  Rocket,
  Save,
  Trash2,
} from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { PanelVacio } from '@/components/common/estado-panel'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { mensajeDeError } from '@/data/crm-api'
import {
  useActualizarBorradorProducto,
  useArchivarProducto,
  useConfiguracionProductos,
  useCrearProductoInversion,
  useCrearVersionProducto,
  usePublicarVersionProducto,
} from '@/data/crm-config-queries'
import {
  CATEGORIAS_PRODUCTO,
  MODALIDADES_PRODUCTO,
  MONEDAS_PRODUCTO,
  TIPOS_INTERES_PRODUCTO,
  type CondicionProductoInput,
  type ProductoCondicion,
  type ProductoInversion,
  type ProductoVersion,
} from '@/lib/productos-inversion'

const ETIQUETA_CATEGORIA = {
  nuevo: 'Nuevo',
  renovacion: 'Renovación',
  upgrade: 'Upgrade',
} as const

const ETIQUETA_MODALIDAD = {
  mensual: 'Mensual',
  trimestral: 'Trimestral',
  semestral: 'Semestral',
  anual: 'Anual',
} as const

const ETIQUETA_INTERES = {
  simple: 'Simple',
  compuesto: 'Compuesto',
} as const

const ESTADO_VERSION = {
  borrador: { etiqueta: 'Borrador', color: 'var(--warning-text)' },
  publicada: { etiqueta: 'Publicada', color: 'var(--exito)' },
  retirada: { etiqueta: 'Retirada', color: 'var(--muted-foreground)' },
} as const

type CondicionFormulario = {
  categoria: (typeof CATEGORIAS_PRODUCTO)[number]
  moneda: (typeof MONEDAS_PRODUCTO)[number]
  plazoMeses: string
  modalidad: (typeof MODALIDADES_PRODUCTO)[number]
  tipoInteres: (typeof TIPOS_INTERES_PRODUCTO)[number]
  capitalMinimo: string
  capitalMaximo: string
  tasaMinima: string
  tasaReferencia: string
  tasaMaxima: string
}

type FormularioProducto = {
  codigo: string
  nombre: string
  descripcion: string
  vigenteDesde: string
  vigenteHasta: string
  condiciones: CondicionFormulario[]
}

type CabeceraValida = {
  codigo: string
  nombre: string
  descripcion: string | null
  vigenteDesde: string
  vigenteHasta: string | null
  condiciones: CondicionProductoInput[]
}

type ObjetivoEditor =
  | { tipo: 'crear-producto' }
  | { tipo: 'crear-version'; producto: ProductoInversion }
  | { tipo: 'editar-borrador'; producto: ProductoInversion; version: ProductoVersion }

type ObjetivoConfirmacion =
  | { tipo: 'publicar'; producto: ProductoInversion; version: ProductoVersion }
  | { tipo: 'archivar'; producto: ProductoInversion }

function hoyLima(): string {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date())
  const valor = Object.fromEntries(partes.map((parte) => [parte.type, parte.value]))
  return `${valor.year}-${valor.month}-${valor.day}`
}

function condicionNueva(): CondicionFormulario {
  return {
    categoria: 'nuevo',
    moneda: 'PEN',
    plazoMeses: '12',
    modalidad: 'mensual',
    tipoInteres: 'simple',
    capitalMinimo: '100',
    capitalMaximo: '100',
    tasaMinima: '1',
    tasaReferencia: '1',
    tasaMaxima: '1',
  }
}

function condicionDesdeCatalogo(condicion: ProductoCondicion): CondicionFormulario {
  return {
    categoria: condicion.categoria,
    moneda: condicion.moneda,
    plazoMeses: String(condicion.plazo_meses),
    modalidad: condicion.modalidad,
    tipoInteres: condicion.tipo_interes,
    capitalMinimo: String(condicion.capital_minimo),
    capitalMaximo: String(condicion.capital_maximo),
    tasaMinima: String(condicion.tasa_minima),
    tasaReferencia: String(condicion.tasa_referencia),
    tasaMaxima: String(condicion.tasa_maxima),
  }
}

function formularioInicial(objetivo: ObjetivoEditor): FormularioProducto {
  if (objetivo.tipo === 'crear-producto') {
    return {
      codigo: '',
      nombre: '',
      descripcion: '',
      vigenteDesde: hoyLima(),
      vigenteHasta: '',
      condiciones: [condicionNueva()],
    }
  }

  const referencia = objetivo.tipo === 'editar-borrador'
    ? objetivo.version
    : objetivo.producto.versiones.find((version) => version.estado === 'publicada')
      ?? objetivo.producto.versiones[0]
  const condiciones = referencia?.condiciones
    .filter((condicion) => condicion.activa)
    .map(condicionDesdeCatalogo) ?? []

  return {
    codigo: objetivo.producto.codigo,
    nombre: referencia?.nombre ?? objetivo.producto.codigo,
    descripcion: referencia?.descripcion ?? '',
    vigenteDesde: objetivo.tipo === 'editar-borrador'
      ? objetivo.version.vigente_desde
      : hoyLima(),
    vigenteHasta: objetivo.tipo === 'editar-borrador'
      ? objetivo.version.vigente_hasta ?? ''
      : '',
    condiciones: condiciones.length > 0 ? condiciones : [condicionNueva()],
  }
}

function fechaIsoValida(valor: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(valor)) return false
  const fecha = new Date(`${valor}T00:00:00.000Z`)
  return Number.isFinite(fecha.getTime()) && fecha.toISOString().slice(0, 10) === valor
}

function numero(valor: string): number {
  if (valor.trim() === '') return Number.NaN
  return Number(valor)
}

function validarFormulario(
  formulario: FormularioProducto,
  requiereCodigo: boolean,
): { error: string } | { valor: CabeceraValida } {
  const codigo = formulario.codigo.trim().toUpperCase()
  const nombre = formulario.nombre.trim()

  if (requiereCodigo
    && (!/^[A-Z0-9][A-Z0-9._-]{1,39}$/.test(codigo)
      || codigo === 'HISTORICO-SIN-CATALOGO')) {
    return { error: 'El código debe tener entre 2 y 40 caracteres: letras, números, punto, guion o guion bajo.' }
  }
  if (nombre.length < 3 || nombre.length > 160) {
    return { error: 'El nombre debe tener entre 3 y 160 caracteres.' }
  }
  if (formulario.descripcion.length > 2_000) {
    return { error: 'La descripción no puede superar los 2,000 caracteres.' }
  }
  if (!fechaIsoValida(formulario.vigenteDesde)) {
    return { error: 'Indica una fecha válida de inicio de vigencia.' }
  }
  if (formulario.vigenteHasta && !fechaIsoValida(formulario.vigenteHasta)) {
    return { error: 'La fecha final de vigencia no es válida.' }
  }
  if (formulario.vigenteHasta && formulario.vigenteHasta < formulario.vigenteDesde) {
    return { error: 'La fecha final no puede ser anterior al inicio de vigencia.' }
  }
  if (formulario.condiciones.length < 1 || formulario.condiciones.length > 100) {
    return { error: 'Envía entre 1 y 100 condiciones.' }
  }

  const condiciones: CondicionProductoInput[] = []
  for (const [indice, condicion] of formulario.condiciones.entries()) {
    const posicion = indice + 1
    if (!CATEGORIAS_PRODUCTO.some((valor) => valor === condicion.categoria)) {
      return { error: `La categoría de la condición ${posicion} no es válida.` }
    }
    if (!MONEDAS_PRODUCTO.some((valor) => valor === condicion.moneda)) {
      return { error: `La moneda de la condición ${posicion} no es válida.` }
    }
    if (!MODALIDADES_PRODUCTO.some((valor) => valor === condicion.modalidad)) {
      return { error: `La modalidad de la condición ${posicion} no es válida.` }
    }
    if (!TIPOS_INTERES_PRODUCTO.some((valor) => valor === condicion.tipoInteres)) {
      return { error: `El tipo de interés de la condición ${posicion} no es válido.` }
    }

    const plazoMeses = numero(condicion.plazoMeses)
    if (!Number.isInteger(plazoMeses) || plazoMeses < 1 || plazoMeses > 600) {
      return { error: `El plazo de la condición ${posicion} debe ser un entero entre 1 y 600 meses.` }
    }

    const capitalMinimo = numero(condicion.capitalMinimo)
    const capitalMaximo = numero(condicion.capitalMaximo)
    if (!Number.isFinite(capitalMinimo) || !Number.isFinite(capitalMaximo)
      || capitalMinimo < 100 || capitalMinimo > 100_000_000
      || capitalMaximo < 100 || capitalMaximo > 100_000_000) {
      return { error: `Los capitales de la condición ${posicion} deben estar entre 100 y 100,000,000.` }
    }
    if (capitalMinimo > capitalMaximo) {
      return { error: `El capital mínimo de la condición ${posicion} no puede superar el máximo.` }
    }

    const tasaMinima = numero(condicion.tasaMinima)
    const tasaReferencia = numero(condicion.tasaReferencia)
    const tasaMaxima = numero(condicion.tasaMaxima)
    if (![tasaMinima, tasaReferencia, tasaMaxima].every(
      (tasa) => Number.isFinite(tasa) && tasa > 0 && tasa <= 50,
    )) {
      return { error: `Las tasas de la condición ${posicion} deben ser mayores que 0 y no superar 50%.` }
    }
    if (tasaMinima > tasaReferencia || tasaReferencia > tasaMaxima) {
      return { error: `Las tasas de la condición ${posicion} deben cumplir mínima ≤ referencia ≤ máxima.` }
    }

    condiciones.push({
      categoria: condicion.categoria,
      moneda: condicion.moneda,
      plazo_meses: plazoMeses,
      modalidad: condicion.modalidad,
      tipo_interes: condicion.tipoInteres,
      capital_minimo: capitalMinimo,
      capital_maximo: capitalMaximo,
      tasa_minima: tasaMinima,
      tasa_referencia: tasaReferencia,
      tasa_maxima: tasaMaxima,
    })
  }

  return {
    valor: {
      codigo,
      nombre,
      descripcion: formulario.descripcion.trim() || null,
      vigenteDesde: formulario.vigenteDesde,
      vigenteHasta: formulario.vigenteHasta || null,
      condiciones,
    },
  }
}

function fechaLegible(valor: string): string {
  return new Intl.DateTimeFormat('es-PE', {
    dateStyle: 'medium',
    timeZone: 'UTC',
  }).format(new Date(`${valor}T12:00:00.000Z`))
}

function fechaHoraLegible(valor: string): string {
  return new Intl.DateTimeFormat('es-PE', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'America/Lima',
  }).format(new Date(valor))
}

function dinero(valor: number, moneda: (typeof MONEDAS_PRODUCTO)[number]): string {
  return new Intl.NumberFormat('es-PE', {
    style: 'currency',
    currency: moneda,
    maximumFractionDigits: 2,
  }).format(valor)
}

function tasa(valor: number): string {
  return `${new Intl.NumberFormat('es-PE', { maximumFractionDigits: 4 }).format(valor)}%`
}

function versionPublicable(version: ProductoVersion): boolean {
  const hoy = hoyLima()
  return version.condiciones.some((condicion) => condicion.activa)
    && version.vigente_desde <= hoy
    && (!version.vigente_hasta || version.vigente_hasta >= hoy)
}

function EditorProductoDialog({
  objetivo,
  guardando,
  onCerrar,
  onGuardar,
}: {
  objetivo: ObjetivoEditor
  guardando: boolean
  onCerrar: () => void
  onGuardar: (valor: CabeceraValida) => Promise<void>
}) {
  const [formulario, setFormulario] = useState(() => formularioInicial(objetivo))
  const [error, setError] = useState<string | null>(null)
  const requiereCodigo = objetivo.tipo === 'crear-producto'
  const titulo = objetivo.tipo === 'crear-producto'
    ? 'Crear producto'
    : objetivo.tipo === 'crear-version'
      ? `Crear versión de ${objetivo.producto.codigo}`
      : `Editar ${objetivo.producto.codigo} · v${objetivo.version.numero_version}`

  const actualizarCondicion = (indice: number, patch: Partial<CondicionFormulario>) => {
    setFormulario((actual) => ({
      ...actual,
      condiciones: actual.condiciones.map((condicion, posicion) =>
        posicion === indice ? { ...condicion, ...patch } : condicion),
    }))
    setError(null)
  }

  const agregarCondicion = () => {
    setFormulario((actual) => actual.condiciones.length >= 100
      ? actual
      : { ...actual, condiciones: [...actual.condiciones, condicionNueva()] })
    setError(null)
  }

  const eliminarCondicion = (indice: number) => {
    setFormulario((actual) => actual.condiciones.length <= 1
      ? actual
      : {
        ...actual,
        condiciones: actual.condiciones.filter((_, posicion) => posicion !== indice),
      })
    setError(null)
  }

  const guardar = async (evento: FormEvent<HTMLFormElement>) => {
    evento.preventDefault()
    const resultado = validarFormulario(formulario, requiereCodigo)
    if ('error' in resultado) {
      setError(resultado.error)
      return
    }
    setError(null)
    await onGuardar(resultado.valor)
  }

  return (
    <Dialog
      open
      onClose={() => { if (!guardando) onCerrar() }}
      ariaLabel={titulo}
      className="w-[1040px]"
    >
      <form className="flex min-h-0 flex-1 flex-col" noValidate onSubmit={guardar}>
        <DialogHeader>
          <DialogTitle>{titulo}</DialogTitle>
          <DialogDescription>
            Define una vigencia y entre 1 y 100 combinaciones comerciales. La versión se guardará como borrador.
          </DialogDescription>
        </DialogHeader>

        <DialogBody className="space-y-5">
          {error && (
            <div
              className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-xs font-semibold text-destructive"
              role="alert"
            >
              {error}
            </div>
          )}

          <section aria-labelledby="datos-version" className="space-y-3">
            <div>
              <h3 id="datos-version" className="text-sm font-bold text-primary">Identidad y vigencia</h3>
              <p className="mt-0.5 text-[11px] text-muted-foreground">
                El código identifica al producto; el nombre y las fechas pertenecen a esta versión.
              </p>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <Label htmlFor="producto-codigo">Código</Label>
                <Input
                  id="producto-codigo"
                  className="mt-1 font-mono uppercase"
                  value={formulario.codigo}
                  disabled={!requiereCodigo || guardando}
                  maxLength={40}
                  autoComplete="off"
                  onChange={(evento) => {
                    setFormulario((actual) => ({ ...actual, codigo: evento.target.value.toUpperCase() }))
                    setError(null)
                  }}
                />
              </div>
              <div>
                <Label htmlFor="producto-nombre">Nombre de la versión</Label>
                <Input
                  id="producto-nombre"
                  className="mt-1"
                  value={formulario.nombre}
                  disabled={guardando}
                  maxLength={160}
                  onChange={(evento) => {
                    setFormulario((actual) => ({ ...actual, nombre: evento.target.value }))
                    setError(null)
                  }}
                />
              </div>
              <div>
                <Label htmlFor="producto-vigente-desde">Vigente desde</Label>
                <Input
                  id="producto-vigente-desde"
                  className="mt-1"
                  type="date"
                  value={formulario.vigenteDesde}
                  disabled={guardando}
                  onChange={(evento) => {
                    setFormulario((actual) => ({ ...actual, vigenteDesde: evento.target.value }))
                    setError(null)
                  }}
                />
              </div>
              <div>
                <Label htmlFor="producto-vigente-hasta">Vigente hasta (opcional)</Label>
                <Input
                  id="producto-vigente-hasta"
                  className="mt-1"
                  type="date"
                  value={formulario.vigenteHasta}
                  disabled={guardando}
                  onChange={(evento) => {
                    setFormulario((actual) => ({ ...actual, vigenteHasta: evento.target.value }))
                    setError(null)
                  }}
                />
              </div>
              <div className="sm:col-span-2">
                <div className="flex items-center justify-between gap-2">
                  <Label htmlFor="producto-descripcion">Descripción (opcional)</Label>
                  <span className="text-[10px] tabular-nums text-muted-foreground">
                    {formulario.descripcion.length}/2,000
                  </span>
                </div>
                <Textarea
                  id="producto-descripcion"
                  className="mt-1"
                  value={formulario.descripcion}
                  disabled={guardando}
                  maxLength={2_001}
                  onChange={(evento) => {
                    setFormulario((actual) => ({ ...actual, descripcion: evento.target.value }))
                    setError(null)
                  }}
                />
              </div>
            </div>
          </section>

          <section aria-labelledby="condiciones-version" className="space-y-3">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <h3 id="condiciones-version" className="text-sm font-bold text-primary">Condiciones comerciales</h3>
                <p className="mt-0.5 text-[11px] text-muted-foreground">
                  Cada fila representa una combinación seleccionable al crear un contrato.
                </p>
              </div>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={agregarCondicion}
                disabled={guardando || formulario.condiciones.length >= 100}
              >
                <CirclePlus aria-hidden /> Agregar condición
              </Button>
            </div>

            <div className="space-y-3">
              {formulario.condiciones.map((condicion, indice) => (
                <fieldset
                  key={indice}
                  className="rounded-xl border border-border bg-muted/20 p-3 sm:p-4"
                  disabled={guardando}
                >
                  <legend className="sr-only">Condición {indice + 1}</legend>
                  <div className="mb-3 flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2">
                      <span className="grid size-6 place-items-center rounded-md bg-primary text-[11px] font-extrabold text-primary-foreground">
                        {indice + 1}
                      </span>
                      <p className="text-xs font-bold">Condición {indice + 1} de {formulario.condiciones.length}</p>
                    </div>
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      aria-label={`Eliminar condición ${indice + 1}`}
                      onClick={() => eliminarCondicion(indice)}
                      disabled={guardando || formulario.condiciones.length <= 1}
                      className="text-destructive hover:text-destructive"
                    >
                      <Trash2 aria-hidden /> Eliminar
                    </Button>
                  </div>

                  <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    <div>
                      <Label htmlFor={`condicion-${indice}-categoria`}>Categoría</Label>
                      <Select
                        id={`condicion-${indice}-categoria`}
                        className="mt-1"
                        value={condicion.categoria}
                        onChange={(evento) => actualizarCondicion(indice, {
                          categoria: evento.target.value as CondicionFormulario['categoria'],
                        })}
                      >
                        {CATEGORIAS_PRODUCTO.map((categoria) => (
                          <option key={categoria} value={categoria}>{ETIQUETA_CATEGORIA[categoria]}</option>
                        ))}
                      </Select>
                    </div>
                    <div>
                      <Label htmlFor={`condicion-${indice}-moneda`}>Moneda</Label>
                      <Select
                        id={`condicion-${indice}-moneda`}
                        className="mt-1"
                        value={condicion.moneda}
                        onChange={(evento) => actualizarCondicion(indice, {
                          moneda: evento.target.value as CondicionFormulario['moneda'],
                        })}
                      >
                        {MONEDAS_PRODUCTO.map((moneda) => <option key={moneda}>{moneda}</option>)}
                      </Select>
                    </div>
                    <div>
                      <Label htmlFor={`condicion-${indice}-plazo`}>Plazo (meses)</Label>
                      <Input
                        id={`condicion-${indice}-plazo`}
                        className="mt-1 tabular-nums"
                        type="number"
                        inputMode="numeric"
                        min={1}
                        max={600}
                        step={1}
                        value={condicion.plazoMeses}
                        onChange={(evento) => actualizarCondicion(indice, { plazoMeses: evento.target.value })}
                      />
                    </div>
                    <div>
                      <Label htmlFor={`condicion-${indice}-modalidad`}>Modalidad</Label>
                      <Select
                        id={`condicion-${indice}-modalidad`}
                        className="mt-1"
                        value={condicion.modalidad}
                        onChange={(evento) => actualizarCondicion(indice, {
                          modalidad: evento.target.value as CondicionFormulario['modalidad'],
                        })}
                      >
                        {MODALIDADES_PRODUCTO.map((modalidad) => (
                          <option key={modalidad} value={modalidad}>{ETIQUETA_MODALIDAD[modalidad]}</option>
                        ))}
                      </Select>
                    </div>
                    <div>
                      <Label htmlFor={`condicion-${indice}-interes`}>Tipo de interés</Label>
                      <Select
                        id={`condicion-${indice}-interes`}
                        className="mt-1"
                        value={condicion.tipoInteres}
                        onChange={(evento) => actualizarCondicion(indice, {
                          tipoInteres: evento.target.value as CondicionFormulario['tipoInteres'],
                        })}
                      >
                        {TIPOS_INTERES_PRODUCTO.map((tipo) => (
                          <option key={tipo} value={tipo}>{ETIQUETA_INTERES[tipo]}</option>
                        ))}
                      </Select>
                    </div>
                    <div className="hidden lg:block" aria-hidden />
                    <div>
                      <Label htmlFor={`condicion-${indice}-capital-minimo`}>Capital mínimo</Label>
                      <Input
                        id={`condicion-${indice}-capital-minimo`}
                        className="mt-1 tabular-nums"
                        type="number"
                        inputMode="decimal"
                        min={100}
                        max={100_000_000}
                        step="any"
                        value={condicion.capitalMinimo}
                        onChange={(evento) => actualizarCondicion(indice, { capitalMinimo: evento.target.value })}
                      />
                    </div>
                    <div>
                      <Label htmlFor={`condicion-${indice}-capital-maximo`}>Capital máximo</Label>
                      <Input
                        id={`condicion-${indice}-capital-maximo`}
                        className="mt-1 tabular-nums"
                        type="number"
                        inputMode="decimal"
                        min={100}
                        max={100_000_000}
                        step="any"
                        value={condicion.capitalMaximo}
                        onChange={(evento) => actualizarCondicion(indice, { capitalMaximo: evento.target.value })}
                      />
                    </div>
                    <div className="hidden lg:block" aria-hidden />
                    <div>
                      <Label htmlFor={`condicion-${indice}-tasa-minima`}>Tasa mínima (%)</Label>
                      <Input
                        id={`condicion-${indice}-tasa-minima`}
                        className="mt-1 tabular-nums"
                        type="number"
                        inputMode="decimal"
                        min="0.0001"
                        max={50}
                        step="any"
                        value={condicion.tasaMinima}
                        onChange={(evento) => actualizarCondicion(indice, { tasaMinima: evento.target.value })}
                      />
                    </div>
                    <div>
                      <Label htmlFor={`condicion-${indice}-tasa-referencia`}>Tasa de referencia (%)</Label>
                      <Input
                        id={`condicion-${indice}-tasa-referencia`}
                        className="mt-1 tabular-nums"
                        type="number"
                        inputMode="decimal"
                        min="0.0001"
                        max={50}
                        step="any"
                        value={condicion.tasaReferencia}
                        onChange={(evento) => actualizarCondicion(indice, { tasaReferencia: evento.target.value })}
                      />
                    </div>
                    <div>
                      <Label htmlFor={`condicion-${indice}-tasa-maxima`}>Tasa máxima (%)</Label>
                      <Input
                        id={`condicion-${indice}-tasa-maxima`}
                        className="mt-1 tabular-nums"
                        type="number"
                        inputMode="decimal"
                        min="0.0001"
                        max={50}
                        step="any"
                        value={condicion.tasaMaxima}
                        onChange={(evento) => actualizarCondicion(indice, { tasaMaxima: evento.target.value })}
                      />
                    </div>
                  </div>
                </fieldset>
              ))}
            </div>
          </section>
        </DialogBody>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={onCerrar} disabled={guardando}>
            Cancelar
          </Button>
          <Button type="submit" disabled={guardando}>
            <Save aria-hidden /> {guardando ? 'Guardando…' : objetivo.tipo === 'editar-borrador' ? 'Guardar borrador' : 'Crear borrador'}
          </Button>
        </DialogFooter>
      </form>
    </Dialog>
  )
}

function ConfirmacionDialog({
  objetivo,
  procesando,
  onCerrar,
  onConfirmar,
}: {
  objetivo: ObjetivoConfirmacion
  procesando: boolean
  onCerrar: () => void
  onConfirmar: () => Promise<void>
}) {
  const publica = objetivo.tipo === 'publicar'
  const titulo = publica
    ? `¿Publicar ${objetivo.producto.codigo} · v${objetivo.version.numero_version}?`
    : `¿Archivar ${objetivo.producto.codigo}?`

  return (
    <Dialog
      open
      onClose={() => { if (!procesando) onCerrar() }}
      ariaLabel={titulo}
      className="w-[480px]"
    >
      <DialogHeader>
        <DialogTitle>{titulo}</DialogTitle>
        <DialogDescription>
          {publica
            ? 'Esta versión reemplazará la publicación vigente. Los contratos históricos conservarán sus condiciones originales.'
            : 'El producto dejará de estar disponible y sus versiones activas se retirarán. Los contratos históricos no cambiarán.'}
        </DialogDescription>
      </DialogHeader>
      <DialogBody>
        <div className={`rounded-lg px-3 py-3 text-xs font-semibold ${publica ? 'bg-accent/10 text-accent' : 'bg-destructive/10 text-destructive'}`}>
          {publica
            ? 'La publicación no edita versiones anteriores.'
            : 'Archivar no elimina el producto ni se puede deshacer desde esta pantalla.'}
        </div>
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" onClick={onCerrar} disabled={procesando}>
          Cancelar
        </Button>
        <Button
          type="button"
          variant={publica ? 'default' : 'destructive'}
          onClick={() => void onConfirmar()}
          disabled={procesando}
        >
          {publica ? <Rocket aria-hidden /> : <Archive aria-hidden />}
          {procesando
            ? publica ? 'Publicando…' : 'Archivando…'
            : publica
              ? `Sí, publicar versión ${objetivo.version.numero_version}`
              : `Sí, archivar ${objetivo.producto.codigo}`}
        </Button>
      </DialogFooter>
    </Dialog>
  )
}

function TablaCondiciones({ version }: { version: ProductoVersion }) {
  if (version.condiciones.length === 0) {
    return <p className="px-4 py-5 text-xs text-muted-foreground">Esta versión no tiene condiciones visibles.</p>
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[900px] border-separate border-spacing-0 text-left text-xs">
        <caption className="sr-only">Condiciones de la versión {version.numero_version}</caption>
        <thead>
          <tr className="text-[10px] font-extrabold uppercase tracking-[0.07em] text-muted-foreground">
            <th scope="col" className="border-b border-border px-4 py-2.5">Condición</th>
            <th scope="col" className="border-b border-border px-3 py-2.5">Plazo</th>
            <th scope="col" className="border-b border-border px-3 py-2.5">Modalidad</th>
            <th scope="col" className="border-b border-border px-3 py-2.5">Capital</th>
            <th scope="col" className="border-b border-border px-3 py-2.5">Tasas mín. / ref. / máx.</th>
            <th scope="col" className="border-b border-border px-3 py-2.5">Estado</th>
          </tr>
        </thead>
        <tbody>
          {version.condiciones.map((condicion) => (
            <tr key={condicion.id} className={condicion.activa ? '' : 'opacity-60'}>
              <td className="border-b border-border/60 px-4 py-3">
                <p className="font-bold text-primary">{ETIQUETA_CATEGORIA[condicion.categoria]} · {condicion.moneda}</p>
                <p className="mt-0.5 text-[10px] text-muted-foreground">Interés {ETIQUETA_INTERES[condicion.tipo_interes].toLowerCase()}</p>
              </td>
              <td className="border-b border-border/60 px-3 py-3 tabular-nums">{condicion.plazo_meses} meses</td>
              <td className="border-b border-border/60 px-3 py-3">{ETIQUETA_MODALIDAD[condicion.modalidad]}</td>
              <td className="border-b border-border/60 px-3 py-3 tabular-nums">
                {dinero(condicion.capital_minimo, condicion.moneda)} – {dinero(condicion.capital_maximo, condicion.moneda)}
              </td>
              <td className="border-b border-border/60 px-3 py-3 tabular-nums">
                {tasa(condicion.tasa_minima)} / <strong>{tasa(condicion.tasa_referencia)}</strong> / {tasa(condicion.tasa_maxima)}
              </td>
              <td className="border-b border-border/60 px-3 py-3">
                <Badge
                  variant="outline"
                  color={condicion.activa ? 'var(--exito)' : 'var(--muted-foreground)'}
                >
                  {condicion.activa ? 'Activa' : 'Reemplazada'}
                </Badge>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function VersionCatalogo({
  producto,
  version,
  puedeAdministrar,
  bloqueado,
  onEditar,
  onPublicar,
}: {
  producto: ProductoInversion
  version: ProductoVersion
  puedeAdministrar: boolean
  bloqueado: boolean
  onEditar: () => void
  onPublicar: () => void
}) {
  const estado = ESTADO_VERSION[version.estado]
  const publicable = versionPublicable(version)

  return (
    <article className="relative pl-5 before:absolute before:inset-y-0 before:left-[5px] before:w-px before:bg-border last:before:bottom-1/2">
      <span
        className="absolute left-0 top-5 size-[11px] rounded-full border-2 border-card"
        style={{ background: estado.color }}
        aria-hidden
      />
      <div className="overflow-hidden rounded-xl border border-border bg-background/60">
        <div className="flex flex-col gap-3 border-b border-border px-4 py-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h4 className="text-sm font-bold text-primary">v{version.numero_version} · {version.nombre}</h4>
              <Badge color={estado.color} variant="outline">{estado.etiqueta}</Badge>
              <span className="text-[10px] font-semibold text-muted-foreground">revisión {version.revision}</span>
            </div>
            <p className="mt-1 flex flex-wrap items-center gap-x-1 text-[11px] text-muted-foreground">
              <CalendarDays className="size-3" aria-hidden />
              {fechaLegible(version.vigente_desde)}
              <span aria-hidden>→</span>
              {version.vigente_hasta ? fechaLegible(version.vigente_hasta) : 'sin fecha final'}
            </p>
            {version.descripcion && <p className="mt-2 max-w-3xl text-xs leading-relaxed text-foreground/75">{version.descripcion}</p>}
            {version.publicada_en && (
              <p className="mt-1 text-[10px] text-muted-foreground">
                Publicada por {version.publicada_por_nombre ?? 'usuario no disponible'} · {fechaHoraLegible(version.publicada_en)}
              </p>
            )}
          </div>

          {puedeAdministrar && producto.estado === 'activo' && version.estado === 'borrador' && (
            <div className="flex shrink-0 flex-wrap gap-2">
              <Button type="button" variant="outline" size="sm" onClick={onEditar} disabled={bloqueado}>
                <Edit3 aria-hidden /> Editar borrador
              </Button>
              <Button
                type="button"
                size="sm"
                onClick={onPublicar}
                disabled={bloqueado || !publicable}
                title={publicable ? undefined : 'La versión solo puede publicarse durante su vigencia y con condiciones activas.'}
              >
                <Rocket aria-hidden /> Publicar
              </Button>
            </div>
          )}
        </div>
        {!publicable && version.estado === 'borrador' && (
          <p className="border-b border-border bg-warning/10 px-4 py-2 text-[11px] font-semibold text-warning-text">
            Este borrador solo podrá publicarse durante su vigencia y mientras tenga condiciones activas.
          </p>
        )}
        <TablaCondiciones version={version} />
      </div>
    </article>
  )
}

function ProductoCatalogo({
  producto,
  puedeAdministrar,
  bloqueado,
  onCrearVersion,
  onEditar,
  onPublicar,
  onArchivar,
}: {
  producto: ProductoInversion
  puedeAdministrar: boolean
  bloqueado: boolean
  onCrearVersion: () => void
  onEditar: (version: ProductoVersion) => void
  onPublicar: (version: ProductoVersion) => void
  onArchivar: () => void
}) {
  const tieneBorrador = producto.versiones.some((version) => version.estado === 'borrador')

  return (
    <Card className={producto.estado === 'archivado' ? 'bg-muted/20' : undefined}>
      <CardHeader className="border-b border-border pb-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <CardTitle className="font-mono text-primary">{producto.codigo}</CardTitle>
              <Badge
                color={producto.estado === 'activo' ? 'var(--exito)' : 'var(--muted-foreground)'}
                variant="outline"
              >
                {producto.estado === 'activo' ? 'Activo' : 'Archivado'}
              </Badge>
              <span className="text-[10px] font-semibold text-muted-foreground">revisión {producto.revision}</span>
            </div>
            <p className="mt-1 text-xs text-muted-foreground">
              {producto.versiones.length} {producto.versiones.length === 1 ? 'versión registrada' : 'versiones registradas'}
            </p>
          </div>

          {puedeAdministrar && producto.estado === 'activo' && (
            <div className="flex shrink-0 flex-wrap gap-2">
              {!tieneBorrador && (
                <Button type="button" variant="outline" size="sm" onClick={onCrearVersion} disabled={bloqueado}>
                  <Layers3 aria-hidden /> Crear versión
                </Button>
              )}
              <Button type="button" variant="ghost" size="sm" onClick={onArchivar} disabled={bloqueado} className="text-destructive hover:text-destructive">
                <Archive aria-hidden /> Archivar
              </Button>
            </div>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-4 pt-4">
        {producto.versiones.length === 0 ? (
          <p className="py-5 text-center text-xs text-muted-foreground">No hay versiones visibles para este producto.</p>
        ) : producto.versiones.map((version) => (
          <VersionCatalogo
            key={version.id}
            producto={producto}
            version={version}
            puedeAdministrar={puedeAdministrar}
            bloqueado={bloqueado}
            onEditar={() => onEditar(version)}
            onPublicar={() => onPublicar(version)}
          />
        ))}
      </CardContent>
    </Card>
  )
}

export function ConfigProductos() {
  const consulta = useConfiguracionProductos()
  const crearProducto = useCrearProductoInversion()
  const crearVersion = useCrearVersionProducto()
  const actualizarBorrador = useActualizarBorradorProducto()
  const publicarVersion = usePublicarVersionProducto()
  const archivarProducto = useArchivarProducto()
  const [editor, setEditor] = useState<ObjetivoEditor | null>(null)
  const [confirmacion, setConfirmacion] = useState<ObjetivoConfirmacion | null>(null)

  const puedeAdministrar = Boolean(consulta.data?.puede_administrar)
  const mutando = crearProducto.isPending
    || crearVersion.isPending
    || actualizarBorrador.isPending
    || publicarVersion.isPending
    || archivarProducto.isPending

  const resumen = useMemo(() => {
    const productos = consulta.data?.productos ?? []
    return {
      activos: productos.filter((producto) => producto.estado === 'activo').length,
      publicados: productos.filter((producto) =>
        producto.versiones.some((version) => version.estado === 'publicada')).length,
    }
  }, [consulta.data])

  const guardarEditor = async (valor: CabeceraValida) => {
    if (!editor) return
    const cabecera = {
      nombre: valor.nombre,
      descripcion: valor.descripcion,
      vigenteDesde: valor.vigenteDesde,
      vigenteHasta: valor.vigenteHasta,
      condiciones: valor.condiciones,
    }

    try {
      if (editor.tipo === 'crear-producto') {
        await crearProducto.mutateAsync({ ...cabecera, codigo: valor.codigo })
        toast.success(`Producto ${valor.codigo} creado como borrador.`)
      } else if (editor.tipo === 'crear-version') {
        await crearVersion.mutateAsync({
          ...cabecera,
          productoId: editor.producto.id,
          expectedRevision: editor.producto.revision,
        })
        toast.success(`Nueva versión de ${editor.producto.codigo} creada como borrador.`)
      } else {
        await actualizarBorrador.mutateAsync({
          ...cabecera,
          versionId: editor.version.id,
          expectedRevision: editor.version.revision,
        })
        toast.success(`Borrador de ${editor.producto.codigo} guardado.`)
      }
      setEditor(null)
    } catch (fallo) {
      toast.error(mensajeDeError(fallo, 'No se pudo guardar el borrador del producto.'))
    }
  }

  const confirmarAccion = async () => {
    if (!confirmacion) return
    try {
      if (confirmacion.tipo === 'publicar') {
        await publicarVersion.mutateAsync({
          versionId: confirmacion.version.id,
          expectedRevision: confirmacion.version.revision,
        })
        toast.success(`${confirmacion.producto.codigo} · versión ${confirmacion.version.numero_version} publicada.`)
      } else {
        await archivarProducto.mutateAsync({
          productoId: confirmacion.producto.id,
          expectedRevision: confirmacion.producto.revision,
        })
        toast.success(`Producto ${confirmacion.producto.codigo} archivado.`)
      }
      setConfirmacion(null)
    } catch (fallo) {
      toast.error(mensajeDeError(fallo, confirmacion.tipo === 'publicar'
        ? 'No se pudo publicar la versión.'
        : 'No se pudo archivar el producto.'))
    }
  }

  return (
    <ConfiguracionShell
      icono={Package}
      titulo="Productos de inversión"
      descripcion="Catálogo versionado de condiciones comerciales. Publicar una revisión nueva nunca reescribe los contratos históricos."
      soloLectura={Boolean(consulta.data) && !puedeAdministrar}
      estado={consulta.data ? {
        etiqueta: `${resumen.activos} activos · ${resumen.publicados} publicados`,
        detalle: `Catálogo actualizado ${fechaHoraLegible(consulta.data.generado_en)}.`,
      } : undefined}
      acciones={puedeAdministrar ? (
        <Button type="button" size="sm" onClick={() => setEditor({ tipo: 'crear-producto' })} disabled={mutando}>
          <CirclePlus aria-hidden /> Nuevo producto
        </Button>
      ) : undefined}
    >
      {consulta.isPending && (
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground" role="status" aria-busy>
            Cargando el catálogo autorizado…
          </CardContent>
        </Card>
      )}

      {consulta.isError && !consulta.data && (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-12 text-center" role="alert">
            <p className="text-sm font-semibold text-destructive">
              {mensajeDeError(consulta.error, 'No se pudo cargar el catálogo de productos.')}
            </p>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => void consulta.refetch()}
              disabled={consulta.isFetching}
            >
              <RefreshCw aria-hidden /> {consulta.isFetching ? 'Reintentando…' : 'Reintentar'}
            </Button>
          </CardContent>
        </Card>
      )}

      {consulta.data?.productos.length === 0 && (
        <Card>
          <PanelVacio
            icono={Package}
            titulo="El catálogo todavía está vacío"
            detalle={puedeAdministrar
              ? 'Crea el primer producto y guarda sus condiciones como borrador.'
              : 'Gerencia aún no ha registrado productos de inversión.'}
          >
            {puedeAdministrar && (
              <Button type="button" size="sm" className="mt-2" onClick={() => setEditor({ tipo: 'crear-producto' })}>
                <CirclePlus aria-hidden /> Crear primer producto
              </Button>
            )}
          </PanelVacio>
        </Card>
      )}

      {consulta.data && consulta.data.productos.length > 0 && (
        <section aria-labelledby="catalogo-productos" className="space-y-4">
          <div className="flex items-center gap-2 px-1">
            <Layers3 className="size-4 text-accent" aria-hidden />
            <h2 id="catalogo-productos" className="text-xs font-extrabold uppercase tracking-[0.08em] text-muted-foreground">
              Catálogo y revisiones
            </h2>
          </div>
          {consulta.data.productos.map((producto) => (
            <ProductoCatalogo
              key={producto.id}
              producto={producto}
              puedeAdministrar={puedeAdministrar}
              bloqueado={mutando}
              onCrearVersion={() => setEditor({ tipo: 'crear-version', producto })}
              onEditar={(version) => setEditor({ tipo: 'editar-borrador', producto, version })}
              onPublicar={(version) => setConfirmacion({ tipo: 'publicar', producto, version })}
              onArchivar={() => setConfirmacion({ tipo: 'archivar', producto })}
            />
          ))}
        </section>
      )}

      {editor && (
        <EditorProductoDialog
          key={editor.tipo === 'crear-producto'
            ? editor.tipo
            : `${editor.tipo}-${editor.producto.id}-${editor.tipo === 'editar-borrador' ? editor.version.id : ''}`}
          objetivo={editor}
          guardando={crearProducto.isPending || crearVersion.isPending || actualizarBorrador.isPending}
          onCerrar={() => setEditor(null)}
          onGuardar={guardarEditor}
        />
      )}

      {confirmacion && (
        <ConfirmacionDialog
          objetivo={confirmacion}
          procesando={publicarVersion.isPending || archivarProducto.isPending}
          onCerrar={() => setConfirmacion(null)}
          onConfirmar={confirmarAccion}
        />
      )}
    </ConfiguracionShell>
  )
}
