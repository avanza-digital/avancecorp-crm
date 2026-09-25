// Bloque compartido de DATOS BANCARIOS del cliente del portal (PEN + USD) —
// extraído de cliente-form.tsx para que el alta directa (ClienteForm) y la
// conversión de lead (DialogConvertir) pinten EXACTAMENTE el mismo formulario
// sin duplicar JSX: si el portal cambia un campo, se cambia UNA vez aquí.
// La validación NO vive aquí: es de lib/cliente-form-logica (validarSeccionBancaria
// / validarBancariosForm); este archivo solo pinta y reporta los inputs crudos.
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import {
  BANCOS_PE,
  TIPOS_CUENTA,
  type CampoSeccionBancaria,
  type SeccionBancariaForm,
} from '@/lib/cliente-form-logica'

export interface SeccionesBancariasProps {
  /**
   * Prefijo de los ids de los inputs ('cf' en ClienteForm, 'cv' en la
   * conversión): ids únicos por modal y ESTABLES para los E2E, que localizan
   * los campos como `#cf-pen-banco` (cliente-form.spec.ts).
   */
  idBase: string
  pen: SeccionBancariaForm
  usd: SeccionBancariaForm
  onPen: (v: SeccionBancariaForm) => void
  onUsd: (v: SeccionBancariaForm) => void
  deshabilitado: boolean
  /** Corrección: campos vacíos conservan las cuentas vigentes. */
  registroOpcional?: boolean
}

/** Encabezado + una sección por moneda, con la regla del negocio a la vista. */
export function SeccionesBancarias({ idBase, pen, usd, onPen, onUsd, deshabilitado, registroOpcional = false }: SeccionesBancariasProps) {
  return (
    <div className="space-y-2.5 border-t border-border pt-3">
      <div>
        <p className="text-xs font-bold text-foreground">Datos bancarios</p>
        <p className="text-[11px] text-muted-foreground">
          {registroOpcional
            ? 'Registrar otra cuenta (opcional). Dejar una sección vacía conserva las cuentas vigentes y los vínculos de cada contrato.'
            : 'Registra al menos una cuenta para que el cliente pueda recibir pagos. Puedes registrar cuentas en soles y dólares.'}
        </p>
      </div>
      <SeccionBancariaCampos
        titulo="Cuenta bancaria en Soles (PEN)"
        idBase={idBase}
        prefijo="pen"
        valores={pen}
        onCambio={onPen}
        deshabilitado={deshabilitado}
      />
      <SeccionBancariaCampos
        titulo="Cuenta bancaria en Dólares (USD)"
        idBase={idBase}
        prefijo="usd"
        valores={usd}
        onCambio={onUsd}
        deshabilitado={deshabilitado}
      />
    </div>
  )
}

// ── Sección bancaria (una por moneda) — mismo bloque para PEN y USD ───────────
export interface SeccionBancariaCamposProps {
  titulo: string
  idBase: string
  /** Sufijo estable de los ids ('pen', 'usd', 'nueva'...) para labels únicos. */
  prefijo: string
  valores: SeccionBancariaForm
  onCambio: (v: SeccionBancariaForm) => void
  deshabilitado: boolean
  /** La sección completa es obligatoria (p. ej. alta inline de una cuenta contractual). */
  requerida?: boolean
  /** Campo que falló la validación del alta inline. */
  campoInvalido?: CampoSeccionBancaria | null
  /** Mensaje global ya visible que describe el campo inválido. */
  errorId?: string
}

/**
 * Editor de UNA cuenta. Se exporta para que el alta inline de un contrato use
 * exactamente los mismos campos, catálogo y accesibilidad que el alta de
 * cliente; la validación continúa centralizada en cliente-form-logica.
 */
export function SeccionBancariaCampos({
  titulo,
  idBase,
  prefijo,
  valores,
  onCambio,
  deshabilitado,
  requerida = false,
  campoInvalido = null,
  errorId,
}: SeccionBancariaCamposProps) {
  const id = (campo: string) => `${idBase}-${prefijo}-${campo}`
  const set = (patch: Partial<SeccionBancariaForm>) => onCambio({ ...valores, ...patch })
  const invalido = (campo: CampoSeccionBancaria) => campoInvalido === campo
  const descripcion = (campo: CampoSeccionBancaria, ayuda?: string) =>
    [ayuda, invalido(campo) ? errorId : null].filter(Boolean).join(' ') || undefined

  return (
    // fieldset disabled apaga TODOS los controles de la sección de una vez.
    <fieldset disabled={deshabilitado} className="space-y-2.5 rounded-xl border border-border p-3">
      <legend className="px-1 text-xs font-bold text-primary">{titulo}</legend>
      <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor={id('banco')}>Banco</Label>
          <Select
            id={id('banco')}
            value={valores.banco}
            onChange={(e) => set({ banco: e.target.value })}
            aria-required={requerida || undefined}
            aria-invalid={invalido('banco') || undefined}
            aria-describedby={descripcion('banco')}
          >
            <option value="">— Seleccionar banco —</option>
            {BANCOS_PE.map((g) => (
              <optgroup key={g.grupo} label={g.grupo}>
                {g.opciones.map((b) => <option key={b} value={b}>{b}</option>)}
              </optgroup>
            ))}
            {/* "Otro" SIEMPRE al final, fuera de los grupos (regla del portal). */}
            <option value="Otro">Otro</option>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor={id('tipo')}>Tipo de cuenta</Label>
          <Select
            id={id('tipo')}
            value={valores.tipo_cuenta}
            onChange={(e) => set({ tipo_cuenta: e.target.value })}
            aria-required={requerida || undefined}
            aria-invalid={invalido('tipo_cuenta') || undefined}
            aria-describedby={descripcion('tipo_cuenta')}
          >
            <option value="">— Seleccionar —</option>
            {TIPOS_CUENTA.map((t) => <option key={t.k} value={t.k}>{t.etiqueta}</option>)}
          </Select>
        </div>
      </div>
      <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor={id('numero')}>N° de cuenta</Label>
          <Input
            id={id('numero')}
            value={valores.numero_cuenta}
            onChange={(e) => set({ numero_cuenta: e.target.value })}
            maxLength={30}
            autoComplete="off"
            aria-required={requerida || undefined}
            aria-invalid={invalido('numero_cuenta') || undefined}
            aria-describedby={descripcion('numero_cuenta')}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor={id('cci')}>CCI — Código Interbancario</Label>
          <Input
            id={id('cci')}
            value={valores.cci}
            onChange={(e) => set({ cci: e.target.value })}
            maxLength={20}
            inputMode="numeric"
            placeholder="20 dígitos"
            autoComplete="off"
            aria-describedby={descripcion('cci', id('cci-hint'))}
            aria-required={requerida || undefined}
            aria-invalid={invalido('cci') || undefined}
          />
          <p id={id('cci-hint')} className="text-xs text-muted-foreground">
            Exactamente 20 dígitos. Necesario para transferencias interbancarias.
          </p>
        </div>
      </div>
      <label className="flex min-h-8 cursor-pointer items-center gap-2 py-1 text-xs font-medium has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-60">
        <input
          type="checkbox"
          className="size-3.5 accent-primary"
          checked={valores.titular_distinto}
          onChange={(e) => set({ titular_distinto: e.target.checked })}
        />
        <span>La cuenta es de un <b>beneficiario</b> (no es del socio)</span>
      </label>
      {valores.titular_distinto && (
        <div className="space-y-2.5 rounded-lg bg-muted/40 p-3">
          <p className="text-xs text-muted-foreground">
            Datos de la persona dueña de la cuenta donde se hará el depósito.
          </p>
          <div className="space-y-1.5">
            <Label htmlFor={id('benef-nombre')}>Nombre completo del beneficiario</Label>
            <Input
              id={id('benef-nombre')}
              value={valores.beneficiario_nombre}
              onChange={(e) => set({ beneficiario_nombre: e.target.value })}
              maxLength={200}
              style={{ textTransform: 'uppercase' }}
              autoComplete="off"
              aria-required={requerida || undefined}
              aria-invalid={invalido('beneficiario_nombre') || undefined}
              aria-describedby={descripcion('beneficiario_nombre')}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor={id('benef-doc')}>DNI del beneficiario</Label>
            <Input
              id={id('benef-doc')}
              value={valores.beneficiario_dni}
              onChange={(e) => set({ beneficiario_dni: e.target.value })}
              maxLength={20}
              inputMode="numeric"
              autoComplete="off"
              aria-required={requerida || undefined}
              aria-invalid={invalido('beneficiario_dni') || undefined}
              aria-describedby={descripcion('beneficiario_dni')}
            />
          </div>
        </div>
      )}
    </fieldset>
  )
}
