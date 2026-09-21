// Banco fijo autorizado. No acepta URLs ni instala dependencias.
// Requiere la candidata ya instalada. Pruebas y reversa terminan en rollback.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { db, ejecutar, sql } from '../gestion-diaria-equipo/banco.mjs';
const leer = (ruta) => readFileSync(new URL(ruta, import.meta.url), 'utf8');
const migracion = leer('../../migrations/20260921153654_crm_resultado_llamada_seguimiento.sql');
const reversa = leer('./reversa.sql');
const oraculo = leer('./test-seguimiento.sql');
const PUERTA = 'crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)';
const CORE = 'private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)';
const md5 = (firma) => sql("select md5(pg_get_functiondef('" + firma + "'::regprocedure))");
const hash = (s) => createHash('sha256').update(s).digest('hex');
assert.equal(sql('select current_database()'), db);
assert.match(sql('select private.assert_gestion_diaria_resultado_v4()'), /^OK:/);
const antes = { puerta: md5(PUERTA), core: md5(CORE) };
const censoSQL = "select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()";
const censo = sql(censoSQL);
const tests = [];
const probar = (nombre, consulta, patron = /^OK:/) => {
  const salida = sql(consulta);
  assert.match(salida, patron, nombre + ': ' + salida);
  tests.push(nombre); console.log('PASS: ' + nombre);
};
probar('v4 authenticated: seguimiento, cierre, descarte, veto, replay y permisos', oraculo, /RESULTADO_SEGUIMIENTO_V4_OK/);
for (const [nombre, archivo, patron] of [
  // El oraculo historico F1 tiene una whitelist anterior a F3: falla en J
  // tambien SIN v4 (baseline comprobada 21/09/2026). No se acredita PASS:
  // F1 sigue cubierto por su gate y sus 10 mutantes; F3 por su oraculo vigente.
  ['F2 legacy', '../gestion-diaria-resultado/test-gestion-diaria-resultado.sql', /GESTION_DIARIA_RESULTADO_OK/],
  ['F3', '../gestion-diaria-analista/test-gestion-diaria-analista.sql', /GESTION_DIARIA_ANALISTA_OK/],
  ['F4 equipo', '../gestion-diaria-equipo/test-equipo.sql', /EQUIPO_OK/],
  ['F4 jerarquia', '../gestion-diaria-equipo/test-jerarquia.sql', /JERARQUIA_OK/],
  ['F4 calendario', '../gestion-diaria-equipo/test-calendario.sql', /CALENDARIO_OK/],
]) probar(nombre, leer(archivo), patron);
for (const [nombre, funcion] of [
  ['F1: 10 mutantes', 'private.assert_gestion_diaria_mutantes'],
  ['F2: 14 mutantes', 'private.assert_gestion_diaria_resultado_mutantes'],
  ['F3: 24 mutantes', 'private.assert_gestion_diaria_analista_mutantes'],
]) probar(nombre, 'set gestion_diaria.banco = on; select ' + funcion + '()');
for (const [nombre, cambio, error] of [
  ['puerta expuesta anon', 'grant execute on function ' + PUERTA + ' to anon;', /privilegios excesivos/],
  ['puerta expuesta PUBLIC', 'grant execute on function ' + PUERTA + ' to public;', /privilegios excesivos/],
  ['nucleo expuesto', 'grant execute on function ' + CORE + ' to authenticated;', /privilegios excesivos/],
  ['authenticated sin acceso', 'revoke all on function ' + PUERTA + ' from authenticated;', /falta acceso/],
  ['cuerpo modificado', 'alter function ' + CORE + " set search_path='crm';", /cuerpo ausente o alterado/],
]) {
  const r = ejecutar('begin;\n' + cambio + '\nselect private.assert_gestion_diaria();\nrollback;');
  assert.notEqual(r.status, 0, 'Mutante no detectado: ' + nombre);
  assert.match(r.stderr, error);
  tests.push('v4 mutante: ' + nombre); console.log('PASS: v4 mutante: ' + nombre);
}
probar('gate paraguas tras mutantes', 'select private.assert_gestion_diaria()');

// UNA transaccion exterior para probar reversal/reinstall con datos v4 reales.
const cuerpo = (s) => {
  assert.equal((s.match(/^begin;$/gm) ?? []).length, 1);
  assert.equal((s.match(/^commit;$/gm) ?? []).length, 1);
  return s.replace(/^begin;$/m, '').replace(/^commit;$/m, '');
};
const fixture = oraculo.slice(0, oraculo.indexOf('-- Altas del fixture'));
const historia = [
  "select 'actividades' as objeto, md5(string_agg(to_jsonb(a)::text,',' order by a.id)) huella from crm.actividades a where lead_id in(select id from o_leads)",
  "union all select 'tareas',md5(string_agg(to_jsonb(t)::text,',' order by t.id)) from crm.tareas t where lead_id in(select id from o_leads)",
  "union all select 'leads',md5(string_agg(to_jsonb(l)::text,',' order by l.id)) from crm.leads l where id in(select id from o_leads)",
].join('\n');
const antesReversa = [
  'grant select on o_actores,o_leads to authenticated;',
  'set local role authenticated;',
  "select set_config('request.jwt.claim.sub',(select v1::text from o_actores),true);",
  "select crm.registrar_llamada_v4(gen_random_uuid(),(select id from o_leads where n=1),'no_interesado','otro',null,",
  "jsonb_build_object('tipo','tarea','titulo','Debe sobrevivir a reversa','vence_en',now()+interval '1 day'));",
  'reset role;',
  'create temp table prueba_huellas on commit drop as ' + historia + ';',
].join('\n');
const comprobarHistoria = [
  'do $historia$ begin',
  'if exists((select * from prueba_huellas) except (' + historia + ')) then',
  "raise exception 'La reversa altero datos v4'; end if; end; $historia$;",
].join('\n');
probar('reversa y reinstalacion conservan lead, tarea e historial v4',
  fixture + '\n' + antesReversa + '\n' + cuerpo(reversa)
  + "\ndo $ausente$ begin if to_regprocedure('" + PUERTA + "') is not null then raise exception 'No retiro v4'; end if; end; $ausente$;\n"
  + comprobarHistoria + '\n' + cuerpo(migracion) + '\n' + comprobarHistoria
  + "\nrollback;\nselect 'REVERSA_DATOS_V4_OK';", /REVERSA_DATOS_V4_OK/);
assert.equal(md5(PUERTA), antes.puerta);
assert.equal(md5(CORE), antes.core);
assert.equal(sql(censoSQL), censo);
probar('gates SLA', "select private.assert_sla_nucleo()||' | '||private.assert_sla_operacion()||' | '||private.assert_sla_comandos()||' | '||private.assert_sla_avisos()");
console.log(JSON.stringify({
  base: db, ensayado_en: new Date().toISOString(), md5: antes,
  sha256_migracion: hash(migracion), sha256_reversa: hash(reversa),
  tests, censo_intacto: true, reinstalacion_determinista: true, datos_v4_preservados: true,
}, null, 2));
