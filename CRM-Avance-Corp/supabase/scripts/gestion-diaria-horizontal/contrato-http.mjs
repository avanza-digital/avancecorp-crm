// PostgREST real sobre una segunda copia desechable del banco H3. No mocks,
// credenciales de nube ni cambios de roles compartidos. Se elimina al terminar.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHmac, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { db, contenedor, socket, sql } from './banco.mjs';
const copia = 'gestion_diaria_h3_http_20260923';
const servicio = 'avancecorp-h3-http';
const puerto = 58441;
const docker = (args, opciones = {}) => {
  const r = spawnSync('docker',['--host',socket,...args],{encoding:'utf8',maxBuffer:16*1024*1024,...opciones});
  assert.equal(r.status,0,`Docker ${args[0]}: ${r.stderr}`); return r.stdout.trim();
};
sql('select private.assert_gestion_diaria_pendientes();');
// Rechazar colisiones; nunca retirar el contenedor de otra sesión.
assert.ok(!docker(['ps','-a','--format','{{.Names}}']).split('\n').includes(servicio),'el banco HTTP ya está en uso');
const red = Object.keys(JSON.parse(docker(['inspect',contenedor]))[0].NetworkSettings.Networks)[0];
assert.ok(red);
const rest = JSON.parse(docker(['inspect','supabase_rest_avancecorp-f5-bank']))[0];
const uri = new URL(rest.Config.Env.find(v=>v.startsWith('PGRST_DB_URI=')).slice('PGRST_DB_URI='.length));
assert.equal(uri.hostname,contenedor); uri.pathname=`/${copia}`;
const secreto = randomBytes(32).toString('hex');
const jwt = (id,rol='authenticated') => {
  const cabecera=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
  const cuerpo=Buffer.from(JSON.stringify({sub:id,role:rol,exp:Math.floor(Date.now()/1000)+300})).toString('base64url');
  return `${cabecera}.${cuerpo}.${createHmac('sha256',secreto).update(`${cabecera}.${cuerpo}`).digest('base64url')}`;
};
let creada=false, levantado=false;
try {
  docker(['exec',contenedor,'createdb','-U','supabase_admin','-O','postgres','-T',db,copia]); creada=true;
  const pg=texto=>docker(['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',copia,'-v','ON_ERROR_STOP=1','-f','-'],{input:texto});
  const fixture=readFileSync(new URL('test-pendientes.sql',import.meta.url),'utf8').split('create temporary table h3_paginas')[0];
  const lineas=pg(`${fixture}\nselect row_to_json(a) from h3_actores a;\ncommit;`).split('\n');
  const actores=JSON.parse(lineas.findLast(l=>l.startsWith('{"vendedor"')));
  docker(['run','--rm','-d','--name',servicio,'--network',red,'--label','avancecorp.task=supervisor-h3',
    '-p',`127.0.0.1:${puerto}:3000`,'-e','PGRST_DB_URI','-e','PGRST_JWT_SECRET','-e','PGRST_DB_SCHEMAS=crm',
    '-e','PGRST_DB_ANON_ROLE=anon','-e','PGRST_DB_CONFIG=false','public.ecr.aws/supabase/postgrest:v14.5'],
  {env:{...process.env,PGRST_DB_URI:uri.toString(),PGRST_JWT_SECRET:secreto}}); levantado=true;
  const base=`http://127.0.0.1:${puerto}`;
  for(let n=0;n<40;n++) {
    try { const r=await fetch(base,{signal:AbortSignal.timeout(1000)}); if(r.status===503) throw new Error('Caché inicial pendiente'); break; }
    catch { if(n===39) throw new Error('PostgREST H3 no inició'); await new Promise(r=>setTimeout(r,250)); }
  }
  const rpc=async(actor,args,rol='authenticated')=>{
    const respuesta=await fetch(`${base}/rpc/gestion_diaria_pendientes_fn`,{method:'POST',
      headers:{'Content-Type':'application/json','Content-Profile':'crm',...(actor?{Authorization:`Bearer ${jwt(actor,rol)}`}:{})},body:JSON.stringify(args)});
    return {status:respuesta.status,body:await respuesta.json()};
  };
  let cursor={}, total=0, paginas=0; const ids=new Set();
  do {
    const r=await rpc(actores.supervisor,{p_analista_id:actores.vendedor,p_limite:100,...cursor});
    assert.equal(r.status,200,JSON.stringify(r.body)); assert.equal(r.body.resumen.tareas_pendientes,1008);
    r.body.items.forEach(t=>{assert.ok(!ids.has(t.id)); ids.add(t.id);});
    total+=r.body.items.length; paginas++;
    cursor=r.body.hay_mas?{p_despues_de:r.body.siguiente_cursor.despues_de,p_despues_id:r.body.siguiente_cursor.despues_id}:null;
  } while(cursor);
  assert.equal(total,1008); assert.equal(paginas,11);
  for(const actor of [actores.vendedor,actores.coordinador,actores.gerente,actores.global]) {
    const r=await rpc(actor,{p_analista_id:actores.vendedor}); assert.equal(r.status,403); assert.equal(r.body.code,'42501');
  }
  const ajeno=await rpc(actores.supervisor,{p_analista_id:actores.ajeno}); assert.equal(ajeno.status,403); assert.equal(ajeno.body.code,'42501');
  const invalido=await rpc(actores.supervisor,{p_analista_id:actores.vendedor,p_limite:101}); assert.equal(invalido.status,400); assert.equal(invalido.body.code,'22023');
  const anon=await rpc(null,{p_analista_id:actores.vendedor}); assert.ok([401,403,404].includes(anon.status));
  // Revocación con el mismo JWT: el servidor reevalúa equipo.activo.
  pg(`begin;alter table crm.equipo disable trigger user;update crm.equipo set activo=false where perfil_id='${actores.supervisor}';alter table crm.equipo enable trigger user;commit;`);
  const revocada=await rpc(actores.supervisor,{p_analista_id:actores.vendedor}); assert.equal(revocada.status,403); assert.equal(revocada.body.code,'42501');
  console.log('PASS HTTP real PostgREST 14.5: 1008 tareas/11 páginas, cuatro roles denegados, ajeno, anon, 22023 y revocación con el mismo JWT');
} finally {
  if(levantado) docker(['stop',servicio]);
  if(creada) docker(['exec',contenedor,'dropdb','-U','supabase_admin',copia]);
}
