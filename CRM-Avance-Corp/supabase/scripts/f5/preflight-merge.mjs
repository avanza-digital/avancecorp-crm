import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const proyecto='dctqcbznekcyxhjujuci';
const categorias=['1. columnas','2. funciones','3. disparadores','4. politicas RLS',
 '5. RLS por tabla','6. indices','7. restricciones','8. registro','9. vistas'];
function validarCaptura(c) {
 assert.equal(c.version,1);assert.equal(c.proyecto,proyecto,'Destino distinto de PortalAvanceCorp');
 assert.ok(Number.isFinite(Date.parse(c.capturadoEn)),'Falta la fecha de captura');
 assert.deepEqual(c.esquema.map(x=>x.categoria).sort(),categorias);
 for(const x of c.esquema) {
  assert.ok(Number.isInteger(x.n)&&x.n>=0);assert.match(x.huella,/^[a-f0-9]{32}$/);
 }
 assert.deepEqual(c.acl.map(x=>x.categoria).sort(),['arrays_historial','columnas','esquemas','tablas']);
 for(const x of c.acl) {
  assert.ok(Number.isInteger(x.n)&&x.n>=0);assert.match(x.huella,/^[a-f0-9]{32}$/);
 }
 assert.ok(c.edges.length>0);assert.equal(new Set(c.edges.map(x=>x.nombre)).size,c.edges.length);
 for(const e of c.edges) {
  assert.match(e.nombre,/^[a-z0-9-]+$/);assert.equal(typeof e.verify_jwt,'boolean');
  assert.equal(typeof e.import_map,'boolean');assert.match(e.sha256,/^[a-f0-9]{64}$/);
 }
}
const ordenados=(lista,campo)=>[...lista].sort((a,b)=>a[campo].localeCompare(b[campo]));
export function comprobarPremerge(manifiesto,actual,ahora=Date.now()) {
 const base=manifiesto.baseProductiva;
 validarCaptura(base);validarCaptura(actual);
 assert.match(manifiesto.commit,/^[a-f0-9]{40}$/);
 assert.equal(actual.commitRemoto,manifiesto.commit,'Main remoto avanzó después de construir');
 const edad=ahora-Date.parse(actual.capturadoEn);
 assert.ok(edad>=0&&edad<=60000,'La captura debe recogerse y comprobarse dentro de 60 segundos');
 assert.deepEqual(ordenados(actual.esquema,'categoria'),ordenados(base.esquema,'categoria'),
  'Producción cambió de esquema o historial: volver a integrar y ensayar el banco');
 assert.deepEqual(ordenados(actual.acl,'categoria'),ordenados(base.acl,'categoria'),
  'Producción cambió de permisos o texto exacto de migraciones');
 assert.deepEqual(ordenados(actual.edges,'nombre'),ordenados(base.edges,'nombre'),
  'Producción cambió una Edge: no sobrescribir esa publicación');
 assert.deepEqual(actual.banderas,{resolver_en_puertas:true,ficha_360_neutral:false,inversiones_escritura:false},
  'No se cumplen las banderas aprobadas para instalar F5 apagada');
 return {estado:'PASS',proyecto,commit:manifiesto.commit,
  migraciones:actual.esquema.find(x=>x.categoria==='8. registro').n,
  edges:actual.edges.length,capturadoEn:actual.capturadoEn,verificadoEn:new Date(ahora).toISOString()};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 assert.equal(process.argv.length,4,'Uso: node preflight-merge.mjs manifiesto.json captura-actual.json');
 console.log(JSON.stringify(comprobarPremerge(
  JSON.parse(readFileSync(process.argv[2],'utf8')),JSON.parse(readFileSync(process.argv[3],'utf8')))));
}
