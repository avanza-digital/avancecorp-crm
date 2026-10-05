// crm-llamadas-ingesta — recibe del celular corporativo el aviso de cada llamada y su latido de salud.
//
// Seguridad (F3, decisión 1 provisional de Jhosep, 01/10/2026): se despliega con verify_jwt=false
// porque MacroDroid no tiene sesión de usuario. El control es la CLAVE DEL CELULAR, que viaja en la
// cabecera x-celular-credencial (nunca en la URL). La base solo guarda su sha256 y la valida en una
// RPC que solo puede llamar service_role; cualquier problema de clave responde el MISMO 401.
//
// Contrato con la base (20261005143843, plan v2 de la corrección §1): la BASE es la única que valida el
// contenido. Esta función solo revisa el transporte y contesta sin tocar la base únicamente:
//   método distinto de POST → 405 · tipo distinto de JSON → 415 · clave sin forma válida → 401 ·
//   cuerpo de más de 4 KB → 413 (corta la lectura).
// Todo lo demás llega a la base, también el JSON mal formado y el sobre inválido (con la carga en null):
// la base autentica, gasta cupo y devuelve {resultado: aceptado | invalido, mensaje}. Esta función elige la
// puerta por `accion` y traduce: aceptado → 202 (llamada) o 200 (latido); invalido → 400 con el mensaje de
// la base; 42501 → 401; P0429 → 429 con Retry-After; cualquier otra cosa → 503 (la base revirtió todo).
//
// La respuesta al celular es la misma para una llamada guardada, repetida o ignorada (propuesta #12):
// no delata si un número es de un lead. El celular abre la encuesta de F1 por número (decisión 4), que
// busca con la sesión del analista y solo en su cartera.
//
// Núcleo verificable sin red ni credenciales: las RPC llegan inyectadas desde index.ts.
// Nunca registra cabeceras, cuerpo ni la clave.

type Json = Record<string, unknown>;
export type ErrorRpc = { code?: unknown; message?: unknown; details?: unknown };
export type Dependencias = {
  /** Raíz del CRM, sin barra final (https://crm.miavance.com). */
  urlCrm: string;
  ingerir: (credencial: string, evento: unknown) => Promise<unknown>;
  registrarSalud: (credencial: string, latido: unknown) => Promise<unknown>;
};

const TOPE_BYTES = 4096;
const CREDENCIAL = /^[0-9a-f]{64}$/;

const esObjeto = (x: unknown): x is Json => typeof x === 'object' && x !== null && !Array.isArray(x);

/** La URL que abre el celular tras enviar: la encuesta de F1 por número (decisión 4); sin número, Mi día. */
export function urlAbrir(base: string, numero: unknown): string {
  const raiz = `${base.replace(/\/+$/, '')}/#/gestion-diaria`;
  return typeof numero === 'string' && numero.trim() !== ''
    ? `${raiz}/llamada/${encodeURIComponent(numero.trim())}`
    : raiz;
}

/** Los segundos que la base pide esperar (DETAIL «reintentar_en_seg=N»); 60 si no los dice. */
export function segundosDeEspera(detalle: unknown): number {
  const m = typeof detalle === 'string' ? /^reintentar_en_seg=(\d{1,6})$/.exec(detalle) : null;
  const n = m ? Number(m[1]) : Number.NaN;
  return Number.isInteger(n) && n >= 1 ? n : 60;
}

/** Lo que devolvió la RPC: aceptado, inválido con su mensaje (recortado) o null si no tiene la forma pactada. */
export function leerResultado(dato: unknown): { aceptado: true } | { aceptado: false; mensaje: string } | null {
  if (!esObjeto(dato)) return null;
  if (dato.resultado === 'aceptado') return { aceptado: true };
  if (dato.resultado === 'invalido') {
    return { aceptado: false, mensaje: typeof dato.mensaje === 'string' && dato.mensaje !== '' ? dato.mensaje.slice(0, 200) : 'Petición inválida' };
  }
  return null;
}

// Marcas que ningún JSON puede producir: cuerpo demasiado grande, cuerpo que no se pudo leer y cuerpo que no es JSON.
const GRANDE = Symbol('grande');
const ILEGIBLE = Symbol('ilegible');
const MAL_FORMADO = Symbol('mal formado');
async function leerJson(req: Request): Promise<unknown> {
  const partes: Uint8Array<ArrayBuffer>[] = [];
  let longitud = 0;
  try {
    const lector = req.body?.getReader();
    if (lector) for (;;) {
      const { done, value } = await lector.read();
      if (done) break;
      longitud += value.byteLength;
      if (longitud > TOPE_BYTES) { await lector.cancel(); return GRANDE; }
      partes.push(new Uint8Array(value));
    }
  } catch {
    // La conexión se cortó a mitad del cuerpo: es transporte, no contenido (revisión de Miguel, #190).
    return ILEGIBLE;
  }
  try {
    return JSON.parse(await new Blob(partes).text());
  } catch {
    return MAL_FORMADO;
  }
}

export function crearHandler(d: Dependencias) {
  return async (req: Request): Promise<Response> => {
    const respuesta = (estado: number, cuerpo: Json, extra: Record<string, string> = {}) =>
      new Response(JSON.stringify(cuerpo), {
        status: estado,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
      });
    // Una sola respuesta para todo problema de clave: no se distingue ausente, mal formada,
    // desconocida, revocada o de un analista de baja.
    const noAutorizado = () => respuesta(401, { error: 'No autorizado' });

    // Sin CORS: no la llama un navegador, la llama la macro del celular.
    if (req.method !== 'POST') return respuesta(405, { error: 'Método no admitido' }, { Allow: 'POST' });
    const tipo = (req.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
    if (tipo !== 'application/json') return respuesta(415, { error: 'El cuerpo debe ser JSON' });
    // La clave se mira antes que el cuerpo: sin una clave con forma válida no se revela nada más.
    const credencial = req.headers.get('x-celular-credencial') ?? '';
    if (!CREDENCIAL.test(credencial)) return noAutorizado();

    const cuerpo = await leerJson(req);
    if (cuerpo === GRANDE) return respuesta(413, { error: 'Petición demasiado grande' });
    // Un corte al leer es pasajero: 503 deja el aviso en la cola del celular para reintentar (un 400 lo apartaría).
    if (cuerpo === ILEGIBLE) return respuesta(503, { error: 'No se pudo leer la petición; vuelve a intentarlo' });

    // La puerta se elige por `accion`; un sobre que no es exactamente {accion, evento|latido} llega con la
    // carga en null y la base lo responde «invalido» (después de autenticar y gastar cupo).
    const esLatido = esObjeto(cuerpo) && cuerpo.accion === 'latido';
    const sobre = esObjeto(cuerpo) && Object.keys(cuerpo).length === 2 ? cuerpo : null;
    const carga = esLatido
      ? (sobre && 'latido' in sobre ? sobre.latido : null)
      : (sobre && sobre.accion === 'llamada' && 'evento' in sobre ? sobre.evento : null);

    try {
      const resultado = leerResultado(esLatido ? await d.registrarSalud(credencial, carga) : await d.ingerir(credencial, carga));
      if (resultado === null) return respuesta(503, { error: 'No se pudo guardar; vuelve a intentarlo' });
      if (!resultado.aceptado) return respuesta(400, { error: resultado.mensaje });
      if (esLatido) return respuesta(200, { registrado: true });
      // Guardada, repetida o ignorada: la misma respuesta (propuesta #12).
      return respuesta(202, { recibido: true, abrir: urlAbrir(d.urlCrm, esObjeto(carga) ? carga.numero : null) });
    } catch (error) {
      const e: ErrorRpc = esObjeto(error) ? error : {};
      if (e.code === '42501') return noAutorizado();
      if (e.code === 'P0429') {
        const espera = segundosDeEspera(e.details);
        return respuesta(429, { error: 'Demasiados envíos de este celular', reintentar_en_seg: espera },
          { 'Retry-After': String(espera) });
      }
      return respuesta(503, { error: 'No se pudo guardar; vuelve a intentarlo' });
    }
  };
}
