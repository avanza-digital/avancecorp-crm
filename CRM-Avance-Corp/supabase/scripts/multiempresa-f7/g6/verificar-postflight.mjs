// Comparación reproducible de custodia. Ninguna conexión ni escritura en la base.
import assert from 'node:assert/strict';
import { chmod, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export function verificarPostflight(captura, post) {
  const antes = captura.custodia;
  assert.equal(antes.solo_lectura, 'on');
  assert.equal(post.solo_lectura, 'on');
  assert.ok(Date.parse(post.capturado_en) >= Date.parse(captura.capturado_en));
  for (const campo of ['rol', 'rol_sesion', 'propietario_f7', 'search_path',
    'banderas', 'funciones', 'migraciones', 'fotos_selladas']) {
    assert.deepEqual(post[campo], antes[campo], campo);
  }
  return { estado: 'CUSTODIA_PASS', capturadoEn: captura.capturado_en,
    comprobadoEn: post.capturado_en, funciones: Object.keys(post.funciones).length,
    migraciones: post.migraciones, fotos: post.fotos_selladas.length,
    alcance: 'Coincidencia de las huellas seleccionadas y banderas entre dos lecturas; no monitor global de escrituras.' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.equal(process.argv.length, 5, 'Uso: verificar-postflight.mjs captura.json postflight.json resultado.json');
  let resultado;
  const huellas = {};
  try {
    const lectura = await readFile(process.argv[2], 'utf8');
    const post = await readFile(process.argv[3], 'utf8');
    huellas.capturaSha256 = createHash('sha256').update(lectura).digest('hex');
    huellas.postflightSha256 = createHash('sha256').update(post).digest('hex');
    resultado = verificarPostflight(JSON.parse(lectura), JSON.parse(post));
  } catch (error) {
    resultado = { estado: 'FAIL', error: error.code ?? error.name };
  }
  Object.assign(resultado, huellas);
  await writeFile(process.argv[4], JSON.stringify(resultado, null, 2) + '\n', { mode: 0o600 });
  await chmod(process.argv[4], 0o600);
  console.log(JSON.stringify(resultado, null, 2));
  if (resultado.estado !== 'CUSTODIA_PASS') process.exitCode = 1;
}
