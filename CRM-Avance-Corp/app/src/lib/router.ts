// Router por hash del CRM — SIN dependencias (la fase de datos reales decidirá
// si se adopta un router de verdad). Formato de rutas:
//   #/hoy · #/pipeline · #/cartera · #/agenda · #/clientes · #/contratos ·
//   #/equipo · #/config
//   #/<vista>/lead/<id>   → misma vista con la ficha del lead abierta
// App.tsx sincroniza hash⇄estado; sidebar/topbar navegan con escribirHash().

export const VISTAS = ['hoy', 'pipeline', 'cartera', 'agenda', 'clientes', 'contratos', 'mi-cartera', 'equipo', 'config'] as const
export type Vista = (typeof VISTAS)[number]

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

/** Hash canónico de una vista (+ lead opcional). */
export function hashDe(vista: Vista, leadId?: string | null): string {
  return leadId ? `#/${vista}/lead/${encodeURIComponent(leadId)}` : `#/${vista}`
}

/** Lee y parsea el hash actual. Ruta desconocida → { vista: null, leadId: null }. */
export function leerHash(): RutaHash {
  // Acepta "#/hoy", "#hoy" y barras extra ("#/hoy/") — se normaliza al escribir.
  const crudo = window.location.hash.replace(/^#\/?/, '')
  const partes = crudo.split('/').filter(Boolean)
  const vista = esVista(partes[0]) ? partes[0] : null
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
