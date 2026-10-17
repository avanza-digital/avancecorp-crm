import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { nombres, cuerpoMigracion } from './migraciones-locales.mjs'

const contenedor='avancecorp-tc-20261016'
const base=`tc_venta_tipos_${process.pid}`
function docker(args,opciones={}) {
  const r=spawnSync('docker',args,{encoding:'utf8',timeout:120000,maxBuffer:8*1024*1024,...opciones})
  assert.equal(r.status,0,r.stderr||r.error?.message)
  return r.stdout.trim()
}
function sql(texto,db=base) {
  assert.ok([base,'postgres'].includes(db))
  return docker(['exec','-i',contenedor,'psql','-XqAt','-U','supabase_admin','-d',db,'-v','ON_ERROR_STOP=1','-f','-'],{input:texto})
}
const banco=JSON.parse(docker(['inspect',contenedor]))[0]
assert.equal(banco.HostConfig.NetworkMode,'none')
assert.deepEqual(banco.HostConfig.PortBindings??{},{})
const actual=readFileSync(new URL('../../../app/src/lib/database.types.ts',import.meta.url),'utf8')
const version=actual.match(/PostgrestVersion:\s*"(\d+\.\d+(?:\.\d+)?)"/)?.[1]
assert.ok(version,'Conservar metadata PostgREST del cliente vigente')
let creada=false
try {
  sql(`create database ${base} template tc_venta;`,'postgres');creada=true
  sql(readFileSync(new URL('reversa-persistencia.sql',import.meta.url),'utf8')+'\n'+
    readFileSync(new URL('../../migrations/20261016190725_crm_tipo_cambio_por_venta.sql',import.meta.url),'utf8'))
  sql('begin;\n'+nombres.map(cuerpoMigracion).join('\n')+'\ncommit;')
  const salida=docker(['run','--rm','--pull=never','--network',`container:${contenedor}`,
    '--label','avancecorp.task=tc-venta-tipos','--cap-drop','ALL','--read-only','--security-opt','no-new-privileges=true',
    '-e','PG_META_DB_HOST=127.0.0.1','-e','PG_META_DB_PORT=5432',`-e`,`PG_META_DB_NAME=${base}`,
    '-e','PG_META_DB_USER=supabase_admin','-e','PG_META_DB_PASSWORD',
    '-e','PG_META_DB_SSL_MODE=disable','-e','PG_META_GENERATE_TYPES=typescript',
    '-e','PG_META_GENERATE_TYPES_INCLUDED_SCHEMAS=public,crm','-e','PG_META_GENERATE_TYPES_DETECT_ONE_TO_ONE_RELATIONSHIPS=true',
    '-e',`PG_META_POSTGREST_VERSION=${version}`,'public.ecr.aws/supabase/postgres-meta:v0.99.0'],
    {env:{...process.env,PG_META_DB_PASSWORD:'local-tc-aislado'}})
  assert.ok(salida.startsWith('export type Json ='))
  writeFileSync('/private/tmp/avancecorp-tc-20261016/database-candidato.types.ts',salida+'\n',{mode:0o600})
  console.log(`PASS: tipos oficiales completos, ${nombres.length+1} candidatas, public/crm y metadata PostgREST ${version}; clon retirado al terminar`)
} finally {
  if(creada)sql(`drop database ${base} with(force);`,'postgres')
}
