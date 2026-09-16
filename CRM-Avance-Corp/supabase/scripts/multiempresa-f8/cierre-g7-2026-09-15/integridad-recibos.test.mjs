// Prueba de fallo del registrador: una corrida fallida nunca conserva un PASS.
// Copias efímeras de artefactos no secretos; no necesita Docker ni una base.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtempSync,copyFileSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

for(const caso of ['captura alterada','Docker no disponible'])test(caso,()=>{
  const carpeta=mkdtempSync(join(tmpdir(),'g7-recibo-'));
  try {
    for(const f of ['banco-http.mjs','captura-versiones.json','versiones-casos.json','capturar-versiones.sql','dependencias-local.sql'])
      copyFileSync(new URL(f,import.meta.url),join(carpeta,f));
    const destino=join(carpeta,'cotejo-casos.json');
    writeFileSync(destino,JSON.stringify({estado:'PASS',funciones:203,fecha:'2000-01-01T00:00:00Z'}));
    if(caso==='captura alterada') {
      const archivo=join(carpeta,'versiones-casos.json'),datos=JSON.parse(readFileSync(archivo,'utf8'));
      datos[0].huella='alteracion_deliberada';writeFileSync(archivo,JSON.stringify(datos));
    }
    const r=spawnSync(process.execPath,[join(carpeta,'banco-http.mjs'),'--inventario'],{
      encoding:'utf8',env:{...process.env,PATH:join(carpeta,'sin-binarios')},timeout:10000});
    assert.equal(r.error,undefined);assert.equal(r.status,1);
    const recibo=JSON.parse(readFileSync(destino,'utf8'));
    assert.equal(recibo.estado,'FAIL');assert.equal(recibo.funciones,undefined);
    assert.ok(Date.parse(recibo.fecha)>=Date.parse(recibo.inicio));
    assert.ok(recibo.error);
  } finally {rmSync(carpeta,{recursive:true,force:true});}
});
