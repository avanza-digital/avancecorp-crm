// Cotejo exacto y ensayo administrativo local: todas las escrituras hacen ROLLBACK.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { carpeta, sql } from '../gestion-diaria-cortes/http/banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const respaldo=readFileSync('/private/tmp/gd-f4-ledger-etapa3-respaldo-20260922.json','utf8');
const fila=JSON.parse(respaldo);
assert.equal(fila.version,'20260922164159');assert.equal(fila.name,'crm_gestion_diaria_cortes');
assert.equal(fila.statements.length,33);
const archivo=readFileSync(new URL('../../migrations/20260921214018_crm_gestion_diaria_cortes.sql',import.meta.url),'utf8');
const sha256=createHash('sha256').update(archivo).digest('hex');
assert.equal(sha256,'8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5');
let restante=archivo;
for(const [i,sentencia] of fila.statements.entries()) {
  restante=restante.trimStart();assert.ok(restante.startsWith(sentencia),`Sentencia ${i+1} idéntica`);
  restante=restante.slice(sentencia.length);assert.equal(restante[0],';');restante=restante.slice(1);
}
assert.equal(restante.trim(),'','No quedan sentencias sin cotejar');
assert.equal(createHash('md5').update(fila.statements.join('\n')).digest('hex'),'d3d9cf9cde700b0fc44095fcbd523892');
const reparacion=readFileSync(new URL('./conciliar-ledger-etapa3.sql',import.meta.url),'utf8');
assert.match(reparacion,/\ncommit;\s*$/);
const prueba=reparacion.replace(/\ncommit;\s*$/,'\n');
const literal=s=>`'${s.replaceAll("'","''")}'`;
// El banco no tiene ledger: se crea solo en la transacción y desaparece al terminar.
assert.equal(sql("select to_regclass('supabase_migrations.schema_migrations') is null"),'t');
const preparar=`begin; create schema if not exists supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[],dato_ajeno text);
insert into supabase_migrations.schema_migrations values('20260922164159','crm_gestion_diaria_cortes',
array[${fila.statements.map(literal).join(',')}],'debe conservarse');`;
sql(`${preparar}\n${prueba}\nrollback;`);
for(const [cambio,error] of [
  ["update supabase_migrations.schema_migrations set statements=array['ajeno'];",'difiere del respaldo'],
  ["insert into supabase_migrations.schema_migrations(version,name) values('20260921214018','otro');",'Ya existe la version'],
  ["insert into supabase_migrations.schema_migrations(version,name) values('otra','crm_gestion_diaria_cortes');",'no es unica'],
]) assert.throws(()=>sql(`${preparar}\n${cambio}\n${prueba}\nrollback;`),new RegExp(error));
assert.equal(sql("select to_regclass('supabase_migrations.schema_migrations') is null"),'t');
writeFileSync(`${carpeta}/gd-f4-ledger-ensayo.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),
  sentencias:33,sha256,respaldoSha256:createHash('sha256').update(respaldo).digest('hex'),
  mutantes:3,soloVersion:true,transaccionesRevertidas:true},null,2)+'\n',{mode:0o600});
console.log('PASS: 33 sentencias idénticas; conciliación cambia solo versión, detecta tres derivas y revierte todo');
