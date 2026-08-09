import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// crm-tipo-cambio — TC USD→PEN real para la meta del vendedor.
//
// Fuente: API pública oficial del BCRP (sin token), series diarias del
// TC del Sistema bancario SBS: PD04639PD (compra) y PD04640PD (venta).
// Se promedia el PUNTO MEDIO (compra+venta)/2 de los últimos 7 días hábiles.
// SUNAT publica sobre la base de la SBS, así que es la referencia natural
// para una métrica comercial (no tributaria) como la meta del mes.
//
// Sin BD ni service_role: la edge es un proxy de solo lectura con cache en
// memoria (1 h por isolate). Si el BCRP no responde, 502 → el frontend degrada
// a null y la meta vuelve a "pendiente de tipo de cambio" (nunca inventa TC).
//
// CORS calcado de crm-convertir-lead (el CRM vive en su subdominio).

const ALLOWED_ORIGINS = new Set([
  "https://crm.miavance.com",
  "https://www.crm.miavance.com",
]);

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "https://crm.miavance.com",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
}

const BCRP_BASE = "https://estadisticas.bcrp.gob.pe/estadisticas/series/api";
const SERIE_COMPRA = "PD04639PD"; // TC Sistema bancario SBS (S/ por US$) - Compra
const SERIE_VENTA = "PD04640PD"; // TC Sistema bancario SBS (S/ por US$) - Venta
const DIAS_VENTANA = 16; // calendario: garantiza ≥7 hábiles aun con feriados
const DIAS_PROMEDIO = 7;
const CACHE_MS = 60 * 60 * 1000; // 1 h — el TC diario no cambia más rápido

interface Resultado {
  promedio: number;
  fuente: string;
  dias: number;
  desde: string;
  hasta: string;
}

// Cache por isolate: sobrevive entre invocaciones calientes; un isolate frío
// simplemente vuelve a consultar (el BCRP responde en cientos de ms).
let cache: { en: number; resultado: Resultado } | null = null;

/** Fecha 'YYYY-MM-DD' en Lima (UTC-5 fijo, Perú no tiene horario de verano). */
function fechaLima(desplazamientoDias = 0): string {
  const ms = Date.now() - 5 * 3600 * 1000 + desplazamientoDias * 86_400_000;
  return new Date(ms).toISOString().slice(0, 10);
}

/** Descarga una serie del BCRP → mapa período ("08.Jul.26") → valor numérico. */
async function serieBcrp(codigo: string, desde: string, hasta: string): Promise<Map<string, number>> {
  const url = `${BCRP_BASE}/${codigo}/json/${desde}/${hasta}/ing`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`BCRP respondió ${res.status} para ${codigo}`);
  const cuerpo = await res.json();
  const mapa = new Map<string, number>();
  for (const p of cuerpo?.periods ?? []) {
    const valor = Number(p?.values?.[0]);
    if (Number.isFinite(valor) && valor > 0) mapa.set(String(p.name), valor);
  }
  return mapa;
}

// Los períodos del BCRP (serie pedida en /ing) llegan como "08.Jul.26".
const MES_ING: Record<string, number> = {
  Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
  Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11,
};

/** Clave ordenable de un período "DD.MMM.YY"; formato inesperado → 0 (va al fondo). */
function clavePeriodo(p: string): number {
  const [dia, mes, anio] = p.split(".");
  const m = MES_ING[mes ?? ""];
  const t = m == null ? Number.NaN : Date.UTC(2000 + Number(anio), m, Number(dia));
  return Number.isFinite(t) ? t : 0;
}

async function calcular(): Promise<Resultado> {
  const desde = fechaLima(-DIAS_VENTANA);
  const hasta = fechaLima(0);
  const [compra, venta] = await Promise.all([
    serieBcrp(SERIE_COMPRA, desde, hasta),
    serieBcrp(SERIE_VENTA, desde, hasta),
  ]);

  // Punto medio por día; si un lado falta ese día, vale el otro (mejor un dato
  // de un solo lado que descartar el día entero).
  //
  // ⚠️ ORDEN EXPLÍCITO (hallazgo Codex 2026-08-09): la unión de claves hereda
  // el orden de inserción — un período que solo trae `venta` quedaba APPENDEADO
  // al final y `slice(-7)` podía promediar un día viejo y excluir uno reciente.
  // Se ordena cronológicamente ANTES de recortar.
  const periodos = [...new Set([...compra.keys(), ...venta.keys()])];
  const medios = periodos
    .map((p) => {
      const c = compra.get(p);
      const v = venta.get(p);
      if (c != null && v != null) return { p, t: clavePeriodo(p), valor: (c + v) / 2 };
      return { p, t: clavePeriodo(p), valor: (c ?? v)! };
    })
    .filter((x) => Number.isFinite(x.valor) && x.valor > 0)
    .sort((a, b) => a.t - b.t);

  const ultimos = medios.slice(-DIAS_PROMEDIO);
  if (ultimos.length === 0) throw new Error("BCRP sin datos en la ventana consultada");

  const promedio = ultimos.reduce((a, b) => a + b.valor, 0) / ultimos.length;
  return {
    promedio: Math.round(promedio * 10_000) / 10_000,
    // Rótulo honesto: si el BCRP entregó menos de 7 días hábiles (feriados
    // largos, respuesta parcial), la fuente declara el conteo REAL — jamás se
    // anuncia un promedio de 7 días que no lo es (hallazgo Codex 2026-08-09).
    fuente: `SBS · prom. ${ultimos.length}d`,
    dias: ultimos.length,
    desde: ultimos[0].p,
    hasta: ultimos[ultimos.length - 1].p,
  };
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    if (cache && Date.now() - cache.en < CACHE_MS) {
      return json(cors, cache.resultado, 200);
    }
    const resultado = await calcular();
    cache = { en: Date.now(), resultado };
    return json(cors, resultado, 200);
  } catch (e) {
    // Sin TC no se inventa TC: el frontend degrada la meta a solo-PEN.
    return json(cors, { error: (e as Error)?.message || "No se pudo obtener el tipo de cambio" }, 502);
  }
});

function json(cors: Record<string, string>, payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
