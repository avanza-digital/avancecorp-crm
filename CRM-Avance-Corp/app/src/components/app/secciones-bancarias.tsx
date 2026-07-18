// Bloque compartido de DATOS BANCARIOS del cliente del portal (PEN + USD) —
// extraído de cliente-form.tsx para que el alta directa (ClienteForm) y la
// conversión de lead (DialogConvertir) pinten EXACTAMENTE el mismo formulario
// sin duplicar JSX: si el portal cambia un campo, se cambia UNA vez aquí.
// La validación NO vive aquí: es de lib/cliente-form-logica (validarSeccionBancaria
// / validarBancariosForm); este archivo solo pinta y reporta los inputs crudos.
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { BANCOS_PE, TIPOS_CUENTA, type SeccionBancariaForm } from '@/lib/cliente-form-logica'

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
}

/** Encabezado + una sección por moneda, con la regla del negocio a la vista. */
export function SeccionesBancarias({ idBase, pen, usd, onPen, onUsd, deshabilitado }: SeccionesBancariasProps) {
  return (
    <div className="space-y-2.5 border-t border-border pt-3">
      <div>
        <p className="text-xs font-bold text-foreground">Datos bancarios</p>
        <p className="text-[11px] text-muted-foreground">
          Cuenta(s) donde se depositan los intereses. Si el cliente invierte en soles registra
          la cuenta en soles; si invierte en dólares, la cuenta en dólares. Puedes registrar
          ambas. Debes registrar al menos una.
        </p>
      </div>
      <CamposSeccionBancaria
        titulo="Cuenta bancaria en Soles (PEN)"
        idBase={idBase}
        prefijo="pen"
        valores={pen}
        onCambio={onPen}
        deshabilitado={deshabilitado}
      />
      <CamposSeccionBancaria
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
interface CamposSeccionBancariaProps {
  titulo: string
  idBase: string
  /** Sufijo de moneda de los ids ('pen' | 'usd') para labels únicos. */
  prefijo: 'pen' | 'usd'
  valores: SeccionBancariaForm
  onCambio: (v: SeccionBancariaForm) => void
  deshabilitado: boolean
}

function CamposSeccionBancaria({
  titulo,
  idBase,
  prefijo,
  valores,
  onCambio,
  deshabilitado,
}: CamposSeccionBancariaProps) {
  const id = (campo: string) => `${idBase}-${prefijo}-${campo}`
  const set = (patch: Partial<SeccionBancariaForm>) => onCambio({ ...valores, ...patch })

  return (
    // fieldset disabled apaga TODOS los controles de la sección de una vez.
    <fieldset disabled={deshabilitado} className="space-y-2.5 rounded-xl border border-border p-3">
      <legend className="px-1 text-xs font-bold text-primary">{titulo}</legend>
      <div className="grid grid-cols-2 gap-2.5">
        <div className="space-y-1.5">
          <Label htmlFor={id('banco')}>Banco</Label>
          <Select id={id('banco')} value={valores.banco} onChange={(e) => set({ banco: e.target.value })}>
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
          <Select id={id('tipo')} value={valores.tipo_cuenta} onChange={(e) => set({ tipo_cuenta: e.target.value })}>
            <option value="">— Seleccionar —</option>
            {TIPOS_CUENTA.map((t) => <option key={t.k} value={t.k}>{t.etiqueta}</option>)}
          </Select>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-2.5">
        <div className="space-y-1.5">
          <Label htmlFor={id('numero')}>N° de cuenta</Label>
          <Input
            id={id('numero')}
            value={valores.numero_cuenta}
            onChange={(e) => set({ numero_cuenta: e.target.value })}
            maxLength={30}
            autoComplete="off"
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
            aria-describedby={id('cci-hint')}
          />
          <p id={id('cci-hint')} className="text-[10px] text-muted-foreground">
            Exactamente 20 dígitos. Necesario para transferencias interbancarias.
          </p>
        </div>
      </div>
      <label className="flex cursor-pointer items-center gap-2 text-xs font-medium">
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
          <p className="text-[10px] text-muted-foreground">
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
            />
          </div>
        </div>
      )}
    </fieldset>
  )
}
