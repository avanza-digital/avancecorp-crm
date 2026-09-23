import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {carpeta} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const credenciales=readFileSync('/private/tmp/gestion-diaria-f4-http.WQNCJc/credenciales-fixtures.json');
writeFileSync(`${carpeta}/credenciales-fixtures.json`,credenciales,{mode:0o600});
let fuente=readFileSync(new URL('../contrato-http.mjs',import.meta.url),'utf8');
for(const [anterior,nueva] of [
 ['../gestion-diaria-cortes/http/banco.mjs',new URL('./banco-compat.mjs',import.meta.url).href],
 ['../fixtures.mjs',new URL('../../fixtures.mjs',import.meta.url).href]]){
 assert.equal(fuente.split(anterior).length,2,'Import inesperado');
 fuente=fuente.replace(anterior,nueva);
}
process.argv=[process.argv[0],process.argv[1],'--solo-banco-autorizado'];
await import('data:text/javascript;base64,'+Buffer.from(fuente).toString('base64'));
