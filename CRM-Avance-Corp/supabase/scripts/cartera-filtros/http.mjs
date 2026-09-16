// PostgREST real contra la copia propia. JWT exclusivamente del banco local.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHmac,randomBytes} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {db,sql,objeto,gerencia,preparar,q} from './banco.mjs';
const docker=args=>execFileSync('docker',args,{encoding:'utf8'}).trim();
const nombre='avancecorp-cartera-filtros-rest',url='http://127.0.0.1:58451';
assert.equal(sql('select current_database()'),db);
const original=JSON.parse(docker(['inspect','supabase_rest_avancecorp-f5-bank']))[0];
const red=Object.keys(original.NetworkSettings.Networks)[0];
const conexion=new URL(original.Config.Env.find(e=>e.startsWith('PGRST_DB_URI=')).slice('PGRST_DB_URI='.length));
assert.equal(conexion.hostname,'supabase_db_avancecorp-f5-bank');
assert.equal(conexion.username,'authenticator');
conexion.pathname='/'+db;
// Clave efímera SOLO para esta API loopback; no reutilizar sesiones ni claves
// de Auth. El ensayo acredita RPC/RLS por HTTP, no el login de una persona.
const secreto=randomBytes(48).toString('base64url');
const token=id=>{
  const parte=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
  const cuerpo=parte({alg:'HS256',typ:'JWT'})+'.'+parte({role:'authenticated',sub:id,iss:'supabase-demo',exp:Math.floor(Date.now()/1000)+300});
  return cuerpo+'.'+createHmac('sha256',secreto).update(cuerpo).digest('base64url');
};
const antes=objeto('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags');
let iniciado=false;
const resultados=[];
try {
  // Docker rechaza el nombre si ya existe; jamás se sustituye un recurso ajeno.
  docker(['run','--rm','-d','--name',nombre,'--network',red,'-p','127.0.0.1:58451:3000',
    '-e',`PGRST_DB_URI=${conexion}`,
    '-e','PGRST_DB_CONFIG=false','-e','PGRST_DB_SCHEMAS=public,crm','-e','PGRST_DB_ANON_ROLE=anon','-e',`PGRST_JWT_SECRET=${secreto}`,original.Image]);
  iniciado=true;
  sql('begin;'+preparar+'commit;');
  let listo=false;
  for(let n=0;n<40;n++) {
    try {const r=await fetch(url,{signal:AbortSignal.timeout(1000)});if(r.status<500){listo=true;break;}}catch{}
    await new Promise(r=>setTimeout(r,100));
  }
  if(!listo) {
    const logs=docker(['logs',nombre]).replace(/postgres(?:ql)?:\/\/[^\s]+/g,'[conexión local]');
    throw new Error('PostgREST local no arrancó: '+logs.slice(-1800));
  }
  const rpc=async(nombre,datos,actor=gerencia)=>{
    const r=await fetch(url+'/rpc/'+nombre,{method:'POST',headers:{'Content-Type':'application/json','Content-Profile':'crm',
      'Accept-Profile':'crm',...(actor?{Authorization:'Bearer '+token(actor)}:{})},body:JSON.stringify(datos),signal:AbortSignal.timeout(10000)});
    return {status:r.status,data:await r.json()};
  };
  const v2=await rpc('cartera_inversionistas_filtrada_fn',{p_mes:'2026-07',p_empresa:'qorilazo',p_moneda:'PEN'});
  assert.equal(v2.status,200);assert.equal(v2.data.version,2);assert(v2.data.total>0);
  assert(v2.data.filas.every(p=>p.ultima_fecha_comercial.startsWith('2026-07')));
  assert(v2.data.totales.every(t=>t.empresa==='qorilazo' && t.moneda==='PEN'));
  resultados.push('RPC v2 descubierta por PostgREST; mes, moneda, empresa y JSON correctos');
  const v1=await rpc('cartera_inversionistas_fn',{});
  assert.equal(v1.status,200);assert.equal(v1.data.version,1);assert(!('opciones_meses' in v1.data));
  resultados.push('RPC v1 mantiene su firma y respuesta');
  for(const actor of [null,'8821227a-add2-4e75-83bc-8f7c30070062','3dc87919-4c2a-469c-a7fc-eadd1f9d9433']) {
    const r=await rpc('cartera_inversionistas_filtrada_fn',{},actor);
    assert(r.status===401 || r.status===403);assert.equal(r.data.code,'42501');
  }
  resultados.push('Anon, coordinador y cliente rechazados sin datos');
  const malo=await rpc('cartera_inversionistas_filtrada_fn',{p_mes:'2026-13'});
  assert.equal(malo.status,400);assert.equal(malo.data.code,'22023');
  resultados.push('Filtros inválidos rechazados por HTTP');
  writeFileSync(new URL('http.json',import.meta.url),JSON.stringify({estado:'PASS',banco:db,resultados},null,2)+'\n');
  console.log('PASS: 6 peticiones HTTP reales; sin credenciales ni datos personales en evidencia.');
} finally {
  sql('begin;'+Object.entries(antes).map(([nombre,activo])=>`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)};`).join('')+'commit;');
  if(iniciado) docker(['stop',nombre]);
}
