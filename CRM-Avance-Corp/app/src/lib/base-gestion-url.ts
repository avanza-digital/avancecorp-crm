// Estado de la vista del supervisor (F4) en la URL, con el MISMO patrón que la carpeta del Centro de rescate
// (`rescate_carpeta` / `rescate_mes` en el `?` de la URL, junto al hash `#/rescate`): la pestaña y el analista elegido
// sobreviven a recargar la página o a compartir el enlace, sin tocar el router por hash.
//   ?rescate_vista=gestion&rescate_analista=<uuid>
//   ?rescate_vista=bases&rescate_base=<uuid>          (F5: la tercera pestaña y la base abierta)
// Sin parámetros = «Descartes del mes» (decisión de Miguel, 03/10: al entrar abre ahí).

export const PARAM_VISTA_SUPERVISION = 'rescate_vista'
export const PARAM_ANALISTA_SUPERVISION = 'rescate_analista'
export const PARAM_BASE_SUPERVISION = 'rescate_base'

export type VistaSupervision = 'descartes' | 'gestion' | 'bases'

/** La bandeja del equipo (leads sin analista) en la URL; dentro de la pantalla es la clave «sin dato» del filtro. */
export const ANALISTA_URL_SIN = 'sin-analista'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
// Organigrama del modo demo (lib/demo.ts: d-v1, d-v2…), como en lib/router.ts.
const ID_DEMO = /^d-[a-z0-9]{1,16}$/
// Las bases del espejo demo (lib/bases-cargadas-demo.ts): las dos de muestra y las que se crean en la sesión.
const BASE_DEMO = /^(?:feria-2025|descartes-julio|demo-nueva-\d{1,6})$/

export interface EstadoSupervision {
  vista: VistaSupervision
  /** `vendedor_id` del analista elegido, {@link ANALISTA_URL_SIN} para la bandeja o null (todos). */
  analista: string | null
  /** F5: la base abierta en la pestaña «Bases» (su id) o null (la hoja de bases). */
  base: string | null
}

/** Lee la pestaña y el analista de una URL. Lo que no se reconoce no se usa (nunca se filtra por un valor inventado). */
export function estadoSupervisionDe(href: string): EstadoSupervision {
  const parametros = new URL(href).searchParams
  const pedida = parametros.get(PARAM_VISTA_SUPERVISION)
  const vista: VistaSupervision = pedida === 'gestion' || pedida === 'bases' ? pedida : 'descartes'
  const crudo = parametros.get(PARAM_ANALISTA_SUPERVISION)
  const analista = vista === 'gestion' && crudo !== null && (crudo === ANALISTA_URL_SIN || UUID.test(crudo) || ID_DEMO.test(crudo)) ? crudo : null
  const baseCruda = parametros.get(PARAM_BASE_SUPERVISION)
  const base = vista === 'bases' && baseCruda !== null && (UUID.test(baseCruda) || BASE_DEMO.test(baseCruda)) ? baseCruda : null
  return { vista, analista, base }
}

/** La URL con el estado escrito. «Descartes del mes» es el valor por defecto: no deja parámetros. */
export function hrefConEstadoSupervision(href: string, estado: EstadoSupervision): string {
  const url = new URL(href)
  url.searchParams.delete(PARAM_VISTA_SUPERVISION)
  url.searchParams.delete(PARAM_ANALISTA_SUPERVISION)
  url.searchParams.delete(PARAM_BASE_SUPERVISION)
  if (estado.vista === 'gestion') {
    url.searchParams.set(PARAM_VISTA_SUPERVISION, 'gestion')
    if (estado.analista) url.searchParams.set(PARAM_ANALISTA_SUPERVISION, estado.analista)
  }
  if (estado.vista === 'bases') {
    url.searchParams.set(PARAM_VISTA_SUPERVISION, 'bases')
    if (estado.base) url.searchParams.set(PARAM_BASE_SUPERVISION, estado.base)
  }
  return url.toString()
}

/** Corrige la URL sin crear una entrada de historial (como la ficha de un lead fuera de ámbito en el router). */
export function escribirEstadoSupervision(estado: EstadoSupervision): void {
  const destino = hrefConEstadoSupervision(window.location.href, estado)
  if (destino !== window.location.href) window.history.replaceState(window.history.state, '', destino)
}
