// Ensayo completo del resultado tipificado de llamada (Gestión Diaria, Fase 2)
// sobre la copia local: crea la copia desde la plantilla a paridad, instala (si
// faltan) el historial por lead y la Fase 1, SELLA los md5 propios del gate en
// dos pasadas (la primera instala con placeholders, mide y escribe los md5 en la
// migración; la segunda instala la versión sellada), corre el gate propio, sus
// mutantes (F1 + F2) y el oráculo por actor (escrituras reales que se deshacen
// con rollback), comprueba que el censo no cambió, ensaya la reversa y
// reinstala. Escribe verificacion.json y genera el registrador. Nunca toca
// producción: `banco.mjs` fija el contenedor y la base.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, sql, ejecutar, asegurarCopia } from './banco.mjs';
import { VERSION, NOMBRE, PUERTA, DESHACER, NUCLEO, TRIGGER_FN, HISTORIAL, escribirRegistrador } from './generar-registrador.mjs';

const rutaMigracion = new URL(`../../migrations/${VERSION}_${NOMBRE}.sql`, import.meta.url);
const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const reversa = leer('./reversa.sql');
const oraculo = leer('./test-gestion-diaria-resultado.sql');
const args = process.argv.slice(2);
const opcion = (n, def) => args.includes(n) ? args[args.indexOf(n) + 1] : def;
const historial = opcion('--historial', '../../migrations/20260919185718_crm_actividades_de_lead.sql');
const fase1 = opcion('--fase1', '../../migrations/20260919211958_crm_gestion_diaria_registro.sql');

if (asegurarCopia()) console.log(`copia ${db} creada desde la plantilla`);
assert.equal(sql('select current_database()'), db);
const existe = (f) => sql(`select (to_regprocedure('${f}') is not null)::text`) === 'true';
const md5Vivo = (f) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))),'-')`);
const censo = () => sql(`select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()`);
const censoRojo = () => sql(`select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok)`);
const gate = () => sql('select private.assert_gestion_diaria()');
const sla = () => sql(`select private.assert_sla_nucleo()||' | '||private.assert_sla_operacion()||' | '||private.assert_sla_comandos()||' | '||private.assert_sla_avisos()`);

// 0. Dependencias: historial por lead (en prod) y Fase 1 (pendiente de instalar en prod).
if (!existe('private.nombre_de_autor(uuid)') || !existe('private.assert_actividades_de_lead_base()')) {
  const ruta = new URL(historial, import.meta.url);
  assert.ok(existsSync(ruta), `Falta el historial por lead y no hay archivo en ${historial} (usa --historial <ruta>)`);
  sql(readFileSync(ruta, 'utf8'));
  console.log('historial por lead instalado en la copia (dependencia)');
}
if (!existe('crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)')) {
  const ruta = new URL(fase1, import.meta.url);
  assert.ok(existsSync(ruta), `Falta la Fase 1 y no hay archivo en ${fase1} (usa --fase1 <ruta>)`);
  sql(readFileSync(ruta, 'utf8'));
  console.log('Fase 1 instalada en la copia (dependencia)');
}
assert.match(sla(), /^OK.*\| OK.*\| OK.*\| OK/, 'Los gates SLA deben estar verdes antes');
const censoAntes = censo(), censoRojoAntes = censoRojo();

// 1. Si ya estaba instalada (segunda corrida), se retira con la reversa para ensayar limpio.
if (existe(PUERTA)) { sql(reversa); console.log('instalación previa retirada con la reversa'); }
assert.ok(!existe(PUERTA));
assert.match(sql('select private.assert_gestion_diaria()'), /^OK/, 'gate de F1 verde antes de instalar F2');

// 2. SELLADO en dos pasadas: la migración con placeholders instala todo menos el
//    postflight (que fallaría en el md5); se miden los cuerpos, se escriben en el
//    archivo y se deshace la instalación provisional.
let migracion = readFileSync(rutaMigracion, 'utf8');
if (migracion.includes('_PENDIENTE_')) {
  const sinPostflight = migracion.replace(/do \$postflight\$[\s\S]*?\$postflight\$;/, 'select 1;');
  assert.notEqual(sinPostflight, migracion, 'no se encontró el bloque postflight');
  sql(sinPostflight);
  const sellos = {
    MD5_NUCLEO_PENDIENTE_00000000000000: md5Vivo(NUCLEO),
    MD5_PUERTA_PENDIENTE_00000000000000: md5Vivo(PUERTA),
    MD5_DESHACER_PENDIENTE_000000000000: md5Vivo(DESHACER),
    MD5_TRIGGER_PENDIENTE_0000000000000: md5Vivo(TRIGGER_FN),
    MD5_HISTORIAL_PENDIENTE_00000000000: md5Vivo(HISTORIAL),
  };
  for (const [k, v] of Object.entries(sellos)) {
    assert.match(v, /^[0-9a-f]{32}$/, `md5 de ${k}`);
    assert.ok(migracion.includes(k), `placeholder ${k} ausente`);
    migracion = migracion.replaceAll(k, v);
  }
  writeFileSync(rutaMigracion, migracion);
  sql(reversa);
  assert.ok(!existe(PUERTA), 'la instalación provisional se retiró');
  console.log(`md5 sellados en la migración: ${Object.values(sellos).join(' ')}`);
}
assert.ok(!migracion.includes('_PENDIENTE_'));

// 3. Instalación real + gate + mutantes (F1 y F2) + oráculo + censo intacto.
sql(migracion);
assert.match(gate(), /^OK: Gestion Diaria \[OK.*\] \[OK.*\]$/, 'gate paraguas tras instalar');
const mutantesF2 = sql("set gestion_diaria.banco = on; select private.assert_gestion_diaria_resultado_mutantes()");
assert.match(mutantesF2, /^OK: 14 mutantes detectados/, mutantesF2);
const mutantesF1 = sql("set gestion_diaria.banco = on; select private.assert_gestion_diaria_mutantes()");
assert.match(mutantesF1, /^OK: 10 mutantes detectados/, mutantesF1);
assert.match(ejecutar('select private.assert_gestion_diaria_resultado_mutantes()').stderr, /solo corren en el banco/, 'Sin la marca de banco los mutantes se niegan');
assert.match(gate(), /^OK/, 'gate tras los mutantes (nada quedó alterado)');
assert.match(sla(), /^OK.*\| OK.*\| OK.*\| OK/, 'gates SLA tras instalar');
const salida = sql(oraculo);
assert.match(salida, /GESTION_DIARIA_RESULTADO_OK/, salida);
assert.equal(censo(), censoAntes, 'El censo analítico no cambia');
assert.equal(censoRojo(), censoRojoAntes, 'El conjunto rojo del censo no cambia');
const md5Puerta = md5Vivo(PUERTA), md5Nucleo = md5Vivo(NUCLEO), md5Deshacer = md5Vivo(DESHACER);
for (const m of [md5Puerta, md5Nucleo, md5Deshacer]) assert.match(m, /^[0-9a-f]{32}$/);

// 4. Reversa CON DATOS CONFIRMADOS (hallazgo Codex 19/09): se registra y
//    confirma una llamada de verdad (commit), se revierte y se reinstala; el
//    preflight debe admitir la metadata conservada. El lead nace por la vía legal.
const telefono = `9998${String(Date.now() % 100_000).padStart(5, '0')}`;
const confirmada = sql(`
do $c$
declare a record; v_lead uuid := gen_random_uuid(); v jsonb;
begin
  select (select perfil_id from crm.equipo where rol_crm = 'gerencia' and activo limit 1) as ger,
         (select e.perfil_id from crm.equipo e where e.rol_crm = 'vendedor' and e.activo and e.supervisor_id is not null
            and exists (select 1 from crm.equipo s where s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor' and s.activo)
          order by e.perfil_id limit 1) as v1 into a;
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform crm.crear_lead_si_disponible(p_nombre_completo => 'ENSAYO F2 REINSTALACION', p_telefono => '${telefono}',
    p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_lead, p_correo => null, p_dni => null,
    p_genero => null, p_fecha_nacimiento => null, p_distrito => null, p_etapa => 'nuevo', p_categoria_interes => null,
    p_vendedor_id => a.v1, p_nota => 'ensayo reinstalacion', p_telefono_alternativo => null);
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  v := crm.registrar_llamada_v3(gen_random_uuid(), v_lead, 'no_contesto');
  if (v->>'ok')::boolean is not true then raise exception 'no se confirmo la llamada'; end if;
end $c$;
select (exists(select 1 from crm.actividades where metadata->>'resultado' = 'no_contesto'))::text`);
assert.equal(confirmada, 'true', 'la llamada confirmada debe quedar en la base');

// 5. Reversa + comprobación + reinstalación determinista (con la metadata conservada).
sql(reversa);
assert.ok(!existe(PUERTA), 'La reversa retira la puerta');
assert.ok(!existe('private.assert_gestion_diaria_registro()'), 'La reversa devuelve el gate de F1 a su nombre');
assert.match(sql('select private.assert_gestion_diaria()'), /^OK: registro/, 'gate de F1 verde tras la reversa');
assert.equal(sql(`select (exists(select 1 from pg_constraint where conname='actividades_resultado_llamada_forma'))::text`), 'false');
sql(migracion);
assert.match(gate(), /^OK/, 'gate tras reinstalar');
assert.equal(md5Vivo(PUERTA), md5Puerta, 'La reinstalación es determinista (puerta)');
assert.equal(md5Vivo(NUCLEO), md5Nucleo, 'La reinstalación es determinista (nucleo)');

const verificacion = {
  version: VERSION, nombre: NOMBRE, base: db, ensayado_en: new Date().toISOString(),
  md5_puerta: md5Puerta, md5_nucleo: md5Nucleo, md5_deshacer: md5Deshacer,
  sha256_migracion: createHash('sha256').update(migracion).digest('hex'),
  mutantes_f2: mutantesF2, mutantes_f1: mutantesF1, oraculo: 'GESTION_DIARIA_RESULTADO_OK', censo_intacto: true,
};
writeFileSync(new URL('./verificacion.json', import.meta.url), JSON.stringify(verificacion, null, 2) + '\n');
const { SALIDA, bytes } = escribirRegistrador({ md5Puerta, md5Nucleo, md5Deshacer });
console.log(`ENSAYO OK · ${mutantesF2} · ${mutantesF1} · registrador ${SALIDA} (${bytes} bytes) · md5 puerta ${md5Puerta} · nucleo ${md5Nucleo} · deshacer ${md5Deshacer}`);
