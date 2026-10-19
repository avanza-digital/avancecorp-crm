// Ejecuta la misma matriz que se usa en la rama Supabase autorizada.
// Este punto de entrada conserva el banco Docker local y su limpieza.
import { bancoHttp } from './http-banco.mjs';
import { probarRecorridoHttp } from './http-matriz.mjs';

await bancoHttp(probarRecorridoHttp);
