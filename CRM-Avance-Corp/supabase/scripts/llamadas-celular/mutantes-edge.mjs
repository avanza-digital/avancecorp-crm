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

const MUTANTES = [
  ['clave sin comprobar su forma', 'const CREDENCIAL = /^[0-9a-f]{64}$/;', 'const CREDENCIAL = /./;'],
  ['sin tope de 4 KB', 'const TOPE_BYTES = 4096;', 'const TOPE_BYTES = 1_000_000;'],
  ['claves de más en el cuerpo', ' || Object.keys(cuerpo).length !== 2) return', ') return'],
  ['evento con claves no previstas', 'if (!esObjeto(e) || Object.keys(e).some((k) => !CLAVES_EVENTO.has(k))) return false;', 'if (!esObjeto(e)) return false;'],
  ['evento de otra versión', '  return e.v === 1\n', '  return true\n'],
  ['duración sin rango', 'opcional(e.duracion_seg, (d) => entero(d, 0, 86400))', 'opcional(e.duracion_seg, () => true)'],
  ['latido sin cola obligatoria', '&& entero(l.en_cola, 0, 100000)', '&& opcional(l.en_cola, () => true)'],
  ['42501 con otra respuesta', "if (e.code === '42501') return noAutorizado();", "if (e.code === '42501') return respuesta(403, { error: 'Prohibido' });"],
  ['la respuesta delata lo que contestó la base',
    '        await d.ingerir(credencial, evento);\n        // Guardada, repetida o ignorada: la misma respuesta (propuesta #12).\n        return respuesta(202, { recibido: true, abrir: urlAbrir(d.urlCrm, evento.numero) });',
    '        const dato = await d.ingerir(credencial, evento) as Json;\n        return respuesta(202, { ...dato, recibido: true, abrir: urlAbrir(d.urlCrm, evento.numero) });'],
  ['429 sin Retry-After', "{ 'Retry-After': String(espera) });", '{});'],
  ['P0409 como 503', "if (e.code === 'P0409') return", "if (e.code === 'P0409x') return"],
  ['URL de F1 sin codificar el número', '${encodeURIComponent(numero.trim())}', '${numero.trim()}'],
  ['acepta otros métodos', "if (req.method !== 'POST') return", "if (req.method === 'TRACE') return"],
  ['acepta cuerpos que no se declaran JSON', "if (tipo !== 'application/json') return", "if (tipo === 'x/nada') return"],
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
