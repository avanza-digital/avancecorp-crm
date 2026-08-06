import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// crm-agenda-ics — la agenda del miembro como calendario ICS por suscripción.
//
// Google Calendar (y Apple/Outlook) consumen esta URL con "agregar calendario
// por URL": el vendedor la pega UNA vez y sus tareas pendientes aparecen solas
// en su celular. Google refresca cada varias horas — es un espejo de lectura,
// no sincronización (la bidireccional quedó en Fase H del plan v2).
//
// Seguridad: se despliega con verify_jwt=false (Google no puede mandar JWT);
// el control de acceso es el token secreto de crm.agenda_ics. La RPC de feed
// resuelve en una sola sentencia token + perfil activo + membresía CRM activa
// + tareas del dueño. El offboarding CRM (equipo=false) rota el token; una
// suspensión del perfil corta el feed mientras dure. El gate comprueba ambos
// flags en cada petición. La Edge nunca consulta tablas sueltas.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MILISEGUNDOS_POR_MINUTO = 60_000;
const MILISEGUNDOS_POR_DIA = 86_400_000;
const DURACION_DEFECTO_MIN = 30;
const VENTANA_PASADO_DIAS = 30; // vencidas recientes sí; arqueología no
const PARAMETRO_TOKEN = "t";
const RPC_FEED_AGENDA = "agenda_ics_feed_fn";

const LINEAS_CABECERA_CALENDARIO = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "PRODID:-//Avance Corp//CRM Agenda//ES",
  "CALSCALE:GREGORIAN",
  "METHOD:PUBLISH",
  "X-WR-CALNAME:CRM Avance Corp",
  "X-WR-TIMEZONE:America/Lima",
  "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
] as const;

const CABECERAS_RESPUESTA_ICS: Record<string, string> = {
  "Content-Type": "text/calendar; charset=utf-8",
  "Content-Disposition": 'inline; filename="agenda-crm.ics"',
  // Google decide su propio ritmo de refresco; este cache solo amortigua ráfagas.
  "Cache-Control": "private, max-age=300",
};

const TIPO_LABEL: Record<string, string> = {
  llamada: "Llamada",
  whatsapp: "WhatsApp",
  reunion: "Reunión",
  tarea: "Tarea",
};

/** Texto ICS: escapa \ ; , y saltos de línea (RFC 5545 §3.3.11). */
function escapaIcs(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
}

/** Instante ISO → forma básica UTC de ICS (20260718T150000Z). */
function fechaIcs(ms: number): string {
  return `${new Date(ms).toISOString().slice(0, 19).replace(/[-:]/g, "")}Z`;
}

type ModalidadReunion = "presencial" | "virtual" | "sin_clasificar" | null;

interface FilaTarea {
  id: string;
  tipo: string;
  titulo: string;
  nota: string | null;
  vence_en: string;
  duracion_min: number | null;
  modalidad_reunion: ModalidadReunion;
  ubicacion_reunion: string | null;
  enlace_reunion: string | null;
}

interface RespuestaFeed {
  autorizado: boolean;
  tareas: FilaTarea[];
}

function esObjeto(valor: unknown): valor is Record<string, unknown> {
  return valor !== null && typeof valor === "object";
}

function esCadenaONull(valor: unknown): valor is string | null {
  return valor === null || typeof valor === "string";
}

function esNumeroFinitoONull(valor: unknown): valor is number | null {
  return valor === null || (typeof valor === "number" && Number.isFinite(valor));
}

function esModalidadReunion(valor: unknown): valor is ModalidadReunion {
  return valor === null
    || valor === "presencial"
    || valor === "virtual"
    || valor === "sin_clasificar";
}

function esFilaTarea(valor: unknown): valor is FilaTarea {
  if (!esObjeto(valor)) return false;
  const tarea = valor;
  return typeof tarea.id === "string"
    && typeof tarea.tipo === "string"
    && typeof tarea.titulo === "string"
    && esCadenaONull(tarea.nota)
    && typeof tarea.vence_en === "string"
    && esNumeroFinitoONull(tarea.duracion_min)
    && esModalidadReunion(tarea.modalidad_reunion)
    && esCadenaONull(tarea.ubicacion_reunion)
    && esCadenaONull(tarea.enlace_reunion);
}

function esRespuestaFeed(valor: unknown): valor is RespuestaFeed {
  if (!esObjeto(valor)) return false;
  const feed = valor;
  return typeof feed.autorizado === "boolean"
    && Array.isArray(feed.tareas)
    && feed.tareas.every(esFilaTarea);
}

type PropiedadTextoIcs = "SUMMARY" | "DESCRIPTION" | "LOCATION" | "URL";

function serializaTextoIcs(propiedad: PropiedadTextoIcs, valor: string): string {
  return `${propiedad}:${escapaIcs(valor)}`;
}

function serializaTextoIcsOpcional(
  propiedad: Exclude<PropiedadTextoIcs, "SUMMARY">,
  valor: string | null,
): string[] {
  return valor ? [serializaTextoIcs(propiedad, valor)] : [];
}

function etiquetaModalidad(tarea: FilaTarea): string | null {
  if (!tarea.modalidad_reunion || tarea.modalidad_reunion === "sin_clasificar") return null;
  return `Modalidad: ${tarea.modalidad_reunion === "presencial" ? "Presencial" : "Virtual"}`;
}

function descripcionEvento(tarea: FilaTarea): string {
  return [
    etiquetaModalidad(tarea),
    tarea.enlace_reunion ? `Enlace: ${tarea.enlace_reunion}` : null,
    tarea.nota,
  ]
      .filter((linea): linea is string => Boolean(linea))
      .join("\n\n");
}

function ubicacionEvento(tarea: FilaTarea): string | null {
  return tarea.modalidad_reunion === "presencial"
    ? tarea.ubicacion_reunion
    : (tarea.enlace_reunion ?? tarea.ubicacion_reunion);
}

function serializaEventoIcs(tarea: FilaTarea, ahora: number): string[] | null {
  const inicio = Date.parse(tarea.vence_en);
  if (!Number.isFinite(inicio)) return null;

  const fin = inicio
    + (tarea.duracion_min ?? DURACION_DEFECTO_MIN) * MILISEGUNDOS_POR_MINUTO;
  const resumen = `${TIPO_LABEL[tarea.tipo] ?? "Tarea"} — ${tarea.titulo}`;

  return [
    "BEGIN:VEVENT",
    `UID:${tarea.id}@crm.miavance.com`,
    `DTSTAMP:${fechaIcs(ahora)}`,
    `DTSTART:${fechaIcs(inicio)}`,
    `DTEND:${fechaIcs(fin)}`,
    serializaTextoIcs("SUMMARY", resumen),
    ...serializaTextoIcsOpcional("DESCRIPTION", descripcionEvento(tarea)),
    ...serializaTextoIcsOpcional("LOCATION", ubicacionEvento(tarea)),
    ...serializaTextoIcsOpcional("URL", tarea.enlace_reunion),
    "STATUS:CONFIRMED",
    "END:VEVENT",
  ];
}

function calendarioIcs(tareas: FilaTarea[], ahora: number): string {
  const lineas: string[] = [...LINEAS_CABECERA_CALENDARIO];
  for (const tarea of tareas) {
    const evento = serializaEventoIcs(tarea, ahora);
    if (evento) lineas.push(...evento);
  }
  lineas.push("END:VCALENDAR");
  return lineas.join("\r\n") + "\r\n";
}

function respuestaTexto(cuerpo: string, status: number): Response {
  return new Response(cuerpo, { status });
}

function tokenDeSolicitud(req: Request): string {
  return new URL(req.url).searchParams.get(PARAMETRO_TOKEN) ?? "";
}

function clienteCrmConServiceRole() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { db: { schema: "crm" } },
  );
}

function inicioVentanaIcs(ahora: number): string {
  return new Date(ahora - VENTANA_PASADO_DIAS * MILISEGUNDOS_POR_DIA).toISOString();
}

async function manejarSolicitud(req: Request): Promise<Response> {
  if (req.method !== "GET") return respuestaTexto("Método no permitido", 405);

  const token = tokenDeSolicitud(req);
  if (!UUID_RE.test(token)) return respuestaTexto("No encontrado", 404);

  // El service_role permanece confinado a la Edge; la RPC valida el token y el gate CRM.
  const supabase = clienteCrmConServiceRole();

  const desde = inicioVentanaIcs(Date.now());
  const { data, error } = await supabase.rpc(RPC_FEED_AGENDA, {
    p_token: token,
    p_desde: desde,
  });
  if (error || !esRespuestaFeed(data)) {
    return respuestaTexto("Error interno", 500);
  }
  if (!data.autorizado) return respuestaTexto("No encontrado", 404);

  return new Response(calendarioIcs(data.tareas, Date.now()), {
    status: 200,
    headers: CABECERAS_RESPUESTA_ICS,
  });
}

Deno.serve(manejarSolicitud);
