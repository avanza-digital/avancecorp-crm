// Secuencial: las pruebas cambian temporalmente banderas del mismo banco.
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {banco} from './banco-local.mjs';
const archivos=['lecturas','flujo','fusion','lecturas-bordes','fechas','pdf','documento','concurrencia','candado-estado'];
const resultados=[];
for(const nombre of archivos) {
 const r=spawnSync(process.execPath,['--test',fileURLToPath(new URL(`${nombre}.test.mjs`,import.meta.url))],{encoding:'utf8',maxBuffer:8*1024*1024});
 writeFileSync(`${banco}/${nombre}-final.log`,r.stdout+r.stderr,{mode:0o600});
 const tests=Number(r.stdout.match(/tests (\d+)/)?.[1]??0);
 resultados.push({grupo:nombre,estado:r.status===0?'PASS':'FAIL',tests});
 console.log(`${nombre}: ${r.status===0?'PASS':'FAIL'} (${tests})`);
 if(r.status!==0) {process.exitCode=1;break;}
}
const evidence={estado:resultados.length===archivos.length&&resultados.every(r=>r.estado==='PASS')?'PASS':'FAIL',
 entorno:'Banco cerrado F5: Auth/PostgREST/Storage reales y datos sintéticos',terminadoEn:new Date().toISOString(),resultados,
 totalTests:resultados.reduce((n,r)=>n+r.tests,0)};
writeFileSync(`${banco}/evidencia-g5-banco.json`,JSON.stringify(evidence,null,2)+'\n',{mode:0o600});
