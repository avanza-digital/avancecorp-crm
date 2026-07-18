// lib/agenda-ics.ts — la suscripción del calendario (feed ICS) como datos puros.
//
// El enlace se pega UNA vez en Google Calendar ("agregar calendario por URL")
// y las tareas pendientes del miembro aparecen solas en su celular. El token
// es el secreto: rotar = enlace anterior muerto. La edge que sirve el feed es
// crm-agenda-ics (verify_jwt=false; el token ES el control de acceso).

/** URL del feed ICS para pegar en Google/Apple/Outlook. */
export function urlFeedIcs(supabaseUrl: string, token: string): string {
  return `${supabaseUrl.replace(/\/+$/, '')}/functions/v1/crm-agenda-ics?t=${token}`
}

/** Pasos que ve el miembro en la tarjeta de Configuración (Google Calendar). */
export const PASOS_GOOGLE_CALENDAR: ReadonlyArray<string> = [
  'Copia tu enlace secreto con el botón de arriba.',
  'En Google Calendar (computadora): Otros calendarios → + → Desde una URL.',
  'Pega el enlace y confirma — tus tareas aparecerán solas, también en el celular.',
]
