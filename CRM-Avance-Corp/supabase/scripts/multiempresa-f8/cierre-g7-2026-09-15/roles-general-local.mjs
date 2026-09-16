// Ejecuta la matriz en la copia fija y vincula el recibo al SQL exacto.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {db,objeto} from './banco-http.mjs';
const destino=new URL('roles-general-local.json',import.meta.url);
const recibo={estado:'RUNNING',inicio:new Date().toISOString(),banco:db};
const guardar=()=>writeFileSync(destino,JSON.stringify(recibo,null,2)+'\n');
guardar();
try {
  const resultado=objeto(readFileSync(new URL('roles-general-local.sql',import.meta.url),'utf8'),{admin:true});
  assert.equal(resultado.estado,'PASS');assert.equal(resultado.banco,db);
  Object.assign(recibo,resultado,{sha256:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
    dependencias_sha256:Object.fromEntries(['roles-general-local.sql','banco-http.mjs','dependencias-local.sql']
      .map(f=>[f,createHash('sha256').update(readFileSync(new URL(f,import.meta.url))).digest('hex')]))});
  console.log(JSON.stringify({estado:'PASS',contextos:resultado.roles.length,
    directorio:resultado.roles.filter(r=>r.directorio_ficha_avance_probada)
      .map(r=>({fichas:r.directorio_fichas_comprobadas,paginas:r.directorio_paginas}))}));
} catch(error) {Object.assign(recibo,{estado:'FAIL',error:error.message});throw error;}
finally {recibo.fin=new Date().toISOString();guardar();}
