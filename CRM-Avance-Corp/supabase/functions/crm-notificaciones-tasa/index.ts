import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
import { crearHandler } from './handler.ts';
import { crearTransporte } from './transporte.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const fetchAcotado: typeof fetch = (entrada, opciones) => fetch(entrada, {
  ...opciones, signal: AbortSignal.timeout(8000),
});
const servicio = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
  global: { fetch: fetchAcotado },
  auth: { persistSession: false, autoRefreshToken: false },
});
const clavePublica = Deno.env.get('VAPID_PUBLIC_KEY') ?? '';
const clavePrivada = Deno.env.get('VAPID_PRIVATE_KEY') ?? '';
const asunto = Deno.env.get('VAPID_SUBJECT') ?? '';
const configurado = /^[A-Za-z0-9_-]{87}$/.test(clavePublica)
  && /^[A-Za-z0-9_-]{43}$/.test(clavePrivada) && /^(mailto:|https:\/\/)/.test(asunto);
const usuario = (token: string) => createClient(url, anon, {
  global: { headers: { Authorization: `Bearer ${token}` }, fetch: fetchAcotado },
  auth: { persistSession: false, autoRefreshToken: false },
});
async function dato<T>(consulta: PromiseLike<{ data: T; error: unknown }>): Promise<T> {
  const { data, error } = await consulta;
  if (error) throw error;
  return data;
}

Deno.serve(crearHandler({
  clavePublica, configurado,
  permitirLocal: Deno.env.get('CRM_PUSH_PERMITIR_LOCAL') === 'true',
  verificarCron: (firma, instante) => dato(servicio.schema('crm').rpc('verificar_cron_push_tasa_fn', {
    p_firma: firma, p_instante: Number(instante),
  })),
  estadoUsuario: (token, endpoint) => dato(usuario(token).schema('crm').rpc('estado_push_tasa_fn', { p_endpoint: endpoint })),
  pruebaUsuario: (token, id) => dato(usuario(token).schema('crm').rpc('preparar_prueba_push_tasa_fn', { p_dispositivo_id: id })),
  tomar: () => dato(servicio.schema('crm').rpc('tomar_envios_push_tasa_fn', { p_limite: 10 })),
  materializar: (id, reserva) => dato(servicio.schema('crm').rpc('materializar_envio_push_tasa_fn', { p_envio_id: id, p_reserva: reserva })),
  confirmar: (id, reserva, resultado, codigo) => dato(servicio.schema('crm').rpc('confirmar_envio_push_tasa_fn', {
    p_envio_id: id, p_reserva: reserva, p_resultado: resultado, p_codigo_http: codigo,
  })),
  enviar: crearTransporte({ subject: asunto, publicKey: clavePublica, privateKey: clavePrivada }),
}));
