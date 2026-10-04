// Sesiones reales del seed de banco. Solo lecturas; nunca producción.
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { USERS, LEADS, PRODUCTION_PROJECT_REF } from '../fixtures.mjs';
const { SUPABASE_URL:url, SUPABASE_ANON_KEY:anon, SUPABASE_SERVICE_ROLE_KEY:service, CRM_DEMO_PASSWORD:password }=process.env;
assert(url && anon && service && password,'Falta entorno del banco');
assert(!url.includes(PRODUCTION_PROJECT_REF),'Prohibido ejecutar contra producción');
const options={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const ids=LEADS.map(l=>l.id);
let casos=0;
for(const usuario of USERS){
 const cliente=createClient(url,anon,options);
 const login=await cliente.auth.signInWithPassword({email:usuario.email,password});
 assert.equal(login.error,null,`Login ${usuario.key}`);
 const {data,error}=await cliente.schema('crm').rpc('gestion_vigente_fn',{p_lead_ids:ids});
 if(!usuario.portalActive || usuario.portalRole==='cliente'){
  assert.equal(error?.code,'42501',`Deniega ${usuario.key}`);casos++;continue;
 }
 assert.equal(error,null,usuario.key);assert.equal(data.version,1);
 const pagina=await cliente.schema('crm').rpc('cartera_filtrada_fn',{p_limite:200,p_etapa:'nuevo'});
 assert.equal(pagina.error,null,`Cartera ${usuario.key}`);
 const gestion=await cliente.schema('crm').rpc('cartera_filtrada_fn',{p_limite:200,p_etapa:'nuevo',p_gestion:'con_gestion'});
 assert.equal(gestion.error,null,`Filtro ${usuario.key}`);
 const visibles=pagina.data.items.filter(l=>ids.includes(l.id));
 assert.deepEqual(data.items.map(l=>l.lead_id).sort(),visibles.map(l=>l.id).sort(),`Ámbito ${usuario.key}`);
 const gestionados=new Set(gestion.data.items.map(l=>l.id));
 for(const l of data.items)assert.equal(l.gestion_vigente,gestionados.has(l.lead_id),`Regla ${usuario.key}`);
 console.log(`PASS HTTP ${usuario.key}: ámbito y filtro coinciden (${data.items.length})`);casos++;
 if(usuario.key==='gerencia'){
  for(const p_lead_ids of [null,[null],Array(101).fill(ids[0]),[[ids[0]],[ids[1]]]]){
   const r=await cliente.schema('crm').rpc('gestion_vigente_fn',{p_lead_ids});assert.equal(r.error?.code,'22023');casos++;
  }
  const vacio=await cliente.schema('crm').rpc('gestion_vigente_fn',{p_lead_ids:[]});assert.equal(vacio.error,null);assert.deepEqual(vacio.data,{version:1,items:[]});casos++;
  const cien=await cliente.schema('crm').rpc('gestion_vigente_fn',{p_lead_ids:Array(100).fill(ids[0])});assert.equal(cien.error,null);assert.equal(cien.data.items.length,1);casos++;
  const privado=await cliente.schema('private').rpc('gestion_vigente_lectura',{p_lead_ids:ids});assert.equal(privado.error?.code,'PGRST106','private no se expone por HTTP');casos++;
 }
 await cliente.auth.signOut({scope:'local'});
}
for(const [nombre,key] of [['anon',anon],['service_role',service]]){
 const r=await createClient(url,key,options).schema('crm').rpc('gestion_vigente_fn',{p_lead_ids:ids});
 assert.equal(r.error?.code,'42501',`ACL ${nombre}`);casos++;
}
console.log(`HTTP OK — ${casos} escenarios`);
