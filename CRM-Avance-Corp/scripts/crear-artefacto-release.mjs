import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { loadEnvFile } from 'node:process'
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const APP = path.join(RAIZ, 'app')
const DIST = path.join(APP, 'dist')
const MIGRACIONES = path.join(RAIZ, 'supabase', 'migrations')
const SUPABASE_PRODUCCION = 'https://dctqcbznekcyxhjujuci.supabase.co'

function sha256Archivo(ruta) {
  return createHash('sha256').update(readFileSync(ruta)).digest('hex')
}

function archivosRecursivos(raiz, actual = raiz) {
  return readdirSync(actual, { withFileTypes: true })
    .flatMap((entrada) => {
      const absoluta = path.join(actual, entrada.name)
      return entrada.isDirectory() ? archivosRecursivos(raiz, absoluta) : [absoluta]
    })
    .sort((a, b) => a.localeCompare(b))
}

function ejecutar(programa, argumentos, opciones = {}) {
  return execFileSync(programa, argumentos, {
    cwd: RAIZ,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...opciones,
  }).trim()
}

function valorArgumento(argumentos, nombre) {
  const indice = argumentos.indexOf(nombre)
  if (indice === -1) return null
  const valor = argumentos[indice + 1]
  if (!valor || valor.startsWith('--')) throw new Error(`Falta valor para ${nombre}`)
  return valor
}

function verificarConfiguracionProduccion() {
  const rutaEnv = path.join(APP, '.env')
  if ((!process.env.VITE_SUPABASE_URL || !process.env.VITE_SUPABASE_ANON_KEY)
      && existsSync(rutaEnv)) {
    loadEnvFile(rutaEnv)
  }

  const url = process.env.VITE_SUPABASE_URL?.trim()
  const clave = process.env.VITE_SUPABASE_ANON_KEY?.trim()
  if (url !== SUPABASE_PRODUCCION) {
    throw new Error(`El release exige VITE_SUPABASE_URL=${SUPABASE_PRODUCCION}`)
  }
  if (!clave || clave.length < 20 || /\s|^sb_secret_|service[_-]?role/i.test(clave)) {
    throw new Error('Falta una VITE_SUPABASE_ANON_KEY pública válida para producción')
  }

  let contieneUrl = false
  let contieneClave = false
  for (const archivo of archivosRecursivos(DIST).filter((ruta) => ruta.endsWith('.js'))) {
    const contenido = readFileSync(archivo, 'utf8')
    contieneUrl ||= contenido.includes(url)
    contieneClave ||= contenido.includes(clave)
    if (contieneUrl && contieneClave) break
  }
  if (!contieneUrl || !contieneClave) {
    throw new Error(
      'El bundle no contiene la configuración pública de Supabase; reconstruye con las variables de producción',
    )
  }
}

function verificar(manifiestoEntrada) {
  if (!manifiestoEntrada) {
    throw new Error('Uso: npm run release:crm:verify -- <ruta.manifest.json>')
  }
  const rutaManifiesto = path.resolve(manifiestoEntrada)
  const manifiesto = JSON.parse(readFileSync(rutaManifiesto, 'utf8'))
  const carpeta = path.dirname(rutaManifiesto)
  const rutaZip = path.resolve(carpeta, manifiesto?.archivo?.nombre ?? '')
  if (path.dirname(rutaZip) !== carpeta) throw new Error('Ruta de ZIP insegura en el manifiesto')
  if (!existsSync(rutaZip)) throw new Error(`No existe ${rutaZip}`)

  const hash = sha256Archivo(rutaZip)
  if (hash !== manifiesto.archivo.sha256) {
    throw new Error(`SHA-256 distinto: esperado ${manifiesto.archivo.sha256}, obtenido ${hash}`)
  }
  if (statSync(rutaZip).size !== manifiesto.archivo.bytes) {
    throw new Error('El tamaño del ZIP no coincide con el manifiesto')
  }

  const entradas = ejecutar('unzip', ['-Z1', rutaZip]).split('\n').filter(Boolean)
  for (const requerida of ['index.html', '.htaccess']) {
    if (!entradas.includes(requerida)) throw new Error(`El ZIP no contiene ${requerida} en la raíz`)
  }
  if (entradas.some((entrada) => /(^|\/)(\.env|node_modules|\.git|\.vite)(\/|$)/.test(entrada))) {
    throw new Error('El ZIP contiene una ruta interna o sensible')
  }

  process.stdout.write(`ARTEFACTO_OK ${manifiesto.release_id} ${hash}\n`)
}

function crear(argumentos) {
  for (const requerida of ['index.html', '.htaccess']) {
    if (!existsSync(path.join(DIST, requerida))) {
      throw new Error(`Falta app/dist/${requerida}; ejecuta el build antes de empaquetar`)
    }
  }
  verificarConfiguracionProduccion()

  const commit = ejecutar('git', ['rev-parse', '--verify', 'HEAD'])
  const cambios = ejecutar('git', ['status', '--porcelain', '--untracked-files=normal'])
  const permiteSucio = argumentos.includes('--allow-dirty')
  if (cambios && !permiteSucio) {
    throw new Error('El worktree tiene cambios. Confirma el release en un commit o usa --allow-dirty de forma explícita.')
  }

  const creadoEn = new Date().toISOString()
  const sello = creadoEn.replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z')
  const releaseId = `crm-${sello}-${commit.slice(0, 12)}`
  const salida = path.resolve(valorArgumento(argumentos, '--output') ?? path.join(RAIZ, 'releases'))
  mkdirSync(salida, { recursive: true })

  const nombreZip = `${releaseId}.zip`
  const rutaZip = path.join(salida, nombreZip)
  const rutaManifiesto = path.join(salida, `${releaseId}.manifest.json`)
  if (existsSync(rutaZip) || existsSync(rutaManifiesto)) {
    throw new Error(`El release ${releaseId} ya existe; no se sobrescribe`)
  }

  // dist/.vite/ (license.md: inventario de dependencias con versiones exactas)
  // NUNCA se publica — es justo lo que el bloqueo de package(-lock).json en el
  // .htaccess intenta negar. Queda fuera del manifiesto, del ZIP y lo veta verify.
  const payload = archivosRecursivos(DIST)
    .filter((absoluta) => !path.relative(DIST, absoluta).split(path.sep).includes('.vite'))
    .map((absoluta) => ({
      ruta: path.relative(DIST, absoluta).split(path.sep).join('/'),
      bytes: statSync(absoluta).size,
      sha256: sha256Archivo(absoluta),
    }))
  const migraciones = readdirSync(MIGRACIONES)
    .filter((nombre) => nombre.endsWith('.sql'))
    .sort()

  ejecutar('zip', ['-q', '-r', '-X', rutaZip, '.', '-x', '.vite/*', '-x', './.vite/*', '-x', '.vite/'], { cwd: DIST })

  const manifiesto = {
    schema_version: 1,
    release_id: releaseId,
    creado_en: creadoEn,
    destino: 'crm.miavance.com',
    fuente: {
      commit,
      worktree_sucio: Boolean(cambios),
      cambios: cambios ? cambios.split('\n') : [],
    },
    build: {
      comando: 'npm --prefix app run build',
      archivos: payload,
      cantidad_archivos: payload.length,
    },
    base_datos: {
      ultima_migracion: migraciones.at(-1) ?? null,
      migraciones,
    },
    archivo: {
      nombre: nombreZip,
      bytes: statSync(rutaZip).size,
      sha256: sha256Archivo(rutaZip),
    },
    rollback: {
      conservar_release_anterior: true,
      nota: 'El ZIP y manifiesto anteriores deben permanecer fuera del web root.',
    },
  }

  writeFileSync(rutaManifiesto, `${JSON.stringify(manifiesto, null, 2)}\n`, { flag: 'wx' })
  verificar(rutaManifiesto)
  process.stdout.write(`${rutaZip}\n${rutaManifiesto}\n`)
}

const [modo = 'create', ...argumentos] = process.argv.slice(2)
if (modo === 'verify') verificar(argumentos[0])
else if (modo === 'create') crear(argumentos)
else throw new Error(`Modo desconocido: ${modo}`)
