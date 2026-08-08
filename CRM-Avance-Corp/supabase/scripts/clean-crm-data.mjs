// Limpieza controlada del dataset del CRM (branch/staging).
//
// Uso:
//   # 1) preflight sin tocar datos
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node supabase/scripts/clean-crm-data.mjs --preflight
//
//   # 2) limpieza con confirmación estricta
//   CRM_CLEAN_CONFIRM=QUIERO_BORRAR_TODOS_LOS_DATOS \
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node supabase/scripts/clean-crm-data.mjs
//
// Opciones:
//   --preflight            Valida entorno y destino permitido sin conexiones de datos.
//   --dry-run              Muestra conteos previos y no ejecuta DELETE.
//   --preserve-equipo      Mantiene crm.equipo (por defecto se borra en limpieza normal).
//   --preserve-reference    Mantiene enfriamiento, cuentas bancarias y sus enlaces con contratos.
//   --help                 Muestra esta ayuda.
//
// Restricciones de seguridad:
//   * NUNCA corre sobre producción: se rechaza si la URL contiene `dctqcbznekcyxhjujuci`.
//   * Requiere confirmación explícita por variable `CRM_CLEAN_CONFIRM=QUIERO_BORRAR_TODOS_LOS_DATOS`
//     (salvo preflight/dry-run).
//   * WIP: dry-run y limpieza efectiva permanecen bloqueados hasta resolver el
//     ledger append-only crm.lead_asignaciones con una operación transaccional.

import { createClient } from '@supabase/supabase-js';
import { PRODUCTION_PROJECT_REF } from './fixtures.mjs';

const HELP = `
Limpieza controlada de datos del CRM en branch/staging.

Uso:
  node supabase/scripts/clean-crm-data.mjs [opciones]

Opciones:
  --preflight            Valida entorno y destino permitido sin tocar datos.
  --dry-run              Muestra conteos y no ejecuta DELETE.
  --preserve-equipo      Mantiene crm.equipo (sin borrar estructura de roles).
  --preserve-reference    Mantiene enfriamiento, cuentas bancarias y sus enlaces con contratos.
  --help                 Muestra esta ayuda.

Variables requeridas para limpieza:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Variables requeridas para ejecución real (excepto preflight/dry-run):
  CRM_CLEAN_CONFIRM = QUIERO_BORRAR_TODOS_LOS_DATOS

Estado actual:
  Solo --help y --preflight están habilitados. Dry-run y limpieza efectiva
  abortan antes de crear el cliente mientras siga pendiente el ledger append-only.
`;

const args = new Set(process.argv.slice(2));
const allowedArgs = new Set([
  '--help',
  '-h',
  '--preflight',
  '--dry-run',
  '--preserve-equipo',
  '--preserve-reference',
]);
const unknownArgs = [...args].filter((arg) => !allowedArgs.has(arg));
if (unknownArgs.length > 0) {
  console.error(`Opciones desconocidas: ${unknownArgs.join(', ')}`);
  console.error('Usa --help para ver las opciones disponibles.');
  process.exit(2);
}

if (args.has('--help') || args.has('-h')) {
  console.log(HELP.trim());
  process.exit(0);
}

if (args.has('--preflight') && args.has('--dry-run')) {
  console.error('Las opciones --preflight y --dry-run son mutuamente excluyentes.');
  process.exit(2);
}

const SUPABASE_URL = process.env.SUPABASE_URL?.trim();
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

const isPreflight = args.has('--preflight');
const isDryRun = args.has('--dry-run');
const preserveEquipo = args.has('--preserve-equipo');
const preserveReference = args.has('--preserve-reference');
const needsConfirmation = !(isPreflight || isDryRun);
const confirmation = process.env.CRM_CLEAN_CONFIRM?.trim();

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

function validateNode() {
  const [major, minor] = process.versions.node.split('.').map(Number);
  if (major < 22 || (major === 22 && minor < 12)) {
    fail(`Node ${process.versions.node} no es compatible; se requiere >=22.12.0.`);
  }
}

function validateEnvironment() {
  if (!SUPABASE_URL) fail('Falta SUPABASE_URL.');
  if (!SERVICE_KEY) fail('Falta SUPABASE_SERVICE_ROLE_KEY.');
  if (needsConfirmation && confirmation !== 'QUIERO_BORRAR_TODOS_LOS_DATOS') {
    fail(
      'Falta confirmación explícita: '
      + 'usa CRM_CLEAN_CONFIRM=QUIERO_BORRAR_TODOS_LOS_DATOS.',
    );
  }

  let parsed;
  try {
    parsed = new URL(SUPABASE_URL);
  } catch {
    fail('SUPABASE_URL no es una URL valida.');
  }
  const loopbackHosts = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);
  if (parsed.protocol !== 'https:'
      && !(parsed.protocol === 'http:' && loopbackHosts.has(parsed.hostname))) {
    fail('SUPABASE_URL debe usar HTTPS; HTTP solo se permite en localhost/loopback.');
  }
  if (parsed.username || parsed.password) {
    fail('SUPABASE_URL no debe incluir credenciales.');
  }
  if (SUPABASE_URL.includes(PRODUCTION_PROJECT_REF)) {
    fail('Destino de PRODUCCION detectado. Este script solo corre en branch/staging.');
  }
}

function validateOperationalGate() {
  if (isPreflight) return;
  fail(
    'Ejecución deshabilitada: crm.lead_asignaciones veta DELETE mediante un trigger '
    + 'append-only. Define y prueba primero una limpieza transaccional en una base desechable.',
  );
}

function formatTableLabel(prefix) {
  return `${prefix.schema}.${prefix.table}`;
}

function pkSentinel(pkType) {
  return pkType === 'uuid'
    ? '00000000-0000-0000-0000-000000000000'
    : '__CRM_CLEAN_SENTINEL__';
}

function printPlan() {
  const targets = getTargets();
  const mode = isPreflight
    ? 'PREFLIGHT SIN RED'
    : (isDryRun ? 'DRY-RUN' : 'LIMPIEZA EFECTIVA');
  console.log('✓ runtime y variables validos');
  console.log(`✓ destino permitido: ${new URL(SUPABASE_URL).host}`);
  console.log(`✓ modo: ${mode}`);
  for (const target of targets) {
    console.log(`  - ${formatTableLabel(target)}`);
  }
  console.log(
    needsConfirmation
      ? '✓ seguridad: confirmación destructiva validada; producción bloqueada.'
      : '✓ seguridad: modo sin borrado; producción bloqueada.',
  );
}

function getTargets() {
  const hardTargets = [
    { schema: 'crm', table: 'tareas', pk: 'id', pkType: 'uuid' },
    { schema: 'crm', table: 'lead_asignaciones', pk: 'id', pkType: 'uuid' },
    { schema: 'crm', table: 'actividades', pk: 'id', pkType: 'uuid' },
    { schema: 'crm', table: 'contrato_cuentas_pago', pk: 'id', pkType: 'uuid' },
    { schema: 'crm', table: 'cuentas_bancarias', pk: 'id', pkType: 'uuid' },
    { schema: 'crm', table: 'agenda_ics', pk: 'perfil_id', pkType: 'uuid' },
    { schema: 'crm', table: 'objetivos_vendedores', pk: 'id', pkType: 'uuid' },
    { schema: 'crm', table: 'objetivos', pk: 'id', pkType: 'uuid' },
    { schema: 'crm', table: 'enfriamiento_politica', pk: 'motivo', pkType: 'text' },
    { schema: 'crm', table: 'leads', pk: 'id', pkType: 'uuid' },
  ];

  const optionalTargets = [
    { schema: 'crm', table: 'equipo', pk: 'perfil_id', pkType: 'uuid' },
  ];

  const referenceTables = new Set([
    'enfriamiento_politica',
    'cuentas_bancarias',
    'contrato_cuentas_pago',
  ]);
  const baseTargets = hardTargets.filter(
    (target) => !(preserveReference && referenceTables.has(target.table)),
  );

  const team = (!preserveEquipo) ? optionalTargets : [];
  return [...baseTargets, ...team];
}

async function requireResponse(label, promise) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    fail(`${label}: ${error?.message ?? String(error)}`);
  }
  if (response.error) {
    fail(`${label}: ${response.error.message}`,);
  }
  return response;
}

async function countRows(client, target) {
  const { count, error } = await client
    .schema(target.schema)
    .from(target.table)
    .select(`${target.pk}`, { count: 'exact', head: true });

  if (error) {
    fail(`${formatTableLabel(target)}: no se pudo contar filas (${error.message}).`);
  }

  return count ?? 0;
}

async function deleteRows(client, target) {
  const { count, error } = await client
    .schema(target.schema)
    .from(target.table)
    .delete({ count: 'exact' })
    .neq(target.pk, pkSentinel(target.pkType));

  if (error) {
    fail(`${formatTableLabel(target)}: error al borrar (${error.message}).`);
  }

  return count ?? 0;
}

async function clean() {
  printPlan();
  if (isPreflight) {
    console.log('Preflight terminado; no se creó ningún cliente ni se abrió una conexión.');
    return;
  }

  const client = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });
  const targets = getTargets();

  const totalBefore = [];
  for (const target of targets) {
    const before = await countRows(client, target);
    totalBefore.push({ target, before });
    console.log(`- ${formatTableLabel(target)} => ${before} fila(s)`);
  }

  if (isDryRun) {
    console.log('DRY-RUN activo: no se ejecutó ningún DELETE.');
    return;
  }

  console.log('\nIniciando limpieza...');
  for (const { target, before } of totalBefore) {
    const deleted = await deleteRows(client, target);
    const status = deleted === before ? 'OK' : 'ATIPICO';
    console.log(`${status} ${formatTableLabel(target)} => ${deleted}/${before} borradas`);
  }

  console.log('\nLimpieza finalizada. Recomendación:');
  console.log('- Re-ejecutar `seed:demo` para levantar un dataset limpio y predecible.');
  console.log('- Volver a correr `test:rls` si necesitas validar que la rama sigue limpia.');
}

validateNode();
validateEnvironment();
validateOperationalGate();

if (preserveEquipo && preserveReference) {
  console.log('Aviso: se ejecutará limpieza preservando equipo y referencia.');
}

await clean();
