// Ensayo de transición, no es el SQL de activación productiva ni una autorización.
// Destino fijo y sintético; no acepta URL, contraseña o nombre de base externos.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
const db='g7_cierre_20260915';
const args=['exec','-i','supabase_db_avancecorp-f5-bank','psql','-X','-qAt',
  '-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'];
const q=x=>`'${String(x).replaceAll("'","''")}'`;
const ejecutar=s=>spawnSync('docker',args,{input:'\\set VERBOSITY verbose\n'+s,encoding:'utf8'});
const sql=s=>{const r=ejecutar(s);assert.equal(r.status,0,r.stderr||r.error?.message);return r.stdout.trim();};
const objeto=s=>JSON.parse(sql(s));
const inicio=new Date().toISOString(),resultados=[];
const archivo=new URL('transicion-local.json',import.meta.url);
writeFileSync(archivo,JSON.stringify({estado:'RUNNING',inicio,banco:db})+'\n');
assert.equal(sql('select current_database()'),db);
const originales=objeto('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags');
assert.equal(sql('select activo from crm.piloto_f8_control where singleton'),'f');
assert.equal(sql('select count(*) from crm.piloto_f8_miembros where activo'),'0');
const estado=()=>objeto(`select jsonb_build_object(
  'control',(select to_jsonb(t) from crm.piloto_f8_control t where singleton),
  'flags',(select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags),
  'miembros',(select jsonb_agg(to_jsonb(t) order by perfil_id) from crm.piloto_f8_miembros t))`);
const tablas=['public.contratos','public.cronograma_pagos','private.contrato_pdfs',
  'crm.cierres_externos','crm.inversiones','crm.inversion_titulares','crm.inversion_solicitudes',
  'crm.depositos_reclamados','crm.inversion_eventos','crm.inversionistas',
  'crm.inversionista_gestiones','crm.tareas','crm.leads','crm.periodos_cerrados',
  'crm.cierre_mes_vendedor','auth.users'];
const huellas=()=>objeto('select jsonb_build_object('+tablas.map(t=>
  `${q(t)},(select md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,'')) from ${t} t)`).join(',')+')');
// F3 exterior: espera las puertas ya iniciadas antes de tomar los candados F5/F4/F8.
// Los escritores administrativos ajenos aún pueden competir; lock_timeout aborta
// toda la transacción. No se promete ausencia universal de contención/deadlocks.
const inicioTx=`begin isolation level read committed;
  set local lock_timeout='500ms';set local statement_timeout='10s';
  select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  select pg_advisory_xact_lock(hashtext('crm_flag_ficha_360_neutral'));
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  select pg_advisory_xact_lock(hashtext('crm_flag_postventa_neutral'));
  select pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));`;
const abrir=`update crm.piloto_f8_control set activo=false where singleton;
  update crm.multiempresa_flags set activo=true
    where nombre in('inversiones_escritura','ficha_360_neutral','postventa_neutral');`;
const cerrar=`update crm.multiempresa_flags set activo=false
  where nombre in('inversiones_escritura','ficha_360_neutral','postventa_neutral');`;
function sesion(s) {
  const p=spawn('docker',args);let out='',err='';
  p.stdout.setEncoding('utf8');p.stderr.setEncoding('utf8');
  p.stdout.on('data',x=>{out+=x;});p.stderr.on('data',x=>{err+=x;});
  const fin=new Promise(resolve=>p.on('close',status=>resolve({status,out,err})));
  p.stdin.write(s);return {p,fin,salida:()=>out};
}
async function esperar(fn) {
  for(let n=0;n<100;n++){if(fn())return;await new Promise(r=>setTimeout(r,50));}
  throw new Error('La sesión SQL no alcanzó la barrera del ensayo');
}
let exito=false,conservadas;
try {
  sql(`begin;update crm.multiempresa_flags set activo=(nombre='resolver_en_puertas');
    update crm.piloto_f8_miembros set activo=true;
    update crm.piloto_f8_control set activo=true,motivo='Ensayo sintético G7 de transición y reversa' where singleton;commit;`);
  assert.equal(sql('select private.piloto_f8_modo_activo()'),'t');
  const piloto=estado(),hechos=huellas();
  const roto=ejecutar(inicioTx+abrir+"do $$begin raise exception using errcode='P0409',message='Corte deliberado del ensayo G7';end$$;commit;");
  assert.notEqual(roto.status,0);assert.match(roto.stderr,/P0409/);
  assert.deepEqual(estado(),piloto);assert.deepEqual(huellas(),hechos);
  resultados.push({caso:'Fallo después de cambiar control y banderas revierte todo',estado:'PASS'});

  const ocupado=sesion("begin;select pg_advisory_xact_lock_shared(hashtext('crm_flag_resolver_en_puertas'));select 'G7_OCUPADO';\n");
  try {
    await esperar(()=>ocupado.salida().includes('G7_OCUPADO'));
    const bloqueo=ejecutar(inicioTx+abrir+'commit;');
    assert.notEqual(bloqueo.status,0);assert.match(bloqueo.stderr,/55P03/);
    assert.deepEqual(estado(),piloto);assert.deepEqual(huellas(),hechos);
  } finally {ocupado.p.stdin.end('rollback;\n');assert.equal((await ocupado.fin).status,0);}
  resultados.push({caso:'Puerta económica en curso impide el cambio sin dejarlo parcial',estado:'PASS'});

  const abierta=sesion(inicioTx+abrir+"select 'G7_SIN_COMMIT';\n");
  try {
    await esperar(()=>abierta.salida().includes('G7_SIN_COMMIT'));
    assert.deepEqual(estado(),piloto,'Otra conexión vio un estado intermedio');
    abierta.p.stdin.end('commit;\n');
    const r=await abierta.fin;assert.equal(r.status,0,r.err);
  } catch(error) {if(!abierta.p.stdin.writableEnded)abierta.p.stdin.end('rollback;\n');await abierta.fin;throw error;}
  const general=estado();
  assert.equal(general.control.activo,false);
  assert.deepEqual(general.flags,{resolver_en_puertas:true,inversiones_escritura:true,
    ficha_360_neutral:true,postventa_neutral:true,metricas_multiempresa_sombra:false});
  assert.deepEqual(huellas(),hechos);
  resultados.push({caso:'El modo general solo aparece íntegro después del COMMIT',estado:'PASS'});

  sql(inicioTx+cerrar+"update crm.piloto_f8_control set activo=true where singleton;commit;");
  const vuelta=estado();assert.equal(vuelta.control.activo,true);
  assert.equal(vuelta.control.inicia_en,piloto.control.inicia_en);
  assert.equal(vuelta.control.vence_en,piloto.control.vence_en);
  assert.deepEqual(vuelta.flags,piloto.flags);
  assert.equal(sql('select private.piloto_f8_modo_activo()'),'t');
  assert.deepEqual(huellas(),hechos);
  resultados.push({caso:'Reversa al piloto vigente conserva su ventana y los hechos',estado:'PASS'});
  sql(inicioTx+abrir+'commit;');
  sql(inicioTx+cerrar+'commit;');
  assert.equal(sql('select private.piloto_f8_modo_activo()'),'f');
  assert.deepEqual(huellas(),hechos);
  conservadas=hechos;
  resultados.push({caso:'Apagado de capacidades nuevas conserva 16 superficies',estado:'PASS'});
  exito=true;
} finally {
  sql(`begin;update crm.piloto_f8_control set activo=false where singleton;
    update crm.piloto_f8_miembros set activo=false;
    ${Object.entries(originales).map(([n,v])=>`update crm.multiempresa_flags set activo=${v} where nombre=${q(n)};`).join('\n')}
    commit;`);
  const recibo={estado:exito?'PASS':'FAIL',inicio,fin:new Date().toISOString(),banco:db,
    resultados,huellas_economicas_conservadas:conservadas,
    limites:['Banco local SQL, sin activación productiva ni aprobación G7.',
      'Reversa nominal probada dentro de su ventana vigente; no extiende vencimiento.',
      'No sustituye las guardias de roster/versiones del futuro SQL exacto de producción.',
      'Ensayo de estados y atomicidad; la matriz de capacidades está en roles-general-local.json.']};
  writeFileSync(archivo,JSON.stringify(recibo,null,2)+'\n');console.log(JSON.stringify(recibo,null,2));
}
