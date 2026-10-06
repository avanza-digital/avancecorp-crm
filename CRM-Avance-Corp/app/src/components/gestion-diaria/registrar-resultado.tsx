import { textoEnlace } from '@/lib/llamadas-celular'
// Panel «Registrar resultado de la llamada» (Gestión Diaria F2, mockup 5).
// Es la ÚNICA definición del resultado de una llamada en el CRM: lo montan las
// acciones de contacto (colas, Hoy, ficha), el cierre de una tarea de llamada
// y el composer del drawer. Paso 1 = uno de siete resultados (atajos 1–7);
// paso 2 = lo que ese resultado exige (fecha, cita, submotivo o la decisión del
// analista ante un número errado); nota opcional; «Guardar».
//
// DOS PRESENTACIONES, UNA SOLA LÓGICA (27/09/2026, diseño de Gestión Diaria):
// `useRegistroResultado` guarda el estado, las reglas espejo del servidor y el
// envío; `CamposResultado` pinta los dos pasos. `RegistrarResultado` los monta
// en el `Dialog` de siempre (ficha, Hoy, colas, composer: su contrato no
// cambia) y `RegistroResultadoTarjeta` dentro de la tarjeta «Ahora» de «Mi
// día», sin ventana encima. La tarjeta NO finge un diálogo (hallazgo de Codex):
// tiene su propio contrato de teclado —atajos 1–7 solo con el foco dentro de
// ella y fuera de un campo, Escape = «Cerrar sin registrar» salvo mientras
// guarda— y el foco lo maneja quien la monta.
//
// El paso 1 (los siete resultados, sus atajos y «Cambiar resultado») es el
// componente compartido `SelectorResultado` (03/10/2026): aquí solo se le pasa
// el estado y dónde valen los atajos (`dentro`).
//
// Nada en silencio: el toast enumera lo que ocurrió DE VERDAD (registrado,
// tarea cerrada, etapa, siguiente, descarte, No insistir) y ofrece «Deshacer»
// 15 s, que llama a `crm.deshacer_resultado_llamada` (24 h, solo el autor).
// La regla comercial vive en el servidor (`crm.registrar_llamada_v4`): aquí
// solo se arma la petición y se espeja lo que él rechazaría.
import { useEffect, useId, useMemo, useRef, useState, type JSX, type KeyboardEvent as EventoTeclado } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { RadioGroup, type OpcionRadio } from '@/components/ui/radio-group'
import { Textarea } from '@/components/ui/textarea'
import { CAMPOS_REUNION_VACIOS, CamposReunion, camposTareaDeReunion, type EstadoCamposReunion } from '@/components/app/campos-reunion'
import { SelectorResultado } from '@/components/gestion-diaria/selector-resultado'
import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
import { fechaLima, horaLima, proximoSlotSugerido, tareaAEvento } from '@/lib/agenda-derivada'
import { useAhora } from '@/lib/ahora'
import { useAuth } from '@/lib/auth-context'
import { camposDeSugerencia, isoDeCampos, tituloProximaAccion, type CamposSiguiente } from '@/lib/campos-siguiente'
import { useIntencionContacto } from '@/lib/intencion-contacto'
import { cuandoFueLaLlamada } from '@/lib/origen-llamada'
import { evidenciaNoResponde } from '@/lib/descarte-evidencia'
import { esPlanVivo } from '@/lib/plan-lead'
import { primerNombre } from '@/lib/format'
import { slotHabil, sugerirSiguiente } from '@/lib/motor-siguiente'
import {
  INTENTOS_PARA_OFRECER_PERDIDO, SUBMOTIVOS, definicionResultado, dentroDeVentanaLegal, etiquetaResultado, tiposSiguientesDeResultado,
  type ResultadoLlamada, type SubmotivoLlamada,
} from '@/lib/resultado-llamada'
import { validarReunionOperativa } from '@/lib/reunion-operativa'
import { useCRMData } from '@/lib/store-context'
import type { RegistrarLlamadaInput } from '@/lib/store'
import { presentarCitas } from '@/lib/terminologia'
import { cn } from '@/lib/utils'
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
   *  siguiente fila de la cola del día. `onClose` se dispara igual, ANTES. */
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

/**
 * La lógica ÚNICA del resultado de una llamada. `dentro` dice si una tecla
 * pertenece a esta presentación (el diálogo o la tarjeta): los atajos de un
 * carácter se acotan al componente (WCAG 2.1.4), nunca a cualquier cosa que
 * esté en pantalla. El hook no escucha el teclado: lo devuelve para que
 * `SelectorResultado` acote sus atajos.
 */
function useRegistroResultado(
  { lead, tarea, notaInicial, onClose, onGuardado }: RegistrarResultadoProps,
  dentro: (objetivo: EventTarget | null) => boolean,
) {
  const { registrarLlamada, deshacerResultadoLlamada, tareasDe } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  // F4-b: si esta encuesta la abrió el enlace del celular con el id de la llamada, se dice de cuál es. La intención
  // abierta de este lead es la fuente común del diálogo y de la tarjeta «Ahora».
  const intencion = useIntencionContacto(yo?.id ?? null, lead.id)
  const llamadaCelular = intencion?.abierta && intencion.origenLlamada ? cuandoFueLaLlamada(intencion.origenLlamada, ahora) : null
  const historial = useActividadesDeLead(lead.id)
  const nombre = primerNombre(lead.nombre_completo)
  const soyDueno = lead.vendedor_id != null && lead.vendedor_id === yo?.id
  const pendientes = tareasDe(lead.id)

  const [resultado, setResultado] = useState<ResultadoLlamada | null>(null)
  const [mostrarOpciones, setMostrarOpciones] = useState(true)
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

  // Lo llama `SelectorResultado` (clic o atajo). La regla «contraído = solo el
  // mismo atajo» y el foco ya los aplica él; aquí queda el seguro de «guardando».
  const elegir = (r: ResultadoLlamada) => {
    if (enviando.current || sinConfirmar) return
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
  const alternarOpciones = () => setMostrarOpciones((abierto) => !abierto)

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

  useEffect(() => { setNota(notaInicial ?? '') }, [notaInicial])

  const armar = (): RegistrarLlamadaInput | string => {
    if (!def) return 'Elige el resultado de la llamada'
    const entrada: RegistrarLlamadaInput = { resultado: def.clave, detalle: nota.trim() || null, tarea_id: tarea && cierraTarea ? tarea.id : null }
    if (intencion?.abierta && intencion.origenLlamada) {
      entrada.evento_origen_id = intencion.origenLlamada
      entrada.via_llamada = intencion.viaLlamada ?? 'al_colgar'
    }
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
      const enlace = confirmacion?.enlace ? textoEnlace(confirmacion.enlace, llamadaCelular ?? '') : null
      const texto = `${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}${enlace ? `. ${enlace}` : ''}`
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
  // Con un guardado sin confirmar NO se afirma que no quedó nada: el servidor
  // pudo haberlo escrito. Queda en «Guardados por confirmar».
  const cerrarSinRegistrar = () => {
    if (enviando.current) return
    onClose()
    if (sinConfirmar) toast.warning('Guardado pendiente de confirmar: verifícalo en «Guardados por confirmar»')
    else toast.info('Llamada sin registrar: no quedó en el historial')
  }

  const opcionesSubmotivo: OpcionRadio<SubmotivoLlamada>[] = def?.paso === 'submotivo'
    ? SUBMOTIVOS[def.clave as 'no_interesado' | 'pide_otro_producto'].map((s) => ({ valor: s.clave, etiqueta: s.etiqueta }))
    : []
  const opcionesDecision: OpcionRadio<DecisionNumero>[] = [
    ...(tieneSegundoNumero ? [{ valor: 'segundo_numero' as const, etiqueta: `Llamar al 2.º número (${lead.telefono_alternativo})`, detalle: 'Se agenda para hoy' }] : []),
    { valor: 'descartar' as const, etiqueta: 'Descartar por datos inválidos', detalle: 'Sale de tu cartera; puedes deshacerlo desde el aviso al guardar' },
    { valor: 'reintento' as const, etiqueta: 'Mantener con reintento a 7 días', detalle: 'Se agenda otra llamada' },
    { valor: 'solo_registrar' as const, etiqueta: 'Solo registrar', detalle: 'Sin tarea ni descarte' },
  ]

  /** Seguro SÍNCRONO de «está guardando»: `procesando` llega un render tarde. */
  const estaEnviando = () => enviando.current

  return {
    lead, tarea, nombre, soyDueno, ahora, estaEnviando, dentro, llamadaCelular,
    resultado, def, mostrarOpciones, alternarOpciones, elegir,
    submotivo, setSubmotivo, decision, setDecision, agendar, setAgendar, perdido, setPerdido,
    descartarInteres, setDescartarInteres, noInsista, setNoInsista, cierraTarea, setCierraTarea,
    nota, setNota, campos, editar, setTituloEditado, tituloEditado, camposReunion, setCamposReunion,
    procesando, sinConfirmar, enviar, guardar, cerrarSinRegistrar,
    intentosPrevios, ofrecePerdido, descarta, muestraSiguiente, siguienteOpcional, tiposSiguientes, cancelaria,
    opcionesSubmotivo, opcionesDecision,
  }
}
type ControlRegistro = ReturnType<typeof useRegistroResultado>

/**
 * Los dos pasos del resultado, iguales en el diálogo y en la tarjeta. `grande`
 * = el diálogo de siempre (piso de 16 px); sin él, la escala del diseño de
 * Gestión Diaria que lleva la tarjeta «Ahora» (27/09/2026).
 */
function CamposResultado({ c, grande, idBase }: { c: ControlRegistro; grande: boolean; idBase: string }): JSX.Element {
  const texto = grande ? 'text-base' : 'text-[13px]'
  // Un nombre de grupo POR INSTANCIA (revisión a11y, 27/09): la tarjeta sigue a
  // la vista mientras la ficha abre el diálogo, y dos grupos de radios con el
  // mismo `name` fuera de un <form> son UNO para el navegador (flechas que saltan
  // de uno a otro, marcas que se desmarcan solas, descripciones duplicadas).
  const sufijo = idBase.replaceAll(':', '')
  const ids = { opciones: `${idBase}-opciones`, submotivo: `${idBase}-submotivo`, tipo: `${idBase}-siguiente-tipo`, titulo: `${idBase}-siguiente-titulo`, fecha: `${idBase}-siguiente-fecha`, hora: `${idBase}-siguiente-hora` }
  const { def, campos } = c
  const congelado = c.procesando || c.sinConfirmar !== null
  return (
    // El selector va DENTRO del fieldset: mientras guarda (o queda por
    // confirmar), sus radios y «Cambiar resultado» quedan deshabilitados.
    <fieldset disabled={congelado} className="min-w-0 space-y-3">
      <SelectorResultado
        valor={c.resultado} abierto={c.mostrarOpciones} onElegir={c.elegir} onAlternar={c.alternarOpciones} dentro={c.dentro}
        nombre={sufijo} idOpciones={ids.opciones} leyenda="Resultado" grande={grande} deshabilitado={congelado}
        // La tarjeta es compacta: el detalle de cada opción queda para el diálogo.
        detalles={grande ? undefined : null}
        ayudaAtajos={grande ? 'Atajos: las teclas 1 a 7 eligen el resultado.' : 'Atajos: 1 a 7 eligen el resultado; Esc cierra sin registrar.'}
      />

      {def?.paso === 'submotivo' && (
        <div className="space-y-3">
          <div>
            <Label htmlFor={ids.submotivo} className={texto}>{def.clave === 'no_interesado' ? '¿Por qué no le interesa?' : '¿Qué producto pide?'} · obligatorio</Label>
            <Select id={ids.submotivo} required value={c.submotivo ?? ''} className={texto} onChange={(e) => {
              c.setSubmotivo(c.opcionesSubmotivo.find((s) => s.valor === e.target.value)?.valor ?? null)
            }}>
              <option value="" disabled>Selecciona un motivo</option>
              {c.opcionesSubmotivo.map((s) => <option key={s.valor} value={s.valor}>{s.etiqueta}</option>)}
            </Select>
          </div>
          <label className={cn('flex cursor-pointer items-start gap-2 font-semibold', texto)}>
            <input type="checkbox" className="mt-1 size-4 shrink-0 accent-[var(--accent)]" checked={c.descartarInteres} onChange={(e) => c.setDescartarInteres(e.target.checked)} />
            <span>Descartar y enviar al Centro de rescate</span>
          </label>
          {c.descartarInteres && <p className={cn('font-semibold text-foreground/85', texto)}>
            {c.nombre} saldrá de tu cartera hacia el Centro de rescate; puedes deshacerlo desde el aviso al guardar (el servidor lo admite 24 h).
            {c.cancelaria > 0 && ` Se cancelarán ${c.cancelaria} ${c.cancelaria === 1 ? 'tarea pendiente' : 'tareas pendientes'}.`}
          </p>}
          <label className={cn('flex cursor-pointer items-start gap-2 font-semibold text-foreground/85', texto)}>
            <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.noInsista} onChange={(e) => c.setNoInsista(e.target.checked)} />
            <span>Pidió que no lo vuelvan a llamar <span className="font-normal text-[var(--muted-foreground-strong)]">(Ley 29571; esta marca no se puede deshacer desde aquí)</span></span>
          </label>
          {!c.descartarInteres && <p className={cn('text-muted-foreground', texto)}>El lead se mantiene en tu cartera. Este resultado no lo descarta.</p>}
        </div>
      )}

      {def?.paso === 'decision_numero' && (
        <div className="space-y-2 rounded-xl border border-[var(--accent)]/40 p-2.5">
          <RadioGroup<DecisionNumero> grande={grande} leyenda="¿Qué hacemos con este número?" opciones={c.opcionesDecision} valor={c.decision} onCambio={c.setDecision} obligatorio nombre={`decision-numero-${sufijo}`} descripcion="Esta llamada cuenta como intento, pero no entra en la tasa de contacto." />
        </div>
      )}

      {c.ofrecePerdido && (
        <label className={cn('flex cursor-pointer items-start gap-2 rounded-xl border border-destructive/30 p-2.5 font-semibold text-foreground/85', texto)}>
          <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.perdido} onChange={(e) => c.setPerdido(e.target.checked)} />
          <span>Marcar perdido: no responde <span className="font-normal text-[var(--muted-foreground-strong)]">(ya van {c.intentosPrevios} intentos sin respuesta; sale de tu cartera; deshacer desde el aviso)</span></span>
        </label>
      )}

      {c.muestraSiguiente && campos && (
        <div className="space-y-2 rounded-xl border border-[var(--accent)]/40 p-2.5">
          {c.siguienteOpcional ? (
            <label className={cn('flex cursor-pointer items-start gap-2 font-semibold text-foreground/85', texto)}>
              <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.agendar} onChange={(e) => c.setAgendar(e.target.checked)} />
              <span>Agendar próxima acción <span className="font-normal text-[var(--muted-foreground-strong)]">(puedes ajustar el tipo, la fecha y la hora)</span></span>
            </label>
          ) : (
            <p className={cn('font-bold text-[var(--muted-foreground-strong)]', texto)}>{campos.tipo === 'reunion' ? 'La cita' : 'Cuándo volver a llamar'}</p>
          )}
          {(!c.siguienteOpcional || c.agendar) && (
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="sm:col-span-2">
                <Label htmlFor={ids.tipo} className={texto}>Tipo de próxima acción</Label>
                <Select id={ids.tipo} value={campos.tipo} className={texto} onChange={(e) => {
                  const tipo = e.target.value
                  if (!esTipoTarea(tipo) || !c.tiposSiguientes.includes(tipo)) return
                  c.editar({ tipo, ...(!c.tituloEditado ? { titulo: tituloProximaAccion(tipo, c.nombre) } : {}) })
                }}>
                  {TIPOS_TAREA.filter((t) => c.tiposSiguientes.includes(t.k)).map((t) => <option key={t.k} value={t.k}>{t.label}</option>)}
                </Select>
              </div>
              <div className="sm:col-span-2">
                <Label htmlFor={ids.titulo} className={texto}>Título</Label>
                <Input id={ids.titulo} value={campos.titulo} onChange={(e) => { c.setTituloEditado(true); c.editar({ titulo: e.target.value }) }} className={cn('h-10', texto)} maxLength={200} />
              </div>
              <div>
                <Label htmlFor={ids.fecha} className={texto}>Fecha</Label>
                <Input id={ids.fecha} type="date" value={campos.fecha} onChange={(e) => c.editar({ fecha: e.target.value })} className={cn('h-10', texto)} />
              </div>
              <div>
                <Label htmlFor={ids.hora} className={texto}>Hora</Label>
                <Input id={ids.hora} type="time" value={campos.hora} onChange={(e) => c.editar({ hora: e.target.value })} className={cn('h-10', texto)} />
              </div>
              {(campos.tipo === 'llamada' || campos.tipo === 'whatsapp') && (
                <p className={cn('text-[var(--muted-foreground-strong)] sm:col-span-2', texto)}>Ventana legal: lunes a sábado, 07:00–20:00 (Lima).</p>
              )}
              {campos.tipo === 'reunion' && (
                <div className="sm:col-span-2"><CamposReunion valor={c.camposReunion} onChange={c.setCamposReunion} /></div>
              )}
            </div>
          )}
        </div>
      )}

      <p role="status" className={c.noInsista || c.lead.no_contactar ? cn('text-muted-foreground', texto) : 'sr-only'}>
        {(c.noInsista || c.lead.no_contactar) ? 'No volver a contactar: no se agendará una próxima acción.' : ''}
      </p>

      {def && !c.soyDueno && !c.descarta && !c.noInsista && (
        <p className={cn('text-muted-foreground', texto)}>La agenda es del analista dueño del lead: se registra la llamada sin agendar el siguiente paso.</p>
      )}

      {c.tarea && (
        <label className={cn('flex cursor-pointer items-start gap-2 font-semibold text-foreground/85', texto)}>
          <input type="checkbox" className="mt-0.5 size-4 shrink-0 cursor-pointer accent-[var(--accent)]" checked={c.cierraTarea} onChange={(e) => c.setCierraTarea(e.target.checked)} />
          <span>Cerrar también «{presentarCitas(c.tarea.titulo)}» <span className="font-normal text-muted-foreground">({tareaAEvento(c.tarea, c.ahora).cuando})</span></span>
        </label>
      )}

      <Textarea aria-label="Nota de la llamada" value={c.nota} onChange={(e) => c.setNota(e.target.value)} placeholder="Nota (opcional)…" className={cn('min-h-[56px]', texto)} />
    </fieldset>
  )
}

/** El diálogo de siempre: ficha del lead, Hoy, colas y composer. Contrato intacto. */
export function RegistrarResultado(props: RegistrarResultadoProps): JSX.Element {
  const raiz = useRef<HTMLDivElement>(null)
  const idBase = useId()
  const c = useRegistroResultado(props, (objetivo) => {
    // Solo mientras ESTE diálogo tiene el foco (WCAG 2.1.4), no cualquier modal apilado.
    const dialogo = raiz.current?.closest<HTMLElement>('[role="dialog"]')
    return Boolean(dialogo) && objetivo instanceof Node && dialogo!.contains(objetivo)
  })
  return (
    // Escape o el fondo NO cierran mientras guarda. Se mira el seguro síncrono
    // (`estaEnviando`) y no `procesando`: entre el clic en «Guardar» y el render
    // siguiente hay un instante en que el estado aún dice «no» (Codex, 27/09).
    <Dialog open onClose={() => { if (!c.estaEnviando()) props.onClose() }} ariaLabel="Resultado de la llamada" className="w-[560px] [&_button]:text-base [&_select]:text-base [&_label]:text-base [&_p]:text-base">
      {/* Columna flex que hereda la altura del Dialog: sin esto el cuerpo no
          obtiene su scroll interno y «Guardar» queda fuera de la pantalla. */}
      <div ref={raiz} className="flex min-h-0 flex-1 flex-col">
        <DialogHeader>
          <DialogTitle className="text-xl">¿Cómo salió la llamada con {c.nombre}?</DialogTitle>
          <DialogDescription className="text-base">
            Registra el resultado y elige la próxima acción. Se guardan juntos en el historial y la agenda.
          </DialogDescription>
          {c.llamadaCelular && <p className="text-base font-semibold text-muted-foreground">Llamada del celular {c.llamadaCelular}.</p>}
        </DialogHeader>
        <DialogBody className="space-y-3">
          <CamposResultado c={c} grande idBase={idBase} />
          {c.sinConfirmar && <p role="alert" className="text-base text-destructive">El guardado todavía no está confirmado. Reintenta la misma operación para comprobar su resultado.</p>}
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" size="sm" disabled={c.procesando} onClick={c.cerrarSinRegistrar}>
            {c.sinConfirmar ? 'Cerrar (pendiente de confirmar)' : 'Cerrar sin registrar'}
          </Button>
          {c.sinConfirmar
            ? <Button size="sm" disabled={c.procesando} onClick={() => void c.enviar(c.sinConfirmar!)}>{c.procesando ? 'Confirmando…' : 'Reintentar guardado'}</Button>
            : <Button size="sm" disabled={c.procesando || !c.resultado} onClick={c.guardar}>{c.procesando ? 'Guardando…' : 'Guardar'}</Button>}
        </DialogFooter>
      </div>
    </Dialog>
  )
}

/**
 * El resultado DENTRO de la tarjeta «Ahora» de «Mi día» (diseño del 27/09/2026):
 * sin ventana encima. No finge un diálogo: es una sección con su título, y su
 * teclado es propio (atajos 1–7 con el foco dentro; Escape = cerrar sin
 * registrar, salvo mientras guarda). Al abrir, el foco va a los resultados.
 */
export function RegistroResultadoTarjeta(props: RegistrarResultadoProps): JSX.Element {
  const raiz = useRef<HTMLElement>(null)
  const idBase = useId()
  const c = useRegistroResultado(props, (objetivo) => objetivo instanceof Node && Boolean(raiz.current?.contains(objetivo)))
  useEffect(() => {
    raiz.current?.querySelector<HTMLInputElement>('input[type="radio"]')?.focus()
  }, [])
  const alTecla = (e: EventoTeclado<HTMLElement>) => {
    if (e.key !== 'Escape' || e.defaultPrevented || c.estaEnviando()) return
    e.preventDefault()
    e.stopPropagation()
    c.cerrarSinRegistrar()
  }
  return (
    // oxlint-disable-next-line jsx-a11y/no-noninteractive-element-interactions -- Escape de la sección: el contrato de teclado de la tarjeta (Codex, 27/09).
    <section ref={raiz} role="group" aria-labelledby={`${idBase}-titulo`} onKeyDown={alTecla} className="flex min-h-0 flex-1 flex-col">
      <div className="ac-scroll min-h-0 flex-1 space-y-3 overflow-y-auto px-[18px] pb-3 [&_:is(input,select,textarea,button)]:scroll-mb-20">
        <h4 id={`${idBase}-titulo`} className="text-sm font-extrabold text-primary">¿Qué pasó con la llamada?</h4>
        {c.llamadaCelular && <p className="text-[13px] font-semibold text-muted-foreground">Llamada del celular {c.llamadaCelular}.</p>}
        <CamposResultado c={c} grande={false} idBase={idBase} />
        {c.sinConfirmar && <p role="alert" className="text-[13px] font-semibold text-[var(--destructive-text)]">El guardado todavía no está confirmado. Reintenta la misma operación para comprobar su resultado.</p>}
      </div>
      {/* Pegado abajo también en el celular, donde la tarjeta no tiene alto fijo
          y la página es la que se desplaza: «Guardar» nunca queda fuera de la vista. */}
      <div className="sticky bottom-0 z-10 flex shrink-0 items-center justify-between gap-2 border-t border-border bg-card px-[18px] py-3">
        {/* `aria-disabled` y no `disabled` (regla de la casa): el botón pulsado
            conserva el foco aunque el guardado falle o quede sin confirmar. */}
        <button type="button" aria-disabled={c.procesando} onClick={c.cerrarSinRegistrar}
          className="inline-flex h-10 cursor-pointer items-center rounded-[10px] px-2.5 text-[13px] font-bold text-[var(--accent-press)] transition-colors hover:bg-accent/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50">
          {c.sinConfirmar ? 'Cerrar (pendiente de confirmar)' : 'Cerrar sin registrar'}
        </button>
        {c.sinConfirmar
          ? <Button className="h-10 rounded-[10px] bg-accent px-4 text-[13px] font-bold hover:bg-accent-press aria-disabled:cursor-default aria-disabled:opacity-50" aria-disabled={c.procesando} aria-busy={c.procesando || undefined}
            onClick={() => { if (!c.estaEnviando() && c.sinConfirmar) void c.enviar(c.sinConfirmar) }}>{c.procesando ? 'Confirmando…' : 'Reintentar guardado'}</Button>
          : <Button className="h-10 rounded-[10px] bg-accent px-4 text-[13px] font-bold hover:bg-accent-press aria-disabled:cursor-default aria-disabled:opacity-50" aria-disabled={c.procesando || !c.resultado} aria-busy={c.procesando || undefined}
            onClick={() => { if (!c.estaEnviando() && c.resultado) c.guardar() }}>{c.procesando ? 'Guardando…' : 'Guardar'}</Button>}
      </div>
    </section>
  )
}
