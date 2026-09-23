// Adaptador del arnés existente; el nombre histórico del helper se conserva
// para ejecutar exactamente las mismas aserciones HTTP, con URL remota fija.
export {carpeta,apiUrl,sql} from './banco.mjs';
import {cfg} from './banco.mjs';
export const credencialesLocales=()=>({ANON_KEY:cfg.SUPABASE_ANON_KEY,SERVICE_ROLE_KEY:cfg.SUPABASE_SERVICE_ROLE_KEY});
