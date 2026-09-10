// Solo la copia sintética del banco F5. Nunca recibe destino ni credenciales externas.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {randomUUID,createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {banco,contenedor} from '../f5/banco-local.mjs';
const db=`f6_replay_${randomUUID().replaceAll('-','').slice(0,12)}`;
assert.match(db,/^f6_replay_[a-f0-9]{12}$/);
const run=(args,input)=>{const r=spawnSync('docker',['exec','-i',contenedor,...args],{input,encoding:'utf8',maxBuffer:32*1024*1024});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
const sql=(texto,transaccion=false)=>run(['psql','-X','-qAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1',...(transaccion?['--single-transaction']:[]),'-f','-'],texto);
const funciones=()=>JSON.parse(sql(`select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,'md5',md5(pg_get_functiondef(p.oid)),'acl',p.proacl,'propietario',p.proowner) order by p.oid::regprocedure::text)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','crm','private') and p.prokind='f'`));
const fuentes=()=>Object.fromEntries(['public.contratos','public.cronograma_pagos','crm.inversiones','crm.cierres_externos','crm.depositos_reclamados','crm.inversion_solicitudes','crm.inversionistas','crm.inversionista_identificadores','crm.leads','crm.tareas','auth.users'].map(tabla=>[tabla,sql(`select md5(coalesce(string_agg((to_jsonb(t)${tabla==='crm.tareas'?"-'inversionista_id'-'postventa_revision'":''})::text,'' order by (to_jsonb(t)${tabla==='crm.tareas'?"-'inversionista_id'-'postventa_revision'":''})::text),'')) from ${tabla} t`)]));
const archivos=['20260908230249_crm_f5_cartera_ficha_multiempresa.sql','20260909170900_crm_f5_candado_estado_cartera.sql','20260910150039_crm_f6_postventa_persona.sql'];
const textos=archivos.map(a=>readFileSync(new URL(`../../migrations/${a}`,import.meta.url),'utf8'));
const hash=x=>createHash('sha256').update(x).digest('hex');
run(['psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',`create database ${db} template template0`]);
try {
 sql('drop schema public;create schema extensions;create extension pgcrypto with schema extensions;create extension "uuid-ossp" with schema extensions;create extension btree_gist with schema extensions;create extension pg_trgm with schema extensions;');
 run(['pg_restore','--exit-on-error','-U','supabase_admin','-d',db],readFileSync(`${banco}/base-sintetica.dump`));
 sql(textos[0],true);sql(textos[1],true);
 const antes=fuentes(),defs=funciones(),flags=sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags');
 const admitidas=new Set(['private.trg_tareas_destino_efectivo()','private.agenda_ics_feed_implementacion(uuid,timestamp with time zone)',
 'crm.marcar_no_contactar(uuid,text)','private.inversion_solicitud_resultado(uuid,jsonb)','crm.inversionista_ficha_fn(uuid,integer,integer)',
 'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)']);
 writeFileSync(`${banco}/f6-funciones-base.json`,JSON.stringify(defs,null,2)+'\n',{mode:0o600});
 sql(textos[2]);
 const actuales=new Map(funciones().map(f=>[f.firma,f]));
 for(const def of defs){const ahora=actuales.get(def.firma);assert.ok(ahora,def.firma);assert.deepEqual(ahora.acl,def.acl,`ACL ${def.firma}`);assert.equal(ahora.propietario,def.propietario);
  if(!admitidas.has(def.firma))assert.equal(ahora.md5,def.md5,`Función ajena modificada: ${def.firma}`);
 }
 assert.deepEqual(fuentes(),antes,'F6 modificó datos anteriores');
 assert.equal(sql("select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags where nombre<>'postventa_neutral'"),flags);
 assert.equal(sql("select activo from crm.multiempresa_flags where nombre='postventa_neutral'"),'f');
 assert.equal(sql("select count(*) from crm.postventa_escrituras"),'0');
 assert.equal(sql("select count(*) from crm.inversionista_gestiones"),'0');
 assert.equal(sql("select has_function_privilege('anon','crm.postventa_tarea_fn(uuid,uuid,integer,text,jsonb,uuid)','execute')"),'f');
 sql("update crm.multiempresa_flags set activo=true where nombre='postventa_neutral'");
 sql(readFileSync(new URL('reversa-operativa.sql',import.meta.url),'utf8'));
 assert.equal(sql("select activo from crm.multiempresa_flags where nombre='postventa_neutral'"),'f');assert.deepEqual(fuentes(),antes);
 assert.equal(sql(`select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private','public') and strpos(p.prosrc,'resolver_en_puertas')>0 and strpos(p.prosrc,'crm_flag_resolver_en_puertas')=0 and strpos(p.prosrc,'resolver_en_puertas_bajo_candado')=0`),'0');
 const evidencia={estado:'PASS',archivos:archivos.map((archivo,i)=>({archivo,sha256:hash(textos[i])})),funcionesPreexistentes:defs.length,integracionesPrevistas:admitidas.size,fuentesAuthIdentidadesConservadas:true,banderasAnterioresConservadas:true,nuevaBanderaOFF:true,reversa:'PASS',d19:0};
 writeFileSync(`${banco}/evidencia-replay-f6.json`,JSON.stringify(evidencia,null,2)+'\n',{mode:0o600});
 console.log(JSON.stringify(evidencia,null,2));
} finally {
 run(['psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',`drop database ${db}`]);
}
