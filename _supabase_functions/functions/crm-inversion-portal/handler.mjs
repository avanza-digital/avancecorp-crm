import { claveTemporalDesdeDocumento } from '../_shared/documento.ts';
import { validarDomicilioLegal } from '../_shared/domicilio.mjs';
import { authTieneMarca, correoYaRegistrado, interpretarReclamo, statusDeErrorSaga } from '../_shared/saga-auth.mjs';

const origenesProduccion = new Set([
  'https://crm.miavance.com', 'https://www.crm.miavance.com',
  'https://miavance.com', 'https://www.miavance.com',
]);
const erroresPublicosRpc = new Set(['P0409', 'P0429', '22023', 'P0002', '42501']);
const errorPublico = (message, status) => Object.assign(new Error(message), { status, publico: true });

// Mismo límite en bytes con y sin Content-Length; no acumula cuerpos arbitrarios.
async function leerSolicitud(req) {
  const longitud = req.headers.get('Content-Length');
  if (longitud !== null && (!/^\d+$/.test(longitud) || !Number.isSafeInteger(Number(longitud)))) {
    throw errorPublico('Envía una solicitud JSON válida.', 400);
  }
  if (longitud !== null && Number(longitud) > 4096) throw errorPublico('Solicitud demasiado grande.', 400);
  if (!req.body) throw errorPublico('Envía una solicitud JSON válida.', 400);
  const reader = req.body.getReader(), chunks = [];
  let total = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > 4096) {
        await reader.cancel();
        throw errorPublico('Solicitud demasiado grande.', 400);
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
  catch { throw errorPublico('Envía una solicitud JSON válida.', 400); }
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/**
 * La misma función se usa en Deno y en el oráculo HTTP del banco. fetchImpl solo
 * permite observar/pérder respuestas reales en las pruebas; no inventa estados.
 * No envía correos. La clave inicial conserva la política actual del Portal.
 */
export function crearHandlerAccesoInversion({ supabaseUrl, anonKey, serviceKey, fetchImpl = fetch }) {
  const base = supabaseUrl.replace(/\/$/, '');
  return async function atender(req) {
    const origin = req.headers.get('Origin');
    const cors = {
      'Access-Control-Allow-Origin': origin && origenesProduccion.has(origin) ? origin : 'https://crm.miavance.com',
      'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Cache-Control': 'no-store', 'Vary': 'Origin', 'X-Content-Type-Options': 'nosniff',
    };
    const respuesta = (status, body) => new Response(JSON.stringify(body), {
      status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' },
    });
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return respuesta(405, { error: 'Usa POST para completar el acceso.' });
    const authorization = req.headers.get('Authorization');
    if (!authorization?.match(/^Bearer \S+$/i)) return respuesta(401, { error: 'Inicia sesión para continuar.' });
    let solicitud;
    let tokenRecuperacion;
    try {
      solicitud = await leerSolicitud(req);
      if (!solicitud || typeof solicitud !== 'object' || Array.isArray(solicitud)
        || Object.keys(solicitud).some(k => !['solicitud_id', 'token'].includes(k))
        || typeof solicitud.solicitud_id !== 'string' || !uuid.test(solicitud.solicitud_id)
        || (solicitud.token != null && (typeof solicitud.token !== 'string' || !/^[a-f0-9]{48}$/.test(solicitud.token)))) {
        return respuesta(400, { error: 'Identificador o token de solicitud inválido.' });
      }
      tokenRecuperacion = solicitud.token ?? undefined;
      async function llamar(ruta, { admin = false, method = 'POST', body, crm = false } = {}) {
        const res = await fetchImpl(`${base}${ruta}`, {
          method, signal: AbortSignal.timeout(25_000),
          headers: {
            apikey: anonKey, Authorization: admin ? `Bearer ${serviceKey}` : authorization,
            'Content-Type': 'application/json',
            ...(crm ? { 'Accept-Profile': 'crm', 'Content-Profile': 'crm' } : {}),
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        });
        const data = await res.json();
        if (!res.ok) {
          const error = new Error(data.message ?? data.msg ?? data.error_description ?? 'No se pudo completar el acceso.');
          error.code = data.code ?? data.error_code;
          error.status = crm ? statusDeErrorSaga(error) : (res.status === 401 || res.status === 403 ? 401 : 409);
          error.publico = crm && erroresPublicosRpc.has(error.code);
          throw error;
        }
        return data;
      }
      const usuario = await llamar('/auth/v1/user', { method: 'GET' });
      if (!usuario?.id) return respuesta(401, { error: 'La sesión no está vigente.' });
      const paso = (nombre, payload = {}) => llamar('/rest/v1/rpc/acceso_inversion_fn', {
        crm: true, body: { p_solicitud: solicitud.solicitud_id, p_paso: nombre, p_payload: payload },
      });
      let reclamo = await paso('reclamar', tokenRecuperacion ? { token: tokenRecuperacion } : {});
      let estado = interpretarReclamo(reclamo);
      if (estado.paso === 'listo') return respuesta(200, {
        ok: true, solicitud_id: solicitud.solicitud_id, perfil_id: estado.perfilId, reintento: true,
      });
      if (!estado.claimId || !estado.token || !estado.version || estado.paso === 'desconocido') {
        throw new Error('El servidor devolvió un estado de acceso incompleto.');
      }
      tokenRecuperacion = estado.token;
      const datos = reclamo.datos_portal;
      const domicilio = validarDomicilioLegal(datos?.domicilio);
      if (!domicilio.ok) throw errorPublico(domicilio.error, 400);
      const contextoPaso = () => ({ token: tokenRecuperacion, version: estado.version });
      const comprobarUsuario = user => {
        if (!authTieneMarca(user, estado.claimId) || user.email?.toLowerCase() !== datos.correo) {
          throw errorPublico('Ese acceso no pertenece a esta solicitud; requiere revisión.', 409);
        }
        return user;
      };
      if (estado.paso === 'crear_auth') {
        let auth;
        try {
          auth = await llamar('/auth/v1/admin/users', {
            admin: true, body: {
              email: datos.correo, password: claveTemporalDesdeDocumento(reclamo.documento), email_confirm: true,
              app_metadata: { claim_id: estado.claimId },
            },
          });
        } catch (error) {
          if (error.code !== 'email_exists' && !correoYaRegistrado(error.message)) throw error;
          const encontrado = await llamar('/rest/v1/rpc/auth_usuario_por_correo_fn', {
            admin: true, crm: true, body: { p_correo: datos.correo },
          });
          if (!encontrado.id || !authTieneMarca(encontrado, estado.claimId)) {
            throw errorPublico('El correo ya pertenece a otro acceso; requiere revisión de Gerencia.', 409);
          }
          auth = await llamar(`/auth/v1/admin/users/${encontrado.id}`, { admin: true, method: 'GET' });
        }
        comprobarUsuario(auth);
        reclamo = await paso('registrar_auth', { ...contextoPaso(), auth_user_id: auth.id });
        estado = interpretarReclamo(reclamo);
      }
      if (estado.paso === 'crear_perfil') {
        const auth = await llamar(`/auth/v1/admin/users/${estado.authUserId}`, { admin: true, method: 'GET' });
        comprobarUsuario(auth);
        reclamo = await paso('crear_perfil', contextoPaso());
        estado = interpretarReclamo(reclamo);
      }
      if (estado.paso === 'enlazar') {
        reclamo = await paso('enlazar', contextoPaso());
        estado = interpretarReclamo(reclamo);
      }
      if (estado.paso !== 'listo' || !estado.perfilId) throw new Error('El acceso sigue pendiente de completar.');
      return respuesta(200, { ok: true, solicitud_id: solicitud.solicitud_id, perfil_id: estado.perfilId, reintento: false });
    } catch (error) {
      return respuesta(error.status ?? 503, {
        error: error.publico === true ? error.message : 'No se pudo completar el acceso. Retoma esta misma solicitud.',
        ...(solicitud?.solicitud_id ? { solicitud_id: solicitud.solicitud_id } : {}),
        ...(tokenRecuperacion ? { token: tokenRecuperacion } : {}),
      });
    }
  };
}
