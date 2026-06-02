import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Elimina PERMANENTEMENTE a un cliente: borra su perfil y su usuario de auth.
// Solo un superadmin activo puede invocarla (verificación server-side, no se
// confía en el frontend). Bloquea el borrado si el cliente tiene contratos —
// los registros financieros/legales no se destruyen desde un botón.

const ALLOWED_ORIGINS = new Set([
  "https://miavance.com",
  "https://www.miavance.com",
]);

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "https://miavance.com",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json(cors, { error: "Falta header Authorization" }, 401);
    const token = authHeader.replace("Bearer ", "");

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    });

    // 1) Identidad del que invoca
    const { data: userRes, error: userErr } = await adminClient.auth.getUser(token);
    if (userErr || !userRes?.user) return json(cors, { error: "Sesión inválida" }, 401);
    const callerId = userRes.user.id;

    // 2) Solo superadmin activo
    const { data: perfilCaller } = await adminClient
      .from("perfiles")
      .select("rol, activo")
      .eq("id", callerId)
      .single();

    if (!perfilCaller || !perfilCaller.activo || perfilCaller.rol !== "superadmin") {
      return json(cors, { error: "Solo un superadmin puede eliminar clientes" }, 403);
    }

    // 3) Body
    const body = await req.json().catch(() => ({}));
    const userId = String(body?.user_id || "").trim();
    if (!userId) return json(cors, { error: "Falta user_id" }, 400);
    if (userId === callerId) {
      return json(cors, { error: "No puedes eliminar tu propia cuenta" }, 400);
    }

    // 4) El objetivo debe existir y ser rol 'cliente' (nunca admin/superadmin)
    const { data: target, error: targetErr } = await adminClient
      .from("perfiles")
      .select("id, rol, nombre_completo")
      .eq("id", userId)
      .single();

    if (targetErr || !target) {
      return json(cors, { error: "El cliente no existe o ya fue eliminado" }, 404);
    }
    if (target.rol !== "cliente") {
      return json(cors, { error: "Esta función solo elimina clientes, no administradores" }, 403);
    }

    // 5) Bloquear si tiene contratos (protege historial financiero/legal)
    const { count: nContratos, error: contErr } = await adminClient
      .from("contratos")
      .select("id", { count: "exact", head: true })
      .eq("cliente_id", userId);

    if (contErr) {
      return json(cors, { error: `No se pudo verificar contratos: ${contErr.message}` }, 500);
    }
    if ((nContratos ?? 0) > 0) {
      return json(cors, {
        error: `Este cliente tiene ${nContratos} contrato(s) asociado(s). Desactívalo en vez de eliminarlo para conservar el historial.`,
        code: "HAS_CONTRACTS",
      }, 409);
    }

    // 6) Limpiar comunicados dirigidos a este cliente (FK NO ACTION en novedades.destinatario_id)
    const { error: novErr } = await adminClient
      .from("novedades")
      .delete()
      .eq("destinatario_id", userId);
    if (novErr) {
      return json(cors, { error: `No se pudieron limpiar los comunicados del cliente: ${novErr.message}` }, 500);
    }

    // 7) Borrar el perfil (cascada: novedades_leidas, suscripciones_push; audit_log → SET NULL)
    const { error: perfilErr } = await adminClient
      .from("perfiles")
      .delete()
      .eq("id", userId);
    if (perfilErr) {
      return json(cors, {
        error: `No se pudo eliminar el perfil: ${perfilErr.message}. Si el cliente tiene registros asociados, desactívalo en su lugar.`,
      }, 409);
    }

    // 8) Borrar el usuario de auth (no hay FK que lo cascade; debe ser explícito)
    const { error: authErr } = await adminClient.auth.admin.deleteUser(userId);
    if (authErr) {
      // El perfil ya se borró; avisamos para limpieza manual del usuario de auth.
      return json(cors, {
        ok: true,
        warning: `Perfil eliminado, pero no se pudo borrar el usuario de autenticación (${authErr.message}). Bórralo manualmente en Supabase → Authentication.`,
        nombre: target.nombre_completo,
      }, 200);
    }

    return json(cors, { ok: true, nombre: target.nombre_completo }, 200);

  } catch (e) {
    return json(corsHeaders(req), { error: (e as Error)?.message || "Error inesperado" }, 500);
  }
});

function json(cors: Record<string, string>, payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
