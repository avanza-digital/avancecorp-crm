/**
 * Gate de los Apps Script (`scripts/*.gs`): que no quede NINGUNA función invocada y
 * sin definir.
 * ─────────────────────────────────────────────────────────────────────────────
 * POR QUÉ EXISTE. El 2026-08-16 el puente quedó llamando a `leerMarcas()` y
 * `guardarMarcas()` sin haberlas escrito todavía. `node --check` no lo ve —es JavaScript
 * válido— y Apps Script tampoco: revienta EN CALIENTE, a las 9 de la mañana, a mitad de
 * una corrida, después de haber leído 12.000 filas. Los .gs no se importan ni se
 * compilan en ningún sitio, así que ningún otro control del repo los mira.
 *
 * A PRUEBA DE COMENTARIOS, TEXTOS Y EXPRESIONES REGULARES — la lección del oráculo del
 * cierre de mes. Un detector ingenuo lee la prosa de los comentarios ("apertura(", "a
 * mirar(") y las regex (`/\bsol(es)?\b/`) como si fueran llamadas, y da 60 falsos
 * positivos: tanto ruido que se acaba ignorando, que es lo mismo que no tenerlo.
 *
 * Correr: node scripts/gate-apps-script.mjs      (va dentro de `npm run check:scripts`)
 */
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));

/** Lo que Apps Script y el propio JavaScript ponen sobre la mesa. */
const GLOBALES = new Set([
  // Servicios de Apps Script usados por estos scripts.
  "SpreadsheetApp", "ScriptApp", "DriveApp", "Utilities", "Session", "LockService",
  "PropertiesService", "UrlFetchApp", "MailApp", "GmailApp", "CacheService", "Logger",
  // JavaScript.
  "console", "JSON", "Math", "Date", "String", "Number", "Boolean", "Object", "Array",
  "RegExp", "Error", "Map", "Set", "Promise", "Symbol", "parseInt", "parseFloat",
  "isNaN", "isFinite", "encodeURIComponent", "decodeURIComponent", "escape", "unescape",
  // Palabras clave que van seguidas de paréntesis y no son llamadas.
  "if", "for", "while", "switch", "catch", "return", "typeof", "function", "do",
  "else", "new", "delete", "void", "in", "of", "await", "yield", "throw", "case",
]);

/**
 * Quita comentarios, cadenas y expresiones regulares, dejando el hueco. Recorre el
 * texto carácter a carácter porque cualquier atajo con regex se equivoca justo en los
 * casos que importan (una comilla dentro de un comentario, un `/` de división…).
 */
function soloCodigo(src) {
  let out = "";
  let i = 0;
  // `anterior` = último carácter significativo: decide si un "/" abre una regex
  // (después de `(`, `=`, `,`…) o es una división (después de un valor).
  let anterior = "";
  while (i < src.length) {
    const c = src[i];
    const d = src[i + 1];
    if (c === "/" && d === "/") {
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && d === "*") {
      i += 2;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++;
      i += 2;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") {
      const cierre = c;
      i++;
      while (i < src.length && src[i] !== cierre) {
        if (src[i] === "\\") i++;
        i++;
      }
      i++;
      out += '""';
      anterior = '"';
      continue;
    }
    if (c === "/" && /[(,=:[!&|?{};+\-*%<>~^]|^$/.test(anterior)) {
      i++;
      let clase = false;
      while (i < src.length) {
        if (src[i] === "\\") { i += 2; continue; }
        if (src[i] === "[") clase = true;
        else if (src[i] === "]") clase = false;
        else if (src[i] === "/" && !clase) break;
        else if (src[i] === "\n") break; // no era una regex
        i++;
      }
      i++;
      while (i < src.length && /[gimsuy]/.test(src[i])) i++;
      out += "RE";
      anterior = "E";
      continue;
    }
    out += c;
    if (!/\s/.test(c)) anterior = c;
    i++;
  }
  return out;
}

function definidas(codigo) {
  const nombres = new Set();
  // function nombre(...)
  for (const m of codigo.matchAll(/\bfunction\s+([A-Za-z_$][\w$]*)/g)) nombres.add(m[1]);
  // const/let/var nombre = function | = (...) => | = arg =>
  for (const m of codigo.matchAll(
    /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)/g
  )) nombres.add(m[1]);
  // Los PARÁMETROS también se pueden llamar (`conCandado(fn)` → `fn()`). Se recogen
  // todos, de todas las funciones, sin analizar ámbitos: eso solo afloja el control
  // para nombres que además son parámetro en alguna parte, y a cambio evita el falso
  // positivo que haría que nadie volviera a mirar este gate.
  for (const m of codigo.matchAll(/\bfunction\s*[A-Za-z_$][\w$]*?\s*\(([^)]*)\)/g)) {
    for (const p of m[1].split(",")) {
      const n = p.trim().replace(/=.*$/, "").trim();
      if (/^[A-Za-z_$][\w$]*$/.test(n)) nombres.add(n);
    }
  }
  for (const m of codigo.matchAll(/\bfunction\s*\(([^)]*)\)/g)) {
    for (const p of m[1].split(",")) {
      const n = p.trim().replace(/=.*$/, "").trim();
      if (/^[A-Za-z_$][\w$]*$/.test(n)) nombres.add(n);
    }
  }
  return nombres;
}

function invocadas(codigo) {
  const llamadas = new Map(); // nombre → primera línea donde aparece
  const lineas = codigo.split("\n");
  lineas.forEach((linea, idx) => {
    for (const m of linea.matchAll(/(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(/g)) {
      if (!llamadas.has(m[1])) llamadas.set(m[1], idx + 1);
    }
  });
  return llamadas;
}

const archivos = readdirSync(AQUI).filter((f) => f.endsWith(".gs")).sort();
let fallos = 0;

for (const archivo of archivos) {
  const bruto = readFileSync(join(AQUI, archivo), "utf8");
  const codigo = soloCodigo(bruto);
  const def = definidas(codigo);
  const huerfanas = [...invocadas(codigo)].filter(
    ([nombre]) => !def.has(nombre) && !GLOBALES.has(nombre)
  );

  if (huerfanas.length) {
    fallos += huerfanas.length;
    console.error(`\n✖ ${archivo} — ${huerfanas.length} función(es) invocada(s) y NO definida(s):`);
    for (const [nombre, linea] of huerfanas) {
      console.error(`    ${nombre}()  ·  línea ${linea}`);
    }
  } else {
    console.log(`✔ ${archivo} — ${def.size} funciones definidas, todas las llamadas resuelven`);
  }
}

// Los dos .gs conviven en UN solo proyecto de Apps Script: dos `const` con el mismo
// nombre en el ámbito global es un SyntaxError que tumba el proyecto entero, menú
// incluido. Se comprueba aquí porque por separado cada archivo es válido.
const constantes = new Map();
const choques = [];
for (const archivo of archivos) {
  const codigo = soloCodigo(readFileSync(join(AQUI, archivo), "utf8"));
  for (const m of codigo.matchAll(/^(?:const|let)\s+([A-Za-z_$][\w$]*)/gm)) {
    if (constantes.has(m[1]) && constantes.get(m[1]) !== archivo) {
      choques.push(`${m[1]} (en ${constantes.get(m[1])} y en ${archivo})`);
    } else {
      constantes.set(m[1], archivo);
    }
  }
}
// Y lo mismo con las funciones: la última definición gana, en silencio.
const funciones = new Map();
for (const archivo of archivos) {
  const codigo = soloCodigo(readFileSync(join(AQUI, archivo), "utf8"));
  for (const m of codigo.matchAll(/^function\s+([A-Za-z_$][\w$]*)/gm)) {
    if (funciones.has(m[1]) && funciones.get(m[1]) !== archivo) {
      choques.push(`${m[1]}() (en ${funciones.get(m[1])} y en ${archivo})`);
    } else {
      funciones.set(m[1], archivo);
    }
  }
}
if (choques.length) {
  fallos += choques.length;
  console.error(`\n✖ nombres repetidos entre archivos del MISMO proyecto de Apps Script:`);
  choques.forEach((c) => console.error(`    ${c}`));
} else {
  console.log(`✔ sin choques de nombres entre los ${archivos.length} archivos del proyecto`);
}

if (fallos) {
  console.error(`\n${fallos} problema(s). Estos scripts se pegan en Apps Script tal cual: no se publica así.\n`);
  process.exit(1);
}
console.log("\nGate de Apps Script en verde.\n");
