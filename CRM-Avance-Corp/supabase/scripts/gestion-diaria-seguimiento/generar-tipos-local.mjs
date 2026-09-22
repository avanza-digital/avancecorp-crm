// Mismo generador oficial postgres-meta, dentro del namespace sin egreso de
// la DB autorizada. --local de CLI presupone un alias 'db' que este banco no usa.
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { docker, contenedor, credencialesLocales } from '../gestion-diaria-cortes/http/banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const c=credencialesLocales();
const imagenes=docker(['image','ls','--format','{{.Repository}}:{{.Tag}}']).split('\n');
const imagen=imagenes.find(i=>i==='public.ecr.aws/supabase/postgres-meta:v0.99.0');
assert.ok(imagen,'Falta imagen oficial postgres-meta ya disponible localmente');
const rest=JSON.parse(docker(['inspect','supabase_rest_gestion-diaria-f4-http']))[0];
const version=rest.Config.Image.match(/:v?(\d+\.\d+(?:\.\d+)?)/)?.[1];
assert.ok(version,'Versión de PostgREST no identificada');
const conexion=new URL(c.DB_URL);
const salida=docker(['run','--rm','--pull=never','--name','gestion-diaria-f4-tipos',
  '--label','avancecorp.task=gestion-diaria-f4-http','--network',`container:${contenedor}`,
  '--cap-drop','ALL','--read-only','--security-opt','no-new-privileges=true',
  '--env','PG_META_DB_HOST=127.0.0.1','--env','PG_META_DB_PORT=5432',
  '--env','PG_META_DB_NAME=postgres','--env','PG_META_DB_USER=postgres','--env','PG_META_DB_PASSWORD',
  '--env','PG_META_DB_SSL_MODE=disable','--env','PG_META_GENERATE_TYPES=typescript',
  '--env','PG_META_GENERATE_TYPES_INCLUDED_SCHEMAS=public,crm',
  '--env','PG_META_GENERATE_TYPES_DETECT_ONE_TO_ONE_RELATIONSHIPS=true',
  '--env',`PG_META_POSTGREST_VERSION=${version}`,imagen],
  {env:{...process.env,PG_META_DB_PASSWORD:decodeURIComponent(conexion.password)}});
assert.ok(salida.startsWith('export type Json ='),'No se recibieron tipos TypeScript completos');
writeFileSync('/private/tmp/gd-f4-tipos-generados.ts',salida+'\n',{mode:0o600});
console.log(`PASS: tipos oficiales generados desde gestion-diaria-f4-http; imagen ${imagen}, PostgREST ${version}`);
