import { entorno } from './banco-local.mjs';
// Checkpoint de la ampliación técnica PDF del 07/09/2026. No ejecuta oráculos.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sql } from './banco-local.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const evidencia = 'CRM-Avance-Corp/supabase/scripts/evidencia-f4/';
const archivoVersion = `${evidencia}version-pdf-bordes-2026-09-07/`;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const leer = ruta => readFileSync(resolve(root, ruta));
const referencia = archivo => ({ archivo, sha256: hash(leer(archivo)) });
function archivar(rutaTrabajo) {
  const destino = resolve(root, archivoVersion, rutaTrabajo);
  const bytes = leer(rutaTrabajo);
  mkdirSync(dirname(destino), { recursive: true });
  writeFileSync(destino, bytes, { flag: 'wx' });
  assert.equal(hash(readFileSync(destino)), hash(bytes));
  return { archivo: archivoVersion + rutaTrabajo, rutaTrabajo, sha256: hash(bytes) };
}

// Las referencias anteriores deben seguir comprobándose después de archivar.
const anteriorRuta = `${evidencia}2026-09-07-continuacion-pdf-auditoria.json`;
const anterior = JSON.parse(leer(anteriorRuta));
let referenciasAnteriores = 0;
function comprobarReferencias(valor) {
  if (!valor || typeof valor !== 'object') return;
  if (typeof valor.archivo === 'string' && typeof valor.sha256 === 'string') {
    assert.equal(hash(leer(valor.archivo)), valor.sha256, valor.archivo);
    referenciasAnteriores++;
  }
  for (const v of Object.values(valor)) comprobarReferencias(v);
}
comprobarReferencias(anterior);

const reportes = [
  'pdf-bordes-de9b6514-ab69-416e-bd01-d4293f48ddaa.json',
  'pdf-real-5c9cfcc2-b1c5-4930-8552-2337d1b0f49b.json',
].map(nombre => {
  const archivo = evidencia + nombre;
  const r = JSON.parse(leer(archivo));
  assert.equal(r.entorno, 'avancecorp-f4-bank');
  assert(r.pruebas.every(p => p.conforme === true));
  return { ...referencia(archivo), grupos: r.pruebas.length,
    contratos: r.contratos, terminadoEn: r.terminadoEn };
});
assert.deepEqual(reportes.map(r => [r.grupos, r.contratos]), [[10, 8], [12, 10]]);

const candidataRuta = 'CRM-Avance-Corp/supabase/migrations/20260907191832_crm_f4_inversiones_base_y_escritores.sql';
assert.equal(hash(leer(candidataRuta)), anterior.candidata.sha256);
const banderasFinales = JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
assert.equal(banderasFinales.inversiones_escritura, false);
assert.equal(banderasFinales.ficha_360_neutral, false);
assert.equal(banderasFinales.resolver_en_puertas, true);

const generador = 'CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/';
const archivosServidos = ['index.ts', 'handler.ts', 'storage.ts', 'renderer.ts',
  'template-v2.ts', 'assets-v2.ts', 'pdfmake-0.2.20-pdfprinter.js',
  'vfs-fonts-0.2.20.js', 'deno.json'].map(nombre => {
  const fuente = generador + nombre;
  const banco = '/private/tmp/avancecorp-f4-bank/supabase/functions/crm-contrato-pdf-v2/' + nombre;
  assert.equal(hash(readFileSync(banco)), hash(leer(fuente)), nombre);
  return { ...referencia(fuente), copiaServidaIdentica: true };
});
const documentoSinCambios = anterior.pdf.documentoSinCambios.map(r => {
  const bytes = leer(r.archivo);
  const head = execFileSync('git', ['show', `HEAD:${r.archivo}`], { cwd: root, maxBuffer: 32 * 1024 * 1024 });
  assert.equal(hash(bytes), r.sha256, r.archivo);
  assert.equal(hash(bytes), hash(head), r.archivo);
  return { ...referencia(r.archivo), igualAHead: true };
});
const codigo = [
  ...['index.ts', 'handler.ts', 'handler.test.ts', 'storage.ts', 'storage.test.ts', 'deno.json'].map(n => generador + n),
  ...['banco-local.mjs', 'pdf-fixture.mjs', 'preparar-pdf-local.mjs', 'probar-pdf-bordes.mjs',
    'probar-pdf-real.mjs', 'capturar-pdf-bordes-local.mjs'].map(n => 'CRM-Avance-Corp/supabase/scripts/f4/' + n),
].map(archivar);
const documentos = [
  'PLAN-MAESTRO-MULTIEMPRESA.html',
  'BASE DE CONOCIMINETO/AVANCECORP/Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01).md',
  'BASE DE CONOCIMINETO/AVANCECORP/F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07).md',
  'BASE DE CONOCIMINETO/AVANCECORP/F4 multiempresa - construccion y pruebas parciales (2026-09-07).md',
  'BASE DE CONOCIMINETO/AVANCECORP/F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07).md',
  'BASE DE CONOCIMINETO/AVANCECORP/RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07).md',
  'CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md',
  'CRM-Avance-Corp/supabase/scripts/f4/README.md',
  evidencia + 'auditoria-claude-2026-09-07/evaluacion-codex.md',
].map(archivar);

const checkpoint = {
  entorno, capturadoEn: new Date().toISOString(),
  estado: 'avance-parcial-G4-abierto', objetivo: 'activo; no completado',
  candidata: archivar(candidataRuta), funciones: 34, funcionesNuevas: 17,
  checkpointAnterior: referencia(anteriorRuta), referenciasAnterioresComprobadas: referenciasAnteriores,
  pdf: {
    bordes: reportes[0], regresion: reportes[1], esperaLeaseSegundos: 120,
    plazoStorageMs: 20_000, rangoCortesConHandlerMs: [20195, 20269],
    subidaTardia: { tokenVencidoStatus: 409, colisionStatus: 503, colisionMs: 370, intentoFinal: 3 },
    pruebasUnitarias: { handler: 31, storage: 11, total: 42, estado: 'PASS',
      fuente: 'Salida de deno test observada por Codex en esta continuación (sesión 5690); este capturador no vuelve a ejecutarlas.' },
    validacionEstatica: { entrypointDenoCheck: 'PASS', formatoCincoArchivos: 'PASS',
      fuente: 'Salidas de deno check del entrypoint y deno fmt --check observadas por Codex en esta continuación.' },
    revisionVisual: { nuevaRevision: false, anterior: anterior.pdf.revisionVisual,
      limite: 'La revisión de 14 páginas corresponde a los dos archivos del bloque anterior; no se extrapola a cada PDF posterior.' },
    documentoSinCambios, archivosServidos,
  },
  codigo, documentos, banderasFinales,
  servidorTemporalFunciones: 'Detenido por SIGINT; sesión 52304 terminó con código 0.',
  produccionModificada: false,
  auditoria: { nuevaConsulta: false,
    alcance: 'Claude revisó la versión anterior conservada; Codex implementó y comprobó estas correcciones posteriores.' },
  limites: [
    'El timeout cubre Storage; no es un plazo global para Auth, RPC o render.',
    'Se alteran respuestas para simular incompatibilidad; no se cambian estados, versión ni snapshot contractual en SQL.',
    'Validar tamaño antes de la huella evita una copia adicional; el SDK aún materializa el cuerpo descargado.',
    'No hay incorporación PDF de cotitulares aprobada ni aplicada: requiere texto, ubicación y aprobación previa de Miguel.',
    'Históricos F2, cotitularidad neutral, roles dinámicos, multirrol, bajas, sin responsable y lectores heredados pendientes.',
    'Renovaciones, comisión, demos, anulaciones y carrera de sello mensual pendientes.',
    'Términos/correcciones S8/S9, inventario, reconstrucción y reversa completas pendientes.',
    'Los jobs de estos dos ensayos terminan sellados; no se afirma que todos los jobs históricos del banco estén terminados.',
  ],
};
const destino = resolve(root, evidencia, '2026-09-07-continuacion-pdf-bordes.json');
writeFileSync(destino, JSON.stringify(checkpoint, null, 2) + '\n', { flag: 'wx' });
console.log('Checkpoint PDF: 22 grupos, 18 contratos, 42 pruebas; contenido intacto, escritor apagado y G4 abierto.');
