// Ejecuta los parsers reales de Main pre-F4.3 y los del candidato sobre
// respuestas capturadas de la API local. No reimplementa ningún contrato.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { carpeta } from './banco.mjs';

assert.deepEqual(process.argv.slice(2),['--solo-capturas-locales']);
const app=fileURLToPath(new URL('../../../../app/',import.meta.url));
const repo=fileURLToPath(new URL('../../../../../',import.meta.url));
const req=createRequire(`${app}package.json`);
const {createServer}=await import(pathToFileURL(req.resolve('vite')).href);
const {safeParse}=await import(pathToFileURL(req.resolve('valibot')).href);
const anterior='59dd14805b646e2adb281302b8441265e969d914';
const nombres=['gestion-diaria-equipo','gestion-diaria-analista'];
const archivos=Object.fromEntries(nombres.map(n=>[`${app}src/lib/${n}.ts`,execFileSync('git',
  ['show',`${anterior}:CRM-Avance-Corp/app/src/lib/${n}.ts`],{cwd:repo,encoding:'utf8'})]));
const capturas={anterior:JSON.parse(readFileSync(`${carpeta}/contrato-reversa-resultado.json`,'utf8')).respuestas,
  candidato:JSON.parse(readFileSync(`${carpeta}/contrato-reversa.json`,'utf8')).respuestas};
const resultados=[];
for(const cliente of ['anterior','candidato']) {
  const cargados=new Set();
  const server=await createServer({root:app,configFile:false,envDir:false,logLevel:'silent',
    server:{middlewareMode:true,hmr:false,watch:null},
    plugins:cliente==='anterior'?[{name:'contratos-main-inmutables',enforce:'pre',load(id){
      if(archivos[id]) {cargados.add(id);return archivos[id];}
    }}]:[]});
  try {
    const equipo=(await server.ssrLoadModule('/src/lib/gestion-diaria-equipo.ts')).DiaEquipoSchema;
    const analista=(await server.ssrLoadModule('/src/lib/gestion-diaria-analista.ts')).DiaAnalistaSchema;
    if(cliente==='anterior') assert.equal(cargados.size,2,'Se debe ejecutar el código anterior real');
    for(const [backend,respuestas] of Object.entries(capturas)) {
      let casos=0;
      for(const [key,dato] of Object.entries(respuestas)) {
        const r=safeParse(key.endsWith('/equipo')?equipo:analista,dato);
        assert.ok(r.success,`${cliente}/${backend}/${key}: contrato rechazado`);
        if(cliente==='candidato'&&backend==='anterior'&&key.endsWith('/equipo')) {
          assert.equal(r.output.cortes,undefined,'Sin cortes no es cero ni un objeto simulado');
          assert.equal(r.output.umbrales.politica_version,undefined);
        }
        casos++;
      }
      resultados.push({cliente,backend,casos,estado:'PASS'});
    }
  } finally {await server.close();}
}
writeFileSync(`${carpeta}/compatibilidad-cliente.json`,JSON.stringify({estado:'PASS',commitAnterior:anterior,resultados},null,2)+'\n',{mode:0o600});
console.log('PASS: 28 parseos reales; cliente anterior/nuevo × servidor anterior/nuevo, sin falsos ceros');
