// Ensayo completo del día del analista (Gestión Diaria, Fase 3) sobre la copia
// local: crea la copia (de la copia del ensayo de F2 o de la plantilla base),
// instala lo que falte para estar a paridad con producción al 20/09/2026, SELLA
// los md5 propios del gate en dos pasadas (la primera instala con placeholders,
// mide y escribe los md5 en la migración; la segunda instala la versión sellada),
// corre el gate paraguas, los mutantes (F1 + F2 + F3) y el oráculo por actor
// (escrituras reales que se deshacen con rollback), comprueba que el censo no
// cambió, ensaya la reversa (que debe devolver EXACTAMENTE los cuerpos de
// producción) y reinstala. Escribe verificacion.json y genera el registrador.
// Nunca toca producción: `banco.mjs` fija el contenedor y la base.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, sql, ejecutar, asegurarCopia } from './banco.mjs';
import { VERSION, NOMBRE, PUERTA, CORE, LLAMADAS, UMBRALES, REGISTRO_CORE, escribirRegistrador } from './generar-registrador.mjs';

const rutaMigracion = new URL(`../../migrations/${VERSION}_${NOMBRE}.sql`, import.meta.url);
const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const reversa = leer('./reversa.sql');
const oraculo = leer('./test-gestion-diaria-analista.sql');
const MIG = (v) => new URL(`../../migrations/${v}`, import.meta.url);

// md5 vivos en producción el 20/09/2026 (los mismos que pinna el preflight).
const PROD = {
  registroCore: 'd1c922eb5081e30f3581b95a95d74656',
  gateRegistro: 'd2ab883a409638299c135d4bee043575',
  paraguasF2: '32148d3276427fb6004201323e4b9a1f',
  colaV2: 'ef9b56eddeaad5c4297ac0e20777799c',
};

const plantilla = asegurarCopia();
if (plantilla) console.log(`copia ${db} creada desde ${plantilla}`);
assert.equal(sql('select current_database()'), db);
const existe = (f) => sql(`select (to_regprocedure('${f}') is not null)::text`) === 'true';
const md5Vivo = (f) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))),'-')`);
const censo = () => sql(`select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()`);
const censoRojo = () => sql(`select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok)`);
const gate = () => sql('select private.assert_gestion_diaria()');
const sla = () => sql(`select private.assert_sla_nucleo()||' | '||private.assert_sla_operacion()||' | '||private.assert_sla_comandos()||' | '||private.assert_sla_avisos()`);

// 0. Dependencias, en el orden de producción: historial por lead, grant por
//    columna, F1, tareas keyset, F2, actividad reciente.
const deps = [
  ['private.nombre_de_autor(uuid)', '20260919185718_crm_actividades_de_lead.sql'],
  [null, '20260919211105_crm_leads_grant_columna_procedencia.sql', () => sql(`select (exists (select 1 from pg_attribute where attrelid='crm.leads'::regclass and attname='alta_manual' and attacl is not null))::text`) === 'true'],
  ['crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)', '20260919211958_crm_gestion_diaria_registro.sql'],
  ['crm.tareas_pendientes_fn(integer,timestamptz,uuid)', '20260919235100_crm_tareas_pendientes_keyset.sql'],
  ['crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', '20260920005000_crm_gestion_diaria_resultado_llamada.sql'],
  ['crm.actividades_recientes_fn(integer)', '20260920014500_crm_actividades_recientes.sql'],
];
for (const [firma, archivo, presente] of deps) {
  const ya = presente ? presente() : existe(firma);
  if (ya) continue;
  const ruta = MIG(archivo);
  assert.ok(existsSync(ruta), `Falta la dependencia ${archivo}`);
  sql(readFileSync(ruta, 'utf8'));
  console.log(`dependencia instalada en la copia: ${archivo}`);
}
assert.match(sla(), /^OK.*\| OK.*\| OK.*\| OK/, 'Los gates SLA deben estar verdes antes');
assert.equal(md5Vivo('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)'), PROD.colaV2, 'La copia tiene la cola v2 de producción');
const censoAntes = censo(), censoRojoAntes = censoRojo();

// 1. Si ya estaba instalada (segunda corrida), se retira con la reversa para ensayar limpio.
if (existe(PUERTA)) { sql(reversa); console.log('instalación previa retirada con la reversa'); }
assert.ok(!existe(PUERTA));
assert.match(gate(), /^OK: Gestion Diaria \[OK.*\] \[OK.*\]$/, 'paraguas de F1+F2 verde antes de instalar F3');
assert.equal(md5Vivo(REGISTRO_CORE), PROD.registroCore, 'La copia tiene el núcleo del registro de producción');
assert.equal(md5Vivo('private.assert_gestion_diaria_registro()'), PROD.gateRegistro, 'La copia tiene el gate de F1 de producción');
assert.equal(md5Vivo('private.assert_gestion_diaria()'), PROD.paraguasF2, 'La copia tiene el paraguas de F2 de producción');

// 2. SELLADO en dos pasadas: la migración con placeholders instala todo menos el
//    postflight (que fallaría en el md5); se miden los cuerpos, se escriben en el
//    archivo y se deshace la instalación provisional.
let migracion = readFileSync(rutaMigracion, 'utf8');
if (migracion.includes('_PENDIENTE_')) {
  const sinPostflight = migracion.replace(/do \$postflight\$[\s\S]*?\$postflight\$;/, 'select 1;');
  assert.notEqual(sinPostflight, migracion, 'no se encontró el bloque postflight');
  sql(sinPostflight);
  const sellos = {
    MD5_ANALISTA_PUERTA_PENDIENTE_000: md5Vivo(PUERTA),
    MD5_ANALISTA_CORE_PENDIENTE_00000: md5Vivo(CORE),
    MD5_LLAMADAS_PENDIENTE_0000000000: md5Vivo(LLAMADAS),
    MD5_UMBRALES_PENDIENTE_0000000000: md5Vivo(UMBRALES),
    MD5_REGISTRO_CORE_PENDIENTE_0000000: md5Vivo(REGISTRO_CORE),
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

// 3. Instalación real + gate + mutantes (F3, F2 y F1) + oráculo + censo intacto.
sql(migracion);
assert.match(gate(), /^OK: Gestion Diaria \[OK.*\] \[OK.*\] \[OK.*\]$/, 'gate paraguas tras instalar');
const mutantesF3 = sql("set gestion_diaria.banco = on; select private.assert_gestion_diaria_analista_mutantes()");
assert.match(mutantesF3, /^OK: 20 mutantes detectados/, mutantesF3);
const mutantesF2 = sql("set gestion_diaria.banco = on; select private.assert_gestion_diaria_resultado_mutantes()");
assert.match(mutantesF2, /^OK: 14 mutantes detectados/, mutantesF2);
const mutantesF1 = sql("set gestion_diaria.banco = on; select private.assert_gestion_diaria_mutantes()");
assert.match(mutantesF1, /^OK: 10 mutantes detectados/, mutantesF1);
assert.match(ejecutar('select private.assert_gestion_diaria_analista_mutantes()').stderr, /solo corren en el banco/, 'Sin la marca de banco los mutantes se niegan');
assert.match(gate(), /^OK/, 'gate tras los mutantes (nada quedó alterado)');
assert.match(sla(), /^OK.*\| OK.*\| OK.*\| OK/, 'gates SLA tras instalar');
const salida = sql(oraculo);
assert.match(salida, /GESTION_DIARIA_ANALISTA_OK/, salida);
assert.equal(censo(), censoAntes, 'El censo analítico no cambia');
assert.equal(censoRojo(), censoRojoAntes, 'El conjunto rojo del censo no cambia');
const md5 = { puerta: md5Vivo(PUERTA), core: md5Vivo(CORE), llamadas: md5Vivo(LLAMADAS), umbrales: md5Vivo(UMBRALES), registroCore: md5Vivo(REGISTRO_CORE) };
for (const m of Object.values(md5)) assert.match(m, /^[0-9a-f]{32}$/);
assert.notEqual(md5.registroCore, PROD.registroCore, 'El núcleo del registro cambió de cuerpo (lista blanca ampliada)');

// 4. Reversa: devuelve EXACTAMENTE los cuerpos de producción (medidos el 20/09) y reinstalación determinista.
sql(reversa);
assert.ok(!existe(PUERTA), 'La reversa retira la puerta');
assert.ok(!existe('private.assert_gestion_diaria_analista()'), 'La reversa retira el gate de F3');
assert.match(gate(), /^OK: Gestion Diaria \[OK.*\] \[OK.*\]$/, 'paraguas de F1+F2 verde tras la reversa');
assert.equal(md5Vivo(REGISTRO_CORE), PROD.registroCore, 'La reversa devuelve el núcleo del registro al cuerpo de producción');
assert.equal(md5Vivo('private.assert_gestion_diaria_registro()'), PROD.gateRegistro, 'La reversa devuelve el gate de F1 al cuerpo de producción');
assert.equal(md5Vivo('private.assert_gestion_diaria()'), PROD.paraguasF2, 'La reversa devuelve el paraguas al cuerpo de F2');
sql(migracion);
assert.match(gate(), /^OK: Gestion Diaria \[OK.*\] \[OK.*\] \[OK.*\]$/, 'gate tras reinstalar');
assert.equal(md5Vivo(PUERTA), md5.puerta, 'La reinstalación es determinista (puerta)');
assert.equal(md5Vivo(CORE), md5.core, 'La reinstalación es determinista (nucleo)');
assert.equal(md5Vivo(REGISTRO_CORE), md5.registroCore, 'La reinstalación es determinista (registro)');

const verificacion = {
  version: VERSION, nombre: NOMBRE, base: db, ensayado_en: new Date().toISOString(),
  md5_puerta: md5.puerta, md5_core: md5.core, md5_llamadas: md5.llamadas, md5_umbrales: md5.umbrales, md5_registro_core: md5.registroCore,
  sha256_migracion: createHash('sha256').update(migracion).digest('hex'),
  sha256_reversa: createHash('sha256').update(reversa).digest('hex'),
  mutantes_f3: mutantesF3, mutantes_f2: mutantesF2, mutantes_f1: mutantesF1,
  oraculo: 'GESTION_DIARIA_ANALISTA_OK', censo_intacto: true, reversa_a_produccion: true,
};
writeFileSync(new URL('./verificacion.json', import.meta.url), JSON.stringify(verificacion, null, 2) + '\n');
const { SALIDA, bytes } = escribirRegistrador({ md5Puerta: md5.puerta, md5Core: md5.core, md5Llamadas: md5.llamadas, md5Umbrales: md5.umbrales, md5RegistroCore: md5.registroCore });
console.log(`ENSAYO OK · ${mutantesF3} · ${mutantesF2} · ${mutantesF1} · registrador ${SALIDA} (${bytes} bytes) · md5 puerta ${md5.puerta} · nucleo ${md5.core} · llamadas ${md5.llamadas} · registro ${md5.registroCore}`);
