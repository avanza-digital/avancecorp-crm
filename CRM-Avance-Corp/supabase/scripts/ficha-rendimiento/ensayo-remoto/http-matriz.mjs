import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
const dir='/private/tmp/avancecorp-ficha-optim-20260915/';
const modalidad=process.argv[3]||'piloto';assert.ok(['piloto','general'].includes(modalidad));
const fase=process.argv[2];assert.ok(['antes','despues'].includes(fase));
const cfg=JSON.parse(readFileSync(dir+'rama-privada.json','utf8'));
const url='https://tufxjboalbtekbszckcf.supabase.co';assert.equal(cfg.SUPABASE_URL,url);
const info=JSON.parse(readFileSync(dir+'http-fixture-info.json','utf8'));
const grupo=JSON.parse(readFileSync(dir+'http-miembros.json','utf8'));
const password=readFileSync(dir+'auth-fixture-password.txt','utf8');
const sesiones=existsSync(dir+'http-sesiones.json')?JSON.parse(readFileSync(dir+'http-sesiones.json','utf8')):{};const casos={};
async function pedir(path,{token,body,method='GET',schema}={}) {
 const headers={apikey:cfg.SUPABASE_ANON_KEY};
 if(token)headers.Authorization='Bearer '+token;
 if(body!==undefined)headers['Content-Type']='application/json';
 if(schema){headers['Accept-Profile']=schema;headers['Content-Profile']=schema;}
 const res=await fetch(url+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const texto=await res.text();let data;try{data=JSON.parse(texto)}catch{data=texto}
 return {status:res.status,body:data};
}
const rpc=(name,args,token)=>pedir('/rest/v1/rpc/'+name,{token,method:'POST',body:args,schema:'crm'});
for(const a of info.actores) {
 if(sesiones[a.id]) {
  const claims=JSON.parse(Buffer.from(sesiones[a.id].split('.')[1],'base64url').toString());
  assert.equal(claims.sub,a.id);
  if(claims.exp>Date.now()/1000+300)continue;
 }
 const r=await pedir('/auth/v1/token?grant_type=password',{method:'POST',body:{email:a.email,password}});
 assert.equal(r.status,200,`Login ${a.id}: ${r.body?.msg||r.body?.error_description||r.status}`);
 assert.equal(r.body.user.id,a.id);
 sesiones[a.id]=r.body.access_token;
}
writeFileSync(dir+'http-sesiones.json',JSON.stringify(sesiones),{mode:0o600});
for(const a of info.actores) {
 const miembro=modalidad==='piloto'?grupo.miembros.some(m=>m.id===a.id):(a.activo&&['gerencia','vendedor','supervisor','directorio'].includes(a.rol_crm));
 const r=await rpc('cartera_inversionistas_fn',{p_tamano:25},sesiones[a.id]);
 casos['cartera/'+a.id]=r;
 if(miembro){assert.equal(r.status,200,`Cartera ${a.rol_crm}: ${JSON.stringify(r.body)}`);assert.ok(r.body.total>0);}
 else assert.ok(r.status!==200 || r.body.total===0,`Actor fuera del piloto pudo consultar Cartera: ${a.id}`);
 console.log('Cartera',a.rol_crm||a.rol,miembro?'piloto':'fuera',r.status,r.body.total??r.body.code,miembro?Object.keys(r.body).join(','):'');
 if(!miembro)continue;
 const filas=r.body.filas;
 assert.ok(Array.isArray(filas),'Colección de personas no reconocida');
 for(const persona of filas) {
  const id=persona.inversionista_id??persona.id;assert.ok(id);
  const ficha=await rpc('inversionista_ficha_fn',{p_inversionista:id},sesiones[a.id]);
  assert.equal(ficha.status,200,`Ficha visible ${a.id}/${id}: ${ficha.status}`);
  casos['ficha/'+a.id+'/'+id]=ficha;
 }
 const interna=await pedir('/rest/v1/inversion_solicitudes?select=id&limit=1',{token:sesiones[a.id],schema:'crm'});
 assert.ok([401,403].includes(interna.status),'Acceso directo a solicitudes privadas');
 casos['tabla_privada/'+a.id]=interna;
 const esquema=await pedir('/rest/v1/contrato_pdfs?select=*&limit=1',{token:sesiones[a.id],schema:'private'});
 assert.equal(esquema.status,406);casos['esquema_privado/'+a.id]=esquema;
}
const anon=await rpc('cartera_inversionistas_fn',{},undefined);assert.ok([401,403].includes(anon.status));casos.anon=anon;
const analista=grupo.analistas[0];
const propia=new Set(casos['cartera/'+analista.id].body.filas.map(x=>x.inversionista_id??x.id));
const ajena=info.personas.find(p=>p.responsable===grupo.analistas[1].id&&p.estado==='activo'&&!propia.has(p.id));
assert.ok(ajena,'Falta persona ajena para el rechazo');
const cruzada=await rpc('inversionista_ficha_fn',{p_inversionista:ajena.id},sesiones[analista.id]);
assert.ok([400,401,403,404].includes(cruzada.status)||(cruzada.status===200&&cruzada.body===null));casos.ficha_ajena=cruzada;
function normalizar(x){
 if(Array.isArray(x))return x.map(normalizar);
 if(x&&typeof x==='object')return Object.fromEntries(Object.entries(x).filter(([k,v])=>!(k==='condiciones_coopac'&&v==null)).map(([k,v])=>[k,normalizar(v)]));
 return x;
}
writeFileSync(dir+'http-'+modalidad+'-'+fase+'.json',JSON.stringify({fase,casos},null,2),{mode:0o600});
if(fase==='despues'){
 const antes=JSON.parse(readFileSync(dir+'http-'+modalidad+'-antes.json','utf8'));
 assert.deepEqual(casos,antes.casos,'La migración cambió lecturas/permisos de las fuentes históricas');
}
console.log(`PASS: 15 sesiones, ${Object.keys(casos).length} casos HTTP/RLS ${modalidad}/${fase}`);
