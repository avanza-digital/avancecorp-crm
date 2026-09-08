import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  type ActorContratoPdfV2,
  type BackendResult,
  crearHandlerContratoPdfV2,
} from "./handler.ts";
import { renderizarContratoPdfV2 } from "./renderer.ts";
import { crearStorageContratoPdfV2, errorBackend } from "./storage.ts";

function env(nombre: string, alternativa?: string): string {
  const valor = Deno.env.get(nombre) ??
    (alternativa ? Deno.env.get(alternativa) : undefined);
  if (!valor) throw new Error(`Falta ${nombre}`);
  return valor;
}

const SUPABASE_URL = env("SUPABASE_URL");
const PUBLIC_KEY = env("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY");
const SECRET_KEY = env("SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY");

function origenLoopback(
  hostRaw: string | null,
  puertoRaw: string | null,
  protocoloRaw: string | null,
): string | null {
  const host = hostRaw?.split(",", 1)[0].trim();
  const puerto = puertoRaw?.split(",", 1)[0].trim();
  const protocolo = protocoloRaw?.split(",", 1)[0].trim().toLowerCase();
  if (!host || (protocolo && protocolo !== "http")) return null;
  try {
    const candidato = new URL(`http://${host}`);
    if (
      candidato.hostname !== "localhost" &&
      candidato.hostname !== "127.0.0.1" &&
      candidato.hostname !== "[::1]"
    ) return null;
    if (!candidato.port && puerto && /^\d{2,5}$/.test(puerto)) {
      candidato.port = puerto;
    }
    return candidato.origin;
  } catch {
    return null;
  }
}

function resolverBasePublica(req: Request): string {
  const configurada = Deno.env.get("CRM_PUBLIC_SUPABASE_URL")?.trim() ||
    Deno.env.get("SUPABASE_PUBLIC_URL")?.trim();
  if (configurada) return configurada;
  const supabase = new URL(SUPABASE_URL);
  if (supabase.protocol === "https:") return SUPABASE_URL;
  return origenLoopback(
    req.headers.get("x-forwarded-host") ?? req.headers.get("host"),
    req.headers.get("x-forwarded-port"),
    req.headers.get("x-forwarded-proto"),
  ) ?? origenLoopback(
    new URL(req.url).host,
    null,
    new URL(req.url).protocol.slice(0, -1),
  ) ?? SUPABASE_URL;
}

const admin = createClient(SUPABASE_URL, SECRET_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
    detectSessionInUrl: false,
  },
});

function resultado(data: unknown, error: unknown): BackendResult {
  return { data, error: errorBackend(error) };
}

function crearActor(token: string): ActorContratoPdfV2 {
  const cliente = createClient(SUPABASE_URL, PUBLIC_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
  return {
    async verificarSesion() {
      const { data, error } = await cliente.auth.getUser(token);
      return error || !data.user ? null : { id: data.user.id };
    },
    async rpc(nombre, argumentos) {
      const { data, error } = await cliente.schema("crm").rpc(
        nombre,
        argumentos,
      );
      return resultado(data, error);
    },
  };
}

const origenesAdicionales = [
  "http://localhost:5173",
  "http://127.0.0.1:5173",
  ...(Deno.env.get("CRM_ALLOWED_ORIGINS") ?? "").split(","),
].map((origen) => origen.trim()).filter((origen) => {
  if (!origen || origen.includes("*")) return false;
  try {
    const url = new URL(origen);
    return url.origin === origen && (url.protocol === "https:" ||
      ((url.hostname === "localhost" || url.hostname === "127.0.0.1") &&
        url.protocol === "http:"));
  } catch {
    return false;
  }
});

const handler = crearHandlerContratoPdfV2({
  crearActor,
  origenesAdicionales,
  renderizar: renderizarContratoPdfV2,
  async rpcAdmin(nombre, argumentos) {
    const { data, error } = await admin.schema("crm").rpc(nombre, argumentos);
    return resultado(data, error);
  },
  storage: crearStorageContratoPdfV2({
    supabaseUrl: SUPABASE_URL,
    secretKey: SECRET_KEY,
    basePublica: resolverBasePublica,
  }),
});

Deno.serve(handler);
