import { readFileSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'
const banco='avancecorp-citas-fecha-20261017'
const evidencia=process.env.CITAS_EVIDENCIA
assert.ok(evidencia, 'CITAS_EVIDENCIA debe contener las definiciones anteriores extraídas de solo lectura')
function docker(args,input) {
 const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:32*1024*1024,timeout:120000})
 if(r.status!==0) throw new Error(r.stderr || r.error || 'Falló Docker')
 return {stdout:r.stdout,stderr:r.stderr}
}
assert.equal(docker(['inspect','--format','{{.HostConfig.NetworkMode}}',banco]).stdout.trim(),'none')
let sql=readFileSync(new URL('./prueba.sql',import.meta.url),'utf8')
for(const [marca,archivo,nombre] of [['LECTOR','citas_gerencia_consulta','lector_antes'],['TESTIGO','citas_testigo_mes','testigo_antes']]) {
 const anterior=readFileSync(`${evidencia}/private.${archivo}.sql`,'utf8').trim().replace(`private.${archivo}(`,`pg_temp.${nombre}(`)+';'
 sql=sql.replace(`-- @${marca}_ANTERIOR@`,anterior)
}
const r=docker(['exec','-i',banco,'psql','-X','-qAt','-U','supabase_admin','-d','citas_final','-v','ON_ERROR_STOP=1'],sql)
writeFileSync(`${evidencia}/sql-prueba.log`,r.stdout+'\n'+r.stderr)
for (const linea of r.stdout.split('\n').filter(l=>l.startsWith('{'))) {
 const dato=JSON.parse(linea)
 if(dato.fixture) writeFileSync(`${evidencia}/banco-${dato.fixture}.json`,JSON.stringify(dato.payload))
}
console.log(r.stderr)
