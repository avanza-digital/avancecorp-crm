// Cambio de dominio de correo (@cacmascapital.com -> @groupmascapital.com) para
// identidades CRM (rol_crm activo en crm.equipo) y administrativas (perfiles.rol
// admin/superadmin). NO toca cliente/analista/directorio ni cuentas ya migradas.
// Operacion de una sola vez: mantiene actualizado_en, no crea abstracciones extra.
// Actualiza auth.users.email (email_confirm=true, sin correo de verificacion) y
// public.perfiles.correo en el mismo paso por usuario.

import { createClient } from '@supabase/supabase-js';
import { spawnSync } from 'node:child_process';

const DOMINIO_ANTERIOR = '@cacmascapital.com';
const DOMINIO_NUEVO = '@groupmascapital.com';
const ROLES_CRM_ACTIVOS = new Set(['vendedor', 'supervisor', 'gerencia', 'coordinador']);
const ROLES_ADMINISTRATIVOS = new Set(['admin', 'superadmin']);

const HELP = `
Cambiar dominio de correo: identidades CRM + administrativas

Uso:
  node supabase/scripts/cambiar-dominio-correo-crm.mjs --preflight
  node supabase/scripts/cambiar-dominio-correo-crm.mjs --dry-run
  CAMBIO_DOMINIO_CONFIRM=SOLO_CRM_CLAVE_DOCUMENTO \\
  CAMBIO_DOMINIO_EXPECTED_COUNT=<conteo-del-dry-run> \\
    node supabase/scripts/cambiar-dominio-correo-crm.mjs --apply

Modos:
  --preflight  Valida entorno y confirmaciones sin abrir conexion.
  --dry-run    Lista candidatas (correo actual -> nuevo) sin cambiar nada.
  --apply      Actualiza auth.users.email y public.perfiles.correo por candidata.
  --help       Muestra esta ayuda.

Variables requeridas:
  SUPABASE_URL o SUPABASE_PROJECT_REF
  SUPABASE_SERVICE_ROLE_KEY, o SUPABASE_PROJECT_REF + CLI autenticada

Guardas adicionales para --apply:
  CAMBIO_DOMINIO_CONFIRM=SOLO_CRM_CLAVE_DOCUMENTO
  CAMBIO_DOMINIO_EXPECTED_COUNT=<entero exacto obtenido en dry-run>
`;

const args = new Set(process.argv.slice(2));
const permitidos = new Set(['--help', '-h', '--preflight', '--dry-run', '--apply']);
const desconocidos = [...args].filter((arg) => !permitidos.has(arg));
if (desconocidos.length > 0) {
  console.error(`Opciones desconocidas: ${desconocidos.join(', ')}`);
  process.exit(2);
}

if (args.has('--help') || args.has('-h')) {
  console.log(HELP.trim());
  process.exit(0);
}

const modos = ['--preflight', '--dry-run', '--apply'].filter((modo) => args.has(modo));
if (modos.length !== 1) {
  console.error('Selecciona exactamente un modo: --preflight, --dry-run o --apply.');
  process.exit(2);
}

const modo = modos[0];
const projectRef = process.env.SUPABASE_PROJECT_REF?.trim();
const supabaseUrl = process.env.SUPABASE_URL?.trim()
  || (projectRef ? `https://${projectRef}.supabase.co` : undefined);
const serviceKeyEntorno = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const supabaseCli = process.env.SUPABASE_CLI_BIN?.trim() || 'supabase';
const confirmacion = process.env.CAMBIO_DOMINIO_CONFIRM?.trim();
const esperadoTexto = process.env.CAMBIO_DOMINIO_EXPECTED_COUNT?.trim();

function fallar(mensaje) {
  console.error(`✗ ${mensaje}`);
  process.exit(1);
}

function validarEntorno() {
  if (!supabaseUrl) fallar('Falta SUPABASE_URL.');
  if (!serviceKeyEntorno && !projectRef) {
    fallar('Falta SUPABASE_SERVICE_ROLE_KEY o SUPABASE_PROJECT_REF para usar la CLI autenticada.');
  }

  let url;
  try {
    url = new URL(supabaseUrl);
  } catch {
    fallar('SUPABASE_URL no es una URL valida.');
  }
  const loopback = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);
  if (url.protocol !== 'https:'
      && !(url.protocol === 'http:' && loopback.has(url.hostname))) {
    fallar('SUPABASE_URL debe usar HTTPS; HTTP solo se permite en loopback.');
  }
  if (url.username || url.password || url.search || url.hash) {
    fallar('SUPABASE_URL no debe contener credenciales ni parametros.');
  }

  if (modo === '--apply') {
    if (confirmacion !== 'SOLO_CRM_CLAVE_DOCUMENTO') {
      fallar('Falta CAMBIO_DOMINIO_CONFIRM=SOLO_CRM_CLAVE_DOCUMENTO.');
    }
    if (!/^(0|[1-9][0-9]*)$/.test(esperadoTexto ?? '')) {
      fallar('CAMBIO_DOMINIO_EXPECTED_COUNT debe ser un entero no negativo.');
    }
  }

  return url;
}

const destino = validarEntorno();
if (modo === '--preflight') {
  console.log('✓ entorno valido');
  console.log(`✓ destino: ${destino.host}`);
  console.log(`✓ dominio anterior: ${DOMINIO_ANTERIOR}`);
  console.log(`✓ dominio nuevo: ${DOMINIO_NUEVO}`);
  console.log('✓ preflight terminado sin crear cliente ni abrir conexion');
  process.exit(0);
}

function obtenerServiceKey() {
  if (serviceKeyEntorno) return serviceKeyEntorno;
  const resultado = spawnSync(supabaseCli, [
    'projects',
    'api-keys',
    '--project-ref',
    projectRef,
    '--reveal',
    '--output',
    'json',
  ], {
    encoding: 'utf8',
    timeout: 30_000,
    maxBuffer: 2 * 1024 * 1024,
  });
  if (resultado.error || resultado.status !== 0) {
    fallar('No se pudo obtener una key administrativa desde la CLI autenticada.');
  }
  let payload;
  try {
    payload = JSON.parse(resultado.stdout);
  } catch {
    fallar('La CLI no devolvio un contrato JSON reconocido para las API keys.');
  }
  const filas = Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.keys)
      ? payload.keys
      : [];
  const fila = filas.find((item) =>
    item?.name === 'service_role'
    || item?.type === 'secret'
    || String(item?.api_key ?? item?.key ?? '').startsWith('sb_secret_'));
  const key = fila?.api_key ?? fila?.key ?? fila?.value;
  if (typeof key !== 'string' || key.length < 20) {
    fallar('La CLI no devolvio una key administrativa utilizable.');
  }
  return key;
}

const admin = createClient(supabaseUrl, obtenerServiceKey(), {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
});

async function exigir(etiqueta, promesa) {
  let respuesta;
  try {
    respuesta = await promesa;
  } catch {
    throw new Error(`${etiqueta}: fallo de red`);
  }
  if (respuesta.error) {
    throw new Error(`${etiqueta}: operacion rechazada`);
  }
  return respuesta.data;
}

async function listarUsuariosAuth() {
  const usuarios = [];
  for (let pagina = 1; pagina <= 1000; pagina++) {
    const data = await exigir(
      `listar Auth pagina ${pagina}`,
      admin.auth.admin.listUsers({ page: pagina, perPage: 1000 }),
    );
    const lote = data.users ?? [];
    usuarios.push(...lote);
    if (lote.length < 1000) return usuarios;
  }
  throw new Error('listar Auth excedio el limite defensivo de paginas');
}

async function listarPerfilesDominioAnterior() {
  const perfiles = [];
  for (let desde = 0; desde < 1_000_000; desde += 1000) {
    const data = await exigir(
      `listar perfiles dominio anterior desde ${desde}`,
      admin.schema('public').from('perfiles')
        .select('id,correo,rol,activo')
        .ilike('correo', `%${DOMINIO_ANTERIOR}`)
        .range(desde, desde + 999),
    );
    const lote = data ?? [];
    perfiles.push(...lote);
    if (lote.length < 1000) return perfiles;
  }
  throw new Error('listar perfiles excedio el limite defensivo');
}

async function listarEquipoCrm() {
  const equipo = [];
  for (let desde = 0; desde < 1_000_000; desde += 1000) {
    const data = await exigir(
      `listar crm.equipo desde ${desde}`,
      admin.schema('crm').from('equipo')
        .select('perfil_id,rol_crm,activo')
        .range(desde, desde + 999),
    );
    const lote = data ?? [];
    equipo.push(...lote);
    if (lote.length < 1000) return equipo;
  }
  throw new Error('listar crm.equipo excedio el limite defensivo');
}

function esElegible(perfil, equipoPorId) {
  if (!perfil.activo) return false;
  if (ROLES_ADMINISTRATIVOS.has(perfil.rol)) return true;
  const membresia = equipoPorId.get(perfil.id);
  return Boolean(membresia?.activo && ROLES_CRM_ACTIVOS.has(membresia.rol_crm));
}

function calcularNuevoCorreo(correoActual) {
  const local = correoActual.slice(0, correoActual.toLowerCase().lastIndexOf(DOMINIO_ANTERIOR));
  return `${local}${DOMINIO_NUEVO}`.toLowerCase();
}

try {
  const [usuariosAuth, perfilesDominioAnterior, equipoCrm] = await Promise.all([
    listarUsuariosAuth(),
    listarPerfilesDominioAnterior(),
    listarEquipoCrm(),
  ]);

  const authPorId = new Map(usuariosAuth.map((usuario) => [usuario.id, usuario]));
  const equipoPorId = new Map(equipoCrm.map((fila) => [fila.perfil_id, fila]));
  const correosAuthMinuscula = new Set(
    usuariosAuth.map((usuario) => String(usuario.email ?? '').toLowerCase()).filter(Boolean),
  );

  const candidatas = [];
  let sinAuth = 0;
  let noElegible = 0;
  let correoAuthDesalineado = 0;

  for (const perfil of perfilesDominioAnterior) {
    if (!esElegible(perfil, equipoPorId)) {
      noElegible++;
      continue;
    }
    const usuario = authPorId.get(perfil.id);
    if (!usuario) {
      sinAuth++;
      continue;
    }
    if (String(usuario.email ?? '').toLowerCase() !== perfil.correo.toLowerCase()) {
      correoAuthDesalineado++;
      continue;
    }
    candidatas.push({
      id: perfil.id,
      rol: perfil.rol,
      correoActual: perfil.correo.toLowerCase(),
      correoNuevo: calcularNuevoCorreo(perfil.correo),
    });
  }

  const nuevosCorreos = new Map();
  const colisiones = [];
  for (const candidata of candidatas) {
    if (correosAuthMinuscula.has(candidata.correoNuevo)) {
      colisiones.push(`${candidata.correoNuevo} (ya existe en Auth)`);
    }
    if (nuevosCorreos.has(candidata.correoNuevo)) {
      colisiones.push(`${candidata.correoNuevo} (duplicado dentro del lote)`);
    }
    nuevosCorreos.set(candidata.correoNuevo, candidata.id);
  }

  console.log(`Destino: ${destino.host}`);
  console.log(`perfiles_dominio_anterior: ${perfilesDominioAnterior.length}`);
  console.log(`elegibles: ${candidatas.length}`);
  console.log(`no_elegibles_por_rol_o_inactivo: ${noElegible}`);
  console.log(`sin_auth: ${sinAuth}`);
  console.log(`correo_auth_desalineado_de_perfil: ${correoAuthDesalineado}`);
  console.log(`colisiones_de_correo_nuevo: ${colisiones.length}`);
  for (const candidata of candidatas) {
    console.log(`  ${candidata.rol}: ${candidata.correoActual} -> ${candidata.correoNuevo}`);
  }
  if (colisiones.length > 0) {
    console.log('Colisiones detectadas:');
    for (const colision of colisiones) console.log(`  ${colision}`);
  }

  if (modo === '--dry-run') {
    console.log('DRY_RUN_OK: cero correos modificados');
    process.exit(0);
  }

  if (colisiones.length > 0) {
    fallar('Hay colisiones de correo nuevo sin resolver. Corrige antes de --apply.');
  }

  const esperado = Number(esperadoTexto);
  if (candidatas.length !== esperado) {
    fallar(
      `El conteo elegible cambio: esperado=${esperado}, actual=${candidatas.length}. `
      + 'Ejecuta nuevamente --dry-run.',
    );
  }

  let actualizadas = 0;
  for (const candidata of candidatas) {
    await exigir(
      `actualizar Auth ${actualizadas + 1}/${candidatas.length}`,
      admin.auth.admin.updateUserById(candidata.id, {
        email: candidata.correoNuevo,
        email_confirm: true,
      }),
    );
    await exigir(
      `actualizar perfiles ${actualizadas + 1}/${candidatas.length}`,
      admin.schema('public').from('perfiles')
        .update({ correo: candidata.correoNuevo, actualizado_en: new Date().toISOString() })
        .eq('id', candidata.id),
    );
    actualizadas++;
    console.log(`✓ ${candidata.correoActual} -> ${candidata.correoNuevo}`);
  }
  console.log(`CAMBIO_DOMINIO_OK: ${actualizadas} correos actualizados`);
} catch (error) {
  fallar(error instanceof Error ? error.message : 'Fallo inesperado');
}
