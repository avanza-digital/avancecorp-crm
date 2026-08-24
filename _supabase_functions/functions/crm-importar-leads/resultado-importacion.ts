export type CategoriaResultadoImportacion =
  | "importado"
  | "duplicado"
  | "rechazado"
  | "error_temporal";

export type ResultadoImportacion = {
  resultado: CategoriaResultadoImportacion;
  estado: string;
};

type ErrorPostgrestMinimo = {
  code?: string | null;
  message?: string | null;
};

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
