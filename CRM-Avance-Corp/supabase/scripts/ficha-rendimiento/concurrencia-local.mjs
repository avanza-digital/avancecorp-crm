import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {sql,ajustes,contenedor,base} from './banco-local.mjs';

const leer=(ruta)=>readFileSync(new URL(ruta,import.meta.url),'utf8');
const migracion=leer('../../migrations/20260915170237_crm_ficha_lectura_individual.sql');
const reversa=leer('./REVERSA.sql');
const nombres=['resolver_en_puertas','ficha_360_neutral','inversiones_escritura','postventa_neutral'];
const filtro=nombres.map(n=>`'${n}'`).join(',');
const banderas=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',nombre,'activo',activo)) from crm.multiempresa_flags where nombre in (${filtro});`));
assert.equal(banderas.length,4);
assert.equal(sql("select to_regprocedure('private.cartera_f5_personas_visibles(uuid)') is null;"),'t');
const funciones=`select jsonb_agg(x order by firma) from (select p.oid::regprocedure::text firma,
 md5(pg_get_functiondef(p.oid)) md5,p.proacl::text acl from pg_proc p
 where p.oid in ('private.cartera_f5_personas_visibles()'::regprocedure,
 'crm.inversionista_ficha_fn(uuid,integer,integer)'::regprocedure)) x;`;
const original=JSON.parse(sql(funciones));
const a=JSON.parse(sql(`select jsonb_build_object(
 'gerencia',(select perfil_id from crm.equipo where activo and rol_crm='gerencia' order by perfil_id limit 1),
 'analista',(select perfil_id from crm.equipo where activo and rol_crm='vendedor' order by perfil_id limit 1),
 'supervisor',(select supervisor_id from crm.equipo where activo and rol_crm='vendedor' order by perfil_id limit 1));`));
for(const id of Object.values(a)) assert.match(id,/^[0-9a-f-]{36}$/);
function sqlConcurrente(consulta) {
 return new Promise((resolve,reject)=>{
  const proceso=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',base,'-v','ON_ERROR_STOP=1','-f','-']);
  let salida='',error='';
  proceso.stdout.on('data',x=>salida+=x);proceso.stderr.on('data',x=>error+=x);
  proceso.on('error',reject);
  proceso.on('close',codigo=>codigo===0?resolve(JSON.parse(salida.trim())):reject(new Error(error)));
  proceso.stdin.end(consulta);
 });
}
const medidas=[],oleadas=[];let instalada=false;
try {
 // Única copia local propia. Solo aquí se confirma temporalmente la migración
 // para que varias sesiones puedan verla. El finally revierte SQL y banderas.
 sql(`begin;${ajustes}update crm.multiempresa_flags set activo=true where nombre in (${filtro});commit;`);
 const persona=sql(`begin;${ajustes}set local request.jwt.claim.sub='${a.analista}';
 select p.inversionista_id from private.cartera_f5_personas_visibles() p
 where (crm.inversionista_ficha_fn(p.inversionista_id)#>>'{capacidades,nueva_inversion}')::boolean
 order by p.inversionista_id limit 1;rollback;`);
 assert.match(persona,/^[0-9a-f-]{36}$/,'Hace falta una ficha operable que tome el lock F4 real');
 for(const fase of ['antes','despues']) {
  if(fase==='despues'){sql(migracion);instalada=true;}
  for(const cantidad of [1,2,3]) {
   const inicio=Date.now()/1000+1.5;
   const tareas=Object.entries(a).slice(0,cantidad).map(([rol,uid])=>sqlConcurrente(`begin;${ajustes}
    set local application_name='ficha_concurrencia_local';
    set local role authenticated;set local request.jwt.claim.sub='${uid}';
    do $barrera$ begin perform pg_sleep(greatest(0,${inicio}-extract(epoch from clock_timestamp()))); end; $barrera$;
    with inicio as materialized(select clock_timestamp() t0),
    lectura as materialized(select crm.inversionista_ficha_fn('${persona}'::uuid) dato,t0 from inicio),
    fin as materialized(select dato,t0,clock_timestamp() t1 from lectura)
    select jsonb_build_object('fase','${fase}','rol','${rol}','oleada',${cantidad},'pid',pg_backend_pid(),
     'inicio',t0,'fin',t1,'ms',round((extract(epoch from t1-t0)*1000)::numeric,3),'huella',md5(dato::text),
     'operable',dato#>'{capacidades,nueva_inversion}') from fin;rollback;`));
   // Esperar también procesos fallidos antes de restaurar las funciones.
   const terminadas=await Promise.allSettled(tareas);
   for(const t of terminadas) assert.equal(t.status,'fulfilled',t.reason?.message);
   const r=terminadas.map(t=>t.value);
   assert.equal(new Set(r.map(x=>x.pid)).size,cantidad);
   assert.ok(r.every(x=>x.operable===true),'No se ejercitó el contexto F4 operable');
   const solapamiento=Math.min(...r.map(x=>Date.parse(x.fin)))-Math.max(...r.map(x=>Date.parse(x.inicio)));
   assert.ok(solapamiento>0,'Las sesiones no se solaparon realmente');
   medidas.push(...r);oleadas.push({fase,cantidad,solapamiento_ms:solapamiento});
  }
 }
 for(const rol of Object.keys(a)) assert.equal(new Set(medidas.filter(m=>m.rol===rol).map(m=>m.huella)).size,1,
  'Una ficha o capacidad varió al concurrir');
} finally {
 if(instalada) sql(reversa);
 sql(`begin;${ajustes}${banderas.map(b=>`update crm.multiempresa_flags set activo=${b.activo?'true':'false'} where nombre='${b.nombre}';`).join('\n')}commit;`);
 assert.deepEqual(JSON.parse(sql(funciones)),original,'No se restauraron funciones y ACL');
 assert.equal(sql("select to_regprocedure('private.cartera_f5_personas_visibles(uuid)') is null;"),'t');
 assert.equal(sql("select count(*) from pg_stat_activity where datname=current_database() and application_name='ficha_concurrencia_local';"),'0');
}
const resultado={resultado:'PASS',base,fecha:new Date().toISOString(),restauracion:'PASS',
 alcance:'12 lecturas SQL en seis oleadas de 1/2/3 sesiones, misma persona, tres roles. Banco sintético pequeño; no equivale a concurrencia productiva ni HTTP.',oleadas,medidas};
const evidencias=new URL('./evidencias/',import.meta.url);mkdirSync(evidencias,{recursive:true});
writeFileSync(new URL('concurrencia-local.json',evidencias),JSON.stringify(resultado,null,2)+'\n');
console.log(JSON.stringify({...resultado,medidas:undefined}));
