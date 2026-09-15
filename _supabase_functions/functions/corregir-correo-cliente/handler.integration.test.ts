import { createClient } from "jsr:@supabase/supabase-js@2.110.2";
import { corregirCorreoCliente } from "./handler.ts";

// Banco propio y sintético; nunca admite un destino de producción.
const env = JSON.parse(
  await Deno.readTextFile(
    "/private/tmp/avance-correo-admin-bank/credenciales.json",
  ),
);
if (env.API_URL !== "http://127.0.0.1:60321") {
  throw new Error("Solo banco local de correos");
}
const opciones = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, opciones);
const nuevos: string[] = [];
const password = `Prueba!${crypto.randomUUID()}`;
const marca = crypto.randomUUID().slice(0, 8);
function comprobar(valor: unknown, mensaje: string): asserts valor {
  if (!valor) throw new Error(mensaje);
}
async function alta(rol: string, activo = true) {
  const email = `${marca}-${rol}-${nuevos.length}@example.test`;
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { conservar: "valor" },
  });
  comprobar(!error && data.user, error?.message ?? "alta sin usuario");
  nuevos.push(data.user.id);
  const id = data.user.id;
  const perfil = await admin.from("perfiles").insert({
    id,
    rol,
    activo,
    correo: email,
  });
  comprobar(!perfil.error, perfil.error?.message ?? "perfil");
  const sesion = await createClient(env.API_URL, env.ANON_KEY, opciones).auth
    .signInWithPassword({ email, password });
  comprobar(sesion.data.session, sesion.error?.message ?? "login actor");
  return { id, email, token: sesion.data.session.access_token };
}
async function invocar(
  token: string,
  clienteId: string,
  correo: string,
  motivo = "Corrección solicitada",
  api = admin,
) {
  return await corregirCorreoCliente(
    new Request("https://miavance.com/corregir", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Origin: "https://miavance.com",
      },
      body: JSON.stringify({
        cliente_id: clienteId,
        correo,
        motivo,
        p_actor_id: "ignorado",
      }),
    }),
    api,
  );
}
async function estado(id: string) {
  const auth = await admin.auth.admin.getUserById(id);
  const perfil = await admin.from("perfiles").select("*").eq("id", id).single();
  comprobar(auth.data.user && perfil.data, "estado ausente");
  return { user: auth.data.user, perfil: perfil.data };
}
function sql(texto: string) {
  const r = new Deno.Command("/opt/homebrew/opt/postgresql@17/bin/psql", {
    args: [
      "postgresql://postgres:postgres@127.0.0.1:60322/postgres",
      "-X",
      "-qAt",
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      texto,
    ],
    stdout: "piped",
    stderr: "piped",
  }).outputSync();
  comprobar(r.success, new TextDecoder().decode(r.stderr));
  return new TextDecoder().decode(r.stdout).trim();
}

Deno.test({
  name: "Corrección de clientes con Auth y Postgres reales",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async (t) => {
    try {
      const operador = await alta("admin");
      const superior = await alta("superadmin");
      const cliente = await alta("cliente");
      const analista = await alta("analista");
      const inactivo = await alta("admin", false);
      let vigente = cliente.email;
      await t.step(
        "admin cambia correo: nuevo login, misma clave, identidad y perfil alineados",
        async () => {
          const nuevo = `${marca}-nuevo@example.test`;
          const r = await invocar(operador.token, cliente.id, nuevo);
          comprobar(r.status === 200, `${r.status}: ${await r.text()}`);
          const s = await estado(cliente.id);
          comprobar(
            s.user.email === nuevo && s.perfil.correo === nuevo,
            "perfil o Auth desalineado",
          );
          comprobar(
            s.user.identities?.find((i) => i.provider === "email")
              ?.identity_data?.email === nuevo,
            "identidad desalineada",
          );
          comprobar(
            s.user.app_metadata.conservar === "valor",
            "se perdió app_metadata ajeno",
          );
          const nuevoLogin = await createClient(
            env.API_URL,
            env.ANON_KEY,
            opciones,
          ).auth.signInWithPassword({ email: nuevo, password });
          comprobar(
            nuevoLogin.data.session,
            nuevoLogin.error?.message ?? "no entra con nuevo",
          );
          const viejoLogin = await createClient(
            env.API_URL,
            env.ANON_KEY,
            opciones,
          ).auth.signInWithPassword({ email: vigente, password });
          comprobar(viejoLogin.error, "el correo anterior todavía entra");
          vigente = nuevo;
          comprobar(
            sql(
              `select count(*) from crm.correcciones_correo_acceso where cliente_id='${cliente.id}' and por='${operador.id}' and auth_confirmado_en is not null`,
            ) === "1",
            "falta auditoría con actor",
          );
        },
      );
      await t.step("superadmin también puede corregir", async () => {
        const nuevo = `${marca}-super@example.test`;
        const r = await invocar(superior.token, cliente.id, nuevo);
        comprobar(r.status === 200, await r.text());
        vigente = nuevo;
      });
      await t.step(
        "rechaza cliente, analista, admin inactivo y sesión inválida",
        async () => {
          for (const actor of [cliente, analista, inactivo]) {
            const r = await invocar(
              actor.token,
              cliente.id,
              `${marca}-denegado@example.test`,
            );
            comprobar(
              r.status === 403,
              `rol sin permiso respondió ${r.status}`,
            );
          }
          comprobar(
            (await invocar("token-falso", cliente.id, vigente)).status === 401,
            "JWT inválido admitido",
          );
          comprobar(
            (await estado(cliente.id)).user.email === vigente,
            "denegado cambió acceso",
          );
        },
      );
      await t.step(
        "rechaza objetivos del equipo, duplicados y motivo ausente",
        async () => {
          comprobar(
            (await invocar(
              operador.token,
              analista.id,
              `${marca}-equipo@example.test`,
            )).status === 404,
            "modificó staff",
          );
          comprobar(
            (await invocar(operador.token, cliente.id, analista.email))
              .status === 409,
            "admitió duplicado",
          );
          comprobar(
            (await invocar(operador.token, cliente.id, vigente, "")).status ===
              400,
            "admitió motivo vacío",
          );
          comprobar(
            (await estado(cliente.id)).user.email === vigente,
            "rechazo cambió acceso",
          );
        },
      );
      await t.step(
        "el navegador no puede suplantar actor por RPC ni editar correo por tabla",
        async () => {
          const navegador = createClient(env.API_URL, env.ANON_KEY, {
            ...opciones,
            global: { headers: { Authorization: `Bearer ${operador.token}` } },
          });
          const rpc = await navegador.schema("crm").rpc(
            "preparar_correccion_correo_acceso_fn",
            {
              p_cliente_id: cliente.id,
              p_actor_id: superior.id,
              p_correo: vigente,
              p_motivo: "Suplantar",
            },
          );
          comprobar(rpc.error?.code === "42501", "RPC privilegiada expuesta");
          const update = await navegador.from("perfiles").update({
            correo: `${marca}-atajo@example.test`,
          }).eq("id", cliente.id);
          comprobar(
            update.error?.code === "42501",
            "atajo de perfil permitido",
          );
        },
      );
      await t.step(
        "un rechazo del perfil revierte Auth y el reintento posterior funciona",
        async () => {
          const nuevo = `${marca}-rollback@example.test`;
          sql(
            "alter table public.perfiles add constraint prueba_correo_rechazo check(correo not like '%-rollback@%')",
          );
          const r = await invocar(operador.token, cliente.id, nuevo);
          comprobar(r.status !== 200, "anunció éxito rechazado");
          const s = await estado(cliente.id);
          comprobar(
            s.user.email === vigente && s.perfil.correo === vigente,
            "fallo dejó cambio parcial",
          );
          sql(
            "alter table public.perfiles drop constraint prueba_correo_rechazo",
          );
          const retry = await invocar(operador.token, cliente.id, nuevo);
          comprobar(retry.status === 200, await retry.text());
          vigente = nuevo;
        },
      );
      await t.step("recupera un commit cuya respuesta se perdió", async () => {
        const api = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
          ...opciones,
          global: {
            fetch: async (input, init) => {
              const res = await fetch(input, init);
              if (
                init?.method === "PUT" &&
                String(input).includes("/admin/users/")
              ) throw new Error("Pérdida simulada después del commit");
              return res;
            },
          },
        });
        const nuevo = `${marca}-respuesta@example.test`;
        const r = await invocar(
          operador.token,
          cliente.id,
          nuevo,
          "Respuesta perdida",
          api,
        );
        comprobar(r.status === 200, await r.text());
        vigente = nuevo;
      });
      await t.step(
        "dos correcciones simultáneas conservan Auth, identidad y perfil alineados",
        async () => {
          const respuestas = await Promise.all(
            ["uno", "dos"].map((x) =>
              invocar(operador.token, cliente.id, `${marca}-${x}@example.test`)
            ),
          );
          comprobar(
            respuestas.some((r) => r.status === 200),
            "ninguna corrección pudo confirmarse",
          );
          const s = await estado(cliente.id);
          comprobar(
            s.user.email === s.perfil.correo,
            "concurrencia desalineó perfil",
          );
          comprobar(
            s.user.identities?.find((i) => i.provider === "email")
              ?.identity_data?.email === s.user.email,
            "concurrencia desalineó identidad",
          );
          vigente = s.user.email!;
        },
      );
      await t.step(
        "cambiar contraseña y metadatos de usuario conserva el correo",
        async () => {
          const r = await admin.auth.admin.updateUserById(cliente.id, {
            password,
            user_metadata: { prueba: true },
          });
          comprobar(!r.error, r.error?.message ?? "cambio password bloqueado");
          comprobar(
            (await estado(cliente.id)).user.email === vigente,
            "cambio de contraseña movió correo",
          );
        },
      );
    } finally {
      for (const id of nuevos) {
        const r = await admin.auth.admin.deleteUser(id);
        comprobar(!r.error, r.error?.message ?? "limpieza fallida");
      }
    }
  },
});
