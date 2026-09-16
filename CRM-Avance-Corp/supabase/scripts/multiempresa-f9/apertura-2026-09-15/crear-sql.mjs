// Genera artefactos revisables; no abre conexiones ni ejecuta SQL.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
const config=JSON.parse(readFileSync(new URL('config.json',import.meta.url),'utf8'));
assert.equal(config.proyecto,'dctqcbznekcyxhjujuci');
assert.equal(config.equipo.length,24);assert.equal(config.miembros.length,4);
assert.equal(config.control.revision,1);assert.equal(config.funciones.length,211);
assert.equal(config.lectores_globales.length,0);
assert.ok(config.catalogo_firmas.length>=config.funciones.length);
for(const [origen,destino] of [['activar.plantilla.sql','ACTIVAR.sql'],['revertir.plantilla.sql','REVERTIR.sql'],['postflight.plantilla.sql','POSTFLIGHT.sql']]) {
  const plantilla=readFileSync(new URL(origen,import.meta.url),'utf8');
  assert.equal(plantilla.split('__CONFIG__').length,2);
  const serializado=JSON.stringify(config);
  assert.ok(!/\$f9(?:_reversa|_verificar)?\$/.test(serializado),'Delimitador SQL en configuración');
  writeFileSync(new URL(destino,import.meta.url),plantilla.replace('__CONFIG__',serializado.replaceAll("'","''")));
}
