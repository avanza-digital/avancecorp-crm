import { crearHandlerDocumentoInversion } from './handler.mjs';
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if (!supabaseUrl || !anonKey || !serviceKey) throw new Error('Falta la configuración documental.');
Deno.serve(crearHandlerDocumentoInversion({supabaseUrl, anonKey, serviceKey}));
