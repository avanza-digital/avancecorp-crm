export type CategoriaResultadoImportacion =
  | "importado"
  | "duplicado"
  | "ya_cliente"
  | "rechazado"
  | "error_temporal";

export type ResultadoImportacion = {
  resultado: CategoriaResultadoImportacion;
  estado: string;
  /** Solo en `ya_cliente`: el lead canónico de la persona (para registrar el reingreso). */
  lead_id?: string;
  asesor?: string;
};

type ErrorPostgrestMinimo = {
  code?: string | null;
  message?: string | null;
  details?: string | null;
};

/**
 * Veredicto de disponibilidad que el servidor adjunta en DETAIL (P0481/P0429)
 * como JSON. Devuelve null si no hay JSON legible.
 */
export function veredictoDeError(
  error: ErrorPostgrestMinimo,
): Record<string, unknown> | null {
  const crudo = String(error?.details ?? "").trim();
  if (!crudo.startsWith("{")) return null;
  try {
    const v = JSON.parse(crudo);
    return v && typeof v === "object" ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const CODIGOS_TEMPORALES = new Set([
  "55P03", // lock_not_available
  "57014", // query_canceled / timeout
  "57P01", // admin_shutdown
  "57P02", // crash_shutdown
  "57P03", // cannot_connect_now
]);

/**
 * Convierte un fallo de INSERT en una categoría estable para la hoja.
 *
 * Las restricciones/datos inválidos son definitivos y requieren corregir la fila.
 * Los fallos de conexión, concurrencia, capacidad o servidor se reintentan: nunca
 * deben congelarse en la hoja como un rechazo permanente. Una carrera contra el
 * índice único de teléfono es un duplicado, no un error crudo de Postgres.
 */
export function clasificarErrorInsercion(
  error: ErrorPostgrestMinimo,
  status?: number | null,
): ResultadoImportacion {
  const codigo = String(error?.code ?? "").trim().toUpperCase();
  if (codigo === "23505") {
    return {
      resultado: "duplicado",
      estado: "DUPLICADO: ya existe en el CRM",
    };
  }

  // F2.b b1 (identidad unificada, con la bandera resolver_en_puertas encendida):
  // la BD reconoce a la PERSONA por su documento. «Ya es cliente» no es un
  // rechazo: es un reingreso que se registra en SU lead. «No insistir» sí lo es.
  if (codigo === "P0481") {
    const v = veredictoDeError(error);
    if (v?.estado === "ya_es_cliente" && v?.via === "identidad") {
      const asesor = typeof v.asesor === "string" ? v.asesor : "";
      return {
        resultado: "ya_cliente",
        estado: `YA ES CLIENTE: reingreso registrado en su ficha${
          asesor ? ` (asesor: ${asesor})` : ""
        }`,
        lead_id: typeof v.lead_id === "string" ? v.lead_id : undefined,
        asesor: asesor || undefined,
      };
    }
    const estado = typeof v?.estado === "string" ? v.estado : "no disponible";
    return {
      resultado: "rechazado",
      estado: `RECHAZADO: contacto ${estado.replace(/_/g, " ")}`,
    };
  }
  if (codigo === "P0429") {
    return {
      resultado: "rechazado",
      estado: "RECHAZADO: la persona tiene la restricción «No insistir»",
    };
  }

  const clase = codigo.slice(0, 2);
  const statusTemporal = status === 0 || status === 408 || status === 425 ||
    status === 429 || (typeof status === "number" && status >= 500);
  const codigoTemporal = CODIGOS_TEMPORALES.has(codigo) ||
    ["08", "40", "53", "58", "XX"].includes(clase);

  if (statusTemporal || codigoTemporal) {
    return {
      resultado: "error_temporal",
      estado:
        "ERROR temporal: el CRM no confirmó la importación — se reintenta solo",
    };
  }

  const detalle = String(error?.message ?? "el CRM rechazó los datos")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 120) || "el CRM rechazó los datos";
  return {
    resultado: "rechazado",
    estado: `RECHAZADO: ${detalle}`,
  };
}
