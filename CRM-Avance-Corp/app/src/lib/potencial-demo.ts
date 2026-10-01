// Potencial del lead en MODO DEMO (sin red): las marcas viven en memoria.
//
// La demo enseña la función encendida: unos pocos leads de `LEADS_DEMO` traen
// marca para que las cuatro vistas tengan algo que pintar, y marcar funciona en
// local y reinicia el reloj, igual que en el servidor. No se guarda en
// `sessionStorage`: recargar la pestaña devuelve las marcas sembradas.
//
// Va fuera del store del CRM a propósito: en sesión real la marca tampoco viaja
// en la fila del lead (se lee por ids), y así los dos mundos tienen la misma
// forma (`PotencialLead`).
//
// ⚠️ El ESPEJO de la regla de caducidad vive AQUÍ y solo aquí. La regla es del
// servidor (`private.potencial_nivel_tras`, `private.dias_lunes_a_sabado`); la
// demo no tiene servidor y por eso la imita. La sesión real NO lo usa nunca:
// ni para pintar ni para el instante optimista (ver `potencialRecienMarcado`).
import { fechaLima } from './agenda-derivada'
import { potencialRecienMarcado, sumarDiasFecha, type NivelPotencial, type PotencialLead } from './potencial'

// ── Espejo demo de la regla de caducidad ─────────────────────────────────────

/** Días completos sin gestión con los que cada nivel baja. Frío no baja. */
const DIAS_PARA_BAJAR: Record<NivelPotencial, number | null> = { estrella: 5, tibio: 10, frio: null }

export function nivelAlBajar(nivel: NivelPotencial): 'tibio' | 'frio' | null {
  if (nivel === 'estrella') return 'tibio'
  if (nivel === 'tibio') return 'frio'
  return null
}

function esDomingo(fecha: string): boolean {
  return new Date(`${fecha}T00:00:00Z`).getUTCDay() === 0
}

/**
 * Días COMPLETOS de lunes a sábado estrictamente entre dos fechas (ninguna de
 * las dos puntas cuenta; los domingos tampoco).
 */
export function diasLunesASabado(desde: string, hasta: string): number {
  let dias = 0
  for (let dia = sumarDiasFecha(desde, 1); dia < hasta; dia = sumarDiasFecha(dia, 1)) {
    if (!esDomingo(dia)) dias += 1
  }
  return dias
}

/**
 * Primer día cuya madrugada bajaría la marca si nadie gestiona, contando desde
 * el día del reloj (la última marca o el último contacto). null si no baja.
 */
export function fechaDeBajada(nivel: NivelPotencial, relojDia: string): string | null {
  const limite = DIAS_PARA_BAJAR[nivel]
  if (limite == null) return null
  let dias = 0
  for (let salto = 1; salto <= 60; salto += 1) {
    const dia = sumarDiasFecha(relojDia, salto)
    if (dias >= limite) return dia
    if (!esDomingo(dia)) dias += 1
  }
  return null
}

// ── Marcas en memoria ────────────────────────────────────────────────────────

interface MarcaDemo {
  nivel: NivelPotencial
  /** El nivel que puso la persona; distinto de `nivel` si la marca bajó sola. */
  nivelMarcado: NivelPotencial
  /** Días de calendario desde la última gestión o marca al sembrar la demo. */
  haceDias: number
  /** Si se marcó en esta sesión, el instante: su reloj ya no depende de `haceDias`. */
  marcadoEn?: number
}

// Sembrado: una Estrella a punto de bajar, un Tibio, un Tibio que bajó solo de
// Estrella y un Frío para el analista uno; y una marca para cada compañero.
const SEMILLA: ReadonlyArray<readonly [string, MarcaDemo]> = [
  ['l17', { nivel: 'estrella', nivelMarcado: 'estrella', haceDias: 4 }],
  ['l2', { nivel: 'tibio', nivelMarcado: 'tibio', haceDias: 5 }],
  ['l16', { nivel: 'tibio', nivelMarcado: 'estrella', haceDias: 8 }],
  ['l1', { nivel: 'frio', nivelMarcado: 'frio', haceDias: 2 }],
  ['l4', { nivel: 'estrella', nivelMarcado: 'estrella', haceDias: 1 }],
  ['l6', { nivel: 'tibio', nivelMarcado: 'tibio', haceDias: 9 }],
]

let marcas: ReadonlyMap<string, MarcaDemo> = new Map(SEMILLA)
const oyentes = new Set<() => void>()

function publicar(siguiente: ReadonlyMap<string, MarcaDemo>): void {
  marcas = siguiente
  for (const avisar of oyentes) avisar()
}

/** Suscripción para `useSyncExternalStore`. */
export function suscribirPotencialDemo(avisar: () => void): () => void {
  oyentes.add(avisar)
  return () => { oyentes.delete(avisar) }
}

/** Foto inmutable de las marcas: cambia de identidad con cada marca nueva. */
export function leerPotencialDemo(): ReadonlyMap<string, MarcaDemo> {
  return marcas
}

/** Marcar en demo: vale lo del analista y el reloj vuelve a cero. */
export function marcarPotencialDemo(leadId: string, nivel: NivelPotencial, ahora = Date.now()): void {
  const siguiente = new Map(marcas)
  siguiente.set(leadId, { nivel, nivelMarcado: nivel, haceDias: 0, marcadoEn: ahora })
  publicar(siguiente)
}

/** Vuelve a las marcas sembradas (pruebas y cambio de sesión demo). */
export function reiniciarPotencialDemo(): void {
  publicar(new Map(SEMILLA))
}

/**
 * El ítem de un lead con la MISMA forma que sirve `crm.potencial_leads_fn`.
 * `puedeMarcar` lo decide quien llama (en demo: analista o supervisor).
 */
export function potencialDemoDe(
  leadId: string,
  foto: ReadonlyMap<string, MarcaDemo>,
  contexto: { puedeMarcar: boolean; hoy: string },
): PotencialLead {
  const marca = foto.get(leadId)
  if (!marca) {
    return {
      lead_id: leadId, nivel: null, origen: null, nivel_marcado: null, marcado_en: null,
      dias_sin_gestion: null, baja_a: null, baja_el: null, puede_marcar: contexto.puedeMarcar,
    }
  }
  // El reloj: el día en que se marcó en esta sesión, o los días que trae la semilla.
  const relojDia = marca.marcadoEn != null ? fechaLima(marca.marcadoEn) : sumarDiasFecha(contexto.hoy, -marca.haceDias)
  const marcadoEn = marca.marcadoEn ?? Date.parse(`${relojDia}T12:00:00-05:00`)
  return {
    ...potencialRecienMarcado({ lead_id: leadId, puede_marcar: contexto.puedeMarcar }, marca.nivel, marcadoEn),
    origen: marca.nivel === marca.nivelMarcado ? 'manual' : 'caducidad',
    nivel_marcado: marca.nivelMarcado,
    // Lo que en sesión real contesta el servidor, aquí lo calcula el espejo.
    dias_sin_gestion: diasLunesASabado(relojDia, contexto.hoy),
    baja_a: nivelAlBajar(marca.nivel),
    baja_el: fechaDeBajada(marca.nivel, relojDia),
  }
}
