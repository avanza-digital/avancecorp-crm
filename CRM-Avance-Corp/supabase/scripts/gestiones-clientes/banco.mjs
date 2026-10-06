// Destino fijo sintético. No acepta URL ni credenciales externas.
import { spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import assert from 'node:assert/strict'
import { catalogosUiSql } from './catalogo-ui.mjs'
const contenedor = 'supabase_db_crm-avance-corp-local'
const db = 'gestiones_clientes_20261006'
const sello = 'BANCO SINTETICO gestiones clientes 20261006 / sin produccion'
function psql(base, texto, verificar = true) {
  const guardia = verificar ? `do $$ begin if current_database()<>'${db}' or shobj_description((select oid from pg_database where datname=current_database()),'pg_database') is distinct from '${sello}' then raise exception 'Banco incorrecto'; end if; end $$;\n` : ''
  const r = spawnSync('docker', ['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',base,'-v','ON_ERROR_STOP=1','-f','-'], {input:guardia+texto,encoding:'utf8',maxBuffer:16*1024*1024})
  assert.equal(r.status,0,(r.stderr||r.error?.message||'')+'\n'+(r.stdout||''))
  return r.stdout.trim()
}
const orden=process.argv[2]
if (orden==='crear') {
  assert.equal(psql('postgres',`select 1 from pg_database where datname='${db}'`,false),'','El banco ya existe')
  psql('postgres',`create database ${db} template base_gestion_20261002;`,false)
  psql('postgres',`comment on database ${db} is '${sello}';`,false)
  console.log('PASS banco propio creado')
} else if (orden==='esquema') {
  const ruta=process.argv[3]
  assert(ruta?.startsWith('/private/tmp/'), 'Solo snapshot local de esquema')
  const esquema=readFileSync(ruta,'utf8')
  const nombres=['gestion_diaria_equipo_ambito','gestion_diaria_citas_core','gestion_diaria_citas_fn','gestion_diaria_pendientes_core','gestion_diaria_pendientes_fn']
  for (const nombre of nombres) {
    const ini=esquema.indexOf(`CREATE OR REPLACE FUNCTION "${nombre.endsWith('_fn')?'crm':'private'}"."${nombre}"(`)
    assert(ini>=0,nombre)
    const fin=esquema.indexOf('\nALTER FUNCTION',ini)
    assert(fin>ini,nombre)
    psql(db,esquema.slice(ini,fin))
  }
  psql(db,`revoke all on function crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid),private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid) from public,anon,service_role; grant execute on function crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid),private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid) to authenticated;`)
  psql(db,'revoke all on function private.gestion_diaria_equipo_ambito(uuid) from public,anon,service_role; grant execute on function private.gestion_diaria_equipo_ambito(uuid) to authenticated;')
  psql(db,'revoke all on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid),crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) from public,anon,service_role; grant execute on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid),crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) to authenticated;')
  // La plantilla sintética excluía ACL de auth. USAGE coincide con el stack
  // Supabase local (sin SELECT sobre usuarios ni sesiones).
  psql(db, 'grant usage on schema auth to anon,authenticated,service_role; grant execute on function auth.uid() to anon,authenticated,service_role;')
  console.log('PASS prerequisitos G4b y ACL Auth del stack local')
} else if (orden==='actualizar-lecturas') {
  // Iterar únicamente la migración aún no publicada en este banco sellado.
  const ddl=readFileSync(new URL('../../migrations/20261006012208_crm_gestiones_clientes_supervision.sql',import.meta.url),'utf8')
    .replace(/^begin;$/m,'').replace(/^commit;$/m,'').replace(/^create function /gm,'create or replace function ')
  console.log(psql(db,`begin;
    drop function if exists private.gestiones_operativas_eventos(date,date,uuid[]);
    drop function if exists private.gestiones_clientes_eventos(date,date,uuid[]);
    ${ddl}
    commit;`))
  console.log('PASS lectores actualizados solo en '+db)
} else if (orden==='ensayar' || orden==='instalar' || orden==='probar' || orden==='volumen') {
  const migrations=['20261005224214_crm_resultados_cliente_postventa.sql','20261006012208_crm_gestiones_clientes_supervision.sql']
  const fuentes=migrations.map(n=>readFileSync(new URL('../../migrations/'+n,import.meta.url),'utf8').replace(/^begin;$/m,'').replace(/^commit;$/m,''))
  const test=['test.sql','test-casos.sql','test-integracion.sql'].map(n=>readFileSync(new URL(n,import.meta.url),'utf8')).join('\n')
    +'\n'+await catalogosUiSql()+'\n'+readFileSync(new URL('test-revision.sql',import.meta.url),'utf8')
    +(orden==='volumen'?'\n'+readFileSync(new URL('test-volumen.sql',import.meta.url),'utf8'):'')
  if (orden==='instalar') {
    assert.equal(psql(db,"select md5(prosrc) from pg_proc where oid='crm.postventa_tarea_fn(uuid,uuid,integer,text,jsonb,uuid)'::regprocedure"),'4fe2e158e6d359fcc25c64bc6624d2e5','Solo instalar una vez sobre la base sintética')
    console.log(psql(db,'begin;\n'+fuentes.join('\n')+'\ncommit;'))
    console.log('PASS migraciones instaladas solo en '+db)
  } else console.log(psql(db,'begin;\n'+(orden==='ensayar'?fuentes.join('\n'):'')+'\n'+test+'\nrollback;'))
} else if (orden==='consulta') {
  console.log(psql(db,readFileSync(0,'utf8')))
} else if (orden==='tipos') {
  // Guarda los contratos de las nuevas RPC para compararlos con los tipos del cliente.
  writeFileSync(new URL('./firmas-locales.txt',import.meta.url),psql(db,"select p.oid::regprocedure,pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname in ('registro_actividad_v2_fn','gestiones_resumen_fn','citas_clientes_fn','gestion_diaria_citas_v2_fn','gestion_diaria_pendientes_v2_fn');"))
} else throw new Error('Usa crear | esquema <snapshot> | ensayar | instalar | actualizar-lecturas | probar | volumen | consulta | tipos')
