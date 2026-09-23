// Refresca SOLO la base sintética, ANTES del candidato, con los catorce avances
// ya presentes en producción al reanudar el 23/09.
// Copia definiciones finales y declaraciones técnicas, nunca personas ni negocios.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {isDeepStrictEqual as igual} from 'node:util';
import {carpeta,sql,objeto} from './banco.mjs';
const verificar=process.argv[3]==='--verificar';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada',...(verificar?['--verificar']:[])]);
assert.equal(existsSync(`${carpeta}/avances-sincronizados.json`),false);
const leer=n=>JSON.parse(readFileSync('/private/tmp/'+n,'utf8'));
const original=leer('gd-f4-catalogo-productivo-20260922.json').rows[0].catalogo;
// Catálogo y ledger se exportan en la misma consulta/snapshot.
const padre=leer('gd-f4-avances-atomico-20260923.json').rows[0].catalogo;
const avances=padre.avances;
const consulta=readFileSync('/private/tmp/gd-f4-exportar-definiciones-refresco-20260922.sql','utf8');
const respaldo=verificar?JSON.parse(readFileSync(`${carpeta}/refresco-respaldo.json`,'utf8')):null;
const antes=verificar?respaldo.catalogo:objeto(consulta);
const mapa=c=>new Map(c.funciones.map(f=>[f.firma,f]));
const inicial=mapa(original),remoto=mapa(padre),banco=mapa(antes);
const campos=['cuerpo','owner','definer','config','acl'];
const mismo=(a,b)=>campos.every(k=>igual(a[k],b[k]));
const cambiadas=original.funciones.filter(f=>!mismo(f,remoto.get(f.firma))).map(f=>f.firma);
assert.equal(cambiadas.length,10);assert.equal(remoto.size,inicial.size);
const f4=original.funciones.filter(f=>!mismo(f,banco.get(f.firma))).map(f=>f.firma);
assert.deepEqual(f4,[],'Sin cambios F4 antes de refrescar la base');
assert.equal(sql("select to_regclass('crm.gestion_diaria_entregas') is null"),'t');
for(const firma of cambiadas){
 assert.ok(!f4.includes(firma));assert.ok(mismo(inicial.get(firma),banco.get(firma)));
 for(const k of campos.filter(k=>k!=='cuerpo'))assert.ok(igual(inicial.get(firma)[k],remoto.get(firma)[k]));
}
const comentarios=padre.funciones.filter(f=>!f4.includes(f.firma)&&f.comentario!==banco.get(f.firma).comentario);
const citar=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
assert.deepEqual(antes.exenciones.map(e=>e.objeto),padre.exenciones.map(e=>e.objeto));
const exenciones=padre.exenciones.filter(e=>!igual(e,antes.exenciones.find(a=>a.objeto===e.objeto)));
assert.equal(exenciones.length,3);
for(const e of exenciones)assert.equal(e.clase,antes.exenciones.find(a=>a.objeto===e.objeto).clase);
assert.equal(padre.tope.tope,antes.tope.tope);
assert.equal(avances.length,14);assert.equal(antes.migraciones,327);assert.equal(padre.migraciones,341);
const consultaLedger='select jsonb_agg(to_jsonb(m) order by version) from supabase_migrations.schema_migrations m';
const ledgerAntes=verificar?respaldo.ledger:objeto(consultaLedger);
for(const a of avances)assert.ok(!ledgerAntes.some(b=>b.version===a.version));
if(!verificar)writeFileSync(`${carpeta}/refresco-respaldo.json`,JSON.stringify({catalogo:antes,ledger:ledgerAntes}),{mode:0o600});
const preflight=cambiadas.concat(f4).map(f=>`if (select md5(prosrc) from pg_proc where oid=${citar(f)}::regprocedure)<>${citar(banco.get(f).cuerpo)} then raise exception 'El banco cambió'; end if;`).join('\n');
if(!verificar)sql(`begin; set local lock_timeout='5s';
 lock table supabase_migrations.schema_migrations, private.analitica_leads_citas_exenciones,private.analitica_lc_sello in share row exclusive mode;
 do $preflight$ begin ${preflight} end $preflight$;
 ${cambiadas.map(f=>remoto.get(f).definicion+';').join('\n')}
 ${comentarios.map(f=>`comment on function ${f.firma} is ${citar(f.comentario)};`).join('\n')}
 ${exenciones.map(e=>`update private.analitica_leads_citas_exenciones set huella=${citar(e.huella)},razon=${citar(e.razon)} where objeto=${citar(e.objeto)};`).join('\n')}
 update private.analitica_lc_sello set sello=${citar(padre.sello.sello)},sellado_en=${citar(padre.sello.sellado_en)}::timestamptz where id;
 select private.assert_analitica_leads_citas(); select private.assert_analista_vigencia(); select private.assert_gestion_diaria();
 insert into supabase_migrations.schema_migrations(version,name,statements)
 select version,name,statements from jsonb_populate_recordset(null::supabase_migrations.schema_migrations,${citar(JSON.stringify(avances))}::jsonb);
 commit;`);
const despues=objeto(consulta),final=mapa(despues),ledgerDespues=objeto(consultaLedger);
assert.equal(despues.migraciones,341);assert.equal(final.size,banco.size);
for(const [firma,b] of banco){
 const esperado=cambiadas.includes(firma)?remoto.get(firma):b;
 assert.ok(mismo(final.get(firma),esperado),firma);
 if(!f4.includes(firma)&&remoto.has(firma))assert.equal(final.get(firma).comentario,remoto.get(firma).comentario,firma);
}
assert.deepEqual(despues.exenciones,padre.exenciones);
assert.deepEqual(despues.sello,padre.sello);
for(const a of ledgerAntes)assert.deepEqual(ledgerDespues.find(b=>a.version===b.version),a);
for(const a of avances){const b=ledgerDespues.find(b=>b.version===a.version);for(const k of ['version','name','statements'])assert.deepEqual(a[k],b[k]);}
// El ledger recién creado por Supabase tiene tres columnas; el padre tiene
// además metadatos administrativos. No alterar la tabla del servicio para
// simularlos. El merge conservará las filas previas del padre; cotejar también
// esos metadatos productivos antes/después de publicar, sin copiarlos al banco.
for(const r of padre.ledger)assert.deepEqual(Object.keys(r).sort(),
 ['created_by','idempotency_key','name','rollback','statements','version']);
assert.deepEqual(ledgerDespues,padre.ledger.map(({version,name,statements})=>({version,name,statements})),
 'Versiones, nombres y cada sentencia idénticos al snapshot productivo');
writeFileSync(`${carpeta}/catalogo-despues-refresco.json`,JSON.stringify(despues),{mode:0o600});
writeFileSync(`${carpeta}/avances-sincronizados.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
 funciones:cambiadas,comentarios:comentarios.length,declaraciones:exenciones.length,ledger:341,
 conservado:'ACL/owners, datos sintéticos y 327 entradas previas. Catorce avances ya productivos; base previa al candidato F4.',
 ledger_metadatos:'created_by, idempotency_key y rollback no existen en el ledger nuevo de la rama. No se copian. Versiones, nombres y sentencias exactas; conservar y cotejar todos los metadatos del padre al publicar.'},null,2)+'\n',{mode:0o600});
console.log('PASS: diez funciones y catorce avances incorporados; 341 migraciones idénticas al padre; gates verdes');
