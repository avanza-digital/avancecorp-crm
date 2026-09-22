// Aplica al banco propio el vigilante ya publicado por la otra tarea.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { carpeta, sql } from '../gestion-diaria-cortes/http/banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const columna="select exists(select 1 from pg_attribute where attrelid='private.analitica_leads_citas_exenciones'::regclass and attname='clase' and not attisdropped)";
const antes=sql('select private.assert_analitica_leads_citas(); select private.assert_gestion_diaria();');
const yaInstalada=sql(columna)==='t';
if(!yaInstalada) sql(readFileSync(new URL('../../migrations/20260922153708_crm_vigilante_techo_por_clase.sql',import.meta.url),'utf8'));
assert.equal(sql(columna),'t');
const despues=sql('select private.assert_analitica_leads_citas(); select private.assert_gestion_diaria();');
writeFileSync(`${carpeta}/gd-f4-integracion-main.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
  migracion:'20260922153708_crm_vigilante_techo_por_clase',yaInstalada,antes,despues},null,2)+'\n',{mode:0o600});
console.log('PASS: F4 convive con el vigilante de Main; gates de ambas tareas correctos');
