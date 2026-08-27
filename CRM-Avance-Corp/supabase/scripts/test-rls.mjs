// Gate RLS del CRM con sesiones reales y anon key.
// Requiere el seed determinista de seed-demo.mjs y corre solo en branch/staging.
// La service_role se usa EXCLUSIVAMENTE para validar/limpiar fixtures; todas las
// aserciones de permisos se ejecutan con sesiones de usuario o como anon.

import { randomUUID } from 'node:crypto';
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

  // Desde la creación atómica (20260804165440, en prod 2026-08-04) el INSERT
  // directo sobre crm.leads está revocado para authenticated: los leads nacen
  // SOLO por crm.crear_lead_si_disponible. La sonda usa la vía legal — mismo
  // lead transitorio, mismo vendedor destino — y el trigger de reasignación
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
// cancela el asesor" y "si se anula la reu y no se reagenda una en ese mismo
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
  //    RPC: un vendedor podia vaciar su agenda por /rest/v1/tareas SIN quedar
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

  // 2) LA ETIQUETA NO SE PUEDE INYECTAR: escribirla suelta en el payload es un
  //    no-op silencioso (el BEFORE trigger la reescribe desde old).
  const forjada = await positive(
    'vend1 intenta escribir cancelada_por="sistema" en una tarea viva',
    vend1.client.schema('crm').from('tareas')
      .update({ cancelada_por: 'sistema' })
      .eq('id', TRANSIENT_IDS.anularTareaReunion)
      .select('id, estado, cancelada_por')
      .single(),
  );
  if (forjada) {
    check(forjada.data.cancelada_por === null && forjada.data.estado === 'pendiente',
      'la etiqueta inyectada por el cliente se ignora (sigue null y pendiente)',
      `cancelada_por=${forjada.data.cancelada_por}`);
  }

  // 2b) LA FIRMA TAMPOCO (20260727032429). Mismo contrato que la etiqueta: un
  //     no-op SILENCIOSO, no un 400 de constraint — el CHECK tambien la
  //     atraparia, pero el cliente debe ver "campo ignorado" como en el resto de
  //     columnas selladas. Se intenta firmar como sup1: si colara, un vendedor
  //     podria marcar sus propias anulaciones como si se las hubiera ordenado su
  //     jefe y sacarlas del denominador de su %.
  const firmaForjada = await positive(
    'vend1 intenta firmar una tarea viva como si la hubiera anulado sup1',
    vend1.client.schema('crm').from('tareas')
      .update({ cancelada_por_id: sup1Id })
      .eq('id', TRANSIENT_IDS.anularTareaReunion)
      .select('id, estado, cancelada_por_id')
      .single(),
  );
  if (firmaForjada) {
    check(firmaForjada.data.cancelada_por_id === null && firmaForjada.data.estado === 'pendiente',
      'la firma inyectada por el cliente se ignora (sigue null y pendiente)',
      `cancelada_por_id=${firmaForjada.data.cancelada_por_id}`);
  }

  // 3) Por la RPC si, y queda firmada como ASESOR.
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
    'la anulacion quedo firmada por el ASESOR',
    `cancelada_por=${filaAnulada.data.cancelada_por}`);
  // 20260727032429: y la firma es EL PROPIO vendedor, o sea PROPIA — la unica
  // clase de anulacion que sigue pesando en su % de cumplimiento.
  check(filaAnulada.data.cancelada_por_id === vend1Id,
    'la firma es el vendedor que la ordeno (anulacion PROPIA: cuenta en su %)',
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
  //    cerrar bien un lead le bajara la nota al vendedor.
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
      'la cancelacion automatica quedo firmada por el SISTEMA, no por el asesor',
      `cancelada_por=${filaSistema.data.cancelada_por}`);
    // 20260727032429: sin persona no hay firma. Si aqui quedara un uuid, el
    // CHECK tareas_cancelada_por_id_valida ni siquiera habria dejado escribir.
    check(filaSistema.data.cancelada_por_id === null,
      'una cancelacion de SISTEMA no lleva firma: no hay a quien atribuirla',
      `cancelada_por_id=${filaSistema.data.cancelada_por_id}`);
  }

  // 7) EL CASO QUE MOTIVA 20260727032429: el SUPERVISOR anula la tarea de su
  //    vendedor. La fila se sigue agrupando por vendedor_id (como el resto de
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
      'sup1 anula por la RPC una tarea de SU vendedor',
      sessions.sup1.client.schema('crm').rpc('cerrar_tarea', {
        p_estado: 'cancelada',
        p_resultado_detalle: null,
        p_resultado_tipo: null,
        p_tarea_id: TRANSIENT_IDS.anularTareaAjena,
      }),
    );
    const filaAjena = await leerTarea(TRANSIENT_IDS.anularTareaAjena, 'releer la tarea anulada por el jefe');
    check(filaAjena.data.estado === 'cancelada' && filaAjena.data.cancelada_por === 'asesor',
      'anular siendo supervisor tambien es una PERSONA: etiqueta asesor',
      `cancelada_por=${filaAjena.data.cancelada_por}`);
    check(filaAjena.data.cancelada_por_id === sup1Id,
      'la firma es el SUPERVISOR que la ordeno, no el vendedor',
      `cancelada_por_id=${filaAjena.data.cancelada_por_id}`);
    check(filaAjena.data.cancelada_por_id !== filaAjena.data.vendedor_id,
      'firma != dueño de la tarea: la metrica la clasifica como AJENA y la saca del % del vendedor',
      `firma=${filaAjena.data.cancelada_por_id} dueño=${filaAjena.data.vendedor_id}`);
  }

  // 8) INVARIANTE DE TODO EL MECANISMO (B1 de la auditoria): ninguna anulacion
  //    humana puede quedarse SIN firma. Si alguna lo hiciera, la metrica la
  //    mandaria a "ajena" en silencio y desapareceria del denominador de todos.
  //    El CHECK la permite a proposito (historia inatribuible del backfill), asi
  //    que la garantia para las filas NUEVAS tiene que vivir aqui, en el gate.
  const huerfanas = await requireAdmin(
    'buscar anulaciones de asesor sin firma',
    admin.schema('crm').from('tareas')
      .select('id')
      .eq('cancelada_por', 'asesor')
      .is('cancelada_por_id', null),
  );
  if (huerfanas) {
    check(huerfanas.data.length === 0,
      'ninguna anulacion de asesor quedo sin firma (si no, saldria del % de todos en silencio)',
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
    'el vendedor de la cartera ve que falta el domicilio',
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
    'el supervisor del árbol del vendedor también alcanza al cliente',
    leer(sessions.sup1.client),
  );
  await positive(
    'gerencia alcanza a cualquier cliente activo',
    leer(sessions.gerencia.client),
  );

  // ── Quién NO alcanza ──────────────────────────────────────────────────────
  const ajeno = await expectExpectedFailure(
    'un vendedor de OTRO subárbol no lee los datos legales',
    leer(sessions.vend3.client),
    ['42501', 'P0001'],
    /fuera de tu cartera/i,
  );
  await expectExpectedFailure(
    'un vendedor de OTRO subárbol tampoco escribe el domicilio',
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
    'el normalizador NO es superficie pública ni para un vendedor autorizado',
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
    'el vendedor rellena el domicilio vacío de SU cliente',
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
  const ownedLead = seed.leadByName.get('LEAD DE VENDEDOR INACTIVO DEMO');
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

  async function setState({ portalActive, crmActive, portalRole = originalProfile.rol }) {
    const updateProfile = () => requireAdmin(
      `P04: fijar perfil activo=${portalActive}, rol=${portalRole}`,
      admin.from('perfiles')
        .update({ activo: portalActive, rol: portalRole })
        .eq('id', memberId),
    );
    const updateTeam = () => requireAdmin(
      `P04: fijar equipo activo=${crmActive}`,
      admin.schema('crm').from('equipo')
        .update({ activo: crmActive })
        .eq('perfil_id', memberId),
    );

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

  async function assertAccess(client, expectedState, label, expectedId, expectedRole = undefined) {
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
    }
  }

  async function assertDenied(label) {
    await assertAccess(
      member.client,
      'revocado',
      `${label}: auth canónica no aplica fallback`,
      memberId,
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
      'F1 lead libre: el vendedor NO edita las perillas',
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
      'F1 lead libre: el log anti-pesca es invisible para el vendedor (aunque él generó filas)',
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
        'F1 lead libre: la RPC del vendedor dejó su rastro (quién y veredicto)',
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
    // Solo vendedores toman, y para sí mismos; supervisión asigna por reparto.
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
    // vendedor rebota (RLS + veto sin flag: la válvula solo vive dentro de la
    // RPC) y acto seguido la RPC sí la toma.
    await expectBlockedMutation(
      'F2 lead libre: el vendedor NO se auto-asigna la bolsa por PATCH directo',
      member.client.schema('crm').from('leads')
        .update({ vendedor_id: memberId })
        .eq('id', bolsaTransientId)
        .select('id'),
    );
    const tomaBolsa = await positive(
      'F2 lead libre: el vendedor TOMA la bolsa',
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
        'F2 lead libre: la fila tomada quedó del vendedor',
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
      'F3 lead libre: el vendedor crea su recordatorio (teléfono tecleado a lo humano)',
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
      'F3 lead libre: el supervisor no crea recordatorios (la antesala de tomar es del vendedor)',
      sessions.sup1.client.schema('crm').from('recordatorios_disponibilidad')
        .insert({
          telefono: '+51996600324',
          recordar_en: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
        })
        .select('id'),
    );
    if (recordatorioCreado?.data?.id) {
      // El ARQUETIPO del owner-only (auditor M1): otro VENDEDOR — mismo rol,
      // pasa el gate de rol y debe morir por el predicado perfil_id. Gerencia
      // y supervisor caen por rol; sin este par, mutar el predicado owner
      // dejando el gate de rol pasaría la matriz en verde.
      await expectHidden(
        'F3 lead libre: OTRO vendedor no ve el recordatorio ajeno (predicado owner)',
        sessions.vend1.client.schema('crm').from('recordatorios_disponibilidad')
          .select('id')
          .eq('id', recordatorioCreado.data.id),
      );
      await expectBlockedMutation(
        'F3 lead libre: otro vendedor no reprograma el ajeno',
        sessions.vend1.client.schema('crm').from('recordatorios_disponibilidad')
          .update({ recordar_en: new Date(Date.now() + 20 * 24 * 3600 * 1000).toISOString() })
          .eq('id', recordatorioCreado.data.id)
          .select('id'),
      );
      await expectBlockedMutation(
        'F3 lead libre: otro vendedor no borra el ajeno',
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
        'F4 sin ruido: el VENDEDOR no escribe en el libro (gate de rol)',
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
          'F4 sin ruido: el vendedor no lee el libro (gate de rol)',
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
          'F4.2 vigentes: el vendedor tampoco ve nada por la vista',
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
        // La vista es auto-actualizable para Postgres: el DML a través de
        // ella queda pinneado como DENEGADO (auditor F4.2 #5) — sin grant
        // de escritura sobre la vista, ni siquiera para el dueño.
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
        );
        await expectBlockedMutation(
          'F4.2 vigentes: ni el dueño EDITA a través de la vista',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .update({ severidad: 'atencion' })
            .eq('id', f4Reconocido.data.id)
            .select('id'),
        );
        await expectBlockedMutation(
          'F4.2 vigentes: ni el dueño BORRA a través de la vista',
          sessions.sup1.client.schema('crm').from('alertas_reconocimientos_vigentes')
            .delete()
            .eq('id', f4Reconocido.data.id)
            .select('id'),
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

    // Un rol global del portal no se SUMA a una membresía CRM activa: el rol
    // CRM manda y conserva su ámbito. El fallback solo existe sin fila equipo.
    await setState({ portalActive: true, crmActive: true, portalRole: 'directorio' });
    await assertAccess(
      member.client,
      'miembro',
      'P04 miembro + rol global: auth conserva la membresía CRM',
      memberId,
      originalTeam.rol_crm,
    );
    const scopedMember = await positive(
      'P04 miembro + rol global: consulta leads sin elevar ámbito',
      member.client.schema('crm').from('leads').select('nombre_completo'),
    );
    if (scopedMember) {
      const actualNames = scopedMember.data.map((row) => row.nombre_completo);
      check(sameStrings(actualNames, [ownedLead.nombre_completo]),
        'P04 miembro + rol global: ve exactamente su cartera CRM',
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

    // Revocar corta primero CRM. Para habilitar ambos, primero vive el perfil.
    // El estado false/true se construye apagando el perfil antes de asegurar la
    // membresia; nunca hay una ventana mas permisiva que el estado de destino.
    if (!crmActive) {
      await updateTeam();
      await updateProfile();
    } else if (!portalActive) {
      await updateProfile();
      await updateTeam();
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
    await expectExpectedFailure(
      `${label}: no crea contrato con cuenta`,
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta', {
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
      `${label}: no corrige contrato ya enlazado`,
      sessions.vend1.client.schema('crm').rpc('actualizar_contrato_con_cuenta', {
        p_id: seed.contract.id,
        p_contrato: { moneda: BANK_CONTRACT.currency },
        p_cronograma: [],
      }),
      ['42501'],
      /contrato no encontrado o fuera de tu cartera/i,
    );
    await expectExpectedFailure(
      `${label}: no corrige contrato legacy sin enlace`,
      sessions.vend1.client.schema('crm').rpc('actualizar_contrato_con_cuenta', {
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
  // durante la sonda a los dos vendedores a `analista`: reproduce la identidad
  // real que autoriza crear contratos y restaura ambos roles en `finally`.
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
    // gate de P04 ya no la frena, así que lo que queda expuesto —y es lo que
    // debe seguir cerrado— es el SCOPING POR CARTERA: el cliente bancario tiene
    // asesor_perfil_id = vend1, de modo que un analista ajeno sigue sin
    // alcanzarlo ni por la banca del CRM ni por el ALTA LEGACY del portal
    // (`public.crear_contrato`, llamador del guard desde el catálogo). Mismo
    // 42501 que antes, pero ahora por la razón correcta.
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
      'analista sin membresia CRM: la cartera sigue cerrando el alta legacy ajena',
      sessions.directorio.client.rpc('crear_contrato', {
        p_contrato: {
          cliente_id: bankProfileId,
          moneda: BANK_CONTRACT.currency,
          capital: 1000,
          tasa_anual: 10,
          categoria: 'nuevo',
        },
        p_cronograma: [],
      }),
      ['42501'],
      /cliente no encontrado o fuera de tu cartera/i,
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
      sessions.directorio.client.rpc('actualizar_numero_contrato', {
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
    await requireAdmin(
      'banca P04: retirar la membresia revocada fabricada',
      admin.schema('crm').from('equipo').delete().eq('perfil_id', directorProfileId),
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
      sessions.directorio.client.rpc('actualizar_numero_contrato', {
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

    await expectExpectedFailure(
      'el alta rechaza una instantanea obsoleta de la cuenta del perfil',
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta', {
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
      'el alta rechaza un UUID de cuenta existente forjado',
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta', {
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
      'una falla del contrato revierte tambien la cuenta nueva de la misma RPC',
      sessions.vend1.client.schema('crm').rpc('crear_contrato_con_cuenta', {
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

    // El cronograma deliberadamente invalido evita una mutacion aun si hubiera
    // una regresion de autorizacion; la asercion solo acepta un error de scope.
    for (const key of ['vend3', 'directorio']) {
      await expectExplicitAuthorizationDenied(
        `${key} no corrige el contrato bancario por el wrapper`,
        sessions[key].client.schema('crm').rpc('actualizar_contrato_con_cuenta', {
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
    if (directorMembershipFabricated) {
      await requireAdmin(
        'retirar la membresia CRM fabricada para directorio tras sondas bancarias',
        admin.schema('crm').from('equipo').delete().eq('perfil_id', directorProfileId),
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
// degradado (vendedor sin supervisor, supervisor de baja) siguen en PostgreSQL
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
      'cada vendedor visible conserva las seis dimensiones categoria x moneda');

    const ids = new Set(idsMetas(configGerencia));
    for (const key of ['vend1', 'vend2', 'vend3', 'vend4', 'vendNested']) {
      check(ids.has(seed.profileIdByKey[key]),
        `gerencia ve al vendedor activo ${key}`);
    }
    check(!ids.has(seed.profileIdByKey.vendInactive),
      'el roster de metas excluye al vendedor inactivo');
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
    'coordinador no obtiene metas de vendedores');
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
    // El lector global ve también soft-borrados por RLS; las RPC solo ámbito
    // vivo — el oráculo aplica el mismo recorte (activo + ventana).
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
    'sup2 lee metricas de vendedores sin cruzar de subarbol',
    sessions.sup2.client.schema('crm').rpc('metricas_vendedores_fn'),
  );
  if (mvSup2) {
    const ids = new Set((mvSup2.data?.vendedores ?? []).map((v) => v.vendedor_id));
    check(ids.has(seed.profileIdByKey.vend3), 'sup2 incluye a vend3');
    check(ids.has(seed.profileIdByKey.vendInactive),
      'sup2 incluye a su vendedor desactivado (gerencia reasigna esa cartera)');
    check(!ids.has(seed.profileIdByKey.vend1), 'sup2 excluye a vend1 (subarbol ajeno)');
    const equipos = new Set((mvSup2.data?.equipos ?? []).map((e) => e.supervisor_id));
    check(equipos.has(seed.profileIdByKey.sup2) && !equipos.has(seed.profileIdByKey.sup1),
      'sup2 solo recibe la comparativa de su propio equipo');
  }
  const mvVend1 = await positive(
    'vend1 lee metricas de vendedores',
    sessions.vend1.client.schema('crm').rpc('metricas_vendedores_fn'),
  );
  if (mvVend1) {
    check((mvVend1.data?.vendedores ?? []).length === 1
      && (mvVend1.data?.equipos ?? []).length === 0,
      'vend1 recibe solo su propia fila y cero equipos');
  }
  const mvGerencia = await positive(
    'gerencia lee metricas de vendedores del roster completo',
    sessions.gerencia.client.schema('crm').rpc('metricas_vendedores_fn'),
  );
  if (mvGerencia) {
    const filaInactivo = (mvGerencia.data?.vendedores ?? [])
      .find((v) => v.vendedor_id === seed.profileIdByKey.vendInactive);
    check(filaInactivo?.activo === false,
      'gerencia ve la fila del vendedor desactivado marcada activo=false');
  }

  // series_comerciales_fn: shape de 6 arrays paralelos.
  const series = await positive(
    'gerencia obtiene series_comerciales_fn',
    sessions.gerencia.client.schema('crm').rpc('series_comerciales_fn', { p_meses: 6 }),
  );
  if (series) {
    const d = series.data ?? {};
    check((d.meses ?? []).length === 6
      && ['nuevos', 'cierres', 'cohorte_clientes', 'capital_pen', 'capital_usd', 'conversion_pct']
        .every((k) => (d[k] ?? []).length === 6),
      'gerencia recibe 6 arrays paralelos de 6 meses');
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
      'el subarbol es RECURSIVO: sup1 ve al vendedor de su supervisor anidado');
    check(!suyos.has(ids.vend3) && !suyos.has(ids.vend4),
      'sup1 NO ve a los vendedores de sup2');
    check(!suyos.has(ids.sup1) && !suyos.has(ids.sup1Nested),
      'los supervisores no aparecen como filas del ranking');
    check(!suyos.has(ids.vendInactive),
      'el vendedor inactivo NO figura como responsable');
  }
  if (deSup2) {
    const suyos = idsDe(deSup2.data);
    check(suyos.has(ids.vend3) && suyos.has(ids.vend4), 'sup2 ve a sus dos vendedores');
    check(!suyos.has(ids.vend1) && !suyos.has(ids.vend2) && !suyos.has(ids.vendNested),
      'sup2 NO ve el subarbol de sup1');
  }
  if (deNested) {
    const suyos = idsDe(deNested.data);
    check(!suyos.has(ids.vend1) && !suyos.has(ids.vend2),
      'sup1Nested no ve HACIA ARRIBA: solo su propia rama');
  }

  // Paridad con gerencia: el mismo vendedor y el mismo periodo dan los MISMOS
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
      'PARIDAD: sup1 ve los mismos numeros que gerencia para sus vendedores',
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
      'SUPERVISOR UNO recibe solo sus asesores directos activos',
      JSON.stringify(ids),
    );
    check(
      !(payload?.asesores ?? []).some((fila) => fila.asesor_id === seed.profileIdByKey.vendNested),
      'el vendedor del supervisor anidado no se mezcla en las cards directas',
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
      'el segundo supervisor no recibe asesores del primero',
      JSON.stringify(ids),
    );
  }

  const reporteAnidado = await sessions.sup1Nested.client.schema('crm')
    .rpc('reporte_derivaciones_equipo_fn');
  if (check(!reporteAnidado.error, 'el supervisor anidado consulta su equipo directo', errorText(reporteAnidado.error))) {
    check(
      JSON.stringify((reporteAnidado.data?.asesores ?? []).map((fila) => fila.asesor_id))
        === JSON.stringify([seed.profileIdByKey.vendNested]),
      'el supervisor anidado recibe únicamente a su vendedor directo',
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
    'el supervisor no deriva un lead a un asesor de otro equipo',
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
  // despachador es LO UNICO que separa a un vendedor de las metricas de toda
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
      // `tareas_destino_reunion_coherente`: una reunion virtual EXIGE enlace
      // (y una presencial, ubicacion). Una reunion sin canal seria
      // 'sin_clasificar'; aqui se siembra completa para que el fixture sea una
      // cita de verdad, no un caparazon que pase el check por omision.
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
    'carrera: quedo UN solo supervisor asignado y ningun vendedor');

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

  // NO-REGRESION DEL ALCANCE: bajar de la bandeja a un vendedor NO es un
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
    'bajar el lead de la bandeja a un vendedor (NO es re-encolado)',
    admin.schema('crm').from('leads')
      .update({ vendedor_id: seed.profileIdByKey.vend3, asignado_supervisor_id: null })
      .eq('id', TRANSIENT_IDS.repartoLeadBandeja)
      .select('id'),
  );
  const bandeja = await requireAdmin(
    'releer el lead bajado a vendedor',
    admin.schema('crm').from('leads').select('etapa, vendedor_id')
      .eq('id', TRANSIENT_IDS.repartoLeadBandeja).single(),
  );
  const tareaBandeja = await requireAdmin(
    'releer la reunion del lead bajado a vendedor',
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
    'gerencia filtra la cartera por vendedor',
    gerencia.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 200, p_vendedor_id: seed.profileIdByKey.vend1,
    }),
  );
  if (porVendedor) {
    const filas = porVendedor.data ?? [];
    check(filas.length > 0 && filas.every((f) => f.vendedor_id === seed.profileIdByKey.vend1),
      `el filtro por vendedor solo devuelve su cartera (${filas.length})`);
  }

  // El filtro NO es una puerta: pedir la cartera de un vendedor ajeno devuelve
  // vacio porque la RLS ya recorto ANTES — no porque el filtro sea amable.
  const ajena = await positive(
    'vend1 pide la cartera de un vendedor de otro subarbol',
    sessions.vend1.client.schema('crm').rpc('cartera_pagina_fn', {
      p_limite: 200, p_vendedor_id: seed.profileIdByKey.vend3,
    }),
  );
  if (ajena) {
    check((ajena.data ?? []).length === 0,
      'vend1 no obtiene ni una fila filtrando por un vendedor ajeno');
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
    'cartera_pagina_fn rechaza sin_asignar junto a un vendedor',
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
  // contacto real registrado por el vendedor debe verse identico desde su
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
      'vendedor, supervisor y gerencia ven EXACTAMENTE el mismo ultimo contacto',
      JSON.stringify([...sellos]));
  }
}

// ── Migracion A: conversion mensual ponderada (crm.conversion_mensual_fn) ────
// La RPC nueva abre al VENDEDOR un informe (cobertura del ledger, total del
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
const CLAVES_PAYLOAD_CONVERSION = ['alcance', 'cierre', 'cobertura', 'fuentes', 'generado_en',
  'periodo', 'ponderacion', 'responsables', 'total', 'version'];
const CLAVES_PERIODO_CONVERSION = ['anio', 'desde', 'hasta', 'mes', 'mes_nombre', 'zona'];
const CLAVES_PONDERACION_CONVERSION = ['fuente', 'referido'];
const CLAVES_COBERTURA_CONVERSION = ['cierres_sin_episodio', 'divisor_aproximado',
  'divisor_por_motivo', 'fuera_de_roster', 'medible', 'motivo_no_medible', 'suelo_historico'];
// Actualizadas el 2026-08-11 tras la consolidación final de la migración A:
// `cierres_de_arrastre` (exigida por los revisores para que un % > 100 sea
// explicable en pantalla) viaja en la fila Y en el total, y el total lleva
// además `referidos_aporta_pct` (espejo del aporta_pct por fila).
const CLAVES_TOTAL_CONVERSION = ['analistas', 'cierres_de_arrastre',
  'cierres_no_referidos', 'cierres_referidos', 'conversion_pct', 'divisor',
  'numerador', 'referidos_aporta_pct', 'referidos_recibidos'];
const CLAVES_RESPONSABLE_CONVERSION = ['ajuste', 'cierres_de_arrastre',
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
// 'propio' cuando el vendedor no esta en el roster. No son metadato del ledger
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
  if (!check(filaAntesVend1 !== null,
    'vend1 tiene fila en la linea base: los tramos de delta, paridad y soft-delete tienen sujeto',
    JSON.stringify([...idsDe(antes.data)]))) {
    return;
  }
  // El LEFT JOIN desde el roster: «desaparecer no es un estado». Se asevera
  // sobre la linea base y no sobre el payload final porque el tramo 0 consume
  // justamente al analista ocioso para fabricar `solo_referidos`.
  check(filasDe(antes.data).some((fila) => fila.estado === 'sin_actividad'),
    'la linea base tiene al menos una fila sin_actividad (el roster manda, no la actividad)',
    JSON.stringify(filasDe(antes.data).map((f) => [f.vendedor_id, f.estado])));

  // El sujeto de `solo_referidos` se elige del PAYLOAD, no del fixture: quien
  // esta ocioso depende de lo que hayan hecho los bloques anteriores de main()
  // (testReassignmentTrigger y testTareaFollowsLead mueven leads a vend2), y
  // clavar una clave aqui seria un fixture que caduca al reordenar el gate.
  const candidato = filasDe(antes.data).find((fila) => Number(fila.divisor) === 0
    && Number(fila.cierres_no_referidos) === 0
    && Number(fila.cierres_referidos) === 0
    && Number(fila.referidos?.recibidos) === 0);
  if (!check(candidato != null,
    'hay un analista del roster sin actividad al que darle SOLO un referido (estado solo_referidos)',
    JSON.stringify(filasDe(antes.data).map((f) => [f.vendedor_id, f.divisor, f.estado])))) {
    return;
  }
  const candidatoId = candidato.vendedor_id;

  try {
    // ── 0b · la semilla, por la VIA REAL ────────────────────────────────────
    // Los cierres se producen con `crm.convertir_lead` y la sesion del vendedor:
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
        'el subarbol es RECURSIVO: sup1 ve al vendedor de su supervisor anidado');
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
      check(suyos.has(ids.vend3) && suyos.has(ids.vend4), 'sup2 ve a sus dos vendedores');
      check(!suyos.has(ids.vend1) && !suyos.has(ids.vend2) && !suyos.has(ids.vendNested),
        'sup2 NO ve el subarbol de sup1');
      // AQUI la revocacion es una decision y no un accidente de topologia: el
      // CTE recursivo de private.vendedor_ids_visibles recorre crm.equipo SIN
      // predicado de `activo`, asi que vendInactive SI esta en el ambito de
      // sup2 (el propio gate lo constata en testMetasVersionadas). Lo unico que
      // lo saca es el roster, que exige rol_crm activo en los dos extremos. Es
      // la invariante de [[crm-p04-revocado-vs-ajeno]]: offboarding =
      // activo=false, y un asesor dado de baja no reaparece con nombre propio
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
      check(propio.data?.alcance === 'propio', 'el vendedor recibe alcance "propio"');
      check(filas.length === 1 && filas[0]?.vendedor_id === ids.vend1,
        'el vendedor recibe EXACTAMENTE una fila y es la suya',
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
      'el vendedor entra en la MISMA rama de validacion que gerencia',
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
      check(Number(filaCandidato.divisor) === 0
        && Number(filaCandidato.referidos?.recibidos) === 1,
        'T10 · recibir SOLO un referido deja el divisor en 0 y el contador de referidos en 1',
        JSON.stringify(filaCandidato));
      check(filaCandidato.estado === 'solo_referidos',
        'el TERCER estado existe y se emite: divisor 0 con referidos NO es sin_actividad',
        String(filaCandidato.estado));
      check(filaCandidato.conversion_pct === null
        && filaCandidato.referidos?.aporta_pct === null,
        'sin divisor no hay porcentaje: NULL, jamas 0, ni en la fila ni en el aporte',
        JSON.stringify([filaCandidato.conversion_pct, filaCandidato.referidos?.aporta_pct]));
      check(Number(filaCandidato.referidos?.dados_de_alta) === 1,
        'el alta del referido se le acredita a quien lo dio de alta');
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
      && deltaTotal('analistas') === 1,
      'D8 · el TOTAL global se mueve lo sembrado INCLUYENDO al productor fuera de roster (+2 divisor, +1 analista)',
      JSON.stringify({ antes: totalAntes, despues: totalDespues }));

    const coberturaDespues = payload?.cobertura ?? {};
    const motivoAntes = num(coberturaAntes?.divisor_por_motivo?.ingreso);
    const motivoDespues = num(coberturaDespues?.divisor_por_motivo?.ingreso);
    check(motivoDespues - motivoAntes === 1,
      'el desglose por motivo sube +1 en "ingreso" (el valor REAL del CHECK, no "reasignacion")',
      JSON.stringify(coberturaDespues?.divisor_por_motivo));
    check(num(coberturaDespues?.fuera_de_roster?.analistas)
      - num(coberturaAntes?.fuera_de_roster?.analistas) === 1
      && num(coberturaDespues?.fuera_de_roster?.divisor)
      - num(coberturaAntes?.fuera_de_roster?.divisor) === 1,
      'el productor SIN rol de vendedor se cuenta entero en fuera_de_roster, y solo alli',
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
      check(num(deSup2.data?.cobertura?.fuera_de_roster?.analistas) === 0
        && num(deSup2.data?.cobertura?.fuera_de_roster?.numerador) === 0,
        'D8 · el fuera-de-roster ajeno NO entra al ambito de sup2',
        JSON.stringify(deSup2.data?.cobertura?.fuera_de_roster));
    }

    // ── F · forma del contrato: una clave de mas es superficie sin auditar ───
    check(mismasClaves(payload, CLAVES_PAYLOAD_CONVERSION),
      'el payload trae SOLO las 9 claves del contrato', clavesDe(payload).join(','));
    check(mismasClaves(payload?.periodo, CLAVES_PERIODO_CONVERSION),
      'periodo trae SOLO sus 6 claves', clavesDe(payload?.periodo).join(','));
    check(mismasClaves(payload?.ponderacion, CLAVES_PONDERACION_CONVERSION),
      'ponderacion trae SOLO sus 2 claves', clavesDe(payload?.ponderacion).join(','));
    check(mismasClaves(payload?.cobertura, CLAVES_COBERTURA_CONVERSION),
      'cobertura trae SOLO las 7 claves del contrato', clavesDe(payload?.cobertura).join(','));
    check(mismasClaves(payload?.total, CLAVES_TOTAL_CONVERSION),
      'total trae SOLO las 9 claves del contrato', clavesDe(payload?.total).join(','));
    check(mismasClaves(payload?.cobertura?.fuera_de_roster, CLAVES_FUERA_DE_ROSTER),
      'fuera_de_roster es un AGREGADO SIN IDENTIDAD (ni un uuid dentro)',
      clavesDe(payload?.cobertura?.fuera_de_roster).join(','));
    check(MOTIVOS_NO_MEDIBLE.has(payload?.cobertura?.motivo_no_medible ?? null),
      'motivo_no_medible pertenece al vocabulario CERRADO que el front declara como picklist',
      String(payload?.cobertura?.motivo_no_medible));

    const clavesFilas = [...new Set(filas.flatMap((fila) => Object.keys(fila)))].sort();
    check(clavesFilas.length > 0
      && JSON.stringify(clavesFilas) === JSON.stringify(CLAVES_RESPONSABLE_CONVERSION),
      'cada responsable trae SOLO las 11 claves del contrato', clavesFilas.join(','));
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
    // ambito, y viaja tambien al vendedor: la cobertura es una propiedad del
    // LEDGER —cuando empieza a existir el registro—, no de una persona. Si se
    // recortara, el supervisor de un equipo nuevo veria «mes_parcial» sobre un
    // mes que la empresa mide perfectamente, y dos roles dirian cosas distintas
    // del mismo mes.
    //
    // ⚠️ `medible` y `motivo_no_medible` NO entran en esta cabecera comun. La
    // RPC los SOBREESCRIBE a proposito (paso 5b) para alcance 'propio' cuando el
    // vendedor no esta en el roster — la correccion #7, que existe para que ese
    // vendedor no reciba una pantalla en blanco sin explicacion. Exigirlos
    // identicos entre roles cementaria como invariante justo lo que la migracion
    // rompe, y pondria el gate en rojo el dia que el fixture tenga un vendedor
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
      // si el vendedor esta en el roster (lo esta si tiene fila en el payload
      // global), 5b no se ejecuta y la cobertura debe coincidir; si no lo
      // estuviera, debe venir medible=false con uno de los TRES motivos de
      // exclusion. Escrito asi, el dia que el fixture crezca con un vendedor
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
      // cuenta y el vendedor —cuyo ambito es el suyo— NO puede verlo.
      check(num(payload?.cobertura?.fuera_de_roster?.analistas) >= 1,
        'fuera_de_roster tiene CONTENIDO en global: las monotonias de arriba no son 0 > 0',
        JSON.stringify(payload?.cobertura?.fuera_de_roster));
      if (propio) {
        check(num(propio.data?.cobertura?.fuera_de_roster?.analistas) === 0,
          'el vendedor no ve NADA del agregado de fuera de roster: su ambito es el suyo',
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
      'post-B cada vendedor trae numerador y sus dos sumandos', JSON.stringify(fila));
    check(payGer?.ponderacion_referido !== undefined,
      'post-B el payload declara la ponderacion aplicada');
    check(filas(payGer).every((f) => Number(f.resueltos) >= 0),
      'ningun divisor negativo');
  }

  // ── C · SUPERVISOR: su subarbol y NADIE mas ─────────────────────────────
  const sup = await positive('sup1 lee el cumplimiento de su equipo', pedir('sup1'));
  const idsSup = idsDe(sup?.data);
  check(idsSup.size > 0, 'sup1 recibe al menos un vendedor de su equipo');
  check(!idsSup.has(ids.vend3),
    'sup1 NO ve a vend3, que cuelga de sup2', JSON.stringify([...idsSup]));
  check([...idsSup].every((id) => idsDe(payGer).has(id)),
    'todo lo que ve sup1 esta dentro de lo que ve gerencia');

  // ── D · VENDEDOR: solo su propia fila ───────────────────────────────────
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
    'el coordinador recibe la lista de vendedores VACIA',
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
      }

      // ── 5 · La ANULACION es de gerencia, y deja de contar ────────────────
      // Es el freno de emergencia contra un cierre falso. Aqui se vigila QUIEN
      // puede tirar de el (solo gerencia) y que el cierre salga de los totales
      // sin desaparecer de las filas.
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
        const enTotales = (traAnular?.data?.totales ?? [])
          .some((t) => t.cooperativa === 'prodelco' && Number(t.capital) >= 1500);
        check(!enTotales,
          'el cierre anulado salio de los totales (no es dinero)',
          JSON.stringify(traAnular?.data?.totales));
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
      await testCarteraKeyset(sessions, verifiedSeed);
      await testReparto(sessions, verifiedSeed);
      await testDescarte(sessions, verifiedSeed);
      await testBankingBoundary(sessions, verifiedSeed);
      await testContractBankAccounts(sessions, verifiedSeed);
      await testAnon(verifiedSeed);
      // Cierres externos ANTES de la conversion: convierte un lead de vend1 que
      // la conversion absorbe en su LINEA BASE (sus aserciones son deltas).
      await testCierresExternos(sessions, verifiedSeed);
      // Va el ÚLTIMO a propósito: siembra dos leads que sobreviven visibles para
      // `directorio` (la rama del lector global de `leads_select` no lleva
      // predicado de `activo`), así que cualquier bloque posterior heredaría ese
      // estado. Limpia lo suyo en su propio `finally`.
      await testConversionMensual(sessions, verifiedSeed);
      await testCumplimientoMetas(sessions, verifiedSeed);
      await testCierreDeMes(sessions, verifiedSeed);
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
