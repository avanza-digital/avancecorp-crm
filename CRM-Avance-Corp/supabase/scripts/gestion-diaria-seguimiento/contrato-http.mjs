// Auth y REST reales, destino fijo del banco. Sin interceptar respuestas.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { carpeta, apiUrl, sql, credencialesLocales } from '../gestion-diaria-cortes/http/banco.mjs';
import { USER_BY_KEY } from '../fixtures.mjs';

assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado']);
const c = credencialesLocales();
const {password} = JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`, 'utf8'));
const resultados = [];
const sesiones = {};
async function peticion(ruta,token,body) {
  const r = await fetch(`${apiUrl}${ruta}`, {method:'POST',redirect:'error',signal:AbortSignal.timeout(30_000),
    headers:{apikey:c.ANON_KEY,Authorization:`Bearer ${token ?? c.ANON_KEY}`,
      'Content-Type':'application/json','Accept-Profile':'crm','Content-Profile':'crm'},body:JSON.stringify(body)});
  return {status:r.status,data:await r.json()};
}
for (const key of ['sup1','sup2','vend1','gerencia','coordinador','directorio']) {
  const r = await peticion('/auth/v1/token?grant_type=password',null,{email:USER_BY_KEY[key].email,password});
  assert.equal(r.status,200,`Auth real: ${key}`);
  sesiones[key]={token:r.data.access_token,id:r.data.user.id};
}
const rpc = (nombre,key,body={}) => peticion(`/rest/v1/rpc/${nombre}`,key?sesiones[key].token:null,body);
for (const key of Object.keys(sesiones)) {
  const r = await rpc('gestion_diaria_avisos_fn',key);
  if (key.startsWith('sup')) {
    assert.equal(r.status,200,`Avisos ${key}`);
    assert.equal(r.data.supervisor_id,sesiones[key].id);
    assert.equal(r.data.estado_cortes,'desactivados');
    assert.ok(r.data.contexto.equipo.length>=2,'No aceptar prueba vacía de ámbito');
    const equipo=await rpc('gestion_diaria_equipo_fn',key);
    assert.equal(equipo.status,200);
    assert.deepEqual(r.data.contexto.equipo.map(e=>e.analista_id).sort(),equipo.data.equipo.map(e=>e.analista_id).sort());
    resultados.push(`${key}: avisos OFF, contexto completo y paridad de ámbito`);
  } else {
    assert.equal(r.status,403,`Avisos denegados a ${key}`);
    assert.equal(r.data.code,'42501');
    resultados.push(`${key}: avisos denegados por servidor`);
  }
  const config=await rpc('configuracion_gestion_diaria_fn',key);
  if(['gerencia','directorio'].includes(key)) {
    assert.equal(config.status,200);
    assert.equal(config.data.puede_editar,key==='gerencia');
    assert.equal(config.data.vigente.configuracion.tasa_baja_diferencia_pp,null);
  } else { assert.equal(config.status,403); assert.equal(config.data.code,'42501'); }
}
const anon=await rpc('gestion_diaria_avisos_fn',null);
assert.ok([401,403].includes(anon.status));
for(const key of ['sup1','vend1','directorio']) {
  const r=await rpc('publicar_politica_gestion_diaria',key,{p_expected_version:1,
    p_vigente_desde:'2026-10-01T00:00:00-05:00',p_config:{},p_motivo:'No autorizado'});
  assert.equal(r.status,403,`Escritura gerencial denegada ${key}`);
  assert.equal(r.data.code,'42501');
}
const config=await rpc('configuracion_gestion_diaria_fn','gerencia');
const intento=await rpc('publicar_politica_gestion_diaria','gerencia',{
  p_expected_version:config.data.expected_version,p_vigente_desde:'2026-10-01T00:00:00-05:00',
  p_config:{...config.data.vigente.configuracion,tasa_baja_diferencia_pp:20},p_motivo:'Tasa reservada hasta F5'});
assert.equal(intento.status,400);
assert.equal(intento.data.code,'22023');
assert.match(intento.data.message,/F5/);
assert.equal(sql('select count(*)=1 and bool_and(version=1 and not cortes_activos) from crm.politica_gestion_diaria'),'t');
writeFileSync(`${carpeta}/gd-f4-http-permisos.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
  resultados,configuracion:'Solo gerencia escribe; directorio lee; tasa baja no activable; sin mutaciones'},null,2)+'\n',{mode:0o600});
console.log('PASS: Auth/HTTP real de seis roles, ámbito completo de dos equipos, anonimato denegado y tasa baja OFF hasta F5');
