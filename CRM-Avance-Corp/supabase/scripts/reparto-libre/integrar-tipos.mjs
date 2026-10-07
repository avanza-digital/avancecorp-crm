// Integra únicamente la tabla y las RPC de reparto introspectadas en el banco.
// Conserva los contratos ajenos que la plantilla sintética aún no contiene.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
const generado=process.argv[2];assert(generado,'Uso: node integrar-tipos.mjs <salida de supabase gen types> [--verificar]');
function nodos(src){const out=new Map();
 for(const schema of ['crm','public']){
  const a=src.indexOf(`  ${schema}: {\n`);assert(a>=0);
  const fin=/^  }\n/m.exec(src.slice(a));assert(fin);const b=a+fin.index+fin[0].length,body=src.slice(a,b);
  for(const sec of ['Tables','Views','Functions','Enums','CompositeTypes']){
   const m=new RegExp(`^    ${sec}:[^\\n]*\\n`,'m').exec(body);if(!m)continue;
   const start=a+m.index+m[0].length,n=/^    [A-Z][a-zA-Z]+:/m.exec(src.slice(start,b));
   let texto=src.slice(start,n?start+n.index:b);const cierre=/^    }\n/m.exec(texto);if(cierre)texto=texto.slice(0,cierre.index);
   const miembros=[...texto.matchAll(/^      ([a-zA-Z_][a-zA-Z_0-9]*):/gm)];
   for(const [i,x] of miembros.entries()){const e=miembros[i+1]?.index??texto.length;
    out.set(`${schema}.${sec}.${x[1]}`,{s:start+x.index,e:start+e,texto:texto.slice(x.index,e)});}
  }
 }return out;
}
const origen=readFileSync(generado,'utf8'),destino=new URL('../../../app/src/lib/database.types.ts',import.meta.url);
let actual=readFileSync(destino,'utf8');const nuevos=nodos(origen);
const claves=['crm.Tables.configuracion_reparto','crm.Functions.configuracion_reparto_fn','crm.Functions.guardar_configuracion_reparto_fn'];
for(const k of claves) assert(nuevos.has(k),k);
for(const clave of claves){
 const nodo=nuevos.get(clave),vigente=nodos(actual).get(clave);
 if(process.argv.includes('--verificar')) assert.equal(vigente?.texto,nodo.texto,`Regenerar ${clave}`);
 else if(vigente) actual=actual.slice(0,vigente.s)+nodo.texto+actual.slice(vigente.e);
 else {const sec=clave.split('.')[1],prefijo=`  crm: {\n    ${sec}: {\n`;
   const inicio=actual.indexOf('  crm: {\n');const ancla=actual.indexOf(`    ${sec}: {\n`,inicio)+`    ${sec}: {\n`.length;
   assert(ancla>inicio,prefijo);actual=actual.slice(0,ancla)+nodo.texto+actual.slice(ancla);}
}
if(!process.argv.includes('--verificar')) writeFileSync(destino,actual);
console.log(`Tipos de reparto: ${claves.length} nodos ${process.argv.includes('--verificar')?'verificados':'integrados'}; contratos ajenos conservados.`);
