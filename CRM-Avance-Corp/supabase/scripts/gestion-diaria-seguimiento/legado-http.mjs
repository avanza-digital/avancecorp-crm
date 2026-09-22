// Compatibilidad del libro anterior con miembros SLA (ids de lead).
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { carpeta, apiUrl, sql, credencialesLocales } from '../gestion-diaria-cortes/http/banco.mjs';
import { USER_BY_KEY } from '../fixtures.mjs';
import { aplicarReconocimientos } from '../../../app/src/lib/reconocimientos-alertas.ts';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const c=credencialesLocales();
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
async function request(path,token,body,method='POST') {
  const r=await fetch(`${apiUrl}${path}`,{method,redirect:'error',signal:AbortSignal.timeout(30_000),
    headers:{apikey:c.ANON_KEY,Authorization:`Bearer ${token??c.ANON_KEY}`,'Content-Type':'application/json',
      'Accept-Profile':'crm','Content-Profile':'crm'},...(body===undefined?{}:{body:JSON.stringify(body)})});
  const texto=await r.text();
  return {status:r.status,data:texto?JSON.parse(texto):null};
}
async function login(key) {
  const r=await request('/auth/v1/token?grant_type=password',null,{email:USER_BY_KEY[key].email,password});
  assert.equal(r.status,200);return r.data;
}
const gerente=await login('gerencia');
const rpc=(name,token,body={})=>request(`/rest/v1/rpc/${name}`,token,body);
const modoAnterior=sql('select modo from crm.sla_operacion_control where id');
let estado='FAIL';
const evidencia=[];
try {
  if(sql('select count(*) from private.sla_politica_operativa(statement_timestamp())')==='0') {
    const r=await rpc('publicar_reglas_sla_aprobadas_v2',gerente.access_token,
      {p_expected_version:Number(sql('select max(version) from crm.sla_politicas'))});
    assert.equal(r.status,200);
  }
  if(modoAnterior!=='activo') {
    const r=await rpc('cambiar_modo_sla_operacion',gerente.access_token,
      {p_expected_revision:Number(sql('select revision from crm.sla_operacion_control where id')),p_modo:'activo'});
    assert.equal(r.status,200);
  }
  for(const [key,accion] of [['sup1','reconocer'],['sup2','posponer']]) {
    const primera=await login(key),segunda=await login(key);
    assert.ok(primera.session_id!==segunda.session_id || primera.access_token!==segunda.access_token,'Sesiones distintas');
    const r=await rpc('gestion_diaria_avisos_fn',primera.access_token);assert.equal(r.status,200);
    const grupo=r.data.diarias.alertas.find(g=>g.tipo==='tarea_vencida');
    assert.ok(grupo&&grupo.miembros.length>0,`SLA no vacío para ${key}`);
    const hasta=accion==='posponer'?new Date(Date.now()+3_600_000).toISOString():null;
    const guardado=await request('/rest/v1/alertas_reconocimientos',primera.access_token,{
      perfil_id:primera.user.id,alerta_id:grupo.id,accion,miembros:grupo.miembros,severidad:grupo.severidad,hasta});
    assert.equal(guardado.status,201,`POST real ${accion}`);
    const libro=await request('/rest/v1/alertas_reconocimientos_vigentes?select=id,alerta_id,accion,miembros,severidad,hasta,creado_en,secuencia',segunda.access_token,undefined,'GET');
    assert.equal(libro.status,200);
    const grupos=[{...grupo,miembros:grupo.miembros}];
    const aplicado=aplicarReconocimientos(grupos,libro.data,Date.now());
    assert.equal(aplicado.pendientes,0,'Campana descuenta el grupo confirmado');
    if(accion==='reconocer') assert.equal(aplicado.visibles[0]?.reconocimiento?.accion,'reconocer','Lista atenúa');
    else {assert.equal(aplicado.visibles.length,0);assert.equal(aplicado.pospuestas,1);}
    evidencia.push(`${key}: ${accion}, POST Auth real y segunda sesión con lógica canónica lista/campana`);
  }
  const hijo=spawn(process.execPath,[fileURLToPath(new URL('./navegador.mjs',import.meta.url)),
    '--solo-banco-autorizado','--solo-alertas'],{stdio:'inherit'});
  assert.equal(await new Promise(resolve=>hijo.on('close',resolve)),0,'Interfaz real del libro SLA');
  estado='PASS';
} finally {
  if(sql('select modo from crm.sla_operacion_control where id')!==modoAnterior) {
    const r=await rpc('cambiar_modo_sla_operacion',gerente.access_token,
      {p_expected_revision:Number(sql('select revision from crm.sla_operacion_control where id')),p_modo:modoAnterior});
    assert.equal(r.status,200,'Restituir modo anterior por API');
  }
  sql('select private.assert_gestion_diaria()');
  writeFileSync(`${carpeta}/gd-f4-legado-http.json`,JSON.stringify({estado,fecha:new Date().toISOString(),
    evidencia,modoInicial:modoAnterior,modoFinal:sql('select modo from crm.sla_operacion_control where id'),historiaConservada:true},null,2)+'\n',{mode:0o600});
}
console.log('PASS: ids de lead compatibles, reconocer/posponer compartidos, lista/campana y navegador real');
