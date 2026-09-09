// Ensayo del SQL EXACTO en una copia nueva y sintética. No reinicia el banco HTTP.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {randomUUID,createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {banco,contenedor} from './banco-local.mjs';
const db=`f5_replay_${randomUUID().replaceAll('-','').slice(0,12)}`;
assert.match(db,/^f5_replay_[a-f0-9]{12}$/);
const run=(args,input)=>{
 const r=spawnSync('docker',['exec','-i',contenedor,...args],{input,encoding:'utf8',maxBuffer:16*1024*1024});
 assert.equal(r.status,0,r.stderr);return r.stdout.trim();
};
const sql=(text,transaction=false)=>run(['psql','-X','-qAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1',
 ...(transaction?['--single-transaction']:[]),'-f','-'],text);
run(['psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',`create database ${db} template template0`]);
// El dump incluye public; la base recién creada trae ese schema vacío.
sql('drop schema public');
// El respaldo de negocio excluye extensiones administradas por Supabase.
// Sus tipos/operadores son prerrequisitos del schema, no sustitutos de constraints.
sql(`create schema extensions;
create extension pgcrypto with schema extensions;
create extension "uuid-ossp" with schema extensions;
create extension btree_gist with schema extensions;
create extension pg_trgm with schema extensions;`);
const dump=readFileSync(`${banco}/base-sintetica.dump`);
run(['pg_restore','--exit-on-error','-U','supabase_admin','-d',db],dump);
assert.equal(sql("select to_regclass('crm.cartera_lecturas') is null"),'t');
const firmas=`select coalesce(jsonb_agg(jsonb_build_array(n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
 md5(pg_get_functiondef(p.oid)),p.proacl,p.proowner) order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),'[]')
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','crm','private') and p.prokind='f'
 and p.proname not in ('cartera_f5_fuentes','cartera_f5_exigir','cartera_f5_personas_visibles','cartera_f5_registrar',
 'cartera_inversionistas_estado_fn','cartera_inversionistas_fn','inversionista_ficha_fn','inversionista_cuentas_fn','inversionista_documento_fn')`;
const fuentes=()=>sql(`select jsonb_build_object('contratos',(select count(*) from public.contratos),
 'capital',(select sum(capital) from public.contratos),'cronograma',(select count(*) from public.cronograma_pagos),
 'cierres',(select count(*) from crm.cierres_externos),'monto',(select sum(monto) from crm.cierres_externos),
 'auth',(select count(*) from auth.users),'personas',(select count(*) from crm.inversionistas),
 'banderas',(select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags))`);
const cuerpos=sql(firmas),antes=fuentes();
const candidato=readFileSync(new URL('../../migrations/20260908230249_crm_f5_cartera_ficha_multiempresa.sql',import.meta.url),'utf8');
sql(candidato,true);
const correccion=readFileSync(new URL('../../migrations/20260909170900_crm_f5_candado_estado_cartera.sql',import.meta.url),'utf8');
sql(correccion,true);
assert.equal(sql(firmas),cuerpos,'Una función publicada ajena a F5 cambió');
assert.equal(fuentes(),antes,'La migración cambió fuentes, identidades, Auth o banderas');
assert.equal(sql("select has_function_privilege('anon','crm.inversionista_ficha_fn(uuid,integer,integer)','execute')"),'f');
// Reversa ensayada sobre la copia, sin borrar la lectura ni los datos.
sql("update crm.multiempresa_flags set activo=true where nombre='ficha_360_neutral'");
sql(readFileSync(new URL('reversa-operativa.sql',import.meta.url),'utf8'));
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='ficha_360_neutral'"),'f');
assert.equal(fuentes(),antes);assert.equal(sql(firmas),cuerpos);
const hash=x=>createHash('sha256').update(x).digest('hex');
writeFileSync(`${banco}/evidencia-replay.json`,JSON.stringify({estado:'PASS',db,baseSintetica:hash(dump),
 sql:hash(candidato),correccion:hash(correccion),funcionesPublicadasConservadas:true,fuentesBanderasAuthConservadas:true,reversa:'PASS'},null,2)+'\n',{mode:0o600});
console.log('Replay F5 PASS: copia sintética nueva, migración exacta y reversa; funciones publicadas y dinero intactos.');
