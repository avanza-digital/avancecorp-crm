// Gate RLS del CRM con sesiones reales y anon key.
// Requiere el seed determinista de seed-demo.mjs y corre solo en branch/staging.
// La service_role se usa EXCLUSIVAMENTE para validar/limpiar fixtures; todas las
// aserciones de permisos se ejecutan con sesiones de usuario o como anon.

import { createClient } from '@supabase/supabase-js';
import {
  BANK_CLIENT,
  BANK_CONTRACT,
  EXPECTED_LEAD_NAMES,
  LEADS,
  PRODUCTION_PROJECT_REF,
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
anonimo y ausencia de acceso bancario/contratos crudos desde los roles CRM.
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
    console.log(`  - ${key}: ${names.length} leads`);
  }
  console.log(`✓ fixtures: ${LEADS.length} leads, ${LEADS.length} actividades, 1 usuario inactivo`);
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
  await requireAdmin(
    'limpiar actividades transitorias',
    admin.schema('crm').from('actividades').delete().in('id', [
      TRANSIENT_IDS.directoryActivity,
      TRANSIENT_IDS.crossTeamActivity,
    ]),
  );
  await requireAdmin(
    'limpiar leads transitorios',
    admin.schema('crm').from('leads').delete().in('id', [
      TRANSIENT_IDS.directoryLead,
      TRANSIENT_IDS.crossTeamLead,
      TRANSIENT_IDS.portalClientLead,
    ]),
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
  const sup2Id = seed.profileIdByKey.sup2;

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
      asignado_supervisor_id: sup2Id,
      creado_por: sessions.sup1.user.id,
      etapa: 'nuevo',
      id: TRANSIENT_IDS.crossTeamLead,
      moneda: 'PEN',
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
      nombre_completo: 'RLS DIRECTORIO TRANSIENT',
      origen: 'otro',
      telefono: '999000001',
      vendedor_id: null,
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
      nombre_completo: 'RLS CLIENTE TRANSIENT',
      origen: 'otro',
      telefono: '999000003',
      vendedor_id: null,
    }).select('id'),
  );
}

async function testBankingBoundary(sessions, seed) {
  console.log('\n— Frontera portal/CRM y datos bancarios —');
  const vend1 = sessions.vend1.client;
  const bankProfileId = seed.profileIdByKey[BANK_CLIENT.key];
  const vend1ProfileId = seed.profileIdByKey.vend1;

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

  const bankProjection = [
    'id', 'banco', 'numero_cuenta', 'tipo_cuenta', 'cci',
    'beneficiario_nombre', 'beneficiario_dni',
    'banco_usd', 'numero_cuenta_usd', 'tipo_cuenta_usd', 'cci_usd',
    'beneficiario_nombre_usd', 'beneficiario_dni_usd',
  ].join(', ');

  await expectHidden(
    'rol CRM no lee columnas bancarias de su propio public.perfiles',
    vend1.from('perfiles').select(bankProjection).eq('id', vend1ProfileId),
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
