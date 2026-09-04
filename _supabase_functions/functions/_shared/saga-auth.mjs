// F2.b E2 — la SAGA de Auth vista desde los edges (crear-cliente, importar-clientes,
// crm-convertir-lead). Lógica PURA (sin red) para decidir qué paso toca según el estado
// que devuelve el servidor, y para verificar la marca del claim en un usuario de Auth.
// El servidor (crm.alta_cliente_identidad_fn / crm.saga_conversion_fn) es la verdad:
// aquí no se inventa estado, solo se interpreta.

/** Estados no terminales de la saga y el paso que le toca al edge en cada uno. */
export const PASO_POR_ESTADO = Object.freeze({
  reclamado: 'crear_auth',      // createUser (con app_metadata.claim_id) → registrar_auth
  auth_creado: 'crear_perfil',  // reutilizar el Auth marcado → INSERT perfil → perfil_creado
  perfil_creado: 'enlazar',     // enlazar / cerrar
  enlazado: 'listo',            // idempotente: ya está
});

/**
 * @param {unknown} respuesta  resultado JSON de reclamar/reservar
 * @returns {{ paso: string, claimId: string|null, token: string|null, version: number|null,
 *            estado: string, authUserId: string|null, perfilId: string|null, reanudar: boolean }}
 */
export function interpretarReclamo(respuesta) {
  const r = respuesta && typeof respuesta === 'object' && !Array.isArray(respuesta)
    ? /** @type {Record<string, unknown>} */ (respuesta) : {};
  const estado = typeof r.estado === 'string' ? r.estado : 'desconocido';
  const paso = estado === 'ya_existia' ? 'ya_existia' : (PASO_POR_ESTADO[estado] ?? 'desconocido');
  return {
    paso,
    estado,
    claimId: typeof r.claim_id === 'string' ? r.claim_id : null,
    token: typeof r.token === 'string' ? r.token : null,
    version: typeof r.version === 'number' ? r.version : null,
    authUserId: typeof r.auth_user_id === 'string' ? r.auth_user_id : null,
    perfilId: typeof r.perfil_id === 'string' ? r.perfil_id : null,
    reanudar: r.reanudar === true,
  };
}

/**
 * Un Auth SOLO se reutiliza si lleva la marca de ESTE claim (app_metadata.claim_id).
 * Un usuario hallado por correo sin esa marca no se adopta: revisión de Gerencia.
 * @param {unknown} user  usuario de Auth (admin API) o el JSON de crm.auth_usuario_por_correo_fn
 * @param {string} claimId
 */
export function authTieneMarca(user, claimId) {
  if (!user || typeof user !== 'object' || !claimId) return false;
  const u = /** @type {Record<string, unknown>} */ (user);
  const meta = u.app_metadata && typeof u.app_metadata === 'object'
    ? /** @type {Record<string, unknown>} */ (u.app_metadata) : null;
  const marca = meta ? meta.claim_id : u.claim_id;
  return typeof marca === 'string' && marca === claimId;
}

/** Mensaje de Auth que significa «ese correo ya existe». */
export function correoYaRegistrado(mensaje) {
  return /already been registered|already exists|already registered/i.test(String(mensaje ?? ''));
}

/**
 * Tras fallar el INSERT del perfil: ¿se compensa (borrar Auth + compensar_auth) o se sigue?
 * Solo se compensa por DATOS inválidos (23514) — Codex E2 #3. Un 23505 por `id` significa
 * que el perfil de ESTA saga ya existía (reintento): se sigue a perfil_creado. Un 23505 por
 * documento no debería ocurrir (reclamar lo habría devuelto como ya_existia): revisión.
 * @param {{ code?: string|null, message?: string|null }} error
 * @returns {'compensar'|'perfil_ya_existia'|'revision'|'error'}
 */
export function decidirTrasFalloPerfil(error) {
  const code = String(error?.code ?? '');
  const msg = String(error?.message ?? '');
  if (code === '23514') return 'compensar';
  if (code === '23505' && /perfiles_pkey|\(id\)/i.test(msg)) return 'perfil_ya_existia';
  if (code === '23505') return 'revision';
  return 'error';
}

/** Traduce un error de las RPC de la saga a un status HTTP. */
export function statusDeErrorSaga(error) {
  const code = String(error?.code ?? '');
  if (code === 'P0409' || code === '40001') return 409;
  if (code === 'P0429') return 409;
  if (code === '42501') return 403;
  if (code === '22023' || code === 'P0002') return 400;
  if (code === 'PGRST202') return 503; // función ausente: el servidor va primero; nunca degradar
  return 500;
}
