// Router por hash del CRM — SIN dependencias (la fase de datos reales decidirá
// si se adopta un router de verdad). Formato de rutas:
//   #/hoy · #/alertas · #/pipeline · #/cartera · #/agenda · #/mi-cartera · #/equipo · #/config
//   #/<vista>/lead/<id>   → misma vista con la ficha del lead abierta
// App.tsx sincroniza hash⇄estado y concentra la navegación entre vistas.
// Fase 6 (2026-07-21): 'clientes' y 'contratos' se retiraron — la pantalla
// unificada 'mi-cartera' las reemplaza para todos los roles.

// 'repartir' (C1, 2026-07-22) NO entra en VISTAS_LEADS a propósito: el gate de
// leads está cerrado para el coordinador y ocultaría la única pantalla que debe ver.
import { consultaCitasValida, type ConsultaCitasEnlace } from './enlace-citas'

export const VISTAS = [
  'hoy',
  'alertas',
  'seguimiento',
  // Gestión Diaria (19/09/2026): módulo propio del mundo leads; absorbe
  // Seguimiento en su última fase (cerrar → observar → derribar).
  'gestion-diaria',
  'conversiones',
  'ranking-vendedores',
  'reuniones',
  'metas',
  'rendimiento',
  'facturacion',
  'informes-empresas',
  'pipeline',
  'cartera',
  'agenda',
  'mi-cartera',
  'repartir',
  'rescate',
  'rescate-carpeta',
  'derivaciones',
  'equipo',
  'config',
  'config-usuarios',
  'config-productos',
  'config-metas',
  'config-sla',
  'config-gestion-diaria',
  'config-rentabilidad',
  'config-citas',
] as const
export type Vista = (typeof VISTAS)[number]

/** Rutas de trabajo alcanzables por enlace, sin duplicarse en el menú lateral. */
export const VISTAS_INTERNAS = ['rescate-carpeta'] as const satisfies readonly Vista[]
export type VistaInterna = (typeof VISTAS_INTERNAS)[number]

export function esVistaInterna(vista: Vista): vista is VistaInterna {
  return (VISTAS_INTERNAS as readonly Vista[]).includes(vista)
}

/** Rutas internas del panel de gobierno; no se duplican en el menú lateral. */
export const VISTAS_CONFIGURACION = [
  'config-usuarios',
  'config-productos',
  'config-metas',
  'config-sla',
  'config-gestion-diaria',
  'config-rentabilidad',
  'config-citas',
] as const satisfies readonly Vista[]
export type VistaConfiguracion = (typeof VISTAS_CONFIGURACION)[number]

export function esVistaConfiguracion(vista: Vista): vista is VistaConfiguracion {
  return (VISTAS_CONFIGURACION as readonly Vista[]).includes(vista)
}

/**
 * Vistas de inteligencia exclusivas de Gerencia; no son operación de leads.
 * 'facturacion' NO está aquí desde el 16/09/2026: la comparte Supervisión (ve su
 * equipo) y se gatea por la capacidad `verFacturacion` en vistas.ts.
 */
export const VISTAS_GERENCIA = [
  'conversiones',
  'ranking-vendedores',
  'reuniones',
  'metas',
  'rendimiento',
  'informes-empresas',
] as const satisfies readonly Vista[]

export function esVistaGerencia(vista: Vista): boolean {
  return (VISTAS_GERENCIA as readonly Vista[]).includes(vista)
}

/**
 * Vistas del MUNDO LEADS, gateadas por FUNCIONES_LEADS_APROBADAS (config.ts):
 * mientras Miguel no las apruebe, no aparecen en NAV ni son alcanzables por URL
 * para cuentas reales (el demo sí las muestra). Fuente única para sidebar y App.
 */
export const VISTAS_LEADS = ['hoy', 'seguimiento', 'gestion-diaria', 'pipeline', 'cartera', 'agenda', 'rescate', 'rescate-carpeta'] as const satisfies readonly Vista[]

export function esVistaLeads(vista: Vista): boolean {
  return (VISTAS_LEADS as readonly Vista[]).includes(vista)
}

export interface RutaHash {
  vista: Vista | null // null → ruta desconocida o vacía (el caller decide el default)
  leadId: string | null
  inversionistaId?: string
  solicitudTasaId?: string
  detalleGestion?: DetalleGestion
  /** El número que trae el enlace del celular al colgar (F1.2.1), tal cual llegó. */
  llamadaNumero?: string
  consultaCitas?: ConsultaCitasEnlace
  /** El id de esa llamada (`C1-1790980958`, F4-b), si la macro lo mandó y tiene la forma de la base. */
  llamadaOrigenId?: string
}

/**
 * Vistas que reciben el enlace del celular «#/<vista>/llamada/<numero>» (plan
 * «Llamadas desde el celular al CRM», F1.2.1): Hoy, como dice el plan, y
 * Gestión Diaria, donde aterriza la macro del piloto (Jhosep, 30/09/2026).
 * Desde F4-b puede traer el id de la llamada detrás: «…/llamada/<numero>/<id>».
 */
export const VISTAS_CON_LLAMADA = ['hoy', 'gestion-diaria'] as const satisfies readonly Vista[]

export function admiteLlamada(vista: Vista): boolean {
  return (VISTAS_CON_LLAMADA as readonly Vista[]).includes(vista)
}

/**
 * El número tal cual lo deja un marcador: `+` opcional y hasta 39 caracteres
 * entre dígitos (al menos uno), espacios, paréntesis, punto y guion. Los códigos
 * de servicio (`*123#`) no entran: no son leads. Acota lo que viaja en el hash;
 * canonizar y buscar es del receptor, no del router.
 */
const NUMERO_LLAMADA = /^\+?(?=.*\d)[0-9 ().-]{1,39}$/

export function numeroLlamadaValido(valor: string): boolean {
  return NUMERO_LLAMADA.test(valor)
}

/**
 * El id que la macro pone a cada llamada (F4-b): la etiqueta del celular y los
 * segundos de su reloj («C1-1790980958»). La MISMA forma que exige la base
 * (crm.registrar_llamada_v5); la ventana y el dueño del celular los decide ella.
 */
const ORIGEN_LLAMADA = /^C[1-9][0-9]{0,2}-[0-9]{10}$/

export function origenLlamadaValido(valor: string): boolean {
  return ORIGEN_LLAMADA.test(valor)
}

export type DetalleGestion = { tipo: 'equipo' | 'analista'; id: string } | { tipo: 'cola' }

function esVista(v: string | undefined): v is Vista {
  return v != null && (VISTAS as readonly string[]).includes(v)
}

/**
 * Alias de rutas HEREDADAS: vistas retiradas cuyo bookmark viejo debe seguir
 * cayendo en su reemplazo. 'clientes' y 'contratos' se fusionaron en 'mi-cartera'
 * (Fase 6): NO están en VISTAS (no se navega HACIA ellas), pero un enlace viejo
 * se resuelve a la cartera unificada en vez de degradar a la vista base (que
 * sería 'hoy' cuando leadsVisibles). Solo lectura; nunca se escribe un alias.
 */
const ALIAS_HEREDADO: Record<string, Vista> = {
  clientes: 'mi-cartera',
  contratos: 'mi-cartera',
  // N1 (F3 de «Conversión única», 2026-08-27): la ruta «Capital» estaba muerta
  // por autorización desde su nacimiento y todo lo que prometía vive en el
  // Resumen de Hoy. Un bookmark viejo cae ahí, no en una pantalla en blanco.
  'capital-cierres': 'hoy',
}

/** Resuelve un segmento de ruta (vista real o alias heredado) a una Vista, o null. */
function resolverVista(seg: string | undefined): Vista | null {
  if (esVista(seg)) return seg
  // Object.hasOwn evita que claves del prototipo ('constructor', 'toString',
  // '__proto__'…) resuelvan a un miembro heredado en vez de a null.
  const alias = seg != null && Object.hasOwn(ALIAS_HEREDADO, seg) ? ALIAS_HEREDADO[seg] : undefined
  return alias ?? null
}

const UUID_PERSONA = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
// Organigrama del modo demo (lib/demo.ts: d-ger, d-sup1, d-v1…): sin él, la
// gerencia demo no podría abrir un equipo ni un analista. Nunca coincide con un
// UUID real; en sesión real sólo lleva a «ya no aparece», sin consultar nada.
const ID_PERSONA_DEMO = /^d-[a-z0-9]{1,16}$/

/** Hash canónico de una vista y su ficha opcional. */
function detalleGestionValido(detalle: DetalleGestion | undefined): detalle is DetalleGestion {
  return !!detalle && (detalle.tipo === 'cola' || ((detalle.tipo === 'equipo' || detalle.tipo === 'analista')
    && (UUID_PERSONA.test(detalle.id) || ID_PERSONA_DEMO.test(detalle.id) || (detalle.tipo === 'equipo' && detalle.id === 'fuera'))))
}

export function hashDe(vista: Vista, leadId?: string | null, inversionistaId?: string, solicitudTasaId?: string, detalleGestion?: DetalleGestion, llamadaNumero?: string, consultaCitas?: ConsultaCitasEnlace, llamadaOrigenId?: string): string {
  if (vista === 'reuniones' && consultaCitasValida(consultaCitas)) {
    const periodo = consultaCitas.dia ? `dia/${consultaCitas.dia}` : `mes/${consultaCitas.mes}${consultaCitas.semana ? `/semana/${consultaCitas.semana}` : ''}`
    return `#/reuniones/${periodo}${consultaCitas.equipo ? `/equipo/${consultaCitas.equipo}` : ''}${leadId ? `/lead/${encodeURIComponent(leadId)}` : ''}`
  }
  if (vista === 'gestion-diaria' && detalleGestionValido(detalleGestion)) {
    const seccion = detalleGestion.tipo === 'cola' ? 'cola' : `${detalleGestion.tipo}/${detalleGestion.id}`
    return `#/gestion-diaria/${seccion}${leadId ? `/lead/${encodeURIComponent(leadId)}` : ''}`
  }
  if (vista === 'hoy' && !leadId && solicitudTasaId && UUID_PERSONA.test(solicitudTasaId)) return `#/hoy/solicitud-tasa/${solicitudTasaId}`
  if (vista === 'mi-cartera' && !leadId && inversionistaId && UUID_PERSONA.test(inversionistaId)) return `#/mi-cartera/inversionista/${inversionistaId}`
  // F1.2.1: el enlace del celular. Solo se codifica SU segmento (el `+` vuelve
  // intacto al leer) y solo sin ficha: al abrirse el lead, el número ya cumplió.
  if (!leadId && llamadaNumero !== undefined && admiteLlamada(vista) && numeroLlamadaValido(llamadaNumero)) {
    const id = llamadaOrigenId !== undefined && origenLlamadaValido(llamadaOrigenId) ? `/${llamadaOrigenId}` : ''
    return `#/${vista}/llamada/${encodeURIComponent(llamadaNumero)}${id}`
  }
  return leadId ? `#/${vista}/lead/${encodeURIComponent(leadId)}` : `#/${vista}`
}

/** Lee y parsea el hash actual. Ruta desconocida → { vista: null, leadId: null }. */
export function leerHash(): RutaHash {
  // Acepta "#/hoy", "#hoy" y barras extra ("#/hoy/") — se normaliza al escribir.
  const crudo = window.location.hash.replace(/^#\/?/, '')
  const partes = crudo.split('/').filter(Boolean)
  const vista = resolverVista(partes[0])
  const indiceEquipo = partes[1] === 'mes' && partes[3] === 'semana' ? 5 : 3
  const equipoCitas = partes[indiceEquipo] === 'equipo' ? { equipo: partes[indiceEquipo + 1] ?? '' } : {}
  const candidataCitas = vista === 'reuniones' && partes[2]
    ? partes[1] === 'dia' ? { dia: partes[2], ...equipoCitas }
      : partes[1] === 'mes' ? { mes: partes[2], ...(partes[3] === 'semana' ? { semana: partes[4] ?? '' } : {}), ...equipoCitas } : undefined
    : undefined
  const consultaCitas = consultaCitasValida(candidataCitas) ? candidataCitas : undefined
  let leadId: string | null = null
  const candidato = (partes[1] === 'cola' ? { tipo: 'cola' } : { tipo: partes[1], id: partes[2] }) as DetalleGestion
  const detalleGestion = vista === 'gestion-diaria' && detalleGestionValido(candidato) ? candidato : undefined
  const indiceLead = consultaCitas ? indiceEquipo + (consultaCitas.equipo ? 2 : 0) : detalleGestion?.tipo === 'cola' ? 2 : detalleGestion ? 3 : 1
  if (vista && partes[indiceLead] === 'lead' && partes[indiceLead + 1]) {
    try {
      leadId = decodeURIComponent(partes[indiceLead + 1]!)
    } catch {
      leadId = null // %-escape malformado en la URL → se ignora el lead
    }
  }
  const inversionistaId = vista === 'mi-cartera' && partes[1] === 'inversionista' && partes[2] && UUID_PERSONA.test(partes[2]) ? partes[2] : undefined
  const solicitudTasaId = vista === 'hoy' && partes[1] === 'solicitud-tasa' && partes[2] && UUID_PERSONA.test(partes[2]) ? partes[2] : undefined
  let llamadaNumero: string | undefined
  let llamadaOrigenId: string | undefined
  if (vista && admiteLlamada(vista) && partes[1] === 'llamada' && partes[2]) {
    try {
      // Llega codificado (`%2B51…`) o crudo (`+51…`): las dos formas dan el mismo número.
      const crudo = decodeURIComponent(partes[2])
      if (numeroLlamadaValido(crudo)) llamadaNumero = crudo
    } catch {
      // %-escape malformado → sin número (el receptor no tiene nada que buscar)
    }
    // El id de la llamada (F4-b) solo acompaña a un número válido; sin la forma de la base se ignora y el
    // enlace funciona como F1.
    if (llamadaNumero && partes[3] && origenLlamadaValido(partes[3])) llamadaOrigenId = partes[3]
  }
  return { vista, leadId, ...(inversionistaId ? {inversionistaId} : {}), ...(solicitudTasaId ? {solicitudTasaId} : {}), ...(detalleGestion ? { detalleGestion } : {}), ...(llamadaNumero ? { llamadaNumero } : {}), ...(llamadaOrigenId ? { llamadaOrigenId } : {}), ...(consultaCitas ? { consultaCitas } : {}) }
}

/**
 * Escribe el hash SI difiere del actual (comparar antes de escribir evita
 * bucles hash⇄estado). Por defecto empuja una entrada de historial (back/
 * forward funcionan); con `reemplazar` corrige la URL sin ensuciar el
 * historial (rutas desconocidas, leads fuera de ámbito). OJO: replaceState
 * NO dispara `hashchange` — el caller ya debe tener el estado correcto.
 */
export function escribirHash(vista: Vista, leadId?: string | null, reemplazar = false, inversionistaId?: string, solicitudTasaId?: string, detalleGestion?: DetalleGestion, llamadaNumero?: string, consultaCitas?: ConsultaCitasEnlace, llamadaOrigenId?: string): void {
  const destino = hashDe(vista, leadId, inversionistaId, solicitudTasaId, detalleGestion, llamadaNumero, consultaCitas, llamadaOrigenId)
  if (window.location.hash === destino) return
  if (reemplazar) {
    history.replaceState(null, '', destino)
  } else {
    window.location.hash = destino
  }
}

/** La ficha vuelve a comprobar ámbito y canonicalización en el servidor. */
export function abrirInversionista(id: string): void {
  escribirHash('mi-cartera', null, false, id)
}
