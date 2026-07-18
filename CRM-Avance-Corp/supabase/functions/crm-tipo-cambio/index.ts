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

async function calcular(): Promise<Resultado> {
  const desde = fechaLima(-DIAS_VENTANA);
  const hasta = fechaLima(0);
  const [compra, venta] = await Promise.all([
    serieBcrp(SERIE_COMPRA, desde, hasta),
    serieBcrp(SERIE_VENTA, desde, hasta),
  ]);

  // Punto medio por día; si un lado falta ese día, vale el otro (mejor un dato
  // de un solo lado que descartar el día entero).
  const periodos = [...new Set([...compra.keys(), ...venta.keys()])];
  const medios = periodos
    .map((p) => {
      const c = compra.get(p);
      const v = venta.get(p);
      if (c != null && v != null) return { p, valor: (c + v) / 2 };
      return { p, valor: (c ?? v)! };
    })
    .filter((x) => Number.isFinite(x.valor) && x.valor > 0);

  const ultimos = medios.slice(-DIAS_PROMEDIO);
  if (ultimos.length === 0) throw new Error("BCRP sin datos en la ventana consultada");

  const promedio = ultimos.reduce((a, b) => a + b.valor, 0) / ultimos.length;
  return {
    promedio: Math.round(promedio * 10_000) / 10_000,
    fuente: "SBS · prom. 7d",
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
