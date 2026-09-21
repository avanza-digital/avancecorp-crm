// Exclusivo del banco propio sintético; las carreras requieren COMMIT real.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import test from 'node:test';
const db=process.env.CONTRATOS_AUDITORIA_BANCO || 'contratos_vinculados_20260916';
assert.ok(['contratos_vinculados_20260916','contratos_registro_20260921'].includes(db), 'Banco local no autorizado');
const args=['exec','-i','supabase_db_avancecorp-f5-bank','psql','-XqAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','--set','VERBOSITY=verbose'];
function sql(texto) {
  const r=spawnSync('docker',args,{input:texto,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr); return r.stdout.trim();
}
function conexion(nombre) {
  const p=spawn('docker',args);let salida='',errores='',terminado=false;
  // psql puede cerrar stdin al rechazar una consulta antes de que llegue COMMIT.
  p.stdin.on('error',e=>{if(e.code!=='EPIPE')throw e;});
  p.stdout.on('data',d=>salida+=d);p.stderr.on('data',d=>errores+=d);
  const fin=new Promise((resolve,reject)=>{p.on('error',reject);p.on('close',code=>{terminado=true;resolve({code,salida,errores});});});
  p.stdin.write(`set application_name='${nombre}'; set statement_timeout='12s'; begin;\n`);
  return {enviar:s=>p.stdin.write(s+'\n'),salida:()=>salida,terminado:()=>terminado,
    cerrar:(s='rollback;')=>{if(!terminado)p.stdin.end(s+'\n\\q\n');return fin;}};
}
async function esperar(condicion) {
  const inicio=Date.now();do {if(condicion())return;await delay(25);}while(Date.now()-inicio<3500);
  assert.fail('No se observó el estado de concurrencia esperado');
}
const q=s=>"'"+s.replaceAll("'","''")+"'";
function fixture() {
  const c=randomUUID(),i=randomUUID();
  const a=sql("select id from public.perfiles where rol='admin' and activo limit 1");
  sql(`begin;set local session_replication_role=replica;
    insert into public.contratos select (jsonb_populate_record(null::public.contratos,to_jsonb(x)||jsonb_build_object('id',${q(c)},'numero_contrato',${q('CARRERA-'+c)}))).* from public.contratos x where numero_contrato='AC-2026-0001';
    insert into crm.inversiones select (jsonb_populate_record(null::crm.inversiones,to_jsonb(x)||jsonb_build_object('id',${q(i)},'contrato_id',${q(c)}))).* from crm.inversiones x join public.contratos c on c.id=x.contrato_id where c.numero_contrato='AC-2026-0001';
    insert into crm.inversion_titulares select (jsonb_populate_record(null::crm.inversion_titulares,to_jsonb(x)||jsonb_build_object('id',gen_random_uuid(),'inversion_id',${q(i)}))).* from crm.inversion_titulares x join crm.inversiones v on v.id=x.inversion_id join public.contratos c on c.id=v.contrato_id where c.numero_contrato='AC-2026-0001';
    insert into public.cronograma_pagos(contrato_id,numero_cuota,fecha_programada,monto_programado,estado) values(${q(c)},1,current_date,125,'pendiente');commit;`);
  return {c,i,a,borrar:`select crm.contrato_eliminar_auditado(${q(c)},${q(a)});`,evento:`insert into crm.inversion_eventos(inversion_id,tipo,motivo,creado_por) values(${q(i)},'correccion','Prueba sintética simultánea',${q(a)});`};
}
async function bloqueada(nombre) {
  await esperar(()=>sql(`select exists(select 1 from pg_stat_activity where datname=current_database() and application_name=${q(nombre)} and wait_event_type='Lock')`)==='t');
}
async function lista(c,s) {c.enviar(s+" select 'LISTA';");await esperar(()=>c.salida().includes('LISTA'));}
function bien(r) {assert.equal(r.code,0,r.errores);}

test('Dos eliminaciones simultáneas comparten una única auditoría',async()=>{
  const f=fixture(),a=conexion('auditada_doble_a'),b=conexion('auditada_doble_b');
  try {
    await lista(a,f.borrar);b.enviar(f.borrar);await bloqueada('auditada_doble_b');bien(await a.cerrar('commit;'));bien(await b.cerrar('commit;'));
    assert.equal(sql(`select count(*) from crm.contratos_eliminados_auditoria where contrato_id=${q(f.c)}`),'1');
    const recibo=s=>JSON.parse(s.split('\n').find(l=>l.startsWith('{')));
    assert.deepEqual(recibo(a.salida()),recibo(b.salida()));
  } finally {await a.cerrar();await b.cerrar();}
});

test('Un evento que llega después del borrado espera y falla sin quedar huérfano',async()=>{
  const f=fixture(),a=conexion('auditada_evento_despues_a'),b=conexion('auditada_evento_despues_b');
  try {
    await lista(a,f.borrar);b.enviar(f.evento);await bloqueada('auditada_evento_despues_b');bien(await a.cerrar('commit;'));
    const r=await b.cerrar('commit;');assert.notEqual(r.code,0);assert.match(r.errores,/23503/);
    assert.equal(sql(`select count(*) from crm.inversion_eventos where inversion_id=${q(f.i)}`),'0');
  } finally {await a.cerrar();await b.cerrar();}
});

test('Un evento confirmado mientras el borrado espera protege contrato e inversión',async()=>{
  const f=fixture(),a=conexion('auditada_evento_antes_a'),b=conexion('auditada_evento_antes_b');
  try {
    await lista(a,f.evento);b.enviar(f.borrar);await bloqueada('auditada_evento_antes_b');bien(await a.cerrar('commit;'));
    const r=await b.cerrar('commit;');assert.notEqual(r.code,0);assert.match(r.errores,/55000.*historial propio/);
    assert.equal(sql(`select exists(select 1 from public.contratos where id=${q(f.c)}) and exists(select 1 from crm.inversiones where id=${q(f.i)}) and not exists(select 1 from crm.contratos_eliminados_auditoria where contrato_id=${q(f.c)}) and not exists(select 1 from private.contrato_eliminaciones where contrato_id=${q(f.c)})`),'t');
  } finally {await a.cerrar();await b.cerrar();}
});

test('Un pago confirmado mientras el borrado espera se incluye íntegro en la copia',async()=>{
  const f=fixture(),a=conexion('auditada_pago_a'),b=conexion('auditada_pago_b');
  try {
    await lista(a,`update public.cronograma_pagos set estado='pagado',monto_pagado=125,fecha_pago_real=current_date,registrado_por=${q(f.a)} where contrato_id=${q(f.c)};`);
    b.enviar(f.borrar);await bloqueada('auditada_pago_b');bien(await a.cerrar('commit;'));bien(await b.cerrar('commit;'));
    const copia=JSON.parse(sql(`select snapshot->'cronograma' from crm.contratos_eliminados_auditoria where contrato_id=${q(f.c)}`));
    assert.equal(copia.length,1);assert.equal(copia[0].estado,'pagado');assert.equal(copia[0].monto_pagado,125);assert.equal(copia[0].registrado_por,f.a);
  } finally {await a.cerrar();await b.cerrar();}
});
