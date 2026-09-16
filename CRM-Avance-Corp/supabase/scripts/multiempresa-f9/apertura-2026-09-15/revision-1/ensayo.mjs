// Ensaya ACTIVAR/REVERTIR literales, concurrencia y abortos en la copia F9.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {db,args,sql,objeto,ejecutar,q} from './banco.mjs';
const leer=f=>readFileSync(new URL(f,import.meta.url),'utf8');
const activar=leer('ACTIVAR.sql'),revertir=leer('REVERTIR.sql'),cfg=JSON.parse(leer('config.json'));
const resultados=[],inicio=new Date().toISOString(),archivo=new URL('ensayo.json',import.meta.url);
writeFileSync(archivo,JSON.stringify({estado:'RUNNING',inicio,banco:db}));
const tablas=['public.contratos','public.cronograma_pagos','private.contrato_pdfs','crm.cierres_externos',
  'crm.inversiones','crm.inversion_titulares','crm.inversion_solicitudes','crm.depositos_reclamados',
  'crm.inversion_eventos','crm.inversionistas','crm.inversionista_gestiones','crm.tareas','crm.leads',
  'crm.periodos_cerrados','crm.cierre_mes_vendedor','auth.users','public.perfiles'];
const hechos=()=>objeto('select jsonb_build_object('+tablas.map(t=>`${q(t)},(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text)::text,'')) from ${t} x)`).join(',')+')');
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
  assert.notEqual(r.status,0);assert(r.stderr.includes(codigo),r.stderr);
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
let exito=false,conservadas,apertura;
try {
  assert.equal(sql('select current_database()'),db);piloto();
  conservadas=hechos();
  // Inyección del fallo justo después de apagar F8 y antes de encender flags.
  const roto=activar.replace('  update crm.multiempresa_flags set activo=true',
    "  raise exception 'Interrupción deliberada' using errcode='P0409';\n  update crm.multiempresa_flags set activo=true");
  assert.notEqual(roto,activar);denegado('P0409',roto);bien('Fallo intermedio revierte piloto y banderas completos');
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
  const vence=activar.replace(cfg.vence_sql,'2000-01-01T00:00:00.000Z');assert.notEqual(vence,activar);
  denegado('P0409',vence);bien('Captura vencida aborta apertura');
  const ocupado=sesion("begin;select pg_advisory_xact_lock_shared(hashtext('crm_flag_resolver_en_puertas'));select 'F9_OCUPADO';\n");
  try {await esperar(()=>ocupado.salida().includes('F9_OCUPADO'));denegado('55P03');}
  finally {ocupado.p.stdin.end('rollback;\n');assert.equal((await ocupado.fin).status,0);}
  bien('Operación en curso bloquea y aborta sin estado parcial');
  const antes=estado();
  const fragmento=activar.replace(/commit;\s*$/, "select 'F9_SIN_COMMIT';\n");assert.notEqual(fragmento,activar);
  const pendiente=sesion(fragmento);
  try {
    await esperar(()=>pendiente.salida().includes('F9_SIN_COMMIT'));
    assert.deepEqual(estado(),antes,'Se vio estado intermedio desde otra conexión');
    pendiente.p.stdin.end('commit;\n');const r=await pendiente.fin;assert.equal(r.status,0,r.err);
    apertura=JSON.parse(r.out.split('\n').find(x=>x.startsWith('{')));
  } finally {if(!pendiente.p.stdin.writableEnded)pendiente.p.stdin.end('rollback;\n');await pendiente.fin;}
  assert.equal(apertura.estado,'PASS');assert.equal(apertura.roles.length,24);
  assert.equal(apertura.roles.filter(r=>r.rol==='vendedor'&&r.cartera.escritura_habilitada).length,18);
  assert.equal(estado().control.activo,false);assert.deepEqual(hechos(),conservadas);
  bien('COMMIT atómico habilita 23 gestores y conserva exclusión de Coordinación');
  denegado('P0409');bien('Segunda activación no sobrescribe el estado ya abierto');
  const vuelta=objeto(revertir);assert.equal(vuelta.estado,'PASS');
  assert.deepEqual(vuelta.banderas,{resolver_en_puertas:true,inversiones_escritura:false,ficha_360_neutral:false,postventa_neutral:false,metricas_multiempresa_sombra:false});
  assert.equal(estado().control.activo,false);assert.deepEqual(hechos(),conservadas);
  bien('Reversa exacta apaga capacidades y conserva 17 superficies');
  exito=true;
} finally {
  const recibo={estado:exito?'PASS':'FAIL',inicio,fin:new Date().toISOString(),banco:db,resultados,
    apertura,superficies_conservadas:conservadas,
    sha256:Object.fromEntries(['ACTIVAR.sql','REVERTIR.sql','config.json','crear-sql.mjs','banco.mjs','ensayo.mjs','preparar-banco.mjs']
      .map(f=>[f,createHash('sha256').update(leer(f)).digest('hex')])),
    limites:['Copia sintética SQL; no login Auth/HTTP ni navegador.',
      'UUID/roles del equipo con nombres y correos ficticios. No copia credenciales.',
      'Fixture anterior conserva dependencias inactivas; validadores reactivados antes del ensayo.',
      'No operaciones financieras de prueba en producción.']};
  writeFileSync(archivo,JSON.stringify(recibo,null,2)+'\n');
}
