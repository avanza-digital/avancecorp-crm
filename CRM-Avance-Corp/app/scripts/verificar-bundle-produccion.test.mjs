import assert from 'node:assert/strict'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import test from 'node:test'

const verificador = fileURLToPath(new URL('./verificar-bundle-produccion.mjs', import.meta.url))

// Un bundle que cumple TODOS los contratos del gate. Se parte de aquí y cada
// prueba quita una pieza: así un contrato nuevo no deja verde una prueba que
// solo miraba otro (esta suite llevaba tiempo en rojo por el gate de la Ficha
// 360, y no la corría ningún script).
const JS_COMPLETO = [
  'console.log("bundle productivo")',
  'const ficha = ["Inversiones y contratos", "Historial de gestiones", "Capital vigente"]',
].join('\n')
const CSS_CON_FOCO = [
  '@media (forced-colors:active){:focus-visible{outline:3px solid canvastext!important}}',
  '[class*=focus-visible\\:outline-none]:focus-visible{outline:2px solid var(--ring)}',
].join('')
const BUNDLE_COMPLETO = { 'assets/index.js': JS_COMPLETO, 'assets/index.css': CSS_CON_FOCO }

async function ejecutarConBundle(entradas) {
  const temporal = await mkdtemp(resolve(tmpdir(), 'avance-bundle-'))
  const dist = resolve(temporal, 'dist')
  try {
    await mkdir(dist)
    for (const [ruta, contenido] of Object.entries(entradas)) {
      const destino = resolve(dist, ruta)
      await mkdir(dirname(destino), { recursive: true })
      await writeFile(destino, contenido)
    }
    return spawnSync(process.execPath, [verificador], {
      cwd: temporal,
      encoding: 'utf8',
    })
  } finally {
    await rm(temporal, { recursive: true, force: true })
  }
}

test('acepta un bundle sin fixtures contractuales de demo', async () => {
  const resultado = await ejecutarConBundle(BUNDLE_COMPLETO)

  assert.equal(resultado.status, 0, resultado.stderr)
  assert.match(resultado.stdout, /BUNDLE_PRODUCCION_SIN_PDFMAKE_NI_FIXTURES_DEMO/)
})

test('rechaza un bundle que se publicaria sin indicador de foco', async (t) => {
  // Un mutante por cada mitad de la defensa: si una sola de las dos reglas de
  // `index.css` se pierde en el build —ya pasó una vez, por un `*/` dentro de
  // un comentario— el gate tiene que caerse. En `npm run dev` el navegador se
  // recupera solo, así que este es el único sitio donde se nota.
  const mitades = {
    'sin la regla de alto contraste': CSS_CON_FOCO.split('@media')[1].length > 0
      ? CSS_CON_FOCO.slice(CSS_CON_FOCO.indexOf('[class*='))
      : '',
    'sin el outline de modo normal': CSS_CON_FOCO.slice(0, CSS_CON_FOCO.indexOf('[class*=')),
    'sin CSS ninguno': '',
  }
  for (const [caso, css] of Object.entries(mitades)) {
    await t.test(caso, async () => {
      const resultado = await ejecutarConBundle({ 'assets/index.js': JS_COMPLETO, 'assets/index.css': css })
      assert.notEqual(resultado.status, 0)
      assert.match(resultado.stderr, /sin indicador de foco accesible/)
    })
  }
})

test('rechaza firma-kirk en cualquier segmento, sufijo o combinación de mayúsculas', async (t) => {
  const variantes = [
    'contrato/firma-kirk.png',
    'contrato/firma-kirk 2.png',
    'assets/FIRMA-KIRK-backup.svg',
    'assets/firma-kirk/copia.png',
  ]

  for (const ruta of variantes) {
    await t.test(ruta, async () => {
      const resultado = await ejecutarConBundle({ ...BUNDLE_COMPLETO, [ruta]: 'fixture' })
      assert.notEqual(resultado.status, 0)
      assert.match(resultado.stderr, /firma-kirk/i)
    })
  }
})

test('rechaza también una referencia renombrada dentro del código emitido', async () => {
  const resultado = await ejecutarConBundle({
    ...BUNDLE_COMPLETO,
    'assets/otro.js': 'const firma = "/contrato/FIRMA-KIRK-alternativa.webp"',
  })

  assert.notEqual(resultado.status, 0)
  assert.match(resultado.stderr, /firma-kirk/i)
})
