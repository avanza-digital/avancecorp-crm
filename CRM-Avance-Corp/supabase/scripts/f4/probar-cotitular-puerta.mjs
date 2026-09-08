import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { sql as sqlOriginal, literal as q, leer } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';
const tablas=['public.contratos','public.contrato_titulares','public.cronograma_pagos','private.contrato_pdfs',
  'crm.inversiones','crm.inversion_titulares','auth.users','public.perfiles'];
const foto=`select jsonb_object_agg(tabla,huella) from (${tablas.map(t=>`select ${q(t)} tabla,
  private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')) huella from ${t} t`).join(' union all ')}) x`;
const original=sqlOriginal(foto),copia=crearCopiaSql('cotitular_puerta'),{sql,abrirSesion}=copia;
assert.equal(sql(foto),original);
const modulo=readFileSync(new URL('./09-cotitular-puerta.sql',import.meta.url),'utf8');
const funcionesSql=`select jsonb_object_agg(oid::regprocedure::text,md5(pg_get_functiondef(oid))) from pg_proc
  where oid in ('public._sync_contrato_titulares(uuid,jsonb)'::regprocedure,
    'public.crear_contrato(jsonb,jsonb)'::regprocedure,'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure)`;
const cuerpos=JSON.parse(sql(funcionesSql)),pruebas=[];
const f=leer('fixtures.json');
const contratoBase=sql("select id from public.contratos where numero_contrato='F4-BASE-INICIAL'");
const perfil=sql(`select cliente_id from public.contratos where id=${q(contratoBase)}`);
const datos=contratoPrueba(perfil,f.usuarios.vendedor.id,{inicio:'2026-09-01'});
const titular={nombre_completo:'COTITULAR FICTICIO PUERTA',tipo_documento:'DNI',documento:'98765432'};
datos.contrato.titulares=[titular];
const claims=q(JSON.stringify({sub:f.usuarios.gerencia.id,role:'authenticated'}));
const como=sentencia=>sql(`begin;set local request.jwt.claims=${claims};set local role authenticated;${sentencia};commit;`);
async function rechazar(rol,consulta,patron){
 const s=abrirSesion('f4_cotitular_negativo');s.enviar('\\set VERBOSITY verbose');
 s.enviar(`begin;set local request.jwt.claims='{}';set local role ${rol};${consulta};`);
 const r=await s.cerrar('rollback;');assert.notEqual(r.codigo,0);assert.match(r.error,patron);return r;
}
try {
  sql(`begin;${modulo}commit;`);
  assert.deepEqual(JSON.parse(sql(funcionesSql)),cuerpos);
  for(const [nombre,preparacion] of [
    ['Grantee adicional impide dar por cerrado el auxiliar',
      'grant execute on function public._sync_contrato_titulares(uuid,jsonb) to crm_metricas_bridge;'],
    ['Ejecutor sin derecho a revocar no puede declarar éxito',
      'grant execute on function public._sync_contrato_titulares(uuid,jsonb) to anon,authenticated;set local role authenticated;'],
  ]){
    assert.throws(()=>sql(`begin;${preparacion}${modulo}commit;`),/conserva EXECUTE fuera de su propietario/);
    assert.equal(sql("select has_function_privilege('anon','public._sync_contrato_titulares(uuid,jsonb)','EXECUTE')"),'f');
    pruebas.push({nombre,postcondicionRechaza:true});
  }
  const fotoCerrada=sql(foto);
  for(const rol of ['anon','authenticated','service_role']){
    assert.equal(sql(`select has_function_privilege(${q(rol)},'public._sync_contrato_titulares(uuid,jsonb)','EXECUTE')`),'f');
    await rechazar(rol,`select public._sync_contrato_titulares(${q(contratoBase)},${q(JSON.stringify([titular]))})`,/42501:[\s\S]*_sync_contrato_titulares/);
    pruebas.push({nombre:`Llamada directa ${rol} rechazada`,sqlstate:'42501'});
  }
  assert.equal(sql(foto),fotoCerrada,'Los rechazos no cambian las fuentes');
  const r=JSON.parse(como(`select public.crear_contrato(${q(JSON.stringify(datos.contrato))},${q(JSON.stringify(datos.cronograma))})`));
  assert(r.id);
  assert.equal(sql(`select count(*) from public.contrato_titulares where contrato_id=${q(r.id)}`),'1');
  assert.equal(sql(`select creado_por from public.contrato_titulares where contrato_id=${q(r.id)}`),f.usuarios.gerencia.id);
  pruebas.push({nombre:'Alta autorizada crea contrato y cotitular mediante helper interno',contrato:r.id});
  const payload=JSON.parse(sql(`select to_jsonb(c) from public.contratos c where id=${q(r.id)}`));
  payload.titulares=[{...titular,nombre_completo:'COTITULAR FICTICIO CORREGIDO'}];
  como(`select public.actualizar_contrato(${q(r.id)},${q(JSON.stringify(payload))},null)`);
  assert.equal(sql(`select nombre_completo from public.contrato_titulares where contrato_id=${q(r.id)}`),'COTITULAR FICTICIO CORREGIDO');
  assert.equal(sql(`select creado_por from public.contrato_titulares where contrato_id=${q(r.id)}`),f.usuarios.gerencia.id);
  pruebas.push({nombre:'Corrección autorizada conserva el circuito de titulares'});
  const antesRechazo=sql(foto);
  await rechazar('anon',`select public.actualizar_contrato(${q(r.id)},${q(JSON.stringify(payload))},null)`,/42501/);
  await rechazar('anon',`select public.crear_contrato(${q(JSON.stringify(datos.contrato))},${q(JSON.stringify(datos.cronograma))})`,/42501/);
  assert.equal(sql(foto),antesRechazo);
  pruebas.push({nombre:'Puertas canónicas rechazan usuario sin sesión, sin efectos'});
  const congelado=sql("select id from public.contratos where numero_contrato='F4-BASE-UPGRADE-ELEGIBLE'");
  const cerrado=JSON.parse(sql(`select to_jsonb(c) from public.contratos c where id=${q(congelado)}`));cerrado.titulares=[titular];
  const s=abrirSesion('f4_cotitular_pdf');s.enviar('\\set VERBOSITY verbose');
  s.enviar(`begin;set local request.jwt.claims=${claims};set local role authenticated;
    select public.actualizar_contrato(${q(congelado)},${q(JSON.stringify(cerrado))},null);`);
  const neg=await s.cerrar('rollback;');assert.notEqual(neg.codigo,0);assert.match(neg.error,/55000/);
  assert.equal(sql(foto),antesRechazo);
  pruebas.push({nombre:'La congelación documental sigue impidiendo modificar cotitulares'});
  assert.deepEqual(JSON.parse(sql(funcionesSql)),cuerpos);
} finally {assert.equal(sqlOriginal(foto),original,'Banco original sin cambios');}
writeFileSync(new URL(`../evidencia-f4/cotitular-puerta-${copia.id}.json`,import.meta.url),JSON.stringify({
  entorno,baseCopia:copia.nombre,terminadoEn:new Date().toISOString(),pruebas,
  cuerposSinModificar:cuerpos,sha256Modulo:createHash('sha256').update(modulo).digest('hex'),
  sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
  bancoOriginalSinCambios:true,produccionModificada:false,
  limite:'Cierre ACL del auxiliar y llamadas SQL con roles/claims sintéticos; no vincula cotitulares neutrales ni cambia el PDF.',
},null,2)+'\n',{flag:'wx'});
console.log(`Cotitularidad: ${pruebas.length} grupos de puerta conformes.`);
