// Corrige únicamente las diferencias ACL demostradas de la restauración vacía.
// No acepta destinos y no ejecuta SQL en el origen. No cambia cuerpos ni RLS.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { carpeta, sql } from './banco.mjs';

assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado']);
const evidencia = JSON.parse(readFileSync(`${carpeta}/paridad-diferencias.json`, 'utf8'));
assert.equal(evidencia.origen, 'dctqcbznekcyxhjujuci');
assert.equal(evidencia.banco, 'gestion-diaria-f4-http');
assert.equal(sql('select count(*) from auth.users'), '0', 'Antes de Auth fixtures únicamente');
const sentencias = [];

for (const r of evidencia.sobran.filter(r => r.categoria === 'acl_default')) {
  const m = /^postgres\.public\.r postgres:(anon|authenticated):(MAINTAIN|REFERENCES|TRIGGER|TRUNCATE):false$/.exec(r.linea);
  assert.ok(m, 'Diferencia de default ACL no prevista');
  sentencias.push(`alter default privileges for role postgres in schema public revoke ${m[2]} on tables from ${m[1]};`);
}
for (const r of evidencia.sobran.filter(r => r.categoria === 'acl_tablas_secuencias')) {
  const m = /^(public\.[a-z_]+) owner=postgres grantor=postgres grantee=(anon|authenticated) (MAINTAIN|REFERENCES|TRIGGER|TRUNCATE) grantable=false$/.exec(r.linea);
  assert.ok(m, 'Diferencia de tabla no prevista');
  sentencias.push(`revoke ${m[3]} on table ${m[1]} from ${m[2]};`);
}
for (const r of evidencia.faltan.filter(r => r.categoria === 'acl_tablas_secuencias')) {
  const m = /^((?:crm|private)\.[a-z_]+_seq) owner=postgres grantor=postgres grantee=postgres (SELECT|UPDATE) grantable=false$/.exec(r.linea);
  assert.ok(m, 'Diferencia de secuencia no prevista');
  sentencias.push(`grant ${m[2]} on sequence ${m[1]} to postgres;`);
}
for (const r of evidencia.faltan.filter(r => r.categoria === 'funciones')) {
  const prefijo = r.linea.split(' acl=')[0];
  const local = evidencia.sobran.find(s => s.categoria === 'funciones' && s.linea.split(' acl=')[0] === prefijo);
  assert.ok(local, 'Cambió el cuerpo, propietario o comentario; no es una reparación ACL');
  const firma = /^(public\.[a-z_]+\([a-zA-Z0-9_ ,.[\]"]*\)) [a-f0-9]{32} owner=postgres comment=/.exec(prefijo)?.[1];
  assert.ok(firma, 'Firma no prevista');
  const autorizados = new Set(r.linea.split(' acl=')[1].split(','));
  for (const acl of local.linea.split(' acl=')[1].split(',')) {
    if (autorizados.has(acl)) continue;
    const rol = /^postgres:(anon|authenticated|service_role):EXECUTE:false$/.exec(acl)?.[1];
    assert.ok(rol, 'Diferencia de EXECUTE no prevista');
    sentencias.push(`revoke execute on function ${firma} from ${rol};`);
  }
}
assert.ok(sentencias.length > 0);
sql(`begin; set local lock_timeout='5s'; ${sentencias.join('\n')} notify pgrst, 'reload schema'; commit;`);
console.log(`PASS: ${sentencias.length} ajustes ACL exclusivamente en el banco vacío; repetir paridad`);
