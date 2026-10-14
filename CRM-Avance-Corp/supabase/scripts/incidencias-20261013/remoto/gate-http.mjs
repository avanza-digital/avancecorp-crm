import assert from 'node:assert/strict';
import{readFileSync,openSync,closeSync,writeFileSync}from'node:fs';
import{spawnSync}from'node:child_process';
import{fileURLToPath}from'node:url';
import{createHash}from'node:crypto';
import{carpeta,cfg,env as pgEnv,sql,objeto}from'./banco.mjs';
import{restaurarBandera}from'./restaurar-bandera.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.equal(JSON.parse(readFileSync(`${carpeta}/sql-resultados.json`)).estado,'PASS');
const env={...pgEnv,PATH:'/opt/homebrew/opt/postgresql@17/bin:'+process.env.PATH,
 SUPABASE_URL:cfg.SUPABASE_URL,SUPABASE_ANON_KEY:cfg.SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY:cfg.SUPABASE_SERVICE_ROLE_KEY,
 CRM_DEMO_PASSWORD:JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`)).password,CRM_BANCO_PSQL_URL:cfg.POSTGRES_URL,
 CRM_RLS_EXIGE_GESTION_DIARIA:'1',CRM_RLS_EXIGE_COLA_V3:'1',CRM_RLS_EXIGE_CUENTAS_PAGO:'1',CRM_RLS_EXIGE_GRUPO_A:'1'};
const archivo=fileURLToPath(new URL('../../test-rls.mjs',import.meta.url));
const sha256=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const evidencia={inicio:new Date().toISOString(),gateSha256:sha256(archivo),
 migraciones:Object.fromEntries(['20261014001044_crm_f7_redeclarar_huella_metricas_cartera.sql',
 '20261014001346_crm_sla_agrupar_tareas_por_lead.sql'].map(n=>[n,sha256(new URL('../../../migrations/'+n,import.meta.url))]))};
const pre=spawnSync(process.execPath,[archivo,'--preflight'],{env,encoding:'utf8'});
assert.equal(pre.status,0,pre.stderr);console.log('PASS: preflight HTTP con destino banco-f7.');
// El gate ensaya potencial OFF y ON por sí mismo. La política productiva viene
// encendida; se preserva su fila exacta y se restaura incluso si falla la suite.
const flag=objeto("select to_jsonb(f) from crm.multiempresa_flags f where nombre='potencial_lead'");
assert.ok(flag&&typeof flag.activo==='boolean');
writeFileSync(`${carpeta}/gate-http-inicio.json`,JSON.stringify({...evidencia,flag}),{mode:0o600});
assert.equal(sql('select count(*) from crm.lead_potencial'),'0','El fixture debe iniciar sin marcas');
sql("update crm.multiempresa_flags set activo=false where nombre='potencial_lead'");
const fd=openSync(`${carpeta}/gate-http.log`,'w',0o600);
const inicio=Date.now();let r;try{r=spawnSync(process.execPath,[archivo],{env,stdio:['ignore',fd,fd],timeout:7200000});}finally{
 closeSync(fd);
 restaurarBandera(flag);
}
assert.equal(sha256(archivo),evidencia.gateSha256,'El gate cambió durante la corrida');
writeFileSync(`${carpeta}/gate-http-estado.json`,JSON.stringify({...evidencia,fin:new Date().toISOString(),estado:r.status===0?'PASS':'FAIL',exit:r.status,segundos:Math.round((Date.now()-inicio)/1000),error:r.error?.message??null}),{mode:0o600});
console.log(`Gate HTTP ${r.status===0?'PASS':'FAIL'}; log privado ${carpeta}/gate-http.log`);process.exitCode=r.status===0?0:1;
