// Sólo sintaxis y tests puros; nunca arranca servicios ni conecta al banco.
import { readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

for(const archivo of readdirSync(new URL('.',import.meta.url)).filter(n=>n.endsWith('.mjs'))) {
  const r=spawnSync(process.execPath,['--check',fileURLToPath(new URL(archivo,import.meta.url))],{stdio:'inherit'});
  if(r.status!==0) process.exit(r.status??1);
}
const r=spawnSync(process.execPath,['--test',fileURLToPath(new URL('./guardas.test.mjs',import.meta.url)),
  fileURLToPath(new URL('../../rls-conversion-vigente.test.mjs',import.meta.url))],{stdio:'inherit'});
process.exitCode=r.status??1;
