// Router por hash del CRM — SIN dependencias (la fase de datos reales decidirá
// si se adopta un router de verdad). Formato de rutas:
//   #/hoy · #/alertas · #/pipeline · #/cartera · #/agenda · #/mi-cartera · #/equipo · #/config
//   #/<vista>/lead/<id>   → misma vista con la ficha del lead abierta
// App.tsx sincroniza hash⇄estado y concentra la navegación entre vistas.
// Fase 6 (2026-07-21): 'clientes' y 'contratos' se retiraron — la pantalla
// unificada 'mi-cartera' las reemplaza para todos los roles.

// 'repartir' (C1, 2026-07-22) NO entra en VISTAS_LEADS a propósito: el gate de
// leads está cerrado para el coordinador y ocultaría la única pantalla que debe ver.
export const VISTAS = [
  'hoy',
  'alertas',
  'seguimiento',
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
export const VISTAS_LEADS = ['hoy', 'seguimiento', 'pipeline', 'cartera', 'agenda', 'rescate', 'rescate-carpeta'] as const satisfies readonly Vista[]

export function esVistaLeads(vista: Vista): boolean {
  return (VISTAS_LEADS as readonly Vista[]).includes(vista)
}

export interface RutaHash {
  vista: Vista | null // null → ruta desconocida o vacía (el caller decide el default)
  leadId: string | null
  inversionistaId?: string
  solicitudTasaId?: string
}

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

/** Hash canónico de una vista y su ficha opcional. */
export function hashDe(vista: Vista, leadId?: string | null, inversionistaId?: string, solicitudTasaId?: string): string {
  if (vista === 'hoy' && !leadId && solicitudTasaId && UUID_PERSONA.test(solicitudTasaId)) return `#/hoy/solicitud-tasa/${solicitudTasaId}`
  if (vista === 'mi-cartera' && !leadId && inversionistaId && UUID_PERSONA.test(inversionistaId)) return `#/mi-cartera/inversionista/${inversionistaId}`
  return leadId ? `#/${vista}/lead/${encodeURIComponent(leadId)}` : `#/${vista}`
}

/** Lee y parsea el hash actual. Ruta desconocida → { vista: null, leadId: null }. */
export function leerHash(): RutaHash {
  // Acepta "#/hoy", "#hoy" y barras extra ("#/hoy/") — se normaliza al escribir.
  const crudo = window.location.hash.replace(/^#\/?/, '')
  const partes = crudo.split('/').filter(Boolean)
  const vista = resolverVista(partes[0])
  let leadId: string | null = null
  if (vista && partes[1] === 'lead' && partes[2]) {
    try {
      leadId = decodeURIComponent(partes[2])
    } catch {
      leadId = null // %-escape malformado en la URL → se ignora el lead
    }
  }
  const inversionistaId = vista === 'mi-cartera' && partes[1] === 'inversionista' && partes[2] && UUID_PERSONA.test(partes[2]) ? partes[2] : undefined
  const solicitudTasaId = vista === 'hoy' && partes[1] === 'solicitud-tasa' && partes[2] && UUID_PERSONA.test(partes[2]) ? partes[2] : undefined
  return { vista, leadId, ...(inversionistaId ? {inversionistaId} : {}), ...(solicitudTasaId ? {solicitudTasaId} : {}) }
}

/**
 * Escribe el hash SI difiere del actual (comparar antes de escribir evita
 * bucles hash⇄estado). Por defecto empuja una entrada de historial (back/
 * forward funcionan); con `reemplazar` corrige la URL sin ensuciar el
 * historial (rutas desconocidas, leads fuera de ámbito). OJO: replaceState
 * NO dispara `hashchange` — el caller ya debe tener el estado correcto.
 */
export function escribirHash(vista: Vista, leadId?: string | null, reemplazar = false, inversionistaId?: string, solicitudTasaId?: string): void {
  const destino = hashDe(vista, leadId, inversionistaId, solicitudTasaId)
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
