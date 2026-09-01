#!/usr/bin/env node
// ---------------------------------------------------------------------------
// Verificador ESTÁTICO y LOCAL de la cola F0.5 de identidad de inversionistas.
// No abre red ni conexión alguna: solo lee el .sql hermano y comprueba que
// las salvaguardas del encargo estén presentes y que no exista ninguna vía
// de escritura ni de fuga de PII cruda. NO valida esquema ni semántica: eso
// exige ejecución read-only contra la base y revisión humana. Uso:
//
//   node supabase/scripts/verificar-cola-f05-identidad.mjs
//
// Sale con código 0 si TODO pasa; 1 si alguna verificación falla.
// ---------------------------------------------------------------------------
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const rutaSql = join(aqui, 'cola-f05-identidad-inversionistas.sql');
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
      // dollar-quoting: prohibido en la cola (esconde cuerpo ejecutable)
      throw new Error('la cola no debe contener dollar-quoting ($$...$$)');
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

function argumentosDeLlamadas(sql, nombre) {
  const resultados = [];
  const re = new RegExp(`\\b${nombre}\\s*\\(`, 'ig');
  for (let m; (m = re.exec(sql)) !== null;) {
    const inicio = re.lastIndex;
    let profundidad = 1;
    let enLiteral = false;
    let i = inicio;
    for (; i < sql.length && profundidad > 0; i += 1) {
      const ch = sql[i];
      if (ch === "'") {
        if (enLiteral && sql[i + 1] === "'") { i += 1; continue; }
        enLiteral = !enLiteral;
      } else if (!enLiteral && ch === '(') profundidad += 1;
      else if (!enLiteral && ch === ')') profundidad -= 1;
    }
    if (profundidad !== 0) throw new Error(`${nombre}(...) sin cierre`);
    resultados.push(sql.slice(inicio, i - 1));
    re.lastIndex = i;
  }
  return resultados;
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

  // --- 6. núcleos: mismas firmas y factor real que el censo F0 --------------
  exige(
    crudo.includes('private.conversion_episodios('),
    'usa el núcleo private.conversion_episodios (mismo universo del F0)',
  );
  exige(
    crudo.includes('private.capital_episodios('),
    'usa el núcleo private.capital_episodios (mismo universo del F0)',
  );
  exige(!/p_factor\s*=\s*1\b/i.test(esq), 'sin «p_factor = 1»: el factor de referido debe ser el real del mes');
  exige(!/1\s*::\s*numeric/.test(esq), 'sin factor 1 literal (1::numeric) hacia el núcleo');
  exige(/peso_referido_conversion/i.test(esq), 'usa private.peso_referido_conversion (meses abiertos)');
  exige(/ponderacion_referido/i.test(esq), 'usa periodos_cerrados.ponderacion_referido (meses sellados)');
  exige(/aporte_numerador/i.test(esq), 'conserva las unidades ponderadas (aporte_numerador)');

  // --- 7. identidad SOLO documental: cero fallback débil --------------------
  exige(!/(perfil~|lead~)/.test(crudo), 'sin fallback «perfil~» / «lead~» (clave técnica disfrazada de identidad)');
  exige(/clase\s+in\s*\(\s*'A'\s*,\s*'B'\s*\)/.test(crudo), 'la resolubilidad pasa por el gate de clases A/B');
  // tel9/correo_n/nombre_n solo pueden aparecer en las señales agregadas
  // (leads_f / seniales); si alguna vez alimentan «identidad», es regresión.
  const bloqueIdentidad = crudo.match(/lead_identidad as \([\s\S]*?\n\),/);
  exige(bloqueIdentidad !== null, 'existe el CTE lead_identidad');
  if (bloqueIdentidad) {
    exige(
      !/(tel9|correo_n|nombre_n)/.test(bloqueIdentidad[0]),
      'lead_identidad no usa teléfono/correo/nombre para vincular',
    );
  }
  exige(
    /jamás|jamas|nunca/i.test(crudo),
    'la cola declara por escrito que la señal débil no une identidades',
  );

  // --- 8. pseudonimización: hashes deterministas, cero PII cruda ------------
  exige(/md5\(\s*'f05\|/.test(crudo), 'referencia_hash = md5 determinista con prefijo f05|tipo|PK');
  exige(!/md5\(\s*'gp\|'/i.test(crudo), 'ningún grupo hashea directamente tipo+documento (evita fuerza bruta de DNI)');
  exige(/gp-clave-tecnica\|/i.test(crudo), 'grupo documental derivado de referencias técnicas aleatorias');
  const md5Args = argumentosDeLlamadas(crudo, 'md5');
  exige(md5Args.length > 0, 'se identifican las llamadas md5 para inspección');
  exige(
    md5Args.every((arg) => !/\b(doc|dni|documento|correo|telefono|nombre)\b/i.test(arg)),
    'ningún hash recibe documento, DNI u otra PII como argumento',
  );
  exige(/grupo_persona_hash/i.test(esq), 'expone grupo_persona_hash para explicar solapamientos');
  exige(/as\s+caso_codigo\b/i.test(esq), 'la salida declara caso_codigo');
  for (const col of ['categoria', 'impacto_comercial', 'estado_recomendado',
    'accion_propuesta', 'fuente', 'referencia_hash', 'grupo_persona_hash', 'detalle']) {
    exige(new RegExp(`as\\s+${col}\\b`, 'i').test(esq) || new RegExp(`\\b${col}\\b`, 'i').test(esq),
      `la salida declara la columna ${col}`);
  }
  // ninguna clave de jsonb puede transportar PII cruda ni IDs crudos
  const clavesProhibidas = [
    'dni', 'documento', 'telefono', 'correo', 'nombre', 'nombre_completo',
    'direccion', 'email', 'id', 'uuid', 'lead_id', 'perfil_id', 'cliente_id',
    'contrato_id', 'cierre_externo_id', 'operacion_id', 'vendedor_id',
    'asesor_perfil_id', 'responsable_id',
  ];
  for (const k of clavesProhibidas) {
    exige(
      !new RegExp(`'${k}'\\s*,`).test(crudo),
      `sin clave jsonb «${k}» (PII o ID crudo) en el detalle`,
    );
  }
  // la proyección final solo puede exponer las 9 columnas de la cola: en el
  // SELECT externo (después del cierre del WITH) no puede aparecer ninguna
  // referencia cruda a doc/dni/tel9/correo_n/nombre_n fuera de un md5(...)
  const proyeccionFinal = esq.slice(esq.lastIndexOf('order by'));
  exige(
    /order by\s+categoria\s*,\s*caso_codigo/i.test(proyeccionFinal),
    'la salida se ordena por categoria, caso_codigo (columnas de la cola)',
  );

  // --- 9. las diez categorías del encargo + filas de control ----------------
  const categorias = [
    'perfil_sin_documento',
    'perfil_documento_invalido',
    'clave_compartida_con_otro_rol',
    'identidad_sin_responsable',
    'veto_sin_identidad_fuerte',
    'discrepancia_documental_convertido',
    'episodio_conversion_sin_identidad',
    'episodio_capital_sin_identidad',
    'demo_por_confirmar',
    'senial_debil_agregada',
  ];
  for (const c of categorias) {
    exige(crudo.includes(`'${c}'`), `categoría presente: ${c}`);
  }
  const bloqueCasos = crudo.match(/casos as \([\s\S]*?\n\),\nesperados_f0/);
  exige(bloqueCasos !== null, 'se puede aislar el CTE productor de casos');
  if (bloqueCasos) {
    for (const c of categorias) {
      const apariciones = bloqueCasos[0].match(new RegExp(`'${c}'`, 'g'))?.length ?? 0;
      exige(apariciones === 1, `exactamente una rama productora para ${c}`, `hay ${apariciones}`);
    }
    exige(
      !/'[^']+'\s*,\s*\w+\.(doc|dni|correo_n|tel9|nombre_n|id)\s*[,)]/i.test(bloqueCasos[0]),
      'ningún valor JSON/proyectado toma PII o ID crudo directamente',
    );
  }
  exige(crudo.includes("'F05-CONTEXTO'"), 'fila de contexto F05-CONTEXTO');
  exige(crudo.includes("'F05-RECONCILIACION'"), 'fila de reconciliación F05-RECONCILIACION');
  exige(/esperados_f0/.test(crudo), 'la reconciliación declara la baseline histórica F0');
  exige(/cuadra_con_f0_canonico/i.test(crudo), 'la reconciliación calcula un booleano de gate');
  exige(/DETENER_Y_EXPLICAR_DERIVA/.test(crudo), 'la deriva bloquea uso para F1');

  // --- 10. reglas específicas de casos --------------------------------------
  exige(
    /cooperativa\s*=\s*'qorilazo'\s+and\s+c\.moneda\s*=\s*'PEN'\s+and\s+c\.monto\s*=\s*100000/i.test(crudo),
    'el candidato demo es EXACTAMENTE el cierre Qorilazo de 100000 PEN',
  );
  exige(crudo.includes("'requiere_confirmacion_demo'"), 'el demo queda en requiere_confirmacion_demo, sin asumir');
  exige(/monto_agregado_del_caso/.test(crudo), 'capital sin identidad expone monto agregado del caso');
  exige(/leads_afectados/.test(crudo), 'la señal débil emite solo un conteo agregado');
  exige(
    /where\s+s\.n\s*>\s*0/i.test(esq),
    'la señal débil emite a lo sumo una fila por tipo (solo si aporta)',
  );
  exige(
    /ce\.tipo\s*<>\s*'DNI'\s+or\s+ce\.doc\s*<>\s*ln\.dni/i.test(crudo),
    'la discrepancia documental detecta también CE/PASAPORTE (por tipo y por valor)',
  );
  exige(/n_perfiles_no_cliente\s*>\s*0/i.test(esq), 'la clave compartida con otro rol se individualiza por clave');
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
