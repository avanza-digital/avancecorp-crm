// Dos conexiones reales: comprobar espera por pg_locks, no por una pausa fija.
// Solo el banco local cerrado de F5. No recibe destinos del entorno.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {setTimeout as pausa} from 'node:timers/promises';
import {contenedor,leer,sql,literal as q} from './banco-local.mjs';

function conexion(nombre){
 const p=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{stdio:'pipe'});
 let salida='',error='';
 p.stdout.on('data',b=>{salida+=b});p.stderr.on('data',b=>{error+=b});
 const termina=new Promise((resolve,reject)=>{p.on('error',reject);p.on('close',codigo=>resolve({codigo,salida,error}))});
 p.stdin.write(`set application_name=${q(nombre)};\n`);
 return {p,termina,salida:()=>salida};
}
async function hasta(condicion,mensaje){
 const fin=Date.now()+3000;
 while(Date.now()<fin){if(condicion())return;await pausa(40)}
 assert.fail(mensaje);
}
function sujeto(actor){return `set local request.jwt.claims=${q(JSON.stringify({sub:actor,role:'authenticated'}))}; set local role authenticated;`}

test('D-19 F5: capacidad serializada con el cambio de modo',async t=>{
 const f=leer('fixtures.json');
 const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
 const miembro=f.usuarios.ajeno.id;
 const activo=sql(`select activo from crm.equipo where perfil_id=${q(miembro)}`)==='t';
 try {
  sql("update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas'; update crm.multiempresa_flags set activo=false where nombre='ficha_360_neutral';");
  await t.test('la consulta espera al apagado y devuelve su estado confirmado',async()=>{
   sql("update crm.multiempresa_flags set activo=true where nombre='ficha_360_neutral'");
   const nombre=`f5_lector_${randomUUID()}`;
   const escritor=conexion(`f5_escritor_${randomUUID()}`);let lector;
   try {
    escritor.p.stdin.write("begin; update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas'; select 'F5_LISTO';\n");
    await hasta(()=>escritor.salida().includes('F5_LISTO'),'El escritor no obtuvo su bloqueo');
    lector=conexion(nombre);
    lector.p.stdin.end(`begin; ${sujeto(f.usuarios.gerencia.id)} select crm.cartera_inversionistas_estado_fn(); commit;\n`);
    await hasta(()=>sql(`select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid
      where a.application_name=${q(nombre)} and l.locktype='advisory' and l.mode='ShareLock' and not l.granted)`)==='t',
     'La consulta devolvió una respuesta sin esperar al cambio de modo');
    escritor.p.stdin.end('commit;\n');assert.equal((await escritor.termina).codigo,0);
    const r=await lector.termina;assert.equal(r.codigo,0,r.error);
    const estado=JSON.parse(r.salida.trim());assert.equal(estado.habilitada,false);assert.equal(estado.escritura_habilitada,false);
    assert.equal(estado.motivo,'La cartera multiempresa aún no está habilitada');
   } finally {
    if(!escritor.p.stdin.writableEnded)escritor.p.stdin.end('rollback;\n');
    await escritor.termina;if(lector)await lector.termina;
    sql("update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas'");
    sql("update crm.multiempresa_flags set activo=false where nombre='ficha_360_neutral'");
   }
  });
  await t.test('una baja durante la espera invalida la autorización inicial',async()=>{
   const nombre=`f5_revocado_${randomUUID()}`;
   const escritor=conexion(`f5_baja_${randomUUID()}`);let lector;
   try {
    escritor.p.stdin.write("begin; select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas')); select 'F5_LISTO';\n");
    await hasta(()=>escritor.salida().includes('F5_LISTO'),'No se obtuvo el bloqueo de prueba');
    lector=conexion(nombre);
    lector.p.stdin.end(`\\set VERBOSITY verbose\nbegin; ${sujeto(miembro)} select crm.cartera_inversionistas_estado_fn(); commit;\n`);
    await hasta(()=>sql(`select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid
      where a.application_name=${q(nombre)} and l.locktype='advisory' and l.mode='ShareLock' and not l.granted)`)==='t',
     'El lector no esperó antes de comprobar de nuevo su membresía');
    escritor.p.stdin.end(`alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
      update crm.equipo set activo=false where perfil_id=${q(miembro)};
      alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia; commit;\n`);
    const w=await escritor.termina;assert.equal(w.codigo,0,w.error);
    const r=await lector.termina;assert.notEqual(r.codigo,0);assert.match(r.error,/42501/);
   } finally {
    if(!escritor.p.stdin.writableEnded)escritor.p.stdin.end('rollback;\n');
    await escritor.termina;if(lector)await lector.termina;
    sql(`update crm.equipo set activo=${activo} where perfil_id=${q(miembro)}`);
   }
  });
  await t.test('rechaza snapshots de REPEATABLE READ aunque F5 esté apagada',()=>{
   sql(`begin isolation level repeatable read; ${sujeto(f.usuarios.gerencia.id)}
    do $prueba$ begin
      perform crm.cartera_inversionistas_estado_fn();
      raise exception 'Se aceptó un snapshot anterior al cambio de modo';
    exception when sqlstate '0A000' then null; end $prueba$; rollback;`);
  });
  await t.test('censo D-19 en cero, bloqueo limitado y mismos permisos',()=>{
   assert.equal(sql(`select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('crm','private','public') and strpos(p.prosrc,'resolver_en_puertas')>0
      and strpos(p.prosrc,'crm_flag_resolver_en_puertas')=0 and strpos(p.prosrc,'resolver_en_puertas_bajo_candado')=0`),'0');
   assert.equal(sql(`select (p.provolatile='v' and p.proconfig @> array['search_path=""','lock_timeout=5s'])
    from pg_proc p where p.oid='crm.cartera_inversionistas_estado_fn()'::regprocedure`),'t');
   assert.equal(sql("select has_function_privilege('anon','crm.cartera_inversionistas_estado_fn()','execute')"),'f');
   assert.equal(sql("select has_function_privilege('authenticated','crm.cartera_inversionistas_estado_fn()','execute')"),'t');
  });
 } finally {
  for(const [nombre,valor] of Object.entries(flags))sql(`update crm.multiempresa_flags set activo=${valor} where nombre=${q(nombre)}`);
 }
});
