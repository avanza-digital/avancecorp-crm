// El lector del archivo de una base (F5): CSV propio (comillas, «;», BOM, Windows-1252) y .xlsx con `read-excel-file`
// (cargado con import() solo al usarlo). Los .xlsx se FABRICAN aquí (un ZIP mínimo sin compresión con la hoja en XML):
// así la prueba lee un Excel de verdad, también uno de 5000 filas, sin guardar binarios en el repositorio.
import { describe, expect, it } from 'vitest'
import { MAX_FILAS_BASE, detectarColumnas, prepararFilas } from './bases-cargadas'
import { ErrorArchivoBase, decodificarCsv, leerArchivoBase, parsearCsv, tablaDesdeFilas, tipoDeArchivo } from './bases-cargadas-archivo'

// ── Un .xlsx mínimo (ZIP «stored» + CRC-32) ───────────────────────────────────────────────────────────────────────
const TABLA_CRC = Array.from({ length: 256 }, (_, n) => {
  let c = n
  for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  return c >>> 0
})
function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff
  for (const b of bytes) c = (TABLA_CRC[(c ^ b) & 0xff] ?? 0) ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}
function zip(archivos: Record<string, string>): Uint8Array {
  const cod = new TextEncoder()
  const partes: Uint8Array[] = []
  const central: Uint8Array[] = []
  let desplazamiento = 0
  for (const [nombre, texto] of Object.entries(archivos)) {
    const datos = cod.encode(texto)
    const n = cod.encode(nombre)
    const crc = crc32(datos)
    const local = new DataView(new ArrayBuffer(30))
    local.setUint32(0, 0x04034b50, true); local.setUint16(4, 20, true); local.setUint32(14, crc, true)
    local.setUint32(18, datos.length, true); local.setUint32(22, datos.length, true); local.setUint16(26, n.length, true)
    const dir = new DataView(new ArrayBuffer(46))
    dir.setUint32(0, 0x02014b50, true); dir.setUint16(4, 20, true); dir.setUint16(6, 20, true); dir.setUint32(16, crc, true)
    dir.setUint32(20, datos.length, true); dir.setUint32(24, datos.length, true); dir.setUint16(28, n.length, true); dir.setUint32(42, desplazamiento, true)
    partes.push(new Uint8Array(local.buffer), n, datos)
    central.push(new Uint8Array(dir.buffer), n)
    desplazamiento += 30 + n.length + datos.length
  }
  const tamCentral = central.reduce((s, p) => s + p.length, 0)
  const fin = new DataView(new ArrayBuffer(22))
  fin.setUint32(0, 0x06054b50, true); fin.setUint16(8, Object.keys(archivos).length, true); fin.setUint16(10, Object.keys(archivos).length, true)
  fin.setUint32(12, tamCentral, true); fin.setUint32(16, desplazamiento, true)
  const todo = [...partes, ...central, new Uint8Array(fin.buffer)]
  const salida = new Uint8Array(todo.reduce((s, p) => s + p.length, 0))
  let i = 0
  for (const p of todo) { salida.set(p, i); i += p.length }
  return salida
}
const esc = (t: string) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;')
function xlsx(filas: (string | number | null)[][]): Uint8Array {
  const letra = (i: number) => String.fromCharCode(65 + i)
  const hoja = filas.map((fila, r) => `<row r="${r + 1}">${fila.map((v, c) => v === null ? ''
    : typeof v === 'number' ? `<c r="${letra(c)}${r + 1}"><v>${v}</v></c>`
      : `<c r="${letra(c)}${r + 1}" t="inlineStr"><is><t>${esc(v)}</t></is></c>`).join('')}</row>`).join('')
  return zip({
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Contactos" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml': `<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${hoja}</sheetData></worksheet>`,
  })
}
const archivo = (contenido: BlobPart, nombre: string) => new File([contenido], nombre)

describe('CSV', () => {
  it('comillas, comillas escapadas, saltos de línea dentro de comillas, CRLF y BOM; separador «;» detectado', () => {
    const texto = '\uFEFFNombre;Teléfono;Comentario\r\n"QUISPE; ROSA";987654321;"dijo ""llámame""\nmañana"\r\nLUIS;987000111;\r\n'
    expect(parsearCsv(texto)).toEqual([
      ['Nombre', 'Teléfono', 'Comentario'],
      ['QUISPE; ROSA', '987654321', 'dijo "llámame"\nmañana'],
      ['LUIS', '987000111', ''],
    ])
    expect(parsearCsv('a,b\n1,2')).toEqual([['a', 'b'], ['1', '2']])
    expect(parsearCsv('a\tb\n1\t2\n')).toEqual([['a', 'b'], ['1', '2']])
  })

  it('el separador sale de la primera línea NO vacía («;» o tabulador tras líneas en blanco)', () => {
    expect(parsearCsv('\n\nNombre;Celular\nROSA;987654321\n')).toEqual([[''], [''], ['Nombre', 'Celular'], ['ROSA', '987654321']])
    expect(parsearCsv('\r\n  \r\nNombre\tCelular\r\nROSA\t987654321')).toEqual([[''], ['  '], ['Nombre', 'Celular'], ['ROSA', '987654321']])
    expect(tablaDesdeFilas(parsearCsv('\n\nNombre;Celular\nROSA;987654321\n')).encabezados).toEqual(['Nombre', 'Celular'])
  })

  it('comillas sin cerrar: se rechaza el archivo con un mensaje claro (no se «come» el resto en silencio)', () => {
    expect(() => parsearCsv('Nombre;Celular\nROSA;987654321\n"LUIS;987000111\nANA;987000222\n')).toThrow(ErrorArchivoBase)
    expect(() => parsearCsv('Nombre;Celular\nROSA;987654321\n"LUIS;987000111\nANA;987000222\n')).toThrow(/comillas sin cerrar \(desde la fila 3\)/)
  })

  it('UTF-8 si lo es; si no, Windows-1252 (el CSV que guarda Excel en Windows)', () => {
    expect(decodificarCsv(new TextEncoder().encode('NÚÑEZ').buffer as ArrayBuffer)).toBe('NÚÑEZ')
    expect(decodificarCsv(new Uint8Array([0x4e, 0xda, 0xd1, 0x45, 0x5a]).buffer)).toBe('NÚÑEZ')
  })
})

describe('la tabla del archivo', () => {
  it('el encabezado es la primera fila con algo; los datos llevan su número de fila de Excel; las vacías se saltan', () => {
    const t = tablaDesdeFilas([[null, ''], ['Nombre', 'Celular'], ['ROSA', '987654321'], [null, null], ['LUIS', '987000111']])
    expect(t.encabezados).toEqual(['Nombre', 'Celular'])
    expect(t.filas.map((f) => f.numero)).toEqual([3, 5])
  })
  it('vacío, solo encabezado o más de 5000 filas: se rechaza con un mensaje claro (nunca se recorta en silencio)', () => {
    expect(() => tablaDesdeFilas([[null]])).toThrow(ErrorArchivoBase)
    expect(() => tablaDesdeFilas([['Nombre']])).toThrow(/solo tiene el encabezado/)
    const muchas = [['Nombre', 'Celular'], ...Array.from({ length: MAX_FILAS_BASE + 1 }, (_, i) => [`C ${i}`, '987654321'])]
    expect(() => tablaDesdeFilas(muchas)).toThrow(/5[.,\s]?001 filas y una base admite hasta 5[.,\s]?000/)
    expect(tablaDesdeFilas(muchas.slice(0, MAX_FILAS_BASE + 1)).filas).toHaveLength(MAX_FILAS_BASE)
  })
  it('solo .xlsx y .csv', () => {
    expect(tipoDeArchivo('Feria.XLSX')).toBe('xlsx')
    expect(tipoDeArchivo('feria.csv')).toBe('csv')
    expect(tipoDeArchivo('feria.xls')).toBeNull()
  })
})

describe('leerArchivoBase', () => {
  it('un .csv: se lee, se reconocen las columnas y se valida', async () => {
    const t = await leerArchivoBase(archivo('Nombres y apellidos;Celular;DNI\nROSA QUISPE;987 654 321;04587123\nSIN TEL;;\n', 'feria.csv'))
    const p = prepararFilas(t, detectarColumnas(t.encabezados))
    expect(p.filas.map((f) => [f.fila, f.telefono, f.dni, f.error])).toEqual([[2, '+51987654321', '04587123', null], [3, '', '', 'telefono_invalido']])
  })

  it('un .xlsx de verdad: textos y números (el DNI numérico recupera su cero)', async () => {
    const t = await leerArchivoBase(archivo(xlsx([['Nombre', 'Celular', 'DNI', 'Capital'], ['ROSA QUISPE', 987654321, 4587123, 30000.5], ['LUIS', '987000111', null, null]]) as BlobPart, 'Feria 2025.xlsx'))
    expect(t.encabezados).toEqual(['Nombre', 'Celular', 'DNI', 'Capital'])
    const p = prepararFilas(t, detectarColumnas(t.encabezados))
    expect(p.validas.map((f) => [f.nombre, f.telefono, f.dni, f.capital])).toEqual([['ROSA QUISPE', '+51987654321', '04587123', '30000.5'], ['LUIS', '+51987000111', '', '']])
  })

  it(`un .xlsx de ${MAX_FILAS_BASE} filas se lee entero`, async () => {
    const filas = [['Nombre', 'Celular'], ...Array.from({ length: MAX_FILAS_BASE }, (_, i) => [`CONTACTO ${i}`, 910_000_000 + i])]
    const t = await leerArchivoBase(archivo(xlsx(filas) as BlobPart, 'grande.xlsx'))
    expect(t.filas).toHaveLength(MAX_FILAS_BASE)
    expect(prepararFilas(t, detectarColumnas(t.encabezados)).validas).toHaveLength(MAX_FILAS_BASE)
  })

  it('un .xlsx roto, otra extensión o más de 10 MB: mensaje claro', async () => {
    await expect(leerArchivoBase(archivo('no es un zip', 'roto.xlsx'))).rejects.toThrow(/No se pudo leer el Excel/)
    await expect(leerArchivoBase(archivo('x', 'viejo.xls'))).rejects.toThrow(/\.xlsx o \.csv/)
    const grande = archivo('x', 'grande.csv')
    Object.defineProperty(grande, 'size', { value: 11 * 1024 * 1024 })
    await expect(leerArchivoBase(grande)).rejects.toThrow(/más de 10 MB/)
  })
})
