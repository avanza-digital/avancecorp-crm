// Estrés sintético posterior a la matriz: más leads/actividades que el total
// activo medido, concentrado en menos analistas y en el mismo día.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {carpeta,sql,objeto,http} from './banco.mjs';
import {USER_BY_KEY} from '../../fixtures.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.equal(JSON.parse(readFileSync(`${carpeta}/matriz-candidato.json`,'utf8')).estado,'PASS');
assert.equal(existsSync(`${carpeta}/carga.json`),false);
const preparado=sql("select count(*) from crm.leads where nombre_completo like 'CARGA GESTION DIARIA %'");
assert.ok(['0','2200'].includes(preparado),'Carga parcial inesperada');
if(preparado==='0')sql(`begin;
select set_config('request.jwt.claim.sub',(select id::text from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe'),true);
do $semilla$ declare ids uuid[]; r jsonb; i integer; begin
 select array_agg(perfil_id order by perfil_id) into ids from crm.equipo
 where activo and private.rol_crm(perfil_id)='vendedor';
 if cardinality(ids)<4 then raise exception 'Faltan vendedores activos'; end if;
 for i in 1..2200 loop
  r:=crm.crear_lead_si_disponible(p_nombre_completo=>'CARGA GESTION DIARIA '||i,
   p_telefono=>'+51970'||lpad(i::text,6,'0'),p_origen=>'oficina',p_monto_estimado=>25000,
   p_moneda=>'PEN',p_vendedor_id=>ids[1+(i-1)%cardinality(ids)],p_nota=>'SOLO FIXTURE DE CARGA');
  if r->>'estado'<>'creado' then raise exception 'Fixture de carga no creado: %',i; end if;
 end loop;
end $semilla$;
-- Inserción interna de fixtures: no desactiva triggers ni altera código.
select set_config('request.jwt.claim.sub','',true);
insert into crm.actividades(lead_id,tipo,detalle,creado_por)
 select l.id,'llamada_no_contestada','SOLO FIXTURE DE CARGA',l.vendedor_id
 from crm.leads l cross join generate_series(1,7) n
 where nombre_completo like 'CARGA GESTION DIARIA %';
do $conteo$ begin
 if (select count(*) from crm.leads where nombre_completo like 'CARGA GESTION DIARIA %')<>2200
 or (select count(*) from crm.actividades where detalle='SOLO FIXTURE DE CARGA')<>15400 then
 raise exception 'Volumen incompleto'; end if;
end $conteo$; commit;`);
sql('analyze crm.leads; analyze crm.actividades; analyze crm.lead_asignaciones;');
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
const sesiones={};
for(const key of ['gerencia','sup1','sup2']){
 const r=await http('/auth/v1/token?grant_type=password',{body:{email:USER_BY_KEY[key].email,password}});
 assert.equal(r.status,200,`Auth ${key}`);sesiones[key]=r.data.access_token;
}
const rpc=(nombre,key,body={})=>http('/rest/v1/rpc/'+nombre,{token:sesiones[key],body});
const inicial=await rpc('configuracion_sla_v2_fn','gerencia');assert.equal(inicial.status,200);
const modoInicial=objeto("select to_jsonb(c) from crm.sla_operacion_control c where id");
const mediciones=[];
try{
 for(const modo of ['legado','activo']){
  // La matriz ya ensayó la publicación de reglas; si aún falta, prepararla en
  // el banco con la misma puerta antes de activar su modo de operación.
  const vigente=sql('select exists(select 1 from private.sla_politica_operativa(statement_timestamp()))');
  if(modo==='activo'&&vigente!=='t'){
   const version=Number(sql('select max(version) from crm.sla_politicas'));
   const r=await rpc('publicar_reglas_sla_aprobadas_v2','gerencia',{p_expected_version:version});
   assert.equal(r.status,200,'Reglas SLA de fixture');
  }
  const control=objeto('select to_jsonb(c) from crm.sla_operacion_control c where id');
  if(control.modo!==modo){
   const r=await rpc('cambiar_modo_sla_operacion','gerencia',{p_expected_revision:control.revision,p_modo:modo});
   assert.equal(r.status,200,'Modo SLA de fixture');
  }
  for(const key of ['sup1','sup2']){
   const tiempos=[];let miembros=0,bytes=0;
   for(let i=0;i<30;i++){
    const inicio=performance.now();const r=await rpc('gestion_diaria_avisos_fn',key);
    tiempos.push(Math.round(performance.now()-inicio));assert.equal(r.status,200,`GET ${key} ${modo}`);
    assert.equal(r.data.diarias.modo_sla,modo);assert.equal(r.data.estado_cortes,'desactivados');
    miembros=r.data.contexto.equipo.length;bytes=Buffer.byteLength(JSON.stringify(r.data));
   }
   const orden=[...tiempos].sort((a,b)=>a-b);
   const resumen={modo,actor:key,n:tiempos.length,miembros,bytes,
    primera_ms:tiempos[0],p50_ms:orden[14],p95_ms:orden[28],max_ms:orden[29]};
   mediciones.push({...resumen,tiempos});console.log(JSON.stringify(resumen));
  }
 }
}finally{
 const c=objeto('select to_jsonb(c) from crm.sla_operacion_control c where id');
 if(c.modo!==modoInicial.modo){
  const r=await rpc('cambiar_modo_sla_operacion','gerencia',{p_expected_revision:c.revision,p_modo:modoInicial.modo});
  assert.equal(r.status,200,'Restituir modo SLA');
 }
}
sql('select private.assert_gestion_diaria(); select private.assert_sla_nucleo(); select private.assert_sla_operacion();');
writeFileSync(`${carpeta}/carga.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
 fixture:{leads_agregados:2200,actividades_agregadas:15400},mediciones,
 limites:'Estrés sintético remoto: no equivale a p95 de usuarios reales. Datos conservados hasta eliminar rama.'},null,2)+'\n',{mode:0o600});
