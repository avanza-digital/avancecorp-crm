import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, copyFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const destino = '/private/tmp/avancecorp-f4-bank/supabase/functions';
const config = readFileSync('/private/tmp/avancecorp-f4-bank/supabase/config.toml', 'utf8');
assert.match(config, /project_id\s*=\s*"avancecorp-f4-bank"/);
const archivos = ['crm-inversion-portal/index.ts', 'crm-inversion-portal/handler.mjs',
  '_shared/documento.ts', '_shared/domicilio.mjs', '_shared/saga-auth.mjs'];
for (const archivo of archivos) {
  const origen = fileURLToPath(new URL(`../../../../_supabase_functions/functions/${archivo}`, import.meta.url));
  mkdirSync(dirname(`${destino}/${archivo}`), { recursive: true });
  copyFileSync(origen, `${destino}/${archivo}`);
}
console.log('Función Portal y sus tres módulos compartidos copiados al banco local. No se copiaron entornos ni secretos.');
