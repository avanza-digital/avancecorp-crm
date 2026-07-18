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
// el control de acceso es el token secreto de crm.agenda_ics — cada token abre
// SOLO el feed de su dueño (tareas donde él es el vendedor), nada más. Rotar
// el token en el CRM invalida el enlace anterior de inmediato. La consulta va
// con service_role pero SIEMPRE filtrada por el perfil dueño del token.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DURACION_DEFECTO_MIN = 30;
const VENTANA_PASADO_DIAS = 30; // vencidas recientes sí; arqueología no

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

interface FilaTarea {
  id: string;
  tipo: string;
  titulo: string;
  nota: string | null;
  vence_en: string;
  duracion_min: number | null;
}

function calendarioIcs(tareas: FilaTarea[], ahora: number): string {
  const lineas = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Avance Corp//CRM Agenda//ES",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:CRM Avance Corp",
    "X-WR-TIMEZONE:America/Lima",
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
  ];
  for (const t of tareas) {
    const inicio = Date.parse(t.vence_en);
    if (!Number.isFinite(inicio)) continue;
    const fin = inicio + (t.duracion_min ?? DURACION_DEFECTO_MIN) * 60_000;
    const resumen = `${TIPO_LABEL[t.tipo] ?? "Tarea"} — ${t.titulo}`;
    lineas.push(
      "BEGIN:VEVENT",
      `UID:${t.id}@crm.miavance.com`,
      `DTSTAMP:${fechaIcs(ahora)}`,
      `DTSTART:${fechaIcs(inicio)}`,
      `DTEND:${fechaIcs(fin)}`,
      `SUMMARY:${escapaIcs(resumen)}`,
      ...(t.nota ? [`DESCRIPTION:${escapaIcs(t.nota)}`] : []),
      "STATUS:CONFIRMED",
      "END:VEVENT",
    );
  }
  lineas.push("END:VCALENDAR");
  return lineas.join("\r\n") + "\r\n";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") return new Response("Método no permitido", { status: 405 });

  const token = new URL(req.url).searchParams.get("t") ?? "";
  if (!UUID_RE.test(token)) return new Response("No encontrado", { status: 404 });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { db: { schema: "crm" } },
  );

  // Token → dueño. Un token desconocido responde igual que uno mal formado.
  const { data: fila, error: errToken } = await supabase
    .from("agenda_ics")
    .select("perfil_id")
    .eq("token", token)
    .maybeSingle();
  if (errToken) return new Response("Error interno", { status: 500 });
  if (!fila) return new Response("No encontrado", { status: 404 });

  const desde = new Date(Date.now() - VENTANA_PASADO_DIAS * 86_400_000).toISOString();
  const { data: tareas, error: errTareas } = await supabase
    .from("tareas")
    .select("id, tipo, titulo, nota, vence_en, duracion_min")
    .eq("vendedor_id", fila.perfil_id)
    .eq("estado", "pendiente")
    .eq("activo", true)
    .gte("vence_en", desde)
    .order("vence_en", { ascending: true })
    .limit(500);
  if (errTareas) return new Response("Error interno", { status: 500 });

  return new Response(calendarioIcs((tareas ?? []) as FilaTarea[], Date.now()), {
    status: 200,
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="agenda-crm.ics"',
      // Google decide su propio ritmo de refresco; este cache solo amortigua ráfagas.
      "Cache-Control": "private, max-age=300",
    },
  });
});
