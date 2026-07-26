// Gate RLS del CRM con sesiones reales y anon key.
// Requiere el seed determinista de seed-demo.mjs y corre solo en branch/staging.
// La service_role se usa EXCLUSIVAMENTE para validar/limpiar fixtures; todas las
// aserciones de permisos se ejecutan con sesiones de usuario o como anon.

import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import {
  BANK_CLIENT,
  BANK_CONTRACT,
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
cruzadas, inmutabilidad, usuario inactivo, directorio de solo lectura, acceso
anonimo, la agenda de tareas (tenencia derivada del lead, cierre solo por RPC),
las metas del mes (crm.objetivos: todos leen, solo gerencia escribe via RPC)
y ausencia de acceso bancario/contratos crudos desde los roles CRM.
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
  console.log(`✓ fixtures: ${LEADS.length} leads, ${LEADS.length} actividades, ${TAREAS.length} tareas, 1 usuario inactivo`);
  console.log('✓ fixtures: 1 cliente bancario + 1 contrato sensible');
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
      TRANSIENT_IDS.directoryTarea,
      TRANSIENT_IDS.portalClientTarea,
      TRANSIENT_IDS.rpcCloseTarea,
      TRANSIENT_IDS.taskFollowTarea,
      TRANSIENT_IDS.repartoTareaReencolada,
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
      TRANSIENT_IDS.taskFollowLead,
      TRANSIENT_IDS.repartoLeadOk,
      TRANSIENT_IDS.repartoLeadNoContactar,
      TRANSIENT_IDS.repartoLeadCarrera,
      TRANSIENT_IDS.repartoLeadReencolado,
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
  // Metas sentinela de testObjetivos: periodo 2099-12 jamas es real; el DELETE
  // de service_role existe justo para esta limpieza de fixtures.
  await requireAdmin(
    'borrar metas transitorias del periodo sentinela',
    admin.schema('crm').from('objetivos').delete().eq('periodo', PERIODO_OBJETIVOS_GATE),
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
    'asesor del cliente bancario no coincide');
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

  return {
    activities: activitiesResponse.data,
    activityById,
    contract: contractResponse.data,
    leadByName,
    leads: leadsResponse.data,
    profileIdByKey,
    profiles: profilesResponse.data,
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

async function restoreSeedIfNeeded(seed) {
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
    const ownedLead = seed.leadByName.get('LEAD DE VENDEDOR INACTIVO DEMO');
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
      'sup1 ve supervisor hijo y vendedor nieto por recursion');
  }

  const nestedTeam = await positive(
    'supervisor anidado consulta su rama',
    sessions.sup1Nested.client.schema('crm').from('equipo')
      .select('perfil_id', { count: 'exact' })
      .in('perfil_id', [nestedSupervisorId, nestedSellerId]),
  );
  if (nestedTeam) {
    check(nestedTeam.count === 2 && nestedTeam.data.length === 2,
      'supervisor anidado ve su propia fila y su vendedor');
  }

  const recursiveLead = await positive(
    'sup1 consulta el lead de su vendedor nieto',
    sessions.sup1.client.schema('crm').from('leads')
      .select('id, vendedor_id')
      .eq('id', carlos.id)
      .single(),
  );
  if (recursiveLead) {
    check(recursiveLead.data.vendedor_id === nestedSellerId,
      'lead recursivo pertenece al vendedor anidado');
  }

  await expectHidden(
    'vend1 no ve al vendedor de la rama anidada hermana',
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
    'vend3 no lee el lead de otro vendedor',
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

async function testWrites(sessions, seed) {
  console.log('\n— Escrituras cruzadas y privilegios bloqueados —');
  const juan = seed.leadByName.get('JUAN PEREZ DEMO');
  const maria = seed.leadByName.get('MARIA LOPEZ DEMO');
  const ana = seed.leadByName.get('ANA TORRES DEMO');
  const vend1Id = seed.profileIdByKey.vend1;
  const vend3Id = seed.profileIdByKey.vend3;

  await expectBlockedMutation(
    'vend1 no reasigna su lead a otro vendedor',
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
      // Tenencia valida: debe fallar por vendedor ajeno, no por enviar ambos
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

  const assignedInsert = await positive(
    'sup1 crea un lead que nace asignado',
    sup1.client.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.triggerAssignedInsertLead,
      nombre_completo: 'TRIGGER INSERT ASIGNADO TRANSIENT',
      telefono: '999000006',
      vendedor_id: vend1Id,
    }).select('id').single(),
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
    'crear fixture transitorio para cambio de vendedor',
    admin.schema('crm').from('leads').insert({
      ...common,
      id: TRANSIENT_IDS.triggerSellerChangeLead,
      nombre_completo: 'TRIGGER CAMBIO VENDEDOR TRANSIENT',
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
      'leer actividad del cambio de vendedor',
    );
    const [activity] = activities.rows;
    check(activities.count === 1,
      'cambio de vendedor emite exactamente una reasignacion',
      `emitio ${activities.count}`);
    check(activity?.detalle === `${USER_BY_KEY.vend1.name} → ${USER_BY_KEY.vend2.name}`,
      'reasignacion conserva el detalle humano exacto',
      `detalle=${activity?.detalle ?? 'ausente'}`);
    check(activity?.metadata?.vendedor_anterior === vend1Id
        && activity?.metadata?.vendedor_nuevo === vend2Id,
    'reasignacion conserva vendedor anterior y nuevo en metadata');
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
 * El reloj del vendedor — crm.leads.tenencia_desde (pedido de Miguel 2026-07-24).
 *
 * Complementa al oraculo SQL (test-tenencia.sql) por la via PostgREST REAL, que
 * es la unica que recorre grants por columna + RLS + trigger juntos. Prueba lo
 * que de verdad importa en produccion: que el asesor LEA su reloj, que NO pueda
 * falsificarlo (el ACL de crm.leads es de TABLA, asi que PostgREST acepta la
 * columna en el body: la defensa es el trigger, no un 403) y que una asignacion
 * de hoy sobre un lead viejo arranque el reloj HOY.
 */
async function testTenencia(sessions, seed) {
  console.log('\n— El reloj del vendedor: tenencia_desde —');
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
  // paso dias en la cola de Rosa antes de que alguien lo bajara a un asesor).
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
    'un lead parkeado en bandeja NO tiene reloj de asesor',
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
    'asignar a un vendedor enciende el reloj de tenencia',
    `tenencia_desde=${relojAsignacion ?? 'null'}`);
  check(relojAsignacion != null
    && Date.parse(relojAsignacion) >= antesDeAsignar - 60_000,
    'el reloj arranca en la ASIGNACION, no cuando entro el lead',
    `tenencia_desde=${relojAsignacion} creado_en=${asignado?.data?.creado_en}`);

  // ── El asesor LEE su propio reloj (grant por columna + RLS).
  const leidoPorDuenio = await positive(
    'vend1 lee el reloj de su propio lead',
    vend1.client.schema('crm').from('leads')
      .select('id, tenencia_desde')
      .eq('id', TRANSIENT_IDS.tenenciaLeadViejo)
      .maybeSingle(),
  );
  check(leidoPorDuenio?.data?.tenencia_desde != null,
    'el vendedor recibe tenencia_desde de su lead (sin grant, PostgREST la omitiria en silencio)',
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
    'un vendedor NO puede falsificar su propio reloj (lo reimpone el trigger)',
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
    'un vendedor de otro equipo no ve el lead ajeno ni su reloj',
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

  // ── El caso de Miguel, END TO END y con una sesion REAL de vendedor: el
  // asesor registra que SI hablo con la persona y la etapa sube sola.
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
  // historial no le atribuya al vendedor un movimiento que el no pidio.
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
  await expectBlockedMutation(
    'sup1 intenta agendar una reunion sobre un lead de la cola global que NO puede ver',
    sup1.client.schema('crm').from('tareas').insert({
      lead_id: TRANSIENT_IDS.avanceLeadColaGlobal,
      tipo: 'reunion',
      titulo: 'GATE reunion cola global',
      vence_en: new Date(Date.now() + 2 * 86_400_000).toISOString(),
      creado_por: sup1Id,
    }),
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

  // La SEGUNDA capa, aislada: con las llaves de service_role se fabrica la
  // tarea que la policy ya no deja crear (service_role no pasa por RLS), para
  // comprobar que el gate del TRIGGER la frena igual. Sin esto, tapar la policy
  // habria dejado el gate del trigger sin cobertura y nadie lo notaria el dia
  // que alguien reabra la policy.
  await requireAdmin(
    'fabricar por service_role la reunion sobre el lead de la cola global',
    admin.schema('crm').from('tareas').insert({
      lead_id: TRANSIENT_IDS.avanceLeadColaGlobal,
      tipo: 'reunion',
      titulo: 'GATE reunion cola global (service_role)',
      vence_en: new Date(Date.now() + 2 * 86_400_000).toISOString(),
      creado_por: sup1Id,
    }),
  );
  const trasFabricada = await positive(
    'releer la etapa tras la tarea fabricada saltandose la policy',
    admin.schema('crm').from('leads')
      .select('id, etapa')
      .eq('id', TRANSIENT_IDS.avanceLeadColaGlobal)
      .single(),
  );
  check(trasFabricada?.data?.etapa === 'nuevo',
    'DEFENSA EN PROFUNDIDAD: ni saltandose la policy asciende un lead sin dueno',
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

  // Completar va SOLO por la RPC: el trigger corta el UPDATE directo (P0001).
  await expectBlockedMutation(
    'vend1 no completa su tarea por UPDATE directo',
    sessions.vend1.client.schema('crm').from('tareas')
      .update({ estado: 'completada' }, { count: 'exact' })
      .eq('id', llamadaJuan.id)
      .select('id'),
    ['P0001'],
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

  // Cerrada => inmutable: nadie la reabre por UPDATE directo (trigger P0001).
  await expectBlockedMutation(
    'vend1 no reabre una tarea cerrada',
    vend1.client.schema('crm').from('tareas')
      .update({ estado: 'pendiente' }, { count: 'exact' })
      .eq('id', TRANSIENT_IDS.rpcCloseTarea)
      .select('id'),
    ['P0001'],
  );
  // Restauracion: ver cleanupTransientRows — la tarea cerrada y su actividad de
  // resultado QUEDAN (log INSERT-only; borrar la actividad es imposible porque
  // el SET NULL de la FK dispara el trigger de inmutabilidad de la cerrada).
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
    'la tarea pendiente siguio al nuevo vendedor',
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
    'sup1 no ve el token de su vendedor',
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
}

// Periodo sentinela de las metas del gate: valido para el CHECK (< 2100) pero
// imposible como mes real de operacion — la limpieza borra exactamente esto.
const PERIODO_OBJETIVOS_GATE = '2099-12-01';

async function testObjetivos(sessions) {
  console.log('\n— Metas del mes (crm.objetivos): todos leen, solo gerencia escribe —');
  const gerencia = sessions.gerencia.client;
  const vend1 = sessions.vend1.client;
  const sup1 = sessions.sup1.client;
  const directorio = sessions.directorio.client;

  const fijadas = await positive(
    'gerencia fija las metas del periodo sentinela (RPC fijar_objetivos)',
    gerencia.schema('crm').rpc('fijar_objetivos', {
      p_periodo: PERIODO_OBJETIVOS_GATE,
      p_objetivos: {
        vendedor: { capital_objetivo: 250000, ventas_objetivo: 3, conversion_objetivo: 25 },
        supervisor: { capital_objetivo: 500000, ventas_objetivo: 6, conversion_objetivo: 25 },
        gerencia: { capital_objetivo: 1000000, ventas_objetivo: 12, conversion_objetivo: 28 },
      },
    }),
  );
  if (fijadas) {
    check(Array.isArray(fijadas.data) && fijadas.data.length === 3,
      'la RPC devolvio las 3 filas del periodo',
      `devolvio ${Array.isArray(fijadas.data) ? fijadas.data.length : 'no-array'}`);
  }

  // Lectura: TODO el arbol comercial y el lector global ven las mismas metas.
  for (const [key, client] of [['vend1', vend1], ['sup1', sup1], ['directorio', directorio]]) {
    const lectura = await positive(
      `${key} lee las metas del periodo`,
      client.schema('crm').from('objetivos')
        .select('rol, capital_objetivo')
        .eq('periodo', PERIODO_OBJETIVOS_GATE),
    );
    if (lectura) {
      check(lectura.data.length === 3,
        `${key} ve las 3 metas del periodo`,
        `vio ${lectura.data.length}`);
    }
  }

  // Un miembro desactivado no resuelve rol → 0 filas (fail-closed).
  if (sessions.vendInactive) {
    await expectHidden(
      'usuario inactivo no lee las metas',
      sessions.vendInactive.client.schema('crm').from('objetivos')
        .select('id').eq('periodo', PERIODO_OBJETIVOS_GATE),
    );
  }

  // Escritura via RPC: bloqueada para todos menos gerencia (42501 del gate).
  for (const [key, client] of [['vend1', vend1], ['sup1', sup1], ['directorio', directorio]]) {
    await expectBlockedMutation(
      `${key} no puede fijar metas por la RPC`,
      client.schema('crm').rpc('fijar_objetivos', {
        p_periodo: PERIODO_OBJETIVOS_GATE,
        p_objetivos: { vendedor: { capital_objetivo: 1 } },
      }),
      ['42501'],
    );
  }

  // Escritura DIRECTA: sin policies ni grants — ni siquiera gerencia.
  await expectBlockedMutation(
    'gerencia no puede insertar directo en objetivos (solo RPC)',
    gerencia.schema('crm').from('objetivos')
      .insert({ periodo: PERIODO_OBJETIVOS_GATE, rol: 'vendedor' })
      .select('id'),
  );
  await expectBlockedMutation(
    'vend1 no puede actualizar metas directo',
    vend1.schema('crm').from('objetivos')
      .update({ ventas_objetivo: 99 })
      .eq('periodo', PERIODO_OBJETIVOS_GATE)
      .select('id'),
  );
  await expectBlockedMutation(
    'gerencia no puede borrar metas (sin DELETE en el API)',
    gerencia.schema('crm').from('objetivos')
      .delete().eq('periodo', PERIODO_OBJETIVOS_GATE).select('id'),
  );

  // La validacion del servidor viaja como 22023 (parametro invalido).
  await expectBlockedMutation(
    'la RPC rechaza un periodo que no es primer dia de mes',
    gerencia.schema('crm').rpc('fijar_objetivos', {
      p_periodo: '2099-12-15',
      p_objetivos: { vendedor: { capital_objetivo: 1 } },
    }),
    ['22023'],
  );

  // Upsert parcial: cambia SOLO el vendedor; la meta de la empresa no se pisa.
  const refijadas = await positive(
    'gerencia re-fija la meta del vendedor (upsert parcial)',
    gerencia.schema('crm').rpc('fijar_objetivos', {
      p_periodo: PERIODO_OBJETIVOS_GATE,
      p_objetivos: { vendedor: { capital_objetivo: 300000, ventas_objetivo: 4, conversion_objetivo: 30 } },
    }),
  );
  if (refijadas) {
    const filaVendedor = (refijadas.data ?? []).find((row) => row.rol === 'vendedor');
    const filaEmpresa = (refijadas.data ?? []).find((row) => row.rol === 'gerencia');
    check(Number(filaVendedor?.capital_objetivo) === 300000,
      'el upsert parcial actualizo la meta del vendedor');
    check(Number(filaEmpresa?.capital_objetivo) === 1000000,
      'el upsert parcial no piso la meta de la empresa');
  }
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
  await expectHidden(
    'coordinador no ve las metas del mes (crm.objetivos)',
    coordinador.schema('crm').from('objetivos').select('id'),
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
  // constancia de que el rol nuevo tampoco entra por ahi.
  for (const fn of ['metricas_distribucion_leads_fn', 'metricas_distribucion_leads_v2_fn']) {
    await expectBlockedMutation(
      `coordinador no lee las metricas de distribucion (${fn})`,
      coordinador.schema('crm').rpc(fn, { p_desde: '2026-07-01', p_hasta: '2026-07-15' }),
      ['42501'],
    );
  }
  // Las 4 RPC de metricas comerciales recortan por vendedor_ids_visibles (∅ para
  // el coordinador) o exigen gerencia/lector: ninguna le devuelve filas.
  for (const [fn, args] of [
    ['metricas_capital_mes_fn', { p_meses: 12 }],
    ['metricas_pagos_mes_fn', { p_meses: 12 }],
    ['metricas_altas_analista_fn', { p_meses: 12 }],
    ['metricas_vencimientos_fn', { p_dias: 90 }],
  ]) {
    await expectHidden(
      `coordinador no obtiene filas de ${fn}`,
      coordinador.schema('crm').rpc(fn, args),
    );
  }

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
    'coordinador no se auto-inserta un lead (vendedor = el mismo)',
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
        ...colaComun, id: TRANSIENT_IDS.repartoLeadReencolado, monto_estimado: 5000,
        nombre_completo: 'REPARTO REENCOLADO TRANSIENT', telefono: '999000113',
      },
    ]),
  );
  // Camino real no cubierto antes: un lead devuelto a la cola por gerencia
  // conserva tareas pendientes; al repartirlo deben SEGUIR al lead a la bandeja.
  await requireAdmin(
    'sembrar la tarea pendiente del lead re-encolado',
    admin.schema('crm').from('tareas').insert({
      creado_por: sup1Id,
      id: TRANSIENT_IDS.repartoTareaReencolada,
      lead_id: TRANSIENT_IDS.repartoLeadReencolado,
      tipo: 'tarea',
      titulo: 'REPARTO TAREA REENCOLADA TRANSIENT',
      vence_en: '2026-08-05T15:00:00Z',
    }),
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
    'carrera: quedo UN solo supervisor asignado y ningun vendedor');

  // sync_tareas: la pendiente del lead re-encolado sigue al lead a la bandeja.
  await positive(
    'coordinador reparte el lead re-encolado (con tarea pendiente)',
    coordinador.schema('crm').rpc('repartir_lead', {
      p_lead: TRANSIENT_IDS.repartoLeadReencolado,
      p_supervisor: sup1Id,
    }),
  );
  const tarea = await requireAdmin(
    'releer la tarea del lead re-encolado',
    admin.schema('crm').from('tareas')
      .select('asignado_supervisor_id, vendedor_id, estado')
      .eq('id', TRANSIENT_IDS.repartoTareaReencolada).single(),
  );
  check(tarea.data?.asignado_supervisor_id === sup1Id
    && tarea.data?.vendedor_id === null
    && tarea.data?.estado === 'pendiente',
    'la tarea pendiente siguio al lead hasta la bandeja, sin bloquearse',
    JSON.stringify(tarea.data));
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

  // (A) Gate de rol de las 2 RPC nuevas: fuera vendedor, supervisor y directorio.
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
  await expectHidden(
    'anon no lee crm.objetivos',
    anon.schema('crm').from('objetivos').select('id').limit(1),
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
  await expectHidden(
    'anon no lee datos bancarios public.perfiles',
    anon.from('perfiles').select('id, banco, numero_cuenta, cci').eq('id', bankProfileId),
  );
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
      await testWrites(sessions, verifiedSeed);
      await testReassignmentTrigger(sessions, verifiedSeed);
      await testTenencia(sessions, verifiedSeed);
      await testAvanceEtapa(sessions, verifiedSeed);
      await testTareaIsolation(sessions, verifiedSeed);
      await testTareaCloseRpc(sessions, verifiedSeed);
      await testTareaFollowsLead(sessions, verifiedSeed);
      await testAgendaIcs(sessions, verifiedSeed);
      await testObjetivos(sessions);
      await testReparto(sessions, verifiedSeed);
      await testDescarte(sessions, verifiedSeed);
      await testBankingBoundary(sessions, verifiedSeed);
      await testAnon(verifiedSeed);
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
