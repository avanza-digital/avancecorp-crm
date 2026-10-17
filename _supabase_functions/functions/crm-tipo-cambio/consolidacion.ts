// Evidencia para fijar el TC comercial por fecha. El promedio monetario se
// calcula en Postgres numeric; aquí se conservan los valores decimales fuente.
import { clavePeriodo, fechaLima } from "./handler.ts";

export const POLITICA_TC_VENTA = "sbs_punto_medio_7d_v1";
export const POLITICA_TC_LEGADA = "sbs_punto_medio_hasta7_legado_v1";
const BASE = "https://estadisticas.bcrp.gob.pe/estadisticas/series/api";
const DIA = 86_400_000;

export interface ParCotizacion {
  fecha: string;
  compra: string | null;
  venta: string | null;
}

export interface EvidenciaTipoCambio {
  fecha_corte: string;
  politica: typeof POLITICA_TC_VENTA | typeof POLITICA_TC_LEGADA;
  publicacion_confirmada: string;
  pares: ParCotizacion[];
  fuente: "BCRP · SBS PD04639PD/PD04640PD";
  huella_respuestas: string;
}

export type ConsolidacionTipoCambio =
  | { estado: "consolidado"; evidencia: EvidenciaTipoCambio }
  | {
    estado: "pendiente";
    motivo: "publicacion_pendiente" | "serie_parcial" | "historia_insuficiente";
  };

type CuerpoSerie = { periods?: { name?: unknown; values?: unknown[] }[] };

function fechaCalendario(valor: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(valor)) return false;
  const t = Date.parse(`${valor}T00:00:00Z`);
  return Number.isFinite(t) && new Date(t).toISOString().slice(0, 10) === valor;
}

function mapaSerie(cuerpo: unknown): Map<string, string> {
  if (
    cuerpo == null || typeof cuerpo !== "object" ||
    !Array.isArray((cuerpo as CuerpoSerie).periods)
  ) throw new Error("BCRP: respuesta sin períodos válidos");
  const mapa = new Map<string, string>();
  for (const fila of (cuerpo as Required<CuerpoSerie>).periods) {
    const raw = fila?.values?.[0];
    if (raw == null || String(raw).trim().toLowerCase() === "n.d.") continue;
    const decimal = String(raw).trim();
    if (!/^\d{1,6}(\.\d{1,10})?$/.test(decimal) || Number(decimal) <= 0) {
      throw new Error("BCRP: cotización decimal inválida");
    }
    const periodo = String(fila.name ?? "");
    const t = clavePeriodo(periodo);
    if (t == null) throw new Error(`BCRP: período no reconocido: ${periodo}`);
    // clavePeriodo legado acepta el rollover de Date.UTC. Una tasa permanente
    // exige que también coincida el día real del calendario.
    const fecha = new Date(t).toISOString().slice(0, 10);
    if (Number(periodo.trim().split(".")[0]) !== Number(fecha.slice(8))) {
      throw new Error(`BCRP: período fuera del calendario: ${periodo}`);
    }
    const anterior = mapa.get(fecha);
    if (anterior != null && Number(anterior) !== Number(decimal)) {
      throw new Error(`BCRP: cotizaciones contradictorias para ${fecha}`);
    }
    mapa.set(fecha, decimal);
  }
  return mapa;
}

/** La publicación posterior acredita disponibilidad; nunca entra al promedio. */
export function prepararEvidenciaTipoCambio(
  corte: string,
  hastaVerificado: string,
  compra: unknown,
  venta: unknown,
  huellaRespuestas: string,
): ConsolidacionTipoCambio {
  if (
    !fechaCalendario(corte) || !fechaCalendario(hastaVerificado) ||
    corte > hastaVerificado
  ) {
    throw new Error("Fecha de corte/verificación inválida");
  }
  if (!/^[a-f0-9]{64}$/.test(huellaRespuestas)) {
    throw new Error("Huella inválida");
  }
  const compras = mapaSerie(compra), ventas = mapaSerie(venta);
  const confirmada =
    [...compras.keys()].filter((f) =>
      f >= corte && f <= hastaVerificado && ventas.has(f)
    ).sort()[0];
  if (confirmada == null) {
    return { estado: "pendiente", motivo: "publicacion_pendiente" };
  }
  const fechas = [...new Set([...compras.keys(), ...ventas.keys()])]
    .filter((f) => f <= corte).sort().slice(-7);
  if (fechas.some((f) => !compras.has(f) || !ventas.has(f))) {
    return { estado: "pendiente", motivo: "serie_parcial" };
  }
  if (fechas.length < 7) {
    return { estado: "pendiente", motivo: "historia_insuficiente" };
  }
  return {
    estado: "consolidado",
    evidencia: {
      fecha_corte: corte,
      politica: POLITICA_TC_VENTA,
      publicacion_confirmada: confirmada,
      pares: fechas.map((fecha) => ({
        fecha,
        compra: compras.get(fecha)!,
        venta: ventas.get(fecha)!,
      })),
      fuente: "BCRP · SBS PD04639PD/PD04640PD",
      huella_respuestas: huellaRespuestas,
    },
  };
}

/** Reconstrucción del régimen anterior, solo para cortes preoctubre. */
export function prepararEvidenciaTipoCambioLegado(
  corte: string,
  hastaVerificado: string,
  compra: unknown,
  venta: unknown,
  huellaRespuestas: string,
): ConsolidacionTipoCambio {
  if (
    !fechaCalendario(corte) || !fechaCalendario(hastaVerificado) ||
    corte > hastaVerificado || corte >= "2026-10-01"
  ) {
    throw new Error("El corte legado debe ser anterior a octubre de 2026");
  }
  if (!/^[a-f0-9]{64}$/.test(huellaRespuestas)) {
    throw new Error("Huella inválida");
  }
  const compras = mapaSerie(compra), ventas = mapaSerie(venta);
  const confirmada =
    [...compras.keys()].filter((f) =>
      f >= corte && f <= hastaVerificado && ventas.has(f)
    ).sort()[0];
  if (!confirmada) {
    return { estado: "pendiente", motivo: "publicacion_pendiente" };
  }
  const desde = new Date(Date.parse(`${corte}T00:00:00Z`) - 16 * DIA)
    .toISOString().slice(0, 10);
  const fechas = [...new Set([...compras.keys(), ...ventas.keys()])]
    .filter((f) => f >= desde && f <= corte).sort().slice(-7);
  if (!fechas.length) {
    return { estado: "pendiente", motivo: "historia_insuficiente" };
  }
  return {
    estado: "consolidado",
    evidencia: {
      fecha_corte: corte,
      politica: POLITICA_TC_LEGADA,
      publicacion_confirmada: confirmada,
      pares: fechas.map((fecha) => ({
        fecha,
        compra: compras.get(fecha) ?? null,
        venta: ventas.get(fecha) ?? null,
      })),
      fuente: "BCRP · SBS PD04639PD/PD04640PD",
      huella_respuestas: huellaRespuestas,
    },
  };
}

async function descargar(
  fetcher: typeof fetch,
  serie: string,
  desde: string,
  hasta: string,
) {
  const respuesta = await fetcher(
    `${BASE}/${serie}/json/${desde}/${hasta}/ing`,
    {
      signal: AbortSignal.timeout(10_000),
    },
  );
  if (!respuesta.ok) {
    throw new Error(`BCRP respondió ${respuesta.status} para ${serie}`);
  }
  const texto = await respuesta.text();
  if (texto.length > 512_000) {
    throw new Error("BCRP: respuesta demasiado grande");
  }
  try {
    return { cuerpo: JSON.parse(texto) as unknown, texto };
  } catch {
    throw new Error(`BCRP: respuesta no JSON para ${serie}`);
  }
}

/** Un lote comparte las dos descargas; evita pedir la misma serie por venta. */
export async function obtenerLoteEvidenciasTipoCambio(
  cortes: string[],
  deps: { fetch: typeof fetch; ahora: () => number },
) {
  const hoy = fechaLima(deps.ahora());
  const fechas = [...new Set(cortes)].sort();
  if (
    fechas.length === 0 || fechas.length > 62 ||
    fechas.some((f) => !fechaCalendario(f) || f > hoy)
  ) {
    throw new Error("Lote de fechas inválido");
  }
  const desde = new Date(Date.parse(`${fechas[0]}T00:00:00Z`) - 64 * DIA)
    .toISOString().slice(0, 10);
  const [compra, venta] = await Promise.all([
    descargar(deps.fetch, "PD04639PD", desde, hoy),
    descargar(deps.fetch, "PD04640PD", desde, hoy),
  ]);
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${compra.texto}\n${venta.texto}`),
  );
  const huella = [...new Uint8Array(bytes)].map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
  return {
    porCorte: new Map(
      fechas.map((
        fecha,
      ) => [
        fecha,
        prepararEvidenciaTipoCambio(
          fecha,
          hoy,
          compra.cuerpo,
          venta.cuerpo,
          huella,
        ),
      ]),
    ),
    respuestas: { compra: compra.cuerpo, venta: venta.cuerpo },
    huella_respuestas: huella,
    hasta_verificado: hoy,
  };
}

export async function obtenerEvidenciaTipoCambio(
  corte: string,
  deps: { fetch: typeof fetch; ahora: () => number },
): Promise<ConsolidacionTipoCambio> {
  const hoy = fechaLima(deps.ahora());
  if (!fechaCalendario(corte) || corte > hoy) {
    throw new Error("Fecha de corte inválida o futura");
  }
  for (const ventana of [16, 32, 64]) {
    const desde = new Date(Date.parse(`${corte}T00:00:00Z`) - ventana * DIA)
      .toISOString().slice(0, 10);
    const [compra, venta] = await Promise.all([
      descargar(deps.fetch, "PD04639PD", desde, hoy),
      descargar(deps.fetch, "PD04640PD", desde, hoy),
    ]);
    const bytes = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(`${compra.texto}\n${venta.texto}`),
    );
    const huella = [...new Uint8Array(bytes)].map((b) =>
      b.toString(16).padStart(2, "0")
    ).join("");
    const resultado = prepararEvidenciaTipoCambio(
      corte,
      hoy,
      compra.cuerpo,
      venta.cuerpo,
      huella,
    );
    if (
      resultado.estado === "consolidado" ||
      resultado.motivo !== "historia_insuficiente" || ventana === 64
    ) {
      return resultado;
    }
  }
  throw new Error("No se completó la consulta del BCRP");
}
