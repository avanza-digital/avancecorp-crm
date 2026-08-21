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
const SUPERVISOR_ID = "10000000-0000-4000-8000-000000000004";
const REQUEST_ID = "90000000-0000-4000-8000-000000000001";
const ORIGIN = "https://crm.miavance.com";

type EstadoFake = {
  rpcs: string[];
  argumentosRpc: Record<string, unknown>[];
  altasAuth: number;
  documentosAuth: string[];
  busquedasAuth: number;
};

function fake(opciones: {
  sesion?: boolean;
  respuestas?: RpcResult[];
  altaAuth?: { id: string | null; error: string | null };
  authExistente?: string | null;
} = {}): { deps: DependenciasUsuarios; estado: EstadoFake } {
  const respuestas = [...(opciones.respuestas ?? [])];
  const estado: EstadoFake = {
    rpcs: [],
    argumentosRpc: [],
    altasAuth: 0,
    documentosAuth: [],
    busquedasAuth: 0,
  };
  return {
    estado,
    deps: {
      crearActor: () => ({
        verificarSesion: () => Promise.resolve(opciones.sesion ?? true),
        rpc: (nombre, argumentos) => {
          estado.rpcs.push(nombre);
          estado.argumentosRpc.push(argumentos);
          return Promise.resolve(
            respuestas.shift() ?? { data: null, error: null },
          );
        },
      }),
      crearUsuarioAuth: (input) => {
        estado.altasAuth++;
        estado.documentosAuth.push(input.documento);
        return Promise.resolve(
          opciones.altaAuth ?? { id: ID, error: null },
        );
      },
      buscarUsuarioAuthPorCorreo: () => {
        estado.busquedasAuth++;
        return Promise.resolve(opciones.authExistente ?? null);
      },
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
    supervisor_id: SUPERVISOR_ID,
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

Deno.test("supervisor es obligatorio y debe ser UUID", async () => {
  for (const supervisor_id of [undefined, null, "", "no-es-uuid"]) {
    const f = fake();
    const payload = alta();
    if (supervisor_id === undefined) delete payload.supervisor_id;
    else payload.supervisor_id = supervisor_id;
    const res = await crearHandlerUsuarios(f.deps)(request(payload));
    igual(res.status, 400, `rechazo supervisor ${String(supervisor_id)}`);
    igual(f.estado.rpcs.length, 0, "sin DB ante supervisor invalido");
    igual(f.estado.altasAuth, 0, "sin Auth ante supervisor invalido");
  }
});

Deno.test("alta feliz crea Auth con documento exacto y no inicia recuperacion", async () => {
  const f = fake({
    respuestas: [
      { data: null, error: null },
      { data: { perfil_id: ID, estado: "activo" }, error: null },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 201, "status alta");
  igual(f.estado.altasAuth, 1, "una alta Auth");
  igual(f.estado.documentosAuth.join(","), "12345678", "clave documento");
  igual(
    f.estado.rpcs.join(","),
    "buscar_candidato_por_correo_fn,registrar_vendedor_usuario_fn",
    "orden de fronteras",
  );
  igual(
    f.estado.argumentosRpc[1]?.p_supervisor_id,
    SUPERVISOR_ID,
    "supervisor llega a la frontera DB",
  );
  const texto = await res.text();
  assert(
    !/password|contrase|token|secret|correo@|12345678/i.test(texto),
    "respuesta sin secretos",
  );
});

Deno.test("CE conserva ceros y pasaporte se normaliza sin relleno", async () => {
  for (
    const [tipo, documento, esperado] of [
      ["CE", "001237707", "001237707"],
      ["PASAPORTE", "ab1234", "AB1234"],
    ] as const
  ) {
    const f = fake({
      respuestas: [
        { data: null, error: null },
        { data: { perfil_id: ID, estado: "activo" }, error: null },
      ],
    });
    const res = await crearHandlerUsuarios(f.deps)(
      request(alta({ tipo_documento: tipo, documento })),
    );
    igual(res.status, 201, `status ${tipo}`);
    igual(f.estado.documentosAuth.join(","), esperado, `documento ${tipo}`);
  }
});

Deno.test("candidato Portal existente conserva su identidad Auth", async () => {
  const f = fake({
    respuestas: [
      { data: ID, error: null },
      { data: { perfil_id: ID, estado: "candidato_existente" }, error: null },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 200, "status candidato existente");
  igual(f.estado.altasAuth, 0, "no recrea Auth");
  igual(f.estado.busquedasAuth, 0, "no busca ni muta Auth Admin");
  igual(
    f.estado.rpcs.join(","),
    "buscar_candidato_por_correo_fn,registrar_vendedor_usuario_fn",
    "DB decide sin mutar la identidad Portal",
  );
  igual(
    (await res.json()).estado,
    "candidato_existente",
    "estado existente",
  );
});

Deno.test("candidato CRM pendiente como Alan se activa sin recrear ni borrar Auth", async () => {
  const f = fake({
    respuestas: [
      { data: ID, error: null },
      { data: { perfil_id: ID, estado: "activo" }, error: null },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta({
    nombre_completo: "ALAN YUTRONIC",
    tipo_documento: "CE",
    documento: "001237707",
  })));
  igual(res.status, 200, "status candidato CRM pendiente");
  igual(f.estado.altasAuth, 0, "no recrea Auth existente");
  igual(f.estado.busquedasAuth, 0, "no recorre Auth Admin");
  igual((await res.json()).estado, "activo", "estado activo");
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

Deno.test("un error de validacion DB no se presenta como falta de autorizacion", async () => {
  const f = fake({
    respuestas: [
      { data: null, error: { code: "P0001", message: "correo invalido" } },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 400, "status validacion");
  igual(
    (await res.json()).error,
    "No se pudo validar el candidato CRM",
    "mensaje no confunde validacion con autorizacion",
  );
  igual(f.estado.altasAuth, 0, "no crea Auth ante error DB");
});

Deno.test("fallo DB conserva la identidad CRM para retry concurrente seguro", async () => {
  const f = fake({
    respuestas: [
      { data: null, error: null },
      { data: null, error: { code: "23505", message: "duplicado" } },
    ],
  });
  const res = await crearHandlerUsuarios(f.deps)(request(alta()));
  igual(res.status, 409, "status conflicto");
  igual(f.estado.altasAuth, 1, "la identidad fue creada una sola vez");
});

Deno.test("retry con Auth preexistente conserva la identidad ajena si DB rechaza", async () => {
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
});

Deno.test("la antigua accion de recuperacion deja de existir", async () => {
  const f = fake();
  const res = await crearHandlerUsuarios(f.deps)(request({
    accion: "enviar_recuperacion",
    request_id: REQUEST_ID,
    perfil_id: ID,
  }));
  igual(res.status, 400, "status accion retirada");
  igual(f.estado.rpcs.length, 0, "sin RPC de recuperacion");
  igual(f.estado.altasAuth, 0, "sin Auth Admin");
});
