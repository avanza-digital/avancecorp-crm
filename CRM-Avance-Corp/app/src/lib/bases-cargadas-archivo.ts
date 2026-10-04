// Lector del archivo de una base cargada (F5): .xlsx o .csv, SOLO en el navegador de quien carga (el servidor recibe las
// filas ya partidas en lotes). El lector de Excel (`read-excel-file`) se descarga SOLO al elegir un .xlsx (`import()`,
// molde de `contrato-pdf.ts`): nadie más paga su peso. Se usa su variante `universal` (sin Web Workers): con el tope de
// 5000 filas lee en una fracción de segundo, funciona igual en el navegador y en las pruebas, y no depende de crear
// workers desde `blob:` bajo la política de seguridad del CRM. El CSV lo lee un lector propio (unas líneas: comillas,
// separador «,», «;» o tabulador, BOM y archivos guardados por Excel en Windows-1252).
import { MAX_FILAS_BASE, type Celda, type TablaArchivo } from './bases-cargadas'

export class ErrorArchivoBase extends Error {
  constructor(mensaje: string) {
    super(mensaje)
    this.name = 'ErrorArchivoBase'
  }
}

/** Tope del archivo en disco: 5000 filas de contacto caben de sobra en 10 MB (un archivo mayor es otra cosa). */
export const MAX_BYTES_ARCHIVO = 10 * 1024 * 1024

export type TipoArchivo = 'xlsx' | 'csv'

export function tipoDeArchivo(nombre: string): TipoArchivo | null {
  const extension = nombre.toLowerCase().split('.').pop()
  return extension === 'xlsx' ? 'xlsx' : extension === 'csv' ? 'csv' : null
}

// ── CSV ────────────────────────────────────────────────────────────────────────────────────────────────────────────
/** El separador de la primera línea (fuera de comillas): el que más aparece entre «,», «;» y tabulador. */
function separadorDe(texto: string): string {
  const conteo = new Map<string, number>([[',', 0], [';', 0], ['\t', 0]])
  let entreComillas = false
  for (const c of texto) {
    if (c === '"') entreComillas = !entreComillas
    else if (!entreComillas && (c === '\n' || c === '\r')) break
    else if (!entreComillas && conteo.has(c)) conteo.set(c, (conteo.get(c) ?? 0) + 1)
  }
  let mejor = ','
  for (const [sep, n] of conteo) if (n > (conteo.get(mejor) ?? 0)) mejor = sep
  return mejor
}

/** Registros de un CSV (RFC 4180: comillas dobles, comillas escapadas «""», saltos de línea dentro de comillas). */
export function parsearCsv(texto: string): string[][] {
  const limpio = texto.replace(/^﻿/, '')
  const sep = separadorDe(limpio)
  const registros: string[][] = []
  let registro: string[] = []
  let campo = ''
  let entreComillas = false
  for (let i = 0; i < limpio.length; i += 1) {
    const c = limpio[i]
    if (entreComillas) {
      if (c === '"' && limpio[i + 1] === '"') { campo += '"'; i += 1 }
      else if (c === '"') entreComillas = false
      else campo += c
      continue
    }
    if (c === '"') entreComillas = true
    else if (c === sep) { registro.push(campo); campo = '' }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && limpio[i + 1] === '\n') i += 1
      registro.push(campo); registros.push(registro); registro = []; campo = ''
    } else campo += c
  }
  if (campo !== '' || registro.length > 0) { registro.push(campo); registros.push(registro) }
  return registros
}

/** El texto del CSV: UTF-8 si lo es; si no, Windows-1252 (el «CSV» que guarda Excel en Windows con tildes). */
export function decodificarCsv(bytes: ArrayBuffer): string {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    return new TextDecoder('windows-1252').decode(bytes)
  }
}

// ── Una hoja (de cualquiera de los dos) a la tabla de la pantalla ───────────────────────────────────────────────
const vacia = (fila: readonly Celda[]) => fila.every((c) => c === null || (typeof c === 'string' && c.trim() === ''))

/**
 * La primera fila con algo es el encabezado; las demás, los datos con su número de fila del archivo (como en Excel).
 * Más de {@link MAX_FILAS_BASE} filas con datos no se recortan en silencio: se rechaza el archivo.
 */
export function tablaDesdeFilas(filas: readonly (readonly Celda[])[]): TablaArchivo {
  const inicio = filas.findIndex((f) => !vacia(f))
  if (inicio < 0) throw new ErrorArchivoBase('El archivo está vacío.')
  const encabezados = (filas[inicio] ?? []).map((c) => (c === null ? '' : String(c).trim()))
  const datos: TablaArchivo['filas'] = []
  for (let i = inicio + 1; i < filas.length; i += 1) {
    const celdas = filas[i] ?? []
    if (vacia(celdas)) continue
    datos.push({ numero: i + 1, celdas: [...celdas] })
  }
  if (datos.length === 0) throw new ErrorArchivoBase('El archivo solo tiene el encabezado: no hay contactos que cargar.')
  if (datos.length > MAX_FILAS_BASE) {
    throw new ErrorArchivoBase(`El archivo trae ${datos.length.toLocaleString('es-PE')} filas y una base admite hasta ${MAX_FILAS_BASE.toLocaleString('es-PE')}. Divídelo en dos archivos.`)
  }
  return { encabezados, filas: datos }
}

/** Lee el .xlsx (primera hoja) con el lector que se descarga en este momento. */
async function leerXlsx(bytes: ArrayBuffer): Promise<Celda[][]> {
  const { readSheet } = await import('read-excel-file/universal')
  try {
    const hoja = await readSheet(bytes)
    return hoja.map((fila) => fila.map((c) => (c ?? null) as Celda))
  } catch {
    throw new ErrorArchivoBase('No se pudo leer el Excel. Ábrelo y guárdalo de nuevo como .xlsx, o expórtalo como .csv.')
  }
}

/** Lee el archivo elegido y devuelve su tabla. Solo .xlsx o .csv, hasta 10 MB y 5000 filas. */
export async function leerArchivoBase(archivo: File): Promise<TablaArchivo> {
  const tipo = tipoDeArchivo(archivo.name)
  if (!tipo) throw new ErrorArchivoBase('Elige un archivo .xlsx o .csv. (Un .xls antiguo: ábrelo en Excel y guárdalo como .xlsx.)')
  if (archivo.size > MAX_BYTES_ARCHIVO) throw new ErrorArchivoBase('El archivo pesa más de 10 MB. Revisa que sea solo la lista de contactos.')
  const bytes = await archivo.arrayBuffer()
  const filas: Celda[][] = tipo === 'xlsx' ? await leerXlsx(bytes) : parsearCsv(decodificarCsv(bytes))
  return tablaDesdeFilas(filas)
}
