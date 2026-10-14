// Recuperación acotada de la tercera corrida: test-rls termina, pero la
// restitución del timestamp falla porque el trigger touch lo sustituye.
// No convierte un test fallido en PASS: exige su resumen canónico sin fallos,
// conserva el error del wrapper y verifica el fixture por separado.
import assert from 'node:assert/strict';
import{readFileSync,writeFileSync,copyFileSync,statSync}from'node:fs';
import{createHash}from'node:crypto';
import{execFileSync}from'node:child_process';
import{carpeta,objeto}from'./banco.mjs';
import{restaurarBandera}from'./restaurar-bandera.mjs';
assert.deepEqual(process.argv.slice(2),['--recuperar-solo-touch']);
const error=JSON.parse(readFileSync(`${carpeta}/wrapper-restauracion-error.json`));
assert.equal(error.exit_code,1);
assert.match(error.output,/AssertionError/);
assert.match(error.output,/actualizado_en/);
assert.ok(!/error fatal|ERROR:/.test(error.output));
const log=readFileSync(`${carpeta}/gate-http.log`,'utf8');
const resumen=log.match(/✅ RLS OK — (\d+) aserciones; gate aprobado/g);
assert.equal(resumen?.length,1);
assert.ok(!/[✗❌]|NO PROBADO|error fatal/.test(log),'El gate tiene fallos');
const sha=b=>createHash('sha256').update(b).digest('hex');
const ruta='CRM-Avance-Corp/supabase/scripts/test-rls.mjs';
const repo=execFileSync('git',['rev-parse','--show-toplevel'],{encoding:'utf8'}).trim();
const fuente=execFileSync('git',['show','0daf3d80:'+ruta],{cwd:repo,maxBuffer:4*1024*1024});
assert.equal(sha(readFileSync(`${repo}/${ruta}`)),sha(fuente));
const linea=readFileSync(`${carpeta}/banderas-fixture.sql`,'utf8').split('\n').find(x=>x.startsWith('potencial_lead\t'));
assert.ok(linea);const campos=linea.split('\t');assert.equal(campos.length,5);assert.equal(campos[1],'t');assert.equal(campos[4],'\\N');
const original={nombre:campos[0],activo:true,descripcion:campos[2],actualizado_en:campos[3],actualizado_por:null};
const literal="'"+JSON.stringify(original).replaceAll("'","''")+"'::jsonb";
const flag=objeto(`select to_jsonb(r) from jsonb_populate_record(null::crm.multiempresa_flags,${literal}) r`);
const actual=objeto("select to_jsonb(f) from crm.multiempresa_flags f where nombre='potencial_lead'");
assert.deepEqual({...actual,actualizado_en:flag.actualizado_en},flag);
restaurarBandera(flag);
copyFileSync(`${carpeta}/gate-http-estado.json`,`${carpeta}/gate-http-estado-intento-anterior.json`);
const migraciones=Object.fromEntries(['20261014001044_crm_f7_redeclarar_huella_metricas_cartera.sql',
 '20261014001346_crm_sla_agrupar_tareas_por_lead.sql'].map(n=>[n,sha(readFileSync(new URL('../../../migrations/'+n,import.meta.url)))]));
const resultado={estado:'PASS',fecha:new Date().toISOString(),gateSha256:sha(fuente),migraciones,
 resumen:resumen[0],logSha256:sha(log),logFin:statSync(`${carpeta}/gate-http.log`).mtime.toISOString(),
 wrapperOriginal:'FAIL únicamente al restaurar actualizado_en; error privado conservado',
 recuperacion:'PASS: bandera y timestamp originales, trigger activo y cero marcas; no se repitió ni omitió ninguna assertion HTTP'};
writeFileSync(`${carpeta}/gate-http-estado.json`,JSON.stringify(resultado,null,2),{mode:0o600});
console.log(JSON.stringify(resultado));
