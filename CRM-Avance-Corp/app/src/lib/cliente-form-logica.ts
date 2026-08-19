// Lógica PURA del formulario de cliente del CRM (alta + corregir) — espejo fiel
// del modal #modalCliente del panel del analista del portal
// (public_html/admin/analista.html + js/admin/analista.js: normNombrePersona,
// BANCOS_PE, leerYValidarBancarios y las validaciones de guardarCliente).
// Vive separada del componente (patrón documento-core del portal) para poder
// testearse sin DOM. Si el portal cambia una regla, cambiar AMBOS lados.
import type { ClienteDetalle, CuentaBancariaSeleccionable } from './clientes-tipos'
import { RE_DOC_GENERICO, validarDocumento, type TipoDocumento } from './documento'

/**
 * Catálogo canónico de entidades financieras peruanas, agrupado en apartados —
 * copiado VERBATIM de analista.js (que a su vez espeja js/admin/clientes.js).
 * "Otro" NO figura aquí a propósito: el <select> lo agrega aparte, SIEMPRE al
 * final y fuera de los grupos. (Caja Sullana se excluyó a propósito en el
 * portal — intervenida por la SBS en 2024.)
 */
export const BANCOS_PE = [
  {
    grupo: 'Bancos',
    opciones: [
      'BCP', 'Interbank', 'BBVA', 'Scotiabank', 'BanBif', 'Banco de la Nación',
      'Banco Pichincha', 'Banco Falabella', 'Banco GNB', 'MiBanco', 'Banco Ripley',
      'Banco de Comercio', 'Banco SIP', 'Citibank',
    ],
  },
  {
    grupo: 'Cajas municipales',
    opciones: [
      'Caja Arequipa', 'Caja Cusco', 'Caja del Santa', 'Caja Huancayo', 'Caja Ica',
      'Caja Los Andes', 'Caja Maynas', 'Caja Metropolitana de Lima', 'Caja Paita',
      'Caja Piura', 'Caja Tacna', 'Caja Trujillo',
    ],
  },
  {
    grupo: 'Financieras',
    opciones: [
      'Compartamos Financiera', 'Financiera Confianza', 'Financiera Credinka',
      'Financiera Efectiva', 'Financiera Oh!', 'Financiera Proempresa',
      'Financiera Qapaq',
    ],
  },
] as const

/** Tipos de cuenta que acepta el portal (valores EXACTOS que van a la BD). */
export const TIPOS_CUENTA = [
  { k: 'ahorros', etiqueta: 'Ahorros' },
  { k: 'corriente', etiqueta: 'Corriente' },
] as const

/**
 * Norma de nombres de la BD (portal 2026-06-04): MAYÚSCULA, sin espacios en los
 * extremos y sin espacios dobles internos. Se aplica ANTES de mandar para que lo
 * que ve el usuario en el toast coincida con lo que guardará el trigger.
 */
export function normNombrePersona(s: string): string {
  return s.trim().replace(/\s+/g, ' ').toUpperCase()
}

// 15, no 5. Decidido con los 19 domicilios reales de producción: el más corto
// tiene 28 caracteres y el 100% lleva número. Con 5 pasaban «LIMA.», «no tiene»
// y «PENDIENTE», que se imprimen tal cual en el contrato.
export const DOMICILIO_LEGAL_MIN = 15
export const DOMICILIO_LEGAL_MAX = 240

/** Rechaza controles Unicode C0/C1 sin depender de una regex con bytes invisibles. */
function contieneCaracterControl(s: string): boolean {
  for (const caracter of s) {
    const codigo = caracter.codePointAt(0) ?? 0
    if (codigo <= 0x1f || (codigo >= 0x7f && codigo <= 0x9f)) return true
  }
  return false
}

/**
 * Caracteres de ancho CERO y controles de dirección bidi. No se normalizan: se
 * rechazan. Un domicilio hecho solo de estos pasa cualquier control de longitud,
 * se imprime en el contrato como NADA («con domicilio en , a quien…») y además
 * cierra el hueco PARA SIEMPRE: el trigger `perfiles_domicilio_legal_no_borrar`
 * impide volver a NULL y la RPC nunca pisa un domicilio existente.
 * Hallazgo de la auditoría adversaria del 2026-08-19, comprobado contra el CHECK
 * vivo de producción — seis U+200B lo pasaban.
 */
const INVISIBLES = /[\u00AD\u180E\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2064\uFEFF]/

/**
 * Espacios Unicode que SÍ ocupan sitio: se normalizan a espacio simple.
 * U+0085 (NEL) va aquí y no entre los controles: PostgreSQL lo trata como
 * espacio y lo colapsa, así que rechazarlo solo en el navegador rompía el
 * espejo — medido contra producción el 2026-08-19.
 */
const ESPACIOS_EXOTICOS = /[\u0085\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]/g

/**
 * Normaliza igual que `crm.normalizar_domicilio_legal` en el servidor. Sin
 * esto había dos varas para el mismo dato: `btrim` de Postgres solo quita
 * U+0020 mientras que `.trim()` de JS quita todo el espacio Unicode, así que
 * «Lima» rodeado de U+00A0 lo rechazaba el navegador (4 caracteres) y lo aceptaba el
 * servidor (7).
 */
function normalizarDomicilio(valor: string): string {
  return valor.replace(ESPACIOS_EXOTICOS, ' ').replace(/\s+/g, ' ').trim()
}

/**
 * La dirección de la PROPIA Avance Corp, la que ya sale en la cabecera del
 * contrato. Se comparó en plano (sin tildes ni puntuación) porque un acento o un
 * «N.°» no puede ser lo que la salve. No es hipotético: el 2026-08-19 se tecleó
 * como domicilio de una clienta, y el PDF habría dejado a las dos partes
 * domiciliadas en el mismo sitio — con la cláusula 14.ª mandando ahí TODAS las
 * notificaciones.
 */
function esDomicilioDeLaEmpresa(valor: string): boolean {
  const plano = valor
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ')
  return plano.includes('republica de panama') && plano.includes('3635')
}

/**
 * Fuente unica de validacion del domicilio en el navegador. Cuenta puntos de
 * codigo (no unidades UTF-16), igual que la Edge y PostgreSQL.
 */
export function validarDomicilioLegal(valor: string):
  | { ok: true; valor: string }
  | { ok: false; error: string } {
  const domicilio = normalizarDomicilio(valor)
  if (!domicilio) return { ok: false, error: 'Completa el domicilio legal del cliente.' }
  if (INVISIBLES.test(domicilio)) {
    return {
      ok: false,
      error: 'El domicilio legal contiene caracteres invisibles que no se imprimirían en el contrato.',
    }
  }
  const longitud = Array.from(domicilio).length
  if (longitud < DOMICILIO_LEGAL_MIN || longitud > DOMICILIO_LEGAL_MAX) {
    return {
      ok: false,
      error: `El domicilio legal debe tener entre ${DOMICILIO_LEGAL_MIN} y ${DOMICILIO_LEGAL_MAX} caracteres.`,
    }
  }
  if (contieneCaracterControl(domicilio)) {
    return { ok: false, error: 'El domicilio legal contiene caracteres no permitidos.' }
  }
  // Al menos un dígito: es lo que separa una dirección de un relleno, y lo
  // cumplen los 19 domicilios reales de producción sin excepción.
  if (!/[0-9]/.test(domicilio)) {
    return {
      ok: false,
      error: 'El domicilio legal necesita el número de la calle, el lote o la manzana.',
    }
  }
  const soloAlfanum = domicilio.replace(/[^0-9a-zA-ZÁÉÍÓÚÜÑáéíóúüñ]/g, '').toLowerCase()
  if (soloAlfanum.length > 0 && new Set(soloAlfanum).size === 1) {
    return { ok: false, error: 'El domicilio legal no puede ser un solo carácter repetido.' }
  }
  if (esDomicilioDeLaEmpresa(domicilio)) {
    return {
      ok: false,
      error: 'Esa es la dirección de Avance Corp, no la del cliente: el contrato dejaría a las dos partes domiciliadas en el mismo sitio.',
    }
  }
  return { ok: true, valor: domicilio }
}

// ── Sección bancaria (una por moneda: PEN = columnas base, USD = sufijo _usd) ──

/** Estado crudo de los inputs de UNA sección bancaria del formulario. */
export interface SeccionBancariaForm {
  banco: string
  tipo_cuenta: string
  numero_cuenta: string
  cci: string
  titular_distinto: boolean
  beneficiario_nombre: string
  beneficiario_dni: string
}

export const SECCION_BANCARIA_VACIA: SeccionBancariaForm = Object.freeze({
  banco: '',
  tipo_cuenta: '',
  numero_cuenta: '',
  cci: '',
  titular_distinto: false,
  beneficiario_nombre: '',
  beneficiario_dni: '',
})

/** Precarga de la sección en SOLES desde el detalle (modo corregir). */
export function seccionPenDesdeDetalle(d: ClienteDetalle): SeccionBancariaForm {
  return {
    banco: d.banco ?? '',
    tipo_cuenta: d.tipo_cuenta ?? '',
    numero_cuenta: d.numero_cuenta ?? '',
    cci: d.cci ?? '',
    titular_distinto: d.titular_distinto,
    beneficiario_nombre: d.beneficiario_nombre ?? '',
    beneficiario_dni: d.beneficiario_dni ?? '',
  }
}

/** Precarga de la sección en DÓLARES desde el detalle (modo corregir). */
export function seccionUsdDesdeDetalle(d: ClienteDetalle): SeccionBancariaForm {
  return {
    banco: d.banco_usd ?? '',
    tipo_cuenta: d.tipo_cuenta_usd ?? '',
    numero_cuenta: d.numero_cuenta_usd ?? '',
    cci: d.cci_usd ?? '',
    titular_distinto: d.titular_distinto_usd,
    beneficiario_nombre: d.beneficiario_nombre_usd ?? '',
    beneficiario_dni: d.beneficiario_dni_usd ?? '',
  }
}

/**
 * ¿El ledger (RPC cuentas_bancarias_cliente_fn) trae alguna cuenta REAL del
 * cliente? Cuenta las filas que no son la casilla del perfil: esas viven en
 * crm.cuentas_bancarias (una cuenta registrada al crear un contrato, o la
 * copia histórica de la casilla). Decide dos cosas en CORREGIR: mostrar el
 * bloque informativo y perdonar la regla «al menos una cuenta».
 * ⚠️ Las cuentas del ledger JAMÁS se siembran en las casillas editables: al
 * guardar irían a public.perfiles y el fallback perfil_legacy de Pagos las
 * usaría para contratos viejos SIN vínculo — un backfill por inferencia que
 * la nota del vault «Cuentas bancarias por contrato» prohíbe (veto Codex
 * 2026-08-11 al diseño anterior de este mismo arreglo).
 */
export function hayCuentaEnLedger(cuentas: readonly CuentaBancariaSeleccionable[]): boolean {
  return cuentas.some((c) => !c.es_cuenta_perfil)
}

/** Sección ya validada, con nulls listos para las columnas de perfiles. */
export interface DatosSeccionBancaria {
  banco: string | null
  numero_cuenta: string | null
  tipo_cuenta: string | null
  cci: string | null
  titular_distinto: boolean
  beneficiario_nombre: string | null
  beneficiario_dni: string | null
}

type ResultadoSeccionValida = { ok: true; vacia: boolean; datos: DatosSeccionBancaria }

export type CampoSeccionBancaria =
  | 'banco'
  | 'numero_cuenta'
  | 'tipo_cuenta'
  | 'cci'
  | 'beneficiario_nombre'
  | 'beneficiario_dni'

export type ResultadoSeccion =
  | ResultadoSeccionValida
  | { ok: false; error: string }

export type ResultadoSeccionDetallado =
  | ResultadoSeccionValida
  | { ok: false; error: string; campo: CampoSeccionBancaria }

const DATOS_SECCION_VACIA: DatosSeccionBancaria = Object.freeze({
  banco: null,
  numero_cuenta: null,
  tipo_cuenta: null,
  cci: null,
  titular_distinto: false,
  beneficiario_nombre: null,
  beneficiario_dni: null,
})

/**
 * Espejo de leerYValidarBancarios(prefix, {opcional:true, moneda}) del portal.
 * Sección COMPLETAMENTE vacía = cuenta no provista (válida); si se llenó algo,
 * se exige el set completo — incluido el CCI, que el portal hace OBLIGATORIO
 * cuando la sección existe (analista.js:403). Mensajes idénticos a los del
 * portal, con la moneda como sufijo para no confundir las dos secciones.
 */
export function validarSeccionBancariaDetallada(
  s: SeccionBancariaForm,
  moneda: 'Soles' | 'Dólares',
): ResultadoSeccionDetallado {
  const suf = ` (${moneda})`
  const banco = s.banco.trim()
  const numero_cuenta = s.numero_cuenta.trim()
  const tipo_cuenta = s.tipo_cuenta.trim()
  const cci = s.cci.trim()
  const titular_distinto = s.titular_distinto

  if (!banco && !numero_cuenta && !tipo_cuenta && !cci && !titular_distinto) {
    return { ok: true, vacia: true, datos: { ...DATOS_SECCION_VACIA } }
  }

  if (!banco) {
    return { ok: false, error: `Selecciona el banco de la cuenta${suf}.`, campo: 'banco' }
  }
  if (!numero_cuenta) {
    return {
      ok: false,
      error: `El N° de cuenta${suf} es obligatorio.`,
      campo: 'numero_cuenta',
    }
  }
  // Cajas municipales (ej. Caja Cusco) emiten cuentas con letras — se acepta
  // alfanumérico y guiones (regla espejo del portal, analista.js 2026-07-18).
  if (!/^[A-Za-z0-9-]+$/.test(numero_cuenta)) {
    return {
      ok: false,
      error: `El N° de cuenta${suf} solo puede contener letras, números y guiones (sin espacios).`,
      campo: 'numero_cuenta',
    }
  }
  if (!tipo_cuenta) {
    return {
      ok: false,
      error: `Selecciona el tipo de cuenta${suf}.`,
      campo: 'tipo_cuenta',
    }
  }
  if (!TIPOS_CUENTA.some((t) => t.k === tipo_cuenta)) {
    return { ok: false, error: `Tipo de cuenta${suf} inválido.`, campo: 'tipo_cuenta' }
  }
  if (!cci) {
    return { ok: false, error: `El CCI${suf} es obligatorio.`, campo: 'cci' }
  }
  if (!/^[0-9]{20}$/.test(cci)) {
    return {
      ok: false,
      error: `El CCI${suf} debe tener exactamente 20 dígitos.`,
      campo: 'cci',
    }
  }

  // Beneficiario (la cuenta es de un tercero): solo se exige con el check activo.
  // Su documento sigue la regla HISTÓRICA 8–12 dígitos (RE_DOC_GENERICO), no la
  // regla por tipo del titular.
  let beneficiario_nombre: string | null = null
  let beneficiario_dni: string | null = null
  if (titular_distinto) {
    beneficiario_nombre = normNombrePersona(s.beneficiario_nombre)
    beneficiario_dni = s.beneficiario_dni.trim()
    if (!beneficiario_nombre) {
      return {
        ok: false,
        error: `Escribe el nombre completo del beneficiario${suf} (titular de la cuenta).`,
        campo: 'beneficiario_nombre',
      }
    }
    if (!beneficiario_dni) {
      return {
        ok: false,
        error: `El DNI del beneficiario${suf} es obligatorio.`,
        campo: 'beneficiario_dni',
      }
    }
    if (!RE_DOC_GENERICO.test(beneficiario_dni)) {
      return {
        ok: false,
        error: `El DNI del beneficiario${suf} debe tener entre 8 y 12 dígitos.`,
        campo: 'beneficiario_dni',
      }
    }
  }

  return {
    ok: true,
    vacia: false,
    datos: { banco, numero_cuenta, tipo_cuenta, cci, titular_distinto, beneficiario_nombre, beneficiario_dni },
  }
}

/**
 * Contrato histórico sin metadatos de UI. Los formularios generales consumen
 * esta forma estable; el alta inline usa la variante detallada para asociar el
 * error al control exacto sin duplicar ninguna regla bancaria.
 */
export function validarSeccionBancaria(
  s: SeccionBancariaForm,
  moneda: 'Soles' | 'Dólares',
): ResultadoSeccion {
  const resultado = validarSeccionBancariaDetallada(s, moneda)
  return resultado.ok
    ? resultado
    : { ok: false, error: resultado.error }
}

/** Las 14 columnas bancarias EXACTAS de public.perfiles (PEN base + _usd). */
export interface PatchBancarios {
  banco: string | null
  tipo_cuenta: string | null
  numero_cuenta: string | null
  cci: string | null
  titular_distinto: boolean
  beneficiario_nombre: string | null
  beneficiario_dni: string | null
  banco_usd: string | null
  tipo_cuenta_usd: string | null
  numero_cuenta_usd: string | null
  cci_usd: string | null
  titular_distinto_usd: boolean
  beneficiario_nombre_usd: string | null
  beneficiario_dni_usd: string | null
}

/** PEN → columnas base; USD → sufijo _usd. Un solo objeto para el UPDATE. */
export function armarPatchBancarios(
  pen: DatosSeccionBancaria,
  usd: DatosSeccionBancaria,
): PatchBancarios {
  return {
    banco: pen.banco,
    tipo_cuenta: pen.tipo_cuenta,
    numero_cuenta: pen.numero_cuenta,
    cci: pen.cci,
    titular_distinto: pen.titular_distinto,
    beneficiario_nombre: pen.beneficiario_nombre,
    beneficiario_dni: pen.beneficiario_dni,
    banco_usd: usd.banco,
    tipo_cuenta_usd: usd.tipo_cuenta,
    numero_cuenta_usd: usd.numero_cuenta,
    cci_usd: usd.cci,
    titular_distinto_usd: usd.titular_distinto,
    beneficiario_nombre_usd: usd.beneficiario_nombre,
    beneficiario_dni_usd: usd.beneficiario_dni,
  }
}

export type ResultadoBancarios =
  | { ok: true; bancarios: PatchBancarios }
  | { ok: false; error: string }

/**
 * Validación bancaria COMPLETA del formulario: las dos monedas + la regla
 * "AL MENOS UNA cuenta" (es donde se le depositan los intereses) — espejo de
 * analista.js:560. Compartida por el alta directa (validarClienteForm) y por la
 * conversión de lead, que captura la identidad por su lado (viene del lead)
 * pero exige los MISMOS bancarios que el alta del portal.
 */
export function validarBancariosForm(
  pen: SeccionBancariaForm,
  usd: SeccionBancariaForm,
  opciones?: {
    /**
     * SOLO corregir: el cliente ya tiene cuenta activa en crm.cuentas_bancarias
     * (vinculada a un contrato). Perdona ÚNICAMENTE la regla «al menos una»
     * con ambas casillas vacías — el patch va con nulls (idempotente: si las
     * casillas ya estaban vacías, el perfil no cambia). Nunca perdona una
     * sección malformada: eso se corrige o se vacía, jamás pasa a medias.
     */
    cuentaEnLedger?: boolean
  },
): ResultadoBancarios {
  const valPen = validarSeccionBancaria(pen, 'Soles')
  if (!valPen.ok) return valPen
  const valUsd = validarSeccionBancaria(usd, 'Dólares')
  if (!valUsd.ok) return valUsd
  if (valPen.vacia && valUsd.vacia && !opciones?.cuentaEnLedger) {
    return {
      ok: false,
      error: 'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    }
  }
  return { ok: true, bancarios: armarPatchBancarios(valPen.datos, valUsd.datos) }
}

// ── Validación del formulario completo (espejo de guardarCliente del portal) ──

/** Estado crudo del formulario completo tal como sale de los inputs. */
export interface ValoresClienteForm {
  apellidos: string
  nombres: string
  tipo_documento: TipoDocumento
  documento: string
  telefono: string
  correo: string
  domicilio: string
  pen: SeccionBancariaForm
  usd: SeccionBancariaForm
}

/** Payload ya normalizado, listo para la edge (alta) o el UPDATE (corregir). */
export interface ClienteValidado {
  /** Derivado con APELLIDOS primero (norma del portal 2026-06-09). */
  nombre_completo: string
  /** null SOLO en el legacy sin separar (corregir): se conserva su nombre original. */
  apellidos: string | null
  nombres: string | null
  tipo_documento: TipoDocumento
  dni: string
  telefono: string | null
  correo: string
  domicilio: string
  bancarios: PatchBancarios
}

export type ResultadoClienteForm =
  | { ok: true; cliente: ClienteValidado }
  | { ok: false; error: string }

/**
 * Validación completa, en el MISMO orden y con los MISMOS mensajes que el
 * portal (guardarCliente de analista.js). `actual` es el detalle cargado en
 * modo corregir (null en el alta): habilita las dos concesiones del portal —
 * (1) LEGACY sin separar: si el cliente viejo no tiene apellidos/nombres, se
 *     permite guardar lo demás con ambos vacíos conservando su nombre_completo;
 * (2) GRANDFATHERING del documento: si NO se tocó ni el tipo ni el número, el
 *     valor legado pasa tal cual aunque hoy no valide (corregir el teléfono no
 *     exige arreglar antes un documento viejo mal formado).
 */
export function validarClienteForm(
  valores: ValoresClienteForm,
  actual: ClienteDetalle | null = null,
  opciones?: { cuentaEnLedger?: boolean },
): ResultadoClienteForm {
  const apellidos = normNombrePersona(valores.apellidos)
  const nombres = normNombrePersona(valores.nombres)
  let nombre_completo = `${apellidos} ${nombres}`.trim()
  const documentoCrudo = valores.documento.trim()
  const telefono = valores.telefono.trim()
  const correo = valores.correo.trim()
  const domicilioValidado = validarDomicilioLegal(valores.domicilio)

  const esLegacySinSeparar = actual !== null
    && !actual.apellidos && !actual.nombres && !!actual.nombre_completo

  if ((apellidos && !nombres) || (!apellidos && nombres)) {
    return { ok: false, error: 'Completa Apellidos y Nombres (ambos campos).' }
  }
  if (!apellidos && !nombres) {
    if (esLegacySinSeparar) {
      nombre_completo = actual.nombre_completo
    } else {
      return { ok: false, error: 'Completa los apellidos y nombres del cliente.' }
    }
  }
  if (!correo || !documentoCrudo) {
    return { ok: false, error: 'Completa apellidos, nombres, documento y correo.' }
  }
  if (!domicilioValidado.ok) return domicilioValidado
  // El portal validaba el formato con el <input type="email"> nativo del <form>;
  // aquí el guardado es onClick, así que el espejo va explícito (sin él, un
  // correo malformado viajaba hasta Auth y volvía un error crudo en inglés).
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo)) {
    return { ok: false, error: 'El correo electrónico no es válido.' }
  }

  const docSinCambios = actual !== null
    && valores.tipo_documento === actual.tipo_documento
    && documentoCrudo === (actual.dni ?? '')
  let dni: string
  if (docSinCambios) {
    dni = documentoCrudo
  } else {
    const valDoc = validarDocumento(valores.tipo_documento, documentoCrudo)
    if (!valDoc.ok) return { ok: false, error: valDoc.error }
    dni = valDoc.valor
  }

  // El cliente puede invertir en soles y/o dólares, con una cuenta de depósito
  // por moneda. Cada una es opcional por separado, pero debe haber AL MENOS UNA
  // — regla que el portal aplica tanto al alta como a la corrección (y aquí
  // también a la conversión de lead, vía la misma validarBancariosForm).
  const valBanc = validarBancariosForm(valores.pen, valores.usd, opciones)
  if (!valBanc.ok) return valBanc

  return {
    ok: true,
    cliente: {
      nombre_completo,
      apellidos: apellidos || null,
      nombres: nombres || null,
      tipo_documento: valores.tipo_documento,
      dni,
      telefono: telefono || null,
      correo,
      domicilio: domicilioValidado.valor,
      bancarios: valBanc.bancarios,
    },
  }
}
