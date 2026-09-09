import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Corrige el CORREO DE ACCESO de un cliente del portal. Solo superadmin.
//
// POR QUÉ ES UNA EDGE Y NO UNA RPC. El correo del cliente vive en TRES sitios:
// `auth.users.email`, `auth.identities` (donde GoTrue busca de verdad al
// usuario al iniciar sesión) y `public.perfiles.correo`. Los dos primeros solo
// se mueven JUNTOS desde la API de administración, que necesita la
// `service_role` y por tanto no puede vivir en una función de SQL llamada por
// el navegador. Mover uno solo deja al cliente sin acceso EN SILENCIO.
//
// EL ORDEN IMPORTA, y es este a propósito:
//   1º el ESPEJO (`perfiles.correo` + su rastro con motivo), por la RPC, con el
//      JWT del que llama — así `auth.uid()` manda y el gate de superadmin es el
//      del servidor, no el de esta edge.
//   2º `auth` (users + identities de una vez) con la service_role.
// Si el paso 2 falla, el paso 1 se REVIERTE por la misma puerta (queda su
// rastro, que es justo lo que se quiere ver después). Y si hasta la reversión
// fallara, el cliente NO se queda fuera: `auth` sigue con el correo viejo, que
// es el que abre la puerta; lo que queda desalineado es el espejo, y el rastro
// lo dice.
//
// Y hay un 3er paso que no es decorativo: el ACUSE. La fila del rastro nace con
// `auth_confirmado_en` en NULL y solo se cierra cuando `auth` respondió OK. Sin
// eso, una caída del isolate entre el paso 1 y el 2 dejaría una fila idéntica a
// la de un éxito y la desalineación sería invisible. Lo que quede sin cerrar lo
// encuentra `crm.desviaciones_correo_cliente_fn()`.
//
// Decisiones de Miguel (08/09/2026): la corrección es SILENCIOSA — no se envía
// ningún correo al cliente, ni a la dirección vieja ni a la nueva — y la puede
// hacer SOLO el superadmin (el `admin`, que sí corrige documentos, aquí no).

const ROLES_QUE_CORRIGEN_CORREO = new Set(["superadmin"]);

const ALLOWED_ORIGINS = new Set([
  "https://miavance.com",
  "https://www.miavance.com",
  // La corrección se opera desde el CRM (modal «Corregir cliente»). El CORS
  // solo decide desde qué páginas puede llamar un navegador; la autorización
  // real es el JWT + el gate de superadmin de la RPC.
  "https://crm.miavance.com",
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
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    });
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });

    // 1) Identidad del que invoca
    const { data: userRes, error: userErr } = await adminClient.auth.getUser(token);
    if (userErr || !userRes?.user) return json(cors, { error: "Sesión inválida" }, 401);
    const callerId = userRes.user.id;

    // 2) Puerta estrecha. La RPC la vuelve a comprobar contra `auth.uid()`;
    //    esto solo evita el viaje y devuelve un 403 legible.
    const { data: perfilCaller } = await adminClient
      .from("perfiles")
      .select("rol, activo")
      .eq("id", callerId)
      .single();

    if (!perfilCaller || !perfilCaller.activo || !ROLES_QUE_CORRIGEN_CORREO.has(perfilCaller.rol)) {
      return json(cors, {
        error: "Solo el superadmin del Portal puede corregir el correo de acceso de un cliente",
      }, 403);
    }

    // 3) Body
    const body = await req.json().catch(() => ({}));
    const clienteId = String(body?.cliente_id || "").trim();
    const correo = String(body?.correo || "").trim().toLowerCase();
    const motivo = String(body?.motivo || "").trim();
    if (!clienteId) return json(cors, { error: "Falta cliente_id" }, 400);
    if (!correo) return json(cors, { error: "Falta el correo nuevo" }, 400);
    if (motivo.length < 3 || motivo.length > 500) {
      return json(cors, { error: "El motivo debe tener entre 3 y 500 caracteres" }, 400);
    }
    if (clienteId === callerId) {
      // La cuenta propia se cambia por el flujo normal de la sesión, no por la
      // puerta administrativa: aquí nadie se corrige a sí mismo.
      return json(cors, { error: "No puedes corregir tu propio correo por esta vía" }, 400);
    }

    // 4) El espejo primero, con el JWT del llamante (gate del servidor + rastro).
    const { data: espejo, error: espejoErr } = await userClient
      .schema("crm")
      .rpc("corregir_correo_cliente_admin_fn", {
        p_cliente_id: clienteId,
        p_correo: correo,
        p_motivo: motivo,
      });

    if (espejoErr) {
      // Aquí NO se escribió nada: la RPC es una transacción y falló entera.
      return json(cors, { error: espejoErr.message }, statusDeErrorEspejo(espejoErr));
    }
    // (La RPC compara el correo pedido contra `auth`, no contra el espejo, así
    //  que un reintento tras una caída a medias NO se rechaza por «es el mismo»:
    //  vuelve a pasar por aquí y termina el trabajo. Es el camino de reparación.)

    // 🔑 A partir de esta línea el espejo YA ESTÁ COMMITEADO. La regla del
    //    proyecto («tras una escritura irreversible NO se falla cerrado», la
    //    que costó 33 altas duplicadas) obliga a distinguir «no se hizo» de
    //    «se hizo y no me gusta la respuesta». El testigo del éxito es `ok`,
    //    NO `correo_anterior`: un cliente legacy con el correo vacío devuelve
    //    `correo_anterior: ''` y eso es un caso válido, no un fallo.
    const recibo = (espejo && !Array.isArray(espejo) ? espejo : null) as
      { ok?: unknown; correo_anterior?: unknown; rastro_id?: unknown } | null;
    if (recibo?.ok !== true) {
      return json(cors, { error: "El servidor no confirmó la corrección del espejo" }, 500);
    }
    const correoAnterior = String(recibo.correo_anterior ?? "");
    const rastroId = String(recibo.rastro_id ?? "");

    // 5) Y ahora `auth`: users e identities de una vez. `email_confirm` evita
    //    mandarle al cliente un correo de verificación — la corrección es
    //    silenciosa por decisión de negocio.
    const { error: authErr } = await adminClient.auth.admin.updateUserById(clienteId, {
      email: correo,
      email_confirm: true,
    });

    if (authErr) {
      // 🔑 ANTES DE COMPENSAR, MIRAR. Un error de transporte no prueba que `auth`
      //    no se movió: la actualización puede haber COMMITEADO y haberse perdido
      //    la respuesta. Si en ese caso revirtiéramos el espejo a ciegas, el
      //    acceso quedaría en el correo NUEVO y la ficha en el VIEJO — y el
      //    cliente, que sigue usando el viejo, se quedaría FUERA. Es el único
      //    desenlace inaceptable de todo este diseño, y era alcanzable.
      //    (P1-D de Codex, 08/09.) Por eso se relee el estado real primero.
      const { data: real } = await adminClient.auth.admin.getUserById(clienteId);
      const authYaMovido =
        (real?.user?.email ?? "").trim().toLowerCase() === correo;

      if (authYaMovido) {
        // No hubo fallo: hubo una respuesta perdida. Se cierra como el éxito
        // que en realidad fue.
        let cerrado = false;
        if (rastroId) {
          const { error: acuseErr } = await userClient
            .schema("crm").rpc("confirmar_correccion_correo_fn", { p_rastro_id: rastroId });
          cerrado = !acuseErr;
        }
        return json(cors, {
          ok: true,
          cliente_id: clienteId,
          correo_anterior: correoAnterior,
          correo_nuevo: correo,
          rastro_cerrado: cerrado,
          nota: "La respuesta del cambio de acceso se perdió, pero el cambio sí se aplicó.",
        }, 200);
      }

      // Compensación: deshacer el espejo por la MISMA puerta, para que el
      // intento y su reversión queden los dos en el rastro.
      //
      // Un cliente legacy sin correo previo no se puede revertir por esta vía
      // (la RPC exige un correo con forma), y es correcto que así sea: se dice
      // en el mensaje en vez de fingir una reversión que no ocurrió.
      const reversible = correoAnterior !== "";
      const { error: revertErr } = reversible
        ? await userClient
          .schema("crm")
          .rpc("corregir_correo_cliente_admin_fn", {
            p_cliente_id: clienteId,
            p_correo: correoAnterior,
            p_motivo: `Reversión automática: el correo no pudo cambiarse en el acceso (${motivo})`.slice(0, 500),
          })
        : { error: null };

      const yaRegistrado = /already.+(registered|exists)|duplicate/i.test(authErr.message || "");
      const base = yaRegistrado
        ? "Ese correo ya está registrado en el portal con otra cuenta"
        : `No se pudo cambiar el correo de acceso: ${authErr.message}`;
      let cola: string;
      if (!reversible) {
        cola = `. El acceso del cliente NO cambió, pero su ficha ya muestra ${correo} y no había correo anterior al que volver. Avisar a soporte.`;
      } else if (revertErr) {
        cola = `. ADEMÁS la reversión falló: el cliente sigue entrando con ${correoAnterior}, pero su ficha muestra ${correo}. Avisar a soporte.`;
      } else {
        cola = ". No se cambió nada.";
      }
      return json(cors, {
        error: `${base}${cola}`,
        revertido: reversible && !revertErr,
      }, yaRegistrado ? 409 : 502);
    }

    // 6) El acuse. Sin esto el rastro guardaría la INTENCIÓN y no el RESULTADO:
    //    una caída entre el paso 4 y el 5 dejaría una fila idéntica a la de un
    //    éxito y nadie se enteraría de la desalineación. Que el acuse falle NO
    //    invalida la corrección —los tres sitios YA están movidos—, así que no
    //    se convierte en un error: se avisa y la fila queda marcada para el
    //    detector `crm.desviaciones_correo_cliente_fn`.
    let rastroCerrado = false;
    if (rastroId) {
      const { error: acuseErr } = await userClient
        .schema("crm").rpc("confirmar_correccion_correo_fn", { p_rastro_id: rastroId });
      rastroCerrado = !acuseErr;
      if (acuseErr) console.error("[corregir-correo-cliente] acuse fallido", rastroId, acuseErr.message);
    }

    return json(cors, {
      ok: true,
      cliente_id: clienteId,
      correo_anterior: correoAnterior,
      correo_nuevo: correo,
      rastro_cerrado: rastroCerrado,
    }, 200);
  } catch (e) {
    console.error("[corregir-correo-cliente]", e);
    return json(cors, { error: (e as Error)?.message || "Error inesperado" }, 500);
  }
});

/** Los códigos que la RPC levanta a propósito, traducidos a HTTP. */
function statusDeErrorEspejo(error: { code?: string }): number {
  switch (error?.code) {
    case "42501": return 403; // no es superadmin
    case "P0002": return 404; // el cliente no existe
    case "23505": return 409; // el correo ya es de otra cuenta
    case "22023": return 400; // correo o motivo inválidos
    default: return 500;
  }
}

function json(cors: Record<string, string>, payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
