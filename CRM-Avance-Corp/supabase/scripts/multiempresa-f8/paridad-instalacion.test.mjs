import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {sql} from './banco-local.mjs';

const consulta=readFileSync(new URL('paridad-instalacion.sql',import.meta.url),'utf8');
// Todas las mutaciones existen solo dentro de una transacción con ROLLBACK en
// el banco sintético fijo. No se recrea el banco ni se cambia su configuración.
const fixture=`
create table crm.__f8_paridad_fixture(id uuid, capital numeric(14,2));
alter table crm.__f8_paridad_fixture enable row level security;
create policy prueba on crm.__f8_paridad_fixture as permissive to authenticated using (true);
create function private.__f8_paridad_trigger() returns trigger
  language plpgsql set search_path='' as $f$begin return new;end;$f$;
create trigger prueba before insert on crm.__f8_paridad_fixture
  for each row execute function private.__f8_paridad_trigger();
create type crm.__f8_paridad_enum as enum ('inicial');
create sequence crm.__f8_paridad_seq;
`;
const casos=[
  ['default_acl', 'alter default privileges for role postgres in schema crm grant select on tables to pg_read_all_stats;'],
  ['triggers','alter table crm.__f8_paridad_fixture disable trigger prueba;'],
  ['politicas','drop policy prueba on crm.__f8_paridad_fixture; create policy prueba on crm.__f8_paridad_fixture as restrictive to authenticated using (true);'],
  ['columnas','alter table crm.__f8_paridad_fixture alter column capital type numeric(16,2);'],
  ['relaciones','grant create on schema crm to authenticated; alter table crm.__f8_paridad_fixture owner to authenticated;'],
  ['tipos',"alter type crm.__f8_paridad_enum add value 'posterior';"],
  ['secuencias','alter sequence crm.__f8_paridad_seq cache 2;'],
];
const capturar=()=>JSON.parse(sql(`begin read only;set local search_path='';set local timezone='UTC';${consulta}rollback;`));
test('las firmas largas conservan su identidad completa en el inventario',()=>{
  const cte=consulta.slice(0,consulta.indexOf('), categorias as ('))+')';
  const salida=JSON.parse(sql(`begin;set local search_path='';
    create function private.__f8_firma_larga_para_probar_identidades_completas_del_catalogo(integer)
      returns integer language sql as 'select $1';
    create function private.__f8_firma_larga_para_probar_identidades_completas_del_catalogo(text)
      returns text language sql as 'select $1';
    ${cte}
    select jsonb_agg(clave order by clave) from objetos where categoria='funciones'
      and clave like 'private.__f8_firma_larga%';rollback;`));
  assert.equal(salida.length,2);
  assert.equal(new Set(salida).size,2,'No truncar ni confundir sobrecargas');
  assert.ok(salida.every(f=>f.length>63));
  assert.ok(salida.some(f=>f.endsWith('(integer)')));
  assert.ok(salida.some(f=>f.endsWith('(text)')));
});
test('el catálogo detecta cambios materiales y conserva el banco tras cada rollback',async t=>{
  const original=capturar();
  for(const [categoria,cambio] of casos) await t.test(categoria,()=>{
    const salida=sql(`begin;set local search_path='';set local timezone='UTC';
      ${fixture}${consulta}${cambio}${consulta}rollback;`).split('\n').filter(Boolean).map(x=>JSON.parse(x));
    assert.equal(salida.length,2);
    const [antes,despues]=salida.map(r=>r.find(x=>x.categoria===categoria));
    assert.notEqual(antes.md5,despues.md5,`No detectó ${categoria}`);
    assert.deepEqual(capturar(),original,'El ensayo debe dejar intacto el catálogo');
  });
});
