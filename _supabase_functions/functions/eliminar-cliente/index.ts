import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Elimina PERMANENTEMENTE a un cliente: borra su perfil y su usuario de auth.
// Solo personal administrativo ACTIVO (rol 'admin' o 'superadmin') puede
// invocarla (verificación server-side, no se confía en el frontend). Bloquea el
// borrado si el cliente tiene contratos — los registros financieros/legales no
// se destruyen desde un botón.

// Quién puede eliminar. El objetivo SIEMPRE debe ser rol 'cliente' (paso 4),
// así que un admin nunca puede borrar a otro admin ni al superadmin.
const ROLES_QUE_ELIMINAN = new Set(["admin", "superadmin"]);

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

    // 2) Solo personal administrativo activo (admin o superadmin).
    //    El rol 'admin' solo lo otorga un superadmin desde el panel de equipo
    //    (`crear-admin` lo revalida server-side), así que este permiso no se
    //    auto-propaga: un admin no puede fabricarse otro admin.
    const { data: perfilCaller } = await adminClient
      .from("perfiles")
      .select("rol, activo")
      .eq("id", callerId)
      .single();

    if (!perfilCaller || !perfilCaller.activo || !ROLES_QUE_ELIMINAN.has(perfilCaller.rol)) {
      return json(cors, { error: "Solo un administrador puede eliminar clientes" }, 403);
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

    // F2.b: bandera de identidad (fail-closed). Con OFF, el flujo de siempre; con ON, la RPC
    // transaccional crm.eliminar_cliente_fn (contratos, identidad, altas en curso, comunicados y
    // perfil en UNA transacción: antes un rechazo tardío dejaba los comunicados ya borrados).
    const { data: banderaIdentidad, error: errBandera } = await adminClient
      .schema("crm").rpc("bandera_activa", { p_nombre: "resolver_en_puertas" });
    if (errBandera) {
      return json(cors, { error: `No se pudo leer la bandera de identidad: ${errBandera.message}` }, 500);
    }
    if (banderaIdentidad !== true) {
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
    } else {
      const { data: borrado, error: borradoErr } = await adminClient
        .schema("crm").rpc("eliminar_cliente_fn", { p_perfil_id: userId });
      if (borradoErr) {
        let detalle: Record<string, unknown> = {};
        try { detalle = JSON.parse(String((borradoErr as { details?: string }).details ?? "{}")); } catch { detalle = {}; }
        const motivo = String(detalle?.motivo ?? "");
        if (borradoErr.code === "P0409") {
          return json(cors, {
            error: borradoErr.message,
            code: motivo === "contratos" ? "HAS_CONTRACTS" : motivo === "identidad" ? "HAS_IDENTITY" : "NOT_DELETABLE",
          }, 409);
        }
        if (borradoErr.code === "P0002") {
          return json(cors, { error: "El cliente no existe o ya fue eliminado" }, 404);
        }
        return json(cors, {
          error: `No se pudo eliminar el perfil: ${borradoErr.message}. Si el cliente tiene registros asociados, desactívalo en su lugar.`,
        }, 409);
      }
      void borrado;
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
