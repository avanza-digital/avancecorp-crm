// Destino cerrado: copia sintética aislada. Nunca acepta URL, contenedor ni base
// proporcionados por el llamador.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawn, spawnSync} from 'node:child_process';

export const contenedor='supabase_db_avancecorp-f5-bank';
export const dbFuente='multiempresa_f7_20260911';
export const db='multiempresa_f8_20260913';
const dump='/tmp/multiempresa_f8_base.dump';
const listaRestore='/tmp/multiempresa_f8_restore.list';
export const migracion=readFileSync(new URL(
  '../../migrations/20260913215240_crm_f8_piloto_controlado.sql',import.meta.url),'utf8');
export const migracionDemo=readFileSync(new URL(
  '../../migrations/20260914025926_crm_f8_excluir_fuentes_demo.sql',import.meta.url),'utf8');
export const reversaDemo=readFileSync(new URL('./demos/reversa.sql',import.meta.url),'utf8');

export const literal=v=>v===null?'null':`'${String(v).replaceAll("'","''")}'`;

function ejecutar(args,{input}={}) {
  const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:32*1024*1024});
  assert.equal(r.status,0,r.stderr||r.error?.message||'Falló el banco aislado F8');
  return r.stdout.trim();
}

export function sql(texto) {
  return ejecutar(['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,
    '-v','ON_ERROR_STOP=1','-f','-'],{input:`set timezone='America/Lima';\n${texto}\n`});
}

export function sqlAsync(texto) {
  return new Promise(resolve=>{
    const proceso=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U',
      'postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-']);
    let stdout='',stderr='';
    proceso.stdout.setEncoding('utf8');proceso.stderr.setEncoding('utf8');
    proceso.stdout.on('data',x=>{stdout+=x;});proceso.stderr.on('data',x=>{stderr+=x;});
    proceso.on('close',status=>resolve({status,stdout:stdout.trim(),stderr:stderr.trim()}));
    proceso.stdin.end(`set timezone='America/Lima';\n${texto}\n`);
  });
}

export const como=(actor,consulta)=>`set local role authenticated;
  set local request.jwt.claim.sub=${literal(actor)};
  ${consulta}`;

export const errorEsperado=(codigo,consulta)=>`do $error$
begin
  begin
    ${consulta.trim().replace(/;+\s*$/,'')};
    raise exception 'Faltó el rechazo esperado ${codigo}';
  exception when sqlstate '${codigo}' then null;
  end;
end;
$error$;`;

export function huellaEconomica() {
  return sql(`select jsonb_build_object(
    'contratos',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from public.contratos t),
    'cierres',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from crm.cierres_externos t),
    'inversiones',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from crm.inversiones t),
    'personas',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from crm.inversionistas t),
    'titulares',(select md5(coalesce(jsonb_agg(t order by inversion_id,inversionista_id)::text,'')) from crm.inversion_titulares t),
    'periodos',(select md5(coalesce(jsonb_agg(t order by periodo)::text,'')) from crm.periodos_cerrados t),
    'auth',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from auth.users t))`);
}

export function preparar({demos=true}={}) {
  assert.equal(ejecutar(['exec',contenedor,'psql','-X','-qAt','-U','postgres','-d',
    dbFuente,'-c','select current_database()']),dbFuente);
  ejecutar(['exec',contenedor,'pg_dump','-Fc','-U','postgres','-d',dbFuente,'-f',dump]);
  // Nunca cerrar sesiones ajenas para recrear el banco. Los procesos internos
  // (p. ej. autovacuum) los coordina DROP DATABASE, no pg_terminate_backend.
  const conexiones=ejecutar(['exec',contenedor,'psql','-X','-qAt','-U','postgres','-d','postgres','-c',
    `select count(*) from pg_stat_activity where datname=${literal(db)} and backend_type='client backend'`]);
  assert.equal(conexiones,'0','El banco F8 está en uso; no se interrumpen sus sesiones');
  ejecutar(['exec',contenedor,'dropdb','--if-exists','-U','postgres',db]);
  ejecutar(['exec',contenedor,'createdb','-U','postgres','-T','template0',db]);
  // Conserva los ACL de objetos del banco fuente. Solo excluye DEFAULT ACL,
  // que PostgreSQL no permite reasignar sin asumir sus roles propietarios.
  const lista=ejecutar(['exec',contenedor,'pg_restore','-l',dump])
    .split('\n').filter(line=>!line.includes(' DEFAULT ACL ')).join('\n');
  ejecutar(['exec','-i',contenedor,'tee',listaRestore],{input:`${lista}\n`});
  ejecutar(['exec',contenedor,'pg_restore','-U','postgres','-d',db,
    '--no-owner','-L',listaRestore,dump]);
  const antes=huellaEconomica();
  sql(`update crm.multiempresa_flags set activo=false
    where nombre in ('inversiones_escritura','ficha_360_neutral',
      'postventa_neutral','metricas_multiempresa_sombra');`);
  assert.equal(huellaEconomica(),antes,'Preparar banderas alteró hechos económicos');
  sql(migracion);
  if(demos) sql(migracionDemo);
  const despues=huellaEconomica();
  return {antes,despues};
}

export function actores() {
  return JSON.parse(sql(`select jsonb_build_object(
    'gerencia',(select e.perfil_id from crm.equipo e join public.perfiles p on p.id=e.perfil_id
      where e.activo and p.activo and e.rol_crm='gerencia' order by e.perfil_id limit 1),
    'supervisor',(select e.perfil_id from crm.equipo e join public.perfiles p on p.id=e.perfil_id
      where e.activo and p.activo and e.rol_crm='supervisor' order by e.perfil_id limit 1),
    'supervisor_ajeno',(select e.perfil_id from crm.equipo e join public.perfiles p on p.id=e.perfil_id
      where e.activo and p.activo and e.rol_crm='supervisor' order by e.perfil_id offset 1 limit 1),
    'vendedores',(select jsonb_agg(perfil_id order by perfil_id) from (
      select e.perfil_id from crm.equipo e join public.perfiles p on p.id=e.perfil_id
      where e.activo and p.activo and e.rol_crm='vendedor' order by e.perfil_id limit 2) x))`));
}

export function miembrosSql(a) {
  return `insert into crm.piloto_f8_miembros
      (perfil_id,rol_esperado,activo,habilitado_desde,vence_en,motivo,actualizado_por)
    values
      (${literal(a.gerencia)},'gerencia',true,now()-interval '1 minute',now()+interval '2 days','Piloto económico F8',${literal(a.gerencia)}),
      (${literal(a.supervisor)},'supervisor',true,now()-interval '1 minute',now()+interval '2 days','Piloto económico F8',${literal(a.gerencia)}),
      (${literal(a.vendedores[0])},'vendedor',true,now()-interval '1 minute',now()+interval '2 days','Piloto económico F8',${literal(a.gerencia)}),
      (${literal(a.vendedores[1])},'vendedor',true,now()-interval '1 minute',now()+interval '2 days','Piloto económico F8',${literal(a.gerencia)});`;
}

export const activarSql=actor=>`update crm.piloto_f8_control set activo=true,
  inicia_en=now()-interval '1 minute',vence_en=now()+interval '2 days',
  motivo='Piloto económico F8 autorizado',actualizado_por=${literal(actor)};`;
