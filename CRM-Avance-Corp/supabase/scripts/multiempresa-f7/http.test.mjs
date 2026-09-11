// JWT emitidos por Auth local; PostgREST conectado EXCLUSIVAMENTE a la copia F7.
import test from 'node:test';
import assert from 'node:assert/strict';
import {como as autenticar} from '../f5/banco-local.mjs';
import {fixture,sql} from './banco-local.mjs';
import {verificarContrato} from './contrato-cliente.mjs';

async function rpc(nombre,payload,token) {
  const r=await fetch(`http://127.0.0.1:59431/rpc/${nombre}`,{method:'POST',
    headers:{'Content-Type':'application/json','Content-Profile':'crm',
      ...(token?{Authorization:`Bearer ${token}`}:{})},
    body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(20_000)});
  return {status:r.status,ok:r.ok,data:await r.json()};
}
test('F7 HTTP: Auth real local, permisos de roles y corte al apagar',async t=>{
  const flag=sql("select activo from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra'");
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre='metricas_multiempresa_sombra'");
    await t.test('anon no consulta cifras',async()=>{
      const r=await rpc('metricas_multiempresa_fn',{});assert.equal(r.ok,false);assert.equal(r.data.code,'42501');
    });
    for(const rol of Object.keys(fixture.usuarios)) {
      await t.test(rol==='gerencia'?'Gerencia obtiene el informe completo':`${rol} no obtiene la información`,async()=>{
        const token=await autenticar(rol),r=await rpc('metricas_multiempresa_fn',{p_mes:'2026-09-01'},token);
        if(rol==='gerencia') {
          assert.equal(r.ok,true,JSON.stringify(r.data));assert.equal(r.data.produccion.length,4);
          verificarContrato(r.data);
          assert.equal(r.data.fuentes_duplicadas,0);
          assert.ok(r.data.conciliacion.every(x=>x.diferencia_capital===0));
          sql("update crm.multiempresa_flags set activo=false where nombre='metricas_multiempresa_sombra'");
          assert.equal((await rpc('metricas_multiempresa_fn',{},token)).data.code,'P0409');
          assert.equal((await rpc('metricas_multiempresa_estado_fn',{},token)).data.habilitada,false);
          sql("update crm.multiempresa_flags set activo=true where nombre='metricas_multiempresa_sombra'");
        } else {assert.equal(r.ok,false);assert.equal(r.data.code,'42501');}
      });
    }
  } finally {sql(`update crm.multiempresa_flags set activo=${flag==='t'} where nombre='metricas_multiempresa_sombra'`);}
});
