// Registrar el intento sobre un lead de la base (F2). Los 7 resultados del catálogo de la casa (atajos 1–7), nota
// libre y, con «volver a llamar», fecha y hora obligatorias (máximo 10 días). La pantalla avisa antes de enviar; la
// puerta `crm.registrar_intento_base` vuelve a validar y manda ella. Cada envío lleva un `p_operacion_id` fijo
// mientras su contenido no cambie: un doble clic o un reintento tras un corte devuelven la respuesta original.
import { useEffect, useId, useRef, useState, type JSX } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { CrmApiError, type RespuestaIntentoBase } from '@/data/crm-api'
import { useRegistrarIntentoBase } from '@/data/crm-queries'
import { fechaLima } from '@/lib/agenda-derivada'
import {
  DIAS_DESCANSO_BASE,
  DIAS_MAX_RELLAMADA,
  MAX_INTENTOS_BASE,
  etiquetaRellamada,
  firmaIntento,
  validarRellamada,
  type FilaBaseGestion,
} from '@/lib/base-gestion'
import { RESULTADOS, type ResultadoLlamada } from '@/lib/resultado-llamada'
import { cn } from '@/lib/utils'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'

/** Qué significa cada resultado AQUÍ, en la base (no en Gestión Diaria). */
const AYUDA_EN_LA_BASE: Record<ResultadoLlamada, string> = {
  no_contesto: 'Cuenta como intento.',
  volver_a_llamar: `Agenda la próxima llamada (hasta ${DIAS_MAX_RELLAMADA} días).`,
  agendo_reunion: 'Vuelve a tu cartera como Contactado.',
  no_interesado: 'Cuenta como intento. Anota el motivo.',
  numero_errado: 'Cuenta como intento.',
  no_es_la_persona: 'Cuenta como intento.',
  pide_otro_producto: 'Cuenta como intento. Anota qué pide.',
}

const DIA_MS = 86_400_000

/** Campos donde se ESCRIBE: ahí un dígito es texto, no un atajo (mismo contrato que el resultado de Gestión Diaria). */
const esCampoDeTexto = (el: EventTarget | null): boolean => {
  if (!(el instanceof HTMLElement)) return false
  if (el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable) return true
  return el instanceof HTMLInputElement && !['radio', 'checkbox', 'button', 'submit'].includes(el.type)
}
const CAMPO = cn('h-10 w-full rounded-lg border border-input bg-background px-3 text-sm text-foreground aria-[invalid=true]:border-[var(--destructive-text)]', FOCO)
/** Qué campo provocó el error: así se asocia (aria-describedby / aria-invalid) al control correcto. */
type CampoConError = 'resultado' | 'rellamada' | 'envio'

export interface DesenlaceIntento {
  /** El lead dejó la base: «agendó cita» lo reactivó, o el tercer intento lo puso a descansar. */
  tipo: 'reactivado' | 'descansa'
  mensaje: string
}

export function RegistrarIntentoBase({ fila, demo, onDejaLaBase }: {
  fila: FilaBaseGestion
  demo: boolean
  onDejaLaBase: (desenlace: DesenlaceIntento) => void
}): JSX.Element {
  const mutacion = useRegistrarIntentoBase()
  const id = useId()
  const hoy = fechaLima(Date.now())
  const [resultado, setResultado] = useState<ResultadoLlamada | null>(null)
  const [nota, setNota] = useState('')
  const [fecha, setFecha] = useState(() => fechaLima(Date.now() + DIA_MS))
  const [hora, setHora] = useState('10:00')
  const [error, setError] = useState<{ campo: CampoConError; texto: string } | null>(null)
  const envio = useRef<{ id: string; firma: string } | null>(null)
  const guardando = mutacion.isPending
  const guardandoRef = useRef(guardando)
  guardandoRef.current = guardando
  const idError = `${id}-error`
  const idAviso = `${id}-aviso`

  // Con este intento llega al tope y el lead descansa (salvo rellamada o cita, que ganan: D12 y D3).
  const descansaria = resultado != null && resultado !== 'volver_a_llamar' && resultado !== 'agendo_reunion'
    && fila.intentos + 1 >= MAX_INTENTOS_BASE && fila.proxima_llamada_en == null

  // Atajos 1–7 solo con el foco DENTRO de este formulario (WCAG 2.1.4) y nunca en un campo donde se escribe.
  const formulario = useRef<HTMLFormElement>(null)
  useEffect(() => {
    const alTecla = (e: globalThis.KeyboardEvent) => {
      if (guardandoRef.current || e.altKey || e.ctrlKey || e.metaKey || e.isComposing || esCampoDeTexto(e.target)) return
      if (!(e.target instanceof Node) || !formulario.current?.contains(e.target)) return
      const elegido = RESULTADOS.find((r) => r.atajo === e.key)
      if (!elegido) return
      e.preventDefault()
      setResultado(elegido.clave)
      setError(null)
      formulario.current.querySelector<HTMLInputElement>(`input[type="radio"][value="${elegido.clave}"]`)?.focus()
    }
    document.addEventListener('keydown', alTecla)
    return () => document.removeEventListener('keydown', alTecla)
  }, [])

  function anunciar(r: RespuestaIntentoBase) {
    if (r.reactivado) {
      onDejaLaBase({ tipo: 'reactivado', mensaje: 'Agendó cita: el lead volvió a tu cartera como Contactado' })
      return
    }
    if (r.enfriado_hasta) {
      const [anio, mes, dia] = r.enfriado_hasta.slice(0, 10).split('-')
      onDejaLaBase({ tipo: 'descansa', mensaje: `Tercer intento: el lead descansa hasta el ${dia}/${mes}/${anio} y vuelve solo a tu base` })
      return
    }
    const partes = [`Intento ${r.intento_n} registrado`]
    if (r.proxima_llamada_en) partes.push(`próxima llamada: ${etiquetaRellamada(r.proxima_llamada_en)}`)
    toast.success(partes.join(' · ') + (r.replay ? ' (ya estaba registrado: no se duplicó)' : ''))
    setResultado(null)
    setNota('')
  }

  async function guardar() {
    if (guardando) return
    if (resultado == null) {
      setError({ campo: 'resultado', texto: 'Elige qué pasó en la llamada (teclas 1–7).' })
      formulario.current?.querySelector<HTMLInputElement>('input[type="radio"]')?.focus()
      return
    }
    setError(null)
    let proxima: string | null = null
    if (resultado === 'volver_a_llamar') {
      const rellamada = validarRellamada(fecha, hora)
      if ('error' in rellamada) { setError({ campo: 'rellamada', texto: rellamada.error }); return }
      proxima = rellamada.iso
    }
    if (demo) { toast.info('En la demo los intentos no se guardan'); return }
    const firma = firmaIntento({ resultado, nota, proximaLlamada: proxima })
    if (envio.current?.firma !== firma) envio.current = { id: crypto.randomUUID(), firma }
    try {
      const r = await mutacion.mutateAsync({ operacionId: envio.current.id, leadId: fila.lead_id, resultado, nota, proximaLlamada: proxima })
      envio.current = null
      anunciar(r)
    } catch (causa: unknown) {
      setError({ campo: 'envio', texto: causa instanceof CrmApiError ? causa.message : 'No se pudo guardar el intento. Inténtalo de nuevo.' })
    }
  }

  return (
    <form
      ref={formulario}
      // La validación que habla es la nuestra (en español y con el porqué); `min`/`max` solo guían el calendario.
      noValidate
      aria-labelledby={`${id}-titulo`}
      className="space-y-4 rounded-xl border border-border bg-card p-4"
      onSubmit={(evento) => { evento.preventDefault(); void guardar() }}
    >
      <h3 id={`${id}-titulo`} className="text-base font-bold text-foreground">Registrar el intento</h3>
      <fieldset
        className="space-y-2"
        aria-invalid={error?.campo === 'resultado' || undefined}
        aria-describedby={error?.campo === 'resultado' ? idError : undefined}
      >
        <legend className="text-sm font-semibold text-[var(--muted-foreground-strong)]">¿Qué pasó en la llamada? <span className="font-normal">(atajos 1–7)</span></legend>
        <div className="grid gap-2 sm:grid-cols-2">
          {RESULTADOS.map((r) => {
            const marcado = resultado === r.clave
            return (
              <label
                key={r.clave}
                className={cn(
                  // El radio nativo va oculto: el foco se marca en la tarjeta con el MISMO contorno que el resto del CRM
                  // (FOCO) y lo elegido no se dice solo con color (borde doble y número relleno).
                  'flex cursor-pointer items-start gap-3 rounded-lg px-3 py-2.5 transition-colors has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-ring',
                  marcado ? 'border-2 border-accent bg-accent/10' : 'border border-border hover:bg-muted/60',
                )}
              >
                <input
                  type="radio"
                  name={`${id}-resultado`}
                  value={r.clave}
                  checked={marcado}
                  onChange={() => { setResultado(r.clave); setError(null) }}
                  className="sr-only"
                />
                <span aria-hidden className={cn('mt-0.5 inline-flex size-6 shrink-0 items-center justify-center rounded-md text-[13px] font-bold tabular-nums', marcado ? 'bg-accent text-accent-foreground' : 'bg-muted text-[var(--muted-foreground-strong)]')}>
                  {r.atajo}
                </span>
                <span className="min-w-0">
                  <span className="block text-[15px] font-semibold text-foreground">{r.etiqueta}</span>
                  <span className="block text-sm text-[var(--muted-foreground-strong)]">{AYUDA_EN_LA_BASE[r.clave]}</span>
                </span>
              </label>
            )
          })}
        </div>
      </fieldset>

      {resultado === 'volver_a_llamar' && (
        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <label htmlFor={`${id}-fecha`} className="mb-1 block text-sm font-semibold text-foreground">Fecha de la próxima llamada</label>
            <input
              id={`${id}-fecha`}
              type="date"
              required
              min={hoy}
              max={fechaLima(Date.now() + DIAS_MAX_RELLAMADA * DIA_MS)}
              value={fecha}
              onChange={(e) => { setFecha(e.target.value); setError(null) }}
              aria-invalid={error?.campo === 'rellamada' || undefined}
              aria-describedby={error?.campo === 'rellamada' ? idError : undefined}
              className={CAMPO}
            />
          </div>
          <div>
            <label htmlFor={`${id}-hora`} className="mb-1 block text-sm font-semibold text-foreground">Hora</label>
            <input
              id={`${id}-hora`}
              type="time"
              required
              value={hora}
              onChange={(e) => { setHora(e.target.value); setError(null) }}
              aria-invalid={error?.campo === 'rellamada' || undefined}
              aria-describedby={error?.campo === 'rellamada' ? idError : undefined}
              className={CAMPO}
            />
          </div>
        </div>
      )}

      <div>
        <label htmlFor={`${id}-nota`} className="mb-1 block text-sm font-semibold text-foreground">Nota <span className="font-normal text-[var(--muted-foreground-strong)]">(opcional)</span></label>
        <textarea
          id={`${id}-nota`}
          value={nota}
          onChange={(e) => setNota(e.target.value)}
          maxLength={1000}
          rows={3}
          placeholder="Qué dijo, a qué hora conviene, qué pidió…"
          className={cn('w-full rounded-lg border border-input bg-background px-3 py-2 text-sm text-foreground placeholder:text-[var(--muted-foreground-strong)]', FOCO)}
        />
      </div>

      {/* Siempre montado: el aviso se anuncia al aparecer (WCAG 4.1.3) y el botón lo enlaza. */}
      <div aria-live="polite">
        {descansaria && (
          <p id={idAviso} className="rounded-lg border border-[var(--warning-text)]/30 bg-[var(--warning-text)]/[0.06] px-3 py-2 text-sm text-[var(--warning-text)]">
            Con este son {MAX_INTENTOS_BASE} intentos sin cita ni rellamada: el lead descansará {DIAS_DESCANSO_BASE} días.
          </p>
        )}
      </div>
      {error && <p id={idError} role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{error.texto}</p>}
      <div className="flex justify-end">
        <Button
          type="submit"
          aria-disabled={guardando || undefined}
          aria-describedby={descansaria ? idAviso : undefined}
          className="aria-disabled:cursor-progress aria-disabled:opacity-60"
          onClick={(e) => { if (guardando) e.preventDefault() }}
        >
          {guardando ? 'Guardando…' : 'Guardar intento'}
        </Button>
      </div>
    </form>
  )
}
