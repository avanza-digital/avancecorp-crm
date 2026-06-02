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

    if (!perfilCaller || !perfilCaller.activo || perfilCaller.rol !== "superadmin") {
      return json(cors, { error: "Solo un superadmin puede crear administradores" }, 403);
    }

    const body = await req.json();
    const { email, password, nombre_completo, dni, telefono } = body || {};

    if (!email || !password || !nombre_completo || !dni) {
      return json(cors, { error: "email, password, nombre_completo y dni son obligatorios" }, 400);
    }
    if (String(password).length < 8) {
      return json(cors, { error: "La contraseña debe tener al menos 8 caracteres" }, 400);
    }

    const emailNorm = String(email).trim().toLowerCase();

    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email: emailNorm,
      password,
      email_confirm: true,
      user_metadata: { nombre: nombre_completo },
    });

    if (createErr || !created?.user) {
      const msg = createErr?.message || "";
      if (/already\s+(registered|exists)/i.test(msg) || /User already registered/i.test(msg) || /duplicate/i.test(msg)) {
        return json(cors, { error: "Este correo ya está registrado" }, 409);
      }
      return json(cors, { error: msg || "No se pudo crear el usuario" }, 400);
    }

    const newUserId = created.user.id;

    const { error: perfilErr } = await adminClient
      .from("perfiles")
      .insert({
        id: newUserId,
        nombre_completo: String(nombre_completo).trim(),
        dni: dni ? String(dni).trim() : null,
        telefono: telefono ? String(telefono).trim() : null,
        correo: emailNorm,
        rol: "admin",
        activo: true,
        creado_por: userRes.user.id,
      });

    if (perfilErr) {
      await adminClient.auth.admin.deleteUser(newUserId);
      if (/duplicate key/i.test(perfilErr.message) && /dni/i.test(perfilErr.message)) {
        return json(cors, { error: "Este DNI ya está registrado" }, 409);
      }
      return json(cors, { error: `Error al crear perfil: ${perfilErr.message}` }, 400);
    }

    return json(cors, { ok: true, user_id: newUserId, email: created.user.email }, 200);

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
