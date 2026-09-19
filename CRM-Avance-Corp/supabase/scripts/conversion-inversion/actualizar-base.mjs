// Integra las migraciones de Main en copias sintéticas propias. No escribe en
// la plantilla compartida ni admite un nombre de base o conexión externa.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {sql,q,db,baseDb} from './banco.mjs';
const migracion=nombre=>readFileSync(new URL(`../../migrations/${nombre}.sql`,import.meta.url),'utf8');
if(sql(`select count(*) from pg_database where datname=${q(baseDb)}`,'postgres')==='0'){
  sql(`create database ${baseDb} template prodelco_usd_20260917`,'postgres','supabase_admin');
}
for(const base of [baseDb,db]){
  if(sql(`select count(*) from pg_database where datname=${q(base)}`,'postgres')==='0')continue;
  if(sql("select position('observacion_sin_aprobacion' in pg_get_functiondef('crm.politica_rentabilidad_fn()'::regprocedure))",base)==='0')
    sql(migracion('20260918210543_crm_modo_rentabilidad_integral'),base);
  if(sql("select to_regprocedure('crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)') is null",base)==='t')
    sql(migracion('20260918213000_crm_entrevista_al_asistir'),base);
  assert.match(sql('select private.assert_entrevista_al_asistir()',base),/^OK:/);
}
const archivo=new URL('./baseline-funciones.json',import.meta.url);
const anterior=JSON.parse(readFileSync(archivo,'utf8'));
const firmas=anterior.map(f=>`${f.esquema}.${f.nombre}(${f.argumentos.split(', ').map(a=>a.split(' ').slice(1).join(' ')).join(',')})`);
const actual=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('esquema',n.nspname,'nombre',p.proname,
  'argumentos',pg_get_function_identity_arguments(p.oid),'huella',md5(pg_get_functiondef(p.oid)),
  'definicion',pg_get_functiondef(p.oid),'propietario',pg_get_userbyid(p.proowner),'permisos',p.proacl::text)
  order by n.nspname,p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.oid in (${firmas.map(f=>`${q(f)}::regprocedure`).join(',')})`,baseDb));
assert.equal(actual.length,16);
for(const f of actual){
  const previa=anterior.find(a=>a.esquema===f.esquema&&a.nombre===f.nombre);assert(previa);
  if(!['enlazar_tasa_lead','validar_tasa_conversion_lead'].includes(f.nombre))assert.equal(f.huella,previa.huella,f.nombre);
}
writeFileSync(archivo,JSON.stringify(actual,null,2)+'\n');
console.log('PASS: Main integrado en las dos copias propias; 14 anclas idénticas, dos anclas de tasas actualizadas.');
