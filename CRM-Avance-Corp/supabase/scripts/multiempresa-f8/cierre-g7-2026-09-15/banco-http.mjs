// Servicios HTTP efímeros sobre la copia SQL propia, nunca producción.
// Reutiliza imágenes y secretos LOCALES sin imprimirlos ni escribirlos en Git.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
import {createHash,createHmac,randomBytes} from 'node:crypto';
import {createServer} from 'node:http';
import {fileURLToPath} from 'node:url';

export const db='g7_cierre_20260915',contenedor='supabase_db_avancecorp-f5-bank';
export const apiUrl='http://127.0.0.1:59321';
const volumen='avancecorp_g7_objetos_20260915';
let secreto;
// Los archivos privados del banco antiguo ya no existen. Emitir claves de
// servicio locales a partir de su secreto de ensayo; nunca se exportan.
function clave(rol) {
  const b=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
  const texto=b({alg:'HS256',typ:'JWT'})+'.'+b({iss:'supabase-demo',role:rol,exp:Math.floor(Date.now()/1000)+86400});
  return texto+'.'+createHmac('sha256',secreto).update(texto).digest('base64url');
}
const inicio={};
function inicializarAuth() {
  const fuenteAuth=JSON.parse(docker(['inspect','supabase_auth_avancecorp-f5-bank']))[0];
  assert(fuenteAuth.NetworkSettings.Networks['avancecorp-f5-bank-red']);
  secreto=fuenteAuth.Config.Env.find(x=>x.startsWith('GOTRUE_JWT_SECRET=')).slice('GOTRUE_JWT_SECRET='.length);
  Object.assign(inicio,{ANON_KEY:clave('anon'),SERVICE_ROLE_KEY:clave('service_role')});
}
export const fixture={password:randomBytes(24).toString('base64url')+'aA1!',usuarios:{}};
export const q=x=>x===null?'null':`'${String(x).replaceAll("'","''")}'`;
export const j=x=>q(JSON.stringify(x))+'::jsonb';
function docker(args,input) {
  const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:16*1024*1024});
  assert.equal(r.status,0,r.stderr||r.error?.message||'Falló Docker local');return r.stdout.trim();
}
export function sql(s,{admin=false}={}) {
  return docker(['exec','-i',contenedor,'psql','-X','-qAt','-U',admin?'supabase_admin':'postgres','-d',db,
    '-v','ON_ERROR_STOP=1','-f','-'],"\\set VERBOSITY verbose\nset timezone='America/Lima';set statement_timeout='20s';\n"+s);
}
export const objeto=(s,opciones)=>JSON.parse(sql(s,opciones));
export async function http(ruta,{token,admin=false,body,bytes,method='POST',headers={}}={}) {
  assert(ruta.startsWith('/')&&!ruta.startsWith('//'));
  const r=await fetch(apiUrl+ruta,{method,headers:{apikey:inicio.ANON_KEY,
    Authorization:`Bearer ${admin?inicio.SERVICE_ROLE_KEY:token??inicio.ANON_KEY}`,
    'Content-Type':'application/json',...headers},
    body:bytes??(body===undefined?undefined:JSON.stringify(body)),
    redirect:'error',signal:AbortSignal.timeout(25000)});
  const texto=await r.text();let data;try{data=JSON.parse(texto);}catch{data=texto;}
  return {ok:r.ok,status:r.status,data};
}
export const rpc=(nombre,body,token)=>{
  assert(/^[a-z_][a-z0-9_]*$/.test(nombre));
  return http('/rest/v1/rpc/'+nombre,{body,token,headers:{'Accept-Profile':'crm','Content-Profile':'crm'}});
};
export const ok=r=>{assert.equal(r.ok,true,`${r.status}: ${r.data?.message??r.data?.error??'Error HTTP local'}`);return r.data;};
export async function sesion(rol) {
  const u=fixture.usuarios[rol];assert(u,'Rol sintético desconocido');
  const r=ok(await http('/auth/v1/token?grant_type=password',{body:{email:u.email,password:fixture.password}}));
  assert.equal(r.user.id,u.id);return r.access_token;
}
export function handlerEnBanco(crearHandler,interceptar=fetch) {
  return crearHandler({supabaseUrl:apiUrl,anonKey:inicio.ANON_KEY,serviceKey:inicio.SERVICE_ROLE_KEY,
    fetchImpl:(url,opciones)=>{assert.equal(new URL(url).origin,apiUrl);return interceptar(url,opciones);}});
}

const configs=[['auth',59329,9999],['rest',59320,3000],['storage',59325,5000]];
const propios=[];let proxy;
export const versiones=[];
function prepararPropietariosServicios() {
  // El dump SQL de la copia fue restaurado como postgres. Auth debe poder ver
  // su tabla de migraciones. Copiar solo propietarios del banco local fuente;
  // no copiar usuarios ni datos, ni alterar permisos del producto CRM.
  const metadatos=JSON.parse(docker(['exec',contenedor,'psql','-X','-qAt','-U','postgres','-d','postgres','-c',
    `select jsonb_build_object('esquemas',(select jsonb_agg(jsonb_build_object('nombre',nspname,
      'propietario',pg_get_userbyid(nspowner))) from pg_namespace where nspname in('auth','storage')),
      'tablas',(select jsonb_agg(jsonb_build_object('nombre',format('%I.%I',n.nspname,c.relname),
      'tipo',c.relkind,'propietario',pg_get_userbyid(c.relowner))) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname in('auth','storage') and c.relkind in('r','p','v','m','S'))) `]));
  const identificador=s=>'"'+s.replaceAll('"','""')+'"';
  const sentencias=metadatos.esquemas.map(x=>`alter schema ${identificador(x.nombre)} owner to ${identificador(x.propietario)};`);
  // Las secuencias ligadas cambian con su tabla; ordenarlas al final.
  for(const x of metadatos.tablas.sort((a,b)=>Number(a.tipo==='S')-Number(b.tipo==='S'))) {
    const tipo={r:'table',p:'table',v:'view',m:'materialized view',S:'sequence'}[x.tipo];
    sentencias.push(`alter ${tipo} ${x.nombre} owner to ${identificador(x.propietario)};`);
  }
  // Restaurar propietarios requiere el administrador existente del contenedor.
  // No cambiar membresías globales ni privilegios del usuario postgres.
  docker(['exec','-i',contenedor,'psql','-X','-qAt','-U','supabase_admin','-d',db,
    '-v','ON_ERROR_STOP=1','-f','-'],
    "begin;set local statement_timeout='20s';\n"+sentencias.join('\n')+
    // La configuración en PostgreSQL precede a las variables PGRST. Acotar
    // el cambio a esta base: no tocar la configuración compartida del rol.
    `alter role authenticator in database ${db} set pgrst.db_schemas='public,crm';commit;`);
}
export async function abrir() {
  inicializarAuth();
  assert.equal(sql('select current_database()'),db);
  prepararPropietariosServicios();
  // Un volumen Linux admite los atributos extendidos que exige Storage; un
  // bind mount de macOS no. Se conserva junto a los fixtures de esta copia.
  docker(['volume','create','--label','avancecorp.g7.owner=20260915',volumen]);
  const v=JSON.parse(docker(['volume','inspect',volumen]))[0];
  assert.equal(v.Labels['avancecorp.g7.owner'],'20260915');
  for(const [tipo,puerto,interno] of configs) {
    const nombre=`avancecorp_g7_${tipo}_20260915`;
    const origen=JSON.parse(docker(['inspect',`supabase_${tipo}_avancecorp-f5-bank`]))[0];
    assert.equal(Object.keys(origen.NetworkSettings.Networks).length,1);
    assert(origen.NetworkSettings.Networks['avancecorp-f5-bank-red']);
    let vars=Object.fromEntries(origen.Config.Env.map(x=>{const i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1)];}));
    if(tipo==='auth') {
      const permitidas=new Set(['PATH','GOTRUE_API_HOST','GOTRUE_API_PORT','GOTRUE_DB_DRIVER',
        'GOTRUE_DB_DATABASE_URL','GOTRUE_JWT_SECRET','GOTRUE_JWT_KEYS','GOTRUE_JWT_AUD',
        'GOTRUE_JWT_EXP','GOTRUE_JWT_ADMIN_ROLES','GOTRUE_JWT_DEFAULT_GROUP_NAME',
        'GOTRUE_JWT_ISSUER','GOTRUE_JWT_VALIDMETHODS','GOTRUE_JWT_VALID_METHODS']);
      vars=Object.fromEntries(Object.entries(vars).filter(([k])=>permitidas.has(k)));
      Object.assign(vars,{GOTRUE_MAILER_AUTOCONFIRM:'true',GOTRUE_SMTP_HOST:'',
        GOTRUE_DISABLE_SIGNUP:'true',GOTRUE_EXTERNAL_EMAIL_ENABLED:'true',GOTRUE_EXTERNAL_PHONE_ENABLED:'false'});
    }
    const clave=tipo==='auth'?'GOTRUE_DB_DATABASE_URL':tipo==='rest'?'PGRST_DB_URI':'DATABASE_URL';
    assert(vars[clave],'No se encontró la conexión local '+clave);
    const conexion=new URL(vars[clave]);
    assert(['db',contenedor].includes(conexion.hostname));assert.equal(conexion.pathname,'/postgres');
    conexion.pathname='/'+db;vars[clave]=conexion.toString();
    if(tipo==='auth') {vars.API_EXTERNAL_URL=apiUrl;vars.GOTRUE_SITE_URL=apiUrl;}
    // Esta copia no incluye GraphQL; los recorridos usan exclusivamente REST.
    if(tipo==='rest')vars.PGRST_DB_SCHEMAS='public,crm';
    if(tipo==='storage') {
      vars.POSTGREST_URL='http://avancecorp_g7_rest_20260915:3000';
      vars.STORAGE_BACKEND='file';vars.FILE_STORAGE_BACKEND_PATH='/var/lib/storage';
    }
    const args=['run','-d','--pull','never','--name',nombre,
      '--label','avancecorp.g7.owner=20260915','--network','avancecorp-f5-bank-red',
      '--cpus','1','--memory','512m','-p',`127.0.0.1:${puerto}:${interno}`];
    args.push('--entrypoint',origen.Config.Entrypoint?.[0]??'');
    for(const [key,value] of Object.entries(vars))args.push('-e',key+'='+value);
    if(tipo==='storage')args.push('-v',volumen+':/var/lib/storage');
    args.push(origen.Config.Image,...(origen.Config.Entrypoint?.slice(1)??[]),...(origen.Config.Cmd??[]));
    docker(args);propios.push(nombre);versiones.push({servicio:tipo,imagen:origen.Config.Image,
      ...(tipo==='auth'?{entorno:'Lista explícita de DB/JWT/API; sin SMTP, proveedores externos ni hooks. Autoconfirmación activa y alta pública deshabilitada.'}:{})});
  }
  proxy=createServer(async(req,res)=>{
    try {
      const ruta=new URL(req.url,apiUrl);let puerto,prefijo;
      if(ruta.pathname.startsWith('/auth/v1/')) {puerto=59329;prefijo='/auth/v1';}
      else if(ruta.pathname.startsWith('/rest/v1/')) {puerto=59320;prefijo='/rest/v1';}
      else if(ruta.pathname.startsWith('/storage/v1/')) {puerto=59325;prefijo='/storage/v1';}
      else {res.writeHead(404);res.end();return;}
      const chunks=[];let total=0;
      for await(const c of req){total+=c.length;if(total>1024*1024)throw new Error('Cuerpo excede fixture');chunks.push(c);}
      const headers={...req.headers};delete headers.host;delete headers.connection;delete headers['content-length'];
      const r=await fetch(`http://127.0.0.1:${puerto}`+ruta.pathname.slice(prefijo.length)+ruta.search,
        {method:req.method,headers,body:chunks.length?Buffer.concat(chunks):undefined,
          redirect:'manual',signal:AbortSignal.timeout(25000)});
      const h=Object.fromEntries(r.headers);delete h['content-encoding'];delete h['content-length'];delete h['transfer-encoding'];
      res.writeHead(r.status,h);res.end(Buffer.from(await r.arrayBuffer()));
    } catch {res.writeHead(502,{'Content-Type':'application/json'});res.end('{"error":"Servicio de ensayo no disponible"}');}
  });
  await new Promise((resolve,reject)=>{proxy.once('error',reject);proxy.listen(59321,'127.0.0.1',resolve);});
  for(let n=0;n<40;n++) {
    const r=await http('/auth/v1/health',{method:'GET'});
    const rest=await http('/rest/v1/',{method:'GET'});
    if(r.ok&&rest.ok) {
      const cuentas=objeto(`select jsonb_agg(jsonb_build_object('id',p.id,'email',u.email,
        'rol',e.rol_crm,'supervisor_id',e.supervisor_id) order by p.id)
        from public.perfiles p join auth.users u on u.id=p.id
        join crm.equipo e on e.perfil_id=p.id where p.activo and e.activo`);
      const vendedores=cuentas.filter(c=>c.rol==='vendedor');assert.equal(vendedores.length,2);
      fixture.usuarios={gerencia:cuentas.find(c=>c.rol==='gerencia'),vendedor:vendedores[0],ajeno:vendedores[1],
        supervisor:cuentas.find(c=>c.id===vendedores[0].supervisor_id),
        supervisor_ajeno:cuentas.find(c=>c.id===vendedores[1].supervisor_id),
        directorio:cuentas.find(c=>c.rol==='directorio')};
      fixture.usuarios.cliente=objeto(`select jsonb_build_object('id',p.id,'email',u.email)
        from public.perfiles p join auth.users u on u.id=p.id
        where p.rol='cliente' and p.activo and u.email is not null order by p.id limit 1`);
      for(const u of Object.values(fixture.usuarios)) {
        assert(u&&u.email,'Falta una cuenta ficticia');
        ok(await http('/auth/v1/admin/users/'+u.id,{admin:true,method:'PUT',body:{password:fixture.password}}));
      }
      const t=await sesion('gerencia');ok(await rpc('postventa_estado_fn',{},t));return;
    }
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  for(const tipo of ['auth','rest','storage']) {
    const resultadoLogs=spawnSync('docker',['logs','--tail','20',`avancecorp_g7_${tipo}_20260915`],{encoding:'utf8'});
    const logs=resultadoLogs.stdout+resultadoLogs.stderr;
    console.error(tipo+': '+logs.replaceAll(secreto,'[secreto local]')
      .replaceAll(inicio.ANON_KEY,'[clave anon local]').replaceAll(inicio.SERVICE_ROLE_KEY,'[clave servicio local]')
      .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,'[JWT local]')
      .replace(/postgres(?:ql)?:\/\/\S+/g,'[conexion local]'));
  }
  throw new Error('Auth/PostgREST local no inició dentro del límite');
}
export async function cerrar() {
  if(proxy) {proxy.closeAllConnections();await new Promise(resolve=>proxy.close(resolve));}
  for(const nombre of propios.reverse()) {
    const c=JSON.parse(docker(['inspect',nombre]))[0];
    assert.equal(c.Config.Labels['avancecorp.g7.owner'],'20260915');
    docker(['stop','--time','5',nombre]);
    docker(['rm',nombre]);
  }
}
if(process.argv[1]&&realpathSync(process.argv[1])===fileURLToPath(import.meta.url)) {
  if(process.argv.includes('--inventario')) {
    const destino=new URL('cotejo-casos.json',import.meta.url);
    const recibo={estado:'RUNNING',inicio:new Date().toISOString(),banco:db};
    const guardar=()=>writeFileSync(destino,JSON.stringify(recibo,null,2)+'\n');
    guardar();
    try {
      const leer=f=>readFileSync(new URL(f,import.meta.url),'utf8');
      const captura=JSON.parse(leer('captura-versiones.json'));
      const productivas=JSON.parse(leer('versiones-casos.json'));
      assert.equal(captura.proyecto,'dctqcbznekcyxhjujuci');assert.equal(captura.solo_lectura,'on');
      assert(Number.isFinite(Date.parse(captura.corte)));
      assert.deepEqual(captura.funciones,productivas);assert.equal(productivas.length,203);
      assert.equal(captura.dependencias.length,3);assert.equal(captura.tablas.length,3);
      const local=objeto(leer('capturar-versiones.sql'));
      assert.equal(local.base,db);assert.equal(local.solo_lectura,'on');
      const normalizar=lista=>lista.map(x=>({...x,acl:x.acl===null?null:x.acl.slice(1,-1).split(',').sort()}));
      const catalogo=x=>({funciones:normalizar(x.funciones),dependencias:normalizar(x.dependencias),tablas:x.tablas});
      assert.deepEqual(catalogo(local),catalogo(captura),'Deriva del catálogo seleccionado');
      Object.assign(recibo,{estado:'PASS',fecha:new Date().toISOString(),proyecto:captura.proyecto,
        corte_produccion:captura.corte,funciones:local.funciones.length,
        dependencias:local.dependencias.length,tablas:local.tablas.length,
        sha256:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
        dependencias_sha256:Object.fromEntries(['captura-versiones.json','versiones-casos.json',
          'capturar-versiones.sql','dependencias-local.sql'].map(f=>[f,createHash('sha256').update(leer(f)).digest('hex')])),
        catalogo_sha256:createHash('sha256').update(JSON.stringify(catalogo(captura))).digest('hex'),
        alcance:'203 funciones y 3 auxiliares con propietarios/ACL; columnas y restricciones de 3 tablas. No acredita paridad del esquema completo.'});
      console.log('PASS: 203 funciones, 3 auxiliares y 3 tablas cotejadas con producción.');
    } catch(error) {
      Object.assign(recibo,{estado:'FAIL',fecha:new Date().toISOString(),error:error.message});throw error;
    } finally {guardar();}
  } else if(process.argv.includes('--diagnostico')) {
    console.log(sql(`select jsonb_build_object('auth_schema',(select jsonb_build_object(
      'owner',nspowner::regrole::text,'acl',nspacl::text) from pg_namespace where nspname='auth'),
      'migraciones',(select jsonb_agg(jsonb_build_object('tabla',c.oid::regclass::text,
      'owner',c.relowner::regrole::text,'acl',c.relacl::text)) from pg_class c
      where c.relname='schema_migrations'),'rutas',(select jsonb_agg(jsonb_build_object(
      'db',d.datname,'rol',r.rolname,'setting',v)) from pg_db_role_setting s
      left join pg_database d on d.oid=s.setdatabase left join pg_roles r on r.oid=s.setrole
      cross join unnest(s.setconfig) v where v like 'search_path=%'))`));
  } else {
    try {await abrir();console.log(JSON.stringify({estado:'PASS',banco:db,servicios:versiones}));}
    finally {await cerrar();}
  }
}
