import {
  crearHandlerUsuarios,
  type DependenciasUsuarios,
  type RpcResult,
} from "./handler.ts";

function assert(condicion: unknown, mensaje: string): asserts condicion {
  if (!condicion) throw new Error(mensaje);
}

function igual(actual: unknown, esperado: unknown, mensaje: string) {
  if (actual !== esperado) {
    throw new Error(
      `${mensaje}: esperado=${String(esperado)} actual=${String(actual)}`,
    );
  }
}

const ID = "10000000-0000-4000-8000-000000000009";
const REQUEST_ID = "90000000-0000-4000-8000-000000000001";
const ORIGIN = "https://crm.miavance.com";

type EstadoFake = {
  rpcs: string[];
  altasAuth: number;
  busquedasAuth: number;
  borrados: string[];
  recuperaciones: number;
};

function fake(opciones: {
  sesion?: boolean;
  respuestas?: RpcResult[];
  altaAuth?: { id: string | null; error: string | null };
  authExistente?: string | null;
  errorRecuperacion?: string | null;
} = {}): { deps: DependenciasUsuarios; estado: EstadoFake } {
  const respuestas = [...(opciones.respuestas ?? [])];
  const estado: EstadoFake = {
    rpcs: [],
    altasAuth: 0,
    busquedasAuth: 0,
    borrados: [],
    recuperaciones: 0,
  };
  return {
    estado,
    deps: {
      crearActor: () => ({
        verificarSesion: async () => opciones.sesion ?? true,
        rpc: async (nombre) => {
          estado.rpcs.push(nombre);
          return respuestas.shift() ?? { data: null, error: null };
        },
      }),
      crearUsuarioAuth: async () => {
        estado.altasAuth++;
        return opciones.altaAuth ?? { id: ID, error: null };
      },
      buscarUsuarioAuthPorCorreo: async () => {
        estado.busquedasAuth++;
        return opciones.authExistente ?? null;
      },
      eliminarUsuarioAuth: async (id) => {
        estado.borrados.push(id);
      },
      enviarRecuperacion: async () => {
        estado.recuperaciones++;
        return { error: opciones.errorRecuperacion ?? null };
      },
      passwordAleatoria: () => "NO_SE_EXPONE_012345678901234567890123456789",
    },
  };
}

function request(
  body: Record<string, unknown>,
  extra: HeadersInit = {},
): Request {
  return new Request("https://project.supabase.co/functions/v1/crm-usuarios", {
    method: "POST",
    headers: {
      Origin: ORIGIN,
      Authorization: "Bearer jwt-valido",
      "Content-Type": "application/json",
      ...extra,
    },
    body: JSON.stringify(body),
  });
}

function alta(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    accion: "crear_candidato",
    request_id: REQUEST_ID,
    correo: "persona@avance.test",
    nombre_completo: "Persona de Prueba",
    tipo_documento: "DNI",
    documento: "12345678",
    telefono: "+51911111111",
    whatsapp: "+51911111111",
    cargo: "Asesor",
    ...overrides,
  };
}

Deno.test("preflight permitido devuelve CORS exacto sin tocar dependencias", async () => {
  const { deps, estado } = fake();
  const handler = crearHandlerUsuarios(deps);
  const res = await handler(
    new Request("https://x/functions/v1/crm-usuarios", {
      method: "OPTIONS",
      headers: { Origin: ORIGIN },
    }),
  );
  igual(res.status, 204, "status preflight");
  igual(res.headers.get("Access-Control-Allow-Origin"), ORIGIN, "origin CORS");
  igual(estado.rpcs.length, 0, "preflight sin DB");
  igual(estado.altasAuth, 0, "preflight sin Auth Admin");
});

Deno.test("origen ajeno se rechaza incluso en preflight", async () => {
  const { deps } = fake();
  const res = await crearHandlerUsuarios(deps)(
    new Request("https://x", {
      method: "OPTIONS",
      headers: { Origin: "https://malicioso.example" },
    }),
  );
  igual(res.status, 403, "status origen ajeno");
  assert(
    res.headers.get("Access-Control-Allow-Origin") !==
      "https://malicioso.example",
    "no refleja origin hostil",
  );
});

Deno.test("origen local configurado se permite sin relajar la lista exacta", async () => {
  const f = fake();
  f.deps.origenesAdicionales = ["http://localhost:5173"];
  const handler = crearHandlerUsuarios(f.deps);
  const permitido = await handler(
    new Request("https://x/functions/v1/crm-usuarios", {
      method: "OPTIONS",
      headers: { Origin: "http://localhost:5173" },
    }),
  );
  igual(permitido.status, 204, "status origen local configurado");
  igual(
    permitido.headers.get("Access-Control-Allow-Origin"),
    "http://localhost:5173",
    "refleja solo el origen exacto permitido",
  );

  const parecido = await handler(
    new Request("https://x/functions/v1/crm-usuarios", {
      method: "OPTIONS",
      headers: { Origin: "http://localhost:5174" },
    }),
  );
  igual(parecido.status, 403, "otro puerto sigue bloqueado");
});

Deno.test("sin bearer o con sesion invalida nunca toca Auth Admin", async () => {
  const f = fake({ sesion: false });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 401, "status sesion invalida");
  igual(f.estado.altasAuth, 0, "sin Auth Admin");
});

Deno.test("payload con rol, activo o password se rechaza por esquema estricto", async () => {
  for (const campo of ["rol_crm", "activo", "password"]) {
    const f = fake();
    const res = await crearHandlerUsuarios(f.deps)(
      request(alta({ [campo]: "inyectado" })),
    );
    igual(res.status, 400, `rechazo de ${campo}`);
    igual(f.estado.altasAuth, 0, `${campo} no alcanza Auth Admin`);
  }
});

Deno.test("alta feliz autoriza en DB, crea Auth, registra candidato y envia recuperacion", async () => {
  const f = fake({
    respuestas: [
      { data: null, error: null },
      { data: { perfil_id: ID, estado: "pendiente_rol" }, error: null },
      { data: { perfil_id: ID, correo: "persona@avance.test" }, error: null },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 201, "status alta");
  igual(f.estado.altasAuth, 1, "una alta Auth");
  igual(f.estado.recuperaciones, 1, "una recuperacion");
  igual(
    f.estado.rpcs.join(","),
    "buscar_candidato_por_correo_fn,registrar_candidato_usuario_fn,preparar_recuperacion_usuario_fn",
    "orden de fronteras",
  );
  const texto = await res.text();
  assert(
    !/password|contrase|token|secret|correo@/i.test(texto),
    "respuesta sin secretos",
  );
});

Deno.test("Gerencia no autorizada falla antes de Auth Admin", async () => {
  const f = fake({
    respuestas: [
      { data: null, error: { code: "42501", message: "solo Gerencia" } },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 403, "status no autorizado");
  igual(f.estado.altasAuth, 0, "no crea identidad antes de autorizar");
});

Deno.test("fallo al registrar compensa solo la identidad creada en esta llamada", async () => {
  const f = fake({
    respuestas: [
      { data: null, error: null },
      { data: null, error: { code: "23505", message: "duplicado" } },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 409, "status conflicto");
  igual(f.estado.borrados.join(","), ID, "compensacion Auth");
});

Deno.test("retry con Auth preexistente no borra la identidad ajena si DB rechaza", async () => {
  const f = fake({
    altaAuth: { id: null, error: "duplicate" },
    authExistente: ID,
    respuestas: [
      { data: null, error: null },
      { data: null, error: { code: "P0001", message: "perfil Portal ajeno" } },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 400, "status perfil ajeno");
  igual(f.estado.busquedasAuth, 1, "busca Auth para retry");
  igual(f.estado.borrados.length, 0, "no borra Auth preexistente");
});

Deno.test("recuperacion usa objetivo autorizado por RPC y no expone correo", async () => {
  const f = fake({
    respuestas: [
      { data: { perfil_id: ID, correo: "persona@avance.test" }, error: null },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request({
    accion: "enviar_recuperacion",
    request_id: REQUEST_ID,
    perfil_id: ID,
  }));
  igual(res.status, 200, "status recuperacion");
  igual(f.estado.recuperaciones, 1, "envio recovery");
  assert(
    !(await res.text()).includes("persona@avance.test"),
    "correo no vuelve al cliente",
  );
});
