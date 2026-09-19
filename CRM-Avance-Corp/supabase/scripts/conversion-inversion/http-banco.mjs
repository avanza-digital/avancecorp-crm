// Servicios HTTP exclusivos del ensayo. Nunca redirige el banco F5 compartido.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {createServer} from 'node:http';
import {db,contenedor} from './banco.mjs';
import {crearHandlerAccesoInversion} from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';

export const carpeta='/private/tmp/avancecorp-conversion-inversion';
export const apiUrl='http://127.0.0.1:59321';
const modeloStorage=JSON.parse(docker(['inspect','supabase_storage_avancecorp-f5-bank']))[0];
const envStorage=Object.fromEntries(modeloStorage.Config.Env.map(x=>[x.slice(0,x.indexOf('=')),x.slice(x.indexOf('=')+1)]));
export const inicio={ANON_KEY:envStorage.ANON_KEY,SERVICE_ROLE_KEY:envStorage.SERVICE_KEY};
assert.equal(JSON.parse(Buffer.from(inicio.SERVICE_ROLE_KEY.split('.')[1],'base64url')).iss,'supabase-demo');
export const fixture=existsSync(`${carpeta}/fixture.json`)?JSON.parse(readFileSync(`${carpeta}/fixture.json`,'utf8')):null;
const nombre=s=>`conversion_inversion_20260918_${s}`;
const servicios={rest:{puerto:59325,interno:3000},auth:{puerto:59326,interno:9999},storage:{puerto:59327,interno:5000}};
function docker(args){const r=spawnSync('docker',args,{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
export async function http(ruta,{token,admin=false,body,rawBody,method='POST',headers={}}={}){
  assert(ruta.startsWith('/')&&!ruta.startsWith('//'));
  const r=await fetch(apiUrl+ruta,{method,headers:{apikey:inicio.ANON_KEY,
    Authorization:`Bearer ${admin?inicio.SERVICE_ROLE_KEY:token??inicio.ANON_KEY}`,
    'Content-Type':'application/json',...headers},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),...(rawBody===undefined?{}:{body:rawBody}),
    redirect:'error',signal:AbortSignal.timeout(30_000)});
  const texto=await r.text();let data;try{data=JSON.parse(texto);}catch{data=texto;}
  return {ok:r.ok,status:r.status,data};
}
export const rpc=(nombre,body,token)=>http(`/rest/v1/rpc/${nombre}`,{token,body,
  headers:{'Accept-Profile':'crm','Content-Profile':'crm'}});
export async function como(rol){
  const u=fixture.usuarios[rol];assert(u);
  const r=await http('/auth/v1/token?grant_type=password',{body:{email:u.email,password:fixture.password}});
  assert.equal(r.ok,true,`Login sintético ${rol}: HTTP ${r.status}`);
  assert.equal(r.data.user.id,u.id);return r.data.access_token;
}
if(process.argv[2]==='storage-volumen'){
  const c=JSON.parse(docker(['inspect',nombre('storage')]))[0];
  assert.equal(c.Config.Labels?.['avancecorp.ensayo'],'conversion_inversion_20260918');
  assert.equal(c.Mounts.find(x=>x.Destination==='/mnt')?.Type,'bind');
  docker(['stop',nombre('storage')]);
  docker(['rename',nombre('storage'),nombre('storage')+'_resguardo_bind']);
}
if(['iniciar','storage-volumen'].includes(process.argv[2])){
  mkdirSync(carpeta,{recursive:true,mode:0o700});
  for(const [servicio,{puerto,interno}] of Object.entries(servicios)){
    const existe=spawnSync('docker',['inspect',nombre(servicio)],{encoding:'utf8'});
    if(existe.status===0){const c=JSON.parse(existe.stdout)[0];
      assert.equal(c.Config.Labels?.['avancecorp.ensayo'],'conversion_inversion_20260918');
      assert.equal(c.State.Running,true,'El servicio propio está detenido; inspección necesaria.');continue;}
    const modelo=JSON.parse(docker(['inspect',`supabase_${servicio}_avancecorp-f5-bank`]))[0];
    assert.deepEqual(Object.keys(modelo.NetworkSettings.Networks),['avancecorp-f5-bank-red']);
    const variables=Object.fromEntries(modelo.Config.Env.map(x=>[x.slice(0,x.indexOf('=')),x.slice(x.indexOf('=')+1)]));
    const llave={rest:'PGRST_DB_URI',auth:'GOTRUE_DB_DATABASE_URL',storage:'DATABASE_URL'}[servicio];
    const uri=new URL(variables[llave]);assert.equal(uri.pathname,'/postgres');
    uri.hostname=contenedor;uri.pathname='/'+db;variables[llave]=uri.href;
    if(servicio==='auth'){
      variables.API_EXTERNAL_URL=apiUrl;variables.GOTRUE_SITE_URL=apiUrl;
      // No se envía correo en este ensayo. Una invocación accidental falla localmente.
      variables.GOTRUE_SMTP_HOST='127.0.0.1';variables.GOTRUE_SMTP_PORT='1';
    }
    const env=`${carpeta}/${servicio}.env`;
    assert(Object.values(variables).every(x=>!/[\r\n]/.test(x)));
    writeFileSync(env,Object.entries(variables).map(([k,v])=>`${k}=${v}`).join('\n')+'\n',{mode:0o600});
    const args=['run','-d','--name',nombre(servicio),'--label','avancecorp.ensayo=conversion_inversion_20260918',
      '--network','avancecorp-f5-bank-red','--env-file',env,'-p',`127.0.0.1:${puerto}:${interno}`];
    if(servicio==='storage'){
      // Volumen Linux propio: el bind de macOS no implementa los xattrs que
      // Storage usa para conservar metadatos de los archivos.
      args.push('--mount','type=volume,src=conversion_inversion_20260918_archivos,dst=/mnt');
    }
    args.push(modelo.Config.Image);docker(args);
  }
  console.log('Tres servicios exclusivos iniciados para conversion_inversion_20260918, puertos locales 59325–59327.');
}else if(process.argv[2]==='servidor'){
  const portal=crearHandlerAccesoInversion({supabaseUrl:apiUrl,anonKey:inicio.ANON_KEY,serviceKey:inicio.SERVICE_ROLE_KEY});
  const server=createServer(async(req,res)=>{
    const cors=req.headers.origin==='http://127.0.0.1:5299'?{
      'Access-Control-Allow-Origin':req.headers.origin,
      'Access-Control-Allow-Methods':'GET,POST,PATCH,DELETE,OPTIONS',
      'Access-Control-Allow-Headers':req.headers['access-control-request-headers']??'authorization,apikey,content-type,x-client-info,x-upsert,cache-control',
    }:{};
    if(req.method==='OPTIONS'&&Object.keys(cors).length){res.writeHead(204,cors);res.end();return;}
    try{
      const url=new URL(req.url,apiUrl), pref=Object.keys(servicios).find(x=>url.pathname.startsWith(`/${x}/v1/`));
      const chunks=[];for await(const c of req)chunks.push(c);const body=Buffer.concat(chunks);
      const headers=Object.fromEntries(Object.entries(req.headers).filter(([k])=>!['host','content-length','connection','transfer-encoding'].includes(k)));
      const options={method:req.method,headers,...(body.length?{body}:{}),duplex:'half'};
      let upstream;
      if(url.pathname==='/functions/v1/crm-inversion-portal')upstream=await portal(new Request(url,options));
      else{
        if(!pref){res.writeHead(404);res.end();return;}
        const destino=`http://127.0.0.1:${servicios[pref].puerto}${url.pathname.replace(`/${pref}/v1`,'')}${url.search}`;
        upstream=await fetch(destino,{...options,signal:AbortSignal.timeout(30_000)});
      }
      const salida=new Headers(upstream.headers);
      for(const k of ['content-encoding','content-length','transfer-encoding'])salida.delete(k);
      for(const [k,v] of Object.entries(cors))salida.set(k,v);
      res.writeHead(upstream.status,Object.fromEntries(salida));
      res.end(Buffer.from(await upstream.arrayBuffer()));
    }catch{res.writeHead(502,{'Content-Type':'application/json',...cors});res.end(JSON.stringify({error:'Servicio local no disponible'}));}
  });
  server.listen(59321,'127.0.0.1',()=>console.log('Gateway de ensayo disponible en 127.0.0.1:59321.'));
}
