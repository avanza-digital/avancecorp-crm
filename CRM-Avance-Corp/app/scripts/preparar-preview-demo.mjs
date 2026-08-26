import { copyFile, readFile, readdir, rm } from 'node:fs/promises'
import { relative, resolve, sep } from 'node:path'
import { pathToFileURL } from 'node:url'

const ARCHIVOS_PROHIBIDOS = [
  /(^|\/)\.htaccess$/i,
  /(^|\/)\.env(?:\.|$)/i,
  /(^|\/)package(?:-lock)?\.json$/i,
  /\.map$/i,
]

const ENDPOINTS_EXTERNOS_PROHIBIDOS = [
  {
    nombre: 'endpoint de Supabase',
    patron: /(?:https?|wss):\/\/[a-z0-9.-]+\.supabase\.(?:co|in)(?=[:/\s"'`]|$)/i,
  },
  {
    nombre: 'endpoint de ingesta de Sentry',
    patron: /https:\/\/[a-z0-9.-]*ingest\.[a-z0-9.-]*sentry\.io(?=[:/\s"'`]|$)/i,
  },
]

function rutaPortable(ruta, raiz) {
  return relative(raiz, ruta).split(sep).join('/')
}

export async function listarArchivos(directorio) {
  const entradas = await readdir(directorio, { withFileTypes: true })
  entradas.sort((a, b) => a.name.localeCompare(b.name))

  const resultado = []
  for (const entrada of entradas) {
    const ruta = resolve(directorio, entrada.name)
    if (entrada.isDirectory()) resultado.push(...await listarArchivos(ruta))
    else if (entrada.isFile()) resultado.push(ruta)
    else throw new Error(`El paquete contiene una entrada no regular: ${ruta}`)
  }
  return resultado
}

function cabeceraGlobal(configuracion, clave) {
  const regla = configuracion.headers?.find((item) => item.source === '/(.*)')
  return regla?.headers?.find((item) => item.key.toLowerCase() === clave.toLowerCase())?.value
}

function tokensDirectiva(csp, nombre) {
  const directiva = csp
    .split(';')
    .map((parte) => parte.trim())
    .find((parte) => parte === nombre || parte.startsWith(`${nombre} `))
  return directiva?.split(/\s+/).slice(1) ?? []
}

export async function verificarPaquetePreview({ directorioDist }) {
  const raiz = resolve(directorioDist)
  const rutas = await listarArchivos(raiz)
  const relativos = rutas.map((ruta) => rutaPortable(ruta, raiz))
  const problemas = []

  for (const relativo of relativos) {
    for (const patron of ARCHIVOS_PROHIBIDOS) {
      if (patron.test(relativo)) problemas.push(`${relativo}: archivo prohibido`)
    }
  }

  for (let indice = 0; indice < rutas.length; indice += 1) {
    const contenido = (await readFile(rutas[indice])).toString('utf8')
    for (const { nombre, patron } of ENDPOINTS_EXTERNOS_PROHIBIDOS) {
      if (patron.test(contenido)) problemas.push(`${relativos[indice]}: ${nombre}`)
    }
  }

  const rutaVercel = resolve(raiz, 'vercel.json')
  let configuracion
  try {
    configuracion = JSON.parse(await readFile(rutaVercel, 'utf8'))
  } catch (error) {
    problemas.push(`vercel.json: ausente o invalido (${error.message})`)
  }

  if (configuracion) {
    const csp = cabeceraGlobal(configuracion, 'Content-Security-Policy')
    if (!csp) {
      problemas.push('vercel.json: falta Content-Security-Policy global')
    } else {
      const conexiones = tokensDirectiva(csp, 'connect-src')
      if (conexiones.length !== 1 || conexiones[0] !== "'self'") {
        problemas.push(`vercel.json: connect-src debe ser exactamente 'self' (recibido: ${conexiones.join(' ') || 'ausente'})`)
      }
    }

    const robots = cabeceraGlobal(configuracion, 'X-Robots-Tag') ?? ''
    if (!/\bnoindex\b/i.test(robots) || !/\bnofollow\b/i.test(robots)) {
      problemas.push('vercel.json: X-Robots-Tag global no bloquea indexacion y seguimiento')
    }

    const reescrituraSpa = configuracion.rewrites?.some(
      (item) => item.source === '/(.*)' && item.destination === '/index.html',
    )
    if (!reescrituraSpa) problemas.push('vercel.json: falta la reescritura SPA a /index.html')
  }

  try {
    const index = await readFile(resolve(raiz, 'index.html'), 'utf8')
    if (!/<meta\s+name=["']robots["']\s+content=["'][^"']*noindex/i.test(index)) {
      problemas.push('index.html: falta meta robots noindex')
    }
  } catch (error) {
    problemas.push(`index.html: no se pudo leer (${error.message})`)
  }

  try {
    const robots = await readFile(resolve(raiz, 'robots.txt'), 'utf8')
    if (!/^\s*Disallow:\s*\/\s*$/im.test(robots)) problemas.push('robots.txt: no bloquea todo el sitio')
  } catch (error) {
    problemas.push(`robots.txt: no se pudo leer (${error.message})`)
  }

  try {
    const version = JSON.parse(await readFile(resolve(raiz, 'version.json'), 'utf8'))
    if (version.schema !== 1 || typeof version.buildId !== 'string' || version.buildId.length === 0) {
      problemas.push('version.json: identidad de build invalida')
    }
  } catch (error) {
    problemas.push(`version.json: ausente o invalido (${error.message})`)
  }

  if (problemas.length > 0) {
    throw new Error(`El paquete de preview no es publicable:\n${problemas.join('\n')}`)
  }

  const ocultos = relativos.filter((ruta) => ruta.split('/').some((parte) => parte.startsWith('.')))
  return { archivos: relativos.length, ocultos }
}

export async function prepararPaquetePreview({ directorioDist, archivoConfig }) {
  const raiz = resolve(directorioDist)
  await rm(resolve(raiz, '.htaccess'), { force: true })
  await copyFile(resolve(archivoConfig), resolve(raiz, 'vercel.json'))
  return verificarPaquetePreview({ directorioDist: raiz })
}

async function main() {
  const directorioDist = resolve(process.cwd(), 'dist')
  const soloVerificar = process.argv.includes('--verify-only')
  const resultado = soloVerificar
    ? await verificarPaquetePreview({ directorioDist })
    : await prepararPaquetePreview({
        directorioDist,
        archivoConfig: resolve(process.cwd(), 'vercel.preview.json'),
      })

  console.log(`PREVIEW_DEMO_AISLADA_OK archivos=${resultado.archivos} ocultos=${resultado.ocultos.join(',') || 'ninguno'}`)
}

const ejecutadoDirectamente = process.argv[1]
  && import.meta.url === pathToFileURL(resolve(process.argv[1])).href

if (ejecutadoDirectamente) await main()
