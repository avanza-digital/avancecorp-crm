import assert from 'node:assert/strict';
import{readFileSync,statSync,writeFileSync}from'node:fs';
import{relative}from'node:path';
import{createHash}from'node:crypto';
import{execFileSync}from'node:child_process';
import{carpeta,objeto}from'./banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const repo=execFileSync('git',['rev-parse','--show-toplevel'],{encoding:'utf8'}).trim();
assert.ok(relative(repo,carpeta).startsWith('..'),'Capturas dentro del repositorio');
const commitProbado='bd59d35d878ed97df71bb45f83db117c71425222';
const artefactos={
 '20261014001044_crm_f7_redeclarar_huella_metricas_cartera.sql':'91ff35883e76c48cc9c367d9a10d86acf9e00e47d14746397d3511d420cd4acf',
 '20261014001346_crm_sla_agrupar_tareas_por_lead.sql':'4b20ab86f61d999d7905ac58274480a67591139a0185ead044db47e2577a720c'};
for(const[nombre,sha]of Object.entries(artefactos))assert.equal(createHash('sha256').update(readFileSync(new URL('../../../migrations/'+nombre,import.meta.url))).digest('hex'),sha);
// La aplicación de Supabase toma el ledger, no git. Esta comprobación adicional
// evita atribuir los gates a un SQL o transporte distintos del commit probado;
// posteriores commits de documentación no invalidan pruebas de código idéntico.
execFileSync('git',['diff','--exit-code',commitProbado,'--',
 ...Object.keys(artefactos).map(x=>'CRM-Avance-Corp/supabase/migrations/'+x),
 'CRM-Avance-Corp/app/src/lib/supabase.ts','CRM-Avance-Corp/app/src/lib/transporte-crm.ts',
 'CRM-Avance-Corp/app/src/lib/transporte-crm.test.ts','CRM-Avance-Corp/app/src/lib/supabase-transporte.test.ts'],{cwd:repo});
const json=f=>JSON.parse(readFileSync(`${carpeta}/${f}`));
// La matriz completa usa el código identificado por su hash al iniciar y al
// terminar. El merge posterior de main añade un alcance CLI independiente;
// no sustituye el cuerpo de la matriz efectivamente ejecutada.
const gateFuente='0daf3d80:CRM-Avance-Corp/supabase/scripts/test-rls.mjs';
assert.equal(json('gate-http-estado.json').gateSha256,
 createHash('sha256').update(execFileSync('git',['show',gateFuente],{cwd:repo,maxBuffer:4*1024*1024})).digest('hex'));
assert.deepEqual(json('gate-http-estado.json').migraciones,artefactos);
const advisors=json('advisors-delta.json');
assert.ok(advisors.security.every(x=>x.nuevas.length===0),'Avisos de seguridad nuevos');
assert.ok(advisors.performance.filter(x=>x.level!=='INFO').every(x=>x.nuevas.length===0),'WARN/ERROR de rendimiento nuevos');
for(const f of ['gate-http-estado.json','sql-resultados.json']){
 assert.equal(json(f).estado,'PASS',f);
 assert.ok(statSync(`${carpeta}/${f}`).mtimeMs>Date.parse('2026-10-14T01:38:30Z'),f+' anterior a las migraciones');
 assert.ok(Date.now()-statSync(`${carpeta}/${f}`).mtimeMs<7200000,f+' vencido');
}
for(const f of ['produccion-catalogo-premerge.json','produccion-extra-premerge.json','edge-premerge.json'])
 assert.ok(Date.now()-statSync(`${carpeta}/${f}`).mtimeMs<60000,'Captura vencida: '+f);
const base=json('produccion-catalogo.json').rows[0].estructura;
const padre=json('produccion-catalogo-premerge.json').rows[0].estructura;
assert.deepEqual(padre,base,'Producción avanzó: integrar y revalidar antes del merge');
const banco=objeto(readFileSync(new URL('./catalogo.sql',import.meta.url),'utf8'));
const firma='private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)';
assert.equal(padre.funciones.find(f=>f.firma===firma).md5,'12749d608bb0a296f763e000f18c03de');
assert.equal(banco.funciones.find(f=>f.firma===firma).md5,'0abdf640b5f4f10ab2e85b6bd2494522');
banco.funciones.find(f=>f.firma===firma).md5='12749d608bb0a296f763e000f18c03de';
for(const c of [padre,banco])for(const f of c.funciones)if(f.acl)f.acl=f.acl.slice(1,-1).split(',').sort();
const normalizaciones=json('paridad-esquema.json').normalizaciones;
assert.deepEqual(normalizaciones.map(x=>[x.tabla,x.restriccion]),[
 ['crm.alertas_reconocimientos','alertas_reconocimientos_miembros_check'],
 ['crm.empresas','empresas_monedas_check'],['crm.producto_condiciones','producto_condiciones_capital_check']]);
for(const n of normalizaciones){const t=banco.tablas.find(t=>t.nombre===n.tabla),r=t.restricciones.find(r=>r[0]===n.restriccion);
 assert.equal(r[1],n.despues);r[1]=n.antes;}
assert.deepEqual(banco,padre,'Deriva del banco distinta de la función SLA');
const p=json('produccion-extra-premerge.json').rows[0].extra;
const b=objeto(readFileSync(new URL('./catalogo-extra.sql',import.meta.url),'utf8'));
assert.deepEqual(p.ledger,{cantidad:473,huella:'8dc43ff2a86e303e86863ba7773b894e'});
assert.deepEqual(b.ledger,p.ledger);assert.equal(p.nuevas,null);
assert.deepEqual(b.nuevas,[
 {version:'20261014013757',nombre:'crm_f7_redeclarar_huella_metricas_cartera',huella:'c93852029dc24884b742bd5098094199'},
 {version:'20261014013830',nombre:'crm_sla_agrupar_tareas_por_lead',huella:'1766dbb19450e2f794eefe2708bec57d'}]);
for(const k of ['esquemas','acl_columnas','default_acl','publicaciones'])assert.deepEqual(b[k],p[k],k);
assert.deepEqual(p.extensiones.find(x=>x[0]==='pg_net'),['pg_net','public','0.20.0']);
assert.deepEqual(b.extensiones.find(x=>x[0]==='pg_net'),['pg_net','extensions','0.20.4']);
assert.deepEqual(b.extensiones.filter(x=>x[0]!=='pg_net'),p.extensiones.filter(x=>x[0]!=='pg_net'));
// pg_net es infraestructura preexistente distinta entre servicios; las dos
// migraciones no la nombran ni el merge transporta su catálogo.
const f7base=json('produccion-controles.json').rows[0].controles['private.f7_piezas_en_observacion'];
const ordenarF7=filas=>[...filas].sort((a,b)=>a.firma.localeCompare(b.firma));
assert.deepEqual(ordenarF7(p.f7),ordenarF7(f7base),'Las declaraciones F7 productivas cambiaron');
const f7=objeto('select jsonb_agg(to_jsonb(t) order by firma) from private.f7_piezas_en_observacion t');
for(const f of f7){const original=f7base.find(x=>x.firma===f.firma);assert.ok(original);
 if(f.firma==='crm.metricas_cartera_fn(date)'){
  assert.equal(f.huella_md5,'869853c25e903fe2f79245b8176c09b9');assert.notEqual(f.nota,original.nota);
  f.huella_md5=original.huella_md5;f.nota=original.nota;
 }assert.deepEqual(f,original);
}assert.equal(f7.length,f7base.length);
const edges=json('edge-premerge.json'),declaradas=json('edge-paridad.json').funciones;
assert.equal(edges.padre.length,declaradas.length);assert.equal(edges.banco.length,declaradas.length);
for(const d of declaradas)for(const [lado,sha]of[['padre','shaProduccion'],['banco','shaBanco']]){
 const e=edges[lado].find(e=>e.slug===d.nombre);assert.ok(e);
 assert.equal(e.ezbr_sha256,d[sha],`${lado} cambió ${d.nombre}`);assert.equal(e.verify_jwt,d.verify_jwt);
 assert.ok(e.entrypoint_path.endsWith('/'+d.entrada));
 if(d.mapa)assert.ok(e.import_map_path.endsWith('/'+d.mapa));else assert.ok(!e.import_map_path);
}
for(const f of ['produccion-catalogo-premerge.json','produccion-extra-premerge.json','edge-premerge.json'])
 assert.ok(Date.now()-statSync(`${carpeta}/${f}`).mtimeMs<60000,'La verificación excedió la ventana: '+f);
const resultado={estado:'PASS',fecha:new Date().toISOString(),commitProbado,gateFuente,artefactos,
 gates:Object.fromEntries(['gate-http-estado.json','sql-resultados.json'].map(f=>[f,createHash('sha256').update(readFileSync(`${carpeta}/${f}`)).digest('hex')])),
 base:473,migracionesExtra:b.nuevas,tablas:149,funciones:1085,edges:23,
 excepcionInfraestructura:'pg_net: padre public 0.20.0, banco extensions 0.20.4; no modificado ni incluido en las migraciones'};
writeFileSync(`${carpeta}/premerge.json`,JSON.stringify(resultado,null,2),{mode:0o600});console.log(JSON.stringify(resultado));
