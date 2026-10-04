// Registrar el intento sobre un lead de la base (F2). Los 7 resultados del catálogo de la casa (atajos 1–7), nota
// libre y, con «volver a llamar», fecha y hora obligatorias (máximo 10 días). La pantalla avisa antes de enviar; la
// puerta `crm.registrar_intento_base` vuelve a validar y manda ella. Cada envío lleva un `p_operacion_id` fijo
// mientras su contenido no cambie: un doble clic o un reintento tras un corte devuelven la respuesta original.
// Se ve y se maneja como «¿Qué pasó con la llamada?» de Gestión Diaria (Miguel, 03/10): el paso 1 es el selector
// compartido (`SelectorResultado`: atajos, «Cambiar resultado», foco) y la tarjeta copia la de «Mi día», con la
// barra de guardar pegada abajo.
import { useId, useRef, useState, type JSX, type RefObject } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { SelectorResultado } from '@/components/gestion-diaria/selector-resultado'
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
import type { ResultadoLlamada } from '@/lib/resultado-llamada'

const DIA_MS = 86_400_000
/** Qué campo provocó el error: así se asocia (aria-describedby / aria-invalid) al control correcto. */
type CampoConError = 'resultado' | 'rellamada' | 'envio'

export interface DesenlaceIntento {
  /** El lead dejó la base: «agendó cita» lo reactivó, o el tercer intento lo puso a descansar. */
  tipo: 'reactivado' | 'descansa'
  mensaje: string
}

export function RegistrarIntentoBase({ fila, demo, onDejaLaBase, formRef }: {
  fila: FilaBaseGestion
  demo: boolean
  onDejaLaBase: (desenlace: DesenlaceIntento) => void
  /** El `<form>` para quien lo monta: la ficha lleva ahí el foco (al abrir y tras «Llamar») sin buscarlo en la página. */
  formRef?: RefObject<HTMLFormElement | null> | undefined
}): JSX.Element {
  const mutacion = useRegistrarIntentoBase()
  const id = useId()
  const hoy = fechaLima(Date.now())
  const [resultado, setResultado] = useState<ResultadoLlamada | null>(null)
  // `true` = los siete a la vista; al elegir se contrae en el elegido (como en Gestión Diaria).
  const [abierto, setAbierto] = useState(true)
  const [nota, setNota] = useState('')
  const [fecha, setFecha] = useState(() => fechaLima(Date.now() + DIA_MS))
  const [hora, setHora] = useState('10:00')
  const [error, setError] = useState<{ campo: CampoConError; texto: string } | null>(null)
  const envio = useRef<{ id: string; firma: string } | null>(null)
  const guardando = mutacion.isPending
  const guardandoRef = useRef(guardando)
  guardandoRef.current = guardando
  const formularioPropio = useRef<HTMLFormElement>(null)
  const formulario = formRef ?? formularioPropio
  const campoFecha = useRef<HTMLInputElement>(null)
  const idError = `${id}-error`
  const idAviso = `${id}-aviso`
  const idTope = `${id}-tope`
  const intentoN = fila.intentos + 1

  // Con este intento llega al tope y el lead descansa (salvo rellamada o cita, que ganan: D12 y D3).
  const descansaria = resultado != null && resultado !== 'volver_a_llamar' && resultado !== 'agendo_reunion'
    && intentoN >= MAX_INTENTOS_BASE && fila.proxima_llamada_en == null
  const errorEn = (campo: CampoConError) => error?.campo === campo
  const describeRellamada = [idTope, errorEn('rellamada') ? idError : null].filter(Boolean).join(' ')
  // El botón pulsado conserva el foco tras un fallo del envío: el error se le asocia para que se lea con él.
  const describeGuardar = [descansaria ? idAviso : null, errorEn('envio') ? idError : null].filter(Boolean).join(' ') || undefined

  // Lo llama el selector (clic o atajo; la regla «contraído = solo el mismo atajo» ya la aplica él).
  function elegir(r: ResultadoLlamada) {
    if (guardandoRef.current) return
    setAbierto(false)
    setResultado(r)
    setError(null)
  }

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
    setAbierto(true)
    setNota('')
  }

  async function guardar() {
    if (guardando) return
    if (resultado == null) {
      setAbierto(true)
      setError({ campo: 'resultado', texto: 'Elige qué pasó en la llamada (teclas 1–7).' })
      formulario.current?.querySelector<HTMLInputElement>('input[type="radio"]')?.focus()
      return
    }
    setError(null)
    let proxima: string | null = null
    if (resultado === 'volver_a_llamar') {
      const rellamada = validarRellamada(fecha, hora)
      if ('error' in rellamada) {
        setError({ campo: 'rellamada', texto: rellamada.error })
        // A corregir: el foco va a la fecha, que ya lleva el error en su descripción.
        campoFecha.current?.focus()
        return
      }
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
      className="rounded-xl border border-border bg-card"
      onSubmit={(evento) => { evento.preventDefault(); void guardar() }}
    >
      <div className="space-y-3 px-[18px] pb-3 pt-4">
        <h3 id={`${id}-titulo`} className="text-sm font-extrabold text-primary">¿Qué pasó con la llamada?</h3>
        {/* Mientras guarda, radios, «Cambiar resultado» y campos quedan inertes; `deshabilitado` apaga los atajos. */}
        <fieldset disabled={guardando} className="min-w-0 space-y-3">
          <SelectorResultado
            valor={resultado}
            abierto={abierto}
            onElegir={elegir}
            onAlternar={() => setAbierto((a) => !a)}
            dentro={(objetivo) => objetivo instanceof Node && Boolean(formulario.current?.contains(objetivo))}
            nombre={id.replaceAll(':', '')}
            idOpciones={`${id}-opciones`}
            leyenda="Resultado"
            // Compacta como la tarjeta de Gestión Diaria: sin segunda línea bajo cada resultado.
            detalles={null}
            ayudaAtajos="Atajos: 1 a 7 eligen el resultado."
            deshabilitado={guardando}
            invalido={errorEn('resultado')}
            describedBy={errorEn('resultado') ? idError : undefined}
          />

          {resultado === 'volver_a_llamar' && (
            <div role="group" aria-labelledby={`${id}-rellamada`} className="space-y-2 rounded-xl border border-[var(--accent)]/40 p-2.5">
              <p id={`${id}-rellamada`} className="text-[13px] font-bold text-[var(--muted-foreground-strong)]">Cuándo volver a llamar</p>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div>
                  <Label htmlFor={`${id}-fecha`} className="text-[13px]">Fecha</Label>
                  <Input
                    ref={campoFecha}
                    id={`${id}-fecha`}
                    type="date"
                    required
                    min={hoy}
                    max={fechaLima(Date.now() + DIAS_MAX_RELLAMADA * DIA_MS)}
                    value={fecha}
                    onChange={(e) => { setFecha(e.target.value); setError(null) }}
                    aria-invalid={errorEn('rellamada') || undefined}
                    aria-describedby={describeRellamada}
                    className="h-10 text-[13px]"
                  />
                </div>
                <div>
                  <Label htmlFor={`${id}-hora`} className="text-[13px]">Hora</Label>
                  <Input
                    id={`${id}-hora`}
                    type="time"
                    required
                    value={hora}
                    onChange={(e) => { setHora(e.target.value); setError(null) }}
                    aria-invalid={errorEn('rellamada') || undefined}
                    aria-describedby={describeRellamada}
                    className="h-10 text-[13px]"
                  />
                </div>
                <p id={idTope} className="text-[13px] text-[var(--muted-foreground-strong)] sm:col-span-2">Como máximo a {DIAS_MAX_RELLAMADA} días desde hoy.</p>
              </div>
            </div>
          )}

          <Textarea
            aria-label="Nota de la llamada"
            value={nota}
            onChange={(e) => setNota(e.target.value)}
            maxLength={1000}
            placeholder="Nota (opcional)…"
            className="min-h-[56px] text-[13px]"
          />
        </fieldset>

        {/* Siempre montado: el aviso se anuncia al aparecer (WCAG 4.1.3) y el botón lo enlaza. */}
        <div aria-live="polite">
          {descansaria && (
            <p id={idAviso} className="rounded-lg border border-[var(--warning-text)]/30 bg-[var(--warning-text)]/[0.06] px-3 py-2 text-sm text-[var(--warning-text)]">
              Con este son {MAX_INTENTOS_BASE} intentos sin cita ni rellamada: el lead descansará {DIAS_DESCANSO_BASE} días.
            </p>
          )}
        </div>
      </div>

      {/* Pegada abajo como en «Mi día»: «Guardar» nunca queda fuera de la vista. En el celular el cuerpo de la ficha
          tiene `py-4` y sin `-bottom-4` las opciones asomarían bajo la barra al desplazar. El error va aquí, junto al
          botón que lo provocó, para que se vea aunque la tarjeta esté desplazada. */}
      <div className="sticky -bottom-4 z-10 flex shrink-0 flex-wrap items-center justify-between gap-2 rounded-b-xl border-t border-border bg-card px-[18px] py-3 lg:bottom-0">
        {error && <p id={idError} role="alert" className="basis-full text-[13px] font-semibold text-[var(--destructive-text)]">{error.texto}</p>}
        <p className="text-[13px] text-[var(--muted-foreground-strong)]">
          Será el intento {intentoN}{intentoN <= MAX_INTENTOS_BASE ? ` de ${MAX_INTENTOS_BASE}` : ''}
        </p>
        {/* `aria-disabled` y no `disabled` (regla de la casa): sin resultado se ve apagado, pero al pulsarlo dice qué falta. */}
        <Button
          type="submit"
          aria-disabled={guardando || resultado == null || undefined}
          aria-busy={guardando || undefined}
          aria-describedby={describeGuardar}
          className="h-10 rounded-[10px] bg-accent px-4 text-[13px] font-bold hover:bg-accent-press aria-disabled:cursor-default aria-disabled:opacity-50"
          onClick={(e) => { if (guardando) e.preventDefault() }}
        >
          {guardando ? 'Guardando…' : 'Guardar intento'}
        </Button>
      </div>
    </form>
  )
}
