import { timingSafeEqual } from "node:crypto";
import {
  type EvidenciaTipoCambio,
  obtenerLoteEvidenciasTipoCambio,
  POLITICA_TC_LEGADA,
  prepararEvidenciaTipoCambioLegado,
} from "../crm-tipo-cambio/consolidacion.ts";

export interface TrabajoTipoCambio {
  fecha_corte: string;
  politica: string;
  reserva: string;
}

export interface DependenciasValoracion {
  claveServicio: string;
  fetch: typeof fetch;
  ahora: () => number;
  reconciliar: () => Promise<unknown>;
  reevaluarCierre: () => Promise<unknown>;
  tomar: () => Promise<TrabajoTipoCambio[]>;
  resolver: (
    trabajo: TrabajoTipoCambio,
    evidencia: EvidenciaTipoCambio | null,
    motivo: string | null,
  ) => Promise<unknown>;
}

const json = (datos: unknown, status = 200) =>
  Response.json(datos, { status, headers: { "Cache-Control": "no-store" } });

function hayAvance(resultado: unknown): boolean {
  if (resultado == null || typeof resultado !== "object") return false;
  const r = resultado as Record<string, unknown>;
  return [r.creadas, r.cortes_publicados].some((n) =>
    typeof n === "number" && Number.isInteger(n) && n > 0
  );
}

/** Solo servicio: un JWT de usuario o un payload con tasas nunca autorizan. */
export function crearHandlerValoracion(deps: DependenciasValoracion) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return json({ error: "Método no permitido" }, 405);
    }
    if (deps.claveServicio.length < 30) {
      return json({ error: "Servicio no configurado" }, 503);
    }
    const recibida = new TextEncoder().encode(
      req.headers.get("Authorization") ?? "",
    );
    const esperada = new TextEncoder().encode(`Bearer ${deps.claveServicio}`);
    if (
      recibida.length !== esperada.length ||
      !timingSafeEqual(recibida, esperada)
    ) {
      return json({ error: "No autorizado" }, 401);
    }
    const raw = await req.text();
    if (raw.length > 1024) return json({ error: "Payload inválido" }, 400);
    if (raw.trim() !== "") {
      let body: unknown;
      try {
        body = JSON.parse(raw);
      } catch {
        return json({ error: "JSON inválido" }, 400);
      }
      if (
        body == null || typeof body !== "object" || Array.isArray(body) ||
        Object.keys(body).length !== 0
      ) {
        return json({
          error: "El trabajo no acepta tasas ni operaciones del cliente",
        }, 400);
      }
    }
    try {
      const inicial = await deps.reconciliar();
      const trabajos = await deps.tomar();
      let lote:
        | Awaited<ReturnType<typeof obtenerLoteEvidenciasTipoCambio>>
        | null = null;
      if (trabajos.length) {
        try {
          lote = await obtenerLoteEvidenciasTipoCambio(
            trabajos.map((t) => t.fecha_corte),
            deps,
          );
        } catch {
          // Una sola descarga por serie y lote; la cola regula el reintento.
        }
      }
      const resultados = await Promise.allSettled(
        trabajos.map(async (trabajo) => {
          try {
            const r = lote && trabajo.politica === POLITICA_TC_LEGADA
              ? prepararEvidenciaTipoCambioLegado(
                trabajo.fecha_corte,
                lote.hasta_verificado,
                lote.respuestas.compra,
                lote.respuestas.venta,
                lote.huella_respuestas,
              )
              : lote?.porCorte.get(trabajo.fecha_corte);
            if (!r) throw new Error("Fuente no disponible");
            await deps.resolver(
              trabajo,
              r.estado === "consolidado" ? r.evidencia : null,
              r.estado === "pendiente" ? r.motivo : null,
            );
            return r.estado;
          } catch {
            // El error del proveedor no impide valorar las otras fechas. Si la
            // base tampoco responde, la reserva persistente expira y se retoma.
            await deps.resolver(trabajo, null, "fuente_no_disponible");
            return "pendiente" as const;
          }
        }),
      );
      const materializacion = await deps.reconciliar();
      let reevaluacion: unknown = { evaluado: false, motivo: "sin_cambios" };
      if (hayAvance(inicial) || hayAvance(materializacion)) {
        try {
          // Cada reconciliación anterior ya confirmó su transacción. No se
          // conserva ningún lock del materializador mientras el ciclo cierra.
          reevaluacion = await deps.reevaluarCierre();
        } catch {
          // La valoración aceptada permanece aunque falle esta solicitud.
          // El ciclo normal sigue siendo la recuperación del cierre.
          reevaluacion = { evaluado: false, motivo: "solicitud_pendiente" };
        }
      }
      return json({
        consolidados: resultados.filter((r) =>
          r.status === "fulfilled" && r.value === "consolidado"
        ).length,
        pendientes: resultados.filter((r) =>
          r.status === "fulfilled" && r.value === "pendiente"
        ).length,
        reservas_sin_confirmar: resultados.filter((r) =>
          r.status === "rejected"
        ).length,
        materializacion,
        reevaluacion,
      });
    } catch {
      return json({
        error: "No se completó el ciclo; los trabajos conservan su reintento",
      }, 502);
    }
  };
}
