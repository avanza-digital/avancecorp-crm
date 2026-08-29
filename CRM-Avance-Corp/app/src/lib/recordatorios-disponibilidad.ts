// F3 «Recordar» del plan «lead libre» (spec §5.3-§5.5): el recordatorio
// PERSONAL para volver a verificar un contacto ocupado. Este módulo es la
// frontera runtime de crm.recordatorios_disponibilidad y la derivación pura
// de su campana. NO es lib/recordatorio.ts (ese es el anti no-show de
// reuniones): nombres distintos a propósito, dominios distintos.
//
// Reglas del plan que este módulo encarna:
//  · el recordatorio no reserva, no prioriza, no toca el lead (§5.3) — aquí
//    solo viven contacto + fecha, jamás veredictos ni lead_id;
//  · la campana deriva EN CLIENTE y la re-verificación es BAJO DEMANDA al
//    clic (nunca N llamadas al abrir la bandeja);
//  · los vencidos >7 días caducan solos en el servidor — el cliente no
//    los filtra de más ni los revive.
import * as v from 'valibot'
import type { AlertaCRM } from './alertas'
import type { DisponibilidadLead } from './disponibilidad-lead'

/** Fila de crm.recordatorios_disponibilidad tal como la sirve PostgREST.
 *  Estricta: la RLS ya acota al dueño; una clave inesperada es un bug. */
export const RecordatorioDisponibilidadSchema = v.strictObject({
  id: v.pipe(v.string(), v.uuid()),
  perfil_id: v.pipe(v.string(), v.uuid()),
  telefono: v.string(),
  dni: v.nullable(v.string()),
  recordar_en: v.pipe(v.string(), v.isoTimestamp()),
  creado_en: v.pipe(v.string(), v.isoTimestamp()),
})

export const RecordatoriosDisponibilidadSchema = v.array(RecordatorioDisponibilidadSchema)

export type RecordatorioDisponibilidad = v.InferOutput<typeof RecordatorioDisponibilidadSchema>

/** Fila de la CAMPANA: SIN dni a propósito (minimización §8, F3.1 — ningún
 *  consumidor de la bandeja lo usa; solo el guardado devuelve la fila entera).
 *  Estricta: si el select trajera el dni de vuelta, esto lo delataría. */
export const RecordatorioCampanaSchema = v.strictObject({
  id: v.pipe(v.string(), v.uuid()),
  perfil_id: v.pipe(v.string(), v.uuid()),
  telefono: v.string(),
  recordar_en: v.pipe(v.string(), v.isoTimestamp()),
  creado_en: v.pipe(v.string(), v.isoTimestamp()),
})

export const RecordatoriosCampanaSchema = v.array(RecordatorioCampanaSchema)

export type RecordatorioCampana = v.InferOutput<typeof RecordatorioCampanaSchema>

/** Teléfono +519######## → «987 654 321» para leerse como se dicta. */
export function telefonoLegible(telefono: string): string {
  const nueve = telefono.startsWith('+51') ? telefono.slice(3) : telefono
  return nueve.length === 9
    ? `${nueve.slice(0, 3)} ${nueve.slice(3, 6)} ${nueve.slice(6)}`
    : telefono
}

export function fechaCortaLima(iso: string): string | null {
  const instante = Date.parse(iso)
  if (!Number.isFinite(instante)) return null
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima',
    day: 'numeric',
    month: 'long',
  }).format(instante)
}

/**
 * La campana (§5.4): SOLO los recordatorios ya vencidos se vuelven alertas —
 * uno vigente todavía no recuerda nada. Severidad 'atencion' (nada arde:
 * es una oportunidad, no un incumplimiento), alcance personal, y la acción
 * real —verificar— la ejecuta la pantalla abriendo el alta con el teléfono
 * precargado: el MISMO circuito de F1/F2, cero código nuevo de verificación.
 */
export function derivarAlertasRecordatorios(
  recordatorios: readonly RecordatorioCampana[],
  ahora: number,
): AlertaCRM[] {
  return recordatorios
    .filter((r) => {
      const vence = Date.parse(r.recordar_en)
      return Number.isFinite(vence) && vence <= ahora
    })
    .map((r) => ({
      id: `revisar-contacto-${r.id}`,
      tipo: 'revisar_contacto' as const,
      severidad: 'atencion' as const,
      alcance: 'personal' as const,
      titulo: 'Revisar contacto',
      detalle: `Programaste verificar si ${telefonoLegible(r.telefono)} ya está libre${
        fechaCortaLima(r.recordar_en) ? ` (recordatorio del ${fechaCortaLima(r.recordar_en)})` : ''
      }.`,
      responsableId: r.perfil_id,
      responsable: null,
      valor: null,
      destino: {
        vista: 'alertas' as const,
        etiqueta: 'Verificar disponibilidad',
      },
      contacto: {
        telefono: r.telefono,
        recordatorioId: r.id,
      },
    }))
}

/**
 * Fecha sugerida para el recordatorio según el veredicto (§5.3 «fecha
 * sugerida de revisión» + la regla de F1: fecha SOLO donde hay regla real).
 *  · enfriamiento → el día en que se libera (disponible_desde);
 *  · tomado → NO hay motor de fecha hasta F4: default +7 días, editable —
 *    es la nota personal del analista, no una promesa del sistema.
 * Devuelve YYYY-MM-DD (input date). Nunca en el pasado: si la regla real
 * quedó atrás (borde), cae a mañana.
 */
export function sugerirFechaRevision(
  resultado: DisponibilidadLead,
  ahora: number,
): string {
  const unDia = 24 * 3600 * 1000
  const manana = ahora + unDia
  let objetivo = ahora + 7 * unDia
  if (resultado.estado === 'enfriamiento') {
    const libre = Date.parse(resultado.disponible_desde)
    objetivo = Number.isFinite(libre) ? Math.max(libre, manana) : manana
  }
  // El día se expresa en Lima (la zona del negocio), no en la del equipo.
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
  const sugerida = fmt.format(objetivo)
  // F3.1: nunca sugerir lo que el formulario y el servidor van a rechazar —
  // un enfriamiento más largo que el tope se acota al último día válido (el
  // analista puede reprogramar cuando llegue). YYYY-MM-DD compara lexicográfico.
  const maxima = fechaMaximaRevision(ahora)
  return sugerida > maxima ? maxima : sugerida
}

/** ¿El veredicto admite «Recordarme revisar»? Solo los ocupados SIN puerta
 *  de toma: tomado y enfriamiento. Los tomables tienen su botón (F2); libre
 *  se crea; cliente/no_contactar jamás se liberan por tiempo. */
export function contactoRecordable(resultado: DisponibilidadLead): boolean {
  return resultado.estado === 'tomado' || resultado.estado === 'enfriamiento'
}

/** El `min` del input date: mañana en Lima — el servidor exige futuro (22023)
 *  y una fecha de hoy ya vencida solo produciría un rechazo evitable. */
export function fechaMinimaRevision(ahora: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(ahora + 24 * 3600 * 1000)
}

/** El `max` del input date: hoy+364 en Lima. El servidor rechaza todo lo que
 *  pase de 365 días desde el INSTANTE de guardar (22023), y el instante viaja
 *  a las 09:00 de Lima: hoy+365 elegido antes de las 09:00 ya rebasaría el
 *  tope — 364 es el último día válido a CUALQUIER hora. */
export function fechaMaximaRevision(ahora: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(ahora + 364 * 24 * 3600 * 1000)
}

/** YYYY-MM-DD del input → instante ISO a las 09:00 de Lima (inicio de la
 *  jornada comercial): la campana suena esa mañana, no a medianoche. */
export function aInstanteRevision(fecha: string): string {
  return `${fecha}T09:00:00-05:00`
}
