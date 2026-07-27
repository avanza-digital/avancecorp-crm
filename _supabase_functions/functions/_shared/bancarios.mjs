/**
 * DATOS BANCARIOS DEL CLIENTE — validación de FRONTERA (servidor).
 *
 * Por qué existe: la cuenta bancaria es donde se le deposita el interés al
 * cliente. Sin ella el área de pagos no puede transferirle (el Excel de pagos
 * sale con "datos bancarios incompletos"), así que un cliente sin cuenta es un
 * cliente roto. Hasta 2026-07-27 la regla "al menos una cuenta" vivía SOLO en el
 * navegador y las columnas se escribían en un SEGUNDO UPDATE, después de crear
 * la cuenta Auth y de mandar el correo de bienvenida: un POST directo, un front
 * viejo o un fallo de red dejaban un cliente REAL sin cuenta donde cobrar.
 * Ahora la regla se exige aquí y las columnas entran en el MISMO INSERT.
 *
 * ESPEJO de app/src/lib/cliente-form-logica.ts (el CRM) — ahí las reglas son
 * idénticas campo por campo. Si se cambia una aquí, cambiarla también allí.
 *
 * ⚠️ El portal (public_html/js/admin/clientes.js y analista.js) es un espejo
 * PARCIAL: su `leerYValidarBancarios` NO valida el FORMATO del número de cuenta
 * (solo que no esté vacío), así que acepta cosas como '0011 0814 0200 12345' con
 * espacios, que esta frontera rechaza. Hoy no rompe nada porque el portal NO
 * manda el bloque `bancarios` a crear-cliente y sigue guardándolas por su UPDATE
 * de siempre. Pero ANTES de hacer que el portal mande el bloque hay que alinear
 * su validación, o números que sus admins tipean hoy pasarían a dar 400.
 *
 * Módulo PURO y sin dependencias (ni Deno ni Supabase) a propósito: así corre
 * bajo `node --test` sin levantar nada — mismo patrón que
 * crm-convertir-lead/preflight.mjs.
 */

/** Tipos de cuenta que acepta el portal (valores EXACTOS que van a la BD). */
export const TIPOS_CUENTA = ["ahorros", "corriente"];

/**
 * Las 14 columnas bancarias EXACTAS de public.perfiles. Declaradas para que las
 * edges en TypeScript puedan hacer `...columnas` sobre un tipo concreto (con un
 * `object` suelto, `deno check` rechaza el spread en un objeto tipado).
 *
 * @typedef {object} ColumnasBancarias
 * @property {string | null} banco
 * @property {string | null} tipo_cuenta
 * @property {string | null} numero_cuenta
 * @property {string | null} cci
 * @property {boolean} titular_distinto
 * @property {string | null} beneficiario_nombre
 * @property {string | null} beneficiario_dni
 * @property {string | null} banco_usd
 * @property {string | null} tipo_cuenta_usd
 * @property {string | null} numero_cuenta_usd
 * @property {string | null} cci_usd
 * @property {boolean} titular_distinto_usd
 * @property {string | null} beneficiario_nombre_usd
 * @property {string | null} beneficiario_dni_usd
 */

/**
 * Una sección ya validada: las 7 columnas de UNA moneda.
 *
 * @typedef {object} DatosSeccion
 * @property {string | null} banco
 * @property {string | null} numero_cuenta
 * @property {string | null} tipo_cuenta
 * @property {string | null} cci
 * @property {boolean} titular_distinto
 * @property {string | null} beneficiario_nombre
 * @property {string | null} beneficiario_dni
 */

/**
 * Documento del BENEFICIARIO: regla histórica genérica 8–12 dígitos, NO la regla
 * por tipo del titular (el beneficiario es otra persona y no tiene tipo propio).
 * Espejo de RE_DOC_GENERICO (app/src/lib/documento.ts).
 */
const RE_DOC_GENERICO = /^[0-9]{8,12}$/;

/** Norma de nombres de la BD: MAYÚSCULA, sin espacios extremos ni dobles. */
function normNombrePersona(s) {
  return String(s ?? "").trim().replace(/\s+/g, " ").toUpperCase();
}

function texto(v) {
  return String(v ?? "").trim();
}

/** Sección vacía = "cuenta no provista". Todas las columnas en null. */
const SECCION_VACIA = Object.freeze({
  banco: null,
  numero_cuenta: null,
  tipo_cuenta: null,
  cci: null,
  titular_distinto: false,
  beneficiario_nombre: null,
  beneficiario_dni: null,
});

/**
 * Valida UNA sección bancaria (una moneda). Espejo fiel de
 * validarSeccionBancaria (app/src/lib/cliente-form-logica.ts): sección
 * COMPLETAMENTE vacía = válida y "no provista"; si se llenó algo, se exige el
 * set completo (banco + n° + tipo + CCI, y el beneficiario si la cuenta es de un
 * tercero). Los mensajes son idénticos a los del navegador para que el asesor
 * lea lo mismo venga de donde venga el rechazo.
 *
 * @param {unknown} seccion
 * @param {'Soles'|'Dólares'} moneda
 * @returns {{ok: true, vacia: boolean, datos: DatosSeccion} | {ok: false, error: string}}
 */
export function validarSeccionBancaria(seccion, moneda) {
  const suf = ` (${moneda})`;
  // Una sección ausente o no-objeto es "no provista", no un error: la regla de
  // "al menos una" se evalúa después, con las dos monedas a la vista.
  const s = seccion && typeof seccion === "object" ? seccion : {};

  const banco = texto(s.banco);
  const numero_cuenta = texto(s.numero_cuenta);
  const tipo_cuenta = texto(s.tipo_cuenta);
  const cci = texto(s.cci);
  const titular_distinto = s.titular_distinto === true;

  if (!banco && !numero_cuenta && !tipo_cuenta && !cci && !titular_distinto) {
    return { ok: true, vacia: true, datos: { ...SECCION_VACIA } };
  }

  if (!banco) return { ok: false, error: `Selecciona el banco de la cuenta${suf}.` };
  if (!numero_cuenta) return { ok: false, error: `El N° de cuenta${suf} es obligatorio.` };
  // Las cajas municipales emiten cuentas con letras: alfanumérico + guiones.
  if (!/^[A-Za-z0-9-]+$/.test(numero_cuenta)) {
    return {
      ok: false,
      error: `El N° de cuenta${suf} solo puede contener letras, números y guiones (sin espacios).`,
    };
  }
  if (!tipo_cuenta) return { ok: false, error: `Selecciona el tipo de cuenta${suf}.` };
  if (!TIPOS_CUENTA.includes(tipo_cuenta)) {
    return { ok: false, error: `Tipo de cuenta${suf} inválido.` };
  }
  if (!cci) return { ok: false, error: `El CCI${suf} es obligatorio.` };
  if (!/^[0-9]{20}$/.test(cci)) {
    return { ok: false, error: `El CCI${suf} debe tener exactamente 20 dígitos.` };
  }

  let beneficiario_nombre = null;
  let beneficiario_dni = null;
  if (titular_distinto) {
    beneficiario_nombre = normNombrePersona(s.beneficiario_nombre);
    beneficiario_dni = texto(s.beneficiario_dni);
    if (!beneficiario_nombre) {
      return {
        ok: false,
        error: `Escribe el nombre completo del beneficiario${suf} (titular de la cuenta).`,
      };
    }
    if (!beneficiario_dni) {
      return { ok: false, error: `El DNI del beneficiario${suf} es obligatorio.` };
    }
    if (!RE_DOC_GENERICO.test(beneficiario_dni)) {
      return {
        ok: false,
        error: `El DNI del beneficiario${suf} debe tener entre 8 y 12 dígitos.`,
      };
    }
  }

  return {
    ok: true,
    vacia: false,
    datos: {
      banco,
      numero_cuenta,
      tipo_cuenta,
      cci,
      titular_distinto,
      beneficiario_nombre,
      beneficiario_dni,
    },
  };
}

/**
 * PEN va a las columnas base, USD a las mismas con sufijo `_usd`.
 *
 * @param {DatosSeccion} pen
 * @param {DatosSeccion} usd
 * @returns {ColumnasBancarias}
 */
function armarColumnas(pen, usd) {
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
  };
}

/**
 * Validación COMPLETA del bloque bancario: las dos monedas + la regla dura
 * "AL MENOS UNA cuenta" (soles o dólares). Devuelve las 14 columnas listas para
 * entrar en el MISMO INSERT de `perfiles` que el resto del cliente.
 *
 * `bancarios` ausente/no-objeto se trata como las dos secciones vacías → falla
 * por "al menos una cuenta". Es deliberado y fail-closed: un caller que no manda
 * el bloque (front viejo, POST directo) recibe un 400 claro en vez de crear un
 * cliente al que después no se le puede depositar.
 *
 * @param {unknown} bancarios  `{ pen: {...}, usd: {...} }`
 * @returns {{ok: true, columnas: ColumnasBancarias} | {ok: false, error: string}}
 */
export function validarBancarios(bancarios) {
  const b = bancarios && typeof bancarios === "object" ? bancarios : {};

  const valPen = validarSeccionBancaria(b.pen, "Soles");
  if (!valPen.ok) return valPen;
  const valUsd = validarSeccionBancaria(b.usd, "Dólares");
  if (!valUsd.ok) return valUsd;

  if (valPen.vacia && valUsd.vacia) {
    return {
      ok: false,
      error:
        "Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.",
    };
  }

  return { ok: true, columnas: armarColumnas(valPen.datos, valUsd.datos) };
}
