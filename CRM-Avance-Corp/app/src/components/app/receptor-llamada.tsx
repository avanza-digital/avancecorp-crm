// components/app/receptor-llamada.tsx — el receptor del enlace del celular
// (F1.2.3 y F1.3.3 del plan «Llamadas desde el celular al CRM», 30/09/2026).
//
// MacroDroid abre «#/<vista>/llamada/<numero>» al colgar. Aquí se lee ese número
// UNA vez, se quita del hash (Atrás no debe volver a buscar), se piden los
// candidatos bajo RLS y se decide:
//  · único → se arma la intención de contacto (origen 'enlace'). Si alguna
//    AccionesContacto de ese lead está en pantalla («Ahora» de Mi día, una fila
//    de la cola) la toma y abre la encuesta con su propia lógica; si nadie la
//    toma en el siguiente tick, se abre la ficha del lead y la toma la suya.
//  · ambiguo / incompleto → se muestran los candidatos y elige la persona.
//  · sin coincidencia / inválido / error → aviso con búsqueda manual AQUÍ (la
//    barra global no existe en el celular) o reintento.
// Nada se autoselecciona salvo `unico`: el analista elige siempre el resultado.
// F4-b: si el enlace trae el id de la llamada («…/llamada/<numero>/<id>»), viaja
// con la intención —también si el lead se elige a mano— hasta la encuesta.
import { useCallback, useEffect, useId, useRef, useState, useSyncExternalStore, type FormEvent, type JSX } from 'react'
import { toast } from 'sonner'
import { llamadasCelularHabilitadas } from '@/lib/config'
import { PhoneCall, Search, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { buscarLeadsManual, resolverNumeroLlamada, type OpcionesResolucion } from '@/data/coincidencia-llamada'
import { useAuth } from '@/lib/auth-context'
import { textoBuscable } from '@/lib/cartera-keyset'
import { digitosParaBuscar, numeroCanonico, type Coincidencia } from '@/lib/coincidencia-telefono'
import { armarIntencion, cerrarIntencion, intencionDe, suscribirIntenciones } from '@/lib/intencion-contacto'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { puedeEscribir } from '@/lib/roles'
import { escribirHash, leerHash } from '@/lib/router'
import { useCRMData, usePanelesActions, useStoreEstado } from '@/lib/store-context'
import { ETAPAS, TERMINALES, type Etapa, type Lead } from '@/lib/tipos'

const suscribirHash = (cambio: () => void) => {
  window.addEventListener('hashchange', cambio)
  return () => window.removeEventListener('hashchange', cambio)
}
const fotoHash = () => window.location.hash

const MENSAJE_ERROR = 'No se pudo buscar el número en tus leads. Revisa tu conexión.'
/** Cuánto espera la demo a que lleguen sus leads antes de buscar con lo que haya. */
const ESPERA_DEMO_MS = 3_000
/**
 * Cuánto se le da a las AccionesContacto del lead (la tarjeta «Ahora», una fila
 * de la cola) para tomar la intención antes de abrir su ficha. Con 0 ms la
 * tarjeta perdía la carrera aunque estuviera en pantalla (visto tras el login,
 * 30/09): React pinta la tarjeta un instante después de que la cola cambia.
 */
const ESPERA_RECLAMO_MS = 600

type Aviso =
  | { fase: 'buscando'; numero: string }
  | { fase: 'aviso'; resultado: Exclude<Coincidencia<Lead>, { estado: 'unico' }> }

function etiquetaEtapa(etapa: Etapa): string {
  return [...ETAPAS, ...TERMINALES].find((e) => e.k === etapa)?.label ?? etapa
}

function listaNombres(leads: readonly Lead[]): string {
  return leads.map((l) => `${l.nombre_completo} (${etiquetaEtapa(l.etapa).toLowerCase()})`).join(', ')
}

export function ReceptorLlamada(): JSX.Element | null {
  const { yo } = useAuth()
  const { ambito, conocerLeads } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const { cargando } = useStoreEstado()
  useSyncExternalStore(suscribirHash, fotoHash, () => '')
  const { llamadaNumero: numeroEnHash, llamadaOrigenId: origenEnHash } = leerHash()
  const actor = yo?.id ?? null
  const rol = yo?.rol
  const demo = yo?.demo === true
  // Mientras la integración está cerrada, conservar el enlace F1 con teléfono
  // sin convertirlo en un guardado v5 que depende del backend aún pendiente.
  const origenLlamada = llamadasCelularHabilitadas(demo) ? origenEnHash : undefined
  const [captura, setCaptura] = useState<{ numero: string; origen?: string | undefined; intento: number } | null>(null)
  const [aviso, setAviso] = useState<Aviso | null>(null)
  // El ámbito local solo importa en la demo; por ref para no relanzar la búsqueda
  // cada vez que el store cambia.
  const leadsLocales = useRef(ambito.leads)
  leadsLocales.current = ambito.leads
  // La demo trae sus leads con una importación diferida y el store no lo anuncia
  // (`cargando` es solo de la sesión real). Visto en C1 el 30/09: tras el login
  // la búsqueda corría con la lista aún vacía y decía «ningún lead». Se espera a
  // que haya leads, con un tope por si la demo viniera vacía.
  const [demoAgotada, setDemoAgotada] = useState(false)
  const demoLista = !demo || ambito.leads.length > 0 || demoAgotada
  useEffect(() => {
    if (!demo || !captura || ambito.leads.length > 0) return
    const reloj = setTimeout(() => setDemoAgotada(true), ESPERA_DEMO_MS)
    return () => clearTimeout(reloj)
  }, [demo, captura, ambito.leads.length])

  // 1) Capturar el número y quitarlo del hash: Atrás no debe volver a buscar y
  //    el resto de la app sigue viendo su ruta de siempre.
  useEffect(() => {
    if (numeroEnHash === undefined || !actor) return
    const ruta = leerHash()
    if (ruta.vista) escribirHash(ruta.vista, ruta.leadId, true, ruta.inversionistaId, ruta.solicitudTasaId, ruta.detalleGestion)
    if (!puedeEscribir(rol)) {
      toast.info('Tu cuenta no registra llamadas.')
      return
    }
    setCaptura((previa) => ({ numero: numeroEnHash, origen: origenLlamada, intento: (previa?.intento ?? 0) + 1 }))
  }, [numeroEnHash, origenLlamada, actor, rol])

  const elegirLead = useCallback((lead: Lead, numero: string, origenLlamada: string | undefined) => {
    if (!actor) return
    conocerLeads([lead])
    // Solo se arma. Si pasa a ser la cabeza de la cola, el efecto de abajo le da
    // tiempo a las AccionesContacto del lead a tomarla y, si nadie lo hace, abre
    // su ficha. Si otra encuesta está abierta, espera detrás (F1.1.3).
    armarIntencion({ actor, leadId: lead.id, canal: 'tel', origen: 'enlace', numero, ...(origenLlamada ? { origenLlamada } : {}) })
    setAviso(null)
  }, [actor, conocerLeads])
  const elegirRef = useRef(elegirLead)
  elegirRef.current = elegirLead

  // 3) La cabeza de la cola, reactiva. Una intención del ENLACE que nadie toma en
  //    ESPERA_RECLAMO_MS se atiende abriendo la ficha del lead; si el lead ya no
  //    es visible, se cierra para que la cola no se atasque. Al cerrarse una
  //    encuesta, la siguiente de la cola pasa a cabeza y llega aquí sola.
  const cabeza = useSyncExternalStore(suscribirIntenciones, () => intencionDe(actor), () => null)
  useEffect(() => {
    if (!actor || !cabeza || cabeza.origen !== 'enlace' || cabeza.abierta) return
    const { id, leadId } = cabeza
    const reloj = setTimeout(() => {
      const vigente = intencionDe(actor, leadId)
      if (!vigente || vigente.id !== id || vigente.abierta) return
      // `abrirLead` avisa con `false` si el lead ya no es visible (su tipo admite void).
      void Promise.resolve(abrirLead(leadId)).then((visible) => { if (visible === false) cerrarIntencion(id) })
    }, ESPERA_RECLAMO_MS)
    return () => clearTimeout(reloj)
  }, [cabeza, actor, abrirLead])

  // 2) Resolver cuando el store esté listo (tras el login termina la carga real;
  //    en la demo, cuando ya hay leads).
  useEffect(() => {
    if (!captura || !actor || cargando || !demoLista) return
    const control = new AbortController()
    let vigente = true
    const canon = numeroCanonico(captura.numero)
    setAviso({ fase: 'buscando', numero: canon })
    const opciones: OpcionesResolucion = { demo, leadsLocales: leadsLocales.current, signal: control.signal }
    resolverNumeroLlamada(captura.numero, opciones).then((resultado) => {
      if (!vigente) return
      if (resultado.estado !== 'unico') {
        setAviso({ fase: 'aviso', resultado })
        return
      }
      // Número reciclado o ya cliente: se dice, pero el candidato es el lead vivo.
      if (resultado.terminales.length > 0) toast.info(`Ojo: este número también figura en ${listaNombres(resultado.terminales)}.`)
      elegirRef.current(resultado.lead, resultado.numero, captura.origen)
    }).catch(() => {
      if (vigente) setAviso({ fase: 'aviso', resultado: { estado: 'error', numero: canon, mensaje: MENSAJE_ERROR } })
    })
    return () => {
      vigente = false
      control.abort()
    }
  }, [captura, actor, demo, cargando, demoLista])

  if (!aviso) return null
  const reintentar = () => setCaptura((previa) => (previa ? { ...previa, intento: previa.intento + 1 } : previa))
  const manual: OpcionesResolucion = { demo, leadsLocales: leadsLocales.current }
  return (
    <section aria-label="Llamada desde el celular" className="px-3 pt-3 sm:px-6">
      {/* `status` (polite): la pantalla sigue operable; nada urgente que interrumpir. */}
      <div role="status" className="rounded-xl border border-warning/30 bg-warning/5 px-3 py-2.5 text-sm text-warning-text">
        <div className="flex items-start gap-2">
          <PhoneCall aria-hidden className="mt-0.5 size-4 shrink-0" />
          <div className="min-w-0 flex-1 space-y-2">
            {aviso.fase === 'buscando'
              ? <p aria-busy className="font-semibold text-foreground">Buscando a quién pertenece {telefonoLegible(aviso.numero)}…</p>
              : <Resultado resultado={aviso.resultado} manual={manual} onReintentar={reintentar}
                  onElegir={(lead) => elegirLead(lead, aviso.resultado.numero, captura?.origen)} />}
          </div>
          <Button type="button" variant="ghost" size="icon" className="-mr-1 -mt-1 size-8 shrink-0 pointer-coarse:size-11" aria-label="Cerrar el aviso de la llamada" onClick={() => setAviso(null)}>
            <X />
          </Button>
        </div>
      </div>
    </section>
  )
}

function Resultado({ resultado, manual, onElegir, onReintentar }: {
  resultado: Exclude<Coincidencia<Lead>, { estado: 'unico' }>
  manual: OpcionesResolucion
  onElegir: (lead: Lead) => void
  onReintentar: () => void
}): JSX.Element {
  const legible = telefonoLegible(resultado.numero)
  const digitos = digitosParaBuscar(resultado.numero) ?? ''
  switch (resultado.estado) {
    case 'ambiguo':
    case 'incompleto':
      return (
        <>
          <p className="font-semibold text-foreground">
            {resultado.leads.length === 0
              ? `Hay demasiados leads con dígitos parecidos a ${legible}. Búscalo por nombre.`
              : `${resultado.leads.length} leads tienen el número ${legible}. ¿A quién llamaste?`}
          </p>
          {resultado.leads.length > 0 && <ListaLeads etiqueta="Leads con este número" leads={resultado.leads} onElegir={onElegir} />}
          {resultado.estado === 'incompleto' && (
            <>
              {resultado.leads.length > 0 && <p>Puede haber más: si no está aquí, búscalo.</p>}
              <BusquedaManual inicial={digitos} manual={manual} onElegir={onElegir} />
            </>
          )}
        </>
      )
    case 'sin_coincidencia':
      return (
        <>
          <p className="font-semibold text-foreground">
            Ningún lead de tu cartera tiene el número {legible}.{!resultado.reconocido && ' No parece un teléfono completo.'}
          </p>
          {resultado.terminales.length > 0 && <p>Figura en {listaNombres(resultado.terminales)}.</p>}
          <BusquedaManual inicial={digitos} manual={manual} onElegir={onElegir} />
        </>
      )
    case 'invalido':
      return (
        <>
          <p className="font-semibold text-foreground">
            El celular no entregó un número reconocible{resultado.numero ? ` («${resultado.numero}»)` : ''}. Busca el lead a mano.
          </p>
          <BusquedaManual inicial="" manual={manual} onElegir={onElegir} />
        </>
      )
    case 'error':
      return (
        <>
          <p className="font-semibold text-foreground">{resultado.mensaje}</p>
          <Button type="button" size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" onClick={onReintentar}>Reintentar</Button>
        </>
      )
  }
}

function ListaLeads({ etiqueta, leads, onElegir }: { etiqueta: string; leads: readonly Lead[]; onElegir: (lead: Lead) => void }): JSX.Element {
  return (
    <ul aria-label={etiqueta} className="flex flex-wrap gap-2">
      {leads.map((l) => (
        <li key={l.id}>
          {/* 44 px en el celular (Ley de Fitts), como la franja «Ahora» de Mi día. */}
          <Button type="button" size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" onClick={() => onElegir(l)}>
            {l.nombre_completo} · {etiquetaEtapa(l.etapa)} · {telefonoLegible(l.telefono)}
          </Button>
        </li>
      ))}
    </ul>
  )
}

/**
 * La misma búsqueda de la barra (nombre, teléfono o DNI), aquí porque en el celular no hay barra. La reutiliza
 * «Elegir el lead» de la pestaña «Llamadas del celular» (F4-b).
 */
export function BusquedaManual({ inicial, manual, onElegir }: { inicial: string; manual: OpcionesResolucion; onElegir: (lead: Lead) => void }): JSX.Element {
  const id = useId()
  const [texto, setTexto] = useState(inicial)
  const [resultados, setResultados] = useState<Lead[] | null>(null)
  const [buscando, setBuscando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const control = useRef<AbortController | null>(null)
  useEffect(() => () => control.current?.abort(), [])

  const buscar = async (e: FormEvent) => {
    e.preventDefault()
    control.current?.abort()
    const propio = new AbortController()
    control.current = propio
    setBuscando(true)
    setError(null)
    try {
      const encontrados = await buscarLeadsManual(texto, { ...manual, signal: propio.signal })
      if (!propio.signal.aborted) setResultados(encontrados)
    } catch (causa) {
      if (!propio.signal.aborted) setError(causa instanceof Error ? causa.message : 'No se pudo buscar.')
    } finally {
      if (!propio.signal.aborted) setBuscando(false)
    }
  }

  return (
    <form onSubmit={(e) => void buscar(e)} className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <label htmlFor={id} className="sr-only">Buscar lead por nombre, teléfono o DNI</label>
        <input
          id={id}
          type="search"
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          placeholder="Nombre, teléfono o DNI"
          className="h-9 min-w-0 flex-1 rounded-lg border border-input bg-background px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:border-ring focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30 pointer-coarse:h-11"
        />
        <Button type="submit" size="sm" variant="outline" className="h-9 text-foreground pointer-coarse:h-11" disabled={buscando || textoBuscable(texto) === null} aria-busy={buscando || undefined}>
          <Search /> Buscar
        </Button>
      </div>
      {error && <p role="alert" className="text-xs text-destructive-text">{error}</p>}
      <p aria-live="polite" className="sr-only">
        {buscando ? 'Buscando leads' : resultados ? `${resultados.length} resultados en tus leads` : ''}
      </p>
      {resultados && (resultados.length === 0
        ? <p>Sin resultados en tus leads para «{texto.trim()}».</p>
        : <ListaLeads etiqueta="Resultados de la búsqueda" leads={resultados} onElegir={onElegir} />)}
    </form>
  )
}
