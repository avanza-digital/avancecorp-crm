import { readdir, readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const raiz = resolve(process.cwd(), 'dist')
const prohibidos = [
  'pdfmake',
  'vfs_fonts',
  // Fragmento, no nombre exacto: cubre copias como "firma-kirk 2.png",
  // mayúsculas y directorios que intenten conservar el fixture bajo otro sufijo.
  'firma-kirk',
  'demo-clientes',
  'demo-contrato-aep-17-v1',
  'ROSA MERCEDES AGUILAR VENTURA',
  'JAVIER ERNESTO MEZA COLLANTES',
  '2026-01-000901',
]

// Contrato de producto del release: «Ver detalle» en Mi cartera debe abrir la
// Ficha 360 completa. Este gate vive en el build para que una rama posterior no
// pueda volver a publicar silenciosamente el detalle básico anterior.
const obligatoriosFicha360 = [
  'Inversiones y contratos',
  'Historial de gestiones',
  'Capital vigente',
]

// Indicador de foco (21/09/2026). Las dos reglas de `index.css` que lo
// arreglan viven FUERA de las utilidades de Tailwind, y ya se perdieron una vez
// en el camino: un `*/` dentro del comentario cerraba el bloque antes de tiempo
// y el parser se comía la regla. En `npm run dev` el navegador se recuperaba
// solo y todo parecía correcto; en `dist` la regla no existía. Se comprueba
// aquí, sobre el CSS que de verdad se publica.
const obligatoriosFoco = [
  // El foco vuelve en alto contraste, donde el navegador borra los box-shadow.
  'forced-colors:active){:focus-visible',
  // Y en modo normal el control que apaga el outline recupera uno de 2 px.
  '[class*=focus-visible\\:outline-none]:focus-visible',
]

async function archivos(directorio) {
  const entradas = await readdir(directorio, { withFileTypes: true })
  const resultado = []
  for (const entrada of entradas) {
    const ruta = resolve(directorio, entrada.name)
    if (entrada.isDirectory()) resultado.push(...await archivos(ruta))
    else if (entrada.isFile()) resultado.push(ruta)
  }
  return resultado
}

const coincidencias = []
const encontradosFicha360 = new Set()
const encontradosFoco = new Set()
for (const ruta of await archivos(raiz)) {
  const contenido = (await readFile(ruta)).toString('utf8')
  const contenidoNormalizado = contenido.toLowerCase()
  for (const prohibido of prohibidos) {
    const fragmento = prohibido.toLowerCase()
    if (ruta.toLowerCase().includes(fragmento) || contenidoNormalizado.includes(fragmento)) {
      coincidencias.push(`${ruta}: ${prohibido}`)
    }
  }
  for (const obligatorio of obligatoriosFicha360) {
    if (contenido.includes(obligatorio)) encontradosFicha360.add(obligatorio)
  }
  for (const obligatorio of obligatoriosFoco) {
    if (contenido.includes(obligatorio)) encontradosFoco.add(obligatorio)
  }
}

if (coincidencias.length > 0) {
  throw new Error(`El bundle productivo contiene codigo o fixtures exclusivos de demo:\n${coincidencias.join('\n')}`)
}

const faltantesFicha360 = obligatoriosFicha360.filter(
  (obligatorio) => !encontradosFicha360.has(obligatorio),
)
if (faltantesFicha360.length > 0) {
  throw new Error(
    `El bundle productivo no contiene la Ficha 360 completa: faltan ${faltantesFicha360.join(', ')}`,
  )
}

const faltantesFoco = obligatoriosFoco.filter((obligatorio) => !encontradosFoco.has(obligatorio))
if (faltantesFoco.length > 0) {
  throw new Error(
    `El bundle productivo se publicaria sin indicador de foco accesible: faltan ${faltantesFoco.join(', ')}`,
  )
}

console.log('BUNDLE_PRODUCCION_SIN_PDFMAKE_NI_FIXTURES_DEMO_CON_FICHA_360_Y_CON_FOCO')
