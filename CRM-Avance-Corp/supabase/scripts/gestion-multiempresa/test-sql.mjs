import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const db='gestion_multiempresa_20260918',container='supabase_db_avancecorp-f5-bank';
const migration=new URL('../../migrations/20260916152851_crm_gestion_integral_multiempresa.sql',import.meta.url);
const rollback=new URL('./REVERTIR-20260916152851.sql',import.meta.url);
function sql(text,database=db,permitirError=false){
 const r=spawnSync('docker',['exec','-i',container,'psql','-X','-qAt','-U','supabase_admin','-d',database,'-v','ON_ERROR_STOP=1','-f','-'],{input:text,encoding:'utf8',maxBuffer:8*1024*1024});
 if(!permitirError)assert.equal(r.status,0,r.stderr);return r;
}
const salida=s=>sql(s).stdout.trim();
// Refuse to reuse a database: replay evidence is always from a fresh clone.
sql(`create database ${db} template rls_vigente_20260916;`,'postgres');
const publicSnapshot=()=>salida(`select md5(string_agg(pg_get_functiondef(oid),'|' order by oid)) from pg_proc where pronamespace='public'::regnamespace and prokind='f';`);
const firma=s=>salida(`select md5(prosrc)||'|'||pg_get_userbyid(proowner)||'|'||coalesce(proacl::text,'') from pg_proc where oid='${s}'::regprocedure`);
const lector='private.cartera_f5_personas_visibles(uuid)',cierre='crm.corregir_cierre_externo(uuid,numeric,text,text,text,text,date,text)';
const originales={lector:firma(lector),cierre:firma(cierre),public:publicSnapshot()};
const body=readFileSync(migration,'utf8');sql(body);
assert.equal(publicSnapshot(),originales.public);
assert.equal(salida("select has_table_privilege('authenticated','crm.inversionista_datos_contacto','select')"),'f');
assert.equal(salida("select has_function_privilege('anon','crm.inversionista_gestion_fn(uuid,uuid)','execute')"),'f');
const instalado={lector:firma(lector),cierre:firma(cierre)};
console.log('PASS replay limpio, funciones public intactas, tabla privada y RPC sin acceso anónimo');
// Several hundred current contacts, including identities with no investments:
// the complete list must retain all its original visibility conditions.
const rendimiento=sql(`begin;set local session_replication_role=replica;
  update crm.multiempresa_flags set activo=true;
  delete from crm.cierres_externos where inversionista_id is null;
  with nuevas as (insert into crm.inversionistas(id,creado_por,responsable_relacion_id)
    select gen_random_uuid(),'100b5ece-ab83-477d-bb26-3f5efdaff8f8','9913c862-e4bc-4a2d-98f9-983a669ac2d7' from generate_series(1,600) returning id)
  select array_agg(id) ids into temporary gestion_contactos_carga from nuevas;
  set local request.jwt.claims='{"sub":"100b5ece-ab83-477d-bb26-3f5efdaff8f8","role":"authenticated"}';
  select array_agg(inversionista_id order by inversionista_id) ids into temporary gestion_visibles_antes
    from private.cartera_f5_personas_visibles(null);
  insert into crm.inversionista_datos_contacto(inversionista_id,nombre_completo,actualizado_por)
    select id,'CONTACTO SINTÉTICO DE CARGA','100b5ece-ab83-477d-bb26-3f5efdaff8f8' from gestion_contactos_carga g cross join unnest(g.ids) id;
  set local session_replication_role=origin;
  set local request.jwt.claims='{"sub":"100b5ece-ab83-477d-bb26-3f5efdaff8f8","role":"authenticated"}';
  do $t$ begin
    assert (select ids from gestion_visibles_antes) is not distinct from
      (select array_agg(inversionista_id order by inversionista_id) from private.cartera_f5_personas_visibles(null)),
      'Los contactos no deben ampliar ni duplicar la visibilidad';
  end;$t$;
  explain (analyze,format json) select count(*) from private.cartera_f5_personas_visibles(null);
  rollback;`).stdout.trim();
const plan=JSON.parse(rendimiento)[0];assert(plan['Execution Time']<2000,JSON.stringify(plan));
console.log('PASS lector completo con 600 contactos sintéticos: '+plan['Execution Time']+' ms');
sql(readFileSync(rollback,'utf8'));
assert.equal(firma(lector),originales.lector);assert.equal(firma(cierre),originales.cierre);assert.equal(publicSnapshot(),originales.public);
assert.equal(salida("select has_function_privilege('authenticated','crm.inversionista_gestion_fn(uuid,uuid)','execute')"),'f');
assert.equal(salida("select to_regclass('crm.inversionista_datos_contacto') is not null"),'t');
console.log('PASS reversa restaura cuerpos/propietarios/ACL anteriores y conserva tabla y auditoría');
// Guard must fail atomically against an already altered reader.
const bad=sql(readFileSync(rollback,'utf8'),db,true);assert.notEqual(bad.status,0);
console.log('PASS guardas rechazan una reversa repetida o ajena');
writeFileSync(process.argv[2]??'/private/tmp/gestion-multiempresa-sql-evidencia.json',JSON.stringify({fecha:new Date().toISOString(),db,sha256:createHash('sha256').update(body).digest('hex'),originales,instalado,lector600ContactosMs:plan['Execution Time'],replay:'PASS',reversa:'PASS',guardas:'PASS'},null,2)+'\n');
