const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const origenes = new Set(['https://crm.miavance.com', 'https://www.crm.miavance.com']);
const buckets = new Set(['contratos-generados', 'documentos', 'f4-comprobantes']);
const fallo = (status, message) => Object.assign(new Error(message), { status });
const maxBytes = 20 * 1024 * 1024;

async function leerBytes(res, maximo) {
  if (!res.body) throw fallo(502, 'El documento está vacío.');
  const reader = res.body.getReader(), partes = [];
  let total = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximo) {await reader.cancel(); throw fallo(413, 'El contenido supera el tamaño permitido.');}
      partes.push(value);
    }
  } finally {reader.releaseLock();}
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const p of partes) {bytes.set(p, offset); offset += p.byteLength;}
  return bytes;
}
/** Proxy documental F5: la RPC verifica la identidad y el permiso vigente.
 * No firma URLs ni escribe archivos. La segunda lectura cierra el intervalo de
 * descarga ante reasignaciones. Los bytes del PDF publicado no se transforman. */
export function crearHandlerDocumentoInversion({supabaseUrl, anonKey, serviceKey, fetchImpl = fetch}) {
  const base = supabaseUrl.replace(/\/$/, '');
  return async req => {
    const origin = req.headers.get('Origin');
    const headers = {
      'Access-Control-Allow-Origin': origenes.has(origin) ? origin : 'https://crm.miavance.com',
      'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Expose-Headers': 'X-Document-Name, X-Document-Sha256',
      'Cache-Control': 'private, no-store', 'Vary': 'Origin', 'X-Content-Type-Options': 'nosniff',
    };
    const error = (status, message) => new Response(JSON.stringify({error: message}), {status,
      headers: {...headers, 'Content-Type': 'application/json'}});
    if (req.method === 'OPTIONS') return new Response(null, {status: 204, headers});
    if (req.method !== 'POST') return error(405, 'Usa POST para consultar el documento.');
    if (origin && !origenes.has(origin)) return error(403, 'Origen no autorizado.');
    const authorization = req.headers.get('Authorization');
    if (!/^Bearer \S+$/i.test(authorization ?? '')) return error(401, 'Inicia sesión para continuar.');
    try {
      let input;
      try {input = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(await leerBytes(req, 1024)));}
      catch (e) {if (e.status === 413) throw e; throw fallo(400, 'Solicitud documental inválida.');}
      if (!input || typeof input !== 'object' || Array.isArray(input)
        || Object.keys(input).length !== 3 || !['inversionista_id','fuente_id','documento_id'].every(k => uuid.test(input[k] ?? ''))) {
        return error(400, 'Solicitud documental inválida.');
      }
      const llamar = (ruta, init) => fetchImpl(`${base}${ruta}`, {...init, redirect: 'error', signal: AbortSignal.timeout(30000)});
      const auth = await llamar('/auth/v1/user', {headers: {apikey: anonKey, Authorization: authorization}});
      if (!auth.ok || !(await auth.json()).id) return error(401, 'La sesión ya no está vigente.');
      const descriptor = async () => {
        const r = await llamar('/rest/v1/rpc/inversionista_documento_fn', {
          method: 'POST', headers: {apikey: anonKey, Authorization: authorization, 'Content-Type': 'application/json',
            'Accept-Profile': 'crm', 'Content-Profile': 'crm'},
          body: JSON.stringify({p_inversionista: input.inversionista_id, p_fuente: input.fuente_id, p_documento: input.documento_id}),
        });
        if (!r.ok) throw fallo(r.status === 401 || r.status === 403 ? 403 : 409, 'El documento no está disponible con tu acceso actual.');
        const d = await r.json();
        if (!d) throw fallo(404, 'El documento no está disponible.');
        if (!buckets.has(d.bucket) || typeof d.ruta !== 'string' || !d.ruta || d.ruta.startsWith('/')
          || d.ruta.split('/').some(p => !p || p === '.' || p === '..') || /[\x00-\x1f\\]/.test(d.ruta)) {
          throw fallo(409, 'La ubicación del documento requiere revisión.');
        }
        return d;
      };
      const d = await descriptor();
      const objeto = await llamar(`/storage/v1/object/${d.bucket}/${d.ruta.split('/').map(encodeURIComponent).join('/')}`, {
        headers: {apikey: anonKey, Authorization: `Bearer ${serviceKey}`},
      });
      if (!objeto.ok) throw fallo(404, 'El archivo no está disponible.');
      const bytes = await leerBytes(objeto, maxBytes);
      if (!bytes.length) throw fallo(409, 'El archivo está vacío.');
      const sha = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
      if ((d.sha256 && d.sha256 !== sha) || (d.bytes != null && d.bytes !== bytes.length)) throw fallo(409, 'La integridad del documento requiere revisión.');
      const actual = await descriptor();
      if (JSON.stringify(actual) !== JSON.stringify(d)) throw fallo(409, 'El documento cambió. Vuelve a consultarlo.');
      const extension = d.ruta.match(/\.(pdf|jpe?g|png)$/i)?.[1]?.toLowerCase() ?? 'bin';
      const nombre = `${String(d.nombre ?? 'Documento').replace(/[\x00-\x1f\x7f/\\]/g, '_').slice(0,140).replace(/\.(pdf|jpe?g|png)$/i, '')}.${extension}`;
      return new Response(bytes, {headers: {...headers, 'Content-Type': 'application/octet-stream',
        'Content-Disposition': 'attachment', 'X-Document-Name': encodeURIComponent(nombre), 'X-Document-Sha256': sha}});
    } catch (e) {return error(e.status ?? 503, e.status ? e.message : 'No se pudo descargar el documento. Reintenta.');}
  };
}
