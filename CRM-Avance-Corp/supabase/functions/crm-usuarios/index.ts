import { createClient } from "jsr:@supabase/supabase-js@2.110.8";
import {
  type ActorBackend,
  crearHandlerUsuarios,
  type RpcResult,
} from "./handler.ts";

// Desplegar SIEMPRE con verify_jwt=true. Aun asi se valida getUser() dentro de
// la funcion: defensa en profundidad y contrato verificable en tests.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const PUBLIC_KEY = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ??
  "";
const SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";
const REDIRECT_RECUPERACION = Deno.env.get("CRM_PASSWORD_RESET_REDIRECT_URL") ??
  "https://miavance.com/reset-password.html";
const ORIGENES_ADICIONALES = (Deno.env.get("CRM_ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((origen) => origen.trim())
  .filter((origen) => {
    if (!origen || origen.includes("*")) return false;
    try {
      const url = new URL(origen);
      const local = url.hostname === "localhost" ||
        url.hostname === "127.0.0.1";
      return url.origin === origen && (url.protocol === "https:" ||
        (local && url.protocol === "http:"));
    } catch {
      return false;
    }
  });

if (!SUPABASE_URL || !PUBLIC_KEY || !SECRET_KEY) {
  throw new Error("Faltan variables Supabase requeridas por crm-usuarios");
}

const authAdmin = createClient(SUPABASE_URL, SECRET_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
    detectSessionInUrl: false,
  },
});

function crearActor(token: string): ActorBackend {
  const cliente = createClient(SUPABASE_URL, PUBLIC_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  return {
    async verificarSesion(): Promise<boolean> {
      const { data, error } = await cliente.auth.getUser(token);
      return !error && data.user !== null;
    },
    async rpc(nombre, argumentos): Promise<RpcResult> {
      const { data, error } = await cliente.schema("crm").rpc(
        nombre,
        argumentos,
      );
      return {
        data,
        error: error ? { code: error.code, message: error.message } : null,
      };
    },
  };
}

const handler = crearHandlerUsuarios({
  crearActor,
  origenesAdicionales: ORIGENES_ADICIONALES,

  async crearUsuarioAuth({ correo, nombreCompleto, passwordAleatoria }) {
    const { data, error } = await authAdmin.auth.admin.createUser({
      email: correo,
      password: passwordAleatoria,
      email_confirm: false,
      user_metadata: {
        nombre_completo: nombreCompleto,
        origen: "crm",
      },
    });
    return {
      id: error ? null : data.user?.id ?? null,
      error: error ? "auth_create_failed" : null,
    };
  },

  async buscarUsuarioAuthPorCorreo(correo) {
    const buscado = correo.toLowerCase();
    // Admin listUsers no expone la service key ni datos al cliente. La cota
    // evita un loop ilimitado; este camino solo se usa para retry/duplicado.
    for (let page = 1; page <= 20; page++) {
      const { data, error } = await authAdmin.auth.admin.listUsers({
        page,
        perPage: 100,
      });
      if (error) return null;
      const encontrado = data.users.find((u) =>
        u.email?.toLowerCase() === buscado
      );
      if (encontrado) return encontrado.id;
      if (data.users.length < 100) return null;
    }
    return null;
  },

  async eliminarUsuarioAuth(id) {
    // Compensacion best-effort solo para una identidad creada en ESTA llamada.
    // La respuesta nunca incluye el error ni el identificador Auth interno.
    await authAdmin.auth.admin.deleteUser(id);
  },

  async enviarRecuperacion(correo) {
    const { error } = await authAdmin.auth.resetPasswordForEmail(correo, {
      redirectTo: REDIRECT_RECUPERACION,
    });
    return { error: error ? "recovery_send_failed" : null };
  },

  passwordAleatoria() {
    // Secreto efimero de 244 bits aproximados. Nunca sale de este isolate, no
    // se registra y el usuario define su propia clave mediante recuperacion.
    return `${crypto.randomUUID()}${crypto.randomUUID()}`;
  },
});

Deno.serve(handler);
