import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {contenedor,como,leer,literal as q,rpc,sql} from './banco-local.mjs';
test('G5: edición concurrente de lead conserva lectura y bloquea solo nueva inversión',async()=>{
  const f=leer('fixtures.json'),e=leer('evidencia-flujo.json');
  const persona=sql(`select private.inversionista_canonica(${q(e.persona)})`);
  const lead=sql(`select id from crm.leads where private.inversionista_canonica(inversionista_id)=${q(persona)} limit 1`);
  assert.ok(lead);const token=await como('vendedor');
  const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
  const lock=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});
  const salida=once(lock,'exit');let stderr='';lock.stderr.on('data',x=>{stderr+=x});
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral')");
    const adquirido=new Promise((resolve,reject)=>{
      let text='';lock.stdout.on('data',x=>{text+=x;if(text.includes('LEAD_F5_BLOQUEADO')) resolve();});
      lock.once('exit',code=>{if(code!==null) reject(new Error(stderr||'El candado terminó antes de comprobarse'));});
    });
    lock.stdin.write(`begin;select id from crm.leads where id=${q(lead)} for update;select 'LEAD_F5_BLOQUEADO';\n`);
    await adquirido;
    const r=await rpc('inversionista_ficha_fn',{p_inversionista:persona},token);
    assert.equal(r.ok,true,JSON.stringify(r.data));assert.equal(r.data.persona.responsable_id,f.usuarios.vendedor.id);
    assert.equal(r.data.capacidades.nueva_inversion,false);assert.match(r.data.capacidades.motivo_no_operable,/actualización en curso/);
    assert.ok(r.data.inversiones_total>0);
  } finally {
    lock.stdin.end('rollback;\n\\q\n');await salida;
    for(const[nombre,activo]of Object.entries(flags)) sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);
  }
});
test('G5: diez comprobaciones de la misma ficha añaden a lo sumo un evento de acceso',async()=>{
  const e=leer('evidencia-flujo.json'),f=leer('fixtures.json');
  const persona=sql(`select private.inversionista_canonica(${q(e.persona)})`),token=await como('vendedor');
  const cuenta=()=>Number(sql(`select count(*) from crm.cartera_lecturas where actor_id=${q(f.usuarios.vendedor.id)} and inversionista_id=${q(persona)} and tipo='ficha'`));
  const antes=cuenta();
  for(let n=0;n<10;n++) {const r=await rpc('inversionista_ficha_fn',{p_inversionista:persona},token);assert.equal(r.ok,true);}
  assert.ok(cuenta()-antes<=1);
});
