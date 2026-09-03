import { readdir, readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { loadEnv } from 'vite'

const PROYECTO_SUPABASE_PRODUCCION = 'dctqcbznekcyxhjujuci'

function valorArgumento(nombre) {
  const indice = process.argv.indexOf(nombre)
  if (indice === -1) return null
  const valor = process.argv[indice + 1]
  if (!valor || valor.startsWith('--')) throw new Error(`Falta valor para ${nombre}`)
  return valor
}

function rolJwt(valor) {
  if (!valor.startsWith('eyJ')) return null
  try {
    const segmento = valor.split('.')[1]
    if (!segmento) return null
    const base64 = segmento.replace(/-/g, '+').replace(/_/g, '/')
      .padEnd(Math.ceil(segmento.length / 4) * 4, '=')
    const payload = JSON.parse(Buffer.from(base64, 'base64').toString('utf8'))
    return typeof payload.role === 'string' ? payload.role : null
  } catch {
    return null
  }
}

function validarConfiguracion(env) {
  const urlOriginal = env.VITE_SUPABASE_URL?.trim()
  const key = env.VITE_SUPABASE_ANON_KEY?.trim()
  if (!urlOriginal) throw new Error('Falta VITE_SUPABASE_URL para el release productivo')
  if (!key) throw new Error('Falta VITE_SUPABASE_ANON_KEY para el release productivo')

  let url
  try {
    url = new URL(urlOriginal)
  } catch {
    throw new Error('VITE_SUPABASE_URL no es una URL válida')
  }

  const hostEsperado = `${PROYECTO_SUPABASE_PRODUCCION}.supabase.co`
  if (url.protocol !== 'https:' || url.hostname !== hostEsperado
      || url.username || url.password || url.search || url.hash
      || !['', '/'].includes(url.pathname)) {
    throw new Error(`VITE_SUPABASE_URL no apunta al proyecto productivo esperado (${hostEsperado})`)
  }

  if (/^sb_secret_/i.test(key) || /service[_-]?role/i.test(key) || rolJwt(key) === 'service_role') {
    throw new Error('VITE_SUPABASE_ANON_KEY contiene una llave privilegiada')
  }
  if (key.length < 20 || /\s/.test(key)) {
    throw new Error('VITE_SUPABASE_ANON_KEY no tiene un formato público válido')
  }

  return { url: url.origin, key }
}

async function archivosJavaScript(directorio) {
  const entradas = await readdir(directorio, { withFileTypes: true })
  const resultado = []
  for (const entrada of entradas) {
    const ruta = resolve(directorio, entrada.name)
    if (entrada.isDirectory()) resultado.push(...await archivosJavaScript(ruta))
    else if (entrada.isFile() && entrada.name.endsWith('.js')) resultado.push(ruta)
  }
  return resultado
}

async function verificarBundle(dist, configuracion) {
  let encontroUrl = false
  let encontroKey = false
  for (const ruta of await archivosJavaScript(dist)) {
    const contenido = await readFile(ruta, 'utf8')
    encontroUrl ||= contenido.includes(configuracion.url)
    encontroKey ||= contenido.includes(configuracion.key)
  }
  if (!encontroUrl || !encontroKey) {
    throw new Error(
      'El bundle no contiene la configuración pública de Supabase; se cancela el release',
    )
  }
}

const app = resolve(import.meta.dirname, '..')
const envDir = resolve(valorArgumento('--env-dir') ?? app)
const dist = resolve(valorArgumento('--dist-dir') ?? resolve(app, 'dist'))
const configuracion = validarConfiguracion(loadEnv('production', envDir, 'VITE_'))
await verificarBundle(dist, configuracion)
console.log(`CONFIG_RELEASE_SUPABASE_OK ${new URL(configuracion.url).hostname}`)
