#!/usr/bin/env node
// Mutantes de la Edge crm-llamadas-ingesta (F3-b): cada uno neutraliza una defensa del handler en una
// COPIA temporal y exige que handler.test.ts falle. El archivo del repo no se toca. Si un mutante
// sobrevive, esa defensa no está probada.
//
// Uso: npm run test:llamadas-ingesta:mutantes   (Deno 2.x en el PATH, o LLAMADAS_DENO con su ruta)
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = fileURLToPath(new URL('../../..', import.meta.url));
const ORIGEN = join(RAIZ, 'supabase/functions/crm-llamadas-ingesta');
const EXE = process.platform === 'win32' ? '.exe' : '';
const DENO = process.env.LLAMADAS_DENO
  ?? (existsSync(join(homedir(), `.local/deno/deno${EXE}`)) ? join(homedir(), `.local/deno/deno${EXE}`) : 'deno');
const original = readFileSync(join(ORIGEN, 'handler.ts'), 'utf8').replace(/\r\n/g, '\n');

// Contrato de 20261005143843 (plan v2 §1): la Edge solo revisa el transporte y traduce el resultado de la base.
const MUTANTES = [
  ['JSON imposible para jsonb pasa a PostgREST', ' && admiteJsonb(cuerpo) ? cuerpo : null;', ' ? cuerpo : null;'],
  ['clave sin comprobar su forma', 'const CREDENCIAL = /^[0-9a-f]{64}$/;', 'const CREDENCIAL = /./;'],
  ['sin tope de 4 KB', 'const TOPE_BYTES = 4096;', 'const TOPE_BYTES = 1_000_000;'],
  ['un sobre con claves de más pasa su carga', ' && Object.keys(cuerpo).length === 2 && admiteJsonb(cuerpo) ? cuerpo : null;', ' && admiteJsonb(cuerpo) ? cuerpo : null;'],
  ['el JSON mal formado no llega a la base (no gasta cupo)', "    if (cuerpo === GRANDE) return respuesta(413, { error: 'Petición demasiado grande' });\n",
    "    if (cuerpo === GRANDE) return respuesta(413, { error: 'Petición demasiado grande' });\n    if (cuerpo === MAL_FORMADO) return respuesta(400, { error: 'Petición inválida' });\n"],
  ['el latido va a la puerta de llamadas', 'esLatido ? await d.registrarSalud(credencial, carga) : await d.ingerir(credencial, carga)', 'await d.ingerir(credencial, carga)'],
  ['el «invalido» de la base sale como aceptado', "  if (dato.resultado === 'invalido') {", "  if (dato.resultado === 'invalido') return { aceptado: true };\n  if (false) {"],
  ['el «invalido» sin el mensaje de la base', "typeof dato.mensaje === 'string' && dato.mensaje !== '' ? dato.mensaje.slice(0, 200) : 'Petición inválida'", "'Petición inválida'"],
  ['el mensaje sin recortar', 'dato.mensaje.slice(0, 200)', 'dato.mensaje'],
  ['un resultado sin la forma pactada se da por aceptado', '  if (!esObjeto(dato)) return null;\n', '  if (!esObjeto(dato)) return { aceptado: true };\n'],
  ['42501 con otra respuesta', "if (e.code === '42501') return noAutorizado();", "if (e.code === '42501') return respuesta(403, { error: 'Prohibido' });"],
  ['la respuesta delata lo que contestó la base',
    "      return respuesta(202, { recibido: true, abrir: urlAbrir(d.urlCrm, esObjeto(carga) ? carga.numero : null) });",
    "      return respuesta(202, { recibido: true, base: resultado, abrir: urlAbrir(d.urlCrm, esObjeto(carga) ? carga.numero : null) });"],
  ['429 sin Retry-After', "{ 'Retry-After': String(espera) });", '{});'],
  ['URL de F1 sin codificar el número', '${encodeURIComponent(numero.trim())}', '${numero.trim()}'],
  ['acepta otros métodos', "if (req.method !== 'POST') return", "if (req.method === 'TRACE') return"],
  ['acepta cuerpos que no se declaran JSON', "if (tipo !== 'application/json') return", "if (tipo === 'x/nada') return"],
  // Revisión de Miguel en el #190 (P3): un corte al leer el cuerpo devuelve una respuesta controlada, y es reintentable.
  ['un corte al leer el cuerpo rompe el handler', '    return ILEGIBLE;\n', "    throw new Error('corte');\n"],
  ['un corte al leer el cuerpo aparta el aviso (400)', "if (cuerpo === ILEGIBLE) return respuesta(503,", "if (cuerpo === ILEGIBLE) return respuesta(400,"],
];

let cazados = 0;
for (const [nombre, buscar, poner] of MUTANTES) {
  const veces = original.split(buscar).length - 1;
  if (veces !== 1) { console.log(`FAIL  ${nombre}: mutante obsoleto (el fragmento aparece ${veces} veces)`); continue; }
  const carpeta = mkdtempSync(join(tmpdir(), 'mut-edge-'));
  try {
    writeFileSync(join(carpeta, 'handler.ts'), original.replace(buscar, poner));
    copyFileSync(join(ORIGEN, 'handler.test.ts'), join(carpeta, 'handler.test.ts'));
    const r = spawnSync(DENO, ['test', '--no-check', '--quiet', join(carpeta, 'handler.test.ts')], { encoding: 'utf8', timeout: 120000 });
    if (r.error) throw new Error(`no se pudo ejecutar Deno (${DENO}): ${r.error.message}`);
    const cazado = r.status !== 0;
    if (cazado) cazados++;
    console.log(`${cazado ? 'PASS' : 'FAIL'}  ${nombre}${cazado ? '' : ': SOBREVIVE (las pruebas no lo notan)'}`);
  } finally {
    rmSync(carpeta, { recursive: true, force: true });
  }
}
console.log(cazados === MUTANTES.length ? `\nTODO EN VERDE: ${cazados} mutantes cazados` : `\n${MUTANTES.length - cazados} de ${MUTANTES.length} mutantes SOBREVIVEN`);
process.exit(cazados === MUTANTES.length ? 0 : 1);
