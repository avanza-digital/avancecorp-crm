// Banco exclusivo y sintético. No acepta URL, proyecto ni base remota.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync, existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {createHmac} from 'node:crypto';

export const contenedor = 'supabase_db_avancecorp-venta-cruzada';
export const db = 'correo_acceso_20260925';
export const carpeta = '/private/tmp/avancecorp-correo-acceso-banco';
export const migracion = new URL('../../migrations/20260925170437_crm_correo_acceso_sincronizado.sql', import.meta.url);
export function docker(args, input) {
  const r = spawnSync('docker', args, {input, encoding:'utf8', maxBuffer:128*1024*1024});
  assert.equal(r.status, 0, r.stderr || r.error?.message); return r.stdout.trim();
}
export function ejecutar(input, base=db, usuario='postgres') {
  assert([db, 'postgres'].includes(base));
  assert(['postgres','supabase_admin'].includes(usuario));
  return spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U',usuario,'-d',base,
    '-v','ON_ERROR_STOP=1','-f','-'],{input:'\\set VERBOSITY verbose\n'+input,encoding:'utf8',maxBuffer:32*1024*1024});
}
export function sql(input, base=db, usuario='postgres') {
  const r=ejecutar(input,base,usuario); assert.equal(r.status,0,r.stderr||r.error?.message); return r.stdout.trim();
}
export const q=x=>"'"+String(x).replaceAll("'","''")+"'";
export function credencialesLocales() {
  const c=JSON.parse(docker(['inspect','supabase_auth_avancecorp-venta-cruzada']))[0];
  const vars=Object.fromEntries(c.Config.Env.map(x=>[x.slice(0,x.indexOf('=')),x.slice(x.indexOf('=')+1)]));
  const secret=vars.GOTRUE_JWT_SECRET;
  assert(secret && new URL(vars.GOTRUE_DB_DATABASE_URL).hostname===contenedor);
  const jwt=(role,sub)=>{
    const ahora=Math.floor(Date.now()/1000);
    const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
    const texto=enc({alg:'HS256',typ:'JWT'})+'.'+enc({iss:'supabase-demo',role,aud:'authenticated',iat:ahora,exp:ahora+3600,...(sub?{sub}:{})});
    return texto+'.'+createHmac('sha256',secret).update(texto).digest('base64url');
  };
  return {anon:jwt('anon'),servicio:jwt('service_role'),actor:id=>jwt('authenticated',id)};
}
const main=process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1]);
if(main&&process.argv[2]==='crear') {
  assert.equal(sql(`select count(*) from pg_database where datname=${q(db)}`,'postgres'),'0','El banco propio ya existe; no se reinicia.');
  assert.equal(sql(`select (count(*)<=200)::text from crm.leads`,'postgres'),'true');
  assert.equal(sql(`select count(*) from public.perfiles where correo not like '%@avancecorp.test' and correo not like '%example%' and correo not like '%.invalid'`,'postgres'),'0','La plantilla no es sintética.');
  mkdirSync(carpeta,{recursive:true,mode:0o700});
  // El banco histórico perdió actores de auditoría al limpiar sus fixtures.
  // Reconstruirlos sólo en la copia, antes de instalar las FK, conserva todos
  // los hechos y permite validar TODAS las restricciones sin deshabilitarlas.
  const refs=JSON.parse(sql(`select coalesce(jsonb_agg(jsonb_build_object('tabla',c.conrelid::regclass::text,'columna',a.attname)),'[]')
    from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
    where c.contype='f' and c.confrelid='public.perfiles'::regclass and cardinality(c.conkey)=1`,'postgres'));
  const consultas=refs.map(r=>`select ${r.columna} id from ${r.tabla} t where ${r.columna} is not null and not exists(select 1 from public.perfiles p where p.id=t.${r.columna})`);
  const faltantes=JSON.parse(sql(`select coalesce(jsonb_agg(distinct id),'[]') from (${consultas.join(' union all ')}) x`,'postgres'));
  assert(faltantes.every(id=>/^[a-f0-9-]{36}$/.test(id)));
  docker(['exec',contenedor,'createdb','-U','postgres','-T','template0',db]);
  for(const seccion of ['pre-data','data','post-data']) {
    const dump=docker(['exec',contenedor,'pg_dump','-U','postgres','-d','postgres','--section='+seccion]);
    sql(dump,db,'supabase_admin');
    if(seccion==='data') for(const id of faltantes) {
      sql(`insert into auth.users(id,aud,role,email,raw_app_meta_data) select ${q(id)},'authenticated','authenticated',${q(id+'@audit.invalid')},'{}'::jsonb where not exists(select 1 from auth.users where id=${q(id)});
        insert into public.perfiles(id,nombre_completo,correo,rol,activo,debe_cambiar_password) values(${q(id)},'ACTOR SINTETICO DE AUDITORIA',${q(id+'@audit.invalid')},'admin',false,false);`,db,'supabase_admin');
    }
  }
  writeFileSync(carpeta+'/reconstruccion.json',JSON.stringify({actoresSinteticosDeAuditoria:faltantes.length})+'\n',{mode:0o600});
  writeFileSync(carpeta+'/creado.txt',new Date().toISOString()+'\n',{mode:0o600});
  console.log('Banco sintético propio creado: '+db);
}
if(main&&process.argv[2]==='aplicar') {
  assert(existsSync(carpeta+'/creado.txt'),'Crear primero el banco propio');
  sql(readFileSync(migracion,'utf8')); console.log('Migración aplicada sólo a '+db);
}
if(main&&process.argv[2]==='sql') {
  assert(existsSync(carpeta+'/creado.txt')); console.log(sql(readFileSync(0,'utf8')));
}
if(main&&process.argv[2]==='test') {
  assert(existsSync(carpeta+'/creado.txt'));
  const r=ejecutar(readFileSync(new URL('./test-correo.sql',import.meta.url),'utf8'));
  process.stdout.write(r.stdout);process.stderr.write(r.stderr);process.exit(r.status??1);
}
if(main&&process.argv[2]==='http-iniciar') {
  assert(existsSync(carpeta+'/creado.txt'));
  for(const [tipo,puerto,interno,clave] of [['auth',59426,9999,'GOTRUE_DB_DATABASE_URL'],['rest',59425,3000,'PGRST_DB_URI']]) {
    const nombre=db+'_'+tipo;
    const existe=spawnSync('docker',['inspect',nombre],{encoding:'utf8'});
    if(existe.status===0){
      const c=JSON.parse(existe.stdout)[0];assert.equal(c.Config.Labels?.['avancecorp.ensayo'],db);assert(c.State.Running);continue;
    }
    const c=JSON.parse(docker(['inspect','supabase_'+tipo+'_avancecorp-venta-cruzada']))[0];
    const vars=Object.fromEntries(c.Config.Env.map(x=>[x.slice(0,x.indexOf('=')),x.slice(x.indexOf('=')+1)]));
    const url=new URL(vars[clave]);assert.equal(url.hostname,contenedor);assert.equal(url.pathname,'/postgres');
    url.pathname='/'+db;vars[clave]=url.href;
    if(tipo==='auth'){
      vars.API_EXTERNAL_URL='http://127.0.0.1:59426';vars.GOTRUE_SITE_URL='http://127.0.0.1:59426';
      vars.GOTRUE_SMTP_HOST='127.0.0.1';vars.GOTRUE_SMTP_PORT='1';
    }
    assert(Object.values(vars).every(x=>!/[\r\n]/.test(x)));
    const env=carpeta+'/'+tipo+'.env';writeFileSync(env,Object.entries(vars).map(([k,v])=>k+'='+v).join('\n'),{mode:0o600});
    const redes=Object.keys(c.NetworkSettings.Networks);assert.equal(redes.length,1);
    docker(['run','-d','--name',nombre,'--label','avancecorp.ensayo='+db,'--network',redes[0],
      '--env-file',env,'-p',`127.0.0.1:${puerto}:${interno}`,c.Config.Image]);
  }
  console.log('Auth y PostgREST exclusivos iniciados en puertos 59426/59425. SMTP deshabilitado.');
}

if(main&&process.argv[2]==='probar-reversion') {
  const original=readFileSync(new URL('./revertir-comportamiento.sql',import.meta.url),'utf8');
  assert(original.trim().endsWith('commit;'));
  const pruebas=`do $$ begin
    assert exists(select 1 from pg_trigger where tgname='inversion_auth_insertado_guard' and not tgisinternal), 'Se conserva el guard Auth';
    assert not exists(select 1 from pg_trigger where tgname in ('inversion_correo_a_ficha','inversion_correo_desde_ficha') and not tgisinternal), 'Sincronización detenida';
    assert md5(pg_get_functiondef('crm.acceso_inversion_fn(uuid,text,jsonb)'::regprocedure))='e4730d0161710fc8a84fb6dc7635bf47', 'Acceso restaurado al byte';
    assert md5(pg_get_functiondef('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'::regprocedure))='3e09703845f2824054ead959fec40e47', 'Corrección restaurada al byte';
  end $$; rollback;`;
  sql(original.replace(/commit;\s*$/,()=>pruebas));
  assert.equal(sql("select count(*) from pg_trigger where tgname in ('inversion_correo_a_ficha','inversion_correo_desde_ficha') and not tgisinternal"),'2');
  console.log('PASS: reversión operativa probada y deshecha; el banco conserva el candidato');
}
