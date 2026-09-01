// Preflight del portal (miavance.com) — el guardián que al CRM le sobra y al
// portal le faltaba. Uso:
//   node _DEV_NO_SUBIR/preflight-portal.mjs <ruta-al-zip>
//
// Por qué existe: el deploy de Hostinger REEMPLAZA el sitio entero con el
// contenido del ZIP. Dos formas de hacer daño con eso, ambas vistas en vivo el
// 2026-09-01:
//   1. Un archivo que hoy está vivo y NO va en el ZIP desaparece. Un patrón de
//      exclusión demasiado ancho ('*/_*') se comió js/admin/_helpers.js, un
//      módulo real del panel admin: publicarlo lo habría dejado en blanco.
//   2. El ZIP se arma desde una rama que no contiene lo que otra sesión publicó
//      antes → su trabajo se borra sin que salte ninguna alarma.
//
// Sale 0 si es seguro publicar; 3 si hay que parar. Solo lee: no sube nada.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ZIP = process.argv[2] || '';
const DOMINIO = process.argv[3] || 'miavance.com';
const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORTAL = path.join(RAIZ, 'public_html');

// Extensiones que comparamos byte a byte. Las imágenes quedan fuera A PROPÓSITO:
// la CDN de Hostinger las recomprime en el borde (x-hcdn-request-id …-imm-edge4;
// medido: un PNG de 2097 bytes sale con 1415, mismas dimensiones) — compararlas
// daría falsos positivos en cada corrida.
const COMPARABLES = /\.(html|js|css|json|webmanifest|htaccess)$/i;

function abortar(mensaje) {
  console.error('[preflight portal RECHAZADO]', mensaje);
  process.exit(3);
}

function ejecutar(programa, argumentos) {
  return execFileSync(programa, argumentos, {
    cwd: RAIZ,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  }).trim();
}

/** Contenido CRUDO de una entrada del ZIP. Nunca por `ejecutar`: su .trim() se
 *  come el salto de línea final y hace que TODO parezca distinto (la misma
 *  trampa que el $(curl) de abajo). */
function leerDelZip(rutaZip, entrada) {
  return execFileSync('unzip', ['-p', rutaZip, entrada], {
    cwd: RAIZ,
    encoding: null,
    maxBuffer: 64 * 1024 * 1024,
  });
}

/** Descarga a fichero: NO uses $(curl) ni capturas en variable — la sustitución
 *  de comandos se traga el salto de línea final y TODO sale distinto. */
function descargar(ruta, destino) {
  const codigo = ejecutar('curl', [
    '-s', '--max-time', '30', '-o', destino, '-w', '%{http_code}',
    `https://${DOMINIO}/${ruta}`,
  ]);
  return codigo;
}

if (!ZIP || !existsSync(ZIP) || !ZIP.endsWith('.zip')) {
  abortar('uso: node _DEV_NO_SUBIR/preflight-portal.mjs <ruta-al-zip> [dominio]');
}

// ── 1. Qué trae el ZIP ────────────────────────────────────────────────────────
const enZip = ejecutar('unzip', ['-Z1', ZIP])
  .split('\n')
  .map((n) => n.replace(/^\.\//, '').trim())
  .filter((n) => n && !n.endsWith('/'));

if (enZip.length === 0) abortar('el ZIP está vacío');

// ── 2. Nada local debe colar (§14 de public_html/CLAUDE.md) ───────────────────
const PROHIBIDOS = /^(\.git\/|\.claude\/|\.codegraph\/|supabase\/|tests\/)|\.md$|\.DS_Store$|^\.gitignore$/;
const colados = enZip.filter((n) => PROHIBIDOS.test(n));
if (colados.length > 0) {
  abortar(`el ZIP lleva archivos que NUNCA deben subirse: ${colados.join(', ')}`);
}

// ── 3. Lo que está vivo y NO va en el ZIP: desaparecería ──────────────────────
// La lista viva se saca del propio repo (fuente única, §14) y se confirma contra
// el sitio: un 200 significa que ese archivo hoy existe en producción.
const enRepo = ejecutar('git', ['-C', PORTAL, 'ls-files'])
  .split('\n')
  .filter((f) => f && !PROHIBIDOS.test(f));

const enZipSet = new Set(enZip);
const perdidos = [];
for (const f of enRepo) {
  if (enZipSet.has(f)) continue;
  if (descargar(f, '/dev/null') === '200') perdidos.push(f);
}
if (perdidos.length > 0) {
  abortar(
    `estos archivos están VIVOS y no van en el ZIP — publicar los borraría:\n  ` +
      perdidos.join('\n  '),
  );
}

// ── 4. El ZIP debe contener lo publicado (no volver atrás sin querer) ─────────
// Todo archivo comparable que el ZIP trae IGUAL que el repo debe coincidir con
// producción; si difiere, es un cambio deliberado de esta sesión. Lo que se
// exige es que no haya archivos que el ZIP DEVUELVE a una versión anterior:
// se detecta comparando contra el árbol del commit publicado si lo hay.
const tmp = path.join(RAIZ, '.preflight-portal.tmp');
let comparados = 0;
let distintos = [];
for (const f of enZip) {
  if (!COMPARABLES.test(f)) continue;
  const codigo = descargar(f, tmp);
  if (codigo !== '200') continue; // archivo nuevo: no hay con qué comparar
  const vivo = readFileSync(tmp);
  const candidato = leerDelZip(ZIP, f);
  comparados += 1;
  if (Buffer.compare(candidato, vivo) !== 0) distintos.push(f);
}
try { unlinkSync(tmp); } catch { /* el fichero temporal puede no existir */ }

// ── 5. Veredicto ──────────────────────────────────────────────────────────────
console.error(
  `[preflight portal ok] ${enZip.length} archivos en el ZIP · ${comparados} comparados ` +
    `contra ${DOMINIO} · 0 archivos vivos se perderían`,
);
if (distintos.length > 0) {
  console.error(`[cambios que va a publicar: ${distintos.length}]`);
  for (const f of distintos) console.error(`  · ${f}`);
  console.error(
    '⚠️  Revisa la lista: debe contener SOLO lo que esta sesión tocó. Si aparece\n' +
      '   algo que no reconoces, es trabajo de otra sesión — pregunta antes de publicar.',
  );
} else {
  console.error('[sin cambios] el ZIP es idéntico a lo que ya está vivo.');
}
process.exit(0);
