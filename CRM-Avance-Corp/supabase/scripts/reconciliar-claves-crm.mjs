// Reconciliacion excepcional de credenciales para identidades SOLO CRM.
// No modifica perfiles `analista` ni ninguna otra identidad compartida Portal.
// No envia correos: usa Auth Admin updateUserById({ password }).

import { createClient } from '@supabase/supabase-js';
import { spawnSync } from 'node:child_process';
import { clasificarCuentasCrm } from './reconciliar-claves-crm-core.mjs';

const HELP = `
Reconciliar claves de identidades exclusivas del CRM

Uso:
  node supabase/scripts/reconciliar-claves-crm.mjs --preflight
  node supabase/scripts/reconciliar-claves-crm.mjs --dry-run
  CRM_PASSWORD_RECONCILE_CONFIRM=SOLO_CRM_CLAVE_DOCUMENTO \\
  CRM_PASSWORD_RECONCILE_EXPECTED_COUNT=<conteo-del-dry-run> \\
    node supabase/scripts/reconciliar-claves-crm.mjs --apply

Modos:
  --preflight  Valida entorno y confirmaciones sin abrir conexion.
  --dry-run    Lee Auth/perfiles y muestra solo conteos; no cambia credenciales.
  --apply      Actualiza solo perfiles rol comercial con marca de origen CRM.
  --help       Muestra esta ayuda.

Variables requeridas:
  SUPABASE_URL o SUPABASE_PROJECT_REF
  SUPABASE_SERVICE_ROLE_KEY, o SUPABASE_PROJECT_REF + CLI autenticada

Variable opcional para cuentas creadas antes de app_metadata.origen_app:
  CRM_PASSWORD_RECONCILE_LEGACY_IDS=<UUIDs separados por coma, obtenidos del audit candidato_creado>

Guardas adicionales para --apply:
  CRM_PASSWORD_RECONCILE_CONFIRM=SOLO_CRM_CLAVE_DOCUMENTO
  CRM_PASSWORD_RECONCILE_EXPECTED_COUNT=<entero exacto obtenido en dry-run>
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
const confirmacion = process.env.CRM_PASSWORD_RECONCILE_CONFIRM?.trim();
const esperadoTexto = process.env.CRM_PASSWORD_RECONCILE_EXPECTED_COUNT?.trim();
const idsLegacyTexto = process.env.CRM_PASSWORD_RECONCILE_LEGACY_IDS?.trim() ?? '';

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
      fallar('Falta CRM_PASSWORD_RECONCILE_CONFIRM=SOLO_CRM_CLAVE_DOCUMENTO.');
    }
    if (!/^(0|[1-9][0-9]*)$/.test(esperadoTexto ?? '')) {
      fallar('CRM_PASSWORD_RECONCILE_EXPECTED_COUNT debe ser un entero no negativo.');
    }
  }

  return url;
}

function idsLegacyAuditados() {
  const ids = idsLegacyTexto
    ? idsLegacyTexto.split(',').map((id) => id.trim()).filter(Boolean)
    : [];
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (ids.some((id) => !uuid.test(id))) {
    fallar('CRM_PASSWORD_RECONCILE_LEGACY_IDS contiene un UUID invalido.');
  }
  return new Set(ids);
}

const destino = validarEntorno();
const idsLegacy = idsLegacyAuditados();
if (modo === '--preflight') {
  console.log('✓ entorno valido');
  console.log(`✓ destino: ${destino.host}`);
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

async function listarPerfilesComerciales() {
  const perfiles = [];
  for (let desde = 0; desde < 1_000_000; desde += 1000) {
    const data = await exigir(
      `listar perfiles comerciales desde ${desde}`,
      admin.schema('public').from('perfiles')
        .select('id,rol,tipo_documento,dni')
        .eq('rol', 'comercial')
        .range(desde, desde + 999),
    );
    const lote = data ?? [];
    perfiles.push(...lote);
    if (lote.length < 1000) return perfiles;
  }
  throw new Error('listar perfiles excedio el limite defensivo');
}

function imprimirResumen(resumen) {
  console.log(`Destino: ${destino.host}`);
  for (const [clave, valor] of Object.entries(resumen)) {
    console.log(`${clave}: ${valor}`);
  }
}

try {
  const [usuariosAuth, perfilesComerciales] = await Promise.all([
    listarUsuariosAuth(),
    listarPerfilesComerciales(),
  ]);
  const { candidatas, resumen } = clasificarCuentasCrm(
    usuariosAuth,
    perfilesComerciales,
    idsLegacy,
  );
  imprimirResumen(resumen);

  if (modo === '--dry-run') {
    console.log('DRY_RUN_OK: cero credenciales modificadas');
    process.exit(0);
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
      `actualizar credencial CRM ${actualizadas + 1}/${candidatas.length}`,
      admin.auth.admin.updateUserById(candidata.id, {
        password: candidata.documento,
        app_metadata: candidata.appMetadata,
      }),
    );
    actualizadas++;
  }
  console.log(`RECONCILIACION_OK: ${actualizadas} credenciales solo CRM actualizadas`);
} catch (error) {
  fallar(error instanceof Error ? error.message : 'Fallo inesperado');
}
