// Dos sesiones Auth y dos esperas reales observadas en PostgreSQL. La jornada
// de popup ya terminó: esas carreras quedan cubiertas localmente, no se simulan
// como HTTP remoto cambiando el reloj del producto.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {carpeta,http,sql,objeto,psql,env} from './banco.mjs';
import {httpIndependiente} from './http-independiente.mjs';
import {USER_BY_KEY} from '../../fixtures.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.equal(existsSync(`${carpeta}/concurrencia.json`),false);
assert.equal(JSON.parse(readFileSync(`${carpeta}/diagnostico-transporte.json`)).estado,'PASS');
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
const sesiones=[];
for(let i=0;i<2;i++){
 const r=await http('/auth/v1/token?grant_type=password',{body:{email:USER_BY_KEY.gerencia.email,password}});
 assert.equal(r.status,200);sesiones.push(r.data.access_token);
}
assert.ok(sesiones[0]!==sesiones[1],'Dos sesiones distintas');
const rpc=(nombre,i,body={})=>httpIndependiente('/rest/v1/rpc/'+nombre,{token:sesiones[i],body});
const pausa=ms=>new Promise(r=>setTimeout(r,ms));
const evidencias=[];
// Observador persistente y asíncrono: abrir psql síncronamente para cada sondeo
// detenía el event loop de fetch y podía consumir la barrera antes de medir.
const observador=spawn(psql,['-X','-qAt','-v','ON_ERROR_STOP=1'],{env,stdio:['pipe','pipe','pipe']});
let observado='',errorObservador='';
observador.stdout.on('data',x=>observado+=x);observador.stderr.on('data',x=>errorObservador+=x);
const finObservador=new Promise(r=>observador.on('close',r));
async function esperar(consulta){
 observado='';observador.stdin.write(consulta+"; select 'FIN_OBSERVACION';\n");
 const limite=Date.now()+10_000;
 while(!observado.includes('FIN_OBSERVACION')&&!errorObservador&&Date.now()<limite)await pausa(20);
 assert.ok(observado.includes('FIN_OBSERVACION'),'Observador no disponible');
 return observado.replace('FIN_OBSERVACION','').trim();
}
await esperar('select 1');
async function simultaneas(objetivo,trabajos){
 const c=spawn(psql,['-X','-qAt','-v','ON_ERROR_STOP=1'],{env,stdio:['pipe','pipe','pipe']});
 let salida='',error='';c.stdout.on('data',x=>salida+=x);c.stderr.on('data',x=>error+=x);
 const cierre=new Promise(r=>c.on('close',r));
 c.stdin.write(`set statement_timeout='30s'; set idle_in_transaction_session_timeout='30s'; begin;
 select pg_advisory_xact_lock(194203,${objetivo}); select 'BARRERA_LISTA';\n`);
 const limite=Date.now()+10_000;
 while(!salida.includes('BARRERA_LISTA')&&!error&&Date.now()<limite)await pausa(20);
 assert.ok(salida.includes('BARRERA_LISTA'),'Barrera no disponible');
 let peticiones,n=0;const medidas=[];const inicio=Date.now();
 try{
  peticiones=Promise.allSettled(trabajos.map(t=>t()));
  for(let i=0;i<40&&n<2&&Date.now()-inicio<5000;i++){
   await pausa(100);
   n=Number(await esperar(`select count(*) from pg_locks where locktype='advisory' and not granted and classid=194203 and objid=${objetivo}`));
   medidas.push({ms:Date.now()-inicio,n,actividad:JSON.parse(await esperar(`select coalesce(jsonb_agg(jsonb_build_object('pid',pid,'espera',wait_event,'tipo',wait_event_type,'bloqueadores',pg_blocking_pids(pid),'politica',query like '%publicar_politica_gestion_diaria%','control',query like '%controlar_avisos_gestion_diaria%')),'[]') from pg_stat_activity where usename='authenticator' and state='active'`))});
  }
 }finally{c.stdin.end('commit;\n');assert.equal(await cierre,0,'Liberación de barrera');}
 const respuestas=await peticiones;
 writeFileSync(`${carpeta}/concurrencia-diagnostico-${objetivo}.json`,JSON.stringify({medidas,respuestas:respuestas.map(r=>r.status==='fulfilled'?{status:r.value.status,code:r.value.data?.code,message:r.value.data?.message}:{error:String(r.reason)})},null,2),{mode:0o600});
 assert.equal(n,2,'Deben esperar las dos solicitudes al mismo tiempo');
 evidencias.push(`Dos solicitudes observadas esperando 194203/${objetivo}`);
 assert.ok(respuestas.every(r=>r.status==='fulfilled'));
 return respuestas.map(r=>r.value);
}
const antes=await rpc('configuracion_gestion_diaria_fn',0);assert.equal(antes.status,200);
const fecha=sql("select to_char(greatest((now() at time zone 'America/Lima')::date,max(vigente_desde at time zone 'America/Lima')::date)+1,'YYYY-MM-DD') from crm.politica_gestion_diaria");
const publicar=i=>rpc('publicar_politica_gestion_diaria',i,{p_expected_version:antes.data.expected_version,
 p_vigente_desde:fecha+'T00:00:00-05:00',p_config:{...antes.data.vigente.configuracion,cortes_activos:false},
 p_motivo:'Ensayo remoto concurrente: próxima política OFF'});
const politicas=await simultaneas(43,[()=>publicar(0),()=>publicar(1)]);
assert.equal(politicas.filter(r=>r.status===200).length,1);
assert.equal(politicas.filter(r=>r.status===409&&r.data.code==='PT409').length,1);
evidencias.push('Publicación futura: una confirma y una rechaza la versión obsoleta con HTTP 409 / PT409');
const control=objeto('select to_jsonb(c) from crm.gestion_diaria_control_avisos c order by version desc limit 1');
const controlar=i=>rpc('controlar_avisos_gestion_diaria',i,{p_expected_version:control.version,
 p_habilitados:!control.habilitados,p_motivo:'Ensayo remoto concurrente del control de avisos'});
try{
 const controles=await simultaneas(44,[()=>controlar(0),()=>controlar(1)]);
 assert.equal(controles.filter(r=>r.status===200).length,1);
 assert.equal(controles.filter(r=>r.status===409&&r.data.code==='PT409').length,1);
 evidencias.push('Control del canal: una confirma y una rechaza la versión obsoleta con HTTP 409 / PT409');
}finally{
 const ultimo=objeto('select to_jsonb(c) from crm.gestion_diaria_control_avisos c order by version desc limit 1');
 if(ultimo.habilitados!==control.habilitados){
  const r=await rpc('controlar_avisos_gestion_diaria',0,{p_expected_version:ultimo.version,
   p_habilitados:control.habilitados,p_motivo:'Restituir canal tras ensayo remoto concurrente'});
  assert.equal(r.status,200,'Control restituido con nueva versión auditada');
 }
}
observador.stdin.end();assert.equal(await finObservador,0);
sql('select private.assert_gestion_diaria();');
writeFileSync(`${carpeta}/concurrencia.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),evidencias,
 limites:'Presentación/aplazamiento HTTP remoto NOT RUN fuera de jornada. Tres carreras locales reales PASS; horarios y acciones SQL remotos PASS.'},null,2)+'\n',{mode:0o600});
console.log('PASS: dos carreras remotas con dos esperas observadas; política futura y control CAS; canal restituido');
