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
      // El estado NO afirma todavía «registrado»: eso lo compone el edge solo
      // después de que la RPC de reingreso haya tenido éxito.
      return {
        resultado: "ya_cliente",
        estado: `YA ES CLIENTE${asesor ? ` (asesor: ${asesor})` : ""}`,
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

/**
 * F2.b [D-4] (auditor A1): un error de la PUERTA que no es un veredicto sobre la fila —la RPC no existe
 * (PGRST202 / 42883: reversa aplicada o caché de PostgREST rancia), el EXECUTE se perdió (42501) o un 404—
 * es un problema del CRM, no de la fila: TEMPORAL, para que la hoja la reintente en vez de congelarla como
 * RECHAZADA. Cualquier otro error sigue la clasificación de siempre (definitivo vs temporal).
 */
export function clasificarErrorPuerta(
  error: ErrorPostgrestMinimo,
  status?: number | null,
): ResultadoImportacion {
  const codigo = String(error?.code ?? "").trim().toUpperCase();
  if (
    codigo === "PGRST202" || codigo === "42883" || codigo === "42501" ||
    status === 404
  ) {
    return {
      resultado: "error_temporal",
      estado:
        "ERROR temporal: la puerta del importador no está disponible en el CRM — se reintenta solo",
    };
  }
  return clasificarErrorInsercion(error, status);
}

// ── F2.b [D-4] (bloque 3): el importador entra por la puerta SQL crm.importar_lead_fn ───────────────────────────────
// La puerta hace el MISMO INSERT que hacía este edge y devuelve un veredicto en vez de una excepción. Los textos que
// llegan a la hoja son los mismos de siempre: aquí solo cambia de dónde sale la categoría.

export type ReingresoPuerta = {
  ok?: boolean;
  repetido?: boolean;
  actividad_id?: string;
  error?: string;
} | null;

/** F2.b [D-20]: lo que la puerta hizo con la solicitud de un cliente que ya no tiene lead vivo. */
export type SolicitudPuerta = {
  ok?: boolean;
  repetido?: boolean;
  actividad_id?: string;
  tarea_id?: string;
  sin_tarea?: boolean;
  sin_ficha?: boolean;
  vetado?: boolean;
  error?: string;
} | null;

export type RespuestaPuerta = {
  resultado: "importado" | "duplicado" | "ya_cliente" | "rechazado";
  lead_id?: string | null;
  veredicto?: Record<string, unknown> | null;
  reingreso?: ReingresoPuerta;
  solicitud?: SolicitudPuerta;
};

/** Texto de rechazo a partir del veredicto (el mismo que hoy sale del DETAIL del INSERT). */
export function textoRechazoDeVeredicto(
  veredicto: Record<string, unknown> | null | undefined,
): string {
  const estado = typeof veredicto?.estado === "string"
    ? veredicto.estado
    : "no disponible";
  // P0429 (trigger 000, identidad encendida): la PERSONA tiene «No insistir».
  if (estado === "no_contactar" && veredicto?.via === "identidad") {
    return "RECHAZADO: la persona tiene la restricción «No insistir»";
  }
  return `RECHAZADO: contacto ${estado.replace(/_/g, " ")}`;
}

/**
 * Convierte la respuesta de crm.importar_lead_fn en la categoría estable de la hoja.
 * `ya_cliente` compone además el texto del reingreso (registrado / no se pudo anotar), que antes componía el edge tras
 * llamar aparte a registrar_reingreso_lead_fn.
 */
const CATEGORIAS_PUERTA = new Set([
  "importado",
  "duplicado",
  "ya_cliente",
  "rechazado",
]);

export function clasificarRespuestaPuerta(
  r: RespuestaPuerta | null | undefined,
): ResultadoImportacion {
  // Solo las cuatro categorías del contrato; cualquier otra cosa (una versión de
  // la puerta que este edge no conoce) es temporal, nunca un rechazo (Codex v3 #4).
  if (
    !r || typeof r !== "object" || typeof r.resultado !== "string" ||
    !CATEGORIAS_PUERTA.has(r.resultado)
  ) {
    return {
      resultado: "error_temporal",
      estado:
        "ERROR temporal: el CRM no confirmó la importación — se reintenta solo",
    };
  }
  if (r.resultado === "importado") {
    return {
      resultado: "importado",
      estado: "IMPORTADO ✓",
      lead_id: r.lead_id ?? undefined,
    };
  }
  if (r.resultado === "duplicado") {
    return { resultado: "duplicado", estado: "DUPLICADO: ya existe en el CRM" };
  }
  if (r.resultado === "ya_cliente") {
    const v = r.veredicto ?? {};
    const asesor = typeof v.asesor === "string" ? v.asesor : "";
    const base = `YA ES CLIENTE${asesor ? ` (asesor: ${asesor})` : ""}`;
    const lead_id = typeof r.lead_id === "string" ? r.lead_id : undefined;
    let estado = base;
    if (r.reingreso && r.reingreso.ok === true) {
      // `repetido`: la hoja reenvió la misma fila (perdió la confirmación) y la
      // puerta reconoció el reingreso ya anotado en las últimas 24 h (v5).
      estado = r.reingreso.repetido === true
        ? `${base}: reingreso ya anotado en su ficha`
        : `${base}: reingreso registrado en su ficha`;
    } else if (r.reingreso && typeof r.reingreso.error === "string") {
      estado = `${base}: NO se pudo anotar el reingreso en su ficha (${
        r.reingreso.error.slice(0, 60)
      })`;
    } else if (r.solicitud) {
      // F2.b [D-20] (auditor A3): el cliente ya no tiene lead vivo, así que la solicitud va a su ficha y a la agenda
      // de su analista. Sin esto la hoja decía «YA ES CLIENTE» tanto si quedó tarea como si no quedó NADA, que es
      // justo el agujero que D-20 viene a cerrar.
      const s = r.solicitud;
      if (s.ok === true && s.repetido === true) {
        estado = `${base}: solicitud ya anotada en su ficha`;
      } else if (s.ok === true && s.sin_tarea === true) {
        estado = `${base}: solicitud anotada en su ficha, SIN analista para la tarea`;
      } else if (s.ok === true) {
        estado = `${base}: solicitud anotada y tarea para su analista`;
      } else if (s.vetado === true) {
        estado = `${base}: no se registra seguimiento («No insistir»)`;
      } else if (s.sin_ficha === true) {
        estado = `${base}: NO se pudo anotar (nadie a cargo de este cliente)`;
      } else {
        estado = `${base}: NO se pudo anotar la solicitud${
          typeof s.error === "string" ? ` (${s.error.slice(0, 60)})` : ""
        }`;
      }
    }
    return {
      resultado: "ya_cliente",
      estado,
      lead_id,
      asesor: asesor || undefined,
    };
  }
  return {
    resultado: "rechazado",
    estado: textoRechazoDeVeredicto(r.veredicto),
  };
}
