// Panel «Registrar resultado de la llamada» (Gestión Diaria F2, mockup 5).
// Es la ÚNICA definición del resultado de una llamada en el CRM: lo montan las
// acciones de contacto (colas, Hoy, ficha), el cierre de una tarea de llamada
// y el composer del drawer. Vive en un `Dialog` (el probado dentro del Sheet
// de la ficha), con la jerarquía del mockup: paso 1 = uno de siete resultados
// (atajos 1–7); paso 2 = lo que ese resultado exige (fecha, cita, submotivo o
// la decisión del analista ante un número errado); nota opcional; «Guardar».
//
// Nada en silencio: el toast enumera lo que ocurrió DE VERDAD (registrado,
// tarea cerrada, etapa, siguiente, descarte, No insistir) y ofrece «Deshacer»
// 15 s, que llama a `crm.deshacer_resultado_llamada` (24 h, solo el autor).
// La regla comercial vive en el servidor (`crm.registrar_llamada_v4`): aquí
// solo se arma la petición y se espeja lo que él rechazaría.
import { useEffect, useMemo, useRef, useState, type JSX } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { RadioGroup, type OpcionRadio } from '@/components/ui/radio-group'
import { Textarea } from '@/components/ui/textarea'
import { CAMPOS_REUNION_VACIOS, CamposReunion, camposTareaDeReunion, type EstadoCamposReunion } from '@/components/app/campos-reunion'
import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
import { fechaLima, horaLima, proximoSlotSugerido, tareaAEvento } from '@/lib/agenda-derivada'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { camposDeSugerencia, isoDeCampos, tituloProximaAccion, type CamposSiguiente } from '@/lib/campos-siguiente'
import { evidenciaNoResponde } from '@/lib/descarte-evidencia'
import { esPlanVivo } from '@/lib/plan-lead'
import { primerNombre } from '@/lib/format'
import { slotHabil, sugerirSiguiente } from '@/lib/motor-siguiente'
import {
  INTENTOS_PARA_OFRECER_PERDIDO, RESULTADOS, SUBMOTIVOS, definicionResultado, dentroDeVentanaLegal, etiquetaResultado, tiposSiguientesDeResultado,
  type ResultadoLlamada, type SubmotivoLlamada,
} from '@/lib/resultado-llamada'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { useCRMData } from '@/lib/store-context'
import type { RegistrarLlamadaInput } from '@/lib/store'
import { presentarCitas } from '@/lib/terminologia'
import { ETAPA_INFO, TIPOS_TAREA, esTipoTarea, type LeadContactable, type Tarea } from '@/lib/tipos'

type DecisionNumero = 'segundo_numero' | 'descartar' | 'reintento' | 'solo_registrar'

export interface RegistrarResultadoProps {
  lead: LeadContactable
  /** Tarea de LLAMADA pendiente que esta llamada cierra (la elige `tareaQueCierra`). */
  tarea?: Tarea | null | undefined
  /** Nota precargada (el composer del drawer la trae escrita). */
  notaInicial?: string | undefined
  onClose: () => void
  /** Se llama SOLO cuando el servidor confirmó el resultado (nunca al cancelar
   *  ni al quedar «por confirmar»): Gestión Diaria lo usa para saltar a la
   *  siguiente fila de la cola del día. `onClose` se dispara igual, después. */
  onGuardado?: (() => void) | undefined
}

const PLANTILLA: Tarea = {
  id: 'sugerencia', lead_id: null, tipo: 'llamada', titulo: '', vence_en: new Date(0).toISOString(),
  estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: new Date(0).toISOString(),
}

/** Campos de la siguiente para una fecha objetivo en ms (ya en ventana legal). */
function camposPara(tipo: CamposSiguiente['tipo'], titulo: string, ms: number): CamposSiguiente {
  return { tipo, titulo, fecha: fechaLima(ms), hora: horaLima(ms) }
}

/** Campos donde se ESCRIBE: ahí los dígitos son texto, no atajos. Los radios y
 *  casillas (donde cae el foco inicial del diálogo) sí aceptan los atajos. */
const ES_CAMPO = (el: EventTarget | null): boolean => {
  if (!(el instanceof HTMLElement)) return false
  if (el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable) return true
  return el instanceof HTMLInputElement && !['radio', 'checkbox', 'button', 'submit'].includes(el.type)
}

export function RegistrarResultado({ lead, tarea, notaInicial, onClose, onGuardado }: RegistrarResultadoProps): JSX.Element {
  const { registrarLlamada, deshacerResultadoLlamada, tareasDe } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  const historial = useActividadesDeLead(lead.id)
  const nombre = primerNombre(lead.nombre_completo)
  const soyDueno = lead.vendedor_id != null && lead.vendedor_id === yo?.id
  const pendientes = tareasDe(lead.id)

  const [resultado, setResultado] = useState<ResultadoLlamada | null>(null)
  const [mostrarOpciones, setMostrarOpciones] = useState(true)
  const enfocarResultado = useRef(false)
  const [submotivo, setSubmotivo] = useState<SubmotivoLlamada | null>(null)
  const [decision, setDecision] = useState<DecisionNumero | null>(null)
  // ANTI-DUPLICADO (misma regla que el diálogo anterior): si el lead ya tiene
  // un plan vivo que esta llamada no cierra, el siguiente intento no se
  // propone marcado. El analista puede marcarlo igual.
  const otroPlanVivo = pendientes.some((t) => t.id !== tarea?.id && esPlanVivo(t, ahora))
  const [agendar, setAgendar] = useState(!otroPlanVivo)
  const [perdido, setPerdido] = useState(false)
  const [descartarInteres, setDescartarInteres] = useState(false)
  const [noInsista, setNoInsista] = useState(false)
  const [cierraTarea, setCierraTarea] = useState(true)
  const [nota, setNota] = useState(notaInicial ?? '')
  const [editados, setEditados] = useState<CamposSiguiente | null>(null)
  const [tituloEditado, setTituloEditado] = useState(false)
  const [camposReunion, setCamposReunion] = useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)
  const [tsEleccion, setTsEleccion] = useState(() => Date.now())
  const [procesando, setProcesando] = useState(false)
  const [sinConfirmar, setSinConfirmar] = useState<RegistrarLlamadaInput | null>(null)
  const enviando = useRef(false)

  const def = resultado ? definicionResultado(resultado) : null
  // Intentos sin respuesta ya registrados: al 6.º se ofrece «marcar perdido».
  // Un número errado no es «no responde» (mismo criterio que el servidor).
  const intentosPrevios = historial.cargando || historial.error
    ? null
    : evidenciaNoResponde(historial.items.filter((a) => {
      const r = a.metadata?.resultado
      return r !== 'numero_errado' && r !== 'no_es_la_persona'
    })).intentos
  const ofrecePerdido = resultado === 'no_contesto' && intentosPrevios !== null && intentosPrevios + 1 >= INTENTOS_PARA_OFRECER_PERDIDO
  const tieneSegundoNumero = Boolean(lead.telefono_alternativo)

  const elegir = (r: ResultadoLlamada, desdeAtajo = false) => {
    if (enviando.current || sinConfirmar) return
    if (desdeAtajo && !mostrarOpciones && r !== resultado) return
    enfocarResultado.current = true
    setMostrarOpciones(false)
    if (r === resultado) return
    setResultado(r)
    setSubmotivo(null)
    setDecision(r === 'numero_errado' || r === 'no_es_la_persona' ? (tieneSegundoNumero ? 'segundo_numero' : null) : null)
    setAgendar(!otroPlanVivo)
    setPerdido(false)
    setDescartarInteres(false)
    setNoInsista(false)
    setEditados(null)
    setTituloEditado(false)
    setCamposReunion(CAMPOS_REUNION_VACIOS)
    setTsEleccion(Date.now())
  }

  // La SUGERENCIA del motor (cadencia D1/D3, alternancia de canal, ventana
  // legal) es el punto de partida editable; el analista manda.
  const sugerida = useMemo<CamposSiguiente | null>(() => {
    if (!def || !soyDueno || lead.no_contactar) return null
    if (def.paso === 'submotivo') {
      return camposPara('llamada', tituloProximaAccion('llamada', nombre), Date.parse(proximoSlotSugerido(tsEleccion)))
    }
    if (def.clave === 'no_contesto' || def.clave === 'volver_a_llamar') {
      const s = sugerirSiguiente({ tareaTipo: 'llamada', estado: 'completada', resultado: def.tipo, leadNombre: lead.nombre_completo, noContactar: lead.no_contactar ?? null, ahora: tsEleccion })
      if (!s) return null
      return def.clave === 'volver_a_llamar' ? { ...camposDeSugerencia(s), tipo: 'llamada', titulo: `Volver a llamar a ${nombre}` } : camposDeSugerencia(s)
    }
    if (def.clave === 'agendo_reunion') {
      return camposPara('reunion', `Cita con ${nombre}`, Date.parse(slotHabil(tsEleccion + 24 * 3600 * 1000)))
    }
    if (def.paso === 'decision_numero') {
      if (decision === 'segundo_numero') return camposPara('llamada', `Llamar al 2.º número ${lead.telefono_alternativo ?? ''}`.trim(), Date.parse(slotHabil(tsEleccion + 30 * 60 * 1000)))
      if (decision === 'reintento') return camposPara('llamada', `Reintentar con ${nombre}`, Date.parse(slotHabil(tsEleccion + 7 * 24 * 3600 * 1000)))
    }
    return null
  }, [def, decision, lead.nombre_completo, lead.no_contactar, lead.telefono_alternativo, nombre, soyDueno, tsEleccion])
  const campos = editados ?? sugerida
  const editar = (parche: Partial<CamposSiguiente>) => setEditados({ ...(campos ?? { tipo: 'llamada', titulo: '', fecha: '', hora: '10:00' }), ...parche })

  const descarta = def != null && ((def.paso === 'submotivo' && descartarInteres) || (def.paso === 'decision_numero' && decision === 'descartar') || (def.clave === 'no_contesto' && perdido))
  const muestraSiguiente = soyDueno && !noInsista && !lead.no_contactar && !descarta && def != null && (
    def.clave === 'volver_a_llamar' || def.clave === 'agendo_reunion'
    || def.paso === 'submotivo'
    || (def.clave === 'no_contesto' && !perdido)
    || (def.paso === 'decision_numero' && (decision === 'segundo_numero' || decision === 'reintento')))
  const siguienteOpcional = def?.clave === 'no_contesto' || def?.paso === 'submotivo'
  const tiposSiguientes = resultado ? tiposSiguientesDeResultado(resultado) : []
  const cancelaria = descarta ? pendientes.filter((t) => t.id !== tarea?.id).length : 0

  // Atajos 1–7 mientras el panel está abierto (es modal): SOLO cuando el foco
  // no está en un campo (teclear «1» en la nota no debe cambiar el resultado)
  // y sin modificadores. Se escucha en el documento porque el foco inicial
  // queda en el contenedor del diálogo, fuera de este árbol.
  const elegirRef = useRef(elegir)
  elegirRef.current = elegir
  const raiz = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!enfocarResultado.current || !resultado) return
    enfocarResultado.current = false
    raiz.current?.querySelector<HTMLInputElement>(`input[name="resultado-llamada"][value="${resultado}"]`)?.focus()
  }, [mostrarOpciones, resultado])
  useEffect(() => {
    const onKeyDown = (e: globalThis.KeyboardEvent) => {
      if (e.altKey || e.ctrlKey || e.metaKey || e.isComposing || ES_CAMPO(e.target)) return
      // Solo mientras ESTE diálogo tiene el foco (WCAG 2.1.4: atajos de un
      // carácter acotados al componente), no cualquier modal apilado.
      const dialogo = raiz.current?.closest<HTMLElement>('[role="dialog"]')
      if (!dialogo || !(e.target instanceof Node) || !dialogo.contains(e.target)) return
      const r = RESULTADOS.find((x) => x.atajo === e.key)
      if (!r) return
      e.preventDefault()
      elegirRef.current(r.clave, true)
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [])
  useEffect(() => { setNota(notaInicial ?? '') }, [notaInicial])

  const armar = (): RegistrarLlamadaInput | string => {
    if (!def) return 'Elige el resultado de la llamada'
    const entrada: RegistrarLlamadaInput = { resultado: def.clave, detalle: nota.trim() || null, tarea_id: tarea && cierraTarea ? tarea.id : null }
    if (def.paso === 'submotivo') {
      if (!submotivo) return def.clave === 'no_interesado' ? 'Indica por qué no le interesa' : 'Indica qué producto pide'
      entrada.submotivo = submotivo
      entrada.no_insista = noInsista
      entrada.descartar = descartarInteres
    }
    if (def.paso === 'decision_numero') {
      if (!decision) return 'Decide qué hacer con este número'
      entrada.descartar = decision === 'descartar'
    }
    if (def.clave === 'no_contesto' && perdido) entrada.descartar = true
    const quiereSiguiente = muestraSiguiente && (!siguienteOpcional || agendar)
    if (quiereSiguiente) {
      if (!campos) return 'Indica la fecha del siguiente paso'
      const iso = isoDeCampos(campos)
      if (!iso || !campos.titulo.trim()) return 'La siguiente tarea necesita título, fecha y hora válidos'
      if (Date.parse(iso) <= Date.now()) return 'La fecha del siguiente paso debe ser futura'
      if (!tiposSiguientes.includes(campos.tipo)) return 'Elige un tipo de próxima acción válido para este resultado'
      if ((campos.tipo === 'llamada' || campos.tipo === 'whatsapp') && !dentroDeVentanaLegal(iso)) return 'Solo se contacta de lunes a sábado entre 07:00 y 20:00 (Ley 29571)'
      if (campos.tipo === 'reunion') {
        const reunion = validarReunionOperativa(camposReunion)
        if (!reunion.ok) return reunion.error
        entrada.siguiente = { tipo: 'reunion', titulo: campos.titulo.trim(), vence_en: iso, ...camposTareaDeReunion(reunion) }
      } else {
        entrada.siguiente = { tipo: campos.tipo, titulo: campos.titulo.trim(), vence_en: iso }
      }
    } else if (soyDueno && (def.clave === 'volver_a_llamar' || def.clave === 'agendo_reunion')) {
      return def.clave === 'volver_a_llamar' ? 'Indica cuándo volver a llamar' : 'Indica la fecha de la cita'
    }
    return entrada
  }

  const enviar = async (entrada: RegistrarLlamadaInput) => {
    if (enviando.current) return
    enviando.current = true
    setProcesando(true)
    try {
      const res = registrarLlamada(lead.id, entrada)
      if (!res.ok) { toast.error(res.error ?? 'No se pudo registrar la llamada'); return }
      const confirmado = await (res.persistido ?? Promise.resolve(true))
      if (!confirmado) { setSinConfirmar(entrada); return }
      const confirmacion = await (res.confirmacion ?? Promise.resolve(null))
      onClose()
      onGuardado?.()
      const partes = [`Llamada registrada · ${etiquetaResultado(entrada.resultado)}`]
      if (entrada.tarea_id && tarea) partes.push(`tarea cerrada («${presentarCitas(tarea.titulo)}»)`)
      if (res.avance && !res.descartado) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
      if (entrada.siguiente) partes.push(`siguiente ${tareaAEvento({ ...PLANTILLA, tipo: entrada.siguiente.tipo as Tarea['tipo'], titulo: entrada.siguiente.titulo, vence_en: entrada.siguiente.vence_en }, ahora).cuando}`)
      if (res.descartado) partes.push('lead descartado (Centro de rescate)')
      if (entrada.no_insista) partes.push('No insistir marcado')
      const texto = `${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}`
      if (confirmacion && !entrada.no_insista) {
        toast.success(texto, {
          duration: 15_000,
          action: {
            label: 'Deshacer',
            onClick: () => {
              const r = deshacerResultadoLlamada(confirmacion.actividad_id)
              if (!r.ok) { toast.error(r.error ?? 'No se pudo deshacer'); return }
              void (r.persistido ?? Promise.resolve(true)).then((ok) => {
                if (ok) toast.success(`Deshecho: ${nombre} vuelve a su etapa y la tarea creada se cancela`)
              })
            },
          },
        })
      } else {
        toast.success(texto)
      }
    } catch {
      setSinConfirmar(entrada)
    } finally {
      enviando.current = false
      setProcesando(false)
    }
  }

  const guardar = () => {
    if (sinConfirmar) return
    const entrada = armar()
    if (typeof entrada === 'string') { toast.error(entrada); return }
    void enviar(entrada)
  }

  const opciones: OpcionRadio<ResultadoLlamada>[] = RESULTADOS.filter((r) => mostrarOpciones || r.clave === resultado).map((r) => ({ valor: r.clave, etiqueta: r.etiqueta, detalle: r.detalle, atajo: r.atajo }))
  const opcionesSubmotivo: OpcionRadio<SubmotivoLlamada>[] = def?.paso === 'submotivo'
    ? SUBMOTIVOS[def.clave as 'no_interesado' | 'pide_otro_producto'].map((s) => ({ valor: s.clave, etiqueta: s.etiqueta }))
    : []
  const opcionesDecision: OpcionRadio<DecisionNumero>[] = [
    ...(tieneSegundoNumero ? [{ valor: 'segundo_numero' as const, etiqueta: `Llamar al 2.º número (${lead.telefono_alternativo})`, detalle: 'Se agenda para hoy' }] : []),
    { valor: 'descartar' as const, etiqueta: 'Descartar por datos inválidos', detalle: 'Sale de tu cartera; puedes deshacerlo desde el aviso al guardar' },
    { valor: 'reintento' as const, etiqueta: 'Mantener con reintento a 7 días', detalle: 'Se agenda otra llamada' },
    { valor: 'solo_registrar' as const, etiqueta: 'Solo registrar', detalle: 'Sin tarea ni descarte' },
  ]

  return (
    <Dialog open onClose={() => { if (!enviando.current) onClose() }} ariaLabel="Resultado de la llamada" className="w-[560px] [&_button]:text-base [&_select]:text-base [&_label]:text-base [&_p]:text-base">
      {/* Columna flex que hereda la altura del Dialog: sin esto el cuerpo no
          obtiene su scroll interno y «Guardar» queda fuera de la pantalla. */}
      <div ref={raiz} className="flex min-h-0 flex-1 flex-col">
        <DialogHeader>
          <DialogTitle className="text-xl">¿Cómo salió la llamada con {nombre}?</DialogTitle>
          <DialogDescription className="text-base">
            Registra el resultado y elige la próxima acción. Se guardan juntos en el historial y la agenda.
          </DialogDescription>
        </DialogHeader>
        <DialogBody className="space-y-3">
          <fieldset disabled={procesando || sinConfirmar !== null} className="min-w-0 space-y-3">
            <div id="opciones-resultado-llamada">
              <RadioGroup<ResultadoLlamada> grande leyenda="Resultado" opciones={opciones} valor={resultado} onCambio={elegir} obligatorio nombre="resultado-llamada" descripcion={mostrarOpciones ? 'Atajos: las teclas 1 a 7 eligen el resultado.' : 'Para elegir otro, usa «Cambiar resultado».'} />
            </div>
            {resultado && <Button type="button" variant="outline" aria-expanded={mostrarOpciones} aria-controls="opciones-resultado-llamada" onClick={() => {
              enfocarResultado.current = true
              setMostrarOpciones(!mostrarOpciones)
            }}>{mostrarOpciones ? 'Mantener resultado' : 'Cambiar resultado'}</Button>}

            {def?.paso === 'submotivo' && (
              <div className="space-y-3">
                <div>
                  <Label htmlFor="submotivo-llamada">{def.clave === 'no_interesado' ? '¿Por qué no le interesa?' : '¿Qué producto pide?'} · obligatorio</Label>
                  <Select id="submotivo-llamada" required value={submotivo ?? ''} onChange={(e) => {
                    setSubmotivo(opcionesSubmotivo.find((s) => s.valor === e.target.value)?.valor ?? null)
                  }}>
                    <option value="" disabled>Selecciona un motivo</option>
                    {opcionesSubmotivo.map((s) => <option key={s.valor} value={s.valor}>{s.etiqueta}</option>)}
                  </Select>
                </div>
                <label className="flex cursor-pointer items-start gap-2 text-base font-semibold">
                  <input type="checkbox" className="mt-1 size-4 shrink-0 accent-[var(--accent)]" checked={descartarInteres} onChange={(e) => setDescartarInteres(e.target.checked)} />
                  <span>Descartar y enviar al Centro de rescate</span>
                </label>
                {descartarInteres && <p className="text-base font-semibold text-foreground/85">
                  {nombre} saldrá de tu cartera hacia el Centro de rescate; puedes deshacerlo desde el aviso al guardar (el servidor lo admite 24 h).
                  {cancelaria > 0 && ` Se cancelarán ${cancelaria} ${cancelaria === 1 ? 'tarea pendiente' : 'tareas pendientes'}.`}
                </p>}
                <label className="flex cursor-pointer items-start gap-2 text-base font-semibold text-foreground/85">
                  <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={noInsista} onChange={(e) => setNoInsista(e.target.checked)} />
                  <span>Pidió que no lo vuelvan a llamar <span className="font-normal text-[var(--muted-foreground-strong)]">(Ley 29571; esta marca no se puede deshacer desde aquí)</span></span>
                </label>
                {!descartarInteres && <p className="text-base text-muted-foreground">El lead se mantiene en tu cartera. Este resultado no lo descarta.</p>}
              </div>
            )}

            {def?.paso === 'decision_numero' && (
              <div className="space-y-2 rounded-xl border border-[var(--accent)]/40 p-2.5">
                <RadioGroup<DecisionNumero> grande leyenda="¿Qué hacemos con este número?" opciones={opcionesDecision} valor={decision} onCambio={setDecision} obligatorio nombre="decision-numero" descripcion="Esta llamada cuenta como intento, pero no entra en la tasa de contacto." />
              </div>
            )}

            {ofrecePerdido && (
              <label className="flex cursor-pointer items-start gap-2 rounded-xl border border-destructive/30 p-2.5 text-base font-semibold text-foreground/85">
                <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={perdido} onChange={(e) => setPerdido(e.target.checked)} />
                <span>Marcar perdido: no responde <span className="font-normal text-[var(--muted-foreground-strong)]">(ya van {intentosPrevios} intentos sin respuesta; sale de tu cartera; deshacer desde el aviso)</span></span>
              </label>
            )}

            {muestraSiguiente && campos && (
              <div className="space-y-2 rounded-xl border border-[var(--accent)]/40 p-2.5">
                {siguienteOpcional ? (
                  <label className="flex cursor-pointer items-start gap-2 text-base font-semibold text-foreground/85">
                    <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={agendar} onChange={(e) => setAgendar(e.target.checked)} />
                    <span>Agendar próxima acción <span className="font-normal text-[var(--muted-foreground-strong)]">(puedes ajustar el tipo, la fecha y la hora)</span></span>
                  </label>
                ) : (
                  <p className="text-base font-bold text-[var(--muted-foreground-strong)]">{campos.tipo === 'reunion' ? 'La cita' : 'Cuándo volver a llamar'}</p>
                )}
                {(!siguienteOpcional || agendar) && (
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div className="sm:col-span-2">
                      <Label htmlFor="siguiente-tipo">Tipo de próxima acción</Label>
                      <Select id="siguiente-tipo" value={campos.tipo} onChange={(e) => {
                        const tipo = e.target.value
                        if (!esTipoTarea(tipo) || !tiposSiguientes.includes(tipo)) return
                        editar({ tipo, ...(!tituloEditado ? { titulo: tituloProximaAccion(tipo, nombre) } : {}) })
                      }}>
                        {TIPOS_TAREA.filter((t) => tiposSiguientes.includes(t.k)).map((t) => <option key={t.k} value={t.k}>{t.label}</option>)}
                      </Select>
                    </div>
                    <div className="sm:col-span-2">
                      <Label htmlFor="siguiente-titulo" className="text-base">Título</Label>
                      <Input id="siguiente-titulo" value={campos.titulo} onChange={(e) => { setTituloEditado(true); editar({ titulo: e.target.value }) }} className="h-10 text-base" maxLength={200} />
                    </div>
                    <div>
                      <Label htmlFor="siguiente-fecha" className="text-base">Fecha</Label>
                      <Input id="siguiente-fecha" type="date" value={campos.fecha} onChange={(e) => editar({ fecha: e.target.value })} className="h-10 text-base" />
                    </div>
                    <div>
                      <Label htmlFor="siguiente-hora" className="text-base">Hora</Label>
                      <Input id="siguiente-hora" type="time" value={campos.hora} onChange={(e) => editar({ hora: e.target.value })} className="h-10 text-base" />
                    </div>
                    {(campos.tipo === 'llamada' || campos.tipo === 'whatsapp') && (
                      <p className="sm:col-span-2 text-base text-[var(--muted-foreground-strong)]">Ventana legal: lunes a sábado, 07:00–20:00 (Lima).</p>
                    )}
                    {campos.tipo === 'reunion' && (
                      <div className="sm:col-span-2"><CamposReunion valor={camposReunion} onChange={setCamposReunion} /></div>
                    )}
                  </div>
                )}
              </div>
            )}

            <p role="status" className={noInsista || lead.no_contactar ? 'text-base text-muted-foreground' : 'sr-only'}>
              {(noInsista || lead.no_contactar) ? 'No volver a contactar: no se agendará una próxima acción.' : ''}
            </p>

            {def && !soyDueno && !descarta && !noInsista && (
              <p className="text-base text-muted-foreground">La agenda es del analista dueño del lead: se registra la llamada sin agendar el siguiente paso.</p>
            )}

            {tarea && (
              <label className="flex cursor-pointer items-start gap-2 text-base font-semibold text-foreground/85">
                <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={cierraTarea} onChange={(e) => setCierraTarea(e.target.checked)} />
                <span>Cerrar también «{presentarCitas(tarea.titulo)}» <span className="font-normal text-muted-foreground">({tareaAEvento(tarea, ahora).cuando})</span></span>
              </label>
            )}

            <Textarea aria-label="Nota de la llamada" value={nota} onChange={(e) => setNota(e.target.value)} placeholder="Nota (opcional)…" className="min-h-[56px] text-base" />
          </fieldset>
          {sinConfirmar && <p role="alert" className="text-base text-destructive">El guardado todavía no está confirmado. Reintenta la misma operación para comprobar su resultado.</p>}
        </DialogBody>
        <DialogFooter>
          {/* Con un guardado sin confirmar NO se afirma que no quedó nada: el
              servidor pudo haberlo escrito. Queda en «Guardados por confirmar». */}
          <Button variant="ghost" size="sm" disabled={procesando} onClick={() => {
            onClose()
            if (sinConfirmar) toast.warning('Guardado pendiente de confirmar: verifícalo en «Guardados por confirmar»')
            else toast.info('Llamada sin registrar: no quedó en el historial')
          }}>
            {sinConfirmar ? 'Cerrar (pendiente de confirmar)' : 'Cerrar sin registrar'}
          </Button>
          {sinConfirmar
            ? <Button size="sm" disabled={procesando} onClick={() => void enviar(sinConfirmar)}>{procesando ? 'Confirmando…' : 'Reintentar guardado'}</Button>
            : <Button size="sm" disabled={procesando || !resultado} onClick={guardar}>{procesando ? 'Guardando…' : 'Guardar'}</Button>}
        </DialogFooter>
      </div>
    </Dialog>
  )
}
