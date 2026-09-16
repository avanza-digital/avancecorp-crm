import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {db,sql,consulta,q} from './banco.mjs';
assert.equal(sql('select current_database()'),db);
const reversa=new URL('reversa.sql',import.meta.url);
// Repetir en nuestra copia restaura primero la definición original, nunca
// convierte una versión candidata en su propia prueba de compatibilidad.
if(existsSync(reversa)) sql(readFileSync(reversa,'utf8').split('\ndrop function')[0]);
const anterior=sql("select pg_get_functiondef('crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean)'::regprocedure)");
const permisos=()=>sql("select jsonb_build_object('owner',pg_get_userbyid(proowner),'security_definer',prosecdef,'acl',proacl::text) from pg_proc where oid='crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean)'::regprocedure");
const permisosAnteriores=permisos();
// Captura antes de instalar, para comparar la respuesta completa publicada.
const casos=[{}, {p_empresa:'avance'}, {p_empresa:'qorilazo'}, {p_empresa:'prodelco'}, {p_pagina:2},
  {p_texto:'qorilazo',p_empresa:'avance'}, {p_texto:'AC-2026-0016'}];
const llamada=c=>'crm.cartera_inversionistas_fn('+Object.entries(c).map(([k,v])=>`${k}=>${typeof v==='number'?v:q(v)}`).join(',')+')';
const respuestas=casos.map(c=>consulta(llamada(c)));
const migracion=readFileSync(new URL('../../migrations/20260916023055_crm_cartera_filtros_comerciales.sql',import.meta.url),'utf8');
sql('begin;'+migracion+'commit;');
for(const [n,c] of casos.entries()) assert.deepEqual(consulta(llamada(c)),respuestas[n],`Compatibilidad v1 caso ${n}`);
assert.equal(permisos(),permisosAnteriores,'Owner y ACL sin cambios tras instalar');
writeFileSync(reversa,
  '-- Reversa de la RPC publicada; ejecutar solo tras retirar el frontend v2.\n'+anterior+';\n'+
  'drop function crm.cartera_inversionistas_filtrada_fn(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean);\n'+
  'drop function private.cartera_f5_listar(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean,boolean);\n'+
  "notify pgrst,'reload schema';\n");
sql('begin;'+readFileSync(reversa,'utf8')+'commit;');
assert.equal(permisos(),permisosAnteriores,'Owner y ACL sin cambios tras revertir');
assert.equal(sql("select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname='cartera_f5_listar') or (n.nspname='crm' and p.proname='cartera_inversionistas_filtrada_fn')"),'0');
for(const [n,c] of casos.entries()) assert.deepEqual(consulta(llamada(c)),respuestas[n],`Reversa v1 caso ${n}`);
sql('begin;'+migracion+'commit;');
assert.equal(permisos(),permisosAnteriores,'Owner y ACL sin cambios tras reinstalar');
for(const [n,c] of casos.entries()) assert.deepEqual(consulta(llamada(c)),respuestas[n],`Reinstalación v1 caso ${n}`);
writeFileSync(new URL('compatibilidad.json',import.meta.url),JSON.stringify({estado:'PASS',banco:db,
  migracion_sha256:createHash('sha256').update(migracion).digest('hex'),casos,
  reversa:'PASS: respuestas v1, owner, ACL y retirada de funciones nuevas',reinstalacion:'PASS',permisos:JSON.parse(permisosAnteriores)},null,2)+'\n');
console.log('PASS: 7 respuestas v1 completas tras instalar, revertir y reinstalar; owner y ACL idénticos.');
