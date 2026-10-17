// CLI oficial verificada (sha256 del release) dentro del namespace sin egreso.
// Compara esquema nativo y las candidatas sobre el MISMO clon vacío.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { nombres, cuerpoMigracion } from './migraciones-locales.mjs'

const contenedor='avancecorp-tc-20261016'
const base=`tc_venta_advisors_${process.pid}`
const carpeta='/private/tmp/avancecorp-tc-20261016'
const archivo=readFileSync(`${carpeta}/supabase-linux-arm64.tar.gz`)
const release=JSON.parse(readFileSync(`${carpeta}/supabase-release.json`,'utf8'))
assert.equal(release.tag_name,'v2.117.0')
assert.equal(release.assets.find(a=>a.name==='supabase_linux_arm64.tar.gz')?.digest,
  'sha256:'+createHash('sha256').update(archivo).digest('hex'))
function docker(args,opciones={}) {
  const r=spawnSync('docker',args,{encoding:'utf8',timeout:120000,maxBuffer:8*1024*1024,...opciones})
  assert.equal(r.status,0,r.stderr||r.error?.message)
  return r.stdout.trim()
}
function sql(texto,db=base) {
  assert.ok([base,'postgres'].includes(db))
  return docker(['exec','-i',contenedor,'psql','-XqAt','-U','supabase_admin','-d',db,'-v','ON_ERROR_STOP=1','-f','-'],{input:texto})
}
function advisors(etapa) {
  const nombre=`tc-venta-advisors-${process.pid}-${etapa}`
  const args=['run','--rm','--pull=never','--name',nombre,'--network',`container:${contenedor}`,
    '--label','avancecorp.task=tc-venta-advisors','--cap-drop','ALL','--read-only','--security-opt','no-new-privileges=true',
    '--tmpfs','/tmp','--tmpfs','/root','--mount',`type=bind,src=${carpeta}/supabase,dst=/opt/supabase,readonly`,
    'mcr.microsoft.com/playwright:v1.61.1-noble','/opt/supabase','db','advisors',
    '--db-url',`postgresql://supabase_admin:local-tc-aislado@127.0.0.1:5432/${base}?sslmode=disable`,
    '--type','all','--level','info','--fail-on','none','--output-format','json']
  const salida=docker(args)
  writeFileSync(`${carpeta}/advisors-${etapa}.json`,salida+'\n',{mode:0o600})
  console.log(`PASS: CLI Advisors ${etapa} ejecutado; revisar findings, no implica ausencia de avisos`)
}
const banco=JSON.parse(docker(['inspect',contenedor]))[0]
assert.equal(banco.HostConfig.NetworkMode,'none')
assert.deepEqual(banco.HostConfig.PortBindings??{},{})
let creada=false
try {
  sql(`create database ${base} template tc_venta;`,'postgres');creada=true
  sql(readFileSync(new URL('reversa-persistencia.sql',import.meta.url),'utf8'))
  advisors('antes')
  sql(readFileSync(new URL('../../migrations/20261016190725_crm_tipo_cambio_por_venta.sql',import.meta.url),'utf8'))
  sql('begin;\n'+nombres.map(cuerpoMigracion).join('\n')+'\ncommit;')
  advisors('despues')
} finally {
  if(creada)sql(`drop database ${base} with(force);`,'postgres')
}
