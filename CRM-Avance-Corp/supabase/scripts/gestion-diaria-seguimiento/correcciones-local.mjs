// Cuarto candidato, sobre las tres etapas ya instaladas en el banco propio.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { carpeta, sql } from '../gestion-diaria-cortes/http/banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const nombre='20260922220800_crm_gestion_diaria_avisos_lectura.sql';
const fuente=readFileSync(new URL(`../../migrations/${nombre}`,import.meta.url),'utf8');
assert.equal(sql("select to_regprocedure('private.gestion_diaria_avisos_con_contexto(timestamptz)') is null"),'t','No reinstalar');
const politica=sql('select jsonb_agg(to_jsonb(p) order by version) from crm.politica_gestion_diaria p');
const cuerpos=sql(`select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,'definicion',pg_get_functiondef(p.oid)))
  from pg_proc p where p.oid in ('private.gestion_diaria_avisos(timestamptz)'::regprocedure,
    'crm.gestion_diaria_avisos_fn()'::regprocedure,'private.assert_gestion_diaria_avisos()'::regprocedure,
    'private.assert_gestion_diaria()'::regprocedure)`);
assert.equal((fuente.match(/^begin;$/gm)??[]).length,1);
assert.equal((fuente.match(/^commit;$/gm)??[]).length,1);
sql(fuente.replace(/^commit;$/m,'rollback;'));
assert.equal(sql("select to_regprocedure('private.gestion_diaria_avisos_con_contexto(timestamptz)') is null"),'t');
writeFileSync(`${carpeta}/gd-f4-lectura-antes.json`,cuerpos+'\n',{mode:0o600,flag:'wx'});
sql(fuente);
assert.equal(sql('select jsonb_agg(to_jsonb(p) order by version) from crm.politica_gestion_diaria p'),politica);
sql('select private.assert_gestion_diaria()');
writeFileSync(`${carpeta}/gd-f4-lectura-instalacion.json`,JSON.stringify({nombre,
  sha256:createHash('sha256').update(fuente).digest('hex'),estado:'PASS',fecha:new Date().toISOString(),
  atomicidad:'ROLLBACK comprobado antes de instalar',politicas:'sin cambios'},null,2)+'\n',{mode:0o600,flag:'wx'});
console.log('PASS: cuarto candidato reversible e instalado solo en Gestión Diaria; políticas intactas');
