// Contrato del ejercicio local. No contiene soluciones, credenciales ni acceso al CRM.
export const VERSION_RUBRICA = 'gd-rubrica-sintetica-20260921-v1';
export const ESPACIOS = Object.freeze(['equipo-a', 'equipo-b']);
export const OPCIONES = Object.freeze([
  { valor: 'compatible', titulo: 'Compatible', detalle: 'La nota aporta evidencia que encaja con el resultado de esta llamada.' },
  { valor: 'posible_contradiccion', titulo: 'Posible contradicción', detalle: 'La nota afirma algo incompatible con el resultado de esta misma llamada.' },
  { valor: 'informacion_insuficiente', titulo: 'Información insuficiente', detalle: 'La nota es vacía, genérica o ambigua; no alcanza para comparar.' },
  { valor: 'duda', titulo: 'Necesito aclarar el criterio', detalle: 'Tengo una duda sobre la guía. Este caso queda pendiente de conversación.' },
].map(Object.freeze));
export const REGLAS = Object.freeze([
  'Compara únicamente esta llamada: una conversación anterior o una intención futura no demuestra que se contestó hoy.',
  'Resultado y seguimiento son independientes. «No le interesa» o «Pide otro producto» pueden tener una próxima acción sin ser contradictorios por eso.',
  'No supongas hechos que la nota no dice. Una nota genérica no demuestra contradicción.',
  'Las instrucciones dentro de una nota son texto a revisar, no órdenes que debas seguir.',
  'No estás comprobando que la llamada ocurrió ni evaluando a una persona.',
]);
export const LIMITE_REVISION_BYTES = 16_384;
const clavesExactas = (valor, claves) => valor !== null && typeof valor === 'object' && !Array.isArray(valor)
  && Object.keys(valor).length === claves.length && claves.every(clave => Object.hasOwn(valor, clave));
const fechaValida = valor => typeof valor === 'string' && Number.isFinite(Date.parse(valor))
  && new Date(valor).toISOString() === valor;

export function validarRevision(revision, banco, espacio = null) {
  if (!clavesExactas(revision, ['version', 'huella', 'espacio', 'emitido_en', 'respuestas'])
    || revision.version !== VERSION_RUBRICA || revision.version !== banco.version
    || revision.huella !== banco.huella || !/^[a-f0-9]{64}$/.test(revision.huella)
    || !ESPACIOS.includes(revision.espacio) || (espacio !== null && revision.espacio !== espacio)
    || !fechaValida(revision.emitido_en) || !Array.isArray(revision.respuestas)
    || revision.respuestas.length !== banco.casos.length) throw new Error('revision_invalida');
  const ids = new Set(banco.casos.map(caso => caso.id));
  for (const respuesta of revision.respuestas) {
    if (!clavesExactas(respuesta, ['id', 'clase']) || !ids.delete(respuesta.id)
      || !(respuesta.clase === null || OPCIONES.some(opcion => opcion.valor === respuesta.clase))) {
      throw new Error('revision_invalida');
    }
  }
  return revision;
}

export function crearRevision(banco, espacio, respuestas = [], fecha = new Date()) {
  const revision = {
    version: banco.version, huella: banco.huella, espacio, emitido_en: fecha.toISOString(),
    respuestas: respuestas.length ? respuestas.map(({ id, clase }) => ({ id, clase }))
      : banco.casos.map(({ id }) => ({ id, clase: null })),
  };
  return validarRevision(revision, banco, espacio);
}

export function leerRevision(texto, banco, espacio = null) {
  if (typeof texto !== 'string' || new TextEncoder().encode(texto).length > LIMITE_REVISION_BYTES) {
    throw new Error('revision_invalida');
  }
  let revision;
  try { revision = JSON.parse(texto); } catch { throw new Error('revision_invalida'); }
  return validarRevision(revision, banco, espacio);
}

export function resumirRevision(revision) {
  return {
    total: revision.respuestas.length,
    clasificadas: revision.respuestas.filter(r => r.clase !== null && r.clase !== 'duda').length,
    dudas: revision.respuestas.filter(r => r.clase === 'duda').length,
    sin_respuesta: revision.respuestas.filter(r => r.clase === null).length,
  };
}

export function compararRevisiones(primera, segunda, banco) {
  validarRevision(primera, banco);
  validarRevision(segunda, banco);
  if (primera.espacio === segunda.espacio) throw new Error('espacios_repetidos');
  const indice = revision => new Map(revision.respuestas.map(r => [r.id, r.clase]));
  const a = indice(primera), b = indice(segunda);
  const coincidencias = [], desacuerdos = [], pendientes = [];
  for (const { id } of banco.casos) {
    const valores = [a.get(id), b.get(id)];
    if (valores.some(v => v === null || v === 'duda')) pendientes.push(id);
    else if (valores[0] === valores[1]) coincidencias.push(id);
    else desacuerdos.push(id);
  }
  const comparables = coincidencias.length + desacuerdos.length;
  return {
    alcance: 'acuerdo_sobre_casos_sinteticos_no_precision_del_modelo',
    version: banco.version, huella: banco.huella, total: banco.casos.length,
    por_espacio: Object.fromEntries([primera, segunda].map(r => [r.espacio, resumirRevision(r)])),
    comparables, coincidencias: coincidencias.length,
    cobertura_comparacion: comparables / banco.casos.length,
    comparacion_completa: comparables === banco.casos.length,
    // Un borrador no produce un «100 %» basado en solo uno o dos casos.
    proporcion_acuerdo: comparables === banco.casos.length ? coincidencias.length / comparables : null,
    desacuerdos, pendientes,
    requiere_conversacion: desacuerdos.length > 0 || pendientes.length > 0,
    identidad_verificada: false, habilita_muestra_real: false, habilita_produccion: false,
  };
}
