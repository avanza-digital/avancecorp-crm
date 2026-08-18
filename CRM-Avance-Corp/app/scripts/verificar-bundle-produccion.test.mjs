import assert from 'node:assert/strict'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import test from 'node:test'

const verificador = fileURLToPath(new URL('./verificar-bundle-produccion.mjs', import.meta.url))

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
  const resultado = await ejecutarConBundle({
    'assets/index.js': 'console.log("bundle productivo")',
  })

  assert.equal(resultado.status, 0, resultado.stderr)
  assert.match(resultado.stdout, /BUNDLE_PRODUCCION_SIN_PDFMAKE_NI_FIXTURES_DEMO/)
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
      const resultado = await ejecutarConBundle({ [ruta]: 'fixture' })
      assert.notEqual(resultado.status, 0)
      assert.match(resultado.stderr, /firma-kirk/i)
    })
  }
})

test('rechaza también una referencia renombrada dentro del código emitido', async () => {
  const resultado = await ejecutarConBundle({
    'assets/index.js': 'const firma = "/contrato/FIRMA-KIRK-alternativa.webp"',
  })

  assert.notEqual(resultado.status, 0)
  assert.match(resultado.stderr, /firma-kirk/i)
})
