import { equal } from "node:assert/strict";
import {
  crearHandlerValoracion,
  type DependenciasValoracion,
} from "./handler.ts";

const CLAVE = "servicio-local-ficticio-para-pruebas-123456";
const trabajo = {
  fecha_corte: "2026-10-02",
  politica: "sbs_punto_medio_7d_v1",
  reserva: "reserva-local",
};
function banco() {
  const llamadas: string[] = [];
  const deps: DependenciasValoracion = {
    claveServicio: CLAVE,
    ahora: () => Date.parse("2026-10-05T15:00:00Z"),
    fetch: (() =>
      Promise.resolve(
        Response.json({
          periods: [23, 24, 25, 28, 29, 30].map((d) => ({
            name: `${d}.Set.26`,
            values: ["3.400"],
          })).concat([
            { name: "01.Oct.26", values: ["3.400"] },
            { name: "02.Oct.26", values: ["3.400"] },
          ]),
        }),
      )) as typeof fetch,
    reconciliar: () => {
      llamadas.push("reconciliar");
      return Promise.resolve({ creadas: 1 });
    },
    reevaluarCierre: () => {
      llamadas.push("reevaluar");
      return Promise.resolve({ evaluado: false, motivo: "cron_pausado" });
    },
    tomar: () => {
      llamadas.push("tomar");
      return Promise.resolve([trabajo]);
    },
    resolver: (_t, evidencia, motivo) => {
      llamadas.push(evidencia ? "consolidar" : `pendiente:${motivo}`);
      return Promise.resolve({});
    },
  };
  return { deps, llamadas };
}
const request = (token = CLAVE, body = "{}", method = "POST") =>
  new Request("https://local.invalid/crm-capital-valorar", {
    method,
    headers: { Authorization: `Bearer ${token}` },
    ...(method === "POST" ? { body } : {}),
  });

Deno.test("un usuario o anónimo no pueden hacer trabajar al servicio", async () => {
  const b = banco();
  equal(
    (await crearHandlerValoracion(b.deps)(request("jwt-usuario"))).status,
    401,
  );
  equal(b.llamadas.length, 0);
});
Deno.test("servicio sin clave configurada queda cerrado", async () => {
  const b = banco();
  b.deps.claveServicio = "";
  equal((await crearHandlerValoracion(b.deps)(request(""))).status, 503);
  equal(b.llamadas.length, 0);
});
Deno.test("rechaza tasas y operaciones proporcionadas desde el request", async () => {
  const b = banco();
  for (const body of ['{"tasa":3.4}', "[]", "null", "{mal", "x".repeat(1025)]) {
    equal(
      (await crearHandlerValoracion(b.deps)(request(CLAVE, body))).status,
      400,
    );
  }
  equal(b.llamadas.length, 0);
});
Deno.test("solo admite POST", async () => {
  equal(
    (await crearHandlerValoracion(banco().deps)(request(CLAVE, "", "GET")))
      .status,
    405,
  );
});
Deno.test("consolida evidencia y materializa después, con límites de trabajo persistentes", async () => {
  const b = banco();
  const r = await crearHandlerValoracion(b.deps)(request());
  equal(r.status, 200);
  equal((await r.json()).consolidados, 1);
  equal(
    b.llamadas.join(","),
    "reconciliar,tomar,consolidar,reconciliar,reevaluar",
  );
});
Deno.test("caída BCRP deja reintento persistente y conserva las ventas", async () => {
  const b = banco();
  b.deps.fetch = (() => Promise.reject(new Error("proveedor"))) as typeof fetch;
  const r = await crearHandlerValoracion(b.deps)(request());
  equal(r.status, 200);
  equal((await r.json()).pendientes, 1);
  equal(b.llamadas.includes("pendiente:fuente_no_disponible"), true);
});
Deno.test("un fallo de base no anuncia éxito ni filtra detalles internos", async () => {
  const b = banco();
  b.deps.tomar = () => Promise.reject(new Error("dato-privado-no-mostrar"));
  const r = await crearHandlerValoracion(b.deps)(request());
  equal(r.status, 502);
  equal((await r.text()).includes("dato-privado"), false);
});

Deno.test("una reserva vencida no abandona la confirmación de las otras fechas", async () => {
  const b = banco();
  b.deps.tomar = () =>
    Promise.resolve([trabajo, {
      ...trabajo,
      fecha_corte: "2026-10-01",
      reserva: "segunda",
    }]);
  b.deps.resolver = (t) => {
    if (t.reserva === trabajo.reserva) {
      return Promise.reject(new Error("PT409"));
    }
    b.llamadas.push("segunda-confirmada");
    return Promise.resolve({});
  };
  const r = await crearHandlerValoracion(b.deps)(request());
  equal(r.status, 200);
  const resultado = await r.json();
  equal(resultado.consolidados, 1);
  equal(resultado.reservas_sin_confirmar, 1);
  equal(b.llamadas.at(-1), "reevaluar");
});

Deno.test("una imputación legada solicita el método de su mes original", async () => {
  const b = banco();
  b.deps.tomar = () =>
    Promise.resolve([{
      ...trabajo,
      fecha_corte: "2026-09-30",
      politica: "sbs_punto_medio_hasta7_legado_v1",
    }]);
  let politica: string | undefined;
  b.deps.resolver = (_t, e) => {
    politica = e?.politica;
    return Promise.resolve({});
  };
  const r = await crearHandlerValoracion(b.deps)(request());
  equal(r.status, 200);
  equal(politica, "sbs_punto_medio_hasta7_legado_v1");
});

Deno.test("sin avance no pide reevaluación; tampoco interpreta contadores ilegibles como avance", async () => {
  for (
    const resultado of [
      { creadas: 0, cortes_publicados: 0 },
      { creadas: "1" },
      null,
    ]
  ) {
    const b = banco();
    b.deps.reconciliar = () => Promise.resolve(resultado);
    b.deps.tomar = () => Promise.resolve([]);
    const r = await crearHandlerValoracion(b.deps)(request());
    equal(r.status, 200);
    equal((await r.json()).reevaluacion.motivo, "sin_cambios");
    equal(b.llamadas.includes("reevaluar"), false);
  }
});

Deno.test("un corte nuevo de una venta ya valorada pide el ciclo después de ambas reconciliaciones", async () => {
  const b = banco();
  let confirmadas = 0;
  b.deps.reconciliar = async () => {
    await Promise.resolve();
    confirmadas += 1;
    return { creadas: 0, cortes_publicados: confirmadas === 1 ? 1 : 0 };
  };
  b.deps.tomar = () => Promise.resolve([]);
  b.deps.reevaluarCierre = () => {
    equal(confirmadas, 2);
    b.llamadas.push("reevaluar");
    return Promise.resolve({ evaluado: true });
  };
  const r = await crearHandlerValoracion(b.deps)(request());
  equal((await r.json()).reevaluacion.evaluado, true);
  equal(b.llamadas.filter((s) => s === "reevaluar").length, 1);
});

Deno.test("si falla la petición de cierre conserva las valoraciones aceptadas y anuncia el reintento pendiente", async () => {
  const b = banco();
  b.deps.reevaluarCierre = () =>
    Promise.reject(new Error("detalle-privado-del-cierre"));
  const r = await crearHandlerValoracion(b.deps)(request());
  const cuerpo = await r.json();
  equal(r.status, 200);
  equal(cuerpo.consolidados, 1);
  equal(cuerpo.materializacion.creadas, 1);
  equal(cuerpo.reevaluacion.motivo, "solicitud_pendiente");
  equal(JSON.stringify(cuerpo).includes("detalle-privado"), false);
});

Deno.test("el servicio informa la pausa sin reinterpretarla como error de valoración", async () => {
  const r = await crearHandlerValoracion(banco().deps)(request());
  const cuerpo = await r.json();
  equal(r.status, 200);
  equal(cuerpo.reevaluacion.evaluado, false);
  equal(cuerpo.reevaluacion.motivo, "cron_pausado");
  equal(cuerpo.materializacion.creadas, 1);
});
