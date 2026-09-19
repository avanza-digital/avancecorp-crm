// Replay y reversa sobre una SEGUNDA copia exclusiva, nunca sobre el banco HTTP.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {sql,q,replayDb,baseDb} from './banco.mjs';
if(sql(`select count(*) from pg_database where datname=${q(replayDb)}`,'postgres')==='0')
  sql(`create database ${replayDb} template ${baseDb}`,'postgres','supabase_admin');
const ejecutar=s=>sql(s,replayDb,'supabase_admin');
const publico=`select jsonb_build_object(
 'funciones',(select jsonb_object_agg(p.oid::regprocedure::text,md5(pg_get_functiondef(p.oid))) from pg_proc p where pronamespace='public'::regnamespace),
 'columnas',(select jsonb_agg(to_jsonb(c) order by table_name,ordinal_position) from information_schema.columns c where table_schema='public'),
 'policies',(select jsonb_agg(to_jsonb(p) order by tablename,policyname) from pg_policies p where schemaname='public'),
 'triggers',(select jsonb_object_agg(t.oid::text,pg_get_triggerdef(t.oid)) from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace='public'::regnamespace))`;
assert.equal(ejecutar("select count(*) from information_schema.columns where table_schema='crm' and table_name='inversion_solicitudes' and column_name='lead_origen_id'"),'0','La copia ya tiene el cambio; no se reinicia automáticamente.');
const antes=ejecutar(publico);
ejecutar(readFileSync(new URL('../../migrations/20260919161807_crm_conversion_inversion_unificada.sql',import.meta.url),'utf8'));
assert.equal(ejecutar(publico),antes,'Se alteró el contrato de public');
ejecutar(readFileSync(new URL('./test-conversion.sql',import.meta.url),'utf8'));
const nuevos=JSON.parse(ejecutar(`select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,'huella',md5(pg_get_functiondef(p.oid)),
  'owner',pg_get_userbyid(p.proowner),'config',p.proconfig,'acl',p.proacl))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where
    (n.nspname='crm' and p.proname in ('preparar_persona_lead_inversion_fn','contexto_conversion_inversion_fn','bienvenida_inversion_estado_fn','bienvenida_inversion_entrega_fn','cancelar_solicitud_inversion_fn'))
    or (n.nspname='private' and (p.proname in ('conversion_reserva_legacy_cerrada','inversion_origen_inmutable','conversion_lead_con_inversion','inversion_persona_lectura','inversion_contexto_lectura')
      or (p.proname='inversion_persona_contexto' and p.pronargs=2)))`));
assert.equal(nuevos.length,11);
for(const f of nuevos){assert.equal(f.owner,'postgres');assert(f.config.includes('search_path=""'));
  for(const rol of ['anon','authenticated','service_role']){
    const permitido=f.firma.startsWith('crm.') && (f.firma.includes('entrega_fn')?rol==='service_role':rol==='authenticated');
    assert.equal(ejecutar(`select has_function_privilege(${q(rol)},${q(f.firma)},'execute')`),permitido?'t':'f',`${f.firma} ${rol}`);
  }
}
const revertir=readFileSync(new URL('./reversa.sql',import.meta.url),'utf8');
ejecutar(revertir);
assert.equal(ejecutar(publico),antes,'La reversa alteró public');
const base=JSON.parse(readFileSync(new URL('./baseline-funciones.json',import.meta.url),'utf8'));
for(const f of base){const firma=`${f.esquema}.${f.nombre}(${f.argumentos.split(', ').map(x=>x.split(' ').slice(1).join(' ')).join(',')})`;
  assert.equal(ejecutar(`select md5(pg_get_functiondef(${q(firma)}::regprocedure))`),f.huella,`Reversa ${firma}`);
}
const evidencia={estado:'PASS',fecha:new Date().toISOString(),base:replayDb,
  checks:['migración completa desde template sin cambios candidatos','oráculo económico rollback','11 funciones nuevas: owner, search_path y 33 permisos',
    'public idéntico antes/después','reversa conserva esquema aditivo y restaura 16 funciones base'],funciones:nuevos};
writeFileSync('/private/tmp/avancecorp-conversion-inversion/evidencia-replay.json',JSON.stringify(evidencia,null,2)+'\n');
console.log('PASS: migración completa, dominio SQL, permisos y reversa en copia exclusiva; public intacto.');
