// Gate RLS del CRM con sesiones reales y anon key.
// Requiere el seed determinista de seed-demo.mjs y corre solo en branch/staging.
// La service_role se usa EXCLUSIVAMENTE para validar/limpiar fixtures; todas las
// aserciones de permisos se ejecutan con sesiones de usuario o como anon.

import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';

// ── Vía fuera de banda del banco (LEEME-seed, «Baja histórica») ─────────────
// El guard `trg_equipo_validar_usuarios_jerarquia` (post-8-ago) prohíbe —con
// razón— desactivar una membresía que conserve leads/tareas. Los estados
// heredados que este gate MIDE (inactivo que aún posee) solo se construyen
// como los construye el seed: por psql con el trigger apagado en UNA
// transacción. CRM_BANCO_PSQL_URL la exporta el ciclo del banco.
function revocarEquipoFueraDeBanda(perfilId) {
  const psqlBanco = process.env.CRM_BANCO_PSQL_URL ?? '';
  if (!psqlBanco) {
    throw new Error('falta CRM_BANCO_PSQL_URL — revocar una membresía con dependencias exige la vía fuera de banda del banco (LEEME-seed)');
  }
  // SOLO el guard de jerarquia se apaga: la rotacion del token ICS
  // (trg_equipo_rotar_agenda_ics_offboarding) y la auditoria SIGUEN corriendo,
  // igual que en una baja real — la matriz mide justamente esa rotacion.
  execFileSync('psql', [psqlBanco, '-v', 'ON_ERROR_STOP=1', '-q', '-c',
    `begin;
     alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
     update crm.equipo set activo = false where perfil_id = '${perfilId}';
     alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
     commit;`]);
}

// El ledger `crm.lead_asignaciones` esta sellado tambien para service_role
// (deny-by-default, y esta bien que lo este: PostgREST devolvia 42501 y la
// medicion de abajo reventaba). Leerlo para calcular deltas esperados es
// trabajo de la MISMA via fuera de banda. Solo lectura; devuelve un entero.
function contarFueraDeBanda(etiqueta, sql) {
  const psqlBanco = process.env.CRM_BANCO_PSQL_URL ?? '';
  if (!psqlBanco) {
    throw new Error(`falta CRM_BANCO_PSQL_URL — ${etiqueta} exige la via fuera de banda del banco (LEEME-seed)`);
  }
  const salida = execFileSync('psql',
    [psqlBanco, '-v', 'ON_ERROR_STOP=1', '-qAt', '-c', sql], { encoding: 'utf8' }).trim();
  const n = Number(salida);
  if (!Number.isInteger(n) || n < 0) {
    throw new Error(`${etiqueta}: el conteo fuera de banda no es un entero (${salida})`);
  }
  return n;
}
// Lee UN valor de texto por la vía fuera de banda (el gate de identidad necesita ids que la API no expone).
function textoFueraDeBanda(etiqueta, sql) {
  const psqlBanco = process.env.CRM_BANCO_PSQL_URL ?? '';
  if (!psqlBanco) {
    throw new Error(`falta CRM_BANCO_PSQL_URL — ${etiqueta} exige la via fuera de banda del banco (LEEME-seed)`);
  }
  return execFileSync('psql', [psqlBanco, '-v', 'ON_ERROR_STOP=1', '-qAt', '-c', sql], { encoding: 'utf8' }).trim() || null;
}
// Ejecuta SQL de setup por la misma vía fuera de banda (una transacción). Lo
// usa el gate de identidad multiempresa para togglear `crm.multiempresa_flags`
// (sin grants API) y limpiar fixtures de identidad (RLS deny-by-default).
function ejecutarFueraDeBanda(etiqueta, sql, { tolerante = false } = {}) {
  const psqlBanco = process.env.CRM_BANCO_PSQL_URL ?? '';
  if (!psqlBanco) {
    throw new Error(`falta CRM_BANCO_PSQL_URL — ${etiqueta} exige la via fuera de banda del banco (LEEME-seed)`);
  }
  if (!tolerante) {
    execFileSync('psql', [psqlBanco, '-v', 'ON_ERROR_STOP=1', '-q', '-c', `begin; ${sql} commit;`]);
    return;
  }
  // Limpieza TOLERANTE: sentencia a sentencia. Varias tablas son append-only por
  // diseño (depositos_reclamados, ledger, cierres): un candado no aborta el resto.
  for (const stmt of sql.split(';').map((x) => x.trim()).filter(Boolean)) {
    try {
      execFileSync('psql', [psqlBanco, '-q', '-c', `begin; select set_config('crm.op_privilegiada','on',true); ${stmt}; commit;`], { stdio: ['ignore', 'ignore', 'ignore'] });
    } catch { /* candado append-only: se deja la fila, es un banco */ }
  }
}
import { createClient } from '@supabase/supabase-js';
import {
  BANK_CLIENT,
  BANK_CONTRACT,
  BANK_LEGACY_CONTRACT,
  EXPECTED_LEAD_NAMES,
  EXPECTED_TAREA_TITULOS,
  LEADS,
  LEAD_BY_KEY,
  PRODUCTION_PROJECT_REF,
  TAREAS,
  TAREA_BY_KEY,
  TRANSIENT_IDS,
  USERS,
  USER_BY_KEY,
  normalizePeruPhone,
  validateFixtureModel,
} from './fixtures.mjs';

const HELP = `
Gate RLS del CRM (solo branch/staging con seed-demo)

Uso:
  node supabase/scripts/test-rls.mjs [--preflight]

Opciones:
  --preflight  Valida runtime, variables y matriz sin abrir conexiones.
  --help       Muestra esta ayuda sin exigir variables de entorno.

Variables requeridas:
  SUPABASE_URL
  SUPABASE_ANON_KEY
  SUPABASE_SERVICE_ROLE_KEY  Solo precondiciones y limpieza de fixtures.
  CRM_DEMO_PASSWORD       Debe coincidir con seed-demo (minimo 12).

El gate comprueba lecturas exactas, aislamiento entre subarboles, escrituras
cruzadas, inmutabilidad, la matriz completa de offboarding (ambos flags y sus
dos estados mixtos), directorio de solo lectura, acceso anonimo, la agenda de
tareas/ICS, las metas versionadas y la frontera bancaria del CRM.
`;

const args = new Set(process.argv.slice(2));
const allowedArgs = new Set(['--help', '-h', '--preflight']);
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

const SUPABASE_URL = process.env.SUPABASE_URL?.trim();
const ANON_KEY = process.env.SUPABASE_ANON_KEY?.trim();
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const PASSWORD = process.env.CRM_DEMO_PASSWORD;

let failures = 0;
let assertions = 0;

function fatal(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

function validateNode() {
  const [major, minor] = process.versions.node.split('.').map(Number);
  if (major < 22 || (major === 22 && minor < 12)) {
    fatal(`Node ${process.versions.node} no es compatible; se requiere >=22.12.0.`);
  }
}

function validateEnvironment() {
  if (!SUPABASE_URL) fatal('Falta SUPABASE_URL.');
  if (!ANON_KEY) fatal('Falta SUPABASE_ANON_KEY.');
  if (!SERVICE_KEY) {
    fatal('Falta SUPABASE_SERVICE_ROLE_KEY (precondiciones y limpieza segura).');
  }
  if (!PASSWORD) fatal('Falta CRM_DEMO_PASSWORD.');
  if (PASSWORD.length < 12) fatal('CRM_DEMO_PASSWORD debe tener al menos 12 caracteres.');

  let parsed;
  try {
    parsed = new URL(SUPABASE_URL);
  } catch {
    fatal('SUPABASE_URL no es una URL valida.');
  }
  const loopbackHosts = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);
  if (parsed.protocol !== 'https:'
      && !(parsed.protocol === 'http:' && loopbackHosts.has(parsed.hostname))) {
    fatal('SUPABASE_URL debe usar HTTPS; HTTP solo se permite en localhost/loopback.');
  }
  if (parsed.username || parsed.password) {
    fatal('SUPABASE_URL no debe incluir credenciales.');
  }
  if (SUPABASE_URL.includes(PRODUCTION_PROJECT_REF)) {
    fatal('Destino de PRODUCCION detectado. El gate RLS solo corre en branch/staging.');
  }
}

function printPreflight() {
  console.log('✓ runtime, dependencia y variables validos');
  console.log(`✓ destino permitido: ${new URL(SUPABASE_URL).host}`);
  console.log(`✓ matriz: ${Object.keys(EXPECTED_LEAD_NAMES).length} sesiones`);
  for (const [key, names] of Object.entries(EXPECTED_LEAD_NAMES)) {
    console.log(`  - ${key}: ${names.length} leads, ${EXPECTED_TAREA_TITULOS[key].length} tareas`);
  }
  console.log(`✓ fixtures: ${LEADS.length} leads, ${LEADS.length} actividades, ${TAREAS.length} tareas`);
  console.log('✓ offboarding: true/true, false/true, true/false, false/false y fallback global');
  console.log('✓ fixtures: 1 cliente bancario + 1 contrato enlazado + 1 contrato legacy + 1 cuenta contractual');
  console.log('Preflight terminado; no se abrio ninguna conexion.');
}

validateNode();
validateEnvironment();
validateFixtureModel();

if (args.has('--preflight')) {
  printPreflight();
  process.exit(0);
}

function clientOptions(storageKey) {
  return {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
      storageKey,
    },
  };
}

const admin = createClient(
  SUPABASE_URL,
  SERVICE_KEY,
  clientOptions('crm-rls-service'),
);

function pass(message) {
  assertions += 1;
  console.log(`  ✓ ${message}`);
}

function fail(message) {
  assertions += 1;
  failures += 1;
  console.error(`  ✗ ${message}`);
}

function check(condition, message, detail = '') {
  if (condition) pass(message);
  else fail(`${message}${detail ? ` — ${detail}` : ''}`);
  return condition;
}

function errorText(error) {
  if (!error) return 'sin detalle';
  return [error.code, error.message, error.details, error.hint].filter(Boolean).join(' · ');
}

function isAuthorizationError(error) {
  const code = String(error?.code ?? '');
  const message = String(error?.message ?? '');
  return code === '42501'
    || code === '42503'
    || /permission denied|row-level security|not authorized|no autorizado/i.test(message);
}

function isMissingColumnError(error) {
  const code = String(error?.code ?? '');
  const message = String(error?.message ?? '');
  return code === '42703'
    || code === 'PGRST204'
    || /column .* does not exist|could not find .* column/i.test(message);
}

async function requireAdmin(label, promise) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    throw new Error(`${label}: ${error?.message ?? String(error)}`, { cause: error });
  }
  if (response.error) {
    throw new Error(`${label}: ${errorText(response.error)}`, { cause: response.error });
  }
  return response;
}

async function positive(label, promise) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    fail(`${label}: excepcion de red/cliente — ${error?.message ?? String(error)}`);
    return null;
  }
  if (response.error) {
    fail(`${label}: query fallo — ${errorText(response.error)}`);
    return null;
  }
  return response;
}

async function expectHidden(label, promise) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    fail(`${label}: excepcion inesperada — ${error?.message ?? String(error)}`);
    return false;
  }

  if (response.error) {
    if (isAuthorizationError(response.error)) {
      pass(`${label} (denegado por permisos)`);
      return true;
    }
    fail(`${label}: fallo no atribuible a permisos — ${errorText(response.error)}`);
    return false;
  }

  if (Array.isArray(response.data) && response.data.length === 0) {
    pass(`${label} (0 filas por RLS)`);
    return true;
  }
  fail(`${label}: devolvio ${Array.isArray(response.data) ? response.data.length : 'respuesta ambigua'} fila(s)`);
  return false;
}

async function expectMissingColumn(label, promise) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    fail(`${label}: excepcion inesperada — ${error?.message ?? String(error)}`);
    return false;
  }
  if (response.error && isMissingColumnError(response.error)) {
    pass(label);
    return true;
  }
  if (response.error) {
    fail(`${label}: error distinto al esperado — ${errorText(response.error)}`);
  } else {
    fail(`${label}: la columna sensible fue aceptada`);
  }
  return false;
}

async function expectBlockedMutation(label, promise, allowedErrorCodes = []) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    fail(`${label}: excepcion inesperada — ${error?.message ?? String(error)}`);
    return false;
  }

  if (response.error) {
    const code = String(response.error.code ?? '');
    if (isAuthorizationError(response.error) || allowedErrorCodes.includes(code)) {
      pass(`${label} (bloqueado: ${code || 'sin codigo'})`);
      return true;
    }
    fail(`${label}: fallo por una causa no valida para RLS — ${errorText(response.error)}`);
    return false;
  }

  if (Array.isArray(response.data) && response.data.length === 0) {
    pass(`${label} (0 filas afectadas)`);
    return true;
  }

  fail(`${label}: la mutacion afecto ${Array.isArray(response.data) ? response.data.length : 'una cantidad ambigua'} fila(s)`);
  return false;
}

/**
 * A diferencia de expectHidden/expectBlockedMutation, esta sonda exige un
 * error explicito de autorizacion: 0 filas no basta para demostrar que una
 * tabla o RPC sensible carece de acceso directo.
 */
async function expectExplicitAuthorizationDenied(label, promise, allowedErrorCodes = []) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    fail(`${label}: excepcion inesperada — ${error?.message ?? String(error)}`);
    return false;
  }

  const code = String(response.error?.code ?? '');
  const message = String(response.error?.message ?? '');
  const isScopedDenial = /fuera de (?:tu|su) cartera|solo puedes|sin permiso/i.test(message);
  if (response.error
      && (isAuthorizationError(response.error)
        || isScopedDenial
        || allowedErrorCodes.includes(code))) {
    pass(`${label} (denegado: ${code || 'sin codigo'})`);
    return true;
  }

  if (response.error) {
    fail(`${label}: error distinto a autorizacion — ${errorText(response.error)}`);
  } else {
    fail(`${label}: la operacion no devolvio un error explicito de autorizacion`);
  }
  return false;
}

/** Exige codigo Y mensaje para no confundir dos rechazos de negocio distintos. */
async function expectExpectedFailure(label, promise, allowedErrorCodes, messagePattern) {
  let response;
  try {
    response = await promise;
  } catch (error) {
    fail(`${label}: excepcion inesperada — ${error?.message ?? String(error)}`);
    return false;
  }

  const code = String(response.error?.code ?? '');
  const message = String(response.error?.message ?? '');
  if (response.error && allowedErrorCodes.includes(code) && messagePattern.test(message)) {
    pass(`${label} (rechazo esperado: ${code})`);
    return true;
  }

  if (response.error) {
    fail(`${label}: rechazo distinto al esperado — ${errorText(response.error)}`);
  } else {
    fail(`${label}: la operacion fue aceptada`);
  }
  return false;
}

function assertSeed(condition, message) {
  if (!condition) throw new Error(`Seed incoherente: ${message}`);
}

async function cleanupTransientRows() {
  // 0C convierte la historia de asignacion en un ledger absoluto: ni el gate
  // perfora esa garantia con hard-delete. Los ids son aleatorios por corrida y
  // el cierre usa el mismo soft-delete que produccion; el branch se destruye al
  // terminar el gate.
  //
  // Tareas transitorias: el cierre de produccion es por estado ('cancelada');
  // el filtro estado='pendiente' evita tocar cerradas (inmutables por trigger).
  // La tarea cerrada por la RPC y su actividad de resultado QUEDAN a proposito:
  // el log es INSERT-only y ademas borrar esa actividad es imposible (el SET
  // NULL de la FK resultado_actividad_id dispara el trigger de inmutabilidad
  // sobre la tarea ya cerrada). Ids aleatorios + branch descartable lo cubren.
  await requireAdmin(
    'cancelar tareas transitorias pendientes',
    admin.schema('crm').from('tareas').update({ estado: 'cancelada' }).in('id', [
      TRANSIENT_IDS.foreignCreatorTarea,
      TRANSIENT_IDS.supervisorClientTarea,
      TRANSIENT_IDS.analystClientTarea,
      TRANSIENT_IDS.directoryTarea,
      TRANSIENT_IDS.portalClientTarea,
      TRANSIENT_IDS.rpcCloseTarea,
      TRANSIENT_IDS.taskFollowTarea,
      TRANSIENT_IDS.repartoTareaReencolada,
      TRANSIENT_IDS.repartoTareaReencoladaContactado,
      TRANSIENT_IDS.repartoTareaReunionHecha,
      TRANSIENT_IDS.repartoTareaBandeja,
      TRANSIENT_IDS.anularTareaReunion,
      TRANSIENT_IDS.anularTareaLlamada,
      TRANSIENT_IDS.anularTareaSistema,
      TRANSIENT_IDS.anularTareaAjena,
    ]).eq('estado', 'pendiente'),
  );
  await requireAdmin(
    'desactivar leads transitorios',
    admin.schema('crm').from('leads').update({ activo: false }).in('id', [
      TRANSIENT_IDS.directoryLead,
      TRANSIENT_IDS.crossTeamLead,
      TRANSIENT_IDS.portalClientLead,
      TRANSIENT_IDS.triggerAssignedInsertLead,
      TRANSIENT_IDS.triggerSellerChangeLead,
      TRANSIENT_IDS.triggerSupervisorOnlyLead,
      TRANSIENT_IDS.triggerNoTenureLead,
      TRANSIENT_IDS.offboardingDestinationPortalLead,
      TRANSIENT_IDS.offboardingDestinationTeamLead,
      TRANSIENT_IDS.taskFollowLead,
      TRANSIENT_IDS.anularLead,
      TRANSIENT_IDS.anularLeadSistema,
      TRANSIENT_IDS.anularLeadAjena,
      TRANSIENT_IDS.repartoLeadOk,
      TRANSIENT_IDS.repartoLeadNoContactar,
      TRANSIENT_IDS.repartoLeadCarrera,
      TRANSIENT_IDS.repartoLeadReencolado,
      TRANSIENT_IDS.repartoLeadReencoladoContactado,
      TRANSIENT_IDS.repartoLeadReunionHecha,
      TRANSIENT_IDS.repartoLeadBandeja,
      TRANSIENT_IDS.descarteLeadCredito,
      TRANSIENT_IDS.descarteLeadLimpio,
      TRANSIENT_IDS.descarteLeadCarrera,
      TRANSIENT_IDS.descarteLeadVista,
      TRANSIENT_IDS.tenenciaLeadViejo,
      TRANSIENT_IDS.tenenciaLeadPropio,
      TRANSIENT_IDS.avanceLeadConversacion,
      TRANSIENT_IDS.avanceLeadIntento,
      TRANSIENT_IDS.avanceLeadManual,
      TRANSIENT_IDS.avanceLeadColaGlobal,
      TRANSIENT_IDS.avanceLeadReunion,
    ]),
  );

  // 🔴 Residuos DE OTRA CORRIDA (banco persistente, 01/09). Los TRANSIENT_IDS
  // son aleatorios por proceso, asi que este arranque no puede verlos por id —
  // pero el lead de bolsa del bloque F2 usa un TELEFONO FIJO y se deja VIVO a
  // proposito en la cola global (prueba la liberacion gerencial). En un branch
  // de un solo uso daba igual; en un banco que se reusa, la corrida siguiente
  // chocaba con `uq_leads_telefono_vivo` (23505) y ademas el lead vivo
  // contaminaba los conteos de cola de los bloques tempranos. Se desactiva por
  // su huella FIJA (telefono + nombre), el mismo soft-delete de produccion; la
  // parcial `uq_leads_telefono_vivo` solo cuenta vivos, asi que con esto basta.
  await requireAdmin(
    'desactivar la bolsa F2 de una corrida anterior (telefono fijo)',
    admin.schema('crm').from('leads')
      .update({ activo: false })
      .eq('telefono', '+51996600311')
      .eq('nombre_completo', 'F2 TOMA BOLSA TRANSIENT')
      .eq('activo', true),
  );
}

async function verifySeed() {
  const emails = USERS.map((user) => user.email);
  const profilesResponse = await requireAdmin(
    'precondicion public.perfiles',
    admin.from('perfiles')
      .select('id, correo, rol, activo, asesor_perfil_id, dni, banco, numero_cuenta, cci, banco_usd, numero_cuenta_usd, cci_usd')
      .in('correo', emails),
  );
  assertSeed(profilesResponse.data.length === USERS.length,
    `se esperaban ${USERS.length} perfiles y hay ${profilesResponse.data.length}`);

  const profileByEmail = new Map(profilesResponse.data.map((row) => [row.correo, row]));
  const profileIdByKey = Object.create(null);
  for (const user of USERS) {
    const row = profileByEmail.get(user.email);
    assertSeed(row, `falta el perfil ${user.email}`);
    assertSeed(row.rol === user.portalRole, `${user.key}.rol=${row.rol}`);
    assertSeed(row.activo === user.portalActive, `${user.key}.activo=${row.activo}`);
    profileIdByKey[user.key] = row.id;
  }

  const crmUsers = USERS.filter((user) => user.crmRole);
  const teamResponse = await requireAdmin(
    'precondicion crm.equipo',
    admin.schema('crm').from('equipo')
      .select('perfil_id, rol_crm, supervisor_id, activo')
      .in('perfil_id', crmUsers.map((user) => profileIdByKey[user.key])),
  );
  assertSeed(teamResponse.data.length === crmUsers.length,
    `se esperaban ${crmUsers.length} miembros CRM y hay ${teamResponse.data.length}`);
  const teamById = new Map(teamResponse.data.map((row) => [row.perfil_id, row]));
  for (const user of crmUsers) {
    const row = teamById.get(profileIdByKey[user.key]);
    assertSeed(row, `falta crm.equipo para ${user.key}`);
    assertSeed(row.rol_crm === user.crmRole, `${user.key}.rol_crm=${row.rol_crm}`);
    assertSeed(row.activo === user.crmActive, `${user.key}.crm_activo=${row.activo}`);
    const expectedSupervisor = user.supervisorKey ? profileIdByKey[user.supervisorKey] : null;
    assertSeed(row.supervisor_id === expectedSupervisor, `${user.key}.supervisor_id no coincide`);
  }

  const leadNames = LEADS.map((lead) => lead.name);
  const leadsResponse = await requireAdmin(
    'precondicion crm.leads',
    admin.schema('crm').from('leads').select('*').in('nombre_completo', leadNames),
  );
  assertSeed(leadsResponse.data.length === LEADS.length,
    `se esperaban ${LEADS.length} leads y hay ${leadsResponse.data.length}`);
  const leadByName = new Map(leadsResponse.data.map((row) => [row.nombre_completo, row]));
  assertSeed(leadByName.size === LEADS.length, 'hay nombres de lead fixture duplicados');

  for (const fixture of LEADS) {
    const row = leadByName.get(fixture.name);
    assertSeed(row, `falta lead ${fixture.key}`);
    assertSeed(row.activo === true, `${fixture.key} no esta activo`);
    assertSeed(row.telefono === normalizePeruPhone(fixture.phone), `${fixture.key}.telefono no coincide`);
    const expectedSeller = fixture.sellerKey ? profileIdByKey[fixture.sellerKey] : null;
    const expectedSupervisor = fixture.supervisorKey ? profileIdByKey[fixture.supervisorKey] : null;
    assertSeed(row.vendedor_id === expectedSeller, `${fixture.key}.vendedor_id no coincide`);
    assertSeed(row.asignado_supervisor_id === expectedSupervisor,
      `${fixture.key}.asignado_supervisor_id no coincide`);
  }

  const activitiesResponse = await requireAdmin(
    'precondicion crm.actividades',
    admin.schema('crm').from('actividades').select('*').in('id', LEADS.map((lead) => lead.activityId)),
  );
  assertSeed(activitiesResponse.data.length === LEADS.length,
    `se esperaban ${LEADS.length} actividades y hay ${activitiesResponse.data.length}`);
  const activityById = new Map(activitiesResponse.data.map((row) => [row.id, row]));
  for (const fixture of LEADS) {
    const activity = activityById.get(fixture.activityId);
    const lead = leadByName.get(fixture.name);
    assertSeed(activity?.lead_id === lead.id, `actividad de ${fixture.key} apunta a otro lead`);
  }

  const tareasResponse = await requireAdmin(
    'precondicion crm.tareas',
    admin.schema('crm').from('tareas')
      .select('*', { count: 'exact' })
      .in('id', TAREAS.map((tarea) => tarea.id)),
  );
  assertSeed(tareasResponse.count === TAREAS.length,
    `se esperaban ${TAREAS.length} tareas y el count exacto dio ${tareasResponse.count}`);
  assertSeed(tareasResponse.data.length === TAREAS.length,
    `se esperaban ${TAREAS.length} tareas y hay ${tareasResponse.data.length}`);
  const tareaById = new Map(tareasResponse.data.map((row) => [row.id, row]));
  for (const fixture of TAREAS) {
    const row = tareaById.get(fixture.id);
    const lead = leadByName.get(LEAD_BY_KEY[fixture.leadKey].name);
    assertSeed(row, `falta tarea ${fixture.key}`);
    assertSeed(row.activo === true, `tarea ${fixture.key} no esta activa`);
    assertSeed(row.estado === 'pendiente', `tarea ${fixture.key} no esta pendiente`);
    assertSeed(row.titulo === fixture.titulo, `tarea ${fixture.key}.titulo no coincide`);
    assertSeed(row.lead_id === lead.id, `tarea ${fixture.key} apunta a otro lead`);
    // La tenencia la derivo el before-insert trigger: debe ser espejo del lead.
    assertSeed(row.vendedor_id === lead.vendedor_id,
      `tarea ${fixture.key}.vendedor_id no es espejo del lead`);
    assertSeed(row.asignado_supervisor_id === lead.asignado_supervisor_id,
      `tarea ${fixture.key}.asignado_supervisor_id no es espejo del lead`);
  }

  const bankProfile = profileByEmail.get(USER_BY_KEY[BANK_CLIENT.key].email);
  assertSeed(bankProfile.dni === BANK_CLIENT.dni, 'DNI del cliente bancario no coincide');
  assertSeed(bankProfile.asesor_perfil_id === profileIdByKey[BANK_CLIENT.adviserKey],
    'analista del cliente bancario no coincide');
  assertSeed(bankProfile.banco === BANK_CLIENT.bank, 'banco PEN fixture no coincide');
  assertSeed(bankProfile.numero_cuenta === BANK_CLIENT.accountNumber, 'cuenta PEN fixture no coincide');
  assertSeed(bankProfile.cci === BANK_CLIENT.cci, 'CCI PEN fixture no coincide');
  assertSeed(bankProfile.banco_usd === BANK_CLIENT.bankUsd, 'banco USD fixture no coincide');
  assertSeed(bankProfile.numero_cuenta_usd === BANK_CLIENT.accountNumberUsd,
    'cuenta USD fixture no coincide');
  assertSeed(bankProfile.cci_usd === BANK_CLIENT.cciUsd, 'CCI USD fixture no coincide');

  const contractResponse = await requireAdmin(
    'precondicion public.contratos',
    admin.from('contratos').select('*').eq('numero_contrato', BANK_CONTRACT.number).single(),
  );
  assertSeed(contractResponse.data.cliente_id === bankProfile.id,
    'el contrato sensible apunta a otro cliente');
  assertSeed(contractResponse.data.notas_internas === BANK_CONTRACT.internalNotes,
    'notas internas del contrato fixture no coinciden');

  const bankLinkResponse = await requireAdmin(
    'precondicion crm.contrato_cuentas_pago',
    admin.schema('crm').from('contrato_cuentas_pago')
      .select('id, contrato_id, cuenta_bancaria_id')
      .eq('contrato_id', contractResponse.data.id)
      .single(),
  );
  assertSeed(bankLinkResponse.data.contrato_id === contractResponse.data.id,
    'el enlace bancario apunta a otro contrato');

  const bankAccountResponse = await requireAdmin(
    'precondicion crm.cuentas_bancarias',
    admin.schema('crm').from('cuentas_bancarias')
      .select('id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, activa')
      .eq('id', bankLinkResponse.data.cuenta_bancaria_id)
      .single(),
  );
  assertSeed(bankAccountResponse.data.cliente_id === bankProfile.id,
    'la cuenta contractual pertenece a otro cliente');
  assertSeed(bankAccountResponse.data.moneda === BANK_CONTRACT.currency,
    'la cuenta contractual tiene otra moneda');
  assertSeed(bankAccountResponse.data.banco === BANK_CLIENT.bank,
    'la cuenta contractual tiene otro banco');
  assertSeed(bankAccountResponse.data.tipo_cuenta === BANK_CLIENT.accountType,
    'la cuenta contractual tiene otro tipo');
  assertSeed(bankAccountResponse.data.numero_cuenta === BANK_CLIENT.accountNumber,
    'la cuenta contractual tiene otro numero');
  assertSeed(bankAccountResponse.data.cci === BANK_CLIENT.cci,
    'la cuenta contractual tiene otro CCI');
  assertSeed(bankAccountResponse.data.activa === true,
    'la cuenta contractual fixture no esta activa');

  const legacyContractResponse = await requireAdmin(
    'precondicion public.contratos legacy sin enlace',
    admin.from('contratos')
      .select('*')
      .eq('numero_contrato', BANK_LEGACY_CONTRACT.number)
      .single(),
  );
  assertSeed(legacyContractResponse.data.cliente_id === bankProfile.id,
    'el contrato legacy apunta a otro cliente');
  assertSeed(legacyContractResponse.data.notas_internas === BANK_LEGACY_CONTRACT.internalNotes,
    'notas internas del contrato legacy no coinciden');
  const legacyLinkResponse = await requireAdmin(
    'precondicion contrato legacy sin cuenta contractual',
    admin.schema('crm').from('contrato_cuentas_pago')
      .select('id', { count: 'exact', head: true })
      .eq('contrato_id', legacyContractResponse.data.id),
  );
  assertSeed(legacyLinkResponse.count === 0,
    'el contrato legacy tiene un enlace y no sirve para probar el fallback');

  return {
    activities: activitiesResponse.data,
    activityById,
    bankAccount: bankAccountResponse.data,
    bankLink: bankLinkResponse.data,
    contract: contractResponse.data,
    legacyContract: legacyContractResponse.data,
    leadByName,
    leads: leadsResponse.data,
    profileIdByKey,
    profiles: profilesResponse.data,
    team: teamResponse.data,
    tareaById,
    tareas: tareasResponse.data,
  };
}

const LEAD_RESTORE_FIELDS = [
  'nombre_completo', 'telefono', 'correo', 'dni', 'distrito', 'origen', 'etapa',
  'motivo_descarte', 'monto_estimado', 'moneda', 'categoria_interes', 'vendedor_id',
  'asignado_supervisor_id', 'perfil_id', 'contrato_id', 'convertido_en', 'nota', 'activo',
];

function businessState(row) {
  return Object.fromEntries(LEAD_RESTORE_FIELDS.map((field) => [field, row[field]]));
}

async function restoreActorStateIfNeeded(seed) {
  const profileIds = seed.profiles.map((row) => row.id);
  const currentProfiles = await requireAdmin(
    'verificar integridad final de perfiles fixture',
    admin.from('perfiles').select('id, rol, activo').in('id', profileIds),
  );
  const currentProfileById = new Map(currentProfiles.data.map((row) => [row.id, row]));
  for (const original of seed.profiles) {
    const current = currentProfileById.get(original.id);
    if (!current || current.rol !== original.rol || current.activo !== original.activo) {
      await requireAdmin(
        `restaurar perfil fixture ${original.correo}`,
        admin.from('perfiles')
          .update({ rol: original.rol, activo: original.activo })
          .eq('id', original.id),
      );
    }
  }

  const teamIds = seed.team.map((row) => row.perfil_id);
  const currentTeam = await requireAdmin(
    'verificar integridad final de membresías CRM fixture',
    admin.schema('crm').from('equipo')
      .select('perfil_id, rol_crm, supervisor_id, activo')
      .in('perfil_id', teamIds),
  );
  const currentTeamById = new Map(currentTeam.data.map((row) => [row.perfil_id, row]));
  for (const original of seed.team) {
    const current = currentTeamById.get(original.perfil_id);
    if (!current
        || current.rol_crm !== original.rol_crm
        || current.supervisor_id !== original.supervisor_id
        || current.activo !== original.activo) {
      await requireAdmin(
        `restaurar membresía CRM fixture ${original.perfil_id}`,
        admin.schema('crm').from('equipo')
          .update({
            rol_crm: original.rol_crm,
            supervisor_id: original.supervisor_id,
            activo: original.activo,
          })
          .eq('perfil_id', original.perfil_id),
      );
    }
  }
}

async function restoreSeedIfNeeded(seed) {
  await restoreActorStateIfNeeded(seed);

  const currentResponse = await requireAdmin(
    'verificar integridad final de leads fixture',
    admin.schema('crm').from('leads').select('*').in('id', seed.leads.map((row) => row.id)),
  );
  const currentById = new Map(currentResponse.data.map((row) => [row.id, row]));

  for (const original of seed.leads) {
    const current = currentById.get(original.id);
    if (!current) {
      await requireAdmin(
        `restaurar lead borrado ${original.nombre_completo}`,
        admin.schema('crm').from('leads').insert(original),
      );
      continue;
    }
    if (JSON.stringify(businessState(current)) !== JSON.stringify(businessState(original))) {
      await requireAdmin(
        `restaurar lead alterado ${original.nombre_completo}`,
        admin.schema('crm').from('leads').update(businessState(original)).eq('id', original.id),
      );
    }
  }

  const currentActivities = await requireAdmin(
    'verificar integridad final de actividades fixture',
    admin.schema('crm').from('actividades').select('id').in('id', seed.activities.map((row) => row.id)),
  );
  const presentIds = new Set(currentActivities.data.map((row) => row.id));
  for (const original of seed.activities) {
    if (!presentIds.has(original.id)) {
      await requireAdmin(
        `restaurar actividad borrada ${original.id}`,
        admin.schema('crm').from('actividades').insert(original),
      );
    }
  }
}

async function login(user) {
  const client = createClient(
    SUPABASE_URL,
    ANON_KEY,
    clientOptions(`crm-rls-${user.key}`),
  );
  let response;
  try {
    response = await client.auth.signInWithPassword({
      email: user.email,
      password: PASSWORD,
    });
  } catch (error) {
    fail(`login ${user.key}: excepcion — ${error?.message ?? String(error)}`);
    return null;
  }
  if (response.error) {
    fail(`login ${user.key}: ${errorText(response.error)}`);
    return null;
  }
  if (!response.data.user || !response.data.session) {
    fail(`login ${user.key}: Supabase no devolvio usuario y sesion`);
    return null;
  }
  check(response.data.user.email?.toLowerCase() === user.email.toLowerCase(),
    `login ${user.key} corresponde al correo esperado`);
  return { client, user: response.data.user };
}

function sorted(values) {
  return [...values].sort((a, b) => a.localeCompare(b));
}

function sameStrings(actual, expected) {
  return JSON.stringify(sorted(actual)) === JSON.stringify(sorted(expected));
}

async function readVisibilityMatrix(sessions, seed) {
  console.log('\n— Visibilidad jerarquica exacta —');
  for (const [key, expectedNames] of Object.entries(EXPECTED_LEAD_NAMES)) {
    const session = sessions[key];
    if (!session) continue;
    const response = await positive(
      `${key} consulta crm.leads`,
      session.client.schema('crm').from('leads')
        .select('id, nombre_completo, vendedor_id, asignado_supervisor_id', { count: 'exact' })
        .order('nombre_completo'),
    );
    if (!response) continue;
    const actualNames = response.data.map((row) => row.nombre_completo);
    check(response.count === response.data.length,
      `${key}: count exact coincide con las filas`,
      `count=${response.count}, filas=${response.data.length}`);
    check(response.data.length === expectedNames.length,
      `${key} ve ${expectedNames.length} lead(s)`,
      `vio ${response.data.length}`);
    check(sameStrings(actualNames, expectedNames),
      `${key} ve exactamente su conjunto`,
      `esperado=[${expectedNames.join(', ')}], real=[${sorted(actualNames).join(', ')}]`);
  }

  console.log('\n— Actividades siguen la misma cartera —');
  const fixtureByName = new Map(LEADS.map((lead) => [lead.name, lead]));
  const allActivityIds = LEADS.map((lead) => lead.activityId);
  for (const [key, expectedNames] of Object.entries(EXPECTED_LEAD_NAMES)) {
    const session = sessions[key];
    if (!session) continue;
    const expectedActivityIds = expectedNames.map((name) => fixtureByName.get(name).activityId);
    const response = await positive(
      `${key} consulta actividades fixture`,
      session.client.schema('crm').from('actividades')
        .select('id, lead_id', { count: 'exact' })
        .in('id', allActivityIds),
    );
    if (!response) continue;
    const actualIds = response.data.map((row) => row.id);
    check(response.count === response.data.length,
      `${key}: count exact de actividades coincide`);
    check(sameStrings(actualIds, expectedActivityIds),
      `${key} ve exactamente ${expectedActivityIds.length} actividad(es) fixture`,
      `vio ${actualIds.length}`);
  }

  console.log('\n— Tareas de agenda siguen la misma cartera —');
  const allTareaIds = TAREAS.map((tarea) => tarea.id);
  for (const [key, expectedTitulos] of Object.entries(EXPECTED_TAREA_TITULOS)) {
    const session = sessions[key];
    if (!session) continue;
    const response = await positive(
      `${key} consulta tareas fixture`,
      session.client.schema('crm').from('tareas')
        .select('id, titulo, lead_id', { count: 'exact' })
        .in('id', allTareaIds),
    );
    if (!response) continue;
    const actualTitulos = response.data.map((row) => row.titulo);
    check(response.count === response.data.length,
      `${key}: count exact de tareas coincide`,
      `count=${response.count}, filas=${response.data.length}`);
    check(response.data.length === expectedTitulos.length,
      `${key} ve ${expectedTitulos.length} tarea(s)`,
      `vio ${response.data.length}`);
    check(sameStrings(actualTitulos, expectedTitulos),
      `${key} ve exactamente sus tareas`,
      `esperado=[${expectedTitulos.join(', ')}], real=[${sorted(actualTitulos).join(', ')}]`);
  }

  console.log('\n— Membresia y desactivacion —');
  for (const user of USERS.filter((candidate) => candidate.crmRole && candidate.crmActive)) {
    const session = sessions[user.key];
    if (!session) continue;
    const response = await positive(
      `${user.key} consulta su membresia activa`,
      session.client.schema('crm').from('equipo')
        .select('perfil_id, rol_crm, activo')
        .eq('perfil_id', session.user.id)
        .eq('activo', true)
        .single(),
    );
    if (!response) continue;
    check(response.data.rol_crm === user.crmRole && response.data.activo === true,
      `${user.key} resuelve su rol CRM activo`);
  }

  const inactive = sessions.vendInactive;
  if (inactive) {
    const membership = await positive(
      'usuario inactivo busca membresia activa',
      inactive.client.schema('crm').from('equipo')
        .select('perfil_id')
        .eq('perfil_id', inactive.user.id)
        .eq('activo', true),
    );
    if (membership) {
      check(membership.data.length === 0, 'usuario inactivo no resuelve membresia activa');
    }
    // Una fila CRM inactiva es revocación: ni siquiera su propia fila de equipo
    // (rol_crm/supervisor_id/creado_por) debe ser legible por el desactivado.
    await expectHidden(
      'usuario inactivo no lee ni su propia fila de crm.equipo',
      inactive.client.schema('crm').from('equipo').select('perfil_id, rol_crm, supervisor_id')
        .eq('perfil_id', inactive.user.id),
    );
    const ownedLead = seed.leadByName.get(LEAD_BY_KEY.inactiveOwned.name);
    await expectHidden(
      'usuario inactivo no lee ni su lead previamente asignado',
      inactive.client.schema('crm').from('leads').select('id').eq('id', ownedLead.id),
    );
    await expectHidden(
      'usuario inactivo no lee la actividad de su lead',
      inactive.client.schema('crm').from('actividades')
        .select('id')
        .eq('id', LEADS.find((lead) => lead.key === 'inactiveOwned').activityId),
    );
  }
}

async function readOneLead(session, id, label) {
  const response = await positive(
    label,
    session.client.schema('crm').from('leads')
      .select('id, vendedor_id, asignado_supervisor_id, nota, activo')
      .eq('id', id)
      .single(),
  );
  return response?.data ?? null;
}

async function readOneTarea(session, id, label) {
  const response = await positive(
    label,
    session.client.schema('crm').from('tareas')
      .select('id, vendedor_id, asignado_supervisor_id, estado, nota, resultado_actividad_id')
      .eq('id', id)
      .single(),
  );
  return response?.data ?? null;
}

async function readReassignmentActivities(leadId, label) {
  const response = await requireAdmin(
    label,
    admin.schema('crm').from('actividades')
      .select('id, detalle, metadata, creado_por', { count: 'exact' })
      .eq('lead_id', leadId)
      .eq('tipo', 'reasignacion')
      .order('creado_en'),
  );
  return { count: response.count ?? response.data.length, rows: response.data };
}

async function testRecursiveHierarchy(sessions, seed) {
  console.log('\n— Jerarquia recursiva (dos niveles) —');
  const nestedSupervisorId = seed.profileIdByKey.sup1Nested;
  const nestedSellerId = seed.profileIdByKey.vendNested;
  const carlos = seed.leadByName.get('CARLOS RUIZ DEMO');

  const sup1Team = await positive(
    'sup1 consulta la rama anidada de crm.equipo',
    sessions.sup1.client.schema('crm').from('equipo')
      .select('perfil_id', { count: 'exact' })
      .in('perfil_id', [nestedSupervisorId, nestedSellerId]),
  );
  if (sup1Team) {
    check(sup1Team.count === 2 && sup1Team.data.length === 2,
      'sup1 ve supervisor hijo y analista nieto por recursion');
  }

  const nestedTeam = await positive(
    'supervisor anidado consulta su rama',
    sessions.sup1Nested.client.schema('crm').from('equipo')
      .select('perfil_id', { count: 'exact' })
      .in('perfil_id', [nestedSupervisorId, nestedSellerId]),
  );
  if (nestedTeam) {
    check(nestedTeam.count === 2 && nestedTeam.data.length === 2,
      'supervisor anidado ve su propia fila y su analista');
  }

  const recursiveLead = await positive(
    'sup1 consulta el lead de su analista nieto',
    sessions.sup1.client.schema('crm').from('leads')
      .select('id, vendedor_id')
      .eq('id', carlos.id)
      .single(),
  );
  if (recursiveLead) {
    check(recursiveLead.data.vendedor_id === nestedSellerId,
      'lead recursivo pertenece al analista anidado');
  }

  await expectHidden(
    'vend1 no ve al analista de la rama anidada hermana',
    sessions.vend1.client.schema('crm').from('equipo')
      .select('perfil_id')
      .eq('perfil_id', nestedSellerId),
  );
  await expectHidden(
    'vend1 no ve el lead de la rama anidada hermana',
    sessions.vend1.client.schema('crm').from('leads').select('id').eq('id', carlos.id),
  );
  await expectHidden(
    'sup2 no ve la rama anidada de sup1',
    sessions.sup2.client.schema('crm').from('equipo')
      .select('perfil_id')
      .eq('perfil_id', nestedSellerId),
  );
  await expectHidden(
    'sup2 no ve el lead anidado de sup1',
    sessions.sup2.client.schema('crm').from('leads').select('id').eq('id', carlos.id),
  );
}

async function testCrossReads(sessions, seed) {
  console.log('\n— Lecturas cruzadas bloqueadas —');
  const juan = seed.leadByName.get('JUAN PEREZ DEMO');
  const carlos = seed.leadByName.get('CARLOS RUIZ DEMO');
  const ana = seed.leadByName.get('ANA TORRES DEMO');

  await expectHidden(
    'vend1 no lee un lead de vend3 (otro subarbol)',
    sessions.vend1.client.schema('crm').from('leads').select('id').eq('id', ana.id),
  );
  await expectHidden(
    'sup1 no lee un lead del equipo de sup2',
    sessions.sup1.client.schema('crm').from('leads').select('id').eq('id', ana.id),
  );
  await expectHidden(
    'sup2 no lee un lead del equipo de sup1',
    sessions.sup2.client.schema('crm').from('leads').select('id').eq('id', juan.id),
  );
  await expectHidden(
    'vend3 no lee el lead de otro analista',
    sessions.vend3.client.schema('crm').from('leads').select('id').eq('id', carlos.id),
  );

  const anaActivity = LEADS.find((lead) => lead.key === 'ana').activityId;
  await expectHidden(
    'vend1 no lee actividades del otro subarbol',
    sessions.vend1.client.schema('crm').from('actividades').select('id').eq('id', anaActivity),
  );
  await expectHidden(
    'sup1 no lee actividades del equipo de sup2',
    sessions.sup1.client.schema('crm').from('actividades').select('id').eq('id', anaActivity),
  );
}

// ── El lector global ve TODO lo vivo y NADA de lo borrado ────────────────────
// Decision de Miguel (01/09) tras el hallazgo de la primera corrida ejecutable
// de esta suite: la rama `es_lector_global()` iba FUERA del candado `activo` —
// con 7 leads vivos, gerencia veia 7 y el Directorio 55, PII incluida.
// Migraciones 20260902040000 (policies) y 20260902050000 (las dos SECURITY
// DEFINER que llevaban el MISMO espejo copiado y que la RLS no alcanza).
//
// Sin este bloque, un futuro drop+create con la forma vieja —el patron que ya
// paso con predicados copiados— pasaria el gate en verde. Se prueban LAS TRES
// PUERTAS, porque cerrar solo la RLS no cerraba nada: medido en el banco con
// la forma vieja, el timeline servia 195 filas de leads borrados.
async function testLectorGlobalNoVeBorrados(sessions, seed) {
  console.log('\n— El lector global: todo lo vivo, nada de lo borrado —');
  const dir = sessions.directorio.client;

  // 1) La rama VIVA intacta: mismo conjunto que gerencia por SELECT directo.
  const vivosGer = await positive('gerencia lista los leads vivos',
    sessions.gerencia.client.schema('crm').from('leads').select('id').eq('activo', true).limit(2000));
  const vivosDir = await positive('directorio lista los leads vivos',
    dir.schema('crm').from('leads').select('id').eq('activo', true).limit(2000));
  if (vivosGer && vivosDir) {
    const g = [...(vivosGer.data ?? []).map((r) => r.id)].sort();
    const d = [...(vivosDir.data ?? []).map((r) => r.id)].sort();
    check(g.length > 0 && JSON.stringify(g) === JSON.stringify(d),
      'el lector global ve EXACTAMENTE los leads vivos de gerencia (la rama viva no se rompio)',
      JSON.stringify({ gerencia: g.length, directorio: d.length }));
  }

  // 2) Los borrados, por las TRES puertas.
  await expectHidden('directorio NO lee leads borrados (policy)',
    dir.schema('crm').from('leads').select('id').eq('activo', false));
  await expectHidden('directorio NO lee tareas borradas (policy)',
    dir.schema('crm').from('tareas').select('id').eq('activo', false));

  const muertos = await requireAdmin('ids de leads borrados (admin)',
    admin.schema('crm').from('leads').select('id').eq('activo', false).limit(200));
  const idsMuertos = (muertos?.data ?? []).map((r) => r.id);
  if (idsMuertos.length === 0) {
    check(false, 'la sonda de borrados necesita al menos un lead inactivo: sin el no prueba nada');
  } else {
    const actsMuertas = await requireAdmin('actividades de leads borrados (admin)',
      admin.schema('crm').from('actividades').select('id').in('lead_id', idsMuertos).limit(200));
    const idsActs = (actsMuertas?.data ?? []).map((r) => r.id);
    if (idsActs.length > 0) {
      await expectHidden('directorio NO lee actividades de leads borrados (policy)',
        dir.schema('crm').from('actividades').select('id').in('id', idsActs));
    }
    // Puerta DEFINER 1: el timeline (la RLS no lo alcanza).
    const timeline = await positive('directorio pide el timeline del ambito',
      dir.schema('crm').rpc('actividades_del_ambito_fn'));
    if (timeline) {
      const cuela = (timeline.data ?? []).filter((f) => idsMuertos.includes(f.lead_id));
      check(cuela.length === 0,
        'actividades_del_ambito_fn (DEFINER) NO sirve al lector el timeline de leads borrados',
        JSON.stringify({ colados: cuela.length }));
    }
    // Puerta DEFINER 2: el estado de cierres.
    const cierres = await positive('directorio pide el estado de cierres de leads borrados',
      dir.schema('crm').rpc('cierres_estado_fn', { p_lead_ids: idsMuertos.slice(0, 200) }));
    if (cierres) {
      check(Array.isArray(cierres.data) && cierres.data.length === 0,
        'cierres_estado_fn (DEFINER) NO sirve al lector el estado de leads borrados',
        JSON.stringify(cierres.data));
    }
  }

  // 3) La EXCEPCION deliberada del P04: el roster historico SI se ve. Sin esta
  //    aserción, alguien "arreglaria" equipo_select por simetria y borraria la
  //    semantica de «revocado ≠ ajeno».
  const equipoBajas = await positive('directorio lee el roster historico',
    dir.schema('crm').from('equipo').select('perfil_id').eq('activo', false));
  check((equipoBajas?.data ?? []).length > 0,
    'P04 INTACTO: el lector global SIGUE viendo las membresias dadas de baja (revocado ≠ ajeno)',
    JSON.stringify({ bajas: (equipoBajas?.data ?? []).length }));
}

async function testWrites(sessions, seed) {
  console.log('\n— Escrituras cruzadas y privilegios bloqueados —');
  const juan = seed.leadByName.get('JUAN PEREZ DEMO');
  const maria = seed.leadByName.get('MARIA LOPEZ DEMO');
  const ana = seed.leadByName.get('ANA TORRES DEMO');
  const vend1Id = seed.profileIdByKey.vend1;
  const vend3Id = seed.profileIdByKey.vend3;

  await expectBlockedMutation(
    'vend1 no reasigna su lead a otro analista',
    sessions.vend1.client.schema('crm').from('leads')
      .update({ vendedor_id: vend3Id }, { count: 'exact' })
      .eq('id', juan.id)
      .select('id, vendedor_id'),
    ['P0001'],
  );
  const juanAfterReassign = await readOneLead(
    sessions.vend1,
    juan.id,
    'verificar lead tras intento de reasignacion',
  );
  if (juanAfterReassign) {
    check(juanAfterReassign.vendedor_id === vend1Id, 'reasignacion bloqueada sin cambio lateral');
  }

  await expectBlockedMutation(
    'vend1 no puede hacer soft-delete de su lead',
    sessions.vend1.client.schema('crm').from('leads')
      .update({ activo: false }, { count: 'exact' })
      .eq('id', juan.id)
      .select('id, activo'),
  );
  const juanAfterSoftDelete = await readOneLead(
    sessions.vend1,
    juan.id,
    'verificar lead tras intento de soft-delete',
  );
  if (juanAfterSoftDelete) check(juanAfterSoftDelete.activo === true, 'soft-delete no altero el lead');

  await expectBlockedMutation(
    'vend1 no puede hacer hard-delete',
    sessions.vend1.client.schema('crm').from('leads')
      .delete({ count: 'exact' })
      .eq('id', maria.id)
      .select('id'),
  );
  const mariaAfterDelete = await readOneLead(
    sessions.vend1,
    maria.id,
    'verificar lead tras intento de hard-delete',
  );
  if (mariaAfterDelete) check(mariaAfterDelete.id === maria.id, 'hard-delete no elimino el lead');

  await expectBlockedMutation(
    'vend1 no actualiza un lead de vend3',
    sessions.vend1.client.schema('crm').from('leads')
      .update({ nota: ana.nota }, { count: 'exact' })
      .eq('id', ana.id)
      .select('id'),
  );
  await expectBlockedMutation(
    'sup1 no actualiza un lead del equipo de sup2',
    sessions.sup1.client.schema('crm').from('leads')
      .update({ nota: ana.nota }, { count: 'exact' })
      .eq('id', ana.id)
      .select('id'),
  );
  const anaAfterCrossWrite = await readOneLead(
    sessions.vend3,
    ana.id,
    'verificar lead ajeno tras escrituras cruzadas',
  );
  if (anaAfterCrossWrite) check(anaAfterCrossWrite.nota === ana.nota, 'lead ajeno no fue alterado');

  await expectBlockedMutation(
    'sup1 no inserta un lead en el equipo de sup2',
    sessions.sup1.client.schema('crm').from('leads').insert({
      // Tenencia valida: debe fallar por analista ajeno, no por enviar ambos
      // propietarios a la vez (invariante 0C).
      asignado_supervisor_id: null,
      creado_por: sessions.sup1.user.id,
      etapa: 'nuevo',
      id: TRANSIENT_IDS.crossTeamLead,
      moneda: 'PEN',
      monto_estimado: 1000,
      nombre_completo: 'RLS CROSS TEAM TRANSIENT',
      origen: 'otro',
      telefono: '999000002',
      vendedor_id: vend3Id,
    }).select('id'),
  );

  await expectBlockedMutation(
    'directorio no inserta leads',
    sessions.directorio.client.schema('crm').from('leads').insert({
      creado_por: sessions.directorio.user.id,
      etapa: 'nuevo',
      id: TRANSIENT_IDS.directoryLead,
      moneda: 'PEN',
      monto_estimado: 1000,
      nombre_completo: 'RLS DIRECTORIO TRANSIENT',
      origen: 'otro',
      telefono: '999000001',
      // Tenencia integra para que la sonda falle por RLS/rol del actor.
      vendedor_id: vend1Id,
    }).select('id'),
  );

  await expectBlockedMutation(
    'directorio no actualiza leads aunque pueda leerlos',
    sessions.directorio.client.schema('crm').from('leads')
      .update({ nota: juan.nota }, { count: 'exact' })
      .eq('id', juan.id)
      .select('id'),
  );

  await expectBlockedMutation(
    'vend1 no registra actividad en un lead de vend3',
    sessions.vend1.client.schema('crm').from('actividades').insert({
      creado_por: sessions.vend1.user.id,
      detalle: 'RLS CROSS TEAM TRANSIENT',
      id: TRANSIENT_IDS.crossTeamActivity,
      lead_id: ana.id,
      tipo: 'nota',
    }).select('id'),
  );
  await expectBlockedMutation(
    'directorio no inserta actividades',
    sessions.directorio.client.schema('crm').from('actividades').insert({
      creado_por: sessions.directorio.user.id,
      detalle: 'RLS DIRECTORIO TRANSIENT',
      id: TRANSIENT_IDS.directoryActivity,
      lead_id: juan.id,
      tipo: 'nota',
    }).select('id'),
  );

  const juanActivity = LEADS.find((lead) => lead.key === 'juan').activityId;
  await expectBlockedMutation(
    'actividades no admite UPDATE',
    sessions.vend1.client.schema('crm').from('actividades')
      .update({ detalle: 'NO DEBE CAMBIAR' }, { count: 'exact' })
      .eq('id', juanActivity)
      .select('id'),
  );
  await expectBlockedMutation(
    'actividades no admite DELETE',
    sessions.vend1.client.schema('crm').from('actividades')
      .delete({ count: 'exact' })
      .eq('id', juanActivity)
      .select('id'),
  );

  await expectBlockedMutation(
    'crm.equipo es de solo lectura por Data API',
    sessions.sup1.client.schema('crm').from('equipo')
      .update({ activo: true }, { count: 'exact' })
      .eq('perfil_id', vend1Id)
      .select('perfil_id'),
  );

  await expectBlockedMutation(
    'cliente del portal no inserta leads CRM',
    sessions.clientBank.client.schema('crm').from('leads').insert({
      creado_por: sessions.clientBank.user.id,
      etapa: 'nuevo',
      id: TRANSIENT_IDS.portalClientLead,
      moneda: 'PEN',
      monto_estimado: 1000,
      nombre_completo: 'RLS CLIENTE TRANSIENT',
      origen: 'otro',
      telefono: '999000003',
      // Tenencia integra para que la sonda falle por RLS/rol del actor.
      vendedor_id: vend1Id,
    }).select('id'),
  );
}

async function testReassignmentTrigger(sessions, seed) {
  console.log('\n— Timeline estructurado de movimientos de tenencia —');
  const gerencia = sessions.gerencia;
  const sup1 = sessions.sup1;
  const sup1Id = seed.profileIdByKey.sup1;
  const vend1Id = seed.profileIdByKey.vend1;
  const vend2Id = seed.profileIdByKey.vend2;

  const common = {
    asignado_supervisor_id: null,
    creado_por: sup1Id,
    etapa: 'nuevo',
    moneda: 'PEN',
    monto_estimado: 1000,
    origen: 'otro',
  };

  // Desde la creación atómica (20260804165440, en prod 2026-08-04) el INSERT
  // directo sobre crm.leads está revocado para authenticated: los leads nacen
  // SOLO por crm.crear_lead_si_disponible. La sonda usa la vía legal — mismo
  // lead transitorio, mismo analista destino — y el trigger de reasignación
  // debe emitir su actividad igual que antes.
  const assignedInsert = await positive(
    'sup1 crea un lead que nace asignado',
    sup1.client.schema('crm').rpc('crear_lead_si_disponible', {
      p_id: TRANSIENT_IDS.triggerAssignedInsertLead,
      p_nombre_completo: 'TRIGGER INSERT ASIGNADO TRANSIENT',
      p_telefono: '999000006',
      p_origen: common.origen,
      p_monto_estimado: common.monto_estimado,
      p_moneda: common.moneda,
      p_vendedor_id: vend1Id,
    }),
  );
  if (assignedInsert) {
    const activities = await readReassignmentActivities(
      TRANSIENT_IDS.triggerAssignedInsertLead,
      'leer actividades del lead nacido asignado',
    );
    check(activities.count === 0,
      'INSERT de lead ya asignado no emite actividad de reasignacion',
      `emitio ${activities.count}`);
  }

  await requireAdmin(
    'crear fixture transitorio para cambio de analista',
    admin.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.triggerSellerChangeLead,
      nombre_completo: 'TRIGGER CAMBIO ANALISTA TRANSIENT',
      telefono: '999000007',
      vendedor_id: vend1Id,
    }),
  );
  const sellerChange = await positive(
    'sup1 reasigna un lead de vend1 a vend2',
    sup1.client.schema('crm').from('leads')
      .update({ vendedor_id: vend2Id })
      .eq('id', TRANSIENT_IDS.triggerSellerChangeLead)
      .select('id, vendedor_id')
      .single(),
  );
  if (sellerChange) {
    const activities = await readReassignmentActivities(
      TRANSIENT_IDS.triggerSellerChangeLead,
      'leer actividad del cambio de analista',
    );
    const [activity] = activities.rows;
    check(activities.count === 1,
      'cambio de analista emite exactamente una reasignacion',
      `emitio ${activities.count}`);
    check(activity?.detalle === `${USER_BY_KEY.vend1.name} → ${USER_BY_KEY.vend2.name}`,
      'reasignacion conserva el detalle humano exacto',
      `detalle=${activity?.detalle ?? 'ausente'}`);
    check(activity?.metadata?.vendedor_anterior === vend1Id
        && activity?.metadata?.vendedor_nuevo === vend2Id,
    'reasignacion conserva analista anterior y nuevo en metadata');
    check(activity?.creado_por === sup1Id,
      'reasignacion acredita como actor al supervisor autenticado');
  }

  await requireAdmin(
    'crear fixture transitorio para cambio solo de supervisor',
    admin.schema('crm').from('leads').insert({
      ...common,
      asignado_supervisor_id: sup1Id,
      id: TRANSIENT_IDS.triggerSupervisorOnlyLead,
      nombre_completo: 'TRIGGER CAMBIO SUPERVISOR TRANSIENT',
      telefono: '999000008',
      vendedor_id: null,
    }),
  );
  const supervisorChange = await positive(
    'gerencia cambia solo asignado_supervisor_id',
    gerencia.client.schema('crm').from('leads')
      .update({ asignado_supervisor_id: null })
      .eq('id', TRANSIENT_IDS.triggerSupervisorOnlyLead)
      .select('id, asignado_supervisor_id')
      .single(),
  );
  if (supervisorChange) {
    const activities = await readReassignmentActivities(
      TRANSIENT_IDS.triggerSupervisorOnlyLead,
      'leer actividades del cambio solo de supervisor',
    );
    const [activity] = activities.rows;
    check(activities.count === 1,
      'cambio solo de asignado_supervisor_id emite exactamente un movimiento',
      `emitio ${activities.count}`);
    check(activity?.detalle === `Bandeja de ${USER_BY_KEY.sup1.name} → Sin asignar`,
      'movimiento de bandeja conserva el detalle humano exacto',
      `detalle=${activity?.detalle ?? 'ausente'}`);
    check(activity?.metadata?.movimiento === 'sale_bandeja'
        && activity?.metadata?.supervisor_anterior === sup1Id
        && activity?.metadata?.supervisor_nuevo === null,
    'movimiento de bandeja conserva supervisor anterior/nuevo y clasificador');
    check(activity?.creado_por === seed.profileIdByKey.gerencia,
      'movimiento de bandeja acredita a Gerencia como actor');
  }

  await requireAdmin(
    'crear fixture transitorio para update sin cambio de tenencia',
    admin.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.triggerNoTenureLead,
      nombre_completo: 'TRIGGER SIN CAMBIO TENENCIA TRANSIENT',
      telefono: '999000009',
      vendedor_id: vend1Id,
    }),
  );
  const noTenureChange = await positive(
    'sup1 actualiza una nota sin cambiar tenencia',
    sup1.client.schema('crm').from('leads')
      .update({ nota: 'Caracterizacion: no debe emitir reasignacion' })
      .eq('id', TRANSIENT_IDS.triggerNoTenureLead)
      .select('id, nota')
      .single(),
  );
  if (noTenureChange) {
    const activities = await readReassignmentActivities(
      TRANSIENT_IDS.triggerNoTenureLead,
      'leer actividades del update sin cambio de tenencia',
    );
    check(activities.count === 0,
      'UPDATE sin cambio de tenencia no emite reasignacion',
      `emitio ${activities.count}`);
  }
}

/**
 * El reloj del analista — crm.leads.tenencia_desde (pedido de Miguel 2026-07-24).
 *
 * Complementa al oraculo SQL (test-tenencia.sql) por la via PostgREST REAL, que
 * es la unica que recorre grants por columna + RLS + trigger juntos. Prueba lo
 * que de verdad importa en produccion: que el analista LEA su reloj, que NO pueda
 * falsificarlo (el ACL de crm.leads es de TABLA, asi que PostgREST acepta la
 * columna en el body: la defensa es el trigger, no un 403) y que una asignacion
 * de hoy sobre un lead viejo arranque el reloj HOY.
 */
async function testTenencia(sessions, seed) {
  console.log('\n— El reloj del analista: tenencia_desde —');
  const sup1 = sessions.sup1;
  const vend1 = sessions.vend1;
  const vend3 = sessions.vend3;
  const sup1Id = seed.profileIdByKey.sup1;
  const vend1Id = seed.profileIdByKey.vend1;

  const common = {
    creado_por: sup1Id,
    etapa: 'nuevo',
    moneda: 'PEN',
    monto_estimado: 1000,
    origen: 'otro',
  };

  // ── Un lead VIEJO parkeado en la bandeja de sup1 (el caso de produccion:
  // paso dias en la cola de Rosa antes de que alguien lo bajara a un analista).
  await requireAdmin(
    'crear lead viejo parkeado para el reloj de tenencia',
    admin.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.tenenciaLeadViejo,
      nombre_completo: 'TENENCIA LEAD VIEJO TRANSIENT',
      telefono: '999000031',
      vendedor_id: null,
      asignado_supervisor_id: sup1Id,
    }),
  );

  const sinDuenio = await positive(
    'leer el lead parkeado antes de asignarlo',
    admin.schema('crm').from('leads')
      .select('id, creado_en, tenencia_desde')
      .eq('id', TRANSIENT_IDS.tenenciaLeadViejo)
      .single(),
  );
  check(sinDuenio?.data?.tenencia_desde == null,
    'un lead parkeado en bandeja NO tiene reloj de analista',
    `tenencia_desde=${sinDuenio?.data?.tenencia_desde ?? 'null'}`);

  // Envejecer creado_en exige saltarse leads_before_update (lo restaura desde
  // OLD), cosa que ni service_role puede por PostgREST. En su lugar se compara
  // contra el instante de la asignacion, que es lo que la migracion promete.
  const antesDeAsignar = Date.now();
  const asignado = await positive(
    'sup1 baja el lead de su bandeja a vend1',
    sup1.client.schema('crm').from('leads')
      .update({ vendedor_id: vend1Id, asignado_supervisor_id: null })
      .eq('id', TRANSIENT_IDS.tenenciaLeadViejo)
      .select('id, creado_en, tenencia_desde')
      .single(),
  );
  const relojAsignacion = asignado?.data?.tenencia_desde;
  check(relojAsignacion != null,
    'asignar a un analista enciende el reloj de tenencia',
    `tenencia_desde=${relojAsignacion ?? 'null'}`);
  check(relojAsignacion != null
    && Date.parse(relojAsignacion) >= antesDeAsignar - 60_000,
    'el reloj arranca en la ASIGNACION, no cuando entro el lead',
    `tenencia_desde=${relojAsignacion} creado_en=${asignado?.data?.creado_en}`);

  // ── El analista LEE su propio reloj (grant por columna + RLS).
  const leidoPorDuenio = await positive(
    'vend1 lee el reloj de su propio lead',
    vend1.client.schema('crm').from('leads')
      .select('id, tenencia_desde')
      .eq('id', TRANSIENT_IDS.tenenciaLeadViejo)
      .maybeSingle(),
  );
  check(leidoPorDuenio?.data?.tenencia_desde != null,
    'el analista recibe tenencia_desde de su lead (sin grant, PostgREST la omitiria en silencio)',
    `fila=${JSON.stringify(leidoPorDuenio?.data ?? null)}`);

  // ── INFALSIFICABLE. No esperamos un 403: el ACL de crm.leads es de TABLA, de
  // modo que PostgREST acepta la columna. Lo que la defiende es el trigger, que
  // reimpone el valor anterior — asi que el UPDATE responde OK y NO cambia nada.
  await requireAdmin(
    'crear lead propio de vend1 para el intento de falsificacion',
    admin.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.tenenciaLeadPropio,
      nombre_completo: 'TENENCIA LEAD PROPIO TRANSIENT',
      telefono: '999000032',
      vendedor_id: vend1Id,
      asignado_supervisor_id: null,
    }),
  );
  const original = await positive(
    'leer el reloj original del lead propio',
    admin.schema('crm').from('leads')
      .select('id, tenencia_desde')
      .eq('id', TRANSIENT_IDS.tenenciaLeadPropio)
      .single(),
  );
  const falsificado = new Date(Date.now() - 90 * 86_400_000).toISOString();
  await vend1.client.schema('crm').from('leads')
    .update({ tenencia_desde: falsificado })
    .eq('id', TRANSIENT_IDS.tenenciaLeadPropio);
  const trasIntento = await positive(
    'releer el reloj tras el intento de falsificacion',
    admin.schema('crm').from('leads')
      .select('id, tenencia_desde')
      .eq('id', TRANSIENT_IDS.tenenciaLeadPropio)
      .single(),
  );
  check(trasIntento?.data?.tenencia_desde === original?.data?.tenencia_desde,
    'un analista NO puede falsificar su propio reloj (lo reimpone el trigger)',
    `antes=${original?.data?.tenencia_desde} despues=${trasIntento?.data?.tenencia_desde}`);

  // ── El ruido no lo mueve: editar la nota no reinicia el reloj.
  await positive(
    'vend1 edita la nota de su lead',
    vend1.client.schema('crm').from('leads')
      .update({ nota: 'llamar por la tarde' })
      .eq('id', TRANSIENT_IDS.tenenciaLeadPropio),
  );
  const trasEditar = await positive(
    'releer el reloj tras editar la nota',
    admin.schema('crm').from('leads')
      .select('id, tenencia_desde')
      .eq('id', TRANSIENT_IDS.tenenciaLeadPropio)
      .single(),
  );
  check(trasEditar?.data?.tenencia_desde === original?.data?.tenencia_desde,
    'editar el lead no reinicia el reloj de tenencia',
    `antes=${original?.data?.tenencia_desde} despues=${trasEditar?.data?.tenencia_desde}`);

  // ── Fuera del ambito no se ve la fila (ni su reloj).
  const ajeno = await positive(
    'vend3 (otro equipo) intenta leer el lead de vend1',
    vend3.client.schema('crm').from('leads')
      .select('id, tenencia_desde')
      .eq('id', TRANSIENT_IDS.tenenciaLeadPropio),
  );
  check((ajeno?.data?.length ?? 0) === 0,
    'un analista de otro equipo no ve el lead ajeno ni su reloj',
    `filas=${ajeno?.data?.length ?? 'n/a'}`);
}

async function testAvanceEtapa(sessions, seed) {
  console.log('\n— La etapa avanza sola: conversacion vs intento —');
  const vend1 = sessions.vend1;
  const vend3 = sessions.vend3;
  const vend1Id = seed.profileIdByKey.vend1;

  const common = {
    creado_por: vend1Id,
    etapa: 'nuevo',
    moneda: 'PEN',
    monto_estimado: 1000,
    origen: 'otro',
    vendedor_id: vend1Id,
    asignado_supervisor_id: null,
  };

  for (const [id, nombre, telefono] of [
    [TRANSIENT_IDS.avanceLeadConversacion, 'AVANCE CONVERSACION TRANSIENT', '999000041'],
    [TRANSIENT_IDS.avanceLeadIntento, 'AVANCE INTENTO TRANSIENT', '999000042'],
    [TRANSIENT_IDS.avanceLeadManual, 'AVANCE MANUAL TRANSIENT', '999000043'],
  ]) {
    await requireAdmin(
      `crear ${nombre} para el avance automatico`,
      admin.schema('crm').from('leads').insert({ ...common, id, nombre_completo: nombre, telefono }),
    );
  }

  // ── El caso de Miguel, END TO END y con una sesion REAL de analista: el
  // analista registra que SI hablo con la persona y la etapa sube sola.
  await positive(
    'vend1 registra una conversacion (llamada_realizada) en su lead nuevo',
    vend1.client.schema('crm').from('actividades').insert({
      lead_id: TRANSIENT_IDS.avanceLeadConversacion,
      tipo: 'llamada_realizada',
      detalle: 'GATE contesto',
      creado_por: vend1Id,
    }),
  );
  const trasConversacion = await positive(
    'leer la etapa tras la conversacion',
    vend1.client.schema('crm').from('leads')
      .select('id, etapa')
      .eq('id', TRANSIENT_IDS.avanceLeadConversacion)
      .single(),
  );
  check(trasConversacion?.data?.etapa === 'contactado',
    'una CONVERSACION sube el lead de nuevo a contactado, sin que nadie mueva la tarjeta',
    `etapa=${trasConversacion?.data?.etapa}`);

  // ── La mitad que impide inflar el embudo: un intento fallido NO avanza. Si
  // esto se rompiera, "No contesto" seria un boton de posponer la alarma 48 h
  // (umbral nuevo 24 h → contactado 72 h) sobre alguien con quien nadie hablo.
  await positive(
    'vend1 registra un intento fallido (llamada_no_contestada)',
    vend1.client.schema('crm').from('actividades').insert({
      lead_id: TRANSIENT_IDS.avanceLeadIntento,
      tipo: 'llamada_no_contestada',
      detalle: 'GATE no contesto',
      creado_por: vend1Id,
    }),
  );
  const trasIntento = await positive(
    'leer la etapa tras el intento fallido',
    vend1.client.schema('crm').from('leads')
      .select('id, etapa')
      .eq('id', TRANSIENT_IDS.avanceLeadIntento)
      .single(),
  );
  check(trasIntento?.data?.etapa === 'nuevo',
    'un INTENTO fallido NO avanza la etapa (el embudo no se infla solo)',
    `etapa=${trasIntento?.data?.etapa}`);

  // ── El rastro: el avance queda marcado como automatico, para que el
  // historial no le atribuya al analista un movimiento que el no pidio.
  const rastro = await positive(
    'leer el cambio_etapa que escribio el trigger',
    admin.schema('crm').from('actividades')
      .select('tipo, metadata')
      .eq('lead_id', TRANSIENT_IDS.avanceLeadConversacion)
      .eq('tipo', 'cambio_etapa'),
  );
  check((rastro?.data?.length ?? 0) === 1,
    'el avance escribe EXACTAMENTE un cambio_etapa',
    `filas=${rastro?.data?.length ?? 'n/a'}`);
  check(rastro?.data?.[0]?.metadata?.automatico === true,
    'el cambio de etapa automatico queda marcado como tal en el timeline',
    `metadata=${JSON.stringify(rastro?.data?.[0]?.metadata ?? null)}`);

  // ── INFALSIFICABLE: el cliente no puede hacerse pasar por el sistema. El
  // flag vive en un set_config LOCAL a la transaccion del trigger; PostgREST no
  // da manera de encenderlo, asi que un movimiento a mano se marca manual.
  await positive(
    'vend1 mueve la etapa A MANO (lo que hace hoy arrastrando la tarjeta)',
    vend1.client.schema('crm').from('leads')
      .update({ etapa: 'contactado' })
      .eq('id', TRANSIENT_IDS.avanceLeadManual),
  );
  const rastroManual = await positive(
    'leer el cambio_etapa del movimiento manual',
    admin.schema('crm').from('actividades')
      .select('metadata')
      .eq('lead_id', TRANSIENT_IDS.avanceLeadManual)
      .eq('tipo', 'cambio_etapa'),
  );
  check(rastroManual?.data?.[0]?.metadata?.automatico === false,
    'un cambio de etapa MANUAL no se puede disfrazar de automatico',
    `metadata=${JSON.stringify(rastroManual?.data?.[0]?.metadata ?? null)}`);

  // ── La via de las TAREAS, que es donde vivia el critico C1 de la auditoria.
  const sup1 = sessions.sup1;
  const sup1Id = seed.profileIdByKey.sup1;

  // (a) Camino legitimo: el DUENIO agenda una reunion sobre su lead trabajado.
  await requireAdmin(
    'crear lead trabajado para la reunion legitima',
    admin.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.avanceLeadReunion,
      nombre_completo: 'AVANCE REUNION TRANSIENT',
      telefono: '999000044',
      etapa: 'contactado',
    }),
  );
  await positive(
    'vend1 registra un intento sobre su lead (deja rastro de trabajo)',
    vend1.client.schema('crm').from('actividades').insert({
      lead_id: TRANSIENT_IDS.avanceLeadReunion,
      tipo: 'llamada_no_contestada',
      creado_por: vend1Id,
    }),
  );
  await positive(
    'vend1 agenda una reunion sobre su propio lead',
    vend1.client.schema('crm').from('tareas').insert({
      lead_id: TRANSIENT_IDS.avanceLeadReunion,
      tipo: 'reunion',
      titulo: 'GATE reunion legitima',
      vence_en: new Date(Date.now() + 2 * 86_400_000).toISOString(),
      creado_por: vend1Id,
    }),
  );
  const trasReunion = await positive(
    'leer la etapa tras agendar la reunion',
    vend1.client.schema('crm').from('leads')
      .select('id, etapa')
      .eq('id', TRANSIENT_IDS.avanceLeadReunion)
      .single(),
  );
  check(trasReunion?.data?.etapa === 'reunion_agendada',
    'agendar una reunion sobre un lead trabajado lo sube solo a reunion_agendada',
    `etapa=${trasReunion?.data?.etapa}`);

  // (b) C1 — REGRESION PERMANENTE. Un lead de la COLA GLOBAL (sin dueno y sin
  // bandeja) que el supervisor ni siquiera puede VER. La policy tareas_insert
  // NO consulta crm.leads, asi que el INSERT de la tarea SI pasa (hueco previo,
  // fuera del alcance de esta migracion) — lo que jamas puede pasar es que
  // ARRASTRE una escritura sobre crm.leads saltandose leads_update.
  await requireAdmin(
    'crear lead de la cola global (vector de C1)',
    admin.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.avanceLeadColaGlobal,
      nombre_completo: 'AVANCE COLA GLOBAL TRANSIENT',
      telefono: '999000045',
      vendedor_id: null,
      asignado_supervisor_id: null,
    }),
  );
  await requireAdmin(
    'dejar rastro de trabajo en el lead de la cola global (peor caso)',
    admin.schema('crm').from('actividades').insert({
      lead_id: TRANSIENT_IDS.avanceLeadColaGlobal,
      tipo: 'llamada_no_contestada',
      creado_por: vend1Id,
    }),
  );
  const invisible = await positive(
    'sup1 intenta VER el lead de la cola global',
    sup1.client.schema('crm').from('leads')
      .select('id')
      .eq('id', TRANSIENT_IDS.avanceLeadColaGlobal),
  );
  check((invisible?.data?.length ?? 0) === 0,
    'el lead de la cola global es INVISIBLE para el supervisor (premisa de C1)',
    `filas=${invisible?.data?.length ?? 'n/a'}`);

  // DOS CAPAS, y las dos se prueban:
  // (1) la policy `tareas_insert` ya no acepta tareas sobre leads invisibles
  //     (migracion 20260725221530, que cerro el hueco previo que destapo C1);
  // (2) aunque alguien la reabriera, el gate de ambito DENTRO del trigger de
  //     avance impide que arrastre una escritura sobre crm.leads.
  // Desde 2026-08-08 (metas/SLA versionados) existe una TERCERA capa que corre
  // ANTES que la policy: el trigger de destino exige que toda tarea pendiente
  // tenga un destino CRM efectivo, y un lead de la cola global no lo tiene.
  // El bloqueo llega como 23514 (BEFORE trigger gana a la evaluacion WITH
  // CHECK), asi que se acepta ese codigo ademas del de RLS.
  await expectBlockedMutation(
    'sup1 intenta agendar una reunion sobre un lead de la cola global que NO puede ver',
    sup1.client.schema('crm').from('tareas').insert({
      lead_id: TRANSIENT_IDS.avanceLeadColaGlobal,
      tipo: 'reunion',
      titulo: 'GATE reunion cola global',
      vence_en: new Date(Date.now() + 2 * 86_400_000).toISOString(),
      creado_por: sup1Id,
    }),
    ['23514'],
  );

  const trasIntrusion = await positive(
    'leer la etapa del lead de la cola global tras el intento',
    admin.schema('crm').from('leads')
      .select('id, etapa')
      .eq('id', TRANSIENT_IDS.avanceLeadColaGlobal)
      .single(),
  );
  check(trasIntrusion?.data?.etapa === 'nuevo',
    'ESCALADA CERRADA: el lead de la cola global sigue en nuevo tras el intento',
    `etapa=${trasIntrusion?.data?.etapa}`);

  // La SEGUNDA capa, aislada: hasta 2026-08-08 se fabricaba con service_role
  // la tarea que la policy no deja crear, para probar que el gate del TRIGGER
  // de avance la frenaba igual. El trigger de destino (metas/SLA versionados)
  // volvio ese estado INFABRICABLE para cualquier escritor, incluido
  // service_role: la reunion sobre un lead sin dueno muere en 23514 antes de
  // existir. Se asevera exactamente eso — la defensa se movio una capa antes y
  // el gate del trigger de avance queda subsumido (su estado gatillo ya es
  // inalcanzable).
  await expectBlockedMutation(
    'ni service_role fabrica una reunion sobre el lead de la cola global (trigger de destino)',
    admin.schema('crm').from('tareas').insert({
      lead_id: TRANSIENT_IDS.avanceLeadColaGlobal,
      tipo: 'reunion',
      titulo: 'GATE reunion cola global (service_role)',
      vence_en: new Date(Date.now() + 2 * 86_400_000).toISOString(),
      creado_por: sup1Id,
    }),
    ['23514'],
  );
  const trasFabricada = await positive(
    'releer la etapa tras el intento de fabricacion bloqueado',
    admin.schema('crm').from('leads')
      .select('id, etapa')
      .eq('id', TRANSIENT_IDS.avanceLeadColaGlobal)
      .single(),
  );
  check(trasFabricada?.data?.etapa === 'nuevo',
    'DEFENSA EN PROFUNDIDAD: el lead sin dueno sigue en nuevo; el estado gatillo es infabricable',
    `etapa=${trasFabricada?.data?.etapa}`);

  // ── La via de ACTIVIDADES no lleva gate propio: toda su seguridad descansa
  // en que `actividades_insert` SI consulta crm.leads bajo RLS. Eso hay que
  // ATARLO con un tipo que MUEVA la etapa — hasta ahora el unico cross-team de
  // actividades usaba `nota`, que no avanza nada y por tanto no probaba la
  // cadena que aqui importa.
  const etapaAntes = trasConversacion?.data?.etapa;
  await expectBlockedMutation(
    'vend3 (otro subarbol) intenta registrar una conversacion en un lead ajeno',
    vend3.client.schema('crm').from('actividades').insert({
      lead_id: TRANSIENT_IDS.avanceLeadConversacion,
      tipo: 'llamada_realizada',
      creado_por: seed.profileIdByKey.vend3,
    }),
  );
  if (sessions.vendInactive) {
    await expectBlockedMutation(
      'un miembro DESACTIVADO intenta registrar una conversacion',
      sessions.vendInactive.client.schema('crm').from('actividades').insert({
        lead_id: TRANSIENT_IDS.avanceLeadConversacion,
        tipo: 'llamada_realizada',
        creado_por: seed.profileIdByKey.vendInactive,
      }),
    );
  }
  const trasIntentosAjenos = await positive(
    'releer la etapa tras los intentos ajenos',
    admin.schema('crm').from('leads')
      .select('id, etapa')
      .eq('id', TRANSIENT_IDS.avanceLeadConversacion)
      .single(),
  );
  check(trasIntentosAjenos?.data?.etapa === etapaAntes,
    'un tercero sin ambito no puede mover la etapa de un lead ajeno por la via de actividades',
    `antes=${etapaAntes} despues=${trasIntentosAjenos?.data?.etapa}`);
}

async function testTareaIsolation(sessions, seed) {
  console.log('\n— Agenda: aislamiento y privilegios de crm.tareas —');
  const llamadaJuan = TAREA_BY_KEY.llamadaJuan;
  const reunionCarlos = TAREA_BY_KEY.reunionCarlos;
  const whatsappAna = TAREA_BY_KEY.whatsappAna;
  const bandejaLuis = TAREA_BY_KEY.bandejaLuis;
  const juan = seed.leadByName.get('JUAN PEREZ DEMO');
  const vend3Id = seed.profileIdByKey.vend3;

  await expectHidden(
    'vend1 no lee la tarea de otro subarbol',
    sessions.vend1.client.schema('crm').from('tareas').select('id').eq('id', whatsappAna.id),
  );
  await expectHidden(
    'vend3 no lee la tarea de la rama anidada de sup1',
    sessions.vend3.client.schema('crm').from('tareas').select('id').eq('id', reunionCarlos.id),
  );
  await expectHidden(
    'sup1 no lee la tarea del equipo de sup2',
    sessions.sup1.client.schema('crm').from('tareas').select('id').eq('id', whatsappAna.id),
  );
  await expectHidden(
    'sup2 no lee la bandeja de tareas de sup1',
    sessions.sup2.client.schema('crm').from('tareas').select('id').eq('id', bandejaLuis.id),
  );
  await expectHidden(
    'vend1 no lee la tarea de bandeja de su propio supervisor',
    sessions.vend1.client.schema('crm').from('tareas').select('id').eq('id', bandejaLuis.id),
  );

  await expectBlockedMutation(
    'vend1 no actualiza una tarea ajena',
    sessions.vend1.client.schema('crm').from('tareas')
      .update({ nota: 'NO DEBE CAMBIAR' }, { count: 'exact' })
      .eq('id', whatsappAna.id)
      .select('id'),
  );
  await expectBlockedMutation(
    'sup1 no actualiza tareas del subarbol de sup2',
    sessions.sup1.client.schema('crm').from('tareas')
      .update({ nota: 'NO DEBE CAMBIAR' }, { count: 'exact' })
      .eq('id', whatsappAna.id)
      .select('id'),
  );
  const anaTarea = await readOneTarea(
    sessions.vend3,
    whatsappAna.id,
    'verificar tarea ajena tras escrituras cruzadas',
  );
  if (anaTarea) {
    check(anaTarea.nota === null && anaTarea.estado === 'pendiente'
        && anaTarea.vendedor_id === vend3Id,
    'la tarea ajena no fue alterada');
  }

  // Sin DELETE para nadie del API: ni el dueno ni gerencia.
  await expectBlockedMutation(
    'vend1 no puede hacer hard-delete ni de su propia tarea',
    sessions.vend1.client.schema('crm').from('tareas')
      .delete({ count: 'exact' })
      .eq('id', llamadaJuan.id)
      .select('id'),
  );
  await expectBlockedMutation(
    'gerencia tampoco puede hacer hard-delete de tareas',
    sessions.gerencia.client.schema('crm').from('tareas')
      .delete({ count: 'exact' })
      .eq('id', llamadaJuan.id)
      .select('id'),
  );

  await expectBlockedMutation(
    'vend1 no inserta una tarea acreditando a otro creador',
    sessions.vend1.client.schema('crm').from('tareas').insert({
      creado_por: vend3Id,
      id: TRANSIENT_IDS.foreignCreatorTarea,
      lead_id: juan.id,
      tipo: 'tarea',
      titulo: 'RLS CREADOR AJENO TRANSIENT',
      vence_en: '2026-08-01T15:00:00Z',
    }).select('id'),
  );

  const tareaClienteEquipo = await positive(
    'sup1 agenda una gestión sobre el cliente de vend1 sin depender de RLS de perfiles',
    sessions.sup1.client.schema('crm').from('tareas').insert({
      creado_por: seed.profileIdByKey.sup1,
      id: TRANSIENT_IDS.supervisorClientTarea,
      perfil_id: seed.profileIdByKey.clientBank,
      tipo: 'tarea',
      titulo: 'RLS SUPERVISOR CLIENTE TRANSIENT',
      vence_en: '2026-08-02T14:00:00Z',
    }).select('id, perfil_id, vendedor_id, asignado_supervisor_id').single(),
  );
  if (tareaClienteEquipo) {
    check(
      tareaClienteEquipo.data.perfil_id === seed.profileIdByKey.clientBank
        && tareaClienteEquipo.data.vendedor_id === seed.profileIdByKey.vend1
        && tareaClienteEquipo.data.asignado_supervisor_id === seed.profileIdByKey.sup1,
      'la tarea del cliente queda anclada al analista y supervisor canónicos',
      JSON.stringify(tareaClienteEquipo.data),
    );
  }

  const tareaClienteAnalista = await positive(
    'el Analista agenda una gestión sobre su propio cliente con destinos canónicos',
    sessions.vend1.client.schema('crm').from('tareas').insert({
      creado_por: seed.profileIdByKey.vend1,
      id: TRANSIENT_IDS.analystClientTarea,
      perfil_id: seed.profileIdByKey.clientBank,
      tipo: 'tarea',
      titulo: 'RLS ANALISTA CLIENTE TRANSIENT',
      vence_en: '2026-08-02T14:30:00Z',
    }).select('id, perfil_id, vendedor_id, asignado_supervisor_id').single(),
  );
  if (tareaClienteAnalista) {
    check(
      tareaClienteAnalista.data.perfil_id === seed.profileIdByKey.clientBank
        && tareaClienteAnalista.data.vendedor_id === seed.profileIdByKey.vend1
        && tareaClienteAnalista.data.asignado_supervisor_id === seed.profileIdByKey.sup1,
      'la tarea del Analista queda anclada al analista y supervisor canónicos',
      JSON.stringify(tareaClienteAnalista.data),
    );
  }

  // Completar va SOLO por la RPC: el trigger corta el UPDATE directo. Emitía
  // P0001; desde 2026-08-08 (configuración operativa) el guard reescrito emite
  // 22023. Ambos códigos prueban lo mismo: el cierre directo no pasa.
  await expectBlockedMutation(
    'vend1 no completa su tarea por UPDATE directo',
    sessions.vend1.client.schema('crm').from('tareas')
      .update({ estado: 'completada' }, { count: 'exact' })
      .eq('id', llamadaJuan.id)
      .select('id'),
    ['P0001', '22023'],
  );
  const juanTarea = await readOneTarea(
    sessions.vend1,
    llamadaJuan.id,
    'verificar tarea propia tras intento de cierre directo',
  );
  if (juanTarea) check(juanTarea.estado === 'pendiente', 'la tarea fixture sigue pendiente');

  await expectBlockedMutation(
    'directorio no actualiza tareas aunque pueda leerlas',
    sessions.directorio.client.schema('crm').from('tareas')
      .update({ nota: 'NO DEBE CAMBIAR' }, { count: 'exact' })
      .eq('id', llamadaJuan.id)
      .select('id'),
  );
  await expectBlockedMutation(
    'directorio no inserta tareas',
    sessions.directorio.client.schema('crm').from('tareas').insert({
      creado_por: sessions.directorio.user.id,
      id: TRANSIENT_IDS.directoryTarea,
      lead_id: juan.id,
      tipo: 'tarea',
      titulo: 'RLS DIRECTORIO TAREA TRANSIENT',
      vence_en: '2026-08-02T15:00:00Z',
    }).select('id'),
  );
  await expectBlockedMutation(
    'directorio no cierra tareas por la RPC',
    sessions.directorio.client.schema('crm').rpc('cerrar_tarea', {
      p_estado: 'completada',
      p_resultado_tipo: 'llamada_realizada',
      p_tarea_id: llamadaJuan.id,
    }),
    ['P0001'],
  );

  await expectHidden(
    'cliente del portal no lee tareas CRM',
    sessions.clientBank.client.schema('crm').from('tareas').select('id').eq('id', llamadaJuan.id),
  );
  await expectBlockedMutation(
    'cliente del portal no inserta tareas CRM',
    sessions.clientBank.client.schema('crm').from('tareas').insert({
      creado_por: sessions.clientBank.user.id,
      id: TRANSIENT_IDS.portalClientTarea,
      lead_id: juan.id,
      tipo: 'tarea',
      titulo: 'RLS CLIENTE TAREA TRANSIENT',
      vence_en: '2026-08-02T16:00:00Z',
    }).select('id'),
  );
}

async function testTareaCloseRpc(sessions, seed) {
  console.log('\n— Agenda: cierre atomico por crm.cerrar_tarea —');
  const juan = seed.leadByName.get('JUAN PEREZ DEMO');
  const vend1 = sessions.vend1;
  const vend1Id = seed.profileIdByKey.vend1;

  const inserted = await positive(
    'vend1 agenda una llamada sobre su propio lead',
    vend1.client.schema('crm').from('tareas').insert({
      creado_por: vend1.user.id,
      id: TRANSIENT_IDS.rpcCloseTarea,
      lead_id: juan.id,
      tipo: 'llamada',
      titulo: 'RLS RPC CIERRE TRANSIENT',
      vence_en: '2026-08-03T15:00:00Z',
    }).select('id, vendedor_id, asignado_supervisor_id, estado').single(),
  );
  if (!inserted) return;
  check(inserted.data.vendedor_id === vend1Id && inserted.data.asignado_supervisor_id === null,
    'el trigger derivo la tenencia de la tarea desde el lead');
  check(inserted.data.estado === 'pendiente', 'la tarea transitoria nace pendiente');

  const closed = await positive(
    'vend1 cierra SU tarea con la RPC (completada + resultado)',
    vend1.client.schema('crm').rpc('cerrar_tarea', {
      p_estado: 'completada',
      p_resultado_detalle: 'RLS RPC CIERRE TRANSIENT',
      p_resultado_tipo: 'llamada_realizada',
      p_tarea_id: TRANSIENT_IDS.rpcCloseTarea,
    }),
  );
  if (!closed) return;
  const actividadId = closed.data?.actividad_id ?? null;
  check(closed.data?.ok === true && Boolean(actividadId),
    'la RPC devolvio ok y el id de la actividad de resultado');

  const tareaAfter = await readOneTarea(
    vend1,
    TRANSIENT_IDS.rpcCloseTarea,
    'releer la tarea cerrada por la RPC',
  );
  if (tareaAfter) {
    check(tareaAfter.estado === 'completada', 'la tarea quedo completada');
    check(tareaAfter.resultado_actividad_id === actividadId,
      'la tarea apunta a la actividad del log');
  }

  if (actividadId) {
    const actividad = await positive(
      'vend1 lee la actividad que registro el cierre',
      vend1.client.schema('crm').from('actividades')
        .select('id, lead_id, tipo, creado_por')
        .eq('id', actividadId)
        .single(),
    );
    if (actividad) {
      check(actividad.data.lead_id === juan.id
          && actividad.data.tipo === 'llamada_realizada'
          && actividad.data.creado_por === vend1.user.id,
      'la actividad de cierre quedo en el log del lead correcto');
    }
  }

  // Cerrada => inmutable: nadie la reabre por UPDATE directo (trigger; P0001
  // histórico, 22023 desde la configuración operativa 2026-08-08).
  await expectBlockedMutation(
    'vend1 no reabre una tarea cerrada',
    vend1.client.schema('crm').from('tareas')
      .update({ estado: 'pendiente' }, { count: 'exact' })
      .eq('id', TRANSIENT_IDS.rpcCloseTarea)
      .select('id'),
    ['P0001', '22023'],
  );
  // Restauracion: ver cleanupTransientRows — la tarea cerrada y su actividad de
  // resultado QUEDAN (log INSERT-only; borrar la actividad es imposible porque
  // el SET NULL de la FK dispara el trigger de inmutabilidad de la cerrada).
}

// ── Anular con AUTORIA + retroceso de etapa (migracion 20260726151751) ────────
// Pedidos de Miguel (2026-07-26): "separa lo que cancela el sistema y lo que
// cancela el analista" y "si se anula la reu y no se reagenda una en ese mismo
// momento, deberia bajar de etapa".
//
// Lo que se asevera aqui es la parte que NO se puede probar en el front: que la
// etiqueta `cancelada_por` la escribe el SERVIDOR y es INFALSIFICABLE, y que el
// retroceso de etapa (SECURITY DEFINER sobre crm.leads, saltandose leads_update)
// no se convierte en un vector para mover leads ajenos.
async function testAnularAutoriaYRetroceso(sessions, seed) {
  console.log('\n— Agenda: anular con autoria y retroceso de etapa —');
  const vend1 = sessions.vend1;
  const vend1Id = seed.profileIdByKey.vend1;
  const sup1Id = seed.profileIdByKey.sup1;

  const leerTarea = (id, label) => requireAdmin(
    label,
    admin.schema('crm').from('tareas')
      .select('estado, cancelada_por, cancelada_por_id, vendedor_id').eq('id', id).single(),
  );
  const leerEtapa = (id, label) => requireAdmin(
    label,
    admin.schema('crm').from('leads').select('etapa').eq('id', id).single(),
  );

  await requireAdmin(
    'crear lead transitorio para anular (ya CONTACTADO)',
    admin.schema('crm').from('leads').insert({
      creado_por: sup1Id,
      etapa: 'contactado',
      id: TRANSIENT_IDS.anularLead,
      moneda: 'PEN',
      monto_estimado: 1000,
      nombre_completo: 'ANULAR RETROCESO TRANSIENT',
      origen: 'otro',
      telefono: '999000020',
      vendedor_id: vend1Id,
    }),
  );
  // Contacto REAL: sin el, el trigger de subida no asciende (y el de bajada no
  // tendria de donde volver a `contactado`).
  await positive(
    'vend1 registra un contacto real sobre el lead transitorio',
    vend1.client.schema('crm').from('actividades').insert({
      creado_por: vend1.user.id,
      detalle: 'RLS ANULAR TRANSIENT',
      lead_id: TRANSIENT_IDS.anularLead,
      tipo: 'llamada_realizada',
    }).select('id').single(),
  );

  const reunion = await positive(
    'vend1 agenda una REUNION sobre el lead transitorio',
    vend1.client.schema('crm').from('tareas').insert({
      creado_por: vend1.user.id,
      id: TRANSIENT_IDS.anularTareaReunion,
      lead_id: TRANSIENT_IDS.anularLead,
      tipo: 'reunion',
      titulo: 'RLS ANULAR REUNION TRANSIENT',
      vence_en: '2027-01-04T15:00:00Z',
    }).select('id').single(),
  );
  if (!reunion) return;
  const trasAgendar = await leerEtapa(TRANSIENT_IDS.anularLead, 'releer la etapa tras agendar');
  check(trasAgendar.data.etapa === 'reunion_agendada',
    'agendar la reunion subio el lead a reunion_agendada',
    `etapa=${trasAgendar.data.etapa}`);

  // 1) EL PORTAZO NUEVO: cancelar por PATCH directo deja de estar permitido.
  //    Antes de esta migracion, `cancelada` era el unico cierre que no exigia la
  //    RPC: un analista podia vaciar su agenda por /rest/v1/tareas SIN quedar
  //    etiquetado y saltandose el retroceso de etapa.
  await expectBlockedMutation(
    'vend1 NO puede anular por UPDATE directo (tiene que pasar por la RPC)',
    vend1.client.schema('crm').from('tareas')
      .update({ estado: 'cancelada' }, { count: 'exact' })
      .eq('id', TRANSIENT_IDS.anularTareaReunion)
      .select('id'),
    // P0001 histórico; 22023 desde la configuración operativa 2026-08-08.
    ['P0001', '22023'],
  );

  // 2) LA ETIQUETA NO SE PUEDE INYECTAR — y desde 20260829175638 la defensa es
  //    MAS temprana: `authenticated` ya ni siquiera tiene UPDATE sobre
  //    crm.tareas, asi que la inyeccion del analista muere en la capa de
  //    permisos (42501), antes de que el trigger tenga nada que decir.
  //    Historia: el contrato original (20260727032429) era "no-op silencioso
  //    del BEFORE trigger" y quedo MUERTO con esa revocacion; la suite no pudo
  //    correr entre ambas fechas (0 demos en prod) y el banco lo destapo el
  //    01/09. El contrato del trigger NO se pierde: se prueba en 2b con el
  //    unico rol que conserva UPDATE.
  //    ⚠️ Codex (01/09) refutó la primera versión de este arreglo: usaba
  //    `expectBlockedMutation`, que acepta CUALQUIER portazo de autorización y
  //    hasta cero filas sin error — no exigía el 42501. Aquí el contrato ES el
  //    codigo y el mensaje exactos, así que va con el helper estricto.
  await expectExpectedFailure(
    'vend1 intenta escribir cancelada_por="sistema" en una tarea viva (sin UPDATE desde 20260829175638)',
    vend1.client.schema('crm').from('tareas')
      .update({ cancelada_por: 'sistema' })
      .eq('id', TRANSIENT_IDS.anularTareaReunion)
      .select('id'),
    ['42501'],
    /permission denied.*tareas/i,
  );
  await expectExpectedFailure(
    'vend1 intenta firmar una tarea viva como si la hubiera anulado sup1 (sin UPDATE desde 20260829175638)',
    vend1.client.schema('crm').from('tareas')
      .update({ cancelada_por_id: sup1Id })
      .eq('id', TRANSIENT_IDS.anularTareaReunion)
      .select('id'),
    ['42501'],
    /permission denied.*tareas/i,
  );

  // 2b) EL TRIGGER SIGUE PROBADO, por el llamador MAS fuerte. service_role SI
  //     conserva UPDATE, y el BEFORE trigger reescribe etiqueta y firma desde
  //     `old` (no-op silencioso) salvo que la RPC encienda su GUC
  //     (crm.op_tarea / crm.cancela_sistema — es exencion por GUC, no por rol).
  //     Si un dia el trigger muere, esto se pone rojo aunque los permisos
  //     sigan bien: son dos defensas y cada una tiene su aserción.
  const forjadaAdmin = await positive(
    'service_role intenta inyectar etiqueta y firma en una tarea viva',
    admin.schema('crm').from('tareas')
      .update({ cancelada_por: 'sistema', cancelada_por_id: sup1Id })
      .eq('id', TRANSIENT_IDS.anularTareaReunion)
      .select('id, estado, cancelada_por, cancelada_por_id')
      .single(),
  );
  if (forjadaAdmin) {
    check(forjadaAdmin.data.cancelada_por === null
        && forjadaAdmin.data.cancelada_por_id === null
        && forjadaAdmin.data.estado === 'pendiente',
      'el trigger reescribe etiqueta y firma desde old (no-op) incluso para service_role',
      JSON.stringify(forjadaAdmin.data));
  }

  // 3) Por la RPC sí, y queda firmada con el sentinel legacy `asesor`.
  const anulada = await positive(
    'vend1 anula SU reunion por crm.cerrar_tarea',
    vend1.client.schema('crm').rpc('cerrar_tarea', {
      p_estado: 'cancelada',
      p_resultado_detalle: null,
      p_resultado_tipo: null,
      p_tarea_id: TRANSIENT_IDS.anularTareaReunion,
    }),
  );
  if (!anulada) return;
  const filaAnulada = await leerTarea(TRANSIENT_IDS.anularTareaReunion, 'releer la reunion anulada');
  check(filaAnulada.data.estado === 'cancelada' && filaAnulada.data.cancelada_por === 'asesor',
    'la anulacion quedo firmada con el sentinel legacy `asesor`',
    `cancelada_por=${filaAnulada.data.cancelada_por}`);
  // 20260727032429: y la firma es EL PROPIO analista, o sea PROPIA — la unica
  // clase de anulacion que sigue pesando en su % de cumplimiento.
  check(filaAnulada.data.cancelada_por_id === vend1Id,
    'la firma es el analista que la ordeno (anulacion PROPIA: cuenta en su %)',
    `cancelada_por_id=${filaAnulada.data.cancelada_por_id}`);
  check(filaAnulada.data.cancelada_por_id === filaAnulada.data.vendedor_id,
    'firma == dueño de la tarea, que es como la metrica la clasifica como propia');
  check(anulada.data?.actividad_id == null,
    'anular NO escribe actividad de resultado en el log');

  // 4) EL RETROCESO: sin reunion viva, el lead vuelve a contactado.
  const trasAnular = await leerEtapa(TRANSIENT_IDS.anularLead, 'releer la etapa tras anular');
  check(trasAnular.data.etapa === 'contactado',
    'anular la ultima reunion devolvio el lead a contactado',
    `etapa=${trasAnular.data.etapa}`);

  // 5) Anular una LLAMADA no mueve ninguna etapa (el trigger filtra por tipo).
  const llamada = await positive(
    'vend1 agenda una llamada sobre el mismo lead',
    vend1.client.schema('crm').from('tareas').insert({
      creado_por: vend1.user.id,
      id: TRANSIENT_IDS.anularTareaLlamada,
      lead_id: TRANSIENT_IDS.anularLead,
      tipo: 'llamada',
      titulo: 'RLS ANULAR LLAMADA TRANSIENT',
      vence_en: '2027-01-05T15:00:00Z',
    }).select('id').single(),
  );
  if (llamada) {
    await positive(
      'vend1 anula esa llamada',
      vend1.client.schema('crm').rpc('cerrar_tarea', {
        p_estado: 'cancelada',
        p_resultado_detalle: null,
        p_resultado_tipo: null,
        p_tarea_id: TRANSIENT_IDS.anularTareaLlamada,
      }),
    );
    const sinCambio = await leerEtapa(TRANSIENT_IDS.anularLead, 'releer la etapa tras anular la llamada');
    check(sinCambio.data.etapa === 'contactado',
      'anular una LLAMADA no mueve la etapa',
      `etapa=${sinCambio.data.etapa}`);
  }

  // 6) LA OTRA MITAD DE LA SEPARACION: lo que cancela el SISTEMA. Descartar el
  //    lead cancela sus pendientes por trigger, y esas NO son gestion de nadie:
  //    contarlas en el denominador de pct_completadas era lo que hacia que
  //    cerrar bien un lead le bajara la nota al analista.
  await requireAdmin(
    'crear lead transitorio para la cancelacion del SISTEMA',
    admin.schema('crm').from('leads').insert({
      creado_por: sup1Id,
      etapa: 'contactado',
      id: TRANSIENT_IDS.anularLeadSistema,
      moneda: 'PEN',
      monto_estimado: 1000,
      nombre_completo: 'ANULAR SISTEMA TRANSIENT',
      origen: 'otro',
      telefono: '999000021',
      vendedor_id: vend1Id,
    }),
  );
  const tareaSistema = await positive(
    'vend1 agenda una tarea sobre el lead que se va a descartar',
    vend1.client.schema('crm').from('tareas').insert({
      creado_por: vend1.user.id,
      id: TRANSIENT_IDS.anularTareaSistema,
      lead_id: TRANSIENT_IDS.anularLeadSistema,
      tipo: 'whatsapp',
      titulo: 'RLS ANULAR SISTEMA TRANSIENT',
      vence_en: '2027-01-06T15:00:00Z',
    }).select('id').single(),
  );
  if (tareaSistema) {
    await positive(
      'vend1 descarta el lead (el trigger cancela sus pendientes)',
      vend1.client.schema('crm').from('leads')
        .update({ etapa: 'descartado', motivo_descarte: 'sin_interes' })
        .eq('id', TRANSIENT_IDS.anularLeadSistema)
        .select('id')
        .single(),
    );
    const filaSistema = await leerTarea(
      TRANSIENT_IDS.anularTareaSistema,
      'releer la tarea cancelada por el trigger',
    );
    check(filaSistema.data.estado === 'cancelada' && filaSistema.data.cancelada_por === 'sistema',
      'la cancelacion automatica quedo firmada por el SISTEMA, no por el analista',
      `cancelada_por=${filaSistema.data.cancelada_por}`);
    // 20260727032429: sin persona no hay firma. Si aqui quedara un uuid, el
    // CHECK tareas_cancelada_por_id_valida ni siquiera habria dejado escribir.
    check(filaSistema.data.cancelada_por_id === null,
      'una cancelacion de SISTEMA no lleva firma: no hay a quien atribuirla',
      `cancelada_por_id=${filaSistema.data.cancelada_por_id}`);
  }

  // 7) EL CASO QUE MOTIVA 20260727032429: el SUPERVISOR anula la tarea de su
  //    analista. La fila se sigue agrupando por vendedor_id (como el resto de
  //    metricas de agenda), asi que sin una firma distinta no habria forma de
  //    saber que esa anulacion no fue suya — y le bajaba el % por una decision
  //    que no tomo y sobre la que no podia hacer nada.
  await requireAdmin(
    'crear lead transitorio para la anulacion AJENA',
    admin.schema('crm').from('leads').insert({
      creado_por: sup1Id,
      etapa: 'contactado',
      id: TRANSIENT_IDS.anularLeadAjena,
      moneda: 'PEN',
      monto_estimado: 1000,
      nombre_completo: 'ANULAR AJENA TRANSIENT',
      origen: 'otro',
      telefono: '999000022',
      vendedor_id: vend1Id,
    }),
  );
  const tareaAjena = await positive(
    'vend1 agenda una tarea que luego le anulara su supervisor',
    vend1.client.schema('crm').from('tareas').insert({
      creado_por: vend1.user.id,
      id: TRANSIENT_IDS.anularTareaAjena,
      lead_id: TRANSIENT_IDS.anularLeadAjena,
      tipo: 'whatsapp',
      titulo: 'RLS ANULAR AJENA TRANSIENT',
      vence_en: '2027-01-07T15:00:00Z',
    }).select('id').single(),
  );
  if (tareaAjena) {
    await positive(
      'sup1 anula por la RPC una tarea de SU analista',
      sessions.sup1.client.schema('crm').rpc('cerrar_tarea', {
        p_estado: 'cancelada',
        p_resultado_detalle: null,
        p_resultado_tipo: null,
        p_tarea_id: TRANSIENT_IDS.anularTareaAjena,
      }),
    );
    const filaAjena = await leerTarea(TRANSIENT_IDS.anularTareaAjena, 'releer la tarea anulada por el jefe');
    check(filaAjena.data.estado === 'cancelada' && filaAjena.data.cancelada_por === 'asesor',
      'anular siendo supervisor tambien es una PERSONA: sentinel legacy `asesor`',
      `cancelada_por=${filaAjena.data.cancelada_por}`);
    check(filaAjena.data.cancelada_por_id === sup1Id,
      'la firma es el SUPERVISOR que la ordeno, no el analista',
      `cancelada_por_id=${filaAjena.data.cancelada_por_id}`);
    check(filaAjena.data.cancelada_por_id !== filaAjena.data.vendedor_id,
      'firma != dueño de la tarea: la metrica la clasifica como AJENA y la saca del % del analista',
      `firma=${filaAjena.data.cancelada_por_id} dueño=${filaAjena.data.vendedor_id}`);
  }

  // 8) INVARIANTE DE TODO EL MECANISMO (B1 de la auditoria): ninguna anulacion
  //    humana puede quedarse SIN firma. Si alguna lo hiciera, la metrica la
  //    mandaria a "ajena" en silencio y desapareceria del denominador de todos.
  //    El CHECK la permite a proposito (historia inatribuible del backfill), asi
  //    que la garantia para las filas NUEVAS tiene que vivir aqui, en el gate.
  const huerfanas = await requireAdmin(
    'buscar anulaciones con sentinel legacy `asesor` sin firma',
    admin.schema('crm').from('tareas')
      .select('id')
      .eq('cancelada_por', 'asesor')
      .is('cancelada_por_id', null),
  );
  if (huerfanas) {
    check(huerfanas.data.length === 0,
      'ninguna anulacion con sentinel legacy `asesor` quedo sin firma (si no, saldria del % de todos en silencio)',
      `huerfanas=${huerfanas.data.length}`);
  }
}

async function testTareaFollowsLead(sessions, seed) {
  console.log('\n— Agenda: la tarea pendiente sigue al lead reasignado —');
  const sup1 = sessions.sup1;
  const sup1Id = seed.profileIdByKey.sup1;
  const vend1Id = seed.profileIdByKey.vend1;
  const vend2Id = seed.profileIdByKey.vend2;

  await requireAdmin(
    'crear lead transitorio para el seguimiento de tareas',
    admin.schema('crm').from('leads').insert({
      asignado_supervisor_id: null,
      creado_por: sup1Id,
      etapa: 'nuevo',
      id: TRANSIENT_IDS.taskFollowLead,
      moneda: 'PEN',
      monto_estimado: 1000,
      nombre_completo: 'TAREA SIGUE AL LEAD TRANSIENT',
      origen: 'otro',
      telefono: '999000010',
      vendedor_id: vend1Id,
    }),
  );

  const inserted = await positive(
    'vend1 agenda una tarea sobre el lead transitorio',
    sessions.vend1.client.schema('crm').from('tareas').insert({
      creado_por: sessions.vend1.user.id,
      id: TRANSIENT_IDS.taskFollowTarea,
      lead_id: TRANSIENT_IDS.taskFollowLead,
      tipo: 'whatsapp',
      titulo: 'RLS TAREA SIGUE AL LEAD TRANSIENT',
      vence_en: '2026-08-04T15:00:00Z',
    }).select('id, vendedor_id').single(),
  );
  if (!inserted) return;
  check(inserted.data.vendedor_id === vend1Id, 'la tarea nace con la tenencia del lead (vend1)');

  const reassigned = await positive(
    'sup1 reasigna el lead transitorio de vend1 a vend2',
    sup1.client.schema('crm').from('leads')
      .update({ vendedor_id: vend2Id })
      .eq('id', TRANSIENT_IDS.taskFollowLead)
      .select('id, vendedor_id')
      .single(),
  );
  if (!reassigned) return;

  const tareaRow = await requireAdmin(
    'leer la tarea tras la reasignacion (service_role)',
    admin.schema('crm').from('tareas')
      .select('vendedor_id, asignado_supervisor_id, estado')
      .eq('id', TRANSIENT_IDS.taskFollowTarea)
      .single(),
  );
  check(tareaRow.data.vendedor_id === vend2Id && tareaRow.data.asignado_supervisor_id === null,
    'la tarea pendiente siguio al nuevo analista',
    `vendedor_id=${tareaRow.data.vendedor_id}`);
  check(tareaRow.data.estado === 'pendiente', 'el seguimiento no altero el estado de la tarea');

  const vend2Read = await positive(
    'vend2 ya ve la tarea que siguio a su lead',
    sessions.vend2.client.schema('crm').from('tareas')
      .select('id')
      .eq('id', TRANSIENT_IDS.taskFollowTarea)
      .single(),
  );
  if (vend2Read) {
    check(vend2Read.data.id === TRANSIENT_IDS.taskFollowTarea, 'vend2 lee la tarea reasignada');
  }
  await expectHidden(
    'vend1 dejo de ver la tarea que siguio al lead',
    sessions.vend1.client.schema('crm').from('tareas')
      .select('id')
      .eq('id', TRANSIENT_IDS.taskFollowTarea),
  );
  // Restauracion: cleanupTransientRows desactiva el lead transitorio y el
  // trigger de coherencia cancela su tarea pendiente (mismo cierre que prod).
}

async function testAgendaIcs(sessions, seed) {
  console.log('\n— Agenda ICS: token privado por miembro —');
  const vend1 = sessions.vend1.client;
  const sup1 = sessions.sup1.client;
  const gerencia = sessions.gerencia.client;
  const directorio = sessions.directorio.client;
  const vend1Id = seed.profileIdByKey.vend1;
  const sup1Id = seed.profileIdByKey.sup1;

  // La fila es idempotente por PK (perfil_id): la primera corrida la crea el
  // PROPIO vend1 y las siguientes la reutilizan. No hay nada que limpiar:
  // service_role solo tiene SELECT aqui (la edge), sin INSERT/DELETE.
  let tokenAntes = null;
  const propia = await positive(
    'vend1 lee su propia fila de agenda_ics',
    vend1.schema('crm').from('agenda_ics').select('token').eq('perfil_id', vend1Id).maybeSingle(),
  );
  if (propia && propia.data) {
    tokenAntes = propia.data.token;
  } else if (propia) {
    const creada = await positive(
      'vend1 crea su fila de agenda_ics',
      vend1.schema('crm').from('agenda_ics').insert({ perfil_id: vend1Id }).select('token').single(),
    );
    if (creada) tokenAntes = creada.data.token;
  }
  check(Boolean(tokenAntes), 'la fila propia tiene token autogenerado');

  // Rotar cambia el token. El uuid nuevo se genera en el cliente: PostgREST
  // no evalua gen_random_uuid() en un UPDATE.
  const rotada = await positive(
    'vend1 rota su token',
    vend1.schema('crm').from('agenda_ics')
      .update({ token: randomUUID(), rotado_en: new Date().toISOString() })
      .eq('perfil_id', vend1Id)
      .select('token')
      .single(),
  );
  if (rotada) {
    check(rotada.data.token !== tokenAntes, 'la rotacion cambio el token');
  }

  // El token es privado incluso hacia ARRIBA: ni su supervisor, ni gerencia,
  // ni el lector global lo ven (a diferencia de leads/tareas, aqui no hay
  // visibilidad jerarquica — el feed ICS es un secreto personal).
  await expectHidden(
    'sup1 no ve el token de su analista',
    sup1.schema('crm').from('agenda_ics').select('token').eq('perfil_id', vend1Id),
  );
  await expectHidden(
    'gerencia no ve el token de vend1',
    gerencia.schema('crm').from('agenda_ics').select('token').eq('perfil_id', vend1Id),
  );
  await expectHidden(
    'directorio (lector global) no ve el token de vend1',
    directorio.schema('crm').from('agenda_ics').select('token').eq('perfil_id', vend1Id),
  );

  // Tampoco se alcanza por escritura, y nadie crea filas a nombre de otro.
  await expectBlockedMutation(
    'sup1 no puede rotar el token de vend1',
    sup1.schema('crm').from('agenda_ics')
      .update({ rotado_en: new Date().toISOString() })
      .eq('perfil_id', vend1Id)
      .select('perfil_id'),
  );
  await expectBlockedMutation(
    'vend1 no puede crear la fila de su supervisor',
    vend1.schema('crm').from('agenda_ics').insert({ perfil_id: sup1Id }).select('perfil_id'),
  );

  // Sin DELETE ni para el dueno: dejar de compartir = rotar el token.
  await expectBlockedMutation(
    'vend1 no puede borrar ni su propia fila',
    vend1.schema('crm').from('agenda_ics').delete().eq('perfil_id', vend1Id).select('perfil_id'),
  );

  // Fuera de crm.equipo no hay feed: el WITH CHECK deja pasar la fila propia
  // pero la FK a crm.equipo corta (23503) — directorio no esta enrolado.
  await expectBlockedMutation(
    'directorio no puede crear su fila (no esta en crm.equipo)',
    directorio.schema('crm').from('agenda_ics')
      .insert({ perfil_id: seed.profileIdByKey.directorio })
      .select('perfil_id'),
    ['23503'],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Domicilio legal faltante (migración 20260819162752)
//
// Por qué existe este bloque: la migración abre por primera vez la escritura de
// `public.perfiles.domicilio` a toda la cartera del CRM —hasta hoy solo Gerencia
// podía— y ese dato se imprime LITERAL en el contrato. Sin sondas aquí, el
// alcance del gate prestado sería una afirmación del comentario, no un hecho.
//
// ⚠️ Va ANTES de testOffboardingMatrix a propósito: ese bloque puede abortar la
// corrida y llevarse por delante todo lo posterior (testAnon incluido). Por eso
// las sondas anon del domicilio viven AQUÍ dentro y no en testAnon.
//
// ⚠️ Este bloque DEJA ESCRITO el domicilio de clientBank y no puede deshacerlo:
// el trigger `perfiles_domicilio_legal_no_borrar` prohíbe volver a NULL incluso
// con service_role. Es coherente con que el gate ya no sea re-ejecutable sobre
// la misma base (relanzar = reset_branch + seed), pero se dice en voz alta.
// Por eso las sondas de LECTURA y de RECHAZO corren primero, con el hueco aún
// abierto, y las de escritura al final.
async function testDomicilioLegal(sessions, seed) {
  console.log('\n— Domicilio legal faltante —');
  const clienteId = seed.profileIdByKey[BANK_CLIENT.key];
  const noCliente = seed.profileIdByKey.vend2;
  const inexistente = '00000000-0000-4000-8000-000000000000';
  const DOMICILIO_OK = 'Av. Los Alamos 123, San Isidro, Lima';
  assertSeed(typeof clienteId === 'string', 'falta el cliente bancario para la sonda de domicilio');
  assertSeed(typeof noCliente === 'string', 'falta vend2 para la sonda de sujeto no-cliente');

  const leer = (sesion, id = clienteId) =>
    sesion.schema('crm').rpc('datos_legales_contrato_fn', { p_cliente_id: id });
  const escribir = (sesion, texto, id = clienteId) =>
    sesion.schema('crm').rpc('completar_domicilio_cliente', {
      p_cliente_id: id,
      p_domicilio: texto,
    });

  const domicilioActual = async () => {
    const { data } = await admin.from('perfiles').select('domicilio').eq('id', clienteId).single();
    return data?.domicilio ?? null;
  };

  check(
    (await domicilioActual()) === null,
    'el cliente de la sonda arranca SIN domicilio (si no, este bloque no prueba nada)',
  );

  // ── Lectura autorizada, con el hueco abierto ──────────────────────────────
  // vend1 pasa SIN tocar su rol de portal: el ámbito CRM
  // (private.vendedor_ids_visibles) basta por sí solo. Es distinto de la sonda
  // bancaria, que sí necesita `analista` porque public.crear_contrato lo exige.
  const lectura = await positive(
    'el analista de la cartera ve que falta el domicilio',
    leer(sessions.vend1.client),
  );
  if (lectura) {
    const r = lectura.data ?? {};
    check(r.falta_domicilio === true, 'la lectura declara el domicilio ausente');
    check(Array.isArray(r.faltan_cliente) && r.faltan_cliente.includes('domicilio'),
      'el domicilio aparece nombrado en faltan_cliente');
    check(Array.isArray(r.faltan_analista),
      'faltan_analista viaja siempre, aunque esté vacío');
    check(!Object.prototype.hasOwnProperty.call(r, 'domicilio'),
      'la lectura NO devuelve el valor del domicilio, solo nombres de campo');
  }

  await positive(
    'el supervisor del árbol del analista también alcanza al cliente',
    leer(sessions.sup1.client),
  );
  await positive(
    'gerencia alcanza a cualquier cliente activo',
    leer(sessions.gerencia.client),
  );

  // ── Quién NO alcanza ──────────────────────────────────────────────────────
  const ajeno = await expectExpectedFailure(
    'un analista de OTRO subárbol no lee los datos legales',
    leer(sessions.vend3.client),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  await expectExpectedFailure(
    'un analista de OTRO subárbol tampoco escribe el domicilio',
    escribir(sessions.vend3.client, DOMICILIO_OK),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  await expectExpectedFailure(
    'el supervisor de OTRO subárbol tampoco alcanza',
    escribir(sessions.sup2.client, DOMICILIO_OK),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  await expectExpectedFailure(
    'coordinación no tiene ámbito de cartera y queda fuera',
    escribir(sessions.coordinador.client, DOMICILIO_OK),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  await expectExpectedFailure(
    'el lector global sin membresía CRM queda fuera',
    escribir(sessions.directorio.client, DOMICILIO_OK),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  await expectExpectedFailure(
    'el propio cliente no puede escribirse el domicilio legal',
    escribir(sessions.clientBank.client, DOMICILIO_OK),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  await expectExpectedFailure(
    'un sujeto que NO es cliente se rechaza igual',
    escribir(sessions.vend1.client, DOMICILIO_OK, noCliente),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );

  // Mismo MENSAJE para «ajeno» que para «no existe»: si difirieran, la función
  // sería un buscador de clientes de otras carteras.
  const fantasma = await expectExpectedFailure(
    'un cliente inexistente da el MISMO rechazo que uno ajeno (sin oráculo de existencia)',
    leer(sessions.vend1.client, inexistente),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  check(ajeno === fantasma,
    'ajeno e inexistente se rechazan por la misma vía');

  // ── Lo que no puede entrar como domicilio ─────────────────────────────────
  // Con el hueco AÚN abierto: cada rechazo tiene que dejar la columna intacta.
  const basura = [
    ['cuatro caracteres', 'Lima'],
    ['241 caracteres', 'a'.repeat(241)],
    // Campana (0x07), no tabulador: el tabulador es espacio en blanco y ambos
    // lados lo colapsan a un espacio normal — que es el comportamiento bueno.
    // Lo destapó el oráculo SQL esperando un rechazo que no tocaba.
    ['un control C0', 'Av. Lima\u0007x'],
    ['seis espacios de ancho cero', '​'.repeat(6)],
    ['seis guiones suaves', '­'.repeat(6)],
    ['un invisible escondido dentro', 'Av. Los​ Alamos 123, Lima'],
  ];
  for (const [nombre, texto] of basura) {
    await expectExpectedFailure(
      `se rechaza un domicilio con ${nombre}`,
      escribir(sessions.vend1.client, texto),
      ['22023', 'P0001'],
      /domicilio legal/i,
    );
  }
  check((await domicilioActual()) === null,
    'ningún rechazo dejó rastro: la columna sigue vacía');

  // ── Superficie pública ────────────────────────────────────────────────────
  // Aceptar PGRST202 ("no existe esa función") como rechazo es tautológico si la
  // migración no se aplicó: la sonda pasaría en verde precisamente cuando NO hay
  // nada que proteger. El ancla es la sonda de lectura de más arriba: si las dos
  // RPC concedidas no respondieran, este bloque ya habría fallado mucho antes.
  // Por eso se exige haber leído bien ANTES de aceptar aquí un «no existe».
  check(lectura !== false,
    'las RPC del domicilio responden: el «no existe» de la sonda siguiente es real, no la migración ausente');
  await expectExplicitAuthorizationDenied(
    'el normalizador NO es superficie pública ni para un analista autorizado',
    sessions.vend1.client.schema('crm').rpc('normalizar_domicilio_legal', {
      p_domicilio: DOMICILIO_OK,
    }),
    ['PGRST202', '42501'],
  );

  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-domicilio'));
  await expectExplicitAuthorizationDenied(
    'anon no lee los datos legales del contrato',
    leer(anon),
    ['PGRST202', '42501', 'PGRST301'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no escribe el domicilio legal',
    escribir(anon, DOMICILIO_OK),
    ['PGRST202', '42501', 'PGRST301'],
  );

  // ── P04 NO se prueba aquí, y conviene decir por qué ──────────────────────
  // Revocar la membresía CRM de vend1 es IMPOSIBLE en este punto de la corrida:
  // todavía es dueño de los leads del fixture y el guard
  // `trg_equipo_validar_usuarios_jerarquia` lo frena («La membresía conserva
  // dependencias activas»). Es la MISMA avería que tiene roja a
  // testOffboardingMatrix desde el 8-ago. La sonda bancaria sí lo consigue
  // porque corre mucho más tarde, cuando esos leads ya se movieron.
  // Se deja fuera en vez de simularla: una sonda que se salta en silencio y
  // reporta verde es exactamente lo que este proyecto llama «rama de aviso
  // disfrazada de OK». El gate ya cubre P04 sobre la superficie bancaria.
  // ── Escritura: lo único irreversible, y por eso va al final ───────────────
  const escrito = await positive(
    'el analista rellena el domicilio vacío de SU cliente',
    // Espacios exóticos a propósito: el servidor tiene que normalizarlos igual
    // que el navegador, o el mismo texto valdría dos cosas distintas.
    escribir(sessions.vend1.client, '  Av.  Grau   456,　Lima  '),
  );
  if (escrito) {
    const r = escrito.data ?? {};
    check(r.accion === 'completado', 'la primera escritura responde completado');
    check(!Object.prototype.hasOwnProperty.call(r, 'domicilio'),
      'la respuesta NO devuelve el domicilio (sería lectura de PII para el supervisor)');
  }
  check((await domicilioActual()) === 'Av. Grau 456, Lima',
    'la columna quedó escrita Y normalizada igual que en el navegador');

  const segundo = await positive(
    'una segunda escritura no pisa el domicilio ya registrado',
    escribir(sessions.vend1.client, 'Jr. Otro 999, Cercado, Lima'),
  );
  if (segundo) {
    check((segundo.data ?? {}).accion === 'conservado',
      'la segunda escritura responde conservado');
  }
  check((await domicilioActual()) === 'Av. Grau 456, Lima',
    'el domicilio existente NO fue sobrescrito');

  const cerrada = await positive(
    'tras rellenarlo, la lectura ya no declara el hueco',
    leer(sessions.vend1.client),
  );
  if (cerrada) {
    const r = cerrada.data ?? {};
    check(r.falta_domicilio === false, 'falta_domicilio vuelve a false');
    check(Array.isArray(r.faltan_cliente) && !r.faltan_cliente.includes('domicilio'),
      'el domicilio desaparece de faltan_cliente');
  }
}

async function testOffboardingMatrix(sessions, seed) {
  console.log('\n— P04: matriz completa de offboarding —');
  const key = 'vendInactive';
  const member = sessions[key];
  const memberId = seed.profileIdByKey[key];
  const originalProfile = seed.profiles.find((row) => row.id === memberId);
  const originalTeam = seed.team.find((row) => row.perfil_id === memberId);
  const ownedLead = seed.leadByName.get(LEAD_BY_KEY.inactiveOwned.name);
  const ownedActivityId = LEAD_BY_KEY.inactiveOwned.activityId;
  const freePhone = '900000009';
  const since = new Date(Date.now() - 30 * 86_400_000).toISOString();

  assertSeed(member, 'falta la sesión vendInactive para la matriz P04');
  assertSeed(originalProfile, 'falta el perfil vendInactive');
  assertSeed(originalTeam, 'falta la membresía CRM vendInactive');
  assertSeed(ownedLead, 'falta el lead de vendInactive');

  // La sonda usa el contacto del lead histórico del propio actor. P-047 debe
  // resolverlo como `tomado`, de modo que probar la RPC de alta nunca deje una
  // fila transitoria ni necesite ampliar el ledger de cleanup.
  const crearLeadSobreContactoBloqueado = (client) =>
    client.schema('crm').rpc('crear_lead_si_disponible', {
      p_nombre_completo: 'P04 SONDA CREACION ATOMICA',
      p_telefono: ownedLead.telefono,
      p_origen: 'otro',
      p_monto_estimado: 1000,
      p_moneda: 'PEN',
      p_vendedor_id: memberId,
    });

  // ── Revocación fuera de banda (arreglo de la avería del 8-ago) ───────────
  // El fixture `inactiveOwned` es un estado HEREDADO a propósito: alguien que
  // YA poseía leads abiertos cuando se fue (LEEME-seed lo documenta — la vida
  // real tiene esos estados y son justo lo que esta matriz mide). El seed lo
  // construye con el trigger apagado porque `trg_equipo_validar_usuarios_
  // jerarquia` cierra las dos vías normales. La matriz luego lo REACTIVA
  // (true/true) y al RE-revocar moría contra el mismo guard («La membresía
  // conserva dependencias activas») — rota desde el 8-ago. Trasladarle los
  // leads a otro analista arreglaría el síntoma TRAICIONANDO la semántica
  // (dejaría de medirse al inactivo-que-aún-posee). El arreglo fiel: revocar
  // por la MISMA vía fuera de banda del seed (psql, trigger apagado en UNA
  // sentencia dentro de la transacción), canalizada por CRM_BANCO_PSQL_URL —
  // presente siempre en el banco, donde este gate corre.

  async function setState({ portalActive, crmActive, portalRole = originalProfile.rol }) {
    const updateProfile = () => requireAdmin(
      `P04: fijar perfil activo=${portalActive}, rol=${portalRole}`,
      admin.from('perfiles')
        .update({ activo: portalActive, rol: portalRole })
        .eq('id', memberId),
    );
    const updateTeam = () => crmActive
      ? requireAdmin(
          'P04: fijar equipo activo=true',
          admin.schema('crm').from('equipo')
            .update({ activo: true })
            .eq('perfil_id', memberId),
        )
      // Revocar va fuera de banda: el guard prohíbe (con razón) desactivar a
      // quien posee leads, y el sujeto DEBE seguir poseyéndolos — es el estado
      // heredado que se mide.
      : Promise.resolve(revocarEquipoFueraDeBanda(memberId));

    // Al habilitar, primero vive la cuenta; al revocar, primero se corta CRM.
    // Evita fabricar durante el test una ventana intermedia más permisiva.
    if (portalActive) {
      await updateProfile();
      await updateTeam();
    } else {
      await updateTeam();
      await updateProfile();
    }
  }

  async function agendaToken() {
    const response = await requireAdmin(
      'P04: leer token ICS con service_role',
      admin.schema('crm').from('agenda_ics')
        .select('token')
        .eq('perfil_id', memberId)
        .single(),
    );
    return response.data.token;
  }

  async function assertFeed(token, expected, label) {
    const response = await positive(
      label,
      admin.schema('crm').rpc('agenda_ics_feed_fn', {
        p_token: token,
        p_desde: since,
      }),
    );
    if (response) {
      check(response.data?.autorizado === expected,
        `${label}: autorizado=${expected}`,
        `respuesta=${JSON.stringify(response.data)}`);
    }
  }

  async function assertAccess(
    client,
    expectedState,
    label,
    expectedId,
    expectedRole = undefined,
    expectedPuedeContratar = undefined,
  ) {
    const response = await positive(
      label,
      client.schema('crm').rpc('mi_acceso_fn'),
    );
    if (response) {
      check(response.data?.estado === expectedState,
        `${label}: estado=${expectedState}`,
        `respuesta=${JSON.stringify(response.data)}`);
      check(response.data?.perfil_id === expectedId,
        `${label}: identidad ligada a la sesión`,
        `respuesta=${JSON.stringify(response.data)}`);
      if (expectedRole !== undefined) {
        check(response.data?.rol_crm === expectedRole,
          `${label}: rol_crm=${expectedRole}`,
          `respuesta=${JSON.stringify(response.data)}`);
      }
      if (expectedPuedeContratar !== undefined) {
        check(response.data?.puede_contratar === expectedPuedeContratar,
          `${label}: puede_contratar=${expectedPuedeContratar}`,
          `respuesta=${JSON.stringify(response.data)}`);
      }
    }
  }

  async function assertDenied(label) {
    await assertAccess(
      member.client,
      'revocado',
      `${label}: auth canónica no aplica fallback`,
      memberId,
      undefined,
      false,
    );
    await expectHidden(
      `${label}: no lee su fila de equipo`,
      member.client.schema('crm').from('equipo')
        .select('perfil_id')
        .eq('perfil_id', memberId),
    );
    await expectHidden(
      `${label}: no lee su lead histórico`,
      member.client.schema('crm').from('leads')
        .select('id')
        .eq('id', ownedLead.id),
    );
    await expectHidden(
      `${label}: no lee la actividad de su lead`,
      member.client.schema('crm').from('actividades')
        .select('id')
        .eq('id', ownedActivityId),
    );
    await expectHidden(
      `${label}: no lee configuración de enfriamiento`,
      member.client.schema('crm').from('enfriamiento_politica')
        .select('motivo')
        .limit(1),
    );
    await expectHidden(
      `${label}: no lee las perillas de abandono (F1 lead libre)`,
      member.client.schema('crm').from('politica_abandono')
        .select('dias_abandono')
        .limit(1),
    );
    await expectHidden(
      `${label}: no lee el log anti-pesca (F1 lead libre)`,
      member.client.schema('crm').from('verificaciones_lead')
        .select('id')
        .limit(1),
    );
    await expectBlockedMutation(
      `${label}: no lee la configuracion versionada de metas`,
      member.client.schema('crm').rpc('configuracion_metas_fn', {
        p_periodo: '2099-11-01',
      }),
      ['42501'],
    );
    await expectHidden(
      `${label}: no lee su token ICS`,
      member.client.schema('crm').from('agenda_ics')
        .select('token')
        .eq('perfil_id', memberId),
    );
    await expectHidden(
      `${label}: equipo_visible_fn no filtra roster`,
      member.client.schema('crm').rpc('equipo_visible_fn'),
    );
    await expectHidden(
      `${label}: verificar_disponibilidad_lead queda denegada`,
      member.client.schema('crm').rpc('verificar_disponibilidad_lead', {
        p_telefono: freePhone,
        p_dni: null,
      }),
    );
    await expectExplicitAuthorizationDenied(
      `${label}: crear_lead_si_disponible queda denegada`,
      crearLeadSobreContactoBloqueado(member.client),
    );
    await expectExplicitAuthorizationDenied(
      `${label}: tomar_lead_libre queda denegada (F2 lead libre)`,
      member.client.schema('crm').rpc('tomar_lead_libre', {
        p_telefono: freePhone,
        p_dni: null,
      }),
    );
    await expectBlockedMutation(
      `${label}: no actualiza su lead histórico`,
      member.client.schema('crm').from('leads')
        .update({ nota: ownedLead.nota })
        .eq('id', ownedLead.id)
        .select('id'),
    );
  }

  async function assertDestinationBlocked(id, phone, label) {
    await expectBlockedMutation(
      label,
      admin.schema('crm').from('leads').insert({
        id,
        nombre_completo: 'P04 DESTINO INACTIVO TRANSIENT',
        telefono: phone,
        origen: 'otro',
        etapa: 'nuevo',
        monto_estimado: 1000,
        moneda: 'PEN',
        vendedor_id: memberId,
      }).select('id'),
      ['P0001'],
    );
  }

  try {
    // P058: la capacidad operativa sale del rol CRM efectivo, nunca del rol
    // Portal. Las tres cuentas positivas usan `portalRole=comercial`.
    await assertAccess(
      sessions.gerencia.client,
      'miembro',
      'P058: Gerencia Comercial puede contratar',
      seed.profileIdByKey.gerencia,
      'gerencia',
      true,
    );
    await assertAccess(
      sessions.sup1.client,
      'miembro',
      'P058: Supervisor Comercial puede contratar',
      seed.profileIdByKey.sup1,
      'supervisor',
      true,
    );
    await assertAccess(
      sessions.coordinador.client,
      'miembro',
      'P058: Coordinador Comercial no puede contratar',
      seed.profileIdByKey.coordinador,
      'coordinador',
      false,
    );

    // El fallback global legítimo se conserva si NO existe membresía CRM.
    const globalRead = await positive(
      'P04: directorio activo sin fila CRM conserva lectura global',
      sessions.directorio.client.schema('crm').from('leads').select('id').limit(1),
    );
    if (globalRead) {
      check(globalRead.data.length === 1,
        'P04: el fallback global sin membresía devuelve datos');
    }
    await assertAccess(
      sessions.directorio.client,
      'global',
      'P04: auth canónica conserva fallback global sin fila CRM',
      seed.profileIdByKey.directorio,
      'directorio',
      false,
    );

    // true / true: baseline permitido y RPC P-047 sin cambio de contrato.
    await setState({ portalActive: true, crmActive: true });
    const activeMembership = await positive(
      'P04 true/true: resuelve membresía propia',
      member.client.schema('crm').from('equipo')
        .select('rol_crm')
        .eq('perfil_id', memberId)
        .single(),
    );
    if (activeMembership) {
      check(activeMembership.data.rol_crm === originalTeam.rol_crm,
        'P04 true/true: conserva el rol CRM');
    }
    await assertAccess(
      member.client,
      'miembro',
      'P04 true/true: auth canónica reconoce la membresía',
      memberId,
      originalTeam.rol_crm,
      true,
    );
    await positive(
      'P04 true/true: lee su lead',
      member.client.schema('crm').from('leads')
        .select('id')
        .eq('id', ownedLead.id)
        .single(),
    );
    const availability = await positive(
      'P04 true/true: RPC de disponibilidad responde',
      member.client.schema('crm').rpc('verificar_disponibilidad_lead', {
        p_telefono: freePhone,
        p_dni: null,
      }),
    );
    if (availability) {
      check(typeof availability.data?.estado === 'string',
        'P04 true/true: conserva el JSON {estado} de P-047');
    }
    const atomicCreation = await positive(
      'P04 true/true: RPC de alta atómica ejecuta el veredicto de negocio',
      crearLeadSobreContactoBloqueado(member.client),
    );
    if (atomicCreation) {
      check(atomicCreation.data?.estado === 'tomado'
        && !Object.hasOwn(atomicCreation.data ?? {}, 'lead_id'),
        'P04 true/true: contacto existente queda tomado y no se crea otro lead',
        `respuesta=${JSON.stringify(atomicCreation.data)}`);
      // F1 lead libre: 'tomado' trae ultima_conversacion_en y su valor es el
      // max(creado_en) de las CONVERSACIONES reales del lead — los intentos
      // (llamada_no_contestada, whatsapp_enviado) quedan fuera. El esperado se
      // ancla contra la base, no contra un supuesto del fixture.
      const conversaciones = await requireAdmin(
        'F1 lead libre: conversaciones reales del lead tomado',
        admin.schema('crm').from('actividades')
          .select('creado_en')
          .eq('lead_id', ownedLead.id)
          .in('tipo', ['llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'])
          .order('creado_en', { ascending: false })
          .limit(1),
      );
      const esperada = conversaciones.data?.[0]?.creado_en ?? null;
      const recibida = atomicCreation.data?.ultima_conversacion_en ?? null;
      check(Object.hasOwn(atomicCreation.data ?? {}, 'ultima_conversacion_en')
        && ((esperada === null && recibida === null)
          || (esperada !== null && recibida !== null
            && new Date(recibida).getTime() === new Date(esperada).getTime())),
        'F1 lead libre: ultima_conversacion_en = max(conversaciones reales), intentos fuera',
        `esperada=${esperada} recibida=${recibida}`);
    }
    const cooling = await positive(
      'P04 true/true: lee política de enfriamiento',
      member.client.schema('crm').from('enfriamiento_politica')
        .select('motivo', { count: 'exact' }),
    );
    if (cooling) {
      check(cooling.count === 7 && cooling.data.length === 7,
        'P04 true/true: conserva los siete motivos de enfriamiento');
    }

    // ── F1 lead libre (20260816221500): perillas, log anti-pesca, clave nueva ──
    const perillas = await positive(
      'F1 lead libre: el miembro activo lee las perillas de abandono',
      member.client.schema('crm').from('politica_abandono')
        .select('dias_abandono, dias_auto_bolsa', { count: 'exact' }),
    );
    if (perillas) {
      check(perillas.count === 1
        && perillas.data[0]?.dias_abandono === 7
        && perillas.data[0]?.dias_auto_bolsa === 7,
        'F1 lead libre: la fila única trae Y=7 y X=7',
        `filas=${JSON.stringify(perillas.data)}`);
    }
    await expectBlockedMutation(
      'F1 lead libre: el analista NO edita las perillas',
      member.client.schema('crm').from('politica_abandono')
        .update({ dias_abandono: 99 })
        .eq('singleton', true)
        .select('dias_abandono'),
    );
    await expectBlockedMutation(
      'F1 lead libre: nadie inserta una segunda fila de perillas (ni con singleton=true)',
      member.client.schema('crm').from('politica_abandono')
        .insert({ singleton: true, dias_abandono: 1, dias_auto_bolsa: 1 })
        .select('singleton'),
    );
    // RLS de SELECT no da error: se asevera el CONTEO, no la ausencia de fallo.
    await expectHidden(
      'F1 lead libre: el log anti-pesca es invisible para el analista (aunque él generó filas)',
      member.client.schema('crm').from('verificaciones_lead')
        .select('id')
        .limit(1),
    );
    const pescaGerencia = await positive(
      'F1 lead libre: gerencia SÍ lee el log anti-pesca',
      sessions.gerencia.client.schema('crm').from('verificaciones_lead')
        .select('veredicto', { count: 'exact' })
        .eq('verificado_por', memberId),
    );
    if (pescaGerencia) {
      check((pescaGerencia.count ?? 0) >= 1,
        'F1 lead libre: la RPC del analista dejó su rastro (quién y veredicto)',
        `filas=${pescaGerencia.count}`);
    }
    await expectBlockedMutation(
      'F1 lead libre: ni gerencia escribe el log a mano — solo la RPC',
      sessions.gerencia.client.schema('crm').from('verificaciones_lead')
        .insert({ verificado_por: memberId, telefono_consultado: 'x', veredicto: 'x' })
        .select('id'),
    );
    const perillaEditada = await positive(
      'F1 lead libre: gerencia SÍ edita las perillas',
      sessions.gerencia.client.schema('crm').from('politica_abandono')
        .update({ dias_abandono: 8 })
        .eq('singleton', true)
        .select('dias_abandono, actualizado_por')
        .single(),
    );
    if (perillaEditada) {
      check(perillaEditada.data?.dias_abandono === 8,
        'F1 lead libre: la edición de gerencia aplica');
      // Autoría SELLADA por trigger (auditor M2): firma quien edita, no lo enviado.
      check(perillaEditada.data?.actualizado_por === seed.profileIdByKey.gerencia,
        'F1 lead libre: actualizado_por lo sella el servidor con el editor real',
        `actualizado_por=${perillaEditada.data?.actualizado_por}`);
      await positive(
        'F1 lead libre: gerencia revierte la perilla a 7',
        sessions.gerencia.client.schema('crm').from('politica_abandono')
          .update({ dias_abandono: 7 })
          .eq('singleton', true)
          .select('dias_abandono')
          .single(),
      );
    }

    // ── F2 lead libre (20260817164745): la toma directa ──────────────────────
    // Solo analistas toman, y para sí mismos; supervisión asigna por reparto.
    await expectExplicitAuthorizationDenied(
      'F2 lead libre: gerencia NO toma (su puerta es el reparto)',
      sessions.gerencia.client.schema('crm').rpc('tomar_lead_libre', {
        p_telefono: freePhone,
        p_dni: null,
      }),
    );
    await expectExplicitAuthorizationDenied(
      'F2 lead libre: supervisor tampoco toma (auditor M2)',
      sessions.sup1.client.schema('crm').rpc('tomar_lead_libre', {
        p_telefono: freePhone,
        p_dni: null,
      }),
    );
    // Sin blanco tomable la RPC responde el veredicto y no inventa filas.
    const tomaLibre = await positive(
      'F2 lead libre: tomar sobre contacto libre responde el veredicto',
      member.client.schema('crm').rpc('tomar_lead_libre', {
        p_telefono: freePhone,
        p_dni: null,
      }),
    );
    if (tomaLibre) {
      check(tomaLibre.data?.estado === 'libre',
        'F2 lead libre: sin blanco tomable el veredicto es libre',
        `respuesta=${JSON.stringify(tomaLibre.data)}`);
    }
    // Contacto con dueño vigente: nadie roba y el UUID no se filtra.
    const tomaAjena = await positive(
      'F2 lead libre: tomar sobre contacto con dueño responde tomado',
      member.client.schema('crm').rpc('tomar_lead_libre', {
        p_telefono: ownedLead.telefono,
        p_dni: null,
      }),
    );
    if (tomaAjena) {
      check(tomaAjena.data?.estado === 'tomado'
        && !Object.hasOwn(tomaAjena.data ?? {}, 'lead_id'),
        'F2 lead libre: el dueño vigente queda intacto y sin lead_id filtrado',
        `respuesta=${JSON.stringify(tomaAjena.data)}`);
      // Auditor A1: el SONDEO por la toma también deja rastro anti-pesca
      // legible por gerencia — sin esto, pescar identidades vía tomar sería
      // el único camino sin log.
      const pescaToma = await positive(
        'F2 lead libre: gerencia ve el asiento de la toma fallida',
        sessions.gerencia.client.schema('crm').from('verificaciones_lead')
          .select('veredicto', { count: 'exact' })
          .eq('verificado_por', memberId)
          .eq('veredicto', 'tomado'),
      );
      if (pescaToma) {
        check((pescaToma.count ?? 0) >= 1,
          'F2 lead libre: la toma fallida quedó asentada (quién y veredicto)',
          `filas=${pescaToma.count}`);
      }
    }
    // La toma real de una bolsa sembrada (queda como lead TRANSIENT del gate).
    const bolsaTransientId = randomUUID();
    const bolsaTransientPhone = '+51996600311';
    await requireAdmin(
      'F2 lead libre: siembra de bolsa TRANSIENT',
      admin.schema('crm').from('leads').insert({
        id: bolsaTransientId,
        nombre_completo: 'F2 TOMA BOLSA TRANSIENT',
        telefono: bolsaTransientPhone,
        origen: 'otro',
        etapa: 'nuevo',
        monto_estimado: 1000,
        moneda: 'PEN',
      }).select('id'),
    );
    // Auditor M2: la MISMA bolsa prueba las dos puertas — el PATCH directo del
    // analista rebota (RLS + veto sin flag: la válvula solo vive dentro de la
    // RPC) y acto seguido la RPC sí la toma.
    await expectBlockedMutation(
      'F2 lead libre: el analista NO se auto-asigna la bolsa por PATCH directo',
      member.client.schema('crm').from('leads')
        .update({ vendedor_id: memberId })
        .eq('id', bolsaTransientId)
        .select('id'),
    );
    const tomaBolsa = await positive(
      'F2 lead libre: el analista TOMA la bolsa',
      member.client.schema('crm').rpc('tomar_lead_libre', {
        p_telefono: bolsaTransientPhone,
        p_dni: null,
      }),
    );
    if (tomaBolsa) {
      check(tomaBolsa.data?.estado === 'tomado_ok'
        && tomaBolsa.data?.modo === 'bolsa'
        && tomaBolsa.data?.lead_id === bolsaTransientId,
        'F2 lead libre: tomado_ok de bolsa con el lead esperado',
        `respuesta=${JSON.stringify(tomaBolsa.data)}`);
      const filaTomada = await requireAdmin(
        'F2 lead libre: la fila tomada quedó del analista',
        admin.schema('crm').from('leads')
          .select('vendedor_id, tenencia_desde')
          .eq('id', bolsaTransientId)
          .single(),
      );
      check(filaTomada.data?.vendedor_id === memberId
        && filaTomada.data?.tenencia_desde !== null,
        'F2 lead libre: dueño nuevo y tenencia renacida',
        `fila=${JSON.stringify(filaTomada.data)}`);
      const notaToma = await requireAdmin(
        'F2 lead libre: la nota §9 quedó asentada',
        admin.schema('crm').from('actividades')
          .select('metadata')
          .eq('lead_id', bolsaTransientId)
          .eq('tipo', 'nota')
          .limit(1),
      );
      check(notaToma.data?.[0]?.metadata?.evento === 'toma_directa'
        && notaToma.data?.[0]?.metadata?.modo === 'bolsa',
        'F2 lead libre: la traza lleva evento toma_directa y modo bolsa',
        `metadata=${JSON.stringify(notaToma.data?.[0]?.metadata)}`);
      // El TRANSIENT vuelve a la cola por la puerta de gerencia: el sujeto
      // conserva su cartera de fixture EXACTA (el caso «ve exactamente su
      // cartera» corre después y esta toma lo contaminaba) y de paso queda
      // probada la liberación gerencial del recién tomado.
      const liberada = await positive(
        'F2 lead libre: gerencia devuelve la bolsa tomada a la cola global',
        sessions.gerencia.client.schema('crm').from('leads')
          .update({ vendedor_id: null })
          .eq('id', bolsaTransientId)
          .select('vendedor_id')
          .single(),
      );
      if (liberada) {
        check(liberada.data?.vendedor_id === null,
          'F2 lead libre: la bolsa liberada queda sin dueño');
      }
    }
    // Revive, veredicto 'reutilizable' y carencia NO se prueban aquí: un
    // descarte VENCIDO no se puede fabricar por la API — el sello
    // (trg_leads_zz_sello_descarte) re-estampa descartado_en con el reloj del
    // servidor y leads_before_insert veta nacer terminal (comprobado contra
    // el banco 2026-08-17). Solo el paso real del tiempo los produce; esas
    // verdades viven en el oráculo test-toma-lead-libre.sql (16 casos, 4
    // carreras dblink) que fabrica el tiempo en un banco desechable.

    // ── F3 lead libre (20260818045032): recordatorios de disponibilidad ──────
    // Owner-only DE VERDAD (ni gerencia lee notas personales ajenas), autoría
    // y teléfono SELLADOS por trigger, DELETE propio como excepción
    // documentada, y el veneno 'infinity' muerto en la puerta de actividades.
    const recordatorioTelTecleado = '996 600 322';
    const recordatorioTelNormal = '+51996600322';
    const recordatorioCreado = await positive(
      'F3 lead libre: el analista crea su recordatorio (teléfono tecleado a lo humano)',
      member.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({
          // Autoría AJENA a propósito: el trigger debe re-firmar con el actor.
          perfil_id: seed.profileIdByKey.gerencia,
          telefono: recordatorioTelTecleado,
          recordar_en: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
        })
        .select('id, perfil_id, telefono')
        .single(),
    );
    if (recordatorioCreado) {
      check(recordatorioCreado.data?.perfil_id === memberId,
        'F3 lead libre: la autoría la SELLA el servidor con el actor real',
        `perfil_id=${recordatorioCreado.data?.perfil_id}`);
      check(recordatorioCreado.data?.telefono === recordatorioTelNormal,
        'F3 lead libre: el teléfono queda normalizado a +519########',
        `telefono=${recordatorioCreado.data?.telefono}`);
    }
    await expectBlockedMutation(
      'F3 lead libre: una fecha de revisión en el pasado no entra',
      member.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({
          telefono: '+51996600323',
          recordar_en: new Date(Date.now() - 3600 * 1000).toISOString(),
        })
        .select('id'),
      ['22023'],
    );
    await expectBlockedMutation(
      'F3 lead libre: el veneno infinity no entra en recordar_en',
      member.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({ telefono: '+51996600323', recordar_en: 'infinity' })
        .select('id'),
      ['22023'],
    );
    await expectBlockedMutation(
      'F3 lead libre: el tope de 365 días también gobierna (auditor m5)',
      member.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({
          telefono: '+51996600323',
          recordar_en: new Date(Date.now() + 400 * 24 * 3600 * 1000).toISOString(),
        })
        .select('id'),
      ['22023'],
    );
    await expectBlockedMutation(
      'F3 lead libre: un teléfono no-celular rebota con el 22023 amable del trigger',
      member.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({
          telefono: '014567890',
          recordar_en: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
        })
        .select('id'),
      ['22023'],
    );
    await expectBlockedMutation(
      'F3 lead libre: segundo recordatorio del MISMO contacto rebota (la llave es upsert)',
      member.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({
          telefono: recordatorioTelNormal,
          recordar_en: new Date(Date.now() + 9 * 24 * 3600 * 1000).toISOString(),
        })
        .select('id'),
      ['23505'],
    );
    await expectHidden(
      'F3 lead libre: ni GERENCIA lee recordatorios ajenos (nota personal)',
      sessions.gerencia.client.schema('crm').from('recordatorios_disponibilidad')
        .select('id')
        .limit(1),
    );
    await expectBlockedMutation(
      'F3 lead libre: el supervisor no crea recordatorios (la antesala de tomar es del analista)',
      sessions.sup1.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({
          telefono: '+51996600324',
          recordar_en: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
        })
        .select('id'),
    );
    if (recordatorioCreado?.data?.id) {
      // El ARQUETIPO del owner-only (auditor M1): otro ANALISTA — mismo rol,
      // pasa el gate de rol y debe morir por el predicado perfil_id. Gerencia
      // y supervisor caen por rol; sin este par, mutar el predicado owner
      // dejando el gate de rol pasaría la matriz en verde.
      await expectHidden(
        'F3 lead libre: OTRO analista no ve el recordatorio ajeno (predicado owner)',
        sessions.vend1.client.schema('crm').from('recordatorios_disponibilidad')
          .select('id')
          .eq('id', recordatorioCreado.data.id),
      );
      await expectBlockedMutation(
        'F3 lead libre: otro analista no reprograma el ajeno',
        sessions.vend1.client.schema('crm').from('recordatorios_disponibilidad')
          .update({ recordar_en: new Date(Date.now() + 20 * 24 * 3600 * 1000).toISOString() })
          .eq('id', recordatorioCreado.data.id)
          .select('id'),
      );
      await expectBlockedMutation(
        'F3 lead libre: otro analista no borra el ajeno',
        sessions.vend1.client.schema('crm').from('recordatorios_disponibilidad')
          .delete()
          .eq('id', recordatorioCreado.data.id)
          .select('id'),
      );
      // El lector global (el «rol raro» de RETOMAR-43): la exclusión es
      // intencional y se consagra en verde.
      await expectHidden(
        'F3 lead libre: directorio (lector global) tampoco ve notas personales',
        sessions.directorio.client.schema('crm').from('recordatorios_disponibilidad')
          .select('id')
          .limit(1),
      );
      await expectBlockedMutation(
        'F3 lead libre: gerencia tampoco borra el recordatorio ajeno',
        sessions.gerencia.client.schema('crm').from('recordatorios_disponibilidad')
          .delete()
          .eq('id', recordatorioCreado.data.id)
          .select('id'),
      );
      const reprogramado = await positive(
        'F3 lead libre: el dueño reprograma su recordatorio',
        member.client.schema('crm').from('recordatorios_disponibilidad')
          .update({ recordar_en: new Date(Date.now() + 14 * 24 * 3600 * 1000).toISOString() })
          .eq('id', recordatorioCreado.data.id)
          .select('id')
          .single(),
      );
      if (reprogramado) {
        check(reprogramado.data?.id === recordatorioCreado.data.id,
          'F3 lead libre: reprogramar conserva la identidad de la fila');
      }
      const borrado = await positive(
        'F3 lead libre: el dueño SÍ elimina su recordatorio (excepción DELETE documentada)',
        member.client.schema('crm').from('recordatorios_disponibilidad')
          .delete()
          .eq('id', recordatorioCreado.data.id)
          .select('id'),
      );
      if (borrado) {
        check((borrado.data?.length ?? 0) === 1,
          'F3 lead libre: el borrado propio afecta exactamente su fila');
      }
    }
    // La deuda F2 saldada: 'infinity' tampoco entra ya en actividades.
    await expectBlockedMutation(
      'F3 lead libre: el veneno infinity muere en crm.actividades (CHECK de finitud)',
      member.client.schema('crm').from('actividades')
        .insert({
          lead_id: ownedLead.id,
          tipo: 'nota',
          detalle: 'veneno',
          creado_en: 'infinity',
        })
        .select('id'),
      ['23514'],
    );

    // ── F4 «sin ruido» (20260823204930): el libro de reconocimientos ─────────
    // Ledger INMUTABLE (solo INSERT) owner-only del SUPERVISOR; gerencia LEE
    // todo (decisión de Miguel 2026-08-23); el alerta_id queda ATADO al actor
    // por el trigger y el tope de posponer es 7 días.
    {
      const f4SupervisorId = seed.profileIdByKey.sup1;
      const f4AlertaPropia = `grupo:por_repartir:${f4SupervisorId}`;
      const f4Reconocido = await positive(
        'F4 sin ruido: el supervisor reconoce una alerta SUYA (autoría re-sellada)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            // Autoría AJENA a propósito: el trigger debe re-firmar con el actor.
            perfil_id: seed.profileIdByKey.gerencia,
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: ['lead-aaa', 'lead-bbb'],
            severidad: 'atencion',
          })
          .select('id, perfil_id')
          .single(),
      );
      if (f4Reconocido) {
        check(f4Reconocido.data?.perfil_id === f4SupervisorId,
          'F4 sin ruido: la autoría la SELLA el servidor con el actor real',
          `perfil_id=${f4Reconocido.data?.perfil_id}`);
      }
      await positive(
        'F4 sin ruido: posponer con fecha dentro del tope entra',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:tarea_vencida:${f4SupervisorId}`,
            accion: 'posponer',
            miembros: ['lead-ccc'],
            severidad: 'critica',
            hasta: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString(),
          })
          .select('id')
          .single(),
      );
      await expectExpectedFailure(
        'F4 sin ruido: posponer más allá de 7 días rebota (tope de Miguel)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:tarea_vencida:${f4SupervisorId}`,
            accion: 'posponer',
            miembros: ['lead-ccc'],
            severidad: 'critica',
            hasta: new Date(Date.now() + 9 * 24 * 3600 * 1000).toISOString(),
          })
          .select('id'),
        ['22023'], /tope de 7 días/,
      );
      await expectExpectedFailure(
        'F4 sin ruido: posponer SIN fecha no existe (CHECK de coherencia)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:tarea_vencida:${f4SupervisorId}`,
            accion: 'posponer',
            miembros: ['lead-ccc'],
            severidad: 'critica',
          })
          .select('id'),
        ['23514'], /check/i,
      );
      await expectExpectedFailure(
        'F4 sin ruido: reconocer no lleva fecha (CHECK de coherencia)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
            hasta: new Date(Date.now() + 3600 * 1000).toISOString(),
          })
          .select('id'),
        ['23514'], /check/i,
      );
      await expectExpectedFailure(
        'F4 sin ruido: nadie reconoce alertas AJENAS (el id queda atado al actor)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: 'grupo:por_repartir:00000000-0000-4000-8000-000000000000',
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
          })
          .select('id'),
        ['42501'], /propia campana/,
      );
      await expectExpectedFailure(
        'F4 sin ruido: un tipo de alerta fuera del catálogo rebota (CHECK de formato)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:invento:${f4SupervisorId}`,
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
          })
          .select('id'),
        ['23514'], /check/i,
      );
      await expectExpectedFailure(
        'F4 sin ruido: una foto de miembros con ids venenosos rebota (22023 del trigger)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: ['lead-ok', 'con espacios malos'],
            severidad: 'atencion',
          })
          .select('id'),
        ['22023'], /ids inválidos/,
      );
      await expectExpectedFailure(
        'F4 sin ruido: la foto vacía no entra (cardinalidad 1..2000)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: [],
            severidad: 'atencion',
          })
          .select('id'),
        ['23514'], /check/i,
      );
      await expectExpectedFailure(
        'F4 sin ruido: posponer con fecha PASADA rebota (auditor #1)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:tarea_vencida:${f4SupervisorId}`,
            accion: 'posponer',
            miembros: ['lead-ccc'],
            severidad: 'critica',
            hasta: new Date(Date.now() - 24 * 3600 * 1000).toISOString(),
          })
          .select('id'),
        ['22023'], /futura/,
      );
      await expectExpectedFailure(
        'F4 sin ruido: hasta=infinity muere en la puerta (dos candados, auditor #10)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:tarea_vencida:${f4SupervisorId}`,
            accion: 'posponer',
            miembros: ['lead-ccc'],
            severidad: 'critica',
            hasta: 'infinity',
          })
          .select('id'),
        ['22023', '23514'], /tope|check/i,
      );
      await expectExpectedFailure(
        'F4 sin ruido: un NULL dentro de la foto rebota (mata el mutante del m is null, auditor #2)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: ['lead-ok', null],
            severidad: 'atencion',
          })
          .select('id'),
        ['22023'], /ids inválidos/,
      );
      await expectExpectedFailure(
        'F4 sin ruido: una foto de 2001 miembros rebota (anti-abuso, auditor #10)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: Array.from({ length: 2001 }, (_, i) => `lead-${i}`),
            severidad: 'atencion',
          })
          .select('id'),
        ['23514'], /check/i,
      );
      // Codex F4 #8: el catálogo COMPLETO tiene su positivo (el 4.º tipo) y
      // los CHECK de accion/severidad tienen quien los mate si se mutan.
      {
        const f4Primero = await positive(
          'F4 sin ruido: el 4.º tipo del catálogo (lead_sin_responder) también entra',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
            .insert({
              alerta_id: `grupo:lead_sin_responder:${f4SupervisorId}`,
              accion: 'reconocer',
              miembros: ['lead-eee'],
              severidad: 'critica',
            })
            .select('id, secuencia')
            .single(),
        );
        const f4Segundo = await positive(
          'F4 sin ruido: un segundo asiento del MISMO grupo entra (supersede, no edita)',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
            .insert({
              alerta_id: `grupo:lead_sin_responder:${f4SupervisorId}`,
              accion: 'posponer',
              miembros: ['lead-eee', 'lead-fff'],
              severidad: 'critica',
              hasta: new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString(),
            })
            .select('id, secuencia')
            .single(),
        );
        if (f4Primero && f4Segundo) {
          // Codex F4 #3: «el último asiento manda» necesita ORDEN TOTAL —
          // creado_en puede empatar al microsegundo; la secuencia no.
          check(Number(f4Segundo.data?.secuencia) > Number(f4Primero.data?.secuencia),
            'F4 sin ruido: la secuencia da el orden total del libro (el 2.º > el 1.º)',
            `secuencias=${f4Primero.data?.secuencia},${f4Segundo.data?.secuencia}`);
        }
      }
      await expectExpectedFailure(
        'F4 sin ruido: una acción fuera del catálogo rebota (CHECK de accion)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'silenciar',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
          })
          .select('id'),
        ['23514'], /check/i,
      );
      await expectExpectedFailure(
        'F4 sin ruido: una severidad fuera del catálogo rebota (CHECK de severidad)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'altisima',
          })
          .select('id'),
        ['23514'], /check/i,
      );
      await expectBlockedMutation(
        'F4 sin ruido: una foto 2D no entra (array_ndims=1, Codex #2)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: f4AlertaPropia,
            accion: 'reconocer',
            miembros: [['lead-a', 'lead-b']],
            severidad: 'atencion',
          })
          .select('id'),
        ['23514', '22P02'],
      );
      // NO OBSERVABLES desde PostgREST y por eso DICHOS (regla de mutantes de
      // la casa): la caducidad de 90 días (pg_cron + guardia BEFORE DELETE
      // solo dejan pasar asientos viejos — exigiría fabricar tiempo en un
      // banco desechable, como el oráculo de F2 lead libre) y la guardia de
      // inmutabilidad frente al OWNER (el gate solo habla PostgREST; ante
      // authenticated la matriz ya prueba UPDATE/DELETE bloqueados). Los
      // asientos que esta corrida deja son jóvenes y la guardia impide
      // limpiarlos: quedan a propósito, el branch del gate es desechable.
      await expectExpectedFailure(
        'F4 sin ruido: el uuid en MAYÚSCULAS no entra (auth.uid()::text siempre es minúscula)',
        sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:por_repartir:${String(f4SupervisorId).toUpperCase()}`,
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
          })
          .select('id'),
        ['23514', '42501'], /check|campana/i,
      );
      {
        // creado_en falso: el servidor RE-SELLA — sin esto un supervisor
        // fecharía un asiento en 2031 y ganaría la supremacía del libro
        // para siempre (auditor #4).
        const f4Fechado = await positive(
          'F4 sin ruido: un creado_en del cliente se RE-SELLA con el reloj del servidor',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
            .insert({
              alerta_id: `grupo:sin_proxima_accion:${f4SupervisorId}`,
              accion: 'reconocer',
              miembros: ['lead-ddd'],
              severidad: 'atencion',
              creado_en: '2031-01-01T00:00:00Z',
            })
            .select('id, creado_en')
            .single(),
        );
        if (f4Fechado) {
          const f4DeltaMs = Math.abs(Date.parse(f4Fechado.data?.creado_en) - Date.now());
          check(Number.isFinite(f4DeltaMs) && f4DeltaMs < 5 * 60 * 1000,
            'F4 sin ruido: el creado_en devuelto es de AHORA, no del cliente',
            `creado_en=${f4Fechado.data?.creado_en}`);
        }
      }
      await expectBlockedMutation(
        'F4 sin ruido: el COORDINADOR no escribe en el libro (auditor #3)',
        sessions.coordinador.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:por_repartir:${seed.profileIdByKey.coordinador}`,
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
          })
          .select('id'),
      );
      await expectBlockedMutation(
        'F4 sin ruido: el ANALISTA no escribe en el libro (gate de rol)',
        member.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:por_repartir:${memberId}`,
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
          })
          .select('id'),
      );
      await expectBlockedMutation(
        'F4 sin ruido: GERENCIA tampoco escribe — el compromiso es personal',
        sessions.gerencia.client.schema('crm').from('alertas_reconocimientos')
          .insert({
            alerta_id: `grupo:por_repartir:${seed.profileIdByKey.gerencia}`,
            accion: 'reconocer',
            miembros: ['lead-ccc'],
            severidad: 'atencion',
          })
          .select('id'),
      );
      if (f4Reconocido?.data?.id) {
        const f4Gerencia = await positive(
          'F4 sin ruido: gerencia LEE el reconocimiento del supervisor (trazabilidad)',
          sessions.gerencia.client.schema('crm').from('alertas_reconocimientos')
            .select('id, perfil_id')
            .eq('id', f4Reconocido.data.id)
            .single(),
        );
        if (f4Gerencia) {
          check(f4Gerencia.data?.perfil_id === f4SupervisorId,
            'F4 sin ruido: la traza dice QUIÉN reconoció');
        }
        // Codex F4 #8: el trigger de auditoría tiene su sonda — sin esto,
        // quitarlo dejaba la matriz en verde y el libro sin rastro permanente.
        const f4Rastro = await requireAdmin(
          'F4 sin ruido: el asiento dejó rastro en audit_log (trigger vivo)',
          admin.from('audit_log')
            .select('id, operacion')
            // log_audit_crm escribe la tabla CALIFICADA (tg_table_schema||'.'||
            // tg_table_name) — la sonda falló en el primer gate por buscarla
            // sin esquema.
            .eq('tabla', 'crm.alertas_reconocimientos')
            .eq('fila_id', f4Reconocido.data.id)
            .limit(1),
        );
        check((f4Rastro?.data?.length ?? 0) === 1
          && f4Rastro?.data?.[0]?.operacion === 'INSERT',
          'F4 sin ruido: el rastro es un INSERT de esta fila',
          `rastro=${JSON.stringify(f4Rastro?.data)}`);
        // El arquetipo del owner-only (auditor M1): OTRO supervisor — mismo
        // rol, pasa el gate y debe morir por el predicado owner.
        await expectHidden(
          'F4 sin ruido: OTRO supervisor no lee el libro ajeno (predicado owner)',
          sessions.sup2.client.schema('crm').from('alertas_reconocimientos')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        await expectHidden(
          'F4 sin ruido: el analista no lee el libro (gate de rol)',
          member.client.schema('crm').from('alertas_reconocimientos')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        await expectHidden(
          'F4 sin ruido: el coordinador tampoco lee el libro (auditor #3)',
          sessions.coordinador.client.schema('crm').from('alertas_reconocimientos')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        await expectHidden(
          'F4 sin ruido: directorio (lector global) tampoco lee el libro',
          sessions.directorio.client.schema('crm').from('alertas_reconocimientos')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        // INMUTABLE de verdad: ni el DUEÑO edita o borra su asiento.
        await expectBlockedMutation(
          'F4 sin ruido: ni el dueño reescribe el libro (sin UPDATE)',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
            .update({ severidad: 'critica' })
            .eq('id', f4Reconocido.data.id)
            .select('id'),
        );
        await expectBlockedMutation(
          'F4 sin ruido: ni el dueño arranca hojas del libro (sin DELETE)',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
            .delete()
            .eq('id', f4Reconocido.data.id)
            .select('id'),
        );

        // ── F4.2: la vista de VIGENTES corta con el reloj de POSTGRES ──────
        // (bloqueante Codex F4.2 #2). NO observables aquí y cerrados por
        // estructura: el corte de 7 días (nadie fabrica un creado_en viejo —
        // lo sella el trigger) y el UNIQUE de secuencia (la identity no
        // empata por la vía normal); ambos DICHOS, regla de la casa.
        await positive(
          'F4.2 vigentes: el asiento fresco del dueño aparece en la vista',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .select('id, secuencia')
            .eq('id', f4Reconocido.data.id)
            .single(),
        );
        await positive(
          'F4.2 vigentes: gerencia LEE por la vista (misma trazabilidad)',
          sessions.gerencia.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .select('id')
            .eq('id', f4Reconocido.data.id)
            .single(),
        );
        await expectHidden(
          'F4.2 vigentes: OTRO supervisor no ve el libro ajeno por la vista (security_invoker)',
          sessions.sup2.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        await expectHidden(
          'F4.2 vigentes: el analista tampoco ve nada por la vista',
          member.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        await expectHidden(
          'F4.2 vigentes: el coordinador tampoco (la vista no amplía la RLS)',
          sessions.coordinador.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        // Simetría tabla↔vista (auditor F4.2 #3): el lector global es el rol
        // donde un fallback descuidado ampliaría sin querer.
        await expectHidden(
          'F4.2 vigentes: directorio (lector global) tampoco ve el libro por la vista',
          sessions.directorio.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .select('id')
            .eq('id', f4Reconocido.data.id),
        );
        // anon: doble candado (sin USAGE de crm + sin grant), pinneado como
        // en las demás secciones (auditor F4.2 #4).
        const anonVigentes = createClient(
          SUPABASE_URL,
          ANON_KEY,
          clientOptions('crm-rls-anon-reconocimientos'),
        );
        await expectExplicitAuthorizationDenied(
          'F4.2 vigentes: anon no lee la vista',
          anonVigentes.schema('crm').from('alertas_reconocimientos_vigentes')
            .select('id')
            .limit(1),
          ['PGRST202', '42501', 'PGRST301', 'PGRST106'],
        );
        // F4.4 (20260824170349) volvió la vista multi-fuente: dejó de ser
        // auto-actualizable y el DML muere con 55000 ANTES de llegar a RLS —
        // un bloqueo ESTRUCTURAL más temprano e igual de cerrado. El pin del
        // auditor F4.2 #5 (DENEGADO para todos, dueño incluido) sigue en pie;
        // 55000 se acepta junto a los códigos de RLS.
        await expectBlockedMutation(
          'F4.2 vigentes: ni el dueño INSERTA a través de la vista',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .insert({
              alerta_id: `grupo:por_repartir:${f4SupervisorId}`,
              accion: 'reconocer',
              miembros: ['lead-ccc'],
              severidad: 'atencion',
            })
            .select('id'),
          ['55000'],
        );
        await expectBlockedMutation(
          'F4.2 vigentes: ni el dueño EDITA a través de la vista',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .update({ severidad: 'atencion' })
            .eq('id', f4Reconocido.data.id)
            .select('id'),
          ['55000'],
        );
        await expectBlockedMutation(
          'F4.2 vigentes: ni el dueño BORRA a través de la vista',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .delete()
            .eq('id', f4Reconocido.data.id)
            .select('id'),
          ['55000'],
        );
        // La prueba TEMPORAL contra el reloj del servidor: una posposición a
        // 8 segundos vista está VIGENTE al nacer (colchón ante un reloj local
        // ligeramente adelantado) y, pasado su `hasta`, la
        // vista la suelta mientras la tabla base la conserva — el corte es
        // de Postgres, no del dispositivo que consulta.
        const f4Pospuesto = await positive(
          'F4.2 vigentes: nace una posposición de 8 segundos (futura, bajo el tope)',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
            .insert({
              alerta_id: `grupo:tarea_vencida:${f4SupervisorId}`,
              accion: 'posponer',
              miembros: ['lead-ccc'],
              severidad: 'atencion',
              hasta: new Date(Date.now() + 8_000).toISOString(),
            })
            .select('id')
            .single(),
        );
        if (f4Pospuesto?.data?.id) {
          await positive(
            'F4.2 vigentes: recién nacida, la posposición está en la vista',
            sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
              .select('id')
              .eq('id', f4Pospuesto.data.id)
              .single(),
          );
          await new Promise((resolver) => setTimeout(resolver, 9_500));
          await expectHidden(
            'F4.2 vigentes: pasado su hasta, la vista la SUELTA (reloj del servidor)',
            sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
              .select('id')
              .eq('id', f4Pospuesto.data.id),
          );
          // B1 (Codex F4.4): el último asiento manda TAMBIÉN vencido. Este
          // grupo tiene una posposición ANTERIOR de 3 días aún dentro de su
          // hasta; con la vista vieja resucitaba al vencer la de 8 s. Ahora
          // el posponer vencido, siendo el último, bloquea a los anteriores:
          // la alerta queda SIN gobierno (cero filas), jamás con un asiento
          // superado al mando.
          await expectHidden(
            'F4.4 vigentes: el posponer vencido BLOQUEA a los asientos anteriores (nada resucita)',
            sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
              .select('id')
              .eq('alerta_id', `grupo:tarea_vencida:${f4SupervisorId}`),
          );
          // Espejo de GERENCIA (auditor RLS M1): la lectura que F4.4 pinta es
          // la de gerencia — tampoco debe listar un compromiso que nadie
          // sostiene.
          await expectHidden(
            'F4.4 vigentes: gerencia TAMPOCO lista la alerta cuyo último asiento venció',
            sessions.gerencia.client.schema('crm').from('alertas_reconocimientos_vigentes')
              .select('id')
              .eq('alerta_id', `grupo:tarea_vencida:${f4SupervisorId}`),
          );
          await positive(
            'F4.2 vigentes: la tabla base la CONSERVA — la vista recorta, no borra',
            sessions.sup1.client.schema('crm').from('alertas_reconocimientos')
              .select('id')
              .eq('id', f4Pospuesto.data.id)
              .single(),
          );
        }
      }
    }

    const ownAgenda = await positive(
      'P04 true/true: busca su fila ICS',
      member.client.schema('crm').from('agenda_ics')
        .select('token')
        .eq('perfil_id', memberId)
        .maybeSingle(),
    );
    if (ownAgenda && !ownAgenda.data) {
      await positive(
        'P04 true/true: crea su fila ICS',
        member.client.schema('crm').from('agenda_ics')
          .insert({ perfil_id: memberId })
          .select('token')
          .single(),
      );
    }
    const tokenBeforePortalOff = await agendaToken();
    await assertFeed(tokenBeforePortalOff, true, 'P04 true/true: feed ICS autorizado');

    // Un rol global del portal no puede coexistir con una membresía CRM
    // operativa. El trigger canónico rechaza la combinación antes de que pueda
    // elevar o volver ambiguo el ámbito del Analista.
    await expectBlockedMutation(
      'P04 miembro activo: no se puede reclasificar como Directorio en el Portal',
      admin.from('perfiles')
        .update({ rol: 'directorio' })
        .eq('id', memberId)
        .select('id'),
      ['P0001'],
    );
    await assertAccess(
      member.client,
      'miembro',
      'P04 miembro activo: auth conserva la membresía CRM tras el rechazo',
      memberId,
      originalTeam.rol_crm,
      true,
    );
    const scopedMember = await positive(
      'P04 miembro activo: consulta leads sin elevar ámbito',
      member.client.schema('crm').from('leads').select('nombre_completo'),
    );
    if (scopedMember) {
      const actualNames = scopedMember.data.map((row) => row.nombre_completo);
      check(sameStrings(actualNames, [ownedLead.nombre_completo]),
        'P04 miembro activo: ve exactamente su cartera CRM',
        `real=[${sorted(actualNames).join(', ')}]`);
    }

    // false / true: el caso que el fixture anterior nunca cubría.
    await setState({ portalActive: false, crmActive: true });
    await assertDenied('P04 false/true');
    const tokenAfterPortalOff = await agendaToken();
    check(tokenAfterPortalOff === tokenBeforePortalOff,
      'P04 false/true: el gate corta el feed sin alterar tablas public');
    await assertFeed(tokenBeforePortalOff, false,
      'P04 false/true: el token no autoriza mientras el perfil está suspendido');
    await assertDestinationBlocked(
      TRANSIENT_IDS.offboardingDestinationPortalLead,
      '999000096',
      'P04 false/true: service_role no asigna a perfil portal inactivo',
    );

    // true / false: reactivar solo el perfil termina la suspensión temporal y
    // conserva su URL; el offboarding CRM (equipo=false) sí la rota de forma
    // irreversible y corta también superficies que antes usaban USING(true).
    await setState({ portalActive: true, crmActive: true });
    const tokenBeforeTeamOff = await agendaToken();
    check(tokenBeforeTeamOff === tokenBeforePortalOff,
      'P04 reactivar perfil: conserva el token de la suspensión temporal');
    await assertFeed(tokenBeforeTeamOff, true,
      'P04 reactivar perfil: el token suspendido vuelve a autorizar');
    await setState({ portalActive: true, crmActive: false });
    await assertDenied('P04 true/false');
    const tokenAfterTeamOff = await agendaToken();
    check(tokenAfterTeamOff !== tokenBeforeTeamOff,
      'P04 true/false: apagar la membresía rota el token ICS');
    await assertFeed(tokenBeforeTeamOff, false,
      'P04 true/false: el token anterior queda inválido');
    await assertDestinationBlocked(
      TRANSIENT_IDS.offboardingDestinationTeamLead,
      '999000097',
      'P04 true/false: service_role no asigna a membresía CRM inactiva',
    );

    // false / false: también cerrado y service_role conserva su bypass RLS
    // deliberado para operaciones de sistema, no el bypass del trigger destino.
    await setState({ portalActive: false, crmActive: false });
    await assertDenied('P04 false/false');
    const serviceRead = await positive(
      'P04: service_role conserva bypass RLS intencional',
      admin.schema('crm').from('leads').select('id').eq('id', ownedLead.id).single(),
    );
    if (serviceRead) {
      check(serviceRead.data.id === ownedLead.id,
        'P04: el proceso de sistema todavía lee el fixture');
    }

    // Un rol portal global NO resucita una fila CRM explícitamente revocada.
    await setState({ portalActive: true, crmActive: false, portalRole: 'directorio' });
    await assertDenied('P04 global con equipo inactivo');

    // La RPC de creación no es un oráculo para otros authenticated activos.
    for (const deniedKey of ['coordinador', 'directorio', 'clientBank']) {
      await expectHidden(
        `P04: ${deniedKey} no usa verificar_disponibilidad_lead`,
        sessions[deniedKey].client.schema('crm').rpc('verificar_disponibilidad_lead', {
          p_telefono: freePhone,
          p_dni: null,
        }),
      );
    }
  } finally {
    await setState({
      portalActive: originalProfile.activo,
      crmActive: originalTeam.activo,
      portalRole: originalProfile.rol,
    });
  }
}

async function testBankingBoundary(sessions, seed) {
  console.log('\n— Frontera portal/CRM y datos bancarios —');
  const vend1 = sessions.vend1.client;
  const bankProfileId = seed.profileIdByKey[BANK_CLIENT.key];

  const viewResponse = await positive(
    'vend1 consulta cliente fixture por crm.clientes_basicos',
    vend1.schema('crm').from('clientes_basicos').select('*').eq('dni', BANK_CLIENT.dni),
  );
  if (viewResponse) {
    check(viewResponse.data.length === 1,
      'clientes_basicos devuelve una fila conocida (prueba no vacia)',
      `devolvio ${viewResponse.data.length}`);
    const columns = Object.keys(viewResponse.data[0] ?? {});
    const bankingColumns = columns.filter((column) =>
      /banco|cuenta|cci|beneficiario|titular_distinto/i.test(column));
    check(bankingColumns.length === 0,
      'clientes_basicos no expone columnas bancarias',
      `columnas sensibles: ${bankingColumns.join(', ')}`);
  }

  await expectMissingColumn(
    'clientes_basicos rechaza incluso una proyeccion explicita de banco',
    vend1.schema('crm').from('clientes_basicos').select('id, banco').eq('id', bankProfileId),
  );

  // Scope de cartera: el cliente bancario tiene asesor_perfil_id = vend1, así que
  // vend1 lo ve (aserción de arriba) pero vend3 (otra cartera) NO debe verlo.
  await expectHidden(
    'clientes_basicos scopea por cartera: vend3 no ve el cliente de vend1',
    sessions.vend3.client.schema('crm').from('clientes_basicos').select('id').eq('id', bankProfileId),
  );

  // Vistas invoker (20260801092924): un cliente del portal tiene SELECT sobre
  // las vistas (grant amplio a authenticated) pero la guardia de las *_fn()
  // lo deja en 0 filas — sin excepción. Clavado aquí porque el flip a
  // security_invoker no debe cambiar este resultado.
  await expectHidden(
    'cliente del portal lee crm.clientes_basicos: 0 filas (guardia de la fn)',
    sessions.clientBank.client.schema('crm').from('clientes_basicos').select('id'),
  );
  await expectHidden(
    'cliente del portal lee crm.contratos_cartera: 0 filas (guardia de la fn)',
    sessions.clientBank.client.schema('crm').from('contratos_cartera').select('id'),
  );

  const bankProjection = [
    'id', 'banco', 'numero_cuenta', 'tipo_cuenta', 'cci',
    'beneficiario_nombre', 'beneficiario_dni',
    'banco_usd', 'numero_cuenta_usd', 'tipo_cuenta_usd', 'cci_usd',
    'beneficiario_nombre_usd', 'beneficiario_dni_usd',
  ].join(', ');

  // La fila PROPIA sí es visible por diseño del portal (perfiles_select:
  // auth.uid() = id): un comercial ve sus propios datos, jamás los de cartera.
  // La frontera que importa es lateral y de clientes: ningún otro perfil crudo.
  await expectHidden(
    'rol CRM (comercial) no lee el perfil crudo de otro miembro del equipo',
    vend1.from('perfiles').select(bankProjection).eq('id', seed.profileIdByKey.sup1),
  );
  await expectHidden(
    'rol CRM no lee columnas bancarias del cliente crudo',
    vend1.from('perfiles').select(bankProjection).eq('id', bankProfileId),
  );
  await expectHidden(
    'Directorio tampoco lee el perfil crudo del cliente',
    sessions.directorio.client.from('perfiles').select(bankProjection).eq('id', bankProfileId),
  );

  const detalleSupervisor = await positive(
    'Supervisor consulta el detalle seguro de un cliente de su equipo',
    sessions.sup1.client.schema('crm').rpc('cliente_detalle_fn', {
      p_cliente_id: bankProfileId,
    }),
  );
  if (detalleSupervisor) {
    const fila = detalleSupervisor.data?.[0];
    check(
      detalleSupervisor.data?.length === 1
        && typeof fila?.domicilio === 'string'
        && fila.domicilio.trim().length > 0
        && fila?.banca_visible === true
        && fila?.banco === BANK_CLIENT.bank
        && fila?.numero_cuenta === BANK_CLIENT.accountNumber
        && fila?.cci === BANK_CLIENT.cci,
      'Supervisor recibe una fila bancaria completa dentro de su árbol',
      JSON.stringify(fila),
    );
  }

  await expectHidden(
    'analista de otro árbol no descubre el cliente por cliente_detalle_fn',
    sessions.vend3.client.schema('crm').rpc('cliente_detalle_fn', {
      p_cliente_id: bankProfileId,
    }),
  );

  const detalleDirectorio = await positive(
    'Directorio consulta identidad global por cliente_detalle_fn',
    sessions.directorio.client.schema('crm').rpc('cliente_detalle_fn', {
      p_cliente_id: bankProfileId,
    }),
  );
  if (detalleDirectorio) {
    const fila = detalleDirectorio.data?.[0];
    const columnasBancarias = [
      'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
      'beneficiario_nombre', 'beneficiario_dni',
      'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
      'beneficiario_nombre_usd', 'beneficiario_dni_usd',
    ];
    check(
      detalleDirectorio.data?.length === 1
        && fila?.nombre_completo
        && fila?.domicilio === null
        && fila?.banca_visible === false
        && columnasBancarias.every((columna) => fila?.[columna] === null)
        && fila?.titular_distinto === false
        && fila?.titular_distinto_usd === false,
      'Directorio recibe identidad mínima con domicilio y banca redactados',
      JSON.stringify(fila),
    );
  }
  await expectHidden(
    'rol CRM no lee el contrato sensible desde public.contratos',
    vend1.from('contratos')
      .select('id, numero_contrato, cliente_id, capital, tasa_anual, notas_internas')
      .eq('numero_contrato', BANK_CONTRACT.number),
  );
  await expectHidden(
    'rol CRM no alcanza datos bancarios mediante contratos crudos',
    vend1.from('contratos')
      .select(`id, numero_contrato, perfiles!contratos_cliente_id_fkey(${bankProjection})`)
      .eq('numero_contrato', BANK_CONTRACT.number),
  );

  const dniRpc = await positive(
    'gerencia usa el RPC acotado de duplicado DNI',
    sessions.gerencia.client.schema('crm').rpc('existe_cliente_por_dni', {
      p_dni: BANK_CLIENT.dni,
    }),
  );
  if (dniRpc) check(dniRpc.data === true, 'RPC de DNI confirma el cliente fixture');

  await expectBlockedMutation(
    'cliente del portal no usa el RPC de enumeracion de DNI',
    sessions.clientBank.client.schema('crm').rpc('existe_cliente_por_dni', {
      p_dni: BANK_CLIENT.dni,
    }),
    ['P0001'],
  );

  // ── contrato_tiene_pagos exige ámbito (20260801092924) ─────────────────────
  // Era la ÚNICA RPC expuesta de las 41 sin guardia: cualquier authenticated
  // (un cliente del portal, un comercial ajeno) podía sondear si un contrato
  // tiene pagos conociendo el UUID. Ahora delega en puede_ver_contrato y para
  // un no autorizado devuelve false SIN excepción (así el llamador del portal
  // admin no cambia). La cuota pagada es transitoria: la crea service_role y
  // se borra al final para no perforar el fixture.
  const cuotaSonda = await positive(
    'admin crea la cuota pagada transitoria del contrato fixture',
    admin.from('cronograma_pagos').insert({
      contrato_id: BANK_CONTRACT.id,
      numero_cuota: 999,
      fecha_programada: '2026-02-01',
      monto_programado: 100,
      estado: 'pagado',
      tipo: 'cuota',
      monto_pagado: 100,
    }).select('id').single(),
  );

  if (cuotaSonda) {
    const sondaDueno = await positive(
      'el cliente dueño consulta pagos de SU contrato',
      sessions.clientBank.client.rpc('contrato_tiene_pagos', {
        p_contrato_id: BANK_CONTRACT.id,
      }),
    );
    if (sondaDueno) check(sondaDueno.data === true,
      'contrato_tiene_pagos: el dueño sigue viendo la señal real (true)');

    const sondaAjena = await positive(
      'vend3 (fuera de la cartera) sondea el mismo contrato',
      sessions.vend3.client.rpc('contrato_tiene_pagos', {
        p_contrato_id: BANK_CONTRACT.id,
      }),
    );
    if (sondaAjena) check(sondaAjena.data === false,
      'contrato_tiene_pagos devuelve false para un authenticated fuera de ámbito',
      `devolvio ${JSON.stringify(sondaAjena.data)}`);

    // Decisión consciente: service_role SIN JWT tampoco ve la señal por esta
    // RPC (auth.uid() null → puede_ver_contrato false). La RPC es para humanos
    // logueados; los procesos con service_role leen cronograma_pagos directo.
    const sondaServiceRole = await positive(
      'service_role sin JWT consulta la RPC (semantica clavada)',
      admin.rpc('contrato_tiene_pagos', { p_contrato_id: BANK_CONTRACT.id }),
    );
    if (sondaServiceRole) check(sondaServiceRole.data === false,
      'contrato_tiene_pagos: service_role sin JWT recibe false (lee tablas directo)');

    await positive(
      'admin borra la cuota transitoria (fixture restaurado)',
      admin.from('cronograma_pagos').delete()
        .eq('id', cuotaSonda.data.id).select('id').single(),
    );
  }

  // ── Trigger perfiles_cuentas_no_vaciar (20260728044338) ────────────────────
  // Un cliente que YA tiene cuenta no puede QUEDAR sin ninguna. La prueba dura
  // es con `admin` (service_role): la RLS no aplica, solo el trigger puede
  // frenar. Los casos permitidos terminan restaurando el fixture exacto.
  const columnasVacias = {
    banco: null, numero_cuenta: null, tipo_cuenta: null, cci: null,
    beneficiario_nombre: null, beneficiario_dni: null,
    banco_usd: null, numero_cuenta_usd: null, tipo_cuenta_usd: null, cci_usd: null,
    beneficiario_nombre_usd: null, beneficiario_dni_usd: null,
  };

  await expectBlockedMutation(
    'trigger: ni service_role puede dejar al cliente SIN ninguna cuenta',
    admin.from('perfiles').update(columnasVacias).eq('id', bankProfileId).select('id'),
    ['P0001'],
  );

  // El bypass que costó el NO-GO de la auditoría: '' satisface `is not null`.
  // El trigger normaliza con nullif(btrim(...)) — cadena vacía = vacío.
  await expectBlockedMutation(
    'trigger: vaciar con cadenas VACIAS tampoco pasa (bypass del NO-GO)',
    admin.from('perfiles').update({
      banco: '', numero_cuenta: '', banco_usd: ' ', numero_cuenta_usd: '',
    }).eq('id', bankProfileId).select('id'),
    ['P0001'],
  );

  await expectBlockedMutation(
    'trigger: el cliente tampoco puede vaciarse sus propias cuentas',
    sessions.clientBank.client.from('perfiles').update(columnasVacias)
      .eq('id', bankProfileId).select('id'),
    ['P0001'],
  );

  const cambioNumero = await positive(
    'trigger: corregir el numero de cuenta (full → full) sigue permitido',
    admin.from('perfiles').update({ numero_cuenta: '19100000000099' })
      .eq('id', bankProfileId).select('id'),
  );
  if (cambioNumero) {
    await positive(
      'trigger: restaurar el numero de cuenta del fixture',
      admin.from('perfiles').update({ numero_cuenta: BANK_CLIENT.accountNumber })
        .eq('id', bankProfileId).select('id'),
    );
  }

  const sinUsd = await positive(
    'trigger: quitar SOLO la cuenta USD (la PEN sigue viva) esta permitido',
    admin.from('perfiles').update({
      banco_usd: null, numero_cuenta_usd: null, tipo_cuenta_usd: null, cci_usd: null,
    }).eq('id', bankProfileId).select('id'),
  );
  if (sinUsd) {
    await positive(
      'trigger: restaurar la cuenta USD del fixture',
      admin.from('perfiles').update({
        banco_usd: BANK_CLIENT.bankUsd,
        numero_cuenta_usd: BANK_CLIENT.accountNumberUsd,
        tipo_cuenta_usd: BANK_CLIENT.accountTypeUsd,
        cci_usd: BANK_CLIENT.cciUsd,
      }).eq('id', bankProfileId).select('id'),
    );
  }

  // Simetria: la rama PEN de «queda» tambien tiene que sostener sola la regla.
  const sinPen = await positive(
    'trigger: quitar SOLO la cuenta PEN (la USD sigue viva) esta permitido',
    admin.from('perfiles').update({
      banco: null, numero_cuenta: null, tipo_cuenta: null, cci: null,
    }).eq('id', bankProfileId).select('id'),
  );
  if (sinPen) {
    await positive(
      'trigger: restaurar la cuenta PEN del fixture',
      admin.from('perfiles').update({
        banco: BANK_CLIENT.bank,
        numero_cuenta: BANK_CLIENT.accountNumber,
        tipo_cuenta: BANK_CLIENT.accountType,
        cci: BANK_CLIENT.cci,
      }).eq('id', bankProfileId).select('id'),
    );
  }
  // Los casos vacio→lleno (flujo del portal) y legacy-sin-cuenta-editable viven
  // en el oraculo test-perfiles-cuentas.sql (V07/V08): alli corren en rollback,
  // sin dejar un fixture compartido mutado si fallara a mitad.
}

async function testContractBankAccounts(sessions, seed) {
  console.log('\n— Cuenta bancaria fija por contrato —');
  const bankProfileId = seed.profileIdByKey[BANK_CLIENT.key];
  const analystIds = [seed.profileIdByKey.vend1, seed.profileIdByKey.vend3];
  const directorProfileId = seed.profileIdByKey.directorio;
  const originalDirectorRole = seed.profiles.find(
    (profile) => profile.id === directorProfileId,
  )?.rol;
  let directorRoleChanged = false;
  // La sonda de revocación fabrica una fila en crm.equipo para directorio (el
  // único fixture que nace SIN membresía). Si una aserción falla a mitad, esa
  // fila apagada sobrevive a la corrida y envenena la siguiente: el lector
  // global cuenta inactivos y el conteo del DIRECTORIO se rompe. Se limpia en
  // el finally, no solo en el camino feliz.
  let directorMembershipFabricated = false;
  // Igual que la fila fabricada: si la sonda del perfil apagado falla a mitad,
  // directorio se queda desactivado y envenena todo lo que venga después.
  let directorDeactivated = false;
  const originalActors = analystIds.map((id) => ({
    activo: seed.profiles.find((profile) => profile.id === id)?.activo,
    crmActivo: seed.team.find((member) => member.perfil_id === id)?.activo,
    id,
    rol: seed.profiles.find((profile) => profile.id === id)?.rol,
  }));
  assertSeed(typeof originalDirectorRole === 'string',
    'falta el rol original de directorio para la sonda bancaria');
  for (const actor of originalActors) {
    assertSeed(typeof actor.activo === 'boolean' && typeof actor.crmActivo === 'boolean',
      `faltan los flags originales del actor bancario ${actor.id}`);
    assertSeed(typeof actor.rol === 'string',
      `falta el rol original del actor bancario ${actor.id}`);
  }
  const expectedProfileAccount = {
    banco: BANK_CLIENT.bank,
    tipo_cuenta: BANK_CLIENT.accountType,
    numero_cuenta: BANK_CLIENT.accountNumber,
    cci: BANK_CLIENT.cci,
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
  };
  const minimalContract = { cliente_id: bankProfileId, moneda: BANK_CONTRACT.currency };

  async function setVend1State({ portalActive, crmActive }) {
    const updateProfile = () => requireAdmin(
      `banca P04: fijar perfil vend1 activo=${portalActive}`,
      admin.from('perfiles')
        .update({ activo: portalActive })
        .eq('id', seed.profileIdByKey.vend1),
    );
    const updateTeam = () => requireAdmin(
      `banca P04: fijar equipo vend1 activo=${crmActive}`,
      admin.schema('crm').from('equipo')
        .update({ activo: crmActive })
        .eq('perfil_id', seed.profileIdByKey.vend1),
    );

    // Revocar corta primero CRM — y va FUERA DE BANDA: vend1 posee los leads
    // del fixture y el guard (con razón) no deja desactivarlo por UPDATE
    // normal (avería hermana de la matriz P04, rota igual desde el 8-ago).
    // El estado perfil-muerto/equipo-vivo NO se re-asegura con updateTeam:
    // post-8-ago esa combinación es infabricable por escritura (el guard la
    // rechaza) y solo existe HEREDADA — apagar el perfil dejando la fila de
    // equipo como está la produce sin fabricar nada.
    if (!crmActive) {
      revocarEquipoFueraDeBanda(seed.profileIdByKey.vend1);
      await updateProfile();
    } else if (!portalActive) {
      await updateProfile();
    } else {
      await updateProfile();
      await updateTeam();
    }
  }

  async function assertBankSurfaceDenied(label) {
    await expectExpectedFailure(
      `${label}: no lista cuentas contractuales`,
      sessions.vend1.client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
      ['42501'],
      /cliente no encontrado o fuera de tu cartera/i,
    );
    // F7.1: las puertas internas quedaron cerradas; estas sondas entran por las
    // puertas VIVAS (pdf_v2/v3), que delegan en las mismas validaciones — la
    // cobertura de negocio NO se pierde (hallazgo Codex 30/08).
    await expectExpectedFailure(
      `${label}: no crea contrato con cuenta (via pdf_v2)`,
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta_pdf_v2', {
        p_contrato: minimalContract,
        p_cronograma: [],
        p_cuenta: {
          tipo: 'perfil',
          cuenta_esperada: expectedProfileAccount,
        },
      }),
      ['42501'],
      /cliente no encontrado o fuera de tu cartera/i,
    );
    await expectExpectedFailure(
      `${label}: no corrige contrato ya enlazado (via pdf_v3)`,
      sessions.vend1.client.schema('crm').rpc('actualizar_contrato_con_cuenta_pdf_v3', {
        p_id: seed.contract.id,
        p_contrato: { moneda: BANK_CONTRACT.currency },
        p_cronograma: [],
      }),
      ['42501'],
      /contrato no encontrado o fuera de tu cartera/i,
    );
    await expectExpectedFailure(
      `${label}: no corrige contrato legacy sin enlace (via pdf_v3)`,
      sessions.vend1.client.schema('crm').rpc('actualizar_contrato_con_cuenta_pdf_v3', {
        p_id: seed.legacyContract.id,
        p_contrato: { moneda: BANK_LEGACY_CONTRACT.currency },
        p_cronograma: { invalido: true },
      }),
      ['42501'],
      /contrato no encontrado o fuera de tu cartera/i,
    );
    await expectExpectedFailure(
      `${label}: no resuelve cuentas contractuales para Pagos`,
      sessions.vend1.client.schema('crm').rpc('cuentas_pago_contratos_fn', {
        p_contrato_ids: [seed.contract.id],
      }),
      ['42501'],
      /no autorizado para consultar cuentas de pago/i,
    );
  }

  async function assertAdminBankRead(client, label) {
    const listed = await positive(
      `${label}: lista cuentas bancarias`,
      client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
    );
    check(
      Array.isArray(listed?.data)
        && listed.data.some((row) => row.cci === BANK_CLIENT.cci),
      `${label}: el listado incluye la cuenta contractual`,
    );

    const paymentAccounts = await positive(
      `${label}: resuelve cuentas para Pagos`,
      client.schema('crm').rpc('cuentas_pago_contratos_fn', {
        p_contrato_ids: [seed.contract.id],
      }),
    );
    check(
      Array.isArray(paymentAccounts?.data)
        && paymentAccounts.data.some(
          (row) => row.contrato_id === seed.contract.id
            && row.cuenta_bancaria_id === seed.bankAccount.id,
        ),
      `${label}: Pagos recibe la fotografia contractual esperada`,
    );
  }

  // El fixture principal usa el rol portal neutro `comercial` para probar que el
  // CRM no hereda las policies bancarias del portal. Esta sección cambia solo
  // Durante la sonda cambia a los dos perfiles con rol CRM legacy `vendedor`
  // al rol Portal `analista`: reproduce la identidad
  // real que autoriza crear contratos y restaura ambos roles en `finally`.
  //
  // La bandera de identidad F2.b `resolver_en_puertas` tiene que estar APAGADA
  // durante este bloque, como aterriza en produccion: encendida,
  // `private.asegurar_identidad_perfil` rechaza al fixture bancario (P0409 «este
  // perfil ya pertenece a otra persona reconocida») y TODA alta de contrato muere
  // antes de probar nada (05/09/2026: 65 rojos que no eran del codigo). Otros
  // ensayos del banco compartido la encienden para lo suyo; aqui se fija y se
  // restaura en el `finally`, igual que hace `oraculo-alta-idempotente.sh`.
  const resolverEnPuertasOriginal = contarFueraDeBanda(
    'bloque bancario: leer resolver_en_puertas',
    "select count(*) from crm.multiempresa_flags where nombre='resolver_en_puertas' and activo",
  ) === 1;
  const fijarResolverEnPuertas = (on, etiqueta) => ejecutarFueraDeBanda(
    `bloque bancario: ${etiqueta}`,
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`,
  );
  fijarResolverEnPuertas(false, 'apagar resolver_en_puertas (estado de produccion)');
  try {
    await requireAdmin(
      'activar temporalmente el rol portal analista para las sondas bancarias',
      admin.from('perfiles').update({ rol: 'analista' }).in('id', analystIds),
    );

    const listed = await positive(
      'analista de cartera lista las cuentas elegibles del cliente',
      sessions.vend1.client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
    );
    if (listed) {
      const account = (listed.data ?? []).find((row) => row.cci === BANK_CLIENT.cci);
      check(!!account,
        'el listado autorizado incluye la cuenta PEN conocida del cliente');
      if (account) {
        check(
          account.moneda === BANK_CONTRACT.currency
            && account.banco === BANK_CLIENT.bank
            && account.numero_cuenta === BANK_CLIENT.accountNumber
            && account.tipo_cuenta === BANK_CLIENT.accountType,
          'la RPC devuelve la cuenta completa en la moneda solicitada',
          JSON.stringify(account),
        );
      }
    }

    await expectExplicitAuthorizationDenied(
      'analista ajeno no lista cuentas fuera de su cartera',
      sessions.vend3.client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
    );
    await expectExplicitAuthorizationDenied(
      'directorio no lista cuentas bancarias de clientes',
      sessions.directorio.client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
    );

    // Regresion que motivo esta entrega: un JWT ya emitido no puede conservar
    // ninguna RPC bancaria si UNO de los dos flags vivos de P04 queda apagado.
    // (false/true es un estado HEREDADO: solo se apaga el perfil; re-escribir
    // la fila de equipo dispararía el guard que hoy prohíbe fabricarlo.)
    await setVend1State({ portalActive: false, crmActive: true });
    await assertBankSurfaceDenied('banca P04 false/true');
    await setVend1State({ portalActive: true, crmActive: false });
    await assertBankSurfaceDenied('banca P04 true/false');
    await setVend1State({ portalActive: true, crmActive: true });

    // El gate tambien envuelve al admin cuando existe una membresia CRM: una
    // fila activa permite su poder del portal y una fila revocada prevalece.
    await requireAdmin(
      'banca P04: convertir vend1 temporalmente en admin con membresia activa',
      admin.from('perfiles').update({ rol: 'admin' }).eq('id', seed.profileIdByKey.vend1),
    );
    await assertAdminBankRead(
      sessions.vend1.client,
      'admin con membresia CRM activa',
    );
    await setVend1State({ portalActive: true, crmActive: false });
    await assertBankSurfaceDenied('banca P04 admin con membresia revocada');
    await setVend1State({ portalActive: true, crmActive: true });
    await requireAdmin(
      'banca P04: restaurar vend1 como analista para las sondas restantes',
      admin.from('perfiles').update({ rol: 'analista' }).eq('id', seed.profileIdByKey.vend1),
    );

    // FALLBACK GLOBAL DE P04, RESTAURADO EL 2026-08-09 (20260809000530).
    //
    // Historia de estas sondas, porque se invirtieron dos veces en dos días:
    //   · P04 original (20260804144555:5-8) lo declaró por escrito: «Un admin
    //     del portal sin membresia CRM conserva el fallback global; si tiene
    //     una fila en crm.equipo y esa membresia se apaga, la revocacion
    //     prevalece». Funcionaba porque es_lector_global() aún cubría a
    //     admin/superadmin, así que puede_acceder_crm() les daba true.
    //   · El 2026-08-08 estas sondas se invirtieron a «ya no lista / ya no
    //     resuelve» al observar el efecto del es_lector_global() estrecho
    //     (20260807203740) compuesto con la línea de P04 repuesta. Se clavó el
    //     SÍNTOMA como si fuera el diseño.
    //   · Medición en prod (2026-08-08) del costo real de esa inversión:
    //     `gloria@` — admin del portal que da soporte a los analistas
    //     gestionando Pagos y creando contratos, sin fila en crm.equipo porque
    //     su trabajo vive en el portal — quedó sin crear contratos, sin
    //     corregirlos y sin la página de Pagos. No es una persona
    //     offboardeada; nunca fue del CRM.
    //   · 20260809000530 separa las dos preguntas: lo que prevalece sobre el
    //     rol de portal es la REVOCACIÓN explícita (private.membresia_crm_revocada),
    //     no la ausencia de membresía. Estas sondas vuelven a su sentido
    //     original y la invariante de offboarding queda clavada aparte, en
    //     'banca P04 admin con membresia revocada' (arriba, con fila apagada).
    await requireAdmin(
      'banca P04: convertir directorio temporalmente en admin global',
      admin.from('perfiles').update({ rol: 'admin' }).eq('id', directorProfileId),
    );
    directorRoleChanged = true;
    await assertAdminBankRead(
      sessions.directorio.client,
      'admin global sin membresia CRM (fallback P04)',
    );
    // Rama analista del guard SIN membresía CRM. Con el fallback restaurado el
    // gate de P04 ya no la frena. Aquí se separan las dos superficies porque
    // desde P-055 F5.c divergen:
    //   · la BANCA del CRM (`cuentas_bancarias_cliente_fn`) SIGUE cerrada por
    //     cartera —P04 vive intacta para banca/PDF/domicilio—: el cliente
    //     bancario tiene asesor_perfil_id = vend1, así que un analista ajeno no
    //     lo alcanza (mismo 42501 de siempre).
    //   · el ALTA LEGACY del portal (`public.crear_contrato`) YA NO cierra por
    //     cartera (decisión B de Miguel): un analista VIGENTE (rol analista del
    //     Portal, sin fila en crm.equipo = no revocado) pasa la autoridad para
    //     CUALQUIER cliente activo, incluido el ajeno. Con cronograma vacío el
    //     alta atraviesa la autorización y muere en la validación de términos
    //     (23514) — eso PRUEBA que la cartera ya no es la barrera, sin escribir
    //     una fila. Esta pareja clava que las dos superficies divergieron a
    //     propósito y no por un predicado suelto.
    //     🔴 F3.7 (20260829183000) añadió una regla que dispara ANTES: si quien
    //     registra no está en el equipo comercial, la venta necesita un
    //     `analista_cierre_id` EXPLÍCITO (22023 «Elige el analista de la
    //     venta»). Sin él, este caso moría ahí y dejaba la cartera SIN medir
    //     (lo destapó el banco el 01/09). Se nombra a vend3 —activo, de OTRO
    //     subárbol y NO dueño del cliente— para atravesar esa puerta y volver
    //     a llegar a la de términos: el actor sigue siendo el MISMO
    //     (directorio-como-analista) y la divergencia banca↔alta sigue clavada
    //     sobre él. Codex verificó el ORDEN vivo de las validaciones: cliente y
    //     autoridad del registrador van ANTES que el analista nombrado, así que
    //     llegar a 23514 sigue midiendo la autoridad, no solo los términos.
    await requireAdmin(
      'banca P04: convertir directorio temporalmente en analista sin membresia',
      admin.from('perfiles').update({ rol: 'analista' }).eq('id', directorProfileId),
    );
    await expectExpectedFailure(
      'analista sin membresia CRM: la cartera sigue cerrando la banca ajena',
      sessions.directorio.client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
      ['42501'],
      /cliente no encontrado o fuera de tu cartera/i,
    );
    await expectExpectedFailure(
      'analista vigente registra para cliente ajeno: la Opcion B ya NO cierra el alta por cartera',
      sessions.directorio.client.rpc('crear_contrato', {
        p_contrato: {
          cliente_id: bankProfileId,
          moneda: BANK_CONTRACT.currency,
          capital: 1000,
          tasa_anual: 10,
          categoria: 'nuevo',
          // F3.7: quien registra (directorio-como-analista) no está en
          // crm.equipo, así que la venta debe nombrar a su analista. vend3 está
          // activo en OTRO subárbol y NO es el dueño del cliente (el dueño es
          // vend1) — doble filo: si la cartera volviera a ser barrera para el
          // registrador O para el analista nombrado, esto no llegaría a los
          // términos.
          analista_cierre_id: seed.profileIdByKey.vend3,
        },
        p_cronograma: [],
      }),
      ['23514'],
      /t[ée]rminos inv[áa]lidos/i,
    );
    // La distinción que introduce 20260809000530, clavada sobre el MISMO actor
    // para que no pueda pasar en falso por diferencias de fixture: directorio
    // como admin global gana la banca sin fila en crm.equipo (arriba) y la
    // pierde en cuanto existe una fila APAGADA. Sin esta pareja, un futuro
    // `not exists(...)` mal escrito —o un regreso a `puede_acceder_crm()`—
    // pasaría verde con solo una de las dos mitades.
    await requireAdmin(
      'banca P04: devolver a directorio el rol admin global',
      admin.from('perfiles').update({ rol: 'admin' }).eq('id', directorProfileId),
    );
    await requireAdmin(
      'banca P04: fabricar membresia CRM REVOCADA para directorio',
      admin.schema('crm').from('equipo').insert({
        perfil_id: directorProfileId,
        rol_crm: 'directorio',
        activo: false,
      }),
    );
    directorMembershipFabricated = true;
    await expectExpectedFailure(
      'admin con membresia CRM revocada: la revocacion prevalece sobre la banca',
      sessions.directorio.client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
      ['42501'],
      /cliente no encontrado o fuera de tu cartera/i,
    );
    await expectExpectedFailure(
      'admin con membresia CRM revocada: la revocacion prevalece sobre Pagos',
      sessions.directorio.client.schema('crm').rpc('cuentas_pago_contratos_fn', {
        p_contrato_ids: [seed.contract.id],
      }),
      ['42501'],
      /no autorizado para consultar cuentas de pago/i,
    );
    // P04 sobre la CORRECCION de contratos por la via admin del Portal
    // (20260809003923). El alta ya estaba gateada para todo actor desde el
    // catalogo; corregir no lo estaba: la rama admin de public.actualizar_contrato
    // pasaba con `null`, y public.actualizar_numero_contrato solo miraba
    // es_admin(). Esta ultima es la mas silenciosa porque no nombra al guard en
    // ninguna parte y ademas SOBREVIVE A CUOTAS PAGADAS. Con el actor revocado ya
    // fabricado arriba, se clavan ambas puertas.
    await expectExpectedFailure(
      'admin con membresia CRM revocada: no corrige terminos del contrato',
      sessions.directorio.client.rpc('actualizar_contrato', {
        p_id: seed.contract.id,
        p_contrato: {
          capital: 5000,
          tasa_anual: 12,
          modalidad: 'mensual',
          fecha_inicio: '2026-01-01',
          fecha_vencimiento: '2027-01-01',
        },
        p_cronograma: [],
      }),
      ['42501'],
      /membresia crm fue revocada/i,
    );
    await expectExpectedFailure(
      'admin con membresia CRM revocada: no corrige N/notas aunque haya cuotas pagadas',
      // F7.1: public.actualizar_numero_contrato quedo cerrada; se entra por su
      // puerta viva pdf_v3, que delega en la misma autorizacion.
      sessions.directorio.client.schema('crm').rpc('actualizar_numero_contrato_pdf_v3', {
        p_id: seed.contract.id,
        p_numero: 'SONDA-P04-REVOCADO',
        p_notas: null,
        p_categoria: null,
      }),
      ['42501'],
      /membresia crm fue revocada/i,
    );
    // «La RPC lanzó excepción» NO es lo mismo que «no escribió». Si el gate
    // regresara, las dos sondas de arriba habrian reescrito capital/tasa/fechas
    // y el numero del contrato del fixture (y puesto notas_internas en NULL,
    // porque el payload no trae la clave). Se comprueba la fila real: asi el
    // rechazo se convierte en prueba de NO-ESCRITURA, que es lo que importa.
    const filaTrasRechazo = await requireAdmin(
      'banca P04: releer el contrato tras las sondas de revocacion',
      admin.from('contratos')
        .select('numero_contrato, capital, notas_internas')
        .eq('id', seed.contract.id)
        .single(),
    );
    check(
      filaTrasRechazo?.data?.numero_contrato === BANK_CONTRACT.number
        && Number(filaTrasRechazo?.data?.capital) === BANK_CONTRACT.capital
        && filaTrasRechazo?.data?.notas_internas === BANK_CONTRACT.internalNotes,
      'admin revocado: el contrato quedo intacto (el rechazo no escribio nada)',
      JSON.stringify(filaTrasRechazo?.data),
    );
    // P-055 F5.a: `crm.equipo` tiene candado BEFORE DELETE -borrar una fila
    // convierte a un REVOCADO en AJENO y le devuelve los accesos del Portal-.
    // La fila fabricada se retira por la PUERTA DECLARADA, que exige llave de
    // servidor, motivo escrito y deja lapida en private.membresias_purgadas.
    await requireAdmin(
      'banca P04: retirar la membresia revocada fabricada (puerta declarada)',
      admin.schema('crm').rpc('purgar_membresia_crm', {
        p_perfil_id: directorProfileId,
        p_motivo: 'Gate test-rls: retirar la membresia CRM fabricada para las sondas de banca P04',
      }),
    );
    directorMembershipFabricated = false;

    // MITAD POSITIVA de la pareja para la correccion de contratos. Sin ella, un
    // futuro predicado invertido —o un regreso a puede_acceder_crm()— dejaria a
    // gloria@ y AdminCorp@ sin corregir contratos (el incidente exacto del
    // 08-08) y el gate seguiria verde con solo las sondas negativas.
    // NO DESTRUCTIVAS a proposito: se envia un payload invalido, asi que
    // atravesar la autorizacion y morir en la VALIDACION siguiente prueba que el
    // gate dejo pasar, sin escribir una sola fila.
    await expectExpectedFailure(
      'admin sin membresia CRM: la correccion de terminos NO se le cierra',
      sessions.directorio.client.rpc('actualizar_contrato', {
        p_id: seed.contract.id,
        p_contrato: {
          capital: 1,
          tasa_anual: 12,
          modalidad: 'mensual',
          fecha_inicio: '2026-01-01',
          fecha_vencimiento: '2027-01-01',
        },
        p_cronograma: [],
      }),
      ['P0001'],
      /capital debe estar entre/i,
    );
    await expectExpectedFailure(
      'admin sin membresia CRM: la correccion de N/notas NO se le cierra',
      // F7.1: por la puerta viva pdf_v3 — atraviesa la autorizacion y muere en
      // la MISMA validacion de siempre (numero vacio), sin escribir nada.
      sessions.directorio.client.schema('crm').rpc('actualizar_numero_contrato_pdf_v3', {
        p_id: seed.contract.id,
        p_numero: '   ',
        p_notas: null,
        p_categoria: null,
      }),
      ['P0001'],
      /no puede quedar vacio/i,
    );

    // Perfil de portal APAGADO, rama admin (hallazgo del auditor-rls
    // 2026-08-08). Antes de 20260809000530 el cierre de un perfil desactivado
    // lo garantizaba `puede_acceder_crm()` de forma independiente del portal
    // (private.rol_crm y es_lector_global exigen ambos `perfiles.activo`). Esa
    // migración retira esa garantía y la delega en `public.es_admin()`, que
    // vive en un esquema que este repo NO versiona. Se verificó con
    // pg_get_functiondef que hoy filtra por `activo = true`; estas sondas lo
    // CLAVAN para que un cambio del portal no lo rompa en silencio. Sin ellas,
    // un empleado desactivado conservaría cuentas_pago_contratos_fn, que
    // devuelve numero_cuenta, cci y beneficiario_dni SIN scoping alguno.
    await requireAdmin(
      'banca P04: apagar el perfil portal de directorio-admin',
      admin.from('perfiles').update({ activo: false }).eq('id', directorProfileId),
    );
    directorDeactivated = true;
    await expectExpectedFailure(
      'admin sin membresia con perfil APAGADO: no lista cuentas bancarias',
      sessions.directorio.client.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
        p_cliente_id: bankProfileId,
        p_moneda: BANK_CONTRACT.currency,
      }),
      ['42501'],
      /cliente no encontrado o fuera de tu cartera/i,
    );
    await expectExpectedFailure(
      'admin sin membresia con perfil APAGADO: no resuelve cuentas para Pagos',
      sessions.directorio.client.schema('crm').rpc('cuentas_pago_contratos_fn', {
        p_contrato_ids: [seed.contract.id],
      }),
      ['42501'],
      /no autorizado para consultar cuentas de pago/i,
    );
    await requireAdmin(
      'banca P04: reactivar el perfil portal de directorio',
      admin.from('perfiles').update({ activo: true }).eq('id', directorProfileId),
    );
    directorDeactivated = false;
    await requireAdmin(
      'banca P04: restaurar el rol global de directorio',
      admin.from('perfiles').update({ rol: originalDirectorRole }).eq('id', directorProfileId),
    );
    directorRoleChanged = false;

    // No se acepta como prueba un SELECT exitoso con 0 filas: las tablas deben
    // carecer de GRANT para authenticated, aun cuando su RLS tambien este activa.
    await expectExplicitAuthorizationDenied(
      'authenticated no tiene SELECT directo sobre crm.cuentas_bancarias',
      sessions.vend1.client.schema('crm').from('cuentas_bancarias').select('id').limit(1),
    );
    await expectExplicitAuthorizationDenied(
      'authenticated no tiene SELECT directo sobre crm.contrato_cuentas_pago',
      sessions.vend1.client.schema('crm').from('contrato_cuentas_pago').select('id').limit(1),
    );

    // F7.1: la puerta interna quedo cerrada; las validaciones de negocio se
    // siguen ejercitando por la puerta VIVA pdf_v2 (mismos argumentos, delega
    // en la misma funcion) — la cobertura semantica NO se pierde (Codex 30/08).
    await expectExpectedFailure(
      'el alta rechaza una instantanea obsoleta de la cuenta del perfil (via pdf_v2)',
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta_pdf_v2', {
        p_contrato: minimalContract,
        p_cronograma: [],
        p_cuenta: {
          tipo: 'perfil',
          cuenta_esperada: { ...expectedProfileAccount, banco: 'BANCO OBSOLETO' },
        },
      }),
      ['P0001'],
      /cuenta actual del cliente cambio/i,
    );
    await expectExpectedFailure(
      'el alta rechaza un UUID de cuenta existente forjado (via pdf_v2)',
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta_pdf_v2', {
        p_contrato: minimalContract,
        p_cronograma: [],
        p_cuenta: { tipo: 'existente', cuenta_id: randomUUID() },
      }),
      ['22023'],
      /cuenta bancaria no esta disponible/i,
    );

    // Oraculo de atomicidad sin DELETE: la cuenta se inserta antes de delegar en
    // public.crear_contrato. Reutilizar el numero del fixture provoca una falla
    // contractual controlada (UNIQUE); toda la llamada debe revertirse.
    const rollbackToken = randomUUID().replaceAll('-', '').toUpperCase();
    const rollbackCci = randomUUID().replace(/\D/g, '').padEnd(20, '0').slice(0, 20);
    const accountBefore = await requireAdmin(
      'precondicion: la cuenta sentinela de rollback no existe',
      admin.schema('crm').from('cuentas_bancarias')
        .select('id', { count: 'exact', head: true })
        .eq('cliente_id', bankProfileId)
        .eq('cci', rollbackCci),
    );
    check(accountBefore.count === 0,
      'la cuenta sentinela es unica antes de probar el rollback');
    const linksBefore = await requireAdmin(
      'contar enlaces contractuales antes del rollback',
      admin.schema('crm').from('contrato_cuentas_pago')
        .select('id', { count: 'exact', head: true }),
    );

    const duplicateContract = {
      cliente_id: bankProfileId,
      numero_contrato: BANK_CONTRACT.number,
      capital: BANK_CONTRACT.capital,
      moneda: BANK_CONTRACT.currency,
      tasa_anual: BANK_CONTRACT.annualRate,
      modalidad: BANK_CONTRACT.paymentMode,
      tipo_interes: BANK_CONTRACT.interestType,
      fecha_inicio: BANK_CONTRACT.startDate,
      fecha_vencimiento: BANK_CONTRACT.endDate,
      categoria: BANK_CONTRACT.category,
      notas_internas: 'RLS ROLLBACK ATOMICO',
      titulares: [],
    };
    const validSchedule = [
      {
        numero_cuota: 1,
        fecha_programada: BANK_CONTRACT.endDate,
        monto_programado: 100,
        tipo: 'cuota',
      },
      {
        numero_cuota: 2,
        fecha_programada: '2027-01-08',
        monto_programado: BANK_CONTRACT.capital,
        tipo: 'retorno',
      },
    ];
    await expectExpectedFailure(
      'una falla del contrato revierte tambien la cuenta nueva de la misma RPC (via pdf_v2)',
      // F7.1: la atomicidad se prueba por la puerta VIVA — la transaccion de
      // pdf_v2 envuelve delegada + PDF; el UNIQUE revienta y TODO se revierte.
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta_pdf_v2', {
        p_contrato: duplicateContract,
        p_cronograma: validSchedule,
        p_cuenta: {
          tipo: 'nueva',
          banco: 'BANCO RLS ROLLBACK',
          tipo_cuenta: 'ahorros',
          numero_cuenta: `RLS-${rollbackToken.slice(0, 12)}`,
          cci: rollbackCci,
          titular_distinto: false,
          beneficiario_nombre: null,
          beneficiario_dni: null,
        },
      }),
      ['23505', 'P0001'],
      /contrato.*(?:ya existe|duplicad)|duplicate key/i,
    );

    const accountAfter = await requireAdmin(
      'verificar que el rollback no dejo la cuenta sentinela',
      admin.schema('crm').from('cuentas_bancarias')
        .select('id', { count: 'exact', head: true })
        .eq('cliente_id', bankProfileId)
        .eq('cci', rollbackCci),
    );
    check(accountAfter.count === 0,
      'rollback atomico: no quedo ninguna cuenta bancaria sentinela');
    const linksAfter = await requireAdmin(
      'contar enlaces contractuales despues del rollback',
      admin.schema('crm').from('contrato_cuentas_pago')
        .select('id', { count: 'exact', head: true }),
    );
    check(linksAfter.count === linksBefore.count,
      'rollback atomico: no quedo ningun enlace cuenta-contrato',
      `antes=${linksBefore.count}, despues=${linksAfter.count}`);

    // ── 05/09/2026: el alta es IDEMPOTENTE por clave (migracion 20260905190000) ──
    // Re-pin defensivo: el bloque lleva minutos y otra sesion del banco compartido
    // puede haber vuelto a encender la bandera entre medias.
    fijarResolverEnPuertas(false, 'reafirmar resolver_en_puertas apagada antes de idempotencia');
    // Reproduce el incidente por la puerta VIVA: misma clave, el analista cambia el
    // numero y reintenta → el servidor devuelve el MISMO contrato en vez de crear
    // otro. Contratos del regimen documental ANTERIOR (firmados antes del 19/08),
    // que es el caso real y ademas no exige la fotografia legal del PDF.
    {
      const claveIdem = randomUUID();
      const idemToken = randomUUID().replaceAll('-', '').toUpperCase().slice(0, 10);
      const idemCci = randomUUID().replace(/\D/g, '').padEnd(20, '0').slice(0, 20);
      const payloadIdem = (numero, extra = {}) => ({
        p_contrato: {
          cliente_id: bankProfileId,
          numero_contrato: numero,
          capital: 20000,
          moneda: 'PEN',
          tasa_anual: 15,
          modalidad: 'mensual',
          tipo_interes: 'simple',
          categoria: 'nuevo',
          fecha_inicio: '2026-03-11',
          fecha_vencimiento: '2027-03-11',
          notas_internas: 'RLS IDEMPOTENCIA DEL ALTA',
          titulares: [],
          ...extra,
        },
        p_cronograma: [
          { numero_cuota: 1, fecha_programada: '2026-04-11', monto_programado: 250, tipo: 'cuota' },
          { numero_cuota: 2, fecha_programada: '2027-03-11', monto_programado: 20000, tipo: 'retorno' },
        ],
        p_cuenta: {
          tipo: 'nueva',
          banco: 'BANCO RLS IDEM',
          tipo_cuenta: 'ahorros',
          numero_cuenta: `IDEM-${idemToken}`,
          cci: idemCci,
          titular_distinto: false,
          beneficiario_nombre: null,
          beneficiario_dni: null,
        },
      });
      const altaIdemComo = (cliente, numero, extra = {}) => cliente.schema('crm')
        .rpc('crear_contrato_con_cuenta_pdf_v2', payloadIdem(numero, extra));
      const altaIdem = (numero, extra = {}) => altaIdemComo(sessions.vend1.client, numero, extra);
      const primera = await positive(
        'idempotencia: el primer alta con clave se crea (regimen anterior → sin_reserva)',
        altaIdem(`RLS-IDEM-${idemToken}-1`, { clave_idempotencia: claveIdem }),
      );
      const idPrimera = typeof primera?.data?.id === 'string' ? primera.data.id : null;
      check(
        idPrimera !== null
          && primera?.data?.pdf?.estado === 'sin_reserva'
          && primera?.data?.pdf?.job_id === null
          && primera?.data?.idempotente === undefined,
        'idempotencia: la respuesta trae id, pdf.estado=sin_reserva, job_id=null y SIN marca idempotente',
        JSON.stringify(primera?.data ?? null).slice(0, 240),
      );
      // El incidente: el analista cree que fallo, CAMBIA el numero y reintenta. La
      // misma clave con otros datos no hace replay ni crea otro: P0409 con el numero.
      await expectExpectedFailure(
        'idempotencia: la MISMA clave con OTRO numero se rechaza nombrando el contrato ya creado (el incidente)',
        altaIdem(`RLS-IDEM-${idemToken}-2`, { clave_idempotencia: claveIdem }),
        ['P0409'],
        new RegExp(`ya creó el contrato RLS-IDEM-${idemToken}-1 con otros datos`),
      );
      const repetida = await positive(
        'idempotencia: el reintento con la MISMA clave y los MISMOS datos devuelve el mismo contrato',
        altaIdem(`RLS-IDEM-${idemToken}-1`, { clave_idempotencia: claveIdem }),
      );
      check(
        repetida?.data?.id === idPrimera
          && repetida?.data?.idempotente === true
          && repetida?.data?.numero_contrato === `RLS-IDEM-${idemToken}-1`
          && repetida?.data?.pdf?.contrato_id === idPrimera,
        'idempotencia: el replay devuelve el MISMO contrato, idempotente=true y el pdf recalculado del mismo contrato',
        JSON.stringify(repetida?.data ?? null).slice(0, 240),
      );
      await expectExpectedFailure(
        'idempotencia: la MISMA clave con OTRO capital tampoco hace replay (P0409)',
        altaIdem(`RLS-IDEM-${idemToken}-1`, { clave_idempotencia: claveIdem, capital: 25000 }),
        ['P0409'],
        /ya creó el contrato .* con otros datos/,
      );
      const contratosIdem = await requireAdmin(
        'contar contratos del ensayo de idempotencia',
        admin.from('contratos').select('id', { count: 'exact', head: true })
          .like('numero_contrato', `RLS-IDEM-${idemToken}-%`),
      );
      check(contratosIdem.count === 1,
        'idempotencia: hay UN solo contrato tras las cuatro llamadas (el duplicado del 05/09 no nace)',
        `count=${contratosIdem.count}`);
      await expectExpectedFailure(
        'idempotencia: una clave que no es uuid se rechaza (22023) sin escribir',
        altaIdem(`RLS-IDEM-${idemToken}-3`, { clave_idempotencia: 'no-es-un-uuid' }),
        ['22023'],
        /clave de idempotencia/i,
      );
      const rechazada = await requireAdmin(
        'verificar que la clave invalida no escribio',
        admin.from('contratos').select('id', { count: 'exact', head: true })
          .eq('numero_contrato', `RLS-IDEM-${idemToken}-3`),
      );
      check(rechazada.count === 0, 'idempotencia: la clave invalida no dejo contrato');
      const otraClave = await positive(
        'idempotencia: otra clave crea otro contrato',
        altaIdem(`RLS-IDEM-${idemToken}-4`, { clave_idempotencia: randomUUID() }),
      );
      check(typeof otraClave?.data?.id === 'string' && otraClave.data.id !== idPrimera,
        'idempotencia: la clave distinta produce un contrato distinto');

      // ── Seguridad del replay (auditor-rls M2, 05/09/2026) ──
      // (a) La memoria es por (actor, clave): OTRO actor con la MISMA clave no
      // encuentra fila, no hereda el contrato de vend1 y crea el SUYO bajo sus gates.
      const ajena = await positive(
        'idempotencia: OTRO actor (gerencia) con la MISMA clave no recibe el alta de vend1: crea la suya',
        altaIdemComo(sessions.gerencia.client, `RLS-IDEM-${idemToken}-5`, { clave_idempotencia: claveIdem }),
      );
      check(typeof ajena?.data?.id === 'string' && ajena.data.id !== idPrimera && ajena?.data?.idempotente === undefined,
        'idempotencia: gerencia no hereda ni el contrato de vend1 ni la marca idempotente',
        JSON.stringify(ajena?.data ?? null).slice(0, 200));
      const ajenaReplay = await positive(
        'idempotencia: gerencia repite SU clave y recupera SU contrato',
        altaIdemComo(sessions.gerencia.client, `RLS-IDEM-${idemToken}-5`, { clave_idempotencia: claveIdem }),
      );
      check(ajenaReplay?.data?.id === ajena?.data?.id && ajenaReplay?.data?.idempotente === true,
        'idempotencia: el replay de gerencia devuelve su contrato (no el de vend1) con idempotente=true');

      // (b) El replay pasa por la autorizacion VIGENTE: vend1 revocado no recupera
      // nada (42501) ni recrea; reactivado, vuelve a recibir el mismo contrato. La
      // revocacion va fuera de banda como en P04 (vend1 posee cartera y el guard, con
      // razon, no deja el UPDATE normal).
      await setVend1State({ portalActive: true, crmActive: false });
      await expectExplicitAuthorizationDenied(
        'idempotencia: vend1 REVOCADO no recupera el alta por replay',
        altaIdem(`RLS-IDEM-${idemToken}-1`, { clave_idempotencia: claveIdem }),
        ['42501'],
      );
      await setVend1State({ portalActive: true, crmActive: true });
      const trasReactivar = await positive(
        'idempotencia: vend1 reactivado vuelve a recuperar el mismo contrato',
        altaIdem(`RLS-IDEM-${idemToken}-1`, { clave_idempotencia: claveIdem }),
      );
      check(trasReactivar?.data?.id === idPrimera && trasReactivar?.data?.idempotente === true,
        'idempotencia: tras reactivar, el replay devuelve el contrato original con idempotente=true');
      const soloUno = await requireAdmin(
        'contar el contrato -1 tras el ciclo revocado/reactivado',
        admin.from('contratos').select('id', { count: 'exact', head: true })
          .eq('numero_contrato', `RLS-IDEM-${idemToken}-1`),
      );
      check(soloUno.count === 1, 'idempotencia: el revocado no recreo el contrato', `count=${soloUno.count}`);

      // (c) La memoria NO es alcanzable por PostgREST para nadie: vive en private,
      // RLS forzada y sin grants (ni service_role).
      const anonIdem = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-idem'));
      for (const [quien, cli] of [
        ['anon', anonIdem], ['vend1', sessions.vend1.client], ['gerencia', sessions.gerencia.client], ['service_role', admin],
      ]) {
        const { error } = await cli.schema('private').from('contrato_altas_idempotentes').select('clave').limit(1);
        check(Boolean(error),
          `idempotencia: ${quien} NO alcanza private.contrato_altas_idempotentes por la API (${error?.code ?? 'sin error'})`);
      }

      // (d) CARRERA REAL: dos envios simultaneos con la misma clave y los mismos datos
      // (doble clic, dos pestañas). El lock advisory por (actor, clave) serializa: uno
      // crea, el otro espera y hace replay; UN solo contrato y el MISMO id para ambos.
      const claveCarrera = randomUUID();
      const [c1, c2] = await Promise.allSettled([
        altaIdem(`RLS-IDEM-${idemToken}-6`, { clave_idempotencia: claveCarrera }),
        altaIdem(`RLS-IDEM-${idemToken}-6`, { clave_idempotencia: claveCarrera }),
      ]);
      const carreraOk = [c1, c2]
        .filter((r) => r.status === 'fulfilled' && !r.value.error)
        .map((r) => r.value.data);
      check(carreraOk.length === 2 && typeof carreraOk[0]?.id === 'string' && carreraOk[0].id === carreraOk[1]?.id,
        'idempotencia: dos envios simultaneos con la misma clave devuelven el MISMO contrato',
        JSON.stringify([c1, c2].map((r) => (r.status === 'fulfilled'
          ? (r.value.error?.code ?? r.value.data?.id)
          : String(r.reason)))).slice(0, 200));
      check(carreraOk.filter((d) => d?.idempotente === true).length === 1,
        'idempotencia: en la carrera exactamente uno de los dos es el replay (idempotente=true)');
      const carreraCount = await requireAdmin(
        'contar contratos de la carrera de idempotencia',
        admin.from('contratos').select('id', { count: 'exact', head: true })
          .eq('numero_contrato', `RLS-IDEM-${idemToken}-6`),
      );
      check(carreraCount.count === 1, 'idempotencia: la carrera dejo UN solo contrato', `count=${carreraCount.count}`);

      // ── El botón «Eliminar contrato» de Gerencia deja el DELETE auditado a nombre de quien
      // lo pulsó (migración 20260905233000). La edge borra por la puerta oficial
      // (contrato_eliminacion_preparar + finalizar) con service_role: aquí, el cliente admin.
      // Sin la migración, auth.uid() es NULL dentro de finalizar y el DELETE de
      // public.contratos queda en audit_log SIN actor (medido en prod el 05/09/2026).
      // La puerta exige es_admin() como actor: vend1 pasa a admin del portal solo para esto
      // (mismo truco que las sondas P04) y vuelve a analista en el finally.
      {
        const actorId = seed.profileIdByKey.vend1;
        const paraBorrar = await positive(
          'eliminación auditada: alta de un contrato que se va a borrar por la puerta',
          altaIdem(`RLS-IDEM-${idemToken}-DEL`, { clave_idempotencia: randomUUID() }),
        );
        const delId = typeof paraBorrar?.data?.id === 'string' ? paraBorrar.data.id : null;
        check(delId !== null, 'eliminación auditada: el contrato a borrar existe');
        await requireAdmin(
          'eliminación auditada: vend1 pasa a admin del portal (la puerta exige es_admin)',
          admin.from('perfiles').update({ rol: 'admin' }).eq('id', actorId),
        );
        try {
          const prep = await requireAdmin(
            'eliminación auditada: preparar como service_role con p_actor_id',
            admin.schema('crm').rpc('contrato_eliminacion_preparar', { p_contrato_id: delId, p_actor_id: actorId }),
          );
          const token = typeof prep?.data?.token === 'string' ? prep.data.token : null;
          check(token !== null, 'eliminación auditada: la puerta autorizó al actor admin (token)');
          const fin = await requireAdmin(
            'eliminación auditada: finalizar como service_role con p_actor_id',
            admin.schema('crm').rpc('contrato_eliminacion_finalizar', { p_contrato_id: delId, p_token: token, p_actor_id: actorId }),
          );
          check(fin?.data?.ok === true, 'eliminación auditada: el contrato se borró por la puerta oficial');
          const queda = await requireAdmin(
            'eliminación auditada: releer el contrato borrado',
            admin.from('contratos').select('id', { count: 'exact', head: true }).eq('id', delId),
          );
          check(queda.count === 0, 'eliminación auditada: no queda el contrato');
          // audit_log está fuera del alcance de la API: se lee por la vía fuera de banda.
          const atribuido = contarFueraDeBanda('audit del DELETE atribuido al actor',
            `select count(*) from public.audit_log where tabla='contratos' and fila_id::text='${delId}' and operacion='DELETE' and usuario_id='${actorId}'`);
          const sinActor = contarFueraDeBanda('audit del DELETE sin actor',
            `select count(*) from public.audit_log where tabla='contratos' and fila_id::text='${delId}' and operacion='DELETE' and usuario_id is null`);
          check(atribuido === 1 && sinActor === 0,
            'eliminación auditada: el DELETE hecho por service_role quedó en audit_log a nombre del actor, no con usuario NULL',
            `atribuido=${atribuido} sinActor=${sinActor}`);

          // ── m3 (migración 20260905234500): el replay NO devuelve un contrato con eliminación PREPARADA ──

          // Gerencia pulsó «Eliminar» (preparar) y la edge aún no finalizó: el replay del alta con la

          // misma clave debe responder 55000 «en proceso de eliminación» (como el alta nueva), sin

          // devolver el contrato como «alta recuperada» y sin crear otro; finalizado el borrado, el replay

          // vuelve a ser lápida P0409. Con el texto vivo (v2.1) el replay devolvía el contrato: falso «ok».

          const claveM3 = randomUUID();

          const altaM3 = await positive(

            'm3: alta con clave K de un contrato que Gerencia va a poner en eliminación',

            altaIdem(`RLS-IDEM-${idemToken}-M3`, { clave_idempotencia: claveM3 }),

          );

          const m3Id = typeof altaM3?.data?.id === 'string' ? altaM3.data.id : null;

          const prepM3 = await requireAdmin(

            'm3: preparar la eliminación como admin (queda PENDIENTE, sin finalizar)',

            admin.schema('crm').rpc('contrato_eliminacion_preparar', { p_contrato_id: m3Id, p_actor_id: actorId }),

          );

          const tokenM3 = typeof prepM3?.data?.token === 'string' ? prepM3.data.token : null;

          await expectExpectedFailure(

            'm3: el replay con la MISMA clave responde 55000 «en proceso de eliminación», no «alta recuperada»',

            altaIdem(`RLS-IDEM-${idemToken}-M3`, { clave_idempotencia: claveM3 }),

            ['55000'],

            /en proceso de eliminaci/i,

          );

          await expectExpectedFailure(

            'm3: misma clave con OTRO número tampoco crea nada mientras hay eliminación pendiente (55000 antes que la huella)',

            altaIdem(`RLS-IDEM-${idemToken}-M3B`, { clave_idempotencia: claveM3 }),

            ['55000'],

            /en proceso de eliminaci/i,

          );

          const sigueM3 = await requireAdmin(

            'm3: releer el contrato en eliminación',

            admin.from('contratos').select('id', { count: 'exact', head: true }).like('numero_contrato', `RLS-IDEM-${idemToken}-M3%`),

          );

          check(sigueM3.count === 1, 'm3: el contrato sigue (uno solo); el replay no lo tocó ni creó otro', `count=${sigueM3.count}`);

          const finM3 = await requireAdmin(

            'm3: Gerencia finaliza el borrado',

            admin.schema('crm').rpc('contrato_eliminacion_finalizar', { p_contrato_id: m3Id, p_token: tokenM3, p_actor_id: actorId }),

          );

          check(finM3?.data?.ok === true, 'm3: el borrado finalizó');

          await expectExpectedFailure(

            'm3: tras el borrado, el replay vuelve a ser lápida P0409 «fue eliminado después» (no recrea)',

            altaIdem(`RLS-IDEM-${idemToken}-M3`, { clave_idempotencia: claveM3 }),

            ['P0409'],

            /fue eliminado después/,

          );

          const nadaM3 = await requireAdmin(

            'm3: contar tras la lápida',

            admin.from('contratos').select('id', { count: 'exact', head: true }).like('numero_contrato', `RLS-IDEM-${idemToken}-M3%`),

          );

          check(nadaM3.count === 0, 'm3: no queda ni se recreó ningún contrato M3', `count=${nadaM3.count}`);


          // Los DENEGADOS de la puerta también en el gate (auditor-rls): la autorización sigue siendo
          // token + solicitado_por = p_actor_id, y ni authenticated ni anon pueden ejecutarla.
          const segundo = await positive(
            'eliminación auditada (denegados): alta de un segundo contrato',
            altaIdem(`RLS-IDEM-${idemToken}-DEL2`, { clave_idempotencia: randomUUID() }),
          );
          const del2 = typeof segundo?.data?.id === 'string' ? segundo.data.id : null;
          await expectExplicitAuthorizationDenied(
            'eliminación auditada (denegados): un actor NO admin (gerencia) no puede preparar la eliminación',
            admin.schema('crm').rpc('contrato_eliminacion_preparar', { p_contrato_id: del2, p_actor_id: seed.profileIdByKey.gerencia }),
            ['42501'],
          );
          const prep2 = await requireAdmin(
            'eliminación auditada (denegados): preparar el segundo contrato como el actor admin',
            admin.schema('crm').rpc('contrato_eliminacion_preparar', { p_contrato_id: del2, p_actor_id: actorId }),
          );
          const token2 = typeof prep2?.data?.token === 'string' ? prep2.data.token : null;
          await expectExpectedFailure(
            'eliminación auditada (denegados): token equivocado → P0002',
            admin.schema('crm').rpc('contrato_eliminacion_finalizar', { p_contrato_id: del2, p_token: '00000000-0000-0000-0000-000000000000', p_actor_id: actorId }),
            ['P0002'],
            /no existe o venció/i,
          );
          await expectExpectedFailure(
            'eliminación auditada (denegados): otro actor con el token correcto → P0002 (el mutex es de quien preparó)',
            admin.schema('crm').rpc('contrato_eliminacion_finalizar', { p_contrato_id: del2, p_token: token2, p_actor_id: seed.profileIdByKey.gerencia }),
            ['P0002'],
            /no existe o venció/i,
          );
          for (const [quien, cli] of [['vend1', sessions.vend1.client], ['gerencia', sessions.gerencia.client], ['anon', anonIdem]]) {
            await expectExplicitAuthorizationDenied(
              `eliminación auditada (denegados): ${quien} no ejecuta contrato_eliminacion_finalizar (sin EXECUTE)`,
              cli.schema('crm').rpc('contrato_eliminacion_finalizar', { p_contrato_id: del2, p_token: token2, p_actor_id: actorId }),
              ['42501', 'PGRST202'],
            );
          }
          const vivo2 = await requireAdmin(
            'eliminación auditada (denegados): releer el segundo contrato',
            admin.from('contratos').select('id', { count: 'exact', head: true }).eq('id', del2),
          );
          check(vivo2.count === 1, 'eliminación auditada (denegados): tras los rechazos el contrato sigue vivo');
          const fin2 = await requireAdmin(
            'eliminación auditada (denegados): limpieza — finalizar con el token y el actor correctos',
            admin.schema('crm').rpc('contrato_eliminacion_finalizar', { p_contrato_id: del2, p_token: token2, p_actor_id: actorId }),
          );
          check(fin2?.data?.ok === true, 'eliminación auditada (denegados): con token y actor correctos sí se borra');
        } finally {
          await requireAdmin(
            'eliminación auditada: vend1 vuelve a analista',
            admin.from('perfiles').update({ rol: 'analista' }).eq('id', actorId),
          );
        }
      }
    }

    // El cronograma deliberadamente invalido evita una mutacion aun si hubiera
    // una regresion de autorizacion; la asercion solo acepta un error de scope.
    for (const key of ['vend3', 'directorio']) {
      await expectExplicitAuthorizationDenied(
        `${key} no corrige el contrato bancario por el wrapper (via pdf_v3)`,
        // F7.1: la puerta interna quedo cerrada; el scope vivo se prueba en pdf_v3.
        sessions[key].client.schema('crm').rpc('actualizar_contrato_con_cuenta_pdf_v3', {
          p_id: seed.contract.id,
          p_contrato: duplicateContract,
          p_cronograma: { invalido: true },
        }),
      );
    }

    for (const key of ['vend1', 'directorio']) {
      await expectExplicitAuthorizationDenied(
        `${key} no usa el resolver de cuentas reservado al administrador`,
        sessions[key].client.schema('crm').rpc('cuentas_pago_contratos_fn', {
          p_contrato_ids: [seed.contract.id],
        }),
      );
    }
  } finally {
    // Devolver la bandera de identidad al valor que tenia al entrar (otra sesion
    // puede estar contando con ella encendida).
    try {
      fijarResolverEnPuertas(resolverEnPuertasOriginal, `restaurar resolver_en_puertas=${resolverEnPuertasOriginal}`);
    } catch (errorFlag) {
      console.warn(`  ⚠ no se pudo restaurar resolver_en_puertas: ${errorFlag?.message ?? errorFlag}`);
    }
    if (directorMembershipFabricated) {
      await requireAdmin(
        'retirar la membresia CRM fabricada para directorio tras sondas bancarias',
        admin.schema('crm').rpc('purgar_membresia_crm', {
          p_perfil_id: directorProfileId,
          p_motivo: 'Gate test-rls (finally): retirar la membresia CRM fabricada para las sondas de banca P04',
        }),
      );
    }
    if (directorDeactivated) {
      await requireAdmin(
        'reactivar el perfil portal de directorio tras sondas bancarias',
        admin.from('perfiles').update({ activo: true }).eq('id', directorProfileId),
      );
    }
    if (directorRoleChanged && originalDirectorRole) {
      await requireAdmin(
        'restaurar rol global de directorio tras sondas bancarias',
        admin.from('perfiles')
          .update({ rol: originalDirectorRole })
          .eq('id', directorProfileId),
      );
    }
    for (const original of originalActors) {
      if (!original.rol) continue;
      await requireAdmin(
        `restaurar perfil portal de ${original.id} tras sondas bancarias`,
        admin.from('perfiles')
          .update({ activo: original.activo, rol: original.rol })
          .eq('id', original.id),
      );
      await requireAdmin(
        `restaurar membresia CRM de ${original.id} tras sondas bancarias`,
        admin.schema('crm').from('equipo')
          .update({ activo: original.crmActivo })
          .eq('perfil_id', original.id),
      );
    }
  }
}

// Aquí se cubre la matriz autenticada/anon, el contrato de lectura vigente y
// —desde 2026-08-10— el ciclo de publicación completo. Se evitó durante meses
// porque la historia de metas es append-only y cada corrida siembra una
// revisión; el precio de esa prudencia fue que publicar metas estuvo roto en
// producción sin que nada lo señalara. Ahora se publica de verdad, leyendo la
// revisión vigente para que el caso siga siendo re-ejecutable sobre la misma
// base. Las dimensiones, la auditoría y los casos que exigen fabricar un roster
// degradado (analista sin supervisor, supervisor de baja) siguen en PostgreSQL
// desechable vía `test-metas-versionadas.sql`.
const PERIODO_METAS_GATE = '2099-11-01';

function idsMetas(configuracion) {
  return (configuracion?.vendedores ?? [])
    .map((vendedor) => vendedor.vendedor_id)
    .sort();
}

function dimensionesMetasValidas(configuracion) {
  const esperadas = new Set([
    'nuevo:PEN', 'nuevo:USD',
    'renovacion:PEN', 'renovacion:USD',
    'upgrade:PEN', 'upgrade:USD',
  ]);
  return (configuracion?.vendedores ?? []).every((vendedor) => {
    const recibidas = new Set(
      (vendedor.detalles ?? []).map((detalle) => `${detalle.categoria}:${detalle.moneda}`),
    );
    return recibidas.size === esperadas.size
      && [...esperadas].every((dimension) => recibidas.has(dimension));
  });
}

// — Ventana de actividades del ámbito (F0 del plan de escalabilidad) ---------
// 20260808163638 recorta actividades_del_ambito_fn a 365 días + limit 10000.
// Se siembra con service_role una actividad VIEJA (400 días) sobre un lead de
// vend1 y se asevera que NO viaja ni para el dueño ni para los lectores
// globales, mientras la actividad reciente del MISMO lead sí sigue viajando
// (prueba que el recorte es la ventana y no el scoping). La fila vieja queda
// en el branch a propósito: el log es INSERT-only y el branch se descarta
// (mismo criterio que las actividades transitorias de otros tests).
async function testVentanaActividades(sessions, seed) {
  console.log('\n— Ventana de actividades: fuera de 365 dias no viaja —');

  const juanFixture = LEAD_BY_KEY.juan;
  const juanLead = seed.leadByName.get(juanFixture.name);
  const actividadViejaId = randomUUID();
  const creadoViejo = new Date(Date.now() - 400 * 24 * 60 * 60 * 1000).toISOString();
  await requireAdmin(
    'sembrar actividad fuera de la ventana de 365 dias',
    admin.schema('crm').from('actividades').insert({
      id: actividadViejaId,
      lead_id: juanLead.id,
      tipo: 'nota',
      detalle: 'gate ventana: actividad fuera de rango temporal',
      creado_por: seed.profileIdByKey[juanFixture.sellerKey],
      creado_en: creadoViejo,
    }),
  );

  for (const key of ['vend1', 'sup1', 'gerencia', 'directorio']) {
    const respuesta = await positive(
      `${key} lee el timeline del ambito con la ventana aplicada`,
      sessions[key].client.schema('crm').rpc('actividades_del_ambito_fn'),
    );
    if (!respuesta) continue;
    const ids = new Set((respuesta.data ?? []).map((fila) => fila.id));
    check(!ids.has(actividadViejaId),
      `${key} no recibe la actividad fuera de la ventana de 365 dias`);
    check(ids.has(juanFixture.activityId),
      `${key} sigue recibiendo la actividad reciente del mismo lead`);
  }

  // Espejo de RLS de la RPC (definer, salta las policies): primera vez que la
  // función queda versionada → se clava su WHERE con sondas NEGATIVAS. vend3
  // (subárbol de sup2) no ve nada de juan (vend1); el coordinador es
  // off-roster (ámbito ∅ por diseño); un miembro desactivado pierde el ámbito
  // entero (rol_crm/vendedor_ids_visibles solo miran equipo.activo).
  const vend3 = await positive(
    'vend3 llama el timeline del ambito sin cruzar de subarbol',
    sessions.vend3.client.schema('crm').rpc('actividades_del_ambito_fn'),
  );
  if (vend3) {
    const ids = new Set((vend3.data ?? []).map((fila) => fila.id));
    check(!ids.has(juanFixture.activityId),
      'vend3 no recibe actividades del subarbol de sup1');
    check(!ids.has(actividadViejaId),
      'vend3 tampoco recibe la actividad vieja ajena');
  }
  for (const key of ['coordinador', 'vendInactive']) {
    const respuesta = await positive(
      `${key} llama el timeline del ambito`,
      sessions[key].client.schema('crm').rpc('actividades_del_ambito_fn'),
    );
    if (!respuesta) continue;
    check((respuesta.data ?? []).length === 0,
      `${key} recibe el timeline vacio (ambito nulo por diseno)`);
  }
}

async function testMetasVersionadas(sessions, seed) {
  console.log('\n— Metas versionadas: lectura scopeada y escritura solo Gerencia —');

  const gerencia = await positive(
    'gerencia lee la configuracion completa de metas',
    sessions.gerencia.client.schema('crm').rpc('configuracion_metas_fn', {
      p_periodo: PERIODO_METAS_GATE,
    }),
  );
  const configGerencia = gerencia?.data;
  if (gerencia) {
    check(configGerencia?.version === 1
      && Number.isInteger(configGerencia?.revision)
      && configGerencia.revision >= 0,
    'la configuracion de metas declara version y revision validas',
    JSON.stringify(configGerencia));
    check(configGerencia?.puede_editar === true,
      'solo Gerencia recibe capacidad de edicion');
    check(dimensionesMetasValidas(configGerencia),
      'cada analista visible conserva las seis dimensiones categoria x moneda');

    const ids = new Set(idsMetas(configGerencia));
    for (const key of ['vend1', 'vend2', 'vend3', 'vend4', 'vendNested']) {
      check(ids.has(seed.profileIdByKey[key]),
        `gerencia ve al analista activo ${key}`);
    }
    check(!ids.has(seed.profileIdByKey.vendInactive),
      'el roster de metas excluye al analista inactivo');
  }

  const casos = [
    ['vend1', ['vend1'], ['vend2', 'vend3']],
    ['sup1Nested', ['vendNested'], ['vend1', 'vend3']],
    ['sup1', ['vend1', 'vend2', 'vendNested'], ['vend3', 'vend4']],
    ['sup2', ['vend3', 'vend4'], ['vend1', 'vendNested']],
  ];
  for (const [actor, incluidos, excluidos] of casos) {
    const respuesta = await positive(
      `${actor} lee solo su roster de metas`,
      sessions[actor].client.schema('crm').rpc('configuracion_metas_fn', {
        p_periodo: PERIODO_METAS_GATE,
      }),
    );
    if (!respuesta) continue;
    const ids = new Set(idsMetas(respuesta.data));
    check(respuesta.data?.puede_editar === false,
      `${actor} recibe metas en solo lectura`);
    for (const key of incluidos) {
      check(ids.has(seed.profileIdByKey[key]), `${actor} incluye ${key}`);
    }
    for (const key of excluidos) {
      check(!ids.has(seed.profileIdByKey[key]), `${actor} excluye ${key}`);
    }
  }

  const coordinador = await positive(
    'coordinador obtiene una configuracion sin roster comercial',
    sessions.coordinador.client.schema('crm').rpc('configuracion_metas_fn', {
      p_periodo: PERIODO_METAS_GATE,
    }),
  );
  if (coordinador) {
    check(coordinador.data?.puede_editar === false
      && idsMetas(coordinador.data).length === 0,
    'coordinador no obtiene metas de analistas');
  }

  const directorio = await positive(
    'directorio audita la configuracion completa de metas',
    sessions.directorio.client.schema('crm').rpc('configuracion_metas_fn', {
      p_periodo: PERIODO_METAS_GATE,
    }),
  );
  if (directorio && gerencia) {
    check(directorio.data?.puede_editar === false,
      'directorio recibe metas en solo lectura');
    check(JSON.stringify(idsMetas(directorio.data)) === JSON.stringify(idsMetas(configGerencia)),
      'directorio y Gerencia ven el mismo roster global');
  }

  // `sin_supervisor` es la contracara del roster: quien no tiene supervisor
  // activo no cabe en crm.metas_vendedor (supervisor_id NOT NULL) y por eso el
  // servidor no le pide meta. El caso con un huérfano VIVO se ejercita en
  // `test-metas-versionadas.sql` (M15..M18), que sí puede fabricarlo; aquí se
  // fija el contrato y, sobre todo, quién tiene derecho a esa lista.
  const excluidosDe = (configuracion) => (configuracion?.sin_supervisor ?? []);
  if (gerencia) {
    const excluidos = excluidosDe(configGerencia);
    check(Array.isArray(configGerencia?.sin_supervisor),
      'la configuracion de metas siempre declara la lista de excluidos');
    check(excluidos.every((fila) => typeof fila?.vendedor_id === 'string'
      && typeof fila?.nombre === 'string' && fila.nombre.length > 0),
    'cada excluido llega con id y nombre utilizables');
    const enRoster = new Set(idsMetas(configGerencia));
    check(excluidos.every((fila) => !enRoster.has(fila.vendedor_id)),
      'ningun excluido aparece tambien en el roster editable');
  }
  if (directorio && gerencia) {
    check(JSON.stringify(excluidosDe(directorio.data).map((f) => f.vendedor_id).sort())
      === JSON.stringify(excluidosDe(configGerencia).map((f) => f.vendedor_id).sort()),
    'directorio, como lector global, ve los mismos excluidos que Gerencia');
  }
  for (const actor of ['vend1', 'sup1', 'sup2', 'coordinador']) {
    const respuesta = await positive(
      `${actor} lee metas sin enumerar excluidos`,
      sessions[actor].client.schema('crm').rpc('configuracion_metas_fn', {
        p_periodo: PERIODO_METAS_GATE,
      }),
    );
    if (!respuesta) continue;
    check(excluidosDe(respuesta.data).length === 0,
      `${actor} no enumera analistas fuera de su ambito`);
  }

  for (const key of ['vend1', 'sup1', 'coordinador', 'directorio']) {
    await expectBlockedMutation(
      `${key} no publica metas`,
      sessions[key].client.schema('crm').rpc('publicar_metas_vendedores', {
        p_periodo: PERIODO_METAS_GATE,
        p_expected_revision: 0,
        p_metas: {},
      }),
      ['42501'],
    );
  }

  await expectBlockedMutation(
    'Gerencia no puede saltarse la validacion del periodo',
    sessions.gerencia.client.schema('crm').rpc('publicar_metas_vendedores', {
      p_periodo: '2099-11-15',
      p_expected_revision: 0,
      p_metas: {},
    }),
    ['22023'],
  );
  await expectBlockedMutation(
    'Gerencia no inserta directo en la historia de metas',
    sessions.gerencia.client.schema('crm').from('meta_periodos').insert({
      periodo: PERIODO_METAS_GATE,
      revision: 999,
    }).select('id'),
    ['42501'],
  );
  await expectExplicitAuthorizationDenied(
    'el archivo legacy de metas no pertenece al Data API autenticado',
    sessions.gerencia.client.schema('crm').from('objetivos_legacy_archivo')
      .select('id').limit(1),
    ['42501', 'PGRST205'],
  );
  await expectExplicitAuthorizationDenied(
    'la RPC legacy fijar_objetivos ya no existe',
    sessions.gerencia.client.schema('crm').rpc('fijar_objetivos', {
      p_periodo: PERIODO_METAS_GATE,
      p_objetivos: {},
    }),
    ['PGRST202'],
  );

  // ── El ciclo completo: publicar de verdad ────────────────────────────────
  // Hasta 2026-08-10 esta matriz solo tenía casos NEGATIVOS de publicación, y
  // por eso el deadlock del roster vivió desde que existe la pantalla: el gate
  // daba 732/732 mientras publicar metas era imposible en producción (el editor
  // ofrecía N y el servidor exigía N+1). Aquí se ejercita lo único que lo
  // demuestra: que el roster que el editor OFRECE es exactamente el que el
  // publicador ACEPTA. Es re-ejecutable —la revisión esperada se lee, no se
  // asume— porque el gate corre más de una vez sobre la misma base.
  if (configGerencia?.vendedores?.length) {
    const revisionPrevia = configGerencia.revision;
    const capitalTestigo = 12_345;
    const metasDelRoster = Object.fromEntries(configGerencia.vendedores.map((vendedor) => [
      vendedor.vendedor_id,
      {
        conversion_objetivo: 0,
        detalles: vendedor.detalles.map((detalle) => ({
          ...detalle,
          capital_objetivo: detalle.categoria === 'nuevo' && detalle.moneda === 'PEN'
            ? capitalTestigo
            : 0,
          contratos_objetivo: 0,
        })),
      },
    ]));

    const publicacion = await positive(
      'gerencia publica el roster exacto que el editor le ofrece',
      sessions.gerencia.client.schema('crm').rpc('publicar_metas_vendedores', {
        p_periodo: PERIODO_METAS_GATE,
        p_expected_revision: revisionPrevia,
        p_metas: metasDelRoster,
      }),
    );
    check(publicacion?.data?.[0]?.revision === revisionPrevia + 1,
      'la publicacion crea la revision siguiente',
      `esperada ${revisionPrevia + 1}, recibida ${JSON.stringify(publicacion?.data?.[0]?.revision)}`);

    // Ida y vuelta: lo publicado es lo que el editor vuelve a leer.
    const relectura = await positive(
      'el editor relee la revision recien publicada',
      sessions.gerencia.client.schema('crm').rpc('configuracion_metas_fn', {
        p_periodo: PERIODO_METAS_GATE,
      }),
    );
    if (relectura) {
      check(relectura.data?.revision === revisionPrevia + 1,
        'el editor ve la revision nueva');
      const nuevoPen = (relectura.data?.vendedores ?? []).flatMap((vendedor) => vendedor.detalles)
        .filter((detalle) => detalle.categoria === 'nuevo' && detalle.moneda === 'PEN');
      check(nuevoPen.length > 0 && nuevoPen.every((d) => Number(d.capital_objetivo) === capitalTestigo),
        'el capital publicado vuelve intacto en la relectura',
        JSON.stringify(nuevoPen.slice(0, 3)));
    }

    const revisionVigente = revisionPrevia + 1;
    const [primerVendedor] = Object.keys(metasDelRoster);
    const rosterIncompleto = { ...metasDelRoster };
    delete rosterIncompleto[primerVendedor];
    await expectBlockedMutation(
      'Gerencia no publica un roster incompleto',
      sessions.gerencia.client.schema('crm').rpc('publicar_metas_vendedores', {
        p_periodo: PERIODO_METAS_GATE,
        p_expected_revision: revisionVigente,
        p_metas: rosterIncompleto,
      }),
      ['22023'],
    );
    await expectBlockedMutation(
      'Gerencia no cuela una meta para alguien fuera del roster',
      sessions.gerencia.client.schema('crm').rpc('publicar_metas_vendedores', {
        p_periodo: PERIODO_METAS_GATE,
        p_expected_revision: revisionVigente,
        p_metas: {
          ...metasDelRoster,
          [seed.profileIdByKey.coordinador]: metasDelRoster[primerVendedor],
        },
      }),
      ['22023'],
    );
    // El CAS (expected_revision obsoleta → 40001) NO se prueba aquí: ya lo hace
    // M05 de `test-metas-versionadas.sql`, que es su sitio. Se intentó igual y
    // resultó ser una cuarta llamada de red que se encola tras el advisory lock
    // del periodo y se pasa del timeout del gateway en una instancia de branch
    // —medido con pg_stat_activity: `wait_event = advisory`—, mientras la misma
    // llamada por SQL directo responde 40001 en 31 ms. Duplicar cobertura que ya
    // existe a cambio de un caso intermitente es un mal negocio: un gate que
    // falla por la red enseña a ignorar los fallos del gate.
  }
}

// ── F1 tanda 1: métricas agregadas en el servidor ─────────────────────────────
// Las 4 RPC (resumen_cartera_fn / cola_accion_fn / metricas_vendedores_fn /
// series_comerciales_fn) replican cálculos del navegador con el predicado
// espejo de leads_select. El oráculo aquí es AUTOCONSISTENTE: lo que cada
// sesión puede SELECTear de crm.leads por RLS (aplicando en JS la ventana de
// convertidos de 45 días) debe cuadrar con los agregados que la RPC le
// devuelve — así la matriz no depende de residuos transitorios de suites
// anteriores. La aritmética fina (cascada de buckets, series, 45d exactos)
// vive en el oráculo SQL desechable test-metricas-servidor.sql
// (token METRICAS_SERVIDOR_TX_OK).
const ETAPAS_ABIERTAS_F1 = new Set(['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']);
const VENTANA_CONVERTIDOS_MS_F1 = 45 * 24 * 60 * 60 * 1000;
const LIMA_OFFSET_MS_F1 = 5 * 3600 * 1000; // UTC-5 fijo (Perú no tiene DST)

/** Primer instante (ms UTC) del mes inicial de una ventana de 6 meses en Lima
 *  — espejo del v_ini de series_comerciales_fn(6). */
function inicioVentanaSeisMesesLimaF1() {
  const lima = new Date(Date.now() - LIMA_OFFSET_MS_F1);
  return Date.UTC(lima.getUTCFullYear(), lima.getUTCMonth() - 5, 1) + LIMA_OFFSET_MS_F1;
}

async function testMetricasServidor(sessions, seed) {
  console.log('\n— Metricas agregadas en el servidor (F1 tandas 1+2) —');

  for (const key of ['vend1', 'sup1', 'sup2', 'gerencia', 'directorio']) {
    const client = sessions[key].client;
    const visibles = await positive(
      `${key} lista su ambito RLS como oraculo de las metricas`,
      client.schema('crm').from('leads')
        .select('id, etapa, moneda, monto_estimado, vendedor_id, convertido_en, activo')
        .limit(2000),
    );
    if (!visibles) continue;
    const corte = Date.now() - VENTANA_CONVERTIDOS_MS_F1;
    // Desde 20260902040000 NADIE ve soft-borrados por RLS, lector global
    // incluido; las RPC solo sirven ámbito vivo. El oráculo aplica el mismo
    // recorte (activo + ventana) — el filtro de `activo` sobra desde entonces,
    // pero se deja porque también recorta la ventana de convertidos.
    const filas = (visibles.data ?? []).filter((l) => l.activo === true
      && (l.etapa !== 'convertido'
        || (l.convertido_en && Date.parse(l.convertido_en) >= corte)));
    const abiertos = filas.filter((l) => ETAPAS_ABIERTAS_F1.has(l.etapa));
    const asignados = abiertos.filter((l) => l.vendedor_id != null);
    const parkeados = abiertos.filter((l) => l.vendedor_id == null);
    const capitalPen = asignados
      .filter((l) => l.moneda !== 'USD')
      .reduce((suma, l) => suma + Number(l.monto_estimado ?? 0), 0);
    const capitalUsd = asignados
      .filter((l) => l.moneda === 'USD')
      .reduce((suma, l) => suma + Number(l.monto_estimado ?? 0), 0);

    const resumen = await positive(
      `${key} obtiene resumen_cartera_fn`,
      client.schema('crm').rpc('resumen_cartera_fn'),
    );
    if (resumen) {
      const t = resumen.data?.totales ?? {};
      check(resumen.data?.version === 1 && resumen.data?.ventana_convertidos_dias === 45,
        `${key} recibe el contrato v1 con la ventana de 45 dias`);
      check(t.vivos === filas.length && t.abiertos === abiertos.length
        && t.asignados === asignados.length && t.parkeados === parkeados.length,
        `${key}: los totales del resumen cuadran con su propio SELECT por RLS`,
        JSON.stringify({ rpc: t, esperado: { vivos: filas.length, abiertos: abiertos.length, asignados: asignados.length, parkeados: parkeados.length } }));
      check(Number(resumen.data?.capital?.asignado?.pen ?? -1) === capitalPen
        && Number(resumen.data?.capital?.asignado?.usd ?? -1) === capitalUsd,
        `${key}: el capital asignado por moneda cuadra (PEN y USD jamas sumados)`);
    }

    const cola = await positive(
      `${key} obtiene cola_accion_fn`,
      client.schema('crm').rpc('cola_accion_fn', { p_limite: 100 }),
    );
    if (cola) {
      const items = cola.data?.items ?? [];
      const idsVisibles = new Set(filas.map((l) => l.id));
      check(items.every((i) => idsVisibles.has(i.lead_id)),
        `${key}: cada item de la cola es un lead que su RLS ya le muestra`);
      const porRepartir = Number(cola.data?.resumen?.por_bucket?.por_repartir ?? 0);
      check(porRepartir === parkeados.length,
        `${key}: por_repartir cuadra con sus parkeados visibles (${parkeados.length})`);
    }
  }

  // vend1 JAMAS recibe por_repartir ni items ajenos (negativa dura del plan).
  const colaVend1 = await positive(
    'vend1 vuelve a pedir su cola para las negativas',
    sessions.vend1.client.schema('crm').rpc('cola_accion_fn', { p_limite: 100 }),
  );
  if (colaVend1) {
    const items = colaVend1.data?.items ?? [];
    check(items.every((i) => i.bucket !== 'por_repartir'),
      'vend1 jamas recibe un item por_repartir');
    check(items.every((i) => i.lead?.vendedor_id === seed.profileIdByKey.vend1),
      'vend1 solo recibe items de su propia cartera');
  }

  // metricas_vendedores_fn: recorte lateral del roster + comparativa.
  const mvSup2 = await positive(
    'sup2 lee metricas de analistas sin cruzar de subarbol',
    sessions.sup2.client.schema('crm').rpc('metricas_vendedores_fn'),
  );
  if (mvSup2) {
    const ids = new Set((mvSup2.data?.vendedores ?? []).map((v) => v.vendedor_id));
    check(ids.has(seed.profileIdByKey.vend3), 'sup2 incluye a vend3');
    check(ids.has(seed.profileIdByKey.vendInactive),
      'sup2 incluye a su analista desactivado (gerencia reasigna esa cartera)');
    check(!ids.has(seed.profileIdByKey.vend1), 'sup2 excluye a vend1 (subarbol ajeno)');
    const equipos = new Set((mvSup2.data?.equipos ?? []).map((e) => e.supervisor_id));
    check(equipos.has(seed.profileIdByKey.sup2) && !equipos.has(seed.profileIdByKey.sup1),
      'sup2 solo recibe la comparativa de su propio equipo');
  }
  const mvVend1 = await positive(
    'vend1 lee metricas de analistas',
    sessions.vend1.client.schema('crm').rpc('metricas_vendedores_fn'),
  );
  if (mvVend1) {
    check((mvVend1.data?.vendedores ?? []).length === 1
      && (mvVend1.data?.equipos ?? []).length === 0,
      'vend1 recibe solo su propia fila y cero equipos');
  }
  const mvGerencia = await positive(
    'gerencia lee metricas de analistas del roster completo',
    sessions.gerencia.client.schema('crm').rpc('metricas_vendedores_fn'),
  );
  if (mvGerencia) {
    const filaInactivo = (mvGerencia.data?.vendedores ?? [])
      .find((v) => v.vendedor_id === seed.profileIdByKey.vendInactive);
    check(filaInactivo?.activo === false,
      'gerencia ve la fila del analista desactivado marcada activo=false');
  }

  // series_comerciales_fn v2 (F6.c): shape de 7 arrays paralelos. La clave de
  // cohorte lleva su apellido y la conversion OFICIAL del nucleo viaja aparte
  // (admite null en los meses sin ledger: un cero mentiria).
  const series = await positive(
    'gerencia obtiene series_comerciales_fn',
    sessions.gerencia.client.schema('crm').rpc('series_comerciales_fn', { p_meses: 6 }),
  );
  if (series) {
    const d = series.data ?? {};
    check(d.version === 2, 'series declara version 2');
    check(!('conversion_pct' in d),
      'la clave sin apellido ya no existe (F6.c)');
    check((d.meses ?? []).length === 6
      && ['nuevos', 'cierres', 'cohorte_clientes', 'capital_pen', 'capital_usd', 'conversion_cohorte_pct']
        .every((k) => (d[k] ?? []).length === 6),
      'gerencia recibe 6 arrays paralelos de 6 meses');
    check(Array.isArray(d.conversion_mensual_pct) && d.conversion_mensual_pct.length === 6,
      'la serie mensual del nucleo viaja con 6 posiciones (null permitido)');
    // Paridad con el OFICIAL: el ultimo mes de la serie == conversion_mensual_fn.
    const mesActual = (d.meses ?? [])[5];
    const oficial = await positive(
      'gerencia lee la conversion oficial del mes para la paridad de series',
      sessions.gerencia.client.schema('crm').rpc('conversion_mensual_fn', { p_periodo: `${mesActual}-01` }),
    );
    if (oficial) {
      const pctOficial = oficial.data?.total?.conversion_pct;
      const pctSerie = d.conversion_mensual_pct?.[5];
      check(pctSerie == null ? pctOficial == null || pctOficial === 0
        : Math.round(Number(pctSerie) * 10) === Math.round(Number(pctOficial) * 10),
      `la serie mensual del nucleo cuadra con la oficial (serie=${pctSerie} oficial=${pctOficial})`);
    }
  }

  // Tanda 2 (20260809144920): la rama de reparto da al coordinador los
  // AGREGADOS de TODOS los sin-dueño (cola global + bandejas) en resumen y
  // series — y NADA más. Oraculo: los sin-dueño que ve gerencia por RLS,
  // leidos inmediatamente antes (la suite es secuencial: nada muta entre
  // ambas lecturas).
  const parkGerencia = await positive(
    'gerencia lista los sin-dueno como oraculo del coordinador',
    sessions.gerencia.client.schema('crm').from('leads')
      .select('id, etapa, moneda, monto_estimado, creado_en, activo')
      .is('vendedor_id', null)
      .eq('activo', true)
      .limit(2000),
  );
  const sinDueno = parkGerencia ? (parkGerencia.data ?? []) : null;
  const coordResumen = await positive(
    'coordinador llama resumen_cartera_fn',
    sessions.coordinador.client.schema('crm').rpc('resumen_cartera_fn'),
  );
  if (coordResumen && sinDueno) {
    const abiertosSinDueno = sinDueno.filter((l) => ETAPAS_ABIERTAS_F1.has(l.etapa));
    const parkPen = abiertosSinDueno
      .filter((l) => l.moneda !== 'USD')
      .reduce((suma, l) => suma + Number(l.monto_estimado ?? 0), 0);
    const t = coordResumen.data?.totales ?? {};
    check(t.parkeados === abiertosSinDueno.length && t.asignados === 0,
      'coordinador ve exactamente los parkeados (rama de reparto) y cero asignados',
      JSON.stringify({ rpc: t, esperado: abiertosSinDueno.length }));
    check(Number(coordResumen.data?.capital?.parkeado?.pen ?? -1) === parkPen
      && Number(coordResumen.data?.capital?.asignado?.pen ?? -1) === 0,
      'coordinador: el capital parkeado cuadra y el asignado sigue en cero');
  }
  const coordCola = await positive(
    'coordinador llama cola_accion_fn',
    sessions.coordinador.client.schema('crm').rpc('cola_accion_fn', { p_limite: 100 }),
  );
  if (coordCola) {
    check((coordCola.data?.items ?? []).length === 0
      && (coordCola.data?.estancados?.items ?? []).length === 0,
      'coordinador recibe la cola vacia (ni siquiera por_repartir)');
  }
  const coordMv = await positive(
    'coordinador llama metricas_vendedores_fn',
    sessions.coordinador.client.schema('crm').rpc('metricas_vendedores_fn'),
  );
  if (coordMv) {
    check((coordMv.data?.vendedores ?? []).length === 0
      && (coordMv.data?.equipos ?? []).length === 0,
      'coordinador recibe roster y comparativa vacios');
  }
  const coordSeries = await positive(
    'coordinador llama series_comerciales_fn',
    sessions.coordinador.client.schema('crm').rpc('series_comerciales_fn', { p_meses: 6 }),
  );
  if (coordSeries && sinDueno) {
    const iniVentana = inicioVentanaSeisMesesLimaF1();
    const nuevosEsperados = sinDueno
      .filter((l) => Date.parse(l.creado_en) >= iniVentana).length;
    const d = coordSeries.data ?? {};
    const sumaNuevos = (d.nuevos ?? []).reduce((s, n) => s + Number(n), 0);
    const sumaCierres = (d.cierres ?? []).reduce((s, n) => s + Number(n), 0);
    check(sumaNuevos === nuevosEsperados && sumaCierres === 0,
      'coordinador: las series suman solo las altas de los sin-dueno',
      JSON.stringify({ sumaNuevos, nuevosEsperados }));
  }

  // ── Tanda 2: resumen_tareas_fn autoconsistente por rol ─────────────────────
  for (const key of ['vend1', 'sup1', 'sup2', 'gerencia', 'directorio']) {
    const client = sessions[key].client;
    const tareasRls = await positive(
      `${key} lista sus tareas pendientes como oraculo`,
      client.schema('crm').from('tareas')
        .select('id, lead_id, tipo, vence_en')
        .eq('estado', 'pendiente').eq('activo', true).limit(2000),
    );
    const leadsRls = await positive(
      `${key} lista sus leads para las senales de tareas`,
      client.schema('crm').from('leads')
        .select('id, etapa, vendedor_id, activo').limit(2000),
    );
    const rt = await positive(
      `${key} obtiene resumen_tareas_fn`,
      client.schema('crm').rpc('resumen_tareas_fn'),
    );
    if (!tareasRls || !leadsRls || !rt) continue;
    const ahora = Date.now();
    const pendientes = tareasRls.data ?? [];
    const abiertos = new Map((leadsRls.data ?? [])
      .filter((l) => l.activo === true && ETAPAS_ABIERTAS_F1.has(l.etapa))
      .map((l) => [l.id, l]));
    const d = rt.data ?? {};
    check(d.version === 1 && d.pendientes?.total === pendientes.length,
      `${key}: el total de tareas pendientes cuadra con su propio SELECT por RLS`,
      JSON.stringify({ rpc: d.pendientes?.total, esperado: pendientes.length }));
    const porTipo = { llamada: 0, whatsapp: 0, reunion: 0, tarea: 0 };
    let vencidasHora = 0;
    for (const t of pendientes) {
      if (t.tipo in porTipo) porTipo[t.tipo] += 1;
      if (Date.parse(t.vence_en) < ahora) vencidasHora += 1;
    }
    check(['llamada', 'whatsapp', 'reunion', 'tarea']
      .every((tipo) => (d.pendientes?.por_tipo?.[tipo] ?? -1) === porTipo[tipo]),
      `${key}: el desglose de pendientes por tipo cuadra`);
    check(d.pendientes?.vencidas_hora === vencidasHora
      && d.pendientes?.vencidas_dia <= vencidasHora,
      `${key}: vencidas por hora cuadran (las de dia jamas las superan)`);
    // La vencida mas antigua por lead ABIERTO (espejo de tareasVencidasPorLead).
    const vencidasPorLead = new Set();
    for (const t of pendientes) {
      if (t.lead_id && abiertos.has(t.lead_id) && Date.parse(t.vence_en) < ahora) {
        vencidasPorLead.add(t.lead_id);
      }
    }
    check(d.vencidas?.leads_total === vencidasPorLead.size
      && (d.vencidas?.items ?? []).every((i) => abiertos.has(i.lead_id)),
      `${key}: un lead vencido por fila y todos de su propio ambito`,
      JSON.stringify({ rpc: d.vencidas?.leads_total, esperado: vencidasPorLead.size }));
    // sin_accion: abiertos CON dueno y sin pendiente alguna. En los fixtures la
    // visibilidad de una tarea calca la de su lead, asi que el espejo local es
    // exacto (la divergencia del anti-join canonico esta documentada en la
    // migracion 20260809144912).
    const conTarea = new Set(pendientes.filter((t) => t.lead_id).map((t) => t.lead_id));
    const sinAccion = [...abiertos.values()]
      .filter((l) => l.vendedor_id != null && !conTarea.has(l.id));
    check(d.sin_accion?.total === sinAccion.length
      && (d.sin_accion?.items ?? []).every((i) => abiertos.has(i.lead_id)),
      `${key}: sin_accion cuadra con su ambito`,
      JSON.stringify({ rpc: d.sin_accion?.total, esperado: sinAccion.length }));
  }
  const coordTareas = await positive(
    'coordinador llama resumen_tareas_fn',
    sessions.coordinador.client.schema('crm').rpc('resumen_tareas_fn'),
  );
  if (coordTareas) {
    check(coordTareas.data?.pendientes?.total === 0
      && coordTareas.data?.vencidas?.leads_total === 0
      && coordTareas.data?.sin_accion?.total === 0,
      'coordinador recibe las tareas en cero (su superficie es el reparto)');
  }

  // ── Tanda 2: resumen_cartera_clientes_fn autoconsistente por rol ───────────
  for (const key of ['vend1', 'sup1', 'gerencia', 'directorio']) {
    const client = sessions[key].client;
    const cli = await positive(
      `${key} lista clientes_basicos_fn como oraculo`,
      client.schema('crm').rpc('clientes_basicos_fn'),
    );
    const cons = await positive(
      `${key} lista contratos_cartera_fn como oraculo`,
      client.schema('crm').rpc('contratos_cartera_fn'),
    );
    const rc = await positive(
      `${key} obtiene resumen_cartera_clientes_fn`,
      client.schema('crm').rpc('resumen_cartera_clientes_fn'),
    );
    if (!cli || !cons || !rc) continue;
    const clientes = cli.data ?? [];
    const activoPorCliente = new Map(clientes.map((c) => [c.id, c.activo]));
    // contratos_cartera_fn tiene una rama extra (huerfanos por creado_por); el
    // resumen NO la tiene: el oraculo descarta contratos cuyo cliente no esta
    // en clientes_basicos_fn (mismo descarte que agruparCartera en el front).
    const contratos = (cons.data ?? []).filter((c) => activoPorCliente.has(c.cliente_id));
    const d = rc.data ?? {};
    const enGestion = clientes.filter((c) => c.activo).length;
    const deBaja = clientes.length - enGestion;
    let pen = 0;
    let usd = 0;
    const conCapital = new Set();
    for (const c of contratos) {
      if (c.estado !== 'activo' || activoPorCliente.get(c.cliente_id) !== true) continue;
      conCapital.add(c.cliente_id);
      const capital = Number(c.capital) || 0;
      if (c.moneda === 'USD') usd += capital;
      else pen += capital;
    }
    check(d.version === 1
      && d.clientes?.en_gestion === enGestion
      && d.clientes?.de_baja === deBaja
      && d.clientes?.con_capital === conCapital.size,
      `${key}: los conteos de clientes cuadran con clientes_basicos_fn`,
      JSON.stringify({ rpc: d.clientes, esperado: { enGestion, deBaja, conCapital: conCapital.size } }));
    check(Math.abs(Number(d.capital_activo?.pen ?? -1) - pen) < 0.005
      && Math.abs(Number(d.capital_activo?.usd ?? -1) - usd) < 0.005,
      `${key}: el capital activo por moneda cuadra (PEN y USD jamas sumados)`);
    const sinAsesor = clientes.filter((c) => c.activo && c.asesor_perfil_id == null).length;
    check(d.clientes?.sin_asesor === sinAsesor,
      `${key}: sin_asesor cuadra con su visibilidad (${sinAsesor})`);
    // Alarma de renovacion: contrato activo venciendo en [hoy, hoy+30] Lima,
    // sobre TODOS los clientes visibles (las bajas no la apagan).
    const hoyLima = new Date(Date.now() - LIMA_OFFSET_MS_F1);
    const base = Date.UTC(hoyLima.getUTCFullYear(), hoyLima.getUTCMonth(), hoyLima.getUTCDate());
    const porVencer = contratos.filter((c) => {
      if (c.estado !== 'activo' || !c.fecha_vencimiento) return false;
      const [y, m, dia] = String(c.fecha_vencimiento).split('-').map(Number);
      const dias = Math.round((Date.UTC(y, m - 1, dia) - base) / 86_400_000);
      return dias >= 0 && dias <= 30;
    });
    check(d.contratos?.por_vencer_30 === porVencer.length,
      `${key}: la alarma de renovacion cuadra (${porVencer.length})`);
  }
  const coordCartClientes = await positive(
    'coordinador llama resumen_cartera_clientes_fn',
    sessions.coordinador.client.schema('crm').rpc('resumen_cartera_clientes_fn'),
  );
  if (coordCartClientes) {
    check(coordCartClientes.data?.clientes?.en_gestion === 0
      && Number(coordCartClientes.data?.capital_activo?.pen ?? -1) === 0,
      'coordinador recibe la cartera de clientes en cero');
  }

  // ── Tanda 2: resumen_reparto_fn — gate coordinador|gerencia ────────────────
  for (const key of ['coordinador', 'gerencia']) {
    const client = sessions[key].client;
    const colaOraculo = await positive(
      `${key} lista leads_por_repartir como oraculo del resumen`,
      client.schema('crm').rpc('leads_por_repartir'),
    );
    const rr = await positive(
      `${key} obtiene resumen_reparto_fn`,
      client.schema('crm').rpc('resumen_reparto_fn'),
    );
    if (!colaOraculo || !rr) continue;
    const cola = colaOraculo.data ?? [];
    const pen = cola.filter((l) => l.moneda !== 'USD')
      .reduce((suma, l) => suma + Number(l.monto_estimado ?? 0), 0);
    const usd = cola.filter((l) => l.moneda === 'USD')
      .reduce((suma, l) => suma + Number(l.monto_estimado ?? 0), 0);
    const credito = cola.filter((l) => l.clasificacion_auto === 'posible_credito').length;
    const d = rr.data?.cola ?? {};
    check(rr.data?.version === 1
      && d.total === cola.length
      && Number(d.capital?.pen ?? -1) === pen
      && Number(d.capital?.usd ?? -1) === usd
      && d.posible_credito === credito,
      `${key}: el resumen de reparto cuadra con leads_por_repartir`,
      JSON.stringify({ rpc: d, esperado: { total: cola.length, pen, usd, credito } }));
  }
  // El lector global (directorio) NO opera el reparto: 42501 igual que en
  // leads_por_repartir (contrato historico de C1).
  for (const key of ['vend1', 'sup1', 'directorio']) {
    await expectExplicitAuthorizationDenied(
      `${key} recibe 42501 en resumen_reparto_fn`,
      sessions[key].client.schema('crm').rpc('resumen_reparto_fn'),
      ['42501'],
    );
  }

  // Sin membresia viva ni lector global: denegacion DURA (42501), no vacio.
  for (const key of ['vendInactive', 'clientBank']) {
    for (const [fn, args] of [
      ['resumen_cartera_fn', {}],
      ['cola_accion_fn', { p_limite: 100 }],
      ['metricas_vendedores_fn', {}],
      ['series_comerciales_fn', { p_meses: 6 }],
      ['resumen_tareas_fn', {}],
      ['resumen_cartera_clientes_fn', {}],
      ['resumen_reparto_fn', {}],
    ]) {
      await expectExplicitAuthorizationDenied(
        `${key} recibe 42501 en ${fn}`,
        sessions[key].client.schema('crm').rpc(fn, args),
        ['42501'],
      );
    }
  }

  // Parametros fuera de rango: 22023 con su mensaje (no un 42501 enmascarado).
  await expectExpectedFailure(
    'cola_accion_fn rechaza p_limite=0',
    sessions.gerencia.client.schema('crm').rpc('cola_accion_fn', { p_limite: 0 }),
    ['22023'],
    /p_limite invalido/i,
  );
  await expectExpectedFailure(
    'cola_accion_fn rechaza p_limite=501',
    sessions.gerencia.client.schema('crm').rpc('cola_accion_fn', { p_limite: 501 }),
    ['22023'],
    /p_limite invalido/i,
  );
  await expectExpectedFailure(
    'series_comerciales_fn rechaza p_meses=0',
    sessions.gerencia.client.schema('crm').rpc('series_comerciales_fn', { p_meses: 0 }),
    ['22023'],
    /p_meses invalido/i,
  );
  await expectExpectedFailure(
    'series_comerciales_fn rechaza p_meses=25',
    sessions.gerencia.client.schema('crm').rpc('series_comerciales_fn', { p_meses: 25 }),
    ['22023'],
    /p_meses invalido/i,
  );
}

// ── Decision #10 (b2): ranking de CONVERSION del equipo del supervisor ───────
// La RPC abre a SUPERVISOR una superficie que hasta ahora era exclusiva de
// gerencia/lector global, asi que el gate es parte del entregable, no un
// seguimiento. Tres bloques: (A) permitidos y FORMA, (B) denegaciones duras,
// (C) NO VACUIDAD — sin el bloque C, todo A puede estar verde y vacio.
async function testMetricasConversionesGlobal(sessions) {
  // `num` vivia solo dentro de testCierreDeMes (linea ~7603) y este bloque
  // -el del filtro de origen, anadido el 28/08- lo llamaba desde otro ambito:
  // el gate moria con «num is not defined» tras 650 comprobaciones verdes,
  // sin llegar a las de cierre de mes. Misma definicion, aqui tambien.
  // (Las dos sesiones paralelas del 29/08 llegaron al MISMO arreglo por
  // separado; en el merge quedo una sola copia.)
  const num = (valor) => Number(valor ?? 0);
  // metricas_conversiones_fn (el panel Conversiones de gerencia) jamas tuvo
  // casos en esta matriz (objecion 3 del auditor RLS, F1.3 27/08): su gate es
  // SOLO gerencia/lector global — mas estrecho que el de equipo_fn — y desde
  // F1.3 agrega crm.cierres_externos (PII fuerte) bajo DEFINER: el payload
  // debe seguir siendo agregados numericos, nunca filas de esa tabla.
  const enLima = (fecha) => new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(fecha);
  const ahora = new Date();
  const P = {
    p_desde: enLima(new Date(ahora.getTime() - 29 * 24 * 60 * 60 * 1000)),
    p_hasta: enLima(ahora),
  };

  // ── A · permitidos y forma ────────────────────────────────────────────────
  const global = await positive(
    'gerencia obtiene las metricas de conversiones globales',
    sessions.gerencia.client.schema('crm').rpc('metricas_conversiones_fn', P),
  );
  if (global) {
    check(global.data?.version === 1, 'el payload de conversiones declara version 1');
    // Filtro de origen (28/08): la clave se declara SIEMPRE; sin filtro es null.
    check(Object.hasOwn(global.data ?? {}, 'origen_filtrado') && global.data?.origen_filtrado === null,
      'origen_filtrado se declara y es null sin filtro');
    // F1.3: produccion mide por los caminos vivos y declara sin_rastro. La
    // forma es EXACTA — un campo de mas es superficie sin auditar.
    const produccion = Object.keys(global.data?.produccion ?? {}).sort();
    check(JSON.stringify(produccion) === JSON.stringify([
      'capital_pen', 'capital_usd', 'clientes', 'contratos', 'sin_rastro',
    ]), 'produccion trae SOLO su contrato F1.3', produccion.join(','));
    check(typeof global.data?.produccion?.sin_rastro === 'number',
      'la sonda sin_rastro es un numero, no un hueco');
    // F1.3b (nota 6 del auditor): la forma de origenes[], responsables[] y
    // sondas tambien se FIJA — un campo de mas es superficie sin auditar.
    const clavesOrigen = [...new Set((global.data?.origenes ?? []).flatMap((f) => Object.keys(f)))].sort();
    check(clavesOrigen.length === 0
      || JSON.stringify(clavesOrigen) === JSON.stringify([
        'capital_pen', 'capital_usd', 'clientes', 'contactados', 'contratos',
        'conversion_clientes_pct', 'conversion_contratos_pct',
        'conversion_resueltos_pct', 'descartados',
        'fuera_del_divisor_del_nucleo', 'leads', 'origen', 'peso_en_nucleo',
        'reuniones_agendadas', 'reuniones_realizadas',
      ]), 'cada origen trae SOLO los 15 campos del contrato', clavesOrigen.join(','));
    const clavesResp = [...new Set((global.data?.responsables ?? []).flatMap((f) => Object.keys(f)))].sort();
    check(clavesResp.length === 0
      || JSON.stringify(clavesResp) === JSON.stringify([
        'capital_pen', 'capital_usd', 'clientes', 'contactados',
        'conversion_pct', 'leads', 'nucleo_conversion_pct', 'nucleo_divisor',
        'nucleo_numerador', 'reuniones_realizadas', 'tendencia_semanal',
        'vendedor_id',
      ]), 'cada responsable trae SOLO los 12 campos del contrato', clavesResp.join(','));
    const clavesSondas = Object.keys(global.data?.sondas ?? {}).sort();
    check(JSON.stringify(clavesSondas) === JSON.stringify([
      'cartera_fuera_del_rango', 'cierres_anulados',
      'cierres_sin_ficha_convertida', 'cohorte_convertidos_sin_cierre_elegible',
      'cuadra', 'divisor_fuera_del_roster', 'episodios_sin_origen',
      'numerador_fuera_del_roster', 'origen_ficha_distinto_del_ledger',
      'paridad_filas', 'paridad_nucleo',
      'perfiles_con_leads_de_varios_vendedores',
    ]), 'el bloque sondas de conversiones trae SOLO su contrato F1.3b', clavesSondas.join(','));
    // La PII de cierres_externos NO viaja: ninguna clave de identidad en el
    // payload plano (strings del documento/nombre/transaccion jamas salen).
    const plano = JSON.stringify(global.data ?? {});
    check(!plano.includes('numero_transaccion') && !plano.includes('nombre_completo')
      && !plano.includes('documento'),
      'el payload no expone columnas de identidad de cierres_externos');
  }

  const directorio = await positive(
    'directorio (lector global) obtiene las metricas de conversiones',
    sessions.directorio.client.schema('crm').rpc('metricas_conversiones_fn', P),
  );
  if (directorio && global) {
    check(directorio.data?.version === 1, 'el lector global recibe el mismo contrato');
  }

  // ── A2 · filtro de origen (28/08): recorta el LOTE y se declara ──────────
  const filtrado = await positive(
    'gerencia filtra las conversiones por origen',
    sessions.gerencia.client.schema('crm').rpc('metricas_conversiones_fn', { ...P, p_origen: 'referido' }),
  );
  if (filtrado) {
    check(filtrado.data?.origen_filtrado === 'referido',
      'el payload declara el origen filtrado');
    const origenesFiltrados = (filtrado.data?.origenes ?? []).map((o) => o.origen);
    check(origenesFiltrados.every((o) => o === 'referido'),
      'origenes[] solo trae el origen elegido', origenesFiltrados.join(','));
    check(num(filtrado.data?.cohorte?.leads) <= num(global?.data?.cohorte?.leads),
      'el lote filtrado nunca supera al total');
    // El nucleo NO se filtra (mide a la empresa; la pantalla no lo pinta con filtro).
    check(num(filtrado.data?.nucleo?.divisor) === num(global?.data?.nucleo?.divisor),
      'el nucleo del mes queda SIN filtrar (deliberado y documentado)');
  }
  // 'sin_origen' es rama propia del contrato (coalesce): lote de leads sin
  // origen registrado, con forma estable.
  const sinOrigen = await positive(
    "gerencia filtra por 'sin_origen' (rama del coalesce)",
    sessions.gerencia.client.schema('crm').rpc('metricas_conversiones_fn', { ...P, p_origen: 'sin_origen' }),
  );
  if (sinOrigen) {
    check(sinOrigen.data?.origen_filtrado === 'sin_origen',
      "el payload declara 'sin_origen' como filtro");
    check((sinOrigen.data?.origenes ?? []).every((o) => o.origen === 'sin_origen'),
      'con sin_origen, origenes[] solo trae esa fila (o ninguna)');
  }
  // Un origen inventado devuelve el LOTE VACIO con la forma intacta — jamas
  // un error ni un payload distinto (quien llega aqui ya ve todo; no hay
  // nada que esconder, solo nada que mostrar).
  const inventado = await positive(
    'un origen inexistente devuelve lote vacio con forma estable',
    sessions.gerencia.client.schema('crm').rpc('metricas_conversiones_fn', { ...P, p_origen: 'marte' }),
  );
  if (inventado) {
    check(num(inventado.data?.cohorte?.leads) === 0 && (inventado.data?.origenes ?? []).length === 0,
      'lote vacio: cohorte 0 y sin origenes');
    check(inventado.data?.version === 1 && Object.hasOwn(inventado.data ?? {}, 'produccion'),
      'la forma del payload sobrevive al lote vacio');
  }

  // ── B · denegaciones DURAS (42501, jamas un payload de ceros) ─────────────
  // A diferencia de equipo_fn, aqui TAMBIEN los supervisores quedan fuera:
  // el gate es gerencia/lector global y nada mas.
  for (const key of ['vend1', 'vend3', 'sup1', 'sup2', 'sup1Nested', 'coordinador', 'vendInactive', 'clientBank']) {
    await expectExplicitAuthorizationDenied(
      `${key} no ejecuta metricas_conversiones_fn`,
      sessions[key].client.schema('crm').rpc('metricas_conversiones_fn', P),
    );
  }

  // El GATE va antes que la validacion de periodo: un rol denegado recibe
  // 42501 aunque el periodo tambien sea invalido.
  const periodoInvalido = { p_desde: P.p_desde, p_hasta: '2999-01-01' };
  await expectExplicitAuthorizationDenied(
    'un supervisor recibe 42501 y NO 22023 con un periodo invalido',
    sessions.sup1.client.schema('crm').rpc('metricas_conversiones_fn', periodoInvalido),
  );
  // El gate tambien manda con el parametro nuevo: filtrar no abre puertas.
  await expectExplicitAuthorizationDenied(
    'un analista sigue denegado aunque pida p_origen',
    sessions.vend1.client.schema('crm').rpc('metricas_conversiones_fn', { ...P, p_origen: 'referido' }),
  );
  await expectExpectedFailure(
    'gerencia recibe 22023 con p_hasta en el futuro',
    sessions.gerencia.client.schema('crm').rpc('metricas_conversiones_fn', periodoInvalido),
    ['22023'],
    /periodo invalido/i,
  );
}

async function testCitasNucleo(sessions, seed) {
  console.log('\n— Citas: la pantalla de reuniones y el nucleo (P-055 F6.a) —');

  // La ventana en zona LIMA (la RPC valida p_hasta > hoy-Lima con 22023).
  const enLima = (fecha) => new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(fecha);
  const ahora = new Date();
  // 🔴 La ventana se ANCLA AL FIXTURE, no a «los ultimos 29 dias»: las citas de
  //    seed-demo tienen fechas FIJAS (TAREAS, 2026-07-2x) y la ventana relativa
  //    al reloj las fue dejando atras — el 01/09 la guarda anti-vacuidad se puso
  //    roja con el fixture INTACTO (bomba de tiempo, no regresion). La RPC
  //    admite hasta 365 dias hacia atras, asi que se abre desde la cita mas
  //    antigua; y si el fixture envejece mas alla del alcance de la RPC, la
  //    aserción de abajo lo dice CON NOMBRE en vez de fingir un mundo vacio.
  //    ⚠️ Codex (01/09) refutó la primera versión del ancla en dos puntos:
  //    (a) tomaba el mínimo de TODAS las TAREAS y la RPC solo mira
  //    `tipo='reunion'` — una llamada vieja habría ensanchado la ventana y
  //    disparado la alarma de envejecimiento con las reuniones aún vigentes;
  //    (b) el clamp usaba 364 días cuando la RPC rechaza solo diferencias
  //    MAYORES que 365 — la alarma se habría puesto roja un día antes que la
  //    propia RPC. Corregido: solo reuniones, y 365.
  const fechasCita = TAREAS
    .filter((t) => t.tipo === 'reunion')
    .map((t) => Date.parse(t.venceEn));
  const primeraCita = fechasCita.length ? Math.min(...fechasCita) : NaN;
  check(Number.isFinite(primeraCita),
    'reuniones: el fixture trae al menos una reunion con fecha valida');
  if (!Number.isFinite(primeraCita)) return;
  const alcanceMaximo = ahora.getTime() - 365 * 24 * 60 * 60 * 1000;
  check(primeraCita >= alcanceMaximo,
    'reuniones: el fixture sigue al alcance de la RPC (reuniones de seed-demo con 365 dias o menos; si esto falla, re-fechar fixtures.mjs)',
    `primera reunion ${new Date(primeraCita).toISOString()}`);
  const P = {
    p_desde: enLima(new Date(Math.max(primeraCita, alcanceMaximo))),
    p_hasta: enLima(ahora),
  };

  // A. Permitidos: gerencia y lector global, con FORMA (no basta un 200).
  const ger = await positive(
    'gerencia obtiene las metricas de reuniones',
    sessions.gerencia.client.schema('crm').rpc('metricas_reuniones_fn', P),
  );
  if (ger) {
    check(ger.data?.version === 1, 'reuniones: el payload declara version 1');
    const r = ger.data?.resumen;
    check(r && typeof r.pactadas === 'number' && typeof r.realizadas === 'number',
      'reuniones: el resumen trae pactadas y realizadas numericas');
    // Guarda anti-vacuidad: un fixture sin UNA cita en la ventana convertiria
    // cualquier paridad en una prueba de nada. La siembra crea reuniones.
    check((r?.pactadas ?? 0) > 0,
      'reuniones: la ventana del fixture contiene al menos una cita pactada');
  }
  await positive(
    'directorio (lector global) obtiene las metricas de reuniones',
    sessions.directorio.client.schema('crm').rpc('metricas_reuniones_fn', P),
  );

  // B. Denegados: ni comercial, ni supervisor, ni coordinador.
  for (const key of ['vend1', 'sup1', 'coordinador']) {
    if (!sessions[key]) continue;
    await expectExplicitAuthorizationDenied(
      `${key} no ejecuta metricas_reuniones_fn`,
      sessions[key].client.schema('crm').rpc('metricas_reuniones_fn', P),
    );
  }

  // C. El NUCLEO no es alcanzable por PostgREST: vive en private y sin grant.
  for (const key of ['gerencia', 'vend1']) {
    const { error } = await sessions[key].client
      .schema('private').rpc('citas_episodios', { p_ini: P.p_desde, p_fin: P.p_hasta });
    check(Boolean(error),
      `${key} NO alcanza private.citas_episodios por la API (${error?.code ?? 'sin error'})`);
  }
}

async function testCapacidadUnificada(sessions, seed) {
  console.log('\n— Una pregunta por capacidad (P-055 F5.b) —');

  // D1 · F5.d: la gemela del catalogo versionado esta CERRADA PARA TODOS
  //     (revoke a authenticated; rama muerta medida el 30/08 — 0 llamadas en
  //     portal, CRM, edges y servidor). La semantica de autoridad de ventas que
  //     este bloque probaba antes por la gemela vive ahora en testVentasNucleoF5c,
  //     sobre el nucleo REAL del alta (public.crear_contrato).
  //     42501 para CUALQUIERA = puerta cerrada; cualquier otro codigo = se abrio.
  const pasaElGate = async (label, promise, deberiaPasar) => {
    const { error } = await promise;
    const denegada = error?.code === '42501' || /no autorizado/i.test(error?.message ?? '');
    check(deberiaPasar ? !denegada : denegada, label);
  };

  // CANARIA del bug de imagen (auditoria F5.d, P1): en la imagen 17.6.1.105
  // llamar una funcion sin EXECUTE por SQL directo SEGFAULTEO el backend
  // (memoria 2026-08-20); la via PostgREST se midio SEGURA en la F1 (20x
  // HTTP 401/42501, banco vivo). Aun asi, la PRIMERA llamada a una gemela
  // cerrada va SOLA y con diagnostico propio: si la respuesta llega sin codigo
  // (fallo de conexion = backend caido), este bloque se aborta nombrando la
  // causa REAL en vez de dejar que la suite muera en cascada espuria.
  // 🪦 F7 Ola 2 (13/09): mientras las siete gemelas EXISTAN cerradas, PostgREST
  //    responde 42501; cuando se demuelan responde PGRST202 «no existe». Las dos
  //    significan «este rol no la alcanza», y por eso aqui valen las dos.
  //    ⚠️ Solo para ESTAS SIETE firmas: `pasaElGate` sigue exigiendo 42501 para
  //    todo lo demas, porque en una puerta VIVA un PGRST202 no seria un candado
  //    sino la prueba de que alguien se llevo por delante algo que debia estar.
  const gemelaFueraDeAlcance = (error) => error?.code === '42501'
    || error?.code === 'PGRST202'
    || /no autorizado/i.test(error?.message ?? '');
  const gemelaNoAlcanzable = async (label, promise) => {
    const { error } = await promise;
    check(gemelaFueraDeAlcance(error), `${label} [${error?.code ?? 'sin codigo'}]`);
  };

  {
    const { error } = await sessions.gerencia.client.schema('crm').rpc('crear_contrato_producto',
      { p_contrato: {}, p_producto_condicion_id: null, p_cronograma: [] });
    if (error && !error.code) {
      check(false,
        'D1/F5.d CANARIA: la gemela cerrada respondio SIN codigo — posible backend caido '
        + '(bug de EXECUTE de la imagen, memoria 2026-08-20); D1 abortado, revisar la imagen del banco',
        error.message ?? 'sin mensaje');
      return;
    }
    check(gemelaFueraDeAlcance(error),
      `D1/F5.d gerencia NO alcanza crm.crear_contrato_producto (gemela cerrada o demolida) [${error?.code ?? 'sin codigo'}]`);
  }

  for (const key of ['vend1', 'sup1', 'coordinador', 'directorio', 'vendInactive']) {
    if (!sessions[key]) continue;
    await gemelaNoAlcanzable(`D1/F5.d ${key} NO alcanza crm.crear_contrato_producto (gemela cerrada o demolida)`,
      sessions[key].client.schema('crm').rpc('crear_contrato_producto',
        { p_contrato: {}, p_producto_condicion_id: null, p_cronograma: [] }));
  }

  // Las SIETE firmas cerradas, probadas por conducta (auditoria Codex, P2:
  // 2/7 dejaba 5 sin sonda PostgREST). crm.crear_contrato_producto ya quedo
  // cubierta arriba con 6 sesiones; aqui vend1 (la sesion antes mas fuerte
  // sobre estas puertas) contra las otras 6 firmas, en sus DOS superficies
  // PostgREST (public sin .schema, crm con ella). Nombres de argumento
  // medidos en prod el 30/08.
  const cerradasF5d = [
    ['public', 'crear_contrato_producto',
      { p_producto_condicion_id: null, p_contrato: {}, p_cronograma: [] }],
    ['public', 'actualizar_contrato_producto',
      { p_id: crypto.randomUUID(), p_producto_condicion_id: null, p_contrato: {}, p_cronograma: [] }],
    ['public', 'actualizar_contrato_con_cuenta_producto',
      { p_id: crypto.randomUUID(), p_producto_condicion_id: null, p_contrato: {}, p_cronograma: [] }],
    ['crm', 'crear_contrato_con_cuenta_producto',
      { p_producto_condicion_id: null, p_contrato: {}, p_cronograma: [], p_cuenta: {} }],
    ['crm', 'actualizar_contrato_producto',
      { p_id: crypto.randomUUID(), p_producto_condicion_id: null, p_contrato: {}, p_cronograma: [] }],
    ['crm', 'actualizar_contrato_con_cuenta_producto',
      { p_id: crypto.randomUUID(), p_producto_condicion_id: null, p_contrato: {}, p_cronograma: [] }],
  ];
  for (const [esquema, fn, payload] of cerradasF5d) {
    const cliente = esquema === 'crm'
      ? sessions.vend1.client.schema('crm')
      : sessions.vend1.client;
    await gemelaNoAlcanzable(`D1/F5.d vend1 NO alcanza ${esquema}.${fn} (gemela cerrada o demolida)`,
      cliente.rpc(fn, payload));
  }

  // D2 · catalogo: coordinador SI (miembro CRM), sin-membresia NO
  await pasaElGate('D2 coordinador VE el catalogo de productos',
    sessions.coordinador.client.schema('crm').rpc('productos_inversion_seleccion_fn', {}), true);
  await pasaElGate('D2 clientBank (sin membresia CRM) NO ve el catalogo',
    sessions.clientBank.client.schema('crm').rpc('productos_inversion_seleccion_fn', {}), false);

  // D3 · cerrar contrato: vendedor NO, gerencia SI
  // 🔴 Los nombres de los parametros van AL LITERAL de la firma viva
  //    (p_id, p_resultado, p_contrato_nuevo_id). Con nombres inventados
  //    PostgREST devuelve PGRST202 «no matching function» y la pareja se rompia
  //    en DOS direcciones: el NO fallaba honesto (PGRST202 no es denegacion)
  //    y el SI pasaba EN FALSO — nunca llego a la funcion, pero "no denegado"
  //    daba verde. Falso verde en la suite de seguridad, destapado por el banco
  //    el 01/09 gracias a que su mitad roja delato a la verde.
  //    ⚠️ Codex refutó ademas el arreglo a medias: `pasaElGate(..., true)`
  //    seguia dando verde con PGRST202, 42P01 o cualquier error interno. Se
  //    clava CODIGO Y MENSAJE exactos en ambas mitades. Nota honesta: Codex
  //    afirmo que el `RAISE 'No autorizado'` no llevaba ERRCODE (P0001) y la
  //    corrida contra el banco lo DESMINTIO: el gate vivo responde 42501 al
  //    literal (`USING ERRCODE = '42501'`, verificado en el prosrc). Se clava
  //    lo MEDIDO, no lo argumentado — ni siquiera cuando lo argumenta el
  //    auditor. La mitad de gerencia si muere en P0001 (Contrato no
  //    encontrado, RAISE sin codigo): cada mitad con su codigo real.
  const argsD3 = { p_id: crypto.randomUUID(), p_resultado: 'retirado', p_contrato_nuevo_id: null };
  await expectExpectedFailure(
    'D3 vend1 NO cierra contratos',
    sessions.vend1.client.rpc('cerrar_contrato', argsD3),
    ['42501'],
    /^No autorizado$/i,
  );
  await expectExpectedFailure(
    'D3 gerencia llega al CUERPO de cerrar_contrato (pasa el gate, muere en el contrato inexistente)',
    sessions.gerencia.client.rpc('cerrar_contrato', argsD3),
    ['P0001'],
    /Contrato no encontrado/i,
  );

  // D4 · el candado de pares, desde el PANEL (auth.uid presente = sesion admin).
  //      Un par no declarado rebota; la tabla de pares NO se puede vaciar.
  const superadmin = sessions.gerencia; // la sesion gerencia del fixture es admin/superadmin en el arbol de pruebas
  await expectExpectedFailure(
    'D4 designar un par no declarado (comercial->gerencia) rebota',
    sessions.coordinador.client.schema('crm').rpc('asignar_rol_usuario_fn',
      { p_perfil_id: seed.profileIdByKey.coordinador, p_rol_crm: 'gerencia', p_desde: null, p_por: null }),
    ['42501', '42P01', 'PGRST202'],  // 42501 candado, o denegado por autorizacion previa de la RPC
    /./,
  );
}

// P-055 F5.c — la pregunta unica LLEGA AL NUCLEO DEL DINERO (Opcion B).
// La F5.b probo las 7 gemelas (crear_contrato_producto, etc.); esto prueba los
// nucleos REALES del alta (public.crear_contrato, el que usa la pantalla de
// contratos via los wrappers _con_cuenta_pdf). La autoridad ya no mira cartera:
// cualquier analista vigente registra para cualquier cliente ACTIVO, y la venta
// cuenta a quien la cierra (analista_cierre, F3).
// P-055 ATR-3a — las lentes y la ficha dicen quien se lleva la produccion.
// Casos runnables HOY: formas por rol + la clave nueva en un contrato normal +
// el no-miembro ve vacio. Los casos de CADENA REAL (permitido cruzado /
// denegado del dueño / sin-analista invisible) esperan el fixture de upgrade
// de seed-demo — la MISMA deuda nombrada de ATR-1/ATR-2 (proximo ciclo de banco).
async function testLentesAtribucion(sessions, seed) {
  console.log('\n— Lentes y ficha de atribucion (P-055 ATR-3a) —');

  // A. Gerencia: las dos lentes responden con la FORMA correcta.
  {
    const { data, error } = await sessions.gerencia.client
      .schema('crm').rpc('metricas_capital_mes_fn', { p_meses: 12 });
    check(!error && Array.isArray(data),
      `gerencia lee metricas_capital_mes_fn (${error?.code ?? data?.length + ' filas'})`);
  }
  {
    const { data, error } = await sessions.gerencia.client
      .schema('crm').rpc('metricas_vencimientos_fn', { p_dias: 90 });
    check(!error && Array.isArray(data),
      `gerencia lee metricas_vencimientos_fn (${error?.code ?? data?.length + ' filas'})`);
  }

  // B. Un analista lee SIN error (su corte ahora es su produccion, no su cartera).
  {
    const { error } = await sessions.vend1.client
      .schema('crm').rpc('metricas_capital_mes_fn', { p_meses: 3 });
    check(!error, `vend1 lee la lente de capital sin error (${error?.code ?? 'ok'})`);
  }

  // C. Un cliente (sin membresia CRM): la lente responde VACIA, no con datos.
  {
    const { data, error } = await sessions.clientBank.client
      .schema('crm').rpc('metricas_capital_mes_fn', { p_meses: 12 });
    check(!error && Array.isArray(data) && data.length === 0,
      `clientBank (sin membresia) recibe la lente VACIA (${error?.code ?? data?.length + ' filas'})`);
  }

  // D. La ficha de un contrato NORMAL trae atribucion_efectiva con la verdad:
  //    cadena=false, adoptada=false, analista = el de la ficha.
  {
    const { data, error } = await sessions.gerencia.client
      .schema('crm').rpc('atribucion_contrato_fn', { p_contrato_id: seed.contract.id });
    const ef = data?.atribucion_efectiva;
    check(!error && ef
      && ef.cadena === false && ef.adoptada === false
      && ef.analista_id === (data?.analista_id ?? null),
      `atribucion_efectiva presente y veraz en contrato normal (${error?.code ?? JSON.stringify(ef ?? null)})`);
  }
}

// P-055 F7 — el SUSTITUTO de metricas_altas_analista_fn (altas de contratos NUEVOS
// por el analista que cierra). Es una VERJA de visibilidad, NO un cierre: el no
// autorizado recibe 0 filas, no un 42501. (auditor-rls 04/09, hallazgo M-1.)
async function testAltasNuevasPorAnalista(sessions, seed) {
  console.log('\n— Altas nuevas por analista (sustituto F7) —');
  const FN = 'altas_nuevas_por_analista_fn';

  // Si la funcion aun no esta desplegada en esta base (suite corrida sin esta
  // migracion, p. ej. otra sesion en su branch), saltar — pero RUIDOSO: un salto
  // silencioso pintaria de verde lo no probado (auditor-rls M-C). Con
  // CRM_RLS_EXIGE_ALTAS=1 el salto es un FALLO (para el ciclo del `!` de esta
  // migracion, donde el bloque TIENE que haber corrido).
  {
    const probe = await sessions.gerencia.client.schema('crm').rpc(FN, { p_meses: 1 });
    if (probe.error?.code === 'PGRST202') {
      const msg = `⚠ ${FN} NO desplegada en esta base: bloque de altas SALTADO (no probado)`;
      if (process.env.CRM_RLS_EXIGE_ALTAS === '1') fail(msg);
      else console.log(`  ${msg}`);
      return;
    }
  }
  const ids = seed.profileIdByKey;
  // Subarbol de sup1 (fixtures.mjs): sup1, vend1, vend2, sup1Nested, vendNested.
  const SUBARBOL_SUP1 = new Set([ids.sup1, ids.vend1, ids.vend2, ids.sup1Nested, ids.vendNested]);
  const FUERA_SUP1 = new Set([ids.sup2, ids.vend3, ids.vend4, ids.vendInactive]);

  // A. Gerencia (global): lee sin error, forma de array. No se fija la CUENTA: el
  //    fixture de seed puede ser escaso y la seguridad no depende del volumen.
  {
    const { data, error } = await sessions.gerencia.client
      .schema('crm').rpc(FN, { p_meses: 12 });
    check(!error && Array.isArray(data),
      `gerencia lee ${FN} (${error?.code ?? (data?.length ?? 0) + ' filas'})`);
  }

  // B. AISLAMIENTO del vendedor: TODO lo que ve es SUYO (analista_id == vend1) y
  //    nunca la fila "Sin analista" (null solo la ve un global). Una regresion
  //    donde `es_global` diera true a todos NO pasaria esto (auditor-rls M-B).
  let filasVend1 = [];
  {
    const { data, error } = await sessions.vend1.client
      .schema('crm').rpc(FN, { p_meses: 60 });
    filasVend1 = data ?? [];
    const soloSuyo = filasVend1.every((f) => f.analista_id === ids.vend1);
    check(!error && Array.isArray(data) && soloSuyo,
      `vend1 solo ve SUS altas en ${FN} (${error?.code ?? filasVend1.length + ' filas'})`);
  }

  // C. Coordinador: NO esta en la allowlist ni es lector global -> 0 filas.
  {
    const { data, error } = await sessions.coordinador.client
      .schema('crm').rpc(FN, { p_meses: 12 });
    check(!error && Array.isArray(data) && data.length === 0,
      `coordinador recibe ${FN} VACIO (${error?.code ?? (data?.length ?? 0) + ' filas'})`);
  }

  // D. Cliente sin membresia CRM: 0 filas.
  {
    const { data, error } = await sessions.clientBank.client
      .schema('crm').rpc(FN, { p_meses: 12 });
    check(!error && Array.isArray(data) && data.length === 0,
      `clientBank (sin membresia) recibe ${FN} VACIO (${error?.code ?? (data?.length ?? 0) + ' filas'})`);
  }

  // E. anon: sin EXECUTE (ni USAGE de crm) -> error de AUTORIZACION, no cualquiera.
  {
    const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-altas'));
    const { error } = await anon.schema('crm').rpc(FN, { p_meses: 12 });
    check(isAuthorizationError(error), `anon NO ejecuta ${FN} (${error?.code ?? 'sin error!'})`);
  }

  // G. AISLAMIENTO del supervisor: sup1 ve SOLO su subarbol y NADA de sup2.
  {
    const { data, error } = await sessions.sup1.client
      .schema('crm').rpc(FN, { p_meses: 60 });
    const filas = data ?? [];
    const dentro = filas.every((f) => f.analista_id !== null && SUBARBOL_SUP1.has(f.analista_id));
    const fuga = filas.some((f) => FUERA_SUP1.has(f.analista_id));
    check(!error && Array.isArray(data) && dentro && !fuga,
      `sup1 ve solo su subarbol en ${FN} (${error?.code ?? filas.length + ' filas'}${fuga ? ' — FUGA a sup2' : ''})`);
  }

  // H. Miembro INACTIVO (activo=false): la verja no le abre -> 0 filas.
  {
    const { data, error } = await sessions.vendInactive.client
      .schema('crm').rpc(FN, { p_meses: 60 });
    check(!error && Array.isArray(data) && data.length === 0,
      `vendInactive recibe ${FN} VACIO (${error?.code ?? (data?.length ?? 0) + ' filas'})`);
  }

  // I. PARIDAD: la fila (mes, vend1) que ve vend1 es LA MISMA que ve gerencia.
  //    Si difieren, uno de los dos miente (distinto conteo por rol = falso).
  let filasGerencia = [];
  {
    const { data, error } = await sessions.gerencia.client
      .schema('crm').rpc(FN, { p_meses: 60 });
    filasGerencia = data ?? [];
    const clave = (f) => `${f.mes}|${f.analista_id}`;
    const deGerencia = new Map(filasGerencia.map((f) => [clave(f), Number(f.altas)]));
    const paridad = filasVend1.every((f) => deGerencia.get(clave(f)) === Number(f.altas));
    check(!error && paridad,
      `paridad vend1 == gerencia por (mes, analista) en ${FN} (${filasVend1.length} filas comparadas)`);
  }

  // J. ORACULO DE FECHA (la defensa REAL contra el footgun de la v1, que la guarda
  //    del postflight NO da: aquella evalua su propia expresion, no la funcion).
  //    Cada `mes` que devuelve la funcion DEBE ser el mes calendario de algun
  //    cierre real, y la suma de altas no puede superar los contratos nuevos.
  //    Robusto a un seed escaso: el fixture cierra el dia 1 (fecha_inicio
  //    2026-01-01 / 2026-02-01), justo el dia que un `at time zone` sobre un
  //    date manda al mes ANTERIOR — la v1 habria devuelto 2025-12-01/2026-01-01
  //    y este oraculo lo habria cazado.
  {
    const { data: contratos, error } = await admin.from('contratos')
      .select('fecha_cierre_comercial')
      .eq('categoria', 'nuevo').eq('es_demo', false);
    const mesesReales = new Set((contratos ?? [])
      .filter((c) => c.fecha_cierre_comercial)
      .map((c) => `${String(c.fecha_cierre_comercial).slice(0, 7)}-01`));
    const mesesDevueltos = [...new Set(filasGerencia.map((f) => String(f.mes)))];
    const fantasma = mesesDevueltos.filter((m) => !mesesReales.has(m));
    const sumaAltas = filasGerencia.reduce((a, f) => a + Number(f.altas), 0);
    check(!error && fantasma.length === 0 && sumaAltas <= (contratos ?? []).length,
      `oraculo de fecha: cada mes devuelto es el mes calendario de un cierre real (${mesesDevueltos.length} meses, ${sumaAltas} altas <= ${(contratos ?? []).length} contratos nuevos)`,
      fantasma.length ? `meses FANTASMA (bucket corrido): ${fantasma.join(', ')}` : '');
  }
}

// P-055 F7.1 — las puertas cerradas de la Ola 1 responden 42501 a TODOS,
// incluida public.actualizar_numero_contrato (sus argumentos son los mismos
// p_id/p_numero/p_notas/p_categoria de las sondas P04 — Codex 30/08) y el
// propio service_role (perdio dos EXECUTE directos en esta ola).
async function testF7Ola1(sessions) {
  console.log('\n— Puertas cerradas de la Ola 1 (P-055 F7.1) —');
  const puertas = [
    ['metricas_distribucion_leads_fn', { p_desde: '2026-08-01', p_hasta: '2026-08-31' }],
    ['metricas_distribucion_leads_v2_fn', { p_desde: '2026-08-01', p_hasta: '2026-08-31' }],
    ['metricas_cartera_fn', { p_periodo: '2026-08-01' }],
    ['metricas_altas_analista_fn', { p_meses: 3 }],
    ['crear_contrato_con_cuenta', { p_contrato: {}, p_cronograma: [], p_cuenta: {} }],
    ['actualizar_contrato_con_cuenta', {
      p_id: '00000000-0000-4000-8000-000000000000',
      p_contrato: {},
      p_cronograma: [],
    }],
  ];
  // CANARIA (patron F5.d): la primera llamada va sola; sin codigo = backend caido.
  {
    const { error } = await sessions.gerencia.client
      .schema('crm').rpc('metricas_cartera_fn', { p_periodo: '2026-08-01' });
    if (error && !error.code) {
      check(false, 'F7.1 CANARIA: respuesta sin codigo — posible backend caido', error.message ?? '');
      return;
    }
    check(error?.code === '42501',
      `F7.1 gerencia NO alcanza metricas_cartera_fn (${error?.code ?? 'sin error'})`);
  }
  // 🪦 De estas puertas, SOLO `metricas_altas_analista_fn` se demuele (Ola 2b,
  //    14/09): cuando desaparezca, PostgREST pasa de 42501 a PGRST202. Las
  //    otras CINCO se quedan (dos del bridge, DEUDA declarada; `metricas_cartera_fn`
  //    y las dos de contrato, `cerrada_permanente`), asi que para ellas un
  //    PGRST202 significaria que
  //    alguien borro algo que debia seguir en pie: ahi se exige 42501 a secas.
  const DEMOLIBLE_EN_OLA_2B = new Set(['metricas_altas_analista_fn']);
  for (const [fn, args] of puertas) {
    for (const key of ['gerencia', 'vend1']) {
      const { error } = await sessions[key].client.schema('crm').rpc(fn, args);
      const fuera = error?.code === '42501'
        || (DEMOLIBLE_EN_OLA_2B.has(fn) && error?.code === 'PGRST202');
      check(fuera, `F7.1 ${key} NO alcanza ${fn} (${error?.code ?? 'sin error'})`);
    }
  }
  // La puerta de public, directa (el 42501 del ACL corre ANTES del cuerpo:
  // ni el id inventado ni el numero llegan a evaluarse).
  for (const key of ['gerencia', 'vend1']) {
    const { error } = await sessions[key].client.rpc('actualizar_numero_contrato', {
      p_id: '00000000-0000-4000-8000-000000000000',
      p_numero: 'SONDA-F7-1',
      p_notas: null,
      p_categoria: null,
    });
    check(error?.code === '42501',
      `F7.1 ${key} NO alcanza public.actualizar_numero_contrato (${error?.code ?? 'sin error'})`);
  }
  // service_role perdio sus DOS EXECUTE directos en esta ola: el cliente admin
  // (llave de servicio) tambien debe recibir 42501 (Codex 30/08). El MENSAJE
  // debe ser el del ACL («permission denied for function»): sin esa distincion
  // la sonda daria falso verde — el CUERPO de cartera tambien lanza 42501
  // cuando auth.uid() es NULL, y eso significaria que la puerta SI abrio.
  {
    const { error } = await admin.schema('crm')
      .rpc('metricas_cartera_fn', { p_periodo: '2026-08-01' });
    check(error?.code === '42501' && /permission denied/i.test(error?.message ?? ''),
      `F7.1 service_role NO alcanza metricas_cartera_fn por ACL (${error?.code ?? 'sin error'}: ${error?.message ?? ''})`);
  }
  {
    const { error } = await admin.rpc('actualizar_numero_contrato', {
      p_id: '00000000-0000-4000-8000-000000000000',
      p_numero: 'SONDA-F7-1-SRV',
      p_notas: null,
      p_categoria: null,
    });
    check(error?.code === '42501' && /permission denied/i.test(error?.message ?? ''),
      `F7.1 service_role NO alcanza public.actualizar_numero_contrato por ACL (${error?.code ?? 'sin error'}: ${error?.message ?? ''})`);
  }
}

// P-055 ATR-1 — la atribucion por cadena de upgrade vive en la LECTURA.
// El resolutor es private y sin grant: NADIE lo alcanza por PostgREST. Los
// casos de CONDUCTA (upgrade de vend2 sobre cliente de vend1 -> las metricas
// se lo acreditan a vend2; el dueno no lo ve como suyo; el directorio del
// Portal NO cambia) necesitan un fixture de upgrade en seed-demo: van en el
// proximo ciclo de banco, junto al resto de la suite.
async function testAtribucionCadena(sessions) {
  console.log('\n— Atribucion por cadena de upgrade (P-055 ATR-1) —');
  for (const key of ['gerencia', 'vend1']) {
    const { error } = await sessions[key].client
      .schema('private').rpc('analista_atribuido_cadena', { p_contrato_id: crypto.randomUUID() });
    check(Boolean(error),
      `${key} NO alcanza private.analista_atribuido_cadena por la API (${error?.code ?? 'sin error'})`);
  }
}

async function testVentasNucleoF5c(sessions, seed) {
  console.log('\n— Ventas al nucleo del dinero: Opcion B (P-055 F5.c) —');
  const bankProfileId = seed.profileIdByKey[BANK_CLIENT.key]; // cliente activo, asesor = vend1
  const altaAjena = {
    p_contrato: {
      cliente_id: bankProfileId,
      moneda: BANK_CONTRACT.currency,
      capital: 1000,
      tasa_anual: 10,
      categoria: 'nuevo',
    },
    // Cronograma vacio A PROPOSITO: pasar la autoridad y morir en la validacion
    // de terminos PRUEBA el gate sin escribir una sola fila.
    p_cronograma: [],
  };

  // Denegacion de AUTORIDAD del nucleo = 42501 con el mensaje de cartera (el
  // raise no cambio en F5.c, solo su condicion). "Paso la autoridad" = NO es ese 42501.
  const negadoPorAutoridad = (error) =>
    error?.code === '42501'
    && /cliente no encontrado o fuera de tu cartera/i.test(error?.message ?? '');

  // POSITIVO (decision B): un analista VIGENTE con ficha CRM (vend3) registra
  // para el cliente de OTRA analista (bankProfileId, asesor = vend1). La autoridad
  // ya NO cierra por cartera -> pasa y muere aguas abajo en la validacion de
  // terminos, sin escribir nada.
  {
    const { error } = await sessions.vend3.client.rpc('crear_contrato', altaAjena);
    check(!negadoPorAutoridad(error),
      'F5.c B: analista vigente (vend3) REGISTRA para cliente ajeno — la autoridad ya no cierra por cartera',
      `code=${error?.code ?? 'sin'} msg=${error?.message ?? ''}`);
  }

  // NEGATIVOS sobre el MISMO nucleo (la pregunta unica sigue cerrando lo que debe):
  //  · un cliente (rol cliente): sin autoridad de ventas
  await expectExpectedFailure(
    'F5.c: un cliente NO registra ventas en el nucleo',
    sessions.clientBank.client.rpc('crear_contrato', altaAjena),
    ['42501'],
    /cliente no encontrado o fuera de tu cartera/i,
  );
  //  · un analista INACTIVO (perfil apagado -> es_analista/rol_crm caen a false)
  if (sessions.vendInactive) {
    await expectExpectedFailure(
      'F5.c: un analista INACTIVO NO registra ventas en el nucleo',
      sessions.vendInactive.client.rpc('crear_contrato', altaAjena),
      ['42501'],
      /cliente no encontrado o fuera de tu cartera/i,
    );
  }
  //  · anon (sin sesion): sin grant de EXECUTE sobre la RPC del portal
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-f5c'));
  await expectExplicitAuthorizationDenied(
    'F5.c: anon NO registra ventas en el nucleo',
    anon.rpc('crear_contrato', altaAjena),
    ['PGRST202', '42501'],
  );

  // NOTA: revocado -> 42501 ya queda cubierto por 'banca P04 * con membresia
  // revocada' (crear_contrato_con_cuenta_pdf_v2 con vend1 revocado — la puerta
  // interna quedo cerrada en F7.1). Cliente INACTIVO ->
  // 42501 se prueba en el postflight/ensayo de la migracion (flip de activo es
  // destructivo para el fixture del gate). La atribucion (analista_cierre =
  // registrador) la verifican la F3 y la auditoria estatica: aqui el alta muere
  // antes de escribir.
}

async function testMetricasConversionEquipo(sessions, seed) {
  console.log('\n— Ranking de conversion del equipo (decision #10 b2) —');

  // Ventana de 30 dias terminada HOY: el mismo periodo para todos los actores,
  // que es lo que hace comparable la paridad con gerencia.
  // OJO: en zona LIMA, no en la de la maquina. La RPC valida `p_hasta > v_hoy`
  // con v_hoy en America/Lima; de madrugada UTC el "hoy" local ya es manana alla
  // y la ventana entera se rechazaria con 22023 sin que nada este roto.
  const enLima = (fecha) => new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(fecha);
  const ahora = new Date();
  const P = {
    p_desde: enLima(new Date(ahora.getTime() - 29 * 24 * 60 * 60 * 1000)),
    p_hasta: enLima(ahora),
  };
  const ids = seed.profileIdByKey;
  const idsDe = (payload) => new Set((payload?.responsables ?? []).map((f) => f.vendedor_id));

  // ── A · permitidos y forma ────────────────────────────────────────────────
  const global = await positive(
    'gerencia obtiene el ranking de conversion global',
    sessions.gerencia.client.schema('crm').rpc('metricas_conversiones_equipo_fn', P),
  );
  if (global) {
    check(global.data?.version === 1, 'el payload de conversion del equipo declara version 1');
    check(global.data?.alcance === 'global', 'gerencia recibe alcance "global"');
    check(Array.isArray(global.data?.responsables),
      'responsables es SIEMPRE un array, nunca null');
    // La forma la fija el contrato: un campo de mas es superficie sin auditar.
    // F2.2 lo amplia de 4 a 7: cada responsable lleva ademas su cifra del
    // NUCLEO (la misma que HOY/Metas). La lista sigue siendo EXACTA, no un
    // «contiene»: relajarla mataria la defensa.
    const claves = [...new Set((global.data?.responsables ?? []).flatMap((f) => Object.keys(f)))].sort();
    check(claves.length === 0
      || JSON.stringify(claves) === JSON.stringify([
        'clientes', 'conversion_pct', 'leads',
        'nucleo_conversion_pct', 'nucleo_divisor', 'nucleo_numerador',
        'vendedor_id',
      ]),
      'cada responsable trae SOLO los 7 campos del contrato', claves.join(','));

    // El bloque `sondas` es superficie nueva: tambien se fija su forma.
    const sondas = Object.keys(global.data?.sondas ?? {}).sort();
    check(JSON.stringify(sondas) === JSON.stringify([
      'cierres_anulados', 'clientes_acreditados_a_otro_dueno', 'cuadra',
      'divisor_fuera_del_roster', 'numerador_fuera_del_roster',
      'paridad_filas', 'paridad_nucleo',
    ]), 'el bloque sondas del ranking trae SOLO su contrato', sondas.join(','));
    check(global.data?.sondas?.paridad_nucleo === null
      || Number(global.data?.sondas?.paridad_nucleo) === 0,
      'la sonda de paridad del ranking cuadra con el nucleo (o se declara no aplicable)',
      String(global.data?.sondas?.paridad_nucleo));
  }

  const directorio = await positive(
    'directorio (lector global) obtiene el ranking global',
    sessions.directorio.client.schema('crm').rpc('metricas_conversiones_equipo_fn', P),
  );
  if (directorio && global) {
    check(directorio.data?.alcance === 'global', 'el lector global recibe alcance "global"');
    check(JSON.stringify([...idsDe(directorio.data)].sort())
      === JSON.stringify([...idsDe(global.data)].sort()),
      'directorio ve el MISMO conjunto que gerencia');
  }

  const deSup1 = await positive(
    'sup1 obtiene el ranking de SU equipo',
    sessions.sup1.client.schema('crm').rpc('metricas_conversiones_equipo_fn', P),
  );
  const deSup2 = await positive(
    'sup2 obtiene el ranking de SU equipo',
    sessions.sup2.client.schema('crm').rpc('metricas_conversiones_equipo_fn', P),
  );
  const deNested = await positive(
    'sup1Nested obtiene el ranking de su rama',
    sessions.sup1Nested.client.schema('crm').rpc('metricas_conversiones_equipo_fn', P),
  );

  if (deSup1) {
    const suyos = idsDe(deSup1.data);
    check(deSup1.data?.alcance === 'equipo', 'el supervisor recibe alcance "equipo"');
    // vendNested cuelga de sup1Nested, que cuelga de sup1: prueba la RECURSION.
    check(suyos.has(ids.vendNested),
      'el subarbol es RECURSIVO: sup1 ve al analista de su supervisor anidado');
    check(!suyos.has(ids.vend3) && !suyos.has(ids.vend4),
      'sup1 NO ve a los analistas de sup2');
    check(!suyos.has(ids.sup1) && !suyos.has(ids.sup1Nested),
      'los supervisores no aparecen como filas del ranking');
    check(!suyos.has(ids.vendInactive),
      'el analista inactivo NO figura como responsable');
  }
  if (deSup2) {
    const suyos = idsDe(deSup2.data);
    check(suyos.has(ids.vend3) && suyos.has(ids.vend4), 'sup2 ve a sus dos analistas');
    check(!suyos.has(ids.vend1) && !suyos.has(ids.vend2) && !suyos.has(ids.vendNested),
      'sup2 NO ve el subarbol de sup1');
  }
  if (deNested) {
    const suyos = idsDe(deNested.data);
    check(!suyos.has(ids.vend1) && !suyos.has(ids.vend2),
      'sup1Nested no ve HACIA ARRIBA: solo su propia rama');
  }

  // Paridad con gerencia: el mismo analista y el mismo periodo dan los MISMOS
  // numeros mire quien mire. Es el invariante que justifica la RPC nueva.
  const globalPorId = new Map((global?.data?.responsables ?? []).map((f) => [f.vendedor_id, f]));
  if (deSup1) {
    const desviados = (deSup1.data?.responsables ?? []).filter((fila) => {
      const suyo = globalPorId.get(fila.vendedor_id);
      return suyo && !(suyo.leads === fila.leads
        && suyo.clientes === fila.clientes
        && suyo.conversion_pct === fila.conversion_pct
        // F2.2: las cifras del nucleo tambien tienen que coincidir, o el
        // supervisor y gerencia estarian viendo dos verdades del mismo dato.
        && suyo.nucleo_divisor === fila.nucleo_divisor
        && String(suyo.nucleo_numerador) === String(fila.nucleo_numerador)
        && String(suyo.nucleo_conversion_pct) === String(fila.nucleo_conversion_pct));
    });
    check(desviados.length === 0,
      'PARIDAD: sup1 ve los mismos numeros que gerencia para sus analistas',
      desviados.map((f) => f.vendedor_id).join(','));
  }

  // ── B · denegaciones DURAS (42501, jamas un payload de ceros) ──────────────
  for (const key of ['vend1', 'vend3', 'coordinador', 'vendInactive', 'clientBank']) {
    await expectExplicitAuthorizationDenied(
      `${key} no ejecuta metricas_conversiones_equipo_fn`,
      sessions[key].client.schema('crm').rpc('metricas_conversiones_equipo_fn', P),
    );
  }

  // El GATE va antes que la validacion de periodo: un rol denegado recibe 42501
  // aunque el periodo tambien sea invalido. Sin este par, el orden no esta probado.
  const periodoInvalido = { p_desde: P.p_desde, p_hasta: '2999-01-01' };
  await expectExplicitAuthorizationDenied(
    'un rol denegado recibe 42501 y NO 22023 con un periodo invalido',
    sessions.vend1.client.schema('crm').rpc('metricas_conversiones_equipo_fn', periodoInvalido),
  );
  await expectExpectedFailure(
    'gerencia recibe 22023 con p_hasta en el futuro',
    sessions.gerencia.client.schema('crm').rpc('metricas_conversiones_equipo_fn', periodoInvalido),
    ['22023'],
    /periodo invalido/i,
  );
  await expectExpectedFailure(
    'el supervisor entra en la MISMA rama de validacion que gerencia',
    sessions.sup1.client.schema('crm').rpc('metricas_conversiones_equipo_fn', periodoInvalido),
    ['22023'],
    /periodo invalido/i,
  );

  // ── C · NO VACUIDAD (leccion de RETOMAR-41) ───────────────────────────────
  if (global && deSup1 && deSup2) {
    const g = idsDe(global.data);
    const s1 = idsDe(deSup1.data);
    const s2 = idsDe(deSup2.data);
    check(g.size > s1.size && g.size > s2.size,
      'el scope del supervisor es ESTRICTAMENTE menor que el global',
      `global=${g.size} sup1=${s1.size} sup2=${s2.size}`);
    check([...s1].every((id) => !s2.has(id)),
      'los dos subarboles no se solapan (forma observable de "subarbol ajeno")');
    check(s1.size > 0 && s2.size > 0,
      'ambos supervisores reciben al menos un responsable: el recorte no es vacio');
  }
}

// ── Supervisión: reporte + borrador + devolución de derivaciones ─────────────
async function testReporteDerivacionesEquipo(sessions, seed) {
  console.log('\n— Reporte y reparto de derivaciones del equipo —');

  const reporteSup1 = await sessions.sup1.client.schema('crm')
    .rpc('reporte_derivaciones_equipo_fn');
  if (check(!reporteSup1.error, 'supervisor consulta el reporte con el rango Ayer por defecto', errorText(reporteSup1.error))) {
    const payload = reporteSup1.data;
    check(payload?.version === 1, 'reporte de derivaciones conserva contrato V1');
    check(
      payload?.periodo?.desde === payload?.periodo?.hasta && payload?.periodo?.dias === 1,
      'el rango por defecto es exactamente un día',
      JSON.stringify(payload?.periodo),
    );

    const ids = (payload?.asesores ?? []).map((fila) => fila.asesor_id).sort();
    const directos = [seed.profileIdByKey.vend1, seed.profileIdByKey.vend2].sort();
    check(
      JSON.stringify(ids) === JSON.stringify(directos),
      'SUPERVISOR UNO recibe solo sus analistas directos activos',
      JSON.stringify(ids),
    );
    check(
      !(payload?.asesores ?? []).some((fila) => fila.asesor_id === seed.profileIdByKey.vendNested),
      'el analista del supervisor anidado no se mezcla en las cards directas',
    );

    const prohibidas = new Set(['telefono', 'correo', 'dni', 'notas', 'detalle', 'metadata']);
    const movimientoConPii = (payload?.movimientos_hoy ?? []).find((movimiento) =>
      Object.keys(movimiento).some((clave) => prohibidas.has(clave)));
    check(!movimientoConPii, 'los movimientos de hoy no exponen contacto, notas ni metadata');
  }

  const reporteSup2 = await sessions.sup2.client.schema('crm')
    .rpc('reporte_derivaciones_equipo_fn');
  if (check(!reporteSup2.error, 'el segundo supervisor consulta su propio reporte', errorText(reporteSup2.error))) {
    const ids = (reporteSup2.data?.asesores ?? []).map((fila) => fila.asesor_id).sort();
    const directos = [seed.profileIdByKey.vend3, seed.profileIdByKey.vend4].sort();
    check(
      JSON.stringify(ids) === JSON.stringify(directos),
      'el segundo supervisor no recibe analistas del primero',
      JSON.stringify(ids),
    );
  }

  const reporteAnidado = await sessions.sup1Nested.client.schema('crm')
    .rpc('reporte_derivaciones_equipo_fn');
  if (check(!reporteAnidado.error, 'el supervisor anidado consulta su equipo directo', errorText(reporteAnidado.error))) {
    check(
      JSON.stringify((reporteAnidado.data?.asesores ?? []).map((fila) => fila.asesor_id))
        === JSON.stringify([seed.profileIdByKey.vendNested]),
      'el supervisor anidado recibe únicamente a su analista directo',
    );
  }

  for (const key of ['vend1', 'coordinador', 'gerencia', 'directorio', 'vendInactive', 'clientBank']) {
    await expectExplicitAuthorizationDenied(
      `${key} no consulta el reporte exclusivo de Supervisión`,
      sessions[key].client.schema('crm').rpc('reporte_derivaciones_equipo_fn'),
      ['42501'],
    );
  }

  const anon = createClient(
    SUPABASE_URL,
    ANON_KEY,
    clientOptions(`crm-derivaciones-anon-${randomUUID()}`),
  );
  await expectExplicitAuthorizationDenied(
    'anon no consulta el reporte de derivaciones',
    anon.schema('crm').rpc('reporte_derivaciones_equipo_fn'),
    ['401', '42501', 'PGRST301'],
  );

  await expectBlockedMutation(
    'el supervisor no deriva un lead a un analista de otro equipo',
    sessions.sup1.client.schema('crm').rpc('derivar_leads_equipo_fn', {
      p_lead_ids: [seed.leadByName.get(LEAD_BY_KEY.luis.name).id],
      p_asesor_ids: [seed.profileIdByKey.vend3],
    }),
    ['42501'],
  );
  await expectBlockedMutation(
    'un borrador no puede repetir el mismo lead',
    sessions.sup1.client.schema('crm').rpc('derivar_leads_equipo_fn', {
      p_lead_ids: [
        seed.leadByName.get(LEAD_BY_KEY.luis.name).id,
        seed.leadByName.get(LEAD_BY_KEY.luis.name).id,
      ],
      p_asesor_ids: [seed.profileIdByKey.vend2, seed.profileIdByKey.vend2],
    }),
    ['22023'],
  );
  await expectBlockedMutation(
    'no se devuelve un lead que no es una derivación vigente de hoy',
    sessions.sup1.client.schema('crm').rpc('revertir_derivacion_equipo_fn', {
      p_lead_id: seed.leadByName.get(LEAD_BY_KEY.luis.name).id,
    }),
    ['P0001'],
  );
  await expectBlockedMutation(
    'el reporte rechaza rangos invertidos',
    sessions.sup1.client.schema('crm').rpc('reporte_derivaciones_equipo_fn', {
      p_desde: '2026-08-20',
      p_hasta: '2026-08-19',
    }),
    ['22023'],
  );
  await expectBlockedMutation(
    'el reporte rechaza fechas futuras',
    sessions.sup1.client.schema('crm').rpc('reporte_derivaciones_equipo_fn', {
      p_desde: '2100-01-01',
      p_hasta: '2100-01-01',
    }),
    ['22023'],
  );
}

// ── C1: reparto de la cola global por el rol `coordinador` ────────────────────
// Tres capas: (A) aislamiento del rol nuevo — incluidas las superficies que se
// abren al dejar de ser rol_crm NULL; (B) control de acceso de las 3 RPC;
// (C) reglas de negocio de repartir_lead con oraculos de ESTADO leidos con
// service_role (una mutacion que "no revienta" no prueba que no haya mutado).
async function testReparto(sessions, seed) {
  console.log('\n— Reparto de la cola global (C1: rol coordinador) —');
  const coordinador = sessions.coordinador.client;
  const gerencia = sessions.gerencia.client;
  const sup1Id = seed.profileIdByKey.sup1;
  const sup2Id = seed.profileIdByKey.sup2;
  const vend1Id = seed.profileIdByKey.vend1;
  const coordId = sessions.coordinador.user.id;

  // (A) Aislamiento: el coordinador NO gana acceso a las superficies gateadas
  // por "es miembro del CRM". Sin esto el gate pasaria verde con PII abierta.
  await expectHidden(
    'coordinador no ve clientes_basicos (PII del portal)',
    coordinador.schema('crm').from('clientes_basicos').select('id'),
  );
  await expectHidden(
    'coordinador no ve los contratos de cartera (capital + nombre de cliente)',
    coordinador.schema('crm').from('contratos_cartera').select('id'),
  );
  await expectBlockedMutation(
    'coordinador no puede sondear DNIs (existe_cliente_por_dni)',
    coordinador.schema('crm').rpc('existe_cliente_por_dni', { p_dni: '99999999' }),
    ['42501'],
  );
  await expectBlockedMutation(
    'coordinador no lee las metricas de agenda del equipo',
    coordinador.schema('crm').rpc('metricas_agenda_fn', {
      p_desde: '2026-07-01',
      p_hasta: '2026-07-15',
    }),
    ['42501'],
  );
  // Las RPC expuestas enrutan por private.metricas_distribucion_leads_autorizada
  // (gate gerencia|lector global). No las toca C1: se aseveran para dejar
  // constancia de que el rol nuevo tampoco entra por ahi. La v3 (F2.3b) entra
  // al MISMO bucle: comparte despachador y gate con las otras dos.
  for (const fn of [
    'metricas_distribucion_leads_fn',
    'metricas_distribucion_leads_v2_fn',
    'metricas_distribucion_leads_v3_fn',
  ]) {
    await expectBlockedMutation(
      `coordinador no lee las metricas de distribucion (${fn})`,
      coordinador.schema('crm').rpc(fn, { p_desde: '2026-07-01', p_hasta: '2026-07-15' }),
      ['42501'],
    );
  }
  // F2.3b: la puerta v3 tiene grant a `authenticated`, asi que el gate del
  // despachador es LO UNICO que separa a un analista de las metricas de toda
  // la casa. Se prueba con los cuatro roles: dos fuera, dos dentro.
  for (const [rol, cliente] of [
    ['vendedor', sessions.vend1.client],
    ['supervisor', sessions.sup1.client],
  ]) {
    await expectBlockedMutation(
      `${rol} no lee la distribucion v3 (solo gerencia o lector global)`,
      cliente.schema('crm').rpc('metricas_distribucion_leads_v3_fn', {
        p_desde: '2026-07-01', p_hasta: '2026-07-15',
      }),
      ['42501'],
    );
  }
  for (const [rol, cliente] of [
    ['gerencia', gerencia],
    ['directorio (lector global)', sessions.directorio.client],
  ]) {
    const v3 = await positive(
      `${rol} lee la distribucion v3 con las claves nuevas`,
      cliente.schema('crm').rpc('metricas_distribucion_leads_v3_fn', {
        p_desde: '2026-07-01', p_hasta: '2026-07-15',
      }),
    );
    if (v3) {
      const payload = v3.data;
      const sondasOk = payload && typeof payload === 'object'
        && payload.sondas && typeof payload.sondas === 'object'
        && payload.resumen && typeof payload.resumen.conversion === 'object';
      if (!sondasOk) {
        fail(`${rol}: la v3 no trae sondas/resumen.conversion`);
      } else if ('sla_global_contactos' in payload.resumen
        || 'sla_global_en_24h' in payload.resumen) {
        fail(`${rol}: la puerta v3 transporta SLA y no debia`);
      } else if (payload.version !== 3) {
        fail(`${rol}: la v3 se rotula version ${payload.version}`);
      } else {
        pass(`${rol}: v3 con sondas + resumen.conversion, sin SLA, version 3`);
      }
    }
  }
  // Las 4 RPC de metricas comerciales recortan por vendedor_ids_visibles (∅ para
  // el coordinador) o exigen gerencia/lector: ninguna le devuelve filas.
  for (const [fn, args] of [
    ['metricas_capital_mes_fn', { p_meses: 12 }],
    ['metricas_pagos_mes_fn', { p_meses: 12 }],
    ['metricas_vencimientos_fn', { p_dias: 90 }],
  ]) {
    await expectHidden(
      `coordinador no obtiene filas de ${fn}`,
      coordinador.schema('crm').rpc(fn, args),
    );
  }

  // F7.1: metricas_altas_analista_fn quedo CERRADA (observacion, demolible
  // 14/09) — para TODO rol la respuesta es denegacion, ya no filas vacias.
  // 🪦 F7 Ola 2b (14/09): cuando se demuela, PostgREST pasa de 42501 a PGRST202
  //    «no existe la funcion». Las dos son «el coordinador no la alcanza».
  await expectExplicitAuthorizationDenied(
    'coordinador no alcanza metricas_altas_analista_fn (cerrada F7.1 o demolida en la Ola 2b)',
    coordinador.schema('crm').rpc('metricas_altas_analista_fn', { p_meses: 12 }),
    ['PGRST202'],
  );

  // convertir_lead tiene allowlist propia ('vendedor','supervisor'): el rol
  // nuevo NO puede dar de alta clientes. Se asevera para blindar ese candado.
  await expectBlockedMutation(
    'coordinador no puede convertir un lead en cliente',
    coordinador.schema('crm').rpc('convertir_lead', {
      p_lead_id: seed.leadByName.get('JUAN PEREZ DEMO').id,
      p_perfil_id: seed.profileIdByKey[BANK_CLIENT.key],
    }),
    ['P0001'],
  );
  await expectBlockedMutation(
    'coordinador no puede cerrar tareas ajenas por la RPC',
    coordinador.schema('crm').rpc('cerrar_tarea', {
      p_tarea_id: TAREA_BY_KEY.llamadaJuan.id,
      p_estado: 'completada',
      p_resultado_tipo: 'llamada_realizada',
    }),
    ['P0001'],
  );
  await expectBlockedMutation(
    'coordinador no puede crear tareas de agenda',
    coordinador.schema('crm').from('tareas').insert({
      creado_por: coordId,
      lead_id: seed.leadByName.get('JUAN PEREZ DEMO').id,
      tipo: 'tarea',
      titulo: 'REPARTO TAREA PROHIBIDA TRANSIENT',
      vence_en: '2026-08-10T15:00:00Z',
    }).select('id'),
    ['P0001'],
  );

  // leads_insert no niega al coordinador por policy: lo corta el guard de
  // tenencia. Se asevera para detectar una regresion futura del trigger.
  await expectBlockedMutation(
    'coordinador no se auto-inserta un lead (analista = él mismo)',
    coordinador.schema('crm').from('leads').insert({
      etapa: 'nuevo', moneda: 'PEN', monto_estimado: 1000, origen: 'otro',
      nombre_completo: 'REPARTO AUTOINSERT TRANSIENT', telefono: '999000101',
      vendedor_id: coordId, asignado_supervisor_id: null,
    }).select('id'),
    ['P0001'],
  );
  await expectBlockedMutation(
    'coordinador no inserta un lead directo en la cola global',
    coordinador.schema('crm').from('leads').insert({
      etapa: 'nuevo', moneda: 'PEN', monto_estimado: 1000, origen: 'otro',
      nombre_completo: 'REPARTO AUTOINSERT COLA TRANSIENT', telefono: '999000102',
      vendedor_id: null, asignado_supervisor_id: null,
    }).select('id'),
    ['P0001'],
  );

  // (B) Control de acceso de las 3 RPC nuevas: solo coordinador y gerencia.
  await positive(
    'coordinador lista la cola por repartir',
    coordinador.schema('crm').rpc('leads_por_repartir'),
  );
  await positive(
    'gerencia tambien lista la cola por repartir',
    gerencia.schema('crm').rpc('leads_por_repartir'),
  );
  await positive(
    'coordinador lista los supervisores destino',
    coordinador.schema('crm').rpc('supervisores_para_reparto'),
  );
  for (const key of ['vend1', 'sup1', 'directorio']) {
    await expectBlockedMutation(
      `${key} no puede ver la cola por repartir`,
      sessions[key].client.schema('crm').rpc('leads_por_repartir'),
      ['42501'],
    );
    await expectBlockedMutation(
      `${key} no puede listar los supervisores de reparto`,
      sessions[key].client.schema('crm').rpc('supervisores_para_reparto'),
      ['42501'],
    );
    await expectBlockedMutation(
      `${key} no puede repartir un lead`,
      sessions[key].client.schema('crm').rpc('repartir_lead', {
        p_lead: TRANSIENT_IDS.repartoLeadOk,
        p_supervisor: sup1Id,
      }),
      ['42501'],
    );
  }

  // Semillas de la cola global (service_role: entrar ambos-null sin disparar la
  // rama "solo gerencia deja el lead en cola" del guard de tenencia).
  // no_contactar va EXPLICITO en todas las filas: en un insert por lotes,
  // PostgREST normaliza las columnas del lote y las filas que lo omiten
  // viajarian con null explicito (violando el NOT NULL, sin usar el default).
  const colaComun = {
    activo: true, asignado_supervisor_id: null, vendedor_id: null,
    creado_por: sup1Id, etapa: 'nuevo', moneda: 'PEN', origen: 'otro',
    no_contactar: false,
  };
  await requireAdmin(
    'sembrar la cola global de reparto',
    admin.schema('crm').from('leads').insert([
      {
        ...colaComun, id: TRANSIENT_IDS.repartoLeadOk, monto_estimado: 12000,
        nombre_completo: 'REPARTO CONTACTABLE TRANSIENT', telefono: '999000110',
      },
      {
        ...colaComun, id: TRANSIENT_IDS.repartoLeadNoContactar, monto_estimado: 8000,
        nombre_completo: 'REPARTO NO INSISTA TRANSIENT', telefono: '999000111',
        no_contactar: true,
      },
      {
        ...colaComun, id: TRANSIENT_IDS.repartoLeadCarrera, monto_estimado: 20000,
        moneda: 'USD', nombre_completo: 'REPARTO CARRERA TRANSIENT', telefono: '999000112',
      },
      {
        // Desde 2026-08-08 (trigger de destino efectivo, metas/SLA
        // versionados) un lead EN COLA no puede tener tarea pendiente: el
        // espejo trg_tareas_00_before_insert copia la tenencia del lead y el
        // destino nulo muere en 23514 — para cualquier escritor, incluido
        // service_role. El fixture nace entonces en la BANDEJA de sup2 con su
        // tarea, y mas abajo se clava el conflicto con el re-encolado.
        ...colaComun, id: TRANSIENT_IDS.repartoLeadReencolado, monto_estimado: 5000,
        nombre_completo: 'REPARTO REENCOLADO TRANSIENT', telefono: '999000113',
        asignado_supervisor_id: seed.profileIdByKey.sup2,
        // etapa REUNION_AGENDADA a proposito (2026-08-09): es el caso REAL que
        // motivo la migracion 20260809024942 — «un lead con cita agendada
        // devuelto a la cola». Con el fixture anterior (etapa 'nuevo' + tipo
        // 'tarea') el retroceso de etapa no se ejercitaba NUNCA, y el gate
        // habria dado verde sobre media correccion.
        //
        // Esta es la UNICA de las cuatro semillas que fuerza la etapa, y no por
        // comodidad: prueba la rama 'nuevo', que exige CERO contacto en el
        // ciclo — justo lo que el trigger de ascenso pide para subir por si
        // solo. El estado es alcanzable en produccion por la via que importa:
        // un lead reciclado cuyo contacto quedo en un ciclo anterior.
        etapa: 'reunion_agendada',
      },
      // Las otras TRES ramas del retroceso. Con una sola semilla el gate solo
      // clavaba el caso 'nuevo' y daba por buena una regla de la que probaba un
      // cuarto.
      {
        ...colaComun, id: TRANSIENT_IDS.repartoLeadReencoladoContactado,
        monto_estimado: 5500, nombre_completo: 'REPARTO REENCOLADO CONTACTADO TRANSIENT',
        telefono: '999000114', asignado_supervisor_id: seed.profileIdByKey.sup2,
      },
      {
        ...colaComun, id: TRANSIENT_IDS.repartoLeadReunionHecha,
        monto_estimado: 6000, nombre_completo: 'REPARTO REUNION YA HECHA TRANSIENT',
        telefono: '999000115', asignado_supervisor_id: seed.profileIdByKey.sup2,
      },
      {
        ...colaComun, id: TRANSIENT_IDS.repartoLeadBandeja,
        monto_estimado: 6500, nombre_completo: 'REPARTO NO ES REENCOLADO TRANSIENT',
        telefono: '999000116', asignado_supervisor_id: seed.profileIdByKey.sup2,
      },
    ]),
  );
  // La tarea hereda la bandeja del lead por el espejo (sup2): destino efectivo.
  // Es una REUNION, no una tarea suelta: solo asi el lead sostiene de verdad la
  // etapa reunion_agendada y el retroceso tiene algo que corregir.
  await requireAdmin(
    'sembrar la reunion pendiente del lead en bandeja',
    admin.schema('crm').from('tareas').insert({
      creado_por: sup1Id,
      // El enlace virtual ahora es opcional, pero este fixture conserva uno
      // para seguir cubriendo la rama de lectura y exportación de URLs.
      enlace_reunion: 'https://meet.example.com/reencolado-transient',
      id: TRANSIENT_IDS.repartoTareaReencolada,
      lead_id: TRANSIENT_IDS.repartoLeadReencolado,
      modalidad_reunion: 'virtual',
      tipo: 'reunion',
      titulo: 'REPARTO REUNION REENCOLADA TRANSIENT',
      vence_en: '2026-08-05T15:00:00Z',
    }),
  );
  // Semillas de las otras tres ramas. Aqui la etapa NO se fuerza: se construye
  // el estado por el CAMINO REAL —contacto y despues reunion— y el trigger de
  // ascenso la sube solo. Dos condiciones suyas mandan el orden y las fechas:
  // exige contacto previo registrado, y exige `vence_en > now()` («agendar en
  // el pasado no es agendar»). Por eso las actividades van ANTES que las tareas
  // y las citas son futuras.
  await requireAdmin(
    'sembrar el contacto previo de las semillas del retroceso',
    admin.schema('crm').from('actividades').insert([
      {
        creado_por: seed.profileIdByKey.sup2,
        detalle: 'REPARTO REENCOLADO CONTACTO TRANSIENT',
        lead_id: TRANSIENT_IDS.repartoLeadReencoladoContactado,
        tipo: 'llamada_realizada',
      },
      // La reunion de ESTE lead YA OCURRIO: su etapa se sostiene en un hecho
      // verdadero y el retroceso debe abstenerse.
      {
        creado_por: seed.profileIdByKey.sup2,
        detalle: 'REPARTO REUNION HECHA TRANSIENT',
        lead_id: TRANSIENT_IDS.repartoLeadReunionHecha,
        tipo: 'reunion_realizada',
      },
      {
        creado_por: seed.profileIdByKey.sup2,
        detalle: 'REPARTO BANDEJA CONTACTO TRANSIENT',
        lead_id: TRANSIENT_IDS.repartoLeadBandeja,
        tipo: 'llamada_realizada',
      },
    ]),
  );
  await requireAdmin(
    'agendar las reuniones que suben las tres semillas a reunion_agendada',
    admin.schema('crm').from('tareas').insert([
      {
        creado_por: sup1Id, id: TRANSIENT_IDS.repartoTareaReencoladaContactado,
        lead_id: TRANSIENT_IDS.repartoLeadReencoladoContactado, tipo: 'reunion',
        titulo: 'REPARTO REUNION CONTACTADO TRANSIENT', vence_en: '2027-01-05T16:00:00Z',
      },
      {
        creado_por: sup1Id, id: TRANSIENT_IDS.repartoTareaReunionHecha,
        lead_id: TRANSIENT_IDS.repartoLeadReunionHecha, tipo: 'reunion',
        titulo: 'REPARTO REUNION HECHA TRANSIENT', vence_en: '2027-01-05T17:00:00Z',
      },
      {
        creado_por: sup1Id, id: TRANSIENT_IDS.repartoTareaBandeja,
        lead_id: TRANSIENT_IDS.repartoLeadBandeja, tipo: 'reunion',
        titulo: 'REPARTO REUNION BANDEJA TRANSIENT', vence_en: '2027-01-05T18:00:00Z',
      },
    ]),
  );

  // La cola que ve el coordinador: proyeccion util y sin PII de contacto.
  const cola = await positive(
    'coordinador relee la cola con las semillas',
    coordinador.schema('crm').rpc('leads_por_repartir'),
  );
  if (cola) {
    const filas = cola.data ?? [];
    const ids = new Set(filas.map((fila) => fila.id));
    check(ids.has(TRANSIENT_IDS.repartoLeadOk),
      'la cola incluye el lead contactable');
    check(!ids.has(TRANSIENT_IDS.repartoLeadNoContactar),
      'no_contactar: NUNCA aparece listado en leads_por_repartir (Ley 29571)');
    const muestra = filas[0] ?? {};
    check(!('telefono' in muestra) && !('correo' in muestra) && !('dni' in muestra),
      'la cola no proyecta PII de contacto (telefono/correo/dni)');
  }

  // (C) Reglas de negocio.
  await positive(
    'coordinador reparte el lead contactable a la bandeja de sup1',
    coordinador.schema('crm').rpc('repartir_lead', {
      p_lead: TRANSIENT_IDS.repartoLeadOk,
      p_supervisor: sup1Id,
    }),
  );
  const repartido = await requireAdmin(
    'releer el lead repartido con service_role',
    admin.schema('crm').from('leads')
      .select('asignado_supervisor_id, vendedor_id')
      .eq('id', TRANSIENT_IDS.repartoLeadOk).single(),
  );
  check(repartido.data?.asignado_supervisor_id === sup1Id && repartido.data?.vendedor_id === null,
    'el lead quedo en la bandeja del supervisor, con vendedor_id null (tenencia exclusiva)',
    JSON.stringify(repartido.data));
  // La actividad la escribe el TRIGGER, acreditando al coordinador como autor.
  const traza = await requireAdmin(
    'releer la actividad de entrada a bandeja',
    admin.schema('crm').from('actividades')
      .select('tipo, creado_por')
      .eq('lead_id', TRANSIENT_IDS.repartoLeadOk),
  );
  check((traza.data ?? []).some((fila) => fila.creado_por === coordId),
    'la traza del movimiento acredita al coordinador como autor');

  // CANDADO LEGAL: codigo EXACTO P0429. No se usa expectBlockedMutation porque
  // auto-aprueba cualquier 42501 — el test no podria fallar si alguien cambiara
  // el veto legal por un error de autorizacion.
  const legal = await coordinador.schema('crm').rpc('repartir_lead', {
    p_lead: TRANSIENT_IDS.repartoLeadNoContactar,
    p_supervisor: sup1Id,
  });
  check(!!legal.error && String(legal.error.code) === 'P0429',
    'no_contactar: bloqueado con el codigo LEGAL P0429 (no un 42501 de permisos)',
    errorText(legal.error));
  const intacto = await requireAdmin(
    'releer el lead No Insista con service_role',
    admin.schema('crm').from('leads')
      .select('asignado_supervisor_id, vendedor_id')
      .eq('id', TRANSIENT_IDS.repartoLeadNoContactar).single(),
  );
  check(intacto.data?.asignado_supervisor_id === null && intacto.data?.vendedor_id === null,
    'no_contactar: el lead permanecio en la cola global, sin bandeja');

  // Destino invalido y lead fuera de la cola.
  await expectBlockedMutation(
    'no se puede repartir a un destino que no es supervisor',
    coordinador.schema('crm').rpc('repartir_lead', {
      p_lead: TRANSIENT_IDS.repartoLeadReencolado,
      p_supervisor: vend1Id,
    }),
    ['22023'],
  );
  await expectBlockedMutation(
    'no se puede repartir un lead que ya tiene dueno',
    coordinador.schema('crm').rpc('repartir_lead', {
      p_lead: TRANSIENT_IDS.repartoLeadOk,
      p_supervisor: sup2Id,
    }),
    ['P0002'],
  );

  // CARRERA REAL: dos sesiones disparan sobre el MISMO lead en paralelo.
  const [a, b] = await Promise.allSettled([
    coordinador.schema('crm').rpc('repartir_lead', {
      p_lead: TRANSIENT_IDS.repartoLeadCarrera, p_supervisor: sup1Id,
    }),
    gerencia.schema('crm').rpc('repartir_lead', {
      p_lead: TRANSIENT_IDS.repartoLeadCarrera, p_supervisor: sup2Id,
    }),
  ]);
  const resueltas = [a, b].filter((r) => r.status === 'fulfilled');
  const ganadores = resueltas.filter((r) => !r.value.error);
  const perdedores = resueltas.filter((r) => r.value.error);
  check(ganadores.length === 1 && perdedores.length === 1,
    'carrera de reparto: exactamente uno gana',
    `ok=${ganadores.length} err=${perdedores.length}`);
  if (perdedores.length === 1) {
    const codigo = String(perdedores[0].value.error.code);
    check(['P0002', '40001'].includes(codigo),
      'carrera: el perdedor recibe P0002 (o 40001 si el aislamiento es mayor)',
      codigo);
  }
  const trasCarrera = await requireAdmin(
    'releer el lead en disputa con service_role',
    admin.schema('crm').from('leads')
      .select('asignado_supervisor_id, vendedor_id')
      .eq('id', TRANSIENT_IDS.repartoLeadCarrera).single(),
  );
  check([sup1Id, sup2Id].includes(trasCarrera.data?.asignado_supervisor_id)
    && trasCarrera.data?.vendedor_id === null,
    'carrera: quedo UN solo supervisor asignado y ningun analista');

  // RE-ENCOLADO CON TAREA PENDIENTE — resuelto el 2026-08-09 (opcion B de
  // Miguel, migracion 20260809024942). Historia de esta sonda, porque cambio de
  // signo dos veces y conviene que el proximo que la lea no la "arregle" al
  // reves:
  //   · Escenario original: «un lead devuelto a la cola conserva su tarea y al
  //     repartirlo la tarea lo sigue».
  //   · 2026-08-08: quedo INALCANZABLE. Re-encolar disparaba el sync (la tarea
  //     espejaba tenencia nula) y el trigger de destino efectivo abortaba el
  //     update entero con 23514. La sonda se reescribio para CLAVAR ese
  //     bloqueo, con la nota de que un ciclo futuro que lo corrigiera la
  //     pondria en rojo. Eso es exactamente lo que paso.
  //   · 2026-08-09: el sync CANCELA por sistema las tareas pendientes cuando el
  //     lead vuelve a la cola. El re-encolado deja de fallar.
  // La cobertura de «la tarea sigue al lead» en asignaciones vivas (que es lo
  // que el escenario original queria probar) vive en testTareaFollowsLead.
  await positive(
    're-encolar un lead con tarea pendiente ya no falla',
    admin.schema('crm').from('leads')
      .update({ vendedor_id: null, asignado_supervisor_id: null })
      .eq('id', TRANSIENT_IDS.repartoLeadReencolado)
      .select('id'),
  );
  const leadReencolado = await requireAdmin(
    'releer el lead tras el re-encolado',
    admin.schema('crm').from('leads')
      .select('vendedor_id, asignado_supervisor_id, etapa')
      .eq('id', TRANSIENT_IDS.repartoLeadReencolado).single(),
  );
  check(leadReencolado.data?.vendedor_id === null
    && leadReencolado.data?.asignado_supervisor_id === null,
    're-encolado: el lead quedo sin dueno, listo para la cola global',
    JSON.stringify(leadReencolado.data));
  // LA MITAD QUE FALTABA. Cancelar la reunion sin bajar la etapa devolveria el
  // lead a la cola AFIRMANDO tener una cita que ya no existe: el coordinador lo
  // repartiria y el nuevo dueno heredaria un hecho falso, el SLA usaria la
  // ventana de reunion_agendada y el embudo lo contaria como reunion viva. El
  // fixture no registra contacto en el ciclo, asi que la regla —la misma de
  // anular reunion— lo devuelve a 'nuevo'.
  check(leadReencolado.data?.etapa === 'nuevo',
    're-encolado: la etapa retrocedio y el lead ya no sostiene una reunion inexistente',
    JSON.stringify(leadReencolado.data));
  const tarea = await requireAdmin(
    'releer la tarea del lead re-encolado',
    admin.schema('crm').from('tareas')
      .select('asignado_supervisor_id, vendedor_id, estado, cancelada_por, cancelada_por_id')
      .eq('id', TRANSIENT_IDS.repartoTareaReencolada).single(),
  );
  // La tarea se cancela pero CONSERVA su bandeja anterior: es historia, no un
  // destino vivo. Y el sello debe decir 'sistema' sin actor humano, para que la
  // auditoria no le impute a nadie una cancelacion que hizo un trigger.
  check(tarea.data?.estado === 'cancelada'
    && tarea.data?.cancelada_por === 'sistema'
    && tarea.data?.cancelada_por_id === null
    && tarea.data?.asignado_supervisor_id === seed.profileIdByKey.sup2,
    're-encolado: la tarea quedo cancelada POR SISTEMA, conservando su bandeja como historia',
    JSON.stringify(tarea.data));
  // El retroceso lo hace un TRIGGER, no la persona que re-encolo: la actividad
  // debe venir marcada como automatica. Sin esta sonda, un cambio futuro podria
  // imputarle a quien devolvio el lead un movimiento que no decidio — que es el
  // motivo entero de existir del flag crm.avance_auto.
  const trazaRetroceso = await requireAdmin(
    'releer la actividad de cambio de etapa del re-encolado',
    admin.schema('crm').from('actividades')
      .select('tipo, metadata')
      .eq('lead_id', TRANSIENT_IDS.repartoLeadReencolado)
      .eq('tipo', 'cambio_etapa'),
  );
  check((trazaRetroceso.data ?? []).some((fila) => fila.metadata?.automatico === true),
    're-encolado: el retroceso quedo sellado como AUTOMATICO, no imputado a la persona',
    JSON.stringify(trazaRetroceso.data));

  // RAMA 'contactado': mismo re-encolado, pero con contacto registrado en el
  // ciclo. La regla de anular reunion no manda todo a 'nuevo'; distingue.
  const contactadoAntes = await requireAdmin(
    'releer la etapa del lead con contacto antes de re-encolar',
    admin.schema('crm').from('leads').select('etapa')
      .eq('id', TRANSIENT_IDS.repartoLeadReencoladoContactado).single(),
  );
  check(contactadoAntes.data?.etapa === 'reunion_agendada',
    'la semilla con contacto llego de verdad a reunion_agendada (si no, la sonda no probaria nada)',
    JSON.stringify(contactadoAntes.data));
  await positive(
    're-encolar el lead que SI tuvo contacto',
    admin.schema('crm').from('leads')
      .update({ vendedor_id: null, asignado_supervisor_id: null })
      .eq('id', TRANSIENT_IDS.repartoLeadReencoladoContactado)
      .select('id'),
  );
  const contactado = await requireAdmin(
    'releer el lead con contacto tras el re-encolado',
    admin.schema('crm').from('leads').select('etapa')
      .eq('id', TRANSIENT_IDS.repartoLeadReencoladoContactado).single(),
  );
  check(contactado.data?.etapa === 'contactado',
    're-encolado: con contacto en el ciclo la etapa cae a contactado, NO a nuevo',
    JSON.stringify(contactado.data));

  // RAMA NO-RETROCESO: si la reunion YA se realizo, la etapa se sostiene en un
  // hecho verdadero y bajarla borraria trabajo hecho. Es el guard mas caro de la
  // doctrina de 20260726151751 y hasta hoy nada lo clavaba.
  const hechaAntes = await requireAdmin(
    'releer la etapa del lead con reunion realizada antes de re-encolar',
    admin.schema('crm').from('leads').select('etapa')
      .eq('id', TRANSIENT_IDS.repartoLeadReunionHecha).single(),
  );
  check(hechaAntes.data?.etapa === 'reunion_agendada',
    'la semilla de reunion realizada llego de verdad a reunion_agendada',
    JSON.stringify(hechaAntes.data));
  await positive(
    're-encolar un lead cuya reunion YA se realizo',
    admin.schema('crm').from('leads')
      .update({ vendedor_id: null, asignado_supervisor_id: null })
      .eq('id', TRANSIENT_IDS.repartoLeadReunionHecha)
      .select('id'),
  );
  const reunionHecha = await requireAdmin(
    'releer el lead de reunion realizada tras el re-encolado',
    admin.schema('crm').from('leads').select('etapa')
      .eq('id', TRANSIENT_IDS.repartoLeadReunionHecha).single(),
  );
  check(reunionHecha.data?.etapa === 'reunion_agendada',
    're-encolado: con la reunion YA realizada la etapa NO retrocede (el hecho es verdadero)',
    JSON.stringify(reunionHecha.data));

  // NO-REGRESION DEL ALCANCE: bajar de la bandeja a un analista NO es un
  // re-encolado. La tarea debe SEGUIR viva y espejar al nuevo dueno, y la etapa
  // no se toca. Sin esto, un futuro "simplifiquemos la condicion" mataria citas
  // vivas en cada reasignacion.
  const bandejaAntes = await requireAdmin(
    'releer la etapa del lead de bandeja antes de reasignarlo',
    admin.schema('crm').from('leads').select('etapa')
      .eq('id', TRANSIENT_IDS.repartoLeadBandeja).single(),
  );
  check(bandejaAntes.data?.etapa === 'reunion_agendada',
    'la semilla de la no-regresion llego de verdad a reunion_agendada',
    JSON.stringify(bandejaAntes.data));
  await positive(
    'bajar el lead de la bandeja a un analista (NO es re-encolado)',
    admin.schema('crm').from('leads')
      .update({ vendedor_id: seed.profileIdByKey.vend3, asignado_supervisor_id: null })
      .eq('id', TRANSIENT_IDS.repartoLeadBandeja)
      .select('id'),
  );
  const bandeja = await requireAdmin(
    'releer el lead bajado a analista',
    admin.schema('crm').from('leads').select('etapa, vendedor_id')
      .eq('id', TRANSIENT_IDS.repartoLeadBandeja).single(),
  );
  const tareaBandeja = await requireAdmin(
    'releer la reunion del lead bajado a analista',
    admin.schema('crm').from('tareas')
      .select('estado, vendedor_id, asignado_supervisor_id')
      .eq('id', TRANSIENT_IDS.repartoTareaBandeja).single(),
  );
  check(bandeja.data?.etapa === 'reunion_agendada'
    && bandeja.data?.vendedor_id === seed.profileIdByKey.vend3,
    'reasignar NO retrocede la etapa: solo el re-encolado real la mueve',
    JSON.stringify(bandeja.data));
  check(tareaBandeja.data?.estado === 'pendiente'
    && tareaBandeja.data?.vendedor_id === seed.profileIdByKey.vend3
    && tareaBandeja.data?.asignado_supervisor_id === null,
    'reasignar NO cancela la reunion: la tarea sigue viva y espeja al nuevo dueno',
    JSON.stringify(tareaBandeja.data));
}

// ── C1-bis: descarte de la cola global (el codigo marca, el coordinador cierra) ─
// Complementa al oraculo test-descarte.sql: aqui se prueba la VIA REAL
// (PostgREST + sesiones), la proyeccion redactada de la cola v2 y la CARRERA de
// descarte (dos sesiones simultaneas, imposible en el oraculo transaccional).
async function testDescarte(sessions, seed) {
  console.log('\n— Descarte de la cola global (C1-bis: pide_credito) —');
  const coordinador = sessions.coordinador.client;
  const gerencia = sessions.gerencia.client;
  const sup1Id = seed.profileIdByKey.sup1;
  const coordId = sessions.coordinador.user.id;

  // (A) Gate de rol de las 2 RPC nuevas: fuera el rol CRM legacy `vendedor`,
  // supervisor y directorio.
  for (const key of ['vend1', 'sup1', 'directorio']) {
    await expectBlockedMutation(
      `${key} no puede descartar un lead de la cola`,
      sessions[key].client.schema('crm').rpc('descartar_lead', {
        p_lead: TRANSIENT_IDS.descarteLeadCredito,
        p_motivo: 'pide_credito',
      }),
      ['42501'],
    );
    await expectBlockedMutation(
      `${key} no puede deshacer un descarte`,
      sessions[key].client.schema('crm').rpc('deshacer_descarte', {
        p_lead: TRANSIENT_IDS.descarteLeadCredito,
      }),
      ['42501'],
    );
  }

  // (B) Semillas por service_role: MISMO camino que la edge de importacion, asi
  // que el trigger clasificador corre de verdad. La nota trae prestamo + PII:
  // la marca debe nacer del texto y la cola debe mostrarla REDACTADA.
  const colaComun = {
    activo: true, asignado_supervisor_id: null, vendedor_id: null,
    creado_por: sup1Id, etapa: 'nuevo', moneda: 'PEN', origen: 'otro',
    no_contactar: false,
  };
  await requireAdmin(
    'sembrar la cola del descarte',
    admin.schema('crm').from('leads').insert([
      {
        ...colaComun, id: TRANSIENT_IDS.descarteLeadCredito, monto_estimado: 3000,
        nombre_completo: 'DESCARTE CREDITO TRANSIENT', telefono: '999000120',
        nota: 'Quiero un préstamo urgente, escríbanme a persona@test.invalid o al 987 654 321',
      },
      {
        ...colaComun, id: TRANSIENT_IDS.descarteLeadLimpio, monto_estimado: 15000,
        nombre_completo: 'DESCARTE LIMPIO TRANSIENT', telefono: '999000121',
        nota: '¿Son una cooperativa de ahorro y crédito? Quiero invertir a plazo fijo',
      },
      {
        ...colaComun, id: TRANSIENT_IDS.descarteLeadCarrera, monto_estimado: 7000,
        nombre_completo: 'DESCARTE CARRERA TRANSIENT', telefono: '999000122',
      },
    ]),
  );

  // La cola v2: la marca del clasificador viaja y el comentario sale redactado.
  const cola = await positive(
    'coordinador relee la cola con la proyeccion v2 (marca + comentario)',
    coordinador.schema('crm').rpc('leads_por_repartir'),
  );
  if (cola) {
    const filas = cola.data ?? [];
    const credito = filas.find((fila) => fila.id === TRANSIENT_IDS.descarteLeadCredito);
    const limpio = filas.find((fila) => fila.id === TRANSIENT_IDS.descarteLeadLimpio);
    check(credito?.clasificacion_auto === 'posible_credito',
      'el clasificador marco "préstamo" en el INSERT real (posible_credito)',
      JSON.stringify(credito ?? null));
    check(limpio?.clasificacion_auto === null,
      'la pregunta de la cooperativa NO quedo marcada (falso positivo)',
      JSON.stringify(limpio ?? null));
    const comentario = String(credito?.comentario ?? '');
    check(comentario.includes('[correo oculto]') && comentario.includes('[teléfono oculto]'),
      'el comentario de la cola viaja redactado (correo y celular ocultos)',
      comentario);
    check(!comentario.includes('persona@test.invalid') && !comentario.includes('987'),
      'no queda PII legible dentro del comentario de la cola',
      comentario);
  }

  // Ni service_role reescribe el veredicto del clasificador (trigger zz).
  await requireAdmin(
    'intentar reescribir clasificacion_auto con service_role',
    admin.schema('crm').from('leads')
      .update({ clasificacion_auto: 'posible_credito' })
      .eq('id', TRANSIENT_IDS.descarteLeadLimpio),
  );
  const inmutable = await requireAdmin(
    'releer la marca tras el intento de reescritura',
    admin.schema('crm').from('leads')
      .select('clasificacion_auto')
      .eq('id', TRANSIENT_IDS.descarteLeadLimpio).single(),
  );
  check(inmutable.data?.clasificacion_auto === null,
    'clasificacion_auto es inmutable incluso para service_role (dato de medicion)');

  // (C) Camino feliz: descarte con motivo pide_credito y nota que se appendea.
  const descarte = await positive(
    'coordinador descarta el lead que pide credito',
    coordinador.schema('crm').rpc('descartar_lead', {
      p_lead: TRANSIENT_IDS.descarteLeadCredito,
      p_motivo: 'pide_credito',
      p_nota: 'confirmado: solo busca prestamo',
    }),
  );
  if (descarte) {
    check(descarte.data?.ya_estaba === false,
      'el primer descarte no vino marcado como ya_estaba');
    check(descarte.data?.descartado_por === coordId,
      'el sello del descarte acredita al coordinador');
  }
  const cerrado = await requireAdmin(
    'releer el lead descartado con service_role',
    admin.schema('crm').from('leads')
      .select('etapa, motivo_descarte, descartado_por, descartado_en, clasificacion_auto, activo, nota')
      .eq('id', TRANSIENT_IDS.descarteLeadCredito).single(),
  );
  check(cerrado.data?.etapa === 'descartado'
    && cerrado.data?.motivo_descarte === 'pide_credito'
    && cerrado.data?.descartado_por === coordId
    && cerrado.data?.descartado_en !== null,
    'el lead quedo descartado con motivo y sello nominal',
    JSON.stringify(cerrado.data));
  check(cerrado.data?.activo === true,
    'el descarte NO desactiva el lead (nada se pierde)');
  check(cerrado.data?.clasificacion_auto === 'posible_credito',
    'la marca del clasificador sobrevive al cierre (matriz de confusion)');
  check(String(cerrado.data?.nota ?? '').startsWith('Quiero un préstamo')
    && String(cerrado.data?.nota ?? '').includes('DESCARTE: confirmado'),
    'la nota del cliente se appendeo sin pisarse');

  // Idempotencia: mismo actor y motivo → ya_estaba; otro motivo → conflicto real.
  const reintento = await positive(
    'el reintento del mismo descarte es idempotente',
    coordinador.schema('crm').rpc('descartar_lead', {
      p_lead: TRANSIENT_IDS.descarteLeadCredito,
      p_motivo: 'pide_credito',
      p_nota: 'confirmado: solo busca prestamo',
    }),
  );
  if (reintento) {
    check(reintento.data?.ya_estaba === true,
      'el reintento devolvio ya_estaba=true sin doble traza');
  }
  await expectBlockedMutation(
    're-descartar con OTRO motivo es un conflicto (P0002)',
    coordinador.schema('crm').rpc('descartar_lead', {
      p_lead: TRANSIENT_IDS.descarteLeadCredito,
      p_motivo: 'sin_interes',
    }),
    ['P0002'],
  );
  // El descartado sale de la cola.
  const colaTras = await positive(
    'coordinador relee la cola tras el descarte',
    coordinador.schema('crm').rpc('leads_por_repartir'),
  );
  if (colaTras) {
    check(!(colaTras.data ?? []).some((fila) => fila.id === TRANSIENT_IDS.descarteLeadCredito),
      'el lead descartado ya no aparece en la cola');
  }

  // (D) Deshacer: es personal (gerencia no toca lo ajeno) y restaura el estado.
  await expectBlockedMutation(
    'gerencia no puede deshacer el descarte del coordinador',
    gerencia.schema('crm').rpc('deshacer_descarte', {
      p_lead: TRANSIENT_IDS.descarteLeadCredito,
    }),
    ['P0002'],
  );
  const deshecho = await positive(
    'el coordinador deshace su propio descarte',
    coordinador.schema('crm').rpc('deshacer_descarte', {
      p_lead: TRANSIENT_IDS.descarteLeadCredito,
    }),
  );
  if (deshecho) {
    check(deshecho.data?.etapa === 'nuevo' && Number(deshecho.data?.ciclo_actual) === 2,
      'el deshacer reabrio en etapa nuevo e incremento el ciclo',
      JSON.stringify(deshecho.data));
  }
  const reabierto = await requireAdmin(
    'releer el lead reabierto con service_role',
    admin.schema('crm').from('leads')
      .select('etapa, motivo_descarte, descartado_por, descartado_en')
      .eq('id', TRANSIENT_IDS.descarteLeadCredito).single(),
  );
  check(reabierto.data?.etapa === 'nuevo'
    && reabierto.data?.motivo_descarte === null
    && reabierto.data?.descartado_por === null
    && reabierto.data?.descartado_en === null,
    'el deshacer limpio motivo y sello (describe el cierre VIGENTE)',
    JSON.stringify(reabierto.data));

  // (E) CARRERA REAL: dos sesiones descartan el MISMO lead con motivos distintos.
  const [a, b] = await Promise.allSettled([
    coordinador.schema('crm').rpc('descartar_lead', {
      p_lead: TRANSIENT_IDS.descarteLeadCarrera, p_motivo: 'sin_interes',
    }),
    gerencia.schema('crm').rpc('descartar_lead', {
      p_lead: TRANSIENT_IDS.descarteLeadCarrera, p_motivo: 'pide_credito',
    }),
  ]);
  const resueltas = [a, b].filter((r) => r.status === 'fulfilled');
  const ganadores = resueltas.filter((r) => !r.value.error);
  const perdedores = resueltas.filter((r) => r.value.error);
  check(ganadores.length === 1 && perdedores.length === 1,
    'carrera de descarte: exactamente uno gana',
    `ok=${ganadores.length} err=${perdedores.length}`);
  if (perdedores.length === 1) {
    const codigo = String(perdedores[0].value.error.code);
    check(['P0002', '40001'].includes(codigo),
      'carrera de descarte: el perdedor recibe P0002 (o 40001 si el aislamiento es mayor)',
      codigo);
  }
  const trasCarrera = await requireAdmin(
    'releer el lead de la carrera de descarte',
    admin.schema('crm').from('leads')
      .select('etapa, motivo_descarte')
      .eq('id', TRANSIENT_IDS.descarteLeadCarrera).single(),
  );
  check(trasCarrera.data?.etapa === 'descartado'
    && ['sin_interes', 'pide_credito'].includes(trasCarrera.data?.motivo_descarte),
    'carrera: quedo UN descarte consistente con el ganador',
    JSON.stringify(trasCarrera.data));

  // (F) C1-ter: la vista de descartados — gate, alcance y hints por actor.
  for (const key of ['vend1', 'sup1', 'directorio']) {
    await expectBlockedMutation(
      `${key} no puede listar los descartados de la cola`,
      sessions[key].client.schema('crm').rpc('leads_descartados'),
      ['42501'],
    );
  }
  // Un descarte fresco del coordinador para aserciones deterministas (el de la
  // carrera lo pudo ganar cualquiera de los dos actores).
  await requireAdmin(
    'sembrar el lead de la vista de descartados',
    admin.schema('crm').from('leads').insert({
      ...colaComun, id: TRANSIENT_IDS.descarteLeadVista, monto_estimado: 9000,
      nombre_completo: 'DESCARTE VISTA TRANSIENT', telefono: '999000123',
      nota: 'Busco financiamiento para mi negocio',
    }),
  );
  await positive(
    'coordinador descarta el lead de la vista',
    coordinador.schema('crm').rpc('descartar_lead', {
      p_lead: TRANSIENT_IDS.descarteLeadVista,
      p_motivo: 'pide_credito',
    }),
  );
  const listado = await positive(
    'coordinador lista los descartados de la cola',
    coordinador.schema('crm').rpc('leads_descartados'),
  );
  if (listado) {
    const filas = listado.data ?? [];
    const mio = filas.find((fila) => fila.id === TRANSIENT_IDS.descarteLeadVista);
    check(!!mio, 'el descarte fresco aparece en el listado');
    check(mio?.es_mio === true && mio?.puede_deshacer === true,
      'el descarte propio y reciente llega con es_mio y puede_deshacer',
      JSON.stringify(mio ?? null));
    check(mio?.clasificacion_auto === 'posible_credito'
      && mio?.motivo_descarte === 'pide_credito',
      'la marca del clasificador y el motivo viajan en el listado');
    check(!!mio?.creado_en && mio?.nota_descarte === null,
      'creado_en viaja y nota_descarte es null cuando no hubo nota de cierre',
      JSON.stringify({ creado_en: mio?.creado_en, nota_descarte: mio?.nota_descarte }));
    check(!('telefono' in (filas[0] ?? {})) && !('dni' in (filas[0] ?? {})),
      'el listado no proyecta PII de contacto');
  }
  const listadoAjeno = await positive(
    'gerencia tambien lista los descartados',
    gerencia.schema('crm').rpc('leads_descartados'),
  );
  if (listadoAjeno) {
    const ajeno = (listadoAjeno.data ?? []).find((fila) => fila.id === TRANSIENT_IDS.descarteLeadVista);
    check(ajeno?.es_mio === false && ajeno?.puede_deshacer === false,
      'para OTRO actor el mismo descarte llega sin es_mio ni puede_deshacer',
      JSON.stringify(ajeno ?? null));
  }
}

// ── F2 tramo 1: cursor keyset de la cartera ──────────────────────────────────
// Esta RPC no devuelve agregados: devuelve FILAS DE LEADS con PII. Por eso la
// matriz mira DOS cosas que no se implican entre si:
//   (A) que pagine bien — orden estable, sin huecos ni repetidos, con los
//       filtros resueltos en el servidor;
//   (B) que no ensanche NI UN LEAD el ambito que la RLS ya concedia. El oraculo
//       es el propio SELECT del actor, leido adyacente (la suite es secuencial:
//       nada muta entre ambas lecturas).
// Sin (B), (A) puede estar entero en verde sobre una fuga.
async function testCarteraKeyset(sessions, seed) {
  console.log('\n— Cartera paginada por keyset (F2 tramo 1) —');

  const corte = Date.now() - VENTANA_CONVERTIDOS_MS_F1;
  // Ambito operativo = vivo (activo) Y dentro de la ventana de convertidos. El
  // `activo` importa SOLO para el directorio: su rama de `leads_select` es la
  // unica que no lo exige, y hasta 20260810151433 la cartera le mezclaba en las
  // filas los soft-borrados que sus tiles nunca contaron.
  const enAmbito = (l) => l.activo === true
    && (l.etapa !== 'convertido'
      || (l.convertido_en && Date.parse(l.convertido_en) >= corte));

  for (const key of ['vend1', 'sup1', 'sup2', 'gerencia', 'directorio', 'coordinador']) {
    const client = sessions[key].client;
    const oraculo = await positive(
      `${key} lista su cartera por RLS como oraculo del keyset`,
      client.schema('crm').from('leads')
        .select('id, nombre_completo, etapa, vendedor_id, convertido_en, actualizado_en, activo')
        .order('actualizado_en', { ascending: false })
        .order('id', { ascending: true })
        .limit(2000),
    );
    if (!oraculo) continue;
    const esperados = (oraculo.data ?? []).filter(enAmbito);
    // Negativa explicita del cambio: ningun soft-borrado que su RLS le muestre
    // puede aparecer en la pagina. Para 5 de los 6 roles el conjunto es vacio
    // (su policy ya los excluia); para el directorio es el caso real.
    const borradosVisibles = (oraculo.data ?? []).filter((l) => l.activo === false);
    if (borradosVisibles.length > 0) {
      const idsBorrados = new Set(borradosVisibles.map((l) => l.id));
      const pagina = await positive(
        `${key} pide la cartera para comprobar que no trae soft-borrados`,
        client.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200 }),
      );
      if (pagina) {
        check((pagina.data ?? []).every((f) => !idsBorrados.has(f.id)),
          `${key}: ninguno de sus ${borradosVisibles.length} soft-borrados llega a la cartera`);
      }
    }

    const completa = await positive(
      `${key} obtiene cartera_pagina_fn`,
      client.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200 }),
    );
    if (!completa) continue;
    const filas = completa.data ?? [];

    // Se compara el PREFIJO, no la longitud: el oraculo lee hasta 2000 filas y
    // la RPC sirve 200. Con el seed coinciden; contra una base con volumen
    // —que es para lo que existe F2— exigir igualdad daria un rojo falso.
    check(filas.every((f, i) => f.id === esperados[i]?.id),
      `${key}: la pagina cuadra fila a fila (y en orden) con su propio SELECT`,
      JSON.stringify({ rpc: filas.length, oraculo: esperados.length }));
    check(filas.length === Math.min(esperados.length, 200),
      `${key}: la pagina trae todo lo visible que cabe en el limite pedido`,
      JSON.stringify({ rpc: filas.length, oraculo: esperados.length }));

    // (B) La negativa que de verdad importa: ni un id fuera del ambito RLS.
    const idsVisibles = new Set(esperados.map((l) => l.id));
    check(filas.every((f) => idsVisibles.has(f.id)),
      `${key}: ninguna fila servida cae fuera de lo que su RLS ya mostraba`);

    // Paginacion real: dos pasadas de 2 reconstruyen el prefijo del oraculo.
    if (esperados.length >= 3) {
      const p1 = await positive(
        `${key} pide la primera pagina de 2`,
        client.schema('crm').rpc('cartera_pagina_fn', { p_limite: 2 }),
      );
      const ultima = (p1?.data ?? [])[1];
      if (ultima) {
        const p2 = await positive(
          `${key} pide la segunda pagina con el cursor de la primera`,
          client.schema('crm').rpc('cartera_pagina_fn', {
            p_limite: 2,
            p_antes_de: ultima.actualizado_en,
            p_antes_id: ultima.id,
          }),
        );
        if (p2) {
          const concatenado = [...p1.data, ...(p2.data ?? [])].map((f) => f.id);
          check(new Set(concatenado).size === concatenado.length,
            `${key}: las dos paginas no repiten ningun lead`);
          check(concatenado.every((id, i) => id === esperados[i]?.id),
            `${key}: las dos paginas reconstruyen el orden del oraculo sin huecos`,
            JSON.stringify({ paginado: concatenado.length, oraculo: esperados.length }));
        }
      }
    }
  }

  // No vacuidad: si el seed dejara de poblar, todo lo de arriba pasaria vacio.
  const gerenciaCompleta = await positive(
    'gerencia obtiene su cartera completa para las aserciones de forma',
    sessions.gerencia.client.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200 }),
  );
  const filasGerencia = gerenciaCompleta?.data ?? [];
  check(filasGerencia.length >= 5,
    `gerencia recibe una cartera no vacia (${filasGerencia.length} leads)`);

  // El semaforo del kanban viaja YA en la pagina (lo que deja a F3 sin
  // migraciones) y mide CONTACTO, no cualquier fila del timeline. El oraculo es
  // el propio SELECT de actividades del actor, leido adyacente: aseverar un
  // valor fijo seria fragil (esta suite registra contactos en tests anteriores)
  // y ademas no probaria que el criterio de tipos sea el correcto.
  const TIPOS_CONTACTO_F2 = new Set([
    'llamada_realizada', 'llamada_no_contestada',
    'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada',
  ]);
  const actividadesGerencia = await positive(
    'gerencia lista actividades como oraculo del ultimo contacto',
    sessions.gerencia.client.schema('crm').from('actividades')
      .select('lead_id, tipo, creado_en').limit(5000),
  );
  if (actividadesGerencia) {
    const ultimoPorLead = new Map();
    for (const a of actividadesGerencia.data ?? []) {
      if (!TIPOS_CONTACTO_F2.has(a.tipo)) continue;
      const previo = ultimoPorLead.get(a.lead_id);
      if (!previo || Date.parse(a.creado_en) > Date.parse(previo)) {
        ultimoPorLead.set(a.lead_id, a.creado_en);
      }
    }
    check(filasGerencia.every((f) => 'ultimo_contacto_en' in f),
      'ultimo_contacto_en viaja en todas las filas de la pagina');
    const desalineadas = filasGerencia.filter((f) => {
      const esperado = ultimoPorLead.get(f.id) ?? null;
      if (esperado === null) return f.ultimo_contacto_en !== null;
      return f.ultimo_contacto_en === null
        || Date.parse(f.ultimo_contacto_en) !== Date.parse(esperado);
    });
    check(desalineadas.length === 0,
      'ultimo_contacto_en es el ultimo CONTACTO real de cada lead (nunca una nota)',
      JSON.stringify(desalineadas.map((f) => ({
        id: f.id, rpc: f.ultimo_contacto_en, oraculo: ultimoPorLead.get(f.id) ?? null,
      }))));
    // No vacuidad del check anterior: si NINGUN lead tuviera contactos, la
    // comparacion de arriba pasaria entera contra puros null.
    check([...ultimoPorLead.keys()].some((id) => filasGerencia.some((f) => f.id === id)),
      'al menos un lead de la pagina tiene contacto real (el check anterior no es vacio)');
  }

  // ── Filtros resueltos en el SERVIDOR (con keyset, filtrar en el cliente
  //    sobre lo ya cargado mentiria: vacios falsos y contadores parciales) ────
  const gerencia = sessions.gerencia.client;
  const nuevosOraculo = await positive(
    'gerencia lista sus leads en etapa nuevo como oraculo del filtro',
    gerencia.schema('crm').from('leads').select('id').eq('etapa', 'nuevo').limit(2000),
  );
  const porEtapa = await positive(
    'gerencia filtra la cartera por etapa en el servidor',
    gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200, p_etapa: 'nuevo' }),
  );
  if (nuevosOraculo && porEtapa) {
    const filas = porEtapa.data ?? [];
    check(filas.length === (nuevosOraculo.data ?? []).length
      && filas.every((f) => f.etapa === 'nuevo'),
      'el filtro por etapa devuelve exactamente los nuevos visibles',
      JSON.stringify({ rpc: filas.length, oraculo: (nuevosOraculo.data ?? []).length }));
  }

  const sinAsignar = await positive(
    'gerencia filtra los leads sin asignar',
    gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200, p_sin_asignar: true }),
  );
  if (sinAsignar) {
    const filas = sinAsignar.data ?? [];
    check(filas.length > 0 && filas.every((f) => f.vendedor_id === null),
      `el filtro sin_asignar solo devuelve parkeados (${filas.length})`);
  }

  const porVendedor = await positive(
    'gerencia filtra la cartera por analista',
    gerencia.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 200, p_vendedor_id: seed.profileIdByKey.vend1,
    }),
  );
  if (porVendedor) {
    const filas = porVendedor.data ?? [];
    check(filas.length > 0 && filas.every((f) => f.vendedor_id === seed.profileIdByKey.vend1),
      `el filtro por analista solo devuelve su cartera (${filas.length})`);
  }

  // El filtro NO es una puerta: pedir la cartera de un analista ajeno devuelve
  // vacio porque la RLS ya recorto ANTES — no porque el filtro sea amable.
  const ajena = await positive(
    'vend1 pide la cartera de un analista de otro subarbol',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 200, p_vendedor_id: seed.profileIdByKey.vend3,
    }),
  );
  if (ajena) {
    check((ajena.data ?? []).length === 0,
      'vend1 no obtiene ni una fila filtrando por un analista ajeno');
  }

  // Busqueda: por nombre dentro del ambito, y NADA fuera de el.
  const buscaPropio = await positive(
    'vend1 busca por nombre dentro de su cartera',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50, p_texto: 'MARIA',
    }),
  );
  if (buscaPropio) {
    const filas = buscaPropio.data ?? [];
    check(filas.length === 1 && filas[0].nombre_completo === 'MARIA LOPEZ DEMO',
      'la busqueda por nombre encuentra el lead propio');
  }
  const buscaAjeno = await positive(
    'vend1 busca por nombre un lead de otro subarbol',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50, p_texto: 'ANA TORRES',
    }),
  );
  if (buscaAjeno) {
    check((buscaAjeno.data ?? []).length === 0,
      'la busqueda jamas alcanza un lead fuera del ambito');
  }
  const buscaTelefono = await positive(
    'vend1 busca por telefono (3+ digitos)',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50, p_texto: '987654322',
    }),
  );
  if (buscaTelefono) {
    const filas = buscaTelefono.data ?? [];
    check(filas.length === 1 && filas[0].nombre_completo === 'MARIA LOPEZ DEMO',
      'la busqueda por telefono encuentra el lead propio');
  }
  // La rama de DIGITOS es un OR distinto al del nombre: necesita sus propias
  // negativas o un fallo ahi (p. ej. que dejara de estar bajo la RLS) pasaria
  // entero por delante de los tests de nombre.
  const telefonoAjeno = await positive(
    'vend1 busca el telefono exacto de un lead de otro subarbol',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50, p_texto: '987654324',
    }),
  );
  if (telefonoAjeno) {
    check((telefonoAjeno.data ?? []).length === 0,
      'el telefono exacto de un lead ajeno no lo saca del ambito');
  }
  // El prefijo que comparten los 5 telefonos del fixture: la prueba de que el
  // recorte ocurre ANTES del filtro, no despues.
  const prefijoComun = await positive(
    'vend1 busca el prefijo comun a toda la cartera del fixture',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50, p_texto: '98765432',
    }),
  );
  if (prefijoComun) {
    const nombres = (prefijoComun.data ?? []).map((f) => f.nombre_completo).sort();
    check(nombres.length === EXPECTED_LEAD_NAMES.vend1.length
      && nombres.every((n, i) => n === EXPECTED_LEAD_NAMES.vend1[i]),
      'un prefijo que casa con TODA la tabla sigue devolviendo solo su ambito',
      JSON.stringify({ recibidos: nombres, esperados: EXPECTED_LEAD_NAMES.vend1 }));
  }
  // `%` y `_` son LITERALES del usuario, no comodines suyos: si no se
  // escaparan, 'A%' traeria media cartera.
  const comodin = await positive(
    'gerencia busca un texto con comodines de LIKE',
    gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200, p_texto: 'A%' }),
  );
  if (comodin) {
    check((comodin.data ?? []).length === 0,
      'los comodines de LIKE del texto se tratan como literales');
  }

  // ── Denegaciones duras: sin membresia viva no hay lista vacia, hay 42501 ───
  for (const key of ['vendInactive', 'clientBank']) {
    await expectExplicitAuthorizationDenied(
      `${key} recibe 42501 en cartera_pagina_fn`,
      sessions[key].client.schema('crm').rpc('cartera_pagina_fn', { p_limite: 50 }),
      ['42501'],
    );
  }

  // ── Parametros invalidos: 22023 con su mensaje, nunca un 42501 enmascarado ─
  await expectExpectedFailure(
    'cartera_pagina_fn rechaza p_limite=0',
    gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 0 }),
    ['22023'], /p_limite invalido/i,
  );
  await expectExpectedFailure(
    'cartera_pagina_fn rechaza p_limite=201',
    gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 201 }),
    ['22023'], /p_limite invalido/i,
  );
  await expectExpectedFailure(
    'cartera_pagina_fn rechaza un cursor a medias',
    gerencia.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50, p_antes_de: new Date().toISOString(),
    }),
    ['22023'], /cursor incompleto/i,
  );
  await expectExpectedFailure(
    'cartera_pagina_fn rechaza una etapa fuera del catalogo',
    gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 50, p_etapa: 'perdido' }),
    ['22023'], /p_etapa invalido/i,
  );
  await expectExpectedFailure(
    'cartera_pagina_fn rechaza una busqueda de 1 caracter',
    gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 50, p_texto: 'a' }),
    ['22023'], /p_texto invalido/i,
  );
  await expectExpectedFailure(
    'cartera_pagina_fn rechaza sin_asignar junto a un analista',
    gerencia.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50, p_sin_asignar: true, p_vendedor_id: seed.profileIdByKey.vend1,
    }),
    ['22023'], /filtro contradictorio/i,
  );
  // Los EXTREMOS validos: probar solo los rechazos deja sin cubrir que el
  // rango aceptado lo sea de verdad (un `< 1` mal escrito rechazaria el 1).
  for (const limite of [1, 200]) {
    await positive(
      `cartera_pagina_fn acepta p_limite=${limite}`,
      gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: limite }),
    );
  }
  // Los OTROS dos metacaracteres de LIKE (`%` ya se probo arriba).
  for (const patron of ['A_', 'A\\']) {
    const literal = await positive(
      `gerencia busca el texto literal ${JSON.stringify(patron)}`,
      gerencia.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200, p_texto: patron }),
    );
    if (literal) {
      check((literal.data ?? []).length === 0,
        `${JSON.stringify(patron)} se busca como literal, no como patron`);
    }
  }
  // Un cursor VALIDO pero de una fila ajena no es una puerta: sigue paginando
  // sobre el ambito propio, nunca sobre el del dueno del cursor.
  const anaAjena = seed.leadByName.get('ANA TORRES DEMO');
  const cursorAjeno = await positive(
    'vend1 pagina con el cursor de un lead que no puede ver',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 50,
      p_antes_de: anaAjena.actualizado_en,
      p_antes_id: anaAjena.id,
    }),
  );
  if (cursorAjeno) {
    const nombres = (cursorAjeno.data ?? []).map((f) => f.nombre_completo);
    check(nombres.every((n) => EXPECTED_LEAD_NAMES.vend1.includes(n)),
      'un cursor ajeno no amplia el ambito de la pagina',
      JSON.stringify(nombres));
  }

  // ── El coordinador: 0 filas, pero NO un error ─────────────────────────────
  // Es la mitad que da sentido a la guardia de admision. Sin esta asercion, la
  // comparacion "vacio == vacio" del bucle de arriba pasa sin probar nada.
  const coordinador = await positive(
    'coordinador ejecuta cartera_pagina_fn (pasa la guardia)',
    sessions.coordinador.client.schema('crm').rpc('cartera_pagina_fn', { p_limite: 50 }),
  );
  if (coordinador) {
    check((coordinador.data ?? []).length === 0,
      'el coordinador recibe 0 filas y NO un 42501 (su ambito de leads es ∅ por diseno)');
  }

  // ── ultimo_contacto_en: mismo valor para todos los que ven el lead ─────────
  // La cabecera de la migracion AFIRMA que el lateral no diverge porque
  // actividades_select es co-extensiva con leads_select. Esto lo comprueba: un
  // contacto real registrado por el analista debe verse identico desde su
  // supervisor y desde gerencia.
  const maria = seed.leadByName.get('MARIA LOPEZ DEMO');
  const contacto = await positive(
    'vend1 registra una llamada realizada sobre su lead',
    sessions.vend1.client.schema('crm').from('actividades').insert({
      creado_por: sessions.vend1.user.id,
      detalle: 'F2 CONTACTO TRANSIENT',
      id: TRANSIENT_IDS.carteraContactoActividad,
      lead_id: maria.id,
      tipo: 'llamada_realizada',
    }).select('id, creado_en').single(),
  );
  if (contacto) {
    const sellos = new Map();
    for (const key of ['vend1', 'sup1', 'gerencia']) {
      const pagina = await positive(
        `${key} relee la cartera tras el contacto`,
        sessions[key].client.schema('crm').rpc('cartera_pagina_fn', { p_limite: 200 }),
      );
      if (!pagina) continue;
      const fila = (pagina.data ?? []).find((f) => f.id === maria.id);
      sellos.set(key, fila?.ultimo_contacto_en ?? null);
    }
    const valores = [...sellos.values()];
    check(valores.length === 3 && valores.every((v) => v !== null),
      'el contacto real llena ultimo_contacto_en (ya no es null)',
      JSON.stringify([...sellos]));
    check(new Set(valores.map((v) => (v === null ? 'null' : Date.parse(v)))).size === 1,
      'analista, supervisor y gerencia ven EXACTAMENTE el mismo ultimo contacto',
      JSON.stringify([...sellos]));
  }
}

// ── Migracion A: conversion mensual ponderada (crm.conversion_mensual_fn) ────
// La RPC nueva abre al ANALISTA un informe (cobertura del ledger, total del
// ambito, ranking) y al SUPERVISOR su subarbol entero, asi que el gate es parte
// del entregable y no un seguimiento. Nueve tramos:
//   (0) LINEA BASE + NO VACUIDAD — se fotografia el payload ANTES de sembrar y
//       despues se aseveran DELTAS EXACTAS. Sin la linea base todo lo que sigue
//       es consistencia INTERNA del payload, y la regla central del ciclo —T10:
//       el referido queda FUERA del divisor— no tendria ni una asercion: un
//       servidor que la revirtiera de forma coherente (divisor +2 en vez de +1,
//       numerador 1,15, porcentaje recalculado) pasaria en verde. El delta es
//       ademas RELATIVO: sobrevive a un ledger que solo crece.
//   (A) permitidos y forma · (B) denegaciones DURAS · (C) ORDEN de los errores
//   (D) PARIDAD entre roles · (E) aritmetica · (F) forma del contrato
//   (G) lo que NO se recorta por ambito, y la tabla del peso, que no existe
//       para la Data API · (H) el soft-delete no mueve la metrica ·
//       (I) anon no ve la RPC ni existiendo.
// El oraculo NO son numeros fijos: son DELTAS e INVARIANTES (el total es la
// suma de las filas, el numerador es la formula, el ambito estrecho es un
// subconjunto del ancho). Es lo unico que sobrevive a un ledger append-only.
//
// ⚠️ ORDEN EN main(): este bloque va EL ULTIMO, despues de testAnon(). Dos
// razones, y la segunda no es evidente: (1) deja cuatro leads nuevos en la
// cartera de vend1, de sup1 y de un tercer analista; (2) el soft-delete NO los
// esconde al rol `directorio`, porque la policy `leads_select` pone su rama
// `es_lector_global()` FUERA del `(activo = true and ...)` — verificado en el
// `qual` de produccion. Encadenarlo antes de readVisibilityMatrix rompe
// «directorio ve exactamente su conjunto» por una causa que no tiene nada que
// ver con la conversion. Es tambien el motivo REAL —junto con la inmutabilidad
// del ledger— por el que el gate no es re-ejecutable sobre la misma base: en
// una segunda corrida esos leads siguen VISIBLES para el lector global.
// `cierre` entra con 20260815003742: dice si el mes esta sellado. El contrato se
// asevera CERRADO a proposito —una clave de mas rompe la pantalla en silencio—,
// asi que ampliarlo aqui es parte de la migracion, no un ajuste del test.
// F2.4 añadió `cartera` (el desglose de operaciones) al payload, al total y a
// cada responsable — el arnés se actualizó el 27/08 al medirlo contra el vivo.
const CLAVES_PAYLOAD_CONVERSION = ['alcance', 'cartera', 'cierre', 'cobertura', 'fuentes',
  'generado_en', 'periodo', 'ponderacion', 'responsables', 'total', 'version'];
const CLAVES_PERIODO_CONVERSION = ['anio', 'desde', 'hasta', 'mes', 'mes_nombre', 'zona'];
const CLAVES_PONDERACION_CONVERSION = ['fuente', 'referido'];
const CLAVES_COBERTURA_CONVERSION = ['cierres_sin_episodio', 'divisor_aproximado',
  'divisor_por_motivo', 'fuera_de_roster', 'medible', 'motivo_no_medible', 'suelo_historico'];
// Actualizadas el 2026-08-11 tras la consolidación final de la migración A:
// `cierres_de_arrastre` (exigida por los revisores para que un % > 100 sea
// explicable en pantalla) viaja en la fila Y en el total, y el total lleva
// además `referidos_aporta_pct` (espejo del aporta_pct por fila).
const CLAVES_TOTAL_CONVERSION = ['analistas', 'cartera', 'cierres_de_arrastre',
  'cierres_no_referidos', 'cierres_referidos', 'conversion_pct', 'divisor',
  'numerador', 'referidos_aporta_pct', 'referidos_recibidos'];
const CLAVES_RESPONSABLE_CONVERSION = ['ajuste', 'cartera', 'cierres_de_arrastre',
  'cierres_no_referidos', 'cierres_referidos', 'conversion_pct', 'divisor',
  'estado', 'numerador', 'procedencia', 'referidos',
  'supervisor_id', 'vendedor_id'];
const CLAVES_REFERIDOS_CONVERSION = ['aporta_pct', 'cerrados', 'dados_de_alta', 'recibidos'];
const CLAVES_PROCEDENCIA_CONVERSION = ['anio', 'cierres', 'cierres_referidos', 'mes', 'mes_nombre'];
// `fuera_de_roster` es un AGREGADO SIN IDENTIDAD a proposito: devolver el uuid
// de alguien sin rol efectivo seria filtrar a una persona por la puerta de atras.
const CLAVES_FUERA_DE_ROSTER = ['analistas', 'cierres', 'divisor', 'numerador'];
// Vocabulario CERRADO: el front los declara como picklist y un valor de mas
// rompe la pantalla en silencio.
const ESTADOS_CONVERSION = new Set(['medible', 'solo_referidos', 'solo_arrastre', 'sin_actividad']);
const MOTIVOS_NO_MEDIBLE = new Set([null, 'sin_ledger', 'anterior_al_ledger', 'mes_parcial',
  'sin_supervisor', 'supervisor_inactivo', 'supervisor_no_es_supervisor']);
// Los TRES motivos del paso 5b: la RPC los sobreescribe SOLO para alcance
// 'propio' cuando el analista no esta en el roster. No son metadato del ledger
// y por eso no pueden exigirse identicos entre roles (ver tramo G).
const MOTIVOS_EXCLUSION_ROSTER = new Set(['sin_supervisor', 'supervisor_inactivo',
  'supervisor_no_es_supervisor']);

// Ids propios del bloque, y NO en fixtures.TRANSIENT_IDS a proposito: la unica
// limpieza que de verdad los alcanza es el `finally` de aqui abajo. Los
// TRANSIENT_IDS se generan con randomUUID() por PROCESO, asi que el
// cleanupTransientRows() del arranque de main() jamas puede ver los de una
// corrida anterior: registrarlos alli daria una sensacion de red que no existe.
// Manteniendolos locales, el bloque es autocontenido y su limpieza no depende
// ni de otro fichero ni de que el tramo H llegue a ejecutarse.
const IDS_CONVERSION = Object.freeze({
  leadReferido: randomUUID(),
  leadDirecto: randomUUID(),
  leadSoloReferidos: randomUUID(),
  leadFueraDeRoster: randomUUID(),
});

// ── F2.b b5 (E3): fusión, corrección, enlace y reasignación — puertas de GERENCIA ──
// Solo grants, gates y paridad apagada (el negocio lo cubre scripts/oraculo-f2b-b5.sh).
// Sin fixtures: argumentos con uuid inexistentes; los guards (bandera → Gerencia →
// argumentos) deben disparar ANTES de tocar nada. Estado de producción = bandera OFF.
async function testIdentidadF2bB5(sessions) {
  console.log('\n— Identidad multiempresa F2.b b5: puertas de Gerencia (fusión, corrección, enlace, reasignación) —');
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b b5)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b b5: ${etiqueta}`, sql);
  const lista = (arr) => `'${arr.join("','")}'`;
  const ejecutablesResiduales = (firmas, roles) => cuenta('EXECUTE residual',
    `select count(*) from unnest(array[${lista(firmas)}]) f(firma), unnest(array[${lista(roles)}]) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE')`)
    + cuenta('PUBLIC residual',
      `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid in (${firmas.map((f) => `'${f}'::regprocedure`).join(',')}) and a.grantee = 0`);
  const Z1 = '00000000-0000-4000-8000-0000000000b5';
  const Z2 = '00000000-0000-4000-8000-0000000000b6';
  const ARGS = {
    fusion_previsualizar_fn: { p_perdedora: Z1, p_canonica: Z2 },
    fusionar_inversionistas_fn: { p_perdedora: Z1, p_canonica: Z2, p_motivo: 'suite b5', p_hash: 'no-es-una-huella' },
    corregir_documento_inversionista_fn: { p_inversionista: Z1, p_tipo: 'DNI', p_documento: '00000001', p_motivo: 'suite b5' },
    enlazar_lead_inversionista_fn: { p_lead_id: Z1, p_inversionista: Z2, p_motivo: 'suite b5' },
    reasignar_responsable_relacion_fn: { p_inversionista: Z1, p_nuevo_responsable: Z2, p_motivo: 'suite b5' },
  };
  const RPC = Object.keys(ARGS);
  const FIRMAS_RPC = ['crm.fusion_previsualizar_fn(uuid,uuid)', 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)',
    'crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)', 'crm.enlazar_lead_inversionista_fn(uuid,uuid,text)',
    'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)'];
  const HELPERS = ['private.inversionista_canonica(uuid)', 'private.fusion_estado_jsonb(uuid,uuid)', 'private.fusion_bloqueos(uuid,uuid)',
    'private.identidad_bloquear_documentos_de(uuid[])', 'private.cancelar_tareas_pendientes_lead(uuid)', 'private.motivo_sin_documento(text,text[])',
    'private.leads_de_identidades(uuid[])', 'private.bloquear_leads_nowait(uuid[])', 'private.documento_es_de_identidad(uuid,text,text)',
    'private.inversionista_operaciones_append_only()'];
  const llamar = (cliente, fn) => cliente.schema('crm').rpc(fn, ARGS[fn]);
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-b5'));
  const NO_GERENCIA = ['vend1', 'sup1', 'coordinador', 'directorio', 'vendInactive', 'clientBank'];

  if (cuenta('b5 aplicada', `select (to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is not null)::int`) !== 1) {
    console.log('  (saltado: b5 (20260905120000) no está en esta base)');
    return;
  }
  try {
    // ── OFF (estado de producción): las 5 son inertes para TODO authenticated; anon y service_role ni entran ──
    flag(false);
    for (const fn of RPC) {
      await expectExpectedFailure(`b5 OFF gerencia ${fn} → P0409 apagada`, llamar(sessions.gerencia.client, fn), ['P0409'], /apagada/i);
      for (const clave of NO_GERENCIA) {
        // La bandera se evalúa ANTES del rol, a propósito (con OFF nadie sondea nada): asertado.
        await expectExpectedFailure(`b5 OFF ${clave} ${fn} → P0409 apagada`, llamar(sessions[clave].client, fn), ['P0409'], /apagada/i);
      }
      await expectExpectedFailure(`b5 anon ${fn} → 42501 (sin EXECUTE)`, llamar(anon, fn), ['42501'], /permission denied|denegado/i);
      await expectExpectedFailure(`b5 service_role ${fn} → 42501 (sin EXECUTE)`, llamar(admin, fn), ['42501'], /permission denied|denegado/i);
    }
    for (const [clave, cliente] of [['gerencia', sessions.gerencia.client], ['vend1', sessions.vend1.client], ['anon', anon], ['service_role', admin]]) {
      await expectExpectedFailure(`b5 ${clave} no lee crm.inversionista_operaciones (sin grants)`,
        cliente.schema('crm').from('inversionista_operaciones').select('id').limit(1), ['42501'], /permission denied|denegado/i);
    }
    check(ejecutablesResiduales(HELPERS, ['anon', 'authenticated', 'service_role']) === 0, 'b5 helpers privados sin EXECUTE (anon/authenticated/service_role/PUBLIC)');
    check(ejecutablesResiduales(FIRMAS_RPC, ['anon', 'service_role']) === 0, 'b5 las 5 RPC sin EXECUTE para anon/service_role ni PUBLIC');
    check(cuenta('RLS tabla', `select (relrowsecurity)::int from pg_class where oid='crm.inversionista_operaciones'::regclass`) === 1, 'b5 crm.inversionista_operaciones con RLS activa');
    check(cuenta('policy DELETE', `select count(*) from pg_policies where schemaname='crm' and tablename='inversionista_operaciones' and cmd in ('DELETE','UPDATE','INSERT')`) === 0, 'b5 sin policies de escritura en el libro de operaciones');

    // ── ON: el gate de Gerencia manda antes de leer argumentos; Gerencia muere en el argumento, no en 42501 ──
    flag(true);
    for (const fn of RPC) {
      for (const clave of NO_GERENCIA) {
        await expectExpectedFailure(`b5 ON ${clave} ${fn} → 42501 (solo Gerencia)`, llamar(sessions[clave].client, fn), ['42501'], /Gerencia/i);
      }
    }
    {
      const { data, error } = await llamar(sessions.gerencia.client, 'fusion_previsualizar_fn');
      check(!error && data?.viable === false && Array.isArray(data?.bloqueos) && data.bloqueos.length > 0,
        'b5 ON gerencia previsualiza dos uuid inexistentes → viable=false con bloqueos (sin excepción)', errorText(error));
    }
    await expectExpectedFailure('b5 ON gerencia fusionar con huella mal formada → 22023', llamar(sessions.gerencia.client, 'fusionar_inversionistas_fn'), ['22023'], /huella/i);
    await expectExpectedFailure('b5 ON gerencia corregir una persona inexistente → P0002', llamar(sessions.gerencia.client, 'corregir_documento_inversionista_fn'), ['P0002'], /no existe/i);
    await expectExpectedFailure('b5 ON gerencia enlazar a una persona inexistente → P0002', llamar(sessions.gerencia.client, 'enlazar_lead_inversionista_fn'), ['P0002'], /no existe/i);
    await expectExpectedFailure('b5 ON gerencia reasignar a alguien que no es del equipo → 22023 (rol efectivo)', llamar(sessions.gerencia.client, 'reasignar_responsable_relacion_fn'), ['22023'], /equipo/i);
  } finally {
    flag(false);
  }
}

// ── F2.b E4 (public, OK de Miguel 05/09): crear_contrato reconoce a la persona (ON) + candado del documento en perfiles ──
// Solo grants, gates y paridad apagada (el negocio lo cubre scripts/oraculo-f2b-e4.sh). Estado de producción = bandera OFF.
async function testIdentidadF2bE4(sessions, seed) {
  console.log('\n— Identidad multiempresa F2.b E4: contrato reconoce a la persona + candado del documento (Portal) —');
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b E4)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b E4: ${etiqueta}`, sql);
  const FN_TRG = 'private.trg_perfiles_documento_protegido()';
  if (cuenta('E4 aplicada', `select count(*) from pg_trigger where tgrelid='public.perfiles'::regclass and tgname='trg_perfiles_zz_documento_protegido'`) !== 1) {
    console.log('  (saltado: E4 (20260905140000) no está en esta base)');
    return;
  }
  const bankProfileId = seed.profileIdByKey.clientBank;
  // El DNI del cliente de banca es el del fixture (lo escribe el seed). NO se lee con la vía tolerante:
  // esa vía no devuelve valor, y la restauración de abajo dejaba el dni en NULL —el siguiente ciclo del banco
  // ya no encontraba la sonda del domicilio (reset-gate busca por dni) y «dni intacto» comparaba contra null.
  const dniActual = BANK_CLIENT.dni;
  try {
    check(cuenta('grants trigger', `select count(*) from unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, '${FN_TRG}', 'EXECUTE')`)
          + cuenta('PUBLIC trigger', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${FN_TRG}'::regprocedure and a.grantee = 0`) === 0,
      'E4 la función del candado no tiene EXECUTE para anon/authenticated/service_role ni PUBLIC');
    check(cuenta('trigger habilitado', `select count(*) from pg_trigger where tgrelid='public.perfiles'::regclass and tgname='trg_perfiles_zz_documento_protegido' and tgenabled='O'`) === 1,
      'E4 el candado está habilitado sobre public.perfiles');
    // OFF (producción): el candado es inerte aunque el perfil esté enlazado; nada cambia para el Portal.
    flag(false);
    {
      const { error } = await sessions.clientBank.client.from('perfiles').update({ dni: '00000099' }).eq('id', bankProfileId).select('id');
      check(!error || error.code !== 'P0409', 'E4 OFF: un cambio de DNI del propio cliente no tropieza con el candado (inerte)', errorText(error));
      await requireAdmin('E4 OFF: restaurar el dni del cliente de banca', admin.from('perfiles').update({ dni: dniActual }).eq('id', bankProfileId));
      check(cuenta('dni restaurado', `select count(*) from public.perfiles where id='${bankProfileId}' and dni = '${dniActual}'`) === 1,
        'E4 OFF: el dni del cliente de banca volvió al del fixture (la sonda de domicilio del siguiente ciclo depende de él)');
    }
    // ON: si el perfil está enlazado a una persona, el cambio real de documento se rechaza; el mismo documento con otro formato pasa.
    flag(true);
    const enlazado = cuenta('perfil de banca enlazado', `select count(*) from crm.inversionistas i where i.perfil_id='${bankProfileId}' and i.estado <> 'fusionado'`) === 1;
    if (enlazado) {
      await expectExpectedFailure('E4 ON: el propio cliente reconocido cambia su DNI → P0409 (solo Gerencia lo corrige)',
        sessions.clientBank.client.from('perfiles').update({ dni: '00000098' }).eq('id', bankProfileId).select('id'), ['P0409'], /solo se corrige desde el CRM/i);
      await expectExpectedFailure('E4 ON: el propio cliente reconocido envía id+dni juntos → P0409 (candado por OLD.id)',
        sessions.clientBank.client.from('perfiles').update({ id: '00000000-0000-4000-8000-0000000000e4', dni: '00000097' }).eq('id', bankProfileId).select('id'), ['P0409'], /solo se corrige desde el CRM/i);
      check(cuenta('dni intacto', `select count(*) from public.perfiles where id='${bankProfileId}' and dni is not distinct from ${dniActual ? `'${dniActual}'` : 'null'}`) === 1, 'E4 ON: el dni del cliente reconocido quedó intacto');
    } else {
      console.log('  (el cliente de banca del seed no está enlazado a una persona en esta base: se omiten los casos ON del candado)');
    }
    // ON: crear_contrato de un no autorizado sigue muriendo en el 42501 uniforme (la autoridad va ANTES del reconocimiento — auditor A1).
    await expectExpectedFailure('E4 ON: un cliente no registra ventas → 42501 uniforme, sin código documental',
      sessions.clientBank.client.rpc('crear_contrato', { p_contrato: { cliente_id: bankProfileId, moneda: 'PEN', capital: 1000, tasa_anual: 10, categoria: 'nuevo' }, p_cronograma: [] }),
      ['42501'], /cliente no encontrado o fuera de tu cartera/i);
    await expectExpectedFailure('E4 ON: un vendedor inactivo no registra ventas → 42501 uniforme',
      sessions.vendInactive.client.rpc('crear_contrato', { p_contrato: { cliente_id: bankProfileId, moneda: 'PEN', capital: 1000, tasa_anual: 10, categoria: 'nuevo' }, p_cronograma: [] }),
      ['42501'], /cliente no encontrado o fuera de tu cartera/i);
    check(cuenta('sin identidad fantasma', `select count(*) from crm.inversionistas i where i.perfil_id='${bankProfileId}' and i.estado <> 'fusionado'`) === (enlazado ? 1 : 0),
      'E4 ON: los rechazos no dejaron identidad nueva (sin efectos laterales persistentes)');
  } finally {
    flag(false);
  }
}

// ── F2.b [D-9] (20260906100000): los auditores genéricos de crm.leads y crm.cierres_externos no copian el documento ──
// Estructura (triggers exactos, trinquete, sello) y un lead sembrado fuera de banda cuyo rastro no lleva el DNI.
async function testIdentidadF2bD9() {
  console.log('\n— Identidad multiempresa F2.b [D-9]: auditores de leads/cierres sin documento —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-9: ${etiqueta}`, sql);
  const DEF_L = "CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''dni'', ''fecha_nacimiento'', ''genero'')";
  const DEF_C = "CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''documento'')";
  const def = (tabla, trg) => `(select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid='${tabla}'::regclass and t.tgname='${trg}' and not t.tgisinternal)`;
  if (cuenta('D-9 aplicada', `select (${def('crm.leads', 'trg_audit_leads')} like '%log_audit_sin_secretos%')::int`) !== 1) {
    console.log('  (saltado: D-9 (20260906100000) no está en esta base)');
    return;
  }
  check(cuenta('trigger leads', `select (${def('crm.leads', 'trg_audit_leads')} = '${DEF_L}')::int`) === 1,
    'D-9 trg_audit_leads es exactamente el de la migración (AFTER I/U/D, log_audit_sin_secretos(dni, fecha_nacimiento, genero))');
  check(cuenta('trigger cierres', `select (${def('crm.cierres_externos', 'trg_audit_cierres_externos')} = '${DEF_C}')::int`) === 1,
    'D-9 trg_audit_cierres_externos es exactamente el de la migración (log_audit_sin_secretos(documento))');
  check(cuenta('trinquete', `select count(*) from private.tablas_sin_rastro() s where s.tabla in ('crm.leads','crm.cierres_externos')`) === 0,
    'D-9 el trinquete de auditoría sigue viendo rastro completo en leads y cierres (reconoce al auditor por OID)');
  check(cuenta('sello', `select (exists (select 1 from private.auditoria_sello h where h.huella = private.huella_exenciones()))::int`) === 1,
    'D-9 el sello de exenciones cuadra (la migración no toca las listas)');
  check(cuenta('auditor definer', `select count(*) from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']`) === 1,
    'D-9 private.log_audit_sin_secretos sigue siendo DEFINER con search_path vacío');
  // Funcional, fuera de banda (writer interno, sin sesión): nace con DNI, se corrige, se desactiva. Ninguna fila lleva el documento.
  const leadId = randomUUID();
  const sufijo = String(Date.now()).slice(-6);
  const dni = `77${sufijo}`;
  ejecutarFueraDeBanda('D-9 fixture lead', `
    insert into crm.leads (id, nombre_completo, telefono, dni, fecha_nacimiento, genero, monto_estimado, origen, etapa, creado_por)
    values ('${leadId}', 'SUITE D-9', '97${sufijo}9', '${dni}', '1990-05-17', 'F', 1000, 'landing', 'nuevo', null);
    update crm.leads set nombre_completo = 'SUITE D-9 bis' where id = '${leadId}';
    update crm.leads set activo = false where id = '${leadId}';`);
  check(cuenta('filas del lead', `select count(*) from public.audit_log where tabla='crm.leads' and fila_id='${leadId}'`) >= 3,
    'D-9 el lead sembrado dejó rastro (INSERT + 2 UPDATE)');
  check(cuenta('dni en claro', `select count(*) from public.audit_log where tabla='crm.leads' and fila_id='${leadId}' and (coalesce(data_antes->>'dni','') = '${dni}' or coalesce(data_despues->>'dni','') = '${dni}')`) === 0,
    'D-9 ninguna fila de auditoría del lead lleva el DNI en claro');
  check(cuenta('dni enmascarado', `select count(*) from public.audit_log where tabla='crm.leads' and fila_id='${leadId}' and data_despues->>'dni' = '***'`) >= 1,
    'D-9 la clave dni sigue presente, enmascarada (***), en el rastro');
  check(cuenta('resto en claro', `select count(*) from public.audit_log where tabla='crm.leads' and fila_id='${leadId}' and data_despues->>'nombre_completo' = 'SUITE D-9 bis'`) >= 1,
    'D-9 las demás columnas siguen auditadas en claro (el cambio real queda)');
  check(cuenta('fecha/genero enmascarados', `select count(*) from public.audit_log where tabla='crm.leads' and fila_id='${leadId}' and (coalesce(data_despues->>'fecha_nacimiento','') = '1990-05-17' or coalesce(data_despues->>'genero','') = 'F')`) === 0
      && cuenta('telefono en claro', `select count(*) from public.audit_log where tabla='crm.leads' and fila_id='${leadId}' and data_despues->>'telefono' = '+5197${sufijo}9'`) >= 1,
    'D-9 fecha_nacimiento y genero enmascarados; el teléfono sigue en claro (decisión de Miguel 06/09)');
}

// ── F2.b [D-3] (20260906110000): el veto de la persona es coherente (tareas de perfil, ficha del cliente, sueltos/puente) ──
// Grants, marcadores, paridad OFF del helper y el gate REAL por la API: una tarea de cliente para una persona vetada.
// El negocio completo (marcar/levantar sobre sueltos y puente, cancelación de tareas de cliente, actividades_cliente)
// lo cubre scripts/oraculo-f2b-d3.sh.
async function testIdentidadF2bD3(sessions) {
  console.log('\n— Identidad multiempresa F2.b [D-3]: veto coherente (perfil, ficha, sueltos/puente) —');
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b D-3)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-3: ${etiqueta}`, sql);
  const marcador = (firma) => cuenta(`marcador ${firma}`, `select (strpos(p.prosrc, 'F2.b [D-3]') > 0)::int from pg_proc p where p.oid = '${firma}'::regprocedure`);
  const DEF_T = 'CREATE TRIGGER trg_actividades_cliente_01_veto_persona BEFORE INSERT ON crm.actividades_cliente FOR EACH ROW EXECUTE FUNCTION private.trg_actividades_cliente_veto_persona()';
  if (cuenta('D-3 aplicada', `select (to_regprocedure('private.persona_vetada_perfil(uuid)') is not null)::int`) !== 1) {
    console.log('  (saltado: D-3 (20260906110000) no está en esta base)');
    return;
  }
  const perfilId = randomUUID();
  const dni = `78${String(Date.now()).slice(-6)}`;
  const tarea = (cliente) => cliente.schema('crm').from('tareas').insert({
    perfil_id: perfilId, tipo: 'llamada', titulo: 'SUITE D-3', vence_en: new Date(Date.now() + 86400000).toISOString(),
    creado_por: cliente === sessions.vend1.client ? sessions.vend1.user.id : null,
  }).select('id').single();
  try {
    check(cuenta('grants RPC', `select count(*) from unnest(array['crm.marcar_no_contactar(uuid,text)','crm.levantar_no_contactar(uuid,text)']) f(firma)
      where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
         or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
         or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0)`) === 0,
      'D-3 marcar/levantar_no_contactar conservan sus grants (solo authenticated; ni anon, ni service_role, ni PUBLIC)');
    check(cuenta('helpers sin EXECUTE', `select count(*) from unnest(array['anon','authenticated','service_role']) r(rol), unnest(array['private.leads_de_persona_veto(uuid)','private.persona_vetada_perfil(uuid)','private.leads_vetados_persona(uuid[])']) f(firma) where has_function_privilege(r.rol, f.firma, 'EXECUTE')`) === 0,
      'D-3 los helpers privados no tienen EXECUTE para la API');
    check(cuenta('definer', `select count(*) from pg_proc p where p.oid in ('private.leads_de_persona_veto(uuid)'::regprocedure, 'private.persona_vetada_perfil(uuid)'::regprocedure, 'private.personas_de_perfil(uuid)'::regprocedure, 'private.trg_tareas_veto_persona_perfil()'::regprocedure, 'private.trg_actividades_cliente_veto_persona()'::regprocedure) and p.prosecdef and p.proconfig @> array['search_path=""']`) === 5,
      'D-3 los 5 objetos nuevos son DEFINER con search_path vacío');
    check(cuenta('trigger ficha', `select ((select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid='crm.actividades_cliente'::regclass and t.tgname='trg_actividades_cliente_01_veto_persona' and not t.tgisinternal and t.tgenabled in ('O','A')) = '${DEF_T}')::int`) === 1,
      'D-3 el trigger de la ficha del cliente está montado tal cual (BEFORE INSERT) y habilitado');
    check(cuenta('trigger tareas', `select ((select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid='crm.tareas'::regclass and t.tgname='trg_tareas_00_0_veto_persona' and not t.tgisinternal and t.tgenabled in ('O','A')) = 'CREATE TRIGGER trg_tareas_00_0_veto_persona BEFORE INSERT ON crm.tareas FOR EACH ROW EXECUTE FUNCTION private.trg_tareas_veto_persona_perfil()')::int`) === 1,
      'D-3 v3: el gate de las tareas de perfil es un trigger propio (00_0, corre primero) y está habilitado');
    check(marcador('crm.marcar_no_contactar(uuid,text)') + marcador('crm.levantar_no_contactar(uuid,text)') + marcador('private.leads_vetados_persona(uuid[])') === 3
        && cuenta('trg_gestion intacta', `select (md5(pg_get_functiondef(p.oid)) = '7af0e66b8a4849566e43b514245e1b86')::int from pg_proc p where p.oid = 'private.trg_gestion_lead_serializada()'::regprocedure`) === 1,
      'D-3 v3: las tres funciones vivas llevan la transformación y private.trg_gestion_lead_serializada sigue byte a byte (Codex #10)');
    // Fixture fuera de banda: persona Q verificada y VETADA; perfil cliente PF con su documento (sin enlace), asesor vend1.
    ejecutarFueraDeBanda('D-3 fixture', `
      select private.inversionista_resolver('DNI', '${dni}', true, 'suite_d3');
      update crm.inversionistas set no_contactar = true, no_contactar_en = now(), no_contactar_por = '${sessions.gerencia.user.id}'
       where id = private.inversionista_por_documento('DNI', '${dni}');
      insert into auth.users (id) values ('${perfilId}') on conflict (id) do nothing;
      insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, correo, asesor_perfil_id, activo)
      values ('${perfilId}', 'SUITE D-3 CLIENTE', 'cliente', 'DNI', '${dni}', 'suite-d3-${dni}@x.pe', '${sessions.vend1.user.id}', true);`);
    flag(false);
    check(cuenta('OFF helper', `select private.persona_vetada_perfil('${perfilId}')::int`) === 0,
      'D-3 OFF: persona_vetada_perfil es false aunque la persona esté vetada (paridad con hoy)');
    const { data: tareaOff, error: errOff } = await tarea(sessions.vend1.client);
    check(!errOff && tareaOff?.id, 'D-3 OFF: vend1 agenda una tarea de cliente para el perfil de la persona vetada (sin gate, como hoy)', errOff?.message ?? '');
    flag(true);
    check(cuenta('ON helper', `select private.persona_vetada_perfil('${perfilId}')::int`) === 1,
      'D-3 ON: persona_vetada_perfil ve el veto por el DOCUMENTO del perfil');
    await expectExpectedFailure('D-3 ON vend1 tarea de cliente para una persona vetada → P0429', tarea(sessions.vend1.client), ['P0429'], /No insistir/i);
    check(cuenta('ON sin tarea nueva', `select count(*) from crm.tareas where perfil_id='${perfilId}' and estado='pendiente'`) === 1,
      'D-3 ON: el rechazo no dejó tarea (solo sigue la de OFF)');
  } finally {
    flag(false);
    ejecutarFueraDeBanda('D-3 limpieza', `
      select set_config('crm.cancela_sistema', 'on', true);
      update crm.tareas set estado = 'cancelada' where perfil_id = '${perfilId}' and estado = 'pendiente';
      update public.perfiles set activo = false where id = '${perfilId}';
      update crm.inversionistas set no_contactar = false, no_contactar_en = null, no_contactar_por = null
       where id = private.inversionista_por_documento('DNI', '${dni}');`, { tolerante: true });
  }
}

// ── F2.b [D-2] (20260906120000): offboarding atómico sobre los tramos y capacidad operativa del nuevo responsable ──
// Grants, marcadores, y el contrato del front: con OFF el impacto lleva EXACTAMENTE las 7 claves de hoy (esquema estricto);
// con ON aparece personas_a_cargo. El negocio (tramos, ledger, cartera) lo cubre scripts/oraculo-f2b-d2.sh.
async function testIdentidadF2bD2(sessions) {
  console.log('\n— Identidad multiempresa F2.b [D-2]: offboarding atómico y capacidad del responsable —');
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b D-2)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-2: ${etiqueta}`, sql);
  const FIRMAS = ['crm.impacto_desactivacion_usuario_fn(uuid)', 'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)', 'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)'];
  const marcador = (firma) => cuenta(`marcador ${firma}`, `select (strpos(p.prosrc, 'F2.b [D-2]') > 0)::int from pg_proc p where p.oid = '${firma}'::regprocedure`);
  const impacto = (cliente, id) => cliente.schema('crm').rpc('impacto_desactivacion_usuario_fn', { p_perfil_id: id });
  const CLAVES_HOY = ['clientes_activos', 'leads_abiertos', 'leads_en_bandeja', 'perfil_id', 'requiere_reemplazo', 'subordinados_activos', 'tareas_pendientes'];
  if (cuenta('D-2 aplicada', `select (strpos(p.prosrc, 'F2.b [D-2]') > 0)::int from pg_proc p where p.oid = 'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)'::regprocedure`) !== 1) {
    console.log('  (saltado: D-2 (20260906120000) no está en esta base)');
    return;
  }
  try {
    check(cuenta('grants', `select count(*) from unnest(array['${FIRMAS.join("','")}']) f(firma)
      where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
         or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
         or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0)
         or not exists (select 1 from pg_proc p where p.oid = f.firma::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'])`) === 0,
      'D-2 las tres RPC conservan sus grants (solo authenticated) y son DEFINER con search_path vacío');
    check(FIRMAS.reduce((n, f) => n + marcador(f), 0) === 3, 'D-2 las tres funciones llevan la transformación (marcador en el cuerpo)');
    check(cuenta('conteo retirado', `select (to_regprocedure('crm.personas_por_responsable_fn(uuid)') is null)::int`) === 1,
      'D-2 crm.personas_por_responsable_fn no existe (un conteo no es un interlock; retirada en b5 v2)');
    check(cuenta('leads_de_personas', `select count(*) from pg_proc p where p.oid = 'private.leads_de_personas(uuid[])'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']`) === 1,
      'D-2 private.leads_de_personas (D-13), de la que depende la cartera, sigue DEFINER con search_path vacío');
    // OFF (producción): la respuesta del impacto es byte a byte la de hoy: exactamente las 7 claves del esquema estricto del front.
    flag(false);
    const { data: off, error: errOff } = await impacto(sessions.gerencia.client, sessions.vend1.user.id);
    check(!errOff && off && Object.keys(off).sort().join(',') === CLAVES_HOY.join(','),
      'D-2 OFF: impacto_desactivacion_usuario_fn devuelve EXACTAMENTE las 7 claves de hoy (ImpactoDesactivacionUsuarioSchema es strictObject)',
      errOff?.message ?? Object.keys(off ?? {}).sort().join(','));
    await expectExpectedFailure('D-2 OFF vend1 impacto → 42501 (solo Gerencia)', impacto(sessions.vend1.client, sessions.vend1.user.id), ['42501'], /Gerencia/i);
    // ON: aparece personas_a_cargo (entero ≥ 0) y requiere_reemplazo la incluye.
    flag(true);
    const { data: on, error: errOn } = await impacto(sessions.gerencia.client, sessions.vend1.user.id);
    check(!errOn && on && Number.isInteger(on.personas_a_cargo) && on.personas_a_cargo >= 0 && Object.keys(on).length === 8,
      'D-2 ON: impacto lleva personas_a_cargo (entero) además de las 7 claves de hoy', errOn?.message ?? '');
    check(!errOn && on && on.requiere_reemplazo === ((on.subordinados_activos + on.leads_abiertos + on.leads_en_bandeja + on.tareas_pendientes + on.clientes_activos + on.personas_a_cargo) > 0),
      'D-2 ON: requiere_reemplazo suma también las personas a cargo');
    await expectExpectedFailure('D-2 ON vend1 impacto → 42501 (solo Gerencia, antes de la bandera)', impacto(sessions.vend1.client, sessions.vend1.user.id), ['42501'], /Gerencia/i);
  } finally {
    flag(false);
  }
}

// ── F2.b [D-4] (20260906130000): el importador entra por la puerta SQL crm.importar_lead_fn ──
// Grants (solo service_role, sin sesión), definer/search_path/lock_timeout, y la puerta por la API con el cliente
// de servicio: importado → duplicado → 42501 para un humano. La paridad fila a fila con el INSERT directo (OFF y ON)
// la cubre scripts/oraculo-f2b-d4.sh.
async function testIdentidadF2bD4(sessions) {
  console.log('\n— Identidad multiempresa F2.b [D-4]: el importador entra por la puerta SQL —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-4: ${etiqueta}`, sql);
  const FIRMA = 'crm.importar_lead_fn(jsonb)';
  if (cuenta('D-4 aplicada', `select (to_regprocedure('${FIRMA}') is not null)::int`) !== 1) {
    console.log('  (saltado: D-4 (20260906130000) no está en esta base)');
    return;
  }
  const sufijo = String(Date.now()).slice(-6);
  const fila = {
    fila: 1, nombre_completo: 'SUITE D-4', telefono: `+5198${sufijo}1`, telefono_alternativo: null, telefono_alternativo_crudo: null,
    correo: null, dni: null, genero: null, fecha_nacimiento: null, distrito: null, origen: 'landing', etapa: 'nuevo',
    monto_estimado: 1000, moneda: 'PEN', categoria_interes: null, nota: null, no_contactar: false,
    consentimiento_en: null, consentimiento_fuente: null, vendedor_id: null, asignado_supervisor_id: null, activo: true,
  };
  let leadId = null;
  let leadPriv = null;
  try {
    check(cuenta('grants', `select (has_function_privilege('service_role', '${FIRMA}', 'EXECUTE'))::int - (has_function_privilege('anon', '${FIRMA}', 'EXECUTE'))::int - (has_function_privilege('authenticated', '${FIRMA}', 'EXECUTE'))::int - (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${FIRMA}'::regprocedure and a.grantee = 0)`) === 1,
      'D-4 la puerta solo tiene EXECUTE para service_role (ni anon, ni authenticated, ni PUBLIC)');
    check(cuenta('definer', `select count(*) from pg_proc p where p.oid = '${FIRMA}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s']`) === 1,
      'D-4 la puerta es DEFINER con search_path vacío y lock_timeout de 5 s');
    const { data: r1, error: e1 } = await admin.schema('crm').rpc('importar_lead_fn', { p_fila: fila });
    leadId = r1?.lead_id ?? null;
    check(!e1 && r1?.resultado === 'importado' && typeof leadId === 'string', 'D-4 service_role: una fila libre → importado con lead_id', e1?.message ?? JSON.stringify(r1));
    check(typeof leadId === 'string' && cuenta('nació como el edge', `select count(*) from crm.leads where id = '${leadId}' and creado_por is null and alta_manual = false and activo and etapa = 'nuevo' and vendedor_id is null and asignado_supervisor_id is null`) === 1,
      'D-4 la fila nace como con el INSERT del edge (sin sesión, cola global, alta_manual false)');
    const { data: r2, error: e2 } = await admin.schema('crm').rpc('importar_lead_fn', { p_fila: fila });
    check(!e2 && r2?.resultado === 'duplicado' && r2?.veredicto?.estado === 'duplicado', 'D-4 la misma fila otra vez → duplicado (lead vivo con ese teléfono), sin excepción', e2?.message ?? JSON.stringify(r2));
    await expectExpectedFailure('D-4 vend1 (authenticated) → 42501 (sin EXECUTE)', sessions.vend1.client.schema('crm').rpc('importar_lead_fn', { p_fila: fila }), ['42501'], /permission denied|denegado/i);
    await expectExpectedFailure('D-4 gerencia (authenticated) → 42501 (sin EXECUTE)', sessions.gerencia.client.schema('crm').rpc('importar_lead_fn', { p_fila: fila }), ['42501'], /permission denied|denegado/i);
    const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-d4'));
    await expectExpectedFailure('D-4 anon → 42501 (sin EXECUTE)', anon.schema('crm').rpc('importar_lead_fn', { p_fila: fila }), ['42501'], /permission denied|denegado/i);
    // v3 (auditor M3a): las claves privilegiadas del payload se IGNORAN; la puerta solo lee las columnas del edge.
    const FORJADO = '00000000-0000-4000-8000-0000000000d4';
    const { data: r4, error: e4 } = await admin.schema('crm').rpc('importar_lead_fn', { p_fila: { ...fila, telefono: `+5198${sufijo}3`, etapa: 'convertido', activo: false, no_contactar: true, alta_manual: true, creado_por: sessions.vend1.user.id, id: FORJADO, perfil_id: sessions.vend1.user.id, contrato_id: FORJADO, inversionista_id: FORJADO } });
    leadPriv = r4?.lead_id ?? null;
    check(!e4 && r4?.resultado === 'importado' && typeof leadPriv === 'string' && leadPriv !== FORJADO
      && cuenta('claves privilegiadas ignoradas', `select count(*) from crm.leads where id = '${leadPriv}' and etapa = 'nuevo' and activo and not no_contactar and alta_manual = false and creado_por is null and perfil_id is null and contrato_id is null and inversionista_id is null`) === 1,
      'D-4 las claves privilegiadas del payload (etapa, activo, no_contactar, alta_manual, creado_por, id, perfil_id, contrato_id, inversionista_id) se IGNORAN', e4?.message ?? JSON.stringify(r4));
    const { error: e3 } = await admin.schema('crm').rpc('importar_lead_fn', { p_fila: { ...fila, telefono: `+5198${sufijo}2`, dni: '123' } });
    check(e3?.code === '22023', 'D-4 un DNI que no es de 8 dígitos → 22023 (la puerta exige lo mismo que la fila al nacer)', e3?.message ?? 'sin error');
  } finally {
    const limpiar = [leadId, leadPriv].filter((x) => typeof x === 'string');
    if (limpiar.length) ejecutarFueraDeBanda('D-4 limpieza', `update crm.leads set activo = false where id in (${limpiar.map((x) => `'${x}'`).join(',')});`, { tolerante: true });
  }
}

// ── F2.b [D-17] (20260906160000) y [D-18] (20260906170000): las últimas puertas antes del encendido ──
// Superficie y marcadores; el comportamiento concurrente (el flip espera a cada puerta; la conversión espera a la
// baja del analista; la fusión cancela tareas de cliente) vive en scripts/oraculo-f2b-d17.sh y oraculo-f2b-d18.sh.
async function testIdentidadF2bD17yD18(sessions) {
  console.log('\n— Identidad multiempresa F2.b [D-17]/[D-18]: las últimas puertas antes del encendido —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-17/D-18: ${etiqueta}`, sql);
  const D17 = ['crm.marcar_no_contactar(uuid,text)', 'crm.levantar_no_contactar(uuid,text)', 'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'];
  const D18 = ['crm.convertir_lead(uuid,uuid)', 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'];
  const lista = (a) => a.map((f) => `'${f}'`).join(',');
  if (cuenta('D-17 aplicada', `select (select count(*) from pg_proc p where p.oid = 'crm.marcar_no_contactar(uuid,text)'::regprocedure and strpos(p.prosrc, 'F2.b [D-17]') > 0)`) !== 1) {
    console.log('  (saltado: D-17 (20260906160000) no está en esta base)');
    return;
  }
  check(cuenta('D-17 marcadores', `select count(*) from pg_proc p where p.oid = any(array[${lista(D17)}]::regprocedure[]) and strpos(p.prosrc, 'F2.b [D-17]') > 0`) === 3
      && cuenta('D-17 compartido', `select count(*) from pg_proc p where p.oid = any(array[${lista(D17)}]::regprocedure[]) and strpos(p.prosrc, 'crm_flag_resolver_en_puertas') > 0 and strpos(p.prosrc, 'read committed') > 0`) === 3,
    'D-17 las tres puertas (marcar, levantar, conversión en cooperativa) leen la bandera bajo el candado compartido y exigen READ COMMITTED');
  check(cuenta('D-17 grants', `select count(*) from unnest(array[${lista(D17)}]) f(firma) where has_function_privilege('authenticated', f.firma, 'EXECUTE') and not has_function_privilege('anon', f.firma, 'EXECUTE') and not has_function_privilege('service_role', f.firma, 'EXECUTE')`) === 3
      && cuenta('D-17 PUBLIC', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = any(array[${lista(D17)}]::regprocedure[]) and a.grantee = 0`) === 0,
    'D-17 las tres conservan sus grants (solo authenticated; ni anon, ni service_role, ni PUBLIC)');
  if (cuenta('D-18 aplicada', `select (select count(*) from pg_proc p where p.oid = 'crm.convertir_lead(uuid,uuid)'::regprocedure and strpos(p.prosrc, 'F2.b [D-18]') > 0)`) === 1) {
    check(cuenta('D-18 marcadores', `select count(*) from pg_proc p where p.oid = any(array[${lista(D18)}]::regprocedure[]) and strpos(p.prosrc, 'F2.b [D-18]') > 0`) === 2
        && cuenta('D-18 jerarquía', `select (strpos(p.prosrc, 'usuarios_jerarquia') > 0)::int from pg_proc p where p.oid = 'crm.convertir_lead(uuid,uuid)'::regprocedure`) === 1,
      'D-18 la conversión toma el interlock de jerarquía y la fusión cancela tareas de cliente (marcadores en el cuerpo)');
    check(cuenta('D-18 grants', `select count(*) from unnest(array[${lista(D18)}]) f(firma) where has_function_privilege('authenticated', f.firma, 'EXECUTE') and not has_function_privilege('anon', f.firma, 'EXECUTE') and not has_function_privilege('service_role', f.firma, 'EXECUTE')`) === 2
        && cuenta('D-18 PUBLIC', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = any(array[${lista(D18)}]::regprocedure[]) and a.grantee = 0`) === 0,
      'D-18 las dos conservan sus grants (solo authenticated; ni anon, ni service_role, ni PUBLIC)');
    // El interlock hace ESPERAR: sin lock_timeout la conversión se cuelga hasta el timeout de PostgREST (auditor D-18 #2).
    check(cuenta('D-18 lock_timeout', `select count(*) from pg_proc p where p.oid = 'crm.convertir_lead(uuid,uuid)'::regprocedure and p.proconfig @> array['lock_timeout=5s']`) === 1,
      'D-18 la conversión lleva lock_timeout, así que esperar detrás de un offboarding se corta con 55P03 y no cuelga la petición');
    // La cancelación de tareas de cliente tiene que quedar a nombre del SISTEMA, no de quien fusiona, y alcanzar a los
    // mismos perfiles que D-3 (identidad ∪ perfil cliente con el documento exacto ∪ perfil del lead) — auditor D-18 #3 y #8.
    check(cuenta('D-18 sello sistema', `select (strpos(p.prosrc, 'crm.cancela_sistema') > 0)::int from pg_proc p where p.oid = 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure`) === 1
        && cuenta('D-18 criterio de perfiles', `select (strpos(p.prosrc, 'any(v_docs)') > 0 and strpos(p.prosrc, 'v_perfiles_fusion') > 0)::int from pg_proc p where p.oid = 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure`) === 1,
      'D-18 la fusión cancela las tareas de cliente bajo el sello del sistema y con el criterio de perfiles de D-3');
    // Contador siempre presente (0 cuando no hay veto): el front no puede distinguir «no cancelé» de «no lo informo».
    check(cuenta('D-18 contador siempre', `select (strpos(p.prosrc, '''tareas_cliente_canceladas''') > 0)::int from pg_proc p where p.oid = 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure`) === 1,
      'D-18 la respuesta de la fusión informa siempre tareas_cliente_canceladas (0 si no hereda veto)');
  } else {
    console.log('  (D-18 (20260906190000) no está en esta base: se saltan sus aserciones)');
  }
  // El censo que justifica el DRENAJE del script de encendido: cuántas funciones leen la bandera y escriben sin el compartido.
  const sinCompartido = cuenta('funciones que leen la bandera y escriben sin el compartido', `select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm','private','public') and strpos(p.prosrc, 'resolver_en_puertas') > 0 and strpos(p.prosrc, 'crm_flag_resolver_en_puertas') = 0 and (strpos(p.prosrc, 'insert into') > 0 or strpos(p.prosrc, 'update ') > 0 or strpos(p.prosrc, 'delete from') > 0)`);
  if (cuenta('D-19 presente', `select (to_regprocedure('private.resolver_en_puertas_bajo_candado()') is not null)::int`) === 1) {
    console.log('  (censo de D-17/D-18 superado por D-19: lo vigila su propio bloque, que exige CERO)');
  } else {
    check(sinCompartido <= 14, `D-17/D-18: el censo de funciones que leen la bandera y escriben sin el candado compartido no crece (hoy ${sinCompartido})`);
  }
}

// ── F2.b [D-20] (20260906210000): el cliente que vuelve deja tarea a su analista ──
// La conducta (nota + tarea, idempotencia, atribución) la mide scripts/oraculo-f2b-d20.sh. Aquí se vigila la
// superficie: que el ayudante no esté expuesto y que el importador conserve su puerta cerrada a la API.
async function testIdentidadF2bD20(sessions, seed) {
  console.log('\n— Identidad multiempresa F2.b [D-20]: el cliente que vuelve no se pierde —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-20: ${etiqueta}`, sql);
  const AYUD = 'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)';
  if (cuenta('D-20 aplicada', `select (to_regprocedure('${AYUD}') is not null)::int`) !== 1) {
    console.log('  (saltado: D-20 (20260906210000) no está en esta base)');
    return;
  }
  check(cuenta('ayudante', `select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'registrar_solicitud_cliente_fn' and p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s']`) === 1,
    'D-20 el ayudante es DEFINER de postgres, VOLATILE, con search_path vacío y lock_timeout');
  check(cuenta('ayudante cerrado', `select (has_function_privilege('authenticated', '${AYUD}', 'EXECUTE') or has_function_privilege('anon', '${AYUD}', 'EXECUTE') or has_function_privilege('service_role', '${AYUD}', 'EXECUTE'))::int`) === 0
      && cuenta('ayudante PUBLIC', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${AYUD}'::regprocedure and a.grantee = 0`) === 0,
    'D-20 el ayudante no es llamable por la API: solo lo usa el importador, que corre como service_role sin sesión');
  check(cuenta('exige service_role y bandera', `select (strpos(p.prosrc, 'auth.uid()') > 0 and strpos(p.prosrc, 'resolver_en_puertas_bajo_candado') > 0)::int from pg_proc p where p.oid = '${AYUD}'::regprocedure`) === 1,
    'D-20 el ayudante exige que no haya sesión humana y lee la bandera bajo su candado (D-19)');
  // El documento NO puede acabar en la ficha ni en la tarea: la bitácora copia esas filas enteras (regla D-9).
  const SIN_DOC = "select (strpos(p.prosrc, '''dni''') = 0 and strpos(p.prosrc, 'documento') = 0)::int from pg_proc p where p.oid = '" + AYUD + "'::regprocedure";
  check(cuenta('sin documento en la nota', SIN_DOC) === 1,
    'D-20 el ayudante no escribe el documento en la nota ni en la tarea (la bitácora copia esas filas enteras)');
  check(cuenta('importador cerrado', `select (has_function_privilege('service_role', 'crm.importar_lead_fn(jsonb)', 'EXECUTE') and not has_function_privilege('authenticated', 'crm.importar_lead_fn(jsonb)', 'EXECUTE') and not has_function_privilege('anon', 'crm.importar_lead_fn(jsonb)', 'EXECUTE'))::int`) === 1
      && cuenta('importador marcador', `select (strpos(p.prosrc, 'F2.b [D-20]') > 0)::int from pg_proc p where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure`) === 1,
    'D-20 el importador conserva su puerta (solo service_role) y lleva la rama del cliente que vuelve');

  // ── Matriz de RLS sobre lo que D-20 crea (auditor D-20, cobertura) ──────────────────────────────
  // La nota y la tarea son datos nuevos en la ficha de un cliente: hay que fijar quién los ve y que
  // nadie los pueda editar ni borrar por la API.
  const cliente = seed.profileIdByKey[BANK_CLIENT.key];
  const asesor = cuenta('asesor del cliente de banca', `select count(*) from public.perfiles where id = '${cliente}' and asesor_perfil_id is not null`) === 1
    ? textoFueraDeBanda('asesor', `select asesor_perfil_id::text from public.perfiles where id = '${cliente}'`)
    : null;
  if (!asesor) {
    console.log('  (matriz RLS saltada: el cliente de banca del fixture no tiene analista asignado)');
  } else {
    const NOTA = '00000000-0000-4000-8000-0000000000d2';
    const TAREA = '00000000-0000-4000-8000-0000000000d3';
    ejecutarFueraDeBanda('D-20 fixture', `
      delete from crm.tareas where id = '${TAREA}';
      delete from crm.actividades_cliente where id = '${NOTA}';
      insert into crm.actividades_cliente (id, cliente_id, vendedor_id, tipo, detalle, creado_por)
      values ('${NOTA}', '${cliente}', '${asesor}', 'nota', 'D-20 visibilidad · Ref: fixture', null);
      insert into crm.tareas (id, perfil_id, tipo, titulo, vence_en, estado, creado_por)
      values ('${TAREA}', '${cliente}', 'llamada', 'D-20 visibilidad', now() + interval '1 day', 'pendiente', null);`);
    const ve = async (clave, tabla, id) => {
      const s = sessions[clave];
      if (!s) return null;
      const r = await s.client.schema('crm').from(tabla).select('id').eq('id', id);
      return r.error ? 0 : (r.data ?? []).length;
    };
    const asesorEsVend1 = cuenta('el analista del cliente es vend1', `select count(*) from public.perfiles where id = '${cliente}' and asesor_perfil_id = '${seed.profileIdByKey.vend1}'`) === 1;
    if (asesorEsVend1) {
      check(await ve('vend1', 'actividades_cliente', NOTA) === 1 && await ve('vend1', 'tareas', TAREA) === 1,
        'D-20 el analista de la cartera ve la nota y la tarea de la solicitud');
      check(await ve('vend2', 'actividades_cliente', NOTA) === 0 && await ve('vend2', 'tareas', TAREA) === 0,
        'D-20 un analista de otro subárbol no ve ni la nota ni la tarea');
      check(await ve('vendInactive', 'actividades_cliente', NOTA) === 0,
        'D-20 un miembro dado de baja no ve la nota');
    }
    check(await ve('gerencia', 'actividades_cliente', NOTA) === 1 && await ve('gerencia', 'tareas', TAREA) === 1,
      'D-20 Gerencia ve la solicitud y su tarea');
    const upd = await sessions.gerencia.client.schema('crm').from('actividades_cliente').update({ detalle: 'editada' }).eq('id', NOTA).select('id');
    check((upd.error !== null) || ((upd.data ?? []).length === 0),
      'D-20 la nota de la solicitud no se puede editar por la API (la ficha es append-only)');
    const del = await sessions.gerencia.client.schema('crm').from('actividades_cliente').delete().eq('id', NOTA).select('id');
    check((del.error !== null) || ((del.data ?? []).length === 0),
      'D-20 la nota de la solicitud no se puede borrar por la API');
    ejecutarFueraDeBanda('D-20 limpieza', `delete from crm.tareas where id = '${TAREA}'; delete from crm.actividades_cliente where id = '${NOTA}';`, { tolerante: true });
  }
}

// ── F2.b [D-19] (20260906200000): toda escritura lee la bandera bajo el candado del encendido ──
// El invariante es censal: NINGUNA función que escriba puede leer `resolver_en_puertas` sin tomar antes su candado
// compartido. Lo demás (que encender y apagar esperen a una escritura en vuelo) lo mide scripts/oraculo-f2b-d19.sh.
async function testIdentidadF2bD19(sessions) {
  console.log('\n— Identidad multiempresa F2.b [D-19]: ninguna escritura lee la bandera a ciegas —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-19: ${etiqueta}`, sql);
  const AYUDANTE = 'private.resolver_en_puertas_bajo_candado()';
  if (cuenta('D-19 aplicada', `select (to_regprocedure('${AYUDANTE}') is not null)::int`) !== 1) {
    console.log('  (saltado: D-19 (20260906200000) no está en esta base)');
    return;
  }
  check(cuenta('ayudante', `select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'resolver_en_puertas_bajo_candado' and p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']`) === 1,
    'D-19 el ayudante es SECURITY DEFINER de postgres, VOLATILE y con search_path vacío');
  check(cuenta('ayudante cerrado', `select (has_function_privilege('authenticated', '${AYUDANTE}', 'EXECUTE') or has_function_privilege('anon', '${AYUDANTE}', 'EXECUTE') or has_function_privilege('service_role', '${AYUDANTE}', 'EXECUTE'))::int`) === 0
      && cuenta('ayudante PUBLIC', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${AYUDANTE}'::regprocedure and a.grantee = 0`) === 0,
    'D-19 el ayudante no está expuesto a la API (lo llaman las SECURITY DEFINER de postgres, no PostgREST)');
  // No basta con que el candado esté: tiene que estar ANTES de la lectura. Un ayudante que leyera primero y
  // tomara el candado después dejaría intacta la carrera original y pasaría cualquier prueba de tiempos
  // (auditor D-17 #3 y Codex #2), porque el candado es de transacción y retiene igual. Aquí se compara la POSICIÓN.
  check(cuenta('ayudante exige READ COMMITTED', `select (strpos(p.prosrc, 'read committed') > 0)::int from pg_proc p where p.oid = '${AYUDANTE}'::regprocedure`) === 1
      && cuenta('candado antes de la lectura', `select (strpos(p.prosrc, 'pg_advisory_xact_lock_shared') > 0 and strpos(p.prosrc, 'pg_advisory_xact_lock_shared') < strpos(p.prosrc, 'from crm.multiempresa_flags'))::int from pg_proc p where p.oid = '${AYUDANTE}'::regprocedure`) === 1,
    'D-19 el ayudante exige READ COMMITTED y toma el compartido ANTES de leer la bandera, no después');
  // EL invariante. Si alguien añade una escritora que lee la bandera suelta, esto se pone rojo el mismo día.
  const sueltas = cuenta('lectoras sin candado', `select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm','private','public') and strpos(p.prosrc, 'resolver_en_puertas') > 0 and strpos(p.prosrc, 'crm_flag_resolver_en_puertas') = 0 and strpos(p.prosrc, 'resolver_en_puertas_bajo_candado') = 0`);
  check(sueltas === 0, `D-19 ninguna función lee la bandera sin su candado compartido (hoy ${sueltas})`);
  // Contar no basta: se podría revertir una y adoptar otra distinta y el total no se movería (auditor #M4.4).
  // Se comprueban las 34 firmas, una a una.
  const D19 = ['crm.actualizar_cliente_gerencia(uuid,jsonb)', 'crm.alta_cliente_identidad_fn(text,jsonb)', 'crm.auth_usuario_por_correo_fn(text)',
    'crm.cliente_eliminable_fn(uuid)', 'crm.convertir_lead(uuid,uuid)', 'crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)',
    'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', 'crm.eliminar_cliente_fn(uuid)', 'crm.enlazar_lead_inversionista_fn(uuid,uuid,text)',
    'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)', 'crm.fusion_previsualizar_fn(uuid,uuid)', 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)',
    'crm.impacto_desactivacion_usuario_fn(uuid)', 'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)', 'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)',
    'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'crm.saga_conversion_fn(text,jsonb)', 'private.bloquear_personas_de_leads(uuid[],text)',
    'private.enlazar_lead_reabierto(uuid,uuid)', 'private.identidad_bloquear_documento(text,text)', 'private.identidad_bloquear_persona(text,text)',
    'private.leads_por_repartir_implementacion()', 'private.leads_vetados_persona(uuid[])', 'private.persona_vetada_perfil(uuid)',
    'private.trg_leads_disponibilidad_atomica()', 'private.trg_leads_hereda_veto_persona()', 'private.trg_leads_no_contactar_solo_puerta()',
    'private.trg_leads_zz_enlaza_identidad()', 'private.trg_leads_zz_puente_identidad()', 'private.trg_leads_zz_reapertura_solo_rpc()',
    'private.trg_perfiles_documento_protegido()', 'private.trg_tareas_veto_persona_perfil()', 'private.verificar_disponibilidad_lead_impl(text,text,uuid)',
    'public.crear_contrato(jsonb,jsonb)'];
  const listaD19 = D19.map((f) => `'${f}'`).join(',');
  check(cuenta('las 34 la llaman', `select count(*) from unnest(array[${listaD19}]) f(firma) where exists (select 1 from pg_proc p where p.oid = to_regprocedure(f.firma) and strpos(p.prosrc, 'resolver_en_puertas_bajo_candado') > 0)`) === D19.length,
    `D-19 las ${D19.length} funciones que leen la bandera (escrituras, disparadores, ayudantes de bloqueo y consultas) pasan por el ayudante`);
  // public.crear_contrato es la puerta compartida con el Portal: ni permisos, ni definer, ni dueño, ni search_path.
  check(cuenta('crear_contrato intacta', `select count(*) from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""'] and has_function_privilege('authenticated', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE') and has_function_privilege('service_role', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE')`) === 1,
    'D-19 public.crear_contrato conserva permisos, definer, dueño y search_path: el alta del Portal sigue entrando igual');
}

// ── F2.b [D-15] (20260906150000): el botón «Reabrir» pasa por la puerta crm.reabrir_lead_fn ──
// Grants, definer, superficie y paridad apagada (el negocio encendido —persona, veto, enlace— lo cubre scripts/oraculo-f2b-d15.sh).
async function testIdentidadF2bD15(sessions, seed) {
  console.log('\n— Identidad multiempresa F2.b [D-15]: «Reabrir» por su puerta SQL —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-15: ${etiqueta}`, sql);
  const FIRMA = 'crm.reabrir_lead_fn(uuid)';
  if (cuenta('D-15 aplicada', `select (to_regprocedure('${FIRMA}') is not null)::int`) !== 1) {
    console.log('  (saltado: D-15 (20260906150000) no está en esta base)');
    return;
  }
  const LEAD_INEXISTENTE = '00000000-0000-4000-8000-000000000d15';
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-d15'));
  const vend1Id = seed.profileIdByKey.vend1;
  const vend2Id = seed.profileIdByKey.vend2;
  const L_V1 = randomUUID();
  const L_V2 = randomUUID();
  try {
    check(cuenta('grants', `select (has_function_privilege('authenticated', '${FIRMA}', 'EXECUTE'))::int - (has_function_privilege('anon', '${FIRMA}', 'EXECUTE'))::int - (has_function_privilege('service_role', '${FIRMA}', 'EXECUTE'))::int - (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${FIRMA}'::regprocedure and a.grantee = 0)`) === 1,
      'D-15 la puerta solo tiene EXECUTE para authenticated (ni anon, ni service_role, ni PUBLIC)');
    check(cuenta('definer', `select count(*) from pg_proc p where p.oid = '${FIRMA}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole`) === 1,
      'D-15 la puerta es DEFINER de postgres con search_path vacío y lock_timeout de 5 s');
    check(cuenta('trigger reapertura', `select count(*) from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_reapertura_solo_rpc' and tgenabled='O'`) === 1,
      'D-15 la premisa sigue: el trigger «reabrir solo por RPC» (D-13) está habilitado');
    await expectExpectedFailure('D-15 anon → 42501 (sin EXECUTE)', anon.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: LEAD_INEXISTENTE }), ['42501'], /permission denied|denegado/i);
    for (const clave of ['coordinador', 'directorio', 'clientBank', 'vendInactive']) {
      await expectExpectedFailure(`D-15 ${clave} → 42501 (no reabre: sin rol vendedor/supervisor/gerencia)`, sessions[clave].client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: LEAD_INEXISTENTE }), ['42501'], /reabre un lead/i);
    }
    await expectExpectedFailure('D-15 vend1 sobre un lead inexistente → P0002 (sin revelar existencia)', sessions.vend1.client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: LEAD_INEXISTENTE }), ['P0002'], /no encontrado/i);
    await expectExpectedFailure('D-15 vend1 con lead nulo → 22023', sessions.vend1.client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: null }), ['22023'], /obligatorio/i);
    // Paridad apagada con leads de verdad: ámbito (P0002 sin sondear), solo descartados (P0409) y reapertura = el UPDATE de hoy.
    // Un lead no nace descartado (trigger): nace nuevo y lo descarta su analista por el camino del front (UPDATE bajo RLS).
    const base = { activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'otro', monto_estimado: 5000 };
    await requireAdmin('D-15: sembrar dos leads nuevos (vend1 y vend2)', admin.schema('crm').from('leads').insert([
      { ...base, id: L_V1, nombre_completo: 'D15 REABRIR V1 TRANSIENT', telefono: TEL_F2B(191), creado_por: vend1Id, vendedor_id: vend1Id },
      { ...base, id: L_V2, nombre_completo: 'D15 REABRIR V2 TRANSIENT', telefono: TEL_F2B(192), creado_por: vend2Id, vendedor_id: vend2Id },
    ]));
    await requireAdmin('D-15: vend1 descarta el suyo', sessions.vend1.client.schema('crm').from('leads').update({ etapa: 'descartado', motivo_descarte: 'sin_interes' }).eq('id', L_V1));
    await requireAdmin('D-15: vend2 descarta el suyo', sessions.vend2.client.schema('crm').from('leads').update({ etapa: 'descartado', motivo_descarte: 'sin_interes' }).eq('id', L_V2));
    check(cuenta('descartados sembrados', `select count(*) from crm.leads where id in ('${L_V1}','${L_V2}') and etapa = 'descartado' and descartado_por is not null`) === 2, 'D-15 los dos leads quedaron descartados por sus analistas (sello estampado)');
    await expectExpectedFailure('D-15 OFF vend1 reabre un lead de vend2 → P0002 (fuera de ámbito)', sessions.vend1.client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: L_V2 }), ['P0002'], /no encontrado/i);
    const { data: r1, error: e1 } = await sessions.vend1.client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: L_V1 });
    check(!e1 && r1?.ok === true && r1?.etapa === 'nuevo' && r1?.enlazado === false && r1?.reabierto_por === vend1Id,
      'D-15 OFF vend1 reabre el suyo → ok, etapa nuevo, sin enlace, atribuido a vend1', e1?.message ?? JSON.stringify(r1));
    check(cuenta('foto tras reabrir', `select count(*) from crm.leads l where l.id = '${L_V1}' and l.etapa = 'nuevo' and l.motivo_descarte is null and l.descartado_en is null and l.descartado_por is null and l.inversionista_id is null and exists (select 1 from crm.actividades a where a.lead_id = l.id and a.tipo = 'cambio_etapa' and a.detalle = 'descartado → nuevo' and a.creado_por = '${vend1Id}')`) === 1,
      'D-15 OFF la foto es la del UPDATE de hoy: motivo y sello limpios, actividad «descartado → nuevo» atribuida al analista');
    await expectExpectedFailure('D-15 vend1 reabre un lead que ya está abierto → P0409', sessions.vend1.client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: L_V1 }), ['P0409'], /solo se puede reabrir un lead descartado/i);
    const { data: r2, error: e2 } = await sessions.gerencia.client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: L_V2 });
    check(!e2 && r2?.ok === true && r2?.etapa === 'nuevo', 'D-15 OFF gerencia reabre el de vend2 (ámbito global)', e2?.message ?? JSON.stringify(r2));
    // Ámbito jerárquico: el supervisor reabre un lead de SU analista (vend1 cuelga de sup1 en el seed).
    await requireAdmin('D-15: vend1 vuelve a descartar el suyo', sessions.vend1.client.schema('crm').from('leads').update({ etapa: 'descartado', motivo_descarte: 'sin_interes' }).eq('id', L_V1));
    const { data: r3, error: e3 } = await sessions.sup1.client.schema('crm').rpc('reabrir_lead_fn', { p_lead_id: L_V1 });
    check(!e3 && r3?.ok === true && r3?.etapa === 'nuevo' && r3?.reabierto_por === seed.profileIdByKey.sup1, 'D-15 OFF sup1 reabre el lead de su analista vend1 (ámbito jerárquico), atribuido a sup1', e3?.message ?? JSON.stringify(r3));
    // crm.editar_lead_fn (v3, Codex bloque 4 #1): INVOKER — el UPDATE de hoy con la RLS de quien edita, en UNA transacción.
    const FE = 'crm.editar_lead_fn(uuid,jsonb)';
    check(cuenta('editar grants', `select (has_function_privilege('authenticated', '${FE}', 'EXECUTE'))::int - (has_function_privilege('anon', '${FE}', 'EXECUTE'))::int - (has_function_privilege('service_role', '${FE}', 'EXECUTE'))::int - (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${FE}'::regprocedure and a.grantee = 0)`) === 1
        && cuenta('editar invoker', `select count(*) from pg_proc p where p.oid = '${FE}'::regprocedure and not p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s']`) === 1,
      'D-15 editar_lead_fn: solo authenticated, SECURITY INVOKER (la RLS y los grants por columna mandan), search_path vacío, lock_timeout 5 s');
    await expectExpectedFailure('D-15 anon editar_lead_fn → 42501 (sin EXECUTE)', anon.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { nota: 'x' } }), ['42501'], /permission denied|denegado/i);
    await expectExpectedFailure('D-15 vend1 edita un lead de vend2 → P0002 (la RLS no lo ve; nada escrito)', sessions.vend1.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V2, p_cambios: { nota: 'ajena' } }), ['P0002'], /no encontrado/i);
    await expectExpectedFailure('D-15 vend1 manda una clave fuera de la lista blanca (etapa) → 22023', sessions.vend1.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { etapa: 'convertido' } }), ['22023'], /no editable/i);
    const { data: r4, error: e4 } = await sessions.vend1.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { nota: 'editada por su analista', dni: null, distrito: 'Lima' } });
    check(!e4 && r4?.ok === true && r4?.dni_por_puerta === false && cuenta('editada', `select count(*) from crm.leads where id = '${L_V1}' and nota = 'editada por su analista' and distrito = 'Lima' and dni is null`) === 1,
      'D-15 OFF vend1 edita el suyo por editar_lead_fn → escrito (nota, distrito, dni null), dni_por_puerta=false (el UPDATE de hoy)', e4?.message ?? JSON.stringify(r4));
    await expectExpectedFailure('D-15 vend1 editar_lead_fn sin cambios ({}) → 22023', sessions.vend1.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: {} }), ['22023'], /sin cambios|inválidos/i);
    // Matriz de roles (auditor v5 #3): los que no ven el lead (RLS) → P0002 sin sondear; los jerárquicos escriben.
    for (const clave of ['coordinador', 'directorio', 'clientBank', 'vendInactive']) {
      await expectExpectedFailure(`D-15 ${clave} editar_lead_fn sobre el lead de vend1 → P0002 (la RLS no se lo muestra)`, sessions[clave].client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { nota: 'ajena' } }), ['P0002'], /no encontrado/i);
    }
    const { data: r5, error: e5 } = await sessions.sup1.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { nota: 'editada por el supervisor' } });
    check(!e5 && r5?.ok === true && cuenta('editada sup1', `select count(*) from crm.leads where id = '${L_V1}' and nota = 'editada por el supervisor'`) === 1, 'D-15 OFF sup1 edita el lead de su analista (ámbito jerárquico)', e5?.message ?? JSON.stringify(r5));
    const { data: r6, error: e6 } = await sessions.gerencia.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V2, p_cambios: { nota: 'editada por gerencia' } });
    check(!e6 && r6?.ok === true && cuenta('editada gerencia', `select count(*) from crm.leads where id = '${L_V2}' and nota = 'editada por gerencia'`) === 1, 'D-15 OFF gerencia edita el de vend2 (ámbito global)', e6?.message ?? JSON.stringify(r6));
    // Camino ENCENDIDO en la suite (auditor v5 #3): el DNI por su puerta y el resto en UNA transacción; si el resto choca, el DNI tampoco queda.
    const flagD15 = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b D-15)', `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
    const DNI_LIBRE = `7${RUN_IDENTIDAD}191`;
    flagD15(true);
    try {
      const { error: e7 } = await sessions.vend1.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { dni: DNI_LIBRE, telefono: TEL_F2B(192) } });
      check(!!e7 && ['P0481', '23505'].includes(String(e7.code)) && cuenta('dni no quedó', `select count(*) from crm.leads where id = '${L_V1}' and dni is null`) === 1,
        'D-15 ON: DNI nuevo + teléfono de OTRO lead vivo → el resto choca y el DNI tampoco queda (una transacción)', e7?.message ?? 'aceptado');
      const { data: r8, error: e8 } = await sessions.vend1.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { dni: DNI_LIBRE, nota: 'con documento por su puerta' } });
      check(!e8 && r8?.ok === true && r8?.dni_por_puerta === true && cuenta('dni y nota', `select count(*) from crm.leads where id = '${L_V1}' and dni = '${DNI_LIBRE}' and nota = 'con documento por su puerta'`) === 1,
        'D-15 ON: DNI libre + nota → el DNI por su puerta (dni_por_puerta=true) y la nota en la misma transacción', e8?.message ?? JSON.stringify(r8));
      // coordinador no ve el lead (P0002 antes de llamar a la puerta); directorio (lector global) lo VE pero no tiene rol CRM
      // que edite: la puerta del DNI lo rechaza con 42501 antes de tocar nada.
      await expectExpectedFailure('D-15 ON coordinador editar_lead_fn con otro DNI → P0002 (la RLS no muestra el lead; la puerta del DNI no llega a llamarse)', sessions.coordinador.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { dni: `7${RUN_IDENTIDAD}193` } }), ['P0002'], /no encontrado/i);
      await expectExpectedFailure('D-15 ON directorio editar_lead_fn con otro DNI → 42501 (lo ve como lector global, pero la puerta del DNI exige rol CRM que edite)', sessions.directorio.client.schema('crm').rpc('editar_lead_fn', { p_lead_id: L_V1, p_cambios: { dni: `7${RUN_IDENTIDAD}193` } }), ['42501', 'P0002'], /revocado|no encontrado/i);
    } finally {
      flagD15(false);
    }
    check(cuenta('sin identidad fantasma (editar)', `select count(*) from crm.inversionista_identificadores where documento_normalizado in ('${DNI_LIBRE}', '7${RUN_IDENTIDAD}193')`) === 0, 'D-15: editar_lead_fn no crea identidades');
    check(cuenta('flag trigger', `select count(*) from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid = 'crm.multiempresa_flags'::regclass and t.tgname = 'trg_multiempresa_flags_00_serializa_puertas' and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = 'CREATE TRIGGER trg_multiempresa_flags_00_serializa_puertas BEFORE UPDATE OF activo ON crm.multiempresa_flags FOR EACH ROW EXECUTE FUNCTION private.trg_multiempresa_flags_serializa_puertas()' and not has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE') and not has_function_privilege('service_role', p.oid, 'EXECUTE')`) === 1,
      'D-5 el trigger que serializa el cambio de bandera está exactamente como lo genera gen-d5.py (BEFORE UPDATE OF activo, FOR EACH ROW) y su función sin EXECUTE para la API');
    check(cuenta('flags sin privilegios API', `select count(*) from unnest(array['anon','authenticated','service_role']) r(rol) where has_table_privilege(r.rol, 'crm.multiempresa_flags', 'UPDATE') or has_table_privilege(r.rol, 'crm.multiempresa_flags', 'INSERT') or has_table_privilege(r.rol, 'crm.multiempresa_flags', 'DELETE')`) === 0,
      'D-5 ningún rol de la API escribe crm.multiempresa_flags (el cambio de bandera es solo de postgres)');
    await expectExpectedFailure('D-5 gerencia intenta encender la bandera por PostgREST → 42501', sessions.gerencia.client.schema('crm').from('multiempresa_flags').update({ activo: true }).eq('nombre', 'resolver_en_puertas'), ['42501'], /permission denied|denegado/i);
    // Los caminos ENCENDIDOS de abandonar_conversion_gerencia_fn (borrado, auth_creado → retoma, enlazado, «no corresponden», Auth con la
    // marca del claim) y de reabrir (enlace, veto, otro lead, conversión en curso) viven en scripts/oraculo-f2b-d5.sh y oraculo-f2b-d15.sh.
  } finally {
    ejecutarFueraDeBanda('D-15 limpieza', `update crm.leads set activo = false where id in ('${L_V1}','${L_V2}');`, { tolerante: true });
  }
}

// ── RENTABILIDAD R1 (20260906170000): política versionada, núcleo private.resolver_tasa por su puerta, solicitudes de tasa y ledger ──
// Grants, definer, RLS estructural, superficie 42501 y D3. El flujo de negocio completo (pedir → aprobar/rechazar/aprobar hasta X →
// aceptar/declinar, herencia en renovación/upgrade, vencimiento, política) vive en scripts/oraculo-rentabilidad-r1.sh (115 aserciones).
async function testRentabilidadR1(sessions, seed) {
  console.log('\n— Rentabilidad R1: núcleo de tasa, solicitudes y ledger —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`Rentabilidad R1: ${etiqueta}`, sql);
  const PUERTAS = ['crm.resolver_tasa_fn(uuid,text,uuid)', 'crm.solicitar_tasa_fn(jsonb)', 'crm.resolver_solicitud_tasa_fn(uuid,text,numeric,text)',
    'crm.responder_tope_tasa_fn(uuid,boolean,text)', 'crm.publicar_politica_rentabilidad_fn(integer,jsonb)'];
  const PRIVADAS = ['private.resolver_tasa(uuid,text,uuid,timestamptz)', 'private.politica_rentabilidad_vigente(timestamptz)', 'private.puede_operar_tasa_cliente(uuid)',
    'private.huella_solicitud_tasa(uuid,text,uuid,uuid,numeric,text,text,text,date,date)', 'private.vencer_solicitudes_tasa(uuid)'];
  if (cuenta('R1 aplicada', `select (to_regprocedure('${PUERTAS[0]}') is not null)::int`) !== 1) {
    console.log('  (saltado: Rentabilidad R1 (20260906170000) no está en esta base)');
    return;
  }
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-r1'));
  const clienteId = seed.profileIdByKey.clientBank;
  const gerenciaId = seed.profileIdByKey.gerencia;
  const vend1Id = seed.profileIdByKey.vend1;
  let solicitudId = null;
  let solicitudV1 = null;
  try {
    for (const f of PUERTAS) {
      check(cuenta(`grants ${f}`, `select (has_function_privilege('authenticated', '${f}', 'EXECUTE'))::int - (has_function_privilege('anon', '${f}', 'EXECUTE'))::int - (has_function_privilege('service_role', '${f}', 'EXECUTE'))::int - (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${f}'::regprocedure and a.grantee = 0)::int`) === 1,
        `R1 ${f} solo tiene EXECUTE para authenticated (ni anon, ni service_role, ni PUBLIC)`);
      check(cuenta(`definer ${f}`, `select count(*) from pg_proc p where p.oid = '${f}'::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']`) === 1,
        `R1 ${f} es DEFINER de postgres con search_path vacío`);
    }
    for (const f of PRIVADAS) {
      check(cuenta(`privada ${f}`, `select (has_function_privilege('authenticated', '${f}', 'EXECUTE'))::int + (has_function_privilege('anon', '${f}', 'EXECUTE'))::int + (has_function_privilege('service_role', '${f}', 'EXECUTE'))::int + (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${f}'::regprocedure and a.grantee = 0)::int`) === 0,
        `R1 ${f} no es llamable por la API ni por PUBLIC`);
    }
    check(cuenta('RLS tablas', `select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'crm' and c.relname in ('politica_rentabilidad','solicitudes_tasa','ledger_rentabilidad') and c.relrowsecurity`) === 3,
      'R1 las tres tablas tienen RLS encendida');
    check(cuenta('policies', `select count(*) from pg_policies where schemaname = 'crm' and tablename in ('politica_rentabilidad','solicitudes_tasa','ledger_rentabilidad') and cmd = 'SELECT'`) === 3
      && cuenta('policies no-select', `select count(*) from pg_policies where schemaname = 'crm' and tablename in ('politica_rentabilidad','solicitudes_tasa','ledger_rentabilidad') and cmd <> 'SELECT'`) === 0,
      'R1 exactamente una policy SELECT por tabla y ninguna de escritura');
    check(cuenta('privilegios tabla', `select (has_table_privilege('authenticated','crm.solicitudes_tasa','INSERT'))::int + (has_table_privilege('authenticated','crm.solicitudes_tasa','UPDATE'))::int + (has_table_privilege('authenticated','crm.ledger_rentabilidad','INSERT'))::int + (has_table_privilege('authenticated','crm.politica_rentabilidad','INSERT'))::int + (has_table_privilege('anon','crm.solicitudes_tasa','SELECT'))::int + (has_table_privilege('anon','crm.ledger_rentabilidad','SELECT'))::int`) === 0,
      'R1 authenticated no escribe en las tablas y anon no lee nada');
    check(cuenta('política v1', `select count(*) from crm.politica_rentabilidad where version = 1 and modo = 'observacion'`) === 1, 'R1 la política v1 existe en modo observación');
    check(cuenta('legacy coherente', `select count(*) from crm.ledger_rentabilidad l join public.contratos c on c.id = l.contrato_id where l.origen = 'backfill_legacy' and (l.tasa_final <> c.tasa_anual or l.divergente or l.regla <> 'historica_legacy')`) === 0,
      'R1 cada fila legacy del ledger coincide con la tasa del contrato y no es divergente');
    check(cuenta('triggers', `select count(*) from pg_trigger t where not t.tgisinternal and t.tgenabled = 'O' and t.tgname in ('trg_politica_rentabilidad_inmutable','trg_audit_politica_rentabilidad','trg_solicitudes_tasa_00_solo_por_puerta','trg_audit_solicitudes_tasa','trg_ledger_rentabilidad_00_append_only','trg_audit_ledger_rentabilidad')`) === 6,
      'R1 los seis triggers (inmutable, auditoría, solo-por-puerta, append-only) están habilitados');
    // Superficie: sin sesión y sin la autoridad del alta → 42501 uniforme.
    await expectExpectedFailure('R1 anon resolver_tasa_fn → 42501', anon.schema('crm').rpc('resolver_tasa_fn', { p_cliente_id: clienteId, p_categoria: 'nuevo' }), ['42501'], /permission denied|denegado|fuera de tu cartera/i);
    for (const clave of ['coordinador', 'directorio', 'clientBank', 'vendInactive']) {
      await expectExpectedFailure(`R1 ${clave} resolver_tasa_fn → 42501 (sin la autoridad del alta o sin ámbito)`, sessions[clave].client.schema('crm').rpc('resolver_tasa_fn', { p_cliente_id: clienteId, p_categoria: 'nuevo' }), ['42501'], /fuera de tu cartera/i);
    }
    await expectExpectedFailure('R1 gerencia resolver_tasa_fn con cliente inexistente → 42501 uniforme (no P0002)', sessions.gerencia.client.schema('crm').rpc('resolver_tasa_fn', { p_cliente_id: '00000000-0000-4000-8000-0000000000a1', p_categoria: 'nuevo' }), ['42501'], /fuera de tu cartera/i);
    const { data: r1, error: e1 } = await sessions.gerencia.client.schema('crm').rpc('resolver_tasa_fn', { p_cliente_id: clienteId, p_categoria: 'nuevo' });
    check(!e1 && r1?.regla === 'primera_inversion' && Number(r1?.tasa_base) > 0 && r1?.politica?.modo === 'observacion',
      'R1 gerencia resuelve la tasa de un cliente: primera_inversion, base de la política vigente (observación)', e1?.message ?? JSON.stringify(r1));
    // Decisión B (la del alta): cualquier analista/supervisor vigente resuelve la tasa de cualquier cliente ACTIVO.
    for (const clave of ['vend1', 'sup1']) {
      const { data: rr, error: ee } = await sessions[clave].client.schema('crm').rpc('resolver_tasa_fn', { p_cliente_id: clienteId, p_categoria: 'nuevo' });
      check(!ee && rr?.regla === 'primera_inversion' && Number(rr?.tasa_base) === Number(r1?.tasa_base),
        `R1 ${clave} resuelve la tasa del cliente (la autoridad del alta, sin ámbito de cartera) con la misma base`, ee?.message ?? JSON.stringify(rr));
    }
    await expectExpectedFailure('R1 gerencia nuevo con contrato origen → 22023', sessions.gerencia.client.schema('crm').rpc('resolver_tasa_fn', { p_cliente_id: clienteId, p_categoria: 'nuevo', p_contrato_origen_id: '00000000-0000-4000-8000-0000000000a2' }), ['22023'], /primera inversión no lleva/i);
    await expectExpectedFailure('R1 gerencia renovación sin origen → 22023', sessions.gerencia.client.schema('crm').rpc('resolver_tasa_fn', { p_cliente_id: clienteId, p_categoria: 'renovacion' }), ['22023'], /contrato origen/i);
    // Solicitud: gerencia pide (tiene la autoridad del alta) y NO puede resolver la suya (D3); el resto no resuelve (42501).
    const base = Number(r1?.tasa_base ?? 15);
    // Capital único por corrida: la unicidad es por HUELLA (D6), y una corrida anterior o una sesión ajena pudo dejar
    // una solicitud viva sobre la misma intención en el banco compartido.
    const capitalCorrida = 10000 + Math.floor(Math.random() * 8_999_999) / 100;
    const cuerpo = { cliente_id: clienteId, categoria: 'nuevo', capital: capitalCorrida, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple', fecha_inicio: '2026-11-01', fecha_vencimiento: '2027-11-01', tasa_solicitada: base + 1.5, motivo: 'Suite RLS R1 TRANSIENT: prueba de solicitud' };
    const { data: s1, error: es1 } = await sessions.gerencia.client.schema('crm').rpc('solicitar_tasa_fn', { p_solicitud: cuerpo });
    solicitudId = s1?.id ?? null;
    check(!es1 && s1?.estado === 'pendiente' && Number(s1?.tasa_base) === base && s1?.solicitada_por === gerenciaId,
      'R1 gerencia crea una solicitud pendiente con la base del núcleo', es1?.message ?? JSON.stringify(s1));
    if (solicitudId) {
      await expectExpectedFailure('R1 misma huella otra vez → P0409', sessions.gerencia.client.schema('crm').rpc('solicitar_tasa_fn', { p_solicitud: cuerpo }), ['P0409'], /solicitud viva/i);
      await expectExpectedFailure('R1 D6: vend1 tampoco abre otra sobre la MISMA intención (una viva por huella) → P0409', sessions.vend1.client.schema('crm').rpc('solicitar_tasa_fn', { p_solicitud: { ...cuerpo, tasa_solicitada: base + 2 } }), ['P0409'], /solicitud viva/i);
      await expectExpectedFailure('R1 D3: gerencia no resuelve su propia solicitud → 42501', sessions.gerencia.client.schema('crm').rpc('resolver_solicitud_tasa_fn', { p_solicitud_id: solicitudId, p_decision: 'aprobar' }), ['42501'], /propia solicitud/i);
      for (const clave of ['vend1', 'sup1', 'coordinador', 'directorio']) {
        await expectExpectedFailure(`R1 ${clave} no resuelve → 42501`, sessions[clave].client.schema('crm').rpc('resolver_solicitud_tasa_fn', { p_solicitud_id: solicitudId, p_decision: 'aprobar' }), ['42501'], /Solo Gerencia/i);
      }
      await expectExpectedFailure('R1 vend1 no responde una solicitud ajena → 42501', sessions.vend1.client.schema('crm').rpc('responder_tope_tasa_fn', { p_solicitud_id: solicitudId, p_acepta: true }), ['42501'], /fuera de tu ámbito/i);
      await expectExpectedFailure('R1 vend1 no publica la política → 42501', sessions.vend1.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: 1, p_config: { tasa_base_nueva: 15, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'observacion' } }), ['42501'], /Solo Gerencia/i);
      // RLS de lectura: gerencia ve la suya; vend1/sup1 no ven la de gerencia; anon nada.
      const [vG, vV, vS] = await Promise.all([
        sessions.gerencia.client.schema('crm').from('solicitudes_tasa').select('id').eq('id', solicitudId),
        sessions.vend1.client.schema('crm').from('solicitudes_tasa').select('id').eq('id', solicitudId),
        sessions.sup1.client.schema('crm').from('solicitudes_tasa').select('id').eq('id', solicitudId),
      ]);
      check(!vG.error && vG.data?.length === 1, 'R1 gerencia lee su solicitud', vG.error?.message);
      check(!vV.error && vV.data?.length === 0 && !vS.error && vS.data?.length === 0, 'R1 vend1 y sup1 no ven la solicitud de gerencia (RLS)', vV.error?.message ?? vS.error?.message);
      await expectHidden('R1 anon no lee solicitudes', anon.schema('crm').from('solicitudes_tasa').select('id').eq('id', solicitudId));
      await expectBlockedMutation('R1 gerencia no edita una solicitud por la tabla (sin UPDATE)', sessions.gerencia.client.schema('crm').from('solicitudes_tasa').update({ tasa_solicitada: 40 }).eq('id', solicitudId), ['42501']);
    }
    // Flujo positivo con dos actores: vend1 pide, Gerencia (otra persona) decide con tope, vend1 acepta. Supervisor y Gerencia ven la de vend1.
    const cuerpoV1 = { ...cuerpo, capital: capitalCorrida + 1, tasa_solicitada: base + 3, motivo: 'Suite RLS R1 TRANSIENT: solicitud de vend1' };
    const { data: sv, error: esv } = await sessions.vend1.client.schema('crm').rpc('solicitar_tasa_fn', { p_solicitud: cuerpoV1 });
    solicitudV1 = sv?.id ?? null;
    check(!esv && sv?.estado === 'pendiente' && sv?.solicitada_por === vend1Id, 'R1 vend1 crea su solicitud (pendiente)', esv?.message ?? JSON.stringify(sv));
    if (solicitudV1) {
      const [vS, vG, vV2] = await Promise.all([
        sessions.sup1.client.schema('crm').from('solicitudes_tasa').select('id').eq('id', solicitudV1),
        sessions.gerencia.client.schema('crm').from('solicitudes_tasa').select('id').eq('id', solicitudV1),
        sessions.vend2.client.schema('crm').from('solicitudes_tasa').select('id').eq('id', solicitudV1),
      ]);
      check(!vS.error && vS.data?.length === 1 && !vG.error && vG.data?.length === 1, 'R1 sup1 (su supervisor) y gerencia ven la solicitud de vend1', vS.error?.message ?? vG.error?.message);
      check(!vV2.error && vV2.data?.length === 0, 'R1 vend2 no ve la solicitud de vend1', vV2.error?.message);
      await expectExpectedFailure('R1 gerencia aprobar_hasta con tope ≤ base → 22023 (D4)', sessions.gerencia.client.schema('crm').rpc('resolver_solicitud_tasa_fn', { p_solicitud_id: solicitudV1, p_decision: 'aprobar_hasta', p_tasa_maxima: base }), ['22023'], /superar la tasa base/i);
      await expectExpectedFailure('R1 gerencia aprobar_hasta con tope > pedida → 22023', sessions.gerencia.client.schema('crm').rpc('resolver_solicitud_tasa_fn', { p_solicitud_id: solicitudV1, p_decision: 'aprobar_hasta', p_tasa_maxima: base + 4 }), ['22023'], /superar la tasa pedida/i);
      await expectExpectedFailure('R1 vend1 no responde antes de que Gerencia decida → P0409', sessions.vend1.client.schema('crm').rpc('responder_tope_tasa_fn', { p_solicitud_id: solicitudV1, p_acepta: true }), ['P0409'], /autorización con tope/i);
      const { data: d1, error: ed1 } = await sessions.gerencia.client.schema('crm').rpc('resolver_solicitud_tasa_fn', { p_solicitud_id: solicitudV1, p_decision: 'aprobar_hasta', p_tasa_maxima: base + 1, p_motivo: 'Suite: hasta base+1' });
      check(!ed1 && d1?.estado === 'aprobada_con_tope' && Number(d1?.tasa_maxima_autorizada) === base + 1 && d1?.resuelta_por === gerenciaId,
        'R1 D6: gerencia aprueba HASTA base+1 la solicitud de vend1 → aprobada_con_tope', ed1?.message ?? JSON.stringify(d1));
      await expectExpectedFailure('R1 gerencia no resuelve dos veces → P0409', sessions.gerencia.client.schema('crm').rpc('resolver_solicitud_tasa_fn', { p_solicitud_id: solicitudV1, p_decision: 'rechazar' }), ['P0409'], /ya no está pendiente/i);
      await expectExpectedFailure('R1 gerencia no acepta el tope en nombre de vend1 → 42501', sessions.gerencia.client.schema('crm').rpc('responder_tope_tasa_fn', { p_solicitud_id: solicitudV1, p_acepta: true }), ['42501'], /fuera de tu ámbito/i);
      const { data: a1, error: ea1 } = await sessions.vend1.client.schema('crm').rpc('responder_tope_tasa_fn', { p_solicitud_id: solicitudV1, p_acepta: true });
      check(!ea1 && a1?.estado === 'aceptada_por_analista' && Number(a1?.tasa_maxima_autorizada) === base + 1, 'R1 vend1 acepta el tope → aceptada_por_analista', ea1?.message ?? JSON.stringify(a1));
    }
    // Publicar: solo Gerencia; control optimista; enforcement rechazado en R1 (0A000, evaluado antes que la versión).
    let versionActual = cuenta('versión vigente', 'select max(version) from crm.politica_rentabilidad');
    const { data: p1, error: ep1 } = await sessions.gerencia.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: versionActual, p_config: { tasa_base_nueva: base, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'observacion', nota: 'Suite RLS R1 TRANSIENT (misma base)' } });
    check(!ep1 && p1?.version === versionActual + 1 && p1?.publicada_por === gerenciaId && p1?.modo === 'observacion', 'R1 gerencia publica una revisión de la política (misma base) con control de versión', ep1?.message ?? JSON.stringify(p1));
    await expectExpectedFailure('R1 publicar con la versión vieja → 40001', sessions.gerencia.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: versionActual, p_config: { tasa_base_nueva: base, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'observacion' } }), ['P0409'], /Conflicto de versi/i);
    // El modo enforcement lo RECHAZA R1 (0A000)… hasta que R4 lo construye: entonces es EL INTERRUPTOR y se admite.
    // Si se admite, hay que volver a «observacion» en el acto: dejar el banco con el candado encendido rompería los
    // bloques siguientes (y las altas de cualquier otra sesión que comparta esta base).
    const r4Instalada = contarFueraDeBanda('R1: helpers del candado R4',
      `select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'rentabilidad_consumir_autorizacion'`) === 1;
    if (r4Instalada) {
      const { data: pEnf, error: ePEnf } = await sessions.gerencia.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: versionActual + 1, p_config: { tasa_base_nueva: base, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'enforcement', nota: 'Suite RLS: interruptor de R4 (se apaga en la línea siguiente)' } });
      check(!ePEnf && pEnf?.modo === 'enforcement', 'R1+R4 Gerencia SÍ puede publicar el modo enforcement (es el interruptor del candado)', ePEnf?.message ?? JSON.stringify(pEnf));
      const { data: pObs, error: ePObs } = await sessions.gerencia.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: versionActual + 2, p_config: { tasa_base_nueva: base, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'observacion', nota: 'Suite RLS: candado apagado otra vez' } });
      check(!ePObs && pObs?.modo === 'observacion', 'R1+R4 y volver a observacion apaga el candado sin migración (el banco queda como estaba)', ePObs?.message ?? JSON.stringify(pObs));
      const modoFinal = textoFueraDeBanda('R1: modo tras el ensayo del interruptor', `select modo from crm.politica_rentabilidad order by version desc limit 1`);
      check(modoFinal === 'observacion', 'R1+R4 el banco NO se queda con el candado encendido', String(modoFinal));
      versionActual += 2;
    } else {
      await expectExpectedFailure('R1 gerencia no publica en modo enforcement (R4) → 0A000', sessions.gerencia.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: versionActual + 1, p_config: { tasa_base_nueva: base, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'enforcement' } }), ['0A000'], /enforcement/i);
    }
    await expectBlockedMutation('R1 gerencia no inserta en el ledger por la tabla', sessions.gerencia.client.schema('crm').from('ledger_rentabilidad').insert({ contrato_id: '00000000-0000-4000-8000-0000000000a3', numero_contrato: 'X', cliente_id: clienteId, tasa_base: 15, tasa_final: 15, regla: 'sin_regla', origen: 'observacion' }), ['42501']);
    await expectBlockedMutation('R1 gerencia no inserta en la política por la tabla', sessions.gerencia.client.schema('crm').from('politica_rentabilidad').insert({ version: 999, vigente_desde: new Date().toISOString(), tasa_base_nueva: 1 }), ['42501']);
  } finally {
    // La caducidad se calcula por vence_en: «vencida» no es un estado persistido.
    // Se conserva el historial y se exige que la limpieza termine (sin ocultar errores).
    const ids = [solicitudId, solicitudV1].filter((x) => typeof x === 'string');
    if (ids.length) {
      ejecutarFueraDeBanda('R1 limpieza', `select set_config('crm.solicitud_tasa_por_puerta','on',true); update crm.solicitudes_tasa set solicitada_en = clock_timestamp() - interval '8 days', vence_en = clock_timestamp() - interval '1 second' where id in (${ids.map((x) => `'${x}'`).join(',')}) and estado in ('pendiente','aprobada','aprobada_con_tope','aceptada_por_analista');`);
    }
  }
}

// ── RENTABILIDAD R2 (20260906180000): observador diferido de public.contratos + tarjeta crm.observacion_rentabilidad_fn ──
// Superficie y estructura; el comportamiento (alta/renovación/upgrade/corrección observadas) vive en scripts/oraculo-rentabilidad-r2.sh.
async function testRentabilidadR2(sessions) {
  console.log('\n— Rentabilidad R2: observador y tarjeta de Gerencia —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`Rentabilidad R2: ${etiqueta}`, sql);
  const RPC = 'crm.observacion_rentabilidad_fn(date,date)';
  if (cuenta('R2 aplicada', `select (to_regprocedure('${RPC}') is not null)::int`) !== 1) {
    console.log('  (saltado: Rentabilidad R2 (20260906180000) no está en esta base)');
    return;
  }
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-r2'));
  check(cuenta('trigger', `select count(*) from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_zz_observar_rentabilidad' and t.tgenabled = 'O' and t.tgdeferrable and t.tginitdeferred and t.tgconstraint <> 0`) === 1,
    'R2 el observador está montado como constraint trigger diferido y habilitado en public.contratos');
  check(cuenta('hito', `select count(*) from crm.rentabilidad_hitos where clave = 'observacion_activa_desde'`) === 1
    && cuenta('hito RLS', `select (c.relrowsecurity)::int - (has_table_privilege('authenticated','crm.rentabilidad_hitos','INSERT'))::int - (has_table_privilege('anon','crm.rentabilidad_hitos','SELECT'))::int from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'crm' and c.relname = 'rentabilidad_hitos'`) === 1,
    'R2 el hito de activación existe, con RLS y solo SELECT para authenticated');
  check(cuenta('núcleo 5 args', `select (to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)') is not null)::int + (to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz)') is not null)::int`) === 2,
    'R2 el núcleo tiene las dos firmas (la de R1 delega)');
  for (const f of ['private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)', 'private.trg_contratos_observar_rentabilidad()']) {
    check(cuenta(`privada ${f}`, `select (has_function_privilege('authenticated', '${f}', 'EXECUTE'))::int + (has_function_privilege('anon', '${f}', 'EXECUTE'))::int + (has_function_privilege('service_role', '${f}', 'EXECUTE'))::int + (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${f}'::regprocedure and a.grantee = 0)::int`) === 0,
      `R2 ${f} no es llamable por la API ni por PUBLIC`);
  }
  check(cuenta('grants RPC', `select (has_function_privilege('authenticated', '${RPC}', 'EXECUTE'))::int - (has_function_privilege('anon', '${RPC}', 'EXECUTE'))::int - (has_function_privilege('service_role', '${RPC}', 'EXECUTE'))::int - (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${RPC}'::regprocedure and a.grantee = 0)::int`) === 1,
    'R2 la tarjeta solo tiene EXECUTE para authenticated');
  check(cuenta('definer RPC', `select count(*) from pg_proc p where p.oid = '${RPC}'::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']`) === 1,
    'R2 la tarjeta es DEFINER de postgres con search_path vacío');
  await expectExpectedFailure('R2 anon → 42501', anon.schema('crm').rpc('observacion_rentabilidad_fn', {}), ['42501'], /permission denied|denegado|No autorizado/i);
  for (const clave of ['vend1', 'sup1', 'coordinador', 'clientBank', 'vendInactive']) {
    await expectExpectedFailure(`R2 ${clave} no lee la tarjeta → 42501`, sessions[clave].client.schema('crm').rpc('observacion_rentabilidad_fn', {}), ['42501'], /No autorizado/i);
  }
  await expectExpectedFailure('R2 gerencia con desde > hasta → 22023', sessions.gerencia.client.schema('crm').rpc('observacion_rentabilidad_fn', { p_desde: '2026-09-10', p_hasta: '2026-09-01' }), ['22023'], /Periodo/i);
  await expectExpectedFailure('R2 gerencia con rango > 366 días → 22023', sessions.gerencia.client.schema('crm').rpc('observacion_rentabilidad_fn', { p_desde: '2025-01-01', p_hasta: '2026-09-01' }), ['22023'], /Periodo/i);
  await expectExpectedFailure('R2 gerencia con hasta en el futuro → 22023', sessions.gerencia.client.schema('crm').rpc('observacion_rentabilidad_fn', { p_desde: '2030-01-01', p_hasta: '2030-01-31' }), ['22023'], /Periodo/i);
  check(cuenta('precedente intacto', `select count(*) from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_operacion_cartera_commit' and t.tgenabled = 'O'`) === 1,
    'R2 el constraint trigger de operaciones de cartera sigue habilitado (regresión)');
  for (const clave of ['gerencia', 'directorio']) {
    const { data, error } = await sessions[clave].client.schema('crm').rpc('observacion_rentabilidad_fn', {});
    check(!error && data?.version === 1 && typeof data?.coherente === 'boolean' && typeof data?.altas_sin_observar === 'number'
      && data?.metodo === 'simple_sobre_plazo_revision_efectiva' && typeof data?.totales?.contratos === 'number' && typeof data?.totales?.eventos === 'number'
      && typeof data?.sondas?.consistencia_interna === 'boolean' && typeof data?.sondas?.cobertura_altas === 'boolean' && data?.sondas?.cobertura_correcciones === 'desconocida'
      && typeof data?.cobertura?.observacion_activa_desde === 'string' && Array.isArray(data?.por_analista),
      `R2 ${clave} lee la tarjeta: version 1, eventos/contratos, sondas separadas, cobertura desde el hito y método declarado`, error?.message ?? JSON.stringify(data)?.slice(0, 200));
  }
}

// ── RENTABILIDAD R3 (20260906220000): lecturas para la bandeja, la ficha y la política ──
async function testRentabilidadR3(sessions, seed) {
  console.log('\n— Rentabilidad R3: lecturas (solicitudes_tasa_fn, historial_tasa_cliente_fn, politica_rentabilidad_fn) —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`Rentabilidad R3: ${etiqueta}`, sql);
  const FNS = ['crm.solicitudes_tasa_fn(text[],integer,boolean,uuid)', 'crm.historial_tasa_cliente_fn(uuid)', 'crm.politica_rentabilidad_fn()'];
  if (cuenta('R3 aplicada', `select (to_regprocedure('${FNS[2]}') is not null)::int`) !== 1) {
    console.log('  (saltado: Rentabilidad R3 (20260906220000) no está en esta base)');
    return;
  }
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-r3'));
  const clienteId = seed.profileIdByKey.clientBank;
  for (const f of FNS) {
    check(cuenta(`grants ${f}`, `select (has_function_privilege('authenticated', '${f}', 'EXECUTE'))::int - (has_function_privilege('anon', '${f}', 'EXECUTE'))::int - (has_function_privilege('service_role', '${f}', 'EXECUTE'))::int - (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${f}'::regprocedure and a.grantee = 0)::int`) === 1,
      `R3 ${f} solo tiene EXECUTE para authenticated`);
    check(cuenta(`definer ${f}`, `select count(*) from pg_proc p where p.oid = '${f}'::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""'] and p.provolatile = 's'`) === 1,
      `R3 ${f} es DEFINER estable de postgres con search_path vacío`);
  }
  await expectExpectedFailure('R3 anon solicitudes_tasa_fn → 42501', anon.schema('crm').rpc('solicitudes_tasa_fn', {}), ['42501'], /permission denied|denegado|No autorizado/i);
  await expectExpectedFailure('R3 anon politica_rentabilidad_fn → 42501', anon.schema('crm').rpc('politica_rentabilidad_fn'), ['42501'], /permission denied|denegado|No autorizado/i);
  for (const clave of ['clientBank', 'vendInactive']) {
    await expectExpectedFailure(`R3 ${clave} no lee solicitudes → 42501`, sessions[clave].client.schema('crm').rpc('solicitudes_tasa_fn', {}), ['42501'], /No autorizado/i);
    await expectExpectedFailure(`R3 ${clave} no lee la política → 42501`, sessions[clave].client.schema('crm').rpc('politica_rentabilidad_fn'), ['42501'], /No autorizado/i);
  }
  await expectExpectedFailure('R3 gerencia con estado desconocido → 22023', sessions.gerencia.client.schema('crm').rpc('solicitudes_tasa_fn', { p_estados: ['inventado'] }), ['22023'], /Estado desconocido/i);
  for (const clave of ['gerencia', 'directorio', 'vend1', 'sup1', 'coordinador']) {
    const { data, error } = await sessions[clave].client.schema('crm').rpc('politica_rentabilidad_fn');
    check(!error && data?.version === 1 && data?.vigente?.modo === 'observacion' && typeof data?.expected_version === 'number' && Array.isArray(data?.historial),
      `R3 ${clave} lee la política vigente`, error?.message ?? JSON.stringify(data)?.slice(0, 160));
    if (clave === 'gerencia') check(data?.puede_publicar === true, 'R3 gerencia puede publicar la política');
    if (clave === 'vend1') check(data?.puede_publicar === false, 'R3 vend1 no puede publicar la política');
  }
  for (const clave of ['gerencia', 'directorio', 'vend1', 'sup1']) {
    const { data, error } = await sessions[clave].client.schema('crm').rpc('solicitudes_tasa_fn', { p_estados: ['pendiente'], p_limite: 20 });
    check(!error && Array.isArray(data) && data.every((s) => s.estado === 'pendiente' && typeof s.cliente_nombre === 'string' && typeof s.puede_resolver === 'boolean'),
      `R3 ${clave} lee sus solicitudes pendientes con nombres y permisos`, error?.message ?? JSON.stringify(data)?.slice(0, 160));
    if (clave === 'vend1') check(!error && data.every((s) => s.es_mia === true && s.puede_resolver === false), 'R3 vend1 solo ve las suyas y ninguna puede_resolver');
    if (clave === 'gerencia') check(!error && data.every((s) => s.puede_resolver === (s.es_mia === false)), 'R3 gerencia puede resolver exactamente las ajenas (D3)');
  }
  const { data: h, error: eh } = await sessions.gerencia.client.schema('crm').rpc('historial_tasa_cliente_fn', { p_cliente_id: clienteId });
  check(!eh && h?.version === 1 && Array.isArray(h?.contratos) && Array.isArray(h?.solicitudes), 'R3 gerencia lee el historial de tasa del cliente bancario', eh?.message ?? JSON.stringify(h)?.slice(0, 160));
  await expectExpectedFailure('R3 gerencia historial de cliente inexistente → 42501 uniforme', sessions.gerencia.client.schema('crm').rpc('historial_tasa_cliente_fn', { p_cliente_id: '00000000-0000-4000-8000-0000000000a3' }), ['42501'], /fuera de tu cartera/i);
  await expectExpectedFailure('R3 clientBank no lee historial → 42501', sessions.clientBank.client.schema('crm').rpc('historial_tasa_cliente_fn', { p_cliente_id: clienteId }), ['42501'], /fuera de tu cartera/i);
}

// ── RENTABILIDAD R4 (20260907093000): el CANDADO del servidor. Este bloque NO enciende el enforcement (la suite es
// compartida y encenderlo rompería los demás bloques): comprueba que el candado está montado, que sus helpers no se
// alcanzan desde la API, que el trigger diferido sigue en su sitio y que solo Gerencia puede tocar el interruptor.
// El comportamiento del candado (rechazos, consumo, doble consumo, huella, bypass) lo prueba el oráculo adversarial
// supabase/scripts/oraculo-rentabilidad-r4.sh en el banco.
async function testRentabilidadR4(sessions) {
  console.log('\n— Rentabilidad R4: el candado del servidor (montado, no encendido) —');
  const texto = (etiqueta, sql) => textoFueraDeBanda(`R4: ${etiqueta}`, sql);
  const HELPERS = ['private.rentabilidad_origen_declarado(public.contratos)',
                   'private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)'];
  const instaladas = contarFueraDeBanda('R4: helpers del candado',
    `select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname in ('rentabilidad_origen_declarado', 'rentabilidad_consumir_autorizacion')`);
  if (instaladas !== 2) {
    console.log('  ⚠ Rentabilidad R4 NO desplegada en esta base: bloque SALTADO (no probado)');
    return;
  }
  for (const f of HELPERS) {
    const acl = texto(`ACL de ${f}`,
      `select has_function_privilege('authenticated', '${f}', 'EXECUTE')::text || '|' || has_function_privilege('anon', '${f}', 'EXECUTE')::text || '|' || has_function_privilege('service_role', '${f}', 'EXECUTE')::text || '|' || exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = '${f}'::regprocedure and a.grantee = 0)::text`);
    check(acl === 'false|false|false|false', `R4 ${f} NO es ejecutable desde la API (helper privado)`, acl);
    const def = texto(`definer de ${f}`,
      `select p.prosecdef::text || '|' || p.proowner::regrole::text || '|' || exists (select 1 from unnest(p.proconfig) c where c in ('search_path=', 'search_path=""'))::text from pg_proc p where p.oid = '${f}'::regprocedure`);
    check(def === 'true|postgres|true', `R4 ${f} es DEFINER de postgres con search_path vacío`, def);
  }
  const trg = texto('trigger del candado',
    `select t.tgdeferrable::text || '|' || t.tginitdeferred::text || '|' || t.tgenabled::text from pg_trigger t where t.tgname = 'trg_contratos_zz_observar_rentabilidad' and t.tgrelid = 'public.contratos'::regclass`);
  check(trg === 'true|true|O', 'R4 el trigger del candado sigue diferido y habilitado sobre public.contratos', trg);
  const modo = texto('modo vigente', `select p.modo from crm.politica_rentabilidad p order by p.vigente_desde desc, p.version desc limit 1`);
  check(modo === 'observacion' || modo === 'enforcement', 'R4 la política vigente declara su modo', String(modo));
  if (modo === 'enforcement') {
    console.log('  ⚠ la política de esta base está en ENFORCEMENT: los bloques de altas pueden rechazar tasas fuera de la base');
  }
  // El interruptor es de Gerencia: un analista no lo toca, ni para encenderlo ni para apagarlo.
  const version = contarFueraDeBanda('R4: versión vigente', `select max(version) from crm.politica_rentabilidad`);
  await expectExpectedFailure('R4 vend1 no puede tocar el interruptor del candado → 42501',
    sessions.vend1.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: version, p_config: { tasa_base_nueva: 15, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'enforcement' } }),
    ['42501'], /Solo Gerencia|No autorizado|autoriz/i);
  await expectExpectedFailure('R4 un modo inventado → 22023',
    sessions.gerencia.client.schema('crm').rpc('publicar_politica_rentabilidad_fn', { p_expected_version: version, p_config: { tasa_base_nueva: 15, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'candado_total' } }),
    ['22023'], /Modo inválido/i);
}

// ── F2.b [D-5] (20260906140000): las RPC de un argumento de la conversión se cierran con la identidad encendida;
// Gerencia abandona una conversión sellada sin cuenta. Grants, definer, marcadores, paridad apagada y superficie ON.
async function testIdentidadF2bD5(sessions, seed) {
  console.log('\n— Identidad multiempresa F2.b [D-5]: RPC de un argumento cerradas con ON; abandonar conversión —');
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-5: ${etiqueta}`, sql);
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b D-5)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const FA = 'crm.abandonar_conversion_gerencia_fn(uuid,text)';
  const UNO = ['crm.reservar_conversion_lead(uuid)', 'crm.marcar_efectos_conversion(uuid)'];
  if (cuenta('D-5 aplicada', `select (to_regprocedure('${FA}') is not null)::int`) !== 1) {
    console.log('  (saltado: D-5 (20260906140000) no está en esta base)');
    return;
  }
  const LEAD_INEXISTENTE = '00000000-0000-4000-8000-0000000000d5';
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-d5'));
  const vend1Id = seed.profileIdByKey.vend1;
  const L_V1 = randomUUID();
  try {
    check(cuenta('marcadores', `select count(*) from pg_proc p where p.oid in ('${UNO[0]}'::regprocedure, '${UNO[1]}'::regprocedure, 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure) and strpos(p.prosrc, 'F2.b [D-5]') > 0`) === 3,
      'D-5 las dos firmas de un argumento y el sellado por persona llevan la transformación (marcador en el cuerpo)');
    check(cuenta('grants', `select count(*) from unnest(array['${UNO[0]}','${UNO[1]}','crm.marcar_efectos_conversion(uuid,uuid,text)','${FA}']) f(firma) where has_function_privilege('authenticated', f.firma, 'EXECUTE') and not has_function_privilege('anon', f.firma, 'EXECUTE') and not has_function_privilege('service_role', f.firma, 'EXECUTE')`) === 4
        && cuenta('PUBLIC residual', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid in ('${UNO[0]}'::regprocedure, '${UNO[1]}'::regprocedure, 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure, '${FA}'::regprocedure) and a.grantee = 0`) === 0,
      'D-5 las cuatro conservan sus grants (solo authenticated; ni anon, ni service_role, ni PUBLIC)');
    check(cuenta('definer', `select count(*) from pg_proc p where p.oid in ('${UNO[0]}'::regprocedure, '${UNO[1]}'::regprocedure, 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure, '${FA}'::regprocedure) and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole`) === 4,
      'D-5 las cuatro son DEFINER de postgres con search_path vacío');
    await expectExpectedFailure('D-5 anon abandonar → 42501 (sin EXECUTE)', anon.schema('crm').rpc('abandonar_conversion_gerencia_fn', { p_lead_id: LEAD_INEXISTENTE, p_motivo: 'motivo largo' }), ['42501'], /permission denied|denegado/i);
    await expectExpectedFailure('D-5 vend1 abandonar → 42501 (solo Gerencia)', sessions.vend1.client.schema('crm').rpc('abandonar_conversion_gerencia_fn', { p_lead_id: LEAD_INEXISTENTE, p_motivo: 'motivo largo' }), ['42501'], /Gerencia/i);
    await expectExpectedFailure('D-5 OFF gerencia abandonar → P0409 «apagada» (superficie inerte)', sessions.gerencia.client.schema('crm').rpc('abandonar_conversion_gerencia_fn', { p_lead_id: LEAD_INEXISTENTE, p_motivo: 'motivo largo' }), ['P0409'], /apagada/i);
    // Paridad APAGADA de la reserva por lead (la firma vieja del edge de hoy): reserva y sella como siempre.
    await requireAdmin('D-5: sembrar un lead vivo de vend1', admin.schema('crm').from('leads').insert([
      { id: L_V1, nombre_completo: 'D5 RESERVA V1 TRANSIENT', telefono: TEL_F2B(193), creado_por: vend1Id, vendedor_id: vend1Id, activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'otro', monto_estimado: 5000 },
    ]));
    const { data: r1, error: e1 } = await sessions.vend1.client.schema('crm').rpc('reservar_conversion_lead', { p_lead_id: L_V1 });
    check(!e1 && r1?.ok === true && cuenta('reserva por lead', `select count(*) from crm.conversion_reservas where lead_id = '${L_V1}' and inversionista_id is null`) === 1,
      'D-5 OFF vend1 reserva por lead (1 argumento) → ok, como hoy', e1?.message ?? JSON.stringify(r1));
    const { data: r2, error: e2 } = await sessions.vend1.client.schema('crm').rpc('marcar_efectos_conversion', { p_lead_id: L_V1 });
    check(!e2 && r2?.ok === true && cuenta('sellada', `select count(*) from crm.conversion_reservas where lead_id = '${L_V1}' and efectos_iniciados_en is not null`) === 1,
      'D-5 OFF vend1 sella sin persona (1 argumento) → ok, como hoy', e2?.message ?? JSON.stringify(r2));
    ejecutarFueraDeBanda('D-5 soltar la reserva de prueba', `delete from crm.conversion_reservas where lead_id = '${L_V1}';`);
    // Con la bandera ENCENDIDA la firma vieja se cierra sin efectos (P0409 con la firma nueva en HINT); apagada de nuevo, vuelve a servir.
    flag(true);
    await expectExpectedFailure('D-5 ON vend1 reserva por lead (1 argumento) → P0409 «va por persona»', sessions.vend1.client.schema('crm').rpc('reservar_conversion_lead', { p_lead_id: L_V1 }), ['P0409'], /va por persona/i);
    await expectExpectedFailure('D-5 ON vend1 sella sin persona (1 argumento) → P0409 «va por persona»', sessions.vend1.client.schema('crm').rpc('marcar_efectos_conversion', { p_lead_id: L_V1 }), ['P0409'], /va por persona/i);
    check(cuenta('sin reserva con ON', `select count(*) from crm.conversion_reservas where lead_id = '${L_V1}'`) === 0, 'D-5 ON la firma vieja no dejó reserva');
    await expectExpectedFailure('D-5 ON gerencia abandonar un lead sin reserva por persona → P0002', sessions.gerencia.client.schema('crm').rpc('abandonar_conversion_gerencia_fn', { p_lead_id: L_V1, p_motivo: 'motivo largo' }), ['P0002'], /reserva por persona/i);
    await expectExpectedFailure('D-5 ON gerencia abandonar con motivo corto → 22023', sessions.gerencia.client.schema('crm').rpc('abandonar_conversion_gerencia_fn', { p_lead_id: L_V1, p_motivo: 'abc' }), ['22023'], /motivo/i);
    // Con ON, un UPDATE directo que lleva el DNI SIN cambiarlo pasa (auditor v4 #3c): es de lo que depende la fila completa que manda la ficha.
    const { error: eDni } = await sessions.vend1.client.schema('crm').from('leads').update({ dni: null, nota: 'dni igual con ON' }).eq('id', L_V1).select('id');
    check(!eDni && cuenta('dni igual con ON', `select count(*) from crm.leads where id = '${L_V1}' and nota = 'dni igual con ON' and dni is null`) === 1, 'D-5 ON: un UPDATE con el DNI sin cambiar (y otra columna) pasa el trigger de D-13', eDni?.message ?? '');
    flag(false);
    const { data: r3, error: e3 } = await sessions.vend1.client.schema('crm').rpc('reservar_conversion_lead', { p_lead_id: L_V1 });
    check(!e3 && r3?.ok === true, 'D-5 OFF otra vez: la firma vieja vuelve a servir', e3?.message ?? JSON.stringify(r3));
  } finally {
    flag(false);
    ejecutarFueraDeBanda('D-5 limpieza', `delete from crm.conversion_reservas where lead_id = '${L_V1}'; update crm.leads set activo = false where id = '${L_V1}';`, { tolerante: true });
  }
}

// ── F2.b [D-10] (20260905150000): la reserva por persona cuenta el PUENTE en «un solo lead» ──
// Solo grants, paridad apagada y que la rama ON sea alcanzable sin efectos (el negocio —puente, replay
// tras fusión [D-11]— lo cubre scripts/oraculo-f2b-d10-d11.sh).
async function testIdentidadF2bD10(sessions) {
  console.log('\n— Identidad multiempresa F2.b [D-10]: la reserva por persona cuenta el puente —');
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b D-10)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-10: ${etiqueta}`, sql);
  const FIRMA = 'crm.reservar_conversion_lead(uuid,text,text,jsonb)';
  const LEAD_INEXISTENTE = '00000000-0000-4000-8000-00000000d010';
  const reservar = (cliente, documento) => cliente.schema('crm').rpc('reservar_conversion_lead',
    { p_lead_id: LEAD_INEXISTENTE, p_tipo_documento: 'DNI', p_documento: documento, p_payload: { correo: 'd10@x.pe' } });
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-d10'));

  if (cuenta('D-10 aplicada', `select (strpos(p.prosrc, 'F2.b [D-10]') > 0)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb'`) !== 1) {
    console.log('  (saltado: D-10 (20260905150000) no está en esta base)');
    return;
  }
  try {
    check(cuenta('grants', `select (has_function_privilege('authenticated', '${FIRMA}', 'EXECUTE'))::int - (has_function_privilege('anon', '${FIRMA}', 'EXECUTE'))::int - (has_function_privilege('service_role', '${FIRMA}', 'EXECUTE'))::int - (select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid = '${FIRMA}'::regprocedure and a.grantee = 0)`) === 1,
      'D-10 la reserva por persona conserva sus grants (solo authenticated; ni anon, ni service_role, ni PUBLIC)');
    check(cuenta('1 argumento intacta', `select (md5(pg_get_functiondef(p.oid)) in ('a067183bfe986cf7bd5f82b4ed6674d7', 'c9fc656c5f9b57d0688a5ecccd747e73'))::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid'`) === 1,
      'D-10 la reserva de 1 argumento (camino de hoy) sigue byte a byte (texto de producción o el de D-5, que solo añade la guarda con ON)');
    check(cuenta('leads_de_identidades sin EXECUTE', `select count(*) from unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, 'private.leads_de_identidades(uuid[])', 'EXECUTE')`) === 0,
      'D-10 private.leads_de_identidades sigue sin EXECUTE para la API (solo la llama la definer)');
    // OFF (estado de producción): la sobrecarga es inerte antes de leer argumentos.
    flag(false);
    await expectExpectedFailure('D-10 OFF vend1 reserva por persona → P0409 apagada', reservar(sessions.vend1.client, '00000001'), ['P0409'], /apagada/i);
    await expectExpectedFailure('D-10 anon reserva por persona → 42501 (sin EXECUTE)', reservar(anon, '00000001'), ['42501'], /permission denied|denegado/i);
    await expectExpectedFailure('D-10 service_role reserva por persona → 42501 (sin EXECUTE)', reservar(admin, '00000001'), ['42501'], /permission denied|denegado/i);
    for (const clave of ['coordinador', 'directorio', 'vendInactive', 'clientBank']) {
      await expectExpectedFailure(`D-10 OFF ${clave} reserva por persona → 42501 (no gestiona contratos; muere ANTES de la bandera)`, reservar(sessions[clave].client, '00000001'), ['42501'], /no autorizado/i);
    }
    // ON: la rama transformada es alcanzable y muere ANTES de tocar nada (documento vacío → 22023); el cliente no convierte.
    flag(true);
    await expectExpectedFailure('D-10 ON vend1 sin documento → 22023 (rama ON alcanzable, sin efectos)', reservar(sessions.vend1.client, ''), ['22023'], /documento es obligatorio/i);
    await expectExpectedFailure('D-10 ON cliente de banca → 42501 (no gestiona contratos)', reservar(sessions.clientBank.client, '00000001'), ['42501'], /no autorizado/i);
    check(cuenta('sin identidad fantasma', `select count(*) from crm.inversionista_identificadores where documento_normalizado='00000001' and tipo_documento='DNI'`) === 0,
      'D-10 ON: los rechazos no dejaron identidad nueva');
  } finally {
    flag(false);
  }
}

// ── F2.b [D-13] (20260905160000): «un solo lead» y «el puente manda» en todas las puertas con la bandera ON ──
// Solo grants, marcadores y paridad apagada (el negocio —puente, conversión en curso, toma, conversiones— lo
// cubre scripts/oraculo-f2b-d13.sh en el banco, con fixtures que la suite no puede sembrar sin válvula).
async function testIdentidadF2bD13(sessions, seed) {
  console.log('\n— Identidad multiempresa F2.b [D-13]: un solo lead y el puente manda en todas las puertas —');
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b D-13)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b D-13: ${etiqueta}`, sql);
  const lista = (arr) => `'${arr.join("','")}'`;
  const PRIVADAS = ['private.persona_en_conversion(uuid,uuid)', 'private.leads_de_personas(uuid[])', 'private.lead_persona_reabrir(uuid)',
    'private.bloquear_personas_de_leads(uuid[],text)', 'private.lead_dentro_de_bloqueo(uuid,jsonb)', 'private.juicio_reapertura(uuid,text,text)', 'private.enlazar_lead_reabierto(uuid,uuid)',
    'private.trg_leads_zz_reapertura_solo_rpc()', 'private.juicio_persona(uuid,uuid)', 'private.verificar_disponibilidad_lead_impl(text,text,uuid)',
    'private.verificar_disponibilidad_lead_impl(text,text)', 'private.trg_leads_zz_enlaza_identidad()', 'private.leads_de_identidades(uuid[])',
    'private.deshacer_descarte_implementacion(uuid)'];
  const RPC = ['crm.tomar_lead_libre(text,text)', 'crm.convertir_lead(uuid,uuid)', 'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)',
    'crm.marcar_efectos_conversion(uuid,uuid,text)', 'crm.rescatar_descartes(uuid[],uuid[],boolean)', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)',
    'crm.fijar_dni_lead_fn(uuid,text)'];
  const marcador = (nombre, args) => cuenta(`marcador ${nombre}`, `select (strpos(p.prosrc, 'F2.b [D-13]') > 0)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname || '.' || p.proname = '${nombre}' and pg_get_function_identity_arguments(p.oid) = '${args}'`);
  const DNI_SIN_DUENO = '00000013';
  const LEAD_INEXISTENTE = '00000000-0000-4000-8000-00000000d013';
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-d13'));

  // Gate por el objeto MÁS nuevo de D-13 (v4.3: lead_dentro_de_bloqueo): con una versión anterior en la base, el bloque se
  // salta en vez de abortar la suite en las cuentas de grants (has_function_privilege sobre una firma inexistente es un error fatal).
  if (cuenta('D-13 aplicada', `select (to_regprocedure('private.juicio_persona(uuid,uuid)') is not null and to_regprocedure('crm.fijar_dni_lead_fn(uuid,text)') is not null and to_regprocedure('private.lead_dentro_de_bloqueo(uuid,jsonb)') is not null)::int`) !== 1) {
    console.log('  (saltado: D-13 (20260905160000) no está en esta base)');
    return;
  }
  try {
    check(cuenta('EXECUTE residual privadas', `select count(*) from unnest(array[${lista(PRIVADAS)}]) f(firma), unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE')`)
        + cuenta('PUBLIC residual privadas', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid in (${PRIVADAS.map((f) => `'${f}'::regprocedure`).join(',')}) and a.grantee = 0`) === 0,
      'D-13 helper y funciones privadas (verificador, trigger, puente) sin EXECUTE para la API ni PUBLIC');
    check(cuenta('grants RPC', `select count(*) from unnest(array[${lista(RPC)}]) f(firma) where has_function_privilege('authenticated', f.firma, 'EXECUTE') and not has_function_privilege('anon', f.firma, 'EXECUTE') and not has_function_privilege('service_role', f.firma, 'EXECUTE')`) === RPC.length
        && cuenta('PUBLIC residual RPC', `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid in (${RPC.map((f) => `'${f}'::regprocedure`).join(',')}) and a.grantee = 0`) === 0,
      'D-13 las cinco RPC transformadas conservan sus grants (solo authenticated)');
    check(marcador('private.verificar_disponibilidad_lead_impl', 'p_telefono text, p_dni text, p_excluir_lead_id uuid') + marcador('private.trg_leads_zz_enlaza_identidad', '') + marcador('crm.tomar_lead_libre', 'p_telefono text, p_dni text') + marcador('crm.convertir_lead', 'p_lead_id uuid, p_perfil_id uuid') === 4
        && cuenta('marcador externo', `select (strpos(p.prosrc, 'F2.b [D-13]') > 0)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo'`) === 1,
      'D-13 las cinco puertas llevan la transformación (marcador en el cuerpo)');
    check(cuenta('trigger zz vigente', `select count(*) from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_enlaza_identidad' and tgenabled='O' and pg_get_triggerdef(oid) like '%BEFORE INSERT OR UPDATE OF dni%'`) === 1,
      'D-13 el trigger de nacimiento sigue BEFORE INSERT OR UPDATE OF dni y habilitado');
    // La premisa de serialización de D-13 (auditor N1): todo INSERT con DNI toma el candado documental en el trigger 000 (b1).
    check(cuenta('trigger 000', `select count(*) from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid='crm.leads'::regclass and t.tgname='trg_leads_000_hereda_veto' and not t.tgisinternal and t.tgenabled='O' and pg_get_triggerdef(t.oid) like '%BEFORE INSERT ON crm.leads%' and strpos(p.prosrc, 'identidad_bloquear_documento') > 0`) === 1,
      'D-13 trg_leads_000_hereda_veto sigue BEFORE INSERT, habilitado y tomando el candado documental (la reserva y el alta se serializan)');
    check(cuenta('marcador sellado', `select (strpos(p.prosrc, 'F2.b [D-13]') > 0)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_claim_id uuid, p_token text'`)
        + cuenta('marcador rescate', `select (strpos(p.prosrc, 'F2.b [D-13]') > 0)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='rescatar_descartes'`)
        + cuenta('marcador deshacer', `select (strpos(p.prosrc, 'F2.b [D-13]') > 0)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='deshacer_descarte_implementacion'`) === 3,
      'D-13 v2: el sellado, el rescate y el deshacer llevan la transformación');
    check(cuenta('marcador reserva D-13', `select (strpos(p.prosrc, 'F2.b [D-13]') > 0)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb'`) === 1,
      'D-13 v3: la reserva por persona (texto de D-10) cuenta también los sueltos por documento');
    check(cuenta('trigger reapertura', `select count(*) from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_reapertura_solo_rpc' and tgenabled='O' and pg_get_triggerdef(oid) like '%BEFORE UPDATE OF etapa, activo%'`) === 1,
      'D-13 v3: el trigger «reabrir solo por RPC» está BEFORE UPDATE OF etapa, activo y habilitado');
    // La puerta del DNI (v4): OFF = el UPDATE de hoy; ON = el UPDATE directo de dni muere en P0409 «por su puerta» (service_role también).
    for (const clave of ['coordinador', 'clientBank', 'vendInactive']) {
      await expectExpectedFailure(`D-13 ${clave} fijar_dni_lead_fn → 42501 (no es del CRM o está inactivo)`, sessions[clave].client.schema('crm').rpc('fijar_dni_lead_fn', { p_lead_id: LEAD_INEXISTENTE, p_dni: DNI_SIN_DUENO }), ['42501'], /revocado/i);
    }
    await expectExpectedFailure('D-13 anon fijar_dni_lead_fn → 42501 (sin EXECUTE)', anon.schema('crm').rpc('fijar_dni_lead_fn', { p_lead_id: LEAD_INEXISTENTE, p_dni: DNI_SIN_DUENO }), ['42501'], /permission denied|denegado/i);
    for (const on of [false, true]) {
      flag(on);
      await expectExpectedFailure(`D-13 ${on ? 'ON' : 'OFF'} vend1 fijar_dni_lead_fn sobre un lead inexistente → P0002 (sin efectos)`, sessions.vend1.client.schema('crm').rpc('fijar_dni_lead_fn', { p_lead_id: LEAD_INEXISTENTE, p_dni: DNI_SIN_DUENO }), ['P0002'], /no encontrado/i);
    }
    check(cuenta('sin identidad fantasma (fijar)', `select count(*) from crm.inversionista_identificadores where documento_normalizado='${DNI_SIN_DUENO}'`) === 0, 'D-13: fijar_dni_lead_fn no crea identidades');
    // La puerta del DNI con leads de verdad (auditor v4 M3): ámbito antes de candados, OFF = el UPDATE de hoy, ON solo por la puerta.
    {
      const vend1Id = seed.profileIdByKey.vend1;
      const vend2Id = seed.profileIdByKey.vend2;
      const L_V1 = randomUUID();
      const L_V2 = randomUUID();
      const DNI_P = (n) => `8${RUN_IDENTIDAD}${String(n).padStart(3, '0')}`;  // 8 dígitos, distinto por corrida
      const base = { activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'otro', monto_estimado: 5000 };
      const fijar = (clave, leadId, dni) => sessions[clave].client.schema('crm').rpc('fijar_dni_lead_fn', { p_lead_id: leadId, p_dni: dni });
      flag(false);
      await requireAdmin('D-13: sembrar dos leads sin DNI (vend1 y vend2)', admin.schema('crm').from('leads').insert([
        { ...base, id: L_V1, nombre_completo: 'D13 PUERTA DNI V1 TRANSIENT', telefono: TEL_F2B(181), creado_por: vend1Id, vendedor_id: vend1Id },
        { ...base, id: L_V2, nombre_completo: 'D13 PUERTA DNI V2 TRANSIENT', telefono: TEL_F2B(182), creado_por: vend2Id, vendedor_id: vend2Id },
      ]));
      await expectExpectedFailure('D-13 OFF vend1 fija el DNI de un lead de vend2 → P0002 (fuera de ámbito, sin sondear a nadie)', fijar('vend1', L_V2, DNI_P(181)), ['P0002'], /no encontrado/i);
      const r1 = await fijar('vend1', L_V1, DNI_P(181));
      check(!r1.error && r1.data?.ok === true && cuenta('dni fijado', `select count(*) from crm.leads where id='${L_V1}' and dni='${DNI_P(181)}'`) === 1,
        'D-13 OFF: vend1 fija el DNI de su propio lead → ok y DNI cambiado (el UPDATE de hoy)', errorText(r1.error));
      const r2 = await fijar('vend1', L_V1, DNI_P(181));
      check(!r2.error && r2.data?.sin_cambios === true, 'D-13 OFF: la misma llamada otra vez → sin_cambios', errorText(r2.error));
      flag(true);
      await expectExpectedFailure('D-13 ON vend1 UPDATE directo de dni de su lead → P0409 «por su puerta»',
        sessions.vend1.client.schema('crm').from('leads').update({ dni: DNI_P(183) }).eq('id', L_V1).select('id'), ['P0409'], /por su puerta/i);
      await expectExpectedFailure('D-13 ON service_role UPDATE directo de dni → P0409 «por su puerta» (sin válvula el trigger no distingue)',
        admin.schema('crm').from('leads').update({ dni: DNI_P(183) }).eq('id', L_V2).select('id'), ['P0409'], /por su puerta/i);
      check(cuenta('dni intactos', `select count(*) from crm.leads where (id='${L_V1}' and dni='${DNI_P(181)}') or (id='${L_V2}' and dni is null)`) === 2, 'D-13 ON: los DNI quedaron intactos');
      const r3 = await fijar('vend1', L_V1, DNI_P(184));
      check(!r3.error && r3.data?.ok === true && r3.data?.enlazado === false && cuenta('dni por puerta ON', `select count(*) from crm.leads where id='${L_V1}' and dni='${DNI_P(184)}' and inversionista_id is null`) === 1,
        'D-13 ON: por la puerta, un DNI sin persona sí se fija (sin enlace)', errorText(r3.error));
      check(cuenta('sin identidad fantasma (puerta)', `select count(*) from crm.inversionista_identificadores where documento_normalizado in ('${DNI_P(181)}','${DNI_P(183)}','${DNI_P(184)}')`) === 0, 'D-13: la puerta no crea identidades');
      flag(false);
    }
    // El trigger «reabrir solo por RPC»: OFF inerte (el UPDATE directo pasa y la etapa cambia de verdad), ON → P0409 sin GUC
    // (service_role dispara el trigger igual: no lleva válvula), y activo false→true también (auditor v3 M2).
    {
      flag(false);
      // Descartado PROPIO del bloque (auditor v4.2 N3): no se toca el estado del seed.
      const idDesc = randomUUID();
      await requireAdmin('D-13: sembrar un lead y descartarlo (bandera apagada)', admin.schema('crm').from('leads').insert({
        activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'otro', monto_estimado: 5000,
        id: idDesc, nombre_completo: 'D13 REAPERTURA TRANSIENT', telefono: TEL_F2B(183), creado_por: seed.profileIdByKey.vend1, vendedor_id: seed.profileIdByKey.vend1 }));
      await requireAdmin('D-13: descartar el lead sembrado', admin.schema('crm').from('leads').update({ etapa: 'descartado', motivo_descarte: 'sin_interes' }).eq('id', idDesc));
      if (idDesc) {
        const { error } = await sessions.gerencia.client.schema('crm').from('leads').update({ etapa: 'nuevo', motivo_descarte: null }).eq('id', idDesc).select('id');
        check(!error && cuenta('reabierto OFF', `select count(*) from crm.leads where id='${idDesc}' and etapa='nuevo'`) === 1,
          'D-13 OFF: reabrir un descarte por UPDATE directo pasa y la etapa cambia (trigger inerte)', errorText(error));
        await requireAdmin('D-13: volver a descartar el lead sembrado', admin.schema('crm').from('leads').update({ etapa: 'descartado', motivo_descarte: 'sin_interes' }).eq('id', idDesc));
        flag(true);
        await expectExpectedFailure('D-13 ON: UPDATE directo descartado→nuevo (service_role, sin GUC ni válvula) → P0409 «solo por sus puertas»',
          admin.schema('crm').from('leads').update({ etapa: 'nuevo', motivo_descarte: null }).eq('id', idDesc).select('id'), ['P0409'], /solo por sus puertas/i);
        check(cuenta('sigue descartado', `select count(*) from crm.leads where id='${idDesc}' and etapa='descartado'`) === 1, 'D-13 ON: el descarte sigue descartado');
        ejecutarFueraDeBanda('D-13 ON: soft-borrar el descarte sembrado bajo válvula', `select set_config('crm.op_privilegiada','on',true); update crm.leads set activo=false where id='${idDesc}';`);
        await expectExpectedFailure('D-13 ON: activo false→true por UPDATE directo (service_role) → P0409 «solo por sus puertas»',
          admin.schema('crm').from('leads').update({ activo: true }).eq('id', idDesc).select('id'), ['P0409'], /solo por sus puertas/i);
        // Queda desactivado (soft-borrado): el bloque no deja rastro vivo.
      } else {
        console.log('  (sin descartado sembrado: se omite la paridad del trigger de reapertura)');
      }
    }
    // Denegados ejercitados, no solo contados (auditor N7): la toma directa es de vendedores activos.
    const tomarComo = (cliente) => cliente.schema('crm').rpc('tomar_lead_libre', { p_telefono: '900000013', p_dni: DNI_SIN_DUENO });
    await expectExpectedFailure('D-13 anon tomar_lead_libre → 42501 (sin EXECUTE)', tomarComo(anon), ['42501'], /permission denied|denegado/i);
    await expectExpectedFailure('D-13 service_role tomar_lead_libre → 42501 (sin EXECUTE)', tomarComo(admin), ['42501'], /permission denied|denegado/i);
    for (const clave of ['coordinador', 'clientBank', 'vendInactive']) {
      await expectExpectedFailure(`D-13 ${clave} tomar_lead_libre → 42501 (no es vendedor activo; muere antes de la bandera)`, tomarComo(sessions[clave].client), ['42501'], /revocado|solo para vendedores/i);
    }
    // OFF (producción): el verificador responde como hoy para un DNI sin dueño; ON: idem (sin identidad ni reserva no hay rama que actúe).
    for (const on of [false, true]) {
      flag(on);
      const { data, error } = await sessions.vend1.client.schema('crm').rpc('verificar_disponibilidad_lead', { p_telefono: '900000013', p_dni: DNI_SIN_DUENO });
      check(!error && data?.estado === 'libre', `D-13 ${on ? 'ON' : 'OFF'}: un DNI sin persona ni reserva sigue «libre» en el verificador`, errorText(error) || JSON.stringify(data));
    }
    check(cuenta('sin identidad fantasma', `select count(*) from crm.inversionista_identificadores where documento_normalizado='${DNI_SIN_DUENO}'`) === 0,
      'D-13: verificar no crea identidades');
  } finally {
    flag(false);
  }
}

async function testConversionMensual(sessions, seed) {
  console.log('\n— Conversion mensual ponderada (migracion A) —');

  // El periodo se calcula EN LIMA, no en la zona de la maquina: la RPC rechaza
  // el mes futuro comparando contra date_trunc('month', now() at time zone
  // 'America/Lima'), y de madrugada UTC el mes local puede ser todavia el
  // anterior — el gate pediria un mes futuro y moriria con 22023 sin que nada
  // este roto.
  const enLima = (fecha) => new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(fecha);
  const MES = enLima(new Date()).slice(0, 7);
  const PERIODO = `${MES}-01`;
  const ids = seed.profileIdByKey;
  const bankProfileId = ids[BANK_CLIENT.key];

  const pedir = (clave, periodo = PERIODO) => sessions[clave].client
    .schema('crm').rpc('conversion_mensual_fn', { p_periodo: periodo });
  const filasDe = (payload) => payload?.responsables ?? [];
  const idsDe = (payload) => new Set(filasDe(payload).map((fila) => fila.vendedor_id));
  const filaDe = (payload, vendedorId) => filasDe(payload)
    .find((fila) => fila.vendedor_id === vendedorId) ?? null;
  const clavesDe = (objeto) => Object.keys(objeto ?? {}).sort();
  const mismasClaves = (objeto, esperadas) => JSON.stringify(clavesDe(objeto))
    === JSON.stringify(esperadas);
  // Serializacion canonica: dos payloads con las mismas claves en otro orden son
  // el MISMO payload. Sin esto la paridad compararia el orden de jsonb, no los
  // datos.
  const canonico = (valor) => JSON.stringify(valor, (_clave, v) => (
    v && typeof v === 'object' && !Array.isArray(v)
      ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, v[k]]))
      : v));
  // `generado_en` es el reloj de la llamada: comparar dos payloads sin quitarlo
  // solo demostraria que el tiempo pasa.
  const sinReloj = (payload) => canonico({ ...payload, generado_en: null });
  const num = (valor) => Number(valor ?? 0);
  const cerca = (a, b, tolerancia = 1e-9) => Math.abs(num(a) - num(b)) <= tolerancia;

  const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  // Precondicion DURA, no un check: si un refactor futuro vuelve a dejar un id
  // en `undefined`, supabase-js lo elimina al serializar y los leads nacen con
  // uuid aleatorio que nadie limpia, la RPC de cierre viaja sin argumento
  // (PGRST202) y el `.in('id', [undefined])` de la limpieza muere con 22P02
  // TRESCIENTAS lineas mas abajo. Que muera aqui, nombrando la causa.
  assertSeed(
    Object.values(IDS_CONVERSION).every((id) => typeof id === 'string' && UUID_V4.test(id)),
    'los cuatro ids transitorios de la conversion deben ser uuid v4 reales',
  );

  // ── 0 · LINEA BASE: la foto del mes ANTES de tocar nada ────────────────────
  const antes = await positive(
    'gerencia fotografia la conversion del mes ANTES de sembrar (linea base)',
    pedir('gerencia'),
  );
  if (!antes) {
    fail('sin linea base no se puede aseverar ni una delta: el bloque de conversion se aborta');
    return;
  }
  const filaAntesVend1 = filaDe(antes.data, ids.vend1);
  const totalAntes = antes.data?.total ?? {};
  const coberturaAntes = antes.data?.cobertura ?? {};
  // 🔴 Banco persistente (01/09): el divisor bebe del ledger INSERT-only, asi
  //    que sup1 —el productor fuera de roster que siembra este bloque— puede
  //    YA contar como analista del mes por una corrida anterior, y entonces el
  //    delta de `analistas` (conteo de DISTINTOS) es 0 y no 1. En vez de
  //    adivinarlo por los agregados, se MIDE en el ledger antes de sembrar y
  //    el delta esperado se calcula exacto: 1 en mes virgen, 0 si ya contaba.
  //    El delta de `divisor` sigue siendo +1 estricto en ambos casos — esa es
  //    la guarda que impide el «0 > 0» que este productor vino a matar.
  //    El ledger esta sellado tambien para service_role (42501 por PostgREST),
  //    asi que la medicion va por la via fuera de banda del banco, igual que
  //    la baja historica. Lima es UTC-5 fijo (sin DST).
  //
  //    ⚠️ Codex refuto la primera version, que contaba `lead_asignaciones` con
  //    `asignado_en >= dia 1`: el servidor NO define asi «analista del mes».
  //    Lo define con `private.conversion_mensual_por_vendedor(v_ini, v_fin, …)`,
  //    cuya `base` mete tambien cierres no anulados y operaciones elegibles por
  //    FULL OUTER JOIN — una asignacion VIEJA cerrada este mes ya hace contar a
  //    sup1 aunque el ledger crudo diera 0, y una asignacion FUTURA daria
  //    positivo aunque el servidor la excluya. Se pregunta a LA MISMA funcion,
  //    con la misma ventana, alcance global y factor: la unica forma de que la
  //    medicion no pueda divergir del juez.
  const sup1Previas = contarFueraDeBanda(
    'medir si sup1 ya contaba como analista del mes (misma funcion que el servidor)',
    `select count(*) from private.conversion_mensual_por_vendedor(
        ('${PERIODO}'::date)::timestamp at time zone 'America/Lima',
        (('${PERIODO}'::date + interval '1 month')::timestamp at time zone 'America/Lima'),
        true, '{}'::uuid[],
        private.peso_referido_conversion('${PERIODO}'::date)
      ) t where t.analista_id = '${ids.sup1}'`,
  );
  const deltaAnalistaFueraRoster = sup1Previas > 0 ? 0 : 1;
  if (!check(filaAntesVend1 !== null,
    'vend1 tiene fila en la linea base: los tramos de delta, paridad y soft-delete tienen sujeto',
    JSON.stringify([...idsDe(antes.data)]))) {
    return;
  }
  // El LEFT JOIN desde el roster: «desaparecer no es un estado». Se asevera
  // que TODA fila del roster viaje con estado, sea cual sea — antes se exigia
  // una `sin_actividad`, y eso convertia el roster en un recurso agotable (ver
  // abajo). Lo que prueba el LEFT JOIN es que el roster manda: si un analista
  // del roster faltara del payload, esto se pone rojo.
  check(filasDe(antes.data).length > 0
    && filasDe(antes.data).every((fila) => typeof fila.estado === 'string' && fila.estado.length > 0),
    'toda fila del roster viaja con estado (el roster manda, no la actividad)',
    JSON.stringify(filasDe(antes.data).map((f) => [f.vendedor_id, f.estado])));

  // El sujeto de `solo_referidos` se elige del PAYLOAD, no del fixture: quien
  // esta ocioso depende de lo que hayan hecho los bloques anteriores de main()
  // (testReassignmentTrigger y testTareaFollowsLead mueven leads a vend2), y
  // clavar una clave aqui seria un fixture que caduca al reordenar el gate.
  //
  // 🔴 REUTILIZABLE (Codex, 01/09). Antes exigia `referidos.recibidos === 0`, o
  //    sea un analista VIRGEN — pero darle el referido lo mete en el ledger
  //    INSERT-only, asi que cada corrida quemaba uno y a la sexta ya no quedaba
  //    ninguno (medido: 0 de 6). Como el ledger no se puede limpiar —y no se
  //    va a tocar ese candado— el arreglo es no pedir virginidad: basta con
  //    divisor y cierres en cero (que es LO QUE DEFINE el tercer estado), y las
  //    aserciones pasan a ser DELTAS sobre su foto previa. Asi el mismo
  //    candidato sirve indefinidamente y el bloque es re-corrible.
  const candidato = filasDe(antes.data).find((fila) => Number(fila.divisor) === 0
    && Number(fila.cierres_no_referidos) === 0
    && Number(fila.cierres_referidos) === 0);
  if (!check(candidato != null,
    'hay un analista del roster con divisor y cierres en cero al que darle un referido (sujeto del tercer estado)',
    JSON.stringify(filasDe(antes.data).map((f) => [f.vendedor_id, f.divisor, f.estado])))) {
    return;
  }
  const candidatoId = candidato.vendedor_id;
  const candidatoAntes = {
    recibidos: num(candidato.referidos?.recibidos),
    dadosDeAlta: num(candidato.referidos?.dados_de_alta),
    divisor: num(candidato.divisor),
  };

  try {
    // ── 0b · la semilla, por la VIA REAL ────────────────────────────────────
    // Los cierres se producen con `crm.convertir_lead` y la sesion del analista:
    // el ledger solo registra un cierre cuando el trigger lo ve pasar, y un
    // UPDATE directo a etapa='convertido' es imposible incluso con service_role
    // (exige crm.op_privilegiada, que solo pone esa RPC). El cliente destino es
    // el del fixture bancario, cuyo asesor_perfil_id ES vend1 — convertir_lead
    // exige que el cliente pertenezca a la cartera de quien cierra.
    const leadComun = {
      activo: true,
      asignado_supervisor_id: null,
      etapa: 'nuevo',
      moneda: 'PEN',
      no_contactar: false,
    };
    await requireAdmin(
      'sembrar los cuatro leads de la conversion',
      admin.schema('crm').from('leads').insert([
        {
          // origen 'referido' → FUERA del divisor (T10) y al 15 % en el
          // numerador. Nace creado_por vend1 para ejercitar tambien
          // `referidos.dados_de_alta`.
          ...leadComun,
          creado_por: ids.vend1,
          id: IDS_CONVERSION.leadReferido,
          monto_estimado: 9000,
          nombre_completo: 'CONVERSION REFERIDO TRANSIENT',
          origen: 'referido',
          telefono: '999000130',
          vendedor_id: ids.vend1,
        },
        {
          ...leadComun,
          creado_por: ids.vend1,
          id: IDS_CONVERSION.leadDirecto,
          monto_estimado: 11000,
          nombre_completo: 'CONVERSION DIRECTO TRANSIENT',
          origen: 'otro',
          telefono: '999000131',
          vendedor_id: ids.vend1,
        },
        {
          // El TERCER estado. Un analista al que en el mes solo le llega un
          // referido tiene divisor 0 LEGITIMO: trabajo sin denominador. Sin
          // esta fila el gate solo veria 'medible' y 'sin_actividad', y la
          // rama que T10 estreno seria inobservable.
          ...leadComun,
          creado_por: candidatoId,
          id: IDS_CONVERSION.leadSoloReferidos,
          monto_estimado: 4000,
          nombre_completo: 'CONVERSION SOLO REFERIDOS TRANSIENT',
          origen: 'referido',
          telefono: '999000132',
          vendedor_id: candidatoId,
        },
        {
          // Un PRODUCTOR fuera del roster. El guard de tenencia admite
          // explicitamente a un supervisor como analista
          // (`es_destino_crm_activo(vendedor_id, array['vendedor','supervisor'])`)
          // y `roster_metas_vendedores()` solo devuelve rol 'vendedor': su
          // episodio entra en `base`, no en `roster`, y cae en
          // `cobertura.fuera_de_roster`. Sin el, ese agregado vale 0 para todos
          // y las tres comparaciones de monotonia que lo usan son `0 > 0`:
          // aserciones que no pueden fallar. Da ademas sujeto real a «los
          // supervisores no figuran como filas».
          ...leadComun,
          creado_por: ids.sup1,
          id: IDS_CONVERSION.leadFueraDeRoster,
          monto_estimado: 3000,
          nombre_completo: 'CONVERSION FUERA DE ROSTER TRANSIENT',
          origen: 'otro',
          telefono: '999000133',
          vendedor_id: ids.sup1,
        },
      ]),
    );
    for (const [etiqueta, leadId] of [
      ['referido', IDS_CONVERSION.leadReferido],
      ['directo', IDS_CONVERSION.leadDirecto],
    ]) {
      await positive(
        `vend1 cierra el lead ${etiqueta} por la via real (convertir_lead)`,
        sessions.vend1.client.schema('crm').rpc('convertir_lead', {
          p_lead_id: leadId,
          p_perfil_id: bankProfileId,
        }),
      );
    }

    // ── A · permitidos y forma ──────────────────────────────────────────────
    const global = await positive(
      'gerencia obtiene la conversion mensual de la empresa',
      pedir('gerencia'),
    );
    if (!check(global !== null,
      'sin el payload de gerencia no hay oraculo: el bloque de conversion se aborta')) {
      return;
    }
    const payload = global.data;
    check(payload?.version === 1, 'el payload de conversion declara version 1');
    check(payload?.alcance === 'global', 'gerencia recibe alcance "global"');
    check(Array.isArray(payload?.responsables),
      'responsables es SIEMPRE un array, nunca null');
    check(payload?.periodo?.mes === MES && payload?.periodo?.zona === 'America/Lima',
      'el periodo viaja etiquetado y en hora de Lima',
      JSON.stringify(payload?.periodo));
    const factor = Number(payload?.ponderacion?.referido ?? 0);
    check(factor === 0.15 && payload?.ponderacion?.fuente === 'crm.conversion_pesos',
      'la ponderacion vigente es 0,15 y declara su fuente versionada',
      JSON.stringify(payload?.ponderacion));
    // Eco del contrato para el `v.literal` del front: si un servidor viejo
    // colara otra definicion del divisor, el cliente lo rechaza en vez de pintar
    // un numero de otra formula. OJO con lo que esto NO es: son literales de
    // jsonb_build_object, asi que ningun cambio de COMPORTAMIENTO puede
    // romperlos — cambiar el numerador a `finalizado_en` dejando la cadena
    // intacta pasa por aqui sin despeinarse. La formula la cubren las deltas
    // del tramo E, no estas tres cadenas.
    check(payload?.fuentes?.divisor === 'crm.lead_asignaciones.asignado_en'
      && payload?.fuentes?.numerador === 'crm.lead_asignaciones.resultado_en'
      && payload?.fuentes?.referido === 'crm.lead_asignaciones.origen',
      'las tres fuentes viajan literales para el contrato fail-closed',
      JSON.stringify(payload?.fuentes));

    const directorio = await positive(
      'directorio (lector global) obtiene la conversion de la empresa',
      pedir('directorio'),
    );
    if (directorio) {
      check(directorio.data?.alcance === 'global',
        'el lector global recibe alcance "global" (no cae en el deny-by-default de vendedor_ids_visibles)');
      check(JSON.stringify([...idsDe(directorio.data)].sort())
        === JSON.stringify([...idsDe(payload)].sort()),
        'directorio ve EL MISMO conjunto de responsables que gerencia');
    }

    const deSup1 = await positive('sup1 obtiene la conversion de SU equipo', pedir('sup1'));
    const deSup2 = await positive('sup2 obtiene la conversion de SU equipo', pedir('sup2'));
    const deNested = await positive('sup1Nested obtiene la conversion de su rama', pedir('sup1Nested'));
    if (deSup1) {
      const suyos = idsDe(deSup1.data);
      check(deSup1.data?.alcance === 'equipo', 'el supervisor recibe alcance "equipo"');
      // vendNested cuelga de sup1Nested, que cuelga de sup1: prueba la RECURSION.
      check(suyos.has(ids.vendNested),
        'el subarbol es RECURSIVO: sup1 ve al analista de su supervisor anidado');
      check(!suyos.has(ids.vend3) && !suyos.has(ids.vend4),
        'sup1 NO ve la rama de sup2');
      // Ahora sup1 SI produce (lead fuera de roster) y sigue sin ser fila: la
      // asercion pasa a tener sujeto en vez de ser decorativa.
      check(!suyos.has(ids.sup1) && !suyos.has(ids.sup1Nested),
        'un supervisor que PRODUCE no figura como fila (roster + filtrar_desglose_sujetos_crm)');
      check(!suyos.has(ids.vendInactive),
        'sup1 no ve a vendInactive (recorte de AMBITO: cuelga de sup2, no del roster)');
    }
    if (deSup2) {
      const suyos = idsDe(deSup2.data);
      check(suyos.has(ids.vend3) && suyos.has(ids.vend4), 'sup2 ve a sus dos analistas');
      check(!suyos.has(ids.vend1) && !suyos.has(ids.vend2) && !suyos.has(ids.vendNested),
        'sup2 NO ve el subarbol de sup1');
      // AQUI la revocacion es una decision y no un accidente de topologia: el
      // CTE recursivo de private.vendedor_ids_visibles recorre crm.equipo SIN
      // predicado de `activo`, asi que vendInactive SI esta en el ambito de
      // sup2 (el propio gate lo constata en testMetasVersionadas). Lo unico que
      // lo saca es el roster, que exige rol_crm activo en los dos extremos. Es
      // la invariante de [[crm-p04-revocado-vs-ajeno]]: offboarding =
      // activo=false, y un analista dado de baja no reaparece con nombre propio
      // en el informe que decide sueldos.
      check(!suyos.has(ids.vendInactive),
        'sup2 NO ve a vendInactive aunque SI esta en su subarbol: lo excluye el ROSTER',
        JSON.stringify([...suyos]));
    }
    check(!idsDe(payload).has(ids.vendInactive),
      'gerencia tampoco ve a vendInactive: el roster es el unico guardian en alcance global');
    if (directorio) {
      check(!idsDe(directorio.data).has(ids.vendInactive),
        'el lector global tampoco ve a vendInactive');
    }
    if (deNested) {
      check(![ids.vend1, ids.vend2].some((id) => idsDe(deNested.data).has(id)),
        'sup1Nested no mira HACIA ARRIBA: solo su propia rama');
    }

    const propio = await positive('vend1 obtiene SU propia conversion', pedir('vend1'));
    if (propio) {
      const filas = filasDe(propio.data);
      check(propio.data?.alcance === 'propio', 'el analista recibe alcance "propio"');
      check(filas.length === 1 && filas[0]?.vendedor_id === ids.vend1,
        'el analista recibe EXACTAMENTE una fila y es la suya',
        JSON.stringify(filas.map((f) => f.vendedor_id)));
    }

    // ── B · denegaciones DURAS: 42501, jamas un payload de ceros ─────────────
    // Un cero se leeria como «0 % de conversion», o sea como que no cerro nada
    // de lo que recibio: por eso la denegacion es un ERROR y no una lista vacia.
    //   coordinador     — miembro del CRM con rol denegado por contrato (la
    //                     allowlist existe para que `rol_crm is not null` no lo
    //                     cuele).
    //   vendInactive    — membresia inactiva = revocacion.
    //   clientBank      — cliente del portal y, a la vez, AJENO al CRM: no tiene
    //                     fila en crm.equipo. El fixture no distingue esos dos
    //                     casos porque no hay un tercer actor sin membresia.
    for (const clave of ['coordinador', 'vendInactive', 'clientBank']) {
      await expectExplicitAuthorizationDenied(
        `${clave} recibe 42501 en conversion_mensual_fn`,
        pedir(clave),
        ['42501'],
      );
    }

    // ── C · ORDEN de los errores: el codigo NO puede ser un oraculo de pertenencia
    // Si el gate corriera DESPUES de validar el periodo, un ajeno sabria por el
    // codigo de error si el periodo que adivino era el bueno.
    const DIA_15 = `${MES}-15`;
    const MES_FUTURO = `${Number(MES.slice(0, 4)) + 1}-01-01`;
    for (const clave of ['coordinador', 'clientBank']) {
      await expectExplicitAuthorizationDenied(
        `${clave} con un periodo basura recibe 42501 y NO 22023`,
        pedir(clave, DIA_15),
        ['42501'],
      );
    }
    await expectExpectedFailure(
      'gerencia recibe 22023 con un dia 15 (el periodo es MENSUAL por contrato)',
      pedir('gerencia', DIA_15),
      ['22023'],
      /periodo invalido: debe ser el primer dia del mes/i,
    );
    await expectExpectedFailure(
      'gerencia recibe 22023 con un mes futuro (no es "todavia sin datos")',
      pedir('gerencia', MES_FUTURO),
      ['22023'],
      /periodo invalido: el mes no puede ser futuro/i,
    );
    await expectExpectedFailure(
      'el analista entra en la MISMA rama de validacion que gerencia',
      pedir('vend1', MES_FUTURO),
      ['22023'],
      /periodo invalido: el mes no puede ser futuro/i,
    );

    // ── D · PARIDAD: la invariante que la casa se comprometio a custodiar ────
    // La misma persona y el mismo mes dan los MISMOS numeros mire quien mire. Es
    // lo que hace que una conversacion sobre el sueldo de alguien no dependa de
    // quien abrio la pantalla.
    const filaGerencia = filaDe(payload, ids.vend1);
    if (check(filaGerencia !== null,
      'vend1 sigue teniendo fila tras la siembra: la PARIDAD tiene sujeto',
      JSON.stringify([...idsDe(payload)]))) {
      for (const [clave, respuesta] of [['vend1', propio], ['sup1', deSup1], ['directorio', directorio]]) {
        if (!respuesta) continue;
        const fila = filaDe(respuesta.data, ids.vend1);
        check(fila !== null && canonico(fila) === canonico(filaGerencia),
          `PARIDAD: la fila de vend1 es identica campo a campo para ${clave} y para gerencia`,
          JSON.stringify({ [clave]: fila, gerencia: filaGerencia }));
      }
    }

    // ── E · DELTAS EXACTAS: la unica prueba de T1, T2 y T10 ──────────────────
    // Dos leads recibidos por vend1 en el mes, uno REFERIDO, los dos cerrados
    // por el. Si el referido volviera al divisor —la reversion natural de la
    // regla que Miguel cambio la noche del 2026-08-10— la delta seria +2 y no
    // +1, y el porcentaje seguiria cuadrando con el resto del payload: las
    // invariantes internas no lo verian.
    const filaDespuesVend1 = filaGerencia;
    const deltaVend1 = (extraer) => num(extraer(filaDespuesVend1)) - num(extraer(filaAntesVend1));
    check(deltaVend1((f) => f.divisor) === 1,
      'T10 · el divisor de vend1 sube +1 (el REFERIDO no entra: seria +2)',
      JSON.stringify({ antes: filaAntesVend1.divisor, despues: filaDespuesVend1.divisor }));
    check(deltaVend1((f) => f.referidos.recibidos) === 1,
      'T10 · el referido recibido SI se cuenta, en su propio contador');
    check(deltaVend1((f) => f.cierres_no_referidos) === 1
      && deltaVend1((f) => f.cierres_referidos) === 1,
      'T2/T3 · los dos cierres del mes se atribuyen a vend1, cada uno en su cubo',
      JSON.stringify({ cnr: deltaVend1((f) => f.cierres_no_referidos), cr: deltaVend1((f) => f.cierres_referidos) }));
    check(cerca(deltaVend1((f) => f.numerador), 1.15),
      'T6 · el numerador sube 1,15 exactos: 1 + 0,15 × 1, fraccionario y sin redondear',
      String(deltaVend1((f) => f.numerador)));
    check(deltaVend1((f) => f.referidos.cerrados) === 1
      && deltaVend1((f) => f.referidos.dados_de_alta) === 1,
      'el bloque de referidos de vend1 sube su cierre y su alta del mes',
      JSON.stringify(filaDespuesVend1.referidos));

    const filaCandidato = filaDe(payload, candidatoId);
    if (check(filaCandidato !== null,
      'el analista del referido unico sigue en el payload', String(candidatoId))) {
      // DELTAS, no absolutos: el candidato puede venir de corridas anteriores
      // con referidos ya acumulados en el ledger (ver la nota de arriba). Lo
      // que prueba T10 es el MOVIMIENTO — un referido no toca el divisor.
      check(num(filaCandidato.divisor) === candidatoAntes.divisor
        && num(filaCandidato.referidos?.recibidos) === candidatoAntes.recibidos + 1,
        'T10 · recibir SOLO un referido NO mueve el divisor y sube +1 el contador de referidos',
        JSON.stringify({ antes: candidatoAntes, despues: filaCandidato }));
      check(num(filaCandidato.divisor) === 0,
        'T10 · el divisor del candidato sigue en 0: es lo que define el tercer estado',
        String(filaCandidato.divisor));
      check(filaCandidato.estado === 'solo_referidos',
        'el TERCER estado existe y se emite: divisor 0 con referidos NO es sin_actividad',
        String(filaCandidato.estado));
      check(filaCandidato.conversion_pct === null
        && filaCandidato.referidos?.aporta_pct === null,
        'sin divisor no hay porcentaje: NULL, jamas 0, ni en la fila ni en el aporte',
        JSON.stringify([filaCandidato.conversion_pct, filaCandidato.referidos?.aporta_pct]));
      check(num(filaCandidato.referidos?.dados_de_alta) === candidatoAntes.dadosDeAlta + 1,
        'el alta del referido se le acredita a quien lo dio de alta (+1 sobre su foto previa)',
        JSON.stringify({ antes: candidatoAntes.dadosDeAlta, despues: filaCandidato.referidos?.dados_de_alta }));
    }

    const totalDespues = payload?.total ?? {};
    const deltaTotal = (campo) => num(totalDespues[campo]) - num(totalAntes[campo]);
    // D8 (F2.6): el total del ambito SUMA el agregado fuera de roster. Lo
    // sembrado mueve +1 divisor por vend1 (roster) y +1 por sup1 (el productor
    // fuera de roster), cuyo analista tambien entra al total.
    check(deltaTotal('divisor') === 2
      && deltaTotal('cierres_no_referidos') === 1
      && deltaTotal('cierres_referidos') === 1
      && deltaTotal('referidos_recibidos') === 2
      && cerca(deltaTotal('numerador'), 1.15)
      && deltaTotal('analistas') === deltaAnalistaFueraRoster,
      `D8 · el TOTAL global se mueve lo sembrado INCLUYENDO al productor fuera de roster (+2 divisor, +${deltaAnalistaFueraRoster} analista segun el ledger)`,
      JSON.stringify({ antes: totalAntes, despues: totalDespues, sup1YaContaba: deltaAnalistaFueraRoster === 0 }));

    const coberturaDespues = payload?.cobertura ?? {};
    const motivoAntes = num(coberturaAntes?.divisor_por_motivo?.ingreso);
    const motivoDespues = num(coberturaDespues?.divisor_por_motivo?.ingreso);
    // F2.6 (D8): `motivos_totales` cubre TODO el divisor que el total cuenta,
    // productor fuera de roster INCLUIDO — lo sembrado mueve +2 en "ingreso"
    // (+1 vend1 del roster, +1 sup1 fuera de el), igual que el divisor del
    // total de arriba. El +1 anterior era pre-F2.6.
    check(motivoDespues - motivoAntes === 2,
      'el desglose por motivo sube +2 en "ingreso" (roster + fuera de roster, el valor REAL del CHECK)',
      JSON.stringify(coberturaDespues?.divisor_por_motivo));
    check(num(coberturaDespues?.fuera_de_roster?.analistas)
      - num(coberturaAntes?.fuera_de_roster?.analistas) === deltaAnalistaFueraRoster
      && num(coberturaDespues?.fuera_de_roster?.divisor)
      - num(coberturaAntes?.fuera_de_roster?.divisor) === 1,
      `el productor SIN rol CRM legacy \`vendedor\` se cuenta entero en fuera_de_roster, y solo alli (+1 divisor, +${deltaAnalistaFueraRoster} analista segun el ledger)`,
      JSON.stringify({ antes: coberturaAntes?.fuera_de_roster, despues: coberturaDespues?.fuera_de_roster }));
    // La sonda no puede inventarse un hueco: los dos cierres que acaban de
    // nacer TIENEN su episodio cerrado dentro del mismo mes. Si la ventana del
    // `not exists` estuviera mal escrita, estos dos apareceria como cierres sin
    // respaldo y la delta seria +2.
    check(num(coberturaDespues?.cierres_sin_episodio)
      - num(coberturaAntes?.cierres_sin_episodio) === 0,
      'dos cierres por la via real NO ensucian la sonda cierres_sin_episodio',
      JSON.stringify({ antes: coberturaAntes?.cierres_sin_episodio, despues: coberturaDespues?.cierres_sin_episodio }));

    // ── E-bis · invariantes aritmeticas (sobre TODAS las filas, no sobre una) ─
    const filas = filasDe(payload);
    const desviadas = [];
    const procedenciaDescuadrada = [];
    const pctDescuadrado = [];
    const aporteDescuadrado = [];
    const estadoDescuadrado = [];
    for (const fila of filas) {
      const cnr = Number(fila.cierres_no_referidos);
      const cr = Number(fila.cierres_referidos);
      const div = Number(fila.divisor);
      if (!cerca(fila.numerador, cnr + factor * cr)) desviadas.push(fila.vendedor_id);
      const cierresProcedencia = (fila.procedencia ?? [])
        .reduce((suma, tramo) => suma + Number(tramo.cierres), 0);
      const referidosProcedencia = (fila.procedencia ?? [])
        .reduce((suma, tramo) => suma + Number(tramo.cierres_referidos), 0);
      if (cierresProcedencia !== cnr + cr || referidosProcedencia !== cr) {
        procedenciaDescuadrada.push(fila.vendedor_id);
      }
      // NULL, jamas 0, cuando el divisor es 0: «sin datos» y «0 %» son dos
      // frases muy distintas sobre el trabajo de una persona.
      const pctEsperado = div > 0 ? (100 * Number(fila.numerador)) / div : null;
      if (pctEsperado === null
        ? fila.conversion_pct !== null
        : Math.abs(Number(fila.conversion_pct) - pctEsperado) > 0.01) {
        pctDescuadrado.push(fila.vendedor_id);
      }
      // `aporta_pct` lleva el FACTOR dentro. Sin el, la pantalla diria que los
      // referidos pusieron 100 puntos donde pusieron 15.
      const aporteEsperado = div > 0 ? (100 * factor * cr) / div : null;
      if (aporteEsperado === null
        ? fila.referidos?.aporta_pct !== null
        : Math.abs(Number(fila.referidos?.aporta_pct) - aporteEsperado) > 0.01) {
        aporteDescuadrado.push(fila.vendedor_id);
      }
      // ⚠️ Lo que este case NO prueba es el ORDEN de sus dos ramas centrales,
      // porque replica el mismo case del servidor y solo lo discriminaria una
      // fila con divisor 0, referidos > 0 Y cierres > 0 — un arrastre, que por
      // la Data API es INFABRICABLE (el reloj del ledger lo sella el trigger).
      // Ese caso vive en supabase/scripts/test-conversion-mensual.sql
      // (CONV-04b y CONV-08), que retro-fecha episodios con
      // session_replication_role.
      let estadoEsperado = 'sin_actividad';
      if (div > 0) estadoEsperado = 'medible';
      else if (Number(fila.referidos?.recibidos) > 0) estadoEsperado = 'solo_referidos';
      else if (cnr + cr > 0) estadoEsperado = 'solo_arrastre';
      if (fila.estado !== estadoEsperado || !ESTADOS_CONVERSION.has(fila.estado)) {
        estadoDescuadrado.push(`${fila.vendedor_id}:${fila.estado}`);
      }
    }
    check(desviadas.length === 0,
      'numerador == cierres_no_referidos + 0,15 x cierres_referidos en TODAS las filas',
      desviadas.join(','));
    check(procedenciaDescuadrada.length === 0,
      'la suma de procedencia[].cierres cuadra con los cierres de la fila',
      procedenciaDescuadrada.join(','));
    check(pctDescuadrado.length === 0,
      'conversion_pct es 100 x numerador / divisor, y NULL —jamas 0— sin divisor',
      pctDescuadrado.join(','));
    check(aporteDescuadrado.length === 0,
      'referidos.aporta_pct lleva el factor 0,15 dentro (y es NULL sin divisor)',
      aporteDescuadrado.join(','));
    check(estadoDescuadrado.length === 0,
      'cada estado se deriva de los numeros de su propia fila',
      estadoDescuadrado.join(','));
    check(filas.some((fila) => fila.estado === 'medible')
      && filas.some((fila) => fila.estado === 'solo_referidos'),
      'el payload emite de verdad DOS de los cuatro estados (solo_arrastre es del oraculo SQL)',
      JSON.stringify(filas.map((f) => f.estado)));

    // NO VACUIDAD (leccion de RETOMAR-44): sin un cierre de referido, la formula
    // se prueba sobre 0 == 0 y el redondeo que borraria el aporte de los
    // referidos (0,15 × 1 al entero mas cercano es 0) no se ejercita jamas.
    const conCierreReferido = filas.filter((fila) => Number(fila.cierres_referidos) > 0);
    check(conCierreReferido.length > 0,
      'al menos una fila tiene un cierre de REFERIDO: la aritmetica no se prueba sobre ceros',
      JSON.stringify(filas.map((f) => [f.vendedor_id, f.cierres_referidos])));
    check(filas.some((fila) => Number(fila.divisor) > 0),
      'al menos una fila tiene divisor > 0: el mes tiene muestra de verdad');
    for (const fila of conCierreReferido) {
      const esperado = Number(fila.cierres_no_referidos) + factor * Number(fila.cierres_referidos);
      if (esperado % 1 === 0) continue;
      check(Number(fila.numerador) % 1 !== 0,
        'el numerador viaja FRACCIONARIO y sin redondear (0,15 x 1 = 0,15, no 0)',
        `${fila.vendedor_id} → ${fila.numerador}`);
    }

    // El ORDEN de `responsables` es DECISION DE PRODUCTO, no un detalle: «quien
    // no recibio nada NO encabeza el ranking por tener el porcentaje en NULL».
    // Cambiar `nulls last` por `nulls first` pone a los ociosos delante y
    // ninguna otra asercion del bloque lo mira.
    const posiciones = filas.map((fila) => fila.conversion_pct);
    const primeraNula = posiciones.findIndex((pct) => pct === null);
    check(primeraNula === -1
      || posiciones.slice(primeraNula).every((pct) => pct === null),
      'el ranking pone los porcentajes NULOS al final (nulls last), nunca encabezando',
      JSON.stringify(posiciones));
    const conPct = posiciones.filter((pct) => pct !== null).map(Number);
    check(conPct.every((pct, i) => i === 0 || conPct[i - 1] >= pct),
      'dentro del tramo con porcentaje el orden es descendente',
      JSON.stringify(conPct));

    // El TOTAL se recalcula sobre el ambito YA recortado: no es la media de los
    // porcentajes de las filas, y tiene que cuadrar para CADA alcance, no solo
    // para el global (si solo cuadrara en global, el recorte del supervisor
    // estaria dejando fuera filas que el total sigue contando).
    for (const [clave, respuesta] of [
      ['gerencia', global], ['directorio', directorio], ['sup1', deSup1],
      ['sup2', deSup2], ['vend1', propio],
    ]) {
      if (!respuesta) continue;
      const suyas = filasDe(respuesta.data);
      const total = respuesta.data?.total ?? {};
      const suma = (extraer) => suyas.reduce((acumulado, fila) => acumulado + Number(extraer(fila)), 0);
      // D8 (F2.6): el total del ambito = filas con identidad + el agregado
      // fuera de roster que el MISMO payload declara en cobertura. La igualdad
      // por alcance sigue siendo la verificacion cruzada: si el recorte dejara
      // fuera filas que el total cuenta (o al reves), aqui se rompe. El
      // agregado no desglosa referidos_recibidos y el fixture no siembra
      // referidos fuera de roster (el lead de sup1 es origen 'otro'): esa
      // clave se cuadra solo contra las filas. Los cierres se cuadran
      // combinados porque el agregado declara `cierres` sin partir.
      const fuera = respuesta.data?.cobertura?.fuera_de_roster ?? {};
      check(Number(total.analistas) === suyas.length + num(fuera.analistas),
        `${clave}: total.analistas == responsables + fuera_de_roster.analistas`,
        JSON.stringify({ total: total.analistas, filas: suyas.length, fuera: fuera.analistas }));
      check(Number(total.divisor) === suma((f) => f.divisor) + num(fuera.divisor)
        && Number(total.cierres_no_referidos) + Number(total.cierres_referidos)
          === suma((f) => f.cierres_no_referidos) + suma((f) => f.cierres_referidos) + num(fuera.cierres)
        && Number(total.referidos_recibidos) === suma((f) => f.referidos.recibidos)
        && cerca(total.numerador, suma((f) => f.numerador) + num(fuera.numerador)),
        `${clave}: total.* == suma de responsables[].* + fuera_de_roster.*`,
        JSON.stringify({ total, fuera }));
      const totalPctEsperado = Number(total.divisor) > 0
        ? (100 * Number(total.numerador)) / Number(total.divisor)
        : null;
      check(totalPctEsperado === null
        ? total.conversion_pct === null
        : Math.abs(Number(total.conversion_pct) - totalPctEsperado) <= 0.01,
        `${clave}: total.conversion_pct se RECALCULA (no promedia porcentajes) y es NULL sin divisor`,
        JSON.stringify({ pct: total.conversion_pct, esperado: totalPctEsperado }));
      // El desglose por motivo del ambito se agrega desde las MISMAS filas: si su
      // suma no es el divisor, hay un lead contado en un sitio y no en el otro.
      const porMotivo = Object.values(respuesta.data?.cobertura?.divisor_por_motivo ?? {})
        .reduce((acumulado, valor) => acumulado + Number(valor), 0);
      check(porMotivo === Number(total.divisor),
        `${clave}: cobertura.divisor_por_motivo suma exactamente el divisor del ambito`,
        JSON.stringify({ porMotivo, divisor: total.divisor }));
    }

    // D8 · el lado DENEGADO del agregado: el productor fuera de roster es
    // sup1, ajeno al subarbol de sup2 — el ambito de sup2 no puede sumarlo
    // ni verlo, y su total queda intacto por la igualdad del bucle de arriba.
    if (deSup2) {
      // El ambito de sup2 SI declara fuera-de-roster propio: vendInactive (su
      // ex-miembro con episodios, la baja historica del seed) — exactamente el
      // «dado de baja a mitad de mes» que F2.6 documenta. Lo que NO puede
      // entrar es lo PRODUCIDO por el ajeno (sup1): ni sus cierres ni su
      // numerador. El 0 absoluto en analistas era pre-baja-historica.
      check(num(deSup2.data?.cobertura?.fuera_de_roster?.cierres) === 0
        && num(deSup2.data?.cobertura?.fuera_de_roster?.numerador) === 0,
        'D8 · lo producido por el fuera-de-roster ajeno NO entra al ambito de sup2',
        JSON.stringify(deSup2.data?.cobertura?.fuera_de_roster));
    }

    // ── F · forma del contrato: una clave de mas es superficie sin auditar ───
    check(mismasClaves(payload, CLAVES_PAYLOAD_CONVERSION),
      'el payload trae SOLO las 11 claves del contrato', clavesDe(payload).join(','));
    check(mismasClaves(payload?.periodo, CLAVES_PERIODO_CONVERSION),
      'periodo trae SOLO sus 6 claves', clavesDe(payload?.periodo).join(','));
    check(mismasClaves(payload?.ponderacion, CLAVES_PONDERACION_CONVERSION),
      'ponderacion trae SOLO sus 2 claves', clavesDe(payload?.ponderacion).join(','));
    check(mismasClaves(payload?.cobertura, CLAVES_COBERTURA_CONVERSION),
      'cobertura trae SOLO las 7 claves del contrato', clavesDe(payload?.cobertura).join(','));
    check(mismasClaves(payload?.total, CLAVES_TOTAL_CONVERSION),
      'total trae SOLO las 10 claves del contrato', clavesDe(payload?.total).join(','));
    check(mismasClaves(payload?.cobertura?.fuera_de_roster, CLAVES_FUERA_DE_ROSTER),
      'fuera_de_roster es un AGREGADO SIN IDENTIDAD (ni un uuid dentro)',
      clavesDe(payload?.cobertura?.fuera_de_roster).join(','));
    check(MOTIVOS_NO_MEDIBLE.has(payload?.cobertura?.motivo_no_medible ?? null),
      'motivo_no_medible pertenece al vocabulario CERRADO que el front declara como picklist',
      String(payload?.cobertura?.motivo_no_medible));

    const clavesFilas = [...new Set(filas.flatMap((fila) => Object.keys(fila)))].sort();
    check(clavesFilas.length > 0
      && JSON.stringify(clavesFilas) === JSON.stringify(CLAVES_RESPONSABLE_CONVERSION),
      'cada responsable trae SOLO las 13 claves del contrato', clavesFilas.join(','));
    const clavesReferidos = [...new Set(filas
      .flatMap((fila) => Object.keys(fila.referidos ?? {})))].sort();
    check(JSON.stringify(clavesReferidos) === JSON.stringify(CLAVES_REFERIDOS_CONVERSION),
      'el bloque referidos trae SOLO sus 4 claves', clavesReferidos.join(','));
    const tramos = filas.flatMap((fila) => fila.procedencia ?? []);
    const clavesTramo = [...new Set(tramos.flatMap((tramo) => Object.keys(tramo)))].sort();
    check(tramos.length > 0
      && JSON.stringify(clavesTramo) === JSON.stringify(CLAVES_PROCEDENCIA_CONVERSION),
      'cada tramo de procedencia trae SOLO sus 5 claves (y hay al menos uno)',
      clavesTramo.join(','));
    // La procedencia se compara como texto 'YYYY-MM': ningun cierre puede venir
    // de un mes POSTERIOR al que se pregunta, y el mes en curso tiene que estar
    // (los dos cierres del tramo 0 nacieron y murieron en el). ⚠️ `mes` es NULL
    // A PROPOSITO en el cubo `anteriores` (cierres de mas de 11 meses atras), y
    // en JavaScript `typeof null === 'object'`: exigir `typeof === 'string'` a
    // secas pondria el gate en rojo contra un payload perfectamente correcto el
    // primer mes en que alguien cierre cartera de mas de un ano.
    check(tramos.some((tramo) => tramo.mes === MES)
      && tramos.every((tramo) => tramo.mes === null
        || (typeof tramo.mes === 'string' && tramo.mes <= MES)),
      'la procedencia incluye el mes en curso y jamas un mes posterior',
      JSON.stringify(tramos.map((t) => t.mes)));
    check(tramos.every((tramo) => tramo.mes !== null
      || (tramo.mes_nombre === 'anteriores' && tramo.anio === null)),
      'el cubo sin mes se identifica como "anteriores" y sin anio: eso lo distingue de un bug',
      JSON.stringify(tramos.filter((t) => t.mes === null)));

    // ── G · lo que NO se recorta por ambito, y lo que SI ─────────────────────
    // `suelo_historico` es min(asignado_en) de TODO el ledger, sin predicado de
    // ambito, y viaja tambien al analista: la cobertura es una propiedad del
    // LEDGER —cuando empieza a existir el registro—, no de una persona. Si se
    // recortara, el supervisor de un equipo nuevo veria «mes_parcial» sobre un
    // mes que la empresa mide perfectamente, y dos roles dirian cosas distintas
    // del mismo mes.
    //
    // ⚠️ `medible` y `motivo_no_medible` NO entran en esta cabecera comun. La
    // RPC los SOBREESCRIBE a proposito (paso 5b) para alcance 'propio' cuando el
    // analista no esta en el roster — la correccion #7, que existe para que ese
    // analista no reciba una pantalla en blanco sin explicacion. Exigirlos
    // identicos entre roles cementaria como invariante justo lo que la migracion
    // rompe, y pondria el gate en rojo el dia que el fixture tenga un analista
    // fuera del roster (en produccion HOY hay 1 de 17). Se aseveran abajo, cada
    // uno donde su contrato los garantiza.
    const respuestasPorAlcance = [
      ['gerencia', global], ['directorio', directorio], ['sup1', deSup1], ['vend1', propio],
    ].filter(([, respuesta]) => respuesta);
    if (check(respuestasPorAlcance.length === 4,
      'los cuatro alcances respondieron: el tramo G tiene con que comparar')) {
      const cabeceraLedger = (datos) => canonico({
        version: datos?.version,
        periodo: datos?.periodo,
        ponderacion: datos?.ponderacion,
        fuentes: datos?.fuentes,
        suelo_historico: datos?.cobertura?.suelo_historico,
      });
      const referencia = cabeceraLedger(payload);
      for (const [clave, respuesta] of respuestasPorAlcance) {
        check(cabeceraLedger(respuesta.data) === referencia,
          `${clave}: cabecera y suelo_historico identicos a los de gerencia (metadato del LEDGER)`,
          JSON.stringify({ suyo: cabeceraLedger(respuesta.data), gerencia: referencia }));
      }
      check(payload?.cobertura?.suelo_historico !== null
        && !Number.isNaN(Date.parse(payload?.cobertura?.suelo_historico ?? '')),
        'suelo_historico se CALCULA y llega como instante utilizable (nunca una constante escrita a mano)',
        String(payload?.cobertura?.suelo_historico));

      // `medible` sin recorte para los alcances donde 5b no puede dispararse.
      for (const [clave, respuesta] of [['directorio', directorio], ['sup1', deSup1]]) {
        if (!respuesta) continue;
        check(respuesta.data?.cobertura?.medible === payload?.cobertura?.medible
          && (respuesta.data?.cobertura?.motivo_no_medible ?? null)
            === (payload?.cobertura?.motivo_no_medible ?? null),
          `${clave}: la cobertura del ledger dice lo MISMO que a gerencia (alcance no 'propio')`,
          JSON.stringify(respuesta.data?.cobertura?.motivo_no_medible));
      }
      // Y para 'propio' se asevera la regla EXACTA del paso 5b, no la igualdad:
      // si el analista esta en el roster (lo esta si tiene fila en el payload
      // global), 5b no se ejecuta y la cobertura debe coincidir; si no lo
      // estuviera, debe venir medible=false con uno de los TRES motivos de
      // exclusion. Escrito asi, el dia que el fixture crezca con un analista
      // sin supervisor esta asercion PRUEBA la correccion #7 en vez de romperse.
      if (propio) {
        const motivoPropio = propio.data?.cobertura?.motivo_no_medible ?? null;
        const vend1EnRoster = filaGerencia !== null;
        check(vend1EnRoster
          ? (propio.data?.cobertura?.medible === payload?.cobertura?.medible
            && motivoPropio === (payload?.cobertura?.motivo_no_medible ?? null))
          : (propio.data?.cobertura?.medible === false
            && MOTIVOS_EXCLUSION_ROSTER.has(motivoPropio)),
          'vend1 (alcance propio): en el roster ve la cobertura del ledger; fuera de el, su motivo de exclusion',
          JSON.stringify({ vend1EnRoster, motivoPropio }));
      }

      // Y TODO lo demas si se recorta: el ambito estrecho nunca puede ver mas que
      // el ancho. Sin esta mitad, «identico» podria significar «no recorta nada».
      const escalares = ['analistas', 'divisor', 'cierres_no_referidos', 'cierres_referidos'];
      const excesos = [];
      for (const [clave, respuesta] of [['sup1', deSup1], ['vend1', propio]]) {
        if (!respuesta) continue;
        for (const campo of escalares) {
          if (num(respuesta.data?.total?.[campo]) > num(payload?.total?.[campo])) {
            excesos.push(`${clave}.${campo}`);
          }
        }
        if (num(respuesta.data?.cobertura?.cierres_sin_episodio)
          > num(payload?.cobertura?.cierres_sin_episodio)) {
          excesos.push(`${clave}.cierres_sin_episodio`);
        }
        if (num(respuesta.data?.cobertura?.fuera_de_roster?.analistas)
          > num(payload?.cobertura?.fuera_de_roster?.analistas)) {
          excesos.push(`${clave}.fuera_de_roster`);
        }
      }
      check(excesos.length === 0,
        'ningun agregado del ambito estrecho supera al del global: todo menos el suelo se recorta',
        excesos.join(','));
      // Y el recorte de `fuera_de_roster` se asevera con CONTENIDO, no contra 0:
      // hay un productor ajeno al roster de verdad (el lead de sup1), global lo
      // cuenta y el analista —cuyo ambito es el suyo— NO puede verlo.
      check(num(payload?.cobertura?.fuera_de_roster?.analistas) >= 1,
        'fuera_de_roster tiene CONTENIDO en global: las monotonias de arriba no son 0 > 0',
        JSON.stringify(payload?.cobertura?.fuera_de_roster));
      if (propio) {
        check(num(propio.data?.cobertura?.fuera_de_roster?.analistas) === 0,
          'el analista no ve NADA del agregado de fuera de roster: su ambito es el suyo',
          JSON.stringify(propio.data?.cobertura?.fuera_de_roster));
      }
      check(num(payload?.total?.analistas) > num(deSup1?.data?.total?.analistas)
        && num(deSup1?.data?.total?.analistas) > 1
        && num(propio?.data?.total?.analistas) === 1,
        'el recorte es ESTRICTO: global > equipo > propio (y propio es exactamente 1)',
        JSON.stringify({
          global: payload?.total?.analistas,
          equipo: deSup1?.data?.total?.analistas,
          propio: propio?.data?.total?.analistas,
        }));
    }

    // La tabla del peso NO existe para la Data API: RLS ON, cero policies y cero
    // grants. El verbo peligroso no es el SELECT sino la ESCRITURA — quien pudiera
    // poner peso_referido = 1.000 reescribiria el numerador de un mes YA ENSEÑADO
    // —, pero desde una sesion de usuario solo se puede sondear la lectura; la
    // matriz de los cuatro verbos vive en el postflight de la migracion.
    for (const clave of ['gerencia', 'directorio', 'sup1', 'vend1']) {
      await expectExplicitAuthorizationDenied(
        `${clave} no lee crm.conversion_pesos por la Data API`,
        sessions[clave].client.schema('crm').from('conversion_pesos')
          .select('vigente_desde, peso_referido').limit(1),
        ['42501', 'PGRST205'],
      );
    }
    // El ledger es la fuente de TODA la metrica y sigue cerrado a la Data API: sin
    // esto, la migracion A abriria la puerta a leer los episodios crudos (con
    // analista, importe y origen) saltandose el recorte del payload.
    for (const clave of ['gerencia', 'directorio', 'vend1']) {
      await expectExplicitAuthorizationDenied(
        `${clave} no lee crm.lead_asignaciones por la Data API`,
        sessions[clave].client.schema('crm').from('lead_asignaciones')
          .select('lead_id, analista_id').limit(1),
        ['42501', 'PGRST205'],
      );
    }

    // ── H · un lead soft-borrado SIGUE contando ─────────────────────────────
    // La LEY: la conversion no filtra `activo` (un descartado cuenta, un lead
    // borrado tambien). Se cumple por construccion en el divisor y el numerador
    // —el ledger no tiene columna `activo`—, pero hay DOS sitios del payload que
    // leen `crm.leads` de verdad: la sonda `cierres_sin_episodio` y el alta de
    // referidos. Por eso se compara el payload ENTERO (menos `generado_en`) y no
    // solo la fila de vend1: anadir `and l.activo` a la sonda no movería esa
    // fila y pasaría desapercibido. Sirve ademas de limpieza del tramo 0.
    await requireAdmin(
      'desactivar los cuatro leads de la conversion (soft-delete, nunca hard-delete)',
      admin.schema('crm').from('leads').update({ activo: false })
        .in('id', Object.values(IDS_CONVERSION)).eq('activo', true),
    );
    const trasBorrar = await positive(
      'gerencia relee la conversion tras el soft-delete',
      pedir('gerencia'),
    );
    if (trasBorrar) {
      check(sinReloj(trasBorrar.data) === sinReloj(payload),
        'un lead soft-borrado no altera NI UN DIGITO del payload: la conversion NO filtra activo',
        JSON.stringify({
          antes: { cobertura: payload?.cobertura, total: payload?.total },
          despues: { cobertura: trasBorrar.data?.cobertura, total: trasBorrar.data?.total },
        }));
    }
  } finally {
    // Red de la red: si algo de arriba lanzo (requireAdmin es fatal por diseño),
    // los leads no se quedan vivos esperando al tramo H. Idempotente.
    await requireAdmin(
      'limpieza: desactivar los leads transitorios de la conversion',
      admin.schema('crm').from('leads').update({ activo: false })
        .in('id', Object.values(IDS_CONVERSION)).eq('activo', true),
    );
  }

  // ── I · anon ──────────────────────────────────────────────────────────────
  // El contrato de denegacion de la migracion nombra a anon explicitamente, y el
  // postflight (2) solo asevera el CATALOGO dentro de la propia transaccion de
  // la migracion: no prueba el canal real (PostgREST + anon key), que es donde
  // vive el riesgo. Sus cinco hermanas de metricas ya tienen esta sonda en
  // testAnon; esta vive aqui, junto a su contrato.
  const anonConversion = createClient(
    SUPABASE_URL,
    ANON_KEY,
    clientOptions('crm-rls-anon-conversion'),
  );
  await expectExplicitAuthorizationDenied(
    'anon no ejecuta conversion_mensual_fn',
    anonConversion.schema('crm').rpc('conversion_mensual_fn', { p_periodo: PERIODO }),
    ['42501', 'PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no lee crm.conversion_pesos',
    anonConversion.schema('crm').from('conversion_pesos').select('vigente_desde').limit(1),
    ['42501', 'PGRST205'],
  );
}

const IDS_CIERRES_EXTERNOS = Object.freeze({
  leadAjeno: randomUUID(),
  leadCoop: randomUUID(),
});

// ── Migracion B: la CUOTA y su conversion (crm.cumplimiento_metas_fn) ───────
// Esta funcion no tenia NI UN caso en la matriz, y desde la migracion B su
// unica defensa de ambito es el recorte posterior de la CTE `visibles`: pasa
// `p_global => true` al nucleo de conversion y confia en que el join con
// `metas_vendedor ∩ vendedor_ids_visibles` acote. Eso hay que probarlo, no
// razonarlo.
//
// El reparto del fixture (el mismo que usa testMetasVersionadas):
//   sup1 → vend1, vend2, vendNested   · NO vend3, vend4
//   sup2 → vend3, vend4
async function testCumplimientoMetas(sessions, seed) {
  console.log('\n— Cuota y conversion de metas (migracion B) —');

  const ids = seed.profileIdByKey;
  const pedir = (clave) => sessions[clave].client
    .schema('crm').rpc('cumplimiento_metas_fn', { p_periodo: PERIODO_METAS_GATE });
  const filas = (payload) => payload?.vendedores ?? [];
  const idsDe = (payload) => new Set(filas(payload).map((f) => f.vendedor_id));

  // ── A · GERENCIA ve el snapshot completo ─────────────────────────────────
  const ger = await positive('gerencia lee el cumplimiento de metas', pedir('gerencia'));
  const payGer = ger?.data;
  // Guarda anti-vacuidad: con el snapshot vacio TODAS las aserciones de ambito
  // de abajo pasarian sin probar nada (la leccion cara del 2026-08-10).
  check(filas(payGer).length > 0,
    'el snapshot de metas del gate NO esta vacio (si no, el resto pasa por vacuidad)',
    JSON.stringify({ vendedores: filas(payGer).length }));

  // ── B · FORMA del payload, valga el servidor viejo o el nuevo ────────────
  const fuente = payGer?.fuentes_reales?.conversion;
  check(fuente === 'leads_resueltos' || fuente === 'leads_recibidos_ponderado',
    'fuentes_reales.conversion declara una de las dos fuentes conocidas', String(fuente));
  if (fuente === 'leads_recibidos_ponderado') {
    // Post-B las cuatro claves nuevas tienen que venir, o el strictObject del
    // front deja SIN METAS a los tres roles a la vez.
    const fila = filas(payGer)[0];
    check(['numerador', 'cierres_no_referidos', 'cierres_referidos']
      .every((k) => fila?.[k] !== undefined),
      'post-B cada analista trae numerador y sus dos sumandos', JSON.stringify(fila));
    check(payGer?.ponderacion_referido !== undefined,
      'post-B el payload declara la ponderacion aplicada');
    check(filas(payGer).every((f) => Number(f.resueltos) >= 0),
      'ningun divisor negativo');
  }

  // ── C · SUPERVISOR: su subarbol y NADIE mas ─────────────────────────────
  const sup = await positive('sup1 lee el cumplimiento de su equipo', pedir('sup1'));
  const idsSup = idsDe(sup?.data);
  check(idsSup.size > 0, 'sup1 recibe al menos un analista de su equipo');
  check(!idsSup.has(ids.vend3),
    'sup1 NO ve a vend3, que cuelga de sup2', JSON.stringify([...idsSup]));
  check([...idsSup].every((id) => idsDe(payGer).has(id)),
    'todo lo que ve sup1 esta dentro de lo que ve gerencia');

  // ── D · ANALISTA: solo su propia fila ────────────────────────────────────
  const vend = await positive('vend1 lee su cumplimiento', pedir('vend1'));
  const idsVend = idsDe(vend?.data);
  check([...idsVend].every((id) => id === ids.vend1),
    'vend1 solo se ve a si mismo', JSON.stringify([...idsVend]));
  check(!idsVend.has(ids.vend2), 'vend1 NO ve a un companero de su propio equipo');

  // ── E · COORDINADOR: pasa el gate pero no ve a nadie ────────────────────
  // Es 200 con lista vacia, NO 42501: el gate inicial es permisivo por contrato
  // (`rol_crm is not null`) y quien acota es `vendedor_ids_visibles`.
  const coord = await positive('coordinador pasa el gate de cumplimiento', pedir('coordinador'));
  check(filas(coord?.data).length === 0,
    'el coordinador recibe la lista de analistas VACIA',
    JSON.stringify(filas(coord?.data).length));

  // ── F · LECTOR GLOBAL: la rama que `p_global => true` existe para servir ─
  const dir = await positive('directorio (lector global) lee el cumplimiento', pedir('directorio'));
  check(idsDe(dir?.data).size === idsDe(payGer).size,
    'el lector global ve el mismo snapshot que gerencia (no vacio)',
    JSON.stringify({ dir: idsDe(dir?.data).size, ger: idsDe(payGer).size }));

  // ── G · REVOCADOS y ajenos ──────────────────────────────────────────────
  for (const clave of ['vendInactive', 'clientBank']) {
    await expectExplicitAuthorizationDenied(
      `${clave} recibe 42501 en cumplimiento_metas_fn`,
      pedir(clave),
      ['42501'],
    );
  }

  // ── H · anular un cierre de AVANCE es SOLO de gerencia ──────────────────
  // El gate de rol corre ANTES de mirar el lead, asi que estos rechazos no
  // dependen de que exista un cierre: es exactamente lo que se quiere probar.
  // El caso POSITIVO (que anular baja cuota y conversion a la vez, y no le
  // regala el cierre a nadie) vive en el oraculo `test-metas-versionadas.sql`,
  // caso M19, que es donde esta montado el mundo de contratos.
  const anular = (clave) => sessions[clave].client
    .schema('crm').rpc('anular_cierre_avance', {
      p_lead_id: '00000000-0000-0000-0000-000000000000',
      p_motivo: 'intento del gate de RLS',
    });
  for (const clave of ['vend1', 'sup1', 'coordinador', 'vendInactive', 'clientBank']) {
    await expectExplicitAuthorizationDenied(
      `${clave} NO puede anular un cierre de Avance (42501)`,
      anular(clave),
      ['42501'],
    );
  }
  // Gerencia SI pasa el gate de rol: falla mas adelante, por el lead inventado.
  // Distinguir «no puedes» de «ese lead no existe» es el punto del caso.
  await expectExpectedFailure(
    'gerencia pasa el gate de rol y muere en el lead inexistente, no en 42501',
    anular('gerencia'),
    ['P0002', '22023', 'P0001'],
    /Lead no encontrado/i,
  );

  // El motivo es obligatorio, y su guarda corre ANTES de mirar el lead: por eso
  // este caso vale con un lead inventado. Quitar merito a alguien sin dejar la
  // razon escrita es justo lo que la RPC no permite.
  await expectExpectedFailure(
    'gerencia no puede anular sin motivo (22023)',
    sessions.gerencia.client.schema('crm').rpc('anular_cierre_avance', {
      p_lead_id: '00000000-0000-0000-0000-000000000000',
      p_motivo: '   ',
    }),
    ['22023', 'P0001'],
    /Escribe el motivo/i,
  );

  // La tabla es deny-by-default: nadie la lee ni la escribe por la Data API.
  await expectHidden(
    'crm.cierres_avance_anulados no se lee desde la Data API',
    sessions.gerencia.client.schema('crm').from('cierres_avance_anulados').select('id'),
  );
}


// ── Identidad multiempresa: puertas canónicas (lote Contrato-F2, «F3» del plan) ─
// Prueba los 5 invariantes de la meta por LAS PUERTAS reales (no por UPDATE
// directo), con la bandera `resolver_en_puertas` ENCENDIDA, y la paridad con la
// bandera APAGADA (aterrizaje aditivo). Las tablas de identidad son deny-by-default
// incluso para service_role: sus aserciones van por la vía fuera de banda.
const IDS_IDENTIDAD = Object.freeze({
  carreraA: randomUUID(), carreraB: randomUUID(),
  avanceUno: randomUUID(), avanceDos: randomUUID(),
  paridadOff: randomUUID(), veto: randomUUID(), heredaVeto: randomUUID(),
  clienteNuevo: randomUUID(),
});
// Documentos y teléfonos POR CORRIDA: varias tablas son append-only y la limpieza no puede
// borrar leads convertidos ni perfiles enlazados; cada corrida vive en su espacio (como el arnés).
const RUN_IDENTIDAD = String(Math.floor(1000 + Math.random() * 9000));
const DOCS_IDENTIDAD = Object.freeze({ carrera: `7${RUN_IDENTIDAD}001`, clienteNuevo: `7${RUN_IDENTIDAD}002`, veto: `7${RUN_IDENTIDAD}003`, paridadOff: `7${RUN_IDENTIDAD}004` });
const TEL_IDENTIDAD = (n) => `9${RUN_IDENTIDAD}00${String(n).padStart(2, '0')}`;  // 9 dígitos

async function testIdentidadMultiempresa(sessions, seed) {
  console.log('\n— Identidad multiempresa: puertas canónicas (lote Contrato-F2) —');
  const bankProfileId = seed.profileIdByKey[BANK_CLIENT.key];
  const vend1Id = seed.profileIdByKey.vend1;  // mismo patrón que `const ids = seed.profileIdByKey`
  const sufijo = randomUUID().slice(0, 8);
  const trx = (n) => `TRX-ID-${sufijo}-${n}`;
  // F2.b b4 (20260905110000): los hechos de inversión de la conversión coop van con la bandera de
  // F4 `inversiones_escritura`; este bloque cuenta inversiones y titulares, así que enciende las dos.
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas + inversiones_escritura',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre in ('resolver_en_puertas','inversiones_escritura');`);
  const coop = (clave, leadId, doc, n, monto = 1000) => sessions[clave].client.schema('crm')
    .rpc('convertir_lead_externo', {
      p_lead_id: leadId, p_cooperativa: 'qorilazo', p_monto: monto, p_moneda: 'PEN',
      p_documento_tipo: 'DNI', p_documento: doc, p_nombre: 'IDENTIDAD TRANSIENT',
      p_numero_transaccion: trx(n),
    });
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`identidad: ${etiqueta}`, sql);
  const idsPorDoc = (doc) => `(select i.inversionista_id from crm.inversionista_identificadores i where i.documento_normalizado='${doc}' and i.estado='vigente')`;
  const leadBase = { activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'otro', monto_estimado: 5000, creado_por: vend1Id, vendedor_id: vend1Id };

  try {
    // ── 0 · fixtures: leads SIN dni (el índice único de leads impide dos con el
    // mismo DNI; el documento entra por el parámetro de la coop o por el perfil) ─
    await requireAdmin('sembrar los leads de identidad',
      admin.schema('crm').from('leads').insert([
        { ...leadBase, id: IDS_IDENTIDAD.carreraA,   nombre_completo: 'IDENTIDAD CARRERA A TRANSIENT',  telefono: TEL_IDENTIDAD(41) },
        { ...leadBase, id: IDS_IDENTIDAD.carreraB,   nombre_completo: 'IDENTIDAD CARRERA B TRANSIENT',  telefono: TEL_IDENTIDAD(42) },
        { ...leadBase, id: IDS_IDENTIDAD.avanceUno,  nombre_completo: 'IDENTIDAD AVANCE UNO TRANSIENT', telefono: TEL_IDENTIDAD(43) },
        { ...leadBase, id: IDS_IDENTIDAD.avanceDos,  nombre_completo: 'IDENTIDAD AVANCE DOS TRANSIENT', telefono: TEL_IDENTIDAD(44) },
        { ...leadBase, id: IDS_IDENTIDAD.paridadOff, nombre_completo: 'IDENTIDAD PARIDAD OFF TRANSIENT', telefono: TEL_IDENTIDAD(45) },
        { ...leadBase, id: IDS_IDENTIDAD.veto,       nombre_completo: 'IDENTIDAD VETO TRANSIENT',        telefono: TEL_IDENTIDAD(46) },
      ]));
    flag(true);

    // ── #1 · dos conversiones SIMULTÁNEAS del MISMO documento → UNA identidad ─
    const carrera = await Promise.allSettled([
      coop('vend1', IDS_IDENTIDAD.carreraA, DOCS_IDENTIDAD.carrera, 'A'),
      coop('vend1', IDS_IDENTIDAD.carreraB, DOCS_IDENTIDAD.carrera, 'B'),
    ]);
    const ok = carrera.filter((r) => r.status === 'fulfilled' && !r.value?.error);
    const rechazos = carrera.filter((r) => r.status === 'fulfilled' && r.value?.error);
    assertions += 1;
    if (ok.length === 1 && rechazos.length === 1 && /ya tiene un lead/i.test(rechazos[0].value.error.message ?? '')) {
      console.log('  ✓ #1 carrera: UNA conversión ganó y la otra fue P0409 «ya tiene un lead»');
    } else {
      fail(`#1 carrera: esperaba 1 éxito + 1 P0409, obtuve ${ok.length} éxitos / ${rechazos.length} rechazos (${rechazos.map((r) => errorText(r.value.error)).join(' | ')})`);
    }
    const doc = DOCS_IDENTIDAD.carrera;
    if (cuenta('identidades del doc', `select count(distinct inversionista_id) from crm.inversionista_identificadores where documento_normalizado='${doc}' and estado='vigente'`) !== 1) fail('#1: más de una identidad para el mismo documento');
    if (cuenta('leads con la identidad', `select count(*) from crm.leads where inversionista_id in ${idsPorDoc(doc)}`) !== 1) fail('#1: más de un lead con inversionista_id (un solo lead total)');
    if (cuenta('inversiones', `select count(*) from crm.inversiones where inversionista_id in ${idsPorDoc(doc)}`) !== 1) fail('#1: la inversión del ganador no quedó (o se duplicó)');
    if (cuenta('titular principal', `select count(*) from crm.inversion_titulares t join crm.inversiones i on i.id=t.inversion_id where i.inversionista_id in ${idsPorDoc(doc)} and t.rol='principal'`) !== 1) fail('#1: falta el titular principal (candado #6)');
    const ganador = ok.length === 1 && carrera[0] === ok[0] ? IDS_IDENTIDAD.carreraA : IDS_IDENTIDAD.carreraB;
    const trxGanador = ganador === IDS_IDENTIDAD.carreraA ? 'A' : 'B';
    if (cuenta('cierre con identidad', `select count(*) from crm.cierres_externos where lead_id='${ganador}' and inversionista_id is not null`) !== 1) fail('#1: el cierre no nació con inversionista_id');
    if (cuenta('responsable abierto', `select count(*) from crm.inversionista_responsables where inversionista_id in ${idsPorDoc(doc)} and hasta is null`) !== 1) fail('#1: tramo de responsable de relación ≠ 1');

    // ── #4 · reintento IDÉNTICO tras éxito → mismo resultado, sin duplicar ──
    const reintento = await positive('#4 reintento idéntico del ganador', coop('vend1', ganador, doc, trxGanador));
    assertions += 1;
    if (reintento?.data?.reintento === true) console.log('  ✓ #4 el reintento devolvió reintento=true');
    else fail(`#4: el reintento no fue idempotente (${JSON.stringify(reintento?.data)})`);
    if (cuenta('inversiones tras reintento', `select count(*) from crm.inversiones where inversionista_id in ${idsPorDoc(doc)}`) !== 1) fail('#4: el reintento duplicó la inversión');
    await expectExpectedFailure('#4 misma clave con payload DISTINTO → P0409',
      coop('vend1', ganador, doc, trxGanador, 2000), ['P0409'], /datos distintos/i);
    for (const clave of ['coordinador', 'directorio', 'clientBank']) {
      await expectExplicitAuthorizationDenied(`identidad: ${clave} no convierte por coop`,
        coop(clave, IDS_IDENTIDAD.paridadOff, `7${RUN_IDENTIDAD}099`, `X${clave}`));
    }

    // ── #2 · la persona VUELVE (Avance): reutiliza su ÚNICO lead, no crea otro ─
    // El cliente bancario del fixture YA tiene identidad y lead (el backfill del banco lo
    // clasificó): convertirle OTRO lead es exactamente el caso «vuelve» → P0409.
    await expectExpectedFailure('#2 el cliente bancario (ya con identidad y lead) no convierte un SEGUNDO lead → P0409',
      sessions.vend1.client.schema('crm').rpc('convertir_lead', { p_lead_id: IDS_IDENTIDAD.avanceDos, p_perfil_id: bankProfileId }), ['P0409'], /ya tiene un lead/i);
    if (cuenta('avanceDos intacto', `select count(*) from crm.leads where id='${IDS_IDENTIDAD.avanceDos}' and etapa='nuevo' and inversionista_id is null`) !== 1) fail('#2: el segundo lead quedó tocado');
    // PRIMERA conversión por Avance: un cliente TRANSITORIO (fuera de banda, como la siembra),
    // con DNI fresco y asesor vend1, para que el resolver cree la identidad desde el perfil.
    ejecutarFueraDeBanda('cliente transitorio', `
      insert into auth.users (id) values ('${IDS_IDENTIDAD.clienteNuevo}') on conflict (id) do nothing;
      insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, asesor_perfil_id, activo)
      values ('${IDS_IDENTIDAD.clienteNuevo}', 'IDENTIDAD CLIENTE NUEVO TRANSIENT', 'cliente', 'DNI', '${DOCS_IDENTIDAD.clienteNuevo}', '${vend1Id}', true)
      on conflict (id) do nothing;`);
    const av = await positive('#2 vend1 convierte por Avance (primera vez: el resolver crea la identidad desde el perfil)',
      sessions.vend1.client.schema('crm').rpc('convertir_lead', { p_lead_id: IDS_IDENTIDAD.avanceUno, p_perfil_id: IDS_IDENTIDAD.clienteNuevo }));
    assertions += 1;
    if (av?.data?.inversionista_id) console.log('  ✓ #2 la conversión Avance devolvió inversionista_id');
    else fail(`#2: convertir_lead no devolvió inversionista_id (${JSON.stringify(av?.data)})`);
    if (cuenta('perfil enlazado', `select count(*) from crm.inversionistas where perfil_id='${IDS_IDENTIDAD.clienteNuevo}' and estado<>'fusionado'`) !== 1) fail('#2: el perfil no quedó enlazado a una identidad');
    if (cuenta('lead canónico', `select count(*) from crm.inversionista_leads where lead_id='${IDS_IDENTIDAD.avanceUno}' and rol='canonico'`) !== 1) fail('#2: falta el registro de lead canónico');
    if (cuenta('responsable Avance', `select count(*) from crm.inversionista_responsables r join crm.inversionistas i on i.id=r.inversionista_id where i.perfil_id='${IDS_IDENTIDAD.clienteNuevo}' and r.hasta is null and r.responsable_id='${vend1Id}'`) !== 1) fail('#2: el asesor no quedó como responsable de relación');
    const reAv = await positive('#4 reintento idéntico de la conversión Avance',
      sessions.vend1.client.schema('crm').rpc('convertir_lead', { p_lead_id: IDS_IDENTIDAD.avanceUno, p_perfil_id: IDS_IDENTIDAD.clienteNuevo }));
    assertions += 1;
    if (reAv?.data?.reintento === true) console.log('  ✓ #4 reintento Avance idempotente'); else fail('#4: reintento Avance no idempotente');

    // ── #3 · ninguna puerta paralela crea un lead por fuera: disponibilidad ─
    const disp = await positive('#3 disponibilidad por documento de una persona con lead (sin perfil)',
      sessions.vend1.client.schema('crm').rpc('verificar_disponibilidad_lead', { p_telefono: TEL_IDENTIDAD(51), p_dni: doc }));
    assertions += 1;
    if (disp?.data?.estado === 'ya_es_cliente' && disp?.data?.via === 'identidad') console.log('  ✓ #3 disponibilidad → ya_es_cliente vía IDENTIDAD (un solo lead total)');
    else fail(`#3: disponibilidad dijo '${disp?.data?.estado}'/'${disp?.data?.via}' (esperaba ya_es_cliente vía identidad)`);
    // El caso DENEGADO (auditor A1): el ALTA de un 2.º lead para ese documento se
    // bloquea en la puerta. Un INSERT con SESIÓN pasa por trg_leads_00_disponibilidad_insert,
    // que consulta la disponibilidad por (teléfono, dni) → 'Contacto no disponible' (P0481).
    await expectBlockedMutation('#3 alta (INSERT con sesión) de un 2.º lead por documento de persona con lead → denegada',
      sessions.vend1.client.schema('crm').from('leads').insert({ ...leadBase, id: randomUUID(), nombre_completo: 'IDENTIDAD ALTA DENEGADA TRANSIENT', telefono: TEL_IDENTIDAD(53), dni: doc }),
      ['P0481', '42501', '23505']);
    // Contrato real de la puerta (Codex): con 'ya_es_cliente' NO lanza — devuelve el estado
    // como éxito lógico y NO crea el lead. Se aserta eso.
    const altaRpc = await positive('#3 alta por RPC (crear_lead_si_disponible) con ese documento → responde ya_es_cliente',
      sessions.vend1.client.schema('crm').rpc('crear_lead_si_disponible', { p_id: randomUUID(), p_nombre_completo: 'IDENTIDAD ALTA RPC DENEGADA TRANSIENT', p_telefono: TEL_IDENTIDAD(54), p_origen: 'otro', p_monto_estimado: 1000, p_moneda: 'PEN', p_vendedor_id: vend1Id, p_dni: doc }));
    assertions += 1;
    if (altaRpc?.data?.estado === 'ya_es_cliente' && cuenta('alta RPC no creó lead', `select count(*) from crm.leads where telefono='${TEL_IDENTIDAD(54)}'`) === 0) console.log('  ✓ #3 alta por RPC → ya_es_cliente y NO creó lead (un solo lead total)');
    else fail(`#3: alta por RPC devolvió '${altaRpc?.data?.estado}' o creó lead`);

    // ── #5 · no_contactar de la PERSONA + oportunidad viva ────────────────
    await positive('#5 vend1 convierte el lead del veto por coop', coop('vend1', IDS_IDENTIDAD.veto, DOCS_IDENTIDAD.veto, 'V'));
    for (const clave of ['coordinador', 'directorio', 'clientBank']) {
      await expectExplicitAuthorizationDenied(`#5 ${clave} no marca no_contactar`,
        sessions[clave].client.schema('crm').rpc('marcar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'x' }));
    }
    await positive('#5 vend1 marca no_contactar (sube a la persona)',
      sessions.vend1.client.schema('crm').rpc('marcar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'gate' }));
    if (cuenta('veto en la identidad', `select count(*) from crm.inversionistas where id in ${idsPorDoc(DOCS_IDENTIDAD.veto)} and no_contactar and no_contactar_en is not null`) !== 1) fail('#5: el veto no llegó a la identidad (o sin no_contactar_en)');
    const dispVeto = await positive('#5 disponibilidad por documento de persona vetada',
      sessions.vend1.client.schema('crm').rpc('verificar_disponibilidad_lead', { p_telefono: TEL_IDENTIDAD(52), p_dni: DOCS_IDENTIDAD.veto }));
    assertions += 1;
    if (dispVeto?.data?.estado === 'no_contactar') console.log('  ✓ #5 disponibilidad → no_contactar aunque cambie el teléfono');
    else fail(`#5: disponibilidad dijo '${dispVeto?.data?.estado}' (esperaba no_contactar)`);
    await expectBlockedMutation('#5 UPDATE directo para BAJAR el veto → rechazado (bandera on)',
      sessions.vend1.client.schema('crm').from('leads').update({ no_contactar: false }).eq('id', IDS_IDENTIDAD.veto), ['42501']);
    await expectExplicitAuthorizationDenied('#5 vendedor no levanta',
      sessions.vend1.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'intento' }));
    await expectExpectedFailure('#5 gerencia sin motivo → 22023',
      sessions.gerencia.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: '' }), ['22023'], /motivo/i);
    await positive('#5 gerencia CON motivo levanta',
      sessions.gerencia.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'cliente pidió reactivar' }));
    if (cuenta('veto levantado', `select count(*) from crm.inversionistas where id in ${idsPorDoc(DOCS_IDENTIDAD.veto)} and not no_contactar`) !== 1) fail('#5: gerencia no pudo levantar el veto');
    // herencia al INSERT: se vuelve a vetar y un lead NUEVO del mismo documento nace vetado
    await positive('#5 re-marcar para probar herencia',
      sessions.vend1.client.schema('crm').rpc('marcar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'herencia' }));
    // F2.b b1 (20260904120000): el lead nuevo de una persona vetada ya NO nace vetado: se RECHAZA (P0429, contrato §7.3).
    await expectExpectedFailure('#5 alta de un lead nuevo de la persona vetada (como el importador) → P0429 (b1)',
      admin.schema('crm').from('leads').insert({ ...leadBase, id: IDS_IDENTIDAD.heredaVeto, nombre_completo: 'IDENTIDAD HEREDA VETO TRANSIENT', telefono: TEL_IDENTIDAD(47), dni: DOCS_IDENTIDAD.veto }),
      ['P0429'], /No insistir/i);
    check(cuenta('lead nuevo rechazado', `select count(*) from crm.leads where id='${IDS_IDENTIDAD.heredaVeto}'`) === 0, '#5 el lead nuevo de la persona vetada no se insertó (b1 cierra el bypass de importación)');
    await positive('#5 limpieza: gerencia levanta', sessions.gerencia.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'limpieza gate' }));

    // ── Paridad con bandera APAGADA (aterrizaje aditivo) ─────────────────
    flag(false);
    await positive('OFF: conversión coop funciona como hoy', coop('vend1', IDS_IDENTIDAD.paridadOff, DOCS_IDENTIDAD.paridadOff, 'OFF'));
    if (cuenta('OFF sin identidad', `select count(*) from crm.inversionista_identificadores where documento_normalizado='${DOCS_IDENTIDAD.paridadOff}'`) !== 0) fail('OFF: creó identidad con la bandera apagada');
    if (cuenta('OFF lead sin puntero', `select count(*) from crm.leads where id='${IDS_IDENTIDAD.paridadOff}' and inversionista_id is null`) !== 1) fail('OFF: tocó inversionista_id con la bandera apagada');
    await positive('OFF: UPDATE directo de no_contactar por el dueño sigue permitido (no regresión)',
      sessions.vend1.client.schema('crm').from('leads').update({ no_contactar: true }).eq('id', IDS_IDENTIDAD.avanceDos));
  } finally {
    flag(false);
    ejecutarFueraDeBanda('limpieza identidad', `
      delete from crm.inversion_titulares where inversion_id in (select id from crm.inversiones where cierre_externo_id in (select id from crm.cierres_externos where lead_id in ('${Object.values(IDS_IDENTIDAD).join("','")}')));
      delete from crm.inversiones where cierre_externo_id in (select id from crm.cierres_externos where lead_id in ('${Object.values(IDS_IDENTIDAD).join("','")}'));
      delete from crm.depositos_reclamados where numero_norm like 'TRX-ID-${sufijo}-%';
      delete from crm.cierres_externos where lead_id in ('${Object.values(IDS_IDENTIDAD).join("','")}');
      delete from crm.inversionista_leads where lead_id in ('${Object.values(IDS_IDENTIDAD).join("','")}');
      delete from crm.multiempresa_idempotencia where clave like 'conversion%:%' and split_part(clave, ':', 2) in ('${Object.values(IDS_IDENTIDAD).join("','")}');
      delete from crm.actividades where lead_id in ('${Object.values(IDS_IDENTIDAD).join("','")}');
      delete from crm.lead_asignaciones where lead_id in ('${Object.values(IDS_IDENTIDAD).join("','")}');
      delete from crm.leads where id in ('${Object.values(IDS_IDENTIDAD).join("','")}');
      delete from crm.inversionista_responsables where inversionista_id in (select inversionista_id from crm.inversionista_identificadores where documento_normalizado in ('${Object.values(DOCS_IDENTIDAD).join("','")}')) or inversionista_id in (select id from crm.inversionistas where perfil_id='${bankProfileId}');
      delete from crm.inversionista_identificadores where documento_normalizado in ('${Object.values(DOCS_IDENTIDAD).join("','")}') or inversionista_id in (select id from crm.inversionistas where perfil_id='${bankProfileId}');
      delete from crm.inversionista_responsables where inversionista_id in (select id from crm.inversionistas where perfil_id='${IDS_IDENTIDAD.clienteNuevo}');
      delete from crm.inversionista_identificadores where inversionista_id in (select id from crm.inversionistas where perfil_id='${IDS_IDENTIDAD.clienteNuevo}');
      delete from crm.inversionistas where perfil_id='${IDS_IDENTIDAD.clienteNuevo}';
      delete from public.perfiles where id='${IDS_IDENTIDAD.clienteNuevo}';
      delete from auth.users where id='${IDS_IDENTIDAD.clienteNuevo}';
      delete from crm.inversionistas where perfil_id='${bankProfileId}' or (id not in (select inversionista_id from crm.inversionista_identificadores) and not exists (select 1 from crm.leads l where l.inversionista_id=crm.inversionistas.id) and not exists (select 1 from crm.inversiones v where v.inversionista_id=crm.inversionistas.id));
    `, { tolerante: true });
  }
}

// ── Identidad multiempresa F2.b (sub-lotes b1 + b2) ──────────────────────────
// Hermano de testIdentidadMultiempresa: mismos helpers, misma vía fuera de banda,
// misma bandera. Corre justo después.
//   b1 (20260904120000): con la bandera ENCENDIDA todo INSERT en crm.leads y todo
//   cambio de dni pasan por el documento EXACTO (identificador vigente+verificado):
//   persona vetada → P0429 (DETAIL sin documento) · persona con lead → P0481
//   ya_es_cliente vía identidad · persona sin lead → el lead nace ENLAZADO (+ puente
//   canónico) · dni de un lead enlazado → P0409 (solo Gerencia corrige) · un
//   inversionista_id forjado nunca sobrevive · el reingreso del importador queda como
//   actividad 'nota' SIN documento en claro.
//   b2 (20260904130000): reparto, derivación, reversión, toma, reapertura y
//   seguimiento respetan el veto de la PERSONA — también sobre leads SUELTOS que solo
//   comparten el documento — y marcar_no_contactar cancela las tareas pendientes.
//   Con la bandera APAGADA todo devuelve lo de hoy (paridad).
// Las funciones privadas se acreditan por CATÁLOGO (has_function_privilege +
// aclexplode): jamás se llama por SQL a una función sin EXECUTE (memoria 20/08).
const IDS_F2B = Object.freeze({
  // b1
  conLead: randomUUID(),        // convertido por coop → persona CON lead
  nace: randomUUID(),           // suelto → UPDATE dni hacia persona reconocida → P0409, sin enlace (#2, v3)
  naceInsert: randomUUID(),     // INSERT sin sesión con dni de persona sin lead → nace ENLAZADO + puente (#2b); cambiar su dni → P0409 (#1)
  ocupado: randomUUID(),        // suelto → UPDATE dni con doc de persona con lead → P0481 (#3)
  forjadoSinDni: randomUUID(),  // INSERT con sesión + inversionista_id forjado, sin dni (#4a)
  forjadoConDni: randomUUID(),  // INSERT con sesión + inversionista_id forjado + dni con identidad (#4b)
  vetoUpdate: randomUUID(),     // suelto → UPDATE dni con doc de persona vetada → P0429 (#7) / pasa OFF (#8)
  vetoInsert: randomUUID(),     // INSERT service_role con doc vetado → P0429 (#7) / pasa OFF (#8)
  offEnlace: randomUUID(),      // OFF: UPDATE dni con doc de identidad sin lead → sin enlace (#8)
  offOcupado: randomUUID(),     // OFF: UPDATE dni con doc de persona con lead → pasa (#8)
  // b2
  l1: randomUUID(), l2: randomUUID(), l3: randomUUID(), l4: randomUUID(),  // enlazados por coop → se vetan
  lu1: randomUUID(),            // suelto en BOLSA (doc a): repartir / cola / tomar
  lu2: randomUUID(),            // suelto en bandeja de sup1 (doc b): derivar
  lu3: randomUUID(),            // suelto derivado a vend1 ANTES del veto (doc c): revertir / seguimiento
  lu4: randomUUID(),            // suelto en BOLSA (doc d): descartar → deshacer
  lu5: randomUUID(),            // enlazado al nacer (doc e): tarea pendiente → marcar la cancela
});
const TAREA_F2B = randomUUID();
// Documentos POR CORRIDA con prefijo 8 (los del bloque hermano llevan 7): sin choques.
const DOCS_F2B = Object.freeze({
  conLead: `8${RUN_IDENTIDAD}001`, sinLead: `8${RUN_IDENTIDAD}002`, sinLead2: `8${RUN_IDENTIDAD}003`,
  sinLeadOff: `8${RUN_IDENTIDAD}004`, vetada: `8${RUN_IDENTIDAD}005`,
  a: `8${RUN_IDENTIDAD}011`, b: `8${RUN_IDENTIDAD}012`, c: `8${RUN_IDENTIDAD}013`, d: `8${RUN_IDENTIDAD}014`, e: `8${RUN_IDENTIDAD}015`,
  libre: `8${RUN_IDENTIDAD}090`,   // sin identidad (captación): nunca resuelve
});
// 9 dígitos; n ≥ 100 para no pisar TEL_IDENTIDAD (que usa 00NN).
const TEL_F2B = (n) => `9${RUN_IDENTIDAD}${String(n).padStart(4, '0')}`;
const FIRMAS_F2B_B1 = Object.freeze([
  'private.inversionista_por_documento(text,text)',
  'private.identidad_bloquear_documento(text,text)',
  'private.identidad_bloquear_persona(text,text)',
]);
const FIRMAS_F2B_B2 = Object.freeze([
  'private.persona_vetada(uuid)',
  'private.leads_vetados_persona(uuid[])',
]);

async function testIdentidadF2b(sessions, seed) {
  console.log('\n— Identidad multiempresa F2.b: el alta reconoce a la persona (b1) y el veto de la persona bloquea mutaciones (b2) —');
  const ids = seed.profileIdByKey;
  const vend1Id = ids.vend1;
  const sup1Id = ids.sup1;
  const sufijo = randomUUID().slice(0, 8);
  const trx = (n) => `TRX-F2B-${sufijo}-${n}`;
  const flag = (on) => ejecutarFueraDeBanda('bandera resolver_en_puertas (F2.b)',
    `update crm.multiempresa_flags set activo=${on ? 'true' : 'false'}, actualizado_en=now() where nombre='resolver_en_puertas';`);
  const coop = (clave, leadId, doc, n) => sessions[clave].client.schema('crm')
    .rpc('convertir_lead_externo', {
      p_lead_id: leadId, p_cooperativa: 'qorilazo', p_monto: 1000, p_moneda: 'PEN',
      p_documento_tipo: 'DNI', p_documento: doc, p_nombre: 'F2B TRANSIENT',
      p_numero_transaccion: trx(n),
    });
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`F2.b: ${etiqueta}`, sql);
  const invDe = (doc) => `private.inversionista_por_documento('DNI','${doc}')`;
  const lista = (arr) => `'${arr.join("','")}'`;
  const leadBase = { activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'otro', monto_estimado: 5000, creado_por: vend1Id, vendedor_id: vend1Id };
  const bolsa = { ...leadBase, creado_por: null, vendedor_id: null };
  const updDni = (clave, leadId, dni) => sessions[clave].client.schema('crm').from('leads').update({ dni }).eq('id', leadId).select('id');
  const actividad = (leadId, detalle) => sessions.vend1.client.schema('crm').from('actividades')
    .insert({ lead_id: leadId, tipo: 'llamada_realizada', detalle, creado_por: vend1Id }).select('id');
  const tarea = (leadId, titulo, id) => sessions.vend1.client.schema('crm').from('tareas')
    .insert({ ...(id ? { id } : {}), lead_id: leadId, tipo: 'llamada', titulo, vence_en: new Date(Date.now() + 86_400_000).toISOString(), creado_por: vend1Id }).select('id');
  const sinDocumento = (error) => ![error?.message, error?.details, error?.hint]
    .some((campo) => String(campo ?? '').includes(DOCS_F2B.vetada));
  // EXECUTE residual sobre un juego de firmas para un juego de roles (+ PUBLIC, que
  // has_function_privilege enmascara: se mira aclexplode con grantee = 0).
  const ejecutablesResiduales = (firmas, roles) => cuenta('EXECUTE residual',
    `select count(*) from unnest(array[${lista(firmas)}]) f(firma), unnest(array[${lista(roles)}]) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE')`)
    + cuenta('PUBLIC residual',
      `select count(*) from pg_proc p, aclexplode(p.proacl) a where p.oid in (${firmas.map((f) => `'${f}'::regprocedure`).join(',')}) and a.grantee = 0`);
  const leadIds = Object.values(IDS_F2B);
  const sueltosB2 = [IDS_F2B.lu1, IDS_F2B.lu2, IDS_F2B.lu3, IDS_F2B.lu4];
  // F2.b [D-3] (bloque 2): con D-3 instalada los sueltos heredan la bandera propia del veto.
  const conD3 = contarFueraDeBanda('F2.b b2: D-3 instalada', `select (to_regprocedure('private.persona_vetada_perfil(uuid)') is not null)::int`) === 1;

  // Precondición: b1 y b2 aplicados en el banco. Sin ellos no hay nada que medir.
  if (cuenta('b1+b2 aplicados', `select (to_regprocedure('private.trg_leads_zz_enlaza_identidad()') is not null)::int + (to_regprocedure('private.persona_vetada(uuid)') is not null)::int`) !== 2) {
    fail('F2.b: faltan las migraciones 20260904120000 (b1) y/o 20260904130000 (b2) en el banco');
    return;
  }

  try {
    // ── 0 · fixtures ─────────────────────────────────────────────────────
    // Leads b1 SIN dni (el documento entra por el UPDATE/INSERT que se mide) y los
    // leads b2 SUELTOS con documento, nacidos con la bandera APAGADA (hoy no enlaza).
    flag(false);
    await requireAdmin('F2.b: sembrar los leads (bandera apagada)',
      admin.schema('crm').from('leads').insert([
        { ...leadBase, id: IDS_F2B.conLead,    nombre_completo: 'F2B CON LEAD TRANSIENT',    telefono: TEL_F2B(101) },
        { ...leadBase, id: IDS_F2B.nace,       nombre_completo: 'F2B NACE TRANSIENT',        telefono: TEL_F2B(102) },
        { ...leadBase, id: IDS_F2B.ocupado,    nombre_completo: 'F2B OCUPADO TRANSIENT',     telefono: TEL_F2B(103) },
        { ...leadBase, id: IDS_F2B.vetoUpdate, nombre_completo: 'F2B VETO UPDATE TRANSIENT', telefono: TEL_F2B(104) },
        { ...leadBase, id: IDS_F2B.offEnlace,  nombre_completo: 'F2B OFF ENLACE TRANSIENT',  telefono: TEL_F2B(105) },
        { ...leadBase, id: IDS_F2B.offOcupado, nombre_completo: 'F2B OFF OCUPADO TRANSIENT', telefono: TEL_F2B(106) },
        { ...leadBase, id: IDS_F2B.l1, nombre_completo: 'F2B L1 TRANSIENT', telefono: TEL_F2B(111) },
        { ...leadBase, id: IDS_F2B.l2, nombre_completo: 'F2B L2 TRANSIENT', telefono: TEL_F2B(112) },
        { ...leadBase, id: IDS_F2B.l3, nombre_completo: 'F2B L3 TRANSIENT', telefono: TEL_F2B(113) },
        { ...leadBase, id: IDS_F2B.l4, nombre_completo: 'F2B L4 TRANSIENT', telefono: TEL_F2B(114) },
      ]));

    flag(true);
    // Identidades SIN lead (por el resolver, como el arnés) y una persona vetada SIN
    // lead: el veto vive en la IDENTIDAD, no en un lead — así b1 mide el veto de la
    // persona y no el veto del lead (que hoy ya frena por teléfono/dni).
    ejecutarFueraDeBanda('F2.b: identidades sin lead', `
      select private.inversionista_resolver('DNI','${DOCS_F2B.sinLead}',true,'gate_f2b');
      select private.inversionista_resolver('DNI','${DOCS_F2B.sinLead2}',true,'gate_f2b');
      select private.inversionista_resolver('DNI','${DOCS_F2B.sinLeadOff}',true,'gate_f2b');
      select private.inversionista_resolver('DNI','${DOCS_F2B.vetada}',true,'gate_f2b');
      select private.inversionista_resolver('DNI','${DOCS_F2B.e}',true,'gate_f2b');
      select set_config('crm.op_privilegiada','on',true);
      update crm.inversionistas set no_contactar=true, no_contactar_en=now(), no_contactar_por='${vend1Id}' where id=${invDe(DOCS_F2B.vetada)};`);
    check(cuenta('identidades sembradas', `select count(*) from crm.inversionista_identificadores i where i.documento_normalizado in (${lista([DOCS_F2B.sinLead, DOCS_F2B.sinLead2, DOCS_F2B.sinLeadOff, DOCS_F2B.vetada, DOCS_F2B.e])}) and i.estado='vigente' and i.verificado`) === 5,
      'F2.b #0 cinco identidades vigentes+verificadas sin lead');
    check(cuenta('persona vetada sin lead', `select count(*) from crm.inversionistas where id=${invDe(DOCS_F2B.vetada)} and no_contactar`) === 1, 'F2.b #0 la persona vetada (sin lead) quedó vetada en la identidad');
    // Persona CON lead: conLead convertido por coop (queda enlazado).
    await positive('F2.b #0 vend1 convierte por coop → persona CON lead', coop('vend1', IDS_F2B.conLead, DOCS_F2B.conLead, 'C'));
    check(cuenta('conLead enlazado', `select count(*) from crm.leads where id='${IDS_F2B.conLead}' and inversionista_id=${invDe(DOCS_F2B.conLead)}`) === 1, 'F2.b #0 la conversión enlazó el lead a su persona');

    // ══ b1 ═══════════════════════════════════════════════════════════════
    // ── #2 (v3) · UPDATE dni de un lead SUELTO hacia una persona reconocida → P0409, NUNCA enlaza ─
    // (en UPDATE la fila ya está bloqueada: enlazar ahí sería lead→identidad; el enlace de un suelto es corrección/fusión de Gerencia, b5)
    await expectExpectedFailure('b1 #2 vend1 no puede poner en su lead suelto el dni de una persona reconocida → P0409',
      updDni('vend1', IDS_F2B.nace, DOCS_F2B.sinLead), ['P0409'], /Gerencia/i);
    check(cuenta('nace sin enlace', `select count(*) from crm.leads where id='${IDS_F2B.nace}' and dni is null and inversionista_id is null`) === 1,
      'b1 #2 el lead suelto sigue sin dni y sin enlace');
    // ── #2b · el enlace al NACER (alta sin sesión, como el importador) → enlazado + puente ─
    await requireAdmin('b1 #2b alta sin sesión con el dni de una persona sin lead',
      admin.schema('crm').from('leads').insert({ ...leadBase, id: IDS_F2B.naceInsert, nombre_completo: 'F2B NACE INSERT TRANSIENT', telefono: TEL_F2B(110), dni: DOCS_F2B.sinLead }));
    check(cuenta('nace enlazado', `select count(*) from crm.leads where id='${IDS_F2B.naceInsert}' and inversionista_id=${invDe(DOCS_F2B.sinLead)}`) === 1,
      'b1 #2b el lead NACIÓ enlazado (inversionista_id = identidad del documento)');
    check(cuenta('puente canónico', `select count(*) from crm.inversionista_leads where lead_id='${IDS_F2B.naceInsert}' and inversionista_id=${invDe(DOCS_F2B.sinLead)} and rol='canonico'`) === 1,
      'b1 #2b apareció el puente canónico en crm.inversionista_leads');

    // ── #1 · UPDATE dni de un lead ENLAZADO → P0409 (solo Gerencia corrige el documento) ─
    await expectExpectedFailure('b1 #1 vend1 no cambia el dni de un lead enlazado → P0409',
      updDni('vend1', IDS_F2B.naceInsert, DOCS_F2B.libre), ['P0409'], /Gerencia/i);
    check(cuenta('enlazado intacto', `select count(*) from crm.leads where id='${IDS_F2B.naceInsert}' and dni='${DOCS_F2B.sinLead}' and inversionista_id=${invDe(DOCS_F2B.sinLead)}`) === 1,
      'b1 #1 el lead enlazado conserva dni y enlace');

    // ── #3 · UPDATE dni con el documento de una persona CON lead → P0481 ya_es_cliente, nada cambia ─
    {
      const { error } = await updDni('vend1', IDS_F2B.ocupado, DOCS_F2B.conLead);
      check(error?.code === 'P0481' && /Contacto no disponible/i.test(error?.message ?? '') && /ya_es_cliente/.test(String(error?.details ?? '')),
        'b1 #3 vendedor: dni de una persona que ya tiene lead → P0481 con veredicto ya_es_cliente', errorText(error));
    }
    await expectBlockedMutation('b1 #3 coordinador: dni de una persona que ya tiene lead → denegado',
      updDni('coordinador', IDS_F2B.ocupado, DOCS_F2B.conLead), ['P0481']);
    check(cuenta('ocupado intacto', `select count(*) from crm.leads where id='${IDS_F2B.ocupado}' and dni is null and inversionista_id is null`) === 1,
      'b1 #3 nada cambió en el lead (sin dni, sin enlace)');
    check(cuenta('un solo lead', `select count(*) from crm.leads where inversionista_id=${invDe(DOCS_F2B.conLead)}`) === 1,
      'b1 #3 la persona sigue con UN solo lead');

    // ── #4 · INSERT con sesión e inversionista_id FORJADO: NULL o recalculado por dni, nunca el forjado ─
    // El forjado es un uuid al azar: si sobreviviera a los BEFORE (protege + zz) lo
    // cazaría la FK (23503) — y eso sería un FALLO, no un candado.
    const insertForjado = (id, tel, dni) => sessions.vend1.client.schema('crm').from('leads')
      .insert({ ...leadBase, id, nombre_completo: 'F2B FORJADO TRANSIENT', telefono: tel, dni, inversionista_id: randomUUID() }).select('id');
    {
      const { error } = await insertForjado(IDS_F2B.forjadoSinDni, TEL_F2B(107), null);
      if (error) {
        check(isAuthorizationError(error), 'b1 #4a el INSERT directo con inversionista_id forjado (sin dni) se rechaza por permisos (RLS/grant por columna)', errorText(error));
      } else {
        check(cuenta('forjado sin dni', `select count(*) from crm.leads where id='${IDS_F2B.forjadoSinDni}' and inversionista_id is null`) === 1,
          'b1 #4a el forjado se ignoró: nace con inversionista_id NULL (sin dni)');
      }
    }
    {
      const { error } = await insertForjado(IDS_F2B.forjadoConDni, TEL_F2B(108), DOCS_F2B.sinLead2);
      if (error) {
        check(isAuthorizationError(error), 'b1 #4b el INSERT directo con inversionista_id forjado (con dni) se rechaza por permisos (RLS/grant por columna)', errorText(error));
      } else {
        check(cuenta('forjado con dni', `select count(*) from crm.leads where id='${IDS_F2B.forjadoConDni}' and inversionista_id=${invDe(DOCS_F2B.sinLead2)}`) === 1,
          'b1 #4b el forjado se ignoró: nace enlazado a la persona de SU dni (recalculado)');
      }
    }

    // ── #5 · anon / authenticated no alcanzan la RPC de reingreso; los helpers privados no tienen EXECUTE ─
    const anonF2b = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-f2b'));
    const reingreso = (client) => client.schema('crm').rpc('registrar_reingreso_lead_fn', { p_lead_id: IDS_F2B.conLead, p_origen: 'hoja', p_datos: {} });
    await expectExplicitAuthorizationDenied('b1 #5 anon no ejecuta registrar_reingreso_lead_fn', reingreso(anonF2b), ['42501', 'PGRST202']);
    // El MENSAJE debe ser el del ACL: el cuerpo también lanza 42501 cuando hay sesión,
    // y ese 42501 significaría que la puerta SÍ abrió (patrón F7.1).
    for (const clave of ['vend1', 'sup1', 'gerencia', 'coordinador']) {
      const { error } = await reingreso(sessions[clave].client);
      check(error?.code === '42501' && /permission denied/i.test(error?.message ?? ''),
        `b1 #5 ${clave} (authenticated) no ejecuta registrar_reingreso_lead_fn por ACL`, errorText(error));
    }
    check(ejecutablesResiduales([...FIRMAS_F2B_B1, 'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)'], ['anon', 'authenticated']) === 0,
      'b1 #5 anon/authenticated (ni PUBLIC) sin EXECUTE sobre inversionista_por_documento / identidad_bloquear_documento / identidad_bloquear_persona / registrar_reingreso_lead_fn');
    check(ejecutablesResiduales(FIRMAS_F2B_B1, ['service_role']) === 0, 'b1 #5 service_role sin EXECUTE sobre los helpers privados de b1');

    // ── #6 · service_role: bandera_activa y el reingreso (actividad nota sin documento en claro) ─
    const band = await positive('b1 #6 service_role lee crm.bandera_activa', admin.schema('crm').rpc('bandera_activa', { p_nombre: 'resolver_en_puertas' }));
    check(band?.data === true, 'b1 #6 bandera_activa(resolver_en_puertas) = true con la bandera encendida', JSON.stringify(band?.data));
    const rein = await positive('b1 #6 service_role registra el reingreso del cliente que vuelve por la hoja',
      admin.schema('crm').rpc('registrar_reingreso_lead_fn', { p_lead_id: IDS_F2B.conLead, p_origen: 'hoja', p_datos: { nombre: 'F2B', telefono: TEL_F2B(101), dni: DOCS_F2B.conLead, capital: 5000 } }));
    check(rein?.data?.ok === true, 'b1 #6 el reingreso devolvió ok', JSON.stringify(rein?.data));
    check(cuenta('actividad de reingreso', `select count(*) from crm.actividades where lead_id='${IDS_F2B.conLead}' and tipo='nota' and metadata->>'evento'='reingreso' and not (metadata->'datos' ? 'dni') and (metadata->'datos' ? 'telefono')`) === 1,
      'b1 #6 actividad nota evento=reingreso con teléfono y SIN clave dni en metadata.datos');

    // ── #7 · persona VETADA: el alta directa (service_role) y el UPDATE de dni → P0429, DETAIL sin documento ─
    {
      const { error } = await admin.schema('crm').from('leads')
        .insert({ ...leadBase, id: IDS_F2B.vetoInsert, nombre_completo: 'F2B VETO INSERT TRANSIENT', telefono: TEL_F2B(109), dni: DOCS_F2B.vetada }).select('id');
      check(error?.code === 'P0429' && /No insistir/i.test(error?.message ?? '') && sinDocumento(error),
        'b1 #7 INSERT service_role (importador) con documento de persona vetada → P0429, sin documento en el DETAIL', errorText(error));
    }
    {
      const { error } = await updDni('vend1', IDS_F2B.vetoUpdate, DOCS_F2B.vetada);
      // Camino HUMANO: el trigger 00 (disponibilidad) responde antes que zz con el veredicto
      // no_contactar (P0481); el P0429 del 000 es para el INSERT (importador). Ambos sin documento.
      check(((error?.code === 'P0481' && /no_contactar/.test(String(error?.details ?? ''))) || (error?.code === 'P0429' && /No insistir/i.test(error?.message ?? ''))) && sinDocumento(error),
        'b1 #7 UPDATE dni de vendedor con documento de persona vetada → P0481 no_contactar (00) o P0429, sin documento', errorText(error));
    }
    check(cuenta('veto insert no nació', `select count(*) from crm.leads where id='${IDS_F2B.vetoInsert}'`) === 0
      && cuenta('veto update intacto', `select count(*) from crm.leads where id='${IDS_F2B.vetoUpdate}' and dni is null and inversionista_id is null`) === 1,
    'b1 #7 no nació el lead de la persona vetada y el suelto no cambió');

    // ── #8 · paridad con la bandera APAGADA: 1, 2, 3 y 7 devuelven lo de hoy ─
    flag(false);
    await positive('b1 #8 OFF: cambiar el dni de un lead enlazado pasa como hoy (sin P0409)', updDni('vend1', IDS_F2B.naceInsert, DOCS_F2B.libre));
    check(cuenta('OFF dni cambiado', `select count(*) from crm.leads where id='${IDS_F2B.naceInsert}' and dni='${DOCS_F2B.libre}'`) === 1, 'b1 #8 OFF (#1): el dni cambió sin puerta de identidad');
    await positive('b1 #8 OFF: dni de una persona sin lead pasa sin enlazar', updDni('vend1', IDS_F2B.offEnlace, DOCS_F2B.sinLeadOff));
    check(cuenta('OFF sin enlace', `select count(*) from crm.leads where id='${IDS_F2B.offEnlace}' and dni='${DOCS_F2B.sinLeadOff}' and inversionista_id is null`) === 1
      && cuenta('OFF sin puente', `select count(*) from crm.inversionista_leads where lead_id='${IDS_F2B.offEnlace}'`) === 0,
    'b1 #8 OFF (#2): sin enlace y sin puente');
    await positive('b1 #8 OFF: dni de una persona con lead pasa como hoy (sin P0481 por identidad)', updDni('vend1', IDS_F2B.offOcupado, DOCS_F2B.conLead));
    check(cuenta('OFF ocupado sin enlace', `select count(*) from crm.leads where id='${IDS_F2B.offOcupado}' and dni='${DOCS_F2B.conLead}' and inversionista_id is null`) === 1, 'b1 #8 OFF (#3): el dni entró y no hubo enlace');
    // (#7) primero el UPDATE y luego el INSERT: el índice único de dni entre vivos no
    // admite los dos a la vez, así que el suelto suelta el documento antes del alta.
    await positive('b1 #8 OFF: dni de una persona vetada en un UPDATE pasa como hoy (sin P0429)', updDni('vend1', IDS_F2B.vetoUpdate, DOCS_F2B.vetada));
    check(cuenta('OFF veto update', `select count(*) from crm.leads where id='${IDS_F2B.vetoUpdate}' and dni='${DOCS_F2B.vetada}' and inversionista_id is null and no_contactar=false`) === 1, 'b1 #8 OFF (#7): el UPDATE pasó sin enlace ni veto heredado');
    await positive('b1 #8 OFF: el suelto devuelve el documento', updDni('vend1', IDS_F2B.vetoUpdate, null));
    await positive('b1 #8 OFF: INSERT service_role con documento de persona vetada pasa como hoy (sin P0429)',
      admin.schema('crm').from('leads').insert({ ...leadBase, id: IDS_F2B.vetoInsert, nombre_completo: 'F2B VETO INSERT TRANSIENT', telefono: TEL_F2B(109), dni: DOCS_F2B.vetada }).select('id'));
    check(cuenta('OFF veto insert', `select count(*) from crm.leads where id='${IDS_F2B.vetoInsert}' and inversionista_id is null and no_contactar=false`) === 1
      && cuenta('OFF veto insert sin puente', `select count(*) from crm.inversionista_leads where lead_id='${IDS_F2B.vetoInsert}'`) === 0,
    'b1 #8 OFF (#7): el alta nació sin enlace y sin veto heredado');

    // ══ b2 ═══════════════════════════════════════════════════════════════
    flag(true);
    // Personas a–d: su lead enlazado (coop) se veta con marcar_no_contactar → el veto sube
    // a la IDENTIDAD; los sueltos lu1..lu4 solo comparten el documento (sin veto propio).
    for (const [lead, doc, n] of [[IDS_F2B.l1, DOCS_F2B.a, '1'], [IDS_F2B.l2, DOCS_F2B.b, '2'], [IDS_F2B.l3, DOCS_F2B.c, '3'], [IDS_F2B.l4, DOCS_F2B.d, '4']]) {
      await positive(`b2 #0 vend1 convierte por coop (persona ${n})`, coop('vend1', lead, doc, n));
    }
    // Los sueltos lu1..lu4 (mismo documento que las personas a–d) nacen DESPUÉS de las conversiones y con la bandera
    // APAGADA (sin enlace): desde [D-13] un lead vivo suelto con el documento de la persona cuenta en «un solo lead» y la
    // conversión coop de otro lead de esa persona se rechaza («ya tiene un lead»); el veto por documento se mide igual.
    flag(false);
    await requireAdmin('F2.b: sembrar los sueltos b2 (bandera apagada, tras las conversiones)',
      admin.schema('crm').from('leads').insert([
        { ...bolsa, id: IDS_F2B.lu1, nombre_completo: 'F2B LU1 BOLSA TRANSIENT',    telefono: TEL_F2B(121), dni: DOCS_F2B.a },
        { ...bolsa, id: IDS_F2B.lu2, nombre_completo: 'F2B LU2 BANDEJA TRANSIENT',  telefono: TEL_F2B(122), dni: DOCS_F2B.b, asignado_supervisor_id: sup1Id },
        { ...bolsa, id: IDS_F2B.lu3, nombre_completo: 'F2B LU3 DERIVADO TRANSIENT', telefono: TEL_F2B(123), dni: DOCS_F2B.c, asignado_supervisor_id: sup1Id },
        { ...bolsa, id: IDS_F2B.lu4, nombre_completo: 'F2B LU4 BOLSA TRANSIENT',    telefono: TEL_F2B(124), dni: DOCS_F2B.d },
      ]));
    check(cuenta('sueltos sin enlace', `select count(*) from crm.leads where id in (${lista(sueltosB2)}) and inversionista_id is null and no_contactar=false`) === 4,
      'F2.b #0 los 4 leads sueltos nacen sin enlace ni veto con la bandera apagada');
    flag(true);
    // Antes del veto: sup1 deriva lu3 a vend1 (persona aún sin veto → pasa) y lu5 nace
    // enlazado por b1 con una tarea pendiente de vend1.
    await positive('b2 #0 sup1 deriva lu3 a vend1 antes del veto (pasa)',
      sessions.sup1.client.schema('crm').rpc('derivar_leads_equipo_fn', { p_lead_ids: [IDS_F2B.lu3], p_asesor_ids: [vend1Id] }));
    check(cuenta('lu3 derivado', `select count(*) from crm.leads where id='${IDS_F2B.lu3}' and vendedor_id='${vend1Id}'`) === 1, 'b2 #0 lu3 quedó con vend1');
    await requireAdmin('b2 #0 lu5 nace enlazado a la persona e (b1)',
      admin.schema('crm').from('leads').insert({ ...leadBase, id: IDS_F2B.lu5, nombre_completo: 'F2B LU5 ENLAZADO TRANSIENT', telefono: TEL_F2B(125), dni: DOCS_F2B.e }));
    check(cuenta('lu5 enlazado', `select count(*) from crm.leads where id='${IDS_F2B.lu5}' and inversionista_id=${invDe(DOCS_F2B.e)}`) === 1, 'b2 #0 lu5 nació enlazado');
    await positive('b2 #0 vend1 agenda una tarea pendiente en lu5', tarea(IDS_F2B.lu5, 'F2B TAREA TRANSIENT', TAREA_F2B));
    check(cuenta('tarea pendiente', `select count(*) from crm.tareas where id='${TAREA_F2B}' and estado='pendiente'`) === 1, 'b2 #0 la tarea de lu5 está pendiente');
    // El veto de las 5 personas, por su lead enlazado.
    for (const [lead, n] of [[IDS_F2B.l1, '1'], [IDS_F2B.l2, '2'], [IDS_F2B.l3, '3'], [IDS_F2B.l4, '4'], [IDS_F2B.lu5, '5']]) {
      await positive(`b2 #0 vend1 marca no_contactar (persona ${n})`, sessions.vend1.client.schema('crm').rpc('marcar_no_contactar', { p_lead_id: lead, p_motivo: 'gate f2b' }));
    }
    check(cuenta('personas vetadas', `select count(*) from crm.inversionistas i where i.no_contactar and i.id in (${[DOCS_F2B.a, DOCS_F2B.b, DOCS_F2B.c, DOCS_F2B.d, DOCS_F2B.e].map(invDe).join(',')})`) === 5, 'b2 #0 las 5 personas quedaron vetadas');
    // F2.b [D-3] (bloque 2, 20260906110000): los sueltos con el documento de la persona HEREDAN el veto (bandera propia); antes solo la persona los vetaba.
    check(cuenta('sueltos siguen sueltos', `select count(*) from crm.leads where id in (${lista(sueltosB2)}) and no_contactar=${conD3 ? 'true' : 'false'} and inversionista_id is null`) === 4,
      conD3 ? 'b2 #0 [D-3] los 4 sueltos heredan el veto de la persona y siguen SIN enlace' : 'b2 #0 los 4 sueltos siguen SIN veto propio y SIN enlace (solo la persona los veta)');
    check(cuenta('persona_vetada', `select private.persona_vetada('${IDS_F2B.lu1}')::int + private.persona_vetada('${IDS_F2B.lu5}')::int`) === 2,
      'b2 #0 persona_vetada(): por documento (suelto) y por enlace');

    // ── #9 · mutaciones sobre sueltos de personas vetadas → P0429 / veredicto ─
    await expectExpectedFailure('b2 #9 gerencia no reparte un suelto de persona vetada → P0429',
      sessions.gerencia.client.schema('crm').rpc('repartir_lead', { p_lead: IDS_F2B.lu1, p_supervisor: sup1Id }), ['P0429'], /No insist/i);  // «No insistir» (persona) o, con D-3, «No Insista» (bandera propia heredada)
    const cola = await positive('b2 #9 coordinador lee la cola de reparto', sessions.coordinador.client.schema('crm').rpc('leads_por_repartir'));
    check(Array.isArray(cola?.data) && !cola.data.some((f) => f.id === IDS_F2B.lu1 || f.id === IDS_F2B.lu4),
      'b2 #9 la cola (leads_por_repartir_implementacion) no lista los sueltos de personas vetadas');
    const resumen = await positive('b2 #9 coordinador lee el resumen de reparto', sessions.coordinador.client.schema('crm').rpc('resumen_reparto_fn'));
    check(Number(resumen?.data?.cola?.total) === (cola?.data?.length ?? -1),
      'b2 #9 resumen_reparto_fn cuenta lo mismo que la cola', `${resumen?.data?.cola?.total} vs ${cola?.data?.length}`);
    const toma = await positive('b2 #9 vend1 intenta tomar el suelto de la bolsa por teléfono',
      sessions.vend1.client.schema('crm').rpc('tomar_lead_libre', { p_telefono: TEL_F2B(121), p_dni: null }));
    check(toma?.data?.estado === 'no_contactar'
      && cuenta('lu1 sigue en bolsa', `select count(*) from crm.leads where id='${IDS_F2B.lu1}' and vendedor_id is null and asignado_supervisor_id is null`) === 1,
    'b2 #9 tomar_lead_libre → veredicto no_contactar y el lead sigue en la bolsa', JSON.stringify(toma?.data));
    await expectExpectedFailure('b2 #9 sup1 no deriva un suelto de persona vetada → P0429',
      sessions.sup1.client.schema('crm').rpc('derivar_leads_equipo_fn', { p_lead_ids: [IDS_F2B.lu2], p_asesor_ids: [vend1Id] }), ['P0429'], /No insist/i);
    await expectExpectedFailure('b2 #9 sup1 no devuelve a la bandeja (revertir) un suelto de persona vetada → P0429',
      sessions.sup1.client.schema('crm').rpc('revertir_derivacion_equipo_fn', { p_lead_id: IDS_F2B.lu3 }), ['P0429'], /No insistir/i);
    await expectExpectedFailure('b2 #9 vend1 no registra una actividad humana sobre lu3 → P0429',
      actividad(IDS_F2B.lu3, 'F2B SEGUIMIENTO BLOQUEADO TRANSIENT'), ['P0429'], /No insistir/i);
    await expectExpectedFailure('b2 #9 vend1 no agenda una tarea humana sobre lu3 → P0429',
      tarea(IDS_F2B.lu3, 'F2B TAREA BLOQUEADA TRANSIENT'), ['P0429'], /No insistir/i);
    await positive('b2 #9 coordinador descarta lu4 desde la cola (cerrar no es contactar)',
      sessions.coordinador.client.schema('crm').rpc('descartar_lead', { p_lead: IDS_F2B.lu4, p_motivo: 'pide_credito', p_nota: 'gate f2b' }));
    check(cuenta('lu4 descartado', `select count(*) from crm.leads where id='${IDS_F2B.lu4}' and etapa='descartado'`) === 1, 'b2 #9 lu4 quedó descartado');
    await expectExpectedFailure('b2 #9 coordinador no deshace el descarte de una persona vetada → P0429',
      sessions.coordinador.client.schema('crm').rpc('deshacer_descarte', { p_lead: IDS_F2B.lu4 }), ['P0429'], /No insistir/i);

    // ── #10 · marcar cancela las tareas pendientes; levantar no las revive ─
    check(cuenta('tarea cancelada por sistema', `select count(*) from crm.tareas where id='${TAREA_F2B}' and estado='cancelada' and cancelada_por='sistema'`) === 1,
      'b2 #10 marcar_no_contactar canceló la tarea pendiente de la persona (cancelada_por = sistema)');
    check(cuenta('nota del veto', `select count(*) from crm.actividades where lead_id='${IDS_F2B.lu5}' and metadata->>'evento'='no_contactar'`) === 1,
      'b2 #10 la nota de marcar entró bajo la válvula (el trigger de gestión la exime)');
    await positive('b2 #10 gerencia levanta el veto de la persona e',
      sessions.gerencia.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_F2B.lu5, p_motivo: 'gate f2b' }));
    check(cuenta('tarea sigue cancelada', `select count(*) from crm.tareas where id='${TAREA_F2B}' and estado='cancelada'`) === 1, 'b2 #10 levantar NO revive la tarea');
    await positive('b2 #10 tras levantar, el seguimiento vuelve', actividad(IDS_F2B.lu5, 'F2B TRAS LEVANTAR TRANSIENT'));

    // ── #12 · helpers privados de b2 sin EXECUTE para anon/authenticated/service_role ─
    check(ejecutablesResiduales(FIRMAS_F2B_B2, ['anon', 'authenticated', 'service_role']) === 0,
      'b2 #12 persona_vetada / leads_vetados_persona sin EXECUTE para anon, authenticated, service_role (ni PUBLIC)');

    // ── #11 · paridad con la bandera APAGADA: repartir / derivar / actividad pasan como hoy ─
    flag(false);
    check(cuenta('OFF persona_vetada', `select private.persona_vetada('${IDS_F2B.lu1}')::int`) === 0, 'b2 #11 OFF: persona_vetada() = false');
    // F2.b [D-3]: con la bandera encendida los sueltos heredaron la bandera propia; para medir la paridad OFF (lead sin veto propio) se les quita.
    if (conD3) {
      ejecutarFueraDeBanda('b2 #11 sueltos sin bandera propia (D-3)', `select set_config('crm.op_privilegiada', 'on', true); update crm.leads set no_contactar = false where id in ('${IDS_F2B.lu1}', '${IDS_F2B.lu2}') and no_contactar;`);
    }
    await positive('b2 #11 OFF: gerencia reparte lu1 como hoy',
      sessions.gerencia.client.schema('crm').rpc('repartir_lead', { p_lead: IDS_F2B.lu1, p_supervisor: sup1Id }));
    check(cuenta('OFF lu1 repartido', `select count(*) from crm.leads where id='${IDS_F2B.lu1}' and asignado_supervisor_id='${sup1Id}'`) === 1, 'b2 #11 OFF: lu1 fue a la bandeja de sup1');
    await positive('b2 #11 OFF: sup1 deriva lu2 a vend1 como hoy',
      sessions.sup1.client.schema('crm').rpc('derivar_leads_equipo_fn', { p_lead_ids: [IDS_F2B.lu2], p_asesor_ids: [vend1Id] }));
    check(cuenta('OFF lu2 derivado', `select count(*) from crm.leads where id='${IDS_F2B.lu2}' and vendedor_id='${vend1Id}'`) === 1, 'b2 #11 OFF: lu2 quedó con vend1');
    await positive('b2 #11 OFF: vend1 registra una actividad sobre lu3 como hoy', actividad(IDS_F2B.lu3, 'F2B OFF TRANSIENT'));
  } finally {
    flag(false);
    const docs = Object.values(DOCS_F2B);
    ejecutarFueraDeBanda('limpieza F2.b', `
      delete from crm.inversion_titulares where inversion_id in (select id from crm.inversiones where cierre_externo_id in (select id from crm.cierres_externos where lead_id in (${lista(leadIds)})));
      delete from crm.inversiones where cierre_externo_id in (select id from crm.cierres_externos where lead_id in (${lista(leadIds)}));
      delete from crm.depositos_reclamados where numero_norm like 'TRX-F2B-${sufijo}-%';
      delete from crm.cierres_externos where lead_id in (${lista(leadIds)});
      delete from crm.inversionista_leads where lead_id in (${lista(leadIds)});
      delete from crm.multiempresa_idempotencia where clave like 'conversion%:%' and split_part(clave, ':', 2) in (${lista(leadIds)});
      delete from crm.tareas where lead_id in (${lista(leadIds)});
      delete from crm.actividades where lead_id in (${lista(leadIds)});
      delete from crm.lead_asignaciones where lead_id in (${lista(leadIds)});
      delete from crm.leads where id in (${lista(leadIds)});
      update crm.leads set activo=false where id in (${lista(leadIds)});
      delete from crm.inversionista_responsables where inversionista_id in (select inversionista_id from crm.inversionista_identificadores where documento_normalizado in (${lista(docs)}));
      delete from crm.inversionista_identificadores where documento_normalizado in (${lista(docs)});
      delete from crm.inversionistas where id not in (select inversionista_id from crm.inversionista_identificadores) and not exists (select 1 from crm.leads l where l.inversionista_id=crm.inversionistas.id) and not exists (select 1 from crm.inversiones v where v.inversionista_id=crm.inversionistas.id);
    `, { tolerante: true });
  }
}

async function testCierresExternos(sessions, seed) {
  console.log('\n— Cierres externos en cooperativas (Qorilazo/Prodelco) —');

  // Mismo calculo de periodo EN LIMA que el bloque de conversion: la RPC
  // rechaza el mes futuro con el reloj de Lima, no el de la maquina.
  const enLima = (fecha) => new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(fecha);
  const PERIODO = `${enLima(new Date()).slice(0, 7)}-01`;
  const ids = seed.profileIdByKey;

  const pedirFn = (clave) => sessions[clave].client
    .schema('crm').rpc('cierres_externos_fn', { p_periodo: PERIODO });
  const convertir = (clave, args) => sessions[clave].client
    .schema('crm').rpc('convertir_lead_externo', args);
  const corregir = (clave, args) => sessions[clave].client
    .schema('crm').rpc('corregir_cierre_externo', args);

  // ── 1 · La tabla es deny-by-default ABSOLUTO: nadie la toca directo ───────
  for (const clave of ['vend1', 'sup1', 'gerencia', 'coordinador', 'directorio', 'clientBank']) {
    await expectExplicitAuthorizationDenied(
      `cierres_externos: select directo denegado para ${clave}`,
      sessions[clave].client.schema('crm').from('cierres_externos').select('id').limit(1),
    );
  }
  await expectExplicitAuthorizationDenied(
    'cierres_externos: insert directo denegado incluso para gerencia',
    sessions.gerencia.client.schema('crm').from('cierres_externos').insert({
      cooperativa: 'qorilazo',
      creado_por: ids.gerencia,
      documento: '99887799',
      documento_tipo: 'DNI',
      lead_id: IDS_CIERRES_EXTERNOS.leadCoop,
      moneda: 'PEN',
      monto: 1,
      nombre_completo: 'X',
      vendedor_id: ids.vend1,
    }),
  );

  // ── 2 · La RPC de lectura: allowlist y ambito por rol ─────────────────────
  const lecturaVend = await positive('vend1 lee cierres_externos_fn', pedirFn('vend1'));
  if (lecturaVend) {
    check(lecturaVend.data?.alcance === 'propio',
      'el alcance de vend1 es propio', JSON.stringify(lecturaVend.data?.alcance));
  }
  const lecturaSup = await positive('sup1 lee cierres_externos_fn', pedirFn('sup1'));
  if (lecturaSup) {
    check(lecturaSup.data?.alcance === 'equipo',
      'el alcance de sup1 es equipo', JSON.stringify(lecturaSup.data?.alcance));
  }
  const lecturaGer = await positive('gerencia lee cierres_externos_fn', pedirFn('gerencia'));
  if (lecturaGer) {
    check(lecturaGer.data?.alcance === 'global',
      'el alcance de gerencia es global', JSON.stringify(lecturaGer.data?.alcance));
  }
  const lecturaDir = await positive(
    'directorio (lector global) lee cierres_externos_fn', pedirFn('directorio'),
  );
  if (lecturaDir) {
    check(lecturaDir.data?.alcance === 'global',
      'el alcance del lector global es global', JSON.stringify(lecturaDir.data?.alcance));
    check(Array.isArray(lecturaDir.data?.cierres) && lecturaDir.data.cierres.length === 0,
      'el lector global recibe agregados SIN filas (la PII es de los operadores)',
      JSON.stringify(lecturaDir.data?.cierres));
  }
  await expectExplicitAuthorizationDenied(
    'coordinador denegado en cierres_externos_fn', pedirFn('coordinador'),
  );
  await expectExplicitAuthorizationDenied(
    'cliente denegado en cierres_externos_fn', pedirFn('clientBank'),
  );

  // Linea base para la delta global (el fixture del branch puede traer lo suyo).
  const totalAntes = Number(lecturaGer?.data?.cierres_total ?? 0);

  try {
    // ── 3 · El ciclo real: convertir a cooperativa por la VIA REAL ──────────
    await requireAdmin(
      'sembrar los dos leads transitorios de cierres externos',
      admin.schema('crm').from('leads').insert([
        {
          activo: true,
          asignado_supervisor_id: null,
          creado_por: ids.vend1,
          etapa: 'nuevo',
          id: IDS_CIERRES_EXTERNOS.leadCoop,
          moneda: 'PEN',
          monto_estimado: 4000,
          no_contactar: false,
          nombre_completo: 'CIERRE EXTERNO TRANSIENT',
          origen: 'otro',
          telefono: '999000141',
          vendedor_id: ids.vend1,
        },
        {
          activo: true,
          asignado_supervisor_id: null,
          creado_por: ids.vend3,
          etapa: 'nuevo',
          id: IDS_CIERRES_EXTERNOS.leadAjeno,
          moneda: 'PEN',
          monto_estimado: 4000,
          no_contactar: false,
          nombre_completo: 'CIERRE EXTERNO AJENO TRANSIENT',
          origen: 'otro',
          telefono: '999000142',
          vendedor_id: ids.vend3,
        },
      ]),
    );

    // El numero de operacion se DERIVA del UUID aleatorio de la corrida y no es
    // una constante: el indice unico `(cooperativa, numero_transaccion)` lo
    // vigila, el bloque deja la fila viva a proposito (un cierre no se borra) y
    // con un literal fijo una segunda corrida sobre la misma base chocaria
    // contra su propio rastro en vez de probar nada.
    const OPERACION = `OP-GATE-${IDS_CIERRES_EXTERNOS.leadCoop.slice(0, 8)}`;
    const argsCoop = {
      p_cooperativa: 'qorilazo',
      p_documento: '99887761',
      p_documento_tipo: 'DNI',
      p_lead_id: IDS_CIERRES_EXTERNOS.leadCoop,
      p_moneda: 'PEN',
      p_monto: 1234.56,
      p_nombre: 'CIERRE EXTERNO TRANSIENT',
      p_numero_transaccion: OPERACION,
      p_referencia: 'QOR-GATE-1',
    };

    const ajeno = await convertir('vend1', {
      ...argsCoop, p_lead_id: IDS_CIERRES_EXTERNOS.leadAjeno,
    });
    check(ajeno.error != null && /fuera de tu ambito/i.test(ajeno.error?.message ?? ''),
      'vend1 no convierte a coop un lead del equipo ajeno', errorText(ajeno.error));

    await expectExplicitAuthorizationDenied(
      'coordinador no convierte a cooperativa', convertir('coordinador', argsCoop),
    );
    await expectExplicitAuthorizationDenied(
      'cliente no convierte a cooperativa', convertir('clientBank', argsCoop),
    );
    await expectExplicitAuthorizationDenied(
      'directorio (lector global) no convierte a cooperativa',
      convertir('directorio', argsCoop),
    );

    const cierre = await positive(
      'vend1 convierte su lead a COOPAC Qorilazo (sin portal, sin correo)',
      convertir('vend1', argsCoop),
    );
    if (cierre) {
      check(cierre.data?.ok === true,
        'la conversion externa respondio ok', JSON.stringify(cierre.data));
    }

    const leadTras = await requireAdmin(
      'leer el lead convertido (admin)',
      admin.schema('crm').from('leads')
        .select('etapa, perfil_id, convertido_en')
        .eq('id', IDS_CIERRES_EXTERNOS.leadCoop).single(),
    );
    check(leadTras.data.etapa === 'convertido'
      && leadTras.data.perfil_id === null
      && leadTras.data.convertido_en !== null,
      'el lead quedo convertido SIN perfil de portal (el invariante relajado)',
      JSON.stringify(leadTras.data));

    const doble = await convertir('vend1', argsCoop);
    check(doble.error != null && /ya esta cerrado/i.test(doble.error?.message ?? ''),
      'el doble cierre externo se rechaza', errorText(doble.error));

    const lecturaTras = await positive(
      'vend1 relee cierres_externos_fn tras el cierre', pedirFn('vend1'),
    );
    const fila = (lecturaTras?.data?.cierres ?? [])
      .find((c) => c.lead_id === IDS_CIERRES_EXTERNOS.leadCoop) ?? null;
    check(fila !== null,
      'el cierre de vend1 aparece en sus filas con su distintivo',
      JSON.stringify(lecturaTras?.data?.cierres));
    if (fila) {
      check(fila.cooperativa === 'qorilazo' && Number(fila.monto) === 1234.56,
        'la fila trae cooperativa y monto reales', JSON.stringify(fila));
    }

    const gerTras = await positive(
      'gerencia relee cierres_externos_fn (delta global)', pedirFn('gerencia'),
    );
    check(Number(gerTras?.data?.cierres_total ?? 0) === totalAntes + 1,
      'cierres_total global subio exactamente en 1',
      JSON.stringify({ antes: totalAntes, despues: gerTras?.data?.cierres_total }));

    // ── 3bis · crm.cierres_estado_fn: la VENTANA a la anulacion, y su ambito ─
    // Existe porque `crm.cierres_avance_anulados` es deny-by-default: sin ella
    // la anulacion de gerencia seria INVISIBLE en la aplicacion (se anularia y
    // al recargar el lead se veria igual que antes). Como las dos tablas de
    // anulacion no tienen ni una policy, la funcion es DEFINER y su ambito es un
    // predicado COPIADO de `leads_select`. Un predicado copiado se desincroniza
    // en silencio, asi que lo que se asevera aqui no es un ejemplo suelto sino
    // la FRONTERA: el MISMO lead, pedido por dos llamadores distintos.
    const estado = (clave, leadIds) => sessions[clave].client
      .schema('crm').rpc('cierres_estado_fn', { p_lead_ids: leadIds });

    const estadoVend = await positive(
      'vend1 lee el estado del cierre de SU lead',
      estado('vend1', [IDS_CIERRES_EXTERNOS.leadCoop]),
    );
    const filaEstado = (estadoVend?.data ?? [])
      .find((f) => f.lead_id === IDS_CIERRES_EXTERNOS.leadCoop) ?? null;
    check(filaEstado?.canal === 'cooperativa' && filaEstado?.anulado_en === null,
      'el lead de coop se declara canal cooperativa y sin anular (es lo que apaga el boton de Avance)',
      JSON.stringify(estadoVend?.data));

    // LA FRONTERA. Si esto devolviera algo, el predicado copiado ya no seria el
    // de la policy y estariamos sirviendo el motivo de una anulacion ajena.
    const estadoAjeno = await positive(
      'vend3 pide el estado de un lead que NO es suyo',
      estado('vend3', [IDS_CIERRES_EXTERNOS.leadCoop]),
    );
    check(Array.isArray(estadoAjeno?.data) && estadoAjeno.data.length === 0,
      'vend3 no recibe NADA del lead ajeno (el ambito no se recorta en el cliente)',
      JSON.stringify(estadoAjeno?.data));

    const estadoGer = await positive(
      'gerencia lee el estado del mismo cierre',
      estado('gerencia', [IDS_CIERRES_EXTERNOS.leadCoop]),
    );
    check((estadoGer?.data ?? []).length === 1,
      'gerencia recibe exactamente la fila del lead pedido', JSON.stringify(estadoGer?.data));

    const estadoDir = await positive(
      'directorio (lector global) lee el estado del cierre',
      estado('directorio', [IDS_CIERRES_EXTERNOS.leadCoop]),
    );
    check((estadoDir?.data ?? []).length === 1,
      'el lector global ve el estado igual que gerencia (la policy se lo permite)',
      JSON.stringify(estadoDir?.data));

    // El coordinador PASA el gate y recibe vacio: su ambito de leads es ∅, igual
    // que en cumplimiento_metas_fn. Es 200 con [], no 42501 — quien acota es
    // `vendedor_ids_visibles`, no la admision.
    const estadoCoord = await positive(
      'coordinador pasa el gate de cierres_estado_fn',
      estado('coordinador', [IDS_CIERRES_EXTERNOS.leadCoop]),
    );
    check((estadoCoord?.data ?? []).length === 0,
      'el coordinador recibe la lista VACIA (ambito ∅)', JSON.stringify(estadoCoord?.data));

    await expectExplicitAuthorizationDenied(
      'cliente denegado en cierres_estado_fn',
      estado('clientBank', [IDS_CIERRES_EXTERNOS.leadCoop]),
    );
    await expectExplicitAuthorizationDenied(
      'usuario revocado denegado en cierres_estado_fn',
      estado('vendInactive', [IDS_CIERRES_EXTERNOS.leadCoop]),
    );

    // Un lead SIN nada que decir no viaja, y se pregunta desde SU DUENO para que
    // el vacio signifique «no hay nada» y no «no lo ves»: preguntado por un
    // ajeno, este caso pasaria por vacuidad sin probar nada.
    const estadoMudo = await positive(
      'un lead propio sin cierre en coop ni anulacion no aparece',
      estado('vend3', [IDS_CIERRES_EXTERNOS.leadAjeno]),
    );
    check((estadoMudo?.data ?? []).length === 0,
      'el payload solo trae leads con algo que decir', JSON.stringify(estadoMudo?.data));

    // El tope, que es lo que separa una pagina de un volcado.
    await expectExpectedFailure(
      'cierres_estado_fn rechaza mas de 200 ids',
      estado('gerencia', Array.from({ length: 201 }, () => IDS_CIERRES_EXTERNOS.leadCoop)),
      ['22023', 'P0001'],
      /maximo 200/i,
    );

    // ── 4 · La correccion es de gerencia ────────────────────────────────────
    const cierreId = fila?.cierre_id ?? null;
    if (cierreId) {
      // ⚠️ Codex (01/09) refutó la aserción de totales por `.some(>=1500)` sin
      //    moneda: cualquier OTRO prodelco del historial la dejaba verde aunque
      //    los 1500 recien anulados hubieran salido. El contrato de ATR-4 se
      //    prueba con ARITMETICA EXACTA sobre una linea base capturada ANTES de
      //    la correccion: corregir suma 1500/+1 a prodelco/PEN, y anular deja
      //    esa foto EXACTAMENTE igual.
      const totalProdelcoPen = (payload) => {
        const t = (payload?.totales ?? [])
          .find((x) => x.cooperativa === 'prodelco' && x.moneda === 'PEN') ?? null;
        return { capital: Number(t?.capital ?? 0), cierres: Number(t?.cierres ?? 0) };
      };
      // linea base: la relectura de vend1 tras crear el cierre (aun qorilazo).
      const prodelcoBase = totalProdelcoPen(lecturaTras?.data);
      let prodelcoCorr = null;
      const argsCorreccion = {
        p_cierre_id: cierreId,
        p_cooperativa: 'prodelco',
        p_moneda: 'PEN',
        p_monto: 1500,
        p_nota: null,
        p_numero_transaccion: OPERACION,
        p_referencia: 'QOR-GATE-1',
        p_vence_en: null,
      };
      await expectExplicitAuthorizationDenied(
        'vend1 no corrige un cierre externo', corregir('vend1', argsCorreccion),
      );
      await expectExplicitAuthorizationDenied(
        'sup1 no corrige un cierre externo', corregir('sup1', argsCorreccion),
      );
      await expectExplicitAuthorizationDenied(
        'directorio no corrige un cierre externo', corregir('directorio', argsCorreccion),
      );
      const correccion = await positive(
        'gerencia corrige el cierre (monto y cooperativa)',
        corregir('gerencia', argsCorreccion),
      );
      if (correccion) {
        const relectura = await positive('vend1 ve el cierre corregido', pedirFn('vend1'));
        const filaTras = (relectura?.data?.cierres ?? [])
          .find((c) => c.lead_id === IDS_CIERRES_EXTERNOS.leadCoop) ?? null;
        check(filaTras?.cooperativa === 'prodelco' && Number(filaTras?.monto) === 1500,
          'la correccion quedo en la foto', JSON.stringify(filaTras));
        prodelcoCorr = totalProdelcoPen(relectura?.data);
        check(prodelcoCorr.capital === prodelcoBase.capital + 1500
            && prodelcoCorr.cierres === prodelcoBase.cierres + 1,
          'la correccion movio prodelco/PEN EXACTAMENTE +1500 y +1 cierre',
          JSON.stringify({ base: prodelcoBase, tras: prodelcoCorr }));
      }

      // ── 5 · La ANULACION es de gerencia — castiga la CONVERSION, no el capital
      // Freno de emergencia contra un cierre falso. Se vigila QUIEN puede tirar
      // de el (solo gerencia) y el contrato de ATR-4 (registro 193, 01/09,
      // decision de Miguel: «solo la conversion, siempre»): la fila queda
      // MARCADA y el capital SIGUE en los totales — anular es sancion al
      // analista, no un borrador de dinero de la empresa. Lo que baja es su
      // conversion; probar ESA bajada pide los fixtures de cadena del proximo
      // ciclo de banco (deuda ya nombrada en ATR-1/ATR-2).
      // Historia: hasta el 01/09 aqui se exigia lo contrario (que el cierre
      // saliera de los totales). La suite no habia podido correr nunca y el
      // banco destapo la contradiccion el mismo dia en que ATR-4 la volvio
      // norma; Miguel confirmo «ATR-4 manda» antes de tocar esta aserción.
      const anular = (clave, args) => sessions[clave].client
        .schema('crm').rpc('anular_cierre_externo', args);
      const argsAnular = { p_cierre_id: cierreId, p_motivo: 'GATE: cierre de prueba' };
      await expectExplicitAuthorizationDenied(
        'vend1 no anula un cierre externo', anular('vend1', argsAnular),
      );
      await expectExplicitAuthorizationDenied(
        'sup1 no anula un cierre externo', anular('sup1', argsAnular),
      );
      await expectExplicitAuthorizationDenied(
        'directorio no anula un cierre externo', anular('directorio', argsAnular),
      );
      const sinMotivo = await anular('gerencia', { p_cierre_id: cierreId, p_motivo: '   ' });
      check(sinMotivo.error != null && /motivo/i.test(sinMotivo.error?.message ?? ''),
        'gerencia tampoco anula SIN motivo', errorText(sinMotivo.error));

      const anulacion = await positive('gerencia anula el cierre', anular('gerencia', argsAnular));
      if (anulacion) {
        const traAnular = await positive('vend1 relee tras la anulacion', pedirFn('vend1'));
        const filaAnulada = (traAnular?.data?.cierres ?? [])
          .find((c) => c.lead_id === IDS_CIERRES_EXTERNOS.leadCoop) ?? null;
        check(filaAnulada != null && filaAnulada.anulado_en != null,
          'el cierre anulado SIGUE en las filas, marcado',
          JSON.stringify(filaAnulada));
        const prodelcoAnul = totalProdelcoPen(traAnular?.data);
        check(prodelcoCorr != null
            && prodelcoAnul.capital === prodelcoCorr.capital
            && prodelcoAnul.cierres === prodelcoCorr.cierres,
          'ATR-4: anular NO movio ni un centimo de prodelco/PEN (sanciona la conversion del analista; el capital no se toca jamas)',
          JSON.stringify({ trasCorregir: prodelcoCorr, trasAnular: prodelcoAnul }));
        const doble = await anular('gerencia', argsAnular);
        check(doble.error != null && /ya estaba anulado/i.test(doble.error?.message ?? ''),
          'un cierre anulado no se anula dos veces', errorText(doble.error));
      }
    }

    // ── 6 · La RESERVA: quien puede apartar un lead para convertirlo ────────
    // La toma la edge de Avance ANTES de crear el usuario y el correo; aqui se
    // vigila que no sea una puerta mas ancha que la conversion misma.
    const reservar = (clave, leadId) => sessions[clave].client
      .schema('crm').rpc('reservar_conversion_lead', { p_lead_id: leadId });
    await expectExplicitAuthorizationDenied(
      'coordinador no reserva una conversion',
      reservar('coordinador', IDS_CIERRES_EXTERNOS.leadAjeno),
    );
    await expectExplicitAuthorizationDenied(
      'cliente no reserva una conversion',
      reservar('clientBank', IDS_CIERRES_EXTERNOS.leadAjeno),
    );
    const reservaAjena = await reservar('vend1', IDS_CIERRES_EXTERNOS.leadAjeno);
    check(reservaAjena.error != null && /fuera de tu ambito/i.test(reservaAjena.error?.message ?? ''),
      'vend1 no reserva un lead del equipo ajeno', errorText(reservaAjena.error));
    const reservaCerrado = await reservar('vend1', IDS_CIERRES_EXTERNOS.leadCoop);
    check(reservaCerrado.error != null && /ya esta cerrado/i.test(reservaCerrado.error?.message ?? ''),
      'no se reserva un lead ya convertido (asi la edge se entera ANTES de crear nada)',
      errorText(reservaCerrado.error));
    // Sonda FUERTE (42501), no `expectHidden`: en una tabla sensible «0 filas»
    // no demuestra nada —lo dice el propio docstring del helper— y una reserva
    // forjada bloquea el cierre en cooperativa de un lead ajeno.
    for (const clave of ['vend1', 'sup1', 'gerencia', 'coordinador', 'directorio', 'clientBank']) {
      await expectExplicitAuthorizationDenied(
        `conversion_reservas: select directo denegado para ${clave}`,
        sessions[clave].client.schema('crm').from('conversion_reservas').select('lead_id'),
      );
      await expectExplicitAuthorizationDenied(
        `conversion_reservas: insert directo denegado para ${clave}`,
        sessions[clave].client.schema('crm').from('conversion_reservas').insert({
          lead_id: IDS_CIERRES_EXTERNOS.leadAjeno,
          reservado_por: ids.vend1,
          expira_en: new Date(Date.now() + 60000).toISOString(),
          vence_absoluto_en: new Date(Date.now() + 600000).toISOString(),
        }),
      );
    }

    // El NaN por la API REAL: es la ruta por la que llegaría de verdad
    // (PostgREST convierte la cadena JSON con el input del tipo numeric), y en
    // Postgres `NaN > 0` es TRUE, así que se colaba por todas las guardas y
    // envenenaba la suma de la cuota del mes entera.
    // Se asevera el MOTIVO y no solo «hubo error»: sobre este lead ya cerrado
    // cualquier payload falla, así que un `error != null` a secas sería una
    // aserción vacua. La validación del monto corre ANTES del gate de etapa, y
    // ese es justo el mensaje que tiene que salir.
    const nan = await convertir('vend1', { ...argsCoop, p_monto: 'NaN' });
    check(nan.error != null && /mayor que cero/i.test(nan.error?.message ?? ''),
      'un monto NaN por la Data API se rechaza (envenenaba la cuota del equipo)',
      errorText(nan.error));
  } finally {
    // Soft-delete, nunca DELETE: la regla de la casa. El cierre externo se
    // queda (es inmutable por diseño y el DELETE esta vetado con P0409); el
    // gate no es re-ejecutable sobre la misma base de todos modos.
    await requireAdmin(
      'limpieza: desactivar los leads transitorios de cierres externos',
      admin.schema('crm').from('leads').update({ activo: false })
        .in('id', [IDS_CIERRES_EXTERNOS.leadCoop, IDS_CIERRES_EXTERNOS.leadAjeno]),
    );
  }
}

async function testAnon(seed) {
  console.log('\n— Acceso anonimo —');
  const anon = createClient(
    SUPABASE_URL,
    ANON_KEY,
    clientOptions('crm-rls-anon'),
  );
  const knownLead = seed.leadByName.get('JUAN PEREZ DEMO');
  const bankProfileId = seed.profileIdByKey[BANK_CLIENT.key];

  await expectHidden(
    'anon no lee crm.leads',
    anon.schema('crm').from('leads').select('id').eq('id', knownLead.id),
  );
  await expectHidden(
    'anon no lee crm.equipo',
    anon.schema('crm').from('equipo').select('perfil_id').limit(1),
  );
  await expectHidden(
    'anon no lee crm.actividades',
    anon.schema('crm').from('actividades').select('id').eq('id', LEADS[0].activityId),
  );
  await expectHidden(
    'anon no lee crm.tareas',
    anon.schema('crm').from('tareas').select('id').eq('id', TAREA_BY_KEY.llamadaJuan.id),
  );
  await expectHidden(
    'anon no lee crm.agenda_ics',
    anon.schema('crm').from('agenda_ics').select('perfil_id').limit(1),
  );
  await expectExplicitAuthorizationDenied(
    'anon no ejecuta la configuracion versionada de metas',
    anon.schema('crm').rpc('configuracion_metas_fn', { p_periodo: '2026-08-01' }),
    ['42501', 'PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no ejecuta el timeline del ambito',
    anon.schema('crm').rpc('actividades_del_ambito_fn'),
    ['42501', 'PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no ejecuta la cartera paginada por keyset',
    anon.schema('crm').rpc('cartera_pagina_fn', { p_limite: 50 }),
    ['42501', 'PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no lee directamente crm.cuentas_bancarias',
    anon.schema('crm').from('cuentas_bancarias').select('id').limit(1),
    ['PGRST205'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no lee directamente crm.contrato_cuentas_pago',
    anon.schema('crm').from('contrato_cuentas_pago').select('id').limit(1),
    ['PGRST205'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no ejecuta el listado de cuentas bancarias por cliente',
    anon.schema('crm').rpc('cuentas_bancarias_cliente_fn', {
      p_cliente_id: bankProfileId,
      p_moneda: BANK_CONTRACT.currency,
    }),
    ['PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no crea contratos con cuenta bancaria',
    anon.schema('crm').rpc('crear_contrato_con_cuenta', {
      p_contrato: { cliente_id: bankProfileId, moneda: BANK_CONTRACT.currency },
      p_cronograma: [],
      p_cuenta: {},
    }),
    ['PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no corrige contratos legacy por el wrapper bancario',
    anon.schema('crm').rpc('actualizar_contrato_con_cuenta', {
      p_id: seed.legacyContract.id,
      p_contrato: { moneda: BANK_LEGACY_CONTRACT.currency },
      p_cronograma: [],
    }),
    ['PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no resuelve cuentas contractuales para Pagos',
    anon.schema('crm').rpc('cuentas_pago_contratos_fn', {
      p_contrato_ids: [seed.contract.id],
    }),
    ['PGRST202'],
  );
  // C1: las RPC de reparto solo tienen grant para `authenticated`.
  await expectBlockedMutation(
    'anon no puede ver la cola por repartir',
    anon.schema('crm').rpc('leads_por_repartir'),
    ['42501', 'PGRST202'],
  );
  await expectBlockedMutation(
    'anon no puede listar los supervisores de reparto',
    anon.schema('crm').rpc('supervisores_para_reparto'),
    ['42501', 'PGRST202'],
  );
  await expectBlockedMutation(
    'anon no puede repartir un lead',
    anon.schema('crm').rpc('repartir_lead', {
      p_lead: knownLead.id,
      p_supervisor: seed.profileIdByKey.sup1,
    }),
    ['42501', 'PGRST202'],
  );
  // C1-ter: la vista de descartados tampoco (paridad con las hermanas).
  await expectBlockedMutation(
    'anon no puede listar los descartados de la cola',
    anon.schema('crm').rpc('leads_descartados'),
    ['42501', 'PGRST202'],
  );
  // F1 tanda 1: las 4 RPC de metricas agregadas solo existen para authenticated.
  for (const [fn, args] of [
    ['resumen_cartera_fn', {}],
    ['cola_accion_fn', { p_limite: 100 }],
    ['metricas_vendedores_fn', {}],
    ['series_comerciales_fn', { p_meses: 6 }],
    // Decision #10 (b2): la RPC del ranking de conversion del equipo nace con
    // la misma sonda que sus hermanas — anon no la ve ni existiendo.
    ['metricas_conversiones_equipo_fn', { p_desde: '2026-01-01', p_hasta: '2026-01-31' }],
  ]) {
    await expectExplicitAuthorizationDenied(
      `anon no ejecuta ${fn}`,
      anon.schema('crm').rpc(fn, args),
      ['42501', 'PGRST202'],
    );
  }
  await expectHidden(
    'anon no lee datos bancarios public.perfiles',
    anon.from('perfiles').select('id, banco, numero_cuenta, cci').eq('id', bankProfileId),
  );
}

// ── Cierre de mes: el sello, el ciclo y el aviso (migraciones 20260815*) ─────
// El conjunto del cierre de mes trae TRES TABLAS deny-by-default
// (`periodos_cerrados`, `cierre_mes_vendedor`, `ajustes_mes_cerrado`) y tres RPC
// nuevas. Las tablas nacen con RLS ON, CERO policies y los privilegios revocados
// de los cuatro roles: se leen SOLO a traves de funciones. Eso es exactamente lo
// que esta matriz existe para comprobar, porque «no tiene policies» es una
// afirmacion sobre el catalogo y «nadie la puede leer» es una afirmacion sobre
// una sesion real, y no son la misma cosa.
//
// ⚠️ AQUI NO SE CIERRA NINGUN MES. El camino positivo de `crm.cerrar_periodo`
// —gerencia sellando de verdad— NO se ejerce en el gate a proposito: sellar es
// IRREVERSIBLE por diseño (append-only, sin policy DELETE y con trigger que veta
// UPDATE/DELETE), asi que dejaria la branch con un mes cerrado que ni este gate
// ni el bloque de conversion pueden deshacer, y la segunda corrida mediria otro
// mundo. Ese caso positivo vive en el oraculo `test-cierre-mes.sql` (bloque
// 10bis), que corre sobre un banco desechable y lo deshace con un rollback.
// Aqui se prueba lo que el oraculo NO puede: las denegaciones con SESIONES
// REALES y la alcanzabilidad por la Data API.
const TABLAS_CIERRE_MES = ['periodos_cerrados', 'cierre_mes_vendedor', 'ajustes_mes_cerrado'];
// Los cuatro roles que tienen pantalla, mas los dos que no deben tener nada que
// hacer aqui. `vendInactive` y `clientBank` son la frontera: uno salio del CRM,
// el otro nunca estuvo.
const ROLES_CON_AVISO = ['vend1', 'sup1', 'gerencia', 'coordinador', 'directorio'];
const ROLES_SIN_AVISO = ['vendInactive', 'clientBank'];


// P-055 FASE 3 (hallazgo A5 del auditor RLS, 29/08): la atribucion de ventas.
// Cubre la superficie nueva entera: la tabla del rastro (lectura por rol y
// escritura bloqueada), las dos RPC con su gate, los DOS candados de columna
// (analista y es_demo) y el recorte del historial con motivos. Si las
// migraciones 20260829* no estan aplicadas, se dice OMITIDO en voz alta.

// P-055 FASE 4 (hallazgo M2 del auditor RLS): la calculadora unica de capital.
// Los casos PERMITIDOS con filas (no solo denegaciones), el gate de la lista
// del periodo, y que el nucleo/ventana NO sean alcanzables por la API.
async function testCapitalNucleo(sessions, seed) {
  console.log('\n— Fase 4: calculadora unica de capital —');
  void seed;
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-capital'));
  const gerencia = sessions.gerencia.client;

  const sonda = await gerencia.schema('crm').rpc('metricas_capital_mes_fn', { p_meses: 3 });
  if (sonda.error && String(sonda.error.code ?? '') === 'PGRST202') {
    console.log('  ⚠ OMITIDO: las migraciones de la Fase 4 no estan aplicadas en esta base.');
    return;
  }

  // PERMITIDO con filas: gerencia ve capital; vendedor tambien (su ambito).
  if (sonda.error) {
    fail(`gerencia lee metricas_capital_mes_fn: ${sonda.error.message}`);
  } else if (!Array.isArray(sonda.data)) {
    fail('metricas_capital_mes_fn no devolvio filas a gerencia');
  } else {
    pass(`gerencia lee metricas_capital_mes_fn (${sonda.data.length} filas)`);
  }
  const venc = await gerencia.schema('crm').rpc('metricas_vencimientos_fn', { p_dias: 180 });
  if (venc.error) fail(`gerencia lee metricas_vencimientos_fn: ${venc.error.message}`);
  else pass(`gerencia lee metricas_vencimientos_fn (${(venc.data ?? []).length} filas)`);

  const vend = await sessions.vend1.client.schema('crm').rpc('metricas_capital_mes_fn', { p_meses: 3 });
  if (vend.error) fail(`vend1 lee metricas_capital_mes_fn: ${vend.error.message}`);
  else pass('vend1 lee metricas_capital_mes_fn (su ambito, sin error)');

  // La lista del periodo: gerencia SI, vendedor NO (gate gerencia/lector).
  const per = await gerencia.schema('crm').rpc('contratos_por_periodo_comercial_fn',
    { p_periodo: '2026-08-01' });
  if (per.error) fail(`gerencia lee contratos_por_periodo_comercial_fn: ${per.error.message}`);
  else pass('gerencia lee contratos_por_periodo_comercial_fn');
  await expectExplicitAuthorizationDenied(
    'un vendedor NO lee la lista del periodo (gate gerencia/lector)',
    sessions.vend1.client.schema('crm').rpc('contratos_por_periodo_comercial_fn',
      { p_periodo: '2026-08-01' }),
    ['42501'],
  );

  // El nucleo y su ventana NO existen para la API (schema private no expuesto).
  for (const [quien, cli] of [['anon', anon], ['gerencia', gerencia]]) {
    await expectExplicitAuthorizationDenied(
      `${quien} no alcanza capital_autorizada por la API`,
      cli.rpc('capital_autorizada', { p_desde: '2026-08-01', p_hasta: '2026-08-31' }),
      ['42501', 'PGRST202'],
    );
    await expectExplicitAuthorizationDenied(
      `${quien} no alcanza capital_episodios por la API`,
      cli.rpc('capital_episodios', {
        p_ini: '2026-08-01', p_fin: '2026-09-01', p_global: true, p_visibles: [],
      }),
      ['42501', 'PGRST202'],
    );
  }
}

async function testAtribucionVentas(sessions, seed) {
  console.log('\n— Fase 3: atribucion de ventas (analista, demo, rastro) —');
  void seed;
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-atrib'));
  const gerencia = sessions.gerencia.client;

  // ¿Estan las migraciones? Sonda por la RPC de lectura.
  const contratoSonda = await gerencia.schema('crm').from('contratos_cartera').select('id').limit(1);
  if (contratoSonda.error || !contratoSonda.data?.length) {
    fail('fase 3: no se pudo leer un contrato de la cartera para sondear');
    return;
  }
  const contratoId = contratoSonda.data[0].id;
  const sonda = await gerencia.schema('crm').rpc('atribucion_contrato_fn', { p_contrato_id: contratoId });
  if (sonda.error && String(sonda.error.code ?? '') === 'PGRST202') {
    console.log('  ⚠ OMITIDO: las migraciones de la Fase 3 (20260829*) no estan aplicadas en esta base.');
    return;
  }

  // ── (A) El rastro: quien lo lee y quien no ────────────────────────────────
  const lecturaGerencia = await gerencia.schema('crm')
    .from('reasignaciones_analista').select('id').limit(1);
  if (lecturaGerencia.error) {
    fail(`gerencia lee crm.reasignaciones_analista: ${lecturaGerencia.error.message}`);
  } else {
    pass('gerencia lee crm.reasignaciones_analista');
  }
  for (const key of ['vend1', 'sup1', 'coordinador']) {
    if (!sessions[key]) continue;
    await expectHidden(
      `${key} no lee crm.reasignaciones_analista`,
      sessions[key].client.schema('crm').from('reasignaciones_analista').select('id').limit(1),
    );
  }
  await expectHidden(
    'anon no lee crm.reasignaciones_analista',
    anon.schema('crm').from('reasignaciones_analista').select('id').limit(1),
  );

  // Escritura directa: NADIE. Ni gerencia (sin policy de INSERT) ni nadie mas.
  await expectBlockedMutation(
    'gerencia no inserta en el rastro por la Data API',
    gerencia.schema('crm').from('reasignaciones_analista')
      .insert({ contrato_id: contratoId, analista_a: seed.profileIdByKey.vend1, motivo: 'x', reasignado_por: seed.profileIdByKey.gerencia })
      .select(),
    ['42501', 'PGRST301'],
  );
  await expectBlockedMutation(
    'gerencia no edita el rastro (append-only)',
    gerencia.schema('crm').from('reasignaciones_analista')
      .update({ motivo: 'cambiado' }).eq('contrato_id', contratoId).select(),
    ['42501', 'P0409'],
  );

  // ── (B) Los dos candados de columna sobre public.contratos ────────────────
  await expectBlockedMutation(
    'ni gerencia mueve analista_cierre_id con un UPDATE directo',
    gerencia.from('contratos')
      .update({ analista_cierre_id: seed.profileIdByKey.vend1 }).eq('id', contratoId).select(),
    ['P0409', '42501'],
  );
  await expectBlockedMutation(
    'ni gerencia cambia es_demo con un UPDATE directo',
    gerencia.from('contratos')
      .update({ es_demo: true }).eq('id', contratoId).select(),
    ['P0409', '42501'],
  );

  // ── (C) Las puertas: gate por rol y motivo obligatorio ────────────────────
  await expectExplicitAuthorizationDenied(
    'un vendedor no reasigna ventas',
    sessions.vend1.client.rpc('reasignar_analista_contrato',
      { p_contrato_id: contratoId, p_analista_id: seed.profileIdByKey.vend2, p_motivo: 'no deberia poder' }),
    ['42501'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no reasigna ventas',
    anon.rpc('reasignar_analista_contrato',
      { p_contrato_id: contratoId, p_analista_id: seed.profileIdByKey.vend2, p_motivo: 'x' }),
    ['42501', 'PGRST202'],
  );
  await expectBlockedMutation(
    'gerencia no reasigna SIN motivo',
    gerencia.rpc('reasignar_analista_contrato',
      { p_contrato_id: contratoId, p_analista_id: seed.profileIdByKey.vend2, p_motivo: '   ' }),
    ['22023'],
  );
  await expectExplicitAuthorizationDenied(
    'un vendedor no marca contratos como prueba',
    sessions.vend1.client.rpc('marcar_contrato_demo',
      { p_contrato_id: contratoId, p_es_demo: true, p_motivo: 'no deberia' }),
    ['42501'],
  );
  await expectBlockedMutation(
    'gerencia no marca demo SIN motivo',
    gerencia.rpc('marcar_contrato_demo',
      { p_contrato_id: contratoId, p_es_demo: true, p_motivo: '' }),
    ['22023'],
  );

  // ── (D) El camino bueno, ida y vuelta, con su rastro ──────────────────────
  const atribAntes = await gerencia.schema('crm').rpc('atribucion_contrato_fn', { p_contrato_id: contratoId });
  const analistaOriginal = atribAntes.data?.analista_id ?? null;
  const destino = analistaOriginal === seed.profileIdByKey.vend2
    ? seed.profileIdByKey.vend1 : seed.profileIdByKey.vend2;

  const ida = await gerencia.rpc('reasignar_analista_contrato',
    { p_contrato_id: contratoId, p_analista_id: destino, p_motivo: 'GATE: ida del ensayo de atribucion' });
  if (ida.error) {
    fail(`gerencia reasigna con motivo: ${ida.error.message}`);
  } else {
    pass('gerencia reasigna con motivo');
    // El historial se ve CON motivo desde la autoridad.
    const atribDespues = await gerencia.schema('crm').rpc('atribucion_contrato_fn', { p_contrato_id: contratoId });
    const historial = atribDespues.data?.reasignaciones ?? [];
    if (Array.isArray(historial) && historial.length >= 1 && historial[0].motivo) {
      pass('el historial (con motivo) es visible para gerencia');
    } else {
      fail(`el historial no aparecio para gerencia: ${JSON.stringify(atribDespues.data)}`);
    }
    // Y NO desde un vendedor cualquiera que vea el contrato sin ser el analista
    // (hallazgo A3): si lo ve, el historial tiene que venir vacio.
    const atribVend = await sessions.vend1.client.schema('crm')
      .rpc('atribucion_contrato_fn', { p_contrato_id: contratoId });
    if (atribVend.error) {
      fail(`vend1 consulta la atribucion: ${atribVend.error.message}`);
    } else if (atribVend.data == null) {
      pass('vend1 fuera de ambito: la atribucion no revela nada (NULL)');
    } else if (atribVend.data.analista_id === seed.profileIdByKey.vend1
               || (atribVend.data.reasignaciones ?? []).length === 0) {
      pass('vend1 ve la ficha pero NO el historial con motivos (A3)');
    } else {
      fail('vend1 leyo el historial con motivos de otra persona (A3 roto)');
    }
    // Vuelta: el contrato queda como estaba y el rastro suma DOS actos.
    if (analistaOriginal) {
      const vuelta = await gerencia.rpc('reasignar_analista_contrato',
        { p_contrato_id: contratoId, p_analista_id: analistaOriginal, p_motivo: 'GATE: vuelta del ensayo de atribucion' });
      if (vuelta.error) fail(`la vuelta fallo y el contrato quedo movido: ${vuelta.error.message}`);
      else pass('la vuelta restaura al analista original');
    }
  }

  // ── (E) marcar demo: ida y vuelta con motivo, y que la ficha lo declare ───
  const marca = await gerencia.rpc('marcar_contrato_demo',
    { p_contrato_id: contratoId, p_es_demo: true, p_motivo: 'GATE: ensayo de la marca' });
  if (marca.error) {
    fail(`gerencia marca demo con motivo: ${marca.error.message}`);
  } else {
    const ficha = await gerencia.schema('crm').rpc('atribucion_contrato_fn', { p_contrato_id: contratoId });
    if (ficha.data?.es_demo === true) pass('la ficha declara es_demo tras la marca');
    else fail('la marca no se reflejo en la ficha');
    const desmarca = await gerencia.rpc('marcar_contrato_demo',
      { p_contrato_id: contratoId, p_es_demo: false, p_motivo: 'GATE: vuelta de la marca' });
    if (desmarca.error) fail(`la desmarca fallo y el contrato quedo como demo: ${desmarca.error.message}`);
    else pass('la desmarca restaura el contrato');
  }

  // ── (F) anon no ejecuta ninguna de las tres funciones nuevas ──────────────
  await expectExplicitAuthorizationDenied(
    'anon no consulta la atribucion',
    anon.schema('crm').rpc('atribucion_contrato_fn', { p_contrato_id: contratoId }),
    ['42501', 'PGRST202'],
  );
  await expectExplicitAuthorizationDenied(
    'anon no marca demos',
    anon.rpc('marcar_contrato_demo', { p_contrato_id: contratoId, p_es_demo: true, p_motivo: 'x' }),
    ['42501', 'PGRST202'],
  );
}

async function testCierreDeMes(sessions, seed) {
  console.log('\n— Cierre de mes: tablas selladas, ciclo y aviso —');
  void seed;
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-cierre'));

  // ¿Estan aplicadas las migraciones del cierre? Si no, se dice claro y se sale
  // sin contar fallos: un gate corrido sobre una base sin la migracion no esta
  // roto, esta midiendo otra cosa. Lo que NO puede pasar es que se salte en
  // silencio y alguien lea el verde como cobertura.
  const sonda = await sessions.gerencia.client.schema('crm').rpc('cierre_mes_estado_fn');
  if (sonda.error && String(sonda.error.code ?? '') === 'PGRST202') {
    console.log('  ⚠ OMITIDO: las migraciones del cierre de mes no estan aplicadas en esta base.');
    console.log('    (crm.cierre_mes_estado_fn no existe — aplicar 20260815* antes del gate)');
    return;
  }

  // ── (A) Las tres tablas no se leen NUNCA por la Data API ──────────────────
  // Ni siquiera gerencia. La foto de lo que se pago se sirve por funcion, que es
  // donde vive el recorte por ambito; una lectura directa lo saltaria entero.
  for (const tabla of TABLAS_CIERRE_MES) {
    for (const key of [...ROLES_CON_AVISO, ...ROLES_SIN_AVISO]) {
      if (!sessions[key]) continue;
      await expectExplicitAuthorizationDenied(
        `${key} no lee crm.${tabla} directamente`,
        sessions[key].client.schema('crm').from(tabla).select('*').limit(1),
        ['42501', 'PGRST205', 'PGRST202'],
      );
    }
    await expectExplicitAuthorizationDenied(
      `anon no lee crm.${tabla}`,
      anon.schema('crm').from(tabla).select('*').limit(1),
      ['42501', 'PGRST205', 'PGRST202'],
    );
  }

  // Y tampoco se escriben. Se prueba con GERENCIA, que es quien mas permisos
  // tiene: si el candado aguanta con ella, aguanta con todos.
  for (const tabla of TABLAS_CIERRE_MES) {
    // Cada tabla con una columna SUYA: con una inexistente el rechazo llega como
    // PGRST204 (cache de esquema) y eso no prueba nada sobre permisos.
    const filaMinima = tabla === 'ajustes_mes_cerrado'
      ? { periodo_origen: '2020-01-01' }
      : { periodo: '2020-01-01' };
    await expectBlockedMutation(
      `gerencia no inserta en crm.${tabla}`,
      sessions.gerencia.client.schema('crm').from(tabla).insert(filaMinima).select(),
      ['42501', 'PGRST205', 'PGRST202'],
    );
    await expectBlockedMutation(
      `gerencia no borra de crm.${tabla}`,
      sessions.gerencia.client.schema('crm').from(tabla).delete().eq('periodo', '2020-01-01').select(),
      ['42501', 'PGRST205', 'PGRST202', '42703'],
    );
  }

  // ── (B) El ciclo lo dispara el RELOJ, no una persona ──────────────────────
  // Tampoco gerencia: su puerta manual es `cerrar_periodo`, mes a mes. Con una
  // sesion real `auth.uid()` nunca es nulo, asi que el gate interno cierra a
  // todo el mundo — y eso es justo lo que hay que comprobar con sesiones y no
  // leyendo el cuerpo de la funcion.
  for (const key of [...ROLES_CON_AVISO, ...ROLES_SIN_AVISO]) {
    if (!sessions[key]) continue;
    await expectExplicitAuthorizationDenied(
      `${key} no dispara crm.ciclo_cierre_mes`,
      sessions[key].client.schema('crm').rpc('ciclo_cierre_mes'),
      ['42501', 'PGRST202'],
    );
  }
  await expectExplicitAuthorizationDenied(
    'anon no dispara crm.ciclo_cierre_mes',
    anon.schema('crm').rpc('ciclo_cierre_mes'),
    ['42501', 'PGRST202'],
  );

  // ── (C) Sellar un mes: solo gerencia (y aqui solo se prueba el NO) ────────
  // El mes que se pide es el pasado. Para los roles de abajo la funcion corta en
  // el gate ANTES de mirar el periodo, asi que la llamada no escribe nada.
  const hoy = new Date();
  const mesPasado = new Date(Date.UTC(hoy.getUTCFullYear(), hoy.getUTCMonth() - 1, 1))
    .toISOString().slice(0, 10);
  for (const key of ['vend1', 'sup1', 'coordinador', 'directorio', 'vendInactive', 'clientBank']) {
    if (!sessions[key]) continue;
    await expectExplicitAuthorizationDenied(
      `${key} no sella un mes con crm.cerrar_periodo`,
      sessions[key].client.schema('crm').rpc('cerrar_periodo', { p_periodo: mesPasado }),
      ['42501', 'PGRST202'],
    );
  }
  await expectExplicitAuthorizationDenied(
    'anon no sella un mes',
    anon.schema('crm').rpc('cerrar_periodo', { p_periodo: mesPasado }),
    ['42501', 'PGRST202'],
  );

  // ── (D) El aviso: quien lo ve, y que TODOS ven lo mismo ──────────────────
  // Es estado del reloj, no datos de nadie: si el payload cambiara segun el rol,
  // algo se habria colado por la puerta de atras. El coordinador entra a
  // proposito — `crm.cumplimiento_metas_fn` le deja ver un mes cerrado, asi que
  // negarle el aviso le dejaria el banner de la pantalla en error.
  let referencia = null;
  for (const key of ROLES_CON_AVISO) {
    if (!sessions[key]) continue;
    const { data, error } = await sessions[key].client.schema('crm').rpc('cierre_mes_estado_fn');
    if (!check(!error, `${key} lee crm.cierre_mes_estado_fn`, errorText(error))) continue;
    check(
      typeof data?.mes_en_curso?.cierra_el === 'string' && typeof data?.mes_en_curso?.mes === 'string',
      `${key} recibe el aviso del mes en curso con su fecha de cierre`,
      JSON.stringify(data?.mes_en_curso),
    );
    // El estado del pendiente, cuando lo hay, es vocabulario CERRADO: el front
    // lo declara como picklist y un valor de mas rompe la pantalla en silencio.
    if (data?.pendiente) {
      check(
        ['en_ventana', 'hoy', 'atascado'].includes(data.pendiente.estado),
        `${key}: el estado del mes pendiente esta en el vocabulario`,
        String(data.pendiente.estado),
      );
    }
    if (referencia === null) referencia = JSON.stringify([data?.mes_en_curso, data?.pendiente, data?.ultimo_cerrado]);
    else {
      check(
        JSON.stringify([data?.mes_en_curso, data?.pendiente, data?.ultimo_cerrado]) === referencia,
        `${key} ve el MISMO aviso que el primer rol (es estado de reloj, no datos)`,
      );
    }
  }

  for (const key of ROLES_SIN_AVISO) {
    if (!sessions[key]) continue;
    await expectExplicitAuthorizationDenied(
      `${key} no lee el estado del cierre de mes`,
      sessions[key].client.schema('crm').rpc('cierre_mes_estado_fn'),
      ['42501', 'PGRST202'],
    );
  }
  await expectExplicitAuthorizationDenied(
    'anon no lee el estado del cierre de mes',
    anon.schema('crm').rpc('cierre_mes_estado_fn'),
    ['42501', 'PGRST202'],
  );

  // ── (E) Publicar metas por debajo de un mes sellado ──────────────────────
  // Solo se puede aseverar si ya hay algun mes cerrado en esta base; si no, no
  // hay nada por debajo de lo que hablar y forzarlo exigiria sellar un mes, que
  // es justo lo que este gate no hace. Se dice en voz alta en vez de dar por
  // cubierto lo que no se midio.
  const estado = await sessions.gerencia.client.schema('crm').rpc('cierre_mes_estado_fn');
  const ultimoCerrado = estado.data?.ultimo_cerrado?.mes ?? null;
  if (!ultimoCerrado) {
    console.log('  ⚠ sin meses cerrados en esta base: no se puede medir el candado de metas retroactivas');
    console.log('    (cubierto en el oraculo test-cierre-mes.sql, bloque 13)');
  } else {
    await expectBlockedMutation(
      `gerencia no publica metas de un mes <= ${ultimoCerrado} (ya sellado)`,
      sessions.gerencia.client.schema('crm').rpc('publicar_metas_vendedores', {
        p_periodo: `${ultimoCerrado}-01`,
        p_expected_revision: 0,
        p_metas: {},
      }),
      ['22023', '42501', 'PGRST202'],
    );
  }
}

let verifiedSeed = null;

async function main() {
  let primaryError = null;
  const recoveryErrors = [];
  try {
    await cleanupTransientRows();
    verifiedSeed = await verifySeed();
    console.log('✓ precondicion: seed completo y coherente verificado con service_role');

    const sessions = Object.create(null);
    for (const key of Object.keys(EXPECTED_LEAD_NAMES)) {
      const session = await login(USER_BY_KEY[key]);
      if (session) sessions[key] = session;
    }

    const requiredSessions = Object.keys(EXPECTED_LEAD_NAMES);
    const missingSessions = requiredSessions.filter((key) => !sessions[key]);
    if (missingSessions.length > 0) {
      fail(`no se pueden completar las pruebas; faltan sesiones: ${missingSessions.join(', ')}`);
    } else {
      await readVisibilityMatrix(sessions, verifiedSeed);
      await testRecursiveHierarchy(sessions, verifiedSeed);
      await testCrossReads(sessions, verifiedSeed);
      await testLectorGlobalNoVeBorrados(sessions, verifiedSeed);
      await testWrites(sessions, verifiedSeed);
      await testReassignmentTrigger(sessions, verifiedSeed);
      await testTenencia(sessions, verifiedSeed);
      await testAvanceEtapa(sessions, verifiedSeed);
      await testTareaIsolation(sessions, verifiedSeed);
      await testTareaCloseRpc(sessions, verifiedSeed);
      await testAnularAutoriaYRetroceso(sessions, verifiedSeed);
      await testTareaFollowsLead(sessions, verifiedSeed);
      await testAgendaIcs(sessions, verifiedSeed);
      // Antes de la matriz de offboarding a propósito: ese bloque arrastra una
      // avería conocida post-8-ago y puede llevarse por delante lo que venga
      // detrás. El domicilio legal no puede depender de eso.
      await testDomicilioLegal(sessions, verifiedSeed);
      // Este gate nuevo también debe correr antes de la matriz de offboarding:
      // valida una superficie de escritura y no puede quedar oculto tras una
      // avería heredada de fixtures/configuración ajena a derivaciones.
      await testReporteDerivacionesEquipo(sessions, verifiedSeed);
      await testOffboardingMatrix(sessions, verifiedSeed);
      await testVentanaActividades(sessions, verifiedSeed);
      await testMetasVersionadas(sessions, verifiedSeed);
      await testMetricasServidor(sessions, verifiedSeed);
      await testMetricasConversionEquipo(sessions, verifiedSeed);
      await testCitasNucleo(sessions, verifiedSeed);
      await testMetricasConversionesGlobal(sessions);
      await testCarteraKeyset(sessions, verifiedSeed);
      await testReparto(sessions, verifiedSeed);
      await testDescarte(sessions, verifiedSeed);
      await testBankingBoundary(sessions, verifiedSeed);
      await testContractBankAccounts(sessions, verifiedSeed);
      await testAnon(verifiedSeed);
      // Cierres externos ANTES de la conversion: convierte un lead de vend1 que
      // la conversion absorbe en su LINEA BASE (sus aserciones son deltas).
      await testCierresExternos(sessions, verifiedSeed);
      await testIdentidadMultiempresa(sessions, verifiedSeed);
      // F2.b (b1 + b2) justo después: comparte bandera, vía fuera de banda y estilo.
      await testIdentidadF2b(sessions, verifiedSeed);
      await testIdentidadF2bB5(sessions);
      await testIdentidadF2bE4(sessions, verifiedSeed);
      await testIdentidadF2bD10(sessions);
      await testIdentidadF2bD13(sessions, verifiedSeed);
      await testIdentidadF2bD9();
      await testIdentidadF2bD3(sessions);
      await testIdentidadF2bD2(sessions);
      await testIdentidadF2bD4(sessions);
      await testIdentidadF2bD15(sessions, verifiedSeed);
      await testIdentidadF2bD5(sessions, verifiedSeed);
      await testIdentidadF2bD17yD18(sessions);
      await testIdentidadF2bD19(sessions);
      await testIdentidadF2bD20(sessions, verifiedSeed);
      await testRentabilidadR1(sessions, verifiedSeed);
      await testRentabilidadR2(sessions);
      await testRentabilidadR3(sessions, verifiedSeed);
      await testRentabilidadR4(sessions);
      // Va el ÚLTIMO a propósito: siembra dos leads que sobreviven visibles para
      // `directorio` (la rama del lector global de `leads_select` no lleva
      // predicado de `activo`), así que cualquier bloque posterior heredaría ese
      // estado. Limpia lo suyo en su propio `finally`.
      await testConversionMensual(sessions, verifiedSeed);
      await testCumplimientoMetas(sessions, verifiedSeed);
      await testCierreDeMes(sessions, verifiedSeed);
      await testAtribucionVentas(sessions, verifiedSeed);
      await testCapacidadUnificada(sessions, verifiedSeed);
      await testVentasNucleoF5c(sessions, verifiedSeed);
      await testAtribucionCadena(sessions);
      await testLentesAtribucion(sessions, verifiedSeed);
      await testF7Ola1(sessions);
      await testAltasNuevasPorAnalista(sessions, verifiedSeed);
      await testCapitalNucleo(sessions, verifiedSeed);
    }
  } catch (error) {
    primaryError = error;
  } finally {
    try {
      await cleanupTransientRows();
    } catch (error) {
      recoveryErrors.push(error);
    }
    if (verifiedSeed) {
      try {
        await restoreSeedIfNeeded(verifiedSeed);
      } catch (error) {
        recoveryErrors.push(error);
      }
    }
  }

  if (recoveryErrors.length > 0) {
    throw new AggregateError(
      primaryError ? [primaryError, ...recoveryErrors] : recoveryErrors,
      'La corrida y/o la restauracion segura de fixtures fallo.',
    );
  }
  if (primaryError) {
    throw primaryError;
  }

  if (failures === 0) {
    console.log(`\n✅ RLS OK — ${assertions} aserciones; gate aprobado`);
    return;
  }
  console.error(`\n❌ ${failures} de ${assertions} aserciones fallaron — NO mergear`);
  process.exitCode = 1;
}

main().catch((error) => {
  console.error(`✗ error fatal: ${error?.message ?? String(error)}`);
  if (error instanceof AggregateError) {
    for (const cause of error.errors) {
      console.error(`  - ${cause?.message ?? String(cause)}`);
    }
  }
  process.exitCode = 1;
});
