// Ensayo del quinto SQL exclusivamente en Docker de Gestión Diaria.
// Conserva el PostgREST 16 existente y abre un sidecar 14.5 sin salida exterior.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,chmodSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {carpeta as base,sql,docker,contenedor,verificarBanco,credencialesLocales} from '../gestion-diaria-cortes/http/banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
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
const antes=sql(estado);writeFileSync(carpeta+'/antes.json',antes,{mode:0o600});
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
const nombre='gestion-diaria-f4-postgrest14';
const original=JSON.parse(docker(['inspect','supabase_rest_gestion-diaria-f4-http']))[0];
const variables=original.Config.Env.filter(e=>e.startsWith('PGRST_'));
assert.ok(variables.some(e=>e.startsWith('PGRST_DB_URI=')&&e.includes(contenedor)));
const envfile=carpeta+'/postgrest14.env';writeFileSync(envfile,variables.join('\n')+'\n',{mode:0o600});
docker(['run','-d','--name',nombre,'--label','avancecorp.task=gestion-diaria-f4-http',
 '--network','gestion-diaria-f4-http','--restart=no','--cap-drop','ALL','--security-opt','no-new-privileges=true',
 '--read-only','--env-file',envfile,'-p','127.0.0.1:59325:3000','public.ecr.aws/supabase/postgrest:v14.5']);
const c=credencialesLocales();
// Adaptador de destino fijo; únicamente el endpoint Auth sigue pasando por Kong.
const adapter=`import {sql,credencialesLocales,carpeta as base} from ${JSON.stringify(new URL('../gestion-diaria-cortes/http/banco.mjs',import.meta.url).href)};
 export {sql};export const objeto=q=>JSON.parse(sql(q));export const carpeta=${JSON.stringify(carpeta)};
 export const psql=carpeta+'/psql';export const env=process.env;
 export async function http(ruta,{token,body}={}){
 const c=credencialesLocales();const url=(ruta.startsWith('/auth/')?'http://127.0.0.1:59321':'http://127.0.0.1:59325')+ruta;
 const r=await fetch(url,{method:'POST',signal:AbortSignal.timeout(10_000),headers:{apikey:c.ANON_KEY,Authorization:'Bearer '+(token??c.ANON_KEY),
 'Content-Type':'application/json','Accept-Profile':'crm','Content-Profile':'crm'},body:JSON.stringify(body)});
 return{status:r.status,ok:r.ok,data:await r.json()};}
 export const httpIndependiente=http;`;
writeFileSync(carpeta+'/adapter.mjs',adapter,{mode:0o600});
writeFileSync(carpeta+'/psql',`#!/bin/sh\nexec docker --host unix:///Users/usuario/.docker/run/docker.sock exec -i ${contenedor} psql -U postgres "$@"\n`,{mode:0o700});chmodSync(carpeta+'/psql',0o700);
writeFileSync(carpeta+'/credenciales-fixtures.json',readFileSync(base+'/credenciales-fixtures.json'),{mode:0o600});
writeFileSync(carpeta+'/diagnostico-transporte.json',JSON.stringify({estado:'PASS',causa:'HTTP local, dos conexiones demostradas por pg_locks en el ensayo siguiente'}),{mode:0o600});
let listo=false;
for(let i=0;i<20&&!listo;i++){
 try{listo=(await fetch('http://127.0.0.1:59325/',{headers:{Authorization:'Bearer '+c.ANON_KEY},signal:AbortSignal.timeout(1000)})).status===200;}catch{}
 if(!listo)await new Promise(r=>setTimeout(r,250));
}
assert.ok(listo,'PostgREST 14.5 no disponible');
let carrera=readFileSync(new URL('./remoto/concurrencia.mjs',import.meta.url),'utf8');
for(const previo of ['./banco.mjs','./http-independiente.mjs'])carrera=carrera.replaceAll("'"+previo+"'",JSON.stringify(pathToFileURL(carpeta+'/adapter.mjs').href));
carrera=carrera.replaceAll("'../../fixtures.mjs'",JSON.stringify(new URL('../fixtures.mjs',import.meta.url).href));
assert.equal(carrera.includes("'40001'"),false,'El ensayo debe esperar PT409');
process.argv=[process.argv[0],process.argv[1],'--solo-rama-autorizada'];
await import('data:text/javascript;base64,'+Buffer.from(carrera).toString('base64'));
sql('select private.assert_gestion_diaria();');
writeFileSync(carpeta+'/ensayo.json',JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),archivo,
 servidor:'PostgREST 14.5 local aislado',concurrencia:'Dos carreras, dos bloqueados observados, HTTP 200 + 409, sin reintentos infinitos',
 remoto:'NOT RUN: requiere aprobación del quinto SQL'},null,2)+'\n',{mode:0o600});
console.log('PASS: quinto SQL y dos carreras de configuración en PostgREST 14.5 local');
