import assert from 'node:assert/strict'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import test from 'node:test'
import { prepararPaquetePreview, verificarPaquetePreview } from './preparar-preview-demo.mjs'

async function fixture() {
  const raiz = await mkdtemp(join(tmpdir(), 'avancecorp-preview-'))
  const dist = join(raiz, 'dist')
  await mkdir(join(dist, '.vite'), { recursive: true })
  await Promise.all([
    writeFile(join(dist, '.htaccess'), 'connect-src https://servidor-real.invalid'),
    writeFile(join(dist, '.vite', 'license.md'), '# Licencias\n'),
    writeFile(join(dist, 'index.html'), '<meta name="robots" content="noindex, nofollow, noarchive">'),
    writeFile(join(dist, 'robots.txt'), 'User-agent: *\nDisallow: /\n'),
    writeFile(join(dist, 'version.json'), '{"schema":1,"buildId":"f41-preview-test"}\n'),
    writeFile(join(dist, 'app.js'), 'console.log("preview aislada")\n'),
  ])
  return { raiz, dist }
}

test('prepara el paquete, elimina .htaccess e inspecciona archivos ocultos', async () => {
  const { raiz, dist } = await fixture()
  try {
    const resultado = await prepararPaquetePreview({
      directorioDist: dist,
      archivoConfig: resolve(process.cwd(), 'vercel.preview.json'),
    })
    await assert.rejects(readFile(join(dist, '.htaccess')), /ENOENT/)
    assert.equal(JSON.parse(await readFile(join(dist, 'vercel.json'), 'utf8')).$schema, 'https://openapi.vercel.sh/vercel.json')
    assert.deepEqual(resultado.ocultos, ['.vite/license.md'])
  } finally {
    await rm(raiz, { recursive: true, force: true })
  }
})

test('rechaza cualquier endpoint concreto de Supabase dentro del paquete', async () => {
  const { raiz, dist } = await fixture()
  try {
    await prepararPaquetePreview({
      directorioDist: dist,
      archivoConfig: resolve(process.cwd(), 'vercel.preview.json'),
    })
    await writeFile(join(dist, 'app.js'), 'fetch("https://proyecto.supabase.co/rest/v1/clientes")\n')
    await assert.rejects(
      verificarPaquetePreview({ directorioDist: dist }),
      /app\.js: endpoint de Supabase/,
    )
  } finally {
    await rm(raiz, { recursive: true, force: true })
  }
})

test("rechaza una CSP que amplie connect-src mas alla de 'self'", async () => {
  const { raiz, dist } = await fixture()
  try {
    await prepararPaquetePreview({
      directorioDist: dist,
      archivoConfig: resolve(process.cwd(), 'vercel.preview.json'),
    })
    const rutaConfig = join(dist, 'vercel.json')
    const config = JSON.parse(await readFile(rutaConfig, 'utf8'))
    const csp = config.headers[0].headers.find((item) => item.key === 'Content-Security-Policy')
    csp.value = csp.value.replace("connect-src 'self'", "connect-src 'self' https://example.com")
    await writeFile(rutaConfig, `${JSON.stringify(config)}\n`)
    await assert.rejects(
      verificarPaquetePreview({ directorioDist: dist }),
      /connect-src debe ser exactamente 'self'/,
    )
  } finally {
    await rm(raiz, { recursive: true, force: true })
  }
})
