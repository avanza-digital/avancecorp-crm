// lib/bases-cargadas.ts — «Bases cargadas» (F5/F6, 04/10/2026): el contrato servidor ↔ pantalla
// (`BASE PARA GESTION/BASES-CARGADAS-CONTRATO.md`), los topes, los textos y la lógica PURA de la pantalla: reconocer las
// columnas del archivo, validar cada fila COMO EL SERVIDOR (solo para la vista previa), partir en lotes, repartir por
// cantidades y armar el informe. El SERVIDOR decide (veredicto de cada fila, quién es elegible, a quién se reparte); aquí
// solo se prepara, se cuenta y se redacta.
import * as v from 'valibot'
import { EnteroNoNegativoRpcSchema, NumeroRpcSchema } from './esquemas-rpc'
import { csvDe } from './exportar-csv'
import { normalizar } from './clientes-vista'
import type { Moneda } from './format'
import type { FilaBaseGestion } from './base-gestion'
import type { Miembro } from './tipos'

// ── Topes: espejo de `private.bases_carga_constantes()` (B8). Solo para preparar y avisar; el servidor manda. ───────
export const MAX_FILAS_BASE = 5000
export const MAX_FILAS_LOTE = 100
export const MAX_LEADS_ARMAR = 2000
export const MAX_NOMBRE_BASE = 80
/** E6 (Miguel, 04/10): un contacto repartido que nadie toca en 3 días se marca en rojo (nada se mueve solo). */
export const DIAS_SIN_TOCAR = 3

const TextoONulo = v.nullable(v.string())
const Entero = EnteroNoNegativoRpcSchema

// ── El archivo: columnas que se reconocen ─────────────────────────────────────────────────────────────────────────
/** Lo que el CRM sabe leer de un archivo. `apellidos` es una ayuda de la pantalla: si el Excel trae nombres y apellidos
 *  en dos columnas, se juntan en el nombre (el servidor solo recibe `nombre`). */
export const CAMPOS_ARCHIVO = ['nombre', 'apellidos', 'telefono', 'dni', 'distrito', 'comentario', 'capital', 'moneda'] as const
export type CampoArchivo = (typeof CAMPOS_ARCHIVO)[number]

export const ROTULO_CAMPO: Readonly<Record<CampoArchivo, string>> = {
  nombre: 'Nombre', apellidos: 'Apellidos', telefono: 'Teléfono', dni: 'DNI', distrito: 'Distrito',
  comentario: 'Comentario', capital: 'Capital', moneda: 'Moneda',
}

/** E5: nombre y teléfono válido son obligatorios; lo demás, opcional. */
export const CAMPOS_OBLIGATORIOS: readonly CampoArchivo[] = ['nombre', 'telefono']

/** Encabezados que se reconocen solos (sin tildes ni mayúsculas). El primero que aparece gana. */
const SINONIMOS: Readonly<Record<CampoArchivo, readonly string[]>> = {
  nombre: ['nombre', 'nombres', 'nombre completo', 'nombres completos', 'nombres y apellidos', 'apellidos y nombres', 'cliente', 'contacto', 'name', 'full name'],
  apellidos: ['apellidos', 'apellido', 'apellido paterno', 'last name'],
  telefono: ['telefono', 'telefonos', 'tel', 'celular', 'cel', 'movil', 'whatsapp', 'numero', 'nro celular', 'numero de celular', 'phone'],
  dni: ['dni', 'documento', 'doc', 'nro documento', 'numero de documento', 'nro dni', 'num doc'],
  distrito: ['distrito', 'zona', 'ubicacion', 'ciudad'],
  comentario: ['comentario', 'comentarios', 'nota', 'notas', 'observacion', 'observaciones', 'detalle'],
  capital: ['capital', 'capital estimado', 'monto', 'monto estimado', 'importe', 'inversion'],
  moneda: ['moneda', 'divisa', 'currency'],
}

/** Un encabezado comparable: sin tildes, en minúsculas, sin signos y con los espacios colapsados. */
function claveEncabezado(texto: string): string {
  return normalizar(texto).replace(/[^a-z0-9]+/g, ' ').trim()
}

/** Qué columna del archivo (índice) alimenta cada campo; `null` = ninguna. */
export type MapeoColumnas = Record<CampoArchivo, number | null>

export const MAPEO_VACIO: MapeoColumnas = { nombre: null, apellidos: null, telefono: null, dni: null, distrito: null, comentario: null, capital: null, moneda: null }

/**
 * Reconoce las columnas por su encabezado: primero la coincidencia exacta con un sinónimo; después, el encabezado que
 * EMPIEZA por uno («Teléfono 1», «DNI del cliente»). Una columna alimenta un solo campo; cada campo, la primera columna.
 */
export function detectarColumnas(encabezados: readonly string[]): MapeoColumnas {
  const claves = encabezados.map(claveEncabezado)
  const usadas = new Set<number>()
  const mapeo: MapeoColumnas = { ...MAPEO_VACIO }
  for (const pasada of ['exacta', 'prefijo'] as const) {
    for (const campo of CAMPOS_ARCHIVO) {
      if (mapeo[campo] !== null) continue
      const i = claves.findIndex((clave, j) => !usadas.has(j) && clave !== '' && SINONIMOS[campo].some((s) =>
        pasada === 'exacta' ? clave === s : clave.startsWith(`${s} `)))
      if (i >= 0) { mapeo[campo] = i; usadas.add(i) }
    }
  }
  return mapeo
}

// ── Una fila del archivo, validada como el servidor ─────────────────────────────────────────────────────────────
/** Una celda tal como llega del lector (Excel puede traer números, fechas o casillas). */
export type Celda = string | number | boolean | Date | null

export const MOTIVOS_INVALIDA = [
  'nombre_vacio', 'nombre_largo', 'telefono_invalido', 'dni_invalido', 'capital_invalido', 'moneda_invalida', 'distrito_largo', 'comentario_largo',
] as const
export type MotivoInvalida = (typeof MOTIVOS_INVALIDA)[number]

/** Espejo de `private.normalizar_telefono` (la regla del alta y de `cargar_base_lote`): 9 dígitos → +51; si no, + y
 *  los dígitos. El resultado vale solo si es un celular peruano (`^\+519\d{8}$`). */
export function normalizarTelefonoBase(valor: string): string | null {
  const digitos = valor.replace(/\D/g, '')
  if (!digitos) return null
  return digitos.length === 9 ? `+51${digitos}` : `+${digitos}`
}

export function esCelularPeruano(e164: string | null): boolean {
  return e164 !== null && /^\+519\d{8}$/.test(e164)
}

/**
 * El capital como lo escribe la gente («S/ 30,000», «30 000.50», «1.500,75») convertido al formato que acepta el
 * servidor (`^\d{1,10}(\.\d{1,2})?$`, > 0). Con punto y coma a la vez, el ÚLTIMO es el decimal; con uno solo, es decimal
 * si va seguido de 1 o 2 dígitos al final (si no, separa miles). `null` si no se puede leer.
 */
export function normalizarCapital(valor: string): string | null {
  // Un capital negativo no se «arregla» quitándole el signo: es inválido (el servidor también lo rechaza).
  if (/-\s*[\d.,]/.test(valor)) return null
  const limpio = valor.replace(/[^\d.,]/g, '')
  if (!/\d/.test(limpio)) return null
  const ultimoPunto = limpio.lastIndexOf('.')
  const ultimaComa = limpio.lastIndexOf(',')
  let enteros: string
  let decimales = ''
  const separador = Math.max(ultimoPunto, ultimaComa)
  const cola = separador >= 0 ? limpio.slice(separador + 1) : ''
  const ambos = ultimoPunto >= 0 && ultimaComa >= 0
  const unicoSeparador = separador >= 0 && limpio.split(limpio[separador] ?? '').length === 2
  if (separador >= 0 && (ambos || (unicoSeparador && /^\d{1,2}$/.test(cola)))) {
    enteros = limpio.slice(0, separador).replace(/[.,]/g, '')
    decimales = cola.replace(/[.,]/g, '')
  } else {
    enteros = limpio.replace(/[.,]/g, '')
  }
  enteros = enteros.replace(/^0+(?=\d)/, '')
  if (!/^\d{1,10}$/.test(enteros) || !/^\d{0,2}$/.test(decimales)) return null
  const texto = decimales ? `${enteros}.${decimales}` : enteros
  return Number(texto) > 0 ? texto : null
}

/** «S/», «soles» → PEN; «US$», «$», «dólares» → USD; vacío → null (el servidor pone PEN). Otro valor: inválido. */
export function normalizarMoneda(valor: string): Moneda | 'invalida' | null {
  const clave = normalizar(valor.trim()).replace(/[\s.]/g, '')
  if (!clave) return null
  if (['pen', 's/', 's', 'sol', 'soles', 'nuevossoles'].includes(clave)) return 'PEN'
  if (['usd', 'us$', '$', 'dolar', 'dolares', 'dolaresamericanos'].includes(clave)) return 'USD'
  return 'invalida'
}

/** Texto de una celda: los números de Excel sin notación científica ni «.0»; el DNI numérico recupera sus ceros. */
export function textoCelda(celda: Celda, campo: CampoArchivo): string {
  if (celda === null) return ''
  if (typeof celda === 'number') {
    if (!Number.isFinite(celda)) return ''
    if (Number.isInteger(celda)) {
      const entero = celda.toLocaleString('en-US', { useGrouping: false, maximumFractionDigits: 0 })
      // Excel guarda «04587123» como número y se come el cero: un DNI tiene 8 dígitos.
      return campo === 'dni' && entero.length < 8 ? entero.padStart(8, '0') : entero
    }
    return String(celda)
  }
  if (typeof celda === 'boolean') return celda ? 'VERDADERO' : 'FALSO'
  if (celda instanceof Date) return Number.isNaN(celda.getTime()) ? '' : celda.toISOString().slice(0, 10)
  return celda.trim()
}

/** Lo que se envía de una fila (las claves opcionales vacías no viajan). */
export interface FilaEnvio {
  fila: number
  nombre: string
  telefono: string
  dni?: string
  distrito?: string
  comentario?: string
  capital?: string
  moneda?: Moneda
}

export type MotivoLocal = MotivoInvalida | 'en_archivo'

/** Una fila del archivo ya leída: lo que se enviaría, o por qué NO se envía (inválida o repetida en el archivo). */
export interface FilaPreparada {
  /** Número de fila del archivo, como lo ve quien lo abre en Excel (el encabezado es la 1). */
  fila: number
  nombre: string
  telefono: string
  telefonoLeido: string
  dni: string
  distrito: string
  comentario: string
  capital: string
  moneda: Moneda | null
  /** null = se envía. */
  error: MotivoLocal | null
}

function validarFila(fila: number, leer: (campo: CampoArchivo) => string): FilaPreparada {
  const nombre = [leer('nombre'), leer('apellidos')].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim()
  const telefonoLeido = leer('telefono')
  const telefono = normalizarTelefonoBase(telefonoLeido) ?? ''
  const dniLeido = leer('dni')
  // «45.871.236» o «45 871 236» es un DNI con separadores: se envían los dígitos. Otra cosa se envía tal cual (inválida).
  const dni = /^[\d\s.-]+$/.test(dniLeido) ? dniLeido.replace(/\D/g, '') : dniLeido
  const distrito = leer('distrito')
  const comentario = leer('comentario')
  const capitalLeido = leer('capital')
  const capital = capitalLeido ? normalizarCapital(capitalLeido) : ''
  const moneda = normalizarMoneda(leer('moneda'))
  // El orden de las comprobaciones es el del servidor (bases_carga_cargar_lote_core): el primer motivo gana.
  const error: MotivoInvalida | null =
    !nombre ? 'nombre_vacio'
      : nombre.length > 200 ? 'nombre_largo'
        : !esCelularPeruano(telefono || null) ? 'telefono_invalido'
          : dni && !/^\d{8}$/.test(dni) ? 'dni_invalido'
            : capital === null ? 'capital_invalido'
              : moneda === 'invalida' ? 'moneda_invalida'
                : distrito.length > 120 ? 'distrito_largo'
                  : comentario.length > 1000 ? 'comentario_largo'
                    : null
  return {
    fila, nombre, telefono, telefonoLeido, dni, distrito, comentario, capital: capital ?? capitalLeido,
    moneda: moneda === 'invalida' ? null : moneda, error,
  }
}

/** Una hoja leída: el encabezado y las filas de datos con su número de fila del archivo. */
export interface TablaArchivo {
  encabezados: string[]
  filas: { numero: number; celdas: Celda[] }[]
}

export interface Preparacion {
  /** Todas las filas con datos (las vacías no cuentan), en el orden del archivo. */
  filas: FilaPreparada[]
  /** Las que se envían. */
  validas: FilaPreparada[]
  invalidas: number
  repetidas: number
}

/**
 * Valida el archivo entero con el mapeo elegido: cada fila como el servidor y, entre las válidas, la repetida (mismo
 * teléfono o mismo DNI que una anterior) queda fuera —la primera aparición gana, como en el servidor—. Las filas
 * completamente vacías no cuentan (Excel deja muchas al final).
 */
export function prepararFilas(tabla: TablaArchivo, mapeo: MapeoColumnas): Preparacion {
  const filas: FilaPreparada[] = []
  const vistos = new Set<string>()
  let invalidas = 0
  let repetidas = 0
  for (const { numero, celdas } of tabla.filas) {
    const leer = (campo: CampoArchivo) => {
      const i = mapeo[campo]
      return i === null ? '' : textoCelda(celdas[i] ?? null, campo)
    }
    if (CAMPOS_ARCHIVO.every((c) => leer(c) === '')) continue
    const preparada = validarFila(numero, leer)
    if (preparada.error) invalidas += 1
    else if (vistos.has(`t:${preparada.telefono}`) || (preparada.dni && vistos.has(`d:${preparada.dni}`))) {
      preparada.error = 'en_archivo'
      repetidas += 1
    } else {
      vistos.add(`t:${preparada.telefono}`)
      if (preparada.dni) vistos.add(`d:${preparada.dni}`)
    }
    filas.push(preparada)
  }
  return { filas, validas: filas.filter((f) => f.error === null), invalidas, repetidas }
}

/** Lo que viaja de una fila válida. */
export function filaEnvio(f: FilaPreparada): FilaEnvio {
  return {
    fila: f.fila, nombre: f.nombre, telefono: f.telefono,
    ...(f.dni ? { dni: f.dni } : {}),
    ...(f.distrito ? { distrito: f.distrito } : {}),
    ...(f.comentario ? { comentario: f.comentario } : {}),
    ...(f.capital ? { capital: f.capital } : {}),
    ...(f.capital && f.moneda ? { moneda: f.moneda } : {}),
  }
}

/** Parte en lotes de {@link MAX_FILAS_LOTE} (el servidor rechaza uno mayor). */
export function partirEnLotes<T>(filas: readonly T[], tamano: number = MAX_FILAS_LOTE): T[][] {
  const lotes: T[][] = []
  for (let i = 0; i < filas.length; i += tamano) lotes.push(filas.slice(i, i + tamano))
  return lotes
}

/** El nombre de una base: 1 a 80 caracteres (el servidor también lo exige único entre las vivas del supervisor). */
export function errorNombreBase(nombre: string): string | null {
  const limpio = nombre.trim()
  if (!limpio) return 'Escribe el nombre de la base (por ejemplo, «Feria 2025»).'
  if (limpio.length > MAX_NOMBRE_BASE) return `El nombre puede tener hasta ${MAX_NOMBRE_BASE} caracteres.`
  return null
}

/** Sugerencia de nombre a partir del archivo: «Feria 2025.xlsx» → «Feria 2025». */
export function nombreDesdeArchivo(archivo: string): string {
  return archivo.replace(/\.(xlsx|csv)$/i, '').replace(/[_]+/g, ' ').trim().slice(0, MAX_NOMBRE_BASE)
}

// ── Veredictos del servidor (cargar_base_lote) y el informe ─────────────────────────────────────────────────────
export const VEREDICTOS = ['cargada', 'ya_existia', 'no_contactar', 'invalida', 'repetida'] as const
export type Veredicto = (typeof VEREDICTOS)[number]

export const ROTULO_VEREDICTO: Readonly<Record<Veredicto, string>> = {
  cargada: 'Cargadas', ya_existia: 'Ya existían', no_contactar: 'No insistir', invalida: 'Inválidas', repetida: 'Repetidas',
}

const ROTULO_VEREDICTO_FILA: Readonly<Record<Veredicto, string>> = {
  cargada: 'Cargada', ya_existia: 'Ya existía', no_contactar: 'No insistir', invalida: 'Inválida', repetida: 'Repetida',
}

/** Una fila válida que no llegó a enviarse (la carga se detuvo antes y quien carga decidió terminar ahí). */
export const VEREDICTO_SIN_ENVIAR = 'sin_enviar'

/** El resultado de UNA fila, en palabras («Ya existía»); un veredicto que el catálogo no conoce se muestra tal cual. */
export function etiquetaVeredictoFila(veredicto: string): string {
  if (veredicto === VEREDICTO_SIN_ENVIAR) return 'Sin enviar'
  return (VEREDICTOS as readonly string[]).includes(veredicto) ? ROTULO_VEREDICTO_FILA[veredicto as Veredicto] : veredicto
}

const MOTIVO_FILA: Readonly<Record<string, string>> = {
  // ya_existia (B8: cliente, con_dueno, en_bolsa, descartado, convertido, retirado; sin motivo = fuera de tu ámbito)
  cliente: 'Ya es cliente',
  con_dueno: 'Ya es lead de un analista',
  en_bolsa: 'Está en la bolsa por repartir',
  descartado: 'Es un lead descartado',
  convertido: 'Ya se convirtió',
  retirado: 'Es un lead retirado',
  // no_contactar
  no_insistir: 'Marcado «No contactar» (Ley 29571)',
  // invalida
  nombre_vacio: 'Falta el nombre',
  nombre_largo: 'El nombre pasa de 200 caracteres',
  telefono_invalido: 'El teléfono no es un celular peruano válido',
  dni_invalido: 'El DNI debe tener 8 dígitos',
  capital_invalido: 'El capital no es un número mayor que 0 (hasta 2 decimales)',
  moneda_invalida: 'La moneda no es soles ni dólares',
  distrito_largo: 'El distrito pasa de 120 caracteres',
  comentario_largo: 'El comentario pasa de 1000 caracteres',
  // repetida
  en_archivo: 'Repetida en el archivo',
  en_base: 'Ya está en esta base',
}

/** Por qué una fila quedó como quedó, en palabras. Sin motivo, lo que se puede decir sin delatar a otro equipo. */
export function etiquetaMotivoFila(veredicto: string, motivo: string | null | undefined): string {
  if (motivo && MOTIVO_FILA[motivo]) return MOTIVO_FILA[motivo]
  if (motivo) return motivo
  switch (veredicto) {
    case 'cargada': return 'Entró a la base sin repartir'
    case 'ya_existia': return 'Ya existe en el CRM'
    case 'no_contactar': return 'Marcado «No contactar» (Ley 29571)'
    case 'repetida': return 'Repetida'
    case VEREDICTO_SIN_ENVIAR: return 'No se envió: la carga se detuvo antes'
    default: return 'Sin detalle'
  }
}

/** El veredicto de una fila del archivo: el del servidor o el de la vista previa (no se envió). */
export interface ResultadoFila {
  fila: number
  veredicto: string
  motivo: string | null
}

export type ConteoVeredictos = Record<Veredicto, number>

export function contarVeredictos(resultados: readonly ResultadoFila[]): ConteoVeredictos {
  const conteo: ConteoVeredictos = { cargada: 0, ya_existia: 0, no_contactar: 0, invalida: 0, repetida: 0 }
  for (const r of resultados) if ((VEREDICTOS as readonly string[]).includes(r.veredicto)) conteo[r.veredicto as Veredicto] += 1
  return conteo
}

/** Lo que la vista previa ya decidió (no se envía): inválidas y repetidas en el archivo, con su motivo. */
export function resultadosLocales(preparacion: Preparacion): ResultadoFila[] {
  return preparacion.filas
    .filter((f) => f.error !== null)
    .map((f) => ({ fila: f.fila, veredicto: f.error === 'en_archivo' ? 'repetida' : 'invalida', motivo: f.error }))
}

/**
 * El informe descargable: fila del archivo, resultado y motivo, ordenado por fila. NUNCA datos de otros leads (ni el
 * analista ni el id del lead que ya existía): quien lo descarga cruza la fila con su propio archivo.
 */
export function informeCsv(resultados: readonly ResultadoFila[]): string {
  const filas = [...resultados]
    .sort((a, b) => a.fila - b.fila)
    .map((r) => [r.fila, etiquetaVeredictoFila(r.veredicto), etiquetaMotivoFila(r.veredicto, r.motivo)])
  return csvDe(['Fila del archivo', 'Resultado', 'Motivo'], filas)
}

// ── Respuestas de las puertas de B8 (en producción) ────────────────────────────────────────────────────────────
export const RespuestaCrearBaseSchema = v.looseObject({
  ok: v.literal(true),
  base_id: v.string(),
  supervisor_id: v.string(),
})
export type RespuestaCrearBase = v.InferOutput<typeof RespuestaCrearBaseSchema>

const ConteoLoteSchema = v.looseObject({
  cargadas: Entero, ya_existian: Entero, no_contactar: Entero, invalidas: Entero, repetidas: Entero,
})

export const RespuestaCargarLoteSchema = v.looseObject({
  ok: v.literal(true),
  base_id: v.string(),
  lote: ConteoLoteSchema,
  base: v.looseObject({ filas_recibidas: Entero, cargadas: Entero }),
  filas: v.array(v.looseObject({
    fila: Entero,
    veredicto: v.string(),
    motivo: v.optional(v.nullable(v.string()), null),
    lead_id: v.optional(v.nullable(v.string()), null),
  })),
})
export type RespuestaCargarLote = v.InferOutput<typeof RespuestaCargarLoteSchema>

export const MOTIVOS_EXCLUIDO: Readonly<Record<string, string>> = {
  no_encontrado: 'No está en el ámbito del supervisor o no existe',
  ocupado: 'Otro proceso lo tenía tomado: reintenta',
  inactivo: 'Está inactivo',
  no_descartado: 'Ya no está descartado',
  no_contactar: 'Marcado «No contactar»',
  datos_invalidos: 'Descartado por datos inválidos',
  en_descanso: 'Está en descanso',
  en_otra_base: 'Ya está en otra base',
  en_gestion: 'En gestión: tiene seguimiento activo',
  repetido: 'Repetido en la lista',
}

export function etiquetaMotivoExcluido(motivo: string): string {
  return MOTIVOS_EXCLUIDO[motivo] ?? motivo
}

export const RespuestaArmarBaseSchema = v.looseObject({
  ok: v.literal(true),
  base_id: v.string(),
  recibidos: Entero,
  incluidos: Entero,
  excluidos: Entero,
  excluidos_por_motivo: v.record(v.string(), v.array(Entero)),
  excluidos_detalle: v.optional(v.array(v.looseObject({ posicion: Entero, lead_id: v.nullable(v.string()), motivo: v.string() })), []),
})
export type RespuestaArmarBase = v.InferOutput<typeof RespuestaArmarBaseSchema>

/** Cuántos excluidos hay por motivo, del más numeroso al menos. */
export function excluidosPorMotivo(porMotivo: Readonly<Record<string, readonly number[]>>): { motivo: string; n: number }[] {
  return Object.entries(porMotivo)
    .map(([motivo, posiciones]) => ({ motivo, n: posiciones.length }))
    .filter((x) => x.n > 0)
    .sort((a, b) => b.n - a.n || a.motivo.localeCompare(b.motivo))
}

// ── B10 · seguimiento (aún no en producción: la pantalla degrada con PGRST202) ─────────────────────────────────
export const FilaSeguimientoBasesSchema = v.object({
  base_id: v.string(),
  nombre: v.string(),
  origen: v.string(),
  supervisor_id: TextoONulo,
  supervisor_nombre: TextoONulo,
  creado_en: v.string(),
  total: Entero,
  sin_repartir: Entero,
  repartidos: Entero,
  sin_tocar: Entero,
  trabajados: Entero,
  en_descanso: Entero,
  citas: Entero,
  reactivados: Entero,
  avance: v.nullable(NumeroRpcSchema),
})
export type FilaSeguimientoBases = v.InferOutput<typeof FilaSeguimientoBasesSchema>

export const FilaSeguimientoBaseSchema = v.object({
  analista_id: v.string(),
  analista_nombre: TextoONulo,
  asignados: Entero,
  sin_tocar: Entero,
  sin_tocar_3_dias: Entero,
  trabajados: Entero,
  en_descanso: Entero,
  citas: Entero,
  reactivados: Entero,
  ultimo_intento_en: TextoONulo,
  movidos_otra_via: Entero,
})
export type FilaSeguimientoBase = v.InferOutput<typeof FilaSeguimientoBaseSchema>

export const FilaDetalleSeguimientoSchema = v.object({
  lead_id: v.string(),
  nombre_completo: v.string(),
  estado: v.string(),
  asignado_en: TextoONulo,
  ultimo_intento_en: TextoONulo,
  ultimo_resultado: TextoONulo,
})
export type FilaDetalleSeguimiento = v.InferOutput<typeof FilaDetalleSeguimientoSchema>

/** Las cifras de la hoja de bases que se abren (`p_cifra` de `seguimiento_base_detalle`). */
export const CIFRAS_BASE = ['total', 'sin_repartir', 'repartidos', 'sin_tocar', 'trabajados', 'en_descanso', 'citas', 'reactivados'] as const
export type CifraBase = (typeof CIFRAS_BASE)[number]
/** Las cifras de una fila por analista que se abren. */
export const CIFRAS_ANALISTA = ['asignados', 'sin_tocar', 'sin_tocar_3_dias', 'trabajados', 'en_descanso', 'citas', 'reactivados', 'movidos_otra_via'] as const
export type CifraAnalista = (typeof CIFRAS_ANALISTA)[number]
export type CifraSeguimiento = CifraBase | CifraAnalista

export const ROTULO_CIFRA: Readonly<Record<CifraSeguimiento, string>> = {
  total: 'Total', sin_repartir: 'Sin repartir', repartidos: 'Repartidos', sin_tocar: 'Sin tocar', trabajados: 'Trabajados',
  en_descanso: 'En descanso', citas: 'Citas', reactivados: 'Reactivados', asignados: 'Asignados',
  sin_tocar_3_dias: `Sin tocar ${DIAS_SIN_TOCAR} días`, movidos_otra_via: 'Movidos por otra vía',
}

// ── B9 · repartir y recoger ────────────────────────────────────────────────────────────────────────────────────
export const ESTADOS_CONTACTO = ['sin_repartir', 'sin_tocar', 'trabajado', 'en_descanso', 'cita', 'reactivado', 'movido_otra_via', 'no_contactar'] as const

const ROTULO_ESTADO: Readonly<Record<string, string>> = {
  sin_repartir: 'Sin repartir', sin_tocar: 'Sin tocar', trabajado: 'Trabajado', en_descanso: 'En descanso', cita: 'Cita',
  reactivado: 'Reactivado', movido_otra_via: 'Movido por otra vía', no_contactar: 'No contactar',
}

export function etiquetaEstadoContacto(estado: string): string {
  return ROTULO_ESTADO[estado] ?? estado
}

export const ContactoBaseSchema = v.object({
  lead_id: v.string(),
  nombre_completo: v.string(),
  telefono: TextoONulo,
  distrito: TextoONulo,
  agregado_en: v.string(),
  analista_id: TextoONulo,
  analista_nombre: TextoONulo,
  estado: v.string(),
})
export type ContactoBase = v.InferOutput<typeof ContactoBaseSchema>

export type EstadoContactos = 'sin_repartir' | 'repartidos' | 'todos'

export const RespuestaRepartirSchema = v.looseObject({
  repartidos: Entero,
  por_analista: v.optional(v.array(v.looseObject({ analista_id: v.string(), cantidad: Entero })), []),
  omitidos: v.optional(v.array(v.looseObject({ lead_id: v.optional(v.nullable(v.string()), null), motivo: v.string() })), []),
})
export type RespuestaRepartir = v.InferOutput<typeof RespuestaRepartirSchema>

export const RespuestaRecogerSchema = v.looseObject({ recogidos: Entero, omitidos: Entero })
export type RespuestaRecoger = v.InferOutput<typeof RespuestaRecogerSchema>

export type RepartoBase =
  | { modo: 'bloque'; asignaciones: { analista_id: string; cantidad: number }[] }
  | { modo: 'individual'; asignaciones: { lead_id: string; analista_id: string }[] }

/** Cantidad tecleada en la casilla: solo dígitos, sin ceros a la izquierda; vacío = 0. */
export function cantidadDesdeTexto(texto: string): number {
  const digitos = texto.replace(/\D/g, '').slice(0, 5)
  return digitos === '' ? 0 : Number(digitos)
}

export function totalAsignado(cantidades: Readonly<Record<string, number>>): number {
  return Object.values(cantidades).reduce((s, n) => s + n, 0)
}

/**
 * «En partes iguales»: reparte los disponibles entre los analistas que ya tienen cantidad (si ninguno tiene, entre todos).
 * El resto de la división va de a uno a los primeros (en el orden de la lista). Los demás quedan en 0.
 */
export function repartirEnPartesIguales(analistas: readonly string[], disponibles: number, actuales: Readonly<Record<string, number>> = {}): Record<string, number> {
  const conCantidad = analistas.filter((id) => (actuales[id] ?? 0) > 0)
  const entre = conCantidad.length > 0 ? conCantidad : analistas
  const resultado: Record<string, number> = Object.fromEntries(analistas.map((id) => [id, 0]))
  if (entre.length === 0 || disponibles <= 0) return resultado
  const base = Math.floor(disponibles / entre.length)
  const resto = disponibles % entre.length
  entre.forEach((id, i) => { resultado[id] = base + (i < resto ? 1 : 0) })
  return resultado
}

/** El reparto en bloque que viaja: solo los analistas con cantidad, en el orden de la lista. */
export function repartoEnBloque(analistas: readonly string[], cantidades: Readonly<Record<string, number>>): RepartoBase {
  return { modo: 'bloque', asignaciones: analistas.filter((id) => (cantidades[id] ?? 0) > 0).map((id) => ({ analista_id: id, cantidad: cantidades[id] ?? 0 })) }
}

export function repartoIndividual(leadIds: readonly string[], analistaId: string): RepartoBase {
  return { modo: 'individual', asignaciones: leadIds.map((lead_id) => ({ lead_id, analista_id: analistaId })) }
}

/**
 * A quién se le puede repartir (B9): analistas ACTIVOS; Supervisión, los de su equipo; Gerencia, cualquiera (E11), con
 * el equipo del supervisor dueño de la base primero. Por nombre dentro de cada grupo. El servidor vuelve a validar.
 */
export function analistasDelReparto(equipo: readonly Miembro[], yo: { id: string; rol: string }, supervisorDeLaBase: string | null): Miembro[] {
  const delEquipo = (m: Miembro) => m.supervisor_id === supervisorDeLaBase
  return equipo
    .filter((m) => m.activo && m.rol_crm === 'vendedor' && (yo.rol === 'gerencia' || m.supervisor_id === yo.id))
    .sort((a, b) => Number(delEquipo(b)) - Number(delEquipo(a)) || a.nombre_completo.localeCompare(b.nombre_completo, 'es'))
}

/** Los supervisores activos que Gerencia puede elegir como dueños de una base (E11). */
export function supervisoresActivos(equipo: readonly Miembro[]): Miembro[] {
  return equipo.filter((m) => m.activo && m.rol_crm === 'supervisor').sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es'))
}

/** Estados de un contacto que se pueden asignar a mano (el servidor rechaza todo el reparto si uno no es elegible). */
export const ESTADOS_ASIGNABLES: ReadonlySet<string> = new Set(['sin_repartir', 'sin_tocar', 'trabajado'])

/** Lo que el contador dice y si se puede enviar. */
export function estadoContador(asignado: number, disponibles: number): { texto: string; excede: boolean; listo: boolean } {
  const excede = asignado > disponibles
  return {
    texto: `${asignado} de ${disponibles} por repartir`,
    excede,
    listo: asignado > 0 && !excede,
  }
}

// ── Armar desde el CRM ───────────────────────────────────────────────────────────────────────────────────────────
/**
 * Hasta cuándo un descartado tiene SEGUIMIENTO ACTIVO (B6, Miguel 03/10: un intento de los últimos 7 días o una
 * rellamada agendada), o null. Solo para pintarlo en gris y no enviarlo: el servidor vuelve a decidir (`en_gestion`).
 */
export function enGestionHasta(fila: Pick<FilaBaseGestion, 'ultimo_intento_en' | 'proxima_llamada_en'>, ahora: number): number | null {
  const porIntento = fila.ultimo_intento_en ? Date.parse(fila.ultimo_intento_en) + 7 * 86_400_000 : Number.NaN
  const porRellamada = fila.proxima_llamada_en ? Date.parse(fila.proxima_llamada_en) : Number.NaN
  const hasta = Math.max(Number.isFinite(porIntento) && porIntento > ahora ? porIntento : 0, Number.isFinite(porRellamada) ? porRellamada : 0)
  return hasta > 0 ? hasta : null
}

// ── Origen de una base y avance ───────────────────────────────────────────────────────────────────────────────
export function etiquetaOrigenBase(origen: string): string {
  return origen === 'archivo' ? 'Archivo' : origen === 'crm' ? 'Desde el CRM' : origen
}

/** «45 %» (avance = trabajados / repartidos, 0–1); sin repartidos, «—». */
export function etiquetaAvance(avance: number | null): string {
  if (avance === null || !Number.isFinite(avance)) return '—'
  return `${Math.round(Math.min(1, Math.max(0, avance)) * 100)} %`
}

/** ¿Hay que pintar en rojo? Solo lo urgente (E6): contactos sin tocar 3 días. */
export function esUrgenteSinTocar(fila: Pick<FilaSeguimientoBase, 'sin_tocar_3_dias'>): boolean {
  return fila.sin_tocar_3_dias > 0
}
