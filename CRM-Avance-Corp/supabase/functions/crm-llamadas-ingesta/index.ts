import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
import { crearHandler } from './handler.ts';

// La clave de servicio vive en los secretos de Supabase y no sale de esta función: solo la usan las
// dos RPC de servicio (F3-a 20261001212258, con el contrato de 20261005143843), que validan la clave del
// celular y el contenido en la base y devuelven {resultado, mensaje}.
const fetchAcotado: typeof fetch = (entrada, opciones) => fetch(entrada, {
  ...opciones, signal: AbortSignal.timeout(8000),
});
const servicio = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
  global: { fetch: fetchAcotado },
  auth: { persistSession: false, autoRefreshToken: false },
});
async function rpc(nombre: string, argumentos: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await servicio.schema('crm').rpc(nombre, argumentos);
  if (error) throw error;
  return data;
}

Deno.serve(crearHandler({
  urlCrm: 'https://crm.miavance.com',
  ingerir: (credencial, evento) => rpc('ingerir_llamada_celular_servicio', { p_credencial: credencial, p_evento: evento }),
  registrarSalud: (credencial, latido) => rpc('registrar_salud_celular_servicio', { p_credencial: credencial, p_latido: latido }),
}));
