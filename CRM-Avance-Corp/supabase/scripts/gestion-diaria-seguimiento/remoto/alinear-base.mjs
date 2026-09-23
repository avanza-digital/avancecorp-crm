// Alinea exclusivamente el banco sintético con definiciones ya productivas.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {isDeepStrictEqual} from 'node:util';
import {carpeta,sql,objeto,ref} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.ok(existsSync(`${carpeta}/base-reconstruida.json`));
assert.equal(existsSync(`${carpeta}/base-alineada.json`),false);
const respaldo=JSON.parse(readFileSync('/private/tmp/gd-f4-catalogo-productivo-20260922.json','utf8')).rows[0].catalogo;
const consulta=readFileSync('/private/tmp/gd-f4-exportar-catalogo-20260922.sql','utf8');
const citar=x=>"'"+String(x).replaceAll("'","''")+"'";
const vigente=sql("select exists(select 1 from pg_attribute where attrelid='private.analitica_leads_citas_exenciones'::regclass and attname='clase' and not attisdropped)")==='t';
// Si el DDL confirmó y el cotejo posterior encontró ACL heredadas, reanudar
// solo ese cotejo/corrección; nunca volver a instalar el vigilante.
const vigilante=readFileSync(new URL('../../../migrations/20260922153708_crm_vigilante_techo_por_clase.sql',import.meta.url),'utf8');
assert.equal((vigilante.match(/^begin;$/gm)??[]).length,1);
assert.equal((vigilante.match(/^commit;$/gm)??[]).length,1);
const esperadas=['vigia_alertas_sin_cierre','vigia_analista_vigencia','vigia_analitica_leads_citas','vigia_f7_piezas','vigia_fases_cerrables'];
assert.deepEqual(respaldo.vigias.map(v=>v.firma),esperadas.map(n=>`private.${n}()`));
// La función SQL de alertas referencia fases_cerrables al compilarse.
const orden=['vigia_analista_vigencia','vigia_analitica_leads_citas','vigia_f7_piezas','vigia_fases_cerrables','vigia_alertas_sin_cierre'];
const funciones=orden.map(n=>respaldo.vigias.find(v=>v.firma===`private.${n}()`)).map(v=>{
 assert.equal(v.owner,'postgres');
 assert.ok(v.definicion.startsWith(`CREATE OR REPLACE FUNCTION ${v.firma}`));
 return v.definicion+`;\nrevoke all on function ${v.firma} from public, anon, authenticated, service_role;`;
}).join('\n');
const e=respaldo.declaracion_vigencia;
assert.equal(e.objeto,'public.proteger_campos_inmutables()');
const controles=JSON.parse(readFileSync(`${carpeta}/controles-tecnicos-productivos.json`,'utf8'));
const datos=['analista_vigencia_exenciones','analista_vigencia_tope','f7_piezas_en_observacion'].map(t=>{
 assert.ok(controles[t].length>0);
 return `do $vacía$ begin if exists(select 1 from private.${t}) then raise exception 'Control ya cargado: ${t}'; end if; end $vacía$;
 insert into private.${t} select * from jsonb_populate_recordset(null::private.${t},${citar(JSON.stringify(controles[t]))}::jsonb);`;
}).join('\n');
// No reproducir cierres de alertas reales ni preflights que dependen de ellas.
// Solo la declaración técnica, con la huella viva verificada por el gate.
if(!vigente)sql(`begin;\n${vigilante.replace(/^begin;$/m,'').replace(/^commit;$/m,'')}\n${funciones}\n${datos}\n
select private.assert_analista_vigencia(); select private.assert_analitica_leads_citas(); select private.assert_gestion_diaria();
commit;`);
let actual=objeto(consulta);
let m=new Map(actual.funciones.map(f=>[f.firma,f]));
assert.equal(m.size,respaldo.funciones.length);
const retirar=[];
for(const f of respaldo.funciones){
 const b=m.get(f.firma);assert.ok(b);
 assert.ok(isDeepStrictEqual({...b,acl:null},{...f,acl:null}),`Cuerpo o configuración distintos: ${f.firma}`);
 if(isDeepStrictEqual(b.acl,f.acl))continue;
 assert.ok(f.firma.startsWith('public.'));assert.equal(f.owner,'postgres');
 assert.ok(f.acl.every(a=>b.acl.some(v=>isDeepStrictEqual(a,v))),'Falta privilegio esperado');
 for(const a of b.acl.filter(a=>!f.acl.some(v=>isDeepStrictEqual(a,v)))){
  assert.ok(['anon','authenticated','service_role'].includes(a[0]));
  assert.equal(a[1],'EXECUTE');assert.equal(a[2],false);
  retirar.push(`revoke execute on function ${f.firma} from ${a[0]};`);
 }
}
if(retirar.length){
 sql(`begin; do $acl$ begin execute $cambios$${retirar.join('\n')}$cambios$; end $acl$; commit;`);
 actual=objeto(consulta);m=new Map(actual.funciones.map(f=>[f.firma,f]));
}
for(const f of respaldo.funciones)assert.ok(isDeepStrictEqual(m.get(f.firma),f),`Diferencia: ${f.firma}`);
writeFileSync(`${carpeta}/catalogo-base-alineada.json`,JSON.stringify(actual),{mode:0o600});
writeFileSync(`${carpeta}/base-alineada.json`,JSON.stringify({estado:'PASS',ref,fecha:new Date().toISOString(),
 funciones:actual.funciones.length,comparados:['cuerpo','owner','definer','config','acl'],
 limites:'Sin datos ni alertas productivas. Falta cotejo de tablas, RLS, roles y ledger.'},null,2)+'\n',{mode:0o600});
console.log(`PASS: ${actual.funciones.length} funciones coinciden con producción; vigilantes y Gestión Diaria verdes`);
