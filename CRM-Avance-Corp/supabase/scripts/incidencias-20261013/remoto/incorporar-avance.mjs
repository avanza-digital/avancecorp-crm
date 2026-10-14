// Dos migraciones YA productivas que llegaron durante la reconstrucción.
import assert from 'node:assert/strict';
import{readFileSync,writeFileSync}from'node:fs';
import{carpeta,sql,objeto}from'./banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const filas=JSON.parse(readFileSync(`${carpeta}/ledger-avances.json`));
assert.deepEqual(filas.map(f=>[f.version,f.name]),[
 ['20261013192850','crm_atencion_venta_separadas'],['20261013193653','crm_atencion_venta_hardening']]);
assert.equal(sql('select count(*) from supabase_migrations.schema_migrations'),'471');
const declaraciones=filas.flatMap(f=>f.statements.filter(s=>!/^\s*(?:--[^\n]*\n\s*)*(begin|commit)\s*$/i.test(s)));
assert.ok(!declaraciones.some(s=>/^\s*commit\b/i.test(s)));
const json=JSON.stringify(filas).replaceAll("'","''");
sql(`begin; ${declaraciones.join(';\n')};
insert into supabase_migrations.schema_migrations select * from jsonb_populate_recordset(null::supabase_migrations.schema_migrations,'${json}'::jsonb);
commit;`);
const ledger=objeto(`select jsonb_build_object('cantidad',count(*),'huella',md5(string_agg(to_jsonb(t)::text,E'\n' order by version)),'ultimo',max(version)) from supabase_migrations.schema_migrations t`);
assert.equal(ledger.huella,'8dc43ff2a86e303e86863ba7773b894e');
writeFileSync(`${carpeta}/ledger-base.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),...ledger}),{mode:0o600});
writeFileSync(`${carpeta}/produccion-catalogo.json`,readFileSync(`${carpeta}/produccion-catalogo-actual.json`),{mode:0o600});
console.log('PASS: banco actualizado al padre de 473 migraciones; historial literal idéntico.');
