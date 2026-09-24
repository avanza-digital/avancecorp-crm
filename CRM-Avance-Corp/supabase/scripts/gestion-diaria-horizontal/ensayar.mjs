// Se ejecuta solamente sobre la copia local marcada por banco.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { db, sql } from './banco.mjs';
const leer = nombre => readFileSync(new URL(nombre, import.meta.url), 'utf8');
const migracion = leer('../../migrations/20260923234404_crm_gestion_diaria_pendientes_supervisor.sql');
const reversa = leer('reversa.sql');
// Ensayar siempre desde la misma base: reversa verificable, migración y replay.
if (sql("select to_regprocedure('private.assert_gestion_diaria_pendientes()') is not null;")==='t') sql(reversa);
assert.equal(sql("select md5(pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure));"),'17b39a376af0f940f029937a6fa98186');
sql(migracion); console.log('PASS: reversa exacta e instalación H3');
// Comparación de TODO el JSON anterior/nuevo, en la misma sentencia/identidad.
const anterior = reversa.match(/CREATE OR REPLACE FUNCTION private\.gestion_diaria_equipo_core[\s\S]*?\$function\$\s*;/)?.[0];
assert.ok(anterior);
const oraculo = anterior.replace('private.gestion_diaria_equipo_core','pg_temp.equipo_anterior') + `
create function pg_temp.comparar_errores(p_dia date,p_supervisor_id uuid) returns void
language plpgsql as $$ declare a text; b text; begin
  begin perform pg_temp.equipo_anterior(p_dia,p_supervisor_id); exception when others then a:=sqlstate||':'||sqlerrm; end;
  begin perform crm.gestion_diaria_equipo_fn(p_dia,p_supervisor_id); exception when others then b:=sqlstate||':'||sqlerrm; end;
  if a is null or a is distinct from b then raise exception 'H3: error previo distinto: % / %',a,b; end if;
end $$;
create function pg_temp.equipo_comprobado(p_dia date default null,p_supervisor_id uuid default null) returns jsonb
language plpgsql stable security invoker as $$ declare antes jsonb; despues jsonb; begin
  antes:=pg_temp.equipo_anterior(p_dia,p_supervisor_id);
  despues:=crm.gestion_diaria_equipo_fn(p_dia,p_supervisor_id);
  if antes is distinct from despues then raise exception 'H3: extracción cambió el agregado'; end if;
  return despues;
end $$;`;
const jerarquia = leer('../gestion-diaria-equipo/test-jerarquia.sql').replaceAll('gestion_diaria_f4_vista_chvrqh',db)
  .replace('create temporary table f4_jerarquia',()=>`${oraculo}\ncreate temporary table f4_jerarquia`)
  .replaceAll('crm.gestion_diaria_equipo_fn(', 'pg_temp.equipo_comprobado(');
// Evitar que la sustitución haga recursiva la función oráculo.
const comparable = jerarquia.replace('despues:=pg_temp.equipo_comprobado(p_dia,p_supervisor_id);','despues:=crm.gestion_diaria_equipo_fn(p_dia,p_supervisor_id);');
const conPendientes=comparable.replace("-- Límite inclusivo", "reset role;select set_config('request.jwt.claim.sub',supervisor::text,true) from f4_jerarquia;set local role authenticated;select pg_temp.comparar_errores('infinity',gen_random_uuid());select pg_temp.comparar_errores(null,gen_random_uuid());select pg_temp.afirmar(crm.gestion_diaria_pendientes_fn(vendedor)->>'analista_id'=vendedor::text,'Pendientes conserva descendiente bajo puente inactivo') from f4_jerarquia;reset role;select set_config('request.jwt.claim.sub',lector::text,true) from f4_jerarquia;set local role authenticated;\n-- Límite inclusivo");
assert.match(sql(conPendientes),/GESTION_DIARIA_JERARQUIA_OK/);
console.log('PASS: paridad antes/después completa; supervisor, gerencia, global, puente inactivo y ciclo');
for (const nombre of ['test-equipo.sql','test-calendario.sql']) {
  sql(leer(`../gestion-diaria-equipo/${nombre}`).replaceAll('gestion_diaria_f4_vista_chvrqh',db));
  console.log(`PASS: regresión ${nombre}`);
}
const salida = sql(leer('test-pendientes.sql'));
assert.match(salida,/H3_PENDIENTES_OK/); console.log(salida.split('\n').filter(l=>l.startsWith('H3_')||l.startsWith('OK: pendientes')).join('\n'));
sql(reversa); sql(migracion);
console.log(sql('select private.assert_gestion_diaria();'));
console.log('PASS: replay, catálogo de seguridad y gates SLA preservados');
