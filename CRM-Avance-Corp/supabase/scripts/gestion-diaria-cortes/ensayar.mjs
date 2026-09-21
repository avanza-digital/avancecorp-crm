// Preparación sin escrituras por defecto. Sólo --sellos-local o --ensayar-local
// ejecutan SQL, tras aprobación humana sobre este candidato y esta base.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { baseLocal, sqlLocal } from './banco.mjs';
const leer = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
const candidato = '../../migrations/20260921214018_crm_gestion_diaria_cortes.sql';
const fuente = leer(candidato);
const sha256 = createHash('sha256').update(fuente).digest('hex');
const args = process.argv.slice(2);
const modo = args[0] ?? '--preflight';
assert.ok(['--preflight', '--sellos-local', '--ensayar-local'].includes(modo), 'Modo no permitido');
assert.equal(args.length <= 1, true, 'No acepta destinos ni argumentos adicionales');
assert.match(fuente, /^--[\s\S]*\nbegin;\n/);
assert.match(fuente, /commit;\s*$/);
assert.doesNotMatch(fuente, /\b(?:alter|drop)\s+(?:table|function|policy)\s+public\./i);
// Allow-list léxica complementaria a la revisión: sólo la FK preexistente como
// patrón del repositorio. No se presenta como parser SQL ni frontera de seguridad.
assert.equal((fuente.match(/references public\.perfiles\(id\)/g) ?? []).length, 1);
assert.doesNotMatch(fuente.replace('references public.perfiles(id)', ''), /\bpublic["\s]*\./i);
if (modo === '--preflight') {
  console.log(JSON.stringify({ estado: 'PREPARADO_SIN_EJECUTAR_SQL', candidato, baseLocal, sha256 }));
  process.exit(0);
}
assert.equal(sqlLocal('select current_database()'), baseLocal);
assert.equal(sqlLocal("select to_regclass('crm.politica_gestion_diaria') is null"), 't',
  'La base ya tiene política; no reemplazar ni revertir trabajo ajeno');
const firmasPrevias = [
  'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',
  'private.gestion_diaria_equipo_core(date,uuid)', 'private.gestion_diaria_umbrales()',
  'private.assert_gestion_diaria_analista()', 'private.assert_gestion_diaria_equipo()',
  'private.assert_gestion_diaria()',
];
const hashFunciones = (firmas) => sqlLocal(`select jsonb_build_array(${firmas.map(
  (f) => `md5(pg_get_functiondef('${f}'::regprocedure))`).join(',')});`);
const censo = () => sqlLocal("select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()");
if (modo === '--sellos-local') {
  const medicion = `select jsonb_build_object(
    '__MD5_ANALISTA__', md5(pg_get_functiondef('${firmasPrevias[0]}'::regprocedure)),
    '__MD5_EQUIPO__', md5(pg_get_functiondef('${firmasPrevias[1]}'::regprocedure)),
    '__MD5_UMBRALES__', md5(pg_get_functiondef('${firmasPrevias[2]}'::regprocedure)),
    '__SRC_POLITICA__', (select md5(prosrc) from pg_proc where oid='private.politica_gestion_diaria_vigente(timestamptz)'::regprocedure),
    '__SRC_UMBRALES__', (select md5(prosrc) from pg_proc where oid='private.gestion_diaria_umbrales(timestamptz)'::regprocedure),
    '__SRC_CORTES__', (select md5(prosrc) from pg_proc where oid='private.gestion_diaria_cortes(date,uuid[],timestamptz)'::regprocedure),
    '__SRC_INSERTAR__', (select md5(prosrc) from pg_proc where oid='private.trg_politica_gestion_diaria_insertar()'::regprocedure),
    '__RLS_POLITICA__', (select md5(pg_get_expr(polqual,polrelid)) from pg_policy where polrelid='crm.politica_gestion_diaria'::regclass and polname='politica_gestion_diaria_select')
  );`;
  const provisional = fuente.replace(/do \$postflight\$[\s\S]*?\$postflight\$;/, '')
    .replace("notify pgrst, 'reload schema';", '').replace(/commit;\s*$/, `${medicion}\nrollback;`);
  console.log(sqlLocal(provisional));
  assert.equal(sqlLocal("select to_regclass('crm.politica_gestion_diaria') is null"), 't');
  console.log('PASS: compilación y medición revertidas, sin instalación');
  process.exit(0);
}
assert.doesNotMatch(fuente, /__(?:MD5|SRC|RLS)_\w+__/);
const antes = hashFunciones(firmasPrevias);
const censoAntes = censo();
try {
  sqlLocal(fuente);
  console.log('PASS: instalación candidata, gates Gestión Diaria y SLA');
  assert.match(sqlLocal(leer('./test-cortes.sql')), /GESTION_DIARIA_CORTES_OK/);
  console.log('PASS: cortes, política, calendario y permisos por identidad');
  await import('./verificar-tipos.mjs');
  await import('./test-mutantes.mjs');
  for (const linea of sqlLocal(leer('./test-rendimiento.sql')).split('\n')) {
    if (linea.startsWith('F43_RENDIMIENTO:')) console.log(linea);
  }
  for (const nombre of ['equipo', 'calendario', 'jerarquia']) {
    assert.match(sqlLocal(leer(`../gestion-diaria-equipo/test-${nombre}.sql`)), /GESTION_DIARIA_\w+_OK/);
    console.log(`PASS: regresión F4 ${nombre}`);
  }
  assert.equal(censo(), censoAntes, 'No añadir contadores al censo analítico');
  const instalado = hashFunciones(firmasPrevias);
  sqlLocal(leer('./reversa.sql'));
  assert.equal(hashFunciones(firmasPrevias), antes, 'Reversa exacta de funciones previas');
  sqlLocal(fuente);
  assert.equal(hashFunciones(firmasPrevias), instalado, 'Reinstalación determinista');
  console.log('PASS: reversa exacta y reinstalación determinista');
} finally {
  if (sqlLocal("select to_regclass('crm.politica_gestion_diaria') is not null") === 't') {
    sqlLocal(leer('./reversa.sql'));
  }
  assert.equal(hashFunciones(firmasPrevias), antes, 'La base debe terminar restaurada');
  assert.equal(censo(), censoAntes);
}
console.log(JSON.stringify({ estado: 'PASS', baseLocal, sha256, base_final: 'restaurada_sin_cortes',
  ensayado_en: new Date().toISOString() }));
