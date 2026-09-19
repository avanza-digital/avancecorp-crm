// Introspección local oficial. Sólo integra el contrato tocado por esta tarea.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {openSync,closeSync,readFileSync,writeFileSync} from 'node:fs';
import {db,contenedor} from './banco.mjs';
const archivo='/private/tmp/avancecorp-conversion-inversion/tipos-generados.ts';
const fd=openSync(archivo,'w',0o600);
try{
  const r=spawnSync('docker',['run','--rm','--network','avancecorp-f5-bank-red',
    '-e',`PG_META_DB_HOST=${contenedor}`,'-e',`PG_META_DB_NAME=${db}`,'-e','PG_META_GENERATE_TYPES=typescript',
    '-e','PG_META_GENERATE_TYPES_INCLUDED_SCHEMAS=public,crm',
    '-e','PG_META_GENERATE_TYPES_DETECT_ONE_TO_ONE_RELATIONSHIPS=true',
    'public.ecr.aws/supabase/postgres-meta:v0.99.0'],{stdio:['ignore',fd,'pipe'],encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
}finally{closeSync(fd);}
function nodo(texto,nombre,opcional=false){
  const inicio=texto.indexOf(`      ${nombre}: {\n`,texto.indexOf('  crm: {\n'));
  if(inicio<0&&opcional)return null;
  assert(inicio>=0,nombre);
  const fin=texto.indexOf('\n      }',inicio)+'\n      }'.length;
  assert(fin>inicio,nombre);return {inicio,fin,texto:texto.slice(inicio,fin)};
}
const ruta=new URL('../../../app/src/lib/database.types.ts',import.meta.url);
const generado=readFileSync(archivo,'utf8');let actual=readFileSync(ruta,'utf8');
for(const nombre of ['inversion_solicitudes','preparar_persona_lead_inversion_fn','contexto_conversion_inversion_fn','bienvenida_inversion_estado_fn','bienvenida_inversion_entrega_fn','cancelar_solicitud_inversion_fn']){
  const nuevo=nodo(generado,nombre),previo=nodo(actual,nombre,true);
  if(previo)actual=actual.slice(0,previo.inicio)+nuevo.texto+actual.slice(previo.fin);
  else {
    const posicion=actual.indexOf('    Functions: {',actual.indexOf('  crm: {\n'))+'    Functions: {'.length;
    actual=actual.slice(0,posicion)+'\n'+nuevo.texto+actual.slice(posicion);
  }
}
writeFileSync(ruta,actual);
console.log('Seis contratos TypeScript regenerados desde la copia local mediante postgres-meta; otros tipos conservados.');
