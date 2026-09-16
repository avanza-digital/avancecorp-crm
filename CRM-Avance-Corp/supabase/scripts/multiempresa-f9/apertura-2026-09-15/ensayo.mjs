// Ensaya ACTIVAR/REVERTIR literales, concurrencia y abortos en la copia F9.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {db,args,sql,objeto,ejecutar,q} from './banco.mjs';
import {crearOperaciones} from './operaciones-reversa.mjs';
const leer=f=>readFileSync(new URL(f,import.meta.url),'utf8');
const activar=leer('ACTIVAR.sql'),revertir=leer('REVERTIR.sql'),cfg=JSON.parse(leer('config.json'));
const resultados=[],inicio=new Date().toISOString(),archivo=new URL('ensayo.json',import.meta.url);
writeFileSync(archivo,JSON.stringify({estado:'RUNNING',inicio,banco:db}));
const tablas=['public.contratos','public.cronograma_pagos','private.contrato_pdfs','crm.cierres_externos',
  'crm.inversiones','crm.inversion_titulares','crm.inversion_solicitudes','crm.depositos_reclamados',
  'crm.inversion_eventos','crm.inversionistas','crm.inversionista_gestiones','crm.tareas','crm.leads',
  'crm.periodos_cerrados','crm.cierre_mes_vendedor','auth.users','public.perfiles','storage.objects','crm.postventa_retiros'];
const hechos=()=>objeto('select jsonb_build_object('+tablas.map(t=>`${q(t)},(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text)::text,'')) from ${t} x)`).join(',')+')');
const auditoriaActores=()=>sql("select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text)::text,'')) from public.audit_log x where usuario_id is not null");
const estado=()=>objeto(`select jsonb_build_object('control',(select to_jsonb(c) from crm.piloto_f8_control c where singleton),
  'banderas',(select jsonb_agg(to_jsonb(f) order by nombre) from crm.multiempresa_flags f),
  'miembros',(select jsonb_agg(to_jsonb(m) order by perfil_id) from crm.piloto_f8_miembros m))`);
function piloto() {
  sql(`begin;update crm.multiempresa_flags set activo=(nombre='resolver_en_puertas');
    alter table crm.piloto_f8_control disable trigger trg_piloto_f8_control_00_validar;
    update crm.piloto_f8_control set activo=true,revision=1,motivo=${q(cfg.control.motivo)},
      inicia_en=${q(cfg.control.inicia_en)},vence_en=${q(cfg.control.vence_en)},actualizado_por=${q(cfg.responsable_id)} where singleton;
    alter table crm.piloto_f8_control enable trigger trg_piloto_f8_control_00_validar;commit;`);
}
function denegado(codigo,s=activar) {
  const e=estado(),h=hechos(),r=ejecutar(s);
  assert.notEqual(r.status,0);assert([codigo].flat().some(c=>r.stderr.includes(c)),r.stderr);
  assert.deepEqual(estado(),e);assert.deepEqual(hechos(),h);
}
function sesion(s) {
  const p=spawn('docker',args());let out='',err='';p.stdout.setEncoding('utf8');p.stderr.setEncoding('utf8');
  p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>err+=x);
  const fin=new Promise(resolve=>p.on('close',status=>resolve({status,out,err})));
  p.stdin.write(s);return {p,fin,salida:()=>out};
}
async function esperar(fn) {for(let i=0;i<200;i++){if(fn())return;await new Promise(r=>setTimeout(r,50));}throw new Error('Barrera no alcanzada');}
const bien=caso=>{resultados.push({caso,estado:'PASS'});console.log('PASS: '+caso);};
let exito=false,conservadas,apertura,postflight,operaciones,trasOperar,estadosReversa,lecturas,retiro,auditoriaAntes;
try {
  assert.equal(sql('select current_database()'),db);piloto();
  conservadas=hechos();
  // Inyección del fallo justo después de apagar F8 y antes de encender flags.
  const roto=activar.replace('  update crm.multiempresa_flags set activo=true',
    "  raise exception 'Interrupción deliberada' using errcode='P0409';\n  update crm.multiempresa_flags set activo=true");
  assert.notEqual(roto,activar);denegado('P0409',roto);bien('Fallo intermedio revierte piloto y banderas completos');
  const lento=activar.replace('  inicio_bloqueo:=clock_timestamp();','  inicio_bloqueo:=clock_timestamp();perform pg_sleep(4);');
  assert.notEqual(lento,activar);const empieza=performance.now();denegado('57014',lento);
  assert(performance.now()-empieza<3800,'El límite efectivo no interrumpió a tiempo');
  bien('Sentencia lenta aborta a los tres segundos sin esperar su final');
  const vendedor=cfg.equipo.find(x=>x.rol_crm==='vendedor');
  const otro=cfg.equipo.find(x=>x.rol_crm==='supervisor'&&x.perfil_id!==vendedor.supervisor_id);
  sql(`update crm.equipo set supervisor_id=${q(otro.perfil_id)} where perfil_id=${q(vendedor.perfil_id)}`);
  try {denegado('P0409');} finally {sql(`update crm.equipo set supervisor_id=${q(vendedor.supervisor_id)} where perfil_id=${q(vendedor.perfil_id)}`);}
  bien('Cambio real de supervisor aborta apertura');
  sql('revoke execute on function crm.cartera_inversionistas_estado_fn() from authenticated');
  try {denegado('P0409');} finally {sql('grant execute on function crm.cartera_inversionistas_estado_fn() to authenticated');}
  bien('Permiso de RPC distinto aborta apertura');
  sql('alter table crm.multiempresa_flags disable trigger trg_multiempresa_flags_01_bloquear_piloto_f8');
  try {denegado('P0409');} finally {sql('alter table crm.multiempresa_flags enable trigger trg_multiempresa_flags_01_bloquear_piloto_f8');}
  bien('Trigger deshabilitado aborta apertura');
  sql('create function private.f9_funcion_inesperada() returns integer language sql as $$select 1$$');
  try {denegado('P0409');} finally {sql('drop function private.f9_funcion_inesperada()');}
  bien('Función nueva fuera del catálogo aborta apertura');
  const vence=activar.replace(cfg.vence_sql,'2000-01-01T00:00:00.000Z');assert.notEqual(vence,activar);
  denegado('P0409',vence);bien('Captura vencida aborta apertura');
  const inicioViejo='2000-01-01T00:00:00+00:00',finViejo='2000-01-02T00:00:00+00:00';
  sql(`begin;alter table crm.piloto_f8_control disable trigger trg_piloto_f8_control_00_validar;
    update crm.piloto_f8_control set inicia_en=${q(inicioViejo)},vence_en=${q(finViejo)};
    alter table crm.piloto_f8_control enable trigger trg_piloto_f8_control_00_validar;commit;`);
  try {denegado('P0409',activar.replaceAll(cfg.control.inicia_en,inicioViejo).replaceAll(cfg.control.vence_en,finViejo));}
  finally {piloto();}
  bien('Piloto vencido aborta aunque coincida su captura');
  const ocupado=sesion("begin;select pg_advisory_xact_lock_shared(hashtext('crm_flag_resolver_en_puertas'));select 'F9_OCUPADO';\n");
  try {await esperar(()=>ocupado.salida().includes('F9_OCUPADO'));denegado(['55P03','57014']);}
  finally {ocupado.p.stdin.end('rollback;\n');assert.equal((await ocupado.fin).status,0);}
  bien('Operación en curso bloquea y aborta sin estado parcial');
  const antes=estado();auditoriaAntes=auditoriaActores();
  const partes=activar.split('-- F9_COMMIT: frontera usada por el ensayo de atomicidad.');assert.equal(partes.length,2);
  const fragmento=partes[0]+"select 'F9_SIN_COMMIT';\n";
  const pendiente=sesion(fragmento);
  try {
    await esperar(()=>pendiente.salida().includes('F9_SIN_COMMIT'));
    assert.deepEqual(estado(),antes,'Se vio estado intermedio desde otra conexión');
    pendiente.p.stdin.end(partes[1]+'\n');const r=await pendiente.fin;assert.equal(r.status,0,r.err);
    apertura=JSON.parse(r.out.split('\n').find(x=>x.startsWith('{')));
  } finally {if(!pendiente.p.stdin.writableEnded)pendiente.p.stdin.end('rollback;\n');await pendiente.fin;}
  assert.equal(apertura.estado,'PASS');assert.equal(apertura.roles.length,4);
  assert.equal(apertura.confirmado_despues_commit,true);assert(apertura.milisegundos_candados<3000);
  postflight=objeto(leer('POSTFLIGHT.sql'));assert.equal(postflight.roles.length,24);
  for(const [rol,cantidad] of [['vendedor',18],['supervisor',3],['gerencia',2]])
    assert.equal(postflight.roles.filter(r=>r.rol===rol&&r.cartera.escritura_habilitada&&r.postventa.habilitada).length,cantidad);
  assert.equal(estado().control.activo,false);assert.deepEqual(hechos(),conservadas);
  bien('COMMIT atómico habilita 23 gestores y conserva exclusión de Coordinación');
  assert.equal(auditoriaActores(),auditoriaAntes);
  bien('Pruebas de capacidades no generan auditorías atribuidas a usuarios');
  denegado('P0409');bien('Segunda activación no sobrescribe el estado ya abierto');
  assert(!cfg.miembros.some(m=>m.perfil_id===vendedor.perfil_id));
  operaciones=crearOperaciones(vendedor.perfil_id);trasOperar=hechos();
  assert.notDeepEqual(trasOperar,conservadas);bien('Dos inversiones F4 confirmadas por analista durante apertura');
  const fuente=sql(`select cierre_externo_id from crm.inversiones where id=${q(operaciones.inversiones[0].inversion)}`);
  const pedirRetiro=actor=>`begin;set local role authenticated;set local request.jwt.claim.sub=${q(actor)};
    select crm.postventa_solicitar_retiro_fn(${q(randomUUID())},${q(operaciones.persona)},${q(fuente)},'Retiro ficticio ensayo F9');commit;`;
  retiro=objeto(pedirRetiro(vendedor.perfil_id));assert.ok(retiro.retiro?.id);
  trasOperar=hechos();
  denegado('42501',pedirRetiro(cfg.equipo.find(x=>x.rol_crm==='coordinador').perfil_id));
  bien('Analista fuera del piloto solicita retiro; Coordinación no puede hacerlo');
  lecturas=objeto(leer('verificar-lecturas.sql'));assert.equal(lecturas.estado,'PASS');
  assert.equal(lecturas.roles.length,3);assert.deepEqual(hechos(),trasOperar);
  bien('Cartera y ficha por rol: núcleo, totales y ámbito conservados');
  const lector=sesion(`begin;set local role authenticated;set local request.jwt.claim.sub=${q(vendedor.perfil_id)};
    select crm.postventa_estado_fn();select 'F9_POSTVENTA';\n`);
  try {await esperar(()=>lector.salida().includes('F9_POSTVENTA'));denegado('55P03',revertir);}
  finally {lector.p.stdin.end('rollback;\n');assert.equal((await lector.fin).status,0);}
  bien('Reversa bajo consulta real de postventa aborta sin deadlock ni estado parcial');
  const vuelta=objeto(revertir);assert.equal(vuelta.estado,'PASS');
  assert.deepEqual(vuelta.banderas,{resolver_en_puertas:true,inversiones_escritura:false,ficha_360_neutral:false,postventa_neutral:false,metricas_multiempresa_sombra:false});
  assert.equal(vuelta.confirmado_despues_commit,true);
  assert.equal(estado().control.activo,false);assert.deepEqual(hechos(),trasOperar);
  assert.equal(sql(`select count(*) from private.cartera_f5_fuentes_reales() f left join crm.inversionistas i on i.id=f.inversionista_id
    where not coalesce(f.identidad_coherente,false) or i.id is null or i.inversionista_canonico_id is not null`),'0');
  estadosReversa=cfg.equipo.map(actor=>{
    const claims=`begin;set local role authenticated;set local request.jwt.claim.sub=${q(actor.perfil_id)};`;
    const f6=objeto(claims+'select crm.postventa_estado_fn();rollback;');assert.equal(f6.habilitada,false);
    if(actor.rol_crm==='coordinador') {
      const r=ejecutar(claims+'select crm.cartera_inversionistas_estado_fn();rollback;');
      assert.notEqual(r.status,0);assert(r.stderr.includes('42501'),r.stderr);
    } else {const f5=objeto(claims+'select crm.cartera_inversionistas_estado_fn();rollback;');assert.equal(f5.habilitada,false);}
    return {actor:actor.perfil_id,rol:actor.rol_crm,habilitada:false};
  });
  bien('Reversa conserva 19 superficies con nuevas operaciones, coherencia y 24 cuentas apagadas');
  exito=true;
} finally {
  const recibo={estado:exito?'PASS':'FAIL',inicio,fin:new Date().toISOString(),banco:db,resultados,
    apertura,postflight,operaciones,retiro,estadosReversa,lecturas,auditoria_actores_antes:auditoriaAntes,
    superficies_antes:conservadas,superficies_conservadas_por_reversa:trasOperar,
    sha256:Object.fromEntries(['ACTIVAR.sql','REVERTIR.sql','POSTFLIGHT.sql','config.json','crear-sql.mjs','banco.mjs','ensayo.mjs','preparar-banco.mjs','operaciones-reversa.mjs','verificar-lecturas.sql']
      .map(f=>[f,createHash('sha256').update(leer(f)).digest('hex')])),
    limites:['Copia sintética SQL; no login Auth/HTTP ni navegador.',
      'UUID/roles del equipo con nombres y correos ficticios. No copia credenciales.',
      'Fixture anterior conserva dependencias inactivas; validadores reactivados antes del ensayo.',
      'Solo en fixtures se omite temporalmente trg_piloto_f8_control_00_validar para fijar revisión y fechas.',
      'Pruebas SQL de rol y capacidades; no sesión humana ni escritura productiva.',
      'No operaciones financieras de prueba en producción.']};
  writeFileSync(archivo,JSON.stringify(recibo,null,2)+'\n');
}
