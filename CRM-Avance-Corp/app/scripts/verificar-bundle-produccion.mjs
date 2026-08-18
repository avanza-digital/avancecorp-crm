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
for (const ruta of await archivos(raiz)) {
  const contenido = (await readFile(ruta)).toString('utf8')
  const contenidoNormalizado = contenido.toLowerCase()
  for (const prohibido of prohibidos) {
    const fragmento = prohibido.toLowerCase()
    if (ruta.toLowerCase().includes(fragmento) || contenidoNormalizado.includes(fragmento)) {
      coincidencias.push(`${ruta}: ${prohibido}`)
    }
  }
}

if (coincidencias.length > 0) {
  throw new Error(`El bundle productivo contiene codigo o fixtures exclusivos de demo:\n${coincidencias.join('\n')}`)
}

console.log('BUNDLE_PRODUCCION_SIN_PDFMAKE_NI_FIXTURES_DEMO')
