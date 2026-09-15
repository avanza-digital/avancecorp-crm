import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.110.2";

const ORIGENES = new Set([
  "https://miavance.com",
  "https://www.miavance.com",
  "https://crm.miavance.com",
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Auth, identidad email, perfil y auditoría se confirman en una transacción. */
export async function corregirCorreoCliente(
  req: Request,
  admin: SupabaseClient,
): Promise<Response> {
  const origin = req.headers.get("Origin") ?? "";
  const headers = {
    "Access-Control-Allow-Origin": ORIGENES.has(origin)
      ? origin
      : "https://miavance.com",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
    "Content-Type": "application/json",
  };
  const responder = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers });
  if (req.method === "OPTIONS") return responder(200, { ok: true });
  if (req.method !== "POST") {
    return responder(405, { error: "Método no permitido" });
  }
  const token = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i)
    ?.[1];
  if (!token) {
    return responder(401, {
      error: "Sesión inválida. Vuelve a iniciar sesión.",
    });
  }

  try {
    const { data: sesion, error: errorSesion } = await admin.auth.getUser(
      token,
    );
    if (errorSesion || !sesion.user) {
      return responder(401, {
        error: "Sesión inválida. Vuelve a iniciar sesión.",
      });
    }
    const actorId = sesion.user.id;
    const { data: actor, error: errorActor } = await admin.from("perfiles")
      .select("rol,activo").eq("id", actorId).single();
    if (
      errorActor || !actor?.activo ||
      !["admin", "superadmin"].includes(actor.rol)
    ) {
      return responder(403, {
        error:
          "Solo un administrador activo puede corregir el correo de un cliente.",
      });
    }
    const body = await req.json().catch(() => null);
    const clienteId = typeof body?.cliente_id === "string"
      ? body.cliente_id.trim()
      : "";
    const correo = typeof body?.correo === "string"
      ? body.correo.trim().toLowerCase()
      : "";
    const motivo = typeof body?.motivo === "string" ? body.motivo.trim() : "";
    if (!UUID.test(clienteId) || actorId === clienteId) {
      return responder(400, {
        error: "Selecciona una cuenta de cliente válida.",
      });
    }
    if (correo.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo)) {
      return responder(400, { error: "El correo electrónico no es válido." });
    }
    if (motivo.length < 3 || motivo.length > 500) {
      return responder(400, {
        error: "El motivo debe tener entre 3 y 500 caracteres.",
      });
    }

    // El actor proviene del JWT verificado, nunca del cuerpo de la petición.
    const { data: operacionId, error: errorPreparar } = await admin.schema(
      "crm",
    ).rpc("preparar_correccion_correo_acceso_fn", {
      p_cliente_id: clienteId,
      p_actor_id: actorId,
      p_correo: correo,
      p_motivo: motivo,
    });
    if (errorPreparar) {
      const status =
        ({ "42501": 403, "23505": 409, "22023": 400, "P0002": 404 } as Record<
          string,
          number
        >)[errorPreparar.code] ?? 503;
      return responder(status, {
        error: status === 503
          ? "La corrección de correo todavía no está disponible. Intenta nuevamente más tarde."
          : errorPreparar.message,
      });
    }
    if (typeof operacionId !== "string" || !UUID.test(operacionId)) {
      return responder(503, {
        error: "No se pudo preparar la corrección. No se cambió el acceso.",
      });
    }

    // app_metadata solo admite escrituras administrativas. La marca no expone
    // correos, motivos ni actores en el JWT del cliente. El trigger revalida
    // operación, objetivo y permiso vigente antes de mover el perfil.
    let errorCambio: { message?: string } | null = null;
    try {
      const { error } = await admin.auth.admin.updateUserById(clienteId, {
        email: correo,
        email_confirm: true,
        app_metadata: { correccion_correo_acceso_id: operacionId },
      });
      errorCambio = error;
    } catch {
      errorCambio = { message: "Respuesta de acceso no recibida" };
    }
    // Un timeout puede ocurrir después del commit. Se relee; nunca se revierte
    // a ciegas. Reintentar es seguro incluso si ya se confirmó el correo.
    const { data: real, error: errorLectura } = await admin.auth.admin
      .getUserById(clienteId);
    const { data: perfil, error: errorPerfil } = await admin.from("perfiles")
      .select("correo").eq("id", clienteId).single();
    const identidad = real?.user?.identities?.find((item) =>
      item.provider === "email"
    );
    const normalizar = (valor: unknown) =>
      typeof valor === "string" ? valor.trim().toLowerCase() : "";
    if (
      !errorLectura && !errorPerfil && real.user?.email_confirmed_at &&
      normalizar(real.user.email) === correo &&
      normalizar(identidad?.identity_data?.email) === correo &&
      normalizar(perfil?.correo) === correo &&
      real.user.app_metadata?.correccion_correo_acceso_id === operacionId
    ) {
      return responder(200, {
        ok: true,
        cliente_id: clienteId,
        correo_nuevo: correo,
        rastro_cerrado: true,
      });
    }
    if (/already|duplicate|registered/i.test(errorCambio?.message ?? "")) {
      return responder(409, {
        error: "Ese correo ya pertenece a otra cuenta. Usa uno diferente.",
      });
    }
    return responder(503, {
      error:
        "No se pudo confirmar la corrección del correo. Reintenta con el mismo correo y motivo para verificar el resultado.",
    });
  } catch {
    return responder(503, {
      error:
        "No se pudo completar la corrección. Reintenta con el mismo correo y motivo.",
    });
  }
}
