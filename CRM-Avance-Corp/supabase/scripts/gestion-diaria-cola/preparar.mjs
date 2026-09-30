// Repara las ACL de la plantilla local (el dump original usó --no-privileges).
// El snapshot contiene SOLO metadatos públicos del catálogo, nunca usuarios.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sql, q } from './banco.mjs';

assert.deepEqual(process.argv.slice(2), ['--solo-banco-local']);
const acl = JSON.parse(readFileSync(new URL('./fixtures/acl.json', import.meta.url), 'utf8'));
assert.ok(Array.isArray(acl) && acl.length > 100);
const sentencias = [];
const extra = JSON.parse(readFileSync(new URL('./fixtures/acl-extra.json', import.meta.url), 'utf8'));
for (const fila of extra) {
  assert.ok(['schema', 'column'].includes(fila.tipo));
  assert.ok(['PUBLIC', 'anon', 'authenticated', 'service_role'].includes(fila.rol));
  assert.ok(/^(crm|private|public)(\.[a-z_][a-z0-9_]*)?$/.test(fila.objeto));
  assert.ok(['USAGE', 'CREATE', 'SELECT', 'INSERT', 'UPDATE', 'REFERENCES'].includes(fila.permiso));
  if (fila.tipo === 'schema') sentencias.push(`grant ${fila.permiso} on schema ${fila.objeto} to ${fila.rol};`);
  else {
    assert.ok(/^[a-z_][a-z0-9_]*$/.test(fila.columna));
    sentencias.push(`do $col$ begin if exists(select 1 from pg_attribute where attrelid=to_regclass(${q(fila.objeto)}) and attname=${q(fila.columna)} and not attisdropped) then
      execute ${q(`grant ${fila.permiso} (${fila.columna}) on ${fila.objeto} to ${fila.rol}`)}; end if; end $col$;`);
  }
}
for (const fila of acl) {
  assert.ok(['function', 'table'].includes(fila.tipo));
  if (fila.tipo === 'table' && /^[a-z_][a-z0-9_]*$/.test(fila.objeto)) fila.objeto = `public.${fila.objeto}`;
  assert.ok(['PUBLIC', 'anon', 'authenticated', 'service_role'].includes(fila.rol));
  assert.ok(/^(crm|private|public)\.[a-z_][a-z0-9_]*(\([a-z0-9_, .[\]]*\))?$/.test(fila.objeto));
  assert.ok(['EXECUTE', 'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'].includes(fila.permiso));
  const resolver = fila.tipo === 'function' ? 'to_regprocedure' : 'to_regclass';
  sentencias.push(`do $acl$ begin if ${resolver}(${q(fila.objeto)}) is not null then
    execute ${q(`grant ${fila.permiso} on ${fila.tipo} ${fila.objeto} to ${fila.rol}`)};
    end if; end $acl$;`);
}
sql(`begin;
  revoke all on all functions in schema crm,private from public,anon,authenticated,service_role;
  ${sentencias.join('\n')}
  commit;`);
console.log('PASS: ACL de funciones y tablas disponibles cotejadas con producción en la copia local');
console.log(sql('select private.assert_sla_nucleo()'));
const instalada = sql("select to_regprocedure('crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)') is not null") === 't';
if (!instalada) sql(readFileSync(new URL('../../migrations/20260929004455_crm_cola_accion_v3_clientes.sql', import.meta.url), 'utf8'));
console.log(sql('select private.assert_cola_v3()'));
