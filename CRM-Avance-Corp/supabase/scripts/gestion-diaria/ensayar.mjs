// Ensayo completo del registro crudo de Gestión Diaria (Fase 1) sobre la copia
// local: crea la copia desde la plantilla a paridad, instala (si falta) el
// historial por lead del que se toma `private.nombre_de_autor`, mide el censo
// analítico antes, instala la migración, corre el gate propio, sus mutantes y
// el oráculo por actor, comprueba que el censo no cambió, ensaya la reversa y
// reinstala. Escribe verificacion.json y genera el registrador. Nunca toca
// producción: `banco.mjs` fija el contenedor y la base.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, sql, ejecutar, asegurarCopia } from './banco.mjs';
import { VERSION, NOMBRE, PUERTA, NUCLEO, escribirRegistrador } from './generar-registrador.mjs';

const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const migracion = leer(`../../migrations/${VERSION}_${NOMBRE}.sql`);
const reversa = leer('./reversa.sql');
const oraculo = leer('./test-gestion-diaria-registro.sql');
const args = process.argv.slice(2);
const historial = args.includes('--historial') ? args[args.indexOf('--historial') + 1] : '../../migrations/20260919185718_crm_actividades_de_lead.sql';

if (asegurarCopia()) console.log(`copia ${db} creada desde la plantilla`);
assert.equal(sql('select current_database()'), db);
const existe = (f) => sql(`select (to_regprocedure('${f}') is not null)::text`) === 'true';
const md5Vivo = (f) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))),'-')`);
const censo = () => sql(`select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()`);
const gate = () => sql('select private.assert_gestion_diaria()');
const sla = () => sql(`select private.assert_sla_nucleo()||' | '||private.assert_sla_operacion()||' | '||private.assert_sla_comandos()||' | '||private.assert_sla_avisos()`);

// 0. Dependencia: el historial por lead (nombre_de_autor). En producción ya está.
const faltaHistorial = () => !existe('private.nombre_de_autor(uuid)') || !existe('private.assert_actividades_de_lead_base()');
if (faltaHistorial()) {
  const ruta = new URL(historial, import.meta.url);
  assert.ok(existsSync(ruta), `Faltan private.nombre_de_autor / private.assert_actividades_de_lead_base y no hay historial en ${historial} (usa --historial <ruta>)`);
  sql(readFileSync(ruta, 'utf8'));
  console.log('historial por lead instalado en la copia (dependencia)');
}
assert.ok(!faltaHistorial(), 'El historial por lead (20260919185718) es prerrequisito');
assert.match(sla(), /^OK.*\| OK.*\| OK.*\| OK/, 'Los gates SLA deben estar verdes antes');
const censoAntes = censo();

// 1. Si ya estaba instalada (segunda corrida), se retira con la reversa para ensayar limpio.
if (existe(PUERTA)) { sql(reversa); console.log('instalación previa retirada con la reversa'); }
assert.ok(!existe(PUERTA));

// 2. Instalación real + gate + mutantes + oráculo + censo intacto.
sql(migracion);
assert.match(gate(), /^OK/, 'gate propio tras instalar');
const mutantes = sql("set gestion_diaria.banco = on; select private.assert_gestion_diaria_mutantes()");
assert.match(mutantes, /^OK: 10 mutantes detectados/, mutantes);
assert.match(ejecutar('select private.assert_gestion_diaria_mutantes()').stderr, /solo corren en el banco/, 'Sin la marca de banco los mutantes se niegan');
assert.match(gate(), /^OK/, 'gate propio tras los mutantes (nada quedó alterado)');
assert.match(sla(), /^OK.*\| OK.*\| OK.*\| OK/, 'gates SLA tras instalar');
const salida = sql(oraculo);
assert.match(salida, /GESTION_DIARIA_REGISTRO_OK/, salida);
assert.equal(censo(), censoAntes, 'El censo analítico no cambia: esta migración no cuenta nada');
const md5Puerta = md5Vivo(PUERTA);
const md5Nucleo = md5Vivo(NUCLEO);
assert.match(md5Puerta, /^[0-9a-f]{32}$/); assert.match(md5Nucleo, /^[0-9a-f]{32}$/);

// 3. Reversa + comprobación + reinstalación.
sql(reversa);
assert.ok(!existe(PUERTA), 'La reversa retira la puerta');
assert.equal(sql(`select (exists(select 1 from pg_indexes where indexname='actividades_autor_fecha_idx'))::text`), 'false');
sql(migracion);
assert.match(gate(), /^OK/, 'gate tras reinstalar');
assert.equal(md5Vivo(PUERTA), md5Puerta, 'La reinstalación es determinista');

const verificacion = {
  version: VERSION, nombre: NOMBRE, base: db, ensayado_en: new Date().toISOString(),
  md5_puerta: md5Puerta, md5_nucleo: md5Nucleo, sha256_migracion: createHash('sha256').update(migracion).digest('hex'),
  mutantes, oraculo: 'GESTION_DIARIA_REGISTRO_OK', censo_intacto: true,
};
writeFileSync(new URL('./verificacion.json', import.meta.url), JSON.stringify(verificacion, null, 2) + '\n');
const { SALIDA, bytes } = escribirRegistrador({ md5Puerta, md5Nucleo });
console.log(`ENSAYO OK · ${mutantes} · registrador ${SALIDA} (${bytes} bytes) · md5 puerta ${md5Puerta} · md5 nucleo ${md5Nucleo}`);
