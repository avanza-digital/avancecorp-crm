import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
import {
  crearHandler, INSTRUCCIONES, leerJuicio, NIVELES, RespuestaHttp, type Juicio,
} from './handler.ts';

// Única frontera HTTP de la temperatura del lead. Lote de 10 con 15 s de tope
// por consulta: 150 s en el peor caso, holgado dentro de los 5 min de reserva
// que da `tomar_temperatura_lead_fn`. La despierta el cron de la
// base (`private.despertar_temperatura`) con una firma HMAC; no la llama nadie
// más. `verify_jwt=false` porque quien entra es el cron, no una sesión humana:
// la autorización es la firma, que se comprueba contra el Vault en la base.
const url = Deno.env.get('SUPABASE_URL') ?? '';
const fetchAcotado: typeof fetch = (entrada, opciones) => fetch(entrada, {
  ...opciones, signal: AbortSignal.timeout(15000),
});
const servicio = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
  global: { fetch: fetchAcotado },
  auth: { persistSession: false, autoRefreshToken: false },
});
const clave = Deno.env.get('TYPESAFE_API_KEY') ?? '';
const modelo = Deno.env.get('TYPESAFE_MODELO') || 'jev-latest';

async function dato<T>(consulta: PromiseLike<{ data: T; error: unknown }>): Promise<T> {
  const { data, error } = await consulta;
  if (error) throw error;
  return data;
}

async function preguntar(historial: string): Promise<Juicio> {
  const r = await fetchAcotado('https://api.typesafe.ai/v1/systemone', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${clave}`, 'Content-Type': 'application/json' },
    // El historial viaja en un campo CON NOMBRE: es dato del lead, no
    // instrucciones. Así una nota con texto raro no se lee como orden.
    body: JSON.stringify({
      state: { historial_de_gestion: historial },
      model: modelo,
      questions: {
        temperatura: { type: 'score', instructions: INSTRUCCIONES, criteria: NIVELES },
      },
    }),
  });
  if (!r.ok) throw new RespuestaHttp(r.status);
  return leerJuicio(await r.json());
}

async function huella(texto: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto));
  return Array.from(new Uint8Array(bytes)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(crearHandler({
  configurado: clave.length > 20,
  verificarCron: (firma, instante) => dato(servicio.schema('crm').rpc('verificar_cron_temperatura_fn', {
    p_firma: firma, p_instante: Number(instante),
  })),
  tomar: (limite) => dato(servicio.schema('crm').rpc('tomar_temperatura_lead_fn', { p_limite: limite })),
  confirmar: (leadId, reserva, juicio, hue, error) => dato(
    servicio.schema('crm').rpc('confirmar_temperatura_lead_fn', {
      p_lead_id: leadId,
      p_reserva: reserva,
      p_nivel: juicio?.nivel ?? null,
      p_probabilidades: juicio?.probabilidades ?? null,
      p_confianza: juicio?.confianza ?? null,
      p_modelo: juicio?.modelo ?? null,
      p_huella: hue,
      p_error: error,
    }),
  ),
  preguntar,
  huella,
}));
