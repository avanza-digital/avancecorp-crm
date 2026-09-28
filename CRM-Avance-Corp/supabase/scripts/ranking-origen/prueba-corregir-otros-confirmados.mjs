import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
const dir=dirname(fileURLToPath(import.meta.url));
const body=readFileSync(join(dir,'corregir-otros-confirmados.sql'),'utf8');
function sql(input,ok=true,expected){const r=spawnSync('docker',['exec','-i','supabase_db_crm-avance-corp-local','psql','-XqAt','-U','postgres','-d','ranking_origen_correccion_20260928','-v','ON_ERROR_STOP=1','-f','-'],{input,encoding:'utf8',timeout:60000,maxBuffer:4*1024*1024}); if(ok&&r.status!==0)throw Error(r.stderr);if(!ok){assert.notEqual(r.status,0,'Debió rechazar el caso negativo');if(expected)assert.match(r.stderr,expected);}return r.stdout.trim().split('\n').at(-1);}
const uuid=s=>{const h=createHash('md5').update(s).digest('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;};
const plan={batch:uuid('lote-ficticio'),periodo:'2026-09-01',motivo:'Confirmacion y asignacion administrativa ficticias',filas:Array.from({length:7},(_,j)=>{const i=j+1;return{lead_id:uuid('correccion-lead-'+i),fuente_id:uuid('correccion-fuente-'+i),fuente_tipo:i<=5?'contrato':'cierre_externo',vendedor_id:'b0000000-0000-4000-8000-000000000002',capital:1000*i,moneda:i===5?'USD':'PEN',nuevo:i%2?'formulario':'landing',evidencia:i<=2?'confirmacion':'asignacion_administrativa'};})};
const quote=x=>"'"+JSON.stringify(x).replaceAll("'","''")+"'";
const run=(p,{actor='b0000000-0000-4000-8000-000000000003',repeat=false,ok=true,pre='',expected}={})=>sql(`begin isolation level repeatable read;set local statement_timeout='30s';set local lock_timeout='3s';select set_config('request.jwt.claim.sub','${actor}',true);select set_config('crm.correccion_origen_plan',${quote(p)},true);${pre}\n${body}
${repeat?body:''}
select current_setting('crm.correccion_origen_resultado');
do $$begin if (select count(*) from crm.conversion_acreditaciones where lead_id in(select (f->>'lead_id')::uuid from jsonb_array_elements(current_setting('crm.correccion_origen_plan')::jsonb->'filas') f) and origen='otro')<>0 then raise exception 'Acreditacion no sincronizada';end if;
if (select count(*) from public.audit_log where tabla='crm.leads.origen_confirmado' and data_despues->>'batch'='${plan.batch}')<>7 then raise exception 'Auditoria incompleta/duplicada';end if;
if (select count(*) from crm.leads where id in(select (f->>'lead_id')::uuid from jsonb_array_elements(current_setting('crm.correccion_origen_plan')::jsonb->'filas') f) and nota like '%canal historico no acreditado%')<>5 then raise exception 'No distingue asignacion administrativa';end if;end $$;
rollback;`,ok,expected);
if(process.argv.includes('--seed')){console.log(sql(readFileSync(join(dir,'semilla-correccion-origen.sql'),'utf8')));process.exit(0);}
console.log('PASS lote real de triggers, 7 filas, PEN/USD, Avance/COOPAC, acreditacion y notas: '+run(plan));
console.log('PASS repeticion idempotente: '+run(plan,{repeat:true}));
const bad=structuredClone(plan);bad.filas[6].capital=9999;run(bad,{ok:false,expected:/Fuente, importe, moneda, periodo o atribucion divergente/});console.log('PASS importe divergente aborta el lote');
run(plan,{actor:'b0000000-0000-4000-8000-000000000002',ok:false,expected:/Gerencia activa/});console.log('PASS actor sin Gerencia rechazado');
const dup=structuredClone(plan);dup.filas.push(dup.filas[0]);run(dup,{ok:false,expected:/leads duplicados/});console.log('PASS lead duplicado rechazado');
const noReason=structuredClone(plan);delete noReason.motivo;run(noReason,{ok:false,expected:/Manifiesto invalido/});console.log('PASS motivo ausente rechazado');
run(plan,{ok:false,expected:/El mes comercial ya esta sellado/,pre:"insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura) values('2026-09-01',0.15,1,'{}');"});console.log('PASS mes sellado rechaza la correccion');
assert.equal(sql("select count(*) from crm.leads where nombre_completo like 'PRUEBA CORRECCION %' and origen='otro'"),'7');
console.log('PASS todos los ensayos rollback; sin cambios persistentes en fixtures');
writeFileSync(join(tmpdir(),'ranking-correccion-origen-pruebas.json'),JSON.stringify({status:'PASS',cases:7,batch:plan.batch},null,2));
