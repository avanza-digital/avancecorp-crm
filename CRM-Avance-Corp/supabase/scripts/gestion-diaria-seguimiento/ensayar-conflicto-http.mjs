// Ensayo del quinto SQL exclusivamente en Docker de Gestión Diaria.
// Conserva el PostgREST 16 existente y abre un sidecar 14.5 sin salida exterior.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,chmodSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {carpeta as base,sql,docker,contenedor,verificarBanco,credencialesLocales} from '../gestion-diaria-cortes/http/banco.mjs';
const reanudar=process.argv[3]==='--reanudar-http';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado',...(reanudar?['--reanudar-http']:[])]);
verificarBanco();
const carpeta=base+'/conflicto-http';mkdirSync(carpeta,{recursive:true,mode:0o700});
assert.equal(existsSync(carpeta+'/ensayo.json'),false);
const archivo='20260923021512_crm_gestion_diaria_conflicto_http.sql';
const fuente=readFileSync(new URL('../../migrations/'+archivo,import.meta.url),'utf8');
assert.equal((fuente.match(/^begin;$/gm)??[]).length,1);
assert.equal((fuente.match(/^commit;$/gm)??[]).length,1);
const cambio=fuente.replace(/^begin;$/m,'').replace(/^commit;$/m,'');
const estado=`select jsonb_build_object('funciones',(select jsonb_agg(jsonb_build_array(p.oid::regprocedure::text,
 md5(prosrc),proowner,proacl,prosecdef,proconfig) order by p.oid::regprocedure::text)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private','public') and p.prokind='f'),
 'politicas',(select jsonb_agg(to_jsonb(p) order by version) from crm.politica_gestion_diaria p),
 'control',(select jsonb_agg(to_jsonb(c) order by version) from crm.gestion_diaria_control_avisos c),
 'entregas',(select count(*) from crm.gestion_diaria_entregas),
 'reconocimientos',(select count(*) from crm.alertas_reconocimientos));`;
const antes=sql(estado);
const mutantes=readFileSync(new URL('./test-mutantes.sql',import.meta.url),'utf8');
const prueba=`select set_config('request.jwt.claim.sub',(select perfil_id::text from crm.equipo where activo and rol_crm='gerencia' limit 1),true);
 set local role authenticated;
 do $prueba$ declare c jsonb; s text; begin
 c:=crm.configuracion_gestion_diaria_fn();
 begin perform crm.publicar_politica_gestion_diaria(-1,now()+interval '30 days',c#>'{vigente,configuracion}','Versión obsoleta de prueba');
 exception when others then s:=sqlstate; end;
 if s is distinct from 'PT409' then raise exception 'Conflicto de política inesperado: %',s; end if;
 s:=null;
 begin perform crm.controlar_avisos_gestion_diaria(-1,false,'Versión obsoleta de prueba');
 exception when others then s:=sqlstate; end;
 if s is distinct from 'PT409' then raise exception 'Conflicto de control inesperado: %',s; end if;
 if crm.configuracion_gestion_diaria_fn() is distinct from c then raise exception 'El rechazo cambió la configuración'; end if;
 end $prueba$; reset role;`;
if(!reanudar){
assert.equal(existsSync(carpeta+'/instalado-local.json'),false,'Usar --reanudar-http: no reinstalar');
writeFileSync(carpeta+'/antes.json',antes,{mode:0o600});
const salida=sql(`begin; ${cambio}\n${prueba}\n${mutantes}\nrollback;`);
assert.equal(sql(estado),antes,'Rehearsal completamente revertido');
writeFileSync(carpeta+'/ensayo-sql.log',salida,{mode:0o600});
console.log('PASS: conflictos PT409 sin escrituras, 24 mutantes y ROLLBACK íntegro');
// Aplicación solo local para permitir que el servidor HTTP vea el cambio.
sql(fuente);
const despues=JSON.parse(sql(estado)),previo=JSON.parse(antes);
for(const k of ['politicas','control','entregas','reconocimientos'])assert.deepEqual(despues[k],previo[k]);
const nombres=['crm.publicar_politica_gestion_diaria(integer,timestamp with time zone,jsonb,text)',
 'crm.controlar_avisos_gestion_diaria(integer,boolean,text)','private.assert_gestion_diaria_configuracion()'];
const cambios=despues.funciones.filter((f,i)=>JSON.stringify(f)!==JSON.stringify(previo.funciones[i]));
assert.deepEqual(cambios.map(f=>f[0]).sort(),nombres.sort());
for(const f of cambios)assert.deepEqual(f.slice(2),previo.funciones.find(a=>a[0]===f[0]).slice(2));
writeFileSync(carpeta+'/instalado-local.json',JSON.stringify({estado:'PASS',archivo,sha256:createHash('sha256').update(fuente).digest('hex'),cambios:cambios.map(f=>f[0])},null,2),{mode:0o600});
}else{
 const instalado=JSON.parse(readFileSync(carpeta+'/instalado-local.json','utf8'));
 assert.equal(instalado.estado,'PASS');assert.equal(instalado.archivo,archivo);
 assert.equal(instalado.sha256,createHash('sha256').update(fuente).digest('hex'));
 const comprobacion=sql(`select private.assert_gestion_diaria();
 begin; ${prueba}\n${mutantes}\nrollback;`);
 assert.equal(sql(estado),antes,'Retoma SQL completamente revertida');
 writeFileSync(carpeta+'/reanudacion-sql.log',comprobacion,{mode:0o600});
 console.log('PASS: correctivo ya instalado; conflictos PT409 y 24 mutantes, sin reinstalar');
}
const nombre='gestion-diaria-f4-postgrest14';
const original=JSON.parse(docker(['inspect','supabase_rest_gestion-diaria-f4-http']))[0];
const variables=original.Config.Env.filter(e=>e.startsWith('PGRST_'));
assert.ok(variables.some(e=>e.startsWith('PGRST_DB_URI=')&&e.includes(contenedor)));
const envfile=carpeta+'/postgrest14.env';writeFileSync(envfile,variables.join('\n')+'\n',{mode:0o600});
if(!docker(['ps','-a','--filter','name=^/'+nombre+'$','--format','{{.Names}}']))docker(['run','-d','--name',nombre,'--label','avancecorp.task=gestion-diaria-f4-http',
 '--network','gestion-diaria-f4-http','--restart=no','--cap-drop','ALL','--security-opt','no-new-privileges=true',
 '--read-only','--env-file',envfile,'-p','127.0.0.1:59325:3000','public.ecr.aws/supabase/postgrest:v14.5']);
const sidecar=JSON.parse(docker(['inspect',nombre]))[0];
assert.equal(sidecar.Config.Image,'public.ecr.aws/supabase/postgrest:v14.5');
assert.equal(sidecar.Config.Labels?.['avancecorp.task'],'gestion-diaria-f4-http');
assert.deepEqual(Object.keys(sidecar.NetworkSettings.Networks),['gestion-diaria-f4-http']);
assert.deepEqual(sidecar.HostConfig.PortBindings,{'3000/tcp':[{HostIp:'127.0.0.1',HostPort:'59325'}]});
assert.equal(sidecar.HostConfig.RestartPolicy.Name,'no');
assert.ok(sidecar.Config.Env.includes(variables.find(v=>v.startsWith('PGRST_DB_URI='))),'Base propia del sidecar');
if(!sidecar.State.Running)docker(['start',nombre]);
// Docker recrea la ruta por defecto al arrancar: aislar también este sidecar.
const imagen=JSON.parse(docker(['inspect','supabase_kong_gestion-diaria-f4-http']))[0].Image;
const red=['run','--rm','--pull=never','--label','avancecorp.task=gestion-diaria-f4-http',
 '--network','container:'+sidecar.Id,'--cap-drop','ALL','--read-only',
 '--security-opt','no-new-privileges=true','--user','0','--entrypoint','/bin/busybox'];
const rutas=docker([...red,imagen,'ip','route']);
const defecto=rutas.split('\n').find(r=>r.startsWith('default '));
if(defecto){
 assert.equal(defecto.trim(),`default via ${sidecar.NetworkSettings.Networks['gestion-diaria-f4-http'].Gateway} dev eth0`);
 docker([...red,'--cap-add','NET_ADMIN',imagen,'ip','route','del','default']);
}
assert.ok(!docker([...red,imagen,'ip','route']).split('\n').some(r=>r.startsWith('default ')));
assert.ok(!docker([...red,imagen,'ip','-6','route']).split('\n').some(r=>r.startsWith('default ')));
const c=credencialesLocales();
// Adaptador de destino fijo; únicamente el endpoint Auth sigue pasando por Kong.
const adapter=`import {sql,credencialesLocales,carpeta as base} from ${JSON.stringify(new URL('../gestion-diaria-cortes/http/banco.mjs',import.meta.url).href)};
 export {sql};export const objeto=q=>JSON.parse(sql(q));export const carpeta=${JSON.stringify(carpeta)};
 export const psql=carpeta+'/psql';export const env=process.env;
 export const c=credencialesLocales();
 export async function http(ruta,{token,body}={}){
 const auth=ruta.startsWith('/auth/');
 const url=auth?'http://127.0.0.1:59321'+ruta:'http://127.0.0.1:59325'+ruta.replace('/rest/v1/','/');
 const r=await fetch(url,{method:'POST',signal:AbortSignal.timeout(10_000),headers:{apikey:c.ANON_KEY,Authorization:'Bearer '+(token??c.ANON_KEY),
 'Content-Type':'application/json','Accept-Profile':'crm','Content-Profile':'crm'},body:JSON.stringify(body)});
 return{status:r.status,ok:r.ok,data:await r.json()};}
 export const httpIndependiente=http;`;
writeFileSync(carpeta+'/adapter.mjs',adapter,{mode:0o600});
writeFileSync(carpeta+'/psql',`#!/bin/sh\nexec docker --host unix:///Users/usuario/.docker/run/docker.sock exec -i ${contenedor} psql -U postgres "$@"\n`,{mode:0o700});chmodSync(carpeta+'/psql',0o700);
writeFileSync(carpeta+'/credenciales-fixtures.json',readFileSync(base+'/credenciales-fixtures.json'),{mode:0o600});
let listo=false;
for(let i=0;i<20&&!listo;i++){
 try{listo=(await fetch('http://127.0.0.1:59325/',{headers:{Authorization:'Bearer '+c.ANON_KEY},signal:AbortSignal.timeout(1000)})).status===200;}catch{}
 if(!listo)await new Promise(r=>setTimeout(r,250));
}
assert.ok(listo,'PostgREST 14.5 no disponible');
const {http:peticion}=await import(pathToFileURL(carpeta+'/adapter.mjs').href);
const {USER_BY_KEY}=await import(new URL('../fixtures.mjs',import.meta.url));
const {password}=JSON.parse(readFileSync(base+'/credenciales-fixtures.json','utf8'));
const sesiones=[];
for(let i=0;i<2;i++){
 const r=await peticion('/auth/v1/token?grant_type=password',{body:{email:USER_BY_KEY.gerencia.email,password}});
 assert.equal(r.status,200);sesiones.push(r.data.access_token);
}
const inicio=Date.now();
const lecturas=await Promise.all(sesiones.map(async token=>{
 const r=await peticion('/rest/v1/rpc/configuracion_gestion_diaria_fn',{token,body:{}});
 assert.equal(r.status,200);return{status:r.status,ms:Date.now()-inicio};
}));
writeFileSync(carpeta+'/diagnostico-transporte.json',JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),lecturas},null,2),{mode:0o600});
let carrera=readFileSync(new URL('./remoto/concurrencia.mjs',import.meta.url),'utf8');
for(const previo of ['./banco.mjs','./http-independiente.mjs'])carrera=carrera.replaceAll("'"+previo+"'",JSON.stringify(pathToFileURL(carpeta+'/adapter.mjs').href));
carrera=carrera.replaceAll("'../../fixtures.mjs'",JSON.stringify(new URL('../fixtures.mjs',import.meta.url).href));
assert.equal(carrera.includes("'40001'"),false,'El ensayo debe esperar PT409');
carrera=carrera.replace('PASS: dos carreras remotas','PASS: dos carreras locales');
process.argv=[process.argv[0],process.argv[1],'--solo-rama-autorizada'];
writeFileSync(carpeta+'/carreras-locales.mjs',carrera,{mode:0o600});
await import(pathToFileURL(carpeta+'/carreras-locales.mjs').href);
sql('select private.assert_gestion_diaria();');
writeFileSync(carpeta+'/ensayo.json',JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),archivo,
 servidor:'PostgREST 14.5 local aislado',concurrencia:'Dos carreras, dos bloqueados observados, HTTP 200 + 409, sin reintentos infinitos',
 remoto:'NOT RUN: requiere aprobación del quinto SQL'},null,2)+'\n',{mode:0o600});
console.log('PASS: quinto SQL y dos carreras de configuración en PostgREST 14.5 local');
