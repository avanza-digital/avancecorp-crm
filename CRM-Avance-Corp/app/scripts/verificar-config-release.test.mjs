import assert from 'node:assert/strict'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import test from 'node:test'

const verificador = fileURLToPath(new URL('./verificar-config-release.mjs', import.meta.url))
const url = 'https://dctqcbznekcyxhjujuci.supabase.co'
const key = 'sb_publishable_prueba_release_1234567890'

async function ejecutar({ env = '', bundle = '' }) {
  const temporal = await mkdtemp(resolve(tmpdir(), 'avance-config-release-'))
  const envDir = resolve(temporal, 'env')
  const dist = resolve(temporal, 'dist')
  try {
    await mkdir(envDir)
    await mkdir(resolve(dist, 'assets'), { recursive: true })
    await writeFile(resolve(envDir, '.env.production'), env)
    await writeFile(resolve(dist, 'assets', 'index.js'), bundle)
    const entorno = { ...process.env }
    delete entorno.VITE_SUPABASE_URL
    delete entorno.VITE_SUPABASE_ANON_KEY
    return spawnSync(
      process.execPath,
      [verificador, '--env-dir', envDir, '--dist-dir', dist],
      { encoding: 'utf8', env: entorno },
    )
  } finally {
    await rm(temporal, { recursive: true, force: true })
  }
}

test('acepta solo la configuración pública productiva presente en el bundle', async () => {
  const resultado = await ejecutar({
    env: `VITE_SUPABASE_URL=${url}\nVITE_SUPABASE_ANON_KEY=${key}\n`,
    bundle: `const url=${JSON.stringify(url)};const key=${JSON.stringify(key)}`,
  })

  assert.equal(resultado.status, 0, resultado.stderr)
  assert.match(resultado.stdout, /CONFIG_RELEASE_SUPABASE_OK dctqcbznekcyxhjujuci\.supabase\.co/)
  assert.doesNotMatch(resultado.stdout, new RegExp(key))
})

test('rechaza un release sin variables de Supabase', async () => {
  const resultado = await ejecutar({})

  assert.notEqual(resultado.status, 0)
  assert.match(resultado.stderr, /Falta VITE_SUPABASE_URL/)
})

test('rechaza una llave privilegiada', async () => {
  const resultado = await ejecutar({
    env: `VITE_SUPABASE_URL=${url}\nVITE_SUPABASE_ANON_KEY=sb_secret_no_publicar_1234567890\n`,
  })

  assert.notEqual(resultado.status, 0)
  assert.match(resultado.stderr, /llave privilegiada/)
})

test('rechaza un build que no incorporó la configuración', async () => {
  const resultado = await ejecutar({
    env: `VITE_SUPABASE_URL=${url}\nVITE_SUPABASE_ANON_KEY=${key}\n`,
    bundle: 'console.log("sin configuración")',
  })

  assert.notEqual(resultado.status, 0)
  assert.match(resultado.stderr, /bundle no contiene la configuración pública/)
})
