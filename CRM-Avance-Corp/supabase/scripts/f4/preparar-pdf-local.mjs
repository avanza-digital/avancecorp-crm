import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { banco, http } from './banco-local.mjs';

assert.match(readFileSync(join(banco, 'supabase/config.toml'), 'utf8'),
  new RegExp(`project_id\\s*=\\s*"${entorno}"`));
const destino = join(banco, 'supabase/functions/crm-contrato-pdf-v2');
mkdirSync(destino, { recursive: true });
for (const archivo of ['index.ts', 'handler.ts', 'storage.ts', 'renderer.ts', 'template-v2.ts',
  'assets-v2.ts', 'pdfmake-0.2.20-pdfprinter.js', 'vfs-fonts-0.2.20.js', 'deno.json']) {
  const origen = new URL(`../../functions/crm-contrato-pdf-v2/${archivo}`, import.meta.url);
  const final = join(destino, archivo);
  let igual = false;
  try { igual = readFileSync(origen).equals(readFileSync(final)); } catch { /* Primera copia. */ }
  if (!igual) copyFileSync(origen, final);
}
const estado = await http('/storage/v1/bucket/contratos-generados', { method: 'GET', admin: true });
if (!estado.ok) {
  assert.equal(Number(estado.data.statusCode), 404, 'Error inesperado al consultar el bucket local');
  const nuevo = await http('/storage/v1/bucket', { admin: true, body: {
    id: 'contratos-generados', name: 'contratos-generados', public: false,
    file_size_limit: 10 * 1024 * 1024, allowed_mime_types: ['application/pdf'],
  } });
  assert.equal(nuevo.ok, true, 'No se pudo crear el bucket privado del banco');
}
const verificado = await http('/storage/v1/bucket/contratos-generados', { method: 'GET', admin: true });
assert.equal(verificado.ok, true);
assert.equal(verificado.data.public, false);
assert.equal(verificado.data.file_size_limit, 10 * 1024 * 1024);
assert.deepEqual(verificado.data.allowed_mime_types, ['application/pdf']);
console.log('PDF local: nueve archivos del generador y bucket privado verificados. Sin entornos ni secretos productivos.');
