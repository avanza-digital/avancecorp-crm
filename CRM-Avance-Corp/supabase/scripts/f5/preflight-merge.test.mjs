import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {comprobarPremerge} from './preflight-merge.mjs';
const base=JSON.parse(readFileSync(new URL('base-productiva-2026-09-09.json',import.meta.url),'utf8'));
const commit='a'.repeat(40),ahora=Date.parse('2026-09-09T17:40:00Z');
function caso() {
 const actual={...structuredClone(base),capturadoEn:new Date(ahora).toISOString(),commitRemoto:commit,
  banderas:{resolver_en_puertas:true,ficha_360_neutral:false,inversiones_escritura:false}};
 return {manifiesto:{commit,baseProductiva:structuredClone(base)},actual};
}
test('premerge: mismo historial, esquema, permisos y archivos pasa',()=>{
 const {manifiesto,actual}=caso();assert.equal(comprobarPremerge(manifiesto,actual,ahora).estado,'PASS');
});
test('premerge: cambio de historial o función aunque conserve el recuento bloquea',()=>{
 for(const categoria of ['8. registro','2. funciones']) {
  const {manifiesto,actual}=caso();actual.esquema.find(x=>x.categoria===categoria).huella='f'.repeat(32);
  assert.throws(()=>comprobarPremerge(manifiesto,actual,ahora),/Producción cambió/);
 }
});
test('premerge: otro permiso, código Edge, JWT o entrada bloquea',()=>{
 for(const cambiar of [x=>x.acl[0].huella='e'.repeat(32),x=>x.edges[0].sha256='e'.repeat(64),
  x=>x.edges[0].verify_jwt=!x.edges[0].verify_jwt,x=>x.edges[0].entrada='otro/index.ts']) {
  const {manifiesto,actual}=caso();cambiar(actual);
  assert.throws(()=>comprobarPremerge(manifiesto,actual,ahora),/Producción cambió/);
 }
});
test('premerge: captura vieja, destino, commit o banderas distintos bloquean',()=>{
 for(const cambiar of [x=>x.capturadoEn=new Date(ahora-60001).toISOString(),x=>x.proyecto='otro',
  x=>x.commitRemoto='b'.repeat(40),x=>x.banderas.ficha_360_neutral=true]) {
  const {manifiesto,actual}=caso();cambiar(actual);
  assert.throws(()=>comprobarPremerge(manifiesto,actual,ahora));
 }
});
test('premerge: captura incompleta no se acepta por igualdad vacía',()=>{
 const {manifiesto,actual}=caso();manifiesto.baseProductiva.esquema=[];actual.esquema=[];
 assert.throws(()=>comprobarPremerge(manifiesto,actual,ahora));
});
