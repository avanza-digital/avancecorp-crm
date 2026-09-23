// Reconstruye SOLO el historial del banco después de acreditar su catálogo.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {isDeepStrictEqual} from 'node:util';
import {carpeta,sql,objeto,ref} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
for(const archivo of ['base-alineada','estructura-paridad','edge-paridad'])
 assert.equal(JSON.parse(readFileSync(`${carpeta}/${archivo}.json`,'utf8')).estado,'PASS');
assert.equal(existsSync(`${carpeta}/ledger-alineado.json`),false);
const filas=JSON.parse(readFileSync('/private/tmp/gd-f4-ledger-productivo-completo-20260922.json','utf8')).rows;
assert.equal(filas.length,327);assert.equal(new Set(filas.map(f=>f.version)).size,327);
assert.ok(filas.some(f=>f.version==='20260921214018'));
assert.ok(!filas.some(f=>f.version==='20260922164159'));
assert.ok(!filas.some(f=>['20260922184459','20260922185138','20260922204125','20260922220800'].includes(f.version)));
const consulta='select jsonb_agg(jsonb_build_object(\'version\',version,\'name\',name,\'statements\',statements) order by version) from supabase_migrations.schema_migrations';
const antes=objeto(consulta);
writeFileSync(`${carpeta}/ledger-banco-anterior.json`,JSON.stringify(antes),{mode:0o600});
const literal="'"+JSON.stringify(filas).replaceAll("'","''")+"'";
if(!isDeepStrictEqual(antes,filas.toSorted((a,b)=>a.version.localeCompare(b.version))))sql(`begin;
lock table supabase_migrations.schema_migrations in access exclusive mode;
do $guarda$ begin
 if to_regclass('crm.gestion_diaria_entregas') is not null
  or exists(select 1 from cron.job where active)
  or (select count(*) from auth.users)<>17 then raise exception 'Banco fuera del estado aprobado'; end if;
end $guarda$;
truncate supabase_migrations.schema_migrations;
insert into supabase_migrations.schema_migrations(version,name,statements)
 select version,name,statements from jsonb_to_recordset(${literal}::jsonb) as r(version text,name text,statements text[]);
commit;`);
const despues=objeto(consulta);
assert.deepEqual(despues,filas.toSorted((a,b)=>a.version.localeCompare(b.version)));
writeFileSync(`${carpeta}/ledger-alineado.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),ref,
 filas:filas.length,comparacion:'version, name y cada sentencia idénticos; no se reejecutó el historial',
 antes:antes.length},null,2)+'\n',{mode:0o600});
console.log('PASS: ledger del banco con 327 migraciones y sentencias idénticas a producción');
