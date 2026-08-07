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
  'conversiones',
  'ranking-vendedores',
  'reuniones',
  'metas',
  'rendimiento',
  'capital-cierres',
  'pipeline',
  'cartera',
  'agenda',
  'mi-cartera',
  'repartir',
  'equipo',
  'config',
  'config-usuarios',
  'config-productos',
  'config-metas',
  'config-sla',
] as const
export type Vista = (typeof VISTAS)[number]

/** Rutas internas del panel de gobierno; no se duplican en el menú lateral. */
export const VISTAS_CONFIGURACION = [
  'config-usuarios',
  'config-productos',
  'config-metas',
  'config-sla',
] as const satisfies readonly Vista[]
export type VistaConfiguracion = (typeof VISTAS_CONFIGURACION)[number]

export function esVistaConfiguracion(vista: Vista): vista is VistaConfiguracion {
  return (VISTAS_CONFIGURACION as readonly Vista[]).includes(vista)
}

/** Vistas de inteligencia exclusivas de Gerencia; no son operación de leads. */
export const VISTAS_GERENCIA = [
  'conversiones',
  'ranking-vendedores',
  'reuniones',
  'metas',
  'rendimiento',
] as const satisfies readonly Vista[]

export function esVistaGerencia(vista: Vista): boolean {
  return (VISTAS_GERENCIA as readonly Vista[]).includes(vista)
}

/**
 * Vistas del MUNDO LEADS, gateadas por FUNCIONES_LEADS_APROBADAS (config.ts):
 * mientras Miguel no las apruebe, no aparecen en NAV ni son alcanzables por URL
 * para cuentas reales (el demo sí las muestra). Fuente única para sidebar y App.
 */
export const VISTAS_LEADS = ['hoy', 'pipeline', 'cartera', 'agenda'] as const satisfies readonly Vista[]

export function esVistaLeads(vista: Vista): boolean {
  return (VISTAS_LEADS as readonly Vista[]).includes(vista)
}

export interface RutaHash {
  vista: Vista | null // null → ruta desconocida o vacía (el caller decide el default)
  leadId: string | null
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
}

/** Resuelve un segmento de ruta (vista real o alias heredado) a una Vista, o null. */
function resolverVista(seg: string | undefined): Vista | null {
  if (esVista(seg)) return seg
  // Object.hasOwn evita que claves del prototipo ('constructor', 'toString',
  // '__proto__'…) resuelvan a un miembro heredado en vez de a null.
  const alias = seg != null && Object.hasOwn(ALIAS_HEREDADO, seg) ? ALIAS_HEREDADO[seg] : undefined
  return alias ?? null
}

/** Hash canónico de una vista (+ lead opcional). */
export function hashDe(vista: Vista, leadId?: string | null): string {
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
  return { vista, leadId }
}

/**
 * Escribe el hash SI difiere del actual (comparar antes de escribir evita
 * bucles hash⇄estado). Por defecto empuja una entrada de historial (back/
 * forward funcionan); con `reemplazar` corrige la URL sin ensuciar el
 * historial (rutas desconocidas, leads fuera de ámbito). OJO: replaceState
 * NO dispara `hashchange` — el caller ya debe tener el estado correcto.
 */
export function escribirHash(vista: Vista, leadId?: string | null, reemplazar = false): void {
  const destino = hashDe(vista, leadId)
  if (window.location.hash === destino) return
  if (reemplazar) {
    history.replaceState(null, '', destino)
  } else {
    window.location.hash = destino
  }
}
