import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createClient} from '@supabase/supabase-js';
import {carpeta,sql,cfg} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.ok(existsSync(`${carpeta}/reconstruccion.json`));
const datos=JSON.parse(readFileSync(`${carpeta}/produccion-controles.json`)).rows[0].controles;
Object.assign(datos,JSON.parse(readFileSync(`${carpeta}/produccion-extras.json`)).rows[0].extras.controles);
const excluir=['crm.productos_inversion','crm.producto_versiones','crm.producto_condiciones',
 'crm.control_citas_versiones','crm.control_citas_aplicaciones'];
const citar=x=>"'"+String(x).replaceAll("'","''")+"'";
const archivo=`${carpeta}/credenciales-fixtures.json`;
if(!existsSync(archivo))writeFileSync(archivo,JSON.stringify({password:randomBytes(24).toString('base64url')}),{mode:0o600,flag:'wx'});
const password=JSON.parse(readFileSync(archivo)).password;
const admin=createClient(cfg.SUPABASE_URL,cfg.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
// El esquema no transporta filas de storage.buckets. El gate carga comprobantes
// sintéticos por la API real y necesita este bucket privado antes de comenzar.
const {data:buckets,error:errBuckets}=await admin.storage.listBuckets();assert.ifError(errBuckets);
if(!buckets.some(b=>b.id==='f4-comprobantes')){
 const {error}=await admin.storage.createBucket('f4-comprobantes',{public:false,fileSizeLimit:10485760,allowedMimeTypes:['application/pdf','image/jpeg','image/png']});assert.ifError(error);
}
const {data:lista,error:errLista}=await admin.auth.admin.listUsers();assert.ifError(errLista);
assert.ok(lista.users.every(u=>u.email?.endsWith('@demo.avancecorp.pe')));
let actor=lista.users.find(u=>u.email==='gerencia.crm@demo.avancecorp.pe')?.id;
if(!actor){const {data,error}=await admin.auth.admin.createUser({email:'gerencia.crm@demo.avancecorp.pe',password,email_confirm:true});assert.ifError(error);actor=data.user.id;}
assert.match(actor,/^[a-f0-9-]{36}$/);
const {error:errPerfil}=await admin.from('perfiles').upsert({id:actor,activo:true,correo:'gerencia.crm@demo.avancecorp.pe',nombre_completo:'GERENCIA DEMO',rol:'comercial',tipo_documento:'DNI',dni:'99001000',telefono:'999001000'});assert.ifError(errPerfil);
if(!existsSync(`${carpeta}/controles-cargados.json`)){
 const sentencias=[];
 for(const [tabla,filas] of Object.entries(datos)){
  if(excluir.includes(tabla))continue;
  assert.match(tabla,/^(crm|private)\.[a-z_][a-z_0-9]+$/);
  // Autores de configuración no se copian como identidades reales.
  const limpio=filas.map(f=>Object.fromEntries(Object.entries(f).map(([k,v])=>[k,k.endsWith('_por')&&v!==null?actor:v])));
  sentencias.push(`insert into ${tabla} select * from jsonb_populate_recordset(null::${tabla},${citar(JSON.stringify(limpio))}::jsonb);`);
 }
 sql(`begin; set local session_replication_role=replica; ${sentencias.join('\n')} set local session_replication_role=origin;
 insert into crm.empresas(clave,nombre_legal,nombre_visible,monedas,crea_contrato_avance,requiere_portal,exige_numero_transaccion,fuente_capital)
 values ('avance','Avance prueba','Avance prueba',array['PEN','USD'],true,true,false,'contratos'),
 ('qorilazo','Qorilazo prueba','Qorilazo prueba',array['PEN'],false,false,true,'cierres_externos'),
 ('prodelco','Prodelco prueba','Prodelco prueba',array['PEN','USD'],false,false,true,'cierres_externos');
 insert into crm.productos_inversion(codigo,estado,es_legacy,permite_altas_legacy,archivado_en)
 values('HISTORICO-SIN-CATALOGO','archivado',true,true,now());
 commit;`);
 writeFileSync(`${carpeta}/controles-cargados.json`,JSON.stringify({estado:'PASS',tablas:sentencias.length}),{mode:0o600});
}
const env={...process.env,SUPABASE_URL:cfg.SUPABASE_URL,SUPABASE_ANON_KEY:cfg.SUPABASE_ANON_KEY,
 SUPABASE_SERVICE_ROLE_KEY:cfg.SUPABASE_SERVICE_ROLE_KEY,CRM_DEMO_PASSWORD:password};
const previo=sql("select has_table_privilege('service_role','crm.periodos_cerrados','SELECT')")==='t';
let r;
try{
 if(!previo)sql('grant select on crm.periodos_cerrados to service_role');
 r=spawnSync(process.execPath,[fileURLToPath(new URL('../../seed-demo.mjs',import.meta.url))],{env,encoding:'utf8',maxBuffer:8*1024*1024,timeout:240000});
}finally{if(!previo)sql('revoke select on crm.periodos_cerrados from service_role');}
console.log(r.stdout??'');
if(r.status!==0){console.error(r.stderr??'Seed interrumpido');process.exitCode=1;}
else{
 sql(`begin;
 alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
 update crm.equipo set activo=false where perfil_id=(select id from public.perfiles where correo='vend-inactivo.crm@demo.avancecorp.pe');
 alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
 commit;`);
 const sentencias=['crm.control_citas_versiones','crm.control_citas_aplicaciones'].map(tabla=>{
  const filas=datos[tabla].map(f=>Object.fromEntries(Object.entries(f).map(([k,v])=>[k,k.endsWith('_por')?actor:v])));
  return `insert into ${tabla} select * from jsonb_populate_recordset(null::${tabla},${citar(JSON.stringify(filas))}::jsonb) on conflict do nothing;`;
 });
 sql(`begin; set local session_replication_role=replica; ${sentencias.join('\n')} set local session_replication_role=origin; commit;`);
 console.log('PASS: controles técnicos y cuentas/negocio exclusivamente sintéticos; permisos temporales restaurados.');
}
