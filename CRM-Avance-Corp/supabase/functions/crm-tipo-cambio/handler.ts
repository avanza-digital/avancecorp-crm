// crm-tipo-cambio — TC USD→PEN real para el ranking mensual.
//
// Fuente: API pública oficial del BCRP (sin token), series diarias del
// TC del Sistema bancario SBS: PD04639PD (compra) y PD04640PD (venta).
// Para una fecha de corte se promedia el PUNTO MEDIO (compra+venta)/2 de
// las últimas 7 fechas publicadas por el BCRP hasta ese día. Esas fechas son
// los días hábiles efectivos de la fuente; un fin de semana toma los últimos
// datos publicados anteriores, nunca datos posteriores al corte.
//
// Sin BD ni service_role: esta Edge Function es un proxy de solo lectura. Si
// el BCRP falla, responde 502 y el frontend degrada a solo-PEN sin inventar TC.
//
// Trampa conocida de la fuente: aunque se pida `/ing`, el BCRP rotula
// septiembre en español («02.Set.26») y el resto en inglés («03.Aug.26»).
// Un período ilegible NO se descarta en silencio: se responde 502 nombrándolo.

const ALLOWED_ORIGINS = new Set([
  "https://crm.miavance.com",
  "https://www.crm.miavance.com",
]);

const BCRP_BASE = "https://estadisticas.bcrp.gob.pe/estadisticas/series/api";
const SERIE_COMPRA = "PD04639PD";
const SERIE_VENTA = "PD04640PD";
const DIAS_VENTANA = 16;
const DIAS_PROMEDIO = 7;
const CACHE_MS = 60 * 60 * 1000;
const MAX_CORTES_EN_CACHE = 64;
const HORA_LIMA_MS = 5 * 60 * 60 * 1000;
const DIA_MS = 86_400_000;

export interface ResultadoTipoCambio {
  promedio: number;
  fuente: string;
  dias: number;
  desde: string;
  hasta: string;
  fecha_corte: string;
}

export interface DependenciasTipoCambio {
  fetch: typeof fetch;
  ahora: () => number;
}

type EntradaCache = {
  en: number;
  resultado: ResultadoTipoCambio;
};

type FechaSolicitada =
  | { ok: true; fechaCorte: string }
  | { ok: false; error: string };

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin)
      ? origin
      : "https://crm.miavance.com",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
}

/** Fecha `YYYY-MM-DD` en Lima (UTC-5 fijo; Perú no usa horario de verano). */
export function fechaLima(ahoraMs: number): string {
  return new Date(ahoraMs - HORA_LIMA_MS).toISOString().slice(0, 10);
}

function esFechaIsoCalendario(valor: unknown): valor is string {
  if (typeof valor !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(valor)) {
    return false;
  }
  const fecha = new Date(`${valor}T00:00:00.000Z`);
  return Number.isFinite(fecha.getTime()) &&
    fecha.toISOString().slice(0, 10) === valor;
}

function desplazarFecha(fecha: string, dias: number): string {
  const base = Date.parse(`${fecha}T00:00:00.000Z`);
  return new Date(base + dias * DIA_MS).toISOString().slice(0, 10);
}

async function leerFechaCorte(
  req: Request,
  hoy: string,
): Promise<FechaSolicitada> {
  const url = new URL(req.url);
  const tieneQuery = url.searchParams.has("fecha_corte");
  const corteQuery = tieneQuery
    ? url.searchParams.get("fecha_corte")
    : undefined;

  let tieneBody = false;
  let corteBody: unknown;
  if (req.method === "POST") {
    const raw = await req.text();
    if (raw.trim() !== "") {
      let body: unknown;
      try {
        body = JSON.parse(raw);
      } catch {
        return { ok: false, error: "JSON invalido" };
      }
      // `null` y `{}` conservan compatibilidad con invocaciones sin corte.
      if (body != null) {
        if (typeof body !== "object" || Array.isArray(body)) {
          return { ok: false, error: "Payload invalido" };
        }
        const objeto = body as Record<string, unknown>;
        if (Object.keys(objeto).some((clave) => clave !== "fecha_corte")) {
          return { ok: false, error: "Payload contiene campos no permitidos" };
        }
        tieneBody = Object.hasOwn(objeto, "fecha_corte");
        corteBody = objeto.fecha_corte;
      }
    }
  }

  if (tieneQuery && tieneBody && corteQuery !== corteBody) {
    return { ok: false, error: "fecha_corte ambigua" };
  }
  const valor = tieneBody ? corteBody : tieneQuery ? corteQuery : hoy;
  if (!esFechaIsoCalendario(valor)) {
    return { ok: false, error: "fecha_corte debe tener formato YYYY-MM-DD" };
  }
  if (valor > hoy) {
    return { ok: false, error: "fecha_corte no puede estar en el futuro" };
  }
  return { ok: true, fechaCorte: valor };
}

/** Descarga una serie BCRP → mapa período (`08.Jul.26`) → valor numérico. */
async function serieBcrp(
  deps: DependenciasTipoCambio,
  codigo: string,
  desde: string,
  hasta: string,
): Promise<Map<string, number>> {
  const url = `${BCRP_BASE}/${codigo}/json/${desde}/${hasta}/ing`;
  const res = await deps.fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`BCRP respondió ${res.status} para ${codigo}`);
  const cuerpo = await res.json();
  const mapa = new Map<string, number>();
  for (const periodo of cuerpo?.periods ?? []) {
    const valor = Number(periodo?.values?.[0]);
    if (Number.isFinite(valor) && valor > 0) {
      mapa.set(String(periodo.name), valor);
    }
  }
  return mapa;
}

// Abreviaturas en AMBOS idiomas para TODOS los meses: el BCRP mezcla («Set»
// en septiembre, «Aug» en agosto) y nada garantiza que mañana no filtre «Ene»
// o «Dic». La clave se normaliza (trim + minúsculas) antes de buscar.
const MESES: Record<string, number> = {
  ene: 0,
  jan: 0,
  feb: 1,
  mar: 2,
  abr: 3,
  apr: 3,
  may: 4,
  jun: 5,
  jul: 6,
  ago: 7,
  aug: 7,
  set: 8,
  sep: 8,
  sept: 8,
  oct: 9,
  nov: 10,
  dic: 11,
  dec: 11,
};

/**
 * Clave ordenable de `DD.MMM.YY` (o `DD.MMM.YYYY`); `null` si el formato no
 * se reconoce. Devolver `null` y no 0 permite distinguir «período ilegible»
 * de «período fuera de la ventana», que antes se confundían en el filtro.
 */
export function clavePeriodo(periodo: string): number | null {
  const partes = periodo.trim().split(".");
  if (partes.length !== 3) return null;
  const [dia, mes, anio] = partes.map((parte) => parte.trim().toLowerCase());
  const numeroMes = MESES[mes];
  if (
    numeroMes == null || !/^\d{1,2}$/.test(dia) || !/^(\d{2}|\d{4})$/.test(anio)
  ) {
    return null;
  }
  const anioCompleto = anio.length === 2 ? 2000 + Number(anio) : Number(anio);
  const timestamp = Date.UTC(anioCompleto, numeroMes, Number(dia));
  return Number.isFinite(timestamp) ? timestamp : null;
}

export async function calcularTipoCambio(
  deps: DependenciasTipoCambio,
  fechaCorte: string,
): Promise<ResultadoTipoCambio> {
  const desdeConsulta = desplazarFecha(fechaCorte, -DIAS_VENTANA);
  const corteTimestamp = Date.parse(`${fechaCorte}T00:00:00.000Z`);
  const [compra, venta] = await Promise.all([
    serieBcrp(deps, SERIE_COMPRA, desdeConsulta, fechaCorte),
    serieBcrp(deps, SERIE_VENTA, desdeConsulta, fechaCorte),
  ]);

  // La unión no tiene orden cronológico garantizado. Se ordena antes de tomar
  // los últimos siete días hábiles. Si falta compra o venta en una fecha, se
  // usa el lado publicado para no descartar un día válido de la fuente.
  const periodos = [...new Set([...compra.keys(), ...venta.keys()])];
  const noReconocidos: string[] = [];
  const medios = periodos
    .flatMap((periodo) => {
      const timestamp = clavePeriodo(periodo);
      if (timestamp == null) {
        noReconocidos.push(periodo);
        return [];
      }
      const compraDia = compra.get(periodo);
      const ventaDia = venta.get(periodo);
      const valor = compraDia != null && ventaDia != null
        ? (compraDia + ventaDia) / 2
        : (compraDia ?? ventaDia)!;
      return [{ periodo, timestamp, valor }];
    })
    .filter((item) =>
      item.timestamp <= corteTimestamp &&
      Number.isFinite(item.valor) && item.valor > 0
    )
    .sort((a, b) => a.timestamp - b.timestamp);

  const ultimos = medios.slice(-DIAS_PROMEDIO);
  if (ultimos.length === 0) {
    // Dos silencios distintos: la fuente no publicó nada (serie vacía o todo
    // «n.d.») o publicó y no supimos leerlo. El segundo es un bug nuestro y
    // tiene que nombrar el período que lo disparó; antes ambos decían lo mismo.
    if (periodos.length > 0 && noReconocidos.length === periodos.length) {
      throw new Error(
        `BCRP: formato de período no reconocido: ${noReconocidos[0]}`,
      );
    }
    throw new Error("BCRP sin datos en la ventana consultada");
  }

  const promedio = ultimos.reduce((total, item) => total + item.valor, 0) /
    ultimos.length;
  return {
    promedio: Math.round(promedio * 10_000) / 10_000,
    fuente: `SBS · prom. ${ultimos.length}d`,
    dias: ultimos.length,
    desde: ultimos[0].periodo,
    hasta: ultimos[ultimos.length - 1].periodo,
    fecha_corte: fechaCorte,
  };
}

function json(
  cors: Record<string, string>,
  payload: unknown,
  status: number,
): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

export function crearHandlerTipoCambio(deps: DependenciasTipoCambio) {
  // El corte forma parte de la clave: agosto y septiembre nunca comparten TC.
  // El límite evita crecimiento indefinido si un isolate recibe muchos cortes.
  const cachePorCorte = new Map<string, EntradaCache>();

  return async (req: Request): Promise<Response> => {
    const cors = corsHeaders(req);
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: cors });
    }
    if (req.method !== "GET" && req.method !== "POST") {
      return json(cors, { error: "Metodo no permitido" }, 405);
    }

    const ahora = deps.ahora();
    const solicitada = await leerFechaCorte(req, fechaLima(ahora));
    if (!solicitada.ok) {
      return json(cors, { error: solicitada.error }, 400);
    }

    const corte = solicitada.fechaCorte;
    const cache = cachePorCorte.get(corte);
    if (cache && ahora - cache.en < CACHE_MS) {
      // Refrescar orden de inserción para una expulsión LRU simple.
      cachePorCorte.delete(corte);
      cachePorCorte.set(corte, cache);
      return json(cors, cache.resultado, 200);
    }

    try {
      const resultado = await calcularTipoCambio(deps, corte);
      cachePorCorte.set(corte, { en: ahora, resultado });
      while (cachePorCorte.size > MAX_CORTES_EN_CACHE) {
        const masAntiguo = cachePorCorte.keys().next().value;
        if (masAntiguo === undefined) break;
        cachePorCorte.delete(masAntiguo);
      }
      return json(cors, resultado, 200);
    } catch (error) {
      return json(cors, {
        error: (error as Error)?.message ||
          "No se pudo obtener el tipo de cambio",
      }, 502);
    }
  };
}
