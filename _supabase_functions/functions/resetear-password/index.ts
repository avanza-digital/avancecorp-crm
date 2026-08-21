import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

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

    const { data: userRes, error: userErr } = await adminClient.auth.getUser(token);
    if (userErr || !userRes?.user) return json(cors, { error: "Sesión inválida" }, 401);

    const { data: perfilCaller } = await adminClient
      .from("perfiles")
      .select("rol, activo")
      .eq("id", userRes.user.id)
      .single();

    if (!perfilCaller || !perfilCaller.activo || !["admin", "superadmin"].includes(perfilCaller.rol)) {
      return json(cors, { error: "No autorizado" }, 403);
    }

    const body = await req.json();
    const { user_id, new_password } = body || {};

    if (!user_id || !new_password) {
      return json(cors, { error: "user_id y new_password son obligatorios" }, 400);
    }
    if (String(new_password).length < 8) {
      return json(cors, { error: "La contraseña debe tener al menos 8 caracteres" }, 400);
    }

    const { data: perfilTarget } = await adminClient
      .from("perfiles")
      .select("id, rol")
      .eq("id", user_id)
      .single();

    if (!perfilTarget) return json(cors, { error: "Usuario no encontrado" }, 404);
    if (perfilTarget.id === userRes.user.id) {
      return json(cors, { error: "Para cambiar tu propia contraseña usa tu perfil" }, 400);
    }
    if (perfilTarget.rol !== "cliente" && perfilCaller.rol !== "superadmin") {
      return json(cors, { error: "Solo un superadmin puede resetear contraseñas de administradores" }, 403);
    }

    const { error: updErr } = await adminClient.auth.admin.updateUserById(user_id, {
      password: new_password,
    });

    if (updErr) {
      const raw = updErr.message || "No se pudo actualizar la contraseña";
      // Supabase rechaza contraseñas débiles/filtradas (HaveIBeenPwned) con un
      // mensaje en inglés. Lo traducimos para que el admin entienda qué hacer.
      const esDebil = /weak|pwned|leaked|breach|easy to guess|known to be|compromis/i.test(raw);
      if (esDebil) {
        return json(cors, {
          error: "Supabase rechazó esta contraseña por ser muy común o aparecer en filtraciones conocidas. Usa una con mayúsculas, minúsculas, números y un símbolo (ej: NuevaClave2026!).",
        }, 422);
      }
      return json(cors, { error: raw }, 400);
    }

    return json(cors, { ok: true }, 200);

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
