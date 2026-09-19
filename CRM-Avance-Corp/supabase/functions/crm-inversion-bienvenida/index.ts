import {crearHandlerBienvenida} from './handler.mjs';
const supabaseUrl=Deno.env.get('SUPABASE_URL');
const anonKey=Deno.env.get('SUPABASE_ANON_KEY');
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if(!supabaseUrl||!anonKey||!serviceKey)throw new Error('Falta la configuración del servicio.');
Deno.serve(crearHandlerBienvenida({supabaseUrl,anonKey,serviceKey,resendKey:Deno.env.get('RESEND_API_KEY')}));
