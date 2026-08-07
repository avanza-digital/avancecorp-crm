export type RpcError = { code?: string; message?: string };
export type RpcResult = { data: unknown; error: RpcError | null };

export interface ActorBackend {
  verificarSesion(): Promise<boolean>;
  rpc(nombre: string, argumentos: Record<string, unknown>): Promise<RpcResult>;
}

export interface DependenciasUsuarios {
  crearActor(token: string): ActorBackend;
  crearUsuarioAuth(input: {
    correo: string;
    nombreCompleto: string;
    passwordAleatoria: string;
  }): Promise<{ id: string | null; error: string | null }>;
  buscarUsuarioAuthPorCorreo(correo: string): Promise<string | null>;
  eliminarUsuarioAuth(id: string): Promise<void>;
  enviarRecuperacion(correo: string): Promise<{ error: string | null }>;
  passwordAleatoria(): string;
  origenesAdicionales?: readonly string[];
}

const ORIGENES_PRODUCCION = new Set([
  "https://crm.miavance.com",
  "https://www.crm.miavance.com",
]);
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_BODY_BYTES = 16_384;

type CrearCandidato = {
  accion: "crear_candidato";
  request_id: string;
  correo: string;
  nombre_completo: string;
  tipo_documento: "DNI" | "CE" | "PASAPORTE";
  documento: string;
  telefono: string | null;
  whatsapp: string | null;
  cargo: string | null;
};

type Recuperar = {
  accion: "enviar_recuperacion";
  request_id: string;
  perfil_id: string;
};

type Solicitud = CrearCandidato | Recuperar;

function cabeceras(
  origin: string | null,
  origenes: ReadonlySet<string>,
): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin && origenes.has(origin)
      ? origin
      : "https://crm.miavance.com",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "600",
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
  };
}

function json(
  origin: string | null,
  origenes: ReadonlySet<string>,
  cuerpo: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: cabeceras(origin, origenes),
  });
}

function esObjeto(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function cadena(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const limpia = v.trim();
  return limpia.length > 0 && limpia.length <= max ? limpia : null;
}

function opcional(v: unknown, max: number): string | null | undefined {
  if (v === undefined || v === null || v === "") return null;
  return cadena(v, max) ?? undefined;
}

function soloClaves(
  body: Record<string, unknown>,
  permitidas: readonly string[],
): boolean {
  const set = new Set(permitidas);
  return Object.keys(body).every((k) => set.has(k));
}

function parseSolicitud(body: unknown): Solicitud | null {
  if (!esObjeto(body)) return null;
  const accion = body.accion;
  const requestId = cadena(body.request_id, 36);
  if (!requestId || !UUID_RE.test(requestId)) return null;

  if (accion === "enviar_recuperacion") {
    if (!soloClaves(body, ["accion", "request_id", "perfil_id"])) return null;
    const perfilId = cadena(body.perfil_id, 36);
    if (!perfilId || !UUID_RE.test(perfilId)) return null;
    return { accion, request_id: requestId, perfil_id: perfilId };
  }

  if (accion !== "crear_candidato") return null;
  if (
    !soloClaves(body, [
      "accion",
      "request_id",
      "correo",
      "nombre_completo",
      "tipo_documento",
      "documento",
      "telefono",
      "whatsapp",
      "cargo",
    ])
  ) return null;

  const correo = cadena(body.correo, 254)?.toLowerCase();
  const nombre = cadena(body.nombre_completo, 160);
  const tipo = cadena(body.tipo_documento, 10)?.toUpperCase();
  const documento = cadena(body.documento, 12)?.toUpperCase();
  const telefono = opcional(body.telefono, 30);
  const whatsapp = opcional(body.whatsapp, 30);
  const cargo = opcional(body.cargo, 120);

  if (!correo || !CORREO_RE.test(correo) || !nombre || !documento) return null;
  if (telefono === undefined || whatsapp === undefined || cargo === undefined) {
    return null;
  }
  if (tipo === "DNI" && !/^[0-9]{8}$/.test(documento)) return null;
  if (tipo === "CE" && !/^[0-9]{9,12}$/.test(documento)) return null;
  if (tipo === "PASAPORTE" && !/^[A-Z0-9]{6,12}$/.test(documento)) return null;
  if (tipo !== "DNI" && tipo !== "CE" && tipo !== "PASAPORTE") return null;

  return {
    accion,
    request_id: requestId,
    correo,
    nombre_completo: nombre,
    tipo_documento: tipo,
    documento,
    telefono,
    whatsapp,
    cargo,
  };
}

function statusRpc(error: RpcError): number {
  if (error.code === "42501") return 403;
  if (error.code === "40001" || error.code === "23505") return 409;
  if ((error.message ?? "").toLowerCase().includes("demasiadas solicitudes")) {
    return 429;
  }
  return 400;
}

function bearer(req: Request): string | null {
  const value = req.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+([^\s]+)$/i.exec(value);
  return match?.[1] ?? null;
}

export function crearHandlerUsuarios(deps: DependenciasUsuarios) {
  const origenes = new Set(ORIGENES_PRODUCCION);
  for (const origen of deps.origenesAdicionales ?? []) {
    origenes.add(origen);
  }

  return async (req: Request): Promise<Response> => {
    const origin = req.headers.get("Origin");
    if (origin && !origenes.has(origin)) {
      return json(null, origenes, { error: "Origen no permitido" }, 403);
    }

    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: cabeceras(origin, origenes),
      });
    }
    if (req.method !== "POST") {
      return json(origin, origenes, { error: "Metodo no permitido" }, 405);
    }

    const token = bearer(req);
    if (!token) {
      return json(origin, origenes, { error: "Sesion requerida" }, 401);
    }

    const contentLength = Number(req.headers.get("Content-Length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
      return json(
        origin,
        origenes,
        { error: "Solicitud demasiado grande" },
        413,
      );
    }

    const actor = deps.crearActor(token);
    if (!await actor.verificarSesion()) {
      return json(origin, origenes, { error: "Sesion invalida" }, 401);
    }

    let raw: string;
    try {
      raw = await req.text();
    } catch {
      return json(origin, origenes, { error: "Solicitud invalida" }, 400);
    }
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
      return json(
        origin,
        origenes,
        { error: "Solicitud demasiado grande" },
        413,
      );
    }

    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      return json(origin, origenes, { error: "JSON invalido" }, 400);
    }
    const solicitud = parseSolicitud(body);
    if (!solicitud) {
      return json(origin, origenes, {
        error: "Payload invalido o contiene campos no permitidos",
      }, 400);
    }

    if (solicitud.accion === "enviar_recuperacion") {
      const preparado = await actor.rpc("preparar_recuperacion_usuario_fn", {
        p_perfil_id: solicitud.perfil_id,
        p_idempotencia: solicitud.request_id,
      });
      if (preparado.error) {
        return json(
          origin,
          origenes,
          { error: "No se pudo preparar la recuperacion" },
          statusRpc(preparado.error),
        );
      }
      const correo =
        esObjeto(preparado.data) && typeof preparado.data.correo === "string"
          ? preparado.data.correo
          : null;
      if (!correo) {
        return json(
          origin,
          origenes,
          { error: "Respuesta de recuperacion invalida" },
          502,
        );
      }

      const envio = await deps.enviarRecuperacion(correo);
      if (envio.error) {
        return json(
          origin,
          origenes,
          { error: "No se pudo enviar la recuperacion" },
          502,
        );
      }
      return json(origin, origenes, {
        estado: "recuperacion_enviada",
        perfil_id: solicitud.perfil_id,
      });
    }

    // La autorizacion DB ocurre ANTES de tocar Auth Admin.
    const candidato = await actor.rpc("buscar_candidato_por_correo_fn", {
      p_correo: solicitud.correo,
    });
    if (candidato.error) {
      return json(
        origin,
        origenes,
        { error: "No autorizado para crear usuarios CRM" },
        statusRpc(candidato.error),
      );
    }
    if (typeof candidato.data === "string" && UUID_RE.test(candidato.data)) {
      return json(origin, origenes, {
        estado: "candidato_existente",
        perfil_id: candidato.data,
        recuperacion_enviada: false,
      });
    }

    let creadoAhora = false;
    let authId: string | null = null;
    const altaAuth = await deps.crearUsuarioAuth({
      correo: solicitud.correo,
      nombreCompleto: solicitud.nombre_completo,
      passwordAleatoria: deps.passwordAleatoria(),
    });
    if (altaAuth.id) {
      authId = altaAuth.id;
      creadoAhora = true;
    } else {
      // Retry seguro: si Auth ya existe, se recupera el id y DB decide si es
      // candidato CRM valido. Nunca se borra una identidad preexistente.
      authId = await deps.buscarUsuarioAuthPorCorreo(solicitud.correo);
    }
    if (!authId) {
      return json(
        origin,
        origenes,
        { error: "No se pudo crear la identidad" },
        409,
      );
    }

    const registro = await actor.rpc("registrar_candidato_usuario_fn", {
      p_perfil_id: authId,
      p_correo: solicitud.correo,
      p_nombre_completo: solicitud.nombre_completo,
      p_tipo_documento: solicitud.tipo_documento,
      p_documento: solicitud.documento,
      p_telefono: solicitud.telefono,
      p_whatsapp: solicitud.whatsapp,
      p_cargo: solicitud.cargo,
      p_idempotencia: solicitud.request_id,
    });
    if (registro.error) {
      if (creadoAhora) await deps.eliminarUsuarioAuth(authId);
      return json(
        origin,
        origenes,
        { error: "No se pudo registrar el candidato CRM" },
        statusRpc(registro.error),
      );
    }

    const preparado = await actor.rpc("preparar_recuperacion_usuario_fn", {
      p_perfil_id: authId,
      p_idempotencia: solicitud.request_id,
    });
    let recuperacionEnviada = false;
    if (
      !preparado.error && esObjeto(preparado.data) &&
      typeof preparado.data.correo === "string"
    ) {
      const envio = await deps.enviarRecuperacion(preparado.data.correo);
      recuperacionEnviada = envio.error === null;
    }

    return json(origin, origenes, {
      estado: "pendiente_rol",
      perfil_id: authId,
      recuperacion_enviada: recuperacionEnviada,
    }, 201);
  };
}
