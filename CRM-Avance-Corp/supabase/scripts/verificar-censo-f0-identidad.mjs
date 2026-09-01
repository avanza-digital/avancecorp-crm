#!/usr/bin/env node
// ---------------------------------------------------------------------------
// Verificador ESTÁTICO y LOCAL del censo F0 de identidad de inversionistas.
// No abre red ni conexión alguna: solo lee el .sql hermano y comprueba que
// las salvaguardas del encargo estén presentes y que no exista ninguna vía
// de escritura. NO valida esquema ni semántica: eso exige ejecución
// read-only contra la base y revisión humana. Uso:
//
//   node supabase/scripts/verificar-censo-f0-identidad.mjs
//
// Sale con código 0 si TODO pasa; 1 si alguna verificación falla.
// ---------------------------------------------------------------------------
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const rutaSql = join(aqui, 'censo-f0-identidad-inversionistas.sql');
const crudo = readFileSync(rutaSql, 'utf8');

// --- 1. esqueleto: quitar comentarios y literales de texto ------------------
// (los literales '...' pueden contener palabras como "no crea"; no deben
// disparar falsos positivos ni esconder sentencias: se reemplazan por '').
function esqueleto(sql) {
  let out = '';
  let i = 0;
  while (i < sql.length) {
    const dos = sql.slice(i, i + 2);
    if (dos === '--') {
      const fin = sql.indexOf('\n', i);
      i = fin === -1 ? sql.length : fin; // conserva el salto de línea
    } else if (dos === '/*') {
      const fin = sql.indexOf('*/', i + 2);
      if (fin === -1) throw new Error('comentario /* sin cerrar');
      i = fin + 2;
    } else if (sql[i] === "'") {
      let j = i + 1;
      for (;;) {
        const fin = sql.indexOf("'", j);
        if (fin === -1) throw new Error('literal de texto sin cerrar');
        if (sql[fin + 1] === "'") { j = fin + 2; continue; } // '' escapada
        j = fin + 1;
        break;
      }
      out += "''";
      i = j;
    } else if (sql[i] === '$' && /\$[a-zA-Z_]*\$/.test(sql.slice(i, sql.indexOf('$', i + 1) + 1))) {
      // dollar-quoting: prohibido en el censo (esconde cuerpo ejecutable)
      throw new Error('el censo no debe contener dollar-quoting ($$...$$)');
    } else {
      out += sql[i];
      i += 1;
    }
  }
  return out;
}

const fallos = [];
const ok = [];
function exige(cond, nombre, detalle = '') {
  if (cond) ok.push(nombre);
  else fallos.push(nombre + (detalle ? ` — ${detalle}` : ''));
}

let esq = '';
try {
  esq = esqueleto(crudo);
} catch (e) {
  fallos.push(`esqueleto: ${e.message}`);
}

if (esq) {
  // --- 2. forma de la transacción ------------------------------------------
  const sentencias = esq
    .split(';')
    .map((s) => s.replace(/\s+/g, ' ').trim())
    .filter((s) => s.length > 0);

  exige(sentencias.length >= 4, 'hay sentencias suficientes');
  exige(/^begin$/i.test(sentencias[0] ?? ''), 'begin es la PRIMERA sentencia');
  exige(
    /^set transaction read only$/i.test(sentencias[1] ?? ''),
    'set transaction read only es la SEGUNDA sentencia (inmediata)',
  );
  exige(/^rollback$/i.test(sentencias[sentencias.length - 1] ?? ''), 'rollback es la ÚLTIMA sentencia');

  const intermedias = sentencias.slice(2, -1);
  const setsLocales = intermedias.filter((s) => /^set local /i.test(s));
  const consultas = intermedias.filter((s) => /^(with|select)\b/i.test(s));
  exige(
    intermedias.length === setsLocales.length + consultas.length,
    'solo hay set local + consulta entre begin y rollback',
    `sentencias inesperadas: ${intermedias.filter((s) => !/^set local /i.test(s) && !/^(with|select)\b/i.test(s)).map((s) => s.slice(0, 60)).join(' | ') || '(ninguna)'}`,
  );
  exige(consultas.length === 1, 'exactamente UNA consulta SELECT/CTE', `hay ${consultas.length}`);

  // --- 3. salvaguardas locales obligatorias --------------------------------
  exige(setsLocales.some((s) => /^set local statement_timeout/i.test(s)), 'statement_timeout local');
  exige(setsLocales.some((s) => /^set local lock_timeout/i.test(s)), 'lock_timeout local');
  exige(setsLocales.some((s) => /^set local search_path/i.test(s)), 'search_path local');

  // --- 4. cero vías de escritura o de control ------------------------------
  const prohibidas = [
    'insert', 'update', 'delete', 'truncate', 'create', 'alter', 'drop',
    'grant', 'revoke', 'copy', 'merge', 'vacuum', 'refresh', 'reindex',
    'cluster', 'commit', 'call', 'do', 'execute', 'notify', 'listen',
    'unlisten', 'discard', 'prepare', 'deallocate', 'savepoint', 'release',
    'setval', 'nextval', 'pg_advisory_lock', 'pg_terminate_backend',
    'pg_cancel_backend', 'dblink', 'set_config',
  ];
  for (const palabra of prohibidas) {
    const re = new RegExp(`(^|[^a-z0-9_$."])${palabra}([^a-z0-9_$."]|$)`, 'i');
    exige(!re.test(esq), `sin «${palabra}»`);
  }
  exige(!/security\s+definer/i.test(esq), 'sin SECURITY DEFINER propio');
  exige(!/for\s+(update|share|no\s+key|key\s+share)/i.test(esq), 'sin FOR UPDATE/SHARE');

  // --- 5. no depender de lo que aún no existe ------------------------------
  exige(!/\binversionista_id\b/i.test(esq), 'sin inversionista_id (no existe aún)');
  exige(!/crm\s*\.\s*inversionistas\b/i.test(esq), 'sin crm.inversionistas (no existe aún)');
  exige(!/\bnaturaleza\b/i.test(esq), 'sin columna naturaleza (no existe aún)');

  // --- 6. la lectura de los núcleos usa las firmas pinneadas ----------------
  exige(
    crudo.includes("'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure"),
    'evidencia md5 apunta a la firma pinneada de conversion_episodios',
  );
  exige(
    crudo.includes("'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure"),
    'evidencia md5 apunta a la firma pinneada de capital_episodios',
  );
  exige(
    crudo.includes("'private.peso_referido_conversion(date)'::regprocedure"),
    'evidencia md5 apunta a la firma de peso_referido_conversion',
  );

  // --- 6b. regresiones vetadas por la corrección Codex (P1/P2) --------------
  // Fallan si vuelve alguna de las formas corregidas el 2026-08-31.
  exige(!/p_factor\s*=\s*1\b/i.test(esq), 'sin «p_factor = 1»: el factor de referido debe ser el real del mes');
  exige(!/1\s*::\s*numeric/.test(esq), 'sin factor 1 literal (1::numeric) hacia el núcleo');
  exige(/peso_referido_conversion/i.test(esq), 'usa private.peso_referido_conversion (meses abiertos)');
  exige(/ponderacion_referido/i.test(esq), 'usa periodos_cerrados.ponderacion_referido (meses sellados)');
  exige(/aporte_numerador/i.test(esq), 'compara las reglas en unidades ponderadas (SUM de aporte_numerador)');
  exige(/fue_referido/i.test(esq), 'conserva fue_referido del núcleo');
  exige(!/(perfil~|lead~)/.test(crudo), 'sin fallback «perfil~» / «lead~» (clave técnica disfrazada de identidad)');
  exige(/grupo_dedupe_no_resuelto/.test(crudo), 'episodios no resolubles con grupo técnico propio (grupo_dedupe_no_resuelto)');
  exige(/identidad_resoluble/i.test(esq), 'expone identidad_resoluble por episodio');
  exige(/clase\s+in\s*\(\s*'A'\s*,\s*'B'\s*\)/.test(crudo), 'el dedupe documental pasa por el gate de clases A/B');
  exige(!/=\s*'cooperativa'\s*then\s*'cooperativa'/i.test(crudo), 'capital sin colapsar al grupo genérico cooperativa');
  exige(
    /using\s*\(\s*empresa\s*,\s*moneda\s*,\s*medida\s*,\s*estado\s*\)/i.test(esq),
    'paridad de capital comparada por empresa/moneda/medida/estado',
  );
  exige(!/dif_conteo\s*\+\s*dif_monto/i.test(esq), 'paridad sin sumar diferencia de conteo + diferencia monetaria');
  exige(/capital_cardinalidad/i.test(esq), 'prueba explícita de cardinalidad 1:1 del enriquecimiento');
  exige(/cooperativa\s*=\s*'qorilazo'/i.test(crudo), 'censo explícito de Qorilazo');
  exige(/cooperativa\s*=\s*'prodelco'/i.test(crudo), 'censo explícito de Prodelco');
  exige(
    /c\.vigente\s+and\s+c\.moneda\s*=\s*'PEN'/i.test(crudo),
    'monto_pen_vigente filtra explícitamente moneda PEN',
  );
  exige(
    /ce\.tipo\s*<>\s*'DNI'\s+or\s+ce\.doc\s*<>\s*ln\.dni/i.test(crudo),
    'contradicción lead DNI vs cierre detecta también CE/PASAPORTE',
  );
  exige(/n_perfiles_no_cliente\s*>\s*0/i.test(esq), 'colisión cliente vs perfil de otro rol pasa a revisión E');

  // --- 7. forma del resultado agregado -------------------------------------
  exige(/as\s+seccion\b/i.test(esq), 'la salida declara la columna seccion');
  exige(/as\s+metrica\b/i.test(esq), 'la salida declara la columna metrica');
  exige(/as\s+valor\b/i.test(esq), 'la salida declara la columna valor');
  exige(/as\s+detalle\b/i.test(esq), 'la salida declara la columna detalle (jsonb)');
  exige(/transaction_read_only/i.test(crudo), 'emite el indicador real de solo lectura');
  exige(/America\/Lima/.test(crudo), 'rotula la zona horaria America/Lima');
}

// --- resultado --------------------------------------------------------------
console.log(`Verificación estática de ${rutaSql}`);
console.log(`  ✓ ${ok.length} comprobaciones pasaron`);
if (fallos.length > 0) {
  console.error(`  ✗ ${fallos.length} FALLARON:`);
  for (const f of fallos) console.error(`    - ${f}`);
  process.exit(1);
}
console.log('  salvaguardas estáticas OK; esquema/semántica requieren ejecución read-only y revisión');
