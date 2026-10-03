// crm-llamadas-ingesta — recibe del celular corporativo el aviso de cada llamada y su latido de salud.
//
// Seguridad (F3, decisión 1 provisional de Jhosep, 01/10/2026): se despliega con verify_jwt=false
// porque MacroDroid no tiene sesión de usuario. El control es la CLAVE DEL CELULAR, que viaja en la
// cabecera x-celular-credencial (nunca en la URL). La base solo guarda su sha256 y la valida en una
// RPC que solo puede llamar service_role; cualquier problema de clave responde el MISMO 401.
// Cuerpo ≤ 4 KB leído por partes, esquema estricto y límite por celular en la base (P0429 → 429 con
// Retry-After).
//
// La respuesta al celular es la misma para una llamada guardada, repetida o ignorada (propuesta #12):
// no delata si un número es de un lead. El celular abre siempre la encuesta de F1 por número
// (decisión 4), que busca con la sesión del analista y solo en su cartera.
//
// Núcleo verificable sin red ni credenciales: las RPC llegan inyectadas desde index.ts.
// Nunca registra cabeceras, cuerpo ni la clave.

type Json = Record<string, unknown>;
export type ErrorRpc = { code?: unknown; message?: unknown; details?: unknown };
export type Dependencias = {
  /** Raíz del CRM, sin barra final (https://crm.miavance.com). */
  urlCrm: string;
  ingerir: (credencial: string, evento: Json) => Promise<unknown>;
  registrarSalud: (credencial: string, latido: Json) => Promise<unknown>;
};

const TOPE_BYTES = 4096;
const CREDENCIAL = /^[0-9a-f]{64}$/;
const ORIGEN = /^[A-Za-z0-9._:+-]{4,120}$/;
const VERSION_MACRO = /^[A-Za-z0-9._ -]{1,40}$/;
const CLAVES_EVENTO = new Set(['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico', 'duracion_seg', 'ocurrio_en']);
const CLAVES_LATIDO = new Set(['v', 'version_macro', 'en_cola', 'ocurrio_en']);
const DIRECCIONES = new Set(['saliente', 'entrante', 'desconocida']);
const ESTADOS = new Set(['conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido']);

const esObjeto = (x: unknown): x is Json => typeof x === 'object' && x !== null && !Array.isArray(x);
const opcional = (x: unknown, valido: (v: unknown) => boolean) => x === undefined || x === null || valido(x);
const entero = (x: unknown, minimo: number, maximo: number) =>
  typeof x === 'number' && Number.isInteger(x) && x >= minimo && x <= maximo;
const fecha = (x: unknown) => typeof x === 'string' && x.length <= 40 && !Number.isNaN(Date.parse(x));

/** El mismo contrato v1 que valida la base (private.llamada_celular_ingerir): claves exactas. */
export function eventoValido(e: unknown): e is Json {
  if (!esObjeto(e) || Object.keys(e).some((k) => !CLAVES_EVENTO.has(k))) return false;
  return e.v === 1
    && typeof e.evento_origen_id === 'string' && ORIGEN.test(e.evento_origen_id)
    && opcional(e.numero, (n) => typeof n === 'string' && n.length <= 40)
    && opcional(e.direccion, (d) => typeof d === 'string' && DIRECCIONES.has(d))
    && opcional(e.estado_tecnico, (s) => typeof s === 'string' && ESTADOS.has(s))
    && opcional(e.duracion_seg, (d) => entero(d, 0, 86400))
    && opcional(e.ocurrio_en, fecha);
}

/** El latido v1 de private.celular_registrar_salud: versión de la macro y cola obligatorias. */
export function latidoValido(l: unknown): l is Json {
  if (!esObjeto(l) || Object.keys(l).some((k) => !CLAVES_LATIDO.has(k))) return false;
  return l.v === 1
    && typeof l.version_macro === 'string' && VERSION_MACRO.test(l.version_macro)
    && entero(l.en_cola, 0, 100000)
    && opcional(l.ocurrio_en, fecha);
}

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

// Marca de «cuerpo demasiado grande»: un símbolo, que ningún JSON puede producir.
const GRANDE = Symbol('grande');
async function leerJson(req: Request): Promise<unknown> {
  const lector = req.body?.getReader();
  const partes: Uint8Array<ArrayBuffer>[] = [];
  let longitud = 0;
  if (lector) for (;;) {
    const { done, value } = await lector.read();
    if (done) break;
    longitud += value.byteLength;
    if (longitud > TOPE_BYTES) { await lector.cancel(); return GRANDE; }
    partes.push(new Uint8Array(value));
  }
  return JSON.parse(await new Blob(partes).text());
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

    let cuerpo: unknown;
    try {
      cuerpo = await leerJson(req);
    } catch {
      return respuesta(400, { error: 'Petición inválida' });
    }
    if (cuerpo === GRANDE) return respuesta(413, { error: 'Petición demasiado grande' });
    if (!esObjeto(cuerpo) || Object.keys(cuerpo).length !== 2) return respuesta(400, { error: 'Petición inválida' });
    const llamada = cuerpo.accion === 'llamada' && eventoValido(cuerpo.evento);
    const latido = cuerpo.accion === 'latido' && latidoValido(cuerpo.latido);
    if (!llamada && !latido) return respuesta(400, { error: 'Petición inválida' });

    try {
      if (llamada) {
        const evento = cuerpo.evento as Json;
        await d.ingerir(credencial, evento);
        // Guardada, repetida o ignorada: la misma respuesta (propuesta #12).
        return respuesta(202, { recibido: true, abrir: urlAbrir(d.urlCrm, evento.numero) });
      }
      await d.registrarSalud(credencial, cuerpo.latido as Json);
      return respuesta(200, { registrado: true });
    } catch (error) {
      const e: ErrorRpc = esObjeto(error) ? error : {};
      if (e.code === '42501') return noAutorizado();
      if (e.code === 'P0429') {
        const espera = segundosDeEspera(e.details);
        return respuesta(429, { error: 'Demasiados envíos de este celular', reintentar_en_seg: espera },
          { 'Retry-After': String(espera) });
      }
      if (e.code === 'P0409') return respuesta(409, { error: 'Esta llamada ya llegó con otro contenido' });
      // Los 22023 de la base son mensajes escritos para quien arma la macro: se devuelven tal cual.
      if (e.code === '22023') {
        return respuesta(400, { error: typeof e.message === 'string' ? e.message.slice(0, 200) : 'Petición inválida' });
      }
      return respuesta(503, { error: 'No se pudo guardar; vuelve a intentarlo' });
    }
  };
}
